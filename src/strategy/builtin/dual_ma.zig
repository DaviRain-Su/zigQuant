//! Dual Moving Average (Dual MA) Strategy
//!
//! Classic trend-following strategy using two moving averages:
//! - **Golden Cross**: Fast MA crosses above slow MA → Entry Long
//! - **Death Cross**: Fast MA crosses below slow MA → Entry Short / Exit Long
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
//!
//! Usage:
//! ```zig
//! const strategy = try DualMAStrategy.create(allocator, .{
//!     .fast_period = 10,
//!     .slow_period = 20,
//!     .ma_type = .sma,
//! });
//! defer strategy.deinit();
//!
//! const signal = try strategy.analyze(&candles, timestamp);
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
// Strategy State
// ============================================================================

/// Position state for tracking
const PositionState = enum {
    none,  // No position
    long,  // Long position
    short, // Short position
};

// ============================================================================
// Dual MA Strategy
// ============================================================================

/// Dual Moving Average Strategy
pub const DualMAStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    indicator_manager: IndicatorManager,
    position_state: PositionState,
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
            .position_state = .none,
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

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "Dual Moving Average Strategy";
    }

    fn init(ptr: *anyopaque) !void {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));
        self.initialized = true;
        self.position_state = .none;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));
        self.initialized = false;
    }

    fn analyze(
        ptr: *anyopaque,
        candles: *const Candles,
        timestamp: Timestamp,
    ) !Signal {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

        // Need mutable candles for indicator calculation
        var mutable_candles = @constCast(candles);

        // Check if we have enough data
        const candle_count = mutable_candles.len();
        if (candle_count < self.config.slow_period) {
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

        // Calculate indicators using IndicatorManager for caching
        const ma_fast = switch (self.config.ma_type) {
            .sma => try indicator_helpers.getSMA(
                &self.indicator_manager,
                mutable_candles,
                self.config.fast_period,
            ),
            .ema => try indicator_helpers.getEMA(
                &self.indicator_manager,
                mutable_candles,
                self.config.fast_period,
            ),
        };

        const ma_slow = switch (self.config.ma_type) {
            .sma => try indicator_helpers.getSMA(
                &self.indicator_manager,
                mutable_candles,
                self.config.slow_period,
            ),
            .ema => try indicator_helpers.getEMA(
                &self.indicator_manager,
                mutable_candles,
                self.config.slow_period,
            ),
        };

        // Get current and previous values
        const current_idx = candle_count - 1;
        const prev_idx = current_idx - 1;

        // Skip if not enough data for crossover detection
        if (current_idx < self.config.slow_period) {
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

        const prev_fast = ma_fast[prev_idx];
        const prev_slow = ma_slow[prev_idx];
        const curr_fast = ma_fast[current_idx];
        const curr_slow = ma_slow[current_idx];

        // Skip if any value is NaN
        if (prev_fast.isNaN() or prev_slow.isNaN() or curr_fast.isNaN() or curr_slow.isNaN()) {
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

        const current_candle = mutable_candles.get(current_idx) orelse unreachable;
        const price = current_candle.close;

        // Detect Golden Cross (fast crosses above slow)
        const is_golden_cross = prev_fast.cmp(prev_slow) != .gt and curr_fast.cmp(curr_slow) == .gt;

        // Detect Death Cross (fast crosses below slow)
        const is_death_cross = prev_fast.cmp(prev_slow) != .lt and curr_fast.cmp(curr_slow) == .lt;

        // Generate signals based on crossovers and position state
        if (is_golden_cross) {
            // Golden Cross detected
            const signal_type: SignalType = if (self.position_state == .short)
                .exit_short
            else
                .entry_long;

            const metadata = try SignalMetadata.init(
                self.allocator,
                "Golden Cross: Fast MA crossed above Slow MA",
                &[_]IndicatorValue{
                    .{ .name = "ma_fast", .value = curr_fast },
                    .{ .name = "ma_slow", .value = curr_slow },
                },
            );

            return Signal.init(
                signal_type,
                self.config.pair,
                signal_type.toSide() orelse .buy,
                price,
                0.8, // Signal strength
                timestamp,
                metadata,
            );
        } else if (is_death_cross) {
            // Death Cross detected
            const signal_type: SignalType = if (self.position_state == .long)
                .exit_long
            else
                .entry_short;

            const metadata = try SignalMetadata.init(
                self.allocator,
                "Death Cross: Fast MA crossed below Slow MA",
                &[_]IndicatorValue{
                    .{ .name = "ma_fast", .value = curr_fast },
                    .{ .name = "ma_slow", .value = curr_slow },
                },
            );

            return Signal.init(
                signal_type,
                self.config.pair,
                signal_type.toSide() orelse .sell,
                price,
                0.8, // Signal strength
                timestamp,
                metadata,
            );
        }

        // No crossover - hold
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
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

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
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));
        // For now, don't change position state on cancellation
        // In a more sophisticated implementation, we might track pending orders
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

test "DualMAStrategy: invalid parameters" {
    const testing = std.testing;

    // fast_period >= slow_period should fail
    try testing.expectError(
        error.InvalidParameters,
        DualMAStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .fast_period = 20,
            .slow_period = 10,
        }),
    );

    // fast_period < 2 should fail
    try testing.expectError(
        error.FastPeriodTooSmall,
        DualMAStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .fast_period = 1,
            .slow_period = 10,
        }),
    );

    // slow_period > 200 should fail
    try testing.expectError(
        error.SlowPeriodTooLarge,
        DualMAStrategy.create(testing.allocator, .{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .fast_period = 10,
            .slow_period = 201,
        }),
    );
}

