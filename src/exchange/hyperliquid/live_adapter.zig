//! Hyperliquid Live Trading Adapters
//!
//! Provides IDataProvider and IExecutionClient adapters for HyperliquidConnector
//! to enable live trading through the LiveTradingEngine.
//!
//! These adapters bridge the IExchange interface to the data/execution interfaces
//! required by the core trading engine.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import core types
const IDataProvider = @import("../../core/data_engine.zig").IDataProvider;
const DataMessage = @import("../../core/data_engine.zig").DataMessage;
const Subscription = @import("../../core/data_engine.zig").Subscription;
const SubscriptionType = @import("../../core/data_engine.zig").SubscriptionType;
const QuoteMessage = @import("../../core/data_engine.zig").QuoteMessage;
const OrderbookMessage = @import("../../core/data_engine.zig").OrderbookMessage;

const IExecutionClient = @import("../../core/execution_engine.zig").IExecutionClient;
const OrderRequest = @import("../../core/execution_engine.zig").OrderRequest;
const OrderResult = @import("../../core/execution_engine.zig").OrderResult;
const PositionInfo = @import("../../core/execution_engine.zig").PositionInfo;
const BalanceInfo = @import("../../core/execution_engine.zig").BalanceInfo;

const Decimal = @import("../../core/decimal.zig").Decimal;
const Timestamp = @import("../../core/time.zig").Timestamp;
const Side = @import("../types.zig").Side;
const OrderType = @import("../types.zig").OrderType;
const OrderStatus = @import("../types.zig").OrderStatus;
const TradingPair = @import("../types.zig").TradingPair;

// Import Hyperliquid connector
const HyperliquidConnector = @import("connector.zig").HyperliquidConnector;
const ExchangeConfig = @import("../../core/config.zig").ExchangeConfig;
const Logger = @import("../../core/logger.zig").Logger;

// ============================================================================
// Hyperliquid Data Provider
// ============================================================================

