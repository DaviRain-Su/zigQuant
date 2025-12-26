//! Bollinger Bands Breakout Strategy
//!
//! Breakout strategy based on Bollinger Bands expansion and price breakouts.
//! Aims to capture trending moves when price breaks out of the volatility bands.
//!
//! Strategy Logic:
//! - **Entry Long**: Price breaks above upper band (with confirmation threshold)
//! - **Entry Short**: Price breaks below lower band (with confirmation threshold)
//! - **Exit Long**: Price returns to middle band OR breaks below lower band (stop)
//! - **Exit Short**: Price returns to middle band OR breaks above upper band (stop)
//!
//! Bollinger Bands:
//! - Middle Band = SMA(period)
//! - Upper Band = Middle + (std_dev * σ)
//! - Lower Band = Middle - (std_dev * σ)
//!
//! Signal Strength:
//! - Based on breakout magnitude (0.7 - 0.95)
//! - Larger breakout → Higher strength
//!
//! Best for:
//! - Trending markets with volatility expansion
//! - Breakout scenarios
//! - Avoid in choppy/ranging markets (high false breakout rate)

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

/// Strategy configuration
pub const Config = struct {
    /// Trading pair
    pair: TradingPair,

    /// Bollinger Bands period (default: 20)
    bb_period: u32 = 20,

    /// Bollinger Bands standard deviation multiplier (default: 2.0)
    bb_std_dev: f64 = 2.0,

    /// Breakout confirmation threshold as percentage (default: 0.001 = 0.1%)
    breakout_threshold: f64 = 0.001,

    /// Enable long positions (default: true)
    enable_long: bool = true,

    /// Enable short positions (default: true)
    enable_short: bool = true,

    /// Use volume filter for breakout confirmation (default: false)
    use_volume_filter: bool = false,

    /// Volume multiplier for filter (default: 1.5x average)
    volume_multiplier: f64 = 1.5,

    /// Validate configuration
    pub fn validate(self: Config) !void {
        if (self.bb_period < 5 or self.bb_period > 100) {
            return error.InvalidBBPeriod;
        }
        if (self.bb_std_dev < 1.0 or self.bb_std_dev > 3.0) {
            return error.InvalidStdDev;
        }
        if (self.breakout_threshold < 0.0 or self.breakout_threshold > 0.05) {
            return error.InvalidThreshold;
        }
        if (self.volume_multiplier < 1.0) {
            return error.InvalidVolumeMultiplier;
        }
    }
};

// ============================================================================
// Bollinger Breakout Strategy
// ============================================================================

