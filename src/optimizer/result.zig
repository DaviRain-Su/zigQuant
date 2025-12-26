/// Optimization Result Analysis
///
/// Provides analysis and visualization tools for optimization results:
/// - Result filtering and ranking
/// - Statistical analysis
/// - Parameter correlation
/// - Result export and reporting

const std = @import("std");
const root = @import("../root.zig");
const types = @import("types.zig");

const OptimizationResult = types.OptimizationResult;
const ParameterResult = types.ParameterResult;
const ParameterSet = types.ParameterSet;
const ParameterValue = types.ParameterValue;

/// Result Analyzer - provides statistical analysis of optimization results
pub const ResultAnalyzer = struct {
    allocator: std.mem.Allocator,
    result: *const OptimizationResult,

    /// Initialize analyzer
    pub fn init(allocator: std.mem.Allocator, result: *const OptimizationResult) ResultAnalyzer {
        return .{
            .allocator = allocator,
            .result = result,
        };
    }

    /// Deinitialize analyzer
    pub fn deinit(self: *ResultAnalyzer) void {
        _ = self;
    }

    /// Get top N results sorted by score
    pub fn getTopN(self: *ResultAnalyzer, n: usize) ![]const ParameterResult {
        const top_n = @min(n, self.result.all_results.len);

        // Create a copy and sort
        var sorted = try self.allocator.alloc(ParameterResult, self.result.all_results.len);
        @memcpy(sorted, self.result.all_results);

        std.sort.pdq(ParameterResult, sorted, {}, struct {
            fn lessThan(_: void, a: ParameterResult, b: ParameterResult) bool {
                return a.score > b.score; // Descending order
            }
        }.lessThan);

        // Return only top N
        const result = try self.allocator.alloc(ParameterResult, top_n);
        @memcpy(result, sorted[0..top_n]);
        self.allocator.free(sorted);

        return result;
    }

    /// Calculate basic statistics of scores
    pub fn getScoreStatistics(self: *ResultAnalyzer) ScoreStatistics {
        if (self.result.all_results.len == 0) {
            return .{
                .min = 0.0,
                .max = 0.0,
                .mean = 0.0,
                .median = 0.0,
                .std_dev = 0.0,
            };
        }

        var min: f64 = std.math.inf(f64);
        var max: f64 = -std.math.inf(f64);
        var sum: f64 = 0.0;

        // Calculate min, max, and sum
        for (self.result.all_results) |res| {
            min = @min(min, res.score);
            max = @max(max, res.score);
            sum += res.score;
        }

        const mean = sum / @as(f64, @floatFromInt(self.result.all_results.len));

        // Calculate variance and standard deviation
        var variance_sum: f64 = 0.0;
        for (self.result.all_results) |res| {
            const diff = res.score - mean;
            variance_sum += diff * diff;
        }
        const variance = variance_sum / @as(f64, @floatFromInt(self.result.all_results.len));
        const std_dev = @sqrt(variance);

        // Calculate median
        var scores = self.allocator.alloc(f64, self.result.all_results.len) catch {
            // If allocation fails, return without median
            return .{
                .min = min,
                .max = max,
                .mean = mean,
                .median = mean,
                .std_dev = std_dev,
            };
        };
        defer self.allocator.free(scores);

        for (self.result.all_results, 0..) |res, i| {
            scores[i] = res.score;
        }

        std.sort.pdq(f64, scores, {}, struct {
            fn lessThan(_: void, a: f64, b: f64) bool {
                return a < b;
            }
        }.lessThan);

        const median = if (scores.len % 2 == 0)
            (scores[scores.len / 2 - 1] + scores[scores.len / 2]) / 2.0
        else
            scores[scores.len / 2];

        return .{
            .min = min,
            .max = max,
            .mean = mean,
            .median = median,
            .std_dev = std_dev,
        };
    }

    /// Filter results by score threshold
    pub fn filterByScore(self: *ResultAnalyzer, min_score: f64) ![]const ParameterResult {
        var filtered = std.ArrayList(ParameterResult).init(self.allocator);
        defer filtered.deinit();

        for (self.result.all_results) |res| {
            if (res.score >= min_score) {
                try filtered.append(res);
            }
        }

        return filtered.toOwnedSlice();
    }

    /// Get results sorted by score (descending)
    pub fn getSortedResults(self: *ResultAnalyzer) ![]ParameterResult {
        const sorted = try self.allocator.alloc(ParameterResult, self.result.all_results.len);
        @memcpy(sorted, self.result.all_results);

        std.sort.pdq(ParameterResult, sorted, {}, struct {
            fn lessThan(_: void, a: ParameterResult, b: ParameterResult) bool {
                return a.score > b.score;
            }
        }.lessThan);

        return sorted;
    }
};

