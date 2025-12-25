//! Order Manager - 订单生命周期管理
//!
//! 提供订单管理功能：
//! - 订单提交和验证
//! - 订单状态同步
//! - 订单取消和批量取消
//! - 订单历史记录
//! - WebSocket 事件处理
//!
//! 设计特点：
//! - 基于 IExchange 接口（交易所无关）
//! - 线程安全（使用 Mutex）
//! - 回调机制（订单更新、成交）

const std = @import("std");
const IExchange = @import("../exchange/interface.zig").IExchange;
const types = @import("../exchange/types.zig");
const OrderStore = @import("order_store.zig").OrderStore;
const Logger = @import("../core/logger.zig").Logger;
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;

// Re-export types
const TradingPair = types.TradingPair;
const Side = types.Side;
const OrderType = types.OrderType;
const OrderStatus = types.OrderStatus;
const TimeInForce = types.TimeInForce;
const OrderRequest = types.OrderRequest;
const Order = types.Order;
const OrderUpdateEvent = types.OrderUpdateEvent;
const OrderFillEvent = types.OrderFillEvent;

// ============================================================================
// Order Manager
// ============================================================================

pub const OrderManager = struct {
    allocator: std.mem.Allocator,
    exchange: IExchange,
    order_store: OrderStore,
    logger: Logger,
    mutex: std.Thread.Mutex,

    // Callbacks
    on_order_update: ?*const fn (*Order) void,
    on_order_fill: ?*const fn (*Order) void,

    // Client order ID counter (for generating unique IDs)
    next_client_order_id: std.atomic.Value(u64),

    /// Initialize order manager
    ///
    /// @param allocator: Memory allocator
    /// @param exchange: IExchange implementation
    /// @param logger: Logger instance
    pub fn init(
        allocator: std.mem.Allocator,
        exchange: IExchange,
        logger: Logger,
    ) OrderManager {
        return .{
            .allocator = allocator,
            .exchange = exchange,
            .order_store = OrderStore.init(allocator),
            .logger = logger,
            .mutex = .{},
            .on_order_update = null,
            .on_order_fill = null,
            .next_client_order_id = std.atomic.Value(u64).init(1),
        };
    }

    /// Cleanup
    pub fn deinit(self: *OrderManager) void {
        self.order_store.deinit();
    }

    /// Submit an order to the exchange
    ///
    /// @param pair: Trading pair
    /// @param side: Buy or sell
    /// @param order_type: Limit or market
    /// @param amount: Order amount
    /// @param price: Order price (required for limit orders)
    /// @param time_in_force: Time in force (default: GTC)
    /// @param reduce_only: Reduce-only flag (default: false)
    /// @return Order with exchange_order_id populated
    pub fn submitOrder(
        self: *OrderManager,
        pair: TradingPair,
        side: Side,
        order_type: OrderType,
        amount: Decimal,
        price: ?Decimal,
        time_in_force: TimeInForce,
        reduce_only: bool,
    ) !Order {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Generate client order ID
        // Note: Memory is NOT freed here - ownership transfers to order_store
        const client_id_num = self.next_client_order_id.fetchAdd(1, .monotonic);
        const client_order_id = try std.fmt.allocPrint(
            self.allocator,
            "order-{d}-{d}",
            .{ std.time.milliTimestamp(), client_id_num },
        );

        // Create order object
        const order = Order{
            .pair = pair,
            .side = side,
            .order_type = order_type,
            .amount = amount,
            .price = price,
            .status = .pending,
            .client_order_id = client_order_id,
            .exchange_order_id = null,
            .filled_amount = Decimal.ZERO,
            .avg_fill_price = null,
            .created_at = Timestamp.now(),
            .updated_at = Timestamp.now(),
        };

        self.logger.info("Submitting order: {s} {s} {s} {} @ {?}", .{
            @tagName(side),
            pair.base,
            @tagName(order_type),
            amount.toFloat(),
            if (price) |p| p.toFloat() else null,
        }) catch {};

        // Validate order
        if (order_type == .limit and price == null) {
            return error.LimitOrderRequiresPrice;
        }

        // Store order before submission
        // Note: order_store duplicates client_order_id, so we can free the original
        try self.order_store.add(order);
        defer self.allocator.free(client_order_id); // Free original after duplication

        // Create order request
        const request = OrderRequest{
            .pair = pair,
            .side = side,
            .order_type = order_type,
            .amount = amount,
            .price = price,
            .time_in_force = time_in_force,
            .reduce_only = reduce_only,
        };

        // Submit to exchange
        const submitted_order = self.exchange.createOrder(request) catch |err| {
            self.logger.err("Order submission failed: {}", .{err}) catch {};

            // Update order status to rejected
            if (self.order_store.getByClientId(client_order_id)) |stored_order| {
                stored_order.status = .rejected;
                stored_order.updated_at = Timestamp.now();
                self.order_store.update(client_order_id) catch {};
            }

            return err;
        };

        // Update stored order with exchange response
        if (self.order_store.getByClientId(client_order_id)) |stored_order| {
            stored_order.exchange_order_id = submitted_order.exchange_order_id;
            stored_order.status = submitted_order.status;
            stored_order.filled_amount = submitted_order.filled_amount;
            stored_order.avg_fill_price = submitted_order.avg_fill_price;
            stored_order.updated_at = Timestamp.now();
            try self.order_store.update(client_order_id);

            self.logger.info("Order submitted: client_id={s}, exchange_id={?}, status={s}", .{
                client_order_id,
                submitted_order.exchange_order_id,
                @tagName(submitted_order.status),
            }) catch {};

            // Trigger callback
            if (self.on_order_update) |callback| {
                callback(stored_order);
            }

            return stored_order.*;
        }

        return submitted_order;
    }

    /// Cancel an order by exchange order ID
    ///
    /// @param exchange_order_id: Exchange order ID
    pub fn cancelOrder(self: *OrderManager, exchange_order_id: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.logger.info("Cancelling order: exchange_id={d}", .{exchange_order_id}) catch {};

        // Find order in store
        const order = self.order_store.getByExchangeId(exchange_order_id) orelse {
            self.logger.err("Order not found in store: {d}", .{exchange_order_id}) catch {};
            return error.OrderNotFound;
        };

        // Check if order is cancellable
        if (!isOrderCancellable(order.status)) {
            self.logger.err("Order not cancellable: status={s}", .{@tagName(order.status)}) catch {};
            return error.OrderNotCancellable;
        }

        // Cancel on exchange
        try self.exchange.cancelOrder(exchange_order_id);

        // Update order status
        order.status = .cancelled;
        order.updated_at = Timestamp.now();

        const client_id = order.client_order_id orelse {
            return error.MissingClientOrderId;
        };
        try self.order_store.update(client_id);

        self.logger.info("Order cancelled: exchange_id={d}", .{exchange_order_id}) catch {};

        // Trigger callback
        if (self.on_order_update) |callback| {
            callback(order);
        }
    }

    /// Cancel all orders (optionally for a specific pair)
    ///
    /// @param pair: Optional trading pair filter
    /// @return Number of orders cancelled
    pub fn cancelAllOrders(self: *OrderManager, pair: ?TradingPair) !u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.logger.info("Cancelling all orders for pair: {s}", .{
            if (pair) |p| p.base else "ALL",
        }) catch {};

        // Cancel on exchange
        const cancelled_count = try self.exchange.cancelAllOrders(pair);

        // Update local order statuses
        const active_orders = try self.order_store.getActive();
        defer self.allocator.free(active_orders);

        for (active_orders) |order| {
            // Filter by pair if specified
            if (pair) |p| {
                if (!std.mem.eql(u8, order.pair.base, p.base)) continue;
            }

            if (isOrderCancellable(order.status)) {
                order.status = .cancelled;
                order.updated_at = Timestamp.now();
                self.order_store.update(order.client_order_id) catch {};

                // Trigger callback
                if (self.on_order_update) |callback| {
                    callback(order);
                }
            }
        }

        self.logger.info("Cancelled {d} orders", .{cancelled_count}) catch {};

        return cancelled_count;
    }

    /// Get all active orders
    ///
    /// Returns a slice that must be freed by caller
    pub fn getActiveOrders(self: *OrderManager) ![]const *Order {
        self.mutex.lock();
        defer self.mutex.unlock();

        return try self.order_store.getActive();
    }

    /// Get order history
    ///
    /// @param pair: Optional filter by trading pair
    /// @param limit: Optional limit on number of results
    /// Returns a slice that must be freed by caller
    pub fn getOrderHistory(
        self: *OrderManager,
        pair: ?[]const u8,
        limit: ?usize,
    ) ![]const *Order {
        self.mutex.lock();
        defer self.mutex.unlock();

        return try self.order_store.getHistory(pair, limit);
    }

    /// Get order by client ID
    pub fn getOrderByClientId(self: *OrderManager, client_order_id: []const u8) ?*Order {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.order_store.getByClientId(client_order_id);
    }

    /// Get order by exchange ID
    pub fn getOrderByExchangeId(self: *OrderManager, exchange_order_id: u64) ?*Order {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.order_store.getByExchangeId(exchange_order_id);
    }

    /// Refresh order status from exchange
    ///
    /// @param exchange_order_id: Exchange order ID
    pub fn refreshOrderStatus(self: *OrderManager, exchange_order_id: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const order = self.order_store.getByExchangeId(exchange_order_id) orelse {
            return error.OrderNotFound;
        };

        // Query from exchange
        const updated_order = try self.exchange.getOrder(exchange_order_id);

        // Update local order
        order.status = updated_order.status;
        order.filled_amount = updated_order.filled_amount;
        order.avg_fill_price = updated_order.avg_fill_price;
        order.updated_at = Timestamp.now();

        const client_id = order.client_order_id orelse {
            return error.MissingClientOrderId;
        };
        try self.order_store.update(client_id);

        self.logger.info("Order status refreshed: exchange_id={d}, status={s}", .{
            exchange_order_id,
            @tagName(updated_order.status),
        }) catch {};

        // Trigger callback
        if (self.on_order_update) |callback| {
            callback(order);
        }
    }

    /// Get statistics
    pub fn getStats(self: *OrderManager) Stats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .active_count = self.order_store.getActiveCount(),
            .history_count = self.order_store.getHistoryCount(),
        };
    }

    /// Handle order update event (from WebSocket or polling)
    ///
    /// @param event: Order update event with latest status
    pub fn handleOrderUpdate(self: *OrderManager, event: OrderUpdateEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find order by exchange ID
        const order = self.order_store.getByExchangeId(event.exchange_order_id) orelse {
            self.logger.warn("Order update for unknown order: {d}", .{event.exchange_order_id}) catch {};
            return; // Ignore updates for unknown orders
        };

        // Update order fields
        const old_status = order.status;
        order.status = event.status;
        order.filled_amount = event.filled_amount;
        order.avg_fill_price = event.avg_fill_price;
        order.updated_at = event.timestamp;

        // Update in store (may move to history if status is final)
        try self.order_store.update(order.client_order_id.?);

        self.logger.info("Order {d} status updated: {s} -> {s}, filled: {}", .{
            event.exchange_order_id,
            @tagName(old_status),
            @tagName(event.status),
            event.filled_amount.toFloat(),
        }) catch {};

        // Trigger callback if registered
        if (self.on_order_update) |callback| {
            callback(order);
        }

        // Trigger fill callback if order was filled
        if (event.status == .filled and old_status != .filled) {
            if (self.on_order_fill) |callback| {
                callback(order);
            }
        }
    }

    /// Handle order fill event (from WebSocket)
    ///
    /// @param event: Order fill/execution event
    pub fn handleOrderFill(self: *OrderManager, event: OrderFillEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find order by exchange ID
        const order = self.order_store.getByExchangeId(event.exchange_order_id) orelse {
            self.logger.warn("Fill event for unknown order: {d}", .{event.exchange_order_id}) catch {};
            return; // Ignore fills for unknown orders
        };

        // Update filled amount
        order.filled_amount = event.total_filled;

        // Update average fill price (weighted average)
        if (order.avg_fill_price) |avg| {
            // Calculate new weighted average: (old_avg * old_filled + new_px * new_filled) / total_filled
            const old_filled = order.filled_amount.sub(event.fill_amount);
            const old_value = avg.mul(old_filled);
            const new_value = event.fill_price.mul(event.fill_amount);
            order.avg_fill_price = try old_value.add(new_value).div(event.total_filled);
        } else {
            order.avg_fill_price = event.fill_price;
        }

        // Update status if fully filled
        if (order.filled_amount.eql(order.amount)) {
            order.status = .filled;
        } else if (order.filled_amount.cmp(Decimal.ZERO) == .gt) {
            order.status = .partially_filled;
        }

        order.updated_at = event.timestamp;

        // Update in store
        try self.order_store.update(order.client_order_id.?);

        self.logger.info("Order {d} filled: {} @ {}, total filled: {}", .{
            event.exchange_order_id,
            event.fill_amount.toFloat(),
            event.fill_price.toFloat(),
            event.total_filled.toFloat(),
        }) catch {};

        // Trigger callbacks
        if (self.on_order_update) |callback| {
            callback(order);
        }

        if (order.status == .filled) {
            if (self.on_order_fill) |callback| {
                callback(order);
            }
        }
    }

    /// Check if order status allows cancellation
    fn isOrderCancellable(status: OrderStatus) bool {
        return switch (status) {
            .pending, .open, .partially_filled => true,
            .filled, .cancelled, .rejected => false,
        };
    }

    pub const Stats = struct {
        active_count: usize,
        history_count: usize,
    };
};

