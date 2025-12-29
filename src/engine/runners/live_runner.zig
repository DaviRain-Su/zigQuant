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

// Import strategy types
const IStrategy = root.IStrategy;
const StrategyFactory = root.StrategyFactory;
const StrategyWrapper = root.StrategyWrapper;
const Signal = root.Signal;
const SignalType = root.SignalType;
const Candles = root.Candles;
const Candle = root.Candle;
const Account = root.Account;
const BacktestPosition = root.BacktestPosition;
const PositionSide = root.PositionSide;

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
const data_engine = @import("../../core/data_engine.zig");
const IDataProvider = data_engine.IDataProvider;
const DataMessage = data_engine.DataMessage;

// Import exchange types
const exchange_types = @import("../../exchange/types.zig");
const Side = exchange_types.Side;
const OrderType = exchange_types.OrderType;

// Import adapters for Hyperliquid
const adapters = @import("../../adapters/mod.zig");
const HyperliquidDataProvider = adapters.HyperliquidDataProvider;
const HyperliquidExecutionClient = adapters.HyperliquidExecutionClient;

// Import logger
const logger_mod = @import("../../core/logger.zig");
const Logger = logger_mod.Logger;
const LogWriter = logger_mod.LogWriter;
const LogRecord = logger_mod.LogRecord;

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

    // ========================================================================
    // Strategy Configuration (NEW)
    // ========================================================================

    /// Strategy name (e.g., "dual_ma", "rsi_mean_reversion", "grid", "hybrid_ai")
    /// If null, live trading runs without strategy execution (data streaming only)
    strategy: ?[]const u8 = null,

    /// Strategy parameters (JSON string)
    strategy_params: ?[]const u8 = null,

    /// Timeframe for candle aggregation (default: 1h)
    timeframe: []const u8 = "1h",

    /// Initial capital for position sizing (0 = use real balance from exchange)
    initial_capital: f64 = 0,

    /// Leverage multiplier (1-100, default: 1 = no leverage)
    leverage: u32 = 1,

    // ========================================================================
    // Grid Strategy Specific Parameters
    // ========================================================================

    /// Upper price bound for grid (required for grid strategy)
    upper_price: ?f64 = null,

    /// Lower price bound for grid (required for grid strategy)
    lower_price: ?f64 = null,

    /// Number of grid levels (default: 10)
    grid_count: u32 = 10,

    /// Order size per grid level
    order_size: f64 = 0.001,

    /// Take profit percentage per grid
    take_profit_pct: f64 = 0.5,

    /// Check if this is a grid strategy
    pub fn isGridStrategy(self: LiveRequest) bool {
        if (self.strategy) |strat| {
            return std.mem.eql(u8, strat, "grid");
        }
        return false;
    }

    /// Parse timeframe string to Timeframe enum
    pub fn parseTimeframe(self: LiveRequest) !Timeframe {
        return Timeframe.fromString(self.timeframe);
    }

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

