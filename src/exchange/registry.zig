//! Exchange Registry - Manage exchange connections and lifecycle
//!
//! The ExchangeRegistry is responsible for:
//! - Registering exchange connectors
//! - Managing exchange lifecycle (connect/disconnect)
//! - Providing unified access to exchange instances
//! - (Future) Load balancing across multiple exchange instances
//!
//! MVP Implementation:
//! - Single exchange support (Hyperliquid)
//! - Simple getter/setter pattern
//!
//! Future enhancements:
//! - Multiple exchange support
//! - Connection pooling
//! - Automatic reconnection
//! - Health checking

const std = @import("std");
const IExchange = @import("interface.zig").IExchange;
const Logger = @import("../root.zig").Logger;
const ExchangeConfig = @import("../root.zig").ExchangeConfig;

// ============================================================================
// Exchange Registry
// ============================================================================

/// ExchangeRegistry manages exchange connectors and their lifecycle
///
/// MVP: Supports a single exchange instance
/// Future: Will support multiple exchanges with routing
pub const ExchangeRegistry = struct {
    allocator: std.mem.Allocator,
    exchange: ?IExchange,
    config: ?ExchangeConfig,
    logger: Logger,
    connected: bool,

    /// Initialize the registry
    pub fn init(allocator: std.mem.Allocator, logger: Logger) ExchangeRegistry {
        return .{
            .allocator = allocator,
            .exchange = null,
            .config = null,
            .logger = logger,
            .connected = false,
        };
    }

    /// Deinitialize the registry (disconnect all exchanges)
    pub fn deinit(self: *ExchangeRegistry) void {
        self.disconnectAll();
    }

    // ========================================================================
    // Exchange Management
    // ========================================================================

    /// Set the exchange instance and its configuration
    ///
    /// MVP: Only one exchange is supported. Setting a new exchange will replace the old one.
    pub fn setExchange(
        self: *ExchangeRegistry,
        exchange: IExchange,
        config: ExchangeConfig,
    ) !void {
        // Disconnect existing exchange if any
        if (self.exchange) |_| {
            self.disconnectAll();
        }

        self.exchange = exchange;
        self.config = config;

        self.logger.info("Exchange registered: {s}", .{exchange.getName()}) catch {};
    }

    /// Get the registered exchange
    ///
    /// Returns error.NoExchangeRegistered if no exchange is set
    pub fn getExchange(self: *ExchangeRegistry) !IExchange {
        return self.exchange orelse error.NoExchangeRegistered;
    }

    /// Check if an exchange is registered
    pub fn hasExchange(self: *ExchangeRegistry) bool {
        return self.exchange != null;
    }

    /// Get exchange name
    pub fn getExchangeName(self: *ExchangeRegistry) ?[]const u8 {
        if (self.exchange) |exchange| {
            return exchange.getName();
        }
        return null;
    }

    // ========================================================================
    // Connection Management
    // ========================================================================

    /// Connect to all registered exchanges
    ///
    /// MVP: Connects to the single registered exchange
    pub fn connectAll(self: *ExchangeRegistry) !void {
        const exchange = try self.getExchange();

        self.logger.info("Connecting to exchange: {s}", .{exchange.getName()}) catch {};

        try exchange.connect();
        self.connected = true;

        self.logger.info("Successfully connected to {s}", .{exchange.getName()}) catch {};
    }

    /// Disconnect from all registered exchanges
    pub fn disconnectAll(self: *ExchangeRegistry) void {
        if (self.exchange) |exchange| {
            self.logger.info("Disconnecting from exchange: {s}", .{exchange.getName()}) catch {};
            exchange.disconnect();
            self.connected = false;
        }
    }

    /// Check if connected to exchange
    pub fn isConnected(self: *ExchangeRegistry) bool {
        if (self.exchange) |exchange| {
            return exchange.isConnected();
        }
        return false;
    }

    /// Reconnect to all exchanges
    pub fn reconnect(self: *ExchangeRegistry) !void {
        self.logger.info("Reconnecting to exchanges...", .{}) catch {};
        self.disconnectAll();
        try self.connectAll();
    }

    // ========================================================================
    // Future: Multi-Exchange Support
    // ========================================================================

    // The following methods are placeholders for future multi-exchange support:
    //
    // pub fn setExchanges(self: *ExchangeRegistry, exchanges: []IExchange) !void
    // pub fn getExchangeByName(self: *ExchangeRegistry, name: []const u8) !IExchange
    // pub fn getAllExchanges(self: *ExchangeRegistry) []IExchange
    // pub fn removeExchange(self: *ExchangeRegistry, name: []const u8) !void
};

// ============================================================================
// Tests
// ============================================================================

