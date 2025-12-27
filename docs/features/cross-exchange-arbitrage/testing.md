# Cross-Exchange Arbitrage 测试文档

> 跨交易所套利模块的测试策略和用例

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 测试概述

### 测试范围

| 类别 | 描述 | 优先级 |
|------|------|--------|
| 机会检测 | 正向/反向套利检测 | P0 |
| 利润计算 | 费用扣除和净利润 | P0 |
| 订单执行 | 同步/顺序执行 | P0 |
| 风险控制 | 仓位限制、冷却时间 | P1 |
| 边界条件 | 无机会、部分成交 | P1 |
| 集成测试 | 模拟交易所 | P2 |

### 测试文件

```
src/arbitrage/tests/
├── opportunity_test.zig    # 机会检测测试
├── profit_test.zig         # 利润计算测试
├── executor_test.zig       # 执行测试
├── risk_test.zig           # 风险控制测试
└── integration_test.zig    # 集成测试
```

---

## 单元测试

### 机会检测测试

```zig
const testing = @import("std").testing;
const CrossExchangeArbitrage = @import("../cross_exchange.zig").CrossExchangeArbitrage;
const Decimal = @import("decimal").Decimal;

test "detectOpportunity: forward arbitrage" {
    var arb = createTestArbitrage(.{
        .min_profit_bps = 10,
        .fee_bps_a = 10,
        .fee_bps_b = 10,
    });
    defer arb.deinit();

    // 设置报价: A.ask < B.bid
    arb.mock_provider_a.setQuote(.{
        .bid = Decimal.fromFloat(1995.0),
        .ask = Decimal.fromFloat(2000.0),
    });
    arb.mock_provider_b.setQuote(.{
        .bid = Decimal.fromFloat(2010.0), // 比 A.ask 高
        .ask = Decimal.fromFloat(2015.0),
    });

    const opportunity = arb.detectOpportunity();
    try testing.expect(opportunity != null);
    try testing.expectEqual(ExchangeId.exchange_a, opportunity.?.buy_exchange);
    try testing.expectEqual(ExchangeId.exchange_b, opportunity.?.sell_exchange);
}

test "detectOpportunity: reverse arbitrage" {
    var arb = createTestArbitrage(.{
        .min_profit_bps = 10,
        .fee_bps_a = 10,
        .fee_bps_b = 10,
    });
    defer arb.deinit();

    // 设置报价: B.ask < A.bid
    arb.mock_provider_a.setQuote(.{
        .bid = Decimal.fromFloat(2010.0), // 比 B.ask 高
        .ask = Decimal.fromFloat(2015.0),
    });
    arb.mock_provider_b.setQuote(.{
        .bid = Decimal.fromFloat(1995.0),
        .ask = Decimal.fromFloat(2000.0),
    });

    const opportunity = arb.detectOpportunity();
    try testing.expect(opportunity != null);
    try testing.expectEqual(ExchangeId.exchange_b, opportunity.?.buy_exchange);
    try testing.expectEqual(ExchangeId.exchange_a, opportunity.?.sell_exchange);
}

test "detectOpportunity: no opportunity" {
    var arb = createTestArbitrage(.{
        .min_profit_bps = 10,
        .fee_bps_a = 10,
        .fee_bps_b = 10,
    });
    defer arb.deinit();

    // 设置正常报价 (没有套利机会)
    arb.mock_provider_a.setQuote(.{
        .bid = Decimal.fromFloat(1999.0),
        .ask = Decimal.fromFloat(2001.0),
    });
    arb.mock_provider_b.setQuote(.{
        .bid = Decimal.fromFloat(1998.0),
        .ask = Decimal.fromFloat(2002.0),
    });

    const opportunity = arb.detectOpportunity();
    try testing.expect(opportunity == null);
}

test "detectOpportunity: opportunity below threshold" {
    var arb = createTestArbitrage(.{
        .min_profit_bps = 50, // 高阈值
        .fee_bps_a = 10,
        .fee_bps_b = 10,
    });
    defer arb.deinit();

    // 设置小价差
    arb.mock_provider_a.setQuote(.{
        .bid = Decimal.fromFloat(1998.0),
        .ask = Decimal.fromFloat(2000.0),
    });
    arb.mock_provider_b.setQuote(.{
        .bid = Decimal.fromFloat(2003.0), // 只有 0.15% 价差
        .ask = Decimal.fromFloat(2005.0),
    });

    // 扣除费用后低于阈值
    const opportunity = arb.detectOpportunity();
    try testing.expect(opportunity == null);
}
```

### 利润计算测试

