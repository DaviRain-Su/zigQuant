//! RiskMetricsMonitor - Risk Metrics Monitoring (Story 043)
//!
//! Real-time calculation and monitoring of key risk metrics:
//! - VaR (Value at Risk): Potential maximum loss
//! - Maximum Drawdown: Peak to trough decline
//! - Sharpe Ratio: Risk-adjusted return
//! - Sortino Ratio: Downside risk-adjusted return
//! - Calmar Ratio: Return to max drawdown ratio

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;

/// Risk Metrics Monitor
pub const RiskMetricsMonitor = struct {
    allocator: Allocator,
    config: RiskMetricsConfig,

    // Equity history
    equity_history: std.ArrayListUnmanaged(EquitySnapshot),

    // Returns history
    returns_history: std.ArrayListUnmanaged(f64),

    const Self = @This();

    pub fn init(allocator: Allocator, config: RiskMetricsConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .equity_history = .{},
            .returns_history = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.equity_history.deinit(self.allocator);
        self.returns_history.deinit(self.allocator);
    }

    /// Record equity snapshot
    pub fn recordEquity(self: *Self, snapshot: EquitySnapshot) !void {
        // Calculate return rate
        if (self.equity_history.items.len > 0) {
            const prev = self.equity_history.items[self.equity_history.items.len - 1];
            const prev_f = prev.equity.toFloat();
            if (prev_f > 0) {
                const curr_f = snapshot.equity.toFloat();
                const return_pct = (curr_f - prev_f) / prev_f;
                try self.returns_history.append(self.allocator, return_pct);
            }
        }

        try self.equity_history.append(self.allocator, snapshot);

        // Limit history size (keep last 1000)
        if (self.equity_history.items.len > 1000) {
            _ = self.equity_history.orderedRemove(0);
        }
        if (self.returns_history.items.len > 1000) {
            _ = self.returns_history.orderedRemove(0);
        }
    }

    /// Calculate VaR (Value at Risk)
    ///
    /// Uses historical simulation method
    /// VaR represents the maximum potential loss at given confidence level
    pub fn calculateVaR(self: *Self, confidence: f64) VaRResult {
        if (self.returns_history.items.len < 30) {
            return VaRResult{
                .var_amount = Decimal.ZERO,
                .var_percentage = 0,
                .error_message = "Insufficient data (need 30+ observations)",
            };
        }

        // Copy and sort returns
        const sorted_returns = self.allocator.alloc(f64, self.returns_history.items.len) catch {
            return VaRResult{ .error_message = "Allocation failed" };
        };
        defer self.allocator.free(sorted_returns);

        @memcpy(sorted_returns, self.returns_history.items);
        std.mem.sort(f64, sorted_returns, {}, std.sort.asc(f64));

        // Calculate percentile index
        const index = @as(usize, @intFromFloat((1.0 - confidence) * @as(f64, @floatFromInt(sorted_returns.len))));
        const var_pct = sorted_returns[index];

        // Convert to amount
        const current_equity = self.getLatestEquity();
        const var_amount = current_equity.mul(Decimal.fromFloat(-var_pct));

        return VaRResult{
            .var_amount = var_amount,
            .var_percentage = -var_pct,
            .confidence = confidence,
            .observations = sorted_returns.len,
            .error_message = null,
        };
    }

    /// Calculate CVaR (Conditional VaR / Expected Shortfall)
    ///
    /// CVaR is the average loss beyond VaR threshold
    /// Better captures tail risk than VaR
    pub fn calculateCVaR(self: *Self, confidence: f64) CVaRResult {
        if (self.returns_history.items.len < 30) {
            return CVaRResult{ .error_message = "Insufficient data" };
        }

        const sorted_returns = self.allocator.alloc(f64, self.returns_history.items.len) catch {
            return CVaRResult{ .error_message = "Allocation failed" };
        };
        defer self.allocator.free(sorted_returns);

        @memcpy(sorted_returns, self.returns_history.items);
        std.mem.sort(f64, sorted_returns, {}, std.sort.asc(f64));

        // VaR percentile
        const var_index = @as(usize, @intFromFloat((1.0 - confidence) * @as(f64, @floatFromInt(sorted_returns.len))));

        // CVaR = average of values below VaR
        var sum: f64 = 0;
        if (var_index > 0) {
            for (sorted_returns[0..var_index]) |r| {
                sum += r;
            }
        }
        const cvar_pct = if (var_index > 0) sum / @as(f64, @floatFromInt(var_index)) else 0;

        const current_equity = self.getLatestEquity();
        const cvar_amount = current_equity.mul(Decimal.fromFloat(-cvar_pct));

        return CVaRResult{
            .cvar_amount = cvar_amount,
            .cvar_percentage = -cvar_pct,
            .confidence = confidence,
            .error_message = null,
        };
    }

    /// Calculate Maximum Drawdown
    ///
    /// Maximum decline from peak to trough
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
            // Update peak
            if (snapshot.equity.cmp(max_equity) == .gt) {
                max_equity = snapshot.equity;
                current_peak_index = i;
            }

            // Calculate current drawdown
            const max_f = max_equity.toFloat();
            if (max_f > 0) {
                const drawdown = max_equity.sub(snapshot.equity);
                const drawdown_f = drawdown.toFloat();
                const drawdown_pct = drawdown_f / max_f;

                // Update max drawdown
                if (drawdown_pct > max_drawdown_pct) {
                    max_drawdown = drawdown;
                    max_drawdown_pct = drawdown_pct;
                    peak_index = current_peak_index;
                    trough_index = i;
                }
            }
        }

        // Calculate current drawdown
        const current_equity = self.equity_history.items[self.equity_history.items.len - 1].equity;
        const current_drawdown = max_equity.sub(current_equity);
        const max_f_2 = max_equity.toFloat();
        const current_dd_f = current_drawdown.toFloat();
        const current_drawdown_pct = if (max_f_2 > 0) current_dd_f / max_f_2 else 0;

        return DrawdownResult{
            .max_drawdown = max_drawdown,
            .max_drawdown_pct = max_drawdown_pct,
            .peak_equity = max_equity,
            .peak_index = peak_index,
            .trough_index = trough_index,
            .current_drawdown = current_drawdown,
            .current_drawdown_pct = current_drawdown_pct,
            .is_recovering = current_drawdown_pct < max_drawdown_pct,
            .error_message = null,
        };
    }

    /// Calculate Sharpe Ratio
    ///
    /// Sharpe = (R - Rf) / sigma
    /// R = average return
    /// Rf = risk-free rate
    /// sigma = standard deviation
    pub fn calculateSharpeRatio(self: *Self, window: ?usize) SharpeResult {
        const w = window orelse self.config.sharpe_window;

        if (self.returns_history.items.len < w) {
            return SharpeResult{ .error_message = "Insufficient data" };
        }

        // Use most recent window data
        const start = self.returns_history.items.len - w;
        const returns = self.returns_history.items[start..];

        // Calculate mean return
        var sum: f64 = 0;
        for (returns) |r| {
            sum += r;
        }
        const mean = sum / @as(f64, @floatFromInt(returns.len));

        // Calculate standard deviation
        var variance: f64 = 0;
        for (returns) |r| {
            const diff = r - mean;
            variance += diff * diff;
        }
        variance /= @as(f64, @floatFromInt(returns.len - 1));
        const std_dev = @sqrt(variance);

        // Annualize
        const annual_factor = @sqrt(self.config.volatility_annual_factor);
        const annual_return = mean * self.config.volatility_annual_factor;
        const annual_volatility = std_dev * annual_factor;

        // Sharpe ratio
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
            .error_message = null,
        };
    }

    /// Calculate Sortino Ratio
    ///
    /// Sortino = (R - Rf) / sigma_d
    /// sigma_d = downside standard deviation (only negative returns)
    ///
    /// Better suited for asymmetric return distributions
    pub fn calculateSortinoRatio(self: *Self, window: ?usize) SortinoResult {
        const w = window orelse self.config.sharpe_window;

        if (self.returns_history.items.len < w) {
            return SortinoResult{ .error_message = "Insufficient data" };
        }

        const start = self.returns_history.items.len - w;
        const returns = self.returns_history.items[start..];

        // Calculate mean return
        var sum: f64 = 0;
        for (returns) |r| {
            sum += r;
        }
        const mean = sum / @as(f64, @floatFromInt(returns.len));

        // Calculate downside deviation (only negative returns)
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

        // Annualize
        const annual_factor = @sqrt(self.config.volatility_annual_factor);
        const annual_return = mean * self.config.volatility_annual_factor;
        const annual_downside_dev = downside_dev * annual_factor;

        // Sortino ratio
        const sortino = if (annual_downside_dev > 0)
            (annual_return - self.config.risk_free_rate) / annual_downside_dev
        else
            0;

        return SortinoResult{
            .sortino_ratio = sortino,
            .annual_return = annual_return,
            .downside_deviation = annual_downside_dev,
            .window = w,
            .error_message = null,
        };
    }

    /// Calculate Calmar Ratio
    ///
    /// Calmar = Annual Return / Max Drawdown
    ///
    /// Measures return relative to risk
    pub fn calculateCalmarRatio(self: *Self) CalmarResult {
        const drawdown = self.calculateMaxDrawdown();
        if (drawdown.error_message != null) {
            return CalmarResult{ .error_message = drawdown.error_message };
        }

        if (self.returns_history.items.len < 20) {
            return CalmarResult{ .error_message = "Need at least 20 data points" };
        }

        // Calculate annual return
        var sum: f64 = 0;
        for (self.returns_history.items) |r| {
            sum += r;
        }
        const mean = sum / @as(f64, @floatFromInt(self.returns_history.items.len));
        const annual_return = mean * self.config.volatility_annual_factor;

        // Calmar ratio
        const calmar = if (drawdown.max_drawdown_pct > 0)
            annual_return / drawdown.max_drawdown_pct
        else
            0;

        return CalmarResult{
            .calmar_ratio = calmar,
            .annual_return = annual_return,
            .max_drawdown_pct = drawdown.max_drawdown_pct,
            .error_message = null,
        };
    }

    /// Calculate volatility
    pub fn calculateVolatility(self: *Self) f64 {
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

    /// Get full metrics report
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

    /// Get latest equity
    fn getLatestEquity(self: *Self) Decimal {
        if (self.equity_history.items.len > 0) {
            return self.equity_history.items[self.equity_history.items.len - 1].equity;
        }
        return Decimal.ZERO;
    }

    /// Get equity history count
    pub fn getHistoryCount(self: *Self) usize {
        return self.equity_history.items.len;
    }

    /// Get returns history count
    pub fn getReturnsCount(self: *Self) usize {
        return self.returns_history.items.len;
    }
};

