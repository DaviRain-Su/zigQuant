//! Live Trading Command
//!
//! Run live trading with configurable strategy on Hyperliquid.
//! Strategy selection and all configuration is read from config file.
//!
//! Supported strategies:
//! - grid: Grid trading strategy
//! - (more to come: momentum, mean_reversion, etc.)
//!
//! Usage:
//! ```bash
//! # Live trading on testnet (default)
//! zigquant live --config config.json
//!
//! # Live trading on mainnet
//! zigquant live --config config.json --mainnet
//! ```

const std = @import("std");
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
const LiveTradingConfig = zigQuant.LiveTradingConfig;
const ConfigGridParams = zigQuant.ConfigGridParams;
const RiskEngine = zigQuant.RiskEngine;
const RiskEngineConfig = zigQuant.RiskEngineConfig;
const RiskCheckResult = zigQuant.RiskCheckResult;
const AlertManager = zigQuant.AlertManager;
const AlertConfig = zigQuant.AlertConfig;
const AlertCategory = zigQuant.AlertCategory;
const AlertDetails = zigQuant.AlertDetails;
const ConsoleChannel = zigQuant.ConsoleChannel;
const Account = zigQuant.Account;

// ============================================================================
// Strategy Type
// ============================================================================

const StrategyType = enum {
    grid,
    // Future strategies can be added here
    // momentum,
    // mean_reversion,
    // breakout,

    pub fn fromString(s: []const u8) ?StrategyType {
        if (std.mem.eql(u8, s, "grid")) return .grid;
        // if (std.mem.eql(u8, s, "momentum")) return .momentum;
        return null;
    }

    pub fn toString(self: StrategyType) []const u8 {
        return switch (self) {
            .grid => "grid",
        };
    }
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
        pending,
        active,
        filled,
        cancelled,
    };
};

// ============================================================================
// Live Strategy Runner
// ============================================================================

