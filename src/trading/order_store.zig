//! Order Store - 订单存储和索引
//!
//! 提供订单的存储、索引和查询功能：
//! - 按 client_order_id 索引（用户生成的唯一 ID）
//! - 按 exchange_order_id 索引（交易所返回的 ID）
//! - 活跃订单列表（pending, open）
//! - 历史订单列表（filled, cancelled, rejected）
//!
//! 线程安全：调用方负责同步（通常由 OrderManager 的 mutex 保护）

const std = @import("std");
const Order = @import("../exchange/types.zig").Order;
const OrderStatus = @import("../exchange/types.zig").OrderStatus;

// ============================================================================
// Order Store
// ============================================================================

pub const OrderStore = struct {
    allocator: std.mem.Allocator,

    // 按 client_order_id 索引（UUID 字符串）
    orders_by_client_id: std.StringHashMap(*Order),

    // 按 exchange_order_id 索引（交易所返回的订单 ID）
    orders_by_exchange_id: std.AutoHashMap(u64, *Order),

    // 活跃订单列表（pending, open）
    active_orders: std.ArrayList(*Order),

    // 历史订单列表（filled, cancelled, rejected）
    history_orders: std.ArrayList(*Order),

    /// Initialize order store
    pub fn init(allocator: std.mem.Allocator) OrderStore {
        return .{
            .allocator = allocator,
            .orders_by_client_id = std.StringHashMap(*Order).init(allocator),
            .orders_by_exchange_id = std.AutoHashMap(u64, *Order).init(allocator),
            .active_orders = std.ArrayList(*Order).initCapacity(allocator, 0) catch unreachable,
            .history_orders = std.ArrayList(*Order).initCapacity(allocator, 0) catch unreachable,
        };
    }

    /// Cleanup
    pub fn deinit(self: *OrderStore) void {
        // Free all orders and their client_order_id keys
        var iter = self.orders_by_client_id.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*); // Free the key
            self.allocator.destroy(entry.value_ptr.*); // Free the Order object
        }

        self.orders_by_client_id.deinit();
        self.orders_by_exchange_id.deinit();
        self.active_orders.deinit(self.allocator);
        self.history_orders.deinit(self.allocator);
    }

    /// Add a new order
    ///
    /// The order is added to active_orders and indexed by client_order_id
    /// If exchange_order_id is present, it's also indexed by that
    pub fn add(self: *OrderStore, order: Order) !void {
        // Client order ID must be present
        const client_order_id = order.client_order_id orelse return error.MissingClientOrderId;

        // Duplicate the order on heap
        const order_ptr = try self.allocator.create(Order);
        errdefer self.allocator.destroy(order_ptr);
        order_ptr.* = order;

        // Duplicate client_order_id for the hash map key
        const client_id_key = try self.allocator.dupe(u8, client_order_id);
        errdefer self.allocator.free(client_id_key);

        try self.orders_by_client_id.put(client_id_key, order_ptr);

        // Add to exchange_order_id index if present
        if (order.exchange_order_id) |oid| {
            try self.orders_by_exchange_id.put(oid, order_ptr);
        }

        try self.active_orders.append(self.allocator, order_ptr);
    }

    /// Update an existing order
    ///
    /// Updates the exchange_order_id index if present
    /// Moves order from active to history if status is final
    pub fn update(self: *OrderStore, client_order_id: []const u8) !void {
        const order = self.orders_by_client_id.get(client_order_id) orelse return error.OrderNotFound;

        // Update exchange_order_id index if present
        if (order.exchange_order_id) |oid| {
            try self.orders_by_exchange_id.put(oid, order);
        }

        // Move to history if status is final
        if (isStatusFinal(order.status)) {
            // Find and remove from active_orders
            for (self.active_orders.items, 0..) |active_order, i| {
                if (active_order == order) {
                    _ = self.active_orders.swapRemove(i);
                    try self.history_orders.append(self.allocator, order);
                    break;
                }
            }
        }
    }

    /// Get order by client_order_id
    pub fn getByClientId(self: *OrderStore, client_order_id: []const u8) ?*Order {
        return self.orders_by_client_id.get(client_order_id);
    }

    /// Get order by exchange_order_id
    pub fn getByExchangeId(self: *OrderStore, exchange_order_id: u64) ?*Order {
        return self.orders_by_exchange_id.get(exchange_order_id);
    }

    /// Get all active orders
    ///
    /// Returns a slice that must be freed by caller
    pub fn getActive(self: *OrderStore) ![]const *Order {
        return try self.allocator.dupe(*Order, self.active_orders.items);
    }

    /// Get order history
    ///
    /// @param pair: Optional filter by trading pair
    /// @param limit: Optional limit on number of results
    /// Returns a slice that must be freed by caller
    pub fn getHistory(
        self: *OrderStore,
        pair: ?[]const u8,
        limit: ?usize,
    ) ![]const *Order {
        var result = std.ArrayList(*Order).initCapacity(self.allocator, 0) catch unreachable;
        defer result.deinit();

        for (self.history_orders.items) |order| {
            // Filter by pair if specified
            if (pair) |p| {
                const matches_base = std.mem.eql(u8, order.pair.base, p);
                const matches_full = blk: {
                    var buf: [64]u8 = undefined;
                    const full_pair = std.fmt.bufPrint(&buf, "{s}-{s}", .{ order.pair.base, order.pair.quote }) catch break :blk false;
                    break :blk std.mem.eql(u8, full_pair, p);
                };

                if (!matches_base and !matches_full) continue;
            }

            try result.append(self.allocator, order);

            // Check limit
            if (limit) |l| {
                if (result.items.len >= l) break;
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    /// Get count of active orders
    pub fn getActiveCount(self: *OrderStore) usize {
        return self.active_orders.items.len;
    }

    /// Get count of history orders
    pub fn getHistoryCount(self: *OrderStore) usize {
        return self.history_orders.items.len;
    }

    /// Check if an order status is final (cannot change anymore)
    fn isStatusFinal(status: OrderStatus) bool {
        return switch (status) {
            .filled, .cancelled, .rejected => true,
            .pending, .open, .partially_filled => false,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "OrderStore: init and deinit" {
    const allocator = std.testing.allocator;
    var store = OrderStore.init(allocator);
    defer store.deinit();

    try std.testing.expectEqual(@as(usize, 0), store.getActiveCount());
    try std.testing.expectEqual(@as(usize, 0), store.getHistoryCount());
}

test "OrderStore: add and retrieve by client ID" {
    const allocator = std.testing.allocator;
    const TradingPair = @import("../exchange/types.zig").TradingPair;
    const Side = @import("../exchange/types.zig").Side;
    const Decimal = @import("../core/decimal.zig").Decimal;
    const Timestamp = @import("../core/time.zig").Timestamp;

    var store = OrderStore.init(allocator);
    defer store.deinit();

    const order = Order{
        .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
        .side = .buy,
        .order_type = .limit,
        .amount = try Decimal.fromString("1.0"),
        .price = try Decimal.fromString("2000.0"),
        .status = .pending,
        .client_order_id = "test-order-123",
        .exchange_order_id = null,
        .filled_amount = Decimal.ZERO,
        .avg_fill_price = null,
        .created_at = Timestamp.now(),
        .updated_at = Timestamp.now(),
    };

    try store.add(order);

    const retrieved = store.getByClientId("test-order-123");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(Side.buy, retrieved.?.side);
    try std.testing.expectEqual(@as(usize, 1), store.getActiveCount());
}