/// Risk Metrics Configuration
pub const RiskMetricsConfig = struct {
    // VaR config
    var_confidence: f64 = 0.99, // VaR confidence level (99%)
    var_horizon_days: u32 = 1, // VaR time horizon (days)

    // Volatility config
    volatility_window: usize = 20, // Volatility calculation window
    volatility_annual_factor: f64 = 252, // Annualization factor

    // Drawdown config
    max_drawdown_alert: f64 = 0.10, // Max drawdown alert threshold (10%)

    // Sharpe/Sortino config
    risk_free_rate: f64 = 0.02, // Risk-free rate (annual 2%)
    sharpe_window: usize = 60, // Sharpe calculation window

    // Update frequency
    update_interval_ms: u64 = 60000, // Update interval (1 minute)

    pub fn default() RiskMetricsConfig {
        return .{};
    }
};

/// Equity Snapshot
pub const EquitySnapshot = struct {
    equity: Decimal,
    timestamp: i64,
    cash: Decimal = Decimal.ZERO,
    positions_value: Decimal = Decimal.ZERO,
};

/// VaR Result
pub const VaRResult = struct {
    var_amount: Decimal = Decimal.ZERO,
    var_percentage: f64 = 0,
    confidence: f64 = 0,
    observations: usize = 0,
    error_message: ?[]const u8 = null,
};

