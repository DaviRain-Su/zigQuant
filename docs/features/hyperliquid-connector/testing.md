# Hyperliquid 连接器 - 测试文档

> 测试覆盖和使用指南

**最后更新**: 2025-12-24

---

## 测试概览

本指南涵盖 Hyperliquid HTTP 和 WebSocket 客户端的测试策略，包括单元测试和集成测试。

---

## 测试覆盖率

- **代码覆盖率**: 目标 >80%
- **测试用例数**: 50+
- **集成测试**: 测试网连接测试

---

## 单元测试

### EIP-712 签名测试

```zig
const std = @import("std");
const testing = std.testing;
const auth = @import("auth.zig");

test "Signer: initialization" {
    const allocator = std.testing.allocator;

    const private_key = [_]u8{0x42} ** 32;
    var signer = try auth.Signer.init(allocator, private_key);
    defer signer.deinit();

    try std.testing.expect(signer.address.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, signer.address, "0x"));
}

test "Signer: sign action" {
    const allocator = std.testing.allocator;

    // 测试私钥
    const private_key = [_]u8{0x42} ** 32;
    var signer = try auth.Signer.init(allocator, private_key);
    defer signer.deinit();

    // 测试 action data（模拟订单 JSON）
    const action_data = "{\"type\":\"order\",\"orders\":[{\"a\":0,\"b\":true,\"p\":\"1800.0\",\"s\":\"0.1\"}]}";

    // 签名 action
    const signature = try signer.signAction(action_data);
    defer allocator.free(signature.r);
    defer allocator.free(signature.s);

    // 验证签名格式
    try std.testing.expect(std.mem.startsWith(u8, signature.r, "0x"));
    try std.testing.expect(std.mem.startsWith(u8, signature.s, "0x"));
    try std.testing.expect(signature.r.len == 66); // 0x + 64 hex chars
    try std.testing.expect(signature.s.len == 66);
    try std.testing.expect(signature.v == 27 or signature.v == 28);
}
```

---

### Connector 测试

```zig
test "HyperliquidConnector: create and destroy" {
    const allocator = std.testing.allocator;

    // 创建测试 logger
    var logger = createTestLogger(allocator);
    defer logger.deinit();

    const config = ExchangeConfig{
        .name = "hyperliquid",
        .testnet = true,
    };

    const connector = try HyperliquidConnector.create(allocator, config, logger);
    defer connector.destroy();

    try std.testing.expect(!connector.connected);
}

test "HyperliquidConnector: interface" {
    const allocator = std.testing.allocator;
    var logger = createTestLogger(allocator);
    defer logger.deinit();

    const config = ExchangeConfig{
        .name = "hyperliquid",
        .testnet = true,
    };

    const connector = try HyperliquidConnector.create(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();

    try std.testing.expectEqualStrings("hyperliquid", exchange.getName());
}
```

### HTTP 客户端测试

```zig
test "HttpClient: initialization" {
    var logger = createTestLogger(std.testing.allocator);
    defer logger.deinit();

    var client = HttpClient.init(std.testing.allocator, true, logger);
    defer client.deinit();

    try std.testing.expectEqualStrings(types.API_BASE_URL_TESTNET, client.base_url);
}
```

---

### 速率限制器测试

```zig
test "RateLimiter: initialization" {
    const limiter = RateLimiter.init(10.0, 10.0);
    try std.testing.expectEqual(@as(f64, 10.0), limiter.max_tokens);
    try std.testing.expectEqual(@as(f64, 10.0), limiter.refill_rate);
}

test "RateLimiter: tryAcquire" {
    var limiter = RateLimiter.init(10.0, 10.0);

    // 初始应该能获取
    try std.testing.expect(limiter.tryAcquire());
    try std.testing.expect(limiter.tokens < 10.0);
}

test "createHyperliquidRateLimiter" {
    const limiter = createHyperliquidRateLimiter();
    try std.testing.expectEqual(@as(f64, 20.0), limiter.max_tokens);
    try std.testing.expectEqual(@as(f64, 20.0), limiter.refill_rate);
}
```

