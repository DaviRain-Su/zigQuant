//! Live Trading Runner
//!
//! Wraps LiveTradingEngine for lifecycle management via API.
//! Provides real-time trading execution with exchange connectivity,
//! strategy integration, and managed start/stop lifecycle.
//!
//! Features:
//! - Lifecycle management (start/stop/pause/resume)
//! - Real-time market data streaming
//! - Order execution through exchange connectors
//! - Integration with MessageBus, Cache, DataEngine, ExecutionEngine
//! - Statistics and monitoring
//! - Reconnection handling

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import zigQuant types
const root = @import("../../root.zig");
const Decimal = root.Decimal;
const TradingPair = root.TradingPair;
const Timeframe = root.Timeframe;
const Timestamp = root.Timestamp;

// Import LiveTradingEngine from trading module
const live_engine = @import("../../trading/live_engine.zig");
const LiveTradingEngine = live_engine.LiveTradingEngine;
const AsyncLiveTradingEngine = live_engine.AsyncLiveTradingEngine;
const LiveConfig = live_engine.LiveConfig;
const TradingMode = live_engine.TradingMode;
const EngineState = live_engine.EngineState;
const ConnectionState = live_engine.ConnectionState;

// Import execution types
const execution_engine = @import("../../core/execution_engine.zig");
const OrderRequest = execution_engine.OrderRequest;
const OrderResult = execution_engine.OrderResult;
const RiskConfig = execution_engine.RiskConfig;
const IExecutionClient = execution_engine.IExecutionClient;
const IDataProvider = @import("../../core/data_engine.zig").IDataProvider;

/// Live trading request configuration (from API)
pub const LiveRequest = struct {
    /// Unique identifier for this live trading session
    name: []const u8 = "default",

    /// Trading mode (event_driven, clock_driven, hybrid)
    mode: TradingMode = .event_driven,

    /// Symbols to subscribe to
    symbols: []const []const u8 = &[_][]const u8{},

    /// Heartbeat interval in milliseconds
    heartbeat_interval_ms: u64 = 30000,

    /// Tick interval in milliseconds (for clock_driven mode)
    tick_interval_ms: u64 = 1000,

    /// Auto reconnect on disconnect
    auto_reconnect: bool = true,

    /// Max reconnect attempts
    max_reconnect_attempts: u32 = 10,

    /// Risk configuration
    risk: RiskConfig = .{},

    /// Exchange credentials
    exchange: []const u8 = "hyperliquid",
    wallet: ?[]const u8 = null,
    private_key: ?[]const u8 = null,
    testnet: bool = true,

    /// Parse symbol to TradingPair
    pub fn parsePair(symbol: []const u8) TradingPair {
        // Handle formats like "BTCUSDT", "BTC-USDT", "BTC/USDT"
        var base: []const u8 = "";
        var quote: []const u8 = "";

        if (std.mem.indexOf(u8, symbol, "-")) |idx| {
            base = symbol[0..idx];
            quote = symbol[idx + 1 ..];
        } else if (std.mem.indexOf(u8, symbol, "/")) |idx| {
            base = symbol[0..idx];
            quote = symbol[idx + 1 ..];
        } else {
            // Assume format like "BTCUSDT" - try common quote currencies
            const quote_currencies = [_][]const u8{ "USDT", "USDC", "USD", "BTC", "ETH" };
            for (quote_currencies) |q| {
                if (std.mem.endsWith(u8, symbol, q)) {
                    base = symbol[0 .. symbol.len - q.len];
                    quote = q;
                    break;
                }
            }
        }

        if (base.len == 0) {
            base = symbol;
            quote = "USDT";
        }

        return .{ .base = base, .quote = quote };
    }

    /// Convert to LiveConfig
    pub fn toLiveConfig(self: LiveRequest) LiveConfig {
        return .{
            .mode = self.mode,
            .heartbeat_interval_ms = self.heartbeat_interval_ms,
            .tick_interval_ms = self.tick_interval_ms,
            .auto_reconnect = self.auto_reconnect,
            .max_reconnect_attempts = self.max_reconnect_attempts,
            .risk = self.risk,
        };
    }
};

