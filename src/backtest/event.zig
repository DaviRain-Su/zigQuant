//! Backtest Engine - Event System
//!
//! Event-driven architecture for realistic trade simulation.
//! Implements MarketEvent, SignalEvent, OrderEvent, FillEvent and EventQueue.

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const TradingPair = @import("../exchange/types.zig").TradingPair;
const Candle = @import("../market/candles.zig").Candle;
const Signal = @import("../strategy/signal.zig").Signal;
const PositionSide = @import("types.zig").PositionSide;

// ============================================================================
// Event Types
// ============================================================================

pub const EventType = enum {
    market, // New candle data
    signal, // Strategy generated signal
    order, // Order created
    fill, // Order filled
};

/// Unified event type
pub const Event = union(EventType) {
    market: MarketEvent,
    signal: SignalEvent,
    order: OrderEvent,
    fill: FillEvent,

    /// Get timestamp from any event type
    pub fn getTimestamp(self: Event) Timestamp {
        return switch (self) {
            .market => |e| e.timestamp,
            .signal => |e| e.timestamp,
            .order => |e| e.timestamp,
            .fill => |e| e.timestamp,
        };
    }
};

/// New candle arrives
pub const MarketEvent = struct {
    timestamp: Timestamp,
    candle: Candle,
};

/// Strategy generates trading signal
pub const SignalEvent = struct {
    timestamp: Timestamp,
    signal: Signal,
};

/// Order created
pub const OrderEvent = struct {
    id: u64,
    timestamp: Timestamp,
    pair: TradingPair,
    side: OrderSide, // .buy or .sell (different from position side)
    order_type: OrderType,
    price: Decimal,
    size: Decimal,

    pub const OrderSide = enum {
        buy,
        sell,

        /// Convert position side to order side for entry
        pub fn fromPositionSideEntry(pos_side: PositionSide) OrderSide {
            return switch (pos_side) {
                .long => .buy,
                .short => .sell,
            };
        }

        /// Convert position side to order side for exit
        pub fn fromPositionSideExit(pos_side: PositionSide) OrderSide {
            return switch (pos_side) {
                .long => .sell, // Close long by selling
                .short => .buy, // Close short by buying
            };
        }
    };

    pub const OrderType = enum {
        market,
        limit,
    };
};

/// Order executed
pub const FillEvent = struct {
    order_id: u64,
    timestamp: Timestamp,
    fill_price: Decimal,
    fill_size: Decimal,
    commission: Decimal,
};

// ============================================================================
// Event Queue
// ============================================================================

