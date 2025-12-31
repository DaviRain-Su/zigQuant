//! Backtest Command
//!
//! Runs strategy backtests using historical data.
//! Uses the same config.json format as the live command.
//!
//! Usage:
//! ```bash
//! zigquant backtest --config config.json
//! zigquant backtest --config config.json --data data/BTCUSDT_1m.csv
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
const AppConfig = zigQuant.AppConfig;
const BacktestSectionConfig = zigQuant.BacktestSectionConfig;

// Use simplified StrategyContext from interface.zig (backtest only needs allocator and logger)
const StrategyContext = zigQuant.strategy_interface.StrategyContext;

// ============================================================================
// CLI Parameters
// ============================================================================

const params = clap.parseParamsComptime(
    \\-h, --help                Display help
    \\-s, --strategy <str>      Strategy name (optional if in config file)
    \\-c, --config <str>        Config JSON file (required)
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
// Parsed Config Structure
// ============================================================================

const ParsedBacktestConfig = struct {
    strategy_name: []const u8,
    pair: TradingPair,
    timeframe: Timeframe,
    data_file: ?[]const u8,
    initial_capital: f64,
    commission_rate: f64,
    slippage: f64,
    enable_short: bool,
    max_positions: u32,
    output_file: ?[]const u8,
    strategy_config_json: []const u8, // JSON for strategy factory
};

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

    // Validate required config argument
    const config_path = res.args.config orelse {
        try logger.err("Missing required argument: --config", .{});
        try logger.info("Use --help for usage information", .{});
        return error.MissingConfig;
    };

    try logger.info("=== Backtest Command ===", .{});
    try logger.info("Config: {s}", .{config_path});

    // Load configuration file
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

    // Try to parse as unified AppConfig first, then fall back to legacy format
    const parsed_config = try parseConfig(allocator, logger, config_json, res.args.strategy, res.args.data);

    try logger.info("Strategy: {s}", .{parsed_config.strategy_name});

    // Override with CLI arguments if provided
    const data_file = res.args.data orelse parsed_config.data_file;
    const output_file = res.args.output orelse parsed_config.output_file;

    const initial_capital = if (res.args.capital) |s|
        try Decimal.fromString(s)
    else
        Decimal.fromFloat(parsed_config.initial_capital);

    const commission_rate = if (res.args.commission) |s|
        try Decimal.fromString(s)
    else
        Decimal.fromFloat(parsed_config.commission_rate);

    const slippage = if (res.args.slippage) |s|
        try Decimal.fromString(s)
    else
        Decimal.fromFloat(parsed_config.slippage);

    const start_time = if (res.args.start) |s|
        try parseTimestamp(allocator, s)
    else
        Timestamp{ .millis = 0 };

    const end_time = if (res.args.end) |s|
        try parseTimestamp(allocator, s)
    else
        Timestamp{ .millis = std.math.maxInt(i64) };

    // Create strategy
    try logger.info("Creating strategy instance...", .{});
    var factory = StrategyFactory.init(allocator);
    var strategy_wrapper = factory.create(parsed_config.strategy_name, parsed_config.strategy_config_json) catch |err| {
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

    // Build backtest config
    try logger.info("Building backtest configuration...", .{});

    const backtest_config = BacktestConfig{
        .pair = parsed_config.pair,
        .timeframe = parsed_config.timeframe,
        .start_time = start_time,
        .end_time = end_time,
        .initial_capital = initial_capital,
        .commission_rate = commission_rate,
        .slippage = slippage,
        .enable_short = parsed_config.enable_short,
        .max_positions = parsed_config.max_positions,
        .data_file = data_file,
    };

    try backtest_config.validate();

    // Run backtest
    try logger.info("", .{});
    try logger.info("Running backtest...", .{});

    var engine = BacktestEngine.init(allocator, logger.*);

    const progress_callback = struct {
        fn update(prog: f64, current: usize, total: usize) void {
            const percentage = prog * 100;
            std.debug.print("\rProgress: {d:.1}% ({}/{})", .{ percentage, current, total });
        }
    }.update;

    var result = try engine.run(strategy, backtest_config, progress_callback);
    defer result.deinit();

    try logger.info("Backtest complete!", .{});
    try logger.info("", .{});

    // Analyze results
    var analyzer = PerformanceAnalyzer.init(allocator, logger.*);
    const metrics = try analyzer.analyze(result);

    // Display results
    try displayResults(allocator, logger, &result, metrics);

    // Save to JSON if requested
    if (output_file) |out_path| {
        try logger.info("", .{});
        try logger.info("Saving results to {s}...", .{out_path});
        try saveResultsToJSON(allocator, out_path, &result, metrics);
        try logger.info("Results saved successfully", .{});
    }
}

// ============================================================================
// Config Parsing
// ============================================================================

fn parseConfig(
    allocator: std.mem.Allocator,
    logger: *Logger,
    config_json: []const u8,
    cli_strategy: ?[]const u8,
    cli_data: ?[]const u8,
) !ParsedBacktestConfig {
    // Parse as generic JSON first
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        config_json,
        .{ .allocate = .alloc_always },
    ) catch |err| {
        try logger.err("Failed to parse config JSON: {s}", .{@errorName(err)});
        return error.InvalidConfig;
    };
    // Note: We don't deinit parsed here - the strings are used by the returned config
    // The memory will be freed when the allocator is deinited at program exit

    const root = parsed.value;

    // Require "backtest" section in config
    const backtest_section = root.object.get("backtest") orelse {
        try logger.err("Missing 'backtest' section in config file", .{});
        try logger.info("Config file must contain a 'backtest' section. Example:", .{});
        try logger.info("  {{", .{});
        try logger.info("    \"backtest\": {{", .{});
        try logger.info("      \"strategy\": \"dual_ma\",", .{});
        try logger.info("      \"pair\": \"BTC-USDT\",", .{});
        try logger.info("      \"data_file\": \"data/BTCUSDT_1h.csv\"", .{});
        try logger.info("    }}", .{});
        try logger.info("  }}", .{});
        return error.MissingBacktestSection;
    };

    return try parseUnifiedConfig(allocator, root, backtest_section, cli_strategy, cli_data);
}