/// Live runner status
pub const LiveStatus = enum {
    stopped,
    starting,
    running,
    paused,
    stopping,
    reconnecting,
    error_state,

    pub fn toString(self: LiveStatus) []const u8 {
        return switch (self) {
            .stopped => "stopped",
            .starting => "starting",
            .running => "running",
            .paused => "paused",
            .stopping => "stopping",
            .reconnecting => "reconnecting",
            .error_state => "error",
        };
    }

    /// Convert from EngineState
    pub fn fromEngineState(state: EngineState) LiveStatus {
        return switch (state) {
            .stopped => .stopped,
            .starting => .starting,
            .running => .running,
            .stopping => .stopping,
            .failed => .error_state,
        };
    }
};

/// Live trading statistics
pub const LiveStats = struct {
    uptime_ms: u64 = 0,
    ticks: u64 = 0,
    heartbeats_sent: u64 = 0,
    reconnects: u64 = 0,
    orders_submitted: u64 = 0,
    orders_filled: u64 = 0,
    orders_cancelled: u64 = 0,
    orders_rejected: u64 = 0,
    total_volume: f64 = 0,
    realized_pnl: f64 = 0,
    unrealized_pnl: f64 = 0,
    last_price: f64 = 0,
    connection_uptime_pct: f64 = 100.0,
};

/// Order history entry
pub const OrderHistoryEntry = struct {
    timestamp: i64,
    order_id: []const u8,
    symbol: []const u8,
    side: []const u8,
    order_type: []const u8,
    quantity: f64,
    price: ?f64,
    status: []const u8,
    filled_quantity: f64,
    error_message: ?[]const u8,
};

