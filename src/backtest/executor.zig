//! Backtest Engine - Order Executor
//!
//! Simulates order execution with realistic fills, slippage, and commissions.

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Logger = @import("../core/logger.zig").Logger;
const ConsoleWriter = @import("../core/logger.zig").ConsoleWriter;
const Candle = @import("../market/candles.zig").Candle;
const BacktestConfig = @import("types.zig").BacktestConfig;
const OrderEvent = @import("event.zig").OrderEvent;
const FillEvent = @import("event.zig").FillEvent;

// ============================================================================
// Order Executor
// ============================================================================

/// Simulates order execution with realistic fills, slippage, and commissions
pub const OrderExecutor = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    config: BacktestConfig,
    next_order_id: u64,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        config: BacktestConfig,
    ) OrderExecutor {
        return .{
            .allocator = allocator,
            .logger = logger,
            .config = config,
            .next_order_id = 1,
        };
    }

    /// Execute a market order against current candle
    pub fn executeMarketOrder(
        self: *OrderExecutor,
        order: OrderEvent,
        current_candle: Candle,
    ) !FillEvent {
        // 1. Base price: use candle close
        const base_price = current_candle.close;

        // 2. Apply slippage
        const slippage_factor = if (order.side == .buy)
            // Buy: price increases (unfavorable)
            Decimal.ONE.add(self.config.slippage)
        else
            // Sell: price decreases (unfavorable)
            Decimal.ONE.sub(self.config.slippage);

        const fill_price = base_price.mul(slippage_factor);

        // 3. Calculate commission
        const notional = fill_price.mul(order.size);
        const commission = notional.mul(self.config.commission_rate);

        // 4. Log execution
        try self.logger.debug(
            "Order executed: id={}, side={s}, price={}, size={}, fee={}",
            .{
                order.id,
                @tagName(order.side),
                fill_price,
                order.size,
                commission,
            },
        );

        // 5. Return fill event
        return FillEvent{
            .order_id = order.id,
            .timestamp = order.timestamp,
            .fill_price = fill_price,
            .fill_size = order.size,
            .commission = commission,
        };
    }

    /// Generate unique order ID
    pub fn generateOrderId(self: *OrderExecutor) u64 {
        const id = self.next_order_id;
        self.next_order_id += 1;
        return id;
    }

    /// Reset order ID counter (for testing)
    pub fn reset(self: *OrderExecutor) void {
        self.next_order_id = 1;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "OrderExecutor: market order buy with slippage" {
    const testing = std.testing;

    // Setup config with 0.05% slippage and 0.1% commission
    const config = BacktestConfig{
        .pair = @import("../exchange/types.zig").TradingPair{ .base = "ETH", .quote = "USDC" },
        .timeframe = .m15,
        .start_time = .{ .millis = 0 },
        .end_time = .{ .millis = 1000 },
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.fromFloat(0.0005),
    };

    var log_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&log_buf);
    const WriterType = @TypeOf(fbs.writer());
    var console = ConsoleWriter(WriterType).initWithColors(testing.allocator, fbs.writer(), false);
    defer console.deinit();
    var logger = Logger.init(testing.allocator, console.writer(), .err);
    defer logger.deinit();

    var executor = OrderExecutor.init(testing.allocator, logger, config);

    // Create buy order
    const order = OrderEvent{
        .id = 1,
        .timestamp = .{ .millis = 1000 },
        .pair = config.pair,
        .side = .buy,
        .order_type = .market,
        .price = Decimal.fromInt(2000),
        .size = Decimal.fromFloat(1.0),
    };

    // Current candle with close = 2000
    const candle = Candle{
        .timestamp = .{ .millis = 1000 },
        .open = Decimal.fromInt(1995),
        .high = Decimal.fromInt(2005),
        .low = Decimal.fromInt(1990),
        .close = Decimal.fromInt(2000),
        .volume = Decimal.fromInt(100),
    };

    // Execute
    const fill = try executor.executeMarketOrder(order, candle);

    // Verify fill price with slippage
    // buy: close × (1 + slippage) = 2000 × 1.0005 = 2001
    const expected_price = Decimal.fromFloat(2001.0);
    try testing.expect(fill.fill_price.eql(expected_price));

    // Verify commission
    // commission = price × size × rate = 2001 × 1.0 × 0.001 = 2.001
    const expected_commission = Decimal.fromFloat(2.001);
    try testing.expect(fill.commission.eql(expected_commission));

    // Verify fill size
    try testing.expect(fill.fill_size.eql(Decimal.fromFloat(1.0)));

    // Verify order ID
    try testing.expectEqual(@as(u64, 1), fill.order_id);
}

