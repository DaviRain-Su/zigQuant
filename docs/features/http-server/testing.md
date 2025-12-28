# HTTP Server - 测试文档

> 测试覆盖和基准测试

**最后更新**: 2025-12-28

---

## 测试概览

| 类别 | 测试数 | 覆盖率 |
|------|--------|--------|
| 单元测试 | TBD | TBD |
| 集成测试 | TBD | TBD |
| 性能测试 | TBD | TBD |

---

## 单元测试

### JwtManager 测试

```zig
const std = @import("std");
const testing = std.testing;
const JwtManager = @import("api").JwtManager;

test "JwtManager.generateToken creates valid token" {
    const allocator = testing.allocator;
    var jwt = JwtManager.init(allocator, "test-secret-key-32-bytes!!!!!!", 24);

    const token = try jwt.generateToken("user_123");
    defer allocator.free(token);

    // Token 应该包含三个部分
    var parts = std.mem.splitScalar(u8, token, '.');
    try testing.expect(parts.next() != null); // header
    try testing.expect(parts.next() != null); // payload
    try testing.expect(parts.next() != null); // signature
}

test "JwtManager.verifyToken validates signature" {
    const allocator = testing.allocator;
    var jwt = JwtManager.init(allocator, "test-secret-key-32-bytes!!!!!!", 24);

    const token = try jwt.generateToken("user_123");
    defer allocator.free(token);

    const payload = try jwt.verifyToken(token);
    try testing.expectEqualStrings("user_123", payload.sub);
}

test "JwtManager.verifyToken rejects tampered token" {
    const allocator = testing.allocator;
    var jwt = JwtManager.init(allocator, "test-secret-key-32-bytes!!!!!!", 24);

    const token = try jwt.generateToken("user_123");
    defer allocator.free(token);

    // 篡改 token
    var tampered = try allocator.dupe(u8, token);
    defer allocator.free(tampered);
    tampered[10] = if (tampered[10] == 'a') 'b' else 'a';

    try testing.expectError(error.InvalidSignature, jwt.verifyToken(tampered));
}

test "JwtManager.verifyToken rejects expired token" {
    const allocator = testing.allocator;
    // 使用 0 小时过期
    var jwt = JwtManager.init(allocator, "test-secret-key-32-bytes!!!!!!", 0);

    const token = try jwt.generateToken("user_123");
    defer allocator.free(token);

    // 等待过期
    std.time.sleep(1 * std.time.ns_per_s);

    try testing.expectError(error.TokenExpired, jwt.verifyToken(token));
}
```

### 中间件测试

```zig
test "corsMiddleware adds headers" {
    // 模拟请求和响应
    var res = MockResponse{};
    var req = MockRequest{ .origin = "http://localhost:3000" };

    const middleware = corsMiddleware(&.{"http://localhost:3000"});
    try middleware(null, &req, &res);

    try testing.expectEqualStrings(
        "http://localhost:3000",
        res.headers.get("Access-Control-Allow-Origin").?,
    );
}

test "authMiddleware rejects missing token" {
    var res = MockResponse{};
    var req = MockRequest{}; // 无 Authorization 头

    try authMiddleware(null, &req, &res);

    try testing.expect(res.status == .unauthorized);
}

test "authMiddleware accepts valid token" {
    const allocator = testing.allocator;
    var jwt = JwtManager.init(allocator, "test-secret", 24);
    const token = try jwt.generateToken("user_123");
    defer allocator.free(token);

    var res = MockResponse{};
    var req = MockRequest{
        .authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{token}),
    };
    defer allocator.free(req.authorization.?);

    var ctx = MockContext{ .jwt_manager = &jwt };
    try authMiddleware(&ctx, &req, &res);

    try testing.expectEqualStrings("user_123", ctx.user_id.?);
}
```

---

## 集成测试

### API 端点测试

```bash
#!/bin/bash
# test_api.sh

BASE_URL="http://localhost:8080"

# 健康检查
echo "Testing /health..."
curl -s "$BASE_URL/health" | jq .
# Expected: {"status":"healthy","version":"1.0.0"}

# 登录
echo "Testing /api/v1/auth/login..."
TOKEN=$(curl -s -X POST "$BASE_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}' | jq -r '.token')
echo "Token: ${TOKEN:0:50}..."

# 获取策略列表
echo "Testing /api/v1/strategies..."
curl -s "$BASE_URL/api/v1/strategies" \
  -H "Authorization: Bearer $TOKEN" | jq .

# 创建回测
echo "Testing POST /api/v1/backtest..."
BACKTEST_ID=$(curl -s -X POST "$BASE_URL/api/v1/backtest" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "strategy_id": "sma_cross",
    "start_date": "2024-01-01",
    "end_date": "2024-12-31",
    "initial_capital": 10000
  }' | jq -r '.id')
echo "Backtest ID: $BACKTEST_ID"

# 获取回测结果
echo "Testing GET /api/v1/backtest/:id..."
curl -s "$BASE_URL/api/v1/backtest/$BACKTEST_ID" \
  -H "Authorization: Bearer $TOKEN" | jq .

echo "All tests completed!"
```

