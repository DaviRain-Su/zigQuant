/// Data Splitting Strategies for Walk-Forward Analysis
///
/// Provides various methods to split time series data into
/// training and testing sets for robust strategy optimization.
///
/// Supported strategies:
/// - Fixed ratio: Single train/test split
/// - Rolling window: Fixed-size sliding window
/// - Expanding window: Growing training set
/// - Anchored window: Fixed start, expanding end

const std = @import("std");
const root = @import("../root.zig");

const Timestamp = root.Timestamp;
const Candle = root.Candle;

// ============================================================================
// Split Strategy Types
// ============================================================================

/// Data splitting strategy
pub const SplitStrategy = enum {
    /// Fixed ratio split (e.g., 70/30)
    fixed_ratio,

    /// Rolling window: fixed-size window moves forward
    rolling_window,

    /// Expanding window: start fixed, end moves forward
    expanding_window,

    /// Anchored window: first window fixed, subsequent windows roll
    anchored_window,

    pub fn name(self: SplitStrategy) []const u8 {
        return switch (self) {
            .fixed_ratio => "Fixed Ratio",
            .rolling_window => "Rolling Window",
            .expanding_window => "Expanding Window",
            .anchored_window => "Anchored Window",
        };
    }
};

/// Data window representing train/test split
pub const DataWindow = struct {
    /// Window identifier
    window_id: usize,

    /// Training data slice
    train_data: []const Candle,

    /// Testing data slice
    test_data: []const Candle,

    /// Training period timestamps
    train_start: Timestamp,
    train_end: Timestamp,

    /// Testing period timestamps
    test_start: Timestamp,
    test_end: Timestamp,

    /// Get training period duration in milliseconds
    pub fn trainDuration(self: *const DataWindow) u64 {
        return self.train_end.millis - self.train_start.millis;
    }

    /// Get testing period duration in milliseconds
    pub fn testDuration(self: *const DataWindow) u64 {
        return self.test_end.millis - self.test_start.millis;
    }

    /// Get train/test ratio
    pub fn trainTestRatio(self: *const DataWindow) f64 {
        const train_len: f64 = @floatFromInt(self.train_data.len);
        const test_len: f64 = @floatFromInt(self.test_data.len);
        if (test_len == 0) return std.math.inf(f64);
        return train_len / test_len;
    }
};

// ============================================================================
// Split Configuration
// ============================================================================

/// Configuration for data splitting
pub const SplitConfig = struct {
    /// Splitting strategy to use
    strategy: SplitStrategy = .fixed_ratio,

    /// Training set ratio (0.0-1.0)
    train_ratio: f64 = 0.7,

    /// Testing set ratio (0.0-1.0), auto-calculated if not set
    test_ratio: ?f64 = null,

    /// Step size for rolling/expanding windows (number of candles)
    step_size: ?usize = null,

    /// Minimum training set size (candles)
    min_train_size: usize = 100,

    /// Minimum testing set size (candles)
    min_test_size: usize = 30,

    /// Maximum number of windows (null = no limit)
    max_windows: ?usize = null,

    /// Gap between train and test (candles, for lookahead prevention)
    gap_size: usize = 0,

    /// Get effective test ratio
    pub fn getTestRatio(self: *const SplitConfig) f64 {
        return self.test_ratio orelse (1.0 - self.train_ratio);
    }

    /// Validate configuration
    pub fn validate(self: *const SplitConfig) !void {
        if (self.train_ratio <= 0.0 or self.train_ratio >= 1.0) {
            return error.InvalidTrainRatio;
        }

        const test_ratio = self.getTestRatio();
        if (test_ratio <= 0.0 or test_ratio >= 1.0) {
            return error.InvalidTestRatio;
        }

        if (self.train_ratio + test_ratio > 1.0) {
            return error.RatioSumExceedsOne;
        }

        if (self.min_train_size < 10) {
            return error.TrainSizeTooSmall;
        }

        if (self.min_test_size < 5) {
            return error.TestSizeTooSmall;
        }
    }

    /// Calculate number of windows for given data length
    pub fn calculateWindowCount(self: *const SplitConfig, data_len: usize) !usize {
        try self.validate();

        const required_min = self.min_train_size + self.min_test_size + self.gap_size;
        if (data_len < required_min) {
            return error.InsufficientData;
        }

        return switch (self.strategy) {
            .fixed_ratio => 1,
            .rolling_window, .expanding_window, .anchored_window => blk: {
                const train_size = @as(usize, @intFromFloat(
                    @as(f64, @floatFromInt(data_len)) * self.train_ratio,
                ));
                const step = self.step_size orelse @max(1, train_size / 4);
                const remaining = data_len - train_size - self.gap_size;

                if (remaining < self.min_test_size) {
                    break :blk 1;
                }

                var count: usize = (remaining - self.min_test_size) / step + 1;
                if (self.max_windows) |max| {
                    count = @min(count, max);
                }
                break :blk @max(1, count);
            },
        };
    }
};

