//! Queue Position Modeling for Realistic Backtest
//!
//! This module provides queue position tracking for limit orders in order books.
//! It models the realistic behavior of order queues where orders are filled
//! in FIFO order at each price level.
//!
//! ## Why Queue Position Matters
//!
//! Traditional backtests assume immediate fill when price touches limit orders.
//! In reality, limit orders queue behind existing orders at the same price.
//! This can cause 20-30% difference in Sharpe ratio between backtest and live.
//!
//! ## Queue Models
//!
//! - RiskAverse: Conservative, assumes almost never fills unless at front
//! - Probability: Linear probability based on queue position
//! - PowerLaw: Quadratic decay, middle positions have lower probability
//! - Logarithmic: Log-based decay, closer to real market behavior
//!
//! ## Story 038: Queue Position Modeling

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;
const Side = @import("../exchange/types.zig").Side;

// ============================================================================
// Queue Model
// ============================================================================

/// Queue fill probability model
pub const QueueModel = enum {
    /// Conservative model: assumes at queue tail, rarely fills
    /// Fill probability = 1.0 if position < 1%, else 0.0
    RiskAverse,

    /// Linear probability model: position determines fill chance
    /// Fill probability = 1.0 - (position / total)
    Probability,

    /// Power law model: quadratic decay
    /// Fill probability = 1.0 - (position / total)^2
    PowerLaw,

    /// Logarithmic model: closer to real market behavior
    /// Fill probability = 1.0 - log(1 + x) / log(2)
    Logarithmic,

    /// Calculate fill probability for given normalized position
    /// @param x Normalized position (0.0 = front, 1.0 = back)
    pub fn probability(self: QueueModel, x: f64) f64 {
        // Clamp x to valid range
        const pos = @max(0.0, @min(1.0, x));

        return switch (self) {
            .RiskAverse => if (pos < 0.01) 1.0 else 0.0,
            .Probability => 1.0 - pos,
            .PowerLaw => 1.0 - std.math.pow(f64, pos, 2.0),
            .Logarithmic => 1.0 - (@log(1.0 + pos) / @log(2.0)),
        };
    }
};

// ============================================================================
// Queue Position
// ============================================================================

/// Order queue position tracking
pub const QueuePosition = struct {
    /// Order identifier
    order_id: u64,
    /// Price level this order is at
    price_level: Decimal,
    /// Position in queue (0 = front/head)
    position_in_queue: usize,
    /// Total quantity ahead in queue
    total_quantity_ahead: Decimal,
    /// Initial quantity ahead (used for probability calculation)
    initial_quantity_ahead: Decimal,
    /// Order quantity
    order_quantity: Decimal,

    const Self = @This();

    /// Create a new queue position
    pub fn init(
        order_id: u64,
        price: Decimal,
        position: usize,
        qty_ahead: Decimal,
        order_qty: Decimal,
    ) Self {
        return .{
            .order_id = order_id,
            .price_level = price,
            .position_in_queue = position,
            .total_quantity_ahead = qty_ahead,
            .initial_quantity_ahead = if (qty_ahead.isZero()) Decimal.fromInt(1) else qty_ahead,
            .order_quantity = order_qty,
        };
    }

    /// Calculate fill probability using specified model
    pub fn fillProbability(self: Self, model: QueueModel) f64 {
        // At front of queue = 100% fill
        if (self.total_quantity_ahead.isZero() or self.position_in_queue == 0) {
            return 1.0;
        }

        // Normalized position (0.0 = front, 1.0 = back)
        const x = self.total_quantity_ahead.toFloat() / self.initial_quantity_ahead.toFloat();

        return model.probability(x);
    }

    /// Advance queue position when orders ahead are filled/cancelled
    pub fn advance(self: *Self, executed_qty: Decimal) void {
        if (executed_qty.cmp(self.total_quantity_ahead) != .lt) {
            // All orders ahead cleared
            self.position_in_queue = 0;
            self.total_quantity_ahead = Decimal.ZERO;
        } else {
            // Partial advance
            self.total_quantity_ahead = self.total_quantity_ahead.sub(executed_qty);
            // Estimate position change (rough approximation)
            if (self.position_in_queue > 0) {
                self.position_in_queue -= 1;
            }
        }
    }

    /// Check if order is at front of queue
    pub fn isAtFront(self: Self) bool {
        return self.position_in_queue == 0 or self.total_quantity_ahead.isZero();
    }

    /// Check if order should fill based on model and random value
    pub fn shouldFill(self: Self, model: QueueModel, random: f64) bool {
        return random < self.fillProbability(model);
    }

    /// Check if order should fill deterministically (for non-random simulation)
    pub fn shouldFillDeterministic(self: Self, model: QueueModel) bool {
        const prob = self.fillProbability(model);
        // Fill if at front or probability > 90%
        return self.isAtFront() or prob > 0.9;
    }
};