// ============================================================================
// Tests
// ============================================================================

test "OrderManager: init and deinit" {
    const allocator = std.testing.allocator;

    // Create mock exchange
    const MockExchange = struct {
        fn getName(_: *anyopaque) []const u8 {
            return "mock";
        }
        fn connect(_: *anyopaque) anyerror!void {}
        fn disconnect(_: *anyopaque) void {}
        fn isConnected(_: *anyopaque) bool {
            return true;
        }
        fn getTicker(_: *anyopaque, _: TradingPair) anyerror!types.Ticker {
            return error.NotImplemented;
        }
        fn getOrderbook(_: *anyopaque, _: TradingPair, _: u32) anyerror!types.Orderbook {
            return error.NotImplemented;
        }
        fn createOrder(_: *anyopaque, _: OrderRequest) anyerror!Order {
            return error.NotImplemented;
        }
        fn cancelOrder(_: *anyopaque, _: u64) anyerror!void {}
        fn cancelAllOrders(_: *anyopaque, _: ?TradingPair) anyerror!u32 {
            return 0;
        }
        fn getOrder(_: *anyopaque, _: u64) anyerror!Order {
            return error.NotImplemented;
        }
        fn getBalance(_: *anyopaque) anyerror![]types.Balance {
            return error.NotImplemented;
        }
        fn getOpenOrders(_: *anyopaque, _: ?types.TradingPair) anyerror![]types.Order {
            return error.NotImplemented;
        }
        fn getPositions(_: *anyopaque) anyerror![]types.Position {
            return error.NotImplemented;
        }

        const vtable = IExchange.VTable{
            .getName = getName,
            .connect = connect,
            .disconnect = disconnect,
            .isConnected = isConnected,
            .getTicker = getTicker,
            .getOrderbook = getOrderbook,
            .createOrder = createOrder,
            .cancelOrder = cancelOrder,
            .cancelAllOrders = cancelAllOrders,
            .getOrder = getOrder,
            .getOpenOrders = getOpenOrders,
            .getBalance = getBalance,
            .getPositions = getPositions,
        };
    };

    const MockState = struct {};
    var mock = MockState{};
    const exchange = IExchange{
        .ptr = &mock,
        .vtable = &MockExchange.vtable,
    };

    // Create logger
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../core/logger.zig").LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const log_writer = @import("../core/logger.zig").LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    const logger = Logger.init(allocator, log_writer, .info);

    var manager = OrderManager.init(allocator, exchange, logger);
    defer manager.deinit();

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.active_count);
    try std.testing.expectEqual(@as(usize, 0), stats.history_count);
}