/// CVaR Result
pub const CVaRResult = struct {
    cvar_amount: Decimal = Decimal.ZERO,
    cvar_percentage: f64 = 0,
    confidence: f64 = 0,
    error_message: ?[]const u8 = null,
};

/// Drawdown Result
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

/// Sharpe Result
pub const SharpeResult = struct {
    sharpe_ratio: f64 = 0,
    annual_return: f64 = 0,
    annual_volatility: f64 = 0,
    risk_free_rate: f64 = 0,
    window: usize = 0,
    error_message: ?[]const u8 = null,
};

/// Sortino Result
pub const SortinoResult = struct {
    sortino_ratio: f64 = 0,
    annual_return: f64 = 0,
    downside_deviation: f64 = 0,
    window: usize = 0,
    error_message: ?[]const u8 = null,
};

/// Calmar Result
pub const CalmarResult = struct {
    calmar_ratio: f64 = 0,
    annual_return: f64 = 0,
    max_drawdown_pct: f64 = 0,
    error_message: ?[]const u8 = null,
};

/// Full Risk Metrics Report
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

// ============================================================================
// Tests
// ============================================================================

test "RiskMetricsMonitor: initialization" {
    const allocator = std.testing.allocator;

    var monitor = RiskMetricsMonitor.init(allocator, RiskMetricsConfig.default());
    defer monitor.deinit();

    try std.testing.expectEqual(@as(usize, 0), monitor.getHistoryCount());
}

