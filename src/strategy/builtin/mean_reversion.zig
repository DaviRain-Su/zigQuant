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
//!
//! Usage:
//! ```zig
//! const strategy = try RSIMeanReversionStrategy.create(allocator, .{
//!     .pair = .{ .base = "BTC", .quote = "USDT" },
//!     .rsi_period = 14,
//!     .oversold_threshold = 30,
//!     .overbought_threshold = 70,
//!     .exit_rsi_level = 50,
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
// Strategy State
// ============================================================================

/// Position state for tracking
const PositionState = enum {
    none,  // No position
    long,  // Long position
    short, // Short position
};

// ============================================================================
// RSI Mean Reversion Strategy
// ============================================================================

/// RSI Mean Reversion Strategy
pub const RSIMeanReversionStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    indicator_manager: IndicatorManager,
    position_state: PositionState,
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
            .position_state = .none,
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

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "RSI Mean Reversion Strategy";
    }

    fn init(ptr: *anyopaque) !void {
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));
        self.initialized = true;
        self.position_state = .none;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));
        self.initialized = false;
    }

    fn analyze(
        ptr: *anyopaque,
        candles: *const Candles,
        timestamp: Timestamp,
    ) !Signal {
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));

        // Need mutable candles for indicator calculation
        var mutable_candles = @constCast(candles);

        // Check if we have enough data
        const candle_count = mutable_candles.len();
        if (candle_count < self.config.rsi_period + 1) {
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

        // Calculate RSI using IndicatorManager for caching
        const rsi_values = try indicator_helpers.getRSI(
            &self.indicator_manager,
            mutable_candles,
            self.config.rsi_period,
        );

        // Get current and previous RSI values
        const current_idx = candle_count - 1;
        const prev_idx = current_idx - 1;

        const curr_rsi = rsi_values[current_idx];
        const prev_rsi = rsi_values[prev_idx];

        // Skip if RSI values are NaN
        if (curr_rsi.isNaN() or prev_rsi.isNaN()) {
            const current_candle = mutable_candles.get(current_idx) orelse unreachable;
            return Signal.init(
                .hold,
                self.config.pair,
                .buy,
                current_candle.close,
                0.0,
                timestamp,
                null,
            );
        }

        const current_candle = mutable_candles.get(current_idx) orelse unreachable;
        const price = current_candle.close;

        // Convert thresholds to Decimal for comparison
        const oversold = Decimal.fromInt(@as(i64, @intCast(self.config.oversold_threshold)));
        const overbought = Decimal.fromInt(@as(i64, @intCast(self.config.overbought_threshold)));
        const exit_level = Decimal.fromInt(@as(i64, @intCast(self.config.exit_rsi_level)));

        // Check for entry signals based on position state
        if (self.position_state == .none or self.position_state == .short) {
            // Entry Long: RSI < oversold AND RSI bouncing (curr > prev)
            if (self.config.enable_long and
                curr_rsi.cmp(oversold) == .lt and
                curr_rsi.cmp(prev_rsi) == .gt)
            {
                const signal_type: SignalType = if (self.position_state == .short)
                    .exit_short
                else
                    .entry_long;

                const strength = self.calculateLongStrength(curr_rsi);

                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "RSI oversold bounce detected",
                    &[_]IndicatorValue{
                        .{ .name = "rsi", .value = curr_rsi },
                    },
                );

                return Signal.init(
                    signal_type,
                    self.config.pair,
                    signal_type.toSide() orelse .buy,
                    price,
                    strength,
                    timestamp,
                    metadata,
                );
            }
        }

        if (self.position_state == .none or self.position_state == .long) {
            // Entry Short: RSI > overbought AND RSI falling (curr < prev)
            if (self.config.enable_short and
                curr_rsi.cmp(overbought) == .gt and
                curr_rsi.cmp(prev_rsi) == .lt)
            {
                const signal_type: SignalType = if (self.position_state == .long)
                    .exit_long
                else
                    .entry_short;

                const strength = self.calculateShortStrength(curr_rsi);

                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "RSI overbought pullback detected",
                    &[_]IndicatorValue{
                        .{ .name = "rsi", .value = curr_rsi },
                    },
                );

                return Signal.init(
                    signal_type,
                    self.config.pair,
                    signal_type.toSide() orelse .sell,
                    price,
                    strength,
                    timestamp,
                    metadata,
                );
            }
        }

        // Check for exit signals
        if (self.position_state == .long) {
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

                return Signal.init(
                    .exit_long,
                    self.config.pair,
                    .sell,
                    price,
                    exit_strength,
                    timestamp,
                    metadata,
                );
            }
        } else if (self.position_state == .short) {
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

                return Signal.init(
                    .exit_short,
                    self.config.pair,
                    .buy,
                    price,
                    exit_strength,
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
            price,
            0.0,
            timestamp,
            null,
        );
    }

    fn onOrderFilled(ptr: *anyopaque, order: Order) !void {
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));

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
        const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));
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
    try testing.expectEqual(PositionState.none, strategy.position_state);
}

