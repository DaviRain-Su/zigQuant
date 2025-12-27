# LiveTrading - 测试文档

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 测试策略

### 测试层级

| 层级 | 描述 | 覆盖率目标 |
|------|------|------------|
| 单元测试 | WebSocket 和定时器 | > 90% |
| 集成测试 | 完整交易流程 | > 80% |
| 网络测试 | 连接和重连 | 100% |
| 性能测试 | 延迟和吞吐量 | 基准达标 |

---

## 单元测试

### 1. WebSocket 连接测试

```zig
test "websocket - connect success" {
    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{},
    );
    defer engine.deinit();

    // 使用 Mock WebSocket 服务器
    var mock_server = try MockWebSocketServer.init(8080);
    defer mock_server.deinit();

    const conn = try engine.connectWebSocket(.{
        .url = "ws://localhost:8080/ws",
        .host = "localhost",
        .port = 8080,
    });

    try testing.expectEqual(ConnectionState.connected, conn.state);
}

test "websocket - connect timeout" {
    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{},
    );
    defer engine.deinit();

    // 连接到不存在的服务器
    const result = engine.connectWebSocket(.{
        .url = "ws://invalid.example.com:9999/ws",
        .host = "invalid.example.com",
        .port = 9999,
    });

    try testing.expectError(error.ConnectionFailed, result);
}
```

### 2. 自动重连测试

```zig
test "websocket - auto reconnect" {
    var reconnect_count: u32 = 0;

    try bus.subscribe("system.reconnecting", struct {
        fn handler(_: Event) void {
            reconnect_count += 1;
        }
    }.handler);

    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{
            .auto_reconnect = true,
            .reconnect_base_ms = 100,
            .max_reconnect_attempts = 3,
        },
    );
    defer engine.deinit();

    // 模拟连接后断开
    var mock_server = try MockWebSocketServer.init(8080);
    _ = try engine.connectWebSocket(.{ .port = 8080 });

    // 关闭服务器触发断开
    mock_server.close();

    // 等待重连尝试
    std.time.sleep(500 * std.time.ns_per_ms);

    try testing.expect(reconnect_count > 0);
}

test "websocket - max reconnect attempts" {
    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{
            .auto_reconnect = true,
            .max_reconnect_attempts = 3,
        },
    );
    defer engine.deinit();

    const conn = try engine.connectWebSocket(.{
        .url = "ws://invalid:9999/ws",
    });

    // 等待所有重连尝试完成
    std.time.sleep(5 * std.time.ns_per_s);

    try testing.expectEqual(ConnectionState.failed, conn.state);
    try testing.expectEqual(@as(u32, 3), conn.reconnect_attempts);
}
```

### 3. 心跳测试

```zig
test "heartbeat - sends ping" {
    var ping_received = false;

    var mock_server = try MockWebSocketServer.init(8080);
    mock_server.onPing = struct {
        fn handler(_: []const u8) void {
            ping_received = true;
        }
    }.handler;
    defer mock_server.deinit();

    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{
            .heartbeat_interval_ms = 100,
        },
    );
    defer engine.deinit();

    _ = try engine.connectWebSocket(.{ .port = 8080 });

    // 等待心跳
    std.time.sleep(200 * std.time.ns_per_ms);

    try testing.expect(ping_received);
}
```

### 4. Tick 定时器测试

```zig
test "tick timer - fires at interval" {
    var tick_count: u64 = 0;

    try bus.subscribe("system.tick", struct {
        fn handler(_: Event) void {
            tick_count += 1;
        }
    }.handler);

    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{
            .tick_interval_ms = 100,
        },
    );
    defer engine.deinit();

    // 在后台启动
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(e: *LiveTradingEngine) void {
            e.start() catch {};
        }
    }.run, .{&engine});

    std.time.sleep(350 * std.time.ns_per_ms);
    engine.stop();
    thread.join();

    // 应该有 3 次 tick (100, 200, 300ms)
    try testing.expect(tick_count >= 3);
}
```

---

## 集成测试

### 1. 完整交易流程

```zig
test "integration - full trading flow" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var mock_exchange = MockExchange.init();
    var execution_engine = try ExecutionEngine.init(
        testing.allocator,
        &bus,
        &cache,
        &mock_exchange,
        .{},
    );
    defer execution_engine.deinit();

    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{ .tick_interval_ms = 100 },
    );
    engine.setExecutionEngine(&execution_engine);
    defer engine.deinit();

    // 创建简单策略
    var orders_submitted: u32 = 0;
    try bus.subscribe("market_data.*", struct {
        fn handler(event: Event) void {
            if (event.market_data.bid > 50000) {
                bus.request("order.submit", .{
                    .submit_order = .{ .side = .buy },
                }) catch {};
                orders_submitted += 1;
            }
        }
    }.handler);

    // 启动引擎
    const thread = try std.Thread.spawn(.{}, runEngine, .{&engine});

    // 模拟市场数据
    try bus.publish("market_data.BTC-USDT", .{
        .market_data = .{ .bid = 50001 },
    });

    std.time.sleep(100 * std.time.ns_per_ms);
    engine.stop();
    thread.join();

    try testing.expectEqual(@as(u32, 1), orders_submitted);
}
```

### 2. 策略集成测试

```zig
test "integration - strategy receives events" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var events_received = std.ArrayList([]const u8).init(testing.allocator);
    defer events_received.deinit();

    // 订阅所有相关事件
    try bus.subscribe("system.*", struct {
        fn handler(event: Event) void {
            events_received.append(@tagName(event)) catch {};
        }
    }.handler);

    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{ .tick_interval_ms = 50 },
    );
    defer engine.deinit();

    const thread = try std.Thread.spawn(.{}, runEngine, .{&engine});

    std.time.sleep(200 * std.time.ns_per_ms);
    engine.stop();
    thread.join();

    // 验证收到 tick 和 shutdown 事件
    try testing.expect(events_received.items.len > 0);
}
```