const LiveStrategyRunner = struct {
    allocator: std.mem.Allocator,
    logger: *Logger,
    strategy_type: StrategyType,
    live_config: LiveTradingConfig,

    // Exchange connection
    connector: ?*HyperliquidConnector = null,
    pair: TradingPair,

    // Grid state (used when strategy = grid)
    grid_config: ?GridConfig = null,
    grid_levels: ?[]GridLevel = null,
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
    orders_rejected_by_risk: u32 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: *Logger,
        live_config: LiveTradingConfig,
        strategy_type: StrategyType,
        pair: TradingPair,
    ) !*LiveStrategyRunner {
        const self = try allocator.create(LiveStrategyRunner);
        errdefer allocator.destroy(self);

        const buy_orders = try std.ArrayList(GridOrderState).initCapacity(allocator, 32);
        const sell_orders = try std.ArrayList(GridOrderState).initCapacity(allocator, 32);

        self.* = .{
            .allocator = allocator,
            .logger = logger,
            .strategy_type = strategy_type,
            .live_config = live_config,
            .pair = pair,
            .buy_orders = buy_orders,
            .sell_orders = sell_orders,
            .account = Account.init(),
        };

        return self;
    }

    pub fn deinit(self: *LiveStrategyRunner) void {
        self.buy_orders.deinit(self.allocator);
        self.sell_orders.deinit(self.allocator);
        if (self.grid_levels) |levels| {
            self.allocator.free(levels);
        }
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

    /// Initialize grid strategy specific state
    pub fn initGridStrategy(self: *LiveStrategyRunner) !void {
        const grid = self.live_config.grid;

        const strategy_config = GridConfig{
            .pair = self.pair,
            .upper_price = Decimal.fromFloat(grid.upper_price),
            .lower_price = Decimal.fromFloat(grid.lower_price),
            .grid_count = grid.grid_count,
            .order_size = Decimal.fromFloat(self.live_config.order_size),
            .take_profit_pct = grid.take_profit_pct,
            .enable_long = grid.enable_long,
            .enable_short = grid.enable_short,
            .max_position = Decimal.fromFloat(self.live_config.max_position),
        };

        try strategy_config.validate();
        self.grid_config = strategy_config;

        // Initialize grid levels
        const grid_levels = try self.allocator.alloc(GridLevel, grid.grid_count + 1);
        for (0..grid.grid_count + 1) |i| {
            const level: u32 = @intCast(i);
            grid_levels[i] = GridLevel{
                .level = level,
                .price = strategy_config.priceAtLevel(level),
            };
        }
        self.grid_levels = grid_levels;
    }

    /// Initialize risk management
    pub fn initRiskManagement(self: *LiveStrategyRunner, max_position_size: Decimal, risk_limit: f64) !void {
        self.account.cross_margin_summary.account_value = Decimal.fromFloat(10000);

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

        const risk_engine = try self.allocator.create(RiskEngine);
        risk_engine.* = RiskEngine.init(self.allocator, risk_config, null, &self.account);
        self.risk_engine = risk_engine;

        const alert_manager = try self.allocator.create(AlertManager);
        alert_manager.* = AlertManager.init(self.allocator, AlertConfig.default());
        self.alert_manager = alert_manager;

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

    fn checkRisk(self: *LiveStrategyRunner, order_request: OrderRequest) bool {
        if (!self.risk_enabled) return true;

        if (self.risk_engine) |re| {
            const result = re.checkOrder(order_request);
            if (!result.passed) {
                self.orders_rejected_by_risk += 1;
                self.logger.warn("[RISK] Order rejected: {s}", .{result.message orelse "Unknown reason"}) catch {};

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

    fn sendTradeAlert(self: *LiveStrategyRunner, category: AlertCategory, symbol: []const u8, price: Decimal, quantity: Decimal, pnl: ?Decimal) void {
        if (self.alert_manager) |am| {
            am.tradeAlert(category, .{
                .symbol = symbol,
                .price = price,
                .quantity = quantity,
                .pnl = pnl,
            }) catch {};
        }
    }

    /// Connect to exchange
    pub fn connect(self: *LiveStrategyRunner, wallet: []const u8, private_key: []const u8, testnet: bool) !void {
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
    pub fn getCurrentPrice(self: *LiveStrategyRunner) !Decimal {
        if (self.connector) |conn| {
            const exchange = conn.interface();
            const ticker = try exchange.getTicker(self.pair);
            const mid_price = ticker.bid.add(ticker.ask).div(Decimal.fromInt(2)) catch ticker.last;
            self.last_price = mid_price;
            return mid_price;
        }
        return error.NotConnected;
    }

    /// Place initial orders based on strategy type
    pub fn placeInitialOrders(self: *LiveStrategyRunner) !void {
        switch (self.strategy_type) {
            .grid => try self.placeGridInitialOrders(),
        }
    }

    fn placeGridInitialOrders(self: *LiveStrategyRunner) !void {
        const current_price = try self.getCurrentPrice();
        try self.logger.info("Current price: {d:.2}", .{current_price.toFloat()});

        const levels = self.grid_levels orelse return error.GridNotInitialized;

        var buy_count: u32 = 0;
        var sell_count: u32 = 0;

        for (levels) |*level| {
            if (level.price.cmp(current_price) == .lt) {
                try self.placeBuyOrder(level);
                buy_count += 1;
            } else {
                sell_count += 1;
            }
        }

        try self.logger.info("Initial setup: {} buy orders below price, {} potential sell levels above", .{
            buy_count,
            sell_count,
        });
    }

    fn placeBuyOrder(self: *LiveStrategyRunner, level: *GridLevel) !void {
        const config = self.grid_config orelse return error.GridNotInitialized;

        if (self.connector) |conn| {
            const exchange = conn.interface();

            const order_request = OrderRequest{
                .pair = self.pair,
                .side = .buy,
                .order_type = .limit,
                .amount = config.order_size,
                .price = level.price,
                .time_in_force = .gtc,
                .reduce_only = false,
            };

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

            self.sendTradeAlert(.trade_executed, self.pair.base, level.price, config.order_size, null);
        }
    }

    fn placeSellOrder(self: *LiveStrategyRunner, level: *GridLevel, entry_price: Decimal) !void {
        const config = self.grid_config orelse return error.GridNotInitialized;
        const tp_price = entry_price.mul(Decimal.fromFloat(1.0 + config.take_profit_pct / 100.0));

        if (self.connector) |conn| {
            const exchange = conn.interface();

            const order_request = OrderRequest{
                .pair = self.pair,
                .side = .sell,
                .order_type = .limit,
                .amount = config.order_size,
                .price = tp_price,
                .time_in_force = .gtc,
                .reduce_only = false,
            };

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

            self.sendTradeAlert(.trade_executed, self.pair.base, tp_price, config.order_size, null);
        }
    }

    /// Main tick
    pub fn tick(self: *LiveStrategyRunner) !void {
        _ = try self.getCurrentPrice();
        try self.checkRealFills();
    }

    fn checkRealFills(self: *LiveStrategyRunner) !void {
        if (self.connector == null) return;
        try self.logger.debug("Checking order status...", .{});
    }

    /// Print status
    pub fn printStatus(self: *LiveStrategyRunner) !void {
        try self.logger.info("", .{});
        try self.logger.info("===========================================", .{});
        try self.logger.info("      Live Strategy Runner Status", .{});
        try self.logger.info("===========================================", .{});
        try self.logger.info("Strategy:         {s}", .{self.strategy_type.toString()});
        try self.logger.info("Current Price:    {d:.2}", .{self.last_price.toFloat()});
        try self.logger.info("Position:         {d:.6}", .{self.current_position.toFloat()});
        try self.logger.info("Active Buy Orders:  {}", .{self.countActiveOrders(.buy)});
        try self.logger.info("Active Sell Orders: {}", .{self.countActiveOrders(.sell)});
        try self.logger.info("Total Trades:     {}", .{self.trades_count});
        try self.logger.info("Realized PnL:     {d:.4}", .{self.realized_pnl.toFloat()});

        if (self.risk_engine) |re| {
            const stats = re.getStats();
            try self.logger.info("-------------------------------------------", .{});
            try self.logger.info("Risk Checks:      {}", .{stats.total_checks});
            try self.logger.info("Orders Rejected:  {}", .{stats.rejected_orders});
            try self.logger.info("Kill Switch:      {s}", .{if (stats.kill_switch_active) "ACTIVE" else "off"});
        }

        try self.logger.info("===========================================", .{});
        try self.logger.info("", .{});
    }

    fn countActiveOrders(self: *LiveStrategyRunner, side: Side) usize {
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
    pub fn cancelAllOrders(self: *LiveStrategyRunner) !void {
        if (self.connector) |conn| {
            const exchange = conn.interface();
            const cancelled = try exchange.cancelAllOrders(self.pair);
            try self.logger.info("Cancelled {} orders", .{cancelled});
        }
        self.buy_orders.clearRetainingCapacity();
        self.sell_orders.clearRetainingCapacity();
    }
};

// ============================================================================
// Main Command
// ============================================================================

pub fn cmdLive(
    allocator: std.mem.Allocator,
    logger: *Logger,
    args: []const []const u8,
) !void {
    // Parse arguments
    var config_path: []const u8 = "config.json";
    var mainnet_mode = false;
    var show_help = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            i += 1;
            if (i < args.len) {
                config_path = args[i];
            }
        } else if (std.mem.eql(u8, arg, "--mainnet")) {
            mainnet_mode = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        }
    }

    if (show_help) {
        try printHelp();
        return;
    }

    // Load configuration from file (REQUIRED - no env vars fallback)
    try logger.info("Loading configuration from: {s}", .{config_path});
    const app_config = ConfigLoader.load(allocator, config_path, AppConfig) catch |err| {
        try logger.err("Failed to load config file: {s}", .{@errorName(err)});
        try logger.err("All configuration must be in the config file.", .{});
        return error.ConfigNotFound;
    };
    defer app_config.deinit();

    // Get live trading configuration (REQUIRED)
    const live_config = app_config.value.live orelse {
        try logger.err("Missing 'live' section in config file", .{});
        try logger.err("Please add live trading configuration to your config file.", .{});
        try printConfigExample();
        return error.MissingLiveConfig;
    };

    // Parse strategy type
    const strategy_type = StrategyType.fromString(live_config.strategy) orelse {
        try logger.err("Unknown strategy type: {s}", .{live_config.strategy});
        try logger.err("Supported strategies: grid", .{});
        return error.UnknownStrategy;
    };

    // Get exchange configuration (REQUIRED)
    const exchange_cfg = app_config.value.getExchange("hyperliquid") orelse {
        try logger.err("Missing 'hyperliquid' exchange configuration", .{});
        try logger.err("Please add exchange credentials to your config file.", .{});
        return error.MissingExchangeConfig;
    };

    // Validate credentials
    if (exchange_cfg.api_key.len == 0) {
        try logger.err("Missing wallet address (api_key) in exchange config", .{});
        return error.MissingCredentials;
    }
    if (exchange_cfg.api_secret.len == 0) {
        try logger.err("Missing private key (api_secret) in exchange config", .{});
        return error.MissingCredentials;
    }

    // Determine mode - CLI flag overrides config
    const use_testnet = if (mainnet_mode) false else live_config.testnet;

    // Parse trading pair
    var pair_parts = std.mem.splitScalar(u8, live_config.pair, '-');
    const base = pair_parts.next() orelse return error.InvalidPair;
    const quote = pair_parts.next() orelse "USDC";
    const pair = TradingPair{ .base = base, .quote = quote };

    // Print configuration
    try logger.info("", .{});
    try logger.info("========================================================", .{});
    try logger.info("           zigQuant Live Trading", .{});
    try logger.info("========================================================", .{});
    try logger.info("", .{});
    try logger.info("Configuration:", .{});
    try logger.info("  Config File:      {s}", .{config_path});
    try logger.info("  Strategy:         {s}", .{strategy_type.toString()});
    try logger.info("  Trading Pair:     {s}-{s}", .{ pair.base, pair.quote });
    try logger.info("  Order Size:       {d:.6}", .{live_config.order_size});
    try logger.info("  Max Position:     {d:.4}", .{live_config.max_position});
    try logger.info("  Check Interval:   {}ms", .{live_config.interval_ms});
    try logger.info("  Mode:             {s}", .{if (use_testnet) "TESTNET" else "MAINNET"});
    try logger.info("  Risk Management:  {s}", .{if (live_config.risk_enabled) "enabled" else "disabled"});

    // Print strategy-specific config
    switch (strategy_type) {
        .grid => {
            const grid = live_config.grid;
            try logger.info("", .{});
            try logger.info("Grid Strategy Config:", .{});
            try logger.info("  Price Range:      {d:.2} - {d:.2}", .{ grid.lower_price, grid.upper_price });
            try logger.info("  Grid Count:       {}", .{grid.grid_count});
            try logger.info("  Take Profit:      {d:.2}%", .{grid.take_profit_pct});
            try logger.info("  Enable Long:      {}", .{grid.enable_long});
            try logger.info("  Enable Short:     {}", .{grid.enable_short});
        },
    }
    try logger.info("", .{});

    // Warnings
    if (!use_testnet) {
        try logger.warn("========================================================", .{});
        try logger.warn("  WARNING: LIVE TRADING MODE (MAINNET)", .{});
        try logger.warn("  Real money is at risk!", .{});
        try logger.warn("========================================================", .{});
        try logger.info("", .{});
    } else {
        try logger.info("Running on Hyperliquid TESTNET (no real money)", .{});
        try logger.info("", .{});
    }

    // Create runner
    var runner = try LiveStrategyRunner.init(allocator, logger, live_config, strategy_type, pair);
    defer runner.deinit();

    // Initialize strategy-specific state
    switch (strategy_type) {
        .grid => try runner.initGridStrategy(),
    }

    // Initialize risk management
    if (live_config.risk_enabled) {
        try runner.initRiskManagement(
            Decimal.fromFloat(app_config.value.trading.max_position_size),
            app_config.value.trading.risk_limit,
        );
    } else {
        runner.risk_enabled = false;
    }

    // Connect to exchange
    try runner.connect(exchange_cfg.api_key, exchange_cfg.api_secret, use_testnet);

    // Place initial orders
    try logger.info("Placing initial orders...", .{});
    try runner.placeInitialOrders();
    try runner.printStatus();

    // Main loop
    try logger.info("Starting live trading main loop...", .{});
    try logger.info("Press Ctrl+C to stop", .{});
    try logger.info("", .{});

    const start_time = std.time.milliTimestamp();
    const end_time: i64 = if (live_config.duration_minutes > 0)
        start_time + @as(i64, @intCast(live_config.duration_minutes * 60 * 1000))
    else
        std.math.maxInt(i64);

    var iteration: u64 = 0;
    while (std.time.milliTimestamp() < end_time) {
        iteration += 1;

        try runner.tick();

        if (iteration % 10 == 0) {
            try runner.printStatus();
        }

        std.Thread.sleep(live_config.interval_ms * std.time.ns_per_ms);
    }

    // Cleanup
    try logger.info("", .{});
    try logger.info("Live trading stopped. Cancelling remaining orders...", .{});
    try runner.cancelAllOrders();

    // Final summary
    try logger.info("", .{});
    try logger.info("========================================================", .{});
    try logger.info("           Final Summary", .{});
    try logger.info("========================================================", .{});
    try logger.info("Strategy:         {s}", .{strategy_type.toString()});
    try logger.info("Total Trades:     {}", .{runner.trades_count});
    try logger.info("Total Bought:     {d:.6}", .{runner.total_bought.toFloat()});
    try logger.info("Total Sold:       {d:.6}", .{runner.total_sold.toFloat()});
    try logger.info("Final Position:   {d:.6}", .{runner.current_position.toFloat()});
    try logger.info("Realized PnL:     {d:.4}", .{runner.realized_pnl.toFloat()});

    if (runner.risk_engine) |re| {
        const stats = re.getStats();
        try logger.info("-----------------------------------------------", .{});
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
        \\Live Trading Command - Run live trading with configurable strategy
        \\
        \\Strategy is selected through config file. All configuration is read from
        \\config file (no environment variables).
        \\
        \\USAGE:
        \\    zigquant live [OPTIONS]
        \\
        \\OPTIONS:
        \\    -c, --config <file>   Config file path (default: config.json) [REQUIRED]
        \\        --mainnet         Use mainnet instead of testnet
        \\    -h, --help            Display this help message
        \\
        \\SUPPORTED STRATEGIES:
        \\    grid       Grid trading strategy
        \\    (more coming soon: momentum, mean_reversion, breakout)
        \\
        \\CONFIG FILE FORMAT:
        \\    See below for required configuration sections.
        \\
        \\EXAMPLES:
        \\    # Live trading on testnet (default)
        \\    zigquant live --config config.json
        \\
        \\    # Live trading on mainnet
        \\    zigquant live --config config.json --mainnet
        \\
        \\
    );
}

fn printConfigExample() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\
        \\REQUIRED CONFIG FILE FORMAT:
        \\
        \\{
        \\  "exchanges": [
        \\    {
        \\      "name": "hyperliquid",
        \\      "api_key": "0x...",      // wallet address
        \\      "api_secret": "...",     // private key
        \\      "testnet": true
        \\    }
        \\  ],
        \\  "trading": {
        \\    "max_position_size": 1000.0,
        \\    "leverage": 1,
        \\    "risk_limit": 0.02
        \\  },
        \\  "live": {
        \\    "strategy": "grid",        // Strategy to run: grid, momentum, etc.
        \\    "pair": "BTC-USDC",
        \\    "order_size": 0.001,
        \\    "max_position": 1.0,
        \\    "interval_ms": 5000,
        \\    "duration_minutes": 0,     // 0 = run forever
        \\    "risk_enabled": true,
        \\    "testnet": true,
        \\    "grid": {                  // Grid strategy specific config
        \\      "upper_price": 100000.0,
        \\      "lower_price": 90000.0,
        \\      "grid_count": 10,
        \\      "take_profit_pct": 0.5,
        \\      "enable_long": true,
        \\      "enable_short": false
        \\    }
        \\  }
        \\}
        \\
        \\
    );
}
