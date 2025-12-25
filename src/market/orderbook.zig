// Orderbook - L2 Order Book Management
//
// Provides efficient order book data structures for tracking market depth.
// Supports snapshot and incremental updates from exchange WebSocket feeds.
//
// Features:
// - Level-2 aggregated price levels
// - Efficient snapshot and delta updates
// - Best bid/ask queries (O(1))
// - Depth and slippage calculations
// - Thread-safe multi-symbol management
//
// Design:
// - Bids sorted descending (highest price first)
// - Asks sorted ascending (lowest price first)
// - O(1) best price access
// - O(n log n) snapshot application
// - O(n) incremental updates

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;

// ============================================================================
// Type Definitions
// ============================================================================

/// Side of the order book
pub const Side = enum {
    bid, // Buy orders
    ask, // Sell orders
};

/// Price level in the order book
pub const Level = struct {
    price: Decimal, // Price level
    size: Decimal, // Total size at this price
    num_orders: u32, // Number of orders at this price

    /// Compare function for sorting (ascending by price)
    pub fn lessThan(context: void, a: Level, b: Level) bool {
        _ = context;
        return a.price.cmp(b.price) == .lt;
    }

    /// Compare function for sorting (descending by price)
    pub fn greaterThan(context: void, a: Level, b: Level) bool {
        _ = context;
        return a.price.cmp(b.price) == .gt;
    }
};

/// Slippage calculation result
pub const SlippageResult = struct {
    avg_price: Decimal, // Average execution price
    slippage_pct: Decimal, // Slippage percentage (0.01 = 1%)
    total_cost: Decimal, // Total cost
};

/// L2 Order Book
pub const OrderBook = struct {
    allocator: Allocator,
    symbol: []const u8,

    // Bids: sorted descending (highest price first at index 0)
    bids: std.ArrayList(Level),

    // Asks: sorted ascending (lowest price first at index 0)
    asks: std.ArrayList(Level),

    // Metadata
    last_update_time: Timestamp,
    sequence: u64,

    // ========================================================================
    // Initialization and Cleanup
    // ========================================================================

    /// Create a new order book
    pub fn init(allocator: Allocator, symbol: []const u8) !OrderBook {
        // Duplicate symbol to ensure we own the memory
        const owned_symbol = try allocator.dupe(u8, symbol);
        errdefer allocator.free(owned_symbol);

        return OrderBook{
            .allocator = allocator,
            .symbol = owned_symbol,
            .bids = try std.ArrayList(Level).initCapacity(allocator, 0),
            .asks = try std.ArrayList(Level).initCapacity(allocator, 0),
            .last_update_time = Timestamp.now(),
            .sequence = 0,
        };
    }

    /// Free resources
    pub fn deinit(self: *OrderBook) void {
        self.allocator.free(self.symbol);
        self.bids.deinit(self.allocator);
        self.asks.deinit(self.allocator);
    }

    // ========================================================================
    // Update Operations
    // ========================================================================

    /// Apply full snapshot, replacing current order book
    pub fn applySnapshot(
        self: *OrderBook,
        bids: []const Level,
        asks: []const Level,
        timestamp: Timestamp,
    ) !void {
        // Clear existing data while retaining capacity
        self.bids.clearRetainingCapacity();
        self.asks.clearRetainingCapacity();

        // Insert and sort bids (descending: highest price first)
        try self.bids.appendSlice(self.allocator, bids);
        std.mem.sort(Level, self.bids.items, {}, Level.greaterThan);

        // Insert and sort asks (ascending: lowest price first)
        try self.asks.appendSlice(self.allocator, asks);
        std.mem.sort(Level, self.asks.items, {}, Level.lessThan);

        self.last_update_time = timestamp;
        self.sequence = 0;
    }

    /// Apply incremental update
    /// size = 0 means remove the level
    pub fn applyUpdate(
        self: *OrderBook,
        side: Side,
        price: Decimal,
        size: Decimal,
        num_orders: u32,
        timestamp: Timestamp,
    ) !void {
        const levels = if (side == .bid) &self.bids else &self.asks;

        if (size.isZero()) {
            // Remove level
            try self.removeLevel(levels, price);
        } else {
            // Update or insert
            try self.upsertLevel(levels, .{
                .price = price,
                .size = size,
                .num_orders = num_orders,
            }, side);
        }

        self.last_update_time = timestamp;
        self.sequence += 1;
    }

    // ========================================================================
    // Query Operations
    // ========================================================================

    /// Get best bid (highest buy price)
    pub fn getBestBid(self: *const OrderBook) ?Level {
        if (self.bids.items.len == 0) return null;
        return self.bids.items[0];
    }

    /// Get best ask (lowest sell price)
    pub fn getBestAsk(self: *const OrderBook) ?Level {
        if (self.asks.items.len == 0) return null;
        return self.asks.items[0];
    }

    /// Get mid price (average of best bid and ask)
    pub fn getMidPrice(self: *const OrderBook) !?Decimal {
        const bid = self.getBestBid() orelse return null;
        const ask = self.getBestAsk() orelse return null;
        const sum = bid.price.add(ask.price);
        return try sum.div(Decimal.fromInt(2));
    }

    /// Get spread (difference between best ask and bid)
    pub fn getSpread(self: *const OrderBook) ?Decimal {
        const bid = self.getBestBid() orelse return null;
        const ask = self.getBestAsk() orelse return null;
        return ask.price.sub(bid.price);
    }

    /// Get total depth up to a target price
    pub fn getDepth(self: *const OrderBook, side: Side, target_price: Decimal) Decimal {
        const levels = if (side == .bid) self.bids.items else self.asks.items;
        var total_depth = Decimal.ZERO;

        for (levels) |level| {
            // For bids: accumulate if level price >= target
            // For asks: accumulate if level price <= target
            const should_include = if (side == .bid)
                level.price.cmp(target_price) != .lt
            else
                level.price.cmp(target_price) != .gt;

            if (should_include) {
                total_depth = total_depth.add(level.size);
            } else {
                break;
            }
        }

        return total_depth;
    }

    /// Calculate slippage for a market order of given quantity
    pub fn getSlippage(self: *const OrderBook, side: Side, quantity: Decimal) ?SlippageResult {
        const levels = if (side == .bid) self.asks.items else self.bids.items;
        if (levels.len == 0) return null;

        const best_price = levels[0].price;
        var remaining = quantity;
        var total_cost = Decimal.ZERO;
        var weighted_price_sum = Decimal.ZERO;

        for (levels) |level| {
            if (remaining.isZero()) break;

            const fill_size = if (remaining.cmp(level.size) == .lt)
                remaining
            else
                level.size;

            const cost = fill_size.mul(level.price);
            total_cost = total_cost.add(cost);
            weighted_price_sum = weighted_price_sum.add(cost);
            remaining = remaining.sub(fill_size);
        }

        // If couldn't fill entire order, return null
        if (!remaining.isZero()) return null;

        const avg_price = total_cost.div(quantity);
        const slippage = avg_price.sub(best_price).div(best_price).abs();

        return .{
            .avg_price = avg_price,
            .slippage_pct = slippage,
            .total_cost = total_cost,
        };
    }

    // ========================================================================
    // Internal Helper Methods
    // ========================================================================

    /// Remove a price level
    fn removeLevel(self: *OrderBook, levels: *std.ArrayList(Level), price: Decimal) !void {
        _ = self;
        var i: usize = 0;
        while (i < levels.items.len) : (i += 1) {
            if (levels.items[i].price.cmp(price) == .eq) {
                _ = levels.orderedRemove(i);
                return;
            }
        }
    }

    /// Update existing level or insert new one
    fn upsertLevel(
        self: *OrderBook,
        levels: *std.ArrayList(Level),
        new_level: Level,
        side: Side,
    ) !void {
        // Find existing level
        for (levels.items) |*level| {
            if (level.price.cmp(new_level.price) == .eq) {
                // Update existing level
                level.size = new_level.size;
                level.num_orders = new_level.num_orders;
                return;
            }
        }

        // Insert new level and re-sort
        try levels.append(self.allocator, new_level);
        if (side == .bid) {
            std.mem.sort(Level, levels.items, {}, Level.greaterThan);
        } else {
            std.mem.sort(Level, levels.items, {}, Level.lessThan);
        }
    }
};

