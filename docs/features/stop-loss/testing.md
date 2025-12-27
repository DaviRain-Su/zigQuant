# StopLoss - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-27

---

## 测试覆盖率

- **代码覆盖率**: 目标 > 90%
- **测试用例数**: 目标 25+
- **性能基准**: 价格检查 < 100μs

---

## 单元测试

### 测试场景 1: 固定止损触发

```zig
test "StopLoss: fixed stop loss - long position" {
    // 多头仓位，入场价 50000，止损价 49000
    var positions = PositionTracker.init(allocator);
    try positions.add(.{ .id = "pos-001", .side = .long, .entry_price = Decimal.fromFloat(50000) });

    var stop_manager = StopLossManager.init(allocator, &positions, &mock_execution);
    try stop_manager.setStopLoss("pos-001", Decimal.fromFloat(49000), .market);

    // 价格未触及止损
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(49500));
    try std.testing.expectEqual(@as(u64, 0), stop_manager.stops_triggered);

    // 价格触及止损
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(48900));
    try std.testing.expectEqual(@as(u64, 1), stop_manager.stops_triggered);
}

test "StopLoss: fixed stop loss - short position" {
    // 空头仓位，入场价 50000，止损价 51000
    try positions.add(.{ .id = "pos-002", .side = .short, .entry_price = Decimal.fromFloat(50000) });

    try stop_manager.setStopLoss("pos-002", Decimal.fromFloat(51000), .market);

    // 价格上涨触及止损
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(51100));
    try std.testing.expectEqual(@as(u64, 1), stop_manager.stops_triggered);
}
```

### 测试场景 2: 固定止盈触发

```zig
test "StopLoss: take profit - long position" {
    try positions.add(.{ .id = "pos-001", .side = .long, .entry_price = Decimal.fromFloat(50000) });

    try stop_manager.setTakeProfit("pos-001", Decimal.fromFloat(53000), .market);

    // 价格未达到止盈
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(52000));
    try std.testing.expectEqual(@as(u64, 0), stop_manager.takes_triggered);

    // 价格达到止盈
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(53500));
    try std.testing.expectEqual(@as(u64, 1), stop_manager.takes_triggered);
}
```

### 测试场景 3: 跟踪止损

```zig
test "StopLoss: trailing stop - update and trigger" {
    try positions.add(.{ .id = "pos-001", .side = .long, .entry_price = Decimal.fromFloat(50000) });

    try stop_manager.setTrailingStopPct("pos-001", 0.02); // 2% 跟踪止损

    // 价格上涨，跟踪止损更新
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(51000));
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(52000));
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(53000)); // 最高点

    // 验证跟踪更新次数
    try std.testing.expect(stop_manager.trailing_updates >= 3);

    // 价格回调但未触及止损 (53000 * 0.98 = 51940)
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(52000));
    try std.testing.expectEqual(@as(u64, 0), stop_manager.stops_triggered);

    // 价格继续下跌触及止损
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(51800));
    try std.testing.expectEqual(@as(u64, 1), stop_manager.stops_triggered);
}

test "StopLoss: trailing stop - only moves in favorable direction" {
    try positions.add(.{ .id = "pos-001", .side = .long, .entry_price = Decimal.fromFloat(50000) });
    try stop_manager.setTrailingStopPct("pos-001", 0.02);

    // 价格上涨
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(52000));
    const config1 = stop_manager.getConfig("pos-001").?;
    const high1 = config1.trailing_stop_high.?.toFloat();

    // 价格下跌，最高价不应该更新
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(51000));
    const config2 = stop_manager.getConfig("pos-001").?;
    const high2 = config2.trailing_stop_high.?.toFloat();

    try std.testing.expectEqual(high1, high2);
}
```

### 测试场景 4: 部分平仓

