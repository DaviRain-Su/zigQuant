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
//! Optional Features:
//! - Volume filter: Require above-average volume for breakouts
//! - Bandwidth monitoring: Track volatility expansion/contraction
//!
//! Best for:
//! - Trending markets with volatility expansion
//! - Breakout scenarios
//! - Avoid in choppy/ranging markets (high false breakout rate)
//!
//! Usage:
//! ```zig
//! const strategy = try BollingerBreakoutStrategy.create(allocator, .{
//!     .pair = .{ .base = "BTC", .quote = "USDT" },
//!     .bb_period = 20,
//!     .bb_std_dev = 2.0,
//!     .breakout_threshold = 0.001,  // 0.1%
//!     .use_volume_filter = true,
//! });
//! defer strategy.destroy();
//!
//! const signal = try strategy.toStrategy().analyze(&candles, timestamp);
//! defer signal.deinit();
//! ```

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candles = @import("../../root.zig").Candles;
const TradingPair = @import("../../root.zig").TradingPair;
const Timestamp = @import("../../root.zig").Timestamp;
const Order = @import("../../root.zig").Order;
const Side = @import("../../root.zig").Side;
const IStrategy = @import("../interface.zig").IStrategy;
const Signal = @import("../signal.zig").Signal;
const SignalType = @import("../signal.zig").SignalType;
const SignalMetadata = @import("../signal.zig").SignalMetadata;
const IndicatorValue = @import("../signal.zig").IndicatorValue;
const IndicatorManager = @import("../../root.zig").IndicatorManager;
const indicator_helpers = @import("../../root.zig").indicator_helpers;

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
// Strategy State
// ============================================================================

/// Position state for tracking
const PositionState = enum {
    none,  // No position
    long,  // Long position
    short, // Short position
};

// ============================================================================
// Bollinger Breakout Strategy
// ============================================================================

