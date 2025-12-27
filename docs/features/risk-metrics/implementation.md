# RiskMetrics - 实现细节

> 深入了解风险指标计算的内部实现

**最后更新**: 2025-12-27

---

## 数据结构

```zig
pub const RiskMetricsMonitor = struct {
    allocator: Allocator,
    config: RiskMetricsConfig,
    equity_history: std.ArrayList(EquitySnapshot),
    returns_history: std.ArrayList(f64),
    cached_metrics: ?CachedMetrics = null,
    last_update: i64 = 0,
};

pub const RiskMetricsConfig = struct {
    var_confidence: f64 = 0.99,
    var_horizon_days: u32 = 1,
    volatility_window: usize = 20,
    volatility_annual_factor: f64 = 252,
    max_drawdown_alert: f64 = 0.10,
    risk_free_rate: f64 = 0.02,
    sharpe_window: usize = 60,
    update_interval_ms: u64 = 60000,
};
```

---

## 核心算法

### VaR 计算 (历史模拟法)

```zig
pub fn calculateVaR(self: *Self, confidence: f64) VaRResult {
    if (self.returns_history.items.len < 30) {
        return VaRResult{ .error_message = "Insufficient data" };
    }

    // 排序收益率
    var sorted = try self.allocator.dupe(f64, self.returns_history.items);
    defer self.allocator.free(sorted);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));

    // 分位数
    const index = @intFromFloat((1.0 - confidence) * @floatFromInt(sorted.len));
    const var_pct = sorted[index];

    const var_amount = self.getLatestEquity().mul(Decimal.fromFloat(-var_pct));

    return VaRResult{
        .var_amount = var_amount,
        .var_percentage = -var_pct,
        .confidence = confidence,
    };
}
```

### 最大回撤计算

```zig
pub fn calculateMaxDrawdown(self: *Self) DrawdownResult {
    var max_equity = Decimal.ZERO;
    var max_drawdown_pct: f64 = 0;
    var peak_index: usize = 0;
    var trough_index: usize = 0;

    for (self.equity_history.items, 0..) |snapshot, i| {
        if (snapshot.equity.cmp(max_equity) == .gt) {
            max_equity = snapshot.equity;
            peak_index = i;
        }

        const drawdown_pct = max_equity.sub(snapshot.equity).toFloat() / max_equity.toFloat();
        if (drawdown_pct > max_drawdown_pct) {
            max_drawdown_pct = drawdown_pct;
            trough_index = i;
        }
    }

    return DrawdownResult{
        .max_drawdown_pct = max_drawdown_pct,
        .peak_index = peak_index,
        .trough_index = trough_index,
    };
}
```

### 夏普比率计算

```zig
pub fn calculateSharpeRatio(self: *Self, window: ?usize) SharpeResult {
    const w = window orelse self.config.sharpe_window;
    const returns = self.returns_history.items[self.returns_history.items.len - w..];

    // 均值
    var sum: f64 = 0;
    for (returns) |r| sum += r;
    const mean = sum / @floatFromInt(returns.len);

    // 标准差
    var variance: f64 = 0;
    for (returns) |r| {
        const diff = r - mean;
        variance += diff * diff;
    }
    variance /= @floatFromInt(returns.len - 1);
    const std_dev = @sqrt(variance);

    // 年化
    const annual_return = mean * self.config.volatility_annual_factor;
    const annual_vol = std_dev * @sqrt(self.config.volatility_annual_factor);

    const sharpe = (annual_return - self.config.risk_free_rate) / annual_vol;

    return SharpeResult{ .sharpe_ratio = sharpe, ... };
}
```

---

*完整实现请参考: `src/risk/metrics.zig`*
