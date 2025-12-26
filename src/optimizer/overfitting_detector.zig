/// Overfitting Detection for Walk-Forward Analysis
///
/// Provides tools to detect and quantify overfitting in optimized strategies.
/// Key metrics:
/// - Train/test performance gap
/// - Parameter sensitivity
/// - Stability score
/// - Overfitting probability

const std = @import("std");
const root = @import("../root.zig");

const Decimal = root.Decimal;
const PerformanceMetrics = root.PerformanceMetrics;
const ParameterSet = @import("types.zig").ParameterSet;

// ============================================================================
// Overfitting Metrics
// ============================================================================

/// Comprehensive overfitting metrics
pub const OverfittingMetrics = struct {
    /// Average gap between training and testing Sharpe ratio
    train_test_gap: f64,

    /// Coefficient of variation of testing performance
    test_performance_cv: f64,

    /// Parameter sensitivity score (higher = more sensitive)
    param_sensitivity: f64,

    /// Overall stability score (0-1, higher = more stable)
    stability_score: f64,

    /// Estimated overfitting probability (0-1)
    overfitting_probability: f64,

    /// Whether the strategy is likely overfitted
    is_likely_overfitting: bool,

    /// Recommended action based on metrics
    recommendation: Recommendation,

    pub const Recommendation = enum {
        /// Parameters look robust
        proceed,
        /// Some concern, consider wider validation
        caution,
        /// High overfitting risk, re-evaluate strategy
        reject,
        /// Insufficient data to assess
        insufficient_data,
    };

    /// Format metrics for display
    pub fn format(
        self: OverfittingMetrics,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("OverfittingMetrics{{\n", .{});
        try writer.print("  train_test_gap: {d:.4}\n", .{self.train_test_gap});
        try writer.print("  test_performance_cv: {d:.4}\n", .{self.test_performance_cv});
        try writer.print("  param_sensitivity: {d:.4}\n", .{self.param_sensitivity});
        try writer.print("  stability_score: {d:.4}\n", .{self.stability_score});
        try writer.print("  overfitting_probability: {d:.2}%\n", .{self.overfitting_probability * 100});
        try writer.print("  is_likely_overfitting: {}\n", .{self.is_likely_overfitting});
        try writer.print("  recommendation: {s}\n", .{@tagName(self.recommendation)});
        try writer.print("}}", .{});
    }
};

/// Performance metrics for a single window
pub const WindowPerformance = struct {
    window_id: usize,
    train_sharpe: f64,
    test_sharpe: f64,
    train_return: f64,
    test_return: f64,
    train_win_rate: f64,
    test_win_rate: f64,
    params: ?ParameterSet,

    /// Calculate the train/test gap for this window
    pub fn sharpeGap(self: *const WindowPerformance) f64 {
        return self.train_sharpe - self.test_sharpe;
    }

    /// Calculate return gap
    pub fn returnGap(self: *const WindowPerformance) f64 {
        return self.train_return - self.test_return;
    }
};

// ============================================================================
// Overfitting Detector
// ============================================================================

/// Configuration for overfitting detection
pub const DetectorConfig = struct {
    /// Threshold for train/test gap to flag overfitting
    gap_threshold: f64 = 0.5,

    /// Threshold for CV to flag instability
    cv_threshold: f64 = 0.5,

    /// Weight for gap in probability calculation
    gap_weight: f64 = 0.4,

    /// Weight for CV in probability calculation
    cv_weight: f64 = 0.3,

    /// Weight for sensitivity in probability calculation
    sensitivity_weight: f64 = 0.3,

    /// Probability threshold to flag as overfitting
    probability_threshold: f64 = 0.7,
};