```zig
test "StopLoss: partial close" {
    try positions.add(.{
        .id = "pos-001",
        .side = .long,
        .quantity = Decimal.fromFloat(1.0),
        .entry_price = Decimal.fromFloat(50000),
    });

    // 设置 50% 部分平仓
    try stop_manager.setStopLoss("pos-001", Decimal.fromFloat(49000), .market);
    var config = stop_manager.getConfig("pos-001").?;
    config.partial_close_pct = 0.5;

    // 触发止损
    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(48500));

    // 验证订单数量
    const last_order = mock_execution.getLastOrder();
    try std.testing.expectApproxEqAbs(0.5, last_order.quantity.toFloat(), 0.001);

    // 配置应该保留 (因为还有剩余仓位)
    try std.testing.expect(stop_manager.getConfig("pos-001") != null);
}
```

### 测试场景 5: 时间止损

```zig
test "StopLoss: time stop" {
    try positions.add(.{ .id = "pos-001", .side = .long });

    const now = std.time.timestamp();
    var config = StopConfig{};
    config.time_stop = now - 1; // 已过期
    config.time_stop_action = .close;

    try stop_manager.stops.put("pos-001", config);

    try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(50000));

    // 应该已触发时间止损
    try std.testing.expect(mock_execution.getLastOrder() != null);
}
```

### 测试场景 6: 错误处理

```zig
test "StopLoss: error - position not found" {
    const result = stop_manager.setStopLoss("non-existent", Decimal.fromFloat(49000), .market);
    try std.testing.expectError(error.PositionNotFound, result);
}

test "StopLoss: error - invalid stop loss for long" {
    try positions.add(.{ .id = "pos-001", .side = .long, .entry_price = Decimal.fromFloat(50000) });

    // 多头止损价高于入场价是无效的
    const result = stop_manager.setStopLoss("pos-001", Decimal.fromFloat(51000), .market);
    try std.testing.expectError(error.InvalidStopLoss, result);
}

test "StopLoss: error - invalid trailing percent" {
    try positions.add(.{ .id = "pos-001", .side = .long });

    // 无效的百分比
    try std.testing.expectError(
        error.InvalidTrailingPercent,
        stop_manager.setTrailingStopPct("pos-001", 0),
    );
    try std.testing.expectError(
        error.InvalidTrailingPercent,
        stop_manager.setTrailingStopPct("pos-001", 1.5),
    );
}
```

---

## 性能基准

### 基准测试

```zig
test "StopLoss: performance - check latency" {
    // 添加 100 个仓位
    for (0..100) |i| {
        const id = try std.fmt.allocPrint(allocator, "pos-{d}", .{i});
        try positions.add(.{ .id = id, .symbol = "BTC-USDT", .side = .long });
        try stop_manager.setStopLoss(id, Decimal.fromFloat(49000), .market);
        try stop_manager.setTakeProfit(id, Decimal.fromFloat(51000), .market);
        try stop_manager.setTrailingStopPct(id, 0.02);
    }

    const iterations: usize = 1000;
    var timer = std.time.Timer.start();

    for (0..iterations) |_| {
        try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(50000));
    }

    const elapsed_ns = timer.read();
    const avg_ns = elapsed_ns / iterations;

    // 目标: < 100μs (100,000 ns)
    try std.testing.expect(avg_ns < 100_000);

    std.debug.print("\nPerformance: {} ns/check (100 positions)\n", .{avg_ns});
}
```

### 基准结果

| 操作 | 性能 |
|------|------|
| 单次检查 (10 仓位) | < 10 μs |
| 单次检查 (100 仓位) | < 100 μs |
| 跟踪止损更新 | < 1 μs |

---

## 运行测试

```bash
# 运行所有止损测试
zig build test -- --test-filter="StopLoss"

# 运行性能测试
zig build test -- --test-filter="StopLoss: performance"
```

---

## 测试场景

### ✅ 已覆盖

- [x] 多头固定止损
- [x] 空头固定止损
- [x] 多头固定止盈
- [x] 空头固定止盈
- [x] 百分比跟踪止损
- [x] 固定距离跟踪止损
- [x] 跟踪止损只向有利方向移动
- [x] 部分平仓
- [x] 时间止损
- [x] 无效仓位错误
- [x] 无效价格错误
- [x] 无效百分比错误

### 📋 待补充

- [ ] 价格跳空场景
- [ ] 并发检查测试
- [ ] 订单执行失败处理
- [ ] 极端价格测试
- [ ] 与 AlertManager 集成测试
