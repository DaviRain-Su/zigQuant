//! Hyperliquid Connector - IExchange implementation for Hyperliquid DEX
//!
//! This module implements the IExchange interface for Hyperliquid DEX.
//! It provides a unified API for:
//! - Market data (REST API)
//! - Trading operations (REST API with Ed25519 signing)
//! - Account management
//! - WebSocket subscriptions (future)
//!
//! Phase C (Current): Skeleton implementation with stubs
//! Phase D (Next): Full HTTP/WebSocket implementation

const std = @import("std");
const IExchange = @import("../interface.zig").IExchange;
const types = @import("../types.zig");
const symbol_mapper = @import("../symbol_mapper.zig");
const Logger = @import("../../root.zig").Logger;
const ExchangeConfig = @import("../../root.zig").ExchangeConfig;
const Timestamp = @import("../../root.zig").Timestamp;

// Re-export types for convenience
const TradingPair = types.TradingPair;
const Side = types.Side;
const OrderType = types.OrderType;
const OrderRequest = types.OrderRequest;
const Order = types.Order;
const Ticker = types.Ticker;
const Orderbook = types.Orderbook;
const Balance = types.Balance;
const Position = types.Position;

// ============================================================================
// Hyperliquid Connector
// ============================================================================

/// Hyperliquid DEX connector implementing IExchange interface
pub const HyperliquidConnector = struct {
    allocator: std.mem.Allocator,
    config: ExchangeConfig,
    logger: Logger,
    connected: bool,

    // TODO Phase D: Add HTTP and WebSocket clients
    // http: HyperliquidClient,
    // ws: ?WebSocketClient,

    /// Create a new Hyperliquid connector and return it as IExchange
    pub fn create(
        allocator: std.mem.Allocator,
        config: ExchangeConfig,
        logger: Logger,
    ) !*HyperliquidConnector {
        const self = try allocator.create(HyperliquidConnector);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .logger = logger,
            .connected = false,
        };

        return self;
    }

    /// Destroy the connector
    pub fn destroy(self: *HyperliquidConnector) void {
        if (self.connected) {
            disconnect(self);
        }
        self.allocator.destroy(self);
    }

    /// Get the IExchange interface for this connector
    pub fn interface(self: *HyperliquidConnector) IExchange {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    /// VTable for IExchange interface
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
        .getBalance = getBalance,
        .getPositions = getPositions,
    };

    // ========================================================================
    // Basic Operations
    // ========================================================================

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "hyperliquid";
    }

    fn connect(ptr: *anyopaque) anyerror!void {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.info("Connecting to Hyperliquid {s}...", .{
            if (self.config.testnet) "testnet" else "mainnet",
        }) catch {};

        // TODO Phase D: Initialize HTTP client
        // self.http = try HyperliquidClient.init(self.allocator, self.config);

        // TODO Phase D: Optionally initialize WebSocket client
        // if (self.config.enable_websocket) {
        //     self.ws = try WebSocketClient.init(self.allocator, self.config);
        // }

        self.connected = true;

        self.logger.info("Successfully connected to Hyperliquid", .{}) catch {};
    }

    fn disconnect(ptr: *anyopaque) void {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        if (!self.connected) return;

        self.logger.info("Disconnecting from Hyperliquid...", .{}) catch {};

        // TODO Phase D: Cleanup HTTP client
        // self.http.deinit();

        // TODO Phase D: Cleanup WebSocket client if exists
        // if (self.ws) |*ws| {
        //     ws.deinit();
        //     self.ws = null;
        // }

        self.connected = false;

        self.logger.info("Disconnected from Hyperliquid", .{}) catch {};
    }

    fn isConnected(ptr: *anyopaque) bool {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));
        return self.connected;
    }

    // ========================================================================
    // Market Data Operations (REST API - Phase D)
    // ========================================================================

    fn getTicker(ptr: *anyopaque, pair: TradingPair) anyerror!Ticker {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        // Convert to Hyperliquid symbol format
        const symbol = try symbol_mapper.toHyperliquid(pair);
        _ = symbol; // unused for now

        self.logger.debug("getTicker called for {s}-{s}", .{ pair.base, pair.quote }) catch {};

        // TODO Phase D: Call Info API /info endpoint with {"type": "allMids"}
        // const mids = try self.http.getAllMids();
        // const mid_price = mids.get(symbol) orelse return error.SymbolNotFound;
        //
        // return Ticker{
        //     .pair = pair,
        //     .bid = mid_price,
        //     .ask = mid_price,
        //     .last = mid_price,
        //     .volume_24h = Decimal.ZERO,
        //     .timestamp = Timestamp.now(),
        // };

        return error.NotImplemented;
    }

    fn getOrderbook(ptr: *anyopaque, pair: TradingPair, depth: u32) anyerror!Orderbook {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        // Convert to Hyperliquid symbol format
        const symbol = try symbol_mapper.toHyperliquid(pair);

        self.logger.debug("getOrderbook called for {s} ({s}-{s}) depth={d}", .{
            symbol,
            pair.base,
            pair.quote,
            depth,
        }) catch {};

        // TODO Phase D: Call Info API /info endpoint with {"type": "l2Book", "coin": symbol}
        // const l2_data = try self.http.getL2Book(symbol);
        //
        // // Convert Hyperliquid format to unified Orderbook
        // var bids = try self.allocator.alloc(OrderbookLevel, l2_data.levels[0].len);
        // var asks = try self.allocator.alloc(OrderbookLevel, l2_data.levels[1].len);
        //
        // // Parse and sort...
        //
        // return Orderbook{
        //     .pair = pair,
        //     .bids = bids,
        //     .asks = asks,
        //     .timestamp = Timestamp.now(),
        // };

        return error.NotImplemented;
    }

    // ========================================================================
    // Trading Operations (Exchange API - Phase D)
    // ========================================================================

    fn createOrder(ptr: *anyopaque, request: OrderRequest) anyerror!Order {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        // Validate order request
        try request.validate();

        // Convert to Hyperliquid symbol format
        const symbol = try symbol_mapper.toHyperliquid(request.pair);

        self.logger.debug("createOrder called: {s} {s} {s}", .{
            @tagName(request.side),
            @tagName(request.order_type),
            symbol,
        }) catch {};

        // TODO Phase D: Build and sign order request
        // const hl_order = try self.buildHyperliquidOrder(request);
        // const signed = try self.signOrder(hl_order);
        //
        // // Submit to Exchange API /exchange endpoint
        // const response = try self.http.placeOrder(signed);
        //
        // // Convert response to unified Order format
        // return Order{
        //     .exchange_order_id = response.oid,
        //     .client_order_id = request.client_order_id,
        //     .pair = request.pair,
        //     .side = request.side,
        //     .order_type = request.order_type,
        //     .status = .pending,
        //     .amount = request.amount,
        //     .price = request.price,
        //     .filled_amount = Decimal.ZERO,
        //     .created_at = Timestamp.now(),
        //     .updated_at = Timestamp.now(),
        // };

        return error.NotImplemented;
    }

    fn cancelOrder(ptr: *anyopaque, order_id: u64) anyerror!void {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.debug("cancelOrder called: {d}", .{order_id}) catch {};

        // TODO Phase D: Build and sign cancel request
        // const cancel_req = try self.buildCancelRequest(order_id);
        // const signed = try self.signCancelRequest(cancel_req);
        //
        // // Submit to Exchange API
        // try self.http.cancelOrder(signed);

        return error.NotImplemented;
    }

    fn cancelAllOrders(ptr: *anyopaque, pair: ?TradingPair) anyerror!u32 {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        if (pair) |p| {
            const symbol = try symbol_mapper.toHyperliquid(p);
            _ = symbol;
            self.logger.debug("cancelAllOrders called for {s}-{s}", .{ p.base, p.quote }) catch {};
        } else {
            self.logger.debug("cancelAllOrders called for all pairs", .{}) catch {};
        }

        // TODO Phase D: Build and sign cancel all request
        // const cancel_req = try self.buildCancelAllRequest(pair);
        // const signed = try self.signCancelRequest(cancel_req);
        //
        // // Submit to Exchange API
        // const response = try self.http.cancelAllOrders(signed);
        // return response.statuses.len;

        return error.NotImplemented;
    }

    fn getOrder(ptr: *anyopaque, order_id: u64) anyerror!Order {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.debug("getOrder called: {d}", .{order_id}) catch {};

        // TODO Phase D: Query order status from Info API
        // const user_state = try self.http.getUserState(self.config.user_address);
        //
        // // Find order in user_state.assetPositions or openOrders
        // for (user_state.openOrders) |open_order| {
        //     if (open_order.oid == order_id) {
        //         return convertToUnifiedOrder(open_order);
        //     }
        // }
        //
        // return error.OrderNotFound;

        return error.NotImplemented;
    }

    // ========================================================================
    // Account Operations (Info API - Phase D)
    // ========================================================================

    fn getBalance(ptr: *anyopaque) anyerror![]Balance {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.debug("getBalance called", .{}) catch {};

        // TODO Phase D: Query user state from Info API
        // const user_state = try self.http.getUserState(self.config.user_address);
        //
        // // Hyperliquid returns cross margin account data
        // var balances = try self.allocator.alloc(Balance, 1);
        // balances[0] = Balance{
        //     .asset = "USDC",
        //     .total = user_state.crossMarginSummary.accountValue,
        //     .available = user_state.crossMarginSummary.withdrawable,
        //     .locked = user_state.crossMarginSummary.totalMarginUsed,
        // };
        //
        // return balances;

        return error.NotImplemented;
    }

    fn getPositions(ptr: *anyopaque) anyerror![]Position {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.debug("getPositions called", .{}) catch {};

        // TODO Phase D: Query user state from Info API
        // const user_state = try self.http.getUserState(self.config.user_address);
        //
        // var positions = std.ArrayList(Position).init(self.allocator);
        // defer positions.deinit();
        //
        // for (user_state.assetPositions) |asset_pos| {
        //     if (asset_pos.position.szi == 0) continue; // Skip zero positions
        //
        //     const pair = symbol_mapper.fromHyperliquid(asset_pos.position.coin);
        //     const size_f = std.fmt.parseFloat(f64, asset_pos.position.szi) catch continue;
        //
        //     try positions.append(Position{
        //         .pair = pair,
        //         .side = if (size_f > 0) .buy else .sell,
        //         .size = Decimal.fromFloat(@abs(size_f)),
        //         .entry_price = asset_pos.position.entryPx,
        //         .unrealized_pnl = asset_pos.position.unrealizedPnl,
        //         .leverage = asset_pos.position.leverage.value,
        //         .margin_used = asset_pos.position.marginUsed,
        //     });
        // }
        //
        // return positions.toOwnedSlice();

        return error.NotImplemented;
    }

    // ========================================================================
    // Helper Methods (Phase D)
    // ========================================================================

    // TODO Phase D: Add helper methods
    // fn buildHyperliquidOrder(self: *HyperliquidConnector, request: OrderRequest) !HLOrder
    // fn signOrder(self: *HyperliquidConnector, order: HLOrder) !SignedAction
    // fn signCancelRequest(self: *HyperliquidConnector, cancel: CancelRequest) !SignedAction
};

