# Dual Latency 测试文档

> 双向延迟模拟模块的测试策略和用例

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 测试概述

### 测试范围

| 类别 | 描述 | 优先级 |
|------|------|--------|
| 延迟模型 | Constant/Normal/Interpolated | P0 |
| 行情延迟 | applyFeedLatency | P0 |
| 订单延迟 | simulateOrderLatency | P0 |
| 时间线 | OrderTimeline 正确性 | P0 |
| 边界条件 | 零延迟、极大延迟 | P1 |
| 统计验证 | 分布正确性 | P1 |
| 性能测试 | 采样延迟 | P2 |

### 测试文件

```
src/backtest/tests/
├── latency_model_test.zig    # 延迟模型测试
├── latency_sim_test.zig      # 模拟器测试
├── timeline_test.zig         # 时间线测试
└── integration_test.zig      # 集成测试
```

---

## 单元测试

### 延迟模型测试

```zig
const testing = @import("std").testing;
const LatencyModel = @import("../latency_model.zig").LatencyModel;

test "Constant: returns fixed value" {
    const model = LatencyModel{
        .model_type = .Constant,
        .value_ns = 1_000_000, // 1ms
    };

    var rng = std.rand.DefaultPrng.init(42);

    // 多次采样应该返回相同值
    try testing.expectEqual(@as(i64, 1_000_000), model.sample(&rng));
    try testing.expectEqual(@as(i64, 1_000_000), model.sample(&rng));
    try testing.expectEqual(@as(i64, 1_000_000), model.sample(&rng));
}

test "Normal: positive values only" {
    const model = LatencyModel{
        .model_type = .Normal,
        .mean_ns = 1_000_000,
        .std_ns = 500_000,
        .min_ns = 0,
    };

    var rng = std.rand.DefaultPrng.init(42);

    for (0..1000) |_| {
        const sample = model.sample(&rng);
        try testing.expect(sample >= 0);
    }
}

test "Normal: respects min/max" {
    const model = LatencyModel{
        .model_type = .Normal,
        .mean_ns = 1_000_000,
        .std_ns = 500_000,
        .min_ns = 500_000,
        .max_ns = 1_500_000,
    };

    var rng = std.rand.DefaultPrng.init(42);

    for (0..1000) |_| {
        const sample = model.sample(&rng);
        try testing.expect(sample >= 500_000);
        try testing.expect(sample <= 1_500_000);
    }
}

test "Normal: statistical properties" {
    const model = LatencyModel{
        .model_type = .Normal,
        .mean_ns = 1_000_000,
        .std_ns = 100_000,
    };

    var rng = std.rand.DefaultPrng.init(42);
    const n: usize = 10000;

    var sum: i128 = 0;
    var samples: [10000]i64 = undefined;

    for (0..n) |i| {
        samples[i] = model.sample(&rng);
        sum += samples[i];
    }

    const mean = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(n));

    // 均值应该接近配置值 (允许 5% 误差)
    try testing.expect(@abs(mean - 1_000_000) < 50_000);

    // 计算标准差
    var variance_sum: f64 = 0;
    for (samples[0..n]) |s| {
        const diff = @as(f64, @floatFromInt(s)) - mean;
        variance_sum += diff * diff;
    }
    const std_dev = @sqrt(variance_sum / @as(f64, @floatFromInt(n)));

    // 标准差应该接近配置值 (允许 20% 误差)
    try testing.expect(@abs(std_dev - 100_000) < 20_000);
}

test "Interpolated: samples from data" {
    const data = [_]i64{ 100, 200, 300, 400, 500 };
    const model = LatencyModel{
        .model_type = .Interpolated,
        .data = &data,
    };

    var rng = std.rand.DefaultPrng.init(42);

    for (0..100) |_| {
        const sample = model.sample(&rng);
        // 采样应该在数据范围内
        try testing.expect(sample >= 100 and sample <= 500);
    }
}

test "Interpolated: empty data returns 0" {
    const model = LatencyModel{
        .model_type = .Interpolated,
        .data = null,
    };

    var rng = std.rand.DefaultPrng.init(42);
    try testing.expectEqual(@as(i64, 0), model.sample(&rng));
}
```

### 行情延迟测试

