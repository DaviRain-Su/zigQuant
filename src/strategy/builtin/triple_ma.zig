//! Triple Moving Average (Triple MA) Strategy
//!
//! Trend-following strategy using three moving averages for trend confirmation:
//! - **Bullish Alignment**: Fast MA > Medium MA > Slow MA → Uptrend
//! - **Bearish Alignment**: Fast MA < Medium MA < Slow MA → Downtrend
//! - **Golden Cross + Alignment**: Fast crosses above Medium with bullish alignment → Entry Long
//! - **Death Cross + Alignment**: Fast crosses below Medium with bearish alignment → Exit Long
//!
//! Advantages over Dual MA:
//! - Multiple confirmation reduces false signals
//! - Better trend identification
//! - Clearer trend strength assessment
//!
//! Strategy Parameters:
//! - `fast_period` - Fast MA period (default: 5)
//! - `medium_period` - Medium MA period (default: 20)
//! - `slow_period` - Slow MA period (default: 50)
//! - `ma_type` - MA type: SMA or EMA (default: EMA)
//!
//! Performance:
//! - Works best in strong trending markets
//! - Fewer but higher quality signals
//! - Signal strength: 0.85 (high reliability)

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candles = @import("../../root.zig").Candles;
const TradingPair = @import("../../root.zig").TradingPair;
const Timestamp = @import("../../root.zig").Timestamp;
const Side = @import("../../root.zig").Side;
const IStrategy = @import("../interface.zig").IStrategy;
const StrategyContext = @import("../interface.zig").StrategyContext;
const Signal = @import("../signal.zig").Signal;
const SignalType = @import("../signal.zig").SignalType;
const SignalMetadata = @import("../signal.zig").SignalMetadata;
const IndicatorValue = @import("../signal.zig").IndicatorValue;
const StrategyMetadata = @import("../types.zig").StrategyMetadata;
const StrategyParameter = @import("../types.zig").StrategyParameter;
const StrategyType = @import("../types.zig").StrategyType;
const Position = @import("../../backtest/position.zig").Position;
const Account = @import("../../backtest/account.zig").Account;
const IndicatorManager = @import("../../root.zig").IndicatorManager;
const indicator_helpers = @import("../../root.zig").indicator_helpers;
const Logger = @import("../../root.zig").Logger;
const Timeframe = @import("../../root.zig").Timeframe;

// ============================================================================
// Configuration
// ============================================================================

/// Moving Average type
pub const MAType = enum {
    sma, // Simple Moving Average
    ema, // Exponential Moving Average
};

/// Strategy configuration
pub const Config = struct {
    /// Trading pair
    pair: TradingPair,

    /// Fast MA period (must be < medium_period)
    fast_period: u32 = 5,

    /// Medium MA period (must be > fast_period, < slow_period)
    medium_period: u32 = 20,

    /// Slow MA period (must be > medium_period)
    slow_period: u32 = 50,

    /// MA type (SMA or EMA)
    ma_type: MAType = .ema,

    /// Validate configuration
    pub fn validate(self: Config) !void {
        if (self.fast_period >= self.medium_period) {
            return error.InvalidFastPeriod;
        }
        if (self.medium_period >= self.slow_period) {
            return error.InvalidMediumPeriod;
        }
        if (self.fast_period < 2) {
            return error.FastPeriodTooSmall;
        }
        if (self.slow_period > 200) {
            return error.SlowPeriodTooLarge;
        }
    }
};

// ============================================================================
// Triple MA Strategy
// ============================================================================