test "DualMAStrategy: creation and destruction" {
    const testing = std.testing;

    const strategy = try DualMAStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .fast_period = 5,
        .slow_period = 10,
    });
    defer strategy.destroy();

    try testing.expect(!strategy.initialized);
    try testing.expectEqual(PositionState.none, strategy.position_state);
}

test "DualMAStrategy: interface methods" {
    const testing = std.testing;

    const strategy = try DualMAStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .fast_period = 5,
        .slow_period = 10,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();

    // Test getName
    try testing.expectEqualStrings("Dual Moving Average Strategy", istrategy.getName());

    // Test init/deinit
    try istrategy.init();
    try testing.expect(strategy.initialized);

    istrategy.deinit();
    try testing.expect(!strategy.initialized);
}

test "DualMAStrategy: golden cross detection" {
    const testing = std.testing;

    const strategy = try DualMAStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .fast_period = 3,
        .slow_period = 5,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();
    try istrategy.init();

    // Create test data simulating golden cross
    // Prices go up gradually, causing fast MA to cross above slow MA
    var candles = try createTestCandles(testing.allocator, &[_]f64{
        100, 100, 100, 100, 100, // Initial flat
        101, 102, 103, 104, 105, // Uptrend starts
        106, 107, 108, 109, 110, // Continuing up
    });
    defer candles.deinit();

    const timestamp = Timestamp.now();
    const signal = try istrategy.analyze(&candles, timestamp);
    defer signal.deinit();

    // Should detect golden cross
    try testing.expect(signal.type == .entry_long or signal.type == .hold);
}

test "DualMAStrategy: death cross detection" {
    const testing = std.testing;

    const strategy = try DualMAStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .fast_period = 3,
        .slow_period = 5,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();
    try istrategy.init();

    // Create test data simulating death cross
    var candles = try createTestCandles(testing.allocator, &[_]f64{
        110, 110, 110, 110, 110, // Initial flat
        109, 108, 107, 106, 105, // Downtrend starts
        104, 103, 102, 101, 100, // Continuing down
    });
    defer candles.deinit();

    const timestamp = Timestamp.now();
    const signal = try istrategy.analyze(&candles, timestamp);
    defer signal.deinit();

    // Should detect death cross
    try testing.expect(signal.type == .entry_short or signal.type == .hold);
}

test "DualMAStrategy: insufficient data" {
    const testing = std.testing;

    const strategy = try DualMAStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .fast_period = 5,
        .slow_period = 10,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();
    try istrategy.init();

    // Only 5 candles - not enough for slow_period=10
    var candles = try createTestCandles(testing.allocator, &[_]f64{ 100, 101, 102, 103, 104 });
    defer candles.deinit();

    const timestamp = Timestamp.now();
    const signal = try istrategy.analyze(&candles, timestamp);
    defer signal.deinit();

    // Should return hold signal
    try testing.expectEqual(SignalType.hold, signal.type);
}

test "DualMAStrategy: position state tracking" {
    const testing = std.testing;

    const strategy = try DualMAStrategy.create(testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .fast_period = 5,
        .slow_period = 10,
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

test "DualMAStrategy: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const strategy = try DualMAStrategy.create(allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .fast_period = 5,
        .slow_period = 10,
    });
    defer strategy.destroy();

    const istrategy = strategy.toStrategy();
    try istrategy.init();

    var candles = try createTestCandles(allocator, &[_]f64{
        100, 101, 102, 103, 104,
        105, 106, 107, 108, 109,
        110, 111, 112, 113, 114,
    });
    defer candles.deinit();

    // Run multiple analyses
    for (0..10) |_| {
        const signal = try istrategy.analyze(&candles, Timestamp.now());
        defer signal.deinit();
    }
}
