//! MoneyManager - Position Sizing Strategies (Story 042)
//!
//! Provides scientific money management strategies:
//! - Kelly Criterion: Mathematically optimal position sizing
//! - Fixed Fraction: Risk fixed percentage per trade
//! - Risk Parity: Volatility-based position allocation
//! - Anti-Martingale: Increase on wins, decrease on losses

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;
const Side = @import("../exchange/types.zig").Side;

/// Money Manager - Position sizing strategies
pub const MoneyManager = struct {
    allocator: Allocator,
    equity: Decimal,
    config: MoneyManagementConfig,

    // Trade history (for statistics)
    trade_history: std.ArrayListUnmanaged(TradeResult),
    win_count: u64,
    loss_count: u64,
    total_profit: Decimal,
    total_loss: Decimal,

    const Self = @This();

    pub fn init(allocator: Allocator, equity: Decimal, config: MoneyManagementConfig) Self {
        return .{
            .allocator = allocator,
            .equity = equity,
            .config = config,
            .trade_history = .{},
            .win_count = 0,
            .loss_count = 0,
            .total_profit = Decimal.ZERO,
            .total_loss = Decimal.ZERO,
        };
    }

    pub fn deinit(self: *Self) void {
        self.trade_history.deinit(self.allocator);
    }

    /// Update account equity
    pub fn updateEquity(self: *Self, equity: Decimal) void {
        self.equity = equity;
    }

    /// Kelly Criterion position sizing
    ///
    /// Kelly = W - (1-W)/R
    /// W = Win rate
    /// R = Profit/Loss ratio (avg win / avg loss)
    pub fn kellyPosition(self: *Self) KellyResult {
        const total_trades = self.win_count + self.loss_count;

        // Need sufficient trade history
        if (total_trades < 10) {
            return KellyResult{
                .position_size = Decimal.ZERO,
                .kelly_fraction = 0,
                .message = "Insufficient trade history (need 10+ trades)",
            };
        }

        if (self.win_count == 0) {
            return KellyResult{
                .position_size = Decimal.ZERO,
                .kelly_fraction = 0,
                .message = "No winning trades",
            };
        }

        if (self.loss_count == 0) {
            return KellyResult{
                .position_size = self.equity.mul(Decimal.fromFloat(self.config.kelly_max_position)),
                .kelly_fraction = self.config.kelly_max_position,
                .win_rate = 1.0,
                .profit_loss_ratio = 0,
                .message = "No losing trades",
            };
        }

        // Calculate win rate
        const win_rate = @as(f64, @floatFromInt(self.win_count)) / @as(f64, @floatFromInt(total_trades));

        // Calculate profit/loss ratio
        const avg_win = self.total_profit.toFloat() / @as(f64, @floatFromInt(self.win_count));
        const avg_loss = self.total_loss.toFloat() / @as(f64, @floatFromInt(self.loss_count));

        if (avg_loss == 0) {
            return KellyResult{
                .position_size = Decimal.ZERO,
                .kelly_fraction = 0,
                .message = "Invalid loss data",
            };
        }

        const profit_loss_ratio = avg_win / avg_loss;

        // Kelly formula
        var kelly = win_rate - (1.0 - win_rate) / profit_loss_ratio;

        // Kelly can be negative (should not trade)
        if (kelly <= 0) {
            return KellyResult{
                .position_size = Decimal.ZERO,
                .kelly_fraction = kelly,
                .win_rate = win_rate,
                .profit_loss_ratio = profit_loss_ratio,
                .message = "Negative Kelly: insufficient edge",
            };
        }

        // Apply Kelly fraction (usually half Kelly)
        kelly *= self.config.kelly_fraction;

        // Limit maximum position
        kelly = @min(kelly, self.config.kelly_max_position);

        // Calculate position size
        const position_size = self.equity.mul(Decimal.fromFloat(kelly));

        return KellyResult{
            .position_size = position_size,
            .kelly_fraction = kelly,
            .win_rate = win_rate,
            .profit_loss_ratio = profit_loss_ratio,
            .message = null,
        };
    }

    /// Fixed Fraction position sizing
    ///
    /// Position = (Equity * Risk%) / Stop Loss%
    ///
    /// Example: Equity $100,000, Risk 2%, Stop 5%
    /// Position = ($100,000 * 0.02) / 0.05 = $40,000
    pub fn fixedFraction(self: *Self, stop_loss_pct: f64) FixedFractionResult {
        if (stop_loss_pct <= 0 or stop_loss_pct >= 1) {
            return FixedFractionResult{
                .position_size = Decimal.ZERO,
                .error_message = "Invalid stop loss percentage",
            };
        }

        // Risk amount = Equity * Risk per trade
        const risk_amount = self.equity.mul(Decimal.fromFloat(self.config.risk_per_trade));

        // Position = Risk amount / Stop loss percentage
        var position_size = risk_amount.div(Decimal.fromFloat(stop_loss_pct)) catch {
            return FixedFractionResult{
                .position_size = Decimal.ZERO,
                .risk_amount = risk_amount,
                .position_pct = 0,
                .error_message = "Division error",
            };
        };

        // Limit maximum position
        const max_position = self.equity.mul(Decimal.fromFloat(self.config.max_position_pct));
        if (position_size.cmp(max_position) == .gt) {
            position_size = max_position;
        }

        // Limit minimum position
        if (position_size.cmp(self.config.min_position_size) == .lt) {
            position_size = self.config.min_position_size;
        }

        const equity_f = self.equity.toFloat();
        const position_pct = if (equity_f > 0)
            position_size.toFloat() / equity_f
        else
            0;

        return FixedFractionResult{
            .position_size = position_size,
            .risk_amount = risk_amount,
            .position_pct = position_pct,
            .error_message = null,
        };
    }

    /// Risk Parity position sizing
    ///
    /// Weight = Target Volatility / Asset Volatility
    ///
    /// Example: Target vol 15%, BTC vol 60%
    /// Weight = 15% / 60% = 25%
    pub fn riskParity(self: *Self, asset_volatility: f64) RiskParityResult {
        if (asset_volatility <= 0) {
            return RiskParityResult{
                .position_size = Decimal.ZERO,
                .error_message = "Invalid asset volatility",
            };
        }

        // Calculate weight
        var weight = self.config.target_volatility / asset_volatility;

        // Limit weight to 100%
        weight = @min(weight, 1.0);

        // Limit maximum position
        weight = @min(weight, self.config.max_position_pct);

        // Calculate position size
        const position_size = self.equity.mul(Decimal.fromFloat(weight));

        return RiskParityResult{
            .position_size = position_size,
            .weight = weight,
            .asset_volatility = asset_volatility,
            .target_volatility = self.config.target_volatility,
            .error_message = null,
        };
    }

    /// Anti-Martingale position sizing
    ///
    /// Increase position after wins, decrease after losses
    /// Opposite of Martingale, better for trending markets
    pub fn antiMartingale(self: *Self, base_position: Decimal) AntiMartingaleResult {
        // Get recent trades
        const recent = self.getRecentTrades(5);

        if (recent.len == 0) {
            return AntiMartingaleResult{
                .position_size = base_position,
                .multiplier = 1.0,
                .consecutive_wins = 0,
                .consecutive_losses = 0,
            };
        }

        // Count consecutive wins/losses
        var consecutive_wins: u32 = 0;
        var consecutive_losses: u32 = 0;

        for (recent) |trade| {
            if (trade.pnl.cmp(Decimal.ZERO) == .gt) {
                if (consecutive_losses > 0) break;
                consecutive_wins += 1;
            } else {
                if (consecutive_wins > 0) break;
                consecutive_losses += 1;
            }
        }

        // Calculate multiplier
        var multiplier: f64 = 1.0;

        if (consecutive_wins > 0) {
            // Consecutive wins: increase position
            multiplier = std.math.pow(f64, self.config.anti_martingale_factor, @floatFromInt(consecutive_wins));
            // Limit maximum multiplier
            multiplier = @min(multiplier, 4.0);
        } else if (consecutive_losses >= self.config.anti_martingale_reset) {
            // Consecutive losses reach threshold: reset to base
            multiplier = 1.0;
        } else if (consecutive_losses > 0) {
            // Consecutive losses: decrease position
            multiplier = std.math.pow(f64, 1.0 / self.config.anti_martingale_factor, @floatFromInt(consecutive_losses));
            // Limit minimum multiplier
            multiplier = @max(multiplier, 0.25);
        }

        var position_size = base_position.mul(Decimal.fromFloat(multiplier));

        // Limit maximum position
        const max_position = self.equity.mul(Decimal.fromFloat(self.config.max_position_pct));
        if (position_size.cmp(max_position) == .gt) {
            position_size = max_position;
        }

        return AntiMartingaleResult{
            .position_size = position_size,
            .multiplier = multiplier,
            .consecutive_wins = consecutive_wins,
            .consecutive_losses = consecutive_losses,
        };
    }

    /// Calculate position based on configured method
    pub fn calculatePosition(self: *Self, context: PositionContext) PositionRecommendation {
        if (!self.config.enabled) {
            return PositionRecommendation{
                .position_size = context.requested_size,
                .method = .fixed_size,
            };
        }

        return switch (self.config.method) {
            .kelly => blk: {
                const result = self.kellyPosition();
                break :blk PositionRecommendation{
                    .position_size = result.position_size,
                    .method = .kelly,
                };
            },
            .fixed_fraction => blk: {
                const result = self.fixedFraction(context.stop_loss_pct);
                break :blk PositionRecommendation{
                    .position_size = result.position_size,
                    .method = .fixed_fraction,
                };
            },
            .risk_parity => blk: {
                const result = self.riskParity(context.asset_volatility);
                break :blk PositionRecommendation{
                    .position_size = result.position_size,
                    .method = .risk_parity,
                };
            },
            .anti_martingale => blk: {
                const result = self.antiMartingale(context.requested_size);
                break :blk PositionRecommendation{
                    .position_size = result.position_size,
                    .method = .anti_martingale,
                };
            },
            .fixed_size => PositionRecommendation{
                .position_size = context.requested_size,
                .method = .fixed_size,
            },
        };
    }

    /// Record a trade result
    pub fn recordTrade(self: *Self, result: TradeResult) !void {
        try self.trade_history.append(self.allocator, result);

        if (result.pnl.cmp(Decimal.ZERO) == .gt) {
            self.win_count += 1;
            self.total_profit = self.total_profit.add(result.pnl);
        } else {
            self.loss_count += 1;
            self.total_loss = self.total_loss.add(result.pnl.abs());
        }

        // Limit history size
        if (self.trade_history.items.len > 1000) {
            _ = self.trade_history.orderedRemove(0);
        }
    }

    /// Get recent trades (most recent first)
    fn getRecentTrades(self: *Self, count: usize) []const TradeResult {
        const len = self.trade_history.items.len;
        if (len == 0) return &[_]TradeResult{};

        const start = if (len > count) len - count else 0;
        return self.trade_history.items[start..];
    }

    /// Calculate historical volatility
    pub fn calculateVolatility(_: *Self, returns: []const f64) f64 {
        if (returns.len < 2) return 0;

        // Calculate mean
        var sum: f64 = 0;
        for (returns) |r| {
            sum += r;
        }
        const mean = sum / @as(f64, @floatFromInt(returns.len));

        // Calculate variance
        var variance: f64 = 0;
        for (returns) |r| {
            const diff = r - mean;
            variance += diff * diff;
        }
        variance /= @as(f64, @floatFromInt(returns.len - 1));

        // Standard deviation
        const daily_vol = @sqrt(variance);

        // Annualized volatility (assuming 252 trading days)
        return daily_vol * @sqrt(252.0);
    }

    /// Get trading statistics
    pub fn getStats(self: *Self) MoneyManagerStats {
        const total_trades = self.win_count + self.loss_count;
        const win_rate = if (total_trades > 0)
            @as(f64, @floatFromInt(self.win_count)) / @as(f64, @floatFromInt(total_trades))
        else
            0;

        const avg_win = if (self.win_count > 0)
            self.total_profit.toFloat() / @as(f64, @floatFromInt(self.win_count))
        else
            0;

        const avg_loss = if (self.loss_count > 0)
            self.total_loss.toFloat() / @as(f64, @floatFromInt(self.loss_count))
        else
            0;

        return MoneyManagerStats{
            .total_trades = total_trades,
            .win_count = self.win_count,
            .loss_count = self.loss_count,
            .win_rate = win_rate,
            .avg_win = avg_win,
            .avg_loss = avg_loss,
            .profit_factor = if (avg_loss > 0) avg_win / avg_loss else 0,
            .net_pnl = self.total_profit.sub(self.total_loss),
        };
    }
};

