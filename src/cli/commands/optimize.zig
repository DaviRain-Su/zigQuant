//! Optimize Command
//!
//! Parameter optimization for trading strategies using grid search.
//!
//! Usage:
//! ```bash
//! zigquant optimize --strategy dual_ma --config config.json --data data.csv
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
const StrategyWrapper = zigQuant.StrategyWrapper;
const BacktestEngine = zigQuant.BacktestEngine;
const BacktestConfig = zigQuant.BacktestConfig;
const HistoricalDataFeed = zigQuant.HistoricalDataFeed;
const GridSearchOptimizer = zigQuant.GridSearchOptimizer;
const OptimizationConfig = zigQuant.OptimizationConfig;
const OptimizationObjective = zigQuant.OptimizationObjective;
const StrategyParameter = zigQuant.OptimizerStrategyParameter;
const ParameterType = zigQuant.OptimizerParameterType;
const ParameterValue = zigQuant.OptimizerParameterValue;
const ParameterRange = zigQuant.OptimizerParameterRange;
const ParameterSet = zigQuant.OptimizerParameterSet;
const IStrategy = zigQuant.IStrategy;

const StrategyContext = zigQuant.strategy_interface.StrategyContext;

// ============================================================================
// CLI Parameters
// ============================================================================

const params = clap.parseParamsComptime(
    \\-h, --help                Display help
    \\-s, --strategy <str>      Strategy name (dual_ma, rsi_mean_reversion, bollinger_breakout)
    \\-c, --config <str>        Strategy config JSON file with parameter ranges (required)
    \\-d, --data <str>          Historical data CSV file (optional)
    \\    --start <str>         Start timestamp (unix millis or ISO8601)
    \\    --end <str>           End timestamp (unix millis or ISO8601)
    \\    --capital <str>       Initial capital (default: 10000)
    \\    --commission <str>    Commission rate (default: 0.001)
    \\    --slippage <str>      Slippage (default: 0.0005)
    \\    --objective <str>     Optimization objective (sharpe, profit, winrate, drawdown) (default: sharpe)
    \\    --top <str>           Show top N results (default: 10)
    \\-o, --output <str>        Save results to JSON file (optional)
    \\
);

// ============================================================================
// Main Command
// ============================================================================