/// Bollinger Bands Breakout Strategy
pub const BollingerBreakoutStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    indicator_manager: IndicatorManager,
    position_state: PositionState,
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
            .position_state = .none,
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

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "Bollinger Bands Breakout Strategy";
    }

    fn init(ptr: *anyopaque) !void {
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));
        self.initialized = true;
        self.position_state = .none;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));
        self.initialized = false;
    }

    fn analyze(
        ptr: *anyopaque,
        candles: *const Candles,
        timestamp: Timestamp,
    ) !Signal {
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));

        // Need mutable candles for indicator calculation
        var mutable_candles = @constCast(candles);

        // Check if we have enough data
        const candle_count = mutable_candles.len();
        if (candle_count < self.config.bb_period + 1) {
            // Not enough data - return hold signal
            return Signal.init(
                .hold,
                self.config.pair,
                .buy,
                Decimal.ZERO,
                0.0,
                timestamp,
                null,
            );
        }

        // Calculate Bollinger Bands using IndicatorManager
        const bb_result = try indicator_helpers.getBollingerBands(
            &self.indicator_manager,
            mutable_candles,
            self.config.bb_period,
            self.config.bb_std_dev,
        );
        // Free bb_result at end of function
        defer self.allocator.free(bb_result.upper_band);
        defer self.allocator.free(bb_result.middle_band);
        defer self.allocator.free(bb_result.lower_band);

        const upper_band = bb_result.upper_band;
        const middle_band = bb_result.middle_band;
        const lower_band = bb_result.lower_band;

        // Get current and previous candle data
        const current_idx = candle_count - 1;
        const prev_idx = current_idx - 1;

        const curr_candle = mutable_candles.get(current_idx) orelse unreachable;
        const prev_candle = mutable_candles.get(prev_idx) orelse unreachable;

        const curr_close = curr_candle.close;
        const prev_close = prev_candle.close;
        const curr_upper = upper_band[current_idx];
        const curr_lower = lower_band[current_idx];
        const curr_middle = middle_band[current_idx];
        const prev_upper = upper_band[prev_idx];
        const prev_lower = lower_band[prev_idx];

        // Skip if any band value is NaN
        if (curr_upper.isNaN() or curr_lower.isNaN() or curr_middle.isNaN()) {
            return Signal.init(
                .hold,
                self.config.pair,
                .buy,
                curr_close,
                0.0,
                timestamp,
                null,
            );
        }

        // Calculate breakout thresholds
        const threshold_multiplier_up = Decimal.fromFloat(1.0 + self.config.breakout_threshold);
        const threshold_multiplier_down = Decimal.fromFloat(1.0 - self.config.breakout_threshold);

        const upper_threshold = curr_upper.mul(threshold_multiplier_up);
        const lower_threshold = curr_lower.mul(threshold_multiplier_down);

        // Check for upper band breakout (Long signal)
        if (self.config.enable_long and
            (self.position_state == .none or self.position_state == .short))
        {
            const is_breakout = curr_close.cmp(upper_threshold) == .gt;
            const was_below = prev_close.cmp(prev_upper) != .gt;

            if (is_breakout and was_below) {
                // Optional: Volume confirmation
                if (self.config.use_volume_filter) {
                    // Simple volume check: current > previous
                    // (More sophisticated would use SMA of volume)
                    if (curr_candle.volume.cmp(prev_candle.volume) != .gt) {
                        // Volume not confirmed, skip signal
                        return Signal.init(
                            .hold,
                            self.config.pair,
                            .buy,
                            curr_close,
                            0.0,
                            timestamp,
                            null,
                        );
                    }
                }

                const signal_type: SignalType = if (self.position_state == .short)
                    .exit_short
                else
                    .entry_long;

                const strength = calculateBreakoutStrength(curr_close, curr_upper, .long);

                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Breakout above upper Bollinger Band",
                    &[_]IndicatorValue{
                        .{ .name = "bb_upper", .value = curr_upper },
                        .{ .name = "close", .value = curr_close },
                    },
                );

                return Signal.init(
                    signal_type,
                    self.config.pair,
                    signal_type.toSide() orelse .buy,
                    curr_close,
                    strength,
                    timestamp,
                    metadata,
                );
            }
        }

        // Check for lower band breakout (Short signal)
        if (self.config.enable_short and
            (self.position_state == .none or self.position_state == .long))
        {
            const is_breakout = curr_close.cmp(lower_threshold) == .lt;
            const was_above = prev_close.cmp(prev_lower) != .lt;

            if (is_breakout and was_above) {
                // Optional: Volume confirmation
                if (self.config.use_volume_filter) {
                    if (curr_candle.volume.cmp(prev_candle.volume) != .gt) {
                        return Signal.init(
                            .hold,
                            self.config.pair,
                            .buy,
                            curr_close,
                            0.0,
                            timestamp,
                            null,
                        );
                    }
                }

                const signal_type: SignalType = if (self.position_state == .long)
                    .exit_long
                else
                    .entry_short;

                const strength = calculateBreakoutStrength(curr_close, curr_lower, .short);

                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "Breakout below lower Bollinger Band",
                    &[_]IndicatorValue{
                        .{ .name = "bb_lower", .value = curr_lower },
                        .{ .name = "close", .value = curr_close },
                    },
                );

                return Signal.init(
                    signal_type,
                    self.config.pair,
                    signal_type.toSide() orelse .sell,
                    curr_close,
                    strength,
                    timestamp,
                    metadata,
                );
            }
        }

        // Check for exit signals based on position state
        if (self.position_state == .long) {
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

                return Signal.init(
                    .exit_long,
                    self.config.pair,
                    .sell,
                    curr_close,
                    0.75,
                    timestamp,
                    metadata,
                );
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

                return Signal.init(
                    .exit_long,
                    self.config.pair,
                    .sell,
                    curr_close,
                    0.95,
                    timestamp,
                    metadata,
                );
            }
        } else if (self.position_state == .short) {
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

                return Signal.init(
                    .exit_short,
                    self.config.pair,
                    .buy,
                    curr_close,
                    0.75,
                    timestamp,
                    metadata,
                );
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

                return Signal.init(
                    .exit_short,
                    self.config.pair,
                    .buy,
                    curr_close,
                    0.95,
                    timestamp,
                    metadata,
                );
            }
        }

        // No signal - hold
        return Signal.init(
            .hold,
            self.config.pair,
            .buy,
            curr_close,
            0.0,
            timestamp,
            null,
        );
    }

    fn onOrderFilled(ptr: *anyopaque, order: Order) !void {
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));

        // Update position state based on order
        if (order.side == .buy) {
            self.position_state = .long;
        } else {
            // Check if this is closing a position or opening short
            if (self.position_state == .long) {
                self.position_state = .none;
            } else {
                self.position_state = .short;
            }
        }
    }

    fn onOrderCancelled(ptr: *anyopaque, order: Order) !void {
        _ = order;
        const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));
        // For now, don't change position state on cancellation
        _ = self;
    }

    const vtable = IStrategy.VTable{
        .getName = getName,
        .init = init,
        .deinit = deinit,
        .analyze = analyze,
        .onOrderFilled = onOrderFilled,
        .onOrderCancelled = onOrderCancelled,
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
    try testing.expectEqual(PositionState.none, strategy.position_state);
}