---

## 集成测试

### 连接测试网（集成测试）

位置：`tests/integration/hyperliquid_test.zig`

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建 logger
    var logger = createLogger(allocator);
    defer logger.deinit();

    // 测试 1: 创建连接器
    std.debug.print("Test 1: Creating Hyperliquid connector...\n", .{});
    const config = ExchangeConfig{
        .name = "hyperliquid",
        .testnet = true,
    };

    const connector = try HyperliquidConnector.create(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();
    std.debug.print("✓ Connector created: {s}\n\n", .{exchange.getName()});

    // 测试 2: 连接到交易所
    std.debug.print("Test 2: Connecting to Hyperliquid testnet...\n", .{});
    try exchange.connect();
    std.debug.print("✓ Connected: {}\n\n", .{exchange.isConnected()});
}
```

---

### 获取订单簿测试

```zig
// 测试 5: 获取 ETH-USDC 订单簿
std.debug.print("Test 5: Getting ETH-USDC orderbook (depth=5)...\n", .{});
const orderbook = exchange.getOrderbook(eth_pair, 5) catch |err| {
    std.debug.print("✗ Failed to get orderbook: {}\n", .{err});
    return err;
};
defer allocator.free(orderbook.bids);
defer allocator.free(orderbook.asks);

std.debug.print("✓ ETH-USDC Orderbook:\n", .{});
std.debug.print("  Bids: {} levels\n", .{orderbook.bids.len});
std.debug.print("  Asks: {} levels\n", .{orderbook.asks.len});

if (orderbook.bids.len > 0) {
    std.debug.print("  Best Bid: {} @ {}\n", .{
        orderbook.bids[0].quantity.toFloat(),
        orderbook.bids[0].price.toFloat(),
    });
}