/// Multi-symbol order book manager with thread-safe access
pub const OrderBookManager = struct {
    allocator: Allocator,
    orderbooks: std.StringHashMap(*OrderBook),
    mutex: std.Thread.Mutex,

    // ========================================================================
    // Initialization and Cleanup
    // ========================================================================

    pub fn init(allocator: Allocator) OrderBookManager {
        return .{
            .allocator = allocator,
            .orderbooks = std.StringHashMap(*OrderBook).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *OrderBookManager) void {
        var iter = self.orderbooks.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.orderbooks.deinit();
    }

    // ========================================================================
    // Operations
    // ========================================================================

    /// Get or create order book for a symbol
    pub fn getOrCreate(self: *OrderBookManager, symbol: []const u8) !*OrderBook {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.orderbooks.get(symbol)) |ob| {
            return ob;
        }

        // Create new order book
        const ob = try self.allocator.create(OrderBook);
        errdefer self.allocator.destroy(ob);

        ob.* = try OrderBook.init(self.allocator, symbol);
        errdefer ob.deinit();

        // Use the owned symbol from OrderBook as the HashMap key
        try self.orderbooks.put(ob.symbol, ob);

        return ob;
    }

    /// Get existing order book
    pub fn get(self: *OrderBookManager, symbol: []const u8) ?*OrderBook {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.orderbooks.get(symbol);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Level comparison" {
    const testing = std.testing;

    const a = Level{
        .price = Decimal.fromInt(100),
        .size = Decimal.fromInt(10),
        .num_orders = 1,
    };
    const b = Level{
        .price = Decimal.fromInt(200),
        .size = Decimal.fromInt(20),
        .num_orders = 1,
    };

    try testing.expect(Level.lessThan({}, a, b));
    try testing.expect(Level.greaterThan({}, b, a));
}

test "OrderBook init and deinit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ob = try OrderBook.init(allocator, "BTC");
    defer ob.deinit();

    try testing.expectEqualStrings("BTC", ob.symbol);
    try testing.expectEqual(@as(usize, 0), ob.bids.items.len);
    try testing.expectEqual(@as(usize, 0), ob.asks.items.len);
}