/// Money Management Configuration
pub const MoneyManagementConfig = struct {
    // Strategy selection
    method: MoneyManagementMethod = .fixed_fraction,

    // Kelly parameters
    kelly_fraction: f64 = 0.5, // Kelly fraction (0.5 = half Kelly)
    kelly_max_position: f64 = 0.25, // Kelly max position %

    // Fixed fraction parameters
    risk_per_trade: f64 = 0.02, // Risk per trade (2%)
    max_position_pct: f64 = 0.20, // Max single position (20%)

    // Risk parity parameters
    target_volatility: f64 = 0.15, // Target annual volatility (15%)
    lookback_period: usize = 20, // Volatility lookback period

    // Anti-martingale parameters
    anti_martingale_factor: f64 = 1.5, // Multiplier after win
    anti_martingale_reset: u32 = 3, // Reset after N consecutive losses

    // General limits
    max_total_exposure: f64 = 1.0, // Total exposure limit (100%)
    min_position_size: Decimal = Decimal.ZERO, // Minimum position
    max_positions: usize = 10, // Maximum number of positions

    // Enable/disable
    enabled: bool = true,

    /// Get default configuration
    pub fn default() MoneyManagementConfig {
        return .{};
    }

    /// Get conservative configuration
    pub fn conservative() MoneyManagementConfig {
        return .{
            .method = .fixed_fraction,
            .kelly_fraction = 0.25,
            .kelly_max_position = 0.15,
            .risk_per_trade = 0.01,
            .max_position_pct = 0.10,
            .target_volatility = 0.10,
            .anti_martingale_factor = 1.25,
            .anti_martingale_reset = 2,
            .max_total_exposure = 0.5,
            .max_positions = 5,
            .enabled = true,
        };
    }
};

