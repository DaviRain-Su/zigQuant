# Paper Trading 测试文档

**版本**: v0.6.0
**状态**: 📋 待开始

---

## 测试覆盖

| 类别 | 测试数 | 覆盖率 |
|------|--------|--------|
| 模拟执行 | - | - |
| 账户管理 | - | - |
| 统计计算 | - | - |
| 集成测试 | - | - |

---

## 单元测试

### 模拟执行测试

```zig
test "market order execution with slippage" {
    var account = SimulatedAccount.init(Decimal.fromInt(10000));
    var cache = MockCache.init(testing.allocator);
    cache.setQuote("BTC", .{
        .bid = Decimal.fromFloat(50000),
        .ask = Decimal.fromFloat(50001),
    });

    var executor = SimulatedExecutor.init(
        testing.allocator,
        null,  // no message bus for unit test
        &cache,
        &account,
        .{
            .commission_rate = Decimal.fromFloat(0.0005),
            .slippage = Decimal.fromFloat(0.0001),  // 0.01%
        },
    );

    // 买入订单
    try executor.executeOrder(.{
        .client_order_id = "test-001",
        .symbol = "BTC",
        .side = .buy,
        .order_type = .market,
        .quantity = Decimal.fromFloat(0.1),
        .price = null,
    });

    // 验证成交价格包含滑点: 50001 * 1.0001 ≈ 50006
    const pos = account.getPosition("BTC").?;
    try testing.expect(pos.entry_price.greaterThan(Decimal.fromFloat(50001)));
}

test "insufficient balance rejection" {
    var account = SimulatedAccount.init(Decimal.fromFloat(100));  // 只有 100
    var cache = MockCache.init(testing.allocator);
    cache.setQuote("BTC", .{
        .bid = Decimal.fromFloat(50000),
        .ask = Decimal.fromFloat(50001),
    });

    var executor = SimulatedExecutor.init(testing.allocator, null, &cache, &account, .{});

    // 尝试买入价值 5000 的 BTC
    const result = executor.executeOrder(.{
        .client_order_id = "test-002",
        .symbol = "BTC",
        .side = .buy,
        .order_type = .market,
        .quantity = Decimal.fromFloat(0.1),
        .price = null,
    });

    try testing.expectError(error.InsufficientBalance, result);
}

test "limit order placement and trigger" {
    var account = SimulatedAccount.init(Decimal.fromInt(10000));
    var cache = MockCache.init(testing.allocator);
    cache.setQuote("BTC", .{
        .bid = Decimal.fromFloat(50000),
        .ask = Decimal.fromFloat(50001),
    });

    var executor = SimulatedExecutor.init(testing.allocator, null, &cache, &account, .{});

    // 放置限价买单
    try executor.placeLimitOrder(.{
        .client_order_id = "limit-001",
        .symbol = "BTC",
        .side = .buy,
        .order_type = .limit,
        .quantity = Decimal.fromFloat(0.1),
        .price = Decimal.fromFloat(49000),
    });

    // 订单应在挂单列表中
    try testing.expectEqual(@as(usize, 1), executor.open_orders.count());

    // 模拟价格下跌
    cache.setQuote("BTC", .{
        .bid = Decimal.fromFloat(48999),
        .ask = Decimal.fromFloat(49000),
    });

    // 检查限价单
    executor.checkLimitOrders();

    // 订单应已执行
    try testing.expectEqual(@as(usize, 0), executor.open_orders.count());
    try testing.expect(account.getPosition("BTC") != null);
}
```

### 账户管理测试