// ============================================================================
// Data Splitter
// ============================================================================

/// Splits time series data into train/test windows
pub const DataSplitter = struct {
    allocator: std.mem.Allocator,
    config: SplitConfig,

    /// Initialize a data splitter
    pub fn init(allocator: std.mem.Allocator, config: SplitConfig) !DataSplitter {
        try config.validate();
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Deinitialize splitter (no-op for now)
    pub fn deinit(self: *DataSplitter) void {
        _ = self;
    }

    /// Split data into windows
    pub fn split(self: *DataSplitter, data: []const Candle) ![]DataWindow {
        if (data.len < self.config.min_train_size + self.config.min_test_size) {
            return error.InsufficientData;
        }

        return switch (self.config.strategy) {
            .fixed_ratio => try self.splitFixedRatio(data),
            .rolling_window => try self.splitRollingWindow(data),
            .expanding_window => try self.splitExpandingWindow(data),
            .anchored_window => try self.splitAnchoredWindow(data),
        };
    }

    /// Free windows allocated by split
    pub fn freeWindows(self: *DataSplitter, windows: []DataWindow) void {
        self.allocator.free(windows);
    }

    // ========================================================================
    // Private splitting implementations
    // ========================================================================

    fn splitFixedRatio(self: *DataSplitter, data: []const Candle) ![]DataWindow {
        const data_len = data.len;
        const train_size = @as(usize, @intFromFloat(
            @as(f64, @floatFromInt(data_len)) * self.config.train_ratio,
        ));

        // Ensure minimum sizes
        const actual_train = @max(self.config.min_train_size, train_size);
        const gap = self.config.gap_size;
        const test_start_idx = actual_train + gap;

        if (test_start_idx >= data_len) {
            return error.InsufficientTestData;
        }

        const test_size = data_len - test_start_idx;
        if (test_size < self.config.min_test_size) {
            return error.InsufficientTestData;
        }

        const windows = try self.allocator.alloc(DataWindow, 1);
        errdefer self.allocator.free(windows);

        windows[0] = DataWindow{
            .window_id = 0,
            .train_data = data[0..actual_train],
            .test_data = data[test_start_idx..],
            .train_start = data[0].timestamp,
            .train_end = data[actual_train - 1].timestamp,
            .test_start = data[test_start_idx].timestamp,
            .test_end = data[data_len - 1].timestamp,
        };

        return windows;
    }

    fn splitRollingWindow(self: *DataSplitter, data: []const Candle) ![]DataWindow {
        const data_len = data.len;
        const train_size = @as(usize, @intFromFloat(
            @as(f64, @floatFromInt(data_len)) * self.config.train_ratio,
        ));
        const actual_train = @max(self.config.min_train_size, train_size);
        const step = self.config.step_size orelse @max(1, actual_train / 4);
        const gap = self.config.gap_size;

        // Calculate number of windows
        var num_windows: usize = 0;
        var start: usize = 0;
        while (start + actual_train + gap + self.config.min_test_size <= data_len) {
            num_windows += 1;
            start += step;
            if (self.config.max_windows) |max| {
                if (num_windows >= max) break;
            }
        }

        if (num_windows == 0) {
            return error.InsufficientData;
        }

        const windows = try self.allocator.alloc(DataWindow, num_windows);
        errdefer self.allocator.free(windows);

        start = 0;
        for (0..num_windows) |i| {
            const train_end = start + actual_train;
            const test_start_idx = train_end + gap;
            const test_end = @min(test_start_idx + step, data_len);

            windows[i] = DataWindow{
                .window_id = i,
                .train_data = data[start..train_end],
                .test_data = data[test_start_idx..test_end],
                .train_start = data[start].timestamp,
                .train_end = data[train_end - 1].timestamp,
                .test_start = data[test_start_idx].timestamp,
                .test_end = data[test_end - 1].timestamp,
            };

            start += step;
        }

        return windows;
    }

    fn splitExpandingWindow(self: *DataSplitter, data: []const Candle) ![]DataWindow {
        const data_len = data.len;
        const initial_train = @max(
            self.config.min_train_size,
            @as(usize, @intFromFloat(@as(f64, @floatFromInt(data_len)) * self.config.train_ratio * 0.5)),
        );
        const step = self.config.step_size orelse @max(1, initial_train / 4);
        const gap = self.config.gap_size;

        // Calculate number of windows
        var num_windows: usize = 0;
        var train_end = initial_train;
        while (train_end + gap + self.config.min_test_size <= data_len) {
            num_windows += 1;
            train_end += step;
            if (self.config.max_windows) |max| {
                if (num_windows >= max) break;
            }
        }

        if (num_windows == 0) {
            return error.InsufficientData;
        }

        const windows = try self.allocator.alloc(DataWindow, num_windows);
        errdefer self.allocator.free(windows);

        train_end = initial_train;
        for (0..num_windows) |i| {
            const test_start_idx = train_end + gap;
            const test_end_idx = @min(test_start_idx + step, data_len);

            windows[i] = DataWindow{
                .window_id = i,
                .train_data = data[0..train_end], // Always starts from 0 (expanding)
                .test_data = data[test_start_idx..test_end_idx],
                .train_start = data[0].timestamp,
                .train_end = data[train_end - 1].timestamp,
                .test_start = data[test_start_idx].timestamp,
                .test_end = data[test_end_idx - 1].timestamp,
            };

            train_end += step;
        }

        return windows;
    }

    fn splitAnchoredWindow(self: *DataSplitter, data: []const Candle) ![]DataWindow {
        const data_len = data.len;
        const initial_train = @max(
            self.config.min_train_size,
            @as(usize, @intFromFloat(@as(f64, @floatFromInt(data_len)) * self.config.train_ratio * 0.5)),
        );
        const step = self.config.step_size orelse @max(1, initial_train / 4);
        const gap = self.config.gap_size;

        // First window is anchored (used as reference)
        // Subsequent windows roll forward

        var num_windows: usize = 0;
        var window_start: usize = 0;
        while (window_start + initial_train + gap + self.config.min_test_size <= data_len) {
            num_windows += 1;
            if (num_windows == 1) {
                // First window stays anchored
                window_start = 0;
            }
            window_start += step;
            if (self.config.max_windows) |max| {
                if (num_windows >= max) break;
            }
        }

        if (num_windows == 0) {
            return error.InsufficientData;
        }

        const windows = try self.allocator.alloc(DataWindow, num_windows);
        errdefer self.allocator.free(windows);

        // First window is anchored
        windows[0] = DataWindow{
            .window_id = 0,
            .train_data = data[0..initial_train],
            .test_data = data[initial_train + gap .. @min(initial_train + gap + step, data_len)],
            .train_start = data[0].timestamp,
            .train_end = data[initial_train - 1].timestamp,
            .test_start = data[initial_train + gap].timestamp,
            .test_end = data[@min(initial_train + gap + step, data_len) - 1].timestamp,
        };

        // Subsequent windows roll
        var start: usize = step;
        for (1..num_windows) |i| {
            const train_end = start + initial_train;
            const test_start_idx = train_end + gap;
            const test_end_idx = @min(test_start_idx + step, data_len);

            windows[i] = DataWindow{
                .window_id = i,
                .train_data = data[start..train_end],
                .test_data = data[test_start_idx..test_end_idx],
                .train_start = data[start].timestamp,
                .train_end = data[train_end - 1].timestamp,
                .test_start = data[test_start_idx].timestamp,
                .test_end = data[test_end_idx - 1].timestamp,
            };

            start += step;
        }

        return windows;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SplitConfig: validation" {
    // Valid config
    {
        const config = SplitConfig{
            .strategy = .fixed_ratio,
            .train_ratio = 0.7,
            .min_train_size = 100,
            .min_test_size = 30,
        };
        try config.validate();
    }

    // Invalid train ratio
    {
        const config = SplitConfig{
            .train_ratio = 1.5,
        };
        try std.testing.expectError(error.InvalidTrainRatio, config.validate());
    }

    // Ratio sum exceeds 1
    {
        const config = SplitConfig{
            .train_ratio = 0.7,
            .test_ratio = 0.5,
        };
        try std.testing.expectError(error.RatioSumExceedsOne, config.validate());
    }
}

test "DataSplitter: fixed ratio split" {
    const allocator = std.testing.allocator;

    // Create test candles
    var candles: [200]Candle = undefined;
    for (0..200) |i| {
        candles[i] = Candle{
            .timestamp = Timestamp.fromMillis(@intCast(i * 60000)),
            .open = root.Decimal.fromInt(@intCast(100 + i)),
            .high = root.Decimal.fromInt(@intCast(101 + i)),
            .low = root.Decimal.fromInt(@intCast(99 + i)),
            .close = root.Decimal.fromInt(@intCast(100 + i)),
            .volume = root.Decimal.fromInt(1000),
        };
    }

    const config = SplitConfig{
        .strategy = .fixed_ratio,
        .train_ratio = 0.7,
        .min_train_size = 50,
        .min_test_size = 20,
    };

    var splitter = try DataSplitter.init(allocator, config);
    defer splitter.deinit();

    const windows = try splitter.split(&candles);
    defer splitter.freeWindows(windows);

    try std.testing.expectEqual(@as(usize, 1), windows.len);
    try std.testing.expectEqual(@as(usize, 140), windows[0].train_data.len); // 70% of 200
    try std.testing.expectEqual(@as(usize, 60), windows[0].test_data.len); // 30% of 200
}

test "DataSplitter: rolling window split" {
    const allocator = std.testing.allocator;

    // Create test candles
    var candles: [300]Candle = undefined;
    for (0..300) |i| {
        candles[i] = Candle{
            .timestamp = Timestamp.fromMillis(@intCast(i * 60000)),
            .open = root.Decimal.fromInt(@intCast(100 + i)),
            .high = root.Decimal.fromInt(@intCast(101 + i)),
            .low = root.Decimal.fromInt(@intCast(99 + i)),
            .close = root.Decimal.fromInt(@intCast(100 + i)),
            .volume = root.Decimal.fromInt(1000),
        };
    }

    const config = SplitConfig{
        .strategy = .rolling_window,
        .train_ratio = 0.5,
        .step_size = 50,
        .min_train_size = 50,
        .min_test_size = 20,
    };

    var splitter = try DataSplitter.init(allocator, config);
    defer splitter.deinit();

    const windows = try splitter.split(&candles);
    defer splitter.freeWindows(windows);

    // Should have multiple windows
    try std.testing.expect(windows.len > 1);

    // Each window should have proper train size
    for (windows) |window| {
        try std.testing.expect(window.train_data.len >= config.min_train_size);
        try std.testing.expect(window.test_data.len >= config.min_test_size);
    }
}

test "DataSplitter: expanding window split" {
    const allocator = std.testing.allocator;

    // Create test candles
    var candles: [400]Candle = undefined;
    for (0..400) |i| {
        candles[i] = Candle{
            .timestamp = Timestamp.fromMillis(@intCast(i * 60000)),
            .open = root.Decimal.fromInt(@intCast(100 + i)),
            .high = root.Decimal.fromInt(@intCast(101 + i)),
            .low = root.Decimal.fromInt(@intCast(99 + i)),
            .close = root.Decimal.fromInt(@intCast(100 + i)),
            .volume = root.Decimal.fromInt(1000),
        };
    }

    const config = SplitConfig{
        .strategy = .expanding_window,
        .train_ratio = 0.5,
        .step_size = 50,
        .min_train_size = 50,
        .min_test_size = 20,
    };

    var splitter = try DataSplitter.init(allocator, config);
    defer splitter.deinit();

    const windows = try splitter.split(&candles);
    defer splitter.freeWindows(windows);

    // Should have multiple windows
    try std.testing.expect(windows.len > 1);

    // Training data should always start from index 0 (expanding)
    for (windows) |window| {
        try std.testing.expectEqual(candles[0].timestamp, window.train_start);
    }

    // Each subsequent window should have larger training set
    if (windows.len > 1) {
        for (1..windows.len) |i| {
            try std.testing.expect(windows[i].train_data.len > windows[i - 1].train_data.len);
        }
    }
}

test "DataSplitter: insufficient data" {
    const allocator = std.testing.allocator;

    // Create very small dataset
    var candles: [20]Candle = undefined;
    for (0..20) |i| {
        candles[i] = Candle{
            .timestamp = Timestamp.fromMillis(@intCast(i * 60000)),
            .open = root.Decimal.fromInt(@intCast(100 + i)),
            .high = root.Decimal.fromInt(@intCast(101 + i)),
            .low = root.Decimal.fromInt(@intCast(99 + i)),
            .close = root.Decimal.fromInt(@intCast(100 + i)),
            .volume = root.Decimal.fromInt(1000),
        };
    }

    const config = SplitConfig{
        .strategy = .fixed_ratio,
        .train_ratio = 0.7,
        .min_train_size = 100, // Requires more data than available
        .min_test_size = 30,
    };

    var splitter = try DataSplitter.init(allocator, config);
    defer splitter.deinit();

    try std.testing.expectError(error.InsufficientData, splitter.split(&candles));
}