test "OrderManager: handleOrderUpdate" {
    const allocator = std.testing.allocator;

    // Create mock exchange
    const MockExchange = struct {
        fn getName(_: *anyopaque) []const u8 {
            return "mock";
        }
        fn connect(_: *anyopaque) anyerror!void {}
        fn disconnect(_: *anyopaque) void {}
        fn isConnected(_: *anyopaque) bool {
            return true;
        }
        fn getTicker(_: *anyopaque, _: TradingPair) anyerror!types.Ticker {
            return error.NotImplemented;
        }
        fn getOrderbook(_: *anyopaque, _: TradingPair, _: u32) anyerror!types.Orderbook {
            return error.NotImplemented;
        }
        fn createOrder(_: *anyopaque, _: OrderRequest) anyerror!Order {
            return error.NotImplemented;
        }
        fn cancelOrder(_: *anyopaque, _: u64) anyerror!void {}
        fn cancelAllOrders(_: *anyopaque, _: ?TradingPair) anyerror!u32 {
            return 0;
        }
        fn getOrder(_: *anyopaque, _: u64) anyerror!Order {
            return error.NotImplemented;
        }
        fn getBalance(_: *anyopaque) anyerror![]types.Balance {
            return error.NotImplemented;
        }
        fn getOpenOrders(_: *anyopaque, _: ?types.TradingPair) anyerror![]types.Order {
            return error.NotImplemented;
        }
        fn getPositions(_: *anyopaque) anyerror![]types.Position {
            return error.NotImplemented;
        }

        const vtable = IExchange.VTable{
            .getName = getName,
            .connect = connect,
            .disconnect = disconnect,
            .isConnected = isConnected,
            .getTicker = getTicker,
            .getOrderbook = getOrderbook,
            .createOrder = createOrder,
            .cancelOrder = cancelOrder,
            .cancelAllOrders = cancelAllOrders,
            .getOrder = getOrder,
            .getOpenOrders = getOpenOrders,
            .getBalance = getBalance,
            .getPositions = getPositions,
        };
    };

    const MockState = struct {};
    var mock = MockState{};
    const exchange = IExchange{
        .ptr = &mock,
        .vtable = &MockExchange.vtable,
    };

    // Create logger
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../core/logger.zig").LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const log_writer = @import("../core/logger.zig").LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    const logger = Logger.init(allocator, log_writer, .info);

    var manager = OrderManager.init(allocator, exchange, logger);
    defer manager.deinit();

    // Create a test order
    const order = Order{
        .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromInt(1),
        .price = Decimal.fromInt(2000),
        .status = .open,
        .client_order_id = "test-123",
        .exchange_order_id = 12345,
        .filled_amount = Decimal.ZERO,
        .avg_fill_price = null,
        .created_at = Timestamp.now(),
        .updated_at = Timestamp.now(),
    };

    // Add order to store
    try manager.order_store.add(order);

    // Create order update event
    const event = OrderUpdateEvent{
        .exchange_order_id = 12345,
        .status = .partially_filled,
        .filled_amount = try Decimal.fromString("0.5"),
        .avg_fill_price = Decimal.fromInt(2000),
        .timestamp = Timestamp.now(),
    };

    // Handle update
    try manager.handleOrderUpdate(event);

    // Verify order was updated
    const updated = manager.order_store.getByExchangeId(12345).?;
    try std.testing.expectEqual(OrderStatus.partially_filled, updated.status);
    try std.testing.expect((try Decimal.fromString("0.5")).eql(updated.filled_amount));
}