// ============================================================================
// Queued Order
// ============================================================================

/// Order in the queue
pub const QueuedOrder = struct {
    /// Order ID
    id: u64,
    /// Order side
    side: Side,
    /// Price
    price: Decimal,
    /// Original quantity
    quantity: Decimal,
    /// Remaining quantity (unfilled)
    remaining_quantity: Decimal,
    /// Queue position info
    queue_position: QueuePosition,
    /// Timestamp
    timestamp: i64,

    const Self = @This();

    pub fn init(
        id: u64,
        side: Side,
        price: Decimal,
        quantity: Decimal,
        timestamp: i64,
    ) Self {
        return .{
            .id = id,
            .side = side,
            .price = price,
            .quantity = quantity,
            .remaining_quantity = quantity,
            .queue_position = QueuePosition.init(id, price, 0, Decimal.ZERO, quantity),
            .timestamp = timestamp,
        };
    }

    /// Check if order is fully filled
    pub fn isFilled(self: Self) bool {
        return self.remaining_quantity.isZero();
    }

    /// Fill order partially or fully
    pub fn fill(self: *Self, qty: Decimal) Decimal {
        const fill_qty = if (qty.cmp(self.remaining_quantity) == .lt)
            qty
        else
            self.remaining_quantity;

        self.remaining_quantity = self.remaining_quantity.sub(fill_qty);
        return fill_qty;
    }
};

// ============================================================================
// Price Level
// ============================================================================

