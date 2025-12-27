# Hyperliquid Adapter 测试文档

**版本**: v0.6.0
**状态**: 📋 待开始

---

## 测试覆盖

| 类别 | 测试数 | 覆盖率 |
|------|--------|--------|
| WebSocket 客户端 | - | - |
| 消息解析 | - | - |
| 订阅管理 | - | - |
| 签名验证 | - | - |
| 订单执行 | - | - |
| 集成测试 | - | - |

---

## 单元测试

### WebSocket 帧编解码

```zig
test "encode text frame" {
    var client = WebSocketClient.init(testing.allocator);
    defer client.deinit();

    const payload = "Hello, WebSocket!";
    const frame = try client.encodeFrame(.text, payload);
    defer testing.allocator.free(frame);

    // 验证 FIN + opcode
    try testing.expectEqual(@as(u8, 0x81), frame[0]);

    // 验证 MASK bit set
    try testing.expect((frame[1] & 0x80) != 0);
}

test "decode text frame" {
    const raw_frame = [_]u8{
        0x81, // FIN + text
        0x05, // payload length = 5
        'H', 'e', 'l', 'l', 'o',
    };

    var client = WebSocketClient.init(testing.allocator);
    const frame = try client.decodeFrame(&raw_frame);

    try testing.expect(frame.fin);
    try testing.expectEqual(Opcode.text, frame.opcode);
    try testing.expectEqualStrings("Hello", frame.payload);
}
```

### 消息解析

```zig
test "parse allMids message" {
    const raw =
        \\{"channel":"allMids","data":{"mids":{"BTC":"50000.5","ETH":"3000.2"}}}
    ;

    var parser = MessageParser.init(testing.allocator);
    defer parser.deinit();

    const result = try parser.parse(raw);
    const quotes = result.all_mids;

    try testing.expectEqual(@as(usize, 2), quotes.len);
}

test "parse l2Book message" {
    const raw =
        \\{"channel":"l2Book","data":{"coin":"BTC","levels":[
        \\  [["50000","1.5"],["49999","2.0"]],
        \\  [["50001","1.0"],["50002","0.5"]]
        \\]}}
    ;

    var parser = MessageParser.init(testing.allocator);
    const result = try parser.parse(raw);
    const book = result.orderbook;

    try testing.expectEqualStrings("BTC", book.symbol);
    try testing.expectEqual(@as(usize, 2), book.bids.len);
    try testing.expectEqual(@as(usize, 2), book.asks.len);
}

test "parse trades message" {
    const raw =
        \\{"channel":"trades","data":[
        \\  {"coin":"BTC","side":"B","px":"50000","sz":"0.1","time":1704067200000}
        \\]}
    ;

    var parser = MessageParser.init(testing.allocator);
    const result = try parser.parse(raw);
    const trades = result.trades;

    try testing.expectEqual(@as(usize, 1), trades.len);
    try testing.expectEqualStrings("BTC", trades[0].symbol);
}

test "parse orderUpdate message" {
    const raw =
        \\{"channel":"orderUpdates","data":[
        \\  {"oid":12345,"coin":"BTC","side":"B","sz":"0.1","px":"50000","status":"filled"}
        \\]}
    ;

    var parser = MessageParser.init(testing.allocator);
    const result = try parser.parse(raw);
    const update = result.order_update;

    try testing.expectEqual(@as(u64, 12345), update.oid);
    try testing.expectEqual(OrderStatus.filled, update.status);
}
```

### 订阅管理

