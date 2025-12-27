# RiskMetrics - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-27

---

## 测试覆盖率

- **代码覆盖率**: 目标 > 90%
- **测试用例数**: 目标 20+

---

## 单元测试

### VaR 测试

```zig
test "RiskMetrics: VaR calculation" {
    var monitor = RiskMetricsMonitor.init(allocator, config);

    // 模拟正态分布收益率
    for (0..100) |_| {
        const return_pct = random.floatNorm(0, 0.02);
        try monitor.returns_history.append(return_pct);
    }

    const var_99 = monitor.calculateVaR(0.99);
    try std.testing.expect(var_99.var_percentage > 0);
}
```

### 回撤测试

```zig
test "RiskMetrics: drawdown calculation" {
    var monitor = RiskMetricsMonitor.init(allocator, config);

    // 模拟权益曲线: 100 -> 120 -> 90 -> 110
    try monitor.recordEquity(.{ .equity = Decimal.fromFloat(100000) });
    try monitor.recordEquity(.{ .equity = Decimal.fromFloat(120000) });
    try monitor.recordEquity(.{ .equity = Decimal.fromFloat(90000) });
    try monitor.recordEquity(.{ .equity = Decimal.fromFloat(110000) });

    const dd = monitor.calculateMaxDrawdown();

    // 最大回撤: (120000 - 90000) / 120000 = 25%
    try std.testing.expectApproxEqAbs(0.25, dd.max_drawdown_pct, 0.01);
}
```

---

## 测试场景

### ✅ 已覆盖

- [x] VaR 99% 计算
- [x] VaR 95% 计算
- [x] CVaR 计算
- [x] 最大回撤计算
- [x] 夏普比率计算
- [x] Sortino 比率计算
- [x] 数据不足处理

### 📋 待补充

- [ ] 极端市场条件测试
- [ ] 性能基准测试