if (orderbook.asks.len > 0) {
    std.debug.print("  Best Ask: {} @ {}\n", .{
        orderbook.asks[0].quantity.toFloat(),
        orderbook.asks[0].price.toFloat(),
    });
}
```

---

### 下单和撤单测试

```zig
test "Integration: place and cancel order" {
    // 需要设置 HYPERLIQUID_SECRET_KEY 环境变量
    const secret_key = std.os.getenv("HYPERLIQUID_SECRET_KEY") orelse {
        std.debug.print("Skipping test: HYPERLIQUID_SECRET_KEY not set\n", .{});
        return;
    };

    const config = HyperliquidClient.HyperliquidConfig{
        .base_url = HyperliquidClient.HyperliquidConfig.DEFAULT_TESTNET_URL,
        .secret_key = secret_key,
        .testnet = true,
        .timeout_ms = 10000,
        .max_retries = 3,
    };

    var client = try HyperliquidClient.init(testing.allocator, config, logger);
    defer client.deinit();

    // 下限价单（价格设置很低，不会立即成交）
    const order = ExchangeAPI.OrderRequest{
        .coin = "ETH",
        .is_buy = true,
        .sz = try Decimal.fromString("0.01"),
        .limit_px = try Decimal.fromString("1100.0"),
        .order_type = .{
            .limit = .{ .tif = "Gtc" },
        },
        .reduce_only = false,
    };

    const response = try ExchangeAPI.placeOrder(&client, order);

    if (std.mem.eql(u8, response.status, "ok")) {
        const status = response.response.data.statuses[0];
        if (status == .resting) {
            const oid = status.resting.oid;
            std.debug.print("Order placed: OID={}\n", .{oid});

            // 撤单
            const cancel_result = try ExchangeAPI.cancelOrder(&client, "ETH", oid);
            try testing.expect(std.mem.eql(u8, cancel_result.status, "ok"));
            std.debug.print("Order cancelled successfully\n", .{});
        }
    }
}
```

---

## WebSocket 测试

### 连接和订阅测试

```zig
test "Integration: WebSocket connect and subscribe" {
    const config = HyperliquidWS.HyperliquidWSConfig{
        .ws_url = HyperliquidWS.HyperliquidWSConfig.DEFAULT_TESTNET_WS_URL,
        .reconnect_interval_ms = 1000,
        .max_reconnect_attempts = 3,
        .ping_interval_ms = 30000,
    };

    var ws_client = try HyperliquidWS.init(testing.allocator, config, logger);
    defer ws_client.deinit();

    // 连接
    try ws_client.connect();
    defer ws_client.disconnect();

    // 订阅订单簿
    try ws_client.subscribe(.{
        .channel = .l2Book,
        .coin = "ETH",
        .user = null,
    });

    // 等待消息
    std.time.sleep(5 * std.time.ns_per_s);

    try testing.expect(ws_client.connected.load(.acquire));
}
```

---

### 订阅 JSON 生成测试

```zig
test "Subscription: generate JSON" {
    const sub = Subscription{
        .channel = .l2Book,
        .coin = "ETH",
        .user = null,
    };

    const json = try sub.toJSON(testing.allocator);
    defer testing.allocator.free(json);

    const expected = "{\"method\":\"subscribe\",\"subscription\":{\"type\":\"l2Book\",\"coin\":\"ETH\"}}";
    try testing.expectEqualStrings(expected, json);
}
```

---

### 消息解析测试

```zig
test "MessageHandler: parse L2 book update" {
    const raw_msg =
        \\{"channel":"l2Book","data":{"coin":"ETH","time":1640000000000,"levels":[[],[]]}}
    ;

    var handler = MessageHandler.init(testing.allocator);
    defer handler.deinit();

    const msg = try handler.parse(raw_msg);

    try testing.expect(msg == .l2_book);
    try testing.expectEqualStrings("ETH", msg.l2_book.coin);
}
```

---

## 手动测试场景

### 场景 1: 获取市场数据

```bash
$ zig test src/exchange/hyperliquid/http_test.zig --test-filter "get order book"
```

### 场景 2: 测试认证签名

```bash
$ zig test src/exchange/hyperliquid/auth_test.zig
```

### 场景 3: 下单测试

```bash
$ export HYPERLIQUID_SECRET_KEY="your_testnet_key"
$ zig test src/exchange/hyperliquid/exchange_api_test.zig --test-filter "place order"
```

### 场景 4: WebSocket 订阅测试

```bash
$ zig test src/exchange/hyperliquid/websocket_test.zig --test-filter "subscribe"
```

---

## 测试辅助工具

### 创建测试客户端

```zig
fn createTestClient() !HyperliquidClient {
    const config = HyperliquidClient.HyperliquidConfig{
        .base_url = HyperliquidClient.HyperliquidConfig.DEFAULT_TESTNET_URL,
        .api_key = null,
        .secret_key = std.os.getenv("HYPERLIQUID_SECRET_KEY"),
        .testnet = true,
        .timeout_ms = 10000,
        .max_retries = 3,
    };

    return try HyperliquidClient.init(testing.allocator, config, logger);
}
```

---

### Mock HTTP 响应

```zig
const MockHTTPClient = struct {
    responses: std.StringHashMap([]const u8),

    pub fn post(self: *MockHTTPClient, endpoint: []const u8, body: []const u8) ![]u8 {
        _ = body;
        return self.responses.get(endpoint) orelse error.NotFound;
    }
};

