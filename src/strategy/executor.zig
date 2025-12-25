//! Order Executor
//!
//! Handles order execution for strategies:
//! - Order validation
//! - Simulation mode (for backtesting)
//! - Live execution (via exchange)
//! - Order cancellation
//!
//! Design principles:
//! - Clear separation between simulation and live modes
//! - Comprehensive validation
//! - Detailed logging

const std = @import("std");
const Logger = @import("../root.zig").Logger;
const ConsoleWriter = @import("../root.zig").ConsoleWriter;
const Decimal = @import("../root.zig").Decimal;
const OrderRequest = @import("../root.zig").OrderRequest;
const Order = @import("../root.zig").Order;
const OrderType = @import("../root.zig").OrderType;
const OrderStatus = @import("../root.zig").OrderStatus;
const IExchange = @import("../root.zig").IExchange;
const Timestamp = @import("../root.zig").Timestamp;

// Test helper: Create a simple test logger with a buffer
const TestLoggerContext = struct {
    buffer: [4096]u8,
    fbs: std.io.FixedBufferStream([]u8),
    console: ConsoleWriter(std.io.FixedBufferStream([]u8).Writer),
    logger: Logger,

    fn init(self: *TestLoggerContext, allocator: std.mem.Allocator) void {
        self.buffer = undefined;
        self.fbs = std.io.fixedBufferStream(&self.buffer);
        self.console = ConsoleWriter(std.io.FixedBufferStream([]u8).Writer).initWithColors(
            allocator,
            self.fbs.writer(),
            false,
        );
        self.logger = Logger.init(allocator, self.console.writer(), .info);
    }

    fn deinit(self: *TestLoggerContext) void {
        self.console.deinit();
        self.logger.deinit();
    }
};

// ============================================================================
// Order Executor
// ============================================================================

/// Order executor for strategy execution
pub const OrderExecutor = struct {
    allocator: std.mem.Allocator,
    exchange: ?IExchange,
    logger: Logger,
    simulation_mode: bool, // True = backtest mode, False = live mode

    /// Initialize order executor
    pub fn init(
        allocator: std.mem.Allocator,
        exchange: ?IExchange,
        logger: Logger,
    ) OrderExecutor {
        return OrderExecutor{
            .allocator = allocator,
            .exchange = exchange,
            .logger = logger,
            .simulation_mode = exchange == null,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *OrderExecutor) void {
        _ = self;
        // No dynamic allocations to clean up
    }

    /// Execute an order
    pub fn executeOrder(self: *OrderExecutor, request: OrderRequest) !Order {
        // Validate order first
        try self.validateOrder(request);

        if (self.simulation_mode) {
            // Simulate execution for backtesting
            return try self.simulateExecution(request);
        } else {
            // Execute on real exchange
            return try self.liveExecution(request);
        }
    }

    /// Cancel an order
    pub fn cancelOrder(self: *OrderExecutor, order: *Order) !void {
        if (order.status != .open and order.status != .partially_filled) {
            return error.OrderNotCancellable;
        }

        if (self.simulation_mode) {
            // Simulate cancellation
            order.status = .cancelled;
            order.updated_at = Timestamp.now();

            try self.logger.info("Simulated order cancelled", .{});
        } else {
            // Cancel on real exchange
            const exchange = self.exchange orelse return error.NoExchangeConnected;

            if (order.exchange_order_id) |order_id| {
                try exchange.cancelOrder(order_id);
                order.status = .cancelled;
                order.updated_at = Timestamp.now();

                try self.logger.info("Order cancelled: {d}", .{order_id});
            } else {
                return error.OrderIdNotFound;
            }
        }
    }

    /// Validate order request
    fn validateOrder(self: *OrderExecutor, request: OrderRequest) !void {
        _ = self;

        // Validate amount
        if (request.amount.cmp(Decimal.ZERO) != .gt) {
            return error.InvalidOrderAmount;
        }

        // Validate price for limit orders
        if (request.order_type == .limit) {
            const price = request.price orelse return error.LimitOrderRequiresPrice;
            if (price.cmp(Decimal.ZERO) != .gt) {
                return error.InvalidOrderPrice;
            }
        }
    }

    /// Simulate order execution (for backtesting)
    fn simulateExecution(self: *OrderExecutor, request: OrderRequest) !Order {
        const now = Timestamp.now();

        // Generate simulated order ID
        const sim_id = @as(u64, @intCast(now.millis));

        // Use provided price or default to 0 for market orders
        const exec_price = request.price orelse Decimal.ZERO;

        const order = Order{
            .exchange_order_id = sim_id,
            .client_order_id = null,
            .pair = request.pair,
            .side = request.side,
            .order_type = request.order_type,
            .status = .filled, // Simulate immediate fill
            .amount = request.amount,
            .price = exec_price,
            .filled_amount = request.amount, // Fully filled
            .avg_fill_price = exec_price,
            .created_at = now,
            .updated_at = now,
        };

        try self.logger.info(
            "Simulated order executed: {s} {d} @ {d}",
            .{ @tagName(request.side), request.amount.toFloat(), exec_price.toFloat() },
        );

        return order;
    }

    /// Execute order on live exchange
    fn liveExecution(self: *OrderExecutor, request: OrderRequest) !Order {
        const exchange = self.exchange orelse return error.NoExchangeConnected;

        // Submit order to exchange
        const order = try exchange.createOrder(request);

        try self.logger.info(
            "Order submitted: {s} {d} @ {?d} (ID: {?d})",
            .{
                @tagName(request.side),
                request.amount.toFloat(),
                if (request.price) |p| p.toFloat() else null,
                order.exchange_order_id,
            },
        );

        return order;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "OrderExecutor: initialization" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    var executor = OrderExecutor.init(allocator, null, log_ctx.logger);
    defer executor.deinit();

    try std.testing.expect(executor.simulation_mode == true);
    try std.testing.expect(executor.exchange == null);
}

test "OrderExecutor: validate order - valid request" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    var executor = OrderExecutor.init(allocator, null, log_ctx.logger);
    defer executor.deinit();

    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromInt(1),
        .price = Decimal.fromInt(50000),
    };

    try executor.validateOrder(request);
}

