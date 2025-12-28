//! Run-Strategy Command
//!
//! Execute trading strategies in live or paper trading mode.
//!
//! Usage:
//! ```bash
//! # Paper trading (simulated)
//! zigquant run-strategy --strategy dual_ma --config config.json --paper
//!
//! # Live trading (requires exchange API keys)
//! zigquant run-strategy --strategy dual_ma --config config.json --live
//! ```

const std = @import("std");
const clap = @import("clap");
const zigQuant = @import("zigQuant");

const Decimal = zigQuant.Decimal;
const TradingPair = zigQuant.TradingPair;
const Timestamp = zigQuant.Timestamp;
const Timeframe = zigQuant.Timeframe;
const Logger = zigQuant.Logger;
const StrategyFactory = zigQuant.StrategyFactory;
const MessageBus = zigQuant.MessageBus;
const Cache = zigQuant.Cache;
const ExecutionEngine = zigQuant.ExecutionEngine;
const SimulatedExecutor = zigQuant.SimulatedExecutor;
const SimulatedAccount = zigQuant.SimulatedAccount;
const Side = zigQuant.Side;
const OrderType = zigQuant.OrderType;
const Candle = zigQuant.Candle;
const Candles = zigQuant.Candles;
const RiskConfig = zigQuant.RiskConfig;
const ExecOrderRequest = zigQuant.ExecOrderRequest;
const HistoricalDataFeed = zigQuant.HistoricalDataFeed;

// Strategy interface
const StrategyContext = zigQuant.strategy_interface.StrategyContext;
const Signal = zigQuant.strategy_interface.Signal;
const SignalType = zigQuant.strategy_interface.SignalType;

// ============================================================================
// CLI Parameters
// ============================================================================

const params = clap.parseParamsComptime(
    \\-h, --help                Display help
    \\-s, --strategy <str>      Strategy name (dual_ma, rsi_mean_reversion, bollinger_breakout)
    \\-c, --config <str>        Strategy config JSON file (required)
    \\    --live                Run in live trading mode (requires API keys)
    \\    --paper               Run in paper trading mode (simulated, default)
    \\    --capital <str>       Initial capital for paper trading (default: 10000)
    \\    --interval <str>      Update interval in seconds (default: 60)
    \\    --duration <str>      Run duration in minutes, 0 for infinite (default: 0)
    \\
);

// ============================================================================
// Trading Mode
// ============================================================================

const TradingMode = enum {
    paper,
    live,
};

// ============================================================================
// Main Command
// ============================================================================