test "OrderManager: handleOrderFill" {
    const allocator = std.testing.allocator;

    // Create mock exchange (same as above)
    const MockExchange = struct {
        fn getName(_: *anyopaque) []const u8 {
            return "mock";
        }
        fn connect(_: *anyopaque) anyerror!void {}
        fn disconnect(_: *anyopaque) void {}
        fn isConnected(_: *anyopaque) bool {
            return true;
        }
        fn getTicker(_: *anyopaque, _: TradingPair) anyerror!types.Ticker {
            return error.NotImplemented;
        }
        fn getOrderbook(_: *anyopaque, _: TradingPair, _: u32) anyerror!types.Orderbook {
            return error.NotImplemented;
        }
        fn createOrder(_: *anyopaque, _: OrderRequest) anyerror!Order {
            return error.NotImplemented;
        }
        fn cancelOrder(_: *anyopaque, _: u64) anyerror!void {}
        fn cancelAllOrders(_: *anyopaque, _: ?TradingPair) anyerror!u32 {
            return 0;
        }
        fn getOrder(_: *anyopaque, _: u64) anyerror!Order {
            return error.NotImplemented;
        }
        fn getBalance(_: *anyopaque) anyerror![]types.Balance {
            return error.NotImplemented;
        }
        fn getOpenOrders(_: *anyopaque, _: ?types.TradingPair) anyerror![]types.Order {
            return error.NotImplemented;
        }
        fn getPositions(_: *anyopaque) anyerror![]types.Position {
            return error.NotImplemented;
        }

        const vtable = IExchange.VTable{
            .getName = getName,
            .connect = connect,
            .disconnect = disconnect,
            .isConnected = isConnected,
            .getTicker = getTicker,
            .getOrderbook = getOrderbook,
            .createOrder = createOrder,
            .cancelOrder = cancelOrder,
            .cancelAllOrders = cancelAllOrders,
            .getOrder = getOrder,
            .getOpenOrders = getOpenOrders,
            .getBalance = getBalance,
            .getPositions = getPositions,
        };
    };

    const MockState = struct {};
    var mock = MockState{};
    const exchange = IExchange{
        .ptr = &mock,
        .vtable = &MockExchange.vtable,
    };

    // Create logger
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../core/logger.zig").LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const log_writer = @import("../core/logger.zig").LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    const logger = Logger.init(allocator, log_writer, .info);

    var manager = OrderManager.init(allocator, exchange, logger);
    defer manager.deinit();

    // Create a test order
    const order = Order{
        .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromInt(1),
        .price = Decimal.fromInt(2000),
        .status = .open,
        .client_order_id = "test-456",
        .exchange_order_id = 67890,
        .filled_amount = Decimal.ZERO,
        .avg_fill_price = null,
        .created_at = Timestamp.now(),
        .updated_at = Timestamp.now(),
    };

    // Add order to store
    try manager.order_store.add(order);

    // Create fill event
    const event = OrderFillEvent{
        .exchange_order_id = 67890,
        .fill_price = Decimal.fromInt(1999),
        .fill_amount = try Decimal.fromString("0.3"),
        .total_filled = try Decimal.fromString("0.3"),
        .timestamp = Timestamp.now(),
    };

    // Handle fill
    try manager.handleOrderFill(event);

    // Verify order was updated
    const updated = manager.order_store.getByExchangeId(67890).?;
    try std.testing.expectEqual(OrderStatus.partially_filled, updated.status);
    try std.testing.expect((try Decimal.fromString("0.3")).eql(updated.filled_amount));
    try std.testing.expect(Decimal.fromInt(1999).eql(updated.avg_fill_price.?));
}