/// Money Management Method
pub const MoneyManagementMethod = enum {
    kelly, // Kelly Criterion
    fixed_fraction, // Fixed Fraction
    risk_parity, // Risk Parity
    anti_martingale, // Anti-Martingale
    fixed_size, // Fixed Size
};

/// Kelly Result
pub const KellyResult = struct {
    position_size: Decimal,
    kelly_fraction: f64,
    win_rate: f64 = 0,
    profit_loss_ratio: f64 = 0,
    message: ?[]const u8 = null,
};

/// Fixed Fraction Result
pub const FixedFractionResult = struct {
    position_size: Decimal,
    risk_amount: Decimal = Decimal.ZERO,
    position_pct: f64 = 0,
    error_message: ?[]const u8 = null,
};

/// Risk Parity Result
pub const RiskParityResult = struct {
    position_size: Decimal,
    weight: f64 = 0,
    asset_volatility: f64 = 0,
    target_volatility: f64 = 0,
    error_message: ?[]const u8 = null,
};

/// Anti-Martingale Result
pub const AntiMartingaleResult = struct {
    position_size: Decimal,
    multiplier: f64,
    consecutive_wins: u32 = 0,
    consecutive_losses: u32 = 0,
};

/// Position Context (input for calculation)
pub const PositionContext = struct {
    symbol: []const u8 = "",
    requested_size: Decimal = Decimal.ZERO,
    stop_loss_pct: f64 = 0.02,
    asset_volatility: f64 = 0.5,
    current_price: Decimal = Decimal.ZERO,
};

