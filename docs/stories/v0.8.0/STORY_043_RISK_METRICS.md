# Story 043: 风险指标监控

**版本**: v0.8.0
**状态**: 📋 规划中
**优先级**: P1 (重要)
**预计时间**: 2-3 天
**依赖**: Story 041 (止损/止盈系统)
**参考**: VaR, Sharpe Ratio, Maximum Drawdown

---

## 目标

实时计算和监控关键风险指标，帮助交易者了解当前风险状况，及时发现异常并采取措施。

## 背景

专业的风险管理需要持续监控多个风险指标:
1. **VaR (Value at Risk)**: 潜在最大损失
2. **最大回撤**: 从峰值到谷底的最大跌幅
3. **夏普比率**: 风险调整后收益
4. **Sortino 比率**: 仅考虑下行风险的收益指标
5. **Calmar 比率**: 收益与最大回撤的比值

---

## 核心功能

### 1. 风险指标监控器

```zig
/// 风险指标监控器
pub const RiskMetricsMonitor = struct {
    allocator: Allocator,
    config: RiskMetricsConfig,

    // 权益历史
    equity_history: std.ArrayList(EquitySnapshot),

    // 收益历史
    returns_history: std.ArrayList(f64),

    // 缓存的指标
    cached_metrics: ?CachedMetrics = null,
    last_update: i64 = 0,

    const Self = @This();

    pub fn init(allocator: Allocator, config: RiskMetricsConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .equity_history = std.ArrayList(EquitySnapshot).init(allocator),
            .returns_history = std.ArrayList(f64).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.equity_history.deinit();
        self.returns_history.deinit();
    }
};

pub const EquitySnapshot = struct {
    equity: Decimal,
    timestamp: i64,
    cash: Decimal = Decimal.ZERO,
    positions_value: Decimal = Decimal.ZERO,
};

pub const RiskMetricsConfig = struct {
    // VaR 配置
    var_confidence: f64 = 0.99,        // VaR 置信度 (99%)
    var_horizon_days: u32 = 1,          // VaR 时间窗口 (天)

    // 波动率配置
    volatility_window: usize = 20,      // 波动率计算窗口
    volatility_annual_factor: f64 = 252, // 年化因子

    // 回撤配置
    max_drawdown_alert: f64 = 0.10,     // 最大回撤告警阈值 (10%)

    // 夏普/Sortino 配置
    risk_free_rate: f64 = 0.02,         // 无风险利率 (年化 2%)
    sharpe_window: usize = 60,          // 夏普计算窗口

    // 更新频率
    update_interval_ms: u64 = 60000,    // 更新间隔 (1分钟)
};
```

### 2. VaR 计算