/// Triple Moving Average Strategy
pub const TripleMAStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    indicator_manager: IndicatorManager,
    logger: Logger,
    initialized: bool,

    /// Create a new Triple MA strategy instance
    pub fn create(allocator: std.mem.Allocator, config: Config) !*TripleMAStrategy {
        // Validate configuration
        try config.validate();

        const self = try allocator.create(TripleMAStrategy);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .indicator_manager = IndicatorManager.init(allocator),
            .logger = undefined, // Will be set in init()
            .initialized = false,
        };

        return self;
    }

    /// Convert to IStrategy interface
    pub fn toStrategy(self: *TripleMAStrategy) IStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Destroy strategy and free resources
    pub fn destroy(self: *TripleMAStrategy) void {
        self.indicator_manager.deinit();
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn init(ptr: *anyopaque, ctx: StrategyContext) !void {
        const self: *TripleMAStrategy = @ptrCast(@alignCast(ptr));
        self.logger = ctx.logger;
        self.initialized = true;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *TripleMAStrategy = @ptrCast(@alignCast(ptr));
        self.indicator_manager.deinit();
        self.initialized = false;
    }

    fn populateIndicators(ptr: *anyopaque, candles: *Candles) !void {
        const self: *TripleMAStrategy = @ptrCast(@alignCast(ptr));

        // Calculate fast MA
        const ma_fast = switch (self.config.ma_type) {
            .sma => try indicator_helpers.getSMA(
                &self.indicator_manager,
                candles,
                self.config.fast_period,
            ),
            .ema => try indicator_helpers.getEMA(
                &self.indicator_manager,
                candles,
                self.config.fast_period,
            ),
        };

        // Calculate medium MA
        const ma_medium = switch (self.config.ma_type) {
            .sma => try indicator_helpers.getSMA(
                &self.indicator_manager,
                candles,
                self.config.medium_period,
            ),
            .ema => try indicator_helpers.getEMA(
                &self.indicator_manager,
                candles,
                self.config.medium_period,
            ),
        };

        // Calculate slow MA
        const ma_slow = switch (self.config.ma_type) {
            .sma => try indicator_helpers.getSMA(
                &self.indicator_manager,
                candles,
                self.config.slow_period,
            ),
            .ema => try indicator_helpers.getEMA(
                &self.indicator_manager,
                candles,
                self.config.slow_period,
            ),
        };

        // Add indicators to candles
        try candles.addIndicatorValues("ma_fast", ma_fast);
        try candles.addIndicatorValues("ma_medium", ma_medium);
        try candles.addIndicatorValues("ma_slow", ma_slow);
    }

    fn generateEntrySignal(
        ptr: *anyopaque,
        candles: *Candles,
        index: usize,
    ) !?Signal {
        const self: *TripleMAStrategy = @ptrCast(@alignCast(ptr));

        // Need enough data for crossover detection
        if (index < self.config.slow_period + 1) {
            return null;
        }

        // Get indicators
        const ma_fast = candles.getIndicator("ma_fast") orelse return null;
        const ma_medium = candles.getIndicator("ma_medium") orelse return null;
        const ma_slow = candles.getIndicator("ma_slow") orelse return null;

        // Get current and previous values
        const prev_fast = ma_fast.values[index - 1];
        const prev_medium = ma_medium.values[index - 1];
        const curr_fast = ma_fast.values[index];
        const curr_medium = ma_medium.values[index];
        const curr_slow = ma_slow.values[index];

        // Skip if any value is NaN
        if (prev_fast.isNaN() or prev_medium.isNaN() or curr_fast.isNaN() or
            curr_medium.isNaN() or curr_slow.isNaN())
        {
            return null;
        }

        const current_candle = candles.get(index) orelse return null;
        const price = current_candle.close;
        const timestamp = current_candle.timestamp;

        // Check for bullish alignment: Fast > Medium > Slow
        const bullish_alignment = curr_fast.cmp(curr_medium) == .gt and
            curr_medium.cmp(curr_slow) == .gt;

        // Check for golden cross: Fast crosses above Medium
        const golden_cross = prev_fast.cmp(prev_medium) != .gt and
            curr_fast.cmp(curr_medium) == .gt;

        // Entry Long: Golden Cross + Bullish Alignment
        if (golden_cross and bullish_alignment) {
            const metadata = try SignalMetadata.init(
                self.allocator,
                "Triple MA Golden Cross + Bullish Alignment",
                &[_]IndicatorValue{
                    .{ .name = "ma_fast", .value = curr_fast },
                    .{ .name = "ma_medium", .value = curr_medium },
                    .{ .name = "ma_slow", .value = curr_slow },
                },
            );

            const signal = try Signal.init(
                .entry_long,
                self.config.pair,
                .buy,
                price,
                0.85, // Higher signal strength due to triple confirmation
                timestamp,
                metadata,
            );
            return signal;
        }

        // Check for bearish alignment: Fast < Medium < Slow
        const bearish_alignment = curr_fast.cmp(curr_medium) == .lt and
            curr_medium.cmp(curr_slow) == .lt;

        // Check for death cross: Fast crosses below Medium
        const death_cross = prev_fast.cmp(prev_medium) != .lt and
            curr_fast.cmp(curr_medium) == .lt;

        // Entry Short: Death Cross + Bearish Alignment
        if (death_cross and bearish_alignment) {
            const metadata = try SignalMetadata.init(
                self.allocator,
                "Triple MA Death Cross + Bearish Alignment",
                &[_]IndicatorValue{
                    .{ .name = "ma_fast", .value = curr_fast },
                    .{ .name = "ma_medium", .value = curr_medium },
                    .{ .name = "ma_slow", .value = curr_slow },
                },
            );

            const signal = try Signal.init(
                .entry_short,
                self.config.pair,
                .sell,
                price,
                0.85, // Higher signal strength due to triple confirmation
                timestamp,
                metadata,
            );
            return signal;
        }

        return null;
    }

    fn generateExitSignal(
        ptr: *anyopaque,
        candles: *Candles,
        position: Position,
    ) !?Signal {
        const self: *TripleMAStrategy = @ptrCast(@alignCast(ptr));

        const index = candles.len() - 1;

        // Need enough data
        if (index < self.config.slow_period + 1) {
            return null;
        }

        // Get indicators
        const ma_fast = candles.getIndicator("ma_fast") orelse return null;
        const ma_medium = candles.getIndicator("ma_medium") orelse return null;

        const prev_fast = ma_fast.values[index - 1];
        const prev_medium = ma_medium.values[index - 1];
        const curr_fast = ma_fast.values[index];
        const curr_medium = ma_medium.values[index];

        // Skip if any value is NaN
        if (prev_fast.isNaN() or prev_medium.isNaN() or curr_fast.isNaN() or curr_medium.isNaN()) {
            return null;
        }

        const current_candle = candles.get(index) orelse return null;
        const price = current_candle.close;
        const timestamp = current_candle.timestamp;

        // Exit Long: Death Cross (fast crosses below medium)
        if (position.side == .long) {
            const death_cross = prev_fast.cmp(prev_medium) != .lt and
                curr_fast.cmp(curr_medium) == .lt;

            if (death_cross) {
                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Triple MA Death Cross: Exit long position",
                    &[_]IndicatorValue{
                        .{ .name = "ma_fast", .value = curr_fast },
                        .{ .name = "ma_medium", .value = curr_medium },
                    },
                );

                const signal = try Signal.init(
                    .exit_long,
                    position.pair,
                    .sell,
                    price,
                    0.85,
                    timestamp,
                    metadata,
                );
                return signal;
            }
        }

        // Exit Short: Golden Cross (fast crosses above medium)
        if (position.side == .short) {
            const golden_cross = prev_fast.cmp(prev_medium) != .gt and
                curr_fast.cmp(curr_medium) == .gt;

            if (golden_cross) {
                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Triple MA Golden Cross: Exit short position",
                    &[_]IndicatorValue{
                        .{ .name = "ma_fast", .value = curr_fast },
                        .{ .name = "ma_medium", .value = curr_medium },
                    },
                );

                const signal = try Signal.init(
                    .exit_short,
                    position.pair,
                    .buy,
                    price,
                    0.85,
                    timestamp,
                    metadata,
                );
                return signal;
            }
        }

        return null;
    }

    fn calculatePositionSize(
        ptr: *anyopaque,
        signal: Signal,
        account: Account,
    ) !Decimal {
        _ = ptr;

        // Use 95% of available balance
        const available = account.balance.mul(Decimal.fromFloat(0.95));
        const position_size = try available.div(signal.price);
        return position_size;
    }

    fn getParameters(ptr: *anyopaque) []const StrategyParameter {
        const self: *TripleMAStrategy = @ptrCast(@alignCast(ptr));

        const params = [_]StrategyParameter{
            .{
                .name = "fast_period",
                .description = "Fast MA period",
                .value = .{ .integer = @intCast(self.config.fast_period) },
            },
            .{
                .name = "medium_period",
                .description = "Medium MA period",
                .value = .{ .integer = @intCast(self.config.medium_period) },
            },
            .{
                .name = "slow_period",
                .description = "Slow MA period",
                .value = .{ .integer = @intCast(self.config.slow_period) },
            },
            .{
                .name = "ma_type",
                .description = "MA type (sma/ema)",
                .value = .{ .string = @tagName(self.config.ma_type) },
            },
        };

        return &params;
    }

    fn getMetadata(ptr: *anyopaque) StrategyMetadata {
        const self: *TripleMAStrategy = @ptrCast(@alignCast(ptr));

        const roi_targets = [_]@import("../types.zig").ROITarget{
            .{ .time_minutes = 0, .profit_ratio = Decimal.fromFloat(0.05) }, // 5% immediate
            .{ .time_minutes = 30, .profit_ratio = Decimal.fromFloat(0.03) }, // 3% after 30min
            .{ .time_minutes = 90, .profit_ratio = Decimal.fromFloat(0.015) }, // 1.5% after 1.5hr
        };

        return .{
            .name = "Triple Moving Average Strategy",
            .version = "1.0.0",
            .author = "zigQuant",
            .description = "Three MA trend-following strategy with alignment confirmation",
            .strategy_type = .trend_following,
            .timeframe = .h1,
            .startup_candle_count = self.config.slow_period + 1,
            .minimal_roi = .{ .targets = &roi_targets },
            .stoploss = Decimal.fromFloat(-0.05), // -5% stop loss
            .trailing_stop = null,
        };
    }

    const vtable = IStrategy.VTable{
        .init = init,
        .deinit = deinit,
        .populateIndicators = populateIndicators,
        .generateEntrySignal = generateEntrySignal,
        .generateExitSignal = generateExitSignal,
        .calculatePositionSize = calculatePositionSize,
        .getParameters = getParameters,
        .getMetadata = getMetadata,
    };
};