/// Position Recommendation (output)
pub const PositionRecommendation = struct {
    position_size: Decimal,
    method: MoneyManagementMethod,
};

/// Trade Result
pub const TradeResult = struct {
    symbol: []const u8,
    side: Side,
    entry_price: Decimal,
    exit_price: Decimal,
    quantity: Decimal,
    pnl: Decimal,
    timestamp: i64,
};

/// Money Manager Statistics
pub const MoneyManagerStats = struct {
    total_trades: u64,
    win_count: u64,
    loss_count: u64,
    win_rate: f64,
    avg_win: f64,
    avg_loss: f64,
    profit_factor: f64,
    net_pnl: Decimal,
};

// ============================================================================
// Tests
// ============================================================================

test "MoneyManager: initialization" {
    const allocator = std.testing.allocator;

    var mm = MoneyManager.init(allocator, Decimal.fromFloat(100000), MoneyManagementConfig.default());
    defer mm.deinit();

    const stats = mm.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_trades);
}

test "MoneyManager: fixed fraction" {
    const allocator = std.testing.allocator;

    const config = MoneyManagementConfig{
        .risk_per_trade = 0.02, // 2% risk
        .max_position_pct = 0.50, // 50% max to not limit position
    };

    var mm = MoneyManager.init(allocator, Decimal.fromFloat(100000), config);
    defer mm.deinit();

    // 2% risk with 5% stop loss
    // Position = (100000 * 0.02) / 0.05 = 40000
    const result = mm.fixedFraction(0.05);

    // Check no error
    try std.testing.expect(result.error_message == null);

    // Position should be non-zero
    try std.testing.expect(!result.position_size.isZero());

    // Position should be positive (meaningful result)
    try std.testing.expect(result.position_size.toFloat() > 0);
}