```zig
/// 计算 VaR (Value at Risk)
///
/// 使用历史模拟法计算 VaR
/// VaR 表示在给定置信度下，一定时间内的最大可能损失
///
pub fn calculateVaR(self: *Self, confidence: f64) VaRResult {
    if (self.returns_history.items.len < 30) {
        return VaRResult{
            .var_amount = Decimal.ZERO,
            .var_percentage = 0,
            .error_message = "Insufficient data (need 30+ observations)",
        };
    }

    // 复制并排序收益率
    var sorted_returns = self.allocator.alloc(f64, self.returns_history.items.len) catch {
        return VaRResult{ .error_message = "Allocation failed" };
    };
    defer self.allocator.free(sorted_returns);

    @memcpy(sorted_returns, self.returns_history.items);
    std.mem.sort(f64, sorted_returns, {}, std.sort.asc(f64));

    // 计算分位数索引
    const index = @as(usize, @intFromFloat((1.0 - confidence) * @as(f64, @floatFromInt(sorted_returns.len))));
    const var_pct = sorted_returns[index];

    // 转换为金额
    const current_equity = self.getLatestEquity();
    const var_amount = current_equity.mul(Decimal.fromFloat(-var_pct));

    return VaRResult{
        .var_amount = var_amount,
        .var_percentage = -var_pct,
        .confidence = confidence,
        .observations = sorted_returns.len,
    };
}

/// 计算条件 VaR (CVaR / Expected Shortfall)
///
/// CVaR 是超过 VaR 阈值的平均损失
/// 比 VaR 更好地捕捉尾部风险
///
pub fn calculateCVaR(self: *Self, confidence: f64) CVaRResult {
    if (self.returns_history.items.len < 30) {
        return CVaRResult{ .error_message = "Insufficient data" };
    }

    var sorted_returns = self.allocator.alloc(f64, self.returns_history.items.len) catch {
        return CVaRResult{ .error_message = "Allocation failed" };
    };
    defer self.allocator.free(sorted_returns);

    @memcpy(sorted_returns, self.returns_history.items);
    std.mem.sort(f64, sorted_returns, {}, std.sort.asc(f64));

    // VaR 分位数
    const var_index = @as(usize, @intFromFloat((1.0 - confidence) * @as(f64, @floatFromInt(sorted_returns.len))));

    // CVaR = 低于 VaR 的平均值
    var sum: f64 = 0;
    for (sorted_returns[0..var_index]) |r| {
        sum += r;
    }
    const cvar_pct = if (var_index > 0) sum / @as(f64, @floatFromInt(var_index)) else 0;

    const current_equity = self.getLatestEquity();
    const cvar_amount = current_equity.mul(Decimal.fromFloat(-cvar_pct));

    return CVaRResult{
        .cvar_amount = cvar_amount,
        .cvar_percentage = -cvar_pct,
        .confidence = confidence,
    };
}

pub const VaRResult = struct {
    var_amount: Decimal = Decimal.ZERO,
    var_percentage: f64 = 0,
    confidence: f64 = 0,
    observations: usize = 0,
    error_message: ?[]const u8 = null,
};

pub const CVaRResult = struct {
    cvar_amount: Decimal = Decimal.ZERO,
    cvar_percentage: f64 = 0,
    confidence: f64 = 0,
    error_message: ?[]const u8 = null,
};
```

### 3. 最大回撤计算

```zig
/// 计算最大回撤
///
/// 从历史最高点到最低点的最大跌幅
///
pub fn calculateMaxDrawdown(self: *Self) DrawdownResult {
    if (self.equity_history.items.len < 2) {
        return DrawdownResult{ .error_message = "Insufficient data" };
    }

    var max_equity = Decimal.ZERO;
    var max_drawdown = Decimal.ZERO;
    var max_drawdown_pct: f64 = 0;
    var peak_index: usize = 0;
    var trough_index: usize = 0;
    var current_peak_index: usize = 0;

    for (self.equity_history.items, 0..) |snapshot, i| {
        // 更新峰值
        if (snapshot.equity.cmp(max_equity) == .gt) {
            max_equity = snapshot.equity;
            current_peak_index = i;
        }

        // 计算当前回撤
        if (max_equity.cmp(Decimal.ZERO) == .gt) {
            const drawdown = max_equity.sub(snapshot.equity);
            const drawdown_pct = drawdown.toFloat() / max_equity.toFloat();

            // 更新最大回撤
            if (drawdown_pct > max_drawdown_pct) {
                max_drawdown = drawdown;
                max_drawdown_pct = drawdown_pct;
                peak_index = current_peak_index;
                trough_index = i;
            }
        }
    }

    // 计算当前回撤
    const current_equity = self.equity_history.items[self.equity_history.items.len - 1].equity;
    const current_drawdown = max_equity.sub(current_equity);
    const current_drawdown_pct = if (max_equity.cmp(Decimal.ZERO) == .gt)
        current_drawdown.toFloat() / max_equity.toFloat()
    else
        0;

    return DrawdownResult{
        .max_drawdown = max_drawdown,
        .max_drawdown_pct = max_drawdown_pct,
        .peak_equity = max_equity,
        .peak_index = peak_index,
        .trough_index = trough_index,
        .current_drawdown = current_drawdown,
        .current_drawdown_pct = current_drawdown_pct,
        .is_recovering = current_drawdown_pct < max_drawdown_pct,
    };
}

pub const DrawdownResult = struct {
    max_drawdown: Decimal = Decimal.ZERO,
    max_drawdown_pct: f64 = 0,
    peak_equity: Decimal = Decimal.ZERO,
    peak_index: usize = 0,
    trough_index: usize = 0,
    current_drawdown: Decimal = Decimal.ZERO,
    current_drawdown_pct: f64 = 0,
    is_recovering: bool = false,
    error_message: ?[]const u8 = null,
};
```

