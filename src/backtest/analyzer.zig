//! Backtest Engine - Performance Analyzer
//!
//! Calculates comprehensive performance metrics from backtest results.

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Logger = @import("../core/logger.zig").Logger;
const BacktestResult = @import("types.zig").BacktestResult;
const Trade = @import("types.zig").Trade;
const EquitySnapshot = @import("types.zig").EquitySnapshot;

// ============================================================================
// Performance Metrics
// ============================================================================

/// Comprehensive performance analysis metrics
pub const PerformanceMetrics = struct {
    // Profit metrics
    total_profit: Decimal,
    total_loss: Decimal,
    net_profit: Decimal,
    profit_factor: f64,
    average_profit: Decimal,
    average_loss: Decimal,
    expectancy: Decimal,

    // Win rate metrics
    total_trades: u32,
    winning_trades: u32,
    losing_trades: u32,
    win_rate: f64,
    max_consecutive_wins: u32,
    max_consecutive_losses: u32,

    // Risk metrics
    max_drawdown: f64,
    max_drawdown_duration_days: u32,
    sharpe_ratio: f64,

    // Trade statistics
    average_hold_time_minutes: f64,
    max_hold_time_minutes: u64,
    min_hold_time_minutes: u64,

    // Return metrics
    total_return: f64,
    annualized_return: f64,

    // Equity curve
    equity_peak: Decimal,
    equity_trough: Decimal,

    // Configuration
    initial_capital: Decimal,
    final_equity: Decimal,
    total_commission: Decimal,
    backtest_days: u32,
};

// ============================================================================
// Performance Analyzer
// ============================================================================