```zig
test "position opening and closing" {
    var account = SimulatedAccount.init(Decimal.fromInt(10000));

    // 开仓
    try account.applyFill(.{
        .order_id = "buy-001",
        .symbol = "BTC",
        .side = .buy,
        .fill_price = Decimal.fromFloat(50000),
        .fill_quantity = Decimal.fromFloat(0.1),
        .commission = Decimal.fromFloat(2.5),
        .timestamp = Timestamp.now(),
    });

    // 验证仓位
    const pos = account.getPosition("BTC").?;
    try testing.expectApproxEqAbs(@as(f64, 0.1), pos.quantity.toFloat(), 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 50000), pos.entry_price.toFloat(), 0.01);

    // 平仓
    try account.applyFill(.{
        .order_id = "sell-001",
        .symbol = "BTC",
        .side = .sell,
        .fill_price = Decimal.fromFloat(51000),
        .fill_quantity = Decimal.fromFloat(0.1),
        .commission = Decimal.fromFloat(2.55),
        .timestamp = Timestamp.now(),
    });

    // 验证仓位已清空
    try testing.expect(account.getPosition("BTC") == null);

    // 验证盈亏: (51000 - 50000) * 0.1 - 2.5 - 2.55 = 94.95
    const trades = account.trade_history.items;
    try testing.expectEqual(@as(usize, 1), trades.len);
    try testing.expectApproxEqAbs(@as(f64, 94.95), trades[0].pnl.toFloat(), 0.01);
}

test "position averaging" {
    var account = SimulatedAccount.init(Decimal.fromInt(20000));

    // 第一次买入
    try account.applyFill(.{
        .order_id = "buy-001",
        .symbol = "BTC",
        .side = .buy,
        .fill_price = Decimal.fromFloat(50000),
        .fill_quantity = Decimal.fromFloat(0.1),
        .commission = Decimal.fromFloat(2.5),
        .timestamp = Timestamp.now(),
    });

    // 第二次买入 (加仓)
    try account.applyFill(.{
        .order_id = "buy-002",
        .symbol = "BTC",
        .side = .buy,
        .fill_price = Decimal.fromFloat(48000),
        .fill_quantity = Decimal.fromFloat(0.1),
        .commission = Decimal.fromFloat(2.4),
        .timestamp = Timestamp.now(),
    });

    // 验证平均价格: (50000 * 0.1 + 48000 * 0.1) / 0.2 = 49000
    const pos = account.getPosition("BTC").?;
    try testing.expectApproxEqAbs(@as(f64, 0.2), pos.quantity.toFloat(), 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 49000), pos.entry_price.toFloat(), 0.01);
}

test "unrealized pnl calculation" {
    var account = SimulatedAccount.init(Decimal.fromInt(10000));
    var cache = MockCache.init(testing.allocator);

    // 开仓
    try account.applyFill(.{
        .order_id = "buy-001",
        .symbol = "BTC",
        .side = .buy,
        .fill_price = Decimal.fromFloat(50000),
        .fill_quantity = Decimal.fromFloat(0.1),
        .commission = Decimal.fromFloat(2.5),
        .timestamp = Timestamp.now(),
    });

    // 设置当前价格
    cache.setQuote("BTC", .{
        .bid = Decimal.fromFloat(52000),
        .ask = Decimal.fromFloat(52001),
    });

    // 更新未实现盈亏
    account.updateUnrealizedPnl(&cache);

    // 验证: (52000 - 50000) * 0.1 = 200
    const pos = account.getPosition("BTC").?;
    try testing.expectApproxEqAbs(@as(f64, 200), pos.unrealized_pnl.toFloat(), 0.01);
}

test "max drawdown calculation" {
    var account = SimulatedAccount.init(Decimal.fromInt(10000));

    // 模拟盈利
    account.current_balance = Decimal.fromFloat(12000);
    try account.updateEquityCurve();
    try testing.expectApproxEqAbs(@as(f64, 12000), account.peak_equity.toFloat(), 0.01);

    // 模拟回撤
    account.current_balance = Decimal.fromFloat(10800);
    try account.updateEquityCurve();

    // 验证回撤: (12000 - 10800) / 12000 = 10%
    try testing.expectApproxEqAbs(@as(f64, 0.1), account.max_drawdown.toFloat(), 0.001);
}
```