### 4. 夏普比率计算

```zig
/// 计算夏普比率
///
/// Sharpe = (R - Rf) / σ
/// R = 平均收益率
/// Rf = 无风险利率
/// σ = 收益率标准差
///
pub fn calculateSharpeRatio(self: *Self, window: ?usize) SharpeResult {
    const w = window orelse self.config.sharpe_window;

    if (self.returns_history.items.len < w) {
        return SharpeResult{ .error_message = "Insufficient data" };
    }

    // 使用最近 window 个数据
    const start = self.returns_history.items.len - w;
    const returns = self.returns_history.items[start..];

    // 计算平均收益率
    var sum: f64 = 0;
    for (returns) |r| {
        sum += r;
    }
    const mean = sum / @as(f64, @floatFromInt(returns.len));

    // 计算标准差
    var variance: f64 = 0;
    for (returns) |r| {
        const diff = r - mean;
        variance += diff * diff;
    }
    variance /= @as(f64, @floatFromInt(returns.len - 1));
    const std_dev = @sqrt(variance);

    // 年化
    const annual_factor = @sqrt(self.config.volatility_annual_factor);
    const annual_return = mean * self.config.volatility_annual_factor;
    const annual_volatility = std_dev * annual_factor;

    // 夏普比率
    const sharpe = if (annual_volatility > 0)
        (annual_return - self.config.risk_free_rate) / annual_volatility
    else
        0;

    return SharpeResult{
        .sharpe_ratio = sharpe,
        .annual_return = annual_return,
        .annual_volatility = annual_volatility,
        .risk_free_rate = self.config.risk_free_rate,
        .window = w,
    };
}

pub const SharpeResult = struct {
    sharpe_ratio: f64 = 0,
    annual_return: f64 = 0,
    annual_volatility: f64 = 0,
    risk_free_rate: f64 = 0,
    window: usize = 0,
    error_message: ?[]const u8 = null,
};
```

### 5. Sortino 比率计算

```zig
/// 计算 Sortino 比率
///
/// Sortino = (R - Rf) / σd
/// σd = 下行标准差 (只计算负收益)
///
/// 比夏普比率更适合评估非对称收益分布
///
pub fn calculateSortinoRatio(self: *Self, window: ?usize) SortinoResult {
    const w = window orelse self.config.sharpe_window;

    if (self.returns_history.items.len < w) {
        return SortinoResult{ .error_message = "Insufficient data" };
    }

    const start = self.returns_history.items.len - w;
    const returns = self.returns_history.items[start..];

    // 计算平均收益率
    var sum: f64 = 0;
    for (returns) |r| {
        sum += r;
    }
    const mean = sum / @as(f64, @floatFromInt(returns.len));

    // 计算下行标准差 (只考虑负收益)
    var downside_variance: f64 = 0;
    var downside_count: usize = 0;
    for (returns) |r| {
        if (r < 0) {
            downside_variance += r * r;
            downside_count += 1;
        }
    }

    const downside_dev = if (downside_count > 1)
        @sqrt(downside_variance / @as(f64, @floatFromInt(downside_count - 1)))
    else
        0;

    // 年化
    const annual_factor = @sqrt(self.config.volatility_annual_factor);
    const annual_return = mean * self.config.volatility_annual_factor;
    const annual_downside_dev = downside_dev * annual_factor;

    // Sortino 比率
    const sortino = if (annual_downside_dev > 0)
        (annual_return - self.config.risk_free_rate) / annual_downside_dev
    else
        0;

    return SortinoResult{
        .sortino_ratio = sortino,
        .annual_return = annual_return,
        .downside_deviation = annual_downside_dev,
        .window = w,
    };
}

pub const SortinoResult = struct {
    sortino_ratio: f64 = 0,
    annual_return: f64 = 0,
    downside_deviation: f64 = 0,
    window: usize = 0,
    error_message: ?[]const u8 = null,
};
```

