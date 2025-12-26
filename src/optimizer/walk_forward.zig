/// Walk-Forward Analysis for Strategy Optimization
///
/// Implements Walk-Forward optimization to validate strategy parameters
/// and detect overfitting. Key features:
/// - Multiple data splitting strategies
/// - Rolling validation windows
/// - Overfitting detection
/// - Parameter stability analysis
///
/// Walk-Forward Process:
/// 1. Split data into training/testing windows
/// 2. Optimize parameters on training data
/// 3. Validate on out-of-sample testing data
/// 4. Roll forward and repeat
/// 5. Analyze overall robustness

const std = @import("std");
const root = @import("../root.zig");
const types = @import("types.zig");
const data_split = @import("data_split.zig");
const overfitting = @import("overfitting_detector.zig");
const grid_search = @import("grid_search.zig");

const Decimal = root.Decimal;
const Timestamp = root.Timestamp;
const Candle = root.Candle;
const Candles = root.Candles;
const BacktestEngine = root.BacktestEngine;
const BacktestConfig = root.BacktestConfig;
const BacktestResult = root.BacktestResult;
const PerformanceAnalyzer = root.PerformanceAnalyzer;
const PerformanceMetrics = root.PerformanceMetrics;
const IStrategy = root.IStrategy;
const Logger = root.Logger;
const LogWriter = root.logger.LogWriter;
const LogRecord = root.logger.LogRecord;

const ParameterSet = types.ParameterSet;
const OptimizationConfig = types.OptimizationConfig;
const GridSearchOptimizer = grid_search.GridSearchOptimizer;
const DataSplitter = data_split.DataSplitter;
const DataWindow = data_split.DataWindow;
const SplitConfig = data_split.SplitConfig;
const SplitStrategy = data_split.SplitStrategy;
const OverfittingDetector = overfitting.OverfittingDetector;
const OverfittingMetrics = overfitting.OverfittingMetrics;
const WindowPerformance = overfitting.WindowPerformance;
const DetectorConfig = overfitting.DetectorConfig;

// ============================================================================
// Walk-Forward Configuration
// ============================================================================

/// Walk-Forward analysis configuration
pub const WalkForwardConfig = struct {
    /// Data splitting configuration
    split_config: SplitConfig = .{},

    /// Overfitting detection configuration
    overfitting_config: DetectorConfig = .{},

    /// Whether to re-optimize on each window
    reoptimize_each_window: bool = true,

    /// Whether to use anchored first window
    use_anchor: bool = false,

    /// Minimum improvement threshold to accept new parameters
    min_improvement: f64 = 0.0,

    /// Enable verbose logging
    verbose: bool = false,

    /// Validate configuration
    pub fn validate(self: *const WalkForwardConfig) !void {
        try self.split_config.validate();
    }
};

// ============================================================================
// Walk-Forward Result Types
// ============================================================================

/// Result for a single window
pub const WindowResult = struct {
    /// Window identifier
    window_id: usize,

    /// Training period
    train_start: Timestamp,
    train_end: Timestamp,
    train_candles: usize,

    /// Testing period
    test_start: Timestamp,
    test_end: Timestamp,
    test_candles: usize,

    /// Best parameters found on training data
    best_params: ParameterSet,

    /// Training performance metrics
    train_metrics: WindowMetrics,

    /// Testing performance metrics (out-of-sample)
    test_metrics: WindowMetrics,

    /// Overfitting score for this window
    overfitting_score: f64,

    pub fn deinit(self: *WindowResult) void {
        self.best_params.deinit();
    }
};

