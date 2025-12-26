//! Backtest Command
//!
//! Runs strategy backtests using historical data.
//!
//! Usage:
//! ```bash
//! zigquant backtest --strategy dual_ma --config config.json --data data.csv
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
const BacktestEngine = zigQuant.BacktestEngine;
const BacktestConfig = zigQuant.BacktestConfig;
const HistoricalDataFeed = zigQuant.HistoricalDataFeed;
const PerformanceAnalyzer = zigQuant.PerformanceAnalyzer;

// Use simplified StrategyContext from interface.zig (backtest only needs allocator and logger)
const StrategyContext = zigQuant.strategy_interface.StrategyContext;

// ============================================================================
// CLI Parameters
// ============================================================================

const params = clap.parseParamsComptime(
    \\-h, --help                Display help
    \\-s, --strategy <str>      Strategy name (dual_ma, rsi_mean_reversion, bollinger_breakout)
    \\-c, --config <str>        Strategy config JSON file (required)
    \\-d, --data <str>          Historical data CSV file (optional)
    \\    --start <str>         Start timestamp (unix millis or ISO8601)
    \\    --end <str>           End timestamp (unix millis or ISO8601)
    \\    --capital <str>       Initial capital (default: 10000)
    \\    --commission <str>    Commission rate (default: 0.001)
    \\    --slippage <str>      Slippage (default: 0.0005)
    \\-o, --output <str>        Save results to JSON file (optional)
    \\
);

// ============================================================================
// Main Command
// ============================================================================