test "RiskMetricsMonitor: record equity" {
    const allocator = std.testing.allocator;

    var monitor = RiskMetricsMonitor.init(allocator, RiskMetricsConfig.default());
    defer monitor.deinit();

    try monitor.recordEquity(.{ .equity = Decimal.fromFloat(100000), .timestamp = 0 });
    try monitor.recordEquity(.{ .equity = Decimal.fromFloat(101000), .timestamp = 1 });
    try monitor.recordEquity(.{ .equity = Decimal.fromFloat(99000), .timestamp = 2 });

    try std.testing.expectEqual(@as(usize, 3), monitor.getHistoryCount());
    try std.testing.expectEqual(@as(usize, 2), monitor.getReturnsCount());
}

test "RiskMetricsMonitor: max drawdown" {
    const allocator = std.testing.allocator;

    var monitor = RiskMetricsMonitor.init(allocator, RiskMetricsConfig.default());
    defer monitor.deinit();

    // Simulate equity curve: 100 -> 110 -> 90 -> 95
    try monitor.recordEquity(.{ .equity = Decimal.fromFloat(100000), .timestamp = 0 });
    try monitor.recordEquity(.{ .equity = Decimal.fromFloat(110000), .timestamp = 1 });
    try monitor.recordEquity(.{ .equity = Decimal.fromFloat(90000), .timestamp = 2 });
    try monitor.recordEquity(.{ .equity = Decimal.fromFloat(95000), .timestamp = 3 });

    const dd = monitor.calculateMaxDrawdown();
    try std.testing.expect(dd.error_message == null);

    // Max drawdown from 110000 to 90000 = 20000 / 110000 = 18.18%
    try std.testing.expect(dd.max_drawdown_pct > 0.18 and dd.max_drawdown_pct < 0.19);
    try std.testing.expect(dd.is_recovering);
}

test "RiskMetricsMonitor: VaR calculation" {
    const allocator = std.testing.allocator;

    var monitor = RiskMetricsMonitor.init(allocator, RiskMetricsConfig.default());
    defer monitor.deinit();

    // Record enough data for VaR (need 30+)
    var equity: f64 = 100000;
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    for (0..50) |i| {
        try monitor.recordEquity(.{
            .equity = Decimal.fromFloat(equity),
            .timestamp = @intCast(i),
        });
        // Random return between -3% and 3%
        const ret = (random.float(f64) - 0.5) * 0.06;
        equity *= (1.0 + ret);
    }

    const var_result = monitor.calculateVaR(0.95);
    try std.testing.expect(var_result.error_message == null);
    try std.testing.expect(var_result.var_percentage > 0);
    try std.testing.expectEqual(@as(usize, 49), var_result.observations);
}

test "RiskMetricsMonitor: Sharpe ratio" {
    const allocator = std.testing.allocator;

    const config = RiskMetricsConfig{
        .sharpe_window = 20,
        .risk_free_rate = 0.02,
    };

    var monitor = RiskMetricsMonitor.init(allocator, config);
    defer monitor.deinit();

    // Simulate positive returns (should have positive Sharpe)
    var equity: f64 = 100000;
    for (0..30) |i| {
        try monitor.recordEquity(.{
            .equity = Decimal.fromFloat(equity),
            .timestamp = @intCast(i),
        });
        equity *= 1.005; // 0.5% daily return
    }

    const sharpe = monitor.calculateSharpeRatio(null);
    try std.testing.expect(sharpe.error_message == null);
    try std.testing.expect(sharpe.sharpe_ratio > 0); // Should be positive
    try std.testing.expect(sharpe.annual_return > 0);
}

