//! Strategy Execution Context
//!
//! Provides unified context for strategy execution:
//! - Component lifecycle management
//! - Unified API for strategies
//! - Order execution flow orchestration
//! - Risk management integration
//!
//! Design principles:
//! - Single entry point for strategy operations
//! - Clean separation of concerns
//! - Proper resource cleanup

const std = @import("std");
const Logger = @import("../root.zig").Logger;
const Decimal = @import("../root.zig").Decimal;
const TradingPair = @import("../root.zig").TradingPair;
const Timeframe = @import("../root.zig").Timeframe;
const Timestamp = @import("../root.zig").Timestamp;
const OrderRequest = @import("../root.zig").OrderRequest;
const Order = @import("../root.zig").Order;
const IExchange = @import("../root.zig").IExchange;
const Candles = @import("../root.zig").Candles;

const StrategyConfig = @import("types.zig").StrategyConfig;
const PositionManager = @import("position_manager.zig").PositionManager;
const StrategyPosition = @import("position_manager.zig").StrategyPosition;
const MarketDataProvider = @import("market_data.zig").MarketDataProvider;
const RiskManager = @import("risk.zig").RiskManager;
const OrderExecutor = @import("executor.zig").OrderExecutor;

// ============================================================================
// Strategy Context
// ============================================================================

/// Strategy execution context
/// Orchestrates all strategy components and provides unified API
pub const StrategyContext = struct {
    allocator: std.mem.Allocator,
    config: StrategyConfig,
    logger: Logger,

    // Core components
    position_manager: PositionManager,
    market_data: MarketDataProvider,
    risk_manager: RiskManager,
    executor: OrderExecutor,

    // State
    is_backtesting: bool,

    /// Initialize strategy context
    pub fn init(
        allocator: std.mem.Allocator,
        config: StrategyConfig,
        exchange: ?IExchange,
        logger: Logger,
    ) !StrategyContext {
        const position_manager = try PositionManager.init(allocator);
        errdefer position_manager.deinit();

        const market_data = MarketDataProvider.init(allocator, exchange);
        errdefer market_data.deinit();

        const risk_manager = try RiskManager.init(allocator, config);
        errdefer risk_manager.deinit();

        const executor = OrderExecutor.init(allocator, exchange, logger);
        errdefer executor.deinit();

        return StrategyContext{
            .allocator = allocator,
            .config = config,
            .logger = logger,
            .position_manager = position_manager,
            .market_data = market_data,
            .risk_manager = risk_manager,
            .executor = executor,
            .is_backtesting = exchange == null,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *StrategyContext) void {
        self.position_manager.deinit();
        self.market_data.deinit();
        self.risk_manager.deinit();
        self.executor.deinit();
    }

    // ========================================================================
    // Position Management
    // ========================================================================

    /// Get open position for a trading pair
    pub fn getPosition(self: *StrategyContext, pair: TradingPair) ?*StrategyPosition {
        return self.position_manager.getPosition(pair);
    }

    /// Get all open positions
    pub fn getOpenPositions(self: *StrategyContext) ![]StrategyPosition {
        return self.position_manager.getOpenPositions();
    }

    /// Get number of open positions
    pub fn getOpenPositionCount(self: *StrategyContext) u32 {
        return self.position_manager.getOpenPositionCount();
    }

    /// Get total exposure across all positions
    pub fn getTotalExposure(self: *StrategyContext) Decimal {
        return self.position_manager.getTotalExposure();
    }

    // ========================================================================
    // Market Data
    // ========================================================================

    /// Get latest price for a trading pair
    pub fn getLatestPrice(self: *StrategyContext, pair: TradingPair) !Decimal {
        return self.market_data.getLatestPrice(pair);
    }

    /// Update price in cache (for backtesting)
    pub fn updatePrice(self: *StrategyContext, pair: TradingPair, price: Decimal) !void {
        return self.market_data.updatePrice(pair, price);
    }

    /// Get historical candles
    pub fn getCandles(
        self: *StrategyContext,
        pair: TradingPair,
        timeframe: Timeframe,
        start: Timestamp,
        end: Timestamp,
    ) !*Candles {
        return self.market_data.getCandles(pair, timeframe, start, end);
    }

    /// Set candles directly (for backtesting)
    pub fn setCandles(
        self: *StrategyContext,
        pair: TradingPair,
        timeframe: Timeframe,
        candles: *Candles,
    ) !void {
        return self.market_data.setCandles(pair, timeframe, candles);
    }

    // ========================================================================
    // Risk Management
    // ========================================================================

    /// Check if can open a new position
    pub fn canOpenPosition(
        self: *StrategyContext,
        position_value: Decimal,
    ) bool {
        return self.risk_manager.canOpenNewPosition(
            &self.position_manager,
            position_value,
        );
    }

    /// Get current risk ratio [0.0, 1.0]
    pub fn getRiskRatio(self: *StrategyContext) !f64 {
        return self.risk_manager.calculateRisk(&self.position_manager);
    }

    /// Calculate suggested position size using Kelly criterion
    pub fn calculatePositionSize(
        self: *StrategyContext,
        win_rate: f64,
        avg_win: Decimal,
        avg_loss: Decimal,
        account_balance: Decimal,
    ) !Decimal {
        return self.risk_manager.calculatePositionSize(
            win_rate,
            avg_win,
            avg_loss,
            account_balance,
        );
    }

    // ========================================================================
    // Order Execution
    // ========================================================================

    /// Execute an order with risk validation
    pub fn executeOrder(self: *StrategyContext, request: OrderRequest) !Order {
        // Validate against risk limits
        try self.risk_manager.validateOrder(request, &self.position_manager);

        // Execute the order
        const order = try self.executor.executeOrder(request);

        // Add position to tracker
        if (order.status == .filled) {
            // For filled orders, use avg_fill_price if available, otherwise fall back to order price
            const fill_price = if (order.avg_fill_price) |avg_price|
                avg_price
            else if (order.price) |price|
                price
            else
                Decimal.ZERO; // Should not happen for filled orders

            const position = try StrategyPosition.init(
                request.pair,
                request.side,
                order.filled_amount,
                fill_price,
            );
            try self.position_manager.addPosition(position);
        }

        return order;
    }

    /// Close a position
    pub fn closePosition(
        self: *StrategyContext,
        pair: TradingPair,
        exit_price: Decimal,
    ) !?StrategyPosition {
        return self.position_manager.closePosition(pair, exit_price);
    }

    /// Cancel an order
    pub fn cancelOrder(self: *StrategyContext, order: *Order) !void {
        return self.executor.cancelOrder(order);
    }

    // ========================================================================
    // Utility
    // ========================================================================

    /// Clear all market data caches
    pub fn clearCache(self: *StrategyContext) void {
        self.market_data.clearCache();
    }

    /// Get strategy configuration
    pub fn getConfig(self: *StrategyContext) StrategyConfig {
        return self.config;
    }

    /// Check if running in backtest mode
    pub fn isBacktesting(self: *StrategyContext) bool {
        return self.is_backtesting;
    }
};

// ============================================================================
// Tests
// ============================================================================

const ConsoleWriter = @import("../root.zig").ConsoleWriter;

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

test "StrategyContext: initialization" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test Strategy",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        3,
        Decimal.fromInt(1000),
    );
    defer config.deinit();

    var context = try StrategyContext.init(allocator, config, null, log_ctx.logger);
    defer context.deinit();

    try std.testing.expect(context.isBacktesting());
    try std.testing.expectEqual(@as(u32, 0), context.getOpenPositionCount());
}

