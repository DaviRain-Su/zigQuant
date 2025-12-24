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

    // Asset mapping: coin name → asset index
    asset_map: ?std.StringHashMap(u64), // Populated on first use

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
            .asset_map = null, // Lazy-loaded on first use
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
        // Cleanup asset map if initialized
        if (self.asset_map) |*map| {
            // Free all keys
            var iter = map.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            map.deinit();
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

        // Check if signer is available
        if (self.signer == null) {
            return error.SignerRequired;
        }

        // Rate limit
        self.rate_limiter.wait();

        // Query open orders to find the coin for this order_id
        const user_address = self.signer.?.address;
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
        const response = try self.exchange_api.cancelOrder(asset_index, order_id);

        // Check response status
        if (!std.mem.eql(u8, response.status, "ok")) {
            self.logger.err("Order cancellation failed: {s}", .{response.status}) catch {};
            return error.CancelOrderFailed;
        }

        self.logger.info("Order cancelled successfully: ID={d}", .{order_id}) catch {};
    }

    fn cancelAllOrders(ptr: *anyopaque, pair: ?TradingPair) anyerror!u32 {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        // Require signer for authentication
        if (self.signer == null) {
            self.logger.err("Cannot cancel orders: signer not configured", .{}) catch {};
            return error.SignerRequired;
        }

        // Rate limiting
        self.rate_limiter.wait();

        // Get count of open orders before cancellation
        const user_address = self.signer.?.address;
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
        const response = try self.exchange_api.cancelAllOrders(asset_index);

        // Check response status
        if (!std.mem.eql(u8, response.status, "ok")) {
            self.logger.err("Cancel all orders failed: {s}", .{response.status}) catch {};
            return error.CancelAllOrdersFailed;
        }

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
        const user_address = self.signer.?.address;
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

                self.logger.info("Order found: ID={d}, {s}-{s}, {s}, Price={}, Amount={}", .{
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

    // ========================================================================
    // Account Operations (Info API - Phase D)
    // ========================================================================

    fn getBalance(ptr: *anyopaque) anyerror![]Balance {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.debug("getBalance called", .{}) catch {};

        // Check if signer is available (we need the user address)
        if (self.signer == null) {
            return error.SignerRequired;
        }

        // Rate limit
        self.rate_limiter.wait();

        // Get user address from signer
        const user_address = self.signer.?.address;

        // Query user state from Info API
        const user_state = try self.info_api.getUserState(user_address);

        // Hyperliquid returns cross margin account data
        // For now, we return a single USDC balance (Hyperliquid's quote currency)
        var balances = try self.allocator.alloc(Balance, 1);
        errdefer self.allocator.free(balances);

        // Parse account values from string to Decimal
        const account_value = try hl_types.parsePrice(user_state.crossMarginSummary.accountValue);
        const withdrawable = try hl_types.parsePrice(user_state.crossMarginSummary.withdrawable);
        const margin_used = try hl_types.parsePrice(user_state.crossMarginSummary.totalMarginUsed);

        balances[0] = Balance{
            .asset = "USDC", // Hyperliquid uses USDC as collateral
            .total = account_value,
            .available = withdrawable,
            .locked = margin_used,
        };

        self.logger.info("Balance retrieved: total={}, available={}, locked={}", .{
            account_value.toFloat(),
            withdrawable.toFloat(),
            margin_used.toFloat(),
        }) catch {};

        return balances;
    }

    fn getPositions(ptr: *anyopaque) anyerror![]Position {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        self.logger.debug("getPositions called", .{}) catch {};

        // Require signer for authentication (need user address)
        if (self.signer == null) {
            self.logger.err("Cannot get positions: signer not configured", .{}) catch {};
            return error.SignerRequired;
        }

        // Rate limiting
        self.rate_limiter.wait();

        // Get user state from Info API
        const user_address = self.signer.?.address;
        const user_state = try self.info_api.getUserState(user_address);

        // Parse positions from assetPositions array
        var positions_list = try std.ArrayList(Position).initCapacity(self.allocator, user_state.assetPositions.len);
        errdefer positions_list.deinit(self.allocator);

        for (user_state.assetPositions) |asset_pos| {
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

        self.logger.info("Positions retrieved: {} positions", .{positions.len}) catch {};

        return positions;
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

test "HyperliquidConnector: cancelOrder - requires signer" {
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

    // Verify asset map is initially null (lazy initialization)
    try std.testing.expect(connector.asset_map == null);

    // NOTE: Full asset mapping tests (loadAssetMap, getAssetIndex) require
    // network access to call getMeta() API, so they are tested in integration tests.
}
