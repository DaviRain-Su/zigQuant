//! Grid Trading Command
//!
//! Run grid trading strategy on Hyperliquid testnet or mainnet.
//!
//! Usage:
//! ```bash
//! # Paper trading (simulated)
//! zigquant grid --pair BTC-USDC --upper 100000 --lower 90000 --grids 10 --size 0.001 --paper
//!
//! # Live trading on testnet (using config file)
//! zigquant grid --config config.test.json --pair BTC-USDC --upper 100000 --lower 90000 --grids 10 --testnet
//!
//! # Live trading on mainnet (CAUTION!)
//! zigquant grid --pair BTC-USDC --upper 100000 --lower 90000 --grids 10 --size 0.001 --live
//! ```

const std = @import("std");
const clap = @import("clap");
const zigQuant = @import("zigQuant");

const Decimal = zigQuant.Decimal;
const TradingPair = zigQuant.TradingPair;
const Timestamp = zigQuant.Timestamp;
const Logger = zigQuant.Logger;
const Side = zigQuant.Side;
const OrderType = zigQuant.OrderType;
const TimeInForce = zigQuant.TimeInForce;
const HyperliquidConnector = zigQuant.HyperliquidConnector;
const ExchangeConfig = zigQuant.ExchangeConfig;
const OrderRequest = zigQuant.OrderRequest;
const Ticker = zigQuant.Ticker;

// Grid Strategy types
const GridStrategy = zigQuant.GridStrategy;
const GridConfig = zigQuant.GridStrategyConfig;
const GridLevel = zigQuant.GridLevel;

// Config and Risk Management
const ConfigLoader = zigQuant.ConfigLoader;
const AppConfig = zigQuant.AppConfig;
const RiskEngine = zigQuant.RiskEngine;
const RiskEngineConfig = zigQuant.RiskEngineConfig; // Risk engine config from risk module
const RiskCheckResult = zigQuant.RiskCheckResult;
const AlertManager = zigQuant.AlertManager;
const AlertConfig = zigQuant.AlertConfig;
const AlertCategory = zigQuant.AlertCategory;
const AlertDetails = zigQuant.AlertDetails;
const ConsoleChannel = zigQuant.ConsoleChannel;
const Account = zigQuant.Account;

// ============================================================================
// CLI Parameters
// ============================================================================

const params = clap.parseParamsComptime(
    \\-h, --help                Display help
    \\-p, --pair <str>          Trading pair (e.g., BTC-USDC) [required]
    \\    --upper <str>         Upper price bound [required]
    \\    --lower <str>         Lower price bound [required]
    \\-g, --grids <str>         Number of grid levels (default: 10)
    \\-s, --size <str>          Order size per grid (default: 0.001)
    \\    --tp <str>            Take profit percentage per grid (default: 0.5)
    \\    --max-position <str>  Maximum total position (default: 1.0)
    \\    --paper               Paper trading mode (simulated, default)
    \\    --testnet             Live trading on testnet
    \\    --live                Live trading on mainnet (CAUTION!)
    \\    --wallet <str>        Wallet address (0x...)
    \\    --key <str>           Private key (without 0x prefix)
    \\    --config <str>        Config file path (e.g., config.test.json)
    \\    --interval <str>      Check interval in milliseconds (default: 5000)
    \\    --duration <str>      Run duration in minutes, 0 for infinite (default: 0)
    \\    --no-risk             Disable risk management checks
    \\
);

// ============================================================================
// Trading Mode
// ============================================================================

const TradingMode = enum {
    paper,
    testnet,
    mainnet,
};

// ============================================================================
// Grid Order State
// ============================================================================

const GridOrderState = struct {
    level: u32,
    price: Decimal,
    side: Side,
    status: OrderStatus,
    exchange_order_id: ?u64 = null,
    filled_qty: Decimal = Decimal.ZERO,

    const OrderStatus = enum {
        pending, // Not yet placed
        active, // Order is open on exchange
        filled, // Order has been filled
        cancelled, // Order was cancelled
    };
};

// ============================================================================
// Grid Bot
// ============================================================================