// ============================================================================
// Tests
// ============================================================================

test "HyperliquidConnector: create and destroy" {
    const allocator = std.testing.allocator;

    // Create test logger
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../root.zig").logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../root.zig").logger.LogWriter{
        .ptr = @constCast(@ptrCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    var logger = Logger.init(allocator, writer, .info);
    defer logger.deinit();

    const config = ExchangeConfig{
        .name = "hyperliquid",
        .testnet = true,
    };

    const connector = try HyperliquidConnector.create(allocator, config, logger);
    defer connector.destroy();

    try std.testing.expect(!connector.connected);
}

test "HyperliquidConnector: interface" {
    const allocator = std.testing.allocator;

    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../root.zig").logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../root.zig").logger.LogWriter{
        .ptr = @constCast(@ptrCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    var logger = Logger.init(allocator, writer, .info);
    defer logger.deinit();

    const config = ExchangeConfig{
        .name = "hyperliquid",
        .testnet = true,
    };

    const connector = try HyperliquidConnector.create(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();

    try std.testing.expectEqualStrings("hyperliquid", exchange.getName());
}

test "HyperliquidConnector: connect and disconnect" {
    const allocator = std.testing.allocator;

    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../root.zig").logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../root.zig").logger.LogWriter{
        .ptr = @constCast(@ptrCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    var logger = Logger.init(allocator, writer, .info);
    defer logger.deinit();

    const config = ExchangeConfig{
        .name = "hyperliquid",
        .testnet = true,
    };

    const connector = try HyperliquidConnector.create(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();

    // Initially not connected
    try std.testing.expect(!exchange.isConnected());

    // Connect
    try exchange.connect();
    try std.testing.expect(exchange.isConnected());

    // Disconnect
    exchange.disconnect();
    try std.testing.expect(!exchange.isConnected());
}

test "HyperliquidConnector: stub methods return NotImplemented" {
    const allocator = std.testing.allocator;

    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../root.zig").logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../root.zig").logger.LogWriter{
        .ptr = @constCast(@ptrCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    var logger = Logger.init(allocator, writer, .info);
    defer logger.deinit();

    const config = ExchangeConfig{
        .name = "hyperliquid",
        .testnet = true,
    };

    const connector = try HyperliquidConnector.create(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();

    const pair = TradingPair{ .base = "ETH", .quote = "USDC" };

    // All stub methods should return NotImplemented
    try std.testing.expectError(error.NotImplemented, exchange.getTicker(pair));
    try std.testing.expectError(error.NotImplemented, exchange.getOrderbook(pair, 10));
    try std.testing.expectError(error.NotImplemented, exchange.getBalance());
    try std.testing.expectError(error.NotImplemented, exchange.getPositions());
}