fn parseUnifiedConfig(
    allocator: std.mem.Allocator,
    _: std.json.Value, // root - for future use
    backtest_section: std.json.Value,
    cli_strategy: ?[]const u8,
    cli_data: ?[]const u8,
) !ParsedBacktestConfig {
    const bt = backtest_section.object;

    // Get strategy name (CLI overrides config)
    const strategy_name = cli_strategy orelse blk: {
        const s = bt.get("strategy") orelse return error.MissingStrategy;
        break :blk s.string;
    };

    // Parse trading pair from string "BTC-USDT" format
    const pair_str = bt.get("pair") orelse return error.MissingParameter;
    const pair = try parsePairFromString(pair_str.string);

    // Parse timeframe
    const timeframe = if (bt.get("timeframe")) |tf|
        std.meta.stringToEnum(Timeframe, tf.string) orelse Timeframe.h1
    else
        Timeframe.h1;

    // Get optional parameters with defaults
    const data_file = cli_data orelse if (bt.get("data_file")) |df|
        if (df == .string) df.string else null
    else
        null;

    const initial_capital = if (bt.get("initial_capital")) |ic|
        switch (ic) {
            .float => ic.float,
            .integer => @as(f64, @floatFromInt(ic.integer)),
            else => 10000.0,
        }
    else
        10000.0;

    const commission_rate = if (bt.get("commission_rate")) |cr|
        switch (cr) {
            .float => cr.float,
            .integer => @as(f64, @floatFromInt(cr.integer)),
            else => 0.001,
        }
    else
        0.001;

    const slippage = if (bt.get("slippage")) |sl|
        switch (sl) {
            .float => sl.float,
            .integer => @as(f64, @floatFromInt(sl.integer)),
            else => 0.0005,
        }
    else
        0.0005;

    const enable_short = if (bt.get("enable_short")) |es|
        es.bool
    else
        true;

    const max_positions: u32 = if (bt.get("max_positions")) |mp|
        switch (mp) {
            .integer => @intCast(mp.integer),
            else => 1,
        }
    else
        1;

    const output_file = if (bt.get("output_file")) |of|
        if (of == .string) of.string else null
    else
        null;

    // Build strategy config JSON from parameters
    const strategy_config_json = try buildStrategyConfigJson(allocator, strategy_name, pair, timeframe, bt);

    return ParsedBacktestConfig{
        .strategy_name = strategy_name,
        .pair = pair,
        .timeframe = timeframe,
        .data_file = data_file,
        .initial_capital = initial_capital,
        .commission_rate = commission_rate,
        .slippage = slippage,
        .enable_short = enable_short,
        .max_positions = max_positions,
        .output_file = output_file,
        .strategy_config_json = strategy_config_json,
    };
}

fn buildStrategyConfigJson(
    allocator: std.mem.Allocator,
    strategy_name: []const u8,
    pair: TradingPair,
    timeframe: Timeframe,
    bt: std.json.ObjectMap,
) ![]const u8 {
    // Build a strategy config JSON that matches the legacy format
    // This allows the strategy factory to work with the same interface

    var params_json = try std.ArrayList(u8).initCapacity(allocator, 256);
    const writer = params_json.writer(allocator);

    // Start parameters object
    try writer.writeAll("{");

    // Add strategy-specific parameters if present
    if (bt.get("parameters")) |strategy_params| {
        if (strategy_params == .object) {
            var first = true;
            var param_iter = strategy_params.object.iterator();
            while (param_iter.next()) |entry| {
                if (!first) try writer.writeAll(",");
                first = false;

                try writer.print("\"{s}\":", .{entry.key_ptr.*});
                try writeJsonValue(writer, entry.value_ptr.*);
            }
        }
    }

    try writer.writeAll("}");

    // Build the full config JSON
    const config = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "strategy": "{s}",
        \\  "pair": {{ "base": "{s}", "quote": "{s}" }},
        \\  "timeframe": "{s}",
        \\  "parameters": {s}
        \\}}
    , .{
        strategy_name,
        pair.base,
        pair.quote,
        @tagName(timeframe),
        params_json.items,
    });

    params_json.deinit(allocator);
    return config;
}