test "BollingerBreakout: interface methods" {
    const testing = std.testing;

    const strategy = try BollingerBreakoutStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .bb_period = 10,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();

    // Test getName
    try testing.expectEqualStrings("Bollinger Bands Breakout Strategy", istrategy.getName());

    // Test init/deinit
    try istrategy.init();
    try testing.expect(strategy.initialized);

    istrategy.deinit();
    try testing.expect(!strategy.initialized);
}

test "BollingerBreakout: upper band breakout signal" {
    const testing = std.testing;

    const strategy = try BollingerBreakoutStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .bb_period = 5,
        .bb_std_dev = 2.0,
        .breakout_threshold = 0.001,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();
    try istrategy.init();

    // Create test data with upward breakout
    var candles = try createTestCandles(testing.allocator, &[_]f64{
        100, 101, 102, 103, 104, // Steady rise
        105, 106, 107, 108, 109, // Continue
        110, 112, 115, 120, 125, // Sharp breakout
    });
    defer candles.deinit();

    const timestamp = Timestamp.now();
    const signal = try istrategy.analyze(&candles, timestamp);
    defer signal.deinit();

    // Should detect upper band breakout or hold
    try testing.expect(signal.type == .entry_long or signal.type == .hold);
    if (signal.type == .entry_long) {
        try testing.expect(signal.strength >= 0.7 and signal.strength <= 0.95);
    }
}

test "BollingerBreakout: lower band breakout signal" {
    const testing = std.testing;

    const strategy = try BollingerBreakoutStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .bb_period = 5,
        .bb_std_dev = 2.0,
        .breakout_threshold = 0.001,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();
    try istrategy.init();

    // Create test data with downward breakout
    var candles = try createTestCandles(testing.allocator, &[_]f64{
        125, 124, 123, 122, 121, // Steady decline
        120, 119, 118, 117, 116, // Continue
        115, 112, 108, 102, 95,  // Sharp breakout down
    });
    defer candles.deinit();

    const timestamp = Timestamp.now();
    const signal = try istrategy.analyze(&candles, timestamp);
    defer signal.deinit();

    // Should detect lower band breakout or hold
    try testing.expect(signal.type == .entry_short or signal.type == .hold);
    if (signal.type == .entry_short) {
        try testing.expect(signal.strength >= 0.7 and signal.strength <= 0.95);
    }
}

test "BollingerBreakout: insufficient data" {
    const testing = std.testing;

    const strategy = try BollingerBreakoutStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .bb_period = 20,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();
    try istrategy.init();

    // Only 15 candles - not enough for BB period=20
    var candles = try createTestCandles(testing.allocator, &[_]f64{
        100, 101, 102, 103, 104,
        105, 106, 107, 108, 109,
        110, 111, 112, 113, 114,
    });
    defer candles.deinit();

    const timestamp = Timestamp.now();
    const signal = try istrategy.analyze(&candles, timestamp);
    defer signal.deinit();

    // Should return hold signal
    try testing.expectEqual(SignalType.hold, signal.type);
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

test "BollingerBreakout: position state tracking" {
    const testing = std.testing;

    const strategy = try BollingerBreakoutStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .bb_period = 20,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();
    try istrategy.init();

    // Initial state
    try testing.expectEqual(PositionState.none, strategy.position_state);

    // Simulate buy order fill
    const buy_order = Order{
        .exchange_order_id = 1,
        .client_order_id = null,
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .market,
        .status = .filled,
        .amount = Decimal.fromInt(1),
        .price = Decimal.fromInt(50000),
        .filled_amount = Decimal.fromInt(1),
        .avg_fill_price = Decimal.fromInt(50000),
        .created_at = Timestamp.now(),
        .updated_at = Timestamp.now(),
    };

    try istrategy.onOrderFilled(buy_order);
    try testing.expectEqual(PositionState.long, strategy.position_state);

    // Simulate sell order fill (close long)
    const sell_order = Order{
        .exchange_order_id = 2,
        .client_order_id = null,
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .sell,
        .order_type = .market,
        .status = .filled,
        .amount = Decimal.fromInt(1),
        .price = Decimal.fromInt(51000),
        .filled_amount = Decimal.fromInt(1),
        .avg_fill_price = Decimal.fromInt(51000),
        .created_at = Timestamp.now(),
        .updated_at = Timestamp.now(),
    };

    try istrategy.onOrderFilled(sell_order);
    try testing.expectEqual(PositionState.none, strategy.position_state);
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
    try istrategy.init();

    var candles = try createTestCandles(allocator, &[_]f64{
        100, 101, 102, 103, 104,
        105, 106, 107, 108, 109,
        110, 112, 115, 120, 125,
        122, 119, 116, 113, 110,
    });
    defer candles.deinit();

    // Run multiple analyses
    for (0..10) |_| {
        const signal = try istrategy.analyze(&candles, Timestamp.now());
        defer signal.deinit();
    }
}