```zig
test "calculateNetProfit: basic" {
    var arb = createTestArbitrage(.{
        .trade_amount = Decimal.fromFloat(1.0),
        .fee_bps_a = 10, // 0.1%
        .fee_bps_b = 10, // 0.1%
    });

    const result = arb.calculateNetProfit(
        Decimal.fromFloat(2000.0), // buy
        Decimal.fromFloat(2010.0), // sell
    );

    // 毛利润 = 10 / 2000 = 0.5% = 50 bps
    try testing.expectEqual(@as(u32, 50), result.gross_bps);

    // 费用 = 2000 * 0.1% + 2010 * 0.1% = 2 + 2.01 = 4.01
    // 净利润 = 10 - 4.01 = 5.99
    // 净利润 bps ≈ 30 bps
    try testing.expect(result.net_bps >= 28 and result.net_bps <= 32);
}

test "calculateNetProfit: negative profit" {
    var arb = createTestArbitrage(.{
        .trade_amount = Decimal.fromFloat(1.0),
        .fee_bps_a = 50, // 0.5%
        .fee_bps_b = 50, // 0.5%
    });

    const result = arb.calculateNetProfit(
        Decimal.fromFloat(2000.0),
        Decimal.fromFloat(2010.0), // 只有 0.5% 毛利润
    );

    // 费用 (1%) > 毛利润 (0.5%)
    try testing.expectEqual(@as(u32, 0), result.net_bps);
    try testing.expect(result.profit.isNegative());
}

test "calculateNetProfit: different fee rates" {
    var arb = createTestArbitrage(.{
        .trade_amount = Decimal.fromFloat(1.0),
        .fee_bps_a = 5,  // 0.05%
        .fee_bps_b = 15, // 0.15%
    });

    const result = arb.calculateNetProfit(
        Decimal.fromFloat(2000.0),
        Decimal.fromFloat(2010.0),
    );

    // 总费用 = 0.05% + 0.15% = 0.2%
    // 净利润 ≈ 0.5% - 0.2% = 0.3% = 30 bps
    try testing.expect(result.net_bps >= 28 and result.net_bps <= 32);
}
```

### 订单执行测试

```zig
test "executeArbitrage: success" {
    var arb = createTestArbitrage(.{});
    defer arb.deinit();

    // 设置模拟执行器成功
    arb.mock_executor_a.setSuccess(true);
    arb.mock_executor_b.setSuccess(true);

    const opportunity = ArbitrageOpportunity{
        .buy_exchange = .exchange_a,
        .sell_exchange = .exchange_b,
        .buy_price = Decimal.fromFloat(2000.0),
        .sell_price = Decimal.fromFloat(2010.0),
        .amount = Decimal.fromFloat(0.1),
        .net_profit_bps = 30,
        .detected_at = std.time.nanoTimestamp(),
    };

    const result = try arb.executeArbitrage(opportunity);

    try testing.expect(result.success);
    try testing.expect(result.buy_fill != null);
    try testing.expect(result.sell_fill != null);
    try testing.expect(result.actual_profit.isPositive());
}

test "executeArbitrage: buy fails" {
    var arb = createTestArbitrage(.{});
    defer arb.deinit();

    arb.mock_executor_a.setSuccess(false); // 买入失败
    arb.mock_executor_b.setSuccess(true);

    const opportunity = createTestOpportunity(.exchange_a, .exchange_b);
    const result = try arb.executeArbitrage(opportunity);

    try testing.expect(!result.success);
    try testing.expect(result.buy_fill == null);
}

test "executeArbitrage: sell fails" {
    var arb = createTestArbitrage(.{});
    defer arb.deinit();

    arb.mock_executor_a.setSuccess(true);
    arb.mock_executor_b.setSuccess(false); // 卖出失败

    const opportunity = createTestOpportunity(.exchange_a, .exchange_b);
    const result = try arb.executeArbitrage(opportunity);

    try testing.expect(!result.success);
    try testing.expect(result.buy_fill != null); // 买入成功
    try testing.expect(result.sell_fill == null);

    // 应该记录未平仓位
    try testing.expectEqual(@as(usize, 1), arb.pending_positions.items.len);
}

test "executeArbitrage: opportunity expired" {
    var arb = createTestArbitrage(.{});
    defer arb.deinit();

    // 创建过期的机会
    var opportunity = createTestOpportunity(.exchange_a, .exchange_b);
    opportunity.detected_at = std.time.nanoTimestamp() - 5_000_000_000; // 5秒前

    const result = arb.executeArbitrage(opportunity);
    try testing.expectError(error.OpportunityExpired, result);
}

test "executeArbitrage: cooldown" {
    var arb = createTestArbitrage(.{
        .cooldown_ms = 1000,
    });
    defer arb.deinit();

    // 第一次执行
    arb.mock_executor_a.setSuccess(true);
    arb.mock_executor_b.setSuccess(true);
    _ = try arb.executeArbitrage(createTestOpportunity(.exchange_a, .exchange_b));

    // 立即再次执行应该被拒绝
    const result = arb.executeArbitrage(createTestOpportunity(.exchange_a, .exchange_b));
    try testing.expectError(error.Cooldown, result);
}
```