/// FIFO event queue for event-driven simulation
pub const EventQueue = struct {
    allocator: std.mem.Allocator,
    queue: std.ArrayList(Event),

    pub fn init(allocator: std.mem.Allocator) !EventQueue {
        return .{
            .allocator = allocator,
            .queue = try std.ArrayList(Event).initCapacity(allocator, 16),
        };
    }

    pub fn deinit(self: *EventQueue) void {
        self.queue.deinit(self.allocator);
    }

    /// Add event to queue
    pub fn push(self: *EventQueue, event: Event) !void {
        try self.queue.append(self.allocator, event);
    }

    /// Remove and return first event (FIFO)
    pub fn pop(self: *EventQueue) ?Event {
        if (self.queue.items.len == 0) return null;
        return self.queue.orderedRemove(0);
    }

    /// Check if queue is empty
    pub fn isEmpty(self: *const EventQueue) bool {
        return self.queue.items.len == 0;
    }

    /// Get queue size
    pub fn size(self: *const EventQueue) usize {
        return self.queue.items.len;
    }

    /// Clear all events
    pub fn clear(self: *EventQueue) void {
        self.queue.clearRetainingCapacity();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Event: getTimestamp" {
    const testing = std.testing;

    const market_event = Event{
        .market = MarketEvent{
            .timestamp = .{ .millis = 1000 },
            .candle = Candle{
                .timestamp = .{ .millis = 1000 },
                .open = Decimal.fromInt(2000),
                .high = Decimal.fromInt(2010),
                .low = Decimal.fromInt(1990),
                .close = Decimal.fromInt(2005),
                .volume = Decimal.fromInt(100),
            },
        },
    };

    try testing.expectEqual(@as(i64, 1000), market_event.getTimestamp().millis);
}

test "OrderEvent.OrderSide: conversion from position side" {
    const testing = std.testing;

    // Entry: long position -> buy order
    try testing.expectEqual(
        OrderEvent.OrderSide.buy,
        OrderEvent.OrderSide.fromPositionSideEntry(.long),
    );

    // Entry: short position -> sell order
    try testing.expectEqual(
        OrderEvent.OrderSide.sell,
        OrderEvent.OrderSide.fromPositionSideEntry(.short),
    );

    // Exit: long position -> sell order
    try testing.expectEqual(
        OrderEvent.OrderSide.sell,
        OrderEvent.OrderSide.fromPositionSideExit(.long),
    );

    // Exit: short position -> buy order
    try testing.expectEqual(
        OrderEvent.OrderSide.buy,
        OrderEvent.OrderSide.fromPositionSideExit(.short),
    );
}

test "EventQueue: FIFO ordering" {
    const testing = std.testing;

    var queue = try EventQueue.init(testing.allocator);
    defer queue.deinit();

    // Push events
    const event1 = Event{
        .market = MarketEvent{
            .timestamp = .{ .millis = 1000 },
            .candle = Candle{
                .timestamp = .{ .millis = 1000 },
                .open = Decimal.fromInt(2000),
                .high = Decimal.fromInt(2010),
                .low = Decimal.fromInt(1990),
                .close = Decimal.fromInt(2005),
                .volume = Decimal.fromInt(100),
            },
        },
    };

    const event2 = Event{
        .market = MarketEvent{
            .timestamp = .{ .millis = 2000 },
            .candle = Candle{
                .timestamp = .{ .millis = 2000 },
                .open = Decimal.fromInt(2005),
                .high = Decimal.fromInt(2015),
                .low = Decimal.fromInt(1995),
                .close = Decimal.fromInt(2010),
                .volume = Decimal.fromInt(100),
            },
        },
    };

    const event3 = Event{
        .market = MarketEvent{
            .timestamp = .{ .millis = 3000 },
            .candle = Candle{
                .timestamp = .{ .millis = 3000 },
                .open = Decimal.fromInt(2010),
                .high = Decimal.fromInt(2020),
                .low = Decimal.fromInt(2000),
                .close = Decimal.fromInt(2015),
                .volume = Decimal.fromInt(100),
            },
        },
    };

    try queue.push(event1);
    try queue.push(event2);
    try queue.push(event3);

    try testing.expectEqual(@as(usize, 3), queue.size());

    // Pop events - should be in FIFO order
    const e1 = queue.pop().?;
    try testing.expectEqual(@as(i64, 1000), e1.getTimestamp().millis);

    const e2 = queue.pop().?;
    try testing.expectEqual(@as(i64, 2000), e2.getTimestamp().millis);

    const e3 = queue.pop().?;
    try testing.expectEqual(@as(i64, 3000), e3.getTimestamp().millis);

    // Queue should be empty
    try testing.expect(queue.isEmpty());
    try testing.expect(queue.pop() == null);
}

test "EventQueue: clear" {
    const testing = std.testing;

    var queue = try EventQueue.init(testing.allocator);
    defer queue.deinit();

    // Add events
    try queue.push(Event{
        .market = MarketEvent{
            .timestamp = .{ .millis = 1000 },
            .candle = Candle{
                .timestamp = .{ .millis = 1000 },
                .open = Decimal.fromInt(2000),
                .high = Decimal.fromInt(2010),
                .low = Decimal.fromInt(1990),
                .close = Decimal.fromInt(2005),
                .volume = Decimal.fromInt(100),
            },
        },
    });

    try queue.push(Event{
        .market = MarketEvent{
            .timestamp = .{ .millis = 2000 },
            .candle = Candle{
                .timestamp = .{ .millis = 2000 },
                .open = Decimal.fromInt(2005),
                .high = Decimal.fromInt(2015),
                .low = Decimal.fromInt(1995),
                .close = Decimal.fromInt(2010),
                .volume = Decimal.fromInt(100),
            },
        },
    });

    try testing.expect(!queue.isEmpty());
    try testing.expectEqual(@as(usize, 2), queue.size());

    // Clear
    queue.clear();
    try testing.expect(queue.isEmpty());
    try testing.expectEqual(@as(usize, 0), queue.size());
}

test "EventQueue: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var queue = try EventQueue.init(allocator);
    defer queue.deinit();

    // Add many events
    for (0..100) |i| {
        try queue.push(Event{
            .market = MarketEvent{
                .timestamp = .{ .millis = @intCast(i * 1000) },
                .candle = Candle{
                    .timestamp = .{ .millis = @intCast(i * 1000) },
                    .open = Decimal.fromInt(2000),
                    .high = Decimal.fromInt(2010),
                    .low = Decimal.fromInt(1990),
                    .close = Decimal.fromInt(2005),
                    .volume = Decimal.fromInt(100),
                },
            },
        });
    }
}