pub fn cmdRunStrategy(
    allocator: std.mem.Allocator,
    logger: *Logger,
    args: []const []const u8,
) !void {
    // Parse arguments using SliceIterator
    var diag = clap.Diagnostic{};
    var iter = clap.args.SliceIterator{ .args = args };
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, &iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try logger.err("Failed to parse arguments: {s}", .{@errorName(err)});
        if (diag.arg.len > 0) {
            try logger.err("  Problem with argument: {s}", .{diag.arg});
        }
        try logger.info("Use --help for usage information", .{});
        return err;
    };
    defer res.deinit();

    // Show help if requested
    if (res.args.help != 0) {
        try printHelp();
        return;
    }

    // Validate required arguments
    const strategy_name = res.args.strategy orelse {
        try logger.err("Missing required argument: --strategy", .{});
        try logger.info("Use --help for usage information", .{});
        return error.MissingStrategy;
    };

    const config_path = res.args.config orelse {
        try logger.err("Missing required argument: --config", .{});
        try logger.info("Use --help for usage information", .{});
        return error.MissingConfig;
    };

    // Determine trading mode
    const mode: TradingMode = if (res.args.live != 0) .live else .paper;

    // Parse optional parameters
    const initial_capital = if (res.args.capital) |s|
        try Decimal.fromString(s)
    else
        try Decimal.fromString("10000");

    const update_interval: u64 = if (res.args.interval) |s|
        try std.fmt.parseInt(u64, s, 10)
    else
        60; // 60 seconds default

    const duration_minutes: u64 = if (res.args.duration) |s|
        try std.fmt.parseInt(u64, s, 10)
    else
        0; // infinite

    try logger.info("╔════════════════════════════════════════════════════╗", .{});
    try logger.info("║           zigQuant Run-Strategy Command            ║", .{});
    try logger.info("╚════════════════════════════════════════════════════╝", .{});
    try logger.info("", .{});
    try logger.info("Strategy:  {s}", .{strategy_name});
    try logger.info("Config:    {s}", .{config_path});
    try logger.info("Mode:      {s}", .{if (mode == .live) "LIVE TRADING" else "Paper Trading"});
    try logger.info("Capital:   {}", .{initial_capital});
    try logger.info("Interval:  {d}s", .{update_interval});
    try logger.info("Duration:  {s}", .{if (duration_minutes == 0) "Infinite" else ""});
    if (duration_minutes > 0) {
        try logger.info("           {d} minutes", .{duration_minutes});
    }
    try logger.info("", .{});

    // Live trading warning
    if (mode == .live) {
        try logger.warn("╔════════════════════════════════════════════════════╗", .{});
        try logger.warn("║  WARNING: LIVE TRADING MODE                        ║", .{});
        try logger.warn("║  Real money is at risk!                            ║", .{});
        try logger.warn("╚════════════════════════════════════════════════════╝", .{});
        try logger.info("", .{});
        try logger.info("Live trading requires Hyperliquid API keys.", .{});
        try logger.info("Please set environment variables:", .{});
        try logger.info("  ZIGQUANT_EXCHANGES_0_API_KEY=<your_key>", .{});
        try logger.info("  ZIGQUANT_EXCHANGES_0_API_SECRET=<your_secret>", .{});
        try logger.info("", .{});

        // Check for API keys
        if (std.posix.getenv("ZIGQUANT_EXCHANGES_0_API_KEY") == null) {
            try logger.err("Missing API key. Live trading not possible.", .{});
            return error.MissingApiKey;
        }
    }

    // Load configuration
    try logger.info("Loading configuration...", .{});
    const config_json = std.fs.cwd().readFileAlloc(
        allocator,
        config_path,
        1024 * 1024, // 1MB max
    ) catch |err| {
        try logger.err("Failed to read config file: {s}", .{@errorName(err)});
        return error.ConfigLoadFailed;
    };
    defer allocator.free(config_json);

    // Parse config to get pair and timeframe
    const parsed_config = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        config_json,
        .{},
    ) catch |err| {
        try logger.err("Failed to parse config JSON: {s}", .{@errorName(err)});
        return error.InvalidConfig;
    };
    defer parsed_config.deinit();

    const pair = try parseTradingPair(parsed_config.value, "pair");
    const timeframe = try parseTimeframe(parsed_config.value, "timeframe");

    try logger.info("Trading pair: {s}-{s}", .{ pair.base, pair.quote });
    try logger.info("Timeframe:    {s}", .{@tagName(timeframe)});
    try logger.info("", .{});

    // Create strategy
    try logger.info("Creating strategy instance...", .{});
    var factory = StrategyFactory.init(allocator);
    var strategy_wrapper = factory.create(strategy_name, config_json) catch |err| {
        try logger.err("Failed to create strategy: {s}", .{@errorName(err)});
        if (err == error.UnknownStrategy) {
            try logger.info("", .{});
            try logger.info("Available strategies:", .{});
            const strategies = factory.listStrategies();
            for (strategies) |s| {
                try logger.info("  - {s:<25} {s}", .{ s.name, s.description });
            }
        }
        return err;
    };
    defer strategy_wrapper.deinit();

    const strategy = strategy_wrapper.interface;
    const ctx = StrategyContext{
        .allocator = allocator,
        .logger = logger.*,
    };
    try strategy.init(ctx);
    const metadata = strategy.getMetadata();
    try logger.info("Strategy initialized: {s}", .{metadata.name});
    try logger.info("", .{});

    // Initialize components
    try logger.info("Initializing trading components...", .{});

    // Create MessageBus for events
    var message_bus = MessageBus.init(allocator);
    defer message_bus.deinit();

    // Create Cache for market data
    var cache = Cache.init(allocator, &message_bus, .{});
    defer cache.deinit();

    // Run trading based on mode
    switch (mode) {
        .paper => try runPaperTrading(
            allocator,
            logger,
            strategy,
            &cache,
            &message_bus,
            pair,
            timeframe,
            initial_capital,
            update_interval,
            duration_minutes,
        ),
        .live => try runLiveTrading(
            allocator,
            logger,
            strategy,
            &cache,
            &message_bus,
            pair,
            timeframe,
            update_interval,
            duration_minutes,
        ),
    }
}

