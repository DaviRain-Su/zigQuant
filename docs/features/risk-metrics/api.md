# RiskMetrics - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-27

---

## 类型定义

```zig
pub const RiskMetricsMonitor = struct { ... };

pub const RiskMetricsConfig = struct {
    var_confidence: f64 = 0.99,
    risk_free_rate: f64 = 0.02,
    sharpe_window: usize = 60,
    volatility_annual_factor: f64 = 252,
};

pub const EquitySnapshot = struct {
    equity: Decimal,
    timestamp: i64,
    cash: Decimal = Decimal.ZERO,
    positions_value: Decimal = Decimal.ZERO,
};
```

---

## 函数

### `calculateVaR`
计算 Value at Risk

### `calculateCVaR`
计算条件 VaR (Expected Shortfall)

### `calculateMaxDrawdown`
计算最大回撤

### `calculateSharpeRatio`
计算滚动夏普比率

### `calculateSortinoRatio`
计算 Sortino 比率

### `calculateCalmarRatio`
计算 Calmar 比率

### `getFullMetrics`
获取完整风险报告

---

## 返回类型

```zig
pub const VaRResult = struct {
    var_amount: Decimal,
    var_percentage: f64,
    confidence: f64,
};

pub const DrawdownResult = struct {
    max_drawdown: Decimal,
    max_drawdown_pct: f64,
    peak_index: usize,
    trough_index: usize,
    current_drawdown_pct: f64,
    is_recovering: bool,
};

pub const SharpeResult = struct {
    sharpe_ratio: f64,
    annual_return: f64,
    annual_volatility: f64,
};

pub const RiskMetricsReport = struct {
    var_99: VaRResult,
    var_95: VaRResult,
    cvar_99: CVaRResult,
    drawdown: DrawdownResult,
    sharpe: SharpeResult,
    sortino: SortinoResult,
    calmar: CalmarResult,
    volatility: f64,
};
```
