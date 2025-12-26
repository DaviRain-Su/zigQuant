//! Strategy Optimization Example
//!
//! 此示例展示如何使用网格搜索优化器寻找策略的最佳参数。
//!
//! 功能：
//! 1. 定义参数搜索空间
//! 2. 配置优化目标（最大化 Sharpe Ratio）
//! 3. 运行网格搜索优化
//! 4. 分析和展示优化结果
//! 5. 显示 Top N 参数组合
//!
//! 运行：
//!   zig build run-example-optimize

const std = @import("std");
const zigQuant = @import("zigQuant");

const Logger = zigQuant.Logger;
const GridSearchOptimizer = zigQuant.GridSearchOptimizer;
const OptimizationConfig = zigQuant.OptimizationConfig;
const OptimizationObjective = zigQuant.OptimizationObjective;
const StrategyParameter = zigQuant.OptimizerStrategyParameter;
const ParameterType = zigQuant.OptimizerParameterType;
const ParameterValue = zigQuant.OptimizerParameterValue;
const ParameterRange = zigQuant.OptimizerParameterRange;
const ParameterSet = zigQuant.OptimizerParameterSet;
const BacktestConfig = zigQuant.BacktestConfig;
const TradingPair = zigQuant.TradingPair;
const Timeframe = zigQuant.Timeframe;
const Timestamp = zigQuant.Timestamp;
const Decimal = zigQuant.Decimal;
const IStrategy = zigQuant.IStrategy;
const DualMAStrategy = zigQuant.DualMAStrategy;

// Module-level variables for strategy factory (will be set in main)
var g_allocator: std.mem.Allocator = undefined;
var g_pair: TradingPair = undefined;
var g_strategies: std.ArrayList(*DualMAStrategy) = undefined;

// Strategy factory function
fn createStrategy(params: ParameterSet) !IStrategy {
    const fast_period = params.get("fast_period").?.integer;
    const slow_period = params.get("slow_period").?.integer;

    const strategy_ptr = try DualMAStrategy.create(g_allocator, .{
        .pair = g_pair,
        .fast_period = @intCast(fast_period),
        .slow_period = @intCast(slow_period),
        .ma_type = .sma,
    });

    // Save strategy pointer for cleanup
    try g_strategies.append(g_allocator, strategy_ptr);

    return strategy_ptr.toStrategy();
}