/// Live Trading Runner - manages a single live trading session
pub const LiveRunner = struct {
    allocator: Allocator,
    id: []const u8,
    request: LiveRequest,
    status: LiveStatus,
    stats: LiveStats,
    start_time: i64,
    last_error: ?[]const u8,

    // Core engine
    engine: ?LiveTradingEngine,

    // Order history
    order_history: std.ArrayList(OrderHistoryEntry),
    max_history_size: usize,

    // Subscribed symbols (owned copies)
    subscribed_symbols: std.ArrayList([]const u8),

    // Thread management
    thread: ?std.Thread,
    should_stop: std.atomic.Value(bool),
    is_paused: std.atomic.Value(bool),
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Create a new live runner
    pub fn init(allocator: Allocator, id: []const u8, request: LiveRequest) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Copy ID
        const id_copy = try allocator.dupe(u8, id);
        errdefer allocator.free(id_copy);

        // Copy request strings
        const name_copy = try allocator.dupe(u8, request.name);
        errdefer allocator.free(name_copy);

        const exchange_copy = try allocator.dupe(u8, request.exchange);
        errdefer allocator.free(exchange_copy);

        var wallet_copy: ?[]const u8 = null;
        if (request.wallet) |w| {
            wallet_copy = try allocator.dupe(u8, w);
        }

        var private_key_copy: ?[]const u8 = null;
        if (request.private_key) |pk| {
            private_key_copy = try allocator.dupe(u8, pk);
        }

        // Copy symbols
        var symbols_copy = std.ArrayList([]const u8){};
        errdefer {
            for (symbols_copy.items) |s| {
                allocator.free(s);
            }
            symbols_copy.deinit(allocator);
        }

        for (request.symbols) |symbol| {
            const s = try allocator.dupe(u8, symbol);
            try symbols_copy.append(allocator, s);
        }

        self.* = .{
            .allocator = allocator,
            .id = id_copy,
            .request = .{
                .name = name_copy,
                .mode = request.mode,
                .symbols = &[_][]const u8{}, // Will use subscribed_symbols
                .heartbeat_interval_ms = request.heartbeat_interval_ms,
                .tick_interval_ms = request.tick_interval_ms,
                .auto_reconnect = request.auto_reconnect,
                .max_reconnect_attempts = request.max_reconnect_attempts,
                .risk = request.risk,
                .exchange = exchange_copy,
                .wallet = wallet_copy,
                .private_key = private_key_copy,
                .testnet = request.testnet,
            },
            .status = .stopped,
            .stats = .{},
            .start_time = 0,
            .last_error = null,
            .engine = null,
            .order_history = std.ArrayList(OrderHistoryEntry){},
            .max_history_size = 1000,
            .subscribed_symbols = symbols_copy,
            .thread = null,
            .should_stop = std.atomic.Value(bool).init(false),
            .is_paused = std.atomic.Value(bool).init(false),
            .mutex = .{},
        };

        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        // Stop if running
        if (self.status == .running or self.status == .paused) {
            self.stop() catch {};
        }

        // Wait for thread
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        // Clean up engine
        if (self.engine) |*engine| {
            engine.deinit();
        }

        // Clean up order history
        for (self.order_history.items) |entry| {
            self.allocator.free(entry.order_id);
            self.allocator.free(entry.symbol);
            if (entry.error_message) |msg| {
                self.allocator.free(msg);
            }
        }
        self.order_history.deinit(self.allocator);

        // Clean up subscribed symbols
        for (self.subscribed_symbols.items) |s| {
            self.allocator.free(s);
        }
        self.subscribed_symbols.deinit(self.allocator);

        // Clean up request strings
        self.allocator.free(self.id);
        self.allocator.free(self.request.name);
        self.allocator.free(self.request.exchange);

        if (self.request.wallet) |w| {
            self.allocator.free(w);
        }
        if (self.request.private_key) |pk| {
            self.allocator.free(pk);
        }
        if (self.last_error) |err| {
            self.allocator.free(err);
        }

        self.allocator.destroy(self);
    }

    /// Start the live trading runner
    pub fn start(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.status == .running) {
            return error.AlreadyRunning;
        }

        self.status = .starting;
        self.start_time = std.time.timestamp();
        self.should_stop.store(false, .release);
        self.is_paused.store(false, .release);

        // Initialize engine
        try self.initEngine();

        // Start engine
        if (self.engine) |*engine| {
            try engine.start();
        }

        // Subscribe to symbols
        try self.subscribeSymbols();

        // Start background thread for tick processing
        self.thread = try std.Thread.spawn(.{}, runLoop, .{self});

        self.status = .running;
    }

    /// Stop the live trading runner
    pub fn stop(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.status != .running and self.status != .paused) {
            return error.NotRunning;
        }

        self.status = .stopping;
        self.should_stop.store(true, .release);

        // Stop engine
        if (self.engine) |*engine| {
            engine.stop();
        }

        // Wait for thread to finish
        if (self.thread) |thread| {
            self.mutex.unlock();
            thread.join();
            self.mutex.lock();
            self.thread = null;
        }

        self.status = .stopped;

        // Update stats
        if (self.engine) |engine| {
            const engine_stats = engine.getStats();
            self.stats.uptime_ms = engine_stats.uptime_ms;
            self.stats.ticks = engine_stats.ticks;
            self.stats.heartbeats_sent = engine_stats.heartbeats_sent;
            self.stats.reconnects = engine_stats.reconnects;
        }
    }

    /// Pause live trading (keeps connections but stops order execution)
    pub fn pause(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.status != .running) {
            return error.NotRunning;
        }

        self.is_paused.store(true, .release);
        self.status = .paused;
    }

    /// Resume live trading
    pub fn unpause(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.status != .paused) {
            return error.NotPaused;
        }

        self.is_paused.store(false, .release);
        self.status = .running;
    }

    /// Get current status
    pub fn getStatus(self: *Self) LiveStatus {
        return self.status;
    }

    /// Get current statistics
    pub fn getStats(self: *Self) LiveStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var stats = self.stats;

        // Update from engine if running
        if (self.engine) |engine| {
            const engine_stats = engine.getStats();
            stats.uptime_ms = engine_stats.uptime_ms;
            stats.ticks = engine_stats.ticks;
            stats.heartbeats_sent = engine_stats.heartbeats_sent;
            stats.reconnects = engine_stats.reconnects;
        }

        return stats;
    }

    /// Get connection state
    pub fn getConnectionState(self: *Self) ConnectionState {
        if (self.engine) |engine| {
            return engine.getConnectionState();
        }
        return .disconnected;
    }

    /// Submit an order
    pub fn submitOrder(self: *Self, request: OrderRequest) !OrderResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.status != .running) {
            return OrderResult{
                .success = false,
                .error_code = 5001,
                .error_message = "Live runner not running",
                .timestamp = Timestamp.now(),
            };
        }

        if (self.is_paused.load(.acquire)) {
            return OrderResult{
                .success = false,
                .error_code = 5002,
                .error_message = "Live runner is paused",
                .timestamp = Timestamp.now(),
            };
        }

        const engine = self.engine orelse return OrderResult{
            .success = false,
            .error_code = 5003,
            .error_message = "Engine not initialized",
            .timestamp = Timestamp.now(),
        };

        const result = try engine.submitOrder(request);

        // Record in history
        try self.recordOrder(request, result);

        // Update stats
        self.stats.orders_submitted += 1;
        if (result.success) {
            self.stats.orders_filled += 1;
            if (result.filled_quantity) |qty| {
                if (result.filled_price) |price| {
                    self.stats.total_volume += qty.toFloat() * price.toFloat();
                }
            }
        } else {
            self.stats.orders_rejected += 1;
        }

        return result;
    }

    /// Cancel an order
    pub fn cancelOrder(self: *Self, order_id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.engine) |*engine| {
            try engine.cancelOrder(order_id);
            self.stats.orders_cancelled += 1;
        }
    }

    /// Cancel all orders
    pub fn cancelAllOrders(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.engine) |*engine| {
            try engine.cancelAllOrders();
        }
    }

    /// Subscribe to a symbol
    pub fn subscribe(self: *Self, symbol: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Add to list if not already present
        for (self.subscribed_symbols.items) |s| {
            if (std.mem.eql(u8, s, symbol)) {
                return; // Already subscribed
            }
        }

        const symbol_copy = try self.allocator.dupe(u8, symbol);
        try self.subscribed_symbols.append(self.allocator, symbol_copy);

        // Subscribe in engine if running
        if (self.engine) |*engine| {
            try engine.subscribe(symbol);
        }
    }

    /// Unsubscribe from a symbol
    pub fn unsubscribe(self: *Self, symbol: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Remove from list
        for (self.subscribed_symbols.items, 0..) |s, i| {
            if (std.mem.eql(u8, s, symbol)) {
                self.allocator.free(s);
                _ = self.subscribed_symbols.orderedRemove(i);
                break;
            }
        }

        // Unsubscribe in engine if running
        if (self.engine) |*engine| {
            engine.unsubscribe(symbol);
        }
    }

    /// Get order history
    pub fn getOrderHistory(self: *Self, allocator: Allocator, limit: usize) ![]OrderHistoryEntry {
        self.mutex.lock();
        defer self.mutex.unlock();

        const count = @min(limit, self.order_history.items.len);
        const start_idx = self.order_history.items.len - count;

        var history = try allocator.alloc(OrderHistoryEntry, count);
        for (0..count) |i| {
            const entry = self.order_history.items[start_idx + i];
            history[i] = .{
                .timestamp = entry.timestamp,
                .order_id = try allocator.dupe(u8, entry.order_id),
                .symbol = try allocator.dupe(u8, entry.symbol),
                .side = entry.side,
                .order_type = entry.order_type,
                .quantity = entry.quantity,
                .price = entry.price,
                .status = entry.status,
                .filled_quantity = entry.filled_quantity,
                .error_message = if (entry.error_message) |msg| try allocator.dupe(u8, msg) else null,
            };
        }

        return history;
    }

    // ========================================================================
    // Private Methods
    // ========================================================================

    /// Initialize the live trading engine
    fn initEngine(self: *Self) !void {
        const config = self.request.toLiveConfig();
        self.engine = LiveTradingEngine.init(self.allocator, config);

        // Note: In production, we would set up:
        // - Data providers for the exchange
        // - Execution client for order routing
        // These require actual exchange connector setup which depends on
        // credentials and network configuration
    }

    /// Subscribe to all configured symbols
    fn subscribeSymbols(self: *Self) !void {
        if (self.engine) |*engine| {
            for (self.subscribed_symbols.items) |symbol| {
                // Subscribe to each symbol, continue on error
                engine.subscribe(symbol) catch continue;
            }
        }
    }

    /// Record an order in history
    fn recordOrder(self: *Self, request: OrderRequest, result: OrderResult) !void {
        const order_id = try self.allocator.dupe(u8, request.client_order_id);
        errdefer self.allocator.free(order_id);

        const symbol = try self.allocator.dupe(u8, request.symbol);
        errdefer self.allocator.free(symbol);

        var error_message: ?[]const u8 = null;
        if (!result.success) {
            if (result.error_message) |msg| {
                error_message = try self.allocator.dupe(u8, msg);
            }
        }

        try self.order_history.append(self.allocator, .{
            .timestamp = std.time.timestamp(),
            .order_id = order_id,
            .symbol = symbol,
            .side = if (request.side == .buy) "buy" else "sell",
            .order_type = switch (request.order_type) {
                .market => "market",
                .limit => "limit",
                .stop_limit => "stop_limit",
                .stop_market => "stop_market",
            },
            .quantity = request.quantity.toFloat(),
            .price = if (request.price) |p| p.toFloat() else null,
            .status = if (result.success) "filled" else "rejected",
            .filled_quantity = if (result.filled_quantity) |q| q.toFloat() else 0,
            .error_message = error_message,
        });

        // Trim history if too large
        while (self.order_history.items.len > self.max_history_size) {
            const removed = self.order_history.orderedRemove(0);
            self.allocator.free(removed.order_id);
            self.allocator.free(removed.symbol);
            if (removed.error_message) |msg| {
                self.allocator.free(msg);
            }
        }
    }

    /// Main run loop (executed in background thread)
    fn runLoop(self: *Self) void {
        while (!self.should_stop.load(.acquire)) {
            // Skip processing if paused
            if (!self.is_paused.load(.acquire)) {
                self.tick() catch |err| {
                    self.setError(@errorName(err));
                };
            }

            std.Thread.sleep(self.request.tick_interval_ms * std.time.ns_per_ms);
        }
    }

    /// Single tick of the live trading loop
    fn tick(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.engine) |*engine| {
            try engine.tick();
        }
    }

    /// Set error state
    fn setError(self: *Self, err_msg: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.last_error) |old| {
            self.allocator.free(old);
        }
        self.last_error = self.allocator.dupe(u8, err_msg) catch null;
        self.status = .error_state;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "LiveRequest parsePair" {
    const pair1 = LiveRequest.parsePair("BTC-USDT");
    try std.testing.expectEqualStrings("BTC", pair1.base);
    try std.testing.expectEqualStrings("USDT", pair1.quote);

    const pair2 = LiveRequest.parsePair("ETHUSDC");
    try std.testing.expectEqualStrings("ETH", pair2.base);
    try std.testing.expectEqualStrings("USDC", pair2.quote);
}