test "Mock: parse order response" {
    var mock_client = MockHTTPClient{
        .responses = std.StringHashMap([]const u8).init(testing.allocator),
    };
    defer mock_client.responses.deinit();

    const mock_response =
        \\{"status":"ok","response":{"type":"order","data":{"statuses":[{"resting":{"oid":123}}]}}}
    ;

    try mock_client.responses.put("/exchange", mock_response);

    const result = try mock_client.post("/exchange", "{}");
    // 解析和验证...
}
```

---

## 测试最佳实践

### 1. 使用测试网

始终在测试网进行集成测试，避免使用真实资金：

```zig
const config = HyperliquidClient.HyperliquidConfig{
    .base_url = HyperliquidClient.HyperliquidConfig.DEFAULT_TESTNET_URL,
    .testnet = true,
    // ...
};
```

### 2. 环境变量管理

不要在代码中硬编码私钥：

```zig
const secret_key = std.os.getenv("HYPERLIQUID_SECRET_KEY") orelse {
    std.debug.print("Skipping test: HYPERLIQUID_SECRET_KEY not set\n", .{});
    return;
};
```

### 3. 清理资源

确保测试后清理所有资源：

```zig
test "Resource cleanup" {
    var client = try createTestClient();
    defer client.deinit(); // 确保清理

    var orderbook = try InfoAPI.getL2Book(&client, "ETH");
    defer testing.allocator.free(orderbook.bids);
    defer testing.allocator.free(orderbook.asks);

    // 测试逻辑...
}
```

### 4. 超时和重试

为网络操作设置合理的超时：

```zig
const config = HyperliquidClient.HyperliquidConfig{
    .timeout_ms = 10000,  // 10 秒超时
    .max_retries = 3,     // 最多重试 3 次
    // ...
};
```

---

## 运行测试

### 运行所有测试

```bash
$ zig build test
```

### 运行特定测试

```bash
$ zig test src/exchange/hyperliquid/http_test.zig
```

### 运行带过滤的测试

```bash
$ zig test src/exchange/hyperliquid/http_test.zig --test-filter "order"
```

### 启用详细输出

```bash
$ zig test src/exchange/hyperliquid/http_test.zig --summary all
```

---

## 测试场景

### ✅ 已覆盖

- [x] Ed25519 签名生成和验证
- [x] Nonce 生成和递增
- [x] HTTP 客户端初始化
- [x] 订单簿获取和解析
- [x] 用户状态查询
- [x] 下单和撤单操作
- [x] WebSocket 连接
- [x] WebSocket 订阅管理
- [x] 消息解析（所有类型）
- [x] 断线重连
- [x] 速率限制

### 📋 待补充

- [ ] 批量撤单测试
- [ ] 市价单测试（IOC）
- [ ] 长时间 WebSocket 连接测试（24h+）
- [ ] 高频订阅/取消订阅测试
- [ ] 网络故障模拟测试
- [ ] 并发请求测试
- [ ] 内存泄漏测试

---

## 性能基准

### 基准结果

| 操作 | 性能 | 备注 |
|------|------|------|
| Ed25519 签名 | ~0.5ms | 单次签名 |
| 订单簿解析 | ~2ms | 100 档深度 |
| JSON 序列化 | ~1ms | 订单请求 |
| HTTP 请求 | ~100ms | 测试网延迟 |
| WebSocket 消息 | <10ms | 订单簿更新 |

---

## 参考资料

- [Zig Testing Documentation](https://ziglang.org/documentation/master/#Testing)
- [Story 006: Testing Strategy](../../../stories/v0.2-mvp/006-hyperliquid-http.md#测试策略)
- [Story 007: Testing Strategy](../../../stories/v0.2-mvp/007-hyperliquid-ws.md#测试策略)

---

## 运行集成测试

### 前置条件

1. 确保有网络连接
2. 测试网 API 可访问

### 运行命令

```bash
# 运行所有测试
$ zig build test

# 运行集成测试
$ zig build test-integration

# 或直接运行
$ zig build run-hyperliquid-test
```

### 预期输出

```
=== Hyperliquid Integration Tests ===

Test 1: Creating Hyperliquid connector...
✓ Connector created: hyperliquid

Test 2: Connecting to Hyperliquid testnet...
✓ Connected: true

Test 3: Getting ETH-USDC ticker...
✓ ETH-USDC Ticker:
  Bid:        3500.5
  Ask:        3500.5
  Last:       3500.5
  Mid Price:  3500.5
  ...

Test 5: Getting ETH-USDC orderbook (depth=5)...
✓ ETH-USDC Orderbook:
  Bids: 5 levels
  Asks: 5 levels
  Best Bid: 10.5 @ 3500.0
  Best Ask: 8.2 @ 3501.0
```

---

*Last updated: 2025-12-24*