test "OrderExecutor: validate order - invalid amount" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    var executor = OrderExecutor.init(allocator, null, log_ctx.logger);
    defer executor.deinit();

    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .market,
        .amount = Decimal.ZERO, // Invalid
        .price = null,
    };

    try std.testing.expectError(error.InvalidOrderAmount, executor.validateOrder(request));
}

test "OrderExecutor: validate order - limit order without price" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    var executor = OrderExecutor.init(allocator, null, log_ctx.logger);
    defer executor.deinit();

    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromInt(1),
        .price = null, // Invalid for limit order
    };

    try std.testing.expectError(error.LimitOrderRequiresPrice, executor.validateOrder(request));
}

test "OrderExecutor: simulate order execution" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    var executor = OrderExecutor.init(allocator, null, log_ctx.logger);
    defer executor.deinit();

    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromInt(1),
        .price = Decimal.fromInt(50000),
    };

    const order = try executor.executeOrder(request);

    try std.testing.expectEqual(OrderStatus.filled, order.status);
    try std.testing.expect(order.filled_amount.eql(request.amount));
    try std.testing.expect(order.exchange_order_id != null);
}

test "OrderExecutor: cancel order in simulation mode" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    var executor = OrderExecutor.init(allocator, null, log_ctx.logger);
    defer executor.deinit();

    var order = Order{
        .exchange_order_id = 12345,
        .client_order_id = null,
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .status = .open,
        .amount = Decimal.fromInt(1),
        .price = Decimal.fromInt(50000),
        .filled_amount = Decimal.ZERO,
        .avg_fill_price = null,
        .created_at = Timestamp.now(),
        .updated_at = Timestamp.now(),
    };

    try executor.cancelOrder(&order);
    try std.testing.expectEqual(OrderStatus.cancelled, order.status);
}

test "OrderExecutor: cannot cancel filled order" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    var executor = OrderExecutor.init(allocator, null, log_ctx.logger);
    defer executor.deinit();

    var order = Order{
        .exchange_order_id = 12345,
        .client_order_id = null,
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .status = .filled, // Already filled
        .amount = Decimal.fromInt(1),
        .price = Decimal.fromInt(50000),
        .filled_amount = Decimal.fromInt(1),
        .avg_fill_price = Decimal.fromInt(50000),
        .created_at = Timestamp.now(),
        .updated_at = Timestamp.now(),
    };

    try std.testing.expectError(error.OrderNotCancellable, executor.cancelOrder(&order));
}

test "OrderExecutor: market order simulation" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    var executor = OrderExecutor.init(allocator, null, log_ctx.logger);
    defer executor.deinit();

    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .market,
        .amount = Decimal.fromInt(1),
        .price = null, // Market order doesn't need price
    };

    const order = try executor.executeOrder(request);

    try std.testing.expectEqual(OrderStatus.filled, order.status);
    try std.testing.expect(order.filled_amount.eql(request.amount));
}

test "OrderExecutor: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    var executor = OrderExecutor.init(allocator, null, log_ctx.logger);
    defer executor.deinit();

    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromInt(1),
        .price = Decimal.fromInt(50000),
    };

    _ = try executor.executeOrder(request);
}
