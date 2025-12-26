//! Dual Moving Average (Dual MA) Strategy
//!
//! Classic trend-following strategy using two moving averages:
//! - **Golden Cross**: Fast MA crosses above slow MA → Entry Long
//! - **Death Cross**: Fast MA crosses below slow MA → Exit Long / Entry Short
//!
//! Strategy Parameters:
//! - `fast_period` - Fast MA period (default: 10)
//! - `slow_period` - Slow MA period (default: 20)
//! - `ma_type` - MA type: SMA or EMA (default: SMA)
//!
//! Performance:
//! - Works best in trending markets
//! - Prone to whipsaws in ranging markets
//! - Signal strength: 0.8 (relatively reliable)

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

    /// Fast MA period (must be < slow_period)
    fast_period: u32 = 10,

    /// Slow MA period (must be > fast_period)
    slow_period: u32 = 20,

    /// MA type (SMA or EMA)
    ma_type: MAType = .sma,

    /// Validate configuration
    pub fn validate(self: Config) !void {
        if (self.fast_period >= self.slow_period) {
            return error.InvalidParameters;
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
// Dual MA Strategy
// ============================================================================

/// Dual Moving Average Strategy
pub const DualMAStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    indicator_manager: IndicatorManager,
    logger: Logger,
    initialized: bool,

    /// Create a new Dual MA strategy instance
    pub fn create(allocator: std.mem.Allocator, config: Config) !*DualMAStrategy {
        // Validate configuration
        try config.validate();

        const self = try allocator.create(DualMAStrategy);
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
    pub fn toStrategy(self: *DualMAStrategy) IStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Destroy strategy and free resources
    pub fn destroy(self: *DualMAStrategy) void {
        self.indicator_manager.deinit();
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn init(ptr: *anyopaque, ctx: StrategyContext) !void {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));
        self.logger = ctx.logger;
        self.initialized = true;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));
        self.initialized = false;
    }

    fn populateIndicators(ptr: *anyopaque, candles: *Candles) !void {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

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
        try candles.addIndicatorValues("ma_slow", ma_slow);
    }

    fn generateEntrySignal(
        ptr: *anyopaque,
        candles: *Candles,
        index: usize,
    ) !?Signal {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

        // Need enough data for crossover detection
        if (index < self.config.slow_period) {
            return null;
        }

        // Get indicators
        const ma_fast = candles.getIndicator("ma_fast") orelse return null;
        const ma_slow = candles.getIndicator("ma_slow") orelse return null;

        // Get current and previous values
        const prev_fast = ma_fast.values[index - 1];
        const prev_slow = ma_slow.values[index - 1];
        const curr_fast = ma_fast.values[index];
        const curr_slow = ma_slow.values[index];

        // Skip if any value is NaN
        if (prev_fast.isNaN() or prev_slow.isNaN() or curr_fast.isNaN() or curr_slow.isNaN()) {
            return null;
        }

        const current_candle = candles.get(index) orelse return null;
        const price = current_candle.close;
        const timestamp = current_candle.timestamp;

        // Detect Golden Cross (fast crosses above slow) - Entry Long
        if (prev_fast.cmp(prev_slow) != .gt and curr_fast.cmp(curr_slow) == .gt) {
            const metadata = try SignalMetadata.init(
                self.allocator,
                "Golden Cross: Fast MA crossed above Slow MA",
                &[_]IndicatorValue{
                    .{ .name = "ma_fast", .value = curr_fast },
                    .{ .name = "ma_slow", .value = curr_slow },
                },
            );

            const signal = try Signal.init(
                .entry_long,
                self.config.pair,
                .buy,
                price,
                0.8, // Signal strength
                timestamp,
                metadata,
            );
            return signal;
        }

        // Detect Death Cross (fast crosses below slow) - Entry Short
        if (prev_fast.cmp(prev_slow) != .lt and curr_fast.cmp(curr_slow) == .lt) {
            const metadata = try SignalMetadata.init(
                self.allocator,
                "Death Cross: Fast MA crossed below Slow MA",
                &[_]IndicatorValue{
                    .{ .name = "ma_fast", .value = curr_fast },
                    .{ .name = "ma_slow", .value = curr_slow },
                },
            );

            const signal = try Signal.init(
                .entry_short,
                self.config.pair,
                .sell,
                price,
                0.8, // Signal strength
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
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

        const index = candles.len() - 1;

        // Need enough data
        if (index < self.config.slow_period) {
            return null;
        }

        // Get indicators
        const ma_fast = candles.getIndicator("ma_fast") orelse return null;
        const ma_slow = candles.getIndicator("ma_slow") orelse return null;

        const prev_fast = ma_fast.values[index - 1];
        const prev_slow = ma_slow.values[index - 1];
        const curr_fast = ma_fast.values[index];
        const curr_slow = ma_slow.values[index];

        // Skip if any value is NaN
        if (prev_fast.isNaN() or prev_slow.isNaN() or curr_fast.isNaN() or curr_slow.isNaN()) {
            return null;
        }

        const current_candle = candles.get(index) orelse return null;
        const price = current_candle.close;
        const timestamp = current_candle.timestamp;

        // If holding long and death cross occurs - Exit Long
        if (position.side == .long) {
            if (prev_fast.cmp(prev_slow) != .lt and curr_fast.cmp(curr_slow) == .lt) {
                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Death Cross: Exit long position",
                    &[_]IndicatorValue{
                        .{ .name = "ma_fast", .value = curr_fast },
                        .{ .name = "ma_slow", .value = curr_slow },
                    },
                );

                const signal = try Signal.init(
                    .exit_long,
                    position.pair,
                    .sell,
                    price,
                    0.8,
                    timestamp,
                    metadata,
                );
                return signal;
            }
        }

        // If holding short and golden cross occurs - Exit Short
        if (position.side == .short) {
            if (prev_fast.cmp(prev_slow) != .gt and curr_fast.cmp(curr_slow) == .gt) {
                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Golden Cross: Exit short position",
                    &[_]IndicatorValue{
                        .{ .name = "ma_fast", .value = curr_fast },
                        .{ .name = "ma_slow", .value = curr_slow },
                    },
                );

                const signal = try Signal.init(
                    .exit_short,
                    position.pair,
                    .buy,
                    price,
                    0.8,
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
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

        const params = [_]StrategyParameter{
            .{
                .name = "fast_period",
                .description = "Fast MA period",
                .value = .{ .integer = @intCast(self.config.fast_period) },
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
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

        return .{
            .name = "Dual Moving Average Strategy",
            .version = "1.0.0",
            .author = "zigQuant",
            .description = "Classic dual MA crossover trend-following strategy",
            .strategy_type = .trend_following,
            .timeframe = .m15,
            .startup_candle_count = self.config.slow_period,
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