test "OrderBook applySnapshot" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = Decimal.fromInt(2000), .size = Decimal.fromInt(10), .num_orders = 1 },
        .{ .price = Decimal.fromInt(1999), .size = Decimal.fromInt(20), .num_orders = 2 },
    };
    const asks = &[_]Level{
        .{ .price = Decimal.fromInt(2001), .size = Decimal.fromInt(8), .num_orders = 1 },
        .{ .price = Decimal.fromInt(2002), .size = Decimal.fromInt(15), .num_orders = 1 },
    };

    try ob.applySnapshot(bids, asks, Timestamp.now());

    // Check bids sorted descending
    try testing.expectEqual(@as(usize, 2), ob.bids.items.len);
    try testing.expect(ob.bids.items[0].price.cmp(Decimal.fromInt(2000)) == .eq);
    try testing.expect(ob.bids.items[1].price.cmp(Decimal.fromInt(1999)) == .eq);

    // Check asks sorted ascending
    try testing.expectEqual(@as(usize, 2), ob.asks.items.len);
    try testing.expect(ob.asks.items[0].price.cmp(Decimal.fromInt(2001)) == .eq);
    try testing.expect(ob.asks.items[1].price.cmp(Decimal.fromInt(2002)) == .eq);
}

test "OrderBook getBestBid and getBestAsk" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ob = try OrderBook.init(allocator, "BTC");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = Decimal.fromInt(50000), .size = Decimal.fromInt(1), .num_orders = 1 },
        .{ .price = Decimal.fromInt(49999), .size = Decimal.fromInt(2), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = Decimal.fromInt(50001), .size = Decimal.fromInt(1), .num_orders = 1 },
        .{ .price = Decimal.fromInt(50002), .size = Decimal.fromInt(2), .num_orders = 1 },
    };

    try ob.applySnapshot(bids, asks, Timestamp.now());

    const best_bid = ob.getBestBid().?;
    const best_ask = ob.getBestAsk().?;

    try testing.expect(best_bid.price.cmp(Decimal.fromInt(50000)) == .eq);
    try testing.expect(best_ask.price.cmp(Decimal.fromInt(50001)) == .eq);
}

test "OrderBook getMidPrice and getSpread" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = Decimal.fromInt(2000), .size = Decimal.fromInt(10), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = Decimal.fromInt(2002), .size = Decimal.fromInt(8), .num_orders = 1 },
    };

    try ob.applySnapshot(bids, asks, Timestamp.now());

    const mid = (try ob.getMidPrice()).?;
    const spread = ob.getSpread().?;

    try testing.expect(mid.cmp(Decimal.fromInt(2001)) == .eq);
    try testing.expect(spread.cmp(Decimal.fromInt(2)) == .eq);
}

test "OrderBook applyUpdate - insert" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ob = try OrderBook.init(allocator, "BTC");
    defer ob.deinit();

    // Initial snapshot
    const bids = &[_]Level{
        .{ .price = Decimal.fromInt(50000), .size = Decimal.fromInt(1), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, &[_]Level{}, Timestamp.now());

    // Add new bid
    try ob.applyUpdate(.bid, Decimal.fromInt(49999), Decimal.fromInt(2), 1, Timestamp.now());

    try testing.expectEqual(@as(usize, 2), ob.bids.items.len);
    try testing.expect(ob.bids.items[0].price.cmp(Decimal.fromInt(50000)) == .eq);
    try testing.expect(ob.bids.items[1].price.cmp(Decimal.fromInt(49999)) == .eq);
}

test "OrderBook applyUpdate - remove" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ob = try OrderBook.init(allocator, "BTC");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = Decimal.fromInt(50000), .size = Decimal.fromInt(1), .num_orders = 1 },
        .{ .price = Decimal.fromInt(49999), .size = Decimal.fromInt(2), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, &[_]Level{}, Timestamp.now());

    // Remove a level
    try ob.applyUpdate(.bid, Decimal.fromInt(49999), Decimal.ZERO, 0, Timestamp.now());

    try testing.expectEqual(@as(usize, 1), ob.bids.items.len);
    try testing.expect(ob.bids.items[0].price.cmp(Decimal.fromInt(50000)) == .eq);
}

test "OrderBookManager getOrCreate" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = OrderBookManager.init(allocator);
    defer manager.deinit();

    const ob1 = try manager.getOrCreate("BTC");
    const ob2 = try manager.getOrCreate("BTC");
    const ob3 = try manager.getOrCreate("ETH");

    try testing.expect(ob1 == ob2); // Same instance
    try testing.expect(ob1 != ob3); // Different instance
    try testing.expectEqualStrings("BTC", ob1.symbol);
    try testing.expectEqualStrings("ETH", ob3.symbol);
}
