# Story 021: PerformanceAnalyzer 性能分析器

**Story ID**: STORY-021
**版本**: v0.3.0
**优先级**: P0
**工作量**: 1天
**状态**: 待开始
**创建时间**: 2025-12-25

---

## 📋 基本信息

### 所属版本
v0.3.0 - Week 2: 内置策略 + 回测引擎

### 依赖关系
- **前置依赖**:
  - STORY-020: BacktestEngine 回测引擎核心（提供交易数据）
- **后置影响**:
  - STORY-022: GridSearchOptimizer 使用性能指标评估参数
  - STORY-023: CLI 策略命令展示性能报告
  - STORY-024: 示例和文档需要展示性能分析结果

---

## 🎯 Story 描述

### 用户故事
作为一个**量化交易开发者**，我希望**对回测结果进行全面的性能分析**，以便**科学评估策略的盈利能力、风险水平和稳定性**。

### 业务价值
- 提供量化策略评估的标准指标
- 帮助开发者识别策略的优势和劣势
- 支持策略之间的客观对比
- 为参数优化提供评估标准
- 降低策略实盘风险

### 技术背景
性能分析器（Performance Analyzer）是量化交易系统的重要组件，用于评估策略表现：

**核心性能指标**（参考 Freqtrade/Backtrader）:

1. **盈利指标**:
   - 总盈利/亏损
   - 净利润
   - 盈亏比（Profit Factor）
   - 平均盈利/亏损

2. **胜率指标**:
   - 胜率（Win Rate）
   - 盈利交易数/亏损交易数

3. **风险指标**:
   - 最大回撤（Max Drawdown）
   - 最大回撤持续时间
   - 夏普比率（Sharpe Ratio）
   - 索提诺比率（Sortino Ratio）
   - 卡玛比率（Calmar Ratio）

4. **交易统计**:
   - 总交易次数
   - 平均持仓时间
   - 最长/最短持仓时间
   - 最大连续盈利/亏损次数

5. **收益统计**:
   - 总收益率（Total Return）
   - 年化收益率（Annualized Return）
   - 月度/日度收益率