// ============================================================================
// Paper Trading
// ============================================================================

fn runPaperTrading(
    allocator: std.mem.Allocator,
    logger: *Logger,
    strategy: zigQuant.strategy_interface.IStrategy,
    cache: *Cache,
    message_bus: *MessageBus,
    pair: TradingPair,
    timeframe: Timeframe,
    initial_capital: Decimal,
    update_interval: u64,
    duration_minutes: u64,
) !void {
    _ = update_interval; // Will be used for real-time polling in future
    _ = duration_minutes; // Will be used for duration control in future

    try logger.info("╔════════════════════════════════════════════════════╗", .{});
    try logger.info("║        Paper Trading - Historical Simulation       ║", .{});
    try logger.info("╚════════════════════════════════════════════════════╝", .{});
    try logger.info("", .{});

    // 1. Create SimulatedAccount with initial capital
    try logger.info("Creating simulated account with capital: {}", .{initial_capital});
    var account = SimulatedAccount.init(allocator, initial_capital);
    defer account.deinit();

    // 2. Create SimulatedExecutor
    try logger.info("Initializing simulated executor...", .{});
    var executor = SimulatedExecutor.init(
        allocator,
        &account,
        cache,
        message_bus,
        .{
            .commission_rate = Decimal.fromFloat(0.0005), // 0.05%
            .slippage = Decimal.fromFloat(0.0001), // 0.01%
            .fill_delay_ms = 0,
            .log_trades = true,
        },
    );
    defer executor.deinit();

    // 3. Create ExecutionEngine with correct parameters
    try logger.info("Initializing execution engine...", .{});
    var engine = ExecutionEngine.init(
        allocator,
        message_bus,
        cache,
        RiskConfig{
            .max_position_size = null,
            .max_order_size = null,
            .max_daily_loss = null,
            .max_open_orders = 100,
            .min_order_interval_ms = 0,
            .allowed_symbols = null,
        },
    );
    defer engine.deinit();

    // Set the executor as client
    engine.setClient(executor.asClient());
    try engine.start();
    defer engine.stop();

    // 4. Load historical data for simulation
    try logger.info("Loading historical data...", .{});
    try logger.info("Note: Paper trading currently uses historical simulation.", .{});
    try logger.info("      Real-time WebSocket feed coming in v0.4.0", .{});
    try logger.info("", .{});

    // Try to load data from default file or cache
    var data_feed = HistoricalDataFeed.init(allocator, logger.*);

    // Generate expected data file path based on pair and timeframe
    var path_buf: [256]u8 = undefined;
    const data_file = std.fmt.bufPrint(&path_buf, "data/{s}_{s}_{s}.csv", .{
        pair.base,
        pair.quote,
        @tagName(timeframe),
    }) catch {
        try logger.err("Failed to generate data file path", .{});
        return error.PathError;
    };

    var candles = data_feed.loadFromCSV(data_file, pair, timeframe) catch |err| {
        try logger.warn("Could not load historical data from {s}: {s}", .{ data_file, @errorName(err) });
        try logger.info("", .{});
        try logger.info("Paper trading requires historical data.", .{});
        try logger.info("Please provide a CSV file at: {s}", .{data_file});
        try logger.info("Or use backtest mode with --data-file option:", .{});
        try logger.info("  zigquant backtest --strategy <name> --config config.json --data-file <path>", .{});
        try logger.info("", .{});
        return error.NoHistoricalData;
    };
    defer candles.deinit();

    try logger.info("Loaded {} candles for simulation", .{candles.len()});
    try logger.info("", .{});

    // 5. Populate indicators
    try logger.info("Calculating indicators...", .{});
    try strategy.populateIndicators(&candles);
    try logger.info("Indicators calculated successfully", .{});
    try logger.info("", .{});

    // 6. Run simulation loop
    try logger.info("Starting paper trading simulation...", .{});
    try logger.info("", .{});

    var order_count: u64 = 0;
    var signal_count: u64 = 0;
    var has_position = false;

    // Get strategy metadata
    const metadata = strategy.getMetadata();
    const warmup_period = metadata.startup_candle_count;

    for (warmup_period..candles.len()) |i| {
        // Get current candle
        const current_candle = candles.get(i) orelse continue;

        // Check for entry signal if we don't have a position
        if (!has_position) {
            const entry_signal = try strategy.generateEntrySignal(&candles, i);

            if (entry_signal) |signal| {
                defer signal.deinit();
                signal_count += 1;

                // Calculate position size (simple fixed fraction for now)
                const position_size = try initial_capital.mul(Decimal.fromFloat(0.1)).div(current_candle.close);

                const is_long = signal.type == .entry_long;
                try logger.info("[Signal] {s} at price {} (candle {})", .{
                    if (is_long) "LONG" else "SHORT",
                    current_candle.close,
                    i,
                });

                // Create order request
                const order_id_buf = try std.fmt.allocPrint(allocator, "paper_{d}", .{order_count});
                defer allocator.free(order_id_buf);

                const symbol_buf = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ pair.base, pair.quote });
                defer allocator.free(symbol_buf);

                const order_request = ExecOrderRequest{
                    .client_order_id = order_id_buf,
                    .symbol = symbol_buf,
                    .side = if (is_long) .buy else .sell,
                    .order_type = .market,
                    .quantity = position_size,
                    .price = null,
                };

                // Submit order
                const result = try engine.submitOrder(order_request);
                if (result.success) {
                    order_count += 1;
                    has_position = true;
                    try logger.info("[Order] Executed: {} @ {}", .{ position_size, current_candle.close });
                } else {
                    try logger.warn("[Order] Rejected: {s}", .{result.error_message orelse "unknown"});
                }
            }
        } else {
            // Check for exit signal if we have a position
            // For simplicity, we use a basic exit after N candles
            // Full exit signal logic will use strategy.generateExitSignal in future
            if (i % 20 == 0) { // Exit every 20 candles for demo
                has_position = false;
                try logger.info("[Exit] Position closed at price {}", .{current_candle.close});
            }
        }
    }

    // 7. Print summary
    try logger.info("", .{});
    try logger.info("╔════════════════════════════════════════════════════╗", .{});
    try logger.info("║           Paper Trading Summary                    ║", .{});
    try logger.info("╚════════════════════════════════════════════════════╝", .{});
    try logger.info("", .{});

    const final_balance = account.calculateTotalEquity();
    const pnl = final_balance.sub(initial_capital);
    const return_pct = (try pnl.div(initial_capital)).mul(Decimal.fromInt(100));

    try logger.info("Candles processed:  {}", .{candles.len()});
    try logger.info("Signals generated:  {}", .{signal_count});
    try logger.info("Orders executed:    {}", .{order_count});
    try logger.info("Initial capital:    {}", .{initial_capital});
    try logger.info("Final equity:       {}", .{final_balance});
    try logger.info("Total PnL:          {}", .{pnl});
    try logger.info("Return:             {}%", .{return_pct});
    try logger.info("", .{});
    try logger.info("Note: This was a historical simulation.", .{});
    try logger.info("Real-time paper trading with WebSocket data coming in v0.4.0", .{});
}