/// Detects overfitting in optimization results
pub const OverfittingDetector = struct {
    allocator: std.mem.Allocator,
    config: DetectorConfig,

    /// Initialize detector
    pub fn init(allocator: std.mem.Allocator, config: DetectorConfig) OverfittingDetector {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Deinitialize detector
    pub fn deinit(self: *OverfittingDetector) void {
        _ = self;
    }

    /// Analyze window performances for overfitting
    pub fn analyze(
        self: *OverfittingDetector,
        window_performances: []const WindowPerformance,
    ) !OverfittingMetrics {
        if (window_performances.len == 0) {
            return OverfittingMetrics{
                .train_test_gap = 0,
                .test_performance_cv = 0,
                .param_sensitivity = 0,
                .stability_score = 0,
                .overfitting_probability = 0,
                .is_likely_overfitting = false,
                .recommendation = .insufficient_data,
            };
        }

        // Calculate train/test gap
        const gap = self.calculateTrainTestGap(window_performances);

        // Calculate test performance coefficient of variation
        const cv = try self.calculateTestCV(window_performances);

        // Calculate parameter sensitivity
        const sensitivity = self.calculateParamSensitivity(window_performances);

        // Calculate stability score
        const stability = self.calculateStability(gap, cv, sensitivity);

        // Calculate overfitting probability
        const prob = self.calculateOverfittingProbability(gap, cv, sensitivity);

        // Determine recommendation
        const recommendation = self.getRecommendation(prob, stability, window_performances.len);

        return OverfittingMetrics{
            .train_test_gap = gap,
            .test_performance_cv = cv,
            .param_sensitivity = sensitivity,
            .stability_score = stability,
            .overfitting_probability = prob,
            .is_likely_overfitting = prob > self.config.probability_threshold,
            .recommendation = recommendation,
        };
    }

    /// Calculate average train/test Sharpe gap
    fn calculateTrainTestGap(
        self: *const OverfittingDetector,
        windows: []const WindowPerformance,
    ) f64 {
        _ = self;

        if (windows.len == 0) return 0;

        var total_gap: f64 = 0;
        for (windows) |w| {
            total_gap += @abs(w.sharpeGap());
        }

        return total_gap / @as(f64, @floatFromInt(windows.len));
    }

    /// Calculate coefficient of variation of test performance
    fn calculateTestCV(
        self: *OverfittingDetector,
        windows: []const WindowPerformance,
    ) !f64 {
        _ = self;
        if (windows.len < 2) return 0;

        // Calculate mean
        var sum: f64 = 0;
        for (windows) |w| {
            sum += w.test_sharpe;
        }
        const mean = sum / @as(f64, @floatFromInt(windows.len));

        // Calculate variance
        var var_sum: f64 = 0;
        for (windows) |w| {
            const diff = w.test_sharpe - mean;
            var_sum += diff * diff;
        }
        const variance = var_sum / @as(f64, @floatFromInt(windows.len - 1));
        const std_dev = @sqrt(variance);

        // CV = std_dev / |mean|
        if (@abs(mean) < 0.001) {
            // If mean is near zero, use std_dev as proxy
            return @min(1.0, std_dev);
        }

        return @min(2.0, std_dev / @abs(mean));
    }

    /// Calculate parameter sensitivity
    fn calculateParamSensitivity(
        self: *const OverfittingDetector,
        windows: []const WindowPerformance,
    ) f64 {
        _ = self;

        if (windows.len < 2) return 0;

        // Calculate variance in best parameters across windows
        // For now, use performance variance as a proxy
        var max_sharpe: f64 = -std.math.inf(f64);
        var min_sharpe: f64 = std.math.inf(f64);

        for (windows) |w| {
            max_sharpe = @max(max_sharpe, w.train_sharpe);
            min_sharpe = @min(min_sharpe, w.train_sharpe);
        }

        const range = max_sharpe - min_sharpe;

        // Normalize to [0, 1]
        return @min(1.0, range / 2.0);
    }

    /// Calculate overall stability score
    fn calculateStability(
        self: *const OverfittingDetector,
        gap: f64,
        cv: f64,
        sensitivity: f64,
    ) f64 {
        _ = self;

        // Stability is inverse of instability factors
        const gap_factor = 1.0 - @min(1.0, gap);
        const cv_factor = 1.0 - @min(1.0, cv);
        const sens_factor = 1.0 - sensitivity;

        // Weighted average
        return (gap_factor * 0.4 + cv_factor * 0.3 + sens_factor * 0.3);
    }

    /// Calculate overfitting probability
    fn calculateOverfittingProbability(
        self: *const OverfittingDetector,
        gap: f64,
        cv: f64,
        sensitivity: f64,
    ) f64 {
        // Normalize factors
        const gap_score = @min(1.0, gap / self.config.gap_threshold);
        const cv_score = @min(1.0, cv / self.config.cv_threshold);
        const sens_score = sensitivity;

        // Weighted probability
        const prob = gap_score * self.config.gap_weight +
            cv_score * self.config.cv_weight +
            sens_score * self.config.sensitivity_weight;

        return @min(1.0, @max(0.0, prob));
    }

    /// Get recommendation based on metrics
    fn getRecommendation(
        self: *const OverfittingDetector,
        probability: f64,
        stability: f64,
        num_windows: usize,
    ) OverfittingMetrics.Recommendation {
        _ = self;

        if (num_windows < 3) {
            return .insufficient_data;
        }

        if (probability > 0.8 or stability < 0.3) {
            return .reject;
        }

        if (probability > 0.5 or stability < 0.5) {
            return .caution;
        }

        return .proceed;
    }
};

/// Statistics helper for analyzing parameter stability
pub const ParameterStabilityAnalyzer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ParameterStabilityAnalyzer {
        return .{ .allocator = allocator };
    }

    /// Analyze how stable parameters are across windows
    pub fn analyzeStability(
        self: *ParameterStabilityAnalyzer,
        windows: []const WindowPerformance,
    ) !StabilityReport {
        _ = self;

        if (windows.len < 2) {
            return StabilityReport{
                .overall_stability = 1.0,
                .consistent_windows = windows.len,
                .total_windows = windows.len,
                .performance_correlation = 1.0,
            };
        }

        // Calculate correlation between train and test performance
        var train_sum: f64 = 0;
        var test_sum: f64 = 0;
        var train_sq_sum: f64 = 0;
        var test_sq_sum: f64 = 0;
        var product_sum: f64 = 0;
        const n: f64 = @floatFromInt(windows.len);

        for (windows) |w| {
            train_sum += w.train_sharpe;
            test_sum += w.test_sharpe;
            train_sq_sum += w.train_sharpe * w.train_sharpe;
            test_sq_sum += w.test_sharpe * w.test_sharpe;
            product_sum += w.train_sharpe * w.test_sharpe;
        }

        // Pearson correlation coefficient
        const numerator = n * product_sum - train_sum * test_sum;
        const denominator = @sqrt((n * train_sq_sum - train_sum * train_sum) *
            (n * test_sq_sum - test_sum * test_sum));

        const correlation = if (denominator > 0.001) numerator / denominator else 0;

        // Count consistent windows (test performance > 0)
        var consistent: usize = 0;
        for (windows) |w| {
            if (w.test_sharpe > 0) {
                consistent += 1;
            }
        }

        const consistency_ratio: f64 = @as(f64, @floatFromInt(consistent)) / n;

        return StabilityReport{
            .overall_stability = @max(0, (correlation + 1) / 2 * consistency_ratio),
            .consistent_windows = consistent,
            .total_windows = windows.len,
            .performance_correlation = correlation,
        };
    }
};

