# DataEngine - 测试文档

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 测试策略

### 测试层级

| 层级 | 描述 | 覆盖率目标 |
|------|------|------------|
| 单元测试 | 数据源和转换 | > 90% |
| 集成测试 | 完整数据流 | > 80% |
| Code Parity 测试 | 回测/实盘一致性 | 100% |
| 性能测试 | 吞吐量和延迟 | 基准达标 |

---

## 单元测试

### 1. CSV 数据源测试

```zig
test "csv source - parse line" {
    const line = "2024-01-01 00:00:00,50000,50100,49900,50050,1000";
    const bar = try CsvDataSource.parseLine(line, "BTC-USDT");

    try testing.expectEqualStrings("BTC-USDT", bar.instrument_id);
    try testing.expectEqual(@as(f64, 50000), bar.open);
    try testing.expectEqual(@as(f64, 50100), bar.high);
    try testing.expectEqual(@as(f64, 49900), bar.low);
    try testing.expectEqual(@as(f64, 50050), bar.close);
    try testing.expectEqual(@as(f64, 1000), bar.volume);
}

test "csv source - iterate events" {
    var source = try CsvDataSource.init(testing.allocator, .{
        .path = "test_data/sample.csv",
        .instrument_id = "BTC-USDT",
    });
    defer source.deinit();

    var count: usize = 0;
    while (try source.nextEvent()) |_| {
        count += 1;
    }

    try testing.expectEqual(@as(usize, 100), count);
}

test "csv source - empty file" {
    var source = try CsvDataSource.init(testing.allocator, .{
        .path = "test_data/empty.csv",
        .instrument_id = "BTC-USDT",
    });
    defer source.deinit();

    const event = try source.nextEvent();
    try testing.expect(event == null);
}
```

### 2. K 线构建测试

```zig
test "bar builder - single bar" {
    var builder = BarBuffer.init(testing.allocator, "BTC-USDT", .m1);
    defer builder.deinit();

    // 添加交易
    _ = builder.update(.{ .price = 50000, .quantity = 1, .timestamp = 1000 });
    _ = builder.update(.{ .price = 50100, .quantity = 2, .timestamp = 1500 });
    _ = builder.update(.{ .price = 49900, .quantity = 1, .timestamp = 2000 });

    const bar = builder.current_bar.?;
    try testing.expectEqual(@as(f64, 50000), bar.open);
    try testing.expectEqual(@as(f64, 50100), bar.high);
    try testing.expectEqual(@as(f64, 49900), bar.low);
    try testing.expectEqual(@as(f64, 49900), bar.close);
    try testing.expectEqual(@as(f64, 4), bar.volume);
}

test "bar builder - bar completion" {
    var builder = BarBuffer.init(testing.allocator, "BTC-USDT", .m1);
    defer builder.deinit();

    // 第一分钟的交易
    _ = builder.update(.{ .price = 50000, .timestamp = 60000 });

    // 第二分钟的交易 - 应该完成第一根 K 线
    const completed = builder.update(.{ .price = 50100, .timestamp = 120000 });

    try testing.expect(completed != null);
    try testing.expectEqual(@as(f64, 50000), completed.?.close);
}
```

### 3. 数据标准化测试

```zig
test "normalize hyperliquid trade" {
    const raw = HyperliquidTrade{
        .coin = "BTC",
        .px = "50000.5",
        .sz = "1.5",
        .side = "B",
        .time = 1704067200000,
    };

    const trade = DataNormalizer.normalizeHyperliquidTrade(raw);

    try testing.expectEqualStrings("BTC", trade.instrument_id);
    try testing.expectEqual(@as(f64, 50000.5), trade.price);
    try testing.expectEqual(@as(f64, 1.5), trade.quantity);
    try testing.expectEqual(Side.buy, trade.side);
}
```

---

## 集成测试

### 1. 完整回测流程

```zig
test "backtest data flow" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var data_engine = try DataEngine.init(testing.allocator, &bus, &cache, .{
        .mode = .backtest,
    });
    defer data_engine.deinit();

    // 添加测试数据源
    try data_engine.addSource(.{
        .csv = .{ .path = "test_data/sample.csv", .instrument_id = "BTC-USDT" },
    });

    // 记录接收的事件
    var events_received: usize = 0;
    try bus.subscribe("candle.*", struct {
        fn handler(_: Event) void {
            events_received += 1;
        }
    }.handler);

    // 运行回测
    try data_engine.start();

    // 验证事件已发布
    try testing.expect(events_received > 0);
}
```

### 2. MessageBus 集成