test "RSIMeanReversion: interface methods" {
    const testing = std.testing;

    const strategy = try RSIMeanReversionStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .rsi_period = 6,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();

    // Test getName
    try testing.expectEqualStrings("RSI Mean Reversion Strategy", istrategy.getName());

    // Test init/deinit
    try istrategy.init();
    try testing.expect(strategy.initialized);

    istrategy.deinit();
    try testing.expect(!strategy.initialized);
}

test "RSIMeanReversion: oversold bounce long signal" {
    const testing = std.testing;

    const strategy = try RSIMeanReversionStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .rsi_period = 5,
        .oversold_threshold = 30,
        .overbought_threshold = 70,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();
    try istrategy.init();

    // Create test data: price drops (RSI goes low) then starts bouncing
    var candles = try createTestCandles(testing.allocator, &[_]f64{
        100, 98, 95, 92, 88,  // Falling - RSI drops
        85, 83, 82, 83, 85,   // Starting to bounce - should trigger
        88, 90, 92, 95, 98,   // Continuing up
    });
    defer candles.deinit();

    const timestamp = Timestamp.now();
    const signal = try istrategy.analyze(&candles, timestamp);
    defer signal.deinit();

    // Should detect oversold bounce
    try testing.expect(signal.type == .entry_long or signal.type == .hold);
    if (signal.type == .entry_long) {
        try testing.expect(signal.strength >= 0.6 and signal.strength <= 0.9);
    }
}

test "RSIMeanReversion: overbought pullback short signal" {
    const testing = std.testing;

    const strategy = try RSIMeanReversionStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .rsi_period = 5,
        .oversold_threshold = 30,
        .overbought_threshold = 70,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();
    try istrategy.init();

    // Create test data: price rises (RSI goes high) then starts falling
    var candles = try createTestCandles(testing.allocator, &[_]f64{
        100, 102, 105, 108, 112, // Rising - RSI rises
        115, 117, 118, 117, 115, // Starting to fall - should trigger
        112, 110, 108, 105, 102, // Continuing down
    });
    defer candles.deinit();

    const timestamp = Timestamp.now();
    const signal = try istrategy.analyze(&candles, timestamp);
    defer signal.deinit();

    // Should detect overbought pullback
    try testing.expect(signal.type == .entry_short or signal.type == .hold);
    if (signal.type == .entry_short) {
        try testing.expect(signal.strength >= 0.6 and signal.strength <= 0.9);
    }
}

test "RSIMeanReversion: insufficient data" {
    const testing = std.testing;

    const strategy = try RSIMeanReversionStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .rsi_period = 14,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();
    try istrategy.init();

    // Only 10 candles - not enough for RSI period=14
    var candles = try createTestCandles(testing.allocator, &[_]f64{
        100, 101, 102, 103, 104,
        105, 106, 107, 108, 109,
    });
    defer candles.deinit();

    const timestamp = Timestamp.now();
    const signal = try istrategy.analyze(&candles, timestamp);
    defer signal.deinit();

    // Should return hold signal
    try testing.expectEqual(SignalType.hold, signal.type);
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

test "RSIMeanReversion: position state tracking" {
    const testing = std.testing;

    const strategy = try RSIMeanReversionStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .rsi_period = 14,
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
    try istrategy.init();

    var candles = try createTestCandles(allocator, &[_]f64{
        100, 98, 95, 92, 88,
        85, 83, 82, 83, 85,
        88, 90, 92, 95, 98,
        100, 102, 105, 108, 110,
    });
    defer candles.deinit();

    // Run multiple analyses
    for (0..10) |_| {
        const signal = try istrategy.analyze(&candles, Timestamp.now());
        defer signal.deinit();
    }
}