test "RiskMetricsMonitor: Sortino ratio" {
    const allocator = std.testing.allocator;

    const config = RiskMetricsConfig{
        .sharpe_window = 20,
        .risk_free_rate = 0.02,
    };

    var monitor = RiskMetricsMonitor.init(allocator, config);
    defer monitor.deinit();

    // Simulate mixed returns
    var equity: f64 = 100000;
    const returns = [_]f64{ 0.01, -0.005, 0.02, -0.01, 0.015, -0.008, 0.012, -0.003, 0.018, -0.002, 0.01, -0.005, 0.02, -0.01, 0.015, -0.008, 0.012, -0.003, 0.018, -0.002, 0.01, -0.005, 0.02, -0.01, 0.015 };

    for (returns, 0..) |ret, i| {
        try monitor.recordEquity(.{
            .equity = Decimal.fromFloat(equity),
            .timestamp = @intCast(i),
        });
        equity *= (1.0 + ret);
    }

    const sortino = monitor.calculateSortinoRatio(null);
    try std.testing.expect(sortino.error_message == null);
}

test "RiskMetricsMonitor: CVaR calculation" {
    const allocator = std.testing.allocator;

    var monitor = RiskMetricsMonitor.init(allocator, RiskMetricsConfig.default());
    defer monitor.deinit();

    // Record data for CVaR
    var equity: f64 = 100000;
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    for (0..50) |i| {
        try monitor.recordEquity(.{
            .equity = Decimal.fromFloat(equity),
            .timestamp = @intCast(i),
        });
        const ret = (random.float(f64) - 0.5) * 0.06;
        equity *= (1.0 + ret);
    }

    const cvar = monitor.calculateCVaR(0.95);
    try std.testing.expect(cvar.error_message == null);
    // CVaR should be >= VaR
    const var_result = monitor.calculateVaR(0.95);
    try std.testing.expect(cvar.cvar_percentage >= var_result.var_percentage);
}

test "RiskMetricsMonitor: volatility calculation" {
    const allocator = std.testing.allocator;

    const config = RiskMetricsConfig{
        .volatility_window = 10,
    };

    var monitor = RiskMetricsMonitor.init(allocator, config);
    defer monitor.deinit();

    // Simulate equity
    var equity: f64 = 100000;
    for (0..20) |i| {
        try monitor.recordEquity(.{
            .equity = Decimal.fromFloat(equity),
            .timestamp = @intCast(i),
        });
        equity *= if (i % 2 == 0) 1.01 else 0.99;
    }

    const vol = monitor.calculateVolatility();
    try std.testing.expect(vol > 0);
    try std.testing.expect(vol < 2.0); // Should be reasonable annual vol
}

test "RiskMetricsMonitor: full report" {
    const allocator = std.testing.allocator;

    const config = RiskMetricsConfig{
        .sharpe_window = 20,
        .volatility_window = 10,
    };

    var monitor = RiskMetricsMonitor.init(allocator, config);
    defer monitor.deinit();

    // Record sufficient data
    var equity: f64 = 100000;
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    for (0..50) |i| {
        try monitor.recordEquity(.{
            .equity = Decimal.fromFloat(equity),
            .timestamp = @intCast(i),
        });
        const ret = (random.float(f64) - 0.5) * 0.04;
        equity *= (1.0 + ret);
    }

    const report = monitor.getFullMetrics();
    try std.testing.expect(report.observations > 0);
    try std.testing.expect(report.timestamp > 0);
}

test "RiskMetricsMonitor: insufficient data handling" {
    const allocator = std.testing.allocator;

    var monitor = RiskMetricsMonitor.init(allocator, RiskMetricsConfig.default());
    defer monitor.deinit();

    // Only 5 data points
    for (0..5) |i| {
        try monitor.recordEquity(.{
            .equity = Decimal.fromFloat(100000 + @as(f64, @floatFromInt(i)) * 1000),
            .timestamp = @intCast(i),
        });
    }

    // VaR should report insufficient data
    const var_result = monitor.calculateVaR(0.95);
    try std.testing.expect(var_result.error_message != null);

    // Sharpe should report insufficient data (need sharpe_window)
    const sharpe = monitor.calculateSharpeRatio(null);
    try std.testing.expect(sharpe.error_message != null);
}