### 6. Calmar 比率

```zig
/// 计算 Calmar 比率
///
/// Calmar = 年化收益率 / 最大回撤
///
/// 衡量收益与风险的关系
///
pub fn calculateCalmarRatio(self: *Self) CalmarResult {
    const drawdown = self.calculateMaxDrawdown();
    if (drawdown.error_message != null) {
        return CalmarResult{ .error_message = drawdown.error_message };
    }

    if (self.returns_history.items.len < 252) {
        return CalmarResult{ .error_message = "Need at least 252 data points for annual return" };
    }

    // 计算年化收益率
    var sum: f64 = 0;
    for (self.returns_history.items) |r| {
        sum += r;
    }
    const mean = sum / @as(f64, @floatFromInt(self.returns_history.items.len));
    const annual_return = mean * self.config.volatility_annual_factor;

    // Calmar 比率
    const calmar = if (drawdown.max_drawdown_pct > 0)
        annual_return / drawdown.max_drawdown_pct
    else
        0;

    return CalmarResult{
        .calmar_ratio = calmar,
        .annual_return = annual_return,
        .max_drawdown_pct = drawdown.max_drawdown_pct,
    };
}

pub const CalmarResult = struct {
    calmar_ratio: f64 = 0,
    annual_return: f64 = 0,
    max_drawdown_pct: f64 = 0,
    error_message: ?[]const u8 = null,
};
```

### 7. 综合指标报告

```zig
/// 获取所有风险指标
pub fn getFullMetrics(self: *Self) RiskMetricsReport {
    return RiskMetricsReport{
        .timestamp = std.time.timestamp(),
        .var_99 = self.calculateVaR(0.99),
        .var_95 = self.calculateVaR(0.95),
        .cvar_99 = self.calculateCVaR(0.99),
        .drawdown = self.calculateMaxDrawdown(),
        .sharpe = self.calculateSharpeRatio(null),
        .sortino = self.calculateSortinoRatio(null),
        .calmar = self.calculateCalmarRatio(),
        .volatility = self.calculateVolatility(),
        .observations = self.returns_history.items.len,
    };
}

pub const RiskMetricsReport = struct {
    timestamp: i64,
    var_99: VaRResult,
    var_95: VaRResult,
    cvar_99: CVaRResult,
    drawdown: DrawdownResult,
    sharpe: SharpeResult,
    sortino: SortinoResult,
    calmar: CalmarResult,
    volatility: f64,
    observations: usize,
};

/// 计算波动率
fn calculateVolatility(self: *Self) f64 {
    if (self.returns_history.items.len < self.config.volatility_window) {
        return 0;
    }

    const start = self.returns_history.items.len - self.config.volatility_window;
    const returns = self.returns_history.items[start..];

    var sum: f64 = 0;
    for (returns) |r| {
        sum += r;
    }
    const mean = sum / @as(f64, @floatFromInt(returns.len));

    var variance: f64 = 0;
    for (returns) |r| {
        const diff = r - mean;
        variance += diff * diff;
    }
    variance /= @as(f64, @floatFromInt(returns.len - 1));

    const daily_vol = @sqrt(variance);
    return daily_vol * @sqrt(self.config.volatility_annual_factor);
}
```

### 8. 数据记录

