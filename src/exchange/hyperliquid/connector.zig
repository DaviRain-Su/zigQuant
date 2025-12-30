//! Hyperliquid Connector - IExchange implementation for Hyperliquid DEX
//!
//! This module implements the IExchange interface for Hyperliquid DEX.
//! It provides a unified API for:
//! - Market data (REST API via InfoAPI)
//! - Trading operations (REST API with Ed25519 signing via ExchangeAPI)
//! - Account management (balance, positions)
//! - WebSocket subscriptions for real-time data
//!
//! Implementation Status:
//! - Phase A: Interface design ✓
//! - Phase B: Type definitions ✓
//! - Phase C: Core structure ✓
//! - Phase D: Full HTTP/WebSocket implementation ✓

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
const HyperliquidWS = @import("websocket.zig").HyperliquidWS;
const ws_types = @import("ws_types.zig");
const Subscription = ws_types.Subscription;
const Message = ws_types.Message;

// Re-export types for convenience
const TradingPair = types.TradingPair;
const Side = types.Side;
const OrderType = types.OrderType;
const OrderStatus = types.OrderStatus;
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

    // Asset mapping: coin name → asset index
    asset_map: ?std.StringHashMap(u64), // Populated on first use

    // WebSocket client for real-time data
    ws: ?*HyperliquidWS, // Optional: initialized when needed

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
            .asset_map = null, // Lazy-loaded on first use
            .ws = null, // Will be initialized when connect() is called with WebSocket enabled
        };

        // NOTE: Signer initialization is deferred to first use (lazy loading)
        // This prevents blocking on entropy/crypto initialization at startup
        // Signer will be initialized on-demand when needed for trading operations

        // Now initialize APIs with stable pointer to self.http_client
        self.info_api = InfoAPI.init(allocator, &self.http_client, logger);

        // Pass signer pointer to ExchangeAPI (will be null initially, initialized on first trade)
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
        // Cleanup asset map if initialized
        if (self.asset_map) |*map| {
            // Free all keys
            var iter = map.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            map.deinit();
        }
        // Cleanup WebSocket if initialized
        if (self.ws) |ws| {
            ws.deinit();
            self.allocator.destroy(ws);
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
        .getOpenOrders = getOpenOrders,
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

        // HTTP client is already initialized in create() - it's stateless
        // Just verify it's ready by doing a test connection (optional)

        // Initialize WebSocket client if enabled
        if (self.config.enable_websocket) {
            self.logger.info("WebSocket enabled, initializing...", .{}) catch {};
            try self.initWebSocket();
        }

        self.connected = true;

        self.logger.info("Successfully connected to Hyperliquid", .{}) catch {};
    }

    fn disconnect(ptr: *anyopaque) void {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        if (!self.connected) return;

        self.logger.info("Disconnecting from Hyperliquid...", .{}) catch {};

        // HTTP client is stateless - no explicit disconnect needed
        // It will be cleaned up in destroy()

        // Disconnect WebSocket if connected
        if (self.ws) |ws| {
            self.logger.info("Disconnecting WebSocket...", .{}) catch {};
            ws.disconnect();
        }

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

        // Ensure signer is initialized (lazy loading on first trade)
        try self.ensureSigner();

        // Validate order request
        try request.validate();

        // Convert to Hyperliquid symbol format
        const symbol = try symbol_mapper.toHyperliquid(request.pair);

        self.logger.debug("createOrder called: {s} {s} {s}", .{
            @tagName(request.side),
            @tagName(request.order_type),
            symbol,
        }) catch {};

        // Handle market orders: Hyperliquid doesn't support true market orders
        // Instead, use aggressive IOC limit orders with 5% slippage
        const order_price: Decimal = if (request.order_type == .market) blk: {
            // Get current market price from Info API
            var mids = try self.info_api.getAllMids();
            defer {
                // Free all duped strings in the HashMap
                var iter = mids.iterator();
                while (iter.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.allocator.free(entry.value_ptr.*);
                }
                mids.deinit();
            }

            const price_str = mids.get(symbol) orelse return error.SymbolNotFound;
            const current_price = try hl_types.parsePrice(price_str);

            // Apply 5% slippage for aggressive execution
            // Buy: price * 1.05 (pay more to ensure fill)
            // Sell: price * 0.95 (accept less to ensure fill)
            const slippage = try Decimal.fromString("0.05"); // 5%
            const one = Decimal.ONE;

            const aggressive_price_raw = if (request.side == .buy)
                current_price.mul(one.add(slippage)) // Buy: +5%
            else
                current_price.mul(one.sub(slippage)); // Sell: -5%

            // Round price to match BTC tick size (whole numbers for BTC)
            // For buy orders: round up to ensure fill
            // For sell orders: round down to ensure fill
            const price_float = aggressive_price_raw.toFloat();
            const price_rounded = if (request.side == .buy)
                @ceil(price_float) // Buy: round up
            else
                @floor(price_float); // Sell: round down

            const aggressive_price = Decimal.fromInt(@as(i64, @intFromFloat(price_rounded)));

            self.logger.debug("Market order → IOC limit: current={d}, aggressive={d} (rounded from {d})", .{
                current_price.toFloat(),
                aggressive_price.toFloat(),
                price_float,
            }) catch {};

            break :blk aggressive_price;
        } else request.price orelse return error.LimitOrderRequiresPrice;

        const price_str = try hl_types.formatPrice(self.allocator, order_price);
        defer self.allocator.free(price_str);

        const size_str = try hl_types.formatSize(self.allocator, request.amount);
        defer self.allocator.free(size_str);

        // Convert order type and time-in-force
        // Market orders become IOC limit orders
        const hl_order_type = switch (request.order_type) {
            .limit => hl_types.HyperliquidOrderType{
                .limit = .{
                    .tif = switch (request.time_in_force) {
                        .gtc => "Gtc",
                        .ioc => "Ioc",
                        .alo => "Alo",
                        .fok => return error.UnsupportedTimeInForce, // Hyperliquid doesn't support FOK
                    },
                },
            },
            .market => hl_types.HyperliquidOrderType{
                .limit = .{
                    .tif = "Ioc", // Market orders always use IOC
                },
            },
        };

        // Look up asset index for the coin
        const asset_index = try self.getAssetIndex(symbol);

        const hl_request = hl_types.OrderRequest{
            .asset_index = asset_index,
            .coin = symbol,
            .is_buy = request.side == .buy,
            .sz = size_str,
            .limit_px = price_str,
            .order_type = hl_order_type,
            .reduce_only = request.reduce_only,
        };

        // Call Exchange API (with signing)
        const response = try self.exchange_api.placeOrder(hl_request);

        // Check response status
        if (!std.mem.eql(u8, response.status, "ok")) {
            self.logger.err("Order placement failed: {s}", .{response.status}) catch {};
            return error.OrderRejected;
        }

        // Extract order ID and status from response
        // Handle both "resting" (open) and "filled" (immediately executed) orders
        const OrderResult = struct {
            order_id: u64,
            status: OrderStatus,
            filled_amount: Decimal,
            avg_fill_price: ?Decimal,
        };

        const order_result = blk: {
            const resp = response.response;
            if (resp.data) |data| {
                if (data.statuses.len > 0) {
                    const status = data.statuses[0];

                    // Check for resting (open) order
                    if (status.resting) |resting| {
                        break :blk OrderResult{
                            .order_id = resting.oid,
                            .status = OrderStatus.open,
                            .filled_amount = Decimal.ZERO,
                            .avg_fill_price = null,
                        };
                    }

                    // Check for filled order (market IOC orders)
                    if (status.filled) |filled| {
                        const filled_amount = try hl_types.parseSize(filled.totalSz);
                        const avg_price = try hl_types.parsePrice(filled.avgPx);
                        break :blk OrderResult{
                            .order_id = filled.oid,
                            .status = OrderStatus.filled,
                            .filled_amount = filled_amount,
                            .avg_fill_price = avg_price,
                        };
                    }
                }
            }
            return error.InvalidOrderResponse;
        };

        self.logger.info("Order placed successfully: ID={d}, status={s}", .{
            order_result.order_id,
            @tagName(order_result.status),
        }) catch {};

        // Convert to unified Order format
        const now = Timestamp.now();
        return Order{
            .exchange_order_id = order_result.order_id,
            .client_order_id = null,
            .pair = request.pair,
            .side = request.side,
            .order_type = request.order_type,
            .status = order_result.status,
            .amount = request.amount,
            .price = request.price,
            .filled_amount = order_result.filled_amount,
            .avg_fill_price = order_result.avg_fill_price,
            .created_at = now,
            .updated_at = now,
        };
    }

    fn cancelOrder(ptr: *anyopaque, order_id: u64) anyerror!void {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.debug("cancelOrder called: {d}", .{order_id}) catch {};

        // Ensure signer is initialized (lazy loading)
        try self.ensureSigner();

        // Rate limit
        self.rate_limiter.wait();

        // Query open orders to find the coin for this order_id
        // IMPORTANT: Use api_key (main account), not signer address (API wallet)
        const user_address = self.config.api_key;
        const open_orders = try self.info_api.getOpenOrders(user_address);
        defer open_orders.deinit();

        // Find the order and extract its coin name
        var coin: ?[]const u8 = null;
        for (open_orders.value) |order| {
            if (order.oid == order_id) {
                coin = order.coin;
                break;
            }
        }

        if (coin == null) {
            self.logger.err("Order {d} not found in open orders", .{order_id}) catch {};
            return error.OrderNotFound;
        }

        // Look up asset index for the coin
        const asset_index = try self.getAssetIndex(coin.?);

        // Call Exchange API to cancel the order
        // The function returns void on success, throws error on failure
        try self.exchange_api.cancelOrder(asset_index, order_id);

        self.logger.info("Order cancelled successfully: ID={d}", .{order_id}) catch {};
    }

    fn cancelAllOrders(ptr: *anyopaque, pair: ?TradingPair) anyerror!u32 {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        // Ensure signer is initialized (lazy loading)
        try self.ensureSigner();

        // Rate limiting
        self.rate_limiter.wait();

        // Get count of open orders before cancellation
        // IMPORTANT: Use api_key (main account), not signer address (API wallet)
        const user_address = self.config.api_key;
        const before_orders = try self.info_api.getOpenOrders(user_address);
        defer before_orders.deinit();

        var before_count: u32 = 0;
        if (pair) |p| {
            // Count only orders for the specified pair
            for (before_orders.value) |order| {
                if (std.mem.eql(u8, order.coin, p.base)) {
                    before_count += 1;
                }
            }
            self.logger.debug("cancelAllOrders called for {s}-{s} ({d} orders)", .{ p.base, p.quote, before_count }) catch {};
        } else {
            before_count = @intCast(before_orders.value.len);
            self.logger.debug("cancelAllOrders called for all pairs ({d} orders)", .{before_count}) catch {};
        }

        if (before_count == 0) {
            self.logger.info("No orders to cancel", .{}) catch {};
            return 0;
        }

        // Extract coin name and look up asset index if pair is specified
        const asset_index: ?u64 = if (pair) |p|
            try self.getAssetIndex(p.base)
        else
            null;

        // Call Exchange API to cancel all orders
        // The function returns void on success, throws error on failure
        try self.exchange_api.cancelAllOrders(asset_index);

        // Get count of open orders after cancellation
        self.rate_limiter.wait();
        const after_orders = try self.info_api.getOpenOrders(user_address);
        defer after_orders.deinit();

        var after_count: u32 = 0;
        if (pair) |p| {
            for (after_orders.value) |order| {
                if (std.mem.eql(u8, order.coin, p.base)) {
                    after_count += 1;
                }
            }
        } else {
            after_count = @intCast(after_orders.value.len);
        }

        const cancelled_count = before_count - after_count;
        self.logger.info("Cancelled {d} orders", .{cancelled_count}) catch {};

        return cancelled_count;
    }

    fn getOrder(ptr: *anyopaque, order_id: u64) anyerror!Order {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.debug("getOrder called: {d}", .{order_id}) catch {};

        // Require signer for authentication (need user address)
        if (self.signer == null) {
            self.logger.err("Cannot get order: signer not configured", .{}) catch {};
            return error.SignerRequired;
        }

        // Rate limiting
        self.rate_limiter.wait();

        // Get user's open orders
        // IMPORTANT: Use api_key (main account), not signer address (API wallet)
        const user_address = self.config.api_key;
        const parsed_orders = try self.info_api.getOpenOrders(user_address);
        defer parsed_orders.deinit();

        // Search for the order by ID
        for (parsed_orders.value) |open_order| {
            if (open_order.oid == order_id) {
                // Found the order - convert to unified Order format
                const side: Side = if (std.mem.eql(u8, open_order.side, "B")) .buy else .sell;
                const price = try hl_types.parsePrice(open_order.limitPx);
                const amount = try hl_types.parsePrice(open_order.sz);
                const filled_amount = blk: {
                    const orig_sz = try hl_types.parsePrice(open_order.origSz);
                    break :blk orig_sz.sub(amount);
                };

                // Create TradingPair (Hyperliquid uses USDC as quote)
                const pair = TradingPair{
                    .base = open_order.coin,
                    .quote = "USDC",
                };

                // Convert orderType string to OrderType enum
                const order_type: OrderType = if (std.mem.eql(u8, open_order.orderType, "Market"))
                    .market
                else
                    .limit;

                self.logger.info("Order found: ID={d}, {s}-{s}, {s}, Price={d}, Amount={d}", .{
                    order_id,
                    pair.base,
                    pair.quote,
                    @tagName(side),
                    price.toFloat(),
                    amount.toFloat(),
                }) catch {};

                const created_at = Timestamp.fromMillis(@intCast(open_order.timestamp));

                return Order{
                    .exchange_order_id = open_order.oid,
                    .pair = pair,
                    .side = side,
                    .order_type = order_type,
                    .price = price,
                    .amount = amount,
                    .filled_amount = filled_amount,
                    .status = .open, // It's in openOrders, so status is open
                    .created_at = created_at,
                    .updated_at = created_at, // Same as created_at for open orders
                };
            }
        }

        // Order not found
        self.logger.warn("Order not found: ID={d}", .{order_id}) catch {};
        return error.OrderNotFound;
    }

    fn getOpenOrders(ptr: *anyopaque, pair: ?TradingPair) anyerror![]Order {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.debug("getOpenOrders called", .{}) catch {};

        // Ensure signer is initialized (lazy loading)
        try self.ensureSigner();

        // Rate limiting
        self.rate_limiter.wait();

        // Get user's open orders
        // IMPORTANT: Use api_key (main account), not signer address (API wallet)
        const user_address = self.config.api_key;
        const parsed_orders = try self.info_api.getOpenOrders(user_address);
        defer parsed_orders.deinit();

        // Count how many orders match the filter
        var count: usize = 0;
        for (parsed_orders.value) |open_order| {
            if (pair) |p| {
                // Filter by pair if specified
                if (std.mem.eql(u8, open_order.coin, p.base)) {
                    count += 1;
                }
            } else {
                count += 1;
            }
        }

        // Allocate array for result
        var orders = try self.allocator.alloc(Order, count);
        errdefer self.allocator.free(orders);

        // Convert all matching orders
        var idx: usize = 0;
        for (parsed_orders.value) |open_order| {
            // Check if this order matches the filter
            if (pair) |p| {
                if (!std.mem.eql(u8, open_order.coin, p.base)) {
                    continue;
                }
            }

            // Convert to unified Order format
            const side: Side = if (std.mem.eql(u8, open_order.side, "B")) .buy else .sell;
            const price = try hl_types.parsePrice(open_order.limitPx);
            const amount = try hl_types.parsePrice(open_order.sz);
            const filled_amount = blk: {
                const orig_sz = try hl_types.parsePrice(open_order.origSz);
                break :blk orig_sz.sub(amount);
            };

            // Create TradingPair (Hyperliquid uses USDC as quote)
            const order_pair = TradingPair{
                .base = open_order.coin,
                .quote = "USDC",
            };

            // Convert orderType string to OrderType enum
            const order_type: OrderType = if (std.mem.eql(u8, open_order.orderType, "Market"))
                .market
            else
                .limit;

            const created_at = Timestamp.fromMillis(@intCast(open_order.timestamp));

            orders[idx] = Order{
                .exchange_order_id = open_order.oid,
                .pair = order_pair,
                .side = side,
                .order_type = order_type,
                .price = price,
                .amount = amount,
                .filled_amount = filled_amount,
                .status = .open,
                .created_at = created_at,
                .updated_at = created_at,
                .avg_fill_price = null,
            };

            idx += 1;
        }

        self.logger.info("Retrieved {d} open orders", .{count}) catch {};
        return orders;
    }

    // ========================================================================
    // Account Operations (Info API - Phase D)
    // ========================================================================

    fn getBalance(ptr: *anyopaque) anyerror![]Balance {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.debug("getBalance called", .{}) catch {};

        // Ensure signer is initialized (lazy loading)
        try self.ensureSigner();

        // Rate limit
        self.rate_limiter.wait();

        // IMPORTANT: Use api_key (main account address), not signer address!
        // api_key = main account with funds
        // signer.address = API wallet for signing (authorized to trade on behalf of main account)
        const user_address = self.config.api_key;

        // Query user state from Info API
        const parsed = try self.info_api.getUserState(user_address);
        defer parsed.deinit();

        // Hyperliquid returns cross margin account data
        // For now, we return a single USDC balance (Hyperliquid's quote currency)
        var balances = try self.allocator.alloc(Balance, 1);
        errdefer self.allocator.free(balances);

        // Parse account values from string to Decimal
        const account_value = try hl_types.parsePrice(parsed.value.crossMarginSummary.accountValue);
        const withdrawable = try hl_types.parsePrice(parsed.value.withdrawable);
        const margin_used = try hl_types.parsePrice(parsed.value.crossMarginSummary.totalMarginUsed);

        balances[0] = Balance{
            .asset = "USDC", // Hyperliquid uses USDC as collateral
            .total = account_value,
            .available = withdrawable,
            .locked = margin_used,
        };

        self.logger.info("Balance retrieved: total={d}, available={d}, locked={d}", .{
            account_value.toFloat(),
            withdrawable.toFloat(),
            margin_used.toFloat(),
        }) catch {};

        return balances;
    }

    fn getPositions(ptr: *anyopaque) anyerror![]Position {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.debug("getPositions called", .{}) catch {};

        // Ensure signer is initialized (lazy loading)
        try self.ensureSigner();

        // Rate limiting
        self.rate_limiter.wait();

        // IMPORTANT: Use api_key (main account address), not signer address!
        // api_key = main account with funds
        // signer.address = API wallet for signing (authorized to trade on behalf of main account)
        const user_address = self.config.api_key;
        const parsed = try self.info_api.getUserState(user_address);
        defer parsed.deinit();

        // Parse positions from assetPositions array
        var positions_list = try std.ArrayList(Position).initCapacity(self.allocator, parsed.value.assetPositions.len);
        errdefer positions_list.deinit(self.allocator);

        for (parsed.value.assetPositions) |asset_pos| {
            // Parse position size (szi)
            const size_str = asset_pos.position.szi;
            const size_value = try hl_types.parsePrice(size_str);

            // Skip zero positions
            if (size_value.isZero()) continue;

            // Determine side (long if positive, short if negative)
            const is_long = size_value.isPositive();
            const abs_size = if (is_long) size_value else size_value.negate();

            // Parse entry price
            const entry_price = if (asset_pos.position.entryPx) |entry_px|
                try hl_types.parsePrice(entry_px)
            else
                Decimal.ZERO;

            // Parse unrealized PnL
            const unrealized_pnl = try hl_types.parsePrice(asset_pos.position.unrealizedPnl);

            // Convert Hyperliquid symbol to TradingPair
            // Hyperliquid perpetuals always use USDC as quote currency
            const pair = TradingPair{
                .base = asset_pos.position.coin,
                .quote = "USDC",
            };

            // Parse margin used
            const margin_used = try hl_types.parsePrice(asset_pos.position.marginUsed);

            try positions_list.append(self.allocator, Position{
                .pair = pair,
                .side = if (is_long) .buy else .sell,
                .size = abs_size,
                .entry_price = entry_price,
                .unrealized_pnl = unrealized_pnl,
                .leverage = asset_pos.position.leverage.value,
                .margin_used = margin_used,
            });
        }

        const positions = try positions_list.toOwnedSlice(self.allocator);

        self.logger.info("Positions retrieved: {d} positions", .{positions.len}) catch {};

        return positions;
    }

    // ========================================================================
    // WebSocket Methods (Phase D.2)
    // ========================================================================

    /// Initialize WebSocket connection
    ///
    /// Must be called before subscribing to channels
    pub fn initWebSocket(self: *HyperliquidConnector) !void {
        if (self.ws != null) {
            // Already initialized
            return;
        }

        self.logger.debug("Initializing WebSocket client", .{}) catch {};

        // Create WebSocket config
        const ws_url = if (self.config.testnet)
            "wss://api.hyperliquid-testnet.xyz/ws"
        else
            "wss://api.hyperliquid.xyz/ws";

        const ws_config = HyperliquidWS.Config{
            .ws_url = ws_url,
            .host = if (self.config.testnet) "api.hyperliquid-testnet.xyz" else "api.hyperliquid.xyz",
            .port = 443,
            .path = "/ws",
            .use_tls = true,
            .ping_interval_ms = 30000, // 30 seconds
            .reconnect_interval_ms = 5000, // 5 seconds
            .max_reconnect_attempts = 5,
        };

        // Create and initialize WebSocket client
        const ws = try self.allocator.create(HyperliquidWS);
        errdefer self.allocator.destroy(ws);

        ws.* = HyperliquidWS.init(self.allocator, ws_config, self.logger);
        self.ws = ws;

        // Connect
        try ws.connect();

        self.logger.info("WebSocket initialized and connected", .{}) catch {};
    }

    /// Subscribe to a WebSocket channel
    ///
    /// @param subscription: Subscription details (channel, coin, user)
    pub fn subscribe(self: *HyperliquidConnector, subscription: Subscription) !void {
        if (self.ws == null) {
            return error.WebSocketNotInitialized;
        }

        try self.ws.?.subscribe(subscription);
    }

    /// Unsubscribe from a WebSocket channel
    ///
    /// @param subscription: Subscription to remove
    pub fn unsubscribe(self: *HyperliquidConnector, subscription: Subscription) !void {
        if (self.ws == null) {
            return error.WebSocketNotInitialized;
        }

        try self.ws.?.unsubscribe(subscription);
    }

    /// Set WebSocket message callback with context
    ///
    /// @param callback: Function to call when a message is received
    /// @param ctx: Context pointer passed to callback
    pub fn setMessageCallback(
        self: *HyperliquidConnector,
        callback: *const fn (ctx: ?*anyopaque, msg: Message) void,
        ctx: ?*anyopaque,
    ) !void {
        if (self.ws == null) {
            return error.WebSocketNotInitialized;
        }

        self.ws.?.setMessageCallback(callback, ctx);
    }

    /// Check if WebSocket is initialized
    pub fn isWebSocketInitialized(self: *HyperliquidConnector) bool {
        return self.ws != null;
    }

    /// Disconnect WebSocket (does not destroy it)
    pub fn disconnectWebSocket(self: *HyperliquidConnector) void {
        if (self.ws) |ws| {
            ws.disconnect();
        }
    }

    // ========================================================================
    // Helper Methods (Phase D)
    // ========================================================================

    /// Initialize signer from private key hex string
    ///
    /// Ensure signer is initialized (lazy initialization)
    /// Only initializes if not already initialized and credentials are available
    pub fn ensureSigner(self: *HyperliquidConnector) !void {
        // Already initialized
        if (self.signer != null) return;

        // No credentials provided
        if (self.config.api_secret.len == 0) {
            return error.SignerRequired;
        }

        // Initialize signer now
        self.logger.info("Lazy-initializing signer for trading operations...", .{}) catch {};
        self.signer = try self.initializeSigner(self.config.api_secret);

        // Update ExchangeAPI with the new signer
        const signer_ptr = if (self.signer) |*s| s else null;
        self.exchange_api.signer = signer_ptr;
    }

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

        // Initialize signer (with testnet flag for phantom agent)
        const signer = try Signer.init(self.allocator, private_key_bytes, self.config.testnet);

        self.logger.info("Initialized signer with address: {s}", .{signer.address}) catch {};

        return signer;
    }

    /// Load asset mapping from Hyperliquid meta API
    ///
    /// Populates self.asset_map with coin name → asset index mapping
    fn loadAssetMap(self: *HyperliquidConnector) !void {
        if (self.asset_map != null) {
            return; // Already loaded
        }

        self.logger.debug("Loading asset mapping from getMeta", .{}) catch {};

        // Call getMeta API
        const meta = try self.info_api.getMeta();
        defer meta.deinit();

        // Create hash map
        var map = std.StringHashMap(u64).init(self.allocator);
        errdefer map.deinit();

        // Populate map with coin name → asset index
        for (meta.value.universe, 0..) |asset, index| {
            // Duplicate the coin name string (will be freed in destroy())
            const coin_name = try self.allocator.dupe(u8, asset.name);
            errdefer self.allocator.free(coin_name);

            try map.put(coin_name, index);

            self.logger.debug("Asset mapping: {s} → {d}", .{ coin_name, index }) catch {};
        }

        self.asset_map = map;
        self.logger.info("Loaded asset mapping: {d} assets", .{map.count()}) catch {};
    }

    /// Get asset index for a given coin name
    ///
    /// @param coin: Coin name (e.g., "ETH", "BTC")
    /// @return Asset index
    fn getAssetIndex(self: *HyperliquidConnector, coin: []const u8) !u64 {
        // Ensure asset map is loaded
        if (self.asset_map == null) {
            try self.loadAssetMap();
        }

        // Look up asset index
        if (self.asset_map.?.get(coin)) |index| {
            return index;
        }

        // Asset not found
        self.logger.err("Asset not found in mapping: {s}", .{coin}) catch {};
        return error.AssetNotFound;
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
        .ptr = @ptrCast(@constCast(&struct {}{})),
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
        .ptr = @ptrCast(@constCast(&struct {}{})),
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
        .ptr = @ptrCast(@constCast(&struct {}{})),
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
        .ptr = @ptrCast(@constCast(&struct {}{})),
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

    // Trading methods implemented: createOrder, cancelOrder, getBalance
    // getBalance requires signer (no signer in this test config)
    try std.testing.expectError(error.SignerRequired, exchange.getBalance());

    // getPositions requires signer (no signer in this test config)
    try std.testing.expectError(error.SignerRequired, exchange.getPositions());

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
        .ptr = @ptrCast(@constCast(&struct {}{})),
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
        .ptr = @ptrCast(@constCast(&struct {}{})),
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
        .ptr = @ptrCast(@constCast(&struct {}{})),
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
        .ptr = @ptrCast(@constCast(&struct {}{})),
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
        .ptr = @ptrCast(@constCast(&struct {}{})),
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

    // Signer uses lazy initialization, so it won't be initialized until first use
    try std.testing.expect(connector.signer == null);

    // Trigger signer initialization by calling ensureSigner
    try connector.ensureSigner();

    // Now verify signer was initialized
    try std.testing.expect(connector.signer != null);
    if (connector.signer) |signer| {
        try std.testing.expect(signer.address.len > 0);
    }
}