const GridBot = struct {
    allocator: std.mem.Allocator,
    logger: *Logger,
    config: GridConfig,
    mode: TradingMode,

    // Exchange connection (for live trading)
    connector: ?*HyperliquidConnector = null,

    // Grid state
    grid_levels: []GridLevel,
    buy_orders: std.ArrayList(GridOrderState),
    sell_orders: std.ArrayList(GridOrderState),

    // Position tracking
    current_position: Decimal = Decimal.ZERO,
    total_bought: Decimal = Decimal.ZERO,
    total_sold: Decimal = Decimal.ZERO,
    realized_pnl: Decimal = Decimal.ZERO,
    trades_count: u32 = 0,

    // Last known price
    last_price: Decimal = Decimal.ZERO,

    // Risk Management
    risk_engine: ?*RiskEngine = null,
    alert_manager: ?*AlertManager = null,
    account: Account,
    risk_enabled: bool = true,

    // Risk tracking
    orders_rejected_by_risk: u32 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: *Logger,
        config: GridConfig,
        mode: TradingMode,
    ) !*GridBot {
        const self = try allocator.create(GridBot);
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

        const buy_orders = try std.ArrayList(GridOrderState).initCapacity(allocator, config.grid_count + 1);
        errdefer @constCast(&buy_orders).deinit(allocator);
        const sell_orders = try std.ArrayList(GridOrderState).initCapacity(allocator, config.grid_count + 1);

        self.* = .{
            .allocator = allocator,
            .logger = logger,
            .config = config,
            .mode = mode,
            .grid_levels = grid_levels,
            .buy_orders = buy_orders,
            .sell_orders = sell_orders,
            .account = Account.init(),
        };

        return self;
    }

    pub fn deinit(self: *GridBot) void {
        self.buy_orders.deinit(self.allocator);
        self.sell_orders.deinit(self.allocator);
        self.allocator.free(self.grid_levels);
        if (self.connector) |conn| {
            conn.destroy();
        }
        if (self.risk_engine) |re| {
            re.deinit();
            self.allocator.destroy(re);
        }
        if (self.alert_manager) |am| {
            am.deinit();
            self.allocator.destroy(am);
        }
        self.allocator.destroy(self);
    }

    /// Initialize risk management components
    pub fn initRiskManagement(self: *GridBot, max_position_size: Decimal, risk_limit: f64) !void {
        // Initialize account with a default value (will be updated from exchange)
        self.account.cross_margin_summary.account_value = Decimal.fromFloat(10000); // Default

        // Create risk config based on trading config
        const risk_config = RiskEngineConfig{
            .max_position_size = max_position_size,
            .max_position_per_symbol = max_position_size,
            .max_leverage = Decimal.fromFloat(3.0),
            .max_daily_loss = max_position_size.mul(Decimal.fromFloat(risk_limit)),
            .max_daily_loss_pct = risk_limit,
            .max_orders_per_minute = 60,
            .kill_switch_threshold = max_position_size.mul(Decimal.fromFloat(risk_limit * 2)),
            .close_positions_on_kill_switch = true,
        };

        // Create risk engine
        const risk_engine = try self.allocator.create(RiskEngine);
        risk_engine.* = RiskEngine.init(self.allocator, risk_config, null, &self.account);
        self.risk_engine = risk_engine;

        // Create alert manager
        const alert_manager = try self.allocator.create(AlertManager);
        alert_manager.* = AlertManager.init(self.allocator, AlertConfig.default());
        self.alert_manager = alert_manager;

        // Add console channel for alerts
        var console = try self.allocator.create(ConsoleChannel);
        console.* = ConsoleChannel.init(.{
            .colorize = true,
            .show_details = true,
            .show_timestamp = true,
        });
        try alert_manager.addChannel(console.asChannel());

        try self.logger.info("[RISK] Risk management initialized", .{});
        try self.logger.info("[RISK] Max position: {d:.2}, Daily loss limit: {d:.2}%", .{
            max_position_size.toFloat(),
            risk_limit * 100,
        });
    }

    /// Check order against risk limits
    fn checkRisk(self: *GridBot, order_request: OrderRequest) bool {
        if (!self.risk_enabled) return true;

        if (self.risk_engine) |re| {
            const result = re.checkOrder(order_request);
            if (!result.passed) {
                self.orders_rejected_by_risk += 1;
                self.logger.warn("[RISK] Order rejected: {s}", .{result.message orelse "Unknown reason"}) catch {};

                // Send alert
                if (self.alert_manager) |am| {
                    am.riskAlert(.risk_position_exceeded, .{
                        .symbol = order_request.pair.base,
                        .quantity = order_request.amount,
                        .price = order_request.price,
                    }) catch {};
                }
                return false;
            }
        }
        return true;
    }

    /// Send trade alert
    fn sendTradeAlert(self: *GridBot, category: AlertCategory, symbol: []const u8, price: Decimal, quantity: Decimal, pnl: ?Decimal) void {
        if (self.alert_manager) |am| {
            am.tradeAlert(category, .{
                .symbol = symbol,
                .price = price,
                .quantity = quantity,
                .pnl = pnl,
            }) catch {};
        }
    }

    /// Connect to exchange (for live/testnet mode)
    pub fn connect(self: *GridBot, wallet: []const u8, private_key: []const u8, testnet: bool) !void {
        const exchange_config = ExchangeConfig{
            .name = "hyperliquid",
            .api_key = wallet,
            .api_secret = private_key,
            .testnet = testnet,
        };

        self.connector = try HyperliquidConnector.create(
            self.allocator,
            exchange_config,
            self.logger.*,
        );

        try self.logger.info("Connected to Hyperliquid {s}", .{
            if (testnet) "Testnet" else "Mainnet",
        });
    }

    /// Get current market price
    pub fn getCurrentPrice(self: *GridBot) !Decimal {
        if (self.connector) |conn| {
            const exchange = conn.interface();
            const ticker = try exchange.getTicker(self.config.pair);
            const mid_price = ticker.bid.add(ticker.ask).div(Decimal.fromInt(2)) catch ticker.last;
            self.last_price = mid_price;
            return mid_price;
        } else {
            // Paper trading - simulate random price movement within grid
            if (self.last_price.isZero()) {
                // Start at middle of grid
                const mid = self.config.lower_price.add(self.config.upper_price).div(Decimal.fromInt(2)) catch self.config.lower_price;
                self.last_price = mid;
            } else {
                // Simulate random walk within grid bounds
                const grid_interval = self.config.gridInterval();
                const movement_range = grid_interval.mul(Decimal.fromFloat(0.5)); // Move up to 50% of grid interval

                // Simple pseudo-random based on timestamp
                const now = std.time.milliTimestamp();
                const random_factor = @mod(now, 100);

                var new_price = self.last_price;
                if (random_factor < 45) {
                    // Move down
                    new_price = self.last_price.sub(movement_range.mul(Decimal.fromFloat(@as(f64, @floatFromInt(random_factor)) / 100.0)));
                } else if (random_factor > 55) {
                    // Move up
                    new_price = self.last_price.add(movement_range.mul(Decimal.fromFloat(@as(f64, @floatFromInt(random_factor - 55)) / 100.0)));
                }
                // else: stay the same (45-55)

                // Clamp to grid bounds with some margin
                const margin = grid_interval.mul(Decimal.fromFloat(0.1));
                if (new_price.cmp(self.config.lower_price.sub(margin)) == .lt) {
                    new_price = self.config.lower_price;
                } else if (new_price.cmp(self.config.upper_price.add(margin)) == .gt) {
                    new_price = self.config.upper_price;
                }

                self.last_price = new_price;
            }
            return self.last_price;
        }
    }

    /// Place initial grid orders
    pub fn placeInitialOrders(self: *GridBot) !void {
        const current_price = try self.getCurrentPrice();
        try self.logger.info("Current price: {d:.2}", .{current_price.toFloat()});

        var buy_count: u32 = 0;
        var sell_count: u32 = 0;

        for (self.grid_levels) |*level| {
            if (level.price.cmp(current_price) == .lt) {
                // Price below current - place buy order
                if (self.mode != .paper) {
                    try self.placeBuyOrder(level);
                } else {
                    try self.buy_orders.append(self.allocator, .{
                        .level = level.level,
                        .price = level.price,
                        .side = .buy,
                        .status = .pending,
                    });
                }
                buy_count += 1;
            } else {
                // Price above current - place sell order (if we have position)
                // For initial setup, we don't place sell orders without position
                sell_count += 1;
            }
        }

        try self.logger.info("Initial setup: {} buy orders below price, {} potential sell levels above", .{
            buy_count,
            sell_count,
        });
    }

    /// Place a buy order at a grid level
    fn placeBuyOrder(self: *GridBot, level: *GridLevel) !void {
        if (self.connector) |conn| {
            const exchange = conn.interface();

            const order_request = OrderRequest{
                .pair = self.config.pair,
                .side = .buy,
                .order_type = .limit,
                .amount = self.config.order_size,
                .price = level.price,
                .time_in_force = .gtc,
                .reduce_only = false,
            };

            // Check risk before placing order
            if (!self.checkRisk(order_request)) {
                try self.logger.warn("[BUY ORDER] Rejected by risk check @ {d:.2}", .{level.price.toFloat()});
                return;
            }

            const order = try exchange.createOrder(order_request);

            try self.buy_orders.append(self.allocator, .{
                .level = level.level,
                .price = level.price,
                .side = .buy,
                .status = .active,
                .exchange_order_id = order.exchange_order_id,
            });

            try self.logger.info("[BUY ORDER] Level {} @ {d:.2}", .{
                level.level,
                level.price.toFloat(),
            });

            // Send trade alert
            self.sendTradeAlert(.trade_executed, self.config.pair.base, level.price, self.config.order_size, null);
        }
    }

    /// Place a sell order at a grid level
    fn placeSellOrder(self: *GridBot, level: *GridLevel, entry_price: Decimal) !void {
        const tp_price = entry_price.mul(Decimal.fromFloat(1.0 + self.config.take_profit_pct / 100.0));

        if (self.connector) |conn| {
            const exchange = conn.interface();

            const order_request = OrderRequest{
                .pair = self.config.pair,
                .side = .sell,
                .order_type = .limit,
                .amount = self.config.order_size,
                .price = tp_price,
                .time_in_force = .gtc,
                .reduce_only = false,
            };

            // Check risk before placing order
            if (!self.checkRisk(order_request)) {
                try self.logger.warn("[SELL ORDER] Rejected by risk check @ {d:.2}", .{tp_price.toFloat()});
                return;
            }

            const order = try exchange.createOrder(order_request);

            try self.sell_orders.append(self.allocator, .{
                .level = level.level,
                .price = tp_price,
                .side = .sell,
                .status = .active,
                .exchange_order_id = order.exchange_order_id,
            });

            try self.logger.info("[SELL ORDER] Level {} @ {d:.2} (entry: {d:.2})", .{
                level.level,
                tp_price.toFloat(),
                entry_price.toFloat(),
            });

            // Send trade alert
            self.sendTradeAlert(.trade_executed, self.config.pair.base, tp_price, self.config.order_size, null);
        }
    }

    /// Check and update orders (main loop iteration)
    pub fn tick(self: *GridBot) !void {
        const current_price = try self.getCurrentPrice();

        if (self.mode == .paper) {
            try self.simulateFills(current_price);
        } else {
            try self.checkRealFills();
        }
    }

    /// Simulate fills for paper trading
    fn simulateFills(self: *GridBot, current_price: Decimal) !void {
        // Check buy orders
        var i: usize = 0;
        while (i < self.buy_orders.items.len) {
            const order = &self.buy_orders.items[i];
            if (order.status == .pending and current_price.cmp(order.price) != .gt) {
                // Buy order filled!
                order.status = .filled;
                order.filled_qty = self.config.order_size;

                self.current_position = self.current_position.add(self.config.order_size);
                self.total_bought = self.total_bought.add(self.config.order_size);
                self.trades_count += 1;

                try self.logger.info("[FILL] BUY @ {d:.2} | Position: {d:.6}", .{
                    order.price.toFloat(),
                    self.current_position.toFloat(),
                });

                // Place corresponding sell order
                const sell_price = order.price.mul(Decimal.fromFloat(1.0 + self.config.take_profit_pct / 100.0));
                try self.sell_orders.append(self.allocator, .{
                    .level = order.level,
                    .price = sell_price,
                    .side = .sell,
                    .status = .pending,
                });

                // Remove filled buy order
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
                // Sell order filled!
                order.status = .filled;
                order.filled_qty = self.config.order_size;

                // Find the corresponding buy level to calculate profit
                const buy_price = order.price.div(Decimal.fromFloat(1.0 + self.config.take_profit_pct / 100.0)) catch order.price;

                const profit = order.price.sub(buy_price).mul(self.config.order_size);
                self.realized_pnl = self.realized_pnl.add(profit);
                self.current_position = self.current_position.sub(self.config.order_size);
                self.total_sold = self.total_sold.add(self.config.order_size);
                self.trades_count += 1;

                try self.logger.info("[FILL] SELL @ {d:.2} | Profit: {d:.4} | Total PnL: {d:.4}", .{
                    order.price.toFloat(),
                    profit.toFloat(),
                    self.realized_pnl.toFloat(),
                });

                // Place new buy order at the original level
                for (self.grid_levels) |*level| {
                    if (level.level == order.level) {
                        try self.buy_orders.append(self.allocator, .{
                            .level = level.level,
                            .price = level.price,
                            .side = .buy,
                            .status = .pending,
                        });
                        break;
                    }
                }

                // Remove filled sell order
                _ = self.sell_orders.orderedRemove(i);
                continue;
            }
            i += 1;
        }
    }

    /// Check real order fills from exchange
    fn checkRealFills(self: *GridBot) !void {
        if (self.connector == null) return;

        // TODO: Implement WebSocket order update handling
        // For now, poll open orders and check status
        try self.logger.debug("Checking order status...", .{});
    }

    /// Print current status
    pub fn printStatus(self: *GridBot) !void {
        try self.logger.info("", .{});
        try self.logger.info("═══════════════════════════════════════", .{});
        try self.logger.info("         Grid Bot Status", .{});
        try self.logger.info("═══════════════════════════════════════", .{});
        try self.logger.info("Current Price:    {d:.2}", .{self.last_price.toFloat()});
        try self.logger.info("Position:         {d:.6}", .{self.current_position.toFloat()});
        try self.logger.info("Active Buy Orders:  {}", .{self.countActiveOrders(.buy)});
        try self.logger.info("Active Sell Orders: {}", .{self.countActiveOrders(.sell)});
        try self.logger.info("Total Trades:     {}", .{self.trades_count});
        try self.logger.info("Realized PnL:     {d:.4}", .{self.realized_pnl.toFloat()});

        // Risk management stats
        if (self.risk_engine) |re| {
            const stats = re.getStats();
            try self.logger.info("───────────────────────────────────────", .{});
            try self.logger.info("Risk Checks:      {}", .{stats.total_checks});
            try self.logger.info("Orders Rejected:  {}", .{stats.rejected_orders});
            try self.logger.info("Kill Switch:      {s}", .{if (stats.kill_switch_active) "ACTIVE" else "off"});
        }

        try self.logger.info("═══════════════════════════════════════", .{});
        try self.logger.info("", .{});
    }

    fn countActiveOrders(self: *GridBot, side: Side) usize {
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

    /// Cancel all orders
    pub fn cancelAllOrders(self: *GridBot) !void {
        if (self.connector) |conn| {
            const exchange = conn.interface();
            const cancelled = try exchange.cancelAllOrders(self.config.pair);
            try self.logger.info("Cancelled {} orders", .{cancelled});
        }
        self.buy_orders.clearRetainingCapacity();
        self.sell_orders.clearRetainingCapacity();
    }
};

