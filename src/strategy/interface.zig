//! IStrategy Interface
//!
//! This module defines the strategy interface using Zig's VTable pattern.
//! All trading strategies must implement this interface to be used by the
//! backtesting engine and live trading system.
//!
//! Design principles:
//! - Polymorphic interface using anyopaque + VTable
//! - Type-safe signal generation
//! - Event-driven order updates
//! - Stateful strategy instances

const std = @import("std");
const Signal = @import("signal.zig").Signal;
const StrategyConfig = @import("types.zig").StrategyConfig;
const Candles = @import("../root.zig").Candles;
const Order = @import("../root.zig").Order;
const Timestamp = @import("../root.zig").Timestamp;

// ============================================================================
// IStrategy Interface
// ============================================================================

/// Strategy interface using VTable pattern
/// All strategies must implement these methods
pub const IStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    /// Virtual function table
    pub const VTable = struct {
        /// Get strategy name
        getName: *const fn (ptr: *anyopaque) []const u8,

        /// Initialize strategy with configuration
        /// Called once before backtesting or live trading starts
        init: *const fn (ptr: *anyopaque) anyerror!void,

        /// Deinitialize strategy and free resources
        deinit: *const fn (ptr: *anyopaque) void,

        /// Analyze current market state and generate signal
        /// Called on every new candle or price update
        ///
        /// @param candles: Historical candle data (read-only)
        /// @param timestamp: Current timestamp
        /// @return Signal (caller owns memory and must call signal.deinit())
        analyze: *const fn (
            ptr: *anyopaque,
            candles: *const Candles,
            timestamp: Timestamp,
        ) anyerror!Signal,

        /// Handle order fill event
        /// Called when an order is filled (fully or partially)
        ///
        /// @param order: Filled order details
        onOrderFilled: *const fn (
            ptr: *anyopaque,
            order: Order,
        ) anyerror!void,

        /// Handle order cancellation event
        /// Called when an order is cancelled
        ///
        /// @param order: Cancelled order details
        onOrderCancelled: *const fn (
            ptr: *anyopaque,
            order: Order,
        ) anyerror!void,
    };

    // ========================================================================
    // Proxy Methods
    // ========================================================================

    /// Get strategy name
    pub fn getName(self: IStrategy) []const u8 {
        return self.vtable.getName(self.ptr);
    }

    /// Initialize strategy
    pub fn init(self: IStrategy) !void {
        return self.vtable.init(self.ptr);
    }

    /// Deinitialize strategy
    pub fn deinit(self: IStrategy) void {
        self.vtable.deinit(self.ptr);
    }

    /// Analyze market and generate signal
    pub fn analyze(
        self: IStrategy,
        candles: *const Candles,
        timestamp: Timestamp,
    ) !Signal {
        return self.vtable.analyze(self.ptr, candles, timestamp);
    }

    /// Handle order fill event
    pub fn onOrderFilled(self: IStrategy, order: Order) !void {
        return self.vtable.onOrderFilled(self.ptr, order);
    }

    /// Handle order cancellation event
    pub fn onOrderCancelled(self: IStrategy, order: Order) !void {
        return self.vtable.onOrderCancelled(self.ptr, order);
    }
};

// ============================================================================
// Tests - Mock Strategy Implementation
// ============================================================================

