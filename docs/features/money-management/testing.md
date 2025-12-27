# MoneyManagement - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-27

---

## 测试覆盖率

- **代码覆盖率**: 目标 > 90%
- **测试用例数**: 目标 20+
- **性能基准**: 计算延迟 < 1ms

---

## 单元测试

### Kelly 公式测试

```zig
test "MoneyManager: kelly - basic calculation" {
    var mm = MoneyManager.init(allocator, &account, config);

    // 模拟 60% 胜率，2:1 盈亏比
    for (0..60) |_| try mm.recordTrade(.{ .pnl = Decimal.fromFloat(200) });
    for (0..40) |_| try mm.recordTrade(.{ .pnl = Decimal.fromFloat(-100) });

    const result = mm.kellyPosition();

    // Kelly = 0.6 - 0.4/2 = 0.4
    // 半 Kelly = 0.2
    try std.testing.expectApproxEqAbs(0.2, result.kelly_fraction, 0.01);
}

test "MoneyManager: kelly - insufficient history" {
    var mm = MoneyManager.init(allocator, &account, config);

    // 只有 5 笔交易
    for (0..5) |_| try mm.recordTrade(.{ .pnl = Decimal.fromFloat(100) });

    const result = mm.kellyPosition();
    try std.testing.expect(result.position_size.cmp(Decimal.ZERO) == .eq);
    try std.testing.expect(result.message != null);
}

test "MoneyManager: kelly - negative edge" {
    var mm = MoneyManager.init(allocator, &account, config);

    // 40% 胜率，1:1 盈亏比 -> 负 Kelly
    for (0..40) |_| try mm.recordTrade(.{ .pnl = Decimal.fromFloat(100) });
    for (0..60) |_| try mm.recordTrade(.{ .pnl = Decimal.fromFloat(-100) });

    const result = mm.kellyPosition();
    try std.testing.expect(result.kelly_fraction < 0);
    try std.testing.expect(result.position_size.cmp(Decimal.ZERO) == .eq);
}
```

### 固定分数测试

```zig
test "MoneyManager: fixed fraction - basic" {
    // 账户 $100,000, 2% 风险, 5% 止损
    var account = Account{ .equity = Decimal.fromFloat(100000) };
    const config = MoneyManagementConfig{ .risk_per_trade = 0.02 };

    var mm = MoneyManager.init(allocator, &account, config);
    const result = mm.fixedFraction(0.05);

    // 仓位 = ($100,000 * 0.02) / 0.05 = $40,000
    try std.testing.expectApproxEqAbs(40000, result.position_size.toFloat(), 1);
}

test "MoneyManager: fixed fraction - max position limit" {
    var account = Account{ .equity = Decimal.fromFloat(100000) };
    const config = MoneyManagementConfig{
        .risk_per_trade = 0.05,      // 5% 风险
        .max_position_pct = 0.20,     // 20% 最大仓位
    };

    var mm = MoneyManager.init(allocator, &account, config);
    const result = mm.fixedFraction(0.02); // 2% 止损

    // 计算值 = $250,000，但限制在 $20,000
    try std.testing.expectApproxEqAbs(20000, result.position_size.toFloat(), 1);
}

test "MoneyManager: fixed fraction - invalid stop loss" {
    var mm = MoneyManager.init(allocator, &account, config);

    const result1 = mm.fixedFraction(0);
    try std.testing.expect(result1.error_message != null);

    const result2 = mm.fixedFraction(1.5);
    try std.testing.expect(result2.error_message != null);
}
```

### 风险平价测试

```zig
test "MoneyManager: risk parity - basic" {
    // 目标波动率 15%, 资产波动率 60%
    var account = Account{ .equity = Decimal.fromFloat(100000) };
    const config = MoneyManagementConfig{ .target_volatility = 0.15 };

    var mm = MoneyManager.init(allocator, &account, config);
    const result = mm.riskParity(0.60);

    // 权重 = 15% / 60% = 25%
    // 仓位 = $100,000 * 0.25 = $25,000
    try std.testing.expectApproxEqAbs(25000, result.position_size.toFloat(), 1);
}

test "MoneyManager: risk parity - low volatility asset" {
    const config = MoneyManagementConfig{
        .target_volatility = 0.15,
        .max_position_pct = 0.20,
    };

    var mm = MoneyManager.init(allocator, &account, config);
    const result = mm.riskParity(0.10); // 10% 波动率

    // 权重 = 15% / 10% = 150%，但限制在 20%
    try std.testing.expectApproxEqAbs(0.20, result.weight, 0.01);
}
```

### 反马丁格尔测试

```zig
test "MoneyManager: anti-martingale - consecutive wins" {
    const config = MoneyManagementConfig{
        .anti_martingale_factor = 1.5,
    };

    var mm = MoneyManager.init(allocator, &account, config);

    // 3 次连续盈利
    try mm.recordTrade(.{ .pnl = Decimal.fromFloat(100) });
    try mm.recordTrade(.{ .pnl = Decimal.fromFloat(100) });
    try mm.recordTrade(.{ .pnl = Decimal.fromFloat(100) });

    const base = Decimal.fromFloat(10000);
    const result = mm.antiMartingale(base);

    // 倍数 = 1.5^3 = 3.375
    try std.testing.expectApproxEqAbs(3.375, result.multiplier, 0.01);
}

test "MoneyManager: anti-martingale - consecutive losses" {
    var mm = MoneyManager.init(allocator, &account, config);

    // 2 次连续亏损
    try mm.recordTrade(.{ .pnl = Decimal.fromFloat(-100) });
    try mm.recordTrade(.{ .pnl = Decimal.fromFloat(-100) });

    const result = mm.antiMartingale(Decimal.fromFloat(10000));

    // 倍数 < 1 (减仓)
    try std.testing.expect(result.multiplier < 1.0);
}
```

---

## 性能基准

```zig
test "MoneyManager: performance" {
    var mm = MoneyManager.init(allocator, &account, config);

    // 添加 1000 笔交易历史
    for (0..1000) |_| {
        try mm.recordTrade(.{ .pnl = Decimal.fromFloat(100) });
    }

    const iterations: usize = 10000;
    var timer = std.time.Timer.start();

    for (0..iterations) |_| {
        _ = mm.kellyPosition();
        _ = mm.fixedFraction(0.05);
        _ = mm.riskParity(0.5);
    }

    const avg_ns = timer.read() / iterations / 3;
    try std.testing.expect(avg_ns < 1_000_000); // < 1ms
}
```

---

## 测试场景

### ✅ 已覆盖

- [x] Kelly 公式基本计算
- [x] Kelly 历史不足处理
- [x] Kelly 负期望处理
- [x] 固定分数基本计算
- [x] 固定分数最大限制
- [x] 风险平价基本计算
- [x] 反马丁格尔连续盈利
- [x] 反马丁格尔连续亏损

### 📋 待补充

- [ ] 极端盈亏比测试
- [ ] 波动率边界测试
- [ ] 交易历史滚动更新测试
