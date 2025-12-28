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

// Strategy interface
const StrategyContext = zigQuant.strategy_interface.StrategyContext;
const Signal = zigQuant.strategy_interface.Signal;

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
    _ = cache;
    _ = message_bus;
    _ = timeframe;

    try logger.info("Starting Paper Trading...", .{});
    try logger.info("", .{});

    // Create simulated account
    var account = SimulatedAccount.init(allocator, initial_capital);
    defer account.deinit();

    // Create simulated executor
    var executor = SimulatedExecutor.init(allocator, &account, null, null, .{
        .log_trades = true,
    });
    defer executor.deinit();

    // Create execution engine
    var engine = ExecutionEngine.init(allocator, executor.asClient(), null, null);
    defer engine.deinit();

    try logger.info("╔════════════════════════════════════════════════════╗", .{});
    try logger.info("║  Paper Trading Started - Press Ctrl+C to stop     ║", .{});
    try logger.info("╚════════════════════════════════════════════════════╝", .{});
    try logger.info("", .{});

    const start_time = std.time.timestamp();
    const end_time: i64 = if (duration_minutes > 0)
        start_time + @as(i64, @intCast(duration_minutes * 60))
    else
        std.math.maxInt(i64);

    var tick_count: u64 = 0;
    const symbol = try std.fmt.allocPrint(allocator, "{s}", .{pair.base});
    defer allocator.free(symbol);

    // Main trading loop
    while (std.time.timestamp() < end_time) {
        tick_count += 1;
        const now = Timestamp.now();

        try logger.info("[Tick {d}] {}", .{ tick_count, now });

        // Generate simulated price (in real implementation, fetch from exchange)
        // For demo purposes, use a random walk around a base price
        const base_price: f64 = 3500.0; // Example: ETH price
        const noise = @as(f64, @floatFromInt(tick_count % 100)) * 0.5 - 25.0;
        const current_price = Decimal.fromFloat(base_price + noise);

        // Create a simulated candle for strategy
        const candle = Candle{
            .open = current_price,
            .high = current_price.add(Decimal.fromFloat(5.0)),
            .low = current_price.sub(Decimal.fromFloat(5.0)),
            .close = current_price,
            .volume = Decimal.fromFloat(1000.0),
            .timestamp = now,
        };

        // Generate signal from strategy
        const signal = strategy.onData(candle);

        // Process signal
        if (signal) |sig| {
            try logger.info("  Signal: {s} @ {}", .{
                switch (sig.direction) {
                    .long => "LONG",
                    .short => "SHORT",
                    .flat => "FLAT",
                },
                current_price,
            });

            // Execute based on signal
            switch (sig.direction) {
                .long => {
                    // Check if we have a position
                    const pos = account.getPosition(symbol);
                    if (pos == null) {
                        // Calculate quantity based on signal strength
                        const trade_value = account.available_balance.mul(sig.strength);
                        const quantity = trade_value.divTrunc(current_price);

                        if (quantity.cmp(Decimal.ZERO) == .gt) {
                            const result = try engine.submitOrder(.{
                                .client_order_id = try std.fmt.allocPrint(allocator, "paper-{d}", .{tick_count}),
                                .symbol = symbol,
                                .side = .buy,
                                .order_type = .market,
                                .quantity = quantity,
                                .price = current_price,
                            });
                            allocator.free(result.order_id.?);

                            if (result.success) {
                                try logger.info("  Order executed: BUY {} @ {}", .{ quantity, current_price });
                            }
                        }
                    }
                },
                .short => {
                    // Close long position if exists
                    if (account.getPosition(symbol)) |pos| {
                        if (pos.side == .long) {
                            const result = try engine.submitOrder(.{
                                .client_order_id = try std.fmt.allocPrint(allocator, "paper-{d}", .{tick_count}),
                                .symbol = symbol,
                                .side = .sell,
                                .order_type = .market,
                                .quantity = pos.quantity,
                                .price = current_price,
                            });
                            allocator.free(result.order_id.?);

                            if (result.success) {
                                try logger.info("  Order executed: SELL {} @ {}", .{ pos.quantity, current_price });
                            }
                        }
                    }
                },
                .flat => {},
            }
        }

        // Display account status every 5 ticks
        if (tick_count % 5 == 0) {
            const balance = try executor.asClient().getBalance();
            try logger.info("  Balance: {} | Unrealized PnL: {}", .{
                balance.total,
                balance.unrealized_pnl,
            });
        }

        // Sleep until next update
        std.time.sleep(update_interval * std.time.ns_per_s);
    }

    // Final summary
    try logger.info("", .{});
    try logger.info("╔════════════════════════════════════════════════════╗", .{});
    try logger.info("║               Paper Trading Summary                ║", .{});
    try logger.info("╚════════════════════════════════════════════════════╝", .{});
    try logger.info("", .{});

    const final_balance = try executor.asClient().getBalance();
    const pnl = final_balance.total.sub(initial_capital);
    const return_pct = pnl.toFloat() / initial_capital.toFloat() * 100.0;

    try logger.info("Initial Capital:  {}", .{initial_capital});
    try logger.info("Final Balance:    {}", .{final_balance.total});
    try logger.info("Net P&L:          {}", .{pnl});
    try logger.info("Return:           {d:.2}%", .{return_pct});
    try logger.info("Total Ticks:      {d}", .{tick_count});
    try logger.info("", .{});
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