test "LiveRequest toLiveConfig" {
    const request = LiveRequest{
        .mode = .clock_driven,
        .heartbeat_interval_ms = 15000,
        .tick_interval_ms = 500,
    };
    const config = request.toLiveConfig();

    try std.testing.expectEqual(TradingMode.clock_driven, config.mode);
    try std.testing.expectEqual(@as(u64, 15000), config.heartbeat_interval_ms);
    try std.testing.expectEqual(@as(u64, 500), config.tick_interval_ms);
}

test "LiveStatus toString" {
    try std.testing.expectEqualStrings("stopped", LiveStatus.stopped.toString());
    try std.testing.expectEqualStrings("running", LiveStatus.running.toString());
    try std.testing.expectEqualStrings("paused", LiveStatus.paused.toString());
    try std.testing.expectEqualStrings("error", LiveStatus.error_state.toString());
}

test "LiveRunner init and deinit" {
    const allocator = std.testing.allocator;

    const request = LiveRequest{
        .name = "test_live",
        .mode = .event_driven,
        .exchange = "hyperliquid",
        .testnet = true,
    };

    const runner = try LiveRunner.init(allocator, "live_test_1", request);
    defer runner.deinit();

    try std.testing.expectEqualStrings("live_test_1", runner.id);
    try std.testing.expectEqual(LiveStatus.stopped, runner.status);
}

test "LiveStats default values" {
    const stats = LiveStats{};

    try std.testing.expectEqual(@as(u64, 0), stats.uptime_ms);
    try std.testing.expectEqual(@as(u64, 0), stats.ticks);
    try std.testing.expectEqual(@as(u64, 0), stats.orders_submitted);
    try std.testing.expectEqual(@as(f64, 100.0), stats.connection_uptime_pct);
}