/// Create a Logger that writes to std.log
fn createStdLogger(allocator: Allocator) Logger {
    const StdLogWriter = struct {
        fn write(_: *anyopaque, record: LogRecord) anyerror!void {
            // Write to std.log based on level
            switch (record.level) {
                .trace, .debug => std.log.debug("{s}", .{record.message}),
                .info => std.log.info("{s}", .{record.message}),
                .warn => std.log.warn("{s}", .{record.message}),
                .err, .fatal => std.log.err("{s}", .{record.message}),
            }
        }

        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = LogWriter{
        .ptr = @ptrFromInt(1), // Dummy non-null pointer
        .writeFn = StdLogWriter.write,
        .flushFn = StdLogWriter.flush,
        .closeFn = StdLogWriter.close,
    };

    return Logger.init(allocator, writer, .debug);
}

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

    // Core engine (heap-allocated to preserve internal pointers)
    engine: ?*LiveTradingEngine,

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

    // Exchange adapters (owned by runner)
    data_provider: ?*HyperliquidDataProvider,
    execution_client: ?*HyperliquidExecutionClient,

    // ========================================================================
    // Strategy Execution (NEW)
    // ========================================================================

    /// Strategy wrapper for lifecycle management
    strategy_wrapper: ?StrategyWrapper,

    /// Strategy interface for signal generation
    strategy: ?IStrategy,

    /// Candle buffer for indicator calculation
    candles: ?*Candles,

    /// Current trading pair
    pair: TradingPair,

    /// Current timeframe
    timeframe: Timeframe,

    /// Simulated account for paper trading / position tracking
    account: Account,

    /// Initial equity for PnL calculation
    initial_equity: Decimal,

    /// Current position size (positive = long, negative = short)
    current_position: f64,

    /// Entry price for current position
    entry_price: Decimal,

    /// Last known price
    last_price: Decimal,

    /// Previous price (for crossing detection)
    prev_price: Decimal,

    /// Real account balance from exchange (updated periodically)
    real_balance: Decimal,

    /// Real available balance from exchange
    real_available: Decimal,

    /// Last balance update timestamp
    last_balance_update: i64,

    /// Balance update interval (ms)
    balance_update_interval_ms: u64,

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

        // Copy strategy strings (NEW)
        var strategy_copy: ?[]const u8 = null;
        if (request.strategy) |s| {
            strategy_copy = try allocator.dupe(u8, s);
        }

        var strategy_params_copy: ?[]const u8 = null;
        if (request.strategy_params) |sp| {
            strategy_params_copy = try allocator.dupe(u8, sp);
        }

        const timeframe_copy = try allocator.dupe(u8, request.timeframe);
        errdefer allocator.free(timeframe_copy);

        // Parse pair from first symbol (if available)
        const pair: TradingPair = if (request.symbols.len > 0)
            LiveRequest.parsePair(request.symbols[0])
        else
            .{ .base = "BTC", .quote = "USDT" };

        // Parse timeframe
        const timeframe = request.parseTimeframe() catch .h1;

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
                // Strategy fields (NEW)
                .strategy = strategy_copy,
                .strategy_params = strategy_params_copy,
                .timeframe = timeframe_copy,
                .initial_capital = request.initial_capital,
                .upper_price = request.upper_price,
                .lower_price = request.lower_price,
                .grid_count = request.grid_count,
                .order_size = request.order_size,
                .take_profit_pct = request.take_profit_pct,
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
            .data_provider = null,
            .execution_client = null,
            // Strategy fields (NEW)
            .strategy_wrapper = null,
            .strategy = null,
            .candles = null,
            .pair = pair,
            .timeframe = timeframe,
            .account = Account.init(),
            // If initial_capital is 0, it will be set from real balance in fetchBalanceInternal
            .initial_equity = if (request.initial_capital > 0) Decimal.fromFloat(request.initial_capital) else Decimal.ZERO,
            .current_position = 0,
            .entry_price = Decimal.ZERO,
            .last_price = Decimal.ZERO,
            .prev_price = Decimal.ZERO,
            // Real balance fields (NEW)
            .real_balance = Decimal.ZERO,
            .real_available = Decimal.ZERO,
            .last_balance_update = 0,
            .balance_update_interval_ms = 10000, // Update every 10 seconds
        };

        // Initialize account with initial capital
        self.account.margin_summary.account_value = self.initial_equity;
        self.account.cross_margin_summary.account_value = self.initial_equity;

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

        // Clean up engine (use destroy() for heap-allocated engine)
        if (self.engine) |engine| {
            engine.destroy();
            self.engine = null;
        }

        // Clean up adapters (must be done after engine.deinit())
        if (self.execution_client) |exec| {
            exec.deinit();
            self.allocator.destroy(exec);
            self.execution_client = null;
        }
        if (self.data_provider) |provider| {
            provider.deinit();
            self.allocator.destroy(provider);
            self.data_provider = null;
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

        // Clean up strategy resources (NEW)
        if (self.strategy_wrapper) |*wrapper| {
            wrapper.deinit();
        }
        if (self.candles) |candle_buf| {
            candle_buf.deinit();
            self.allocator.destroy(candle_buf);
        }

        // Clean up request strings
        self.allocator.free(self.id);
        self.allocator.free(self.request.name);
        self.allocator.free(self.request.exchange);
        self.allocator.free(self.request.timeframe);

        if (self.request.wallet) |w| {
            self.allocator.free(w);
        }
        if (self.request.private_key) |pk| {
            self.allocator.free(pk);
        }
        if (self.request.strategy) |s| {
            self.allocator.free(s);
        }
        if (self.request.strategy_params) |sp| {
            self.allocator.free(sp);
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

        // Load strategy if specified (NEW)
        if (self.request.strategy != null) {
            try self.loadStrategy();
            std.log.info("LiveRunner: Strategy loaded: {s}", .{self.request.strategy.?});
        }

        // Initialize candles buffer (NEW)
        try self.initCandles();

        // Start engine
        if (self.engine) |engine| {
            try engine.start();
        }

        // Subscribe to symbols (non-fatal if no provider)
        self.subscribeSymbols() catch |err| {
            // Log but continue - we'll run in "simulation mode" without real data
            std.log.warn("LiveRunner: Failed to subscribe to symbols: {} (running in simulation mode)", .{err});
        };

        // Fetch initial balance from exchange (non-fatal if fails)
        // Note: We call the internal fetch directly since we already hold the mutex
        self.fetchBalanceInternal() catch |err| {
            std.log.warn("LiveRunner: Failed to fetch initial balance: {} (using initial_capital)", .{err});
        };

        // Start background thread for tick processing
        self.thread = try std.Thread.spawn(.{}, runLoop, .{self});

        self.status = .running;

        // Log successful start
        const strategy_name = self.request.strategy orelse "none";
        std.log.info("LiveRunner started: id={s}, name={s}, exchange={s}, testnet={}, symbols={d}, strategy={s}", .{
            self.id,
            self.request.name,
            self.request.exchange,
            self.request.testnet,
            self.subscribed_symbols.items.len,
            strategy_name,
        });
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
        if (self.engine) |engine| {
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

        if (self.engine) |engine| {
            try engine.cancelOrder(order_id);
            self.stats.orders_cancelled += 1;
        }
    }

    /// Cancel all orders
    pub fn cancelAllOrders(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.engine) |engine| {
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
        if (self.engine) |engine| {
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
        if (self.engine) |engine| {
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

    /// Get real balance info
    pub const BalanceInfo = struct {
        total: f64,
        available: f64,
        last_updated: i64,
        is_real: bool, // true if from exchange, false if initial/default
    };

    pub fn getBalance(self: *Self) BalanceInfo {
        self.mutex.lock();
        defer self.mutex.unlock();

        // If we have real balance data
        if (self.last_balance_update > 0) {
            return .{
                .total = self.real_balance.toFloat(),
                .available = self.real_available.toFloat(),
                .last_updated = self.last_balance_update,
                .is_real = true,
            };
        }

        // Return initial capital as fallback
        return .{
            .total = self.initial_equity.toFloat(),
            .available = self.initial_equity.toFloat(),
            .last_updated = 0,
            .is_real = false,
        };
    }

    /// Force immediate balance update (for API calls)
    pub fn refreshBalance(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.execution_client) |exec_client| {
            const balance = try exec_client.asClient().getBalance();

            self.real_balance = balance.total;
            self.real_available = balance.available;
            self.last_balance_update = std.time.milliTimestamp();

            // Update account state
            self.account.margin_summary.account_value = balance.total;
            self.account.cross_margin_summary.account_value = balance.total;
        }
    }

    // ========================================================================
    // Private Methods
    // ========================================================================

    /// Initialize the live trading engine
    fn initEngine(self: *Self) !void {
        const config = self.request.toLiveConfig();

        // Use create() which allocates on heap and initializes in-place
        // This preserves internal pointers (components point to sibling fields like &self.bus)
        self.engine = try LiveTradingEngine.create(self.allocator, config);

        // Check if we have exchange credentials for Hyperliquid
        if (std.mem.eql(u8, self.request.exchange, "hyperliquid")) {
            try self.initHyperliquidAdapters();
        }
    }

    /// Initialize Hyperliquid data provider and execution client
    fn initHyperliquidAdapters(self: *Self) !void {
        // Create a simple logger that writes to std.log
        const logger = createStdLogger(self.allocator);

        // Determine host based on testnet setting
        const host: []const u8 = if (self.request.testnet)
            "api.hyperliquid-testnet.xyz"
        else
            "api.hyperliquid.xyz";

        // Create data provider
        const data_provider = try self.allocator.create(HyperliquidDataProvider);
        errdefer self.allocator.destroy(data_provider);

        data_provider.* = HyperliquidDataProvider.init(self.allocator, .{
            .host = host,
            .port = 443,
            .path = "/ws",
            .use_tls = true,
        }, logger);

        self.data_provider = data_provider;

        // Add to engine
        if (self.engine) |engine| {
            try engine.setDataProvider(data_provider.asProvider());
        }

        std.log.info("LiveRunner: HyperliquidDataProvider initialized (testnet={})", .{self.request.testnet});

        // Create execution client if we have credentials
        if (self.request.private_key) |pk_hex| {
            // Parse hex private key to [32]u8
            const private_key = parseHexPrivateKey(pk_hex) catch |err| {
                std.log.err("LiveRunner: Failed to parse private key: {}", .{err});
                return err;
            };

            // Use create() to properly allocate and initialize on heap
            // This avoids dangling pointer issues with internal API references
            const execution_client = try HyperliquidExecutionClient.create(self.allocator, .{
                .testnet = self.request.testnet,
                .private_key = private_key,
            }, logger, null);

            self.execution_client = execution_client;

            // Add to engine
            if (self.engine) |engine| {
                engine.setExecutionClient(execution_client.asClient());
            }

            std.log.info("LiveRunner: HyperliquidExecutionClient initialized", .{});

            // Set leverage for each subscribed symbol
            if (self.request.leverage > 1) {
                for (self.subscribed_symbols.items) |symbol| {
                    execution_client.setLeverage(symbol, self.request.leverage, true) catch |err| {
                        std.log.warn("LiveRunner: Failed to set leverage for {s}: {}", .{ symbol, err });
                    };
                }
                std.log.info("LiveRunner: Leverage set to {d}x for all symbols", .{self.request.leverage});
            }
        } else {
            std.log.warn("LiveRunner: No private key provided, execution client not initialized", .{});
        }
    }

    /// Parse hex string to [32]u8 private key
    fn parseHexPrivateKey(hex_str: []const u8) ![32]u8 {
        // Remove "0x" prefix if present
        const hex = if (std.mem.startsWith(u8, hex_str, "0x"))
            hex_str[2..]
        else
            hex_str;

        if (hex.len != 64) {
            return error.InvalidPrivateKeyLength;
        }

        var result: [32]u8 = undefined;
        for (0..32) |i| {
            const high = std.fmt.charToDigit(hex[i * 2], 16) catch return error.InvalidHexCharacter;
            const low = std.fmt.charToDigit(hex[i * 2 + 1], 16) catch return error.InvalidHexCharacter;
            result[i] = (high << 4) | low;
        }

        return result;
    }

    /// Subscribe to all configured symbols
    fn subscribeSymbols(self: *Self) !void {
        if (self.engine) |engine| {
            for (self.subscribed_symbols.items) |symbol| {
                // Subscribe to each symbol, continue on error
                engine.subscribe(symbol) catch continue;
            }
        }
    }

    /// Load strategy from factory (NEW)
    fn loadStrategy(self: *Self) !void {
        const strategy_name = self.request.strategy orelse return;

        var factory = StrategyFactory.init(self.allocator);

        // Build config JSON based on strategy type
        var json_buf: [4096]u8 = undefined;
        var json: []const u8 = undefined;

        if (self.request.isGridStrategy()) {
            // Build Grid-specific config JSON
            const upper = self.request.upper_price orelse return error.MissingGridPrices;
            const lower = self.request.lower_price orelse return error.MissingGridPrices;

            json = std.fmt.bufPrint(&json_buf,
                \\{{
                \\  "strategy": "grid",
                \\  "pair": {{ "base": "{s}", "quote": "{s}" }},
                \\  "parameters": {{
                \\    "upper_price": {d},
                \\    "lower_price": {d},
                \\    "grid_count": {d},
                \\    "order_size": {d},
                \\    "take_profit_pct": {d},
                \\    "enable_long": true,
                \\    "enable_short": false,
                \\    "max_position": 1.0
                \\  }}
                \\}}
            , .{
                self.pair.base,
                self.pair.quote,
                upper,
                lower,
                self.request.grid_count,
                self.request.order_size,
                self.request.take_profit_pct,
            }) catch return error.ConfigBuildFailed;
        } else {
            // Build standard strategy config JSON
            json = std.fmt.bufPrint(&json_buf,
                \\{{
                \\  "strategy": "{s}",
                \\  "pair": {{ "base": "{s}", "quote": "{s}" }},
                \\  "parameters": {s}
                \\}}
            , .{
                strategy_name,
                self.pair.base,
                self.pair.quote,
                self.request.strategy_params orelse "{}",
            }) catch return error.ConfigBuildFailed;
        }

        std.log.info("LiveRunner: Creating strategy '{s}' with config: {s}", .{ strategy_name, json });

        const wrapper = factory.create(strategy_name, json) catch |err| {
            std.log.err("LiveRunner: Failed to create strategy '{s}': {}", .{ strategy_name, err });
            // Return more specific errors
            return switch (err) {
                error.UpperPriceMustBeGreaterThanLower => error.InvalidGridPrices,
                error.InvalidConfig => error.InvalidStrategyConfig,
                error.MissingParameter => error.MissingStrategyParam,
                error.InvalidParameter => error.InvalidStrategyParam,
                error.UnknownStrategy => error.StrategyNotFound,
                else => error.StrategyCreationFailed,
            };
        };

        self.strategy_wrapper = wrapper;
        self.strategy = wrapper.interface;

        std.log.info("LiveRunner: Strategy '{s}' created successfully", .{strategy_name});
    }

    /// Initialize candles buffer (NEW)
    fn initCandles(self: *Self) !void {
        const candle_buf = try self.allocator.create(Candles);
        candle_buf.* = Candles.init(self.allocator, self.pair, self.timeframe);
        self.candles = candle_buf;

        // Try to load historical candles from exchange
        // This is non-fatal - strategies can still work with real-time data
        self.loadHistoricalCandles() catch |err| {
            std.log.warn("LiveRunner: Failed to load historical candles: {} (will use real-time data)", .{err});
        };
    }

    /// Load historical candles from exchange REST API
    /// This provides strategies with enough historical data to calculate indicators
    fn loadHistoricalCandles(self: *Self) !void {
        // We need the execution client for REST API access
        const exec_client = self.execution_client orelse return error.NoExecutionClient;

        // Get the symbol to fetch candles for
        if (self.subscribed_symbols.items.len == 0) {
            return error.NoSymbols;
        }
        const symbol = self.subscribed_symbols.items[0];

        // Map timeframe to Hyperliquid interval string
        const interval = self.mapTimeframeToInterval(self.timeframe);

        // Calculate time range: fetch last 100 candles
        const now = std.time.milliTimestamp();
        const candle_duration_ms = self.timeframe.toSeconds() * 1000;
        const num_candles: u64 = 100; // Fetch 100 candles for indicator calculation
        const start_time: u64 = @intCast(@max(0, now - @as(i64, @intCast(candle_duration_ms * num_candles))));
        const end_time: u64 = @intCast(now);

        std.log.info("LiveRunner: Fetching historical candles for {s}, interval={s}, count={d}", .{
            symbol,
            interval,
            num_candles,
        });

        // Fetch candles from API
        var parsed = try exec_client.info_api.getCandleSnapshot(symbol, interval, start_time, end_time);
        defer parsed.deinit();

        const candle_data = parsed.value;
        if (candle_data.len == 0) {
            std.log.warn("LiveRunner: No historical candles returned from API", .{});
            return error.NoHistoricalData;
        }

        std.log.info("LiveRunner: Received {} historical candles from API", .{candle_data.len});

        // Allocate candles array
        const candles = try self.allocator.alloc(Candle, candle_data.len);
        errdefer self.allocator.free(candles);

        // Convert API candle data to our Candle format
        for (candle_data, 0..) |api_candle, i| {
            candles[i] = .{
                .timestamp = Timestamp.fromMillis(@intCast(api_candle.t)), // Open time
                .open = Decimal.fromString(api_candle.o) catch Decimal.ZERO,
                .high = Decimal.fromString(api_candle.h) catch Decimal.ZERO,
                .low = Decimal.fromString(api_candle.l) catch Decimal.ZERO,
                .close = Decimal.fromString(api_candle.c) catch Decimal.ZERO,
                .volume = Decimal.fromString(api_candle.v) catch Decimal.ZERO,
            };
        }

        // Update candles buffer
        if (self.candles) |candle_buf| {
            // Free old candles if any
            if (candle_buf.candles.len > 0) {
                self.allocator.free(candle_buf.candles);
            }
            candle_buf.candles = candles;

            // Update last_price from most recent candle
            if (candles.len > 0) {
                self.last_price = candles[candles.len - 1].close;
                self.prev_price = if (candles.len > 1) candles[candles.len - 2].close else self.last_price;
            }
        }

        std.log.info("LiveRunner: Loaded {} historical candles, last_price={d:.2}", .{
            candles.len,
            self.last_price.toFloat(),
        });
    }

    /// Map Timeframe enum to Hyperliquid interval string
    fn mapTimeframeToInterval(self: *Self, timeframe: Timeframe) []const u8 {
        _ = self;
        // Hyperliquid supports: "1m", "3m", "5m", "15m", "30m", "1h", "2h", "4h", "8h", "12h", "1d", "3d", "1w", "1M"
        // Note: 1s and 6h are not supported by Hyperliquid, we fall back to closest alternative
        return switch (timeframe) {
            .s1 => "1m", // Hyperliquid doesn't support 1s, use 1m
            .m1 => "1m",
            .m3 => "3m",
            .m5 => "5m",
            .m15 => "15m",
            .m30 => "30m",
            .h1 => "1h",
            .h2 => "2h",
            .h4 => "4h",
            .h6 => "4h", // Hyperliquid doesn't support 6h, use 4h
            .h8 => "8h",
            .h12 => "12h",
            .d1 => "1d",
            .d3 => "3d",
            .w1 => "1w",
            .M1 => "1M",
        };
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
            },
            .quantity = request.quantity.toFloat(),
            .price = if (request.price) |p| p.toFloat() else null,
            .status = if (result.success) "filled" else "rejected",
            .filled_quantity = result.filled_quantity.toFloat(),
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

        // Process engine tick (data engine, heartbeats, etc.)
        if (self.engine) |engine| {
            try engine.tick();
        }

        // Update market data from cache
        try self.updateMarketData();

        // Update balance periodically
        self.updateBalanceIfNeeded();

        // Execute strategy if configured
        if (self.strategy) |strategy| {
            try self.executeStrategy(strategy);
        }
    }

    /// Update balance from exchange if enough time has passed
    fn updateBalanceIfNeeded(self: *Self) void {
        const now = std.time.milliTimestamp();
        const elapsed = now - self.last_balance_update;

        // Only update if interval has passed
        if (elapsed < @as(i64, @intCast(self.balance_update_interval_ms))) {
            return;
        }

        // Update balance from execution client
        if (self.execution_client) |exec_client| {
            const balance = exec_client.asClient().getBalance() catch {
                // Failed to get balance, keep using last known values
                return;
            };

            self.real_balance = balance.total;
            self.real_available = balance.available;
            self.last_balance_update = now;

            // Also update account state
            self.account.margin_summary.account_value = balance.total;
            self.account.cross_margin_summary.account_value = balance.total;

            std.log.debug("LiveRunner: Balance updated - total={d:.4}, available={d:.4}", .{
                balance.total.toFloat(),
                balance.available.toFloat(),
            });
        }
    }

    /// Internal balance fetch (caller must hold mutex)
    fn fetchBalanceInternal(self: *Self) !void {
        if (self.execution_client) |exec_client| {
            const balance = try exec_client.asClient().getBalance();

            self.real_balance = balance.total;
            self.real_available = balance.available;
            self.last_balance_update = std.time.milliTimestamp();

            // Update account state
            self.account.margin_summary.account_value = balance.total;
            self.account.cross_margin_summary.account_value = balance.total;

            // If initial_capital was 0 (use real balance), update initial_equity
            // This ensures position sizing uses real account balance
            if (self.request.initial_capital == 0 or self.initial_equity.isZero()) {
                self.initial_equity = balance.total;
                std.log.info("LiveRunner: Using real balance as initial equity: {d:.4}", .{
                    balance.total.toFloat(),
                });
            }

            std.log.info("LiveRunner: Initial balance fetched - total={d:.4}, available={d:.4}, leverage={}x", .{
                balance.total.toFloat(),
                balance.available.toFloat(),
                self.request.leverage,
            });
        } else {
            return error.NoExecutionClient;
        }
    }

    /// Update market data from Cache (populated by DataEngine from WebSocket)
    fn updateMarketData(self: *Self) !void {
        // Get the target symbol
        const target_symbol = if (self.subscribed_symbols.items.len > 0)
            self.subscribed_symbols.items[0]
        else
            "BTC";

        // Get price from Cache (DataEngine processes WebSocket messages and updates Cache)
        if (self.engine) |engine| {
            const cache = engine.getCache();

            // Try to get quote from cache
            if (cache.getQuote(target_symbol)) |quote| {
                const mid = quote.midPrice();
                if (!mid.isZero()) {
                    self.last_price = mid;
                }
            }
        }
    }

    /// Execute strategy and generate signals (NEW)
    fn executeStrategy(self: *Self, strategy: IStrategy) !void {
        var candle_buf = self.candles orelse return;

        // Skip if we don't have a price yet
        if (self.last_price.isZero()) {
            return;
        }

        // Case 1: No historical candles loaded - create synthetic candles as fallback
        // This allows strategies to still work (with limitations) when historical data is unavailable
        if (candle_buf.len() < 2) {
            const now = Timestamp.now();
            const price = self.last_price;

            // Allocate array for 2 synthetic candles
            const synthetic_candles = try self.allocator.alloc(Candle, 2);
            synthetic_candles[0] = .{
                .timestamp = Timestamp.fromMillis(now.millis - 1000), // 1 second ago
                .open = if (!self.prev_price.isZero()) self.prev_price else price,
                .high = if (!self.prev_price.isZero()) self.prev_price else price,
                .low = if (!self.prev_price.isZero()) self.prev_price else price,
                .close = if (!self.prev_price.isZero()) self.prev_price else price,
                .volume = Decimal.ZERO,
            };
            synthetic_candles[1] = .{
                .timestamp = now,
                .open = if (!self.prev_price.isZero()) self.prev_price else price,
                .high = price,
                .low = price,
                .close = price,
                .volume = Decimal.ZERO,
            };

            // Replace the empty candles array with our synthetic one
            candle_buf.candles = synthetic_candles;

            std.log.debug("LiveRunner: Created synthetic candles (price={d:.2})", .{
                price.toFloat(),
            });
        }

        // Case 2: Have historical candles - update the last candle with real-time price
        if (candle_buf.len() >= 2) {
            const last_idx = candle_buf.len() - 1;

            // Update the last candle's close price with real-time data
            // This gives strategies the most current price information
            const candle = &candle_buf.candles[last_idx];
            candle.close = self.last_price;

            // Update high/low if price breaks them
            if (self.last_price.cmp(candle.high) == .gt) {
                candle.high = self.last_price;
            }
            if (self.last_price.cmp(candle.low) == .lt) {
                candle.low = self.last_price;
            }
        }

        // Track previous price for crossing detection
        self.prev_price = self.last_price;

        // Populate indicators
        strategy.populateIndicators(candle_buf) catch |err| {
            std.log.warn("LiveRunner: Failed to populate indicators: {}", .{err});
            return;
        };

        const current_index = candle_buf.len() - 1;

        // Check for entry or exit signals based on current position
        if (self.current_position == 0) {
            // No position - check for entry signal
            if (strategy.generateEntrySignal(candle_buf, current_index) catch null) |signal| {
                try self.processSignal(signal);
            }
        } else {
            // Have position - check for exit signal
            const position = BacktestPosition{
                .pair = self.pair,
                .entry_price = self.entry_price,
                .size = Decimal.fromFloat(@abs(self.current_position)),
                .side = if (self.current_position > 0) PositionSide.long else PositionSide.short,
                .entry_time = Timestamp.now(),
                .unrealized_pnl = Decimal.ZERO,
            };

            if (strategy.generateExitSignal(candle_buf, position) catch null) |signal| {
                try self.processSignal(signal);
            }
        }
    }

    /// Process a trading signal and execute orders (NEW)
    fn processSignal(self: *Self, signal: Signal) !void {
        _ = std.time.timestamp(); // For future signal timestamping
        self.stats.orders_submitted += 1;

        // Determine signal type and action
        const is_entry = signal.type == .entry_long or signal.type == .entry_short;
        const is_long = signal.type == .entry_long or signal.type == .exit_short;

        // Use order_size from config (for grid strategy) or calculate based on account
        const position_size = if (self.request.order_size > 0)
            Decimal.fromFloat(self.request.order_size)
        else blk: {
            // Fallback: 2% risk per trade
            const account_value = self.account.getAccountValue();
            const risk_per_trade = account_value.mul(Decimal.fromFloat(0.02));
            break :blk if (!self.last_price.isZero())
                risk_per_trade.div(self.last_price) catch Decimal.fromFloat(0.001)
            else
                Decimal.fromFloat(0.001);
        };

        // Log signal
        const signal_type_str: []const u8 = switch (signal.type) {
            .entry_long => "ENTRY_LONG",
            .entry_short => "ENTRY_SHORT",
            .exit_long => "EXIT_LONG",
            .exit_short => "EXIT_SHORT",
            .hold => "HOLD",
        };

        std.log.info("LiveRunner: Signal generated - type={s}, price={d:.2}, size={d:.6}", .{
            signal_type_str,
            signal.price.toFloat(),
            position_size.toFloat(),
        });

        // Skip hold signals
        if (signal.type == .hold) return;

        // Execute via ExecutionClient if available
        if (self.execution_client) |exec_client| {
            const symbol = if (self.subscribed_symbols.items.len > 0)
                self.subscribed_symbols.items[0]
            else
                "BTC";

            const order_request = OrderRequest{
                .symbol = symbol,
                .side = if (is_long) Side.buy else Side.sell,
                .order_type = .market,
                .quantity = position_size,
                .price = null, // Market order
                .client_order_id = "live_signal",
                .reduce_only = !is_entry,
            };

            const result = exec_client.asClient().submitOrder(order_request) catch |err| {
                std.log.err("LiveRunner: Order submission failed: {}", .{err});
                self.stats.orders_rejected += 1;
                return;
            };

            if (result.success) {
                self.stats.orders_filled += 1;

                // Update position state
                switch (signal.type) {
                    .entry_long => {
                        self.current_position = position_size.toFloat();
                        self.entry_price = self.last_price;
                    },
                    .entry_short => {
                        self.current_position = -position_size.toFloat();
                        self.entry_price = self.last_price;
                    },
                    .exit_long, .exit_short => {
                        // Calculate PnL
                        const exit_price = self.last_price;
                        const pnl = if (self.current_position > 0)
                            exit_price.sub(self.entry_price).mul(Decimal.fromFloat(self.current_position))
                        else
                            self.entry_price.sub(exit_price).mul(Decimal.fromFloat(-self.current_position));

                        self.stats.realized_pnl += pnl.toFloat();
                        self.current_position = 0;
                        self.entry_price = Decimal.ZERO;

                        if (pnl.toFloat() > 0) {
                            self.stats.orders_filled += 1;
                        }
                    },
                    .hold => {},
                }

                // Update volume
                if (result.avg_fill_price) |price| {
                    self.stats.total_volume += result.filled_quantity.toFloat() * price.toFloat();
                }

                // Record order
                try self.recordOrder(order_request, result);

                std.log.info("LiveRunner: Order executed - order_id={?s}, filled_qty={d:.6}", .{
                    result.order_id,
                    result.filled_quantity.toFloat(),
                });
            } else {
                self.stats.orders_rejected += 1;
                std.log.warn("LiveRunner: Order rejected - error={?s}", .{result.error_message});
            }
        } else {
            // Paper trading mode - simulate execution
            switch (signal.type) {
                .entry_long => {
                    self.current_position = position_size.toFloat();
                    self.entry_price = self.last_price;
                    std.log.info("LiveRunner: [PAPER] Long entry at {d:.2}", .{self.last_price.toFloat()});
                },
                .entry_short => {
                    self.current_position = -position_size.toFloat();
                    self.entry_price = self.last_price;
                    std.log.info("LiveRunner: [PAPER] Short entry at {d:.2}", .{self.last_price.toFloat()});
                },
                .exit_long, .exit_short => {
                    const exit_price = self.last_price;
                    const pnl = if (self.current_position > 0)
                        exit_price.sub(self.entry_price).mul(Decimal.fromFloat(self.current_position))
                    else
                        self.entry_price.sub(exit_price).mul(Decimal.fromFloat(-self.current_position));

                    self.stats.realized_pnl += pnl.toFloat();
                    std.log.info("LiveRunner: [PAPER] Exit at {d:.2}, PnL: {d:.4}", .{
                        exit_price.toFloat(),
                        pnl.toFloat(),
                    });

                    self.current_position = 0;
                    self.entry_price = Decimal.ZERO;
                },
                .hold => {},
            }
            self.stats.orders_filled += 1;
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