test "OrderExecutor: market order sell with slippage" {
    const testing = std.testing;

    const config = BacktestConfig{
        .pair = @import("../exchange/types.zig").TradingPair{ .base = "ETH", .quote = "USDC" },
        .timeframe = .m15,
        .start_time = .{ .millis = 0 },
        .end_time = .{ .millis = 1000 },
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.fromFloat(0.0005),
    };

    var log_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&log_buf);
    const WriterType = @TypeOf(fbs.writer());
    var console = ConsoleWriter(WriterType).initWithColors(testing.allocator, fbs.writer(), false);
    defer console.deinit();
    var logger = Logger.init(testing.allocator, console.writer(), .err);
    defer logger.deinit();

    var executor = OrderExecutor.init(testing.allocator, logger, config);

    const order = OrderEvent{
        .id = 1,
        .timestamp = .{ .millis = 1000 },
        .pair = config.pair,
        .side = .sell,
        .order_type = .market,
        .price = Decimal.fromInt(2000),
        .size = Decimal.fromFloat(1.0),
    };

    const candle = Candle{
        .timestamp = .{ .millis = 1000 },
        .open = Decimal.fromInt(1995),
        .high = Decimal.fromInt(2005),
        .low = Decimal.fromInt(1990),
        .close = Decimal.fromInt(2000),
        .volume = Decimal.fromInt(100),
    };

    const fill = try executor.executeMarketOrder(order, candle);

    // Verify fill price with slippage
    // sell: close × (1 - slippage) = 2000 × 0.9995 = 1999
    const expected_price = Decimal.fromFloat(1999.0);
    try testing.expect(fill.fill_price.eql(expected_price));

    // Verify commission
    // commission = price × size × rate = 1999 × 1.0 × 0.001 = 1.999
    const expected_commission = Decimal.fromFloat(1.999);
    try testing.expect(fill.commission.eql(expected_commission));
}

test "OrderExecutor: generate order IDs" {
    const testing = std.testing;

    const config = BacktestConfig{
        .pair = @import("../exchange/types.zig").TradingPair{ .base = "ETH", .quote = "USDC" },
        .timeframe = .m15,
        .start_time = .{ .millis = 0 },
        .end_time = .{ .millis = 1000 },
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.fromFloat(0.0005),
    };

    var log_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&log_buf);
    const WriterType = @TypeOf(fbs.writer());
    var console = ConsoleWriter(WriterType).initWithColors(testing.allocator, fbs.writer(), false);
    defer console.deinit();
    var logger = Logger.init(testing.allocator, console.writer(), .err);
    defer logger.deinit();

    var executor = OrderExecutor.init(testing.allocator, logger, config);

    // Generate sequential IDs
    try testing.expectEqual(@as(u64, 1), executor.generateOrderId());
    try testing.expectEqual(@as(u64, 2), executor.generateOrderId());
    try testing.expectEqual(@as(u64, 3), executor.generateOrderId());

    // Reset and verify
    executor.reset();
    try testing.expectEqual(@as(u64, 1), executor.generateOrderId());
}

test "OrderExecutor: zero slippage" {
    const testing = std.testing;

    const config = BacktestConfig{
        .pair = @import("../exchange/types.zig").TradingPair{ .base = "ETH", .quote = "USDC" },
        .timeframe = .m15,
        .start_time = .{ .millis = 0 },
        .end_time = .{ .millis = 1000 },
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.ZERO, // No slippage
    };

    var log_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&log_buf);
    const WriterType = @TypeOf(fbs.writer());
    var console = ConsoleWriter(WriterType).initWithColors(testing.allocator, fbs.writer(), false);
    defer console.deinit();
    var logger = Logger.init(testing.allocator, console.writer(), .err);
    defer logger.deinit();

    var executor = OrderExecutor.init(testing.allocator, logger, config);

    const order = OrderEvent{
        .id = 1,
        .timestamp = .{ .millis = 1000 },
        .pair = config.pair,
        .side = .buy,
        .order_type = .market,
        .price = Decimal.fromInt(2000),
        .size = Decimal.fromFloat(1.0),
    };

    const candle = Candle{
        .timestamp = .{ .millis = 1000 },
        .open = Decimal.fromInt(1995),
        .high = Decimal.fromInt(2005),
        .low = Decimal.fromInt(1990),
        .close = Decimal.fromInt(2000),
        .volume = Decimal.fromInt(100),
    };

    const fill = try executor.executeMarketOrder(order, candle);

    // With zero slippage, fill price = close price
    try testing.expect(fill.fill_price.eql(Decimal.fromInt(2000)));
}

test "OrderExecutor: zero commission" {
    const testing = std.testing;

    const config = BacktestConfig{
        .pair = @import("../exchange/types.zig").TradingPair{ .base = "ETH", .quote = "USDC" },
        .timeframe = .m15,
        .start_time = .{ .millis = 0 },
        .end_time = .{ .millis = 1000 },
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = Decimal.ZERO, // No commission
        .slippage = Decimal.fromFloat(0.0005),
    };

    var log_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&log_buf);
    const WriterType = @TypeOf(fbs.writer());
    var console = ConsoleWriter(WriterType).initWithColors(testing.allocator, fbs.writer(), false);
    defer console.deinit();
    var logger = Logger.init(testing.allocator, console.writer(), .err);
    defer logger.deinit();

    var executor = OrderExecutor.init(testing.allocator, logger, config);

    const order = OrderEvent{
        .id = 1,
        .timestamp = .{ .millis = 1000 },
        .pair = config.pair,
        .side = .buy,
        .order_type = .market,
        .price = Decimal.fromInt(2000),
        .size = Decimal.fromFloat(1.0),
    };

    const candle = Candle{
        .timestamp = .{ .millis = 1000 },
        .open = Decimal.fromInt(1995),
        .high = Decimal.fromInt(2005),
        .low = Decimal.fromInt(1990),
        .close = Decimal.fromInt(2000),
        .volume = Decimal.fromInt(100),
    };

    const fill = try executor.executeMarketOrder(order, candle);

    // With zero commission rate, commission = 0
    try testing.expect(fill.commission.isZero());
}