/// Mock strategy for testing
const MockStrategy = struct {
    name: []const u8,
    initialized: bool,
    analyze_call_count: u32,
    fill_call_count: u32,
    cancel_call_count: u32,

    pub fn create(name: []const u8) IStrategy {
        const self = MockStrategy{
            .name = name,
            .initialized = false,
            .analyze_call_count = 0,
            .fill_call_count = 0,
            .cancel_call_count = 0,
        };

        // Note: In real usage, this would need to be heap-allocated
        // For tests, we'll use a static variable
        return .{
            .ptr = @constCast(&self),
            .vtable = &vtable,
        };
    }

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *MockStrategy = @ptrCast(@alignCast(ptr));
        return self.name;
    }

    fn init(ptr: *anyopaque) !void {
        const self: *MockStrategy = @ptrCast(@alignCast(ptr));
        self.initialized = true;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *MockStrategy = @ptrCast(@alignCast(ptr));
        self.initialized = false;
    }

    fn analyze(
        ptr: *anyopaque,
        candles: *const Candles,
        timestamp: Timestamp,
    ) !Signal {
        const self: *MockStrategy = @ptrCast(@alignCast(ptr));
        self.analyze_call_count += 1;

        _ = candles; // Unused in mock
        _ = timestamp; // Unused in mock

        // Return a hold signal
        return Signal.init(
            .hold,
            .{ .base = "BTC", .quote = "USDT" },
            .buy,
            @import("../root.zig").Decimal.fromInt(50000),
            0.0,
            @import("../root.zig").Timestamp.now(),
            null,
        );
    }

    fn onOrderFilled(ptr: *anyopaque, order: Order) !void {
        const self: *MockStrategy = @ptrCast(@alignCast(ptr));
        self.fill_call_count += 1;
        _ = order; // Unused in mock
    }

    fn onOrderCancelled(ptr: *anyopaque, order: Order) !void {
        const self: *MockStrategy = @ptrCast(@alignCast(ptr));
        self.cancel_call_count += 1;
        _ = order; // Unused in mock
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

test "IStrategy: interface creation" {
    var strategy = MockStrategy{
        .name = "Test Strategy",
        .initialized = false,
        .analyze_call_count = 0,
        .fill_call_count = 0,
        .cancel_call_count = 0,
    };

    const istrategy = IStrategy{
        .ptr = &strategy,
        .vtable = &MockStrategy.vtable,
    };

    try std.testing.expectEqualStrings("Test Strategy", istrategy.getName());
}

test "IStrategy: initialization lifecycle" {
    var strategy = MockStrategy{
        .name = "Test Strategy",
        .initialized = false,
        .analyze_call_count = 0,
        .fill_call_count = 0,
        .cancel_call_count = 0,
    };

    const istrategy = IStrategy{
        .ptr = &strategy,
        .vtable = &MockStrategy.vtable,
    };

    try std.testing.expect(!strategy.initialized);

    try istrategy.init();
    try std.testing.expect(strategy.initialized);

    istrategy.deinit();
    try std.testing.expect(!strategy.initialized);
}

test "IStrategy: analyze signal generation" {
    const allocator = std.testing.allocator;

    var strategy = MockStrategy{
        .name = "Test Strategy",
        .initialized = false,
        .analyze_call_count = 0,
        .fill_call_count = 0,
        .cancel_call_count = 0,
    };

    const istrategy = IStrategy{
        .ptr = &strategy,
        .vtable = &MockStrategy.vtable,
    };

    // Create mock candles
    var candles = @import("../root.zig").Candles.init(
        allocator,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
    );
    defer candles.deinit();

    const timestamp = @import("../root.zig").Timestamp.now();

    try std.testing.expectEqual(@as(u32, 0), strategy.analyze_call_count);

    const signal = try istrategy.analyze(&candles, timestamp);
    defer signal.deinit();

    try std.testing.expectEqual(@as(u32, 1), strategy.analyze_call_count);
    try std.testing.expectEqual(@import("signal.zig").SignalType.hold, signal.type);
}

test "IStrategy: order event handlers" {
    var strategy = MockStrategy{
        .name = "Test Strategy",
        .initialized = false,
        .analyze_call_count = 0,
        .fill_call_count = 0,
        .cancel_call_count = 0,
    };

    const istrategy = IStrategy{
        .ptr = &strategy,
        .vtable = &MockStrategy.vtable,
    };

    // Create mock order
    const order = Order{
        .exchange_order_id = 12345,
        .client_order_id = null,
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .status = .filled,
        .amount = @import("../root.zig").Decimal.fromInt(1),
        .price = @import("../root.zig").Decimal.fromInt(50000),
        .filled_amount = @import("../root.zig").Decimal.fromInt(1),
        .avg_fill_price = @import("../root.zig").Decimal.fromInt(50000),
        .created_at = @import("../root.zig").Timestamp.now(),
        .updated_at = @import("../root.zig").Timestamp.now(),
    };

    try std.testing.expectEqual(@as(u32, 0), strategy.fill_call_count);
    try std.testing.expectEqual(@as(u32, 0), strategy.cancel_call_count);

    // Test fill event
    try istrategy.onOrderFilled(order);
    try std.testing.expectEqual(@as(u32, 1), strategy.fill_call_count);

    // Test cancel event
    try istrategy.onOrderCancelled(order);
    try std.testing.expectEqual(@as(u32, 1), strategy.cancel_call_count);

    // Multiple calls should increment counters
    try istrategy.onOrderFilled(order);
    try istrategy.onOrderFilled(order);
    try std.testing.expectEqual(@as(u32, 3), strategy.fill_call_count);
}

test "IStrategy: multiple instances" {
    var strategy1 = MockStrategy{
        .name = "Strategy 1",
        .initialized = false,
        .analyze_call_count = 0,
        .fill_call_count = 0,
        .cancel_call_count = 0,
    };

    var strategy2 = MockStrategy{
        .name = "Strategy 2",
        .initialized = false,
        .analyze_call_count = 0,
        .fill_call_count = 0,
        .cancel_call_count = 0,
    };

    const istrategy1 = IStrategy{
        .ptr = &strategy1,
        .vtable = &MockStrategy.vtable,
    };

    const istrategy2 = IStrategy{
        .ptr = &strategy2,
        .vtable = &MockStrategy.vtable,
    };

    try std.testing.expectEqualStrings("Strategy 1", istrategy1.getName());
    try std.testing.expectEqualStrings("Strategy 2", istrategy2.getName());

    try istrategy1.init();
    try std.testing.expect(strategy1.initialized);
    try std.testing.expect(!strategy2.initialized);

    try istrategy2.init();
    try std.testing.expect(strategy1.initialized);
    try std.testing.expect(strategy2.initialized);
}
