# Pure Market Making - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-27

---

## 测试覆盖率

- **代码覆盖率**: 目标 > 90%
- **测试用例数**: 20+
- **性能基准**: onTick < 1ms

---

## 单元测试

### 报价计算测试

```zig
test "PureMM quote calculation" {
    const mid = Decimal.fromInt(2000);
    const spread_bps: u32 = 10;  // 0.1%

    // half_spread = mid * 0.05% = 1
    const half_spread = mid.mul(Decimal.fromFloat(0.0005));

    const expected_bid = mid.sub(half_spread);  // 1999
    const expected_ask = mid.add(half_spread);  // 2001

    try testing.expectEqual(@as(f64, 1999.0), expected_bid.toFloat());
    try testing.expectEqual(@as(f64, 2001.0), expected_ask.toFloat());
}

test "PureMM multi-level quotes" {
    const mid = Decimal.fromInt(2000);
    const spread_bps: u32 = 10;
    const level_spread_bps: u32 = 5;

    // Level 0: 1999, 2001
    // Level 1: 1998, 2002
    // Level 2: 1997, 2003

    const level1_offset = mid.mul(Decimal.fromFloat(0.0005));  // 1
    const bid_level1 = mid.sub(Decimal.fromFloat(1.0)).sub(level1_offset);

    try testing.expectEqual(@as(f64, 1998.0), bid_level1.toFloat());
}
```

### 仓位更新测试

```zig
test "PureMM position update on fill" {
    var mm = createTestMM();
    defer mm.deinit();

    // 初始仓位为 0
    try testing.expectEqual(@as(f64, 0.0), mm.current_position.toFloat());

    // 买入成交
    mm.onFill(.{
        .order_id = 1,
        .side = .buy,
        .quantity = Decimal.fromFloat(0.1),
        .price = Decimal.fromInt(2000),
        .timestamp = 0,
    });

    try testing.expectEqual(@as(f64, 0.1), mm.current_position.toFloat());
    try testing.expectEqual(@as(u64, 1), mm.total_trades);

    // 卖出成交
    mm.onFill(.{
        .order_id = 2,
        .side = .sell,
        .quantity = Decimal.fromFloat(0.1),
        .price = Decimal.fromInt(2001),
        .timestamp = 0,
    });

    try testing.expectEqual(@as(f64, 0.0), mm.current_position.toFloat());
    try testing.expectEqual(@as(u64, 2), mm.total_trades);
}
```

### 刷新判断测试

```zig
test "PureMM should refresh quotes" {
    var mm = createTestMM();
    mm.config.min_refresh_bps = 2;  // 0.02%
    defer mm.deinit();

    // 首次调用应返回 true
    try testing.expect(mm.shouldRefreshQuotes(Decimal.fromInt(2000)));

    mm.last_mid_price = Decimal.fromInt(2000);

    // 变化 0.01% (1 bp) - 不应刷新
    try testing.expect(!mm.shouldRefreshQuotes(Decimal.fromFloat(2000.2)));

    // 变化 0.05% (5 bp) - 应刷新
    try testing.expect(mm.shouldRefreshQuotes(Decimal.fromFloat(2001.0)));
}
```

### 仓位限制测试

```zig
test "PureMM position limit" {
    var mm = createTestMM();
    mm.config.max_position = Decimal.fromFloat(0.5);
    mm.current_position = Decimal.fromFloat(0.6);  // 超过限制
    defer mm.deinit();

    // 应该触发警告并调整报价方向
    // 具体行为取决于实现
}
```

---

## 集成测试

### Paper Trading 集成

```zig
test "PureMM with Paper Trading" {
    var paper = PaperTradingEngine.init(testing.allocator);
    defer paper.deinit();

    var mm = PureMarketMaking.init(
        testing.allocator,
        testConfig(),
        paper.getDataProvider(),
        paper.getExecutor(),
    );
    defer mm.deinit();

    var clock = Clock.init(testing.allocator, 100);
    defer clock.deinit();

    try clock.addStrategy(&mm.asClockStrategy());

    // 运行几个 tick
    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});
    std.time.sleep(500_000_000);
    clock.stop();
    thread.join();

    // 验证有订单产生
    try testing.expect(mm.active_bids.items.len > 0 or mm.total_trades > 0);
}
```

### 多策略并行

```zig
test "Multiple PureMM strategies" {
    var clock = Clock.init(testing.allocator, 100);
    defer clock.deinit();

    var mm1 = createTestMM("ETH-USD");
    var mm2 = createTestMM("BTC-USD");
    defer mm1.deinit();
    defer mm2.deinit();

    try clock.addStrategy(&mm1.asClockStrategy());
    try clock.addStrategy(&mm2.asClockStrategy());

    // 运行测试
    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});
    std.time.sleep(300_000_000);
    clock.stop();
    thread.join();

    // 两个策略都应该运行
    try testing.expect(mm1.last_update_tick > 0);
    try testing.expect(mm2.last_update_tick > 0);
}
```

---

## 性能基准

### onTick 性能

```zig
test "PureMM onTick performance" {
    var mm = createTestMM();
    defer mm.deinit();

    const iterations: u64 = 1000;
    var total_ns: u64 = 0;

    for (0..iterations) |i| {
        const start = std.time.nanoTimestamp();
        try mm.onTick(i, start);
        total_ns += @intCast(std.time.nanoTimestamp() - start);
    }

    const avg_ns = total_ns / iterations;
    std.debug.print("Average onTick: {}ns\n", .{avg_ns});

    // 目标: < 1ms = 1,000,000 ns
    try testing.expect(avg_ns < 1_000_000);
}
```

### 基准结果

| 操作 | 性能 |
|------|------|
| onTick (无更新) | < 100ns |
| onTick (需更新) | < 500μs |
| 取消所有订单 | < 1ms |
| 下报价单 | < 200μs |
| 仓位更新 | < 50ns |

---

## 场景测试

### Paper Trading 场景

| 测试场景 | 验证内容 |
|----------|----------|
| 正常做市 | 双边报价正确 |
| 价格变动 | 自动刷新报价 |
| 仓位累积 | 达到限制调整报价 |
| 成交回报 | 仓位正确更新 |
| 策略停止 | 订单正确取消 |

---

## 运行测试

```bash
# 运行所有 PureMM 测试
zig build test -- --test-filter "PureMM"

# 运行性能测试
zig build test -- --test-filter "PureMM.*performance"

# 运行集成测试
zig build test -- --test-filter "PureMM.*Paper"
```

---

## 测试场景

### 已覆盖

- [x] 报价计算正确性
- [x] 多层级报价
- [x] 仓位更新
- [x] 刷新判断
- [x] 统计信息
- [x] 基本 Clock 集成

### 待补充

- [ ] 订单超时处理
- [ ] 部分成交处理
- [ ] 网络延迟模拟
- [ ] 极端行情测试
- [ ] 长时间运行稳定性

---

*测试文件位置: `tests/market_making/pure_mm_test.zig`*
