# RiskMetrics - 风险指标监控

> 实时计算和监控关键风险指标

**状态**: 📋 待开始
**版本**: v0.8.0
**Story**: [STORY-043](../../stories/v0.8.0/STORY_043_RISK_METRICS.md)
**最后更新**: 2025-12-27

---

## 📋 概述

RiskMetrics 模块实时计算和监控关键风险指标，帮助交易者了解当前风险状况，及时发现异常并采取措施。

### 核心特性

- ✅ **VaR (Value at Risk)**: 潜在最大损失估计
- ✅ **CVaR (Expected Shortfall)**: 尾部风险度量
- ✅ **最大回撤**: 从峰值到谷底的最大跌幅
- ✅ **夏普比率**: 风险调整后收益
- ✅ **Sortino 比率**: 仅考虑下行风险
- ✅ **Calmar 比率**: 收益与最大回撤比值

---

## 🚀 快速开始

```zig
const risk = @import("zigQuant").risk;

var monitor = risk.RiskMetricsMonitor.init(allocator, config);
defer monitor.deinit();

// 记录权益变化
try monitor.recordEquity(.{ .equity = Decimal.fromFloat(100000), .timestamp = now });

// 获取完整报告
const report = monitor.getFullMetrics();
std.debug.print("VaR 99%: ${d}\n", .{report.var_99.var_amount.toFloat()});
std.debug.print("Max Drawdown: {d}%\n", .{report.drawdown.max_drawdown_pct * 100});
std.debug.print("Sharpe: {d:.2}\n", .{report.sharpe.sharpe_ratio});
```

---

## 📚 相关文档

- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [Bug 追踪](./bugs.md)
- [变更日志](./changelog.md)

---

## 🔧 核心 API

```zig
pub const RiskMetricsMonitor = struct {
    pub fn init(allocator: Allocator, config: RiskMetricsConfig) RiskMetricsMonitor;
    pub fn recordEquity(self: *Self, snapshot: EquitySnapshot) !void;
    pub fn calculateVaR(self: *Self, confidence: f64) VaRResult;
    pub fn calculateCVaR(self: *Self, confidence: f64) CVaRResult;
    pub fn calculateMaxDrawdown(self: *Self) DrawdownResult;
    pub fn calculateSharpeRatio(self: *Self, window: ?usize) SharpeResult;
    pub fn calculateSortinoRatio(self: *Self, window: ?usize) SortinoResult;
    pub fn calculateCalmarRatio(self: *Self) CalmarResult;
    pub fn getFullMetrics(self: *Self) RiskMetricsReport;
};
```

---

## 📊 风险指标说明

| 指标 | 公式 | 说明 |
|------|------|------|
| VaR 99% | 1% 分位数收益 | 99% 置信度下最大日损失 |
| CVaR | VaR 以下的平均损失 | 尾部风险度量 |
| 最大回撤 | (峰值-谷底)/峰值 | 历史最大跌幅 |
| 夏普比率 | (R-Rf)/σ | 每单位风险的超额收益 |
| Sortino | (R-Rf)/σd | 每单位下行风险的超额收益 |
| Calmar | 年化收益/最大回撤 | 收益与风险的比值 |

---

*Last updated: 2025-12-27*