// ============================================================================
// Main Command
// ============================================================================

pub fn cmdGrid(
    allocator: std.mem.Allocator,
    logger: *Logger,
    args: []const []const u8,
) !void {
    // Parse arguments
    var diag = clap.Diagnostic{};
    var iter = clap.args.SliceIterator{ .args = args };
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, &iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try logger.err("Failed to parse arguments: {s}", .{@errorName(err)});
        try printHelp();
        return err;
    };
    defer res.deinit();

    // Show help if requested
    if (res.args.help != 0) {
        try printHelp();
        return;
    }

    // Parse required arguments
    const pair_str = res.args.pair orelse {
        try logger.err("Missing required argument: --pair", .{});
        try printHelp();
        return error.MissingPair;
    };

    const upper_str = res.args.upper orelse {
        try logger.err("Missing required argument: --upper", .{});
        try printHelp();
        return error.MissingUpper;
    };

    const lower_str = res.args.lower orelse {
        try logger.err("Missing required argument: --lower", .{});
        try printHelp();
        return error.MissingLower;
    };

    // Load config file if specified
    var app_config: ?std.json.Parsed(AppConfig) = null;
    defer if (app_config) |*cfg| cfg.deinit();

    const config_path = res.args.config;
    if (config_path) |path| {
        try logger.info("Loading config from: {s}", .{path});
        if (ConfigLoader.load(allocator, path, AppConfig)) |parsed| {
            app_config = parsed;
            try logger.info("Config loaded successfully", .{});
        } else |err| {
            try logger.warn("Failed to load config file: {s} - using defaults", .{@errorName(err)});
        }
    }

    // Parse trading pair
    var pair_parts = std.mem.splitScalar(u8, pair_str, '-');
    const base = pair_parts.next() orelse return error.InvalidPair;
    const quote = pair_parts.next() orelse "USDC";
    const pair = TradingPair{ .base = base, .quote = quote };

    // Parse prices
    const upper_price = try Decimal.fromString(upper_str);
    const lower_price = try Decimal.fromString(lower_str);

    // Parse optional arguments
    const grid_count: u32 = if (res.args.grids) |s|
        try std.fmt.parseInt(u32, s, 10)
    else
        10;

    const order_size = if (res.args.size) |s|
        try Decimal.fromString(s)
    else
        Decimal.fromFloat(0.001);

    const take_profit_pct: f64 = if (res.args.tp) |s|
        try std.fmt.parseFloat(f64, s)
    else
        0.5;

    const max_position = if (res.args.@"max-position") |s|
        try Decimal.fromString(s)
    else
        Decimal.fromFloat(1.0);

    const interval_ms: u64 = if (res.args.interval) |s|
        try std.fmt.parseInt(u64, s, 10)
    else
        5000;

    const duration_minutes: u64 = if (res.args.duration) |s|
        try std.fmt.parseInt(u64, s, 10)
    else
        0;

    const risk_enabled = res.args.@"no-risk" == 0;

    // Determine trading mode
    const mode: TradingMode = if (res.args.live != 0)
        .mainnet
    else if (res.args.testnet != 0)
        .testnet
    else
        .paper;

    // Create grid config
    const config = GridConfig{
        .pair = pair,
        .upper_price = upper_price,
        .lower_price = lower_price,
        .grid_count = grid_count,
        .order_size = order_size,
        .take_profit_pct = take_profit_pct,
        .enable_long = true,
        .enable_short = false,
        .max_position = max_position,
    };

    try config.validate();

    // Get trading config from loaded config or use defaults
    const trading_max_position_size: f64 = if (app_config) |cfg|
        cfg.value.trading.max_position_size
    else
        1000.0;

    const trading_risk_limit: f64 = if (app_config) |cfg|
        cfg.value.trading.risk_limit
    else
        0.02;

    // Print configuration
    try logger.info("", .{});
    try logger.info("╔════════════════════════════════════════════════════╗", .{});
    try logger.info("║           zigQuant Grid Trading Bot                ║", .{});
    try logger.info("╚════════════════════════════════════════════════════╝", .{});
    try logger.info("", .{});
    try logger.info("Configuration:", .{});
    try logger.info("  Trading Pair:     {s}-{s}", .{ pair.base, pair.quote });
    try logger.info("  Price Range:      {d:.2} - {d:.2}", .{ lower_price.toFloat(), upper_price.toFloat() });
    try logger.info("  Grid Count:       {}", .{grid_count});
    try logger.info("  Grid Interval:    {d:.2}", .{config.gridInterval().toFloat()});
    try logger.info("  Order Size:       {d:.6}", .{order_size.toFloat()});
    try logger.info("  Take Profit:      {d:.2}%", .{take_profit_pct});
    try logger.info("  Max Position:     {d:.4}", .{max_position.toFloat()});
    try logger.info("  Check Interval:   {}ms", .{interval_ms});
    try logger.info("  Mode:             {s}", .{@tagName(mode)});
    try logger.info("  Risk Management:  {s}", .{if (risk_enabled) "enabled" else "disabled"});
    if (config_path != null) {
        try logger.info("  Config File:      {s}", .{config_path.?});
    }
    try logger.info("", .{});

    // Warnings for live trading
    if (mode == .mainnet) {
        try logger.warn("╔════════════════════════════════════════════════════╗", .{});
        try logger.warn("║  WARNING: LIVE TRADING MODE (MAINNET)              ║", .{});
        try logger.warn("║  Real money is at risk!                            ║", .{});
        try logger.warn("╚════════════════════════════════════════════════════╝", .{});
        try logger.info("", .{});
    } else if (mode == .testnet) {
        try logger.info("Running on Hyperliquid TESTNET (no real money)", .{});
        try logger.info("", .{});
    } else {
        try logger.info("Running in PAPER TRADING mode (simulated)", .{});
        try logger.info("", .{});
    }

    // Create grid bot
    var bot = try GridBot.init(allocator, logger, config, mode);
    defer bot.deinit();

    // Initialize risk management if enabled
    if (risk_enabled) {
        try bot.initRiskManagement(
            Decimal.fromFloat(trading_max_position_size),
            trading_risk_limit,
        );
    } else {
        bot.risk_enabled = false;
    }

    // Connect to exchange if not paper trading
    if (mode != .paper) {
        // Try to get credentials from config file first, then CLI args, then env vars
        var wallet: ?[]const u8 = res.args.wallet;
        var private_key: ?[]const u8 = res.args.key;

        // Try to load from config file
        if (app_config) |cfg| {
            if (cfg.value.getExchange("hyperliquid")) |exchange_cfg| {
                if (wallet == null and exchange_cfg.api_key.len > 0) {
                    wallet = exchange_cfg.api_key;
                    try logger.info("Using wallet from config file", .{});
                }
                if (private_key == null and exchange_cfg.api_secret.len > 0) {
                    private_key = exchange_cfg.api_secret;
                    try logger.info("Using private key from config file", .{});
                }
            }
        }

        // Fall back to environment variables
        if (wallet == null) {
            wallet = std.posix.getenv("ZIGQUANT_WALLET");
        }
        if (private_key == null) {
            private_key = std.posix.getenv("ZIGQUANT_PRIVATE_KEY");
        }

        // Check if we have credentials
        const final_wallet = wallet orelse {
            try logger.err("Missing wallet address. Use --wallet, --config, or set ZIGQUANT_WALLET", .{});
            return error.MissingWallet;
        };

        const final_key = private_key orelse {
            try logger.err("Missing private key. Use --key, --config, or set ZIGQUANT_PRIVATE_KEY", .{});
            return error.MissingPrivateKey;
        };

        try bot.connect(final_wallet, final_key, mode == .testnet);
    }

    // Place initial orders
    try logger.info("Placing initial grid orders...", .{});
    try bot.placeInitialOrders();
    try bot.printStatus();

    // Main loop
    try logger.info("Starting grid bot main loop...", .{});
    try logger.info("Press Ctrl+C to stop", .{});
    try logger.info("", .{});

    const start_time = std.time.milliTimestamp();
    const end_time: i64 = if (duration_minutes > 0)
        start_time + @as(i64, @intCast(duration_minutes * 60 * 1000))
    else
        std.math.maxInt(i64);

    var iteration: u64 = 0;
    while (std.time.milliTimestamp() < end_time) {
        iteration += 1;

        // Run one iteration
        try bot.tick();

        // Print status every 10 iterations
        if (iteration % 10 == 0) {
            try bot.printStatus();
        }

        // Sleep until next check
        std.Thread.sleep(interval_ms * std.time.ns_per_ms);
    }

    // Cleanup
    try logger.info("", .{});
    try logger.info("Grid bot stopped. Cancelling remaining orders...", .{});
    try bot.cancelAllOrders();

    // Final summary
    try logger.info("", .{});
    try logger.info("╔════════════════════════════════════════════════════╗", .{});
    try logger.info("║           Final Summary                            ║", .{});
    try logger.info("╚════════════════════════════════════════════════════╝", .{});
    try logger.info("Total Trades:     {}", .{bot.trades_count});
    try logger.info("Total Bought:     {d:.6}", .{bot.total_bought.toFloat()});
    try logger.info("Total Sold:       {d:.6}", .{bot.total_sold.toFloat()});
    try logger.info("Final Position:   {d:.6}", .{bot.current_position.toFloat()});
    try logger.info("Realized PnL:     {d:.4}", .{bot.realized_pnl.toFloat()});

    // Risk management summary
    if (bot.risk_engine) |re| {
        const stats = re.getStats();
        try logger.info("───────────────────────────────────────────────", .{});
        try logger.info("Risk Management:", .{});
        try logger.info("  Total Risk Checks:    {}", .{stats.total_checks});
        try logger.info("  Orders Rejected:      {}", .{stats.rejected_orders});
        try logger.info("  Rejection Rate:       {d:.2}%", .{stats.rejection_rate * 100});
        try logger.info("  Kill Switch Triggers: {}", .{stats.kill_switch_triggers});
    }

    try logger.info("", .{});
}