/// Adapter that implements IDataProvider using HyperliquidConnector
pub const HyperliquidDataProvider = struct {
    allocator: Allocator,
    connector: *HyperliquidConnector,
    subscriptions: std.StringHashMap(SubscriptionType),
    message_queue: std.ArrayList(DataMessage),
    is_connected: bool,
    poll_interval_ms: u64,
    last_poll: i64,

    const Self = @This();

    /// Create a new HyperliquidDataProvider
    pub fn init(allocator: Allocator, connector: *HyperliquidConnector) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .connector = connector,
            .subscriptions = std.StringHashMap(SubscriptionType).init(allocator),
            .message_queue = std.ArrayList(DataMessage).init(allocator),
            .is_connected = false,
            .poll_interval_ms = 1000, // Poll every 1 second
            .last_poll = 0,
        };
        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        // Free subscription keys
        var iter = self.subscriptions.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.subscriptions.deinit();
        self.message_queue.deinit();
        self.allocator.destroy(self);
    }

    /// Get the IDataProvider interface
    pub fn provider(self: *Self) IDataProvider {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = IDataProvider.VTable{
        .connect = connectImpl,
        .disconnect = disconnectImpl,
        .subscribe = subscribeImpl,
        .unsubscribe = unsubscribeImpl,
        .poll = pollImpl,
    };

    fn connectImpl(ptr: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.is_connected) return;

        // Connect the underlying connector
        const iface = self.connector.interface();
        try iface.connect();

        self.is_connected = true;

        // Queue connected message
        try self.message_queue.append(.connected);

        std.log.info("HyperliquidDataProvider: Connected to exchange", .{});
    }

    fn disconnectImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (!self.is_connected) return;

        // Disconnect the underlying connector
        const iface = self.connector.interface();
        iface.disconnect();

        self.is_connected = false;

        // Queue disconnected message
        self.message_queue.append(.disconnected) catch {};

        std.log.info("HyperliquidDataProvider: Disconnected from exchange", .{});
    }

    fn subscribeImpl(ptr: *anyopaque, sub: Subscription) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // Store subscription
        const symbol_copy = try self.allocator.dupe(u8, sub.symbol);
        errdefer self.allocator.free(symbol_copy);

        const result = try self.subscriptions.getOrPut(symbol_copy);
        if (result.found_existing) {
            self.allocator.free(symbol_copy);
        }
        result.value_ptr.* = sub.sub_type;

        std.log.info("HyperliquidDataProvider: Subscribed to {s}", .{sub.symbol});
    }

    fn unsubscribeImpl(ptr: *anyopaque, symbol: []const u8) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.subscriptions.fetchRemove(symbol)) |kv| {
            self.allocator.free(kv.key);
        }

        std.log.info("HyperliquidDataProvider: Unsubscribed from {s}", .{symbol});
    }

    fn pollImpl(ptr: *anyopaque) ?DataMessage {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // Return queued messages first
        if (self.message_queue.items.len > 0) {
            return self.message_queue.orderedRemove(0);
        }

        // Check if it's time to poll
        const now = std.time.milliTimestamp();
        if (now - self.last_poll < @as(i64, @intCast(self.poll_interval_ms))) {
            return null;
        }
        self.last_poll = now;

        // Poll subscribed symbols for data
        if (!self.is_connected) return null;

        var iter = self.subscriptions.iterator();
        while (iter.next()) |entry| {
            const symbol = entry.key_ptr.*;
            const sub_type = entry.value_ptr.*;

            // Fetch quote data
            if (sub_type == .quote or sub_type == .all) {
                const msg = self.fetchQuote(symbol) catch |err| {
                    std.log.warn("HyperliquidDataProvider: Failed to fetch quote for {s}: {}", .{ symbol, err });
                    continue;
                };
                if (msg) |m| {
                    return m;
                }
            }
        }

        return null;
    }

    /// Fetch quote data for a symbol
    fn fetchQuote(self: *Self, symbol: []const u8) !?DataMessage {
        // Parse symbol to TradingPair
        const pair = parseSymbol(symbol);

        // Get ticker from connector
        const iface = self.connector.interface();
        const ticker = try iface.getTicker(pair);

        return DataMessage{
            .quote = QuoteMessage{
                .symbol = symbol,
                .bid = ticker.bid,
                .ask = ticker.ask,
                .bid_size = Decimal.fromFloat(1.0), // Not available from ticker
                .ask_size = Decimal.fromFloat(1.0),
                .timestamp = ticker.timestamp,
            },
        };
    }

    /// Parse symbol string to TradingPair
    fn parseSymbol(symbol: []const u8) TradingPair {
        // Handle formats like "BTC-USDT", "BTC/USDT", "BTCUSDT"
        if (std.mem.indexOf(u8, symbol, "-")) |idx| {
            return .{ .base = symbol[0..idx], .quote = symbol[idx + 1 ..] };
        } else if (std.mem.indexOf(u8, symbol, "/")) |idx| {
            return .{ .base = symbol[0..idx], .quote = symbol[idx + 1 ..] };
        } else {
            // Try to split known quote currencies
            const quotes = [_][]const u8{ "USDT", "USDC", "USD", "BTC", "ETH" };
            for (quotes) |q| {
                if (std.mem.endsWith(u8, symbol, q)) {
                    return .{ .base = symbol[0 .. symbol.len - q.len], .quote = q };
                }
            }
            return .{ .base = symbol, .quote = "USDT" };
        }
    }
};

// ============================================================================
// Hyperliquid Execution Client
// ============================================================================