/// Simplified metrics for window performance
pub const WindowMetrics = struct {
    sharpe_ratio: f64,
    total_return: f64,
    max_drawdown: f64,
    win_rate: f64,
    profit_factor: f64,
    trade_count: usize,

    /// Create from PerformanceMetrics
    pub fn fromPerformanceMetrics(pm: PerformanceMetrics) WindowMetrics {
        return .{
            .sharpe_ratio = pm.sharpe_ratio,
            .total_return = pm.total_return,
            .max_drawdown = pm.max_drawdown,
            .win_rate = pm.win_rate,
            .profit_factor = pm.profit_factor,
            .trade_count = pm.trade_count,
        };
    }

    /// Create from BacktestResult
    pub fn fromBacktestResult(br: BacktestResult) WindowMetrics {
        return .{
            .sharpe_ratio = 0, // Will be calculated separately
            .total_return = blk: {
                const initial = br.config.initial_capital;
                if (initial.eql(Decimal.ZERO)) break :blk 0;
                const final = initial.add(br.net_profit);
                const ratio = final.div(initial) catch break :blk 0;
                break :blk ratio.sub(Decimal.ONE).toFloat();
            },
            .max_drawdown = blk: {
                var max_dd: f64 = 0;
                var peak = br.config.initial_capital;
                for (br.equity_curve) |snapshot| {
                    if (snapshot.equity.cmp(peak) == .gt) {
                        peak = snapshot.equity;
                    }
                    const dd_decimal = peak.sub(snapshot.equity).div(peak) catch break :blk max_dd;
                    const dd = dd_decimal.toFloat();
                    if (dd > max_dd) {
                        max_dd = dd;
                    }
                }
                break :blk max_dd;
            },
            .win_rate = br.win_rate,
            .profit_factor = br.profit_factor,
            .trade_count = br.trades.len,
        };
    }
};

/// Overall statistics for Walk-Forward analysis
pub const OverallStats = struct {
    /// Average training Sharpe ratio
    avg_train_sharpe: f64,

    /// Average testing Sharpe ratio
    avg_test_sharpe: f64,

    /// Average training return
    avg_train_return: f64,

    /// Average testing return
    avg_test_return: f64,

    /// Consistency score (ratio of profitable test windows)
    consistency_score: f64,

    /// Parameter stability score
    param_stability: f64,

    /// Training/testing correlation
    train_test_correlation: f64,
};

/// Complete Walk-Forward analysis result
pub const WalkForwardResult = struct {
    allocator: std.mem.Allocator,

    /// Number of windows analyzed
    num_windows: usize,

    /// Results for each window
    window_results: []WindowResult,

    /// Overall statistics
    overall_stats: OverallStats,

    /// Overfitting metrics
    overfitting_metrics: OverfittingMetrics,

    /// Best overall parameters (most robust across windows)
    best_params: ParameterSet,

    /// Elapsed time in milliseconds
    elapsed_time_ms: u64,

    /// Deinitialize and free resources
    pub fn deinit(self: *WalkForwardResult) void {
        for (self.window_results) |*wr| {
            wr.deinit();
        }
        self.allocator.free(self.window_results);
        self.best_params.deinit();
    }

    /// Check if the analysis suggests the strategy is robust
    pub fn isRobust(self: *const WalkForwardResult) bool {
        return !self.overfitting_metrics.is_likely_overfitting and
            self.overall_stats.consistency_score > 0.5 and
            self.overall_stats.avg_test_sharpe > 0;
    }

    /// Get summary string
    pub fn getSummary(self: *const WalkForwardResult, writer: anytype) !void {
        try writer.print("Walk-Forward Analysis Summary\n", .{});
        try writer.print("============================\n", .{});
        try writer.print("Windows analyzed: {}\n", .{self.num_windows});
        try writer.print("Avg Train Sharpe: {d:.3}\n", .{self.overall_stats.avg_train_sharpe});
        try writer.print("Avg Test Sharpe:  {d:.3}\n", .{self.overall_stats.avg_test_sharpe});
        try writer.print("Consistency:      {d:.1}%\n", .{self.overall_stats.consistency_score * 100});
        try writer.print("Overfitting Prob: {d:.1}%\n", .{self.overfitting_metrics.overfitting_probability * 100});
        try writer.print("Recommendation:   {s}\n", .{@tagName(self.overfitting_metrics.recommendation)});
        try writer.print("Elapsed Time:     {}ms\n", .{self.elapsed_time_ms});
    }
};

