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
const Decimal = @import("../../root.zig").Decimal;

// Hyperliquid modules
const HttpClient = @import("http.zig").HttpClient;
const RateLimiter = @import("rate_limiter.zig").RateLimiter;
const InfoAPI = @import("info_api.zig").InfoAPI;
const ExchangeAPI = @import("exchange_api.zig").ExchangeAPI;
const Signer = @import("auth.zig").Signer;
const hl_types = @import("types.zig");

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

    // Phase D: HTTP client and API modules
    http_client: HttpClient,
    rate_limiter: RateLimiter,
    info_api: InfoAPI,
    exchange_api: ExchangeAPI,
    signer: ?Signer, // Optional: only needed for trading

    // TODO Phase D.2: WebSocket client (optional)
    // ws: ?WebSocketClient,

    /// Create a new Hyperliquid connector and return it as IExchange
    pub fn create(
        allocator: std.mem.Allocator,
        config: ExchangeConfig,
        logger: Logger,
    ) !*HyperliquidConnector {
        const self = try allocator.create(HyperliquidConnector);
        errdefer allocator.destroy(self);

        // Initialize struct fields (http_client first, then APIs get pointer to it)
        self.* = .{
            .allocator = allocator,
            .config = config,
            .logger = logger,
            .connected = false,
            .http_client = HttpClient.init(allocator, config.testnet, logger),
            .rate_limiter = @import("rate_limiter.zig").createHyperliquidRateLimiter(),
            .info_api = undefined, // Initialize after http_client is in place
            .exchange_api = undefined, // Initialize after http_client is in place
            .signer = null, // Will be initialized below if private_key is provided
        };

        // Initialize signer if private key is provided (api_secret contains hex-encoded private key)
        if (config.api_secret.len > 0) {
            self.signer = try self.initializeSigner(config.api_secret);
        }

        // Now initialize APIs with stable pointer to self.http_client
        self.info_api = InfoAPI.init(allocator, &self.http_client, logger);

        // Pass signer pointer to ExchangeAPI
        const signer_ptr = if (self.signer) |*s| s else null;
        self.exchange_api = ExchangeAPI.init(allocator, &self.http_client, signer_ptr, logger);

        return self;
    }

    /// Destroy the connector
    pub fn destroy(self: *HyperliquidConnector) void {
        if (self.connected) {
            disconnect(self);
        }
        // Cleanup signer if initialized
        if (self.signer) |*signer| {
            signer.deinit();
        }
        // Cleanup HTTP client
        self.http_client.deinit();
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

        self.logger.debug("getTicker called for {s}-{s} (HL: {s})", .{ pair.base, pair.quote, symbol }) catch {};

        // Rate limit
        self.rate_limiter.wait();

        // Call Info API to get all mid prices
        var mids = try self.info_api.getAllMids();
        defer self.info_api.freeAllMids(&mids);

        // Get mid price for this symbol
        const mid_price_str = mids.get(symbol) orelse return error.SymbolNotFound;
        const mid_price = try hl_types.parsePrice(mid_price_str);

        // Return ticker (Hyperliquid only provides mid price, so bid/ask/last are the same)
        return Ticker{
            .pair = pair,
            .bid = mid_price,
            .ask = mid_price,
            .last = mid_price,
            .volume_24h = Decimal.ZERO, // Not available from allMids
            .timestamp = Timestamp.now(),
        };
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

        // Rate limit
        self.rate_limiter.wait();

        // Call Info API to get L2 orderbook
        const parsed_l2_data = try self.info_api.getL2Book(symbol);
        defer parsed_l2_data.deinit();
        const l2_data = parsed_l2_data.value;

        // Convert Hyperliquid format to unified Orderbook
        // l2_data.levels[0] = bids, l2_data.levels[1] = asks
        const num_bids = @min(l2_data.levels[0].len, depth);
        const num_asks = @min(l2_data.levels[1].len, depth);

        var bids = try self.allocator.alloc(types.OrderbookLevel, num_bids);
        errdefer self.allocator.free(bids);

        var asks = try self.allocator.alloc(types.OrderbookLevel, num_asks);
        errdefer self.allocator.free(asks);

        // Parse bids (already sorted from high to low by Hyperliquid)
        for (l2_data.levels[0][0..num_bids], 0..) |level, i| {
            bids[i] = types.OrderbookLevel{
                .price = try hl_types.parsePrice(level.px),
                .quantity = try hl_types.parseSize(level.sz),
                .num_orders = level.n,
            };
        }

        // Parse asks (already sorted from low to high by Hyperliquid)
        for (l2_data.levels[1][0..num_asks], 0..) |level, i| {
            asks[i] = types.OrderbookLevel{
                .price = try hl_types.parsePrice(level.px),
                .quantity = try hl_types.parseSize(level.sz),
                .num_orders = level.n,
            };
        }

        return Orderbook{
            .pair = pair,
            .bids = bids,
            .asks = asks,
            .timestamp = Timestamp.now(),
        };
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

        // Convert unified OrderRequest to Hyperliquid format
        const price_str = try hl_types.formatPrice(self.allocator, request.price orelse Decimal.ZERO);
        defer self.allocator.free(price_str);

        const size_str = try hl_types.formatSize(self.allocator, request.amount);
        defer self.allocator.free(size_str);

        const hl_request = hl_types.OrderRequest{
            .coin = symbol,
            .is_buy = request.side == .buy,
            .sz = size_str,
            .limit_px = price_str,
            .order_type = .{ .limit = .{ .tif = "Gtc" } },
            .reduce_only = false,
        };

        // Call Exchange API (with signing)
        const response = try self.exchange_api.placeOrder(hl_request);

        // Check response status
        if (!std.mem.eql(u8, response.status, "ok")) {
            self.logger.err("Order placement failed: {s}", .{response.status}) catch {};
            return error.OrderRejected;
        }

        // Extract order ID from response
        const order_id = blk: {
            if (response.response) |resp| {
                if (resp.data) |data| {
                    if (data.statuses.len > 0) {
                        if (data.statuses[0].resting) |resting| {
                            break :blk resting.oid;
                        }
                    }
                }
            }
            return error.InvalidOrderResponse;
        };

        self.logger.info("Order placed successfully: ID={d}", .{order_id}) catch {};

        // Convert to unified Order format
        const now = Timestamp.now();
        return Order{
            .exchange_order_id = order_id,
            .client_order_id = null,
            .pair = request.pair,
            .side = request.side,
            .order_type = request.order_type,
            .status = .pending, // Initial status
            .amount = request.amount,
            .price = request.price,
            .filled_amount = Decimal.ZERO,
            .avg_fill_price = null,
            .created_at = now,
            .updated_at = now,
        };
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

    /// Initialize signer from private key hex string
    ///
    /// @param private_key_hex: Private key as hex string (with or without 0x prefix)
    /// @return Initialized Signer
    fn initializeSigner(self: *HyperliquidConnector, private_key_hex: []const u8) !Signer {
        // Remove 0x prefix if present
        const hex_str = if (private_key_hex.len >= 2 and
            private_key_hex[0] == '0' and private_key_hex[1] == 'x')
            private_key_hex[2..]
        else
            private_key_hex;

        // Validate hex string length (32 bytes = 64 hex characters)
        if (hex_str.len != 64) {
            self.logger.err("Invalid private key length: {d} (expected 64 hex chars)", .{hex_str.len}) catch {};
            return error.InvalidPrivateKey;
        }

        // Convert hex string to bytes
        var private_key_bytes: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&private_key_bytes, hex_str) catch {
            self.logger.err("Failed to parse private key hex", .{}) catch {};
            return error.InvalidPrivateKey;
        };

        // Initialize signer
        const signer = try Signer.init(self.allocator, private_key_bytes);

        self.logger.info("Initialized signer with address: {s}", .{signer.address}) catch {};

        return signer;
    }
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