/// Bollinger Bands Breakout Strategy
pub const BollingerBreakoutStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    indicator_manager: IndicatorManager,
    logger: Logger,
    initialized: bool,

    /// Create a new Bollinger Breakout strategy instance
    pub fn create(allocator: std.mem.Allocator, config: Config) !*BollingerBreakoutStrategy {
        // Validate configuration
        try config.validate();

        const self = try allocator.create(BollingerBreakoutStrategy);
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
    pub fn toStrategy(self: *BollingerBreakoutStrategy) IStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Destroy strategy and free resources
    pub fn destroy(self: *BollingerBreakoutStrategy) void {
        self.indicator_manager.deinit();
        self.allocator.destroy(self);
    }

    // ========================================================================
    // Signal Strength Calculation
    // ========================================================================

    /// Calculate breakout signal strength based on magnitude
    /// Larger breakout percentage → Higher strength
    /// Range: 0.7 - 0.95
    fn calculateBreakoutStrength(price: Decimal, band: Decimal, direction: enum { long, short }) f64 {
        // Calculate breakout percentage
        const price_f = price.toFloat();
        const band_f = band.toFloat();

        const percent = if (direction == .long)
            (price_f - band_f) / band_f
        else
            (band_f - price_f) / band_f;

        // Map 0-2% breakout to 0.7-0.95 strength
        const normalized = @max(0.0, @min(1.0, percent / 0.02));
        return 0.7 + (normalized * 0.25);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn init(ptr: *anyopaque, ctx: StrategyContext) !void {
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));
        self.logger = ctx.logger;
        self.initialized = true;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));
        self.indicator_manager.deinit();
        self.initialized = false;
    }

    fn populateIndicators(ptr: *anyopaque, candles: *Candles) !void {
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));

        // Calculate Bollinger Bands
        const bb_result = try indicator_helpers.getBollingerBands(
            &self.indicator_manager,
            candles,
            self.config.bb_period,
            self.config.bb_std_dev,
        );
        defer bb_result.deinit();

        // Add indicators to candles
        try candles.addIndicatorValues("bb_upper", bb_result.upper_band);
        try candles.addIndicatorValues("bb_middle", bb_result.middle_band);
        try candles.addIndicatorValues("bb_lower", bb_result.lower_band);
    }

    fn generateEntrySignal(
        ptr: *anyopaque,
        candles: *Candles,
        index: usize,
    ) !?Signal {
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));

        // Need enough data for BB and breakout detection
        if (index < self.config.bb_period + 1) {
            return null;
        }

        // Get indicators
        const upper_band = candles.getIndicator("bb_upper") orelse return null;
        const lower_band = candles.getIndicator("bb_lower") orelse return null;

        // Get current and previous values
        const curr_upper = upper_band.values[index];
        const curr_lower = lower_band.values[index];
        const prev_upper = upper_band.values[index - 1];
        const prev_lower = lower_band.values[index - 1];

        // Skip if any band value is NaN
        if (curr_upper.isNaN() or curr_lower.isNaN()) {
            return null;
        }

        const current_candle = candles.get(index) orelse return null;
        const prev_candle = candles.get(index - 1) orelse return null;
        const curr_close = current_candle.close;
        const prev_close = prev_candle.close;
        const price = curr_close;
        const timestamp = current_candle.timestamp;

        // Calculate breakout thresholds
        const threshold_multiplier_up = Decimal.fromFloat(1.0 + self.config.breakout_threshold);
        const threshold_multiplier_down = Decimal.fromFloat(1.0 - self.config.breakout_threshold);

        const upper_threshold = curr_upper.mul(threshold_multiplier_up);
        const lower_threshold = curr_lower.mul(threshold_multiplier_down);

        // Check for upper band breakout (Long signal)
        if (self.config.enable_long) {
            const is_breakout = curr_close.cmp(upper_threshold) == .gt;
            const was_below = prev_close.cmp(prev_upper) != .gt;

            if (is_breakout and was_below) {
                // Optional: Volume confirmation
                if (self.config.use_volume_filter) {
                    if (current_candle.volume.cmp(prev_candle.volume) != .gt) {
                        return null;
                    }
                }

                const strength = calculateBreakoutStrength(curr_close, curr_upper, .long);

                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Breakout above upper Bollinger Band",
                    &[_]IndicatorValue{
                        .{ .name = "bb_upper", .value = curr_upper },
                        .{ .name = "close", .value = curr_close },
                    },
                );

                const signal = try Signal.init(
                    .entry_long,
                    self.config.pair,
                    .buy,
                    price,
                    strength,
                    timestamp,
                    metadata,
                );
                return signal;
            }
        }

        // Check for lower band breakout (Short signal)
        if (self.config.enable_short) {
            const is_breakout = curr_close.cmp(lower_threshold) == .lt;
            const was_above = prev_close.cmp(prev_lower) != .lt;

            if (is_breakout and was_above) {
                // Optional: Volume confirmation
                if (self.config.use_volume_filter) {
                    if (current_candle.volume.cmp(prev_candle.volume) != .gt) {
                        return null;
                    }
                }

                const strength = calculateBreakoutStrength(curr_close, curr_lower, .short);

                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Breakout below lower Bollinger Band",
                    &[_]IndicatorValue{
                        .{ .name = "bb_lower", .value = curr_lower },
                        .{ .name = "close", .value = curr_close },
                    },
                );

                const signal = try Signal.init(
                    .entry_short,
                    self.config.pair,
                    .sell,
                    price,
                    strength,
                    timestamp,
                    metadata,
                );
                return signal;
            }
        }

        return null;
    }

    fn generateExitSignal(
        ptr: *anyopaque,
        candles: *Candles,
        position: Position,
    ) !?Signal {
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));

        const index = candles.len() - 1;

        // Need enough data
        if (index < self.config.bb_period) {
            return null;
        }

        // Get indicators
        const upper_band = candles.getIndicator("bb_upper") orelse return null;
        const middle_band = candles.getIndicator("bb_middle") orelse return null;
        const lower_band = candles.getIndicator("bb_lower") orelse return null;

        const curr_upper = upper_band.values[index];
        const curr_middle = middle_band.values[index];
        const curr_lower = lower_band.values[index];

        // Skip if any band value is NaN
        if (curr_upper.isNaN() or curr_middle.isNaN() or curr_lower.isNaN()) {
            return null;
        }

        const current_candle = candles.get(index) orelse return null;
        const curr_close = current_candle.close;
        const price = curr_close;
        const timestamp = current_candle.timestamp;

        // Check for exit signals based on position side
        if (position.side == .long) {
            // Exit Long: Price returns to middle band
            if (curr_close.cmp(curr_middle) != .gt) {
                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Price returned to middle band - take profit",
                    &[_]IndicatorValue{
                        .{ .name = "bb_middle", .value = curr_middle },
                        .{ .name = "close", .value = curr_close },
                    },
                );

                const signal = try Signal.init(
                    .exit_long,
                    position.pair,
                    .sell,
                    price,
                    0.75,
                    timestamp,
                    metadata,
                );
                return signal;
            }

            // Exit Long: Price breaks below lower band (stop loss)
            if (curr_close.cmp(curr_lower) == .lt) {
                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Stop loss: price broke below lower band",
                    &[_]IndicatorValue{
                        .{ .name = "bb_lower", .value = curr_lower },
                        .{ .name = "close", .value = curr_close },
                    },
                );

                const signal = try Signal.init(
                    .exit_long,
                    position.pair,
                    .sell,
                    price,
                    0.95,
                    timestamp,
                    metadata,
                );
                return signal;
            }
        } else if (position.side == .short) {
            // Exit Short: Price returns to middle band
            if (curr_close.cmp(curr_middle) != .lt) {
                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Price returned to middle band - take profit",
                    &[_]IndicatorValue{
                        .{ .name = "bb_middle", .value = curr_middle },
                        .{ .name = "close", .value = curr_close },
                    },
                );

                const signal = try Signal.init(
                    .exit_short,
                    position.pair,
                    .buy,
                    price,
                    0.75,
                    timestamp,
                    metadata,
                );
                return signal;
            }

            // Exit Short: Price breaks above upper band (stop loss)
            if (curr_close.cmp(curr_upper) == .gt) {
                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Stop loss: price broke above upper band",
                    &[_]IndicatorValue{
                        .{ .name = "bb_upper", .value = curr_upper },
                        .{ .name = "close", .value = curr_close },
                    },
                );

                const signal = try Signal.init(
                    .exit_short,
                    position.pair,
                    .buy,
                    price,
                    0.95,
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
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));

        const params = [_]StrategyParameter{
            .{
                .name = "bb_period",
                .description = "Bollinger Bands period",
                .value = .{ .integer = @intCast(self.config.bb_period) },
            },
            .{
                .name = "bb_std_dev",
                .description = "Bollinger Bands standard deviation multiplier",
                .value = .{ .decimal = Decimal.fromFloat(self.config.bb_std_dev) },
            },
            .{
                .name = "breakout_threshold",
                .description = "Breakout confirmation threshold percentage",
                .value = .{ .decimal = Decimal.fromFloat(self.config.breakout_threshold) },
            },
            .{
                .name = "enable_long",
                .description = "Enable long positions",
                .value = .{ .boolean = self.config.enable_long },
            },
            .{
                .name = "enable_short",
                .description = "Enable short positions",
                .value = .{ .boolean = self.config.enable_short },
            },
            .{
                .name = "use_volume_filter",
                .description = "Use volume filter for breakout confirmation",
                .value = .{ .boolean = self.config.use_volume_filter },
            },
            .{
                .name = "volume_multiplier",
                .description = "Volume multiplier for filter",
                .value = .{ .decimal = Decimal.fromFloat(self.config.volume_multiplier) },
            },
        };

        return &params;
    }

    fn getMetadata(ptr: *anyopaque) StrategyMetadata {
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));

        const roi_targets = [_]@import("../types.zig").ROITarget{
            .{ .time_minutes = 0, .profit_ratio = Decimal.fromFloat(0.05) },   // 5% immediate
            .{ .time_minutes = 30, .profit_ratio = Decimal.fromFloat(0.03) },  // 3% after 30min
            .{ .time_minutes = 90, .profit_ratio = Decimal.fromFloat(0.015) }, // 1.5% after 90min
        };

        return .{
            .name = "Bollinger Bands Breakout Strategy",
            .version = "1.0.0",
            .author = "zigQuant",
            .description = "Breakout strategy based on Bollinger Bands volatility expansion",
            .strategy_type = .breakout,
            .timeframe = .m15,
            .startup_candle_count = self.config.bb_period + 1,
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

/// Helper to create test candles with specific prices
fn createTestCandles(allocator: std.mem.Allocator, prices: []const f64) !Candles {
    const candles_data = try allocator.alloc(@import("../../root.zig").Candle, prices.len);
    // Note: candles_data will be freed by candles.deinit()

    for (prices, 0..) |price, i| {
        const dec_price = Decimal.fromFloat(price);
        candles_data[i] = .{
            .timestamp = .{ .millis = @intCast(i * 3600000) }, // 1 hour intervals
            .open = dec_price,
            .high = dec_price,
            .low = dec_price,
            .close = dec_price,
            .volume = Decimal.fromInt(100),
        };
    }

    return Candles.initWithCandles(
        allocator,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        candles_data,
    );
}

test "BollingerBreakout: invalid parameters" {
    const testing = std.testing;

    // Invalid BB period (< 5)
    try testing.expectError(
        error.InvalidBBPeriod,
        BollingerBreakoutStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .bb_period = 4,
        }),
    );

    // Invalid BB period (> 100)
    try testing.expectError(
        error.InvalidBBPeriod,
        BollingerBreakoutStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .bb_period = 101,
        }),
    );

    // Invalid std_dev (< 1.0)
    try testing.expectError(
        error.InvalidStdDev,
        BollingerBreakoutStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .bb_std_dev = 0.5,
        }),
    );

    // Invalid std_dev (> 3.0)
    try testing.expectError(
        error.InvalidStdDev,
        BollingerBreakoutStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .bb_std_dev = 3.5,
        }),
    );

    // Invalid threshold (< 0)
    try testing.expectError(
        error.InvalidThreshold,
        BollingerBreakoutStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .breakout_threshold = -0.01,
        }),
    );

    // Invalid threshold (> 0.05)
    try testing.expectError(
        error.InvalidThreshold,
        BollingerBreakoutStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .breakout_threshold = 0.06,
        }),
    );

    // Invalid volume multiplier (< 1.0)
    try testing.expectError(
        error.InvalidVolumeMultiplier,
        BollingerBreakoutStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .volume_multiplier = 0.5,
        }),
    );
}