### 风险控制测试

```zig
test "position limit: within limit" {
    var arb = createTestArbitrage(.{
        .max_position = Decimal.fromFloat(10.0),
        .trade_amount = Decimal.fromFloat(1.0),
    });
    defer arb.deinit();

    arb.current_position = Decimal.fromFloat(5.0);

    arb.mock_executor_a.setSuccess(true);
    arb.mock_executor_b.setSuccess(true);

    const opportunity = createTestOpportunity(.exchange_a, .exchange_b);
    const result = try arb.executeArbitrage(opportunity);

    try testing.expect(result.success);
}

test "position limit: exceeded" {
    var arb = createTestArbitrage(.{
        .max_position = Decimal.fromFloat(10.0),
        .trade_amount = Decimal.fromFloat(1.0),
    });
    defer arb.deinit();

    arb.current_position = Decimal.fromFloat(10.0); // 已满仓

    const opportunity = createTestOpportunity(.exchange_a, .exchange_b);
    const result = arb.executeArbitrage(opportunity);

    try testing.expectError(error.PositionExceeded, result);
}

test "amount adjustment: limited by depth" {
    var arb = createTestArbitrage(.{
        .trade_amount = Decimal.fromFloat(10.0), // 想买 10
    });
    defer arb.deinit();

    // 但市场深度只有 5
    arb.mock_provider_a.setQuote(.{
        .bid = Decimal.fromFloat(1995.0),
        .ask = Decimal.fromFloat(2000.0),
        .ask_size = Decimal.fromFloat(5.0), // 只有 5
    });
    arb.mock_provider_b.setQuote(.{
        .bid = Decimal.fromFloat(2010.0),
        .ask = Decimal.fromFloat(2015.0),
        .bid_size = Decimal.fromFloat(8.0),
    });

    const opportunity = arb.detectOpportunity();
    try testing.expect(opportunity != null);
    try testing.expect(opportunity.?.amount.eq(Decimal.fromFloat(5.0))); // 调整为 5
}
```

---

## 集成测试

### 模拟交易所测试

```zig
test "integration: full arbitrage cycle" {
    const allocator = testing.allocator;

    // 创建模拟交易所
    var exchange_a = try MockExchange.init(allocator, "ExchangeA");
    defer exchange_a.deinit();

    var exchange_b = try MockExchange.init(allocator, "ExchangeB");
    defer exchange_b.deinit();

    // 创建套利策略
    var arb = CrossExchangeArbitrage.init(
        allocator,
        .{
            .symbol = "ETH-USD",
            .min_profit_bps = 10,
            .trade_amount = Decimal.fromFloat(0.1),
            .fee_bps_a = 10,
            .fee_bps_b = 10,
        },
        &exchange_a.provider, &exchange_a.executor,
        &exchange_b.provider, &exchange_b.executor,
    );
    defer arb.deinit();

    // 模拟价格变化创造套利机会
    exchange_a.setPrice(2000.0, 2001.0);
    exchange_b.setPrice(2010.0, 2011.0); // 套利机会

    // 检测
    const opportunity = arb.detectOpportunity();
    try testing.expect(opportunity != null);

    // 执行
    const result = try arb.executeArbitrage(opportunity.?);
    try testing.expect(result.success);

    // 验证统计
    const stats = arb.getStats();
    try testing.expectEqual(@as(u64, 1), stats.successful);
    try testing.expect(stats.total_profit.isPositive());
}
```

---

## 性能测试

```zig
test "benchmark: opportunity detection" {
    var arb = createTestArbitrage(.{});
    defer arb.deinit();

    arb.mock_provider_a.setQuote(.{
        .bid = Decimal.fromFloat(1999.0),
        .ask = Decimal.fromFloat(2001.0),
    });
    arb.mock_provider_b.setQuote(.{
        .bid = Decimal.fromFloat(1998.0),
        .ask = Decimal.fromFloat(2002.0),
    });

    const iterations: u64 = 100_000;
    var timer = std.time.Timer{};
    timer.reset();

    for (0..iterations) |_| {
        _ = arb.detectOpportunity();
    }

    const elapsed_ns = timer.read();
    const per_call_ns = elapsed_ns / iterations;

    std.debug.print("\nOpportunity detection: {}ns/call\n", .{per_call_ns});
    try testing.expect(per_call_ns < 1000); // < 1μs
}
```

---

## 运行测试

```bash
# 运行所有套利测试
zig build test -- --test-filter="arbitrage"

# 运行特定测试
zig build test -- --test-filter="detectOpportunity"

# 运行性能测试
zig build test -- --test-filter="benchmark"
```

---

*Last updated: 2025-12-27*