// ============================================================================
// Tests
// ============================================================================

test "TripleMAStrategy: config validation" {
    const allocator = std.testing.allocator;

    // Valid config
    {
        const config = Config{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .fast_period = 5,
            .medium_period = 20,
            .slow_period = 50,
            .ma_type = .ema,
        };
        try config.validate();

        const strategy = try TripleMAStrategy.create(allocator, config);
        defer strategy.destroy();
    }

    // Invalid: fast >= medium
    {
        const config = Config{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .fast_period = 20,
            .medium_period = 20,
            .slow_period = 50,
            .ma_type = .ema,
        };
        try std.testing.expectError(error.InvalidFastPeriod, config.validate());
    }

    // Invalid: medium >= slow
    {
        const config = Config{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .fast_period = 5,
            .medium_period = 50,
            .slow_period = 50,
            .ma_type = .ema,
        };
        try std.testing.expectError(error.InvalidMediumPeriod, config.validate());
    }
}

test "TripleMAStrategy: interface conversion" {
    const allocator = std.testing.allocator;

    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .fast_period = 5,
        .medium_period = 20,
        .slow_period = 50,
        .ma_type = .ema,
    };

    const strategy = try TripleMAStrategy.create(allocator, config);
    defer strategy.destroy();

    const interface = strategy.toStrategy();
    _ = interface;
}
