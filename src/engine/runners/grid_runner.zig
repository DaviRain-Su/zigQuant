//! Grid Runner
//!
//! Wraps grid trading logic for lifecycle management via API.
//! Provides a clean interface for starting, stopping, and monitoring
//! grid trading bots through the web control platform.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import zigQuant types
const root = @import("../../root.zig");
const Decimal = root.Decimal;
const TradingPair = root.TradingPair;
const Side = root.Side;
const OrderType = root.OrderType;
const TimeInForce = root.TimeInForce;
const HyperliquidConnector = root.HyperliquidConnector;
const ExchangeConfig = root.ExchangeConfig;
const OrderRequest = root.OrderRequest;
const RiskEngine = root.RiskEngine;
const AlertManager = root.AlertManager;
const Account = root.Account;

/// Grid trading configuration
pub const GridConfig = struct {
    /// Trading pair (e.g., BTC-USDC)
    pair: TradingPair,

    /// Upper price boundary
    upper_price: Decimal,

    /// Lower price boundary
    lower_price: Decimal,

    /// Number of grid levels
    grid_count: u32,

    /// Order size per grid level
    order_size: Decimal,

    /// Take profit percentage per grid (e.g., 0.5 = 0.5%)
    take_profit_pct: f64 = 0.5,

    /// Maximum total position allowed
    max_position: Decimal = Decimal.fromFloat(1.0),

    /// Check interval in milliseconds
    check_interval_ms: u64 = 5000,

    /// Trading mode
    mode: TradingMode = .paper,

    /// Exchange credentials (for live/testnet)
    wallet: ?[]const u8 = null,
    private_key: ?[]const u8 = null,

    /// Risk management settings
    risk_enabled: bool = true,
    max_daily_loss_pct: f64 = 0.02,

    /// Calculate grid interval
    pub fn gridInterval(self: GridConfig) Decimal {
        return self.upper_price.sub(self.lower_price).div(Decimal.fromInt(self.grid_count)) catch Decimal.ZERO;
    }

    /// Calculate price at a specific grid level
    pub fn priceAtLevel(self: GridConfig, level: u32) Decimal {
        const interval = self.gridInterval();
        return self.lower_price.add(interval.mul(Decimal.fromInt(level)));
    }

    /// Validate configuration
    pub fn validate(self: GridConfig) !void {
        if (self.upper_price.cmp(self.lower_price) != .gt) {
            return error.InvalidPriceRange;
        }
        if (self.grid_count < 2) {
            return error.InvalidGridCount;
        }
        if (self.order_size.cmp(Decimal.ZERO) != .gt) {
            return error.InvalidOrderSize;
        }
        if (self.take_profit_pct <= 0 or self.take_profit_pct > 100) {
            return error.InvalidTakeProfit;
        }
    }

    /// Convert to JSON-serializable struct
    pub fn toJson(self: GridConfig) GridConfigJson {
        return .{
            .pair = .{ .base = self.pair.base, .quote = self.pair.quote },
            .upper_price = self.upper_price.toFloat(),
            .lower_price = self.lower_price.toFloat(),
            .grid_count = self.grid_count,
            .order_size = self.order_size.toFloat(),
            .take_profit_pct = self.take_profit_pct,
            .max_position = self.max_position.toFloat(),
            .check_interval_ms = self.check_interval_ms,
            .mode = @tagName(self.mode),
            .risk_enabled = self.risk_enabled,
            .max_daily_loss_pct = self.max_daily_loss_pct,
        };
    }
};

/// JSON-serializable config
pub const GridConfigJson = struct {
    pair: struct { base: []const u8, quote: []const u8 },
    upper_price: f64,
    lower_price: f64,
    grid_count: u32,
    order_size: f64,
    take_profit_pct: f64,
    max_position: f64,
    check_interval_ms: u64,
    mode: []const u8,
    risk_enabled: bool,
    max_daily_loss_pct: f64,
};