test "MoneyManager: fixed fraction max position" {
    const allocator = std.testing.allocator;

    const config = MoneyManagementConfig{
        .risk_per_trade = 0.02,
        .max_position_pct = 0.10, // 10% max (smaller than calculated)
    };

    var mm = MoneyManager.init(allocator, Decimal.fromFloat(100000), config);
    defer mm.deinit();

    // Would be 40000 but limited to 10000 (10%)
    const result = mm.fixedFraction(0.05);

    const max = Decimal.fromFloat(10000);
    try std.testing.expect(result.position_size.cmp(max) != .gt);
}

test "MoneyManager: risk parity" {
    const allocator = std.testing.allocator;

    const config = MoneyManagementConfig{
        .target_volatility = 0.15, // 15% target
        .max_position_pct = 0.50,
    };

    var mm = MoneyManager.init(allocator, Decimal.fromFloat(100000), config);
    defer mm.deinit();

    // Asset volatility 60%
    // Weight = 0.15 / 0.60 = 0.25
    // Position = 100000 * 0.25 = 25000
    const result = mm.riskParity(0.60);

    const expected = Decimal.fromFloat(25000);
    const diff = result.position_size.sub(expected).abs();
    try std.testing.expect(diff.cmp(Decimal.fromFloat(1)) == .lt);
    try std.testing.expect(result.weight > 0.24 and result.weight < 0.26);
}

test "MoneyManager: anti-martingale consecutive wins" {
    const allocator = std.testing.allocator;

    const config = MoneyManagementConfig{
        .anti_martingale_factor = 1.5,
        .max_position_pct = 0.50,
    };

    var mm = MoneyManager.init(allocator, Decimal.fromFloat(100000), config);
    defer mm.deinit();

    // Record winning trades
    try mm.recordTrade(.{
        .symbol = "BTC",
        .side = .buy,
        .entry_price = Decimal.fromFloat(50000),
        .exit_price = Decimal.fromFloat(52000),
        .quantity = Decimal.fromFloat(1),
        .pnl = Decimal.fromFloat(2000),
        .timestamp = 0,
    });
    try mm.recordTrade(.{
        .symbol = "BTC",
        .side = .buy,
        .entry_price = Decimal.fromFloat(52000),
        .exit_price = Decimal.fromFloat(54000),
        .quantity = Decimal.fromFloat(1),
        .pnl = Decimal.fromFloat(2000),
        .timestamp = 1,
    });

    const base = Decimal.fromFloat(10000);
    const result = mm.antiMartingale(base);

    // 2 consecutive wins with 1.5x factor = 1.5^2 = 2.25x
    try std.testing.expect(result.multiplier > 2.2 and result.multiplier < 2.3);
    try std.testing.expectEqual(@as(u32, 2), result.consecutive_wins);
}