test "HyperliquidConnector: cancelOrder - requires signer" {
    const allocator = std.testing.allocator;

    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../root.zig").logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../root.zig").logger.LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
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

    // Should fail because no signer is configured
    try std.testing.expectError(error.SignerRequired, exchange.cancelOrder(12345));
}

test "HyperliquidConnector: getBalance - requires signer" {
    const allocator = std.testing.allocator;

    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../root.zig").logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../root.zig").logger.LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
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

    // Should fail because no signer is configured
    try std.testing.expectError(error.SignerRequired, exchange.getBalance());
}

test "HyperliquidConnector: getPositions - requires signer" {
    const allocator = std.testing.allocator;

    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../root.zig").logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../root.zig").logger.LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
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

    // Should fail because no signer is configured
    try std.testing.expectError(error.SignerRequired, exchange.getPositions());
}

test "HyperliquidConnector: getOrder - requires signer" {
    const allocator = std.testing.allocator;

    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../root.zig").logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../root.zig").logger.LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
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

    // Should fail because no signer is configured
    try std.testing.expectError(error.SignerRequired, exchange.getOrder(12345));
}

test "HyperliquidConnector: cancelAllOrders - requires signer" {
    const allocator = std.testing.allocator;

    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../root.zig").logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../root.zig").logger.LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
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

    // Should fail because no signer is configured
    try std.testing.expectError(error.SignerRequired, exchange.cancelAllOrders(null));
}

test "HyperliquidConnector: asset mapping - lazy initialization" {
    const allocator = std.testing.allocator;

    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../root.zig").logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../root.zig").logger.LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
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

    // Verify asset map is initially null (lazy initialization)
    try std.testing.expect(connector.asset_map == null);

    // NOTE: Full asset mapping tests (loadAssetMap, getAssetIndex) require
    // network access to call getMeta() API, so they are tested in integration tests.
}