```zig
test "applyFeedLatency: basic" {
    var simulator = LatencySimulator.init(.{
        .feed_latency = .{
            .model = .{
                .model_type = .Constant,
                .value_ns = 2_000_000, // 2ms
            },
        },
        .order_latency = .{
            .entry = .{ .model_type = .Constant, .value_ns = 0 },
            .response = .{ .model_type = .Constant, .value_ns = 0 },
        },
    });

    const event = MarketEvent{
        .timestamp = 1_000_000_000, // 1s
        .event_type = .trade,
    };

    const delayed = simulator.applyFeedLatency(event);

    // 延迟后时间应该增加 2ms
    try testing.expectEqual(@as(i64, 1_002_000_000), delayed.timestamp);
}

test "applyFeedLatency: preserves event data" {
    var simulator = LatencySimulator.init(.{
        .feed_latency = .{
            .model = .{ .model_type = .Constant, .value_ns = 1_000_000 },
        },
        .order_latency = .{
            .entry = .{ .model_type = .Constant, .value_ns = 0 },
            .response = .{ .model_type = .Constant, .value_ns = 0 },
        },
    });

    const event = MarketEvent{
        .timestamp = 1_000_000_000,
        .event_type = .trade,
        .symbol = "ETH-USD",
    };

    const delayed = simulator.applyFeedLatency(event);

    try testing.expectEqualStrings("ETH-USD", delayed.symbol);
    try testing.expect(delayed.event_type == .trade);
}
```

### 订单延迟测试

```zig
test "simulateOrderLatency: basic timeline" {
    var simulator = LatencySimulator.init(.{
        .feed_latency = .{
            .model = .{ .model_type = .Constant, .value_ns = 0 },
        },
        .order_latency = .{
            .entry = .{ .model_type = .Constant, .value_ns = 1_000_000 },    // 1ms
            .response = .{ .model_type = .Constant, .value_ns = 1_000_000 }, // 1ms
        },
    });

    const submit_time: i64 = 1_000_000_000; // 1s
    const timeline = simulator.simulateOrderLatency(submit_time);

    try testing.expectEqual(@as(i64, 1_000_000_000), timeline.strategy_submit);
    try testing.expectEqual(@as(i64, 1_001_000_000), timeline.exchange_arrive);
    try testing.expectEqual(@as(i64, 1_002_000_000), timeline.strategy_ack);
    try testing.expectEqual(@as(i64, 2_000_000), timeline.total_roundtrip);
}

test "simulateOrderLatency: different entry and response" {
    var simulator = LatencySimulator.init(.{
        .feed_latency = .{
            .model = .{ .model_type = .Constant, .value_ns = 0 },
        },
        .order_latency = .{
            .entry = .{ .model_type = .Constant, .value_ns = 500_000 },    // 0.5ms
            .response = .{ .model_type = .Constant, .value_ns = 1_500_000 }, // 1.5ms
        },
    });

    const submit_time: i64 = 0;
    const timeline = simulator.simulateOrderLatency(submit_time);

    try testing.expectEqual(@as(i64, 500_000), timeline.entryLatency());
    try testing.expectEqual(@as(i64, 1_500_000), timeline.responseLatency());
    try testing.expectEqual(@as(i64, 2_000_000), timeline.total_roundtrip);
}
```

### 时间线测试

```zig
test "OrderTimeline: helper methods" {
    const timeline = OrderTimeline{
        .strategy_submit = 1_000_000_000,
        .exchange_arrive = 1_001_000_000,
        .exchange_process = 1_001_500_000,
        .strategy_ack = 1_003_000_000,
        .total_roundtrip = 3_000_000,
    };

    try testing.expectEqual(@as(i64, 1_000_000), timeline.entryLatency());
    try testing.expectEqual(@as(i64, 1_500_000), timeline.responseLatency());
}
```

---

## 边界条件测试

```zig
test "zero latency" {
    var simulator = LatencySimulator.init(.{
        .feed_latency = .{
            .model = .{ .model_type = .Constant, .value_ns = 0 },
        },
        .order_latency = .{
            .entry = .{ .model_type = .Constant, .value_ns = 0 },
            .response = .{ .model_type = .Constant, .value_ns = 0 },
        },
    });

    const event = MarketEvent{ .timestamp = 1000, .event_type = .trade };
    const delayed = simulator.applyFeedLatency(event);

    try testing.expectEqual(@as(i64, 1000), delayed.timestamp);
}

test "very large latency" {
    var simulator = LatencySimulator.init(.{
        .feed_latency = .{
            .model = .{
                .model_type = .Constant,
                .value_ns = 1_000_000_000_000, // 1000s
            },
        },
        .order_latency = .{
            .entry = .{ .model_type = .Constant, .value_ns = 0 },
            .response = .{ .model_type = .Constant, .value_ns = 0 },
        },
    });

    const event = MarketEvent{ .timestamp = 0, .event_type = .trade };
    const delayed = simulator.applyFeedLatency(event);

    try testing.expectEqual(@as(i64, 1_000_000_000_000), delayed.timestamp);
}

test "Normal with zero std_ns acts like Constant" {
    const model = LatencyModel{
        .model_type = .Normal,
        .mean_ns = 1_000_000,
        .std_ns = 0, // 零标准差
    };

    var rng = std.rand.DefaultPrng.init(42);

    // 所有采样应该等于均值
    for (0..100) |_| {
        try testing.expectEqual(@as(i64, 1_000_000), model.sample(&rng));
    }
}
```