/// Score statistics
pub const ScoreStatistics = struct {
    min: f64,
    max: f64,
    mean: f64,
    median: f64,
    std_dev: f64,

    /// Format statistics for display
    pub fn format(
        self: ScoreStatistics,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Score Statistics:\n", .{});
        try writer.print("  Min:    {d:.4}\n", .{self.min});
        try writer.print("  Max:    {d:.4}\n", .{self.max});
        try writer.print("  Mean:   {d:.4}\n", .{self.mean});
        try writer.print("  Median: {d:.4}\n", .{self.median});
        try writer.print("  StdDev: {d:.4}\n", .{self.std_dev});
    }
};

// Tests
test "ResultAnalyzer: basic statistics" {
    const allocator = std.testing.allocator;

    // Create mock backtest config
    const backtest_config = root.BacktestConfig{
        .pair = root.TradingPair{ .base = "BTC", .quote = "USDC" },
        .timeframe = .h1,
        .start_time = root.Timestamp.fromSeconds(1000000),
        .end_time = root.Timestamp.fromSeconds(2000000),
        .initial_capital = root.Decimal.fromInt(10000),
        .commission_rate = root.Decimal.fromFloat(0.001),
        .slippage = root.Decimal.fromFloat(0.0005),
    };

    // Create mock parameter results
    var results = [_]ParameterResult{
        .{
            .params = types.ParameterSet.init(allocator),
            .backtest_result = root.BacktestResult.init(allocator, backtest_config, "test"),
            .score = 1.5,
        },
        .{
            .params = types.ParameterSet.init(allocator),
            .backtest_result = root.BacktestResult.init(allocator, backtest_config, "test"),
            .score = 2.5,
        },
        .{
            .params = types.ParameterSet.init(allocator),
            .backtest_result = root.BacktestResult.init(allocator, backtest_config, "test"),
            .score = 3.5,
        },
    };
    defer {
        for (&results) |*res| {
            res.params.deinit();
            res.backtest_result.deinit();
        }
    }

    // Create optimization result
    const best_params = types.ParameterSet.init(allocator);
    var opt_result = OptimizationResult{
        .allocator = allocator,
        .objective = .maximize_sharpe_ratio,
        .best_params = best_params,
        .best_score = 3.5,
        .all_results = &results,
        .total_combinations = 3,
        .elapsed_time_ms = 1000,
    };
    defer opt_result.best_params.deinit();

    // Create analyzer
    var analyzer = ResultAnalyzer.init(allocator, &opt_result);
    defer analyzer.deinit();

    // Get statistics
    const stats = analyzer.getScoreStatistics();

    try std.testing.expectEqual(@as(f64, 1.5), stats.min);
    try std.testing.expectEqual(@as(f64, 3.5), stats.max);
    try std.testing.expectApproxEqRel(@as(f64, 2.5), stats.mean, 0.01);
    try std.testing.expectApproxEqRel(@as(f64, 2.5), stats.median, 0.01);
}

test "ResultAnalyzer: get top N" {
    const allocator = std.testing.allocator;

    // Create mock backtest config
    const backtest_config = root.BacktestConfig{
        .pair = root.TradingPair{ .base = "BTC", .quote = "USDC" },
        .timeframe = .h1,
        .start_time = root.Timestamp.fromSeconds(1000000),
        .end_time = root.Timestamp.fromSeconds(2000000),
        .initial_capital = root.Decimal.fromInt(10000),
        .commission_rate = root.Decimal.fromFloat(0.001),
        .slippage = root.Decimal.fromFloat(0.0005),
    };

    // Create mock parameter results with different scores
    var results = [_]ParameterResult{
        .{
            .params = types.ParameterSet.init(allocator),
            .backtest_result = root.BacktestResult.init(allocator, backtest_config, "test"),
            .score = 1.0,
        },
        .{
            .params = types.ParameterSet.init(allocator),
            .backtest_result = root.BacktestResult.init(allocator, backtest_config, "test"),
            .score = 3.0,
        },
        .{
            .params = types.ParameterSet.init(allocator),
            .backtest_result = root.BacktestResult.init(allocator, backtest_config, "test"),
            .score = 2.0,
        },
    };
    defer {
        for (&results) |*res| {
            res.params.deinit();
            res.backtest_result.deinit();
        }
    }

    // Create optimization result
    const best_params = types.ParameterSet.init(allocator);
    var opt_result = OptimizationResult{
        .allocator = allocator,
        .objective = .maximize_sharpe_ratio,
        .best_params = best_params,
        .best_score = 3.0,
        .all_results = &results,
        .total_combinations = 3,
        .elapsed_time_ms = 1000,
    };
    defer opt_result.best_params.deinit();

    // Create analyzer
    var analyzer = ResultAnalyzer.init(allocator, &opt_result);
    defer analyzer.deinit();

    // Get top 2 results
    const top2 = try analyzer.getTopN(2);
    defer allocator.free(top2);

    try std.testing.expectEqual(@as(usize, 2), top2.len);
    try std.testing.expectEqual(@as(f64, 3.0), top2[0].score);
    try std.testing.expectEqual(@as(f64, 2.0), top2[1].score);
}