/// Price level containing order IDs at same price
pub const PriceLevel = struct {
    /// Price of this level
    price: Decimal,
    /// Order IDs at this price (FIFO queue)
    order_ids: std.ArrayList(u64),
    /// Total quantity at this level
    total_quantity: Decimal,

    const Self = @This();

    pub fn init(allocator: Allocator, price: Decimal) !Self {
        return .{
            .price = price,
            .order_ids = try std.ArrayList(u64).initCapacity(allocator, 4),
            .total_quantity = Decimal.ZERO,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.order_ids.deinit(allocator);
    }

    /// Add order ID to queue tail
    pub fn addOrderId(self: *Self, allocator: Allocator, order_id: u64, qty: Decimal) !usize {
        const position = self.order_ids.items.len;
        try self.order_ids.append(allocator, order_id);
        self.total_quantity = self.total_quantity.add(qty);
        return position;
    }

    /// Remove order ID from queue
    pub fn removeOrderId(self: *Self, order_id: u64, qty: Decimal) bool {
        for (self.order_ids.items, 0..) |id, i| {
            if (id == order_id) {
                _ = self.order_ids.orderedRemove(i);
                self.total_quantity = self.total_quantity.sub(qty);
                return true;
            }
        }
        return false;
    }

    /// Get order count
    pub fn orderCount(self: Self) usize {
        return self.order_ids.items.len;
    }

    /// Check if level is empty
    pub fn isEmpty(self: Self) bool {
        return self.order_ids.items.len == 0;
    }

    /// Get front order ID
    pub fn frontOrderId(self: Self) ?u64 {
        if (self.order_ids.items.len == 0) return null;
        return self.order_ids.items[0];
    }

    /// Remove front order
    pub fn removeFront(self: *Self) ?u64 {
        if (self.order_ids.items.len == 0) return null;
        return self.order_ids.orderedRemove(0);
    }
};

// ============================================================================
// Level-3 Order Book
// ============================================================================

/// Level-3 Order Book (Market-By-Order)
/// Tracks individual orders and their queue positions
pub const Level3OrderBook = struct {
    allocator: Allocator,
    /// Symbol
    symbol: []const u8,
    /// Bid levels (buy orders) - price_key -> level
    bids: std.AutoArrayHashMap(i64, PriceLevel),
    /// Ask levels (sell orders) - price_key -> level
    asks: std.AutoArrayHashMap(i64, PriceLevel),
    /// Order storage (owns the orders)
    order_storage: std.AutoArrayHashMap(u64, QueuedOrder),
    /// Next order ID
    next_order_id: u64,
    /// Queue model for fill probability
    queue_model: QueueModel,

    const Self = @This();

    pub fn init(allocator: Allocator, symbol: []const u8) Self {
        return .{
            .allocator = allocator,
            .symbol = symbol,
            .bids = std.AutoArrayHashMap(i64, PriceLevel).init(allocator),
            .asks = std.AutoArrayHashMap(i64, PriceLevel).init(allocator),
            .order_storage = std.AutoArrayHashMap(u64, QueuedOrder).init(allocator),
            .next_order_id = 1,
            .queue_model = .Probability,
        };
    }

    pub fn deinit(self: *Self) void {
        // Deinit all price levels
        var bid_iter = self.bids.iterator();
        while (bid_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.bids.deinit();

        var ask_iter = self.asks.iterator();
        while (ask_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.asks.deinit();

        self.order_storage.deinit();
    }

    /// Set queue model
    pub fn setQueueModel(self: *Self, model: QueueModel) void {
        self.queue_model = model;
    }

    /// Convert Decimal price to map key
    fn priceToKey(price: Decimal) i64 {
        // Use raw value as key (scaled integer)
        return @intCast(@divTrunc(price.value, 1_000_000_000)); // Reduce precision for key
    }

    /// Calculate quantity ahead for a new order at given price level
    fn calculateQtyAhead(self: *Self, side: Side, price: Decimal) Decimal {
        const book = if (side == .buy) &self.bids else &self.asks;
        const price_key = priceToKey(price);

        if (book.getPtr(price_key)) |level| {
            return level.total_quantity;
        }
        return Decimal.ZERO;
    }

    /// Add order to book
    pub fn addOrder(
        self: *Self,
        side: Side,
        price: Decimal,
        quantity: Decimal,
        timestamp: i64,
    ) !u64 {
        const order_id = self.next_order_id;
        self.next_order_id += 1;

        // Calculate queue position before adding
        const qty_ahead = self.calculateQtyAhead(side, price);
        const book = if (side == .buy) &self.bids else &self.asks;
        const price_key = priceToKey(price);

        // Get or create level
        const level = book.getPtr(price_key) orelse blk: {
            try book.put(price_key, try PriceLevel.init(self.allocator, price));
            break :blk book.getPtr(price_key).?;
        };

        // Add to level first to get position
        const position = try level.addOrderId(self.allocator, order_id, quantity);

        // Create order with proper queue position
        var order = QueuedOrder.init(order_id, side, price, quantity, timestamp);
        order.queue_position = QueuePosition.init(order_id, price, position, qty_ahead, quantity);

        // Store order
        try self.order_storage.put(order_id, order);

        return order_id;
    }

    /// Cancel order
    pub fn cancelOrder(self: *Self, order_id: u64) bool {
        const order = self.order_storage.getPtr(order_id) orelse return false;

        const book = if (order.side == .buy) &self.bids else &self.asks;
        const price_key = priceToKey(order.price);

        if (book.getPtr(price_key)) |level| {
            _ = level.removeOrderId(order_id, order.remaining_quantity);

            // Remove empty levels
            if (level.isEmpty()) {
                level.deinit(self.allocator);
                _ = book.orderedRemove(price_key);
            }
        }

        _ = self.order_storage.orderedRemove(order_id);
        return true;
    }

    /// Process trade event (external trade that affects queue)
    pub fn onTrade(
        self: *Self,
        trade_side: Side,
        trade_price: Decimal,
        trade_qty: Decimal,
    ) void {
        // Trade affects the opposite side of the book
        // Buy trade consumes asks, sell trade consumes bids
        const book = if (trade_side == .buy) &self.asks else &self.bids;
        const price_key = priceToKey(trade_price);

        if (book.getPtr(price_key)) |level| {
            var remaining = trade_qty;

            while (!remaining.isZero() and !level.isEmpty()) {
                const front_id = level.frontOrderId() orelse break;
                const front_order = self.order_storage.getPtr(front_id) orelse {
                    _ = level.removeFront();
                    continue;
                };

                const fill_qty = front_order.fill(remaining);
                remaining = remaining.sub(fill_qty);
                level.total_quantity = level.total_quantity.sub(fill_qty);

                if (front_order.isFilled()) {
                    _ = level.removeFront();
                    _ = self.order_storage.orderedRemove(front_id);
                }
            }

            // Remove empty levels
            if (level.isEmpty()) {
                level.deinit(self.allocator);
                _ = book.orderedRemove(price_key);
            }
        }
    }

    /// Check if my order should fill based on trade
    pub fn checkMyOrderFill(
        self: *Self,
        order_id: u64,
        trade_price: Decimal,
        trade_side: Side,
    ) bool {
        const order = self.order_storage.getPtr(order_id) orelse return false;

        // Price must match
        if (!order.price.eql(trade_price)) return false;

        // Trade must be on opposite side
        if (order.side == trade_side) return false;

        // Check fill probability
        return order.queue_position.shouldFillDeterministic(self.queue_model);
    }

    /// Get order info
    pub fn getOrder(self: *Self, order_id: u64) ?*QueuedOrder {
        return self.order_storage.getPtr(order_id);
    }

    /// Get best bid price
    pub fn bestBid(self: *Self) ?Decimal {
        var best: ?Decimal = null;
        var iter = self.bids.iterator();
        while (iter.next()) |entry| {
            if (best == null or entry.value_ptr.price.cmp(best.?) == .gt) {
                best = entry.value_ptr.price;
            }
        }
        return best;
    }

    /// Get best ask price
    pub fn bestAsk(self: *Self) ?Decimal {
        var best: ?Decimal = null;
        var iter = self.asks.iterator();
        while (iter.next()) |entry| {
            if (best == null or entry.value_ptr.price.cmp(best.?) == .lt) {
                best = entry.value_ptr.price;
            }
        }
        return best;
    }

    /// Get total bid depth
    pub fn bidDepth(self: *Self) Decimal {
        var total = Decimal.ZERO;
        var iter = self.bids.iterator();
        while (iter.next()) |entry| {
            total = total.add(entry.value_ptr.total_quantity);
        }
        return total;
    }

    /// Get total ask depth
    pub fn askDepth(self: *Self) Decimal {
        var total = Decimal.ZERO;
        var iter = self.asks.iterator();
        while (iter.next()) |entry| {
            total = total.add(entry.value_ptr.total_quantity);
        }
        return total;
    }

    /// Get order count
    pub fn orderCount(self: *Self) usize {
        return self.order_storage.count();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "QueueModel: probability calculations" {
    // At front (x = 0)
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), QueueModel.RiskAverse.probability(0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), QueueModel.Probability.probability(0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), QueueModel.PowerLaw.probability(0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), QueueModel.Logarithmic.probability(0.0), 0.001);

    // At back (x = 1)
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), QueueModel.RiskAverse.probability(1.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), QueueModel.Probability.probability(1.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), QueueModel.PowerLaw.probability(1.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), QueueModel.Logarithmic.probability(1.0), 0.001);

    // Middle position (x = 0.5)
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), QueueModel.RiskAverse.probability(0.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), QueueModel.Probability.probability(0.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), QueueModel.PowerLaw.probability(0.5), 0.001);
    // Logarithmic: 1 - log(1.5)/log(2) ≈ 0.415
    try std.testing.expect(QueueModel.Logarithmic.probability(0.5) > 0.4);
    try std.testing.expect(QueueModel.Logarithmic.probability(0.5) < 0.45);
}