```zig
test "add and remove subscription" {
    var manager = SubscriptionManager.init(testing.allocator);
    defer manager.deinit();

    try manager.add(.l2Book, "BTC");
    try manager.add(.trades, "ETH");

    try testing.expectEqual(@as(usize, 2), manager.count());

    manager.remove(.l2Book, "BTC");
    try testing.expectEqual(@as(usize, 1), manager.count());
}

test "build subscription message" {
    const msg = try SubscriptionManager.buildMessage(.l2Book, "BTC", testing.allocator);
    defer testing.allocator.free(msg);

    try testing.expect(std.mem.indexOf(u8, msg, "l2Book") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "BTC") != null);
}

test "get all subscriptions for resubscribe" {
    var manager = SubscriptionManager.init(testing.allocator);
    defer manager.deinit();

    try manager.add(.l2Book, "BTC");
    try manager.add(.trades, "BTC");
    try manager.add(.allMids, "");

    const all = manager.getAll();
    try testing.expectEqual(@as(usize, 3), all.len);
}
```

### 签名验证

```zig
test "wallet initialization from private key" {
    const private_key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const wallet = try Wallet.init(private_key);

    try testing.expectEqual(@as(usize, 20), wallet.address.len);
}

test "sign typed data" {
    const private_key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const wallet = try Wallet.init(private_key);

    const domain = Domain{
        .name = "Hyperliquid",
        .version = "1",
        .chain_id = 42161,
        .verifying_contract = [_]u8{0} ** 20,
    };

    const message = .{
        .action = "order",
        .nonce = 12345,
    };

    const signature = try wallet.signTypedData(domain, message);

    // 验证签名格式
    try testing.expect(signature.v == 27 or signature.v == 28);
}

test "signature hex encoding" {
    const sig = Signature{
        .r = [_]u8{1} ** 32,
        .s = [_]u8{2} ** 32,
        .v = 27,
    };

    const hex = try sig.toHex(testing.allocator);
    defer testing.allocator.free(hex);

    try testing.expect(std.mem.startsWith(u8, hex, "0x"));
    try testing.expectEqual(@as(usize, 132), hex.len);  // 0x + 64 + 64 + 2
}
```

### 订单管理

```zig
test "track order mapping" {
    var manager = OrderManager.init(testing.allocator);
    defer manager.deinit();

    try manager.trackOrder("client-001", 12345);

    const exchange_id = manager.getExchangeOrderId("client-001");
    try testing.expectEqual(@as(?u64, 12345), exchange_id);

    const client_id = manager.getClientOrderId(12345);
    try testing.expectEqualStrings("client-001", client_id.?);
}

test "update order status" {
    var manager = OrderManager.init(testing.allocator);
    defer manager.deinit();

    try manager.trackOrder("client-001", 12345);
    try manager.updateStatus("client-001", .submitted);

    const status = manager.getStatus("client-001");
    try testing.expectEqual(OrderStatus.submitted, status.?);

    try manager.updateStatus("client-001", .filled);
    const new_status = manager.getStatus("client-001");
    try testing.expectEqual(OrderStatus.filled, new_status.?);
}
```

---

## 集成测试

### 连接测试 (需要网络)

```zig
test "integration: connect to testnet" {
    if (std.os.getenv("RUN_NETWORK_TESTS") == null) return error.SkipZigTest;

    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var provider = try HyperliquidDataProvider.init(
        testing.allocator,
        &bus,
        &cache,
        .{ .testnet = true },
    );
    defer provider.deinit();

    try provider.start();

    // 验证连接成功
    try testing.expect(provider.isConnected());
}

test "integration: subscribe and receive data" {
    if (std.os.getenv("RUN_NETWORK_TESTS") == null) return error.SkipZigTest;

    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var received_data = false;
    bus.subscribe("market_data.quote", struct {
        fn callback(_: *anyopaque) void {
            received_data = true;
        }
    }.callback);

    var cache = Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var provider = try HyperliquidDataProvider.init(
        testing.allocator,
        &bus,
        &cache,
        .{ .testnet = true },
    );
    defer provider.deinit();

    try provider.start();
    try provider.subscribe("BTC");

    // 等待数据
    std.time.sleep(5 * std.time.ns_per_s);

    try testing.expect(received_data);
}
```

### 订单执行测试 (Testnet)