pub fn main() !void {
    // 1. 初始化内存分配器
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Set global variables for strategy factory
    g_allocator = allocator;
    g_pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    g_strategies = try std.ArrayList(*DualMAStrategy).initCapacity(allocator, 16);
    defer {
        // Clean up all created strategies
        for (g_strategies.items) |strategy| {
            strategy.destroy();
        }
        g_strategies.deinit(allocator);
    }

    // 2. 初始化日志系统
    const DummyWriter = struct {
        fn write(_: *anyopaque, record: zigQuant.logger.LogRecord) anyerror!void {
            const level_str = switch (record.level) {
                .trace => "TRACE",
                .debug => "DEBUG",
                .info => "INFO ",
                .warn => "WARN ",
                .err => "ERROR",
                .fatal => "FATAL",
            };
            std.debug.print("[{s}] {s}\n", .{ level_str, record.message });
        }
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const dummy = struct {};
    const log_writer = zigQuant.logger.LogWriter{
        .ptr = @constCast(@ptrCast(&dummy)),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    var logger = Logger.init(allocator, log_writer, .info);
    defer logger.deinit();

    try logger.info("═══════════════════════════════════════════════════", .{});
    try logger.info("    zigQuant - Strategy Optimization Example", .{});
    try logger.info("═══════════════════════════════════════════════════", .{});
    try logger.info("", .{});

    // 3. 定义参数搜索空间
    try logger.info("Defining parameter space...", .{});

    const parameters = [_]StrategyParameter{
        .{
            .name = "fast_period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .range = .{
                .integer = .{
                    .min = 5,
                    .max = 15,
                    .step = 5,
                },
            },
            .optimize = true,
        },
        .{
            .name = "slow_period",
            .type = .integer,
            .default_value = .{ .integer = 20 },
            .range = .{
                .integer = .{
                    .min = 20,
                    .max = 40,
                    .step = 10,
                },
            },
            .optimize = true,
        },
    };

    // 计算总组合数: (15-5)/5+1 = 3, (40-20)/10+1 = 3, total = 3*3 = 9
    const total_combinations: u32 = 3 * 3;
    try logger.info("✓ Parameter grid defined:", .{});
    try logger.info("  fast_period: 5, 10, 15", .{});
    try logger.info("  slow_period: 20, 30, 40", .{});
    try logger.info("  Total combinations: {}", .{total_combinations});
    try logger.info("", .{});

    // 4. 配置回测参数
    try logger.info("Configuring backtest...", .{});

    const backtest_config = BacktestConfig{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .timeframe = Timeframe.h1,
        .start_time = try Timestamp.fromISO8601(allocator, "2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.fromISO8601(allocator, "2024-06-30T23:59:59Z"),
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = try Decimal.fromString("0.001"),
        .slippage = try Decimal.fromString("0.0005"),
        .data_file = "data/BTCUSDT_1h_2024.csv",
    };

    try logger.info("✓ Pair: BTC/USDT | Period: 2024 H1 | Capital: $10,000", .{});
    try logger.info("", .{});

    // 5. 配置优化器
    try logger.info("Configuring optimizer...", .{});

    const opt_config = OptimizationConfig{
        .objective = .maximize_profit_factor,
        .backtest_config = backtest_config,
        .parameters = &parameters,
        .max_combinations = null,
        .enable_parallel = false,
    };

    var optimizer = try GridSearchOptimizer.init(allocator, opt_config);
    defer optimizer.deinit();

    try logger.info("✓ Objective: Maximize Profit Factor", .{});
    try logger.info("", .{});

    // 6. 运行优化
    try logger.info("Starting optimization...", .{});
    try logger.info("Testing {} parameter combinations...", .{total_combinations});
    try logger.info("", .{});

    const start_time = std.time.milliTimestamp();

    var result = try optimizer.optimize(createStrategy);
    defer result.deinit();

    const elapsed = std.time.milliTimestamp() - start_time;
    try logger.info("✓ Optimization completed in {}ms", .{elapsed});
    try logger.info("", .{});

    // 8. 展示最佳结果
    try logger.info("═══════════════════════════════════════════════════", .{});
    try logger.info("              Optimization Results", .{});
    try logger.info("═══════════════════════════════════════════════════", .{});
    try logger.info("", .{});

    try logger.info("Best Parameters:", .{});
    const best_fast = result.best_params.get("fast_period").?;
    const best_slow = result.best_params.get("slow_period").?;
    try logger.info("  fast_period: {}", .{best_fast.integer});
    try logger.info("  slow_period: {}", .{best_slow.integer});
    try logger.info("", .{});

    try logger.info("Best Performance:", .{});
    try logger.info("  Optimization Score: {d:.4}", .{result.best_score});
    try logger.info("  Total Combinations: {}", .{result.total_combinations});
    try logger.info("  Time per Test: {d:.1}ms", .{
        @as(f64, @floatFromInt(result.elapsed_time_ms)) / @as(f64, @floatFromInt(result.total_combinations)),
    });
    try logger.info("", .{});

    // 9. 显示 Top 5 结果
    try logger.info("Top 5 Parameter Sets:", .{});
    try logger.info("───────────────────────────────────────────────────", .{});
    try logger.info("{s:<6} {s:<12} {s:<12} {s:<12}", .{ "Rank", "Fast", "Slow", "Score" });
    try logger.info("───────────────────────────────────────────────────", .{});

    const top_5 = try result.getTopResults(allocator, 5);
    defer allocator.free(top_5);

    for (top_5, 1..) |param_result, i| {
        const fast = param_result.params.get("fast_period").?.integer;
        const slow = param_result.params.get("slow_period").?.integer;
        try logger.info("{d:<6} {d:<12} {d:<12} {d:<12.4}", .{
            i,
            fast,
            slow,
            param_result.score,
        });
    }

    try logger.info("", .{});
    try logger.info("═══════════════════════════════════════════════════", .{});
    try logger.info("✓ Example Complete", .{});
    try logger.info("═══════════════════════════════════════════════════", .{});
}