test "BollingerBreakout: creation and destruction" {
    const testing = std.testing;

    const strategy = try BollingerBreakoutStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .bb_period = 20,
        .bb_std_dev = 2.0,
    });
    defer strategy.destroy();

    try testing.expect(!strategy.initialized);
}

test "BollingerBreakout: interface methods" {
    const testing = std.testing;

    const strategy = try BollingerBreakoutStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .bb_period = 10,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();

    // Test init/deinit
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const WriterType = @TypeOf(fbs.writer());
    const ConsoleWriter = @import("../../root.zig").ConsoleWriter;
    var console = ConsoleWriter(WriterType).initWithColors(testing.allocator, fbs.writer(), false);
    defer console.deinit();

    var logger = Logger.init(testing.allocator, console.writer(), .debug);
    defer logger.deinit();

    const ctx = StrategyContext{
        .allocator = testing.allocator,
        .logger = logger,
    };

    try istrategy.init(ctx);
    try testing.expect(strategy.initialized);

    istrategy.deinit();
    try testing.expect(!strategy.initialized);
}

test "BollingerBreakout: signal strength calculation" {
    const testing = std.testing;

    // Test small breakout (0.5% = price 100.5 vs band 100)
    const price_small = Decimal.fromFloat(100.5);
    const band = Decimal.fromFloat(100.0);
    const strength_small = BollingerBreakoutStrategy.calculateBreakoutStrength(price_small, band, .long);
    // 0.5% breakout: normalized = 0.5/2.0 = 0.25, strength = 0.7 + 0.25*0.25 = 0.7625
    try testing.expect(strength_small >= 0.7 and strength_small < 0.8);

    // Test large breakout (2% = price 102 vs band 100)
    const price_large = Decimal.fromFloat(102.0);
    const strength_large = BollingerBreakoutStrategy.calculateBreakoutStrength(price_large, band, .long);
    // 2% breakout: normalized = 2.0/2.0 = 1.0, strength = 0.7 + 1.0*0.25 = 0.95
    try testing.expect(strength_large >= 0.9 and strength_large <= 0.95);

    // Verify: larger breakout = higher strength
    try testing.expect(strength_large > strength_small);
}

test "BollingerBreakout: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const strategy = try BollingerBreakoutStrategy.create(allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .bb_period = 10,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const WriterType = @TypeOf(fbs.writer());
    const ConsoleWriter = @import("../../root.zig").ConsoleWriter;
    var console = ConsoleWriter(WriterType).initWithColors(allocator, fbs.writer(), false);
    defer console.deinit();

    var logger = Logger.init(allocator, console.writer(), .debug);
    defer logger.deinit();

    const ctx = StrategyContext{
        .allocator = allocator,
        .logger = logger,
    };

    try istrategy.init(ctx);

    var candles = try createTestCandles(allocator, &[_]f64{
        100, 101, 102, 103, 104,
        105, 106, 107, 108, 109,
        110, 112, 115, 120, 125,
        122, 119, 116, 113, 110,
    });
    defer candles.deinit();

    // Populate indicators
    try istrategy.populateIndicators(&candles);

    // Generate entry signals
    for (11..candles.len()) |i| {
        const signal = try istrategy.generateEntrySignal(&candles, i);
        if (signal) |sig| {
            sig.deinit();
        }
    }
}