参考实现：
- [Freqtrade Performance Metrics](https://www.freqtrade.io/en/stable/backtesting/#backtesting-metrics)
- [Backtrader Analyzers](https://www.backtrader.com/docu/analyzers/analyzers/)
- [Quantopian Performance Attribution](https://www.quantopian.com/tutorials/getting-started)

---

## 📝 详细需求

### 功能需求

#### FR-021-1: 基础盈利指标计算
- **总盈利（Total Profit）**: 所有盈利交易的盈利总和
- **总亏损（Total Loss）**: 所有亏损交易的亏损总和
- **净利润（Net Profit）**: 总盈利 - 总亏损
- **盈亏比（Profit Factor）**: 总盈利 / 总亏损
- **平均盈利（Average Profit）**: 总盈利 / 盈利交易数
- **平均亏损（Average Loss）**: 总亏损 / 亏损交易数
- **期望值（Expectancy）**: 平均盈利 × 胜率 - 平均亏损 × (1 - 胜率)

#### FR-021-2: 胜率指标计算
- **胜率（Win Rate）**: 盈利交易数 / 总交易数 × 100%
- **盈利交易数（Winning Trades）**: 盈亏 > 0 的交易数量
- **亏损交易数（Losing Trades）**: 盈亏 <= 0 的交易数量
- **最大连续盈利（Max Consecutive Wins）**: 最大连续盈利交易次数
- **最大连续亏损（Max Consecutive Losses）**: 最大连续亏损交易次数

#### FR-021-3: 风险指标计算
- **最大回撤（Max Drawdown）**:
  - 定义: 权益曲线从峰值到谷值的最大跌幅
  - 计算: max((peak_equity - trough_equity) / peak_equity)
  - 单位: 百分比
- **最大回撤持续时间（Max Drawdown Duration）**:
  - 从峰值到恢复至峰值的最长时间
  - 单位: 天数
- **夏普比率（Sharpe Ratio）**:
  - 定义: (年化收益率 - 无风险收益率) / 收益率标准差
  - 无风险收益率: 默认 0%（可配置）
  - 计算周期: 基于日收益率
- **索提诺比率（Sortino Ratio）**:
  - 类似夏普比率，但只考虑下行波动
  - 公式: (年化收益率 - 无风险收益率) / 下行标准差
- **卡玛比率（Calmar Ratio）**:
  - 定义: 年化收益率 / 最大回撤
  - 衡量收益与最大回撤的比例

#### FR-021-4: 交易统计
- **总交易次数（Total Trades）**: 已完成的交易数量
- **平均持仓时间（Average Hold Time）**: 所有交易持仓时间的平均值
- **最长持仓时间（Max Hold Time）**: 最长的单笔交易持仓时间
- **最短持仓时间（Min Hold Time）**: 最短的单笔交易持仓时间
- **平均交易间隔（Average Trade Interval）**: 交易之间的平均时间间隔

#### FR-021-5: 收益率统计
- **总收益率（Total Return）**: (期末权益 - 期初资金) / 期初资金 × 100%
- **年化收益率（Annualized Return）**:
  - 公式: ((1 + 总收益率) ^ (365 / 回测天数) - 1) × 100%
- **月度收益率（Monthly Returns）**: 每个月的收益率列表
- **最佳月份（Best Month）**: 收益率最高的月份
- **最差月份（Worst Month）**: 收益率最低的月份

#### FR-021-6: 权益曲线分析
- **权益峰值（Equity Peak）**: 权益曲线的最高点
- **权益谷值（Equity Trough）**: 权益曲线的最低点
- **权益波动率（Equity Volatility）**: 权益变化的标准差
- **回撤曲线（Drawdown Curve）**: 每个时间点的回撤百分比

#### FR-021-7: 性能报告生成
- **生成文本报告**: 格式化的文本报告（用于 CLI 显示）
- **生成 JSON 报告**: 结构化数据（用于程序处理）
- **生成 Markdown 报告**: 用于文档和分享
- **报告内容**:
  - 策略概述（名称、参数、时间范围）
  - 核心指标摘要
  - 详细指标表格
  - 交易列表（可选）
  - 权益曲线数据（可选）

### 非功能需求

#### NFR-021-1: 计算准确性
- 所有指标计算遵循业界标准公式
- 使用 Decimal 类型避免浮点误差
- 边界条件处理正确（0 交易、0 亏损等）

#### NFR-021-2: 性能要求
- 分析 1000 笔交易 < 100ms
- 内存占用 < 20MB

#### NFR-021-3: 代码质量
- 单元测试覆盖率 > 90%
- 所有公共 API 有文档注释
- 零内存泄漏

#### NFR-021-4: 可扩展性
- 支持添加自定义指标
- 支持不同的报告格式

---

## ✅ 验收标准

### AC-021-1: 指标计算准确性
- [ ] 所有指标计算结果准确（手工验证）
- [ ] 与知名回测框架（如 Freqtrade）结果一致（误差 < 1%）
- [ ] 边界条件处理正确（0 交易、全盈利、全亏损）

### AC-021-2: 最大回撤计算
- [ ] 能正确识别权益曲线的峰值和谷值
- [ ] 回撤百分比计算准确
- [ ] 回撤持续时间计算正确

### AC-021-3: 夏普比率计算
- [ ] 日收益率计算准确
- [ ] 标准差计算准确
- [ ] 年化处理正确

### AC-021-4: 报告生成
- [ ] 文本报告格式清晰易读
- [ ] JSON 报告结构合理
- [ ] Markdown 报告可用于文档

### AC-021-5: 单元测试
- [ ] 每个指标都有单元测试
- [ ] 测试覆盖率 > 90%
- [ ] 测试包含边界条件

### AC-021-6: 性能达标
- [ ] 分析速度 < 100ms（1000 交易）
- [ ] 零内存泄漏

---

## 📂 涉及文件

### 新建文件
- `src/backtest/analyzer.zig` - 性能分析器核心（~500 行）
- `src/backtest/metrics.zig` - 指标计算函数（~400 行）
- `src/backtest/report.zig` - 报告生成（~300 行）
- `src/backtest/analyzer_test.zig` - 单元测试（~400 行）
- `docs/features/backtest/metrics.md` - 指标说明文档

### 修改文件
- `src/backtest/mod.zig` - 添加 analyzer 模块导出
- `src/backtest/engine.zig` - 集成性能分析器
- `src/backtest/types.zig` - 添加分析结果类型
- `build.zig` - 添加测试

### 参考文件
- `src/backtest/engine.zig` - 回测引擎
- `docs/v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md` - 设计文档

---

## 🔨 技术实现

### 实现步骤

#### Step 1: 定义性能指标类型（1小时）
```zig
// src/backtest/metrics.zig

/// 性能指标
pub const PerformanceMetrics = struct {
    // 基础盈利指标
    total_profit: Decimal,
    total_loss: Decimal,
    net_profit: Decimal,
    profit_factor: f64,
    average_profit: Decimal,
    average_loss: Decimal,
    expectancy: Decimal,

    // 胜率指标
    total_trades: u32,
    winning_trades: u32,
    losing_trades: u32,
    win_rate: f64,
    max_consecutive_wins: u32,
    max_consecutive_losses: u32,

    // 风险指标
    max_drawdown: f64,
    max_drawdown_duration_days: u32,
    sharpe_ratio: f64,
    sortino_ratio: f64,
    calmar_ratio: f64,

    // 交易统计
    average_hold_time_minutes: f64,
    max_hold_time_minutes: u64,
    min_hold_time_minutes: u64,
    average_trade_interval_minutes: f64,

    // 收益率统计
    total_return: f64,
    annualized_return: f64,
    best_month_return: f64,
    worst_month_return: f64,

    // 权益曲线
    equity_peak: Decimal,
    equity_trough: Decimal,
    equity_volatility: f64,

    // 回测配置
    initial_capital: Decimal,
    final_equity: Decimal,
    total_commission: Decimal,
    backtest_days: u32,
};

/// 月度收益
pub const MonthlyReturn = struct {
    year: u32,
    month: u32,
    return_pct: f64,
};

/// 回撤点
pub const DrawdownPoint = struct {
    timestamp: Timestamp,
    drawdown_pct: f64,
};
```

#### Step 2: 实现基础指标计算（2小时）
```zig
// src/backtest/analyzer.zig

pub const PerformanceAnalyzer = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    pub fn init(allocator: std.mem.Allocator) PerformanceAnalyzer {
        return .{
            .allocator = allocator,
            .logger = Logger.init("PerformanceAnalyzer"),
        };
    }

    /// 分析回测结果
    pub fn analyze(
        self: *PerformanceAnalyzer,
        result: BacktestResult,
    ) !PerformanceMetrics {
        self.logger.info("Analyzing {} trades", .{result.trades.len});

        // 计算基础盈利指标
        const profit_metrics = try self.calculateProfitMetrics(result.trades);

        // 计算胜率指标
        const win_metrics = try self.calculateWinMetrics(result.trades);

        // 计算风险指标
        const risk_metrics = try self.calculateRiskMetrics(
            result.equity_curve,
            result.config.initial_capital,
        );

        // 计算交易统计
        const trade_stats = try self.calculateTradeStats(result.trades);

        // 计算收益率
        const return_metrics = try self.calculateReturnMetrics(
            result.equity_curve,
            result.config.initial_capital,
        );

        return PerformanceMetrics{
            .total_profit = profit_metrics.total_profit,
            .total_loss = profit_metrics.total_loss,
            .net_profit = profit_metrics.net_profit,
            .profit_factor = profit_metrics.profit_factor,
            .average_profit = profit_metrics.average_profit,
            .average_loss = profit_metrics.average_loss,
            .expectancy = profit_metrics.expectancy,

            .total_trades = win_metrics.total_trades,
            .winning_trades = win_metrics.winning_trades,
            .losing_trades = win_metrics.losing_trades,
            .win_rate = win_metrics.win_rate,
            .max_consecutive_wins = win_metrics.max_consecutive_wins,
            .max_consecutive_losses = win_metrics.max_consecutive_losses,

            .max_drawdown = risk_metrics.max_drawdown,
            .max_drawdown_duration_days = risk_metrics.max_drawdown_duration_days,
            .sharpe_ratio = risk_metrics.sharpe_ratio,
            .sortino_ratio = risk_metrics.sortino_ratio,
            .calmar_ratio = risk_metrics.calmar_ratio,

            .average_hold_time_minutes = trade_stats.average_hold_time,
            .max_hold_time_minutes = trade_stats.max_hold_time,
            .min_hold_time_minutes = trade_stats.min_hold_time,
            .average_trade_interval_minutes = trade_stats.average_interval,

            .total_return = return_metrics.total_return,
            .annualized_return = return_metrics.annualized_return,
            .best_month_return = return_metrics.best_month,
            .worst_month_return = return_metrics.worst_month,

            .equity_peak = return_metrics.equity_peak,
            .equity_trough = return_metrics.equity_trough,
            .equity_volatility = return_metrics.equity_volatility,

            .initial_capital = result.config.initial_capital,
            .final_equity = result.equity_curve[result.equity_curve.len - 1].equity,
            .total_commission = result.calculateTotalCommission(),
            .backtest_days = @intCast(result.calculateDays()),
        };
    }

    fn calculateProfitMetrics(
        self: *PerformanceAnalyzer,
        trades: []Trade,
    ) !struct {
        total_profit: Decimal,
        total_loss: Decimal,
        net_profit: Decimal,
        profit_factor: f64,
        average_profit: Decimal,
        average_loss: Decimal,
        expectancy: Decimal,
    } {
        var total_profit = Decimal.ZERO;
        var total_loss = Decimal.ZERO;
        var profit_count: u32 = 0;
        var loss_count: u32 = 0;

        for (trades) |trade| {
            if (trade.pnl.isPositive()) {
                total_profit = try total_profit.add(trade.pnl);
                profit_count += 1;
            } else {
                total_loss = try total_loss.add(try trade.pnl.abs());
                loss_count += 1;
            }
        }

        const net_profit = try total_profit.sub(total_loss);

        const profit_factor = if (!total_loss.isZero())
            try total_profit.div(total_loss).toFloat()
        else
            0.0;

        const average_profit = if (profit_count > 0)
            try total_profit.div(try Decimal.fromInt(profit_count))
        else
            Decimal.ZERO;

        const average_loss = if (loss_count > 0)
            try total_loss.div(try Decimal.fromInt(loss_count))
        else
            Decimal.ZERO;

        // 期望值 = 平均盈利 × 胜率 - 平均亏损 × 败率
        const win_rate = if (trades.len > 0)
            @as(f64, @floatFromInt(profit_count)) / @as(f64, @floatFromInt(trades.len))
        else
            0.0;
        const loss_rate = 1.0 - win_rate;

        const expectancy = try average_profit.mul(try Decimal.fromFloat(win_rate))
            .sub(try average_loss.mul(try Decimal.fromFloat(loss_rate)));

        return .{
            .total_profit = total_profit,
            .total_loss = total_loss,
            .net_profit = net_profit,
            .profit_factor = profit_factor,
            .average_profit = average_profit,
            .average_loss = average_loss,
            .expectancy = expectancy,
        };
    }

    fn calculateWinMetrics(
        self: *PerformanceAnalyzer,
        trades: []Trade,
    ) !struct {
        total_trades: u32,
        winning_trades: u32,
        losing_trades: u32,
        win_rate: f64,
        max_consecutive_wins: u32,
        max_consecutive_losses: u32,
    } {
        var winning: u32 = 0;
        var losing: u32 = 0;
        var current_wins: u32 = 0;
        var current_losses: u32 = 0;
        var max_wins: u32 = 0;
        var max_losses: u32 = 0;

        for (trades) |trade| {
            if (trade.pnl.isPositive()) {
                winning += 1;
                current_wins += 1;
                current_losses = 0;
                max_wins = @max(max_wins, current_wins);
            } else {
                losing += 1;
                current_losses += 1;
                current_wins = 0;
                max_losses = @max(max_losses, current_losses);
            }
        }

        const win_rate = if (trades.len > 0)
            @as(f64, @floatFromInt(winning)) / @as(f64, @floatFromInt(trades.len))
        else
            0.0;

        return .{
            .total_trades = @intCast(trades.len),
            .winning_trades = winning,
            .losing_trades = losing,
            .win_rate = win_rate,
            .max_consecutive_wins = max_wins,
            .max_consecutive_losses = max_losses,
        };
    }
};
```

#### Step 3: 实现风险指标计算（2.5小时）
```zig
fn calculateRiskMetrics(
    self: *PerformanceAnalyzer,
    equity_curve: []BacktestResult.EquitySnapshot,
    initial_capital: Decimal,
) !struct {
    max_drawdown: f64,
    max_drawdown_duration_days: u32,
    sharpe_ratio: f64,
    sortino_ratio: f64,
    calmar_ratio: f64,
} {
    // 计算最大回撤
    const dd = try self.calculateMaxDrawdown(equity_curve);

    // 计算夏普比率
    const sharpe = try self.calculateSharpeRatio(equity_curve, initial_capital);

    // 计算索提诺比率
    const sortino = try self.calculateSortinoRatio(equity_curve, initial_capital);

    // 计算卡玛比率
    const annual_return = try self.calculateAnnualizedReturn(equity_curve, initial_capital);
    const calmar = if (dd.max_drawdown > 0.0)
        annual_return / dd.max_drawdown
    else
        0.0;

    return .{
        .max_drawdown = dd.max_drawdown,
        .max_drawdown_duration_days = dd.duration_days,
        .sharpe_ratio = sharpe,
        .sortino_ratio = sortino,
        .calmar_ratio = calmar,
    };
}

fn calculateMaxDrawdown(
    self: *PerformanceAnalyzer,
    equity_curve: []BacktestResult.EquitySnapshot,
) !struct {
    max_drawdown: f64,
    duration_days: u32,
} {
    var peak = equity_curve[0].equity;
    var max_dd: f64 = 0.0;
    var peak_time: Timestamp = equity_curve[0].timestamp;
    var max_dd_duration: u64 = 0;

    for (equity_curve) |snapshot| {
        // 更新峰值
        if (snapshot.equity.gt(peak)) {
            peak = snapshot.equity;
            peak_time = snapshot.timestamp;
        }

        // 计算当前回撤
        if (snapshot.equity.lt(peak)) {
            const dd_amount = try peak.sub(snapshot.equity);
            const dd_pct = try dd_amount.div(peak).toFloat();

            if (dd_pct > max_dd) {
                max_dd = dd_pct;
            }

            // 计算回撤持续时间
            const duration = snapshot.timestamp - peak_time;
            max_dd_duration = @max(max_dd_duration, duration);
        }
    }

    const duration_days: u32 = @intCast(max_dd_duration / (24 * 60 * 60 * 1000));

    return .{
        .max_drawdown = max_dd,
        .duration_days = duration_days,
    };
}

fn calculateSharpeRatio(
    self: *PerformanceAnalyzer,
    equity_curve: []BacktestResult.EquitySnapshot,
    initial_capital: Decimal,
) !f64 {
    // 计算日收益率
    var daily_returns = try self.allocator.alloc(f64, equity_curve.len - 1);
    defer self.allocator.free(daily_returns);

    for (1..equity_curve.len) |i| {
        const prev_equity = equity_curve[i - 1].equity;
        const curr_equity = equity_curve[i].equity;
        const ret = try curr_equity.sub(prev_equity).div(prev_equity);
        daily_returns[i - 1] = try ret.toFloat();
    }

    // 计算平均收益率和标准差
    const mean_return = self.calculateMean(daily_returns);
    const std_dev = self.calculateStdDev(daily_returns, mean_return);

    if (std_dev == 0.0) return 0.0;

    // 年化夏普比率（假设 365 个交易日）
    const annual_return = mean_return * 365.0;
    const annual_volatility = std_dev * @sqrt(365.0);

    const risk_free_rate = 0.0;  // 无风险收益率，可配置
    return (annual_return - risk_free_rate) / annual_volatility;
}

fn calculateSortinoRatio(
    self: *PerformanceAnalyzer,
    equity_curve: []BacktestResult.EquitySnapshot,
    initial_capital: Decimal,
) !f64 {
    // 类似夏普比率，但只考虑下行波动
    var daily_returns = try self.allocator.alloc(f64, equity_curve.len - 1);
    defer self.allocator.free(daily_returns);

    for (1..equity_curve.len) |i| {
        const prev_equity = equity_curve[i - 1].equity;
        const curr_equity = equity_curve[i].equity;
        const ret = try curr_equity.sub(prev_equity).div(prev_equity);
        daily_returns[i - 1] = try ret.toFloat();
    }

    const mean_return = self.calculateMean(daily_returns);

    // 计算下行标准差（只考虑负收益）
    var downside_sum: f64 = 0.0;
    var downside_count: usize = 0;
    for (daily_returns) |ret| {
        if (ret < 0.0) {
            downside_sum += ret * ret;
            downside_count += 1;
        }
    }

    const downside_std = if (downside_count > 0)
        @sqrt(downside_sum / @as(f64, @floatFromInt(downside_count)))
    else
        0.0;

    if (downside_std == 0.0) return 0.0;

    const annual_return = mean_return * 365.0;
    const annual_downside_vol = downside_std * @sqrt(365.0);

    return annual_return / annual_downside_vol;
}

fn calculateMean(self: *PerformanceAnalyzer, values: []f64) f64 {
    if (values.len == 0) return 0.0;
    var sum: f64 = 0.0;
    for (values) |v| {
        sum += v;
    }
    return sum / @as(f64, @floatFromInt(values.len));
}

fn calculateStdDev(self: *PerformanceAnalyzer, values: []f64, mean: f64) f64 {
    if (values.len <= 1) return 0.0;
    var sum_sq_diff: f64 = 0.0;
    for (values) |v| {
        const diff = v - mean;
        sum_sq_diff += diff * diff;
    }
    return @sqrt(sum_sq_diff / @as(f64, @floatFromInt(values.len - 1)));
}
```

#### Step 4: 实现报告生成（1.5小时）
```zig
// src/backtest/report.zig

pub const ReportGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ReportGenerator {
        return .{ .allocator = allocator };
    }

    /// 生成文本报告
    pub fn generateTextReport(
        self: *ReportGenerator,
        metrics: PerformanceMetrics,
        strategy_name: []const u8,
    ) ![]const u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("╔════════════════════════════════════════════════════════╗\n", .{});
        try writer.print("║  Performance Report: {s:<38}║\n", .{strategy_name});
        try writer.print("╚════════════════════════════════════════════════════════╝\n\n", .{});

        try writer.print("📊 Profit Metrics\n", .{});
        try writer.print("  Total Profit:        {}\n", .{metrics.total_profit});
        try writer.print("  Total Loss:          {}\n", .{metrics.total_loss});
        try writer.print("  Net Profit:          {}\n", .{metrics.net_profit});
        try writer.print("  Profit Factor:       {d:.2}\n\n", .{metrics.profit_factor});

        try writer.print("🎯 Win Rate\n", .{});
        try writer.print("  Total Trades:        {}\n", .{metrics.total_trades});
        try writer.print("  Winning Trades:      {}\n", .{metrics.winning_trades});
        try writer.print("  Losing Trades:       {}\n", .{metrics.losing_trades});
        try writer.print("  Win Rate:            {d:.1}%\n\n", .{metrics.win_rate * 100.0});

        try writer.print("⚠️  Risk Metrics\n", .{});
        try writer.print("  Max Drawdown:        {d:.2}%\n", .{metrics.max_drawdown * 100.0});
        try writer.print("  Sharpe Ratio:        {d:.2}\n", .{metrics.sharpe_ratio});
        try writer.print("  Sortino Ratio:       {d:.2}\n", .{metrics.sortino_ratio});
        try writer.print("  Calmar Ratio:        {d:.2}\n\n", .{metrics.calmar_ratio});

        try writer.print("📈 Returns\n", .{});
        try writer.print("  Total Return:        {d:.2}%\n", .{metrics.total_return * 100.0});
        try writer.print("  Annualized Return:   {d:.2}%\n\n", .{metrics.annualized_return * 100.0});

        return try buf.toOwnedSlice();
    }

    /// 生成 JSON 报告
    pub fn generateJsonReport(
        self: *ReportGenerator,
        metrics: PerformanceMetrics,
        strategy_name: []const u8,
    ) ![]const u8 {
        // 使用 std.json 序列化
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try std.json.stringify(metrics, .{}, writer);
        return try buf.toOwnedSlice();
    }

    /// 生成 Markdown 报告
    pub fn generateMarkdownReport(
        self: *ReportGenerator,
        metrics: PerformanceMetrics,
        strategy_name: []const u8,
    ) ![]const u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("# Performance Report: {s}\n\n", .{strategy_name});
        try writer.print("## Summary\n\n", .{});
        try writer.print("| Metric | Value |\n", .{});
        try writer.print("|--------|-------|\n", .{});
        try writer.print("| Total Return | {d:.2}% |\n", .{metrics.total_return * 100.0});
        try writer.print("| Win Rate | {d:.1}% |\n", .{metrics.win_rate * 100.0});
        try writer.print("| Sharpe Ratio | {d:.2} |\n", .{metrics.sharpe_ratio});
        try writer.print("| Max Drawdown | {d:.2}% |\n\n", .{metrics.max_drawdown * 100.0});

        return try buf.toOwnedSlice();
    }
};
```

#### Step 5: 编写单元测试（2小时）
```zig
// src/backtest/analyzer_test.zig

test "PerformanceAnalyzer: profit metrics" {
    const allocator = std.testing.allocator;

    var analyzer = PerformanceAnalyzer.init(allocator);

    // 创建测试交易数据
    var trades = [_]Trade{
        Trade{ .pnl = try Decimal.fromInt(100), ... },
        Trade{ .pnl = try Decimal.fromInt(-50), ... },
        Trade{ .pnl = try Decimal.fromInt(200), ... },
    };

    const profit_metrics = try analyzer.calculateProfitMetrics(&trades);

    try std.testing.expectEqual(try Decimal.fromInt(300), profit_metrics.total_profit);
    try std.testing.expectEqual(try Decimal.fromInt(50), profit_metrics.total_loss);
    try std.testing.expectEqual(6.0, profit_metrics.profit_factor);
}

test "PerformanceAnalyzer: max drawdown" {
    // 测试最大回撤计算...
}

test "PerformanceAnalyzer: sharpe ratio" {
    // 测试夏普比率计算...
}
```

### 技术决策

#### 决策 1: 使用日收益率计算风险指标
- **选择**: 基于日收益率计算夏普/索提诺比率
- **理由**: 业界标准做法
- **权衡**: 需要足够的数据点（建议 > 30 天）

#### 决策 2: 无风险收益率默认为 0
- **选择**: 默认 0%，可配置
- **理由**: 简化计算，加密货币无明确无风险收益
- **权衡**: 传统金融可能需要设置（如 3%）

---

## 🧪 测试计划

### 单元测试
- UT-021-1: 盈利指标计算
- UT-021-2: 胜率指标计算
- UT-021-3: 最大回撤计算
- UT-021-4: 夏普比率计算
- UT-021-5: 报告生成

---

## 📊 成功指标

- ✅ 所有指标计算准确
- ✅ 测试覆盖率 > 90%
- ✅ 报告格式清晰

---

## 📖 参考资料

- [Freqtrade Metrics](https://www.freqtrade.io/en/stable/backtesting/)
- [Sharpe Ratio](https://www.investopedia.com/terms/s/sharperatio.asp)
- [Maximum Drawdown](https://www.investopedia.com/terms/m/maximum-drawdown-mdd.asp)

---

**创建时间**: 2025-12-25
**预计开始**: Week 2 Day 6
**预计完成**: Week 2 Day 6

---

Generated with Claude Code