---

## 网络测试

### 1. 网络中断测试

```zig
test "network - handles disconnect" {
    var disconnect_received = false;

    try bus.subscribe("system.disconnected", struct {
        fn handler(_: Event) void {
            disconnect_received = true;
        }
    }.handler);

    var mock_server = try MockWebSocketServer.init(8080);

    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{},
    );
    defer engine.deinit();

    _ = try engine.connectWebSocket(.{ .port = 8080 });

    // 模拟网络中断
    mock_server.forceDisconnect();

    std.time.sleep(100 * std.time.ns_per_ms);

    try testing.expect(disconnect_received);
}
```

### 2. 消息处理测试

```zig
test "network - processes messages" {
    var message_received = false;

    try bus.subscribe("market_data.*", struct {
        fn handler(_: Event) void {
            message_received = true;
        }
    }.handler);

    var mock_server = try MockWebSocketServer.init(8080);
    defer mock_server.deinit();

    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{},
    );
    defer engine.deinit();

    _ = try engine.connectWebSocket(.{ .port = 8080 });

    // 模拟服务器发送消息
    mock_server.send("{\"type\":\"market_data\",\"bid\":50000}");

    std.time.sleep(100 * std.time.ns_per_ms);

    try testing.expect(message_received);
}
```

---

## 性能测试

### 1. 消息延迟测试

```zig
test "performance - message latency" {
    var latencies = std.ArrayList(i64).init(testing.allocator);
    defer latencies.deinit();

    var mock_server = try MockWebSocketServer.init(8080);
    defer mock_server.deinit();

    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{},
    );
    defer engine.deinit();

    _ = try engine.connectWebSocket(.{ .port = 8080 });

    // 发送带时间戳的消息
    for (0..1000) |_| {
        const send_time = std.time.nanoTimestamp();
        mock_server.send("{\"ts\":" ++ std.fmt.allocPrint("{}", .{send_time}) ++ "}");
    }

    // 计算 P99 延迟
    std.sort.sort(i64, latencies.items, {}, std.sort.asc(i64));
    const p99_index = @as(usize, @intFromFloat(@as(f64, @floatFromInt(latencies.items.len)) * 0.99));
    const p99 = latencies.items[p99_index];

    std.debug.print("P99 latency: {} ns ({} ms)\n", .{ p99, p99 / 1_000_000 });

    // 目标: P99 < 5ms
    try testing.expect(p99 < 5_000_000);
}
```

### 2. 消息吞吐量测试

```zig
test "performance - message throughput" {
    var count: u64 = 0;

    try bus.subscribe("market_data.*", struct {
        fn handler(_: Event) void {
            count += 1;
        }
    }.handler);

    var mock_server = try MockWebSocketServer.init(8080);
    defer mock_server.deinit();

    var engine = try LiveTradingEngine.init(
        testing.allocator,
        &bus,
        &cache,
        .{},
    );
    defer engine.deinit();

    _ = try engine.connectWebSocket(.{ .port = 8080 });

    const start = std.time.nanoTimestamp();
    const iterations: u64 = 10_000;

    for (0..iterations) |_| {
        mock_server.send("{\"type\":\"market_data\"}");
    }

    std.time.sleep(1 * std.time.ns_per_s);  // 等待处理完成

    const elapsed_ns = std.time.nanoTimestamp() - start;
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
    const throughput = @as(f64, @floatFromInt(count)) / elapsed_s;

    std.debug.print("Throughput: {d:.0} messages/sec\n", .{throughput});

    // 目标: > 5,000 messages/sec
    try testing.expect(throughput > 5_000);
}
```

---

## Mock 服务器

```zig
const MockWebSocketServer = struct {
    listener: std.net.Server,
    connections: std.ArrayList(*Connection),
    onPing: ?fn([]const u8) void = null,

    pub fn init(port: u16) !MockWebSocketServer {
        const listener = try std.net.Server.init(.{
            .address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port),
        });
        return MockWebSocketServer{
            .listener = listener,
            .connections = std.ArrayList(*Connection).init(std.heap.page_allocator),
        };
    }

    pub fn send(self: *MockWebSocketServer, message: []const u8) void {
        for (self.connections.items) |conn| {
            conn.send(message) catch {};
        }
    }

    pub fn forceDisconnect(self: *MockWebSocketServer) void {
        for (self.connections.items) |conn| {
            conn.close();
        }
    }

    pub fn deinit(self: *MockWebSocketServer) void {
        self.listener.deinit();
    }
};
```

---

## 测试矩阵

| 测试类别 | 测试数量 | 状态 |
|----------|----------|------|
| WebSocket 连接 | 4 | 📋 计划中 |
| 自动重连 | 3 | 📋 计划中 |
| 心跳机制 | 3 | 📋 计划中 |
| Tick 定时器 | 2 | 📋 计划中 |
| 完整交易流程 | 3 | 📋 计划中 |
| 网络异常 | 4 | 📋 计划中 |
| 性能测试 | 3 | 📋 计划中 |

---

## 运行测试

```bash
# 运行所有 LiveTrading 测试
zig build test -- --test-filter="live_trading"

# 运行网络测试
zig build test -- --test-filter="live_trading.*network"

# 运行性能测试
zig build test -- --test-filter="live_trading.*performance"
```

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [实现细节](./implementation.md)

---

**版本**: v0.5.0
**状态**: 计划中
