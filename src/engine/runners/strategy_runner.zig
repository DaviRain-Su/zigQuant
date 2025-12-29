//! Strategy Runner
//!
//! Wraps strategy execution for lifecycle management via API.
//! Provides live/paper strategy execution with real-time monitoring,
//! parameter hot-reload, and controlled start/stop.
//!
//! Features:
//! - Strategy lifecycle management (start/stop)
//! - Live and paper trading modes
//! - Real-time statistics and monitoring
//! - Parameter hot-reload support
//! - Signal history tracking
//! - Integration with risk management

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import zigQuant types
const root = @import("../../root.zig");
const Decimal = root.Decimal;
const TradingPair = root.TradingPair;
const Timeframe = root.Timeframe;
const Timestamp = root.Timestamp;
const Logger = root.Logger;
const LogWriter = root.LogWriter;
const LogRecord = root.LogRecord;
const IStrategy = root.IStrategy;
const StrategyFactory = root.StrategyFactory;
const StrategyWrapper = root.StrategyWrapper;
const Signal = root.Signal;
const SignalType = root.SignalType;
const Candles = root.Candles;
const Candle = root.Candle;
const HyperliquidConnector = root.HyperliquidConnector;
const ExchangeConfig = root.ExchangeConfig;
const RiskEngine = root.RiskEngine;
const AlertManager = root.AlertManager;
const Account = root.Account;

/// Strategy request configuration (from API)
pub const StrategyRequest = struct {
    /// Strategy name (e.g., "dual_ma", "rsi_mean_reversion", "grid")
    strategy: []const u8,

    /// Strategy parameters (JSON string)
    params: ?[]const u8 = null,

    /// Trading pair
    symbol: []const u8,

    /// Timeframe (1m, 5m, 15m, 1h, 4h, 1d, etc.)
    timeframe: []const u8 = "1h",

    /// Trading mode
    mode: TradingMode = .paper,

    /// Initial capital
    initial_capital: f64 = 10000,

    /// Check interval in milliseconds
    check_interval_ms: u64 = 5000,

    /// Exchange credentials (for live/testnet)
    wallet: ?[]const u8 = null,
    private_key: ?[]const u8 = null,

    /// Risk management settings
    risk_enabled: bool = true,
    max_daily_loss_pct: f64 = 0.02,
    max_position_size: f64 = 1.0,

    // ========================================================================
    // Grid Strategy Specific Parameters (used when strategy = "grid")
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
    pub fn isGridStrategy(self: StrategyRequest) bool {
        return std.mem.eql(u8, self.strategy, "grid");
    }

    /// Validate grid parameters
    pub fn validateGridParams(self: StrategyRequest) !void {
        if (!self.isGridStrategy()) return;

        if (self.upper_price == null or self.lower_price == null) {
            return error.MissingGridPrices;
        }
        if (self.upper_price.? <= self.lower_price.?) {
            return error.InvalidPriceRange;
        }
        if (self.grid_count < 2 or self.grid_count > 100) {
            return error.InvalidGridCount;
        }
    }

    /// Parse timeframe string to Timeframe enum
    pub fn parseTimeframe(self: StrategyRequest) !Timeframe {
        return Timeframe.fromString(self.timeframe);
    }

    /// Parse symbol to TradingPair
    pub fn parsePair(self: StrategyRequest) TradingPair {
        // Handle formats like "BTCUSDT", "BTC-USDT", "BTC/USDT"
        var base: []const u8 = "";
        var quote: []const u8 = "";

        if (std.mem.indexOf(u8, self.symbol, "-")) |idx| {
            base = self.symbol[0..idx];
            quote = self.symbol[idx + 1 ..];
        } else if (std.mem.indexOf(u8, self.symbol, "/")) |idx| {
            base = self.symbol[0..idx];
            quote = self.symbol[idx + 1 ..];
        } else {
            // Assume format like "BTCUSDT" - try common quote currencies
            const quote_currencies = [_][]const u8{ "USDT", "USDC", "USD", "BTC", "ETH" };
            for (quote_currencies) |q| {
                if (std.mem.endsWith(u8, self.symbol, q)) {
                    base = self.symbol[0 .. self.symbol.len - q.len];
                    quote = q;
                    break;
                }
            }
        }

        if (base.len == 0) {
            base = self.symbol;
            quote = "USDT";
        }

        return .{ .base = base, .quote = quote };
    }
};