### 统计计算测试

```zig
test "win rate calculation" {
    var account = SimulatedAccount.init(Decimal.fromInt(10000));

    // 添加交易历史: 3 赢 2 输
    try account.trade_history.append(.{ .pnl = Decimal.fromFloat(100) });
    try account.trade_history.append(.{ .pnl = Decimal.fromFloat(-50) });
    try account.trade_history.append(.{ .pnl = Decimal.fromFloat(80) });
    try account.trade_history.append(.{ .pnl = Decimal.fromFloat(-30) });
    try account.trade_history.append(.{ .pnl = Decimal.fromFloat(60) });

    const stats = account.getStats();

    // 胜率: 3/5 = 60%
    try testing.expectApproxEqAbs(@as(f64, 0.6), stats.win_rate, 0.001);
}

test "profit factor calculation" {
    var account = SimulatedAccount.init(Decimal.fromInt(10000));

    // 总盈利: 100 + 80 + 60 = 240
    // 总亏损: 50 + 30 = 80
    try account.trade_history.append(.{ .pnl = Decimal.fromFloat(100) });
    try account.trade_history.append(.{ .pnl = Decimal.fromFloat(-50) });
    try account.trade_history.append(.{ .pnl = Decimal.fromFloat(80) });
    try account.trade_history.append(.{ .pnl = Decimal.fromFloat(-30) });
    try account.trade_history.append(.{ .pnl = Decimal.fromFloat(60) });

    const stats = account.getStats();

    // Profit Factor: 240 / 80 = 3.0
    try testing.expectApproxEqAbs(@as(f64, 3.0), stats.profit_factor, 0.01);
}
```

---

## 集成测试

```zig
test "integration: full paper trading session" {
    if (std.os.getenv("RUN_NETWORK_TESTS") == null) return error.SkipZigTest;

    var engine = try PaperTradingEngine.init(testing.allocator, .{
        .initial_balance = Decimal.fromInt(10000),
        .symbols = &[_][]const u8{"BTC"},
    });
    defer engine.deinit();

    // 设置简单策略
    const strategy = SimpleTestStrategy.init();
    engine.setStrategy(strategy.asStrategy());

    // 启动
    try engine.start();

    // 运行 10 秒
    std.time.sleep(10 * std.time.ns_per_s);

    // 停止
    engine.stop();

    // 验证基本功能
    const stats = engine.getStats();
    try testing.expect(stats.total_trades >= 0);
}
```

---

## 性能基准

```zig
test "benchmark: order execution latency" {
    var account = SimulatedAccount.init(Decimal.fromInt(1000000));
    var cache = MockCache.init(testing.allocator);
    cache.setQuote("BTC", .{
        .bid = Decimal.fromFloat(50000),
        .ask = Decimal.fromFloat(50001),
    });

    var executor = SimulatedExecutor.init(testing.allocator, null, &cache, &account, .{});

    var timer = std.time.Timer{};
    timer.reset();

    const iterations = 10000;
    for (0..iterations) |i| {
        try executor.executeOrder(.{
            .client_order_id = std.fmt.allocPrint(testing.allocator, "order-{d}", .{i}),
            .symbol = "BTC",
            .side = .buy,
            .order_type = .market,
            .quantity = Decimal.fromFloat(0.0001),
            .price = null,
        });
    }

    const elapsed_ns = timer.read();
    const avg_us = elapsed_ns / iterations / 1000;

    std.debug.print("Average execution time: {d}us\n", .{avg_us});

    // 目标: < 100us per execution
    try testing.expect(avg_us < 100);
}
```

---

## 运行测试

```bash
# 运行所有 Paper Trading 测试
zig build test-paper-trading

# 运行集成测试 (需要网络)
RUN_NETWORK_TESTS=1 zig build test-paper-trading-integration

# 运行性能基准
zig build bench-paper-trading
```

---

*Last updated: 2025-12-27*