```zig
test "data engine publishes to message bus" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var data_engine = try DataEngine.init(testing.allocator, &bus, &cache, .{
        .mode = .backtest,
    });
    defer data_engine.deinit();

    var market_data_received = false;
    var tick_received = false;
    var shutdown_received = false;

    try bus.subscribe("market_data.*", struct {
        fn handler(_: Event) void { market_data_received = true; }
    }.handler);

    try bus.subscribe("system.tick", struct {
        fn handler(_: Event) void { tick_received = true; }
    }.handler);

    try bus.subscribe("system.shutdown", struct {
        fn handler(_: Event) void { shutdown_received = true; }
    }.handler);

    try data_engine.addSource(.{ .csv = .{ .path = "test_data/sample.csv" } });
    try data_engine.start();

    try testing.expect(tick_received);
    try testing.expect(shutdown_received);
}
```

---

## Code Parity 测试

### 策略在回测和实盘中行为一致

```zig
test "code parity - strategy behavior" {
    // 创建测试策略
    const TestStrategy = struct {
        signals: std.ArrayList(Signal),

        pub fn onMarketData(self: *@This(), event: Event) void {
            const data = event.market_data;
            if (data.bid > 50000) {
                self.signals.append(.{ .side = .buy }) catch {};
            }
        }
    };

    // 回测模式
    var bus_backtest = MessageBus.init(testing.allocator);
    defer bus_backtest.deinit();

    var strategy_backtest = TestStrategy{ .signals = std.ArrayList(Signal).init(testing.allocator) };
    defer strategy_backtest.signals.deinit();

    try bus_backtest.subscribe("market_data.*", strategy_backtest.onMarketData);

    // 发送相同的事件
    const test_event = Event{
        .market_data = .{ .instrument_id = "BTC-USDT", .bid = 50001 },
    };

    try bus_backtest.publish("market_data.BTC-USDT", test_event);

    // 实盘模式 - 相同的代码
    var bus_live = MessageBus.init(testing.allocator);
    defer bus_live.deinit();

    var strategy_live = TestStrategy{ .signals = std.ArrayList(Signal).init(testing.allocator) };
    defer strategy_live.signals.deinit();

    try bus_live.subscribe("market_data.*", strategy_live.onMarketData);
    try bus_live.publish("market_data.BTC-USDT", test_event);

    // 验证行为一致
    try testing.expectEqual(strategy_backtest.signals.items.len, strategy_live.signals.items.len);
    try testing.expectEqual(strategy_backtest.signals.items[0].side, strategy_live.signals.items[0].side);
}
```

---

## 性能测试

### 1. 数据吞吐量测试

```zig
test "data throughput" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var data_engine = try DataEngine.init(testing.allocator, &bus, &cache, .{
        .mode = .backtest,
        .playback_speed = 0, // 最快速度
    });
    defer data_engine.deinit();

    // 添加大数据文件
    try data_engine.addSource(.{
        .csv = .{ .path = "test_data/large_dataset.csv" },
    });

    var count: u64 = 0;
    try bus.subscribe("candle.*", struct {
        fn handler(_: Event) void { count += 1; }
    }.handler);

    const start = std.time.nanoTimestamp();
    try data_engine.start();
    const elapsed_ns = std.time.nanoTimestamp() - start;

    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const throughput = @as(f64, @floatFromInt(count)) / (elapsed_ms / 1000.0);

    std.debug.print("Throughput: {d:.0} events/sec\n", .{throughput});

    // 目标: > 100,000 events/sec
    try testing.expect(throughput > 100_000);
}
```

### 2. 事件延迟测试

```zig
test "event latency" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var latencies = std.ArrayList(i64).init(testing.allocator);
    defer latencies.deinit();

    try bus.subscribe("test.*", struct {
        fn handler(event: Event) void {
            const now = std.time.nanoTimestamp();
            const latency = now - event.getTimestamp();
            latencies.append(latency) catch {};
        }
    }.handler);

    for (0..1000) |_| {
        try bus.publish("test.event", .{
            .tick = .{ .timestamp = std.time.nanoTimestamp() },
        });
    }

    // 计算 P99 延迟
    std.sort.sort(i64, latencies.items, {}, std.sort.asc(i64));
    const p99 = latencies.items[@as(usize, @intFromFloat(@as(f64, @floatFromInt(latencies.items.len)) * 0.99))];

    std.debug.print("P99 latency: {} ns\n", .{p99});

    // 目标: P99 < 1ms
    try testing.expect(p99 < 1_000_000);
}
```

---

## 测试矩阵

| 测试类别 | 测试数量 | 状态 |
|----------|----------|------|
| CSV 数据源 | 5 | 📋 计划中 |
| K 线构建 | 4 | 📋 计划中 |
| 数据标准化 | 6 | 📋 计划中 |
| MessageBus 集成 | 4 | 📋 计划中 |
| Code Parity | 3 | 📋 计划中 |
| 性能测试 | 4 | 📋 计划中 |

---

## 运行测试

```bash
# 运行所有 DataEngine 测试
zig build test -- --test-filter="data_engine"

# 运行 Code Parity 测试
zig build test -- --test-filter="code_parity"

# 运行性能测试
zig build test -- --test-filter="data_engine.*throughput"
```

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [实现细节](./implementation.md)

---

**版本**: v0.5.0
**状态**: 计划中