pub fn cmdBacktest(
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
        // Print simple error message
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

    try logger.info("=== Backtest Command ===", .{});
    try logger.info("Strategy: {s}", .{strategy_name});
    try logger.info("Config: {s}", .{config_path});

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

    // Build backtest config (engine will load data internally)
    try logger.info("Building backtest configuration...", .{});

    const start_time = if (res.args.start) |s|
        try parseTimestamp(s)
    else
        Timestamp{ .millis = 0 };

    const end_time = if (res.args.@"end") |s|
        try parseTimestamp(s)
    else
        Timestamp{ .millis = std.math.maxInt(i64) };

    const initial_capital = if (res.args.capital) |s|
        try Decimal.fromString(s)
    else
        try Decimal.fromString("10000");

    const commission_rate = if (res.args.commission) |s|
        try Decimal.fromString(s)
    else
        try Decimal.fromString("0.001");

    const slippage = if (res.args.slippage) |s|
        try Decimal.fromString(s)
    else
        try Decimal.fromString("0.0005");

    const backtest_config = BacktestConfig{
        .pair = pair,
        .timeframe = timeframe,
        .start_time = start_time,
        .end_time = end_time,
        .initial_capital = initial_capital,
        .commission_rate = commission_rate,
        .slippage = slippage,
        .enable_short = true,
        .max_positions = 1,
    };

    try backtest_config.validate();

    // Run backtest
    try logger.info("", .{});
    try logger.info("Running backtest...", .{});

    var engine = BacktestEngine.init(allocator, logger.*);
    var result = try engine.run(strategy, backtest_config);
    defer result.deinit();

    try logger.info("Backtest complete!", .{});
    try logger.info("", .{});

    // Analyze results
    var analyzer = PerformanceAnalyzer.init(allocator, logger.*);
    const metrics = try analyzer.analyze(result);

    // Display results
    try displayResults(allocator, logger, &result, metrics);

    // Save to JSON if requested
    if (res.args.output) |output_path| {
        try logger.info("", .{});
        try logger.info("Saving results to {s}...", .{output_path});
        try saveResultsToJSON(allocator, output_path, &result, metrics);
        try logger.info("Results saved successfully", .{});
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn printHelp() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\
        \\Backtest Command - Run strategy backtests
        \\
        \\USAGE:
        \\    zigquant backtest [OPTIONS]
        \\
        \\REQUIRED:
        \\    -s, --strategy <name>     Strategy name
        \\                              Available: dual_ma, rsi_mean_reversion, bollinger_breakout
        \\    -c, --config <file>       Strategy configuration JSON file
        \\
        \\OPTIONS:
        \\    -d, --data <file>         Historical data CSV file
        \\                              If not specified, tries data/<PAIR>_<TIMEFRAME>.csv
        \\    --start <timestamp>       Start timestamp (unix millis or ISO8601)
        \\    --end <timestamp>         End timestamp (unix millis or ISO8601)
        \\    --capital <amount>        Initial capital (default: 10000)
        \\    --commission <rate>       Commission rate (default: 0.001 = 0.1%)
        \\    --slippage <rate>         Slippage rate (default: 0.0005 = 0.05%)
        \\    -o, --output <file>       Save results to JSON file
        \\    -h, --help                Display this help message
        \\
        \\EXAMPLES:
        \\    # Basic backtest
        \\    zigquant backtest --strategy dual_ma --config dual_ma.json --data btc_data.csv
        \\
        \\    # Backtest with custom capital
        \\    zigquant backtest -s dual_ma -c config.json -d data.csv --capital 50000
        \\
        \\    # Save results to file
        \\    zigquant backtest -s rsi_mean_reversion -c rsi.json -d data.csv -o results.json
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

fn parseTimestamp(s: []const u8) !Timestamp {
    // Try to parse as integer (unix millis)
    const millis = std.fmt.parseInt(i64, s, 10) catch {
        // TODO: Parse ISO8601 format
        return error.InvalidTimestamp;
    };

    return Timestamp{ .millis = millis };
}

fn displayResults(
    allocator: std.mem.Allocator,
    logger: *Logger,
    result: *const zigQuant.BacktestResult,
    metrics: zigQuant.PerformanceMetrics,
) !void {
    _ = allocator; // For future use

    try logger.info("╔═══════════════════════════════════════════════════════════╗", .{});
    try logger.info("║                    Backtest Results                       ║", .{});
    try logger.info("╚═══════════════════════════════════════════════════════════╝", .{});
    try logger.info("", .{});

    try logger.info("Strategy: {s}", .{result.strategy_name});
    try logger.info("Pair:     {s}-{s}", .{ result.config.pair.base, result.config.pair.quote });
    try logger.info("Period:   {d} days", .{metrics.backtest_days});
    try logger.info("", .{});

    try logger.info("Trading Performance", .{});
    try logger.info("────────────────────────────────────────────────────────────", .{});
    try logger.info("  Total Trades:        {d}", .{metrics.total_trades});
    try logger.info("  Winning Trades:      {d} ({d:.2}%)", .{
        metrics.winning_trades,
        metrics.win_rate * 100,
    });
    try logger.info("  Losing Trades:       {d}", .{metrics.losing_trades});
    try logger.info("", .{});
    try logger.info("  Net Profit:          {}", .{metrics.net_profit});
    try logger.info("  Profit Factor:       {d:.2}", .{metrics.profit_factor});
    try logger.info("  Average Profit:      {}", .{metrics.average_profit});
    try logger.info("  Average Loss:        {}", .{metrics.average_loss});
    try logger.info("", .{});

    try logger.info("Risk Metrics", .{});
    try logger.info("────────────────────────────────────────────────────────────", .{});
    try logger.info("  Max Drawdown:        {d:.2}%", .{metrics.max_drawdown * 100});
    try logger.info("  Sharpe Ratio:        {d:.2}", .{metrics.sharpe_ratio});
    try logger.info("  Total Return:        {d:.2}%", .{metrics.total_return * 100});
    try logger.info("  Annualized Return:   {d:.2}%", .{metrics.annualized_return * 100});
    try logger.info("", .{});

    try logger.info("Trade Statistics", .{});
    try logger.info("────────────────────────────────────────────────────────────", .{});
    try logger.info("  Avg Hold Time:       {d:.1} minutes", .{metrics.average_hold_time_minutes});
    try logger.info("  Max Hold Time:       {d} minutes", .{metrics.max_hold_time_minutes});
    try logger.info("  Min Hold Time:       {d} minutes", .{metrics.min_hold_time_minutes});
    try logger.info("  Total Commission:    {}", .{metrics.total_commission});
    try logger.info("", .{});
}

fn saveResultsToJSON(
    allocator: std.mem.Allocator,
    path: []const u8,
    result: *const zigQuant.BacktestResult,
    metrics: zigQuant.PerformanceMetrics,
) !void {
    // Create a simple JSON structure
    // Note: This is a simplified version. A full implementation would use std.json.stringify
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    // Build JSON string manually (simplified version)
    const json_content = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "strategy": "{s}",
        \\  "pair": "{s}-{s}",
        \\  "total_trades": {d},
        \\  "winning_trades": {d},
        \\  "losing_trades": {d},
        \\  "win_rate": {d},
        \\  "net_profit": "{}",
        \\  "profit_factor": {d},
        \\  "max_drawdown": {d},
        \\  "sharpe_ratio": {d},
        \\  "total_return": {d},
        \\  "annualized_return": {d}
        \\}}
        \\
    , .{
        result.strategy_name,
        result.config.pair.base,
        result.config.pair.quote,
        metrics.total_trades,
        metrics.winning_trades,
        metrics.losing_trades,
        metrics.win_rate,
        metrics.net_profit,
        metrics.profit_factor,
        metrics.max_drawdown,
        metrics.sharpe_ratio,
        metrics.total_return,
        metrics.annualized_return,
    });
    defer allocator.free(json_content);

    try file.writeAll(json_content);
}