### Zig 集成测试

```zig
const std = @import("std");
const testing = std.testing;
const http = std.http;

test "integration: health endpoint" {
    const allocator = testing.allocator;

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var request = try client.request(.GET, try std.Uri.parse("http://localhost:8080/health"), .{}, .{});
    defer request.deinit();

    try request.send();
    try request.wait();

    try testing.expect(request.status == .ok);

    var body = try request.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(body);

    const parsed = try std.json.parseFromSlice(struct { status: []const u8 }, allocator, body, .{});
    defer parsed.deinit();

    try testing.expectEqualStrings("healthy", parsed.value.status);
}

test "integration: auth flow" {
    const allocator = testing.allocator;

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    // 1. 登录
    const login_body =
        \\{"username":"admin","password":"admin"}
    ;

    var login_req = try client.request(.POST, try std.Uri.parse("http://localhost:8080/api/v1/auth/login"), .{
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        },
    }, .{});
    defer login_req.deinit();

    login_req.transfer_encoding = .{ .content_length = login_body.len };
    try login_req.send();
    try login_req.writer().writeAll(login_body);
    try login_req.finish();
    try login_req.wait();

    try testing.expect(login_req.status == .ok);

    // 2. 使用 token 访问受保护路由
    // ...
}
```

---

## 性能测试

### wrk 基准测试

```bash
# 安装 wrk
# Ubuntu: sudo apt install wrk
# macOS: brew install wrk

# 健康检查端点
wrk -t12 -c400 -d30s http://localhost:8080/health

# 预期结果:
# Requests/sec: 50,000+
# Latency avg: < 1ms

# 受保护端点 (需要 token)
wrk -t12 -c400 -d30s \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/v1/strategies

# 预期结果:
# Requests/sec: 10,000+
# Latency avg: < 10ms
```

### 并发连接测试

```bash
# 使用 hey 工具
hey -n 10000 -c 100 http://localhost:8080/health

# 预期结果:
# Total: 10000 requests
# Requests/sec: 10000+
# 99% in 50ms
```

### 内存使用测试

```bash
# 启动服务器
./zigquant serve &

# 监控内存
watch -n 1 'ps -o rss,vsz,pid -p $(pgrep zigquant)'

# 发送负载
wrk -t4 -c100 -d60s http://localhost:8080/health

# 预期:
# RSS < 50MB
# 无内存泄漏 (RSS 稳定)
```

---

## 测试用例

### 正常情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| JWT 生成 | 生成有效的 JWT token | 📋 待实现 |
| JWT 验证 | 验证有效 token | 📋 待实现 |
| CORS 头 | 添加正确的 CORS 头 | 📋 待实现 |
| 健康检查 | 返回 healthy 状态 | 📋 待实现 |
| 策略列表 | 返回策略数组 | 📋 待实现 |
| 回测创建 | 异步创建回测任务 | 📋 待实现 |
| 订单创建 | 创建限价订单 | 📋 待实现 |

### 边界情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 大请求体 | 超过 10MB 的请求 | 📋 待实现 |
| 并发请求 | 1000+ 并发连接 | 📋 待实现 |
| 慢客户端 | 超时处理 | 📋 待实现 |
| 无效 JSON | 返回 400 错误 | 📋 待实现 |

### 错误情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 缺少 Token | 返回 401 | 📋 待实现 |
| 过期 Token | 返回 401 | 📋 待实现 |
| 无效签名 | 返回 401 | 📋 待实现 |
| 不存在的路由 | 返回 404 | 📋 待实现 |
| 方法不允许 | 返回 405 | 📋 待实现 |

---

## 运行测试

```bash
# 运行所有测试
zig build test

# 运行特定模块测试
zig build test -- --filter "api"

# 运行集成测试 (需要服务器运行)
./scripts/test_api.sh

# 运行性能测试
./scripts/benchmark.sh
```

---

*Last updated: 2025-12-28*
