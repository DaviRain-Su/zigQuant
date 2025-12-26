/// Grid Search Optimizer
///
/// Exhaustive parameter optimization using Cartesian product.
/// Tests all possible combinations of parameter values to find
/// the optimal configuration for a trading strategy.
///
/// Features:
/// - Exhaustive search of parameter space
/// - Multiple optimization objectives
/// - Progress tracking
/// - Result ranking and analysis

const std = @import("std");
const root = @import("../root.zig");
const types = @import("types.zig");
const combination = @import("combination.zig");

const BacktestEngine = root.BacktestEngine;
const BacktestConfig = root.BacktestConfig;
const BacktestResult = root.BacktestResult;
const IStrategy = root.IStrategy;
const PerformanceMetrics = root.PerformanceMetrics;
const PerformanceAnalyzer = root.PerformanceAnalyzer;
const Logger = root.Logger;
const LogWriter = root.logger.LogWriter;
const LogRecord = root.logger.LogRecord;

const OptimizationConfig = types.OptimizationConfig;
const OptimizationResult = types.OptimizationResult;
const OptimizationObjective = types.OptimizationObjective;
const ParameterSet = types.ParameterSet;
const ParameterResult = types.ParameterResult;
const CombinationGenerator = combination.CombinationGenerator;

/// Null writer for optimizer (doesn't write anything)
const NullWriter = struct {
    fn init() NullWriter {
        return .{};
    }

    fn writer(self: *NullWriter) LogWriter {
        return LogWriter{
            .ptr = self,
            .writeFn = writeFn,
            .flushFn = flushFn,
            .closeFn = closeFn,
        };
    }

    fn writeFn(_: *anyopaque, _: LogRecord) anyerror!void {
        // Do nothing
    }

    fn flushFn(_: *anyopaque) anyerror!void {
        // Do nothing
    }

    fn closeFn(_: *anyopaque) void {
        // Do nothing
    }
};