/// Report on parameter stability
pub const StabilityReport = struct {
    /// Overall stability score (0-1)
    overall_stability: f64,

    /// Number of windows with positive test performance
    consistent_windows: usize,

    /// Total number of windows analyzed
    total_windows: usize,

    /// Correlation between train and test performance
    performance_correlation: f64,

    /// Check if strategy is stable enough
    pub fn isStable(self: *const StabilityReport) bool {
        return self.overall_stability > 0.5 and
            self.consistent_windows >= self.total_windows / 2;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "OverfittingDetector: basic analysis" {
    const allocator = std.testing.allocator;

    var detector = OverfittingDetector.init(allocator, .{});
    defer detector.deinit();

    // Create sample window performances
    const windows = [_]WindowPerformance{
        .{
            .window_id = 0,
            .train_sharpe = 2.0,
            .test_sharpe = 1.5,
            .train_return = 0.10,
            .test_return = 0.08,
            .train_win_rate = 0.6,
            .test_win_rate = 0.55,
            .params = null,
        },
        .{
            .window_id = 1,
            .train_sharpe = 1.8,
            .test_sharpe = 1.4,
            .train_return = 0.09,
            .test_return = 0.07,
            .train_win_rate = 0.58,
            .test_win_rate = 0.54,
            .params = null,
        },
        .{
            .window_id = 2,
            .train_sharpe = 2.2,
            .test_sharpe = 1.6,
            .train_return = 0.11,
            .test_return = 0.09,
            .train_win_rate = 0.62,
            .test_win_rate = 0.57,
            .params = null,
        },
    };

    const metrics = try detector.analyze(&windows);

    // Train-test gap should be moderate (around 0.5)
    try std.testing.expect(metrics.train_test_gap > 0);
    try std.testing.expect(metrics.train_test_gap < 1.0);

    // Should not be flagged as overfitting with consistent performance
    try std.testing.expect(!metrics.is_likely_overfitting);
}

test "OverfittingDetector: high overfitting scenario" {
    const allocator = std.testing.allocator;

    var detector = OverfittingDetector.init(allocator, .{});
    defer detector.deinit();

    // Create window performances with large train/test gap (overfitting)
    const windows = [_]WindowPerformance{
        .{
            .window_id = 0,
            .train_sharpe = 3.0,
            .test_sharpe = 0.5, // Big gap!
            .train_return = 0.20,
            .test_return = 0.02,
            .train_win_rate = 0.7,
            .test_win_rate = 0.45,
            .params = null,
        },
        .{
            .window_id = 1,
            .train_sharpe = 2.8,
            .test_sharpe = -0.2, // Negative test!
            .train_return = 0.18,
            .test_return = -0.01,
            .train_win_rate = 0.68,
            .test_win_rate = 0.42,
            .params = null,
        },
        .{
            .window_id = 2,
            .train_sharpe = 3.2,
            .test_sharpe = 0.3,
            .train_return = 0.22,
            .test_return = 0.01,
            .train_win_rate = 0.72,
            .test_win_rate = 0.44,
            .params = null,
        },
    };

    const metrics = try detector.analyze(&windows);

    // Large train-test gap
    try std.testing.expect(metrics.train_test_gap > 1.0);

    // Should have low stability
    try std.testing.expect(metrics.stability_score < 0.5);

    // High overfitting probability
    try std.testing.expect(metrics.overfitting_probability > 0.5);
}

test "OverfittingDetector: empty windows" {
    const allocator = std.testing.allocator;

    var detector = OverfittingDetector.init(allocator, .{});
    defer detector.deinit();

    const windows: []const WindowPerformance = &.{};

    const metrics = try detector.analyze(windows);

    try std.testing.expectEqual(OverfittingMetrics.Recommendation.insufficient_data, metrics.recommendation);
}

test "ParameterStabilityAnalyzer: stability analysis" {
    const allocator = std.testing.allocator;

    var analyzer = ParameterStabilityAnalyzer.init(allocator);

    // Stable performance
    const stable_windows = [_]WindowPerformance{
        .{ .window_id = 0, .train_sharpe = 1.5, .test_sharpe = 1.3, .train_return = 0.08, .test_return = 0.07, .train_win_rate = 0.55, .test_win_rate = 0.53, .params = null },
        .{ .window_id = 1, .train_sharpe = 1.6, .test_sharpe = 1.4, .train_return = 0.09, .test_return = 0.08, .train_win_rate = 0.56, .test_win_rate = 0.54, .params = null },
        .{ .window_id = 2, .train_sharpe = 1.4, .test_sharpe = 1.2, .train_return = 0.07, .test_return = 0.06, .train_win_rate = 0.54, .test_win_rate = 0.52, .params = null },
    };

    const report = try analyzer.analyzeStability(&stable_windows);

    // All windows have positive test Sharpe
    try std.testing.expectEqual(@as(usize, 3), report.consistent_windows);

    // Should be stable
    try std.testing.expect(report.isStable());
}