---

## 集成测试

```zig
test "integration: event ordering with latency" {
    const allocator = testing.allocator;

    var simulator = LatencySimulator.init(.{
        .feed_latency = .{
            .model = .{ .model_type = .Constant, .value_ns = 2_000_000 },
        },
        .order_latency = .{
            .entry = .{ .model_type = .Constant, .value_ns = 1_000_000 },
            .response = .{ .model_type = .Constant, .value_ns = 1_000_000 },
        },
    });

    var queue = EventQueue.init(allocator);
    defer queue.deinit();

    // 添加事件 (交易所时间: 1, 2, 3)
    const events = [_]MarketEvent{
        .{ .timestamp = 1_000_000, .event_type = .trade },
        .{ .timestamp = 2_000_000, .event_type = .trade },
        .{ .timestamp = 3_000_000, .event_type = .trade },
    };

    for (events) |e| {
        const delayed = simulator.applyFeedLatency(e);
        try queue.push(e, delayed.timestamp - e.timestamp);
    }

    // 验证事件顺序 (策略可见时间: 3, 4, 5)
    var visible_times: [3]i64 = undefined;
    var i: usize = 0;
    while (queue.heap.removeOrNull()) |event| {
        visible_times[i] = event.visible_time;
        i += 1;
    }

    try testing.expectEqual(@as(i64, 3_000_000), visible_times[0]);
    try testing.expectEqual(@as(i64, 4_000_000), visible_times[1]);
    try testing.expectEqual(@as(i64, 5_000_000), visible_times[2]);
}

test "integration: order lifecycle" {
    var simulator = LatencySimulator.init(.{
        .feed_latency = .{
            .model = .{ .model_type = .Constant, .value_ns = 2_000_000 },
        },
        .order_latency = .{
            .entry = .{ .model_type = .Constant, .value_ns = 1_000_000 },
            .response = .{ .model_type = .Constant, .value_ns = 1_000_000 },
        },
    });

    // 策略在 T=5ms 看到事件 (交易所时间 T=3ms)
    const event_visible_time: i64 = 5_000_000;

    // 策略决定下单
    const timeline = simulator.simulateOrderLatency(event_visible_time);

    // 验证时间线
    try testing.expectEqual(@as(i64, 5_000_000), timeline.strategy_submit);
    try testing.expectEqual(@as(i64, 6_000_000), timeline.exchange_arrive);
    try testing.expectEqual(@as(i64, 7_000_000), timeline.strategy_ack);

    // 注意: 订单到达交易所时 (T=6ms)，实际市场已经在 T=6ms-2ms=4ms 之后
    // 这反映了 HFT 的时序挑战
}
```

---

## 性能测试

```zig
test "benchmark: sample latency" {
    const model = LatencyModel{
        .model_type = .Normal,
        .mean_ns = 1_000_000,
        .std_ns = 100_000,
    };

    var rng = std.rand.DefaultPrng.init(42);
    const iterations: u64 = 1_000_000;

    var timer = std.time.Timer{};
    timer.reset();

    for (0..iterations) |_| {
        _ = model.sample(&rng);
    }

    const elapsed_ns = timer.read();
    const per_sample_ns = elapsed_ns / iterations;

    std.debug.print("\nNormal sample: {}ns/call\n", .{per_sample_ns});
    try testing.expect(per_sample_ns < 100); // < 100ns
}

test "benchmark: applyFeedLatency" {
    var simulator = LatencySimulator.init(.{
        .feed_latency = .{
            .model = .{
                .model_type = .Normal,
                .mean_ns = 1_000_000,
                .std_ns = 100_000,
            },
        },
        .order_latency = .{
            .entry = .{ .model_type = .Constant, .value_ns = 0 },
            .response = .{ .model_type = .Constant, .value_ns = 0 },
        },
    });

    const event = MarketEvent{ .timestamp = 1000, .event_type = .trade };
    const iterations: u64 = 1_000_000;

    var timer = std.time.Timer{};
    timer.reset();

    for (0..iterations) |_| {
        _ = simulator.applyFeedLatency(event);
    }

    const elapsed_ns = timer.read();
    const per_call_ns = elapsed_ns / iterations;

    std.debug.print("\napplyFeedLatency: {}ns/call\n", .{per_call_ns});
    try testing.expect(per_call_ns < 150); // < 150ns
}
```

---

## 运行测试

```bash
# 运行所有延迟测试
zig build test -- --test-filter="latency"

# 运行模型测试
zig build test -- --test-filter="LatencyModel"

# 运行性能测试
zig build test -- --test-filter="benchmark"
```

---

*Last updated: 2025-12-27*