test "HyperliquidConnector: trading methods return NotImplemented" {
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

    // Trading and account methods should return NotImplemented (Phase D.2)
    try std.testing.expectError(error.NotImplemented, exchange.getBalance());
    try std.testing.expectError(error.NotImplemented, exchange.getPositions());

    // Note: getTicker and getOrderbook are now implemented (Phase D.1)
    // but require network access, so they are tested in integration tests
}

test "HyperliquidConnector: initializeSigner - valid hex without 0x prefix" {
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

    // Test with valid 64-char hex string (without 0x)
    const test_private_key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    var signer = try connector.initializeSigner(test_private_key);
    defer signer.deinit();

    // Verify signer was created with valid address
    try std.testing.expect(signer.address.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, signer.address, "0x"));
}

test "HyperliquidConnector: initializeSigner - valid hex with 0x prefix" {
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

    // Test with valid 64-char hex string (with 0x prefix)
    const test_private_key = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    var signer = try connector.initializeSigner(test_private_key);
    defer signer.deinit();

    // Verify signer was created
    try std.testing.expect(signer.address.len > 0);
}

test "HyperliquidConnector: initializeSigner - invalid length" {
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

    // Test with invalid length (too short)
    const invalid_key = "0123456789abcdef"; // Only 16 chars
    try std.testing.expectError(error.InvalidPrivateKey, connector.initializeSigner(invalid_key));
}

test "HyperliquidConnector: createOrder - requires signer" {
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

    // Create connector WITHOUT api_secret (no signer)
    const config = ExchangeConfig{
        .name = "hyperliquid",
        .testnet = true,
        .api_secret = "", // Empty = no signer
    };

    const connector = try HyperliquidConnector.create(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();

    // Create a test order request
    const order_request = OrderRequest{
        .pair = .{ .base = "ETH", .quote = "USDC" },
        .side = .buy,
        .order_type = .limit, // OrderType is a simple enum, not a union
        .amount = Decimal.fromInt(1),
        .price = Decimal.fromInt(3500),
        .time_in_force = .gtc,
        .reduce_only = false,
    };

    // Should fail because no signer is configured
    try std.testing.expectError(error.SignerRequired, exchange.createOrder(order_request));
}

test "HyperliquidConnector: create with private key initializes signer" {
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

    // Create connector WITH api_secret (private key)
    const config = ExchangeConfig{
        .name = "hyperliquid",
        .testnet = true,
        .api_secret = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    };

    const connector = try HyperliquidConnector.create(allocator, config, logger);
    defer connector.destroy();

    // Verify signer was initialized
    try std.testing.expect(connector.signer != null);
    if (connector.signer) |signer| {
        try std.testing.expect(signer.address.len > 0);
    }
}
