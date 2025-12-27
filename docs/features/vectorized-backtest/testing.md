# Vectorized Backtest 测试文档

**版本**: v0.6.0
**状态**: 📋 待开始

---

## 测试覆盖

| 类别 | 测试数 | 覆盖率 |
|------|--------|--------|
| SIMD 指标 | - | - |
| 数据加载 | - | - |
| 信号生成 | - | - |
| 订单模拟 | - | - |
| 集成测试 | - | - |

---

## 单元测试

### SIMD 指标测试

```zig
test "SIMD SMA matches scalar SMA" {
    const prices = [_]f64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var simd_result: [10]f64 = undefined;
    var scalar_result: [10]f64 = undefined;

    SimdIndicators.computeSMA_SIMD(&prices, 3, &simd_result);
    ScalarIndicators.computeSMA(&prices, 3, &scalar_result);

    for (simd_result, scalar_result) |s, r| {
        if (!std.math.isNan(s) and !std.math.isNan(r)) {
            try std.testing.expectApproxEqAbs(s, r, 1e-10);
        }
    }
}

test "SIMD EMA matches scalar EMA" {
    // 类似测试
}

test "SIMD RSI matches scalar RSI" {
    // 类似测试
}
```

### 数据加载测试

```zig
test "mmap data loading" {
    const loader = MmapDataLoader{};
    const data = try loader.load("test_data.csv");
    defer loader.unload(data);

    try std.testing.expect(data.len() > 0);
}

test "CSV parsing" {
    const csv = "timestamp,open,high,low,close,volume\n1704067200000,42000,42500,41800,42300,1000\n";
    const candles = try parseCandles(csv);

    try std.testing.expectEqual(@as(usize, 1), candles.len);
    try std.testing.expectApproxEqAbs(@as(f64, 42300), candles[0].close, 0.01);
}
```

### 信号生成测试

```zig
test "MA cross signal generation" {
    const fast_ma = [_]f64{ 100, 101, 102, 101, 100 };
    const slow_ma = [_]f64{ 100, 100, 100, 102, 103 };
    var signals: [5]Signal = undefined;

    BatchSignalGenerator.generateMACrossSignals(&fast_ma, &slow_ma, &signals);

    // 验证金叉和死叉
    try std.testing.expectEqual(Signal.Direction.long, signals[1].direction);
    try std.testing.expectEqual(Signal.Direction.short, signals[3].direction);
}
```

---

## 性能基准

### 回测速度基准

```zig
test "benchmark: 100k bars backtest" {
    const data = try generateTestData(100_000);
    var timer = std.time.Timer{};

    timer.start();
    const result = try backtester.run(data, &strategy);
    const elapsed_ns = timer.read();

    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000;
    const bars_per_sec = 100_000 / (elapsed_ms / 1000);

    std.debug.print("Backtest: {d:.2}ms, {d:.0} bars/s\n", .{ elapsed_ms, bars_per_sec });

    // 验证目标: > 100,000 bars/s
    try std.testing.expect(bars_per_sec > 100_000);
}
```

### SIMD vs 标量基准

```zig
test "benchmark: SIMD vs scalar indicators" {
    const prices = try generateRandomPrices(100_000);

    // SIMD
    var simd_timer = std.time.Timer{};
    simd_timer.start();
    SimdIndicators.computeSMA_SIMD(prices, 20, simd_result);
    const simd_time = simd_timer.read();

    // Scalar
    var scalar_timer = std.time.Timer{};
    scalar_timer.start();
    ScalarIndicators.computeSMA(prices, 20, scalar_result);
    const scalar_time = scalar_timer.read();

    const speedup = @as(f64, @floatFromInt(scalar_time)) / @as(f64, @floatFromInt(simd_time));
    std.debug.print("SIMD speedup: {d:.2}x\n", .{speedup});

    // 验证至少 2x 加速
    try std.testing.expect(speedup > 2.0);
}
```

---

## 准确性验证

### 与事件驱动回测对比

```zig
test "vectorized matches event-driven backtest" {
    const data = try loadTestData();
    const strategy = DualMAStrategy.init(.{ .fast = 10, .slow = 30 });

    // 向量化回测
    const vec_result = try vectorizedBacktester.run(data, strategy);

    // 事件驱动回测
    const event_result = try eventDrivenBacktester.run(data, strategy);

    // 验证结果一致
    try std.testing.expectApproxEqAbs(
        vec_result.total_return_pct,
        event_result.total_return_pct,
        0.01,  // 允许 0.01% 误差
    );
    try std.testing.expectEqual(vec_result.trades.len, event_result.trades.len);
}
```

---

## 运行测试

```bash
# 运行所有向量化回测测试
zig build test-vectorized

# 运行性能基准
zig build bench-vectorized

# 运行准确性验证
zig build test-vectorized-accuracy
```

---

*Last updated: 2025-12-27*