/// Analyzes backtest results and calculates performance metrics
pub const PerformanceAnalyzer = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    pub fn init(allocator: std.mem.Allocator, logger: Logger) PerformanceAnalyzer {
        return .{
            .allocator = allocator,
            .logger = logger,
        };
    }

    /// Analyze backtest result and calculate all metrics
    pub fn analyze(
        self: *PerformanceAnalyzer,
        result: BacktestResult,
    ) !PerformanceMetrics {
        self.logger.info("Analyzing {} trades", .{result.trades.len});

        // Calculate each category of metrics
        const profit_metrics = try self.calculateProfitMetrics(result.trades);
        const win_metrics = try self.calculateWinMetrics(result.trades);
        const risk_metrics = try self.calculateRiskMetrics(result.equity_curve, result.config.initial_capital);
        const trade_stats = try self.calculateTradeStats(result.trades);
        const return_metrics = try self.calculateReturnMetrics(result.equity_curve, result.config.initial_capital);

        const final_equity = if (result.equity_curve.len > 0)
            result.equity_curve[result.equity_curve.len - 1].equity
        else
            result.config.initial_capital;

        return PerformanceMetrics{
            // Profit
            .total_profit = profit_metrics.total_profit,
            .total_loss = profit_metrics.total_loss,
            .net_profit = profit_metrics.net_profit,
            .profit_factor = profit_metrics.profit_factor,
            .average_profit = profit_metrics.average_profit,
            .average_loss = profit_metrics.average_loss,
            .expectancy = profit_metrics.expectancy,

            // Win rate
            .total_trades = win_metrics.total_trades,
            .winning_trades = win_metrics.winning_trades,
            .losing_trades = win_metrics.losing_trades,
            .win_rate = win_metrics.win_rate,
            .max_consecutive_wins = win_metrics.max_consecutive_wins,
            .max_consecutive_losses = win_metrics.max_consecutive_losses,

            // Risk
            .max_drawdown = risk_metrics.max_drawdown,
            .max_drawdown_duration_days = risk_metrics.max_drawdown_duration_days,
            .sharpe_ratio = risk_metrics.sharpe_ratio,

            // Trade stats
            .average_hold_time_minutes = trade_stats.average_hold_time,
            .max_hold_time_minutes = trade_stats.max_hold_time,
            .min_hold_time_minutes = trade_stats.min_hold_time,

            // Returns
            .total_return = return_metrics.total_return,
            .annualized_return = return_metrics.annualized_return,

            // Equity
            .equity_peak = risk_metrics.peak,
            .equity_trough = risk_metrics.trough,

            // Config
            .initial_capital = result.config.initial_capital,
            .final_equity = final_equity,
            .total_commission = result.calculateTotalCommission(),
            .backtest_days = result.calculateDays(),
        };
    }

    // Private helper methods

    fn calculateProfitMetrics(
        _: *PerformanceAnalyzer,
        trades: []const Trade,
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
        var winning_count: u32 = 0;
        var losing_count: u32 = 0;

        for (trades) |trade| {
            if (trade.isWinning()) {
                total_profit = try total_profit.add(trade.pnl);
                winning_count += 1;
            } else if (trade.isLosing()) {
                total_loss = total_loss.add(try trade.pnl.abs());
                losing_count += 1;
            }
        }

        const net_profit = try total_profit.sub(total_loss);

        const profit_factor = if (!total_loss.isZero())
            (try total_profit.div(total_loss)).toFloat()
        else if (total_profit.isPositive())
            999.0
        else
            0.0;

        const avg_profit = if (winning_count > 0)
            try total_profit.div(Decimal.fromInt(winning_count))
        else
            Decimal.ZERO;

        const avg_loss = if (losing_count > 0)
            try total_loss.div(Decimal.fromInt(losing_count))
        else
            Decimal.ZERO;

        const win_rate = if (trades.len > 0)
            @as(f64, @floatFromInt(winning_count)) / @as(f64, @floatFromInt(trades.len))
        else
            0.0;

        // Expectancy = avg_profit * win_rate - avg_loss * (1 - win_rate)
        const expectancy_win = avg_profit.mul(Decimal.fromFloat(win_rate));
        const expectancy_loss = avg_loss.mul(Decimal.fromFloat(1.0 - win_rate));
        const expectancy = try expectancy_win.sub(expectancy_loss);

        return .{
            .total_profit = total_profit,
            .total_loss = total_loss,
            .net_profit = net_profit,
            .profit_factor = profit_factor,
            .average_profit = avg_profit,
            .average_loss = avg_loss,
            .expectancy = expectancy,
        };
    }

    fn calculateWinMetrics(
        _: *PerformanceAnalyzer,
        trades: []const Trade,
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
        var current_win_streak: u32 = 0;
        var current_loss_streak: u32 = 0;
        var max_win_streak: u32 = 0;
        var max_loss_streak: u32 = 0;

        for (trades) |trade| {
            if (trade.isWinning()) {
                winning += 1;
                current_win_streak += 1;
                current_loss_streak = 0;
                max_win_streak = @max(max_win_streak, current_win_streak);
            } else if (trade.isLosing()) {
                losing += 1;
                current_loss_streak += 1;
                current_win_streak = 0;
                max_loss_streak = @max(max_loss_streak, current_loss_streak);
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
            .max_consecutive_wins = max_win_streak,
            .max_consecutive_losses = max_loss_streak,
        };
    }

    fn calculateRiskMetrics(
        self: *PerformanceAnalyzer,
        equity_curve: []const EquitySnapshot,
        initial_capital: Decimal,
    ) !struct {
        max_drawdown: f64,
        max_drawdown_duration_days: u32,
        sharpe_ratio: f64,
        peak: Decimal,
        trough: Decimal,
    } {
        if (equity_curve.len == 0) {
            return .{
                .max_drawdown = 0.0,
                .max_drawdown_duration_days = 0,
                .sharpe_ratio = 0.0,
                .peak = initial_capital,
                .trough = initial_capital,
            };
        }

        var peak = equity_curve[0].equity;
        var trough = equity_curve[0].equity;
        var max_dd: f64 = 0.0;
        var peak_time = equity_curve[0].timestamp;
        var max_dd_duration: i64 = 0;

        for (equity_curve) |snapshot| {
            // Update peak
            if (snapshot.equity.gt_internal(peak)) {
                peak = snapshot.equity;
                peak_time = snapshot.timestamp;
            }

            // Update trough
            if (snapshot.equity.lt_internal(trough)) {
                trough = snapshot.equity;
            }

            // Calculate current drawdown
            if (snapshot.equity.lt_internal(peak)) {
                const dd_amount = try peak.sub(snapshot.equity);
                const dd_pct = (try dd_amount.div(peak)).toFloat();
                max_dd = @max(max_dd, dd_pct);

                const duration = snapshot.timestamp.millis - peak_time.millis;
                max_dd_duration = @max(max_dd_duration, duration);
            }
        }

        const dd_duration_days: u32 = @intCast(@divTrunc(max_dd_duration, 24 * 60 * 60 * 1000));

        // Calculate Sharpe ratio (simplified)
        const sharpe = try self.calculateSharpeRatio(equity_curve, initial_capital);

        return .{
            .max_drawdown = max_dd,
            .max_drawdown_duration_days = dd_duration_days,
            .sharpe_ratio = sharpe,
            .peak = peak,
            .trough = trough,
        };
    }

    fn calculateSharpeRatio(
        self: *PerformanceAnalyzer,
        equity_curve: []const EquitySnapshot,
        _: Decimal,
    ) !f64 {
        if (equity_curve.len < 2) return 0.0;

        // Calculate daily returns
        var returns = try self.allocator.alloc(f64, equity_curve.len - 1);
        defer self.allocator.free(returns);

        for (1..equity_curve.len) |i| {
            const prev_equity = equity_curve[i - 1].equity;
            const curr_equity = equity_curve[i].equity;

            if (!prev_equity.isZero()) {
                const ret = try (try curr_equity.sub(prev_equity)).div(prev_equity);
                returns[i - 1] = ret.toFloat();
            } else {
                returns[i - 1] = 0.0;
            }
        }

        // Calculate mean and std dev
        const mean = self.calculateMean(returns);
        const std_dev = self.calculateStdDev(returns, mean);

        if (std_dev == 0.0) return 0.0;

        // Annualize (assume 252 trading days)
        const annual_return = mean * 252.0;
        const annual_volatility = std_dev * @sqrt(252.0);

        // Sharpe ratio (risk-free rate = 0)
        return annual_return / annual_volatility;
    }

    fn calculateMean(_: *PerformanceAnalyzer, values: []const f64) f64 {
        if (values.len == 0) return 0.0;
        var sum: f64 = 0.0;
        for (values) |v| sum += v;
        return sum / @as(f64, @floatFromInt(values.len));
    }

    fn calculateStdDev(_: *PerformanceAnalyzer, values: []const f64, mean: f64) f64 {
        if (values.len <= 1) return 0.0;
        var sum_sq_diff: f64 = 0.0;
        for (values) |v| {
            const diff = v - mean;
            sum_sq_diff += diff * diff;
        }
        return @sqrt(sum_sq_diff / @as(f64, @floatFromInt(values.len - 1)));
    }

    fn calculateTradeStats(
        _: *PerformanceAnalyzer,
        trades: []const Trade,
    ) !struct {
        average_hold_time: f64,
        max_hold_time: u64,
        min_hold_time: u64,
    } {
        if (trades.len == 0) {
            return .{
                .average_hold_time = 0.0,
                .max_hold_time = 0,
                .min_hold_time = 0,
            };
        }

        var total_duration: u64 = 0;
        var max_duration: u64 = 0;
        var min_duration: u64 = std.math.maxInt(u64);

        for (trades) |trade| {
            total_duration += trade.duration_minutes;
            max_duration = @max(max_duration, trade.duration_minutes);
            min_duration = @min(min_duration, trade.duration_minutes);
        }

        const avg_duration = @as(f64, @floatFromInt(total_duration)) /
            @as(f64, @floatFromInt(trades.len));

        return .{
            .average_hold_time = avg_duration,
            .max_hold_time = max_duration,
            .min_hold_time = min_duration,
        };
    }

    fn calculateReturnMetrics(
        _: *PerformanceAnalyzer,
        equity_curve: []const EquitySnapshot,
        initial_capital: Decimal,
    ) !struct {
        total_return: f64,
        annualized_return: f64,
    } {
        if (equity_curve.len == 0) {
            return .{
                .total_return = 0.0,
                .annualized_return = 0.0,
            };
        }

        const final_equity = equity_curve[equity_curve.len - 1].equity;
        const net_profit = try final_equity.sub(initial_capital);
        const total_return = (try net_profit.div(initial_capital)).toFloat();

        // Calculate time period in years
        const first_time = equity_curve[0].timestamp.millis;
        const last_time = equity_curve[equity_curve.len - 1].timestamp.millis;
        const duration_days = @as(f64, @floatFromInt(last_time - first_time)) / (24.0 * 60.0 * 60.0 * 1000.0);
        const duration_years = duration_days / 365.0;

        // Annualized return = total_return / years
        const annualized_return = if (duration_years > 0.0)
            total_return / duration_years
        else
            0.0;

        return .{
            .total_return = total_return,
            .annualized_return = annualized_return,
        };
    }
};