// ============================================================================
// Walk-Forward Analyzer
// ============================================================================

/// Null writer for internal operations
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

    fn writeFn(_: *anyopaque, _: LogRecord) anyerror!void {}
    fn flushFn(_: *anyopaque) anyerror!void {}
    fn closeFn(_: *anyopaque) void {}
};

/// Walk-Forward Analyzer
pub const WalkForwardAnalyzer = struct {
    allocator: std.mem.Allocator,
    config: WalkForwardConfig,
    opt_config: OptimizationConfig,

    /// Initialize Walk-Forward analyzer
    pub fn init(
        allocator: std.mem.Allocator,
        config: WalkForwardConfig,
        opt_config: OptimizationConfig,
    ) !WalkForwardAnalyzer {
        try config.validate();
        try opt_config.validate();

        return .{
            .allocator = allocator,
            .config = config,
            .opt_config = opt_config,
        };
    }

    /// Deinitialize analyzer
    pub fn deinit(self: *WalkForwardAnalyzer) void {
        _ = self;
    }

    /// Run Walk-Forward analysis
    pub fn run(
        self: *WalkForwardAnalyzer,
        candle_data: []const Candle,
        strategy_factory: anytype,
    ) !WalkForwardResult {
        const start_time = std.time.milliTimestamp();

        // 1. Split data into windows
        var splitter = try DataSplitter.init(self.allocator, self.config.split_config);
        defer splitter.deinit();

        const windows = try splitter.split(candle_data);
        defer splitter.freeWindows(windows);

        // 2. Process each window
        const window_results = try self.allocator.alloc(WindowResult, windows.len);
        errdefer {
            for (window_results) |*wr| {
                wr.deinit();
            }
            self.allocator.free(window_results);
        }

        var window_performances = try self.allocator.alloc(WindowPerformance, windows.len);
        defer self.allocator.free(window_performances);

        for (windows, 0..) |window, i| {
            window_results[i] = try self.processWindow(window, strategy_factory);

            // Collect performance for overfitting analysis
            window_performances[i] = WindowPerformance{
                .window_id = i,
                .train_sharpe = window_results[i].train_metrics.sharpe_ratio,
                .test_sharpe = window_results[i].test_metrics.sharpe_ratio,
                .train_return = window_results[i].train_metrics.total_return,
                .test_return = window_results[i].test_metrics.total_return,
                .train_win_rate = window_results[i].train_metrics.win_rate,
                .test_win_rate = window_results[i].test_metrics.win_rate,
                .params = null,
            };
        }

        // 3. Calculate overall statistics
        const overall_stats = self.calculateOverallStats(window_results);

        // 4. Detect overfitting
        var detector = OverfittingDetector.init(self.allocator, self.config.overfitting_config);
        defer detector.deinit();
        const overfitting_metrics = try detector.analyze(window_performances);

        // 5. Find best overall parameters
        const best_params = try self.findBestParams(window_results, window_performances);

        const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));

        return WalkForwardResult{
            .allocator = self.allocator,
            .num_windows = windows.len,
            .window_results = window_results,
            .overall_stats = overall_stats,
            .overfitting_metrics = overfitting_metrics,
            .best_params = best_params,
            .elapsed_time_ms = elapsed,
        };
    }

    /// Process a single window
    fn processWindow(
        self: *WalkForwardAnalyzer,
        window: DataWindow,
        strategy_factory: anytype,
    ) !WindowResult {
        // Create modified backtest config for training data
        var train_config = self.opt_config.backtest_config;
        train_config.start_time = window.train_start;
        train_config.end_time = window.train_end;

        // Optimize on training data
        var train_opt_config = self.opt_config;
        train_opt_config.backtest_config = train_config;

        var optimizer = try GridSearchOptimizer.init(self.allocator, train_opt_config);
        defer optimizer.deinit();

        const opt_result = try optimizer.optimize(strategy_factory);
        defer {
            var result = opt_result;
            result.deinit();
        }

        // Get best parameters
        const best_params = try opt_result.best_params.clone(self.allocator);
        errdefer {
            var params = best_params;
            params.deinit();
        }

        // Validate on testing data
        var test_config = self.opt_config.backtest_config;
        test_config.start_time = window.test_start;
        test_config.end_time = window.test_end;

        // Run backtest on test data with best params
        const FactoryType = @TypeOf(strategy_factory);
        const type_info = @typeInfo(FactoryType);
        const uses_wrapper = type_info == .pointer and @hasDecl(type_info.pointer.child, "createStrategy");

        var strategy_or_wrapper = if (uses_wrapper)
            try strategy_factory.createStrategy(best_params)
        else
            try strategy_factory(best_params);
        defer strategy_or_wrapper.deinit();

        var null_writer = NullWriter.init();
        const log_writer = null_writer.writer();
        var logger = Logger.init(self.allocator, log_writer, .err);
        defer logger.deinit();

        var engine = BacktestEngine.init(self.allocator, logger);
        const strategy_interface = if (uses_wrapper) strategy_or_wrapper.interface else strategy_or_wrapper;
        const test_result = try engine.run(strategy_interface, test_config);

        // Calculate metrics
        const train_metrics = WindowMetrics.fromBacktestResult(opt_result.best_result.backtest_result);
        const test_metrics = WindowMetrics.fromBacktestResult(test_result);

        // Calculate overfitting score
        const train_sharpe = train_metrics.sharpe_ratio;
        const test_sharpe = test_metrics.sharpe_ratio;
        const overfitting_score = if (train_sharpe > 0)
            @max(0, (train_sharpe - test_sharpe) / train_sharpe)
        else
            0;

        return WindowResult{
            .window_id = window.window_id,
            .train_start = window.train_start,
            .train_end = window.train_end,
            .train_candles = window.train_data.len,
            .test_start = window.test_start,
            .test_end = window.test_end,
            .test_candles = window.test_data.len,
            .best_params = best_params,
            .train_metrics = train_metrics,
            .test_metrics = test_metrics,
            .overfitting_score = overfitting_score,
        };
    }

    /// Calculate overall statistics
    fn calculateOverallStats(
        self: *const WalkForwardAnalyzer,
        window_results: []const WindowResult,
    ) OverallStats {
        _ = self;

        if (window_results.len == 0) {
            return OverallStats{
                .avg_train_sharpe = 0,
                .avg_test_sharpe = 0,
                .avg_train_return = 0,
                .avg_test_return = 0,
                .consistency_score = 0,
                .param_stability = 0,
                .train_test_correlation = 0,
            };
        }

        var train_sharpe_sum: f64 = 0;
        var test_sharpe_sum: f64 = 0;
        var train_return_sum: f64 = 0;
        var test_return_sum: f64 = 0;
        var profitable_windows: usize = 0;

        for (window_results) |wr| {
            train_sharpe_sum += wr.train_metrics.sharpe_ratio;
            test_sharpe_sum += wr.test_metrics.sharpe_ratio;
            train_return_sum += wr.train_metrics.total_return;
            test_return_sum += wr.test_metrics.total_return;
            if (wr.test_metrics.total_return > 0) {
                profitable_windows += 1;
            }
        }

        const n: f64 = @floatFromInt(window_results.len);

        // Calculate correlation
        var train_sq_sum: f64 = 0;
        var test_sq_sum: f64 = 0;
        var product_sum: f64 = 0;
        const train_mean = train_sharpe_sum / n;
        const test_mean = test_sharpe_sum / n;

        for (window_results) |wr| {
            const train_diff = wr.train_metrics.sharpe_ratio - train_mean;
            const test_diff = wr.test_metrics.sharpe_ratio - test_mean;
            train_sq_sum += train_diff * train_diff;
            test_sq_sum += test_diff * test_diff;
            product_sum += train_diff * test_diff;
        }

        const denom = @sqrt(train_sq_sum * test_sq_sum);
        const correlation = if (denom > 0.001) product_sum / denom else 0;

        return OverallStats{
            .avg_train_sharpe = train_sharpe_sum / n,
            .avg_test_sharpe = test_sharpe_sum / n,
            .avg_train_return = train_return_sum / n,
            .avg_test_return = test_return_sum / n,
            .consistency_score = @as(f64, @floatFromInt(profitable_windows)) / n,
            .param_stability = 1.0 - @min(1.0, @abs(train_sharpe_sum / n - test_sharpe_sum / n)),
            .train_test_correlation = correlation,
        };
    }

    /// Find the best parameters across all windows
    fn findBestParams(
        self: *WalkForwardAnalyzer,
        window_results: []const WindowResult,
        window_performances: []const WindowPerformance,
    ) !ParameterSet {
        _ = window_performances;

        if (window_results.len == 0) {
            return ParameterSet.init(self.allocator);
        }

        // Find window with best test performance (adjusted for overfitting)
        var best_idx: usize = 0;
        var best_score: f64 = -std.math.inf(f64);

        for (window_results, 0..) |wr, i| {
            // Score = test_sharpe * (1 - overfitting_score)
            const score = wr.test_metrics.sharpe_ratio * (1.0 - wr.overfitting_score);
            if (score > best_score) {
                best_score = score;
                best_idx = i;
            }
        }

        return try window_results[best_idx].best_params.clone(self.allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "WalkForwardConfig: validation" {
    // Valid config
    const config = WalkForwardConfig{
        .split_config = .{
            .strategy = .rolling_window,
            .train_ratio = 0.7,
            .min_train_size = 50,
            .min_test_size = 20,
        },
    };
    try config.validate();

    // Invalid train ratio
    const bad_config = WalkForwardConfig{
        .split_config = .{
            .train_ratio = 1.5,
        },
    };
    try std.testing.expectError(error.InvalidTrainRatio, bad_config.validate());
}

test "WindowMetrics: from backtest result" {
    const allocator = std.testing.allocator;

    const backtest_config = BacktestConfig{
        .pair = root.TradingPair{ .base = "BTC", .quote = "USDT" },
        .timeframe = .h1,
        .start_time = Timestamp.fromSeconds(1000000),
        .end_time = Timestamp.fromSeconds(2000000),
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.fromFloat(0.0005),
        .data_file = null,
    };

    var result = BacktestResult.init(allocator, backtest_config, "test");
    defer result.deinit();

    const metrics = WindowMetrics.fromBacktestResult(result);

    try std.testing.expect(metrics.trade_count == 0);
    try std.testing.expect(metrics.win_rate == 0);
}

test "OverallStats: calculation" {
    const window_results = [_]WindowResult{
        .{
            .window_id = 0,
            .train_start = Timestamp.fromSeconds(0),
            .train_end = Timestamp.fromSeconds(100),
            .train_candles = 100,
            .test_start = Timestamp.fromSeconds(100),
            .test_end = Timestamp.fromSeconds(150),
            .test_candles = 50,
            .best_params = undefined, // Not used in calculation
            .train_metrics = .{
                .sharpe_ratio = 1.5,
                .total_return = 0.10,
                .max_drawdown = 0.05,
                .win_rate = 0.6,
                .profit_factor = 1.8,
                .trade_count = 10,
            },
            .test_metrics = .{
                .sharpe_ratio = 1.2,
                .total_return = 0.08,
                .max_drawdown = 0.06,
                .win_rate = 0.55,
                .profit_factor = 1.5,
                .trade_count = 5,
            },
            .overfitting_score = 0.2,
        },
    };

    const analyzer = WalkForwardAnalyzer{
        .allocator = std.testing.allocator,
        .config = .{},
        .opt_config = undefined,
    };

    const stats = analyzer.calculateOverallStats(&window_results);

    try std.testing.expectApproxEqAbs(@as(f64, 1.5), stats.avg_train_sharpe, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.2), stats.avg_test_sharpe, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), stats.consistency_score, 0.001);
}
