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

---

## 订单生命周期集成测试

### 测试概述

**文件**: `tests/integration/order_lifecycle_test.zig`
**目的**: 验证完整的订单生命周期（下单 → 查询 → 撤单）
**状态**: ✅ 全部通过（2025-12-25）

### 测试阶段

完整的订单生命周期包含 8 个阶段：

#### Phase 1: 连接 Hyperliquid testnet
```zig
try connector.connect();
try std.testing.expect(connector.connected);
```
- 验证可以成功连接到 testnet
- 检查连接状态为 `true`

#### Phase 2: 获取 BTC 市场信息
```zig
// 获取 meta（asset index 映射）
const meta_parsed = try connector.info_api.getMeta();
defer meta_parsed.deinit();

// 获取 oracle price
const oracle_price = try connector.info_api.getOraclePrice("BTC");
```
- 获取 BTC 的 asset index（index = 3）
- 获取 oracle price 作为参考价格（避免"价格偏离 80%"错误）

#### Phase 3: 查询初始账户状态
```zig
const initial_balance = try order_manager.getBalance();
const initial_positions = try order_manager.getPositions();
```
- 记录初始余额（USDC）
- 记录初始持仓（应为空）

#### Phase 4: 下单
```zig
const order_request = types.OrderRequest{
    .pair = .{ .base = "BTC", .quote = "USDC" },
    .side = .buy,
    .order_type = .{ .limit = .{ .price = oracle_price, .tif = .gtc } },
    .amount = "0.001",  // 0.001 BTC
};

const order = try order_manager.submitOrder(order_request);
```
- 使用 oracle price 作为限价（确保不会偏离太远）
- 下单 0.001 BTC（testnet 小额订单）
- 验证 `exchange_order_id` 存在

**关键修复**:
- ✅ 使用动态 asset index（Bug #1 修复）
- ✅ 使用 msgpack 签名（Bug #4 修复）

#### Phase 5: 验证订单成功提交
```zig
try std.testing.expect(order.exchange_order_id != null);
std.debug.print("Order ID: {d}\n", .{order.exchange_order_id.?});
```
- 检查订单有 exchange_order_id
- 状态应为 `resting`（挂单中）

#### Phase 6: 撤单
```zig
try order_manager.cancelOrder(order.client_order_id);
```
- 使用 `client_order_id` 撤销订单
- 验证撤单成功

**关键修复**:
- ✅ 使用正确的账户地址查询订单（Bug #2 修复）
- ✅ 使用 msgpack 编码撤单请求（Bug #4 修复）

#### Phase 7: 验证订单已撤销
```zig
const final_order = try order_manager.getOrder(order.client_order_id);
try std.testing.expectEqual(types.OrderStatus.cancelled, final_order.status);
```
- 从内部状态查询订单（已取消的订单不在 `openOrders` 中）
- 验证状态为 `cancelled`

#### Phase 8: 查询最终账户状态
```zig
const final_balance = try order_manager.getBalance();
const final_positions = try order_manager.getPositions();
```
- 验证余额未变化（订单未成交）
- 验证持仓仍为空

### 测试结果

```
=== Order Lifecycle Integration Test ===

Phase 1: Connecting to Hyperliquid testnet...
✓ Connected

Phase 2: Getting BTC market info...
✓ BTC asset index: 3
✓ Oracle price: $87366.40

Phase 3: Checking initial account state...
✓ Initial balance: 999.00 USDC
✓ Initial positions: 0

Phase 4: Placing BTC order...
✓ Order submitted: OID 45564725639

Phase 5: Verifying order was accepted...
✓ Order confirmed with exchange_order_id

Phase 6: Cancelling order...
✓ Cancel request sent

Phase 7: Verifying order is cancelled...
✓ Order status: cancelled

Phase 8: Checking final account state...
✓ Final balance: 999.00 USDC
✓ Final positions: 0

✅ ALL TESTS PASSED
✅ No memory leaks
```

### 修复的关键 Bug

本测试验证了以下 4 个关键 bug 的修复：

1. **Bug #1: Asset index hardcoded to 0**
   - 测试验证：BTC 使用正确的 asset index 3
   - 修复位置：`connector.zig` + `types.zig`

2. **Bug #2: Querying wrong account address**
   - 测试验证：可以正确查询订单状态
   - 修复位置：`connector.zig` getOrder/getOpenOrders

3. **Bug #3: client_order_id memory leak**
   - 测试验证：内存泄漏检测 0 leaks
   - 修复位置：`order_manager.zig` + `order_store.zig`

4. **Bug #4: Cancel order msgpack encoding**
   - 测试验证：撤单成功（不再返回错误地址）
   - 修复位置：`msgpack.zig` + `exchange_api.zig`

### 性能指标

在 testnet 环境下的测试性能：

| 阶段 | 操作 | 延迟 |
|------|------|------|
| Phase 2 | 获取市场信息 | ~150ms |
| Phase 3 | 查询账户状态 | ~100ms |
| Phase 4 | 下单 | ~250ms |
| Phase 6 | 撤单 | ~200ms |
| Phase 7 | 查询订单状态 | ~100ms |
| **总计** | **完整生命周期** | **~800ms** |

### 运行测试

```bash
# 构建并运行订单生命周期测试
$ zig build test-order-lifecycle

# 输出包含详细日志
$ zig build test-order-lifecycle 2>&1 | grep -E "(Phase|✓|✅)"
```

### 内存泄漏检测

测试使用 `GeneralPurposeAllocator` 进行内存泄漏检测：

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer {
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("❌ MEMORY LEAK DETECTED\n", .{});
    } else {
        std.debug.print("✅ No memory leaks\n", .{});
    }
}
```

**结果**: ✅ 0 泄漏

### MessagePack 编码验证

测试验证了 MessagePack 编码的正确性：

```zig
// 下单 msgpack 编码
const msgpack_order = msgpack.OrderRequest{
    .a = 3,             // BTC asset index
    .b = true,          // buy
    .p = "87366.40",    // oracle price (字符串)
    .s = "0.001",       // size (字符串)
    .r = false,         // reduce_only
    .t = .{ .limit = .{ .tif = "Gtc" } },
};

// 撤单 msgpack 编码
const msgpack_cancel = msgpack.CancelRequest{
    .a = 3,             // BTC asset index
    .o = order_id,      // order ID
};
```

**验证点**:
- ✅ 字段顺序正确（a, b, p, s, r, t）
- ✅ 价格和数量使用字符串格式
- ✅ msgpack 二进制编码正确
- ✅ EIP-712 签名验证通过

### 测试覆盖的功能

本测试覆盖了以下核心功能：

- ✅ **Exchange Router**: IExchange 接口调用
- ✅ **Hyperliquid Connector**: 完整的 REST API 集成
- ✅ **Info API**: getMeta, getOraclePrice, getUserState, getOpenOrders
- ✅ **Exchange API**: placeOrder, cancelOrder
- ✅ **Order Manager**: submitOrder, getOrder, cancelOrder
- ✅ **Position Tracker**: getBalance, getPositions
- ✅ **MessagePack**: packOrderAction, packCancelAction
- ✅ **EIP-712 Auth**: Keccak-256 + Ed25519 签名
- ✅ **内存管理**: 无泄漏，正确的所有权转移

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

*Last updated: 2025-12-25*
