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
/// - Parallel execution support (v0.4.0)

const std = @import("std");
const root = @import("../root.zig");
const types = @import("types.zig");
const combination = @import("combination.zig");
const parallel_executor = @import("parallel_executor.zig");

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
    num_threads: ?usize,

    /// Progress callback type
    pub const ProgressCallback = *const fn (completed: usize, total: usize) void;

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
            .num_threads = null, // Auto-detect
        };
    }

    /// Initialize optimizer with specific thread count
    pub fn initWithThreads(
        allocator: std.mem.Allocator,
        config: OptimizationConfig,
        num_threads: usize,
    ) !GridSearchOptimizer {
        try config.validate();

        return .{
            .allocator = allocator,
            .config = config,
            .num_threads = num_threads,
        };
    }

    /// Deinitialize optimizer
    pub fn deinit(self: *GridSearchOptimizer) void {
        _ = self;
    }

    /// Run optimization (auto-selects parallel or sequential based on config)
    pub fn optimize(
        self: *GridSearchOptimizer,
        strategy_factory: anytype, // Function: (ParameterSet) -> !IStrategy
    ) !OptimizationResult {
        return self.optimizeWithProgress(strategy_factory, null);
    }

    /// Run optimization with progress callback
    pub fn optimizeWithProgress(
        self: *GridSearchOptimizer,
        strategy_factory: anytype,
        progress_callback: ?ProgressCallback,
    ) !OptimizationResult {
        if (self.config.enable_parallel) {
            return self.optimizeParallel(strategy_factory, progress_callback);
        } else {
            return self.optimizeSequential(strategy_factory, progress_callback);
        }
    }

    /// Typed strategy factory function pointer for parallel optimization
    pub const StrategyFactoryFn = *const fn (ParameterSet) anyerror!IStrategy;

    /// Run parallel optimization
    /// Note: Due to Zig's type system limitations with threading, this method
    /// currently runs sequentially. For true parallel execution, use
    /// `optimizeParallelTyped` with a typed function pointer.
    pub fn optimizeParallel(
        self: *GridSearchOptimizer,
        strategy_factory: anytype,
        progress_callback: ?ProgressCallback,
    ) !OptimizationResult {
        // Fall back to sequential execution for anytype factories
        // Zig doesn't support closures, so we can't pass anytype to thread functions
        return self.optimizeSequential(strategy_factory, progress_callback);
    }

    /// Run parallel optimization with typed function pointer
    /// This is the recommended method for parallel execution.
    /// The factory_fn must be a thread-safe function that creates strategies.
    pub fn optimizeParallelTyped(
        self: *GridSearchOptimizer,
        factory_fn: StrategyFactoryFn,
        progress_callback: ?ProgressCallback,
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

        // Determine thread count
        const num_threads = self.num_threads orelse @max(1, std.Thread.getCpuCount() catch 4);

        // For small task counts or single thread, run sequentially
        if (total_combinations <= num_threads or num_threads == 1) {
            return self.optimizeSequentialTyped(factory_fn, progress_callback);
        }

        // Allocate results array
        const results = try self.allocator.alloc(ParameterResult, total_combinations);
        errdefer self.allocator.free(results);

        // Atomic progress counter for thread-safe progress updates
        var completed_count = std.atomic.Value(usize).init(0);

        // Calculate partition sizes
        const tasks_per_thread = total_combinations / num_threads;
        const remainder = total_combinations % num_threads;

        // Spawn worker threads with pre-assigned task ranges
        const threads = try self.allocator.alloc(std.Thread, num_threads);
        defer self.allocator.free(threads);

        for (threads, 0..) |*thread, thread_id| {
            // Calculate range for this thread
            const start_idx = thread_id * tasks_per_thread + @min(thread_id, remainder);
            const extra: usize = if (thread_id < remainder) 1 else 0;
            const end_idx = start_idx + tasks_per_thread + extra;

            // Worker data
            const WorkerArgs = struct {
                allocator: std.mem.Allocator,
                combos: []ParameterSet,
                config: BacktestConfig,
                optimizer: *GridSearchOptimizer,
                res: []ParameterResult,
                start: usize,
                end: usize,
                completed: *std.atomic.Value(usize),
                total: usize,
                cb: ?ProgressCallback,
                factory: StrategyFactoryFn,
            };

            const args = WorkerArgs{
                .allocator = self.allocator,
                .combos = combinations,
                .config = self.config.backtest_config,
                .optimizer = self,
                .res = results,
                .start = start_idx,
                .end = end_idx,
                .completed = &completed_count,
                .total = total_combinations,
                .cb = progress_callback,
                .factory = factory_fn,
            };

            // Spawn thread
            thread.* = try std.Thread.spawn(.{}, workerThread, .{args});
        }

        // Wait for all threads to complete
        for (threads) |thread| {
            thread.join();
        }

        // Find best result
        var best_score: f64 = -std.math.inf(f64);
        var best_index: usize = 0;

        for (results, 0..) |result, i| {
            if (result.score > best_score) {
                best_score = result.score;
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

    /// Worker thread function for parallel typed optimization
    fn workerThread(args: anytype) void {
        for (args.start..args.end) |idx| {
            const params = args.combos[idx];

            // Clone parameters
            var cloned_params = params.clone(args.allocator) catch continue;

            // Create strategy using typed function pointer
            var strategy = args.factory(params) catch {
                cloned_params.deinit();
                continue;
            };
            defer strategy.deinit();

            // Create null logger
            var null_writer = NullWriter.init();
            const log_writer = null_writer.writer();
            var logger = Logger.init(args.allocator, log_writer, .err);
            defer logger.deinit();

            // Run backtest
            var engine = BacktestEngine.init(args.allocator, logger);
            const backtest_result = engine.run(strategy, args.config) catch {
                cloned_params.deinit();
                continue;
            };

            // Calculate score
            const score = args.optimizer.calculateScore(&backtest_result);

            // Store result (thread-safe - each task writes to unique index)
            args.res[idx] = ParameterResult{
                .params = cloned_params,
                .backtest_result = backtest_result,
                .score = score,
            };

            // Update progress atomically
            const done = args.completed.fetchAdd(1, .monotonic) + 1;
            if (args.cb) |callback| {
                callback(done, args.total);
            }
        }
    }

    /// Sequential optimization with typed function pointer
    fn optimizeSequentialTyped(
        self: *GridSearchOptimizer,
        factory_fn: StrategyFactoryFn,
        progress_callback: ?ProgressCallback,
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

            // Create strategy with typed factory
            var strategy = try factory_fn(params);
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

            // Progress callback
            if (progress_callback) |cb| {
                cb(i + 1, total_combinations);
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

    /// Run sequential optimization (original implementation)
    pub fn optimizeSequential(
        self: *GridSearchOptimizer,
        strategy_factory: anytype,
        progress_callback: ?ProgressCallback,
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
            // Support both function pointers and struct pointers with createStrategy method
            const FactoryType = @TypeOf(strategy_factory);
            const type_info = @typeInfo(FactoryType);
            const uses_wrapper = type_info == .pointer and @hasDecl(type_info.pointer.child, "createStrategy");

            // Create strategy - could be wrapper or direct IStrategy
            var strategy_or_wrapper = if (uses_wrapper)
                try strategy_factory.createStrategy(params)
            else
                try strategy_factory(params);
            defer strategy_or_wrapper.deinit();

            // Create null logger for backtest
            var null_writer = NullWriter.init();
            const log_writer = null_writer.writer();
            var logger = Logger.init(self.allocator, log_writer, .err);
            defer logger.deinit();

            // Run backtest - extract interface if wrapper, otherwise use directly
            var engine = BacktestEngine.init(self.allocator, logger);
            const strategy_interface = if (uses_wrapper) strategy_or_wrapper.interface else strategy_or_wrapper;
            const backtest_result = try engine.run(strategy_interface, self.config.backtest_config);

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

            // Progress callback
            if (progress_callback) |cb| {
                cb(i + 1, total_combinations);
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
            return self.calculateBasicScore(result);
        };

        // Use detailed metrics from PerformanceAnalyzer
        return switch (self.config.objective) {
            // v0.3.0 objectives
            .maximize_sharpe_ratio => metrics.sharpe_ratio,
            .maximize_profit_factor => metrics.profit_factor,
            .maximize_win_rate => metrics.win_rate,
            .minimize_max_drawdown => -metrics.max_drawdown, // Negative because we maximize score
            .maximize_net_profit => metrics.net_profit.toFloat(),
            .maximize_total_return => metrics.total_return,

            // v0.4.0 new objectives
            .maximize_sortino_ratio => self.calculateSortinoRatio(result, &metrics),
            .maximize_calmar_ratio => self.calculateCalmarRatio(&metrics),
            .maximize_omega_ratio => self.calculateOmegaRatio(result),
            .maximize_tail_ratio => self.calculateTailRatio(result),
            .maximize_stability => self.calculateStabilityScore(result),
            .maximize_risk_adjusted_return => self.calculateRiskAdjustedReturn(&metrics),

            .custom => unreachable, // Custom objectives not yet supported
        };
    }

    /// Calculate basic score when advanced analysis fails
    fn calculateBasicScore(self: *const GridSearchOptimizer, result: *const BacktestResult) f64 {
        return switch (self.config.objective) {
            .maximize_sharpe_ratio => result.profit_factor,
            .maximize_profit_factor => result.profit_factor,
            .maximize_win_rate => result.win_rate,
            .minimize_max_drawdown => -result.net_profit.toFloat(),
            .maximize_net_profit => result.net_profit.toFloat(),
            .maximize_total_return, .maximize_calmar_ratio => blk: {
                const initial = result.config.initial_capital;
                if (initial.eql(root.Decimal.ZERO)) break :blk 0.0;
                const final = initial.add(result.net_profit);
                const ratio = final.div(initial) catch break :blk 0.0;
                const return_pct = ratio.sub(root.Decimal.ONE);
                break :blk return_pct.toFloat();
            },
            .maximize_sortino_ratio => result.profit_factor, // Fallback
            .maximize_omega_ratio => result.profit_factor,
            .maximize_tail_ratio => result.profit_factor,
            .maximize_stability => result.win_rate,
            .maximize_risk_adjusted_return => result.profit_factor * result.win_rate,
            .custom => unreachable,
        };
    }

    /// Calculate Sortino Ratio (downside deviation only)
    fn calculateSortinoRatio(
        self: *const GridSearchOptimizer,
        result: *const BacktestResult,
        metrics: *const PerformanceMetrics,
    ) f64 {
        _ = self;
        if (result.trades.len < 2) return 0;

        // Calculate downside deviation
        var downside_sum: f64 = 0;
        var count: usize = 0;

        for (result.trades) |trade| {
            const pnl = trade.pnl.toFloat();
            if (pnl < 0) {
                downside_sum += pnl * pnl;
                count += 1;
            }
        }

        if (count == 0) {
            // No losing trades - return high score
            return metrics.total_return * 10;
        }

        const downside_dev = @sqrt(downside_sum / @as(f64, @floatFromInt(count)));
        if (downside_dev < 0.0001) return metrics.total_return * 10;

        return metrics.total_return / downside_dev;
    }

    /// Calculate Calmar Ratio (return / max drawdown)
    fn calculateCalmarRatio(self: *const GridSearchOptimizer, metrics: *const PerformanceMetrics) f64 {
        _ = self;
        if (metrics.max_drawdown < 0.0001) {
            return metrics.total_return * 10;
        }
        return metrics.total_return / metrics.max_drawdown;
    }

    /// Calculate Omega Ratio (probability weighted gains/losses)
    fn calculateOmegaRatio(self: *const GridSearchOptimizer, result: *const BacktestResult) f64 {
        _ = self;
        if (result.trades.len == 0) return 0;

        var gains_sum: f64 = 0;
        var losses_sum: f64 = 0;

        for (result.trades) |trade| {
            const pnl = trade.pnl.toFloat();
            if (pnl > 0) {
                gains_sum += pnl;
            } else {
                losses_sum += @abs(pnl);
            }
        }

        if (losses_sum < 0.0001) return gains_sum * 10;
        return gains_sum / losses_sum;
    }

    /// Calculate Tail Ratio (right tail / left tail)
    fn calculateTailRatio(self: *const GridSearchOptimizer, result: *const BacktestResult) f64 {
        _ = self;
        if (result.trades.len < 10) return 1.0;

        // Use a fixed-size buffer for sorting
        var pnl_buf: [2048]f64 = undefined;
        const len = @min(result.trades.len, pnl_buf.len);

        for (result.trades[0..len], 0..) |trade, i| {
            pnl_buf[i] = trade.pnl.toFloat();
        }

        const pnls = pnl_buf[0..len];
        if (pnls.len < 10) return 1.0;

        std.sort.pdq(f64, @constCast(pnls), {}, std.sort.asc(f64));

        // Get 5th and 95th percentile
        const p5_idx = pnls.len / 20;
        const p95_idx = pnls.len - pnls.len / 20 - 1;

        const left_tail = @abs(pnls[p5_idx]);
        const right_tail = @abs(pnls[p95_idx]);

        if (left_tail < 0.0001) return right_tail * 10;
        return right_tail / left_tail;
    }

    /// Calculate stability score (consistency of returns)
    fn calculateStabilityScore(self: *const GridSearchOptimizer, result: *const BacktestResult) f64 {
        _ = self;
        if (result.equity_curve.len < 10) return 0.5;

        // Calculate R-squared of equity curve (linearity)
        var sum_x: f64 = 0;
        var sum_y: f64 = 0;
        var sum_xy: f64 = 0;
        var sum_x2: f64 = 0;
        var sum_y2: f64 = 0;
        const n: f64 = @floatFromInt(result.equity_curve.len);

        for (result.equity_curve, 0..) |snapshot, i| {
            const x: f64 = @floatFromInt(i);
            const y = snapshot.equity.toFloat();
            sum_x += x;
            sum_y += y;
            sum_xy += x * y;
            sum_x2 += x * x;
            sum_y2 += y * y;
        }

        const numerator = n * sum_xy - sum_x * sum_y;
        const denominator = @sqrt((n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y));

        if (denominator < 0.0001) return 0.5;

        const r = numerator / denominator;
        return r * r; // R-squared
    }

    /// Calculate risk-adjusted return (Sharpe-like with profit factor adjustment)
    fn calculateRiskAdjustedReturn(
        self: *const GridSearchOptimizer,
        metrics: *const PerformanceMetrics,
    ) f64 {
        _ = self;
        // Combine Sharpe ratio with profit factor
        const sharpe_component = @max(0, metrics.sharpe_ratio);
        const pf_component = @min(3.0, metrics.profit_factor) / 3.0; // Normalize to 0-1
        const wr_component = metrics.win_rate;

        return sharpe_component * 0.5 + pf_component * 0.3 + wr_component * 0.2;
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
