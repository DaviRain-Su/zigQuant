//! RSI Mean Reversion Strategy
//!
//! Mean reversion strategy based on RSI overbought/oversold levels.
//! Aims to profit from price reversals when RSI reaches extreme values.
//!
//! Strategy Logic:
//! - **Entry Long**: RSI < oversold_threshold (default: 30) AND RSI starts bouncing (RSI[i] > RSI[i-1])
//! - **Entry Short**: RSI > overbought_threshold (default: 70) AND RSI starts falling (RSI[i] < RSI[i-1])
//! - **Exit Long**: RSI returns to exit_rsi_level (default: 50) OR RSI enters overbought zone
//! - **Exit Short**: RSI returns to exit_rsi_level OR RSI enters oversold zone
//!
//! Signal Strength:
//! - Dynamically calculated based on RSI extreme level
//! - Range: 0.6 - 0.9
//! - More extreme RSI → Higher signal strength
//!
//! Best for:
//! - Range-bound markets
//! - Sideways/choppy conditions
//! - Avoid in strong trending markets

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

    /// RSI period (default: 14)
    rsi_period: u32 = 14,

    /// Oversold threshold - entry long when RSI below this (default: 30)
    oversold_threshold: u32 = 30,

    /// Overbought threshold - entry short when RSI above this (default: 70)
    overbought_threshold: u32 = 70,

    /// Exit RSI level - take profit when RSI returns to this level (default: 50)
    exit_rsi_level: u32 = 50,

    /// Enable long positions (default: true)
    enable_long: bool = true,

    /// Enable short positions (default: true)
    enable_short: bool = true,

    /// Validate configuration
    pub fn validate(self: Config) !void {
        if (self.rsi_period < 2 or self.rsi_period > 50) {
            return error.InvalidRSIPeriod;
        }
        if (self.oversold_threshold >= 50) {
            return error.InvalidOversoldThreshold;
        }
        if (self.overbought_threshold <= 50) {
            return error.InvalidOverboughtThreshold;
        }
        if (self.exit_rsi_level <= self.oversold_threshold or
            self.exit_rsi_level >= self.overbought_threshold)
        {
            return error.InvalidExitLevel;
        }
    }
};

// ============================================================================
// RSI Mean Reversion Strategy
// ============================================================================