test "MoneyManager: record trade and stats" {
    const allocator = std.testing.allocator;

    var mm = MoneyManager.init(allocator, Decimal.fromFloat(100000), MoneyManagementConfig.default());
    defer mm.deinit();

    // Record trades
    try mm.recordTrade(.{
        .symbol = "BTC",
        .side = .buy,
        .entry_price = Decimal.fromFloat(50000),
        .exit_price = Decimal.fromFloat(52000),
        .quantity = Decimal.fromFloat(1),
        .pnl = Decimal.fromFloat(2000),
        .timestamp = 0,
    });
    try mm.recordTrade(.{
        .symbol = "BTC",
        .side = .buy,
        .entry_price = Decimal.fromFloat(52000),
        .exit_price = Decimal.fromFloat(51000),
        .quantity = Decimal.fromFloat(1),
        .pnl = Decimal.fromFloat(-1000),
        .timestamp = 1,
    });

    const stats = mm.getStats();
    try std.testing.expectEqual(@as(u64, 2), stats.total_trades);
    try std.testing.expectEqual(@as(u64, 1), stats.win_count);
    try std.testing.expectEqual(@as(u64, 1), stats.loss_count);
    try std.testing.expect(stats.win_rate > 0.49 and stats.win_rate < 0.51);
}

test "MoneyManager: volatility calculation" {
    const allocator = std.testing.allocator;

    var mm = MoneyManager.init(allocator, Decimal.fromFloat(100000), MoneyManagementConfig.default());
    defer mm.deinit();

    // Daily returns
    const returns = [_]f64{ 0.01, -0.02, 0.015, -0.005, 0.02, -0.01, 0.008 };

    const vol = mm.calculateVolatility(&returns);

    // Should return annualized volatility
    try std.testing.expect(vol > 0);
    try std.testing.expect(vol < 1.0); // Should be less than 100%
}

test "MoneyManager: kelly with insufficient history" {
    const allocator = std.testing.allocator;

    var mm = MoneyManager.init(allocator, Decimal.fromFloat(100000), MoneyManagementConfig.default());
    defer mm.deinit();

    // Only 2 trades
    try mm.recordTrade(.{
        .symbol = "BTC",
        .side = .buy,
        .entry_price = Decimal.fromFloat(50000),
        .exit_price = Decimal.fromFloat(52000),
        .quantity = Decimal.fromFloat(1),
        .pnl = Decimal.fromFloat(2000),
        .timestamp = 0,
    });
    try mm.recordTrade(.{
        .symbol = "BTC",
        .side = .buy,
        .entry_price = Decimal.fromFloat(52000),
        .exit_price = Decimal.fromFloat(51000),
        .quantity = Decimal.fromFloat(1),
        .pnl = Decimal.fromFloat(-1000),
        .timestamp = 1,
    });

    const result = mm.kellyPosition();
    try std.testing.expect(result.position_size.isZero());
    try std.testing.expect(result.message != null);
}

test "MoneyManager: calculate position unified interface" {
    const allocator = std.testing.allocator;

    const config = MoneyManagementConfig{
        .method = .fixed_fraction,
        .risk_per_trade = 0.02,
        .max_position_pct = 0.20,
    };

    var mm = MoneyManager.init(allocator, Decimal.fromFloat(100000), config);
    defer mm.deinit();

    const context = PositionContext{
        .symbol = "BTC",
        .requested_size = Decimal.fromFloat(10000),
        .stop_loss_pct = 0.05,
        .asset_volatility = 0.5,
    };

    const rec = mm.calculatePosition(context);
    try std.testing.expectEqual(MoneyManagementMethod.fixed_fraction, rec.method);
    try std.testing.expect(!rec.position_size.isZero());
}