```zig
/// 记录权益快照
pub fn recordEquity(self: *Self, snapshot: EquitySnapshot) !void {
    // 计算收益率
    if (self.equity_history.items.len > 0) {
        const prev = self.equity_history.items[self.equity_history.items.len - 1];
        if (prev.equity.cmp(Decimal.ZERO) == .gt) {
            const return_pct = snapshot.equity.sub(prev.equity).toFloat() / prev.equity.toFloat();
            try self.returns_history.append(return_pct);
        }
    }

    try self.equity_history.append(snapshot);

    // 限制历史大小 (保留最近 1000 条)
    if (self.equity_history.items.len > 1000) {
        _ = self.equity_history.orderedRemove(0);
    }
    if (self.returns_history.items.len > 1000) {
        _ = self.returns_history.orderedRemove(0);
    }

    // 清除缓存
    self.cached_metrics = null;
}

/// 获取最新权益
fn getLatestEquity(self: *Self) Decimal {
    if (self.equity_history.items.len > 0) {
        return self.equity_history.items[self.equity_history.items.len - 1].equity;
    }
    return Decimal.ZERO;
}
```

---

## 实现任务

### Task 1: 实现数据记录
- [ ] EquitySnapshot 结构
- [ ] recordEquity 函数
- [ ] 收益率计算
- [ ] 历史数据管理

### Task 2: 实现 VaR 计算
- [ ] 历史模拟法 VaR
- [ ] CVaR (Expected Shortfall)
- [ ] 不同置信度支持

### Task 3: 实现回撤计算
- [ ] 最大回撤计算
- [ ] 当前回撤
- [ ] 回撤持续时间

### Task 4: 实现比率计算
- [ ] 夏普比率
- [ ] Sortino 比率
- [ ] Calmar 比率

### Task 5: 实现综合报告
- [ ] getFullMetrics 函数
- [ ] 缓存机制

### Task 6: 单元测试
- [ ] VaR 计算测试
- [ ] 回撤计算测试
- [ ] 比率计算测试
- [ ] 边界条件测试

---

## 验收标准

### 功能
- [ ] VaR 计算正确
- [ ] 最大回撤计算正确
- [ ] 夏普/Sortino/Calmar 比率正确
- [ ] 实时更新功能

### 性能
- [ ] 指标计算 < 10ms
- [ ] 内存稳定

### 测试
- [ ] 与金融库对比验证
- [ ] 极端数据测试

---

## 示例代码

```zig
const std = @import("std");
const RiskMetricsMonitor = @import("risk").RiskMetricsMonitor;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = RiskMetricsConfig{
        .var_confidence = 0.99,
        .sharpe_window = 60,
    };

    var monitor = RiskMetricsMonitor.init(allocator, config);
    defer monitor.deinit();

    // 模拟权益历史
    var equity = Decimal.fromFloat(100000);
    const daily_returns = [_]f64{ 0.01, -0.005, 0.02, -0.01, 0.015, ... };

    for (daily_returns) |ret| {
        equity = equity.mul(Decimal.fromFloat(1 + ret));
        try monitor.recordEquity(.{ .equity = equity, .timestamp = std.time.timestamp() });
    }

    // 获取完整报告
    const report = monitor.getFullMetrics();

    std.debug.print("=== Risk Metrics Report ===\n", .{});
    std.debug.print("VaR 99%: ${d}\n", .{report.var_99.var_amount.toFloat()});
    std.debug.print("Max Drawdown: {d}%\n", .{report.drawdown.max_drawdown_pct * 100});
    std.debug.print("Sharpe Ratio: {d:.2}\n", .{report.sharpe.sharpe_ratio});
    std.debug.print("Sortino Ratio: {d:.2}\n", .{report.sortino.sortino_ratio});
    std.debug.print("Calmar Ratio: {d:.2}\n", .{report.calmar.calmar_ratio});
}
```

---

## 相关文档

- [v0.8.0 Overview](./OVERVIEW.md)
- [Story 041: 止损/止盈系统](./STORY_041_STOP_LOSS.md)
- [Story 044: 告警和通知系统](./STORY_044_ALERT_SYSTEM.md)

---

**Story ID**: STORY-043
**状态**: 📋 规划中
**创建时间**: 2025-12-27