/// Trading mode
pub const TradingMode = enum {
    paper,
    testnet,
    mainnet,

    pub fn toString(self: TradingMode) []const u8 {
        return switch (self) {
            .paper => "paper",
            .testnet => "testnet",
            .mainnet => "mainnet",
        };
    }

    pub fn fromString(str: []const u8) TradingMode {
        if (std.mem.eql(u8, str, "testnet")) return .testnet;
        if (std.mem.eql(u8, str, "mainnet")) return .mainnet;
        return .paper;
    }
};

/// Strategy runner status
pub const StrategyStatus = enum {
    stopped,
    starting,
    running,
    paused,
    stopping,
    error_state,

    pub fn toString(self: StrategyStatus) []const u8 {
        return switch (self) {
            .stopped => "stopped",
            .starting => "starting",
            .running => "running",
            .paused => "paused",
            .stopping => "stopping",
            .error_state => "error",
        };
    }
};

/// Signal history entry
pub const SignalHistoryEntry = struct {
    timestamp: i64,
    signal_type: []const u8,
    price: f64,
    size: f64,
    reason: ?[]const u8,
};

/// Strategy statistics
pub const StrategyStats = struct {
    total_signals: u32 = 0,
    total_trades: u32 = 0,
    winning_trades: u32 = 0,
    losing_trades: u32 = 0,
    current_position: f64 = 0,
    realized_pnl: f64 = 0,
    unrealized_pnl: f64 = 0,
    max_drawdown: f64 = 0,
    win_rate: f64 = 0,
    sharpe_ratio: f64 = 0,
    last_signal_time: i64 = 0,
    last_price: f64 = 0,
    uptime_seconds: i64 = 0,
    signals_rejected_by_risk: u32 = 0,

    pub fn calculateWinRate(self: *StrategyStats) void {
        if (self.total_trades > 0) {
            self.win_rate = @as(f64, @floatFromInt(self.winning_trades)) / @as(f64, @floatFromInt(self.total_trades)) * 100.0;
        }
    }
};