// ============================================================================
// Live Trading
// ============================================================================

fn runLiveTrading(
    allocator: std.mem.Allocator,
    logger: *Logger,
    strategy: zigQuant.strategy_interface.IStrategy,
    cache: *Cache,
    message_bus: *MessageBus,
    pair: TradingPair,
    timeframe: Timeframe,
    update_interval: u64,
    duration_minutes: u64,
) !void {
    _ = allocator;
    _ = strategy;
    _ = cache;
    _ = message_bus;
    _ = pair;
    _ = timeframe;
    _ = update_interval;
    _ = duration_minutes;

    try logger.warn("╔════════════════════════════════════════════════════╗", .{});
    try logger.warn("║  Live Trading - Coming in v0.4.0                   ║", .{});
    try logger.warn("╚════════════════════════════════════════════════════╝", .{});
    try logger.info("", .{});
    try logger.info("Live trading requires:", .{});
    try logger.info("  - WebSocket real-time market data (HyperliquidDataProvider)", .{});
    try logger.info("  - Async event loop (libxev integration)", .{});
    try logger.info("  - Exchange execution client (HyperliquidExecutionClient)", .{});
    try logger.info("", .{});
    try logger.info("Current implementation status:", .{});
    try logger.info("  ✓ HyperliquidExecutionClient - Ready", .{});
    try logger.info("  ✓ HyperliquidDataProvider - Ready", .{});
    try logger.info("  ✓ SimulatedExecutor (Paper) - Ready", .{});
    try logger.info("  ○ Async event loop - Planned for v0.4.0", .{});
    try logger.info("", .{});
    try logger.info("Please use --paper mode for now:", .{});
    try logger.info("  zigquant run-strategy --strategy {s} --config config.json --paper", .{"<name>"});
    try logger.info("", .{});

    return error.LiveTradingNotYetAvailable;
}