/// Grid Search Optimizer
pub const GridSearchOptimizer = struct {
    allocator: std.mem.Allocator,
    config: OptimizationConfig,

    /// Initialize optimizer
    pub fn init(
        allocator: std.mem.Allocator,
        config: OptimizationConfig,
    ) !GridSearchOptimizer {
        // Validate configuration
        try config.validate();

        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Deinitialize optimizer
    pub fn deinit(self: *GridSearchOptimizer) void {
        _ = self;
    }

    /// Run optimization
    pub fn optimize(
        self: *GridSearchOptimizer,
        strategy_factory: anytype, // Function: (ParameterSet) -> !IStrategy
    ) !OptimizationResult {
        const start_time = std.time.milliTimestamp();

        // Generate all parameter combinations
        var generator = CombinationGenerator.init(
            self.allocator,
            self.config.parameters,
        );
        defer generator.deinit();

        const total_combinations = try generator.countCombinations();
        const combinations = try generator.generateAll();
        defer {
            for (combinations) |*combo| {
                combo.deinit();
            }
            self.allocator.free(combinations);
        }

        // Allocate results array
        const results = try self.allocator.alloc(ParameterResult, total_combinations);
        errdefer self.allocator.free(results);

        // Run backtest for each combination
        var best_score: f64 = -std.math.inf(f64);
        var best_index: usize = 0;

        for (combinations, 0..) |*combo, i| {
            // Clone the parameter set for this result
            var params = try combo.clone(self.allocator);
            errdefer params.deinit();

            // Create strategy with these parameters
            var strategy = try strategy_factory(params);
            defer strategy.deinit();

            // Create null logger for backtest
            var null_writer = NullWriter.init();
            const log_writer = null_writer.writer();
            var logger = Logger.init(self.allocator, log_writer, .err);
            defer logger.deinit();

            // Run backtest
            var engine = BacktestEngine.init(self.allocator, logger);
            const backtest_result = try engine.run(strategy, self.config.backtest_config);

            // Calculate score based on objective
            const score = self.calculateScore(&backtest_result);

            // Store result
            results[i] = ParameterResult{
                .params = params,
                .backtest_result = backtest_result,
                .score = score,
            };

            // Track best result
            if (score > best_score) {
                best_score = score;
                best_index = i;
            }
        }

        const elapsed_time = @as(u64, @intCast(std.time.milliTimestamp() - start_time));

        // Clone best parameters
        const best_params = try results[best_index].params.clone(self.allocator);

        return OptimizationResult{
            .allocator = self.allocator,
            .objective = self.config.objective,
            .best_params = best_params,
            .best_score = best_score,
            .all_results = results,
            .total_combinations = total_combinations,
            .elapsed_time_ms = elapsed_time,
        };
    }

    /// Calculate score for a backtest result based on objective
    fn calculateScore(self: *const GridSearchOptimizer, result: *const BacktestResult) f64 {
        // Create a null logger and analyzer for metrics calculation
        var null_writer = NullWriter.init();
        const logger = Logger.init(self.allocator, null_writer.writer(), .err);
        var analyzer = PerformanceAnalyzer.init(self.allocator, logger);

        // Calculate detailed metrics
        const metrics = analyzer.analyze(result.*) catch {
            // If analysis fails, fall back to basic metrics from BacktestResult
            return switch (self.config.objective) {
                .maximize_sharpe_ratio => result.profit_factor,
                .maximize_profit_factor => result.profit_factor,
                .maximize_win_rate => result.win_rate,
                .minimize_max_drawdown => -result.net_profit.toFloat(),
                .maximize_net_profit => result.net_profit.toFloat(),
                .maximize_total_return => blk: {
                    const initial = result.config.initial_capital;
                    if (initial.eql(root.Decimal.ZERO)) break :blk 0.0;
                    const final = initial.add(result.net_profit);
                    const ratio = final.div(initial) catch break :blk 0.0;
                    const return_pct = ratio.sub(root.Decimal.ONE);
                    break :blk return_pct.toFloat();
                },
                .custom => unreachable,
            };
        };

        // Use detailed metrics from PerformanceAnalyzer
        return switch (self.config.objective) {
            .maximize_sharpe_ratio => metrics.sharpe_ratio,
            .maximize_profit_factor => metrics.profit_factor,
            .maximize_win_rate => metrics.win_rate,
            .minimize_max_drawdown => -metrics.max_drawdown, // Negative because we maximize score
            .maximize_net_profit => metrics.net_profit.toFloat(),
            .maximize_total_return => metrics.total_return,
            .custom => unreachable, // Custom objectives not yet supported
        };
    }
};

// Tests
test "GridSearchOptimizer: initialization" {
    const allocator = std.testing.allocator;

    // Create a valid backtest config
    const backtest_config = BacktestConfig{
        .pair = root.TradingPair{ .base = "BTC", .quote = "USDC" },
        .timeframe = .h1,
        .start_time = root.Timestamp.fromSeconds(1000000),
        .end_time = root.Timestamp.fromSeconds(2000000),
        .initial_capital = root.Decimal.fromInt(10000),
        .commission_rate = root.Decimal.fromFloat(0.001),
        .slippage = root.Decimal.fromFloat(0.0005),
        .data_file = null,
    };

    const params = [_]types.StrategyParameter{
        .{
            .name = "period",
            .type = .integer,
            .default_value = types.ParameterValue{ .integer = 10 },
            .optimize = true,
            .range = types.ParameterRange{ .integer = .{ .min = 5, .max = 15, .step = 5 } },
        },
    };

    const config = OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = backtest_config,
        .parameters = &params,
        .max_combinations = null,
        .enable_parallel = false,
    };

    var optimizer = try GridSearchOptimizer.init(allocator, config);
    defer optimizer.deinit();

    try std.testing.expectEqual(OptimizationObjective.maximize_sharpe_ratio, optimizer.config.objective);
}

test "GridSearchOptimizer: score calculation" {
    const allocator = std.testing.allocator;

    // Create a mock backtest config first
    const backtest_config = BacktestConfig{
        .pair = root.TradingPair{ .base = "BTC", .quote = "USDC" },
        .timeframe = .h1,
        .start_time = root.Timestamp.fromSeconds(1000000),
        .end_time = root.Timestamp.fromSeconds(2000000),
        .initial_capital = root.Decimal.fromInt(10000),
        .commission_rate = root.Decimal.fromFloat(0.001),
        .slippage = root.Decimal.fromFloat(0.0005),
        .data_file = null,
    };

    const params = [_]types.StrategyParameter{
        .{
            .name = "period",
            .type = .integer,
            .default_value = types.ParameterValue{ .integer = 10 },
            .optimize = true,
            .range = types.ParameterRange{ .integer = .{ .min = 5, .max = 15, .step = 5 } },
        },
    };

    const config = OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = backtest_config,
        .parameters = &params,
        .max_combinations = null,
        .enable_parallel = false,
    };

    var optimizer = try GridSearchOptimizer.init(allocator, config);
    defer optimizer.deinit();

    // Create a mock backtest result
    var result = BacktestResult.init(allocator, backtest_config, "test_strategy");
    defer result.deinit();

    // Score should be calculated successfully
    const score = optimizer.calculateScore(&result);

    // Score should be a valid number
    try std.testing.expect(!std.math.isNan(score));
}