test "QueuePosition: fill probability" {
    var pos = QueuePosition.init(
        1,
        Decimal.fromInt(2000),
        5,
        Decimal.fromFloat(50.0),
        Decimal.fromFloat(1.0),
    );

    // Middle of queue - probability should be between 0 and 1
    const prob = pos.fillProbability(.Probability);
    try std.testing.expect(prob < 1.0);
    try std.testing.expect(prob >= 0.0);

    // Advance to front
    pos.advance(Decimal.fromFloat(50.0));
    try std.testing.expect(pos.isAtFront());
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), pos.fillProbability(.Probability), 0.001);
}

test "QueuePosition: partial advance" {
    var pos = QueuePosition.init(
        1,
        Decimal.fromInt(2000),
        5,
        Decimal.fromFloat(50.0),
        Decimal.fromFloat(1.0),
    );

    // Advance 20 out of 50
    pos.advance(Decimal.fromFloat(20.0));
    try std.testing.expect(!pos.isAtFront());
    try std.testing.expectApproxEqAbs(
        @as(f64, 30.0),
        pos.total_quantity_ahead.toFloat(),
        0.001,
    );
}

test "PriceLevel: order queue management" {
    const allocator = std.testing.allocator;

    var level = try PriceLevel.init(allocator, Decimal.fromInt(2000));
    defer level.deinit(allocator);

    // Add order IDs
    _ = try level.addOrderId(allocator, 1, Decimal.fromFloat(10.0));
    _ = try level.addOrderId(allocator, 2, Decimal.fromFloat(15.0));
    const pos3 = try level.addOrderId(allocator, 3, Decimal.fromFloat(25.0));

    // Verify positions
    try std.testing.expectEqual(@as(usize, 2), pos3);
    try std.testing.expectEqual(@as(usize, 3), level.orderCount());

    // Total quantity
    try std.testing.expectApproxEqAbs(
        @as(f64, 50.0),
        level.total_quantity.toFloat(),
        0.001,
    );

    // Front order
    try std.testing.expectEqual(@as(?u64, 1), level.frontOrderId());
}