/// Strategy Runner - manages a single strategy execution
pub const StrategyRunner = struct {
    allocator: Allocator,
    id: []const u8,
    request: StrategyRequest,
    status: StrategyStatus,
    stats: StrategyStats,
    start_time: i64,
    last_error: ?[]const u8,

    // Strategy instance
    strategy_wrapper: ?StrategyWrapper,
    strategy: ?IStrategy,

    // Market data
    candles: ?*Candles,
    last_price: Decimal,
    pair: TradingPair,
    timeframe: Timeframe,

    // Account state
    account: Account,
    initial_equity: Decimal,

    // Signal history
    signal_history: std.ArrayList(SignalHistoryEntry),
    max_history_size: usize,

    // Exchange connection (for live/testnet)
    connector: ?*HyperliquidConnector,

    // Risk management
    risk_engine: ?*RiskEngine,
    alert_manager: ?*AlertManager,

    // Thread management
    thread: ?std.Thread,
    should_stop: std.atomic.Value(bool),
    is_paused: std.atomic.Value(bool),
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Create a new strategy runner
    pub fn init(allocator: Allocator, id: []const u8, request: StrategyRequest) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Copy ID
        const id_copy = try allocator.dupe(u8, id);
        errdefer allocator.free(id_copy);

        // Copy request strings
        const strategy_copy = try allocator.dupe(u8, request.strategy);
        errdefer allocator.free(strategy_copy);

        const symbol_copy = try allocator.dupe(u8, request.symbol);
        errdefer allocator.free(symbol_copy);

        const timeframe_copy = try allocator.dupe(u8, request.timeframe);
        errdefer allocator.free(timeframe_copy);

        var params_copy: ?[]const u8 = null;
        if (request.params) |p| {
            params_copy = try allocator.dupe(u8, p);
        }

        var wallet_copy: ?[]const u8 = null;
        if (request.wallet) |w| {
            wallet_copy = try allocator.dupe(u8, w);
        }

        var private_key_copy: ?[]const u8 = null;
        if (request.private_key) |pk| {
            private_key_copy = try allocator.dupe(u8, pk);
        }

        const pair = request.parsePair();
        const timeframe = request.parseTimeframe() catch .h1;

        self.* = .{
            .allocator = allocator,
            .id = id_copy,
            .request = .{
                .strategy = strategy_copy,
                .params = params_copy,
                .symbol = symbol_copy,
                .timeframe = timeframe_copy,
                .mode = request.mode,
                .initial_capital = request.initial_capital,
                .check_interval_ms = request.check_interval_ms,
                .wallet = wallet_copy,
                .private_key = private_key_copy,
                .risk_enabled = request.risk_enabled,
                .max_daily_loss_pct = request.max_daily_loss_pct,
                .max_position_size = request.max_position_size,
                // Grid-specific parameters
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
            .strategy_wrapper = null,
            .strategy = null,
            .candles = null,
            .last_price = Decimal.ZERO,
            .pair = pair,
            .timeframe = timeframe,
            .account = Account.init(),
            .initial_equity = Decimal.fromFloat(request.initial_capital),
            .signal_history = std.ArrayList(SignalHistoryEntry){},
            .max_history_size = 1000,
            .connector = null,
            .risk_engine = null,
            .alert_manager = null,
            .thread = null,
            .should_stop = std.atomic.Value(bool).init(false),
            .is_paused = std.atomic.Value(bool).init(false),
            .mutex = .{},
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

        // Clean up strategy wrapper
        if (self.strategy_wrapper) |*wrapper| {
            wrapper.deinit();
        }

        // Clean up candles
        if (self.candles) |candles| {
            candles.deinit();
            self.allocator.destroy(candles);
        }

        // Clean up signal history
        for (self.signal_history.items) |entry| {
            if (entry.reason) |reason| {
                self.allocator.free(reason);
            }
        }
        self.signal_history.deinit(self.allocator);

        // Clean up strings
        self.allocator.free(self.id);
        self.allocator.free(self.request.strategy);
        self.allocator.free(self.request.symbol);
        self.allocator.free(self.request.timeframe);

        if (self.request.params) |p| {
            self.allocator.free(p);
        }
        if (self.request.wallet) |w| {
            self.allocator.free(w);
        }
        if (self.request.private_key) |pk| {
            self.allocator.free(pk);
        }
        if (self.last_error) |err| {
            self.allocator.free(err);
        }

        // Clean up connector
        if (self.connector) |conn| {
            conn.destroy();
        }

        // Clean up risk engine
        if (self.risk_engine) |re| {
            re.deinit();
            self.allocator.destroy(re);
        }

        // Clean up alert manager
        if (self.alert_manager) |am| {
            am.deinit();
            self.allocator.destroy(am);
        }

        self.allocator.destroy(self);
    }

    /// Start the strategy runner
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

        // Load strategy
        try self.loadStrategy();

        // Connect to exchange if not paper trading
        if (self.request.mode != .paper) {
            try self.connectExchange();
        }

        // Initialize risk management if enabled
        if (self.request.risk_enabled) {
            try self.initRiskManagement();
        }

        // Initialize candles buffer
        try self.initCandles();

        // Start background thread
        self.thread = try std.Thread.spawn(.{}, runLoop, .{self});

        self.status = .running;
    }

    /// Stop the strategy runner
    pub fn stop(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.status != .running and self.status != .paused) {
            return error.NotRunning;
        }

        self.status = .stopping;
        self.should_stop.store(true, .release);

        // Wait for thread to finish
        if (self.thread) |thread| {
            self.mutex.unlock();
            thread.join();
            self.mutex.lock();
            self.thread = null;
        }

        self.status = .stopped;
    }

    /// Pause strategy execution (keeps data streaming)
    pub fn pause(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.status != .running) {
            return error.NotRunning;
        }

        self.is_paused.store(true, .release);
        self.status = .paused;
    }

    /// Resume strategy execution
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
    pub fn getStatus(self: *Self) StrategyStatus {
        return self.status;
    }

    /// Get current statistics
    pub fn getStats(self: *Self) StrategyStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var stats = self.stats;
        if (self.start_time > 0) {
            stats.uptime_seconds = std.time.timestamp() - self.start_time;
        }
        stats.last_price = self.last_price.toFloat();
        stats.calculateWinRate();

        return stats;
    }

    /// Get signal history
    pub fn getSignalHistory(self: *Self, allocator: Allocator, limit: usize) ![]SignalHistoryEntry {
        self.mutex.lock();
        defer self.mutex.unlock();

        const count = @min(limit, self.signal_history.items.len);
        const start_idx = self.signal_history.items.len - count;

        var history = try allocator.alloc(SignalHistoryEntry, count);
        for (0..count) |i| {
            const entry = self.signal_history.items[start_idx + i];
            history[i] = .{
                .timestamp = entry.timestamp,
                .signal_type = entry.signal_type,
                .price = entry.price,
                .size = entry.size,
                .reason = if (entry.reason) |r| try allocator.dupe(u8, r) else null,
            };
        }

        return history;
    }

    /// Update strategy parameters (hot reload)
    pub fn updateParams(self: *Self, params_json: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Store new params
        if (self.request.params) |old| {
            self.allocator.free(old);
        }
        self.request.params = try self.allocator.dupe(u8, params_json);

        // Reload strategy if running
        if (self.status == .running or self.status == .paused) {
            // Clean up old strategy
            if (self.strategy_wrapper) |*wrapper| {
                wrapper.deinit();
                self.strategy_wrapper = null;
                self.strategy = null;
            }

            // Load new strategy
            try self.loadStrategyUnlocked();
        }
    }

    /// Get current parameters
    pub fn getParams(self: *Self) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.request.params;
    }

    // ========================================================================
    // Private Methods
    // ========================================================================

    /// Load strategy from factory
    fn loadStrategy(self: *Self) !void {
        try self.loadStrategyUnlocked();
    }

    fn loadStrategyUnlocked(self: *Self) !void {
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
                \\    "max_position": {d}
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
                self.request.max_position_size,
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
                self.request.strategy,
                self.pair.base,
                self.pair.quote,
                self.request.params orelse "{}",
            }) catch return error.ConfigBuildFailed;
        }

        const wrapper = factory.create(self.request.strategy, json) catch {
            return error.StrategyNotFound;
        };

        self.strategy_wrapper = wrapper;
        self.strategy = wrapper.interface;
    }

    /// Connect to exchange
    fn connectExchange(self: *Self) !void {
        const wallet = self.request.wallet orelse return error.MissingWallet;
        const private_key = self.request.private_key orelse return error.MissingPrivateKey;

        _ = wallet;
        _ = private_key;

        // In production, create HyperliquidConnector here
        // self.connector = try HyperliquidConnector.create(...)
    }

    /// Initialize risk management
    fn initRiskManagement(self: *Self) !void {
        // In production, initialize RiskEngine and AlertManager
        _ = self;
    }

    /// Initialize candles buffer
    fn initCandles(self: *Self) !void {
        // Create empty candles buffer with default pair and timeframe
        const candles = try self.allocator.create(Candles);
        candles.* = Candles.init(self.allocator, self.pair, self.timeframe);
        self.candles = candles;
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

            std.Thread.sleep(self.request.check_interval_ms * std.time.ns_per_ms);
        }
    }

    /// Single tick of the strategy loop
    fn tick(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Fetch latest market data
        try self.updateMarketData();

        // Get strategy
        const strategy = self.strategy orelse return;
        var candles = self.candles orelse return;

        if (candles.len() < 2) return;

        // Populate indicators
        try strategy.populateIndicators(candles);

        // Check for signals
        const current_index = candles.len() - 1;

        // Check for entry signal if no position
        if (self.stats.current_position == 0) {
            if (try strategy.generateEntrySignal(candles, current_index)) |signal| {
                try self.processSignal(signal);
            }
        } else {
            // Check for exit signal
            const BacktestPosition = root.BacktestPosition;
            const PositionSide = root.PositionSide;
            const position = BacktestPosition{
                .pair = self.pair,
                .entry_price = self.last_price,
                .size = Decimal.fromFloat(@abs(self.stats.current_position)),
                .side = if (self.stats.current_position > 0) PositionSide.long else PositionSide.short,
                .entry_time = .{ .millis = std.time.milliTimestamp() },
                .unrealized_pnl = Decimal.ZERO,
            };

            if (try strategy.generateExitSignal(candles, position)) |signal| {
                try self.processSignal(signal);
            }
        }
    }

    /// Update market data
    fn updateMarketData(self: *Self) !void {
        if (self.connector) |conn| {
            // Live mode: fetch from exchange
            const exchange = conn.interface();
            const ticker = try exchange.getTicker(self.pair);
            const mid_price = ticker.bid.add(ticker.ask).div(Decimal.fromInt(2)) catch ticker.last;
            self.last_price = mid_price;

            // Update candles from exchange
            // TODO: Implement real candle fetching
        } else {
            // Paper mode: simulate price
            if (self.last_price.isZero()) {
                // Start with a reasonable price
                self.last_price = Decimal.fromFloat(50000); // Example BTC price
            } else {
                // Random walk simulation
                const now = std.time.milliTimestamp();
                const random_factor = @mod(now, 100);
                const change = Decimal.fromFloat(@as(f64, @floatFromInt(random_factor)) - 50.0);
                self.last_price = self.last_price.add(change);

                // Ensure price is positive
                if (self.last_price.cmp(Decimal.ZERO) != .gt) {
                    self.last_price = Decimal.fromFloat(100);
                }
            }

            // Note: Paper mode doesn't populate candles dynamically
            // In production, we would fetch real candle data from an exchange
            // For paper trading, strategies run on price signals only
        }
    }

    /// Process a trading signal
    fn processSignal(self: *Self, signal: Signal) !void {
        const now = std.time.timestamp();
        self.stats.total_signals += 1;
        self.stats.last_signal_time = now;

        // Determine signal type string and side for logging
        const signal_type_str: []const u8 = switch (signal.type) {
            .entry_long => "entry_long",
            .entry_short => "entry_short",
            .exit_long => "exit_long",
            .exit_short => "exit_short",
            .hold => "hold",
        };

        // Calculate position size based on signal strength and available capital
        const account_value = self.account.getAccountValue();
        const risk_per_trade = account_value.mul(Decimal.fromFloat(0.02)); // 2% per trade
        const position_size = risk_per_trade.div(self.last_price) catch Decimal.fromFloat(0.001);

        try self.signal_history.append(self.allocator, .{
            .timestamp = now,
            .signal_type = signal_type_str,
            .price = self.last_price.toFloat(),
            .size = position_size.toFloat(),
            .reason = null,
        });

        // Trim history if too large
        while (self.signal_history.items.len > self.max_history_size) {
            const removed = self.signal_history.orderedRemove(0);
            if (removed.reason) |reason| {
                self.allocator.free(reason);
            }
        }

        // Execute signal based on type
        switch (signal.type) {
            .entry_long => {
                const size = position_size.toFloat();
                const cost = self.last_price.mul(position_size);

                // Check if we have enough capital
                if (account_value.cmp(cost) == .lt) {
                    self.stats.signals_rejected_by_risk += 1;
                    return;
                }

                // Update position
                self.stats.current_position += size;
                self.account.margin_summary.account_value = account_value.sub(cost);
                self.stats.total_trades += 1;
            },
            .exit_long, .exit_short => {
                const size = @abs(self.stats.current_position);

                if (size < 0.0001) {
                    // No position to exit
                    return;
                }

                // Calculate PnL (simplified - in production would track entry price)
                const revenue = self.last_price.mul(Decimal.fromFloat(size));
                const estimated_cost = signal.price.mul(Decimal.fromFloat(size));
                const pnl = revenue.sub(estimated_cost).toFloat();

                if (pnl > 0) {
                    self.stats.winning_trades += 1;
                } else {
                    self.stats.losing_trades += 1;
                }

                self.stats.realized_pnl += pnl;
                self.stats.current_position = 0;
                self.account.margin_summary.account_value = self.account.margin_summary.account_value.add(revenue);
                self.stats.total_trades += 1;
            },
            .entry_short => {
                const size = position_size.toFloat();

                // Short positions
                self.stats.current_position -= size;
                self.stats.total_trades += 1;
            },
            .hold => {},
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

test "StrategyRequest parsePair" {
    const req1 = StrategyRequest{
        .strategy = "dual_ma",
        .symbol = "BTC-USDT",
        .timeframe = "1h",
    };
    const pair1 = req1.parsePair();
    try std.testing.expectEqualStrings("BTC", pair1.base);
    try std.testing.expectEqualStrings("USDT", pair1.quote);

    const req2 = StrategyRequest{
        .strategy = "dual_ma",
        .symbol = "ETHUSDC",
        .timeframe = "1h",
    };
    const pair2 = req2.parsePair();
    try std.testing.expectEqualStrings("ETH", pair2.base);
    try std.testing.expectEqualStrings("USDC", pair2.quote);
}

test "StrategyRunner init and deinit" {
    const allocator = std.testing.allocator;

    const request = StrategyRequest{
        .strategy = "dual_ma",
        .symbol = "BTC-USDT",
        .timeframe = "1h",
        .mode = .paper,
    };

    const runner = try StrategyRunner.init(allocator, "test_strategy_1", request);
    defer runner.deinit();

    try std.testing.expectEqualStrings("test_strategy_1", runner.id);
    try std.testing.expectEqual(StrategyStatus.stopped, runner.status);
}

test "StrategyStats calculateWinRate" {
    var stats = StrategyStats{
        .total_trades = 10,
        .winning_trades = 7,
        .losing_trades = 3,
    };
    stats.calculateWinRate();

    try std.testing.expectApproxEqAbs(@as(f64, 70.0), stats.win_rate, 0.01);
}

test "TradingMode fromString" {
    try std.testing.expectEqual(TradingMode.paper, TradingMode.fromString("paper"));
    try std.testing.expectEqual(TradingMode.testnet, TradingMode.fromString("testnet"));
    try std.testing.expectEqual(TradingMode.mainnet, TradingMode.fromString("mainnet"));
    try std.testing.expectEqual(TradingMode.paper, TradingMode.fromString("unknown"));
}