test "StrategyContext: execute order with risk validation" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test Strategy",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        2, // max 2 positions
        Decimal.fromInt(1000), // $1000 per position
    );
    defer config.deinit();

    var context = try StrategyContext.init(allocator, config, null, log_ctx.logger);
    defer context.deinit();

    // Execute a valid order
    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromFloat(0.01),
        .price = Decimal.fromInt(50000), // 0.01 * 50000 = $500
    };

    const order = try context.executeOrder(request);
    try std.testing.expectEqual(@as(u32, 1), context.getOpenPositionCount());
    try std.testing.expect(order.status == .filled);
}

test "StrategyContext: reject order exceeding risk limits" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test Strategy",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        1, // max 1 position
        Decimal.fromInt(1000), // $1000 max
    );
    defer config.deinit();

    var context = try StrategyContext.init(allocator, config, null, log_ctx.logger);
    defer context.deinit();

    // Try to execute an order that's too large
    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromFloat(0.1),
        .price = Decimal.fromInt(50000), // 0.1 * 50000 = $5000 > $1000
    };

    try std.testing.expectError(
        error.PositionSizeTooLarge,
        context.executeOrder(request),
    );
}

test "StrategyContext: close position" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test Strategy",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        2,
        Decimal.fromInt(1000),
    );
    defer config.deinit();

    var context = try StrategyContext.init(allocator, config, null, log_ctx.logger);
    defer context.deinit();

    // Open a position
    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromFloat(0.01),
        .price = Decimal.fromInt(50000),
    };
    _ = try context.executeOrder(request);

    // Close the position
    const closed = try context.closePosition(
        .{ .base = "BTC", .quote = "USDT" },
        Decimal.fromInt(51000),
    );

    try std.testing.expect(closed != null);
    try std.testing.expectEqual(@as(u32, 0), context.getOpenPositionCount());

    // Verify PnL: (51000 - 50000) * 0.01 = 10
    const expected_pnl = Decimal.fromInt(10);
    try std.testing.expect(closed.?.pnl.?.eql(expected_pnl));
}

test "StrategyContext: market data operations" {
    const allocator = std.testing.allocator;
    var log_ctx: TestLoggerContext = undefined;
    log_ctx.init(allocator);
    defer log_ctx.deinit();

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test Strategy",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        2,
        Decimal.fromInt(1000),
    );
    defer config.deinit();

    var context = try StrategyContext.init(allocator, config, null, log_ctx.logger);
    defer context.deinit();

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    const price = Decimal.fromInt(50000);

    // Update price
    try context.updatePrice(pair, price);

    // Get price from cache
    const cached_price = try context.getLatestPrice(pair);
    try std.testing.expect(cached_price.eql(price));
}

test "StrategyContext: no memory leak" {
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

    const metadata = @import("types.zig").StrategyMetadata{
        .name = "Test",
        .version = "1.0",
        .author = "Test",
        .description = "Test Strategy",
    };

    const config = try StrategyConfig.init(
        allocator,
        metadata,
        .{ .base = "BTC", .quote = "USDT" },
        .h1,
        &[_]@import("types.zig").StrategyParameter{},
        null,
        null,
        2,
        Decimal.fromInt(1000),
    );
    defer config.deinit();

    var context = try StrategyContext.init(allocator, config, null, log_ctx.logger);
    defer context.deinit();

    // Perform some operations
    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    try context.updatePrice(pair, Decimal.fromInt(50000));
    _ = try context.getLatestPrice(pair);
}