pub fn cmdOptimize(
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

    try logger.info("=== Parameter Optimization ===", .{});
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
        return err;
    };
    defer allocator.free(config_json);

    // Parse strategy configuration (including parameter ranges)
    const parsed_config = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        config_json,
        .{},
    ) catch |err| {
        try logger.err("Failed to parse config JSON: {s}", .{@errorName(err)});
        return err;
    };
    defer parsed_config.deinit();

    const config_obj = parsed_config.value.object;

    // Extract backtest configuration
    const backtest_obj = config_obj.get("backtest") orelse {
        try logger.err("Missing 'backtest' section in config", .{});
        return error.MissingBacktestConfig;
    };

    // Parse pair from JSON object
    const pair = try parseTradingPair(backtest_obj, "pair");

    // Parse timeframe
    const timeframe = try parseTimeframe(backtest_obj, "timeframe");

    // Parse timestamps (support CLI override)
    const start_time = if (res.args.start) |s|
        try parseTimestamp(allocator, s)
    else if (backtest_obj.object.get("start_time")) |t|
        if (t == .string) try parseTimestamp(allocator, t.string) else Timestamp.fromMillis(0)
    else
        Timestamp.fromMillis(0);

    const end_time = if (res.args.@"end") |s|
        try parseTimestamp(allocator, s)
    else if (backtest_obj.object.get("end_time")) |t|
        if (t == .string) try parseTimestamp(allocator, t.string) else Timestamp.fromMillis(std.math.maxInt(i64))
    else
        Timestamp.fromMillis(std.math.maxInt(i64));

    // Parse decimal values
    const initial_capital = if (res.args.capital) |s|
        try Decimal.fromString(s)
    else if (backtest_obj.object.get("initial_capital")) |c| blk: {
        break :blk switch (c) {
            .string => |str| try Decimal.fromString(str),
            .integer => |int| Decimal.fromInt(@intCast(int)),
            .float => |f| Decimal.fromFloat(@floatCast(f)),
            else => try Decimal.fromString("10000"),
        };
    } else
        try Decimal.fromString("10000");

    const commission_rate = if (res.args.commission) |s|
        try Decimal.fromString(s)
    else if (backtest_obj.object.get("commission_rate")) |c| blk: {
        break :blk switch (c) {
            .string => |str| try Decimal.fromString(str),
            .integer => |int| Decimal.fromInt(@intCast(int)),
            .float => |f| Decimal.fromFloat(@floatCast(f)),
            else => try Decimal.fromString("0.001"),
        };
    } else
        try Decimal.fromString("0.001");

    const slippage = if (res.args.slippage) |s|
        try Decimal.fromString(s)
    else if (backtest_obj.object.get("slippage")) |v| blk: {
        break :blk switch (v) {
            .string => |str| try Decimal.fromString(str),
            .integer => |int| Decimal.fromInt(@intCast(int)),
            .float => |f| Decimal.fromFloat(@floatCast(f)),
            else => try Decimal.fromString("0.0005"),
        };
    } else
        try Decimal.fromString("0.0005");

    // Extract parameter ranges for optimization
    const optimize_obj = config_obj.get("optimization") orelse {
        try logger.err("Missing 'optimization' section in config", .{});
        return error.MissingOptimizationConfig;
    };

    // Parse optimization objective
    const objective_str = res.args.objective orelse
        if (optimize_obj.object.get("objective")) |obj| obj.string else "sharpe";
    const objective = try parseObjective(objective_str);

    try logger.info("Optimization objective: {s}", .{objective.name()});

    // Parse parameter ranges
    const param_obj = optimize_obj.object.get("parameters") orelse {
        try logger.err("Missing 'parameters' in optimization config", .{});
        return error.MissingParameters;
    };

    var param_list = try std.ArrayList(StrategyParameter).initCapacity(allocator, 8);
    defer param_list.deinit(allocator);

    var param_iter = param_obj.object.iterator();
    while (param_iter.next()) |entry| {
        const param_name = entry.key_ptr.*;
        const param_range = entry.value_ptr.*;

        try logger.info("Parameter: {s}", .{param_name});

        // Parse parameter range
        const strategy_param = try parseParameterRange(allocator, param_name, param_range);
        try param_list.append(allocator, strategy_param);
    }

    try logger.info("Total parameters to optimize: {d}", .{param_list.items.len});

    // Determine data file path
    const data_path = res.args.data orelse blk: {
        // Try to construct default path: data/<PAIR>_<TIMEFRAME>.csv
        const default_path = try std.fmt.allocPrint(
            allocator,
            "data/{s}{s}_{s}.csv",
            .{ pair.base, pair.quote, @tagName(timeframe) },
        );
        break :blk default_path;
    };
    defer if (res.args.data == null) allocator.free(data_path);

    try logger.info("Data file: {s}", .{data_path});

    // Note: Historical data will be loaded by BacktestEngine for each optimization run

    // Create backtest configuration
    const backtest_config = BacktestConfig{
        .pair = pair,
        .timeframe = timeframe,
        .start_time = start_time,
        .end_time = end_time,
        .initial_capital = initial_capital,
        .commission_rate = commission_rate,
        .slippage = slippage,
        .data_file = data_path,
    };

    // Create optimization configuration
    const opt_config = OptimizationConfig{
        .objective = objective,
        .backtest_config = backtest_config,
        .parameters = param_list.items,
        .max_combinations = null,
        .enable_parallel = false,
    };

    // Calculate total combinations
    const total_combinations = try opt_config.countCombinations();
    try logger.info("Total combinations to test: {d}", .{total_combinations});

    if (total_combinations > 1000) {
        try logger.warn("Large number of combinations may take a while...", .{});
    }

    // Create optimizer
    var optimizer = try GridSearchOptimizer.init(allocator, opt_config);
    defer optimizer.deinit();

    // Create strategy factory
    const StrategyFactoryContext = struct {
        allocator_ctx: std.mem.Allocator,
        strategy_name_ctx: []const u8,
        config_obj_ctx: std.json.ObjectMap,
        logger_ctx: *Logger,
    };

    const factory_context = StrategyFactoryContext{
        .allocator_ctx = allocator,
        .strategy_name_ctx = strategy_name,
        .config_obj_ctx = config_obj,
        .logger_ctx = logger,
    };

    // Create a factory function with captured context
    const StrategyFactoryWithContext = struct {
        ctx: StrategyFactoryContext,

        pub fn createStrategy(self: *const @This(), param_set: ParameterSet) !StrategyWrapper {
            // Create a modified config with optimized parameters
            var params_obj = std.json.ObjectMap.init(self.ctx.allocator_ctx);
            defer params_obj.deinit();

            // First, copy all parameters from original config (fixed parameters)
            if (self.ctx.config_obj_ctx.get("parameters")) |orig_params| {
                if (orig_params == .object) {
                    var orig_iter = orig_params.object.iterator();
                    while (orig_iter.next()) |entry| {
                        try params_obj.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
            }

            // Then, override with optimized parameters from param_set
            var param_values_iter = param_set.values.iterator();
            while (param_values_iter.next()) |entry| {
                const value_json = switch (entry.value_ptr.*) {
                    .integer => |val| std.json.Value{ .integer = val },
                    .decimal => |val| std.json.Value{ .float = val.toFloat() },
                    .boolean => |val| std.json.Value{ .bool = val },
                    .discrete => |val| std.json.Value{ .string = val },
                };
                try params_obj.put(entry.key_ptr.*, value_json);
            }

            // Build a full config JSON with strategy name, pair, timeframe, and parameters
            // Format: {"strategy": "dual_ma", "pair": {...}, "timeframe": "h1", "parameters": {...}}
            var config_builder = try std.ArrayList(u8).initCapacity(self.ctx.allocator_ctx, 1024);
            defer config_builder.deinit(self.ctx.allocator_ctx);

            const writer = config_builder.writer(self.ctx.allocator_ctx);
            try writer.writeAll("{\"strategy\":\"");
            try writer.writeAll(self.ctx.strategy_name_ctx);
            try writer.writeAll("\",");

            // Add pair from config
            if (self.ctx.config_obj_ctx.get("backtest")) |backtest_val| {
                if (backtest_val == .object) {
                    if (backtest_val.object.get("pair")) |pair_val| {
                        try writer.writeAll("\"pair\":");
                        // Simple JSON stringification for pair object
                        if (pair_val == .object) {
                            try writer.writeAll("{");
                            if (pair_val.object.get("base")) |base| {
                                try writer.writeAll("\"base\":\"");
                                try writer.writeAll(base.string);
                                try writer.writeAll("\"");
                            }
                            if (pair_val.object.get("quote")) |quote| {
                                try writer.writeAll(",\"quote\":\"");
                                try writer.writeAll(quote.string);
                                try writer.writeAll("\"");
                            }
                            try writer.writeAll("},");
                        }
                    }
                    if (backtest_val.object.get("timeframe")) |tf_val| {
                        try writer.writeAll("\"timeframe\":\"");
                        try writer.writeAll(tf_val.string);
                        try writer.writeAll("\",");
                    }
                }
            }

            try writer.writeAll("\"parameters\":{");

            // Write all parameters (both fixed and optimized)
            var first = true;
            var all_params_iter = params_obj.iterator();
            while (all_params_iter.next()) |entry| {
                if (!first) try writer.writeAll(",");
                first = false;

                try writer.writeAll("\"");
                try writer.writeAll(entry.key_ptr.*);
                try writer.writeAll("\":");

                switch (entry.value_ptr.*) {
                    .integer => |val| try writer.print("{d}", .{val}),
                    .float => |val| try writer.print("{any}", .{val}),
                    .bool => |val| try writer.writeAll(if (val) "true" else "false"),
                    .string => |val| {
                        try writer.writeAll("\"");
                        try writer.writeAll(val);
                        try writer.writeAll("\"");
                    },
                    else => {}, // Skip other types
                }
            }
            try writer.writeAll("}}");

            // Use StrategyFactory to create strategy
            var factory = StrategyFactory.init(self.ctx.allocator_ctx);
            return try factory.create(self.ctx.strategy_name_ctx, config_builder.items);
        }
    };

    var factory_with_context = StrategyFactoryWithContext{
        .ctx = factory_context,
    };

    // Run optimization
    try logger.info("", .{});
    try logger.info("Starting optimization...", .{});
    const optimize_start = std.time.milliTimestamp();

    var result = try optimizer.optimize(&factory_with_context);
    defer result.deinit();

    const optimize_elapsed = std.time.milliTimestamp() - optimize_start;
    try logger.info("Optimization completed in {d}ms", .{optimize_elapsed});

    // Display results
    try logger.info("", .{});
    try printResults(logger, &result, res.args.top orelse "10");

    // Save results if requested
    if (res.args.output) |output_path| {
        try logger.info("", .{});
        try logger.info("Saving results to {s}...", .{output_path});
        try saveResults(allocator, &result, output_path);
        try logger.info("Results saved successfully", .{});
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn parseObjective(str: []const u8) !OptimizationObjective {
    if (std.mem.eql(u8, str, "sharpe")) return .maximize_sharpe_ratio;
    if (std.mem.eql(u8, str, "profit")) return .maximize_net_profit;
    if (std.mem.eql(u8, str, "winrate")) return .maximize_win_rate;
    if (std.mem.eql(u8, str, "drawdown")) return .minimize_max_drawdown;
    if (std.mem.eql(u8, str, "profit_factor")) return .maximize_profit_factor;
    return error.InvalidObjective;
}

fn parseParameterRange(
    allocator: std.mem.Allocator,
    name: []const u8,
    range_value: std.json.Value,
) !StrategyParameter {
    _ = allocator;

    const range_obj = range_value.object;

    // Determine parameter type from range
    const min_value = range_obj.get("min") orelse return error.MissingMin;
    const max_value = range_obj.get("max") orelse return error.MissingMax;
    const step_value = range_obj.get("step") orelse return error.MissingStep;

    // Check if integer or decimal
    const is_integer = min_value == .integer and max_value == .integer and step_value == .integer;

    if (is_integer) {
        return StrategyParameter{
            .name = name,
            .type = .integer,
            .default_value = .{ .integer = min_value.integer },
            .optimize = true,
            .range = .{
                .integer = .{
                    .min = min_value.integer,
                    .max = max_value.integer,
                    .step = step_value.integer,
                },
            },
        };
    } else {
        return StrategyParameter{
            .name = name,
            .type = .decimal,
            .default_value = .{ .decimal = Decimal.fromFloat(if (min_value == .float) min_value.float else @floatFromInt(min_value.integer)) },
            .optimize = true,
            .range = .{
                .decimal = .{
                    .min = Decimal.fromFloat(if (min_value == .float) min_value.float else @floatFromInt(min_value.integer)),
                    .max = Decimal.fromFloat(if (max_value == .float) max_value.float else @floatFromInt(max_value.integer)),
                    .step = Decimal.fromFloat(if (step_value == .float) step_value.float else @floatFromInt(step_value.integer)),
                },
            },
        };
    }
}

fn printResults(logger: *Logger, result: *const zigQuant.OptimizationResult, top_n_str: []const u8) !void {
    const top_n = try std.fmt.parseInt(u32, top_n_str, 10);

    try logger.info("╔════════════════════════════════════════════════════╗", .{});
    try logger.info("║         Optimization Results                       ║", .{});
    try logger.info("╚════════════════════════════════════════════════════╝", .{});
    try logger.info("", .{});
    try logger.info("Total combinations tested: {d}", .{result.total_combinations});
    try logger.info("Elapsed time: {d}ms ({d:.2}s)", .{ result.elapsed_time_ms, @as(f64, @floatFromInt(result.elapsed_time_ms)) / 1000.0 });
    try logger.info("", .{});
    try logger.info("════════════════════════════════════════════════════", .{});
    try logger.info("Best Parameters:", .{});
    try logger.info("────────────────────────────────────────────────────", .{});

    var iter = result.best_params.values.iterator();
    while (iter.next()) |entry| {
        try logger.info("  {s}: {any}", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    try logger.info("", .{});
    try logger.info("Best Score: {d:.4}", .{result.best_score});
    try logger.info("", .{});

    // Show top N results if available
    const n = @min(top_n, @as(u32, @intCast(result.all_results.len)));
    if (n > 1) {
        try logger.info("════════════════════════════════════════════════════", .{});
        try logger.info("Top {d} Results:", .{n});
        try logger.info("────────────────────────────────────────────────────", .{});

        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const res = result.all_results[i];
            try logger.info("", .{});
            try logger.info("Rank {d}:", .{i + 1});
            try logger.info("  Score: {d:.4}", .{res.score});

            var param_iter = res.params.values.iterator();
            while (param_iter.next()) |entry| {
                try logger.info("  {s}: {any}", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }
    }

    try logger.info("", .{});
    try logger.info("════════════════════════════════════════════════════", .{});
}

fn saveResults(allocator: std.mem.Allocator, result: *const zigQuant.OptimizationResult, path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    // Zig 0.15: File.writer() returns Writer with interface field
    var write_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(&write_buffer);
    const writer = &file_writer.interface;

    // Start JSON object
    try writer.writeAll("{\n");

    // Objective
    try writer.print("  \"objective\": \"{s}\",\n", .{@tagName(result.objective)});

    // Best score
    try writer.print("  \"best_score\": {d:.6},\n", .{result.best_score});

    // Best parameters
    try writer.writeAll("  \"best_params\": {\n");
    var first_param = true;
    var param_iter = result.best_params.values.iterator();
    while (param_iter.next()) |entry| {
        if (!first_param) {
            try writer.writeAll(",\n");
        }
        first_param = false;

        // Write parameter name and value
        try writer.print("    \"{s}\": ", .{entry.key_ptr.*});
        try writeParameterValue(writer, entry.value_ptr.*);
    }
    try writer.writeAll("\n  },\n");

    // Statistics
    try writer.print("  \"total_combinations\": {d},\n", .{result.total_combinations});
    try writer.print("  \"elapsed_time_ms\": {d},\n", .{result.elapsed_time_ms});

    // All results (top 10)
    try writer.writeAll("  \"top_results\": [\n");
    const max_results = @min(result.all_results.len, 10);
    for (result.all_results[0..max_results], 0..) |res, i| {
        if (i > 0) {
            try writer.writeAll(",\n");
        }
        try writer.writeAll("    {\n");
        try writer.print("      \"rank\": {d},\n", .{i + 1});
        try writer.print("      \"score\": {d:.6},\n", .{res.score});

        // Parameters
        try writer.writeAll("      \"params\": {\n");
        var first_inner = true;
        var inner_iter = res.params.values.iterator();
        while (inner_iter.next()) |entry| {
            if (!first_inner) {
                try writer.writeAll(",\n");
            }
            first_inner = false;
            try writer.print("        \"{s}\": ", .{entry.key_ptr.*});
            try writeParameterValue(writer, entry.value_ptr.*);
        }
        try writer.writeAll("\n      }\n");
        try writer.writeAll("    }");
    }
    try writer.writeAll("\n  ]\n");

    // Close JSON
    try writer.writeAll("}\n");

    // Flush the buffer
    try writer.flush();

    // Use allocator for potential future needs
    _ = allocator;
}

fn writeParameterValue(writer: anytype, value: ParameterValue) !void {
    switch (value) {
        .integer => |val| try writer.print("{d}", .{val}),
        .decimal => |val| try writer.print("{d:.6}", .{val.toFloat()}),
        .boolean => |val| try writer.print("{}", .{val}),
        .discrete => |val| try writer.print("\"{s}\"", .{val}),
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

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

fn parseTimestamp(allocator: std.mem.Allocator, s: []const u8) !Timestamp {
    // Try to parse as integer (unix millis)
    const millis = std.fmt.parseInt(i64, s, 10) catch {
        // Try to parse as ISO8601 format
        return Timestamp.fromISO8601(allocator, s) catch {
            return error.InvalidTimestamp;
        };
    };

    return Timestamp.fromMillis(millis);
}

fn printHelp() !void {
    const stdout = std.fs.File.stdout();

    try stdout.writeAll(
        \\Optimize Command - Parameter optimization for trading strategies
        \\
        \\USAGE:
        \\    zigquant optimize [OPTIONS]
        \\
        \\REQUIRED:
        \\    -s, --strategy <name>     Strategy name
        \\                              Available: dual_ma, rsi_mean_reversion, bollinger_breakout
        \\    -c, --config <file>       Strategy configuration JSON file with parameter ranges
        \\
        \\OPTIONS:
        \\    -d, --data <file>         Historical data CSV file
        \\                              If not specified, tries data/<PAIR>_<TIMEFRAME>.csv
        \\    --start <timestamp>       Start timestamp (unix millis or ISO8601)
        \\    --end <timestamp>         End timestamp (unix millis or ISO8601)
        \\    --capital <amount>        Initial capital (default: 10000)
        \\    --commission <rate>       Commission rate (default: 0.001 = 0.1%)
        \\    --slippage <rate>         Slippage rate (default: 0.0005 = 0.05%)
        \\    --objective <type>        Optimization objective (default: sharpe)
        \\                              Options: sharpe, profit, winrate, drawdown, profit_factor
        \\    --top <N>                 Show top N results (default: 10)
        \\    -o, --output <file>       Save results to JSON file
        \\    -h, --help                Display this help message
        \\
        \\EXAMPLES:
        \\    # Basic optimization
        \\    zigquant optimize --strategy dual_ma --config dual_ma_opt.json --data btc_data.csv
        \\
        \\    # Optimize for profit factor
        \\    zigquant optimize -s dual_ma -c config.json -d data.csv --objective profit_factor
        \\
        \\    # Save results and show top 20
        \\    zigquant optimize -s rsi_mean_reversion -c rsi_opt.json -d data.csv --top 20 -o results.json
        \\
        \\CONFIGURATION FILE FORMAT:
        \\    The config JSON file must include an "optimization" section with parameter ranges:
        \\
        \\    {
        \\      "backtest": {
        \\        "pair": "BTC-USDC",
        \\        "timeframe": "15m",
        \\        "start_time": "2024-01-01T00:00:00Z",
        \\        "end_time": "2024-06-30T23:59:59Z"
        \\      },
        \\      "optimization": {
        \\        "objective": "sharpe",
        \\        "parameters": {
        \\          "fast_period": { "min": 5, "max": 20, "step": 5 },
        \\          "slow_period": { "min": 20, "max": 50, "step": 10 }
        \\        }
        \\      }
        \\    }
        \\
        \\
    );
}
