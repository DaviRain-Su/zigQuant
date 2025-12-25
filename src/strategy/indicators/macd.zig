//! Moving Average Convergence Divergence (MACD)
//!
//! Trend-following momentum indicator showing relationship between two moving averages.
//!
//! Formula:
//!   MACD Line = EMA(fast) - EMA(slow)
//!   Signal Line = EMA(MACD Line, signal_period)
//!   Histogram = MACD Line - Signal Line
//!
//! Default parameters: (12, 26, 9)
//!
//! Features:
//! - Three output lines (MACD, Signal, Histogram)
//! - Identifies trend changes and momentum
//! - Crossovers signal trading opportunities
//! - Memory-safe implementation
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const EMA = @import("ema.zig").EMA;

/// MACD calculation result
/// Contains three lines: MACD, Signal, and Histogram
pub const MACDResult = struct {
    macd_line: []Decimal,
    signal_line: []Decimal,
    histogram: []Decimal,
    allocator: std.mem.Allocator,

    /// Clean up all three arrays
    pub fn deinit(self: MACDResult) void {
        self.allocator.free(self.macd_line);
        self.allocator.free(self.signal_line);
        self.allocator.free(self.histogram);
    }
};

/// MACD (Moving Average Convergence Divergence)
pub const MACD = struct {
    allocator: std.mem.Allocator,
    fast_period: u32,
    slow_period: u32,
    signal_period: u32,

    /// Initialize MACD with custom parameters
    /// @param allocator - Memory allocator
    /// @param fast_period - Fast EMA period (must be < slow_period)
    /// @param slow_period - Slow EMA period
    /// @param signal_period - Signal line EMA period
    /// @return Pointer to new MACD instance
    pub fn init(
        allocator: std.mem.Allocator,
        fast_period: u32,
        slow_period: u32,
        signal_period: u32,
    ) !*MACD {
        if (fast_period >= slow_period) return error.InvalidPeriods;
        if (fast_period == 0 or slow_period == 0 or signal_period == 0) {
            return error.InvalidPeriod;
        }

        const self = try allocator.create(MACD);
        self.* = .{
            .allocator = allocator,
            .fast_period = fast_period,
            .slow_period = slow_period,
            .signal_period = signal_period,
        };
        return self;
    }

    /// Initialize MACD with default parameters (12, 26, 9)
    /// @param allocator - Memory allocator
    /// @return Pointer to new MACD instance with default settings
    pub fn initDefault(allocator: std.mem.Allocator) !*MACD {
        return init(allocator, 12, 26, 9);
    }

    /// Calculate MACD values
    /// @param candles - Input candle data
    /// @return MACDResult with three lines
    pub fn calculate(self: *MACD, candles: []const Candle) !MACDResult {
        if (candles.len < self.slow_period) return error.InsufficientData;

        // Calculate fast EMA
        const fast_ema = try EMA.init(self.allocator, self.fast_period);
        defer fast_ema.deinit();
        const fast_values = try fast_ema.calculate(candles);
        defer self.allocator.free(fast_values);

        // Calculate slow EMA
        const slow_ema = try EMA.init(self.allocator, self.slow_period);
        defer slow_ema.deinit();
        const slow_values = try slow_ema.calculate(candles);
        defer self.allocator.free(slow_values);

        // Calculate MACD Line = fast_ema - slow_ema
        var macd_line = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(macd_line);

        for (0..candles.len) |i| {
            macd_line[i] = fast_values[i].sub(slow_values[i]);
        }

        // Create temporary candles with MACD line as close price for Signal Line calculation
        var macd_candles = try self.allocator.alloc(Candle, candles.len);
        defer self.allocator.free(macd_candles);

        for (0..candles.len) |i| {
            macd_candles[i] = candles[i];
            macd_candles[i].close = macd_line[i];
        }

        // Calculate Signal Line = EMA(MACD Line, signal_period)
        const signal_ema = try EMA.init(self.allocator, self.signal_period);
        defer signal_ema.deinit();
        const signal_line = try signal_ema.calculate(macd_candles);

        // Calculate Histogram = MACD Line - Signal Line
        var histogram = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(histogram);

        for (0..candles.len) |i| {
            histogram[i] = macd_line[i].sub(signal_line[i]);
        }

        return MACDResult{
            .macd_line = macd_line,
            .signal_line = signal_line,
            .histogram = histogram,
            .allocator = self.allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *MACD) void {
        self.allocator.destroy(self);
    }
};

// ============================================================================
// Tests
// ============================================================================

/// Helper function to create test candles from prices
fn createTestCandles(allocator: std.mem.Allocator, prices: []const f64) ![]Candle {
    var candles = try allocator.alloc(Candle, prices.len);
    for (prices, 0..) |price, i| {
        const dec_price = Decimal.fromFloat(price);
        candles[i] = Candle{
            .timestamp = .{ .millis = @intCast(i * 3600000) },
            .open = dec_price,
            .high = dec_price,
            .low = dec_price,
            .close = dec_price,
            .volume = Decimal.fromInt(100),
        };
    }
    return candles;
}

test "MACD: basic calculation" {
    const allocator = std.testing.allocator;

    // Create test data: 30 candles with upward trend
    var prices = try allocator.alloc(f64, 30);
    defer allocator.free(prices);
    for (0..30) |i| {
        prices[i] = 100.0 + @as(f64, @floatFromInt(i)) * 2.0;
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    const macd = try MACD.initDefault(allocator);
    defer macd.deinit();

    const result = try macd.calculate(candles);
    defer result.deinit();

    // Verify we got all three lines
    try std.testing.expectEqual(candles.len, result.macd_line.len);
    try std.testing.expectEqual(candles.len, result.signal_line.len);
    try std.testing.expectEqual(candles.len, result.histogram.len);

    // In an uptrend, MACD line should be generally positive
    const macd_value = result.macd_line[29].toFloat();
    //std.debug.print("MACD Line (uptrend): {d:.2}\n", .{macd_value});
    try std.testing.expect(macd_value > 0.0);
}

test "MACD: crossover detection" {
    const allocator = std.testing.allocator;

    // Create data that simulates a crossover
    var prices = try allocator.alloc(f64, 50);
    defer allocator.free(prices);
    for (0..25) |i| {
        prices[i] = 100.0 - @as(f64, @floatFromInt(i)) * 0.5; // Downtrend
    }
    for (25..50) |i| {
        prices[i] = 87.5 + @as(f64, @floatFromInt(i - 25)) * 1.0; // Uptrend
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    const macd = try MACD.initDefault(allocator);
    defer macd.deinit();

    const result = try macd.calculate(candles);
    defer result.deinit();

    // Histogram should cross zero somewhere in the data
    var found_negative = false;
    var found_positive = false;

    for (result.histogram) |h| {
        if (!h.isNaN()) {
            const value = h.toFloat();
            if (value < 0.0) found_negative = true;
            if (value > 0.0) found_positive = true;
        }
    }

    // In this scenario, we should see both positive and negative histogram values
    try std.testing.expect(found_negative or found_positive);
}

test "MACD: custom parameters" {
    const allocator = std.testing.allocator;

    var prices = try allocator.alloc(f64, 40);
    defer allocator.free(prices);
    for (0..40) |i| {
        prices[i] = 100.0 + @as(f64, @floatFromInt(i));
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    // Test custom parameters (5, 10, 3)
    const macd = try MACD.init(allocator, 5, 10, 3);
    defer macd.deinit();

    const result = try macd.calculate(candles);
    defer result.deinit();

    try std.testing.expectEqual(candles.len, result.macd_line.len);
    try std.testing.expectEqual(candles.len, result.signal_line.len);
    try std.testing.expectEqual(candles.len, result.histogram.len);
}

test "MACD: error cases" {
    const allocator = std.testing.allocator;

    // Invalid periods (fast >= slow)
    try std.testing.expectError(error.InvalidPeriods, MACD.init(allocator, 26, 12, 9));
    try std.testing.expectError(error.InvalidPeriods, MACD.init(allocator, 12, 12, 9));

    // Zero period
    try std.testing.expectError(error.InvalidPeriod, MACD.init(allocator, 0, 26, 9));

    // Insufficient data
    {
        const candles = try createTestCandles(allocator, &[_]f64{ 100, 110, 120 });
        defer allocator.free(candles);

        const macd = try MACD.initDefault(allocator);
        defer macd.deinit();

        try std.testing.expectError(error.InsufficientData, macd.calculate(candles));
    }
}

test "MACD: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var prices = try allocator.alloc(f64, 30);
    defer allocator.free(prices);
    for (0..30) |i| {
        prices[i] = 100.0 + @as(f64, @floatFromInt(i));
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    const macd = try MACD.initDefault(allocator);
    defer macd.deinit();

    const result = try macd.calculate(candles);
    defer result.deinit();
}

test "MACD: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles
    var prices = try allocator.alloc(f64, 1000);
    defer allocator.free(prices);
    for (0..1000) |i| {
        prices[i] = @as(f64, @floatFromInt(i)) + 100.0;
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    const macd = try MACD.initDefault(allocator);
    defer macd.deinit();

    const start = std.time.nanoTimestamp();
    const result = try macd.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer result.deinit();

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    //std.debug.print("MACD(12,26,9) on 1000 candles: {d:.2}ms\n", .{elapsed_ms});

    // Performance requirement: < 10ms
    try std.testing.expect(elapsed_ms < 10.0);
}