/// RSI Mean Reversion Strategy
pub const RSIMeanReversionStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    indicator_manager: IndicatorManager,
    logger: Logger,
    initialized: bool,

    /// Create a new RSI mean reversion strategy instance
    pub fn create(allocator: std.mem.Allocator, config: Config) !*RSIMeanReversionStrategy {
        // Validate configuration
        try config.validate();

        const self = try allocator.create(RSIMeanReversionStrategy);
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
    pub fn toStrategy(self: *RSIMeanReversionStrategy) IStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Destroy strategy and free resources
    pub fn destroy(self: *RSIMeanReversionStrategy) void {
        self.indicator_manager.deinit();
        self.allocator.destroy(self);
    }

    // ========================================================================
    // Signal Strength Calculation
    // ========================================================================

    /// Calculate signal strength for long entry based on RSI level
    /// Lower RSI (more oversold) → Higher strength
    /// Range: 0.6 - 0.9
    fn calculateLongStrength(self: *const RSIMeanReversionStrategy, rsi: Decimal) f64 {
        const rsi_float = rsi.toFloat();
        const threshold = @as(f64, @floatFromInt(self.config.oversold_threshold));

        // Normalize: RSI 0-threshold → 1.0-0.0
        const normalized = @max(0.0, @min(1.0, 1.0 - (rsi_float / threshold)));

        // Map to 0.6-0.9 range
        return 0.6 + (normalized * 0.3);
    }

    /// Calculate signal strength for short entry based on RSI level
    /// Higher RSI (more overbought) → Higher strength
    /// Range: 0.6 - 0.9
    fn calculateShortStrength(self: *const RSIMeanReversionStrategy, rsi: Decimal) f64 {
        const rsi_float = rsi.toFloat();
        const threshold = @as(f64, @floatFromInt(self.config.overbought_threshold));

        // Normalize: threshold-100 → 0.0-1.0
        const normalized = @max(0.0, @min(1.0, (rsi_float - threshold) / (100.0 - threshold)));

        // Map to 0.6-0.9 range
        return 0.6 + (normalized * 0.3);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn init(ptr: *anyopaque, ctx: StrategyContext) !void {
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));
        self.logger = ctx.logger;
        self.initialized = true;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));
        self.initialized = false;
    }

    fn populateIndicators(ptr: *anyopaque, candles: *Candles) !void {
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));

        // Calculate RSI
        const rsi_values = try indicator_helpers.getRSI(
            &self.indicator_manager,
            candles,
            self.config.rsi_period,
        );

        // Add indicator to candles
        try candles.addIndicatorValues("rsi", rsi_values);
    }

    fn generateEntrySignal(
        ptr: *anyopaque,
        candles: *Candles,
        index: usize,
    ) !?Signal {
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));

        // Need enough data for RSI and bounce detection
        if (index < self.config.rsi_period + 1) {
            return null;
        }

        // Get RSI indicator
        const rsi_values = candles.getIndicator("rsi") orelse return null;

        // Get current and previous RSI values
        const curr_rsi = rsi_values.values[index];
        const prev_rsi = rsi_values.values[index - 1];

        // Skip if RSI values are NaN
        if (curr_rsi.isNaN() or prev_rsi.isNaN()) {
            return null;
        }

        const current_candle = candles.get(index) orelse return null;
        const price = current_candle.close;
        const timestamp = current_candle.timestamp;

        // Convert thresholds to Decimal for comparison
        const oversold = Decimal.fromInt(@as(i64, @intCast(self.config.oversold_threshold)));
        const overbought = Decimal.fromInt(@as(i64, @intCast(self.config.overbought_threshold)));

        // Entry Long: RSI < oversold AND RSI bouncing (curr > prev)
        if (self.config.enable_long and
            curr_rsi.cmp(oversold) == .lt and
            curr_rsi.cmp(prev_rsi) == .gt)
        {
            const strength = self.calculateLongStrength(curr_rsi);

            const metadata = try SignalMetadata.init(
                self.allocator,
                "RSI oversold bounce detected",
                &[_]IndicatorValue{
                    .{ .name = "rsi", .value = curr_rsi },
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

        // Entry Short: RSI > overbought AND RSI falling (curr < prev)
        if (self.config.enable_short and
            curr_rsi.cmp(overbought) == .gt and
            curr_rsi.cmp(prev_rsi) == .lt)
        {
            const strength = self.calculateShortStrength(curr_rsi);

            const metadata = try SignalMetadata.init(
                self.allocator,
                "RSI overbought pullback detected",
                &[_]IndicatorValue{
                    .{ .name = "rsi", .value = curr_rsi },
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

        return null;
    }

    fn generateExitSignal(
        ptr: *anyopaque,
        candles: *Candles,
        position: Position,
    ) !?Signal {
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));

        const index = candles.len() - 1;

        // Need enough data
        if (index < self.config.rsi_period) {
            return null;
        }

        // Get RSI indicator
        const rsi_values = candles.getIndicator("rsi") orelse return null;
        const curr_rsi = rsi_values.values[index];

        // Skip if RSI is NaN
        if (curr_rsi.isNaN()) {
            return null;
        }

        const current_candle = candles.get(index) orelse return null;
        const price = current_candle.close;
        const timestamp = current_candle.timestamp;

        // Convert thresholds to Decimal
        const oversold = Decimal.fromInt(@as(i64, @intCast(self.config.oversold_threshold)));
        const overbought = Decimal.fromInt(@as(i64, @intCast(self.config.overbought_threshold)));
        const exit_level = Decimal.fromInt(@as(i64, @intCast(self.config.exit_rsi_level)));

        // Check for exit signals based on position side
        if (position.side == .long) {
            // Exit Long: RSI returns to neutral zone OR enters overbought
            if (curr_rsi.cmp(exit_level) != .lt) {
                const reason = if (curr_rsi.cmp(overbought) != .lt)
                    "RSI entered overbought zone - reversal risk"
                else
                    "RSI returned to neutral zone - take profit";

                const exit_strength: f64 = if (curr_rsi.cmp(overbought) != .lt) 0.9 else 0.7;

                const metadata = try SignalMetadata.init(
                    self.allocator,
                    reason,
                    &[_]IndicatorValue{
                        .{ .name = "rsi", .value = curr_rsi },
                    },
                );

                const signal = try Signal.init(
                    .exit_long,
                    position.pair,
                    .sell,
                    price,
                    exit_strength,
                    timestamp,
                    metadata,
                );
                return signal;
            }
        } else if (position.side == .short) {
            // Exit Short: RSI returns to neutral zone OR enters oversold
            if (curr_rsi.cmp(exit_level) != .gt) {
                const reason = if (curr_rsi.cmp(oversold) != .gt)
                    "RSI entered oversold zone - reversal risk"
                else
                    "RSI returned to neutral zone - take profit";

                const exit_strength: f64 = if (curr_rsi.cmp(oversold) != .gt) 0.9 else 0.7;

                const metadata = try SignalMetadata.init(
                    self.allocator,
                    reason,
                    &[_]IndicatorValue{
                        .{ .name = "rsi", .value = curr_rsi },
                    },
                );

                const signal = try Signal.init(
                    .exit_short,
                    position.pair,
                    .buy,
                    price,
                    exit_strength,
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
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));

        const params = [_]StrategyParameter{
            .{
                .name = "rsi_period",
                .description = "RSI period",
                .value = .{ .integer = @intCast(self.config.rsi_period) },
            },
            .{
                .name = "oversold_threshold",
                .description = "Oversold threshold for long entry",
                .value = .{ .integer = @intCast(self.config.oversold_threshold) },
            },
            .{
                .name = "overbought_threshold",
                .description = "Overbought threshold for short entry",
                .value = .{ .integer = @intCast(self.config.overbought_threshold) },
            },
            .{
                .name = "exit_rsi_level",
                .description = "Exit RSI level for take profit",
                .value = .{ .integer = @intCast(self.config.exit_rsi_level) },
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
        };

        return &params;
    }

    fn getMetadata(ptr: *anyopaque) StrategyMetadata {
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));

        return .{
            .name = "RSI Mean Reversion Strategy",
            .version = "1.0.0",
            .author = "zigQuant",
            .description = "Mean reversion strategy using RSI overbought/oversold levels",
            .strategy_type = .mean_reversion,
            .timeframe = .m15,
            .startup_candle_count = self.config.rsi_period + 1,
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

test "RSIMeanReversion: invalid parameters" {
    const testing = std.testing;

    // Invalid RSI period (< 2)
    try testing.expectError(
        error.InvalidRSIPeriod,
        RSIMeanReversionStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .rsi_period = 1,
        }),
    );

    // Invalid RSI period (> 50)
    try testing.expectError(
        error.InvalidRSIPeriod,
        RSIMeanReversionStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .rsi_period = 51,
        }),
    );

    // Invalid oversold threshold (>= 50)
    try testing.expectError(
        error.InvalidOversoldThreshold,
        RSIMeanReversionStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .oversold_threshold = 50,
        }),
    );

    // Invalid overbought threshold (<= 50)
    try testing.expectError(
        error.InvalidOverboughtThreshold,
        RSIMeanReversionStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .overbought_threshold = 50,
        }),
    );

    // Invalid exit level (too low)
    try testing.expectError(
        error.InvalidExitLevel,
        RSIMeanReversionStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .exit_rsi_level = 25,
        }),
    );

    // Invalid exit level (too high)
    try testing.expectError(
        error.InvalidExitLevel,
        RSIMeanReversionStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .exit_rsi_level = 75,
        }),
    );
}