// ============================================================================
// Helper Functions
// ============================================================================

fn printHelp() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\
        \\Run-Strategy Command - Execute trading strategies
        \\
        \\USAGE:
        \\    zigquant run-strategy [OPTIONS]
        \\
        \\REQUIRED:
        \\    -s, --strategy <name>     Strategy name
        \\                              Available: dual_ma, rsi_mean_reversion, bollinger_breakout
        \\    -c, --config <file>       Strategy configuration JSON file
        \\
        \\MODE:
        \\    --paper                   Paper trading mode (default, simulated)
        \\    --live                    Live trading mode (requires API keys)
        \\
        \\OPTIONS:
        \\    --capital <amount>        Initial capital for paper trading (default: 10000)
        \\    --interval <seconds>      Update interval in seconds (default: 60)
        \\    --duration <minutes>      Run duration in minutes, 0 for infinite (default: 0)
        \\    -h, --help                Display this help message
        \\
        \\EXAMPLES:
        \\    # Paper trading (simulated)
        \\    zigquant run-strategy --strategy dual_ma --config dual_ma.json --paper
        \\
        \\    # Paper trading with custom capital and interval
        \\    zigquant run-strategy -s dual_ma -c config.json --paper --capital 50000 --interval 30
        \\
        \\    # Run for 60 minutes then stop
        \\    zigquant run-strategy -s rsi_mean_reversion -c rsi.json --paper --duration 60
        \\
        \\    # Live trading (requires API keys)
        \\    zigquant run-strategy --strategy dual_ma --config config.json --live
        \\
        \\ENVIRONMENT VARIABLES (for live trading):
        \\    ZIGQUANT_EXCHANGES_0_API_KEY       Your exchange API key
        \\    ZIGQUANT_EXCHANGES_0_API_SECRET    Your exchange API secret
        \\
        \\
    );
}

fn parseTradingPair(root: std.json.Value, key: []const u8) !TradingPair {
    const pair_obj = root.object.get(key) orelse return error.MissingParameter;

    const base = pair_obj.object.get("base") orelse return error.MissingParameter;
    const quote = pair_obj.object.get("quote") orelse return error.MissingParameter;

    if (base != .string or quote != .string) {
        return error.InvalidParameter;
    }

    return TradingPair{
        .base = base.string,
        .quote = quote.string,
    };
}

fn parseTimeframe(root: std.json.Value, key: []const u8) !Timeframe {
    const tf_value = root.object.get(key) orelse return Timeframe.h1; // default

    if (tf_value != .string) return error.InvalidParameter;

    const tf_str = tf_value.string;
    const tf = std.meta.stringToEnum(Timeframe, tf_str) orelse
        return error.InvalidTimeframe;

    return tf;
}