/// Trading mode
pub const TradingMode = enum {
    paper,
    testnet,
    mainnet,
};

/// Grid order state
pub const GridOrder = struct {
    level: u32,
    price: f64,
    side: []const u8,
    status: []const u8,
    exchange_order_id: ?u64 = null,
    filled_qty: f64 = 0,
    created_at: i64,
    updated_at: i64,
};

/// Grid runner status
pub const GridStatus = enum {
    stopped,
    starting,
    running,
    stopping,
    error_state,

    pub fn toString(self: GridStatus) []const u8 {
        return switch (self) {
            .stopped => "stopped",
            .starting => "starting",
            .running => "running",
            .stopping => "stopping",
            .error_state => "error",
        };
    }
};

/// Grid statistics
pub const GridStats = struct {
    total_trades: u32 = 0,
    total_bought: f64 = 0,
    total_sold: f64 = 0,
    current_position: f64 = 0,
    realized_pnl: f64 = 0,
    unrealized_pnl: f64 = 0,
    active_buy_orders: u32 = 0,
    active_sell_orders: u32 = 0,
    last_price: f64 = 0,
    uptime_seconds: i64 = 0,
    orders_rejected_by_risk: u32 = 0,
};

/// Grid level state
const GridLevel = struct {
    level: u32,
    price: Decimal,
    has_buy_order: bool = false,
    has_sell_order: bool = false,
    buy_order_id: ?u64 = null,
    sell_order_id: ?u64 = null,
};

/// Grid order internal state
const InternalOrder = struct {
    level: u32,
    price: Decimal,
    side: Side,
    status: OrderStatus,
    exchange_order_id: ?u64 = null,
    filled_qty: Decimal = Decimal.ZERO,
    created_at: i64,
    updated_at: i64,

    const OrderStatus = enum {
        pending,
        active,
        filled,
        cancelled,
    };
};