test "RSIMeanReversion: creation and destruction" {
    const testing = std.testing;

    const strategy = try RSIMeanReversionStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .rsi_period = 14,
        .oversold_threshold = 30,
        .overbought_threshold = 70,
    });
    defer strategy.destroy();

    try testing.expect(!strategy.initialized);
}

test "RSIMeanReversion: interface methods" {
    const testing = std.testing;

    const strategy = try RSIMeanReversionStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .rsi_period = 6,
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

test "RSIMeanReversion: signal strength calculation" {
    const testing = std.testing;

    const strategy = try RSIMeanReversionStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .rsi_period = 14,
        .oversold_threshold = 30,
        .overbought_threshold = 70,
    });
    defer strategy.destroy();

    // Test long strength (lower RSI = higher strength)
    const rsi_20 = Decimal.fromFloat(20.0);
    const strength_20 = strategy.calculateLongStrength(rsi_20);
    try testing.expect(strength_20 >= 0.7 and strength_20 <= 0.9);

    const rsi_30 = Decimal.fromFloat(30.0);
    const strength_30 = strategy.calculateLongStrength(rsi_30);
    try testing.expect(strength_30 >= 0.6 and strength_30 < 0.7);

    // Verify: lower RSI = higher strength
    try testing.expect(strength_20 > strength_30);

    // Test short strength (higher RSI = higher strength)
    const rsi_70 = Decimal.fromFloat(70.0);
    const strength_70 = strategy.calculateShortStrength(rsi_70);
    try testing.expect(strength_70 >= 0.6 and strength_70 < 0.7);

    const rsi_85 = Decimal.fromFloat(85.0);
    const strength_85 = strategy.calculateShortStrength(rsi_85);
    try testing.expect(strength_85 >= 0.7 and strength_85 <= 0.9);

    // Verify: higher RSI = higher strength
    try testing.expect(strength_85 > strength_70);
}

test "RSIMeanReversion: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const strategy = try RSIMeanReversionStrategy.create(allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .rsi_period = 6,
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
        100, 98, 95, 92, 88,
        85, 83, 82, 83, 85,
        88, 90, 92, 95, 98,
        100, 102, 105, 108, 110,
    });
    defer candles.deinit();

    // Populate indicators
    try istrategy.populateIndicators(&candles);

    // Generate entry signals
    for (7..candles.len()) |i| {
        const signal = try istrategy.generateEntrySignal(&candles, i);
        if (signal) |sig| {
            sig.deinit();
        }
    }
}