// ============================================================================
// Help
// ============================================================================

fn printHelp() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\
        \\Grid Trading Command - Automated grid trading bot
        \\
        \\USAGE:
        \\    zigquant grid [OPTIONS]
        \\
        \\REQUIRED:
        \\    -p, --pair <pair>         Trading pair (e.g., BTC-USDC)
        \\        --upper <price>       Upper price bound
        \\        --lower <price>       Lower price bound
        \\
        \\GRID OPTIONS:
        \\    -g, --grids <count>       Number of grid levels (default: 10)
        \\    -s, --size <amount>       Order size per grid (default: 0.001)
        \\        --tp <percent>        Take profit % per grid (default: 0.5)
        \\        --max-position <amt>  Maximum total position (default: 1.0)
        \\
        \\MODE:
        \\        --paper               Paper trading mode (simulated, default)
        \\        --testnet             Live trading on Hyperliquid testnet
        \\        --live                Live trading on mainnet (CAUTION!)
        \\
        \\CONFIG & CREDENTIALS:
        \\        --config <file>       Config file path (e.g., config.test.json)
        \\        --wallet <address>    Wallet address (0x...)
        \\        --key <privatekey>    Private key (without 0x prefix)
        \\
        \\    Config file format (JSON):
        \\        {
        \\          "exchanges": [{
        \\            "name": "hyperliquid",
        \\            "api_key": "0x...",      // wallet address
        \\            "api_secret": "...",     // private key
        \\            "testnet": true
        \\          }],
        \\          "trading": {
        \\            "max_position_size": 1000.0,
        \\            "risk_limit": 0.02
        \\          }
        \\        }
        \\
        \\    Priority: CLI args > config file > environment variables
        \\
        \\    Environment variables:
        \\        ZIGQUANT_WALLET       Your wallet address
        \\        ZIGQUANT_PRIVATE_KEY  Your private key
        \\
        \\RISK MANAGEMENT:
        \\        --no-risk             Disable risk management checks
        \\
        \\    Risk features (enabled by default):
        \\        - Position size limits from config
        \\        - Daily loss limit enforcement
        \\        - Order rate limiting
        \\        - Kill switch on excessive losses
        \\        - Real-time alerts on risk events
        \\
        \\OTHER OPTIONS:
        \\        --interval <ms>       Check interval in milliseconds (default: 5000)
        \\        --duration <minutes>  Run duration, 0 for infinite (default: 0)
        \\    -h, --help                Display this help message
        \\
        \\EXAMPLES:
        \\    # Paper trading (simulated)
        \\    zigquant grid --pair BTC-USDC --upper 100000 --lower 90000 --grids 10
        \\
        \\    # Testnet trading with config file (recommended)
        \\    zigquant grid --config config.test.json -p BTC-USDC \
        \\                  --upper 100000 --lower 90000 -g 10 --testnet
        \\
        \\    # Testnet trading with explicit credentials
        \\    zigquant grid -p BTC-USDC --upper 100000 --lower 90000 -g 10 -s 0.01 \
        \\                  --testnet --wallet 0x... --key abc123...
        \\
        \\    # Live trading with custom take profit (CAUTION!)
        \\    zigquant grid -p ETH-USDC --upper 4000 --lower 3500 -g 20 --tp 0.3 --live
        \\
        \\HOW IT WORKS:
        \\    1. Divides price range into equal grid levels
        \\    2. Places buy orders at levels below current price
        \\    3. When a buy fills, places a sell order at entry + take_profit%
        \\    4. When a sell fills, places a new buy order at the original level
        \\    5. Profits from price oscillations within the grid
        \\
        \\BEST SUITED FOR:
        \\    - Range-bound/sideways markets
        \\    - High volatility within a range
        \\    - Pairs with good liquidity
        \\
        \\
    );
}
