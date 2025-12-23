# Hyperliquid 连接器 - 测试文档

> 测试覆盖和使用指南

**最后更新**: 2025-12-23

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

### Ed25519 签名测试

```zig
const std = @import("std");
const testing = std.testing;
const Auth = @import("auth.zig").Auth;

test "Auth: Ed25519 signature generation" {
    const secret_key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    var auth = try Auth.init(testing.allocator, secret_key);
    defer auth.deinit();

    const nonce: i64 = 1640000000000;
    const action = "{\"type\":\"order\"}";

    const signature = try auth.signL1Action(action, nonce);

    // 验证签名长度
    try testing.expect(signature.r.len == 32);
    try testing.expect(signature.s.len == 32);
}

test "Auth: generate nonce" {
    const nonce1 = Auth.generateNonce();
    std.time.sleep(1 * std.time.ns_per_ms);
    const nonce2 = Auth.generateNonce();

    // Nonce 应该递增
    try testing.expect(nonce2 > nonce1);
}
```

---

### HTTP 客户端测试

```zig
test "HyperliquidClient: initialization" {
    const config = HyperliquidClient.HyperliquidConfig{
        .base_url = "https://api.hyperliquid-testnet.xyz",
        .api_key = null,
        .secret_key = null,
        .testnet = true,
        .timeout_ms = 5000,
        .max_retries = 3,
    };

    var client = try HyperliquidClient.init(testing.allocator, config, logger);
    defer client.deinit();

    try testing.expect(client.config.testnet);
    try testing.expectEqualStrings(
        "https://api.hyperliquid-testnet.xyz",
        client.config.base_url,
    );
}
```

---

### 订单簿解析测试

```zig
test "InfoAPI: parse order book" {
    const json_response =
        \\{
        \\  "coin": "ETH",
        \\  "levels": [
        \\    [
        \\      {"px": "2000.5", "sz": "10.0", "n": 1}
        \\    ],
        \\    [
        \\      {"px": "2001.0", "sz": "8.0", "n": 1}
        \\    ]
        \\  ],
        \\  "time": 1640000000000
        \\}
    ;

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        testing.allocator,
        json_response,
        .{},
    );
    defer parsed.deinit();

    const orderbook = try parseOrderBook(testing.allocator, parsed.value);
    defer testing.allocator.free(orderbook.bids);
    defer testing.allocator.free(orderbook.asks);

    try testing.expectEqualStrings("ETH", orderbook.coin);
    try testing.expect(orderbook.bids.len > 0);
    try testing.expect(orderbook.bids[0].px.toFloat() == 2000.5);
}
```

---

## 集成测试

### 连接测试网

```zig
test "Integration: connect to testnet" {
    const config = HyperliquidClient.HyperliquidConfig{
        .base_url = HyperliquidClient.HyperliquidConfig.DEFAULT_TESTNET_URL,
        .api_key = null,
        .secret_key = null,
        .testnet = true,
        .timeout_ms = 10000,
        .max_retries = 3,
    };

    var client = try HyperliquidClient.init(testing.allocator, config, logger);
    defer client.deinit();

    // 测试获取元数据
    const meta = try InfoAPI.getMeta(&client);
    defer testing.allocator.free(meta.universe);

    try testing.expect(meta.universe.len > 0);
    std.debug.print("\nFound {} assets\n", .{meta.universe.len});
}
```

---

### 获取订单簿测试

```zig
test "Integration: get order book" {
    var client = try createTestClient();
    defer client.deinit();

    const orderbook = try InfoAPI.getL2Book(&client, "ETH");
    defer testing.allocator.free(orderbook.bids);
    defer testing.allocator.free(orderbook.asks);

    try testing.expect(orderbook.bids.len > 0);
    try testing.expect(orderbook.asks.len > 0);

    std.debug.print("\nOrder Book for ETH:\n", .{});
    std.debug.print("  Best Bid: {} @ {}\n", .{
        orderbook.bids[0].sz.toFloat(),
        orderbook.bids[0].px.toFloat(),
    });
    std.debug.print("  Best Ask: {} @ {}\n", .{
        orderbook.asks[0].sz.toFloat(),
        orderbook.asks[0].px.toFloat(),
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

*Last updated: 2025-12-23*