```zig
test "integration: submit and cancel order" {
    if (std.os.getenv("RUN_TESTNET_TESTS") == null) return error.SkipZigTest;
    const private_key = std.os.getenv("TESTNET_PRIVATE_KEY") orelse return error.SkipZigTest;

    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var ws_client = try WebSocketClient.init(testing.allocator, .{ .testnet = true });
    defer ws_client.deinit();
    try ws_client.connect();

    var client = try HyperliquidExecutionClient.init(
        testing.allocator,
        &bus,
        &ws_client,
        .{
            .testnet = true,
            .private_key = private_key,
        },
    );
    defer client.deinit();

    // 提交限价单 (远离市价)
    const result = try client.submitOrder(.{
        .client_order_id = "test-001",
        .symbol = "BTC",
        .side = .buy,
        .order_type = .limit,
        .quantity = Decimal.fromFloat(0.001),
        .price = Decimal.fromFloat(30000),  // 远低于市价
    });

    try testing.expect(result.exchange_order_id != null);

    // 取消订单
    const cancelled = try client.cancelOrder("test-001");
    try testing.expect(cancelled);
}

test "integration: query position and account" {
    if (std.os.getenv("RUN_TESTNET_TESTS") == null) return error.SkipZigTest;
    const private_key = std.os.getenv("TESTNET_PRIVATE_KEY") orelse return error.SkipZigTest;

    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var ws_client = try WebSocketClient.init(testing.allocator, .{ .testnet = true });
    defer ws_client.deinit();

    var client = try HyperliquidExecutionClient.init(
        testing.allocator,
        &bus,
        &ws_client,
        .{
            .testnet = true,
            .private_key = private_key,
        },
    );
    defer client.deinit();

    // 查询账户
    const account = try client.getAccount();
    try testing.expect(account.balance.toFloat() >= 0);

    // 查询仓位 (可能为空)
    _ = try client.getPosition("BTC");
}
```

---

## 性能基准

```zig
test "benchmark: message parsing" {
    const raw =
        \\{"channel":"allMids","data":{"mids":{"BTC":"50000.5","ETH":"3000.2","SOL":"100.5"}}}
    ;

    var parser = MessageParser.init(testing.allocator);
    defer parser.deinit();

    var timer = std.time.Timer{};
    timer.reset();

    const iterations = 10000;
    for (0..iterations) |_| {
        const result = try parser.parse(raw);
        _ = result;
    }

    const elapsed_ns = timer.read();
    const avg_ns = elapsed_ns / iterations;

    std.debug.print("Average parse time: {d}ns\n", .{avg_ns});

    // 目标: < 1000ns per parse
    try testing.expect(avg_ns < 1000);
}

test "benchmark: signature generation" {
    const private_key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const wallet = try Wallet.init(private_key);

    const domain = Domain{
        .name = "Hyperliquid",
        .version = "1",
        .chain_id = 42161,
        .verifying_contract = [_]u8{0} ** 20,
    };

    var timer = std.time.Timer{};
    timer.reset();

    const iterations = 1000;
    for (0..iterations) |i| {
        const message = .{ .action = "order", .nonce = i };
        _ = try wallet.signTypedData(domain, message);
    }

    const elapsed_ns = timer.read();
    const avg_us = elapsed_ns / iterations / 1000;

    std.debug.print("Average sign time: {d}us\n", .{avg_us});

    // 目标: < 1000us (1ms) per signature
    try testing.expect(avg_us < 1000);
}
```

---

## 运行测试

```bash
# 运行所有 Hyperliquid 适配器测试
zig build test-hyperliquid

# 运行网络测试 (需要连接)
RUN_NETWORK_TESTS=1 zig build test-hyperliquid-network

# 运行测试网集成测试 (需要私钥)
RUN_TESTNET_TESTS=1 TESTNET_PRIVATE_KEY=xxx zig build test-hyperliquid-testnet

# 运行性能基准
zig build bench-hyperliquid
```

---

*Last updated: 2025-12-27*