fn writeJsonValue(writer: anytype, value: std.json.Value) !void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.print("{}", .{b}),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .string => |s| try writer.print("\"{s}\"", .{s}),
        .array => |arr| {
            try writer.writeAll("[");
            for (arr.items, 0..) |item, i| {
                if (i > 0) try writer.writeAll(",");
                try writeJsonValue(writer, item);
            }
            try writer.writeAll("]");
        },
        .object => |obj| {
            try writer.writeAll("{");
            var first = true;
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                if (!first) try writer.writeAll(",");
                first = false;
                try writer.print("\"{s}\":", .{entry.key_ptr.*});
                try writeJsonValue(writer, entry.value_ptr.*);
            }
            try writer.writeAll("}");
        },
        else => try writer.writeAll("null"),
    }
}

fn parsePairFromString(pair_str: []const u8) !TradingPair {
    // Parse "BTC-USDT" format
    var iter = std.mem.splitScalar(u8, pair_str, '-');
    const base = iter.next() orelse return error.InvalidPairFormat;
    const quote = iter.next() orelse return error.InvalidPairFormat;

    return TradingPair{
        .base = base,
        .quote = quote,
    };
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
        \\    zigquant backtest --config <file> [OPTIONS]
        \\
        \\REQUIRED:
        \\    -c, --config <file>       Config JSON file (same format as live command)
        \\
        \\OPTIONS:
        \\    -s, --strategy <name>     Strategy name (overrides config file)
        \\                              Available: dual_ma, rsi_mean_reversion, bollinger_breakout
        \\    -d, --data <file>         Historical data CSV file (overrides config file)
        \\    --start <timestamp>       Start timestamp (unix millis or ISO8601)
        \\    --end <timestamp>         End timestamp (unix millis or ISO8601)
        \\    --capital <amount>        Initial capital (default: from config or 10000)
        \\    --commission <rate>       Commission rate (default: from config or 0.001)
        \\    --slippage <rate>         Slippage rate (default: from config or 0.0005)
        \\    -o, --output <file>       Save results to JSON file
        \\    -h, --help                Display this help message
        \\
        \\CONFIG FORMAT:
        \\
        \\    Config file must contain a "backtest" section:
        \\    {
        \\      "backtest": {
        \\        "strategy": "dual_ma",
        \\        "pair": "BTC-USDT",
        \\        "timeframe": "h1",
        \\        "data_file": "data/BTCUSDT_1h.csv",
        \\        "initial_capital": 10000,
        \\        "commission_rate": 0.001,
        \\        "slippage": 0.0005,
        \\        "parameters": {
        \\          "fast_period": 10,
        \\          "slow_period": 20,
        \\          "ma_type": "sma"
        \\        }
        \\      }
        \\    }
        \\
        \\EXAMPLES:
        \\    # Basic backtest using config.json
        \\    zigquant backtest --config config.json
        \\
        \\    # Override data file from CLI
        \\    zigquant backtest --config config.json --data data/BTCUSDT_1m.csv
        \\
        \\    # Override strategy from CLI
        \\    zigquant backtest --config config.json --strategy rsi_mean_reversion
        \\
        \\    # With custom capital and output
        \\    zigquant backtest -c config.json --capital 50000 -o results.json
        \\
        \\
    );
}

fn parseTimestamp(allocator: std.mem.Allocator, s: []const u8) !Timestamp {
    // Try to parse as integer (unix millis)
    const millis = std.fmt.parseInt(i64, s, 10) catch {
        // Try to parse as ISO8601 format
        return Timestamp.fromISO8601(allocator, s) catch {
            return error.InvalidTimestamp;
        };
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
    try logger.info("  Net Profit:          {d:.2}", .{metrics.net_profit.toFloat()});
    try logger.info("  Profit Factor:       {d:.2}", .{metrics.profit_factor});
    try logger.info("  Average Profit:      {d:.2}", .{metrics.average_profit.toFloat()});
    try logger.info("  Average Loss:        {d:.2}", .{metrics.average_loss.toFloat()});
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
    try logger.info("  Total Commission:    {d:.4}", .{metrics.total_commission.toFloat()});
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
        \\  "net_profit": {d},
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
        metrics.net_profit.toFloat(),
        metrics.profit_factor,
        metrics.max_drawdown,
        metrics.sharpe_ratio,
        metrics.total_return,
        metrics.annualized_return,
    });
    defer allocator.free(json_content);

    try file.writeAll(json_content);
}