// Mock Exchange for testing
const MockExchange = struct {
    name: []const u8,
    is_connected: bool,

    pub fn create(name: []const u8) IExchange {
        const self = std.heap.page_allocator.create(MockExchange) catch unreachable;
        self.* = .{
            .name = name,
            .is_connected = false,
        };
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *MockExchange = @ptrCast(@alignCast(ptr));
        return self.name;
    }

    fn connect(ptr: *anyopaque) anyerror!void {
        const self: *MockExchange = @ptrCast(@alignCast(ptr));
        self.is_connected = true;
    }

    fn disconnect(ptr: *anyopaque) void {
        const self: *MockExchange = @ptrCast(@alignCast(ptr));
        self.is_connected = false;
    }

    fn isConnected(ptr: *anyopaque) bool {
        const self: *MockExchange = @ptrCast(@alignCast(ptr));
        return self.is_connected;
    }

    fn getTicker(ptr: *anyopaque, pair: @import("types.zig").TradingPair) anyerror!@import("types.zig").Ticker {
        _ = ptr;
        _ = pair;
        return error.NotImplemented;
    }

    fn getOrderbook(ptr: *anyopaque, pair: @import("types.zig").TradingPair, depth: u32) anyerror!@import("types.zig").Orderbook {
        _ = ptr;
        _ = pair;
        _ = depth;
        return error.NotImplemented;
    }

    fn createOrder(ptr: *anyopaque, request: @import("types.zig").OrderRequest) anyerror!@import("types.zig").Order {
        _ = ptr;
        _ = request;
        return error.NotImplemented;
    }

    fn cancelOrder(ptr: *anyopaque, order_id: u64) anyerror!void {
        _ = ptr;
        _ = order_id;
        return error.NotImplemented;
    }

    fn cancelAllOrders(ptr: *anyopaque, pair: ?@import("types.zig").TradingPair) anyerror!u32 {
        _ = ptr;
        _ = pair;
        return error.NotImplemented;
    }

    fn getOrder(ptr: *anyopaque, order_id: u64) anyerror!@import("types.zig").Order {
        _ = ptr;
        _ = order_id;
        return error.NotImplemented;
    }

    fn getBalance(ptr: *anyopaque) anyerror![]@import("types.zig").Balance {
        _ = ptr;
        return error.NotImplemented;
    }

    fn getOpenOrders(ptr: *anyopaque, pair: ?@import("types.zig").TradingPair) anyerror![]@import("types.zig").Order {
        _ = ptr;
        _ = pair;
        return error.NotImplemented;
    }

    fn getPositions(ptr: *anyopaque) anyerror![]@import("types.zig").Position {
        _ = ptr;
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

// Test helper: Create a dummy LogWriter for testing
fn createTestLogger(allocator: std.mem.Allocator) Logger {
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../root.zig").logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../root.zig").logger.LogWriter{
        .ptr = @constCast(@ptrCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    return Logger.init(allocator, writer, .info);
}

test "ExchangeRegistry: initialization" {
    var logger = createTestLogger(std.testing.allocator);
    defer logger.deinit();

    var registry = ExchangeRegistry.init(std.testing.allocator, logger);
    defer registry.deinit();

    try std.testing.expect(!registry.hasExchange());
    try std.testing.expect(!registry.isConnected());
}

test "ExchangeRegistry: setExchange and getExchange" {
    var logger = createTestLogger(std.testing.allocator);
    defer logger.deinit();

    var registry = ExchangeRegistry.init(std.testing.allocator, logger);
    defer registry.deinit();

    const mock_exchange = MockExchange.create("test_exchange");
    const config = ExchangeConfig{
        .name = "test",
        .api_key = "",
        .api_secret = "",
        .testnet = true,
    };

    try registry.setExchange(mock_exchange, config);

    try std.testing.expect(registry.hasExchange());

    const exchange = try registry.getExchange();
    try std.testing.expectEqualStrings("test_exchange", exchange.getName());
}

test "ExchangeRegistry: connect and disconnect" {
    var logger = createTestLogger(std.testing.allocator);
    defer logger.deinit();

    var registry = ExchangeRegistry.init(std.testing.allocator, logger);
    defer registry.deinit();

    const mock_exchange = MockExchange.create("test_exchange");
    const config = ExchangeConfig{
        .name = "test",
        .api_key = "",
        .api_secret = "",
        .testnet = true,
    };

    try registry.setExchange(mock_exchange, config);

    // Initially not connected
    try std.testing.expect(!registry.isConnected());

    // Connect
    try registry.connectAll();
    try std.testing.expect(registry.isConnected());

    // Disconnect
    registry.disconnectAll();
    try std.testing.expect(!registry.isConnected());
}

test "ExchangeRegistry: no exchange registered error" {
    var logger = createTestLogger(std.testing.allocator);
    defer logger.deinit();

    var registry = ExchangeRegistry.init(std.testing.allocator, logger);
    defer registry.deinit();

    try std.testing.expectError(error.NoExchangeRegistered, registry.getExchange());
}

test "ExchangeRegistry: reconnect" {
    var logger = createTestLogger(std.testing.allocator);
    defer logger.deinit();

    var registry = ExchangeRegistry.init(std.testing.allocator, logger);
    defer registry.deinit();

    const mock_exchange = MockExchange.create("test_exchange");
    const config = ExchangeConfig{
        .name = "test",
        .api_key = "",
        .api_secret = "",
        .testnet = true,
    };

    try registry.setExchange(mock_exchange, config);

    // Connect
    try registry.connectAll();
    try std.testing.expect(registry.isConnected());

    // Reconnect
    try registry.reconnect();
    try std.testing.expect(registry.isConnected());
}