test "Level3OrderBook: basic operations" {
    const allocator = std.testing.allocator;

    var book = Level3OrderBook.init(allocator, "ETH");
    defer book.deinit();

    // Add buy orders
    const id1 = try book.addOrder(.buy, Decimal.fromInt(2000), Decimal.fromFloat(10.0), 1000);
    const id2 = try book.addOrder(.buy, Decimal.fromInt(2000), Decimal.fromFloat(15.0), 1001);
    const id3 = try book.addOrder(.buy, Decimal.fromInt(1999), Decimal.fromFloat(20.0), 1002);

    // Add sell orders
    _ = try book.addOrder(.sell, Decimal.fromInt(2001), Decimal.fromFloat(5.0), 1003);

    try std.testing.expectEqual(@as(usize, 4), book.orderCount());

    // Check best bid/ask
    const best_bid = book.bestBid();
    try std.testing.expect(best_bid != null);
    try std.testing.expectEqual(@as(i128, 2000 * Decimal.MULTIPLIER), best_bid.?.value);

    const best_ask = book.bestAsk();
    try std.testing.expect(best_ask != null);
    try std.testing.expectEqual(@as(i128, 2001 * Decimal.MULTIPLIER), best_ask.?.value);

    // Check queue position of second order at same price
    const order2 = book.getOrder(id2);
    try std.testing.expect(order2 != null);
    try std.testing.expectEqual(@as(usize, 1), order2.?.queue_position.position_in_queue);

    // Cancel first order
    try std.testing.expect(book.cancelOrder(id1));
    try std.testing.expectEqual(@as(usize, 3), book.orderCount());

    _ = id3;
}

test "Level3OrderBook: trade processing" {
    const allocator = std.testing.allocator;

    var book = Level3OrderBook.init(allocator, "ETH");
    defer book.deinit();

    // Add sell orders at 2001
    _ = try book.addOrder(.sell, Decimal.fromInt(2001), Decimal.fromFloat(10.0), 1000);
    _ = try book.addOrder(.sell, Decimal.fromInt(2001), Decimal.fromFloat(20.0), 1001);

    // Process buy trade (consumes asks)
    book.onTrade(.buy, Decimal.fromInt(2001), Decimal.fromFloat(15.0));

    // Should have consumed first order and 5 from second
    try std.testing.expectApproxEqAbs(
        @as(f64, 15.0),
        book.askDepth().toFloat(),
        0.001,
    );
}

test "Level3OrderBook: fill check" {
    const allocator = std.testing.allocator;

    var book = Level3OrderBook.init(allocator, "ETH");
    defer book.deinit();

    // Add my buy order
    const my_order = try book.addOrder(.buy, Decimal.fromInt(2000), Decimal.fromFloat(1.0), 1000);

    // My order is at front, should fill on sell trade at same price
    try std.testing.expect(book.checkMyOrderFill(my_order, Decimal.fromInt(2000), .sell));

    // Should not fill on buy trade (same side)
    try std.testing.expect(!book.checkMyOrderFill(my_order, Decimal.fromInt(2000), .buy));

    // Should not fill at different price
    try std.testing.expect(!book.checkMyOrderFill(my_order, Decimal.fromInt(2001), .sell));
}