/// Adapter that implements IExecutionClient using HyperliquidConnector
pub const HyperliquidExecutionClient = struct {
    allocator: Allocator,
    connector: *HyperliquidConnector,

    const Self = @This();

    /// Create a new HyperliquidExecutionClient
    pub fn init(allocator: Allocator, connector: *HyperliquidConnector) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .connector = connector,
        };
        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Get the IExecutionClient interface
    pub fn client(self: *Self) IExecutionClient {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = IExecutionClient.VTable{
        .submit_order = submitOrderImpl,
        .cancel_order = cancelOrderImpl,
        .get_order_status = getOrderStatusImpl,
        .get_position = getPositionImpl,
        .get_balance = getBalanceImpl,
    };

    fn submitOrderImpl(ptr: *anyopaque, request: OrderRequest) anyerror!OrderResult {
        const self: *Self = @ptrCast(@alignCast(ptr));

        std.log.info("HyperliquidExecutionClient: Submitting order {s} {s} {s}", .{
            @tagName(request.side),
            @tagName(request.order_type),
            request.symbol,
        });

        // Convert to exchange OrderRequest
        const pair = HyperliquidDataProvider.parseSymbol(request.symbol);
        const exchange_request = @import("../types.zig").OrderRequest{
            .pair = pair,
            .side = request.side,
            .order_type = request.order_type,
            .amount = request.quantity,
            .price = request.price,
            .client_order_id = request.client_order_id,
            .time_in_force = switch (request.time_in_force) {
                .gtc => .gtc,
                .ioc => .ioc,
                .fok => .fok,
            },
            .reduce_only = request.reduce_only,
        };

        // Submit order through connector
        const iface = self.connector.interface();
        const order = iface.createOrder(exchange_request) catch |err| {
            return OrderResult{
                .success = false,
                .error_code = 5000,
                .error_message = @errorName(err),
                .timestamp = Timestamp.now(),
            };
        };

        return OrderResult{
            .success = true,
            .order_id = order.order_id,
            .exchange_order_id = order.exchange_order_id,
            .status = order.status,
            .filled_quantity = order.filled_quantity,
            .filled_price = order.average_fill_price,
            .timestamp = Timestamp.now(),
        };
    }

    fn cancelOrderImpl(ptr: *anyopaque, order_id: []const u8) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        std.log.info("HyperliquidExecutionClient: Cancelling order {s}", .{order_id});

        const iface = self.connector.interface();
        try iface.cancelOrder(order_id);
    }

    fn getOrderStatusImpl(ptr: *anyopaque, order_id: []const u8) anyerror!?OrderStatus {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const iface = self.connector.interface();
        const order = iface.getOrder(order_id) catch return null;

        if (order) |o| {
            return o.status;
        }
        return null;
    }

    fn getPositionImpl(ptr: *anyopaque, symbol: []const u8) anyerror!?PositionInfo {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const iface = self.connector.interface();
        const positions = try iface.getPositions();
        defer self.allocator.free(positions);

        for (positions) |pos| {
            // Match by base currency
            const pair = HyperliquidDataProvider.parseSymbol(symbol);
            if (std.mem.eql(u8, pos.pair.base, pair.base)) {
                return PositionInfo{
                    .symbol = symbol,
                    .size = pos.size,
                    .entry_price = pos.entry_price,
                    .unrealized_pnl = pos.unrealized_pnl,
                    .leverage = pos.leverage,
                };
            }
        }

        return null;
    }

    fn getBalanceImpl(ptr: *anyopaque) anyerror!BalanceInfo {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const iface = self.connector.interface();
        const balance = try iface.getBalance();

        return BalanceInfo{
            .total = balance.total,
            .available = balance.available,
            .margin_used = balance.margin_used,
        };
    }
};

// ============================================================================
// Factory Function
// ============================================================================

/// Configuration for creating live trading adapters
pub const LiveAdapterConfig = struct {
    allocator: Allocator,
    wallet: []const u8,
    private_key: []const u8,
    testnet: bool = true,
    enable_websocket: bool = false,
};

/// Create both data provider and execution client for Hyperliquid
pub fn createHyperliquidAdapters(config: LiveAdapterConfig, logger: Logger) !struct {
    connector: *HyperliquidConnector,
    data_provider: *HyperliquidDataProvider,
    execution_client: *HyperliquidExecutionClient,
} {
    // Create exchange config
    const exchange_config = ExchangeConfig{
        .name = "hyperliquid",
        .api_key = config.wallet,
        .api_secret = config.private_key,
        .testnet = config.testnet,
        .enable_websocket = config.enable_websocket,
    };

    // Create connector
    const connector = try HyperliquidConnector.create(config.allocator, exchange_config, logger);
    errdefer connector.destroy();

    // Create data provider
    const data_provider = try HyperliquidDataProvider.init(config.allocator, connector);
    errdefer data_provider.deinit();

    // Create execution client
    const execution_client = try HyperliquidExecutionClient.init(config.allocator, connector);
    errdefer execution_client.deinit();

    return .{
        .connector = connector,
        .data_provider = data_provider,
        .execution_client = execution_client,
    };
}