/// Grid Runner - manages a single grid trading bot
pub const GridRunner = struct {
    allocator: Allocator,
    id: []const u8,
    config: GridConfig,
    status: GridStatus,
    stats: GridStats,
    start_time: i64,
    last_error: ?[]const u8,

    // Internal state
    grid_levels: []GridLevel,
    buy_orders: std.ArrayList(InternalOrder),
    sell_orders: std.ArrayList(InternalOrder),
    last_price: Decimal,

    // Exchange connection (for live/testnet)
    connector: ?*HyperliquidConnector,

    // Risk management
    risk_engine: ?*RiskEngine,
    alert_manager: ?*AlertManager,
    account: Account,

    // Thread management
    thread: ?std.Thread,
    should_stop: std.atomic.Value(bool),
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Create a new grid runner
    pub fn init(allocator: Allocator, id: []const u8, config: GridConfig) !*Self {
        // Validate config
        try config.validate();

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Initialize grid levels
        const grid_levels = try allocator.alloc(GridLevel, config.grid_count + 1);
        errdefer allocator.free(grid_levels);

        for (0..config.grid_count + 1) |i| {
            const level: u32 = @intCast(i);
            grid_levels[i] = GridLevel{
                .level = level,
                .price = config.priceAtLevel(level),
            };
        }

        // Copy ID
        const id_copy = try allocator.dupe(u8, id);

        self.* = .{
            .allocator = allocator,
            .id = id_copy,
            .config = config,
            .status = .stopped,
            .stats = .{},
            .start_time = 0,
            .last_error = null,
            .grid_levels = grid_levels,
            .buy_orders = std.ArrayList(InternalOrder){},
            .sell_orders = std.ArrayList(InternalOrder){},
            .last_price = Decimal.ZERO,
            .connector = null,
            .risk_engine = null,
            .alert_manager = null,
            .account = Account.init(),
            .thread = null,
            .should_stop = std.atomic.Value(bool).init(false),
            .mutex = .{},
        };

        // Re-export TradingMode for external access
        _ = TradingMode;

        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        // Stop if running
        if (self.status == .running) {
            self.stop() catch {};
        }

        // Clean up orders
        self.buy_orders.deinit(self.allocator);
        self.sell_orders.deinit(self.allocator);

        // Clean up grid levels
        self.allocator.free(self.grid_levels);

        // Clean up ID
        self.allocator.free(self.id);

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

        // Clean up error message
        if (self.last_error) |err| {
            self.allocator.free(err);
        }

        self.allocator.destroy(self);
    }

    /// Start the grid runner
    pub fn start(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.status == .running) {
            return error.AlreadyRunning;
        }

        self.status = .starting;
        self.start_time = std.time.timestamp();
        self.should_stop.store(false, .release);

        // Connect to exchange if not paper trading
        if (self.config.mode != .paper) {
            try self.connectExchange();
        }

        // Initialize risk management if enabled
        if (self.config.risk_enabled) {
            try self.initRiskManagement();
        }

        // Place initial orders
        try self.placeInitialOrders();

        // Start background thread
        self.thread = try std.Thread.spawn(.{}, runLoop, .{self});

        self.status = .running;
    }

    /// Stop the grid runner
    pub fn stop(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.status != .running) {
            return error.NotRunning;
        }

        self.status = .stopping;
        self.should_stop.store(true, .release);

        // Wait for thread to finish
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        // Cancel all orders
        try self.cancelAllOrders();

        self.status = .stopped;
    }

    /// Get current status
    pub fn getStatus(self: *Self) GridStatus {
        return self.status;
    }

    /// Get current statistics
    pub fn getStats(self: *Self) GridStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var stats = self.stats;
        stats.uptime_seconds = if (self.start_time > 0)
            std.time.timestamp() - self.start_time
        else
            0;
        stats.last_price = self.last_price.toFloat();
        stats.active_buy_orders = @intCast(self.countActiveOrders(.buy));
        stats.active_sell_orders = @intCast(self.countActiveOrders(.sell));

        return stats;
    }

    /// Get active orders
    pub fn getOrders(self: *Self, allocator: Allocator) ![]GridOrder {
        self.mutex.lock();
        defer self.mutex.unlock();

        const total = self.buy_orders.items.len + self.sell_orders.items.len;
        var orders = try allocator.alloc(GridOrder, total);
        var idx: usize = 0;

        for (self.buy_orders.items) |order| {
            orders[idx] = .{
                .level = order.level,
                .price = order.price.toFloat(),
                .side = "buy",
                .status = switch (order.status) {
                    .pending => "pending",
                    .active => "active",
                    .filled => "filled",
                    .cancelled => "cancelled",
                },
                .exchange_order_id = order.exchange_order_id,
                .filled_qty = order.filled_qty.toFloat(),
                .created_at = order.created_at,
                .updated_at = order.updated_at,
            };
            idx += 1;
        }

        for (self.sell_orders.items) |order| {
            orders[idx] = .{
                .level = order.level,
                .price = order.price.toFloat(),
                .side = "sell",
                .status = switch (order.status) {
                    .pending => "pending",
                    .active => "active",
                    .filled => "filled",
                    .cancelled => "cancelled",
                },
                .exchange_order_id = order.exchange_order_id,
                .filled_qty = order.filled_qty.toFloat(),
                .created_at = order.created_at,
                .updated_at = order.updated_at,
            };
            idx += 1;
        }

        return orders;
    }

    /// Update configuration (hot reload)
    pub fn updateConfig(self: *Self, new_config: GridConfig) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Validate new config
        try new_config.validate();

        // Only allow certain fields to be updated while running
        self.config.take_profit_pct = new_config.take_profit_pct;
        self.config.max_position = new_config.max_position;
        self.config.check_interval_ms = new_config.check_interval_ms;
        self.config.risk_enabled = new_config.risk_enabled;
        self.config.max_daily_loss_pct = new_config.max_daily_loss_pct;
    }

    // ========================================================================
    // Private Methods
    // ========================================================================

    /// Connect to exchange
    fn connectExchange(self: *Self) !void {
        const wallet = self.config.wallet orelse return error.MissingWallet;
        const private_key = self.config.private_key orelse return error.MissingPrivateKey;

        const exchange_config = ExchangeConfig{
            .name = "hyperliquid",
            .api_key = wallet,
            .api_secret = private_key,
            .testnet = self.config.mode == .testnet,
        };

        // Note: Logger needs to be passed properly in production
        // self.connector = try HyperliquidConnector.create(
        //     self.allocator,
        //     exchange_config,
        //     logger,
        // );
        _ = exchange_config;
    }

    /// Initialize risk management
    fn initRiskManagement(self: *Self) !void {
        // In production, initialize RiskEngine and AlertManager
        _ = self;
    }

    /// Place initial grid orders
    fn placeInitialOrders(self: *Self) !void {
        const current_price = try self.getCurrentPrice();
        const now = std.time.timestamp();

        for (self.grid_levels) |level| {
            if (level.price.cmp(current_price) == .lt) {
                // Price below current - place buy order
                try self.buy_orders.append(self.allocator, .{
                    .level = level.level,
                    .price = level.price,
                    .side = .buy,
                    .status = if (self.config.mode == .paper) .pending else .active,
                    .created_at = now,
                    .updated_at = now,
                });
            }
        }
    }

    /// Get current market price
    fn getCurrentPrice(self: *Self) !Decimal {
        if (self.connector) |conn| {
            const exchange = conn.interface();
            const ticker = try exchange.getTicker(self.config.pair);
            const mid_price = ticker.bid.add(ticker.ask).div(Decimal.fromInt(2)) catch ticker.last;
            self.last_price = mid_price;
            return mid_price;
        } else {
            // Paper trading - simulate price
            if (self.last_price.isZero()) {
                const mid = self.config.lower_price.add(self.config.upper_price).div(Decimal.fromInt(2)) catch self.config.lower_price;
                self.last_price = mid;
            } else {
                // Simulate random walk
                const grid_interval = self.config.gridInterval();
                const movement = grid_interval.mul(Decimal.fromFloat(0.3));

                const now = std.time.milliTimestamp();
                const random_factor = @mod(now, 100);

                if (random_factor < 45) {
                    self.last_price = self.last_price.sub(movement.mul(Decimal.fromFloat(@as(f64, @floatFromInt(random_factor)) / 100.0)));
                } else if (random_factor > 55) {
                    self.last_price = self.last_price.add(movement.mul(Decimal.fromFloat(@as(f64, @floatFromInt(random_factor - 55)) / 100.0)));
                }

                // Clamp to bounds
                if (self.last_price.cmp(self.config.lower_price) == .lt) {
                    self.last_price = self.config.lower_price;
                } else if (self.last_price.cmp(self.config.upper_price) == .gt) {
                    self.last_price = self.config.upper_price;
                }
            }
            return self.last_price;
        }
    }

    /// Main run loop (executed in background thread)
    fn runLoop(self: *Self) void {
        while (!self.should_stop.load(.acquire)) {
            self.tick() catch |err| {
                self.setError(@errorName(err));
            };

            std.Thread.sleep(self.config.check_interval_ms * std.time.ns_per_ms);
        }
    }

    /// Single tick of the trading loop
    fn tick(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const current_price = try self.getCurrentPrice();

        if (self.config.mode == .paper) {
            try self.simulateFills(current_price);
        } else {
            try self.checkRealFills();
        }
    }

    /// Simulate fills for paper trading
    fn simulateFills(self: *Self, current_price: Decimal) !void {
        const now = std.time.timestamp();

        // Check buy orders
        var i: usize = 0;
        while (i < self.buy_orders.items.len) {
            const order = &self.buy_orders.items[i];
            if (order.status == .pending and current_price.cmp(order.price) != .gt) {
                // Buy order filled
                order.status = .filled;
                order.filled_qty = self.config.order_size;
                order.updated_at = now;

                self.stats.current_position += self.config.order_size.toFloat();
                self.stats.total_bought += self.config.order_size.toFloat();
                self.stats.total_trades += 1;

                // Place corresponding sell order
                const sell_price = order.price.mul(Decimal.fromFloat(1.0 + self.config.take_profit_pct / 100.0));
                try self.sell_orders.append(self.allocator, .{
                    .level = order.level,
                    .price = sell_price,
                    .side = .sell,
                    .status = .pending,
                    .created_at = now,
                    .updated_at = now,
                });

                _ = self.buy_orders.orderedRemove(i);
                continue;
            }
            i += 1;
        }

        // Check sell orders
        i = 0;
        while (i < self.sell_orders.items.len) {
            const order = &self.sell_orders.items[i];
            if (order.status == .pending and current_price.cmp(order.price) != .lt) {
                // Sell order filled
                order.status = .filled;
                order.filled_qty = self.config.order_size;
                order.updated_at = now;

                // Calculate profit
                const buy_price = order.price.div(Decimal.fromFloat(1.0 + self.config.take_profit_pct / 100.0)) catch order.price;
                const profit = order.price.sub(buy_price).mul(self.config.order_size);

                self.stats.realized_pnl += profit.toFloat();
                self.stats.current_position -= self.config.order_size.toFloat();
                self.stats.total_sold += self.config.order_size.toFloat();
                self.stats.total_trades += 1;

                // Place new buy order at original level
                for (self.grid_levels) |level| {
                    if (level.level == order.level) {
                        try self.buy_orders.append(self.allocator, .{
                            .level = level.level,
                            .price = level.price,
                            .side = .buy,
                            .status = .pending,
                            .created_at = now,
                            .updated_at = now,
                        });
                        break;
                    }
                }

                _ = self.sell_orders.orderedRemove(i);
                continue;
            }
            i += 1;
        }
    }

    /// Check real order fills from exchange
    fn checkRealFills(self: *Self) !void {
        // TODO: Implement real order status checking
        _ = self;
    }

    /// Cancel all orders
    fn cancelAllOrders(self: *Self) !void {
        if (self.connector) |conn| {
            const exchange = conn.interface();
            _ = try exchange.cancelAllOrders(self.config.pair);
        }
        self.buy_orders.clearRetainingCapacity();
        self.sell_orders.clearRetainingCapacity();
    }

    /// Count active orders
    fn countActiveOrders(self: *Self, side: Side) usize {
        var count: usize = 0;
        if (side == .buy) {
            for (self.buy_orders.items) |order| {
                if (order.status == .pending or order.status == .active) count += 1;
            }
        } else {
            for (self.sell_orders.items) |order| {
                if (order.status == .pending or order.status == .active) count += 1;
            }
        }
        return count;
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

test "GridConfig validation" {
    const config = GridConfig{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(100000),
        .lower_price = Decimal.fromFloat(90000),
        .grid_count = 10,
        .order_size = Decimal.fromFloat(0.001),
    };

    try config.validate();
}

test "GridConfig invalid range" {
    const config = GridConfig{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(90000),
        .lower_price = Decimal.fromFloat(100000), // Invalid: lower > upper
        .grid_count = 10,
        .order_size = Decimal.fromFloat(0.001),
    };

    try std.testing.expectError(error.InvalidPriceRange, config.validate());
}

test "GridRunner init and deinit" {
    const allocator = std.testing.allocator;

    const config = GridConfig{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(100000),
        .lower_price = Decimal.fromFloat(90000),
        .grid_count = 5,
        .order_size = Decimal.fromFloat(0.001),
        .mode = .paper,
    };

    const runner = try GridRunner.init(allocator, "test_grid_1", config);
    defer runner.deinit();

    try std.testing.expectEqualStrings("test_grid_1", runner.id);
    try std.testing.expectEqual(GridStatus.stopped, runner.status);
}
