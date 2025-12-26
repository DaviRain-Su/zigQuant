//! Bollinger Bands
//!
//! Volatility indicator that creates upper and lower bands around a moving average.
//!
//! Formula:
//!   Middle Band = SMA(period)
//!   Upper Band = Middle Band + (σ × std_dev)
//!   Lower Band = Middle Band - (σ × std_dev)
//!
//! Default parameters: (20, 2.0)
//!
//! Features:
//! - Three output bands (upper, middle, lower)
//! - Identifies volatility and potential price extremes
//! - Price touching bands signals potential reversals
//! - Memory-safe implementation
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const SMA = @import("sma.zig").SMA;
const utils = @import("utils.zig");

/// Bollinger Bands calculation result
/// Contains three bands: upper, middle, lower
pub const BollingerResult = struct {
    upper_band: []Decimal,
    middle_band: []Decimal,
    lower_band: []Decimal,
    allocator: std.mem.Allocator,

    /// Clean up all three arrays
    pub fn deinit(self: BollingerResult) void {
        self.allocator.free(self.upper_band);
        self.allocator.free(self.middle_band);
        self.allocator.free(self.lower_band);
    }
};

/// Bollinger Bands
pub const BollingerBands = struct {
    allocator: std.mem.Allocator,
    period: u32,
    std_dev_multiplier: Decimal,

    /// Initialize Bollinger Bands with custom parameters
    /// @param allocator - Memory allocator
    /// @param period - SMA period for middle band
    /// @param std_dev_multiplier - Standard deviation multiplier (σ)
    /// @return Pointer to new BollingerBands instance
    pub fn init(
        allocator: std.mem.Allocator,
        period: u32,
        std_dev_multiplier: f64,
    ) !*BollingerBands {
        if (period == 0) return error.InvalidPeriod;
        if (std_dev_multiplier <= 0.0) return error.InvalidMultiplier;

        const self = try allocator.create(BollingerBands);
        self.* = .{
            .allocator = allocator,
            .period = period,
            .std_dev_multiplier = Decimal.fromFloat(std_dev_multiplier),
        };
        return self;
    }

    /// Initialize Bollinger Bands with default parameters (20, 2.0)
    /// @param allocator - Memory allocator
    /// @return Pointer to new BollingerBands instance with default settings
    pub fn initDefault(allocator: std.mem.Allocator) !*BollingerBands {
        return init(allocator, 20, 2.0);
    }

    /// Calculate Bollinger Bands
    /// @param candles - Input candle data
    /// @return BollingerResult with three bands
    pub fn calculate(self: *BollingerBands, candles: []const Candle) !BollingerResult {
        if (candles.len < self.period) return error.InsufficientData;

        // Calculate middle band (SMA)
        const sma = try SMA.init(self.allocator, self.period);
        defer sma.deinit();
        const middle_band = try sma.calculate(candles);
        errdefer self.allocator.free(middle_band);

        // Calculate standard deviation
        const std_dev = try utils.calculateStdDev(
            self.allocator,
            candles,
            middle_band,
            self.period,
        );
        defer self.allocator.free(std_dev);

        // Calculate upper and lower bands
        var upper_band = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(upper_band);

        var lower_band = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(lower_band);

        for (0..candles.len) |i| {
            if (middle_band[i].isNaN()) {
                // First (period-1) values are NaN
                upper_band[i] = Decimal.NaN;
                lower_band[i] = Decimal.NaN;
            } else {
                // Upper = Middle + (σ × std_dev)
                const offset = self.std_dev_multiplier.mul(std_dev[i]);
                upper_band[i] = middle_band[i].add(offset);
                lower_band[i] = middle_band[i].sub(offset);
            }
        }

        return BollingerResult{
            .upper_band = upper_band,
            .middle_band = middle_band,
            .lower_band = lower_band,
            .allocator = self.allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *BollingerBands) void {
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

test "Bollinger Bands: basic calculation" {
    const allocator = std.testing.allocator;

    // Create test data: 25 candles with some variation
    var prices = try allocator.alloc(f64, 25);
    defer allocator.free(prices);
    for (0..25) |i| {
        // Base trend + some oscillation
        const base = 100.0 + @as(f64, @floatFromInt(i)) * 0.5;
        const oscillation = @sin(@as(f64, @floatFromInt(i)) * 0.5) * 2.0;
        prices[i] = base + oscillation;
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    const bb = try BollingerBands.initDefault(allocator);
    defer bb.deinit();

    const result = try bb.calculate(candles);
    defer result.deinit();

    // Verify we got all three bands
    try std.testing.expectEqual(candles.len, result.upper_band.len);
    try std.testing.expectEqual(candles.len, result.middle_band.len);
    try std.testing.expectEqual(candles.len, result.lower_band.len);

    // First (period-1) values should be NaN
    for (0..19) |i| {
        try std.testing.expect(result.upper_band[i].isNaN());
        try std.testing.expect(result.middle_band[i].isNaN());
        try std.testing.expect(result.lower_band[i].isNaN());
    }

    // After period, upper > middle > lower
    const upper = result.upper_band[24].toFloat();
    const middle = result.middle_band[24].toFloat();
    const lower = result.lower_band[24].toFloat();

    //std.debug.print("BB(20,2.0) @ 24: Upper={d:.2}, Middle={d:.2}, Lower={d:.2}\n", .{ upper, middle, lower });

    try std.testing.expect(upper > middle);
    try std.testing.expect(middle > lower);
}

test "Bollinger Bands: custom parameters" {
    const allocator = std.testing.allocator;

    var prices = try allocator.alloc(f64, 30);
    defer allocator.free(prices);
    for (0..30) |i| {
        prices[i] = 100.0 + @as(f64, @floatFromInt(i)) * 0.3;
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    // Test custom parameters (10, 1.5)
    const bb = try BollingerBands.init(allocator, 10, 1.5);
    defer bb.deinit();

    const result = try bb.calculate(candles);
    defer result.deinit();

    try std.testing.expectEqual(candles.len, result.upper_band.len);
    try std.testing.expectEqual(candles.len, result.middle_band.len);
    try std.testing.expectEqual(candles.len, result.lower_band.len);

    // First (period-1) values should be NaN
    for (0..9) |i| {
        try std.testing.expect(result.upper_band[i].isNaN());
    }

    // Bands should be ordered correctly
    const upper = result.upper_band[29].toFloat();
    const middle = result.middle_band[29].toFloat();
    const lower = result.lower_band[29].toFloat();

    try std.testing.expect(upper > middle);
    try std.testing.expect(middle > lower);
}

test "Bollinger Bands: bandwidth changes with volatility" {
    const allocator = std.testing.allocator;

    var prices = try allocator.alloc(f64, 40);
    defer allocator.free(prices);

    // First half: low volatility (stable prices)
    for (0..20) |i| {
        prices[i] = 100.0 + @as(f64, @floatFromInt(i % 2)) * 0.1;
    }

    // Second half: high volatility (large swings)
    for (20..40) |i| {
        const swing = @as(f64, @floatFromInt(i % 2)) * 5.0;
        prices[i] = 100.0 + swing;
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    const bb = try BollingerBands.initDefault(allocator);
    defer bb.deinit();

    const result = try bb.calculate(candles);
    defer result.deinit();

    // Bandwidth in low volatility period
    const low_vol_bandwidth = result.upper_band[19].sub(result.lower_band[19]).toFloat();

    // Bandwidth in high volatility period
    const high_vol_bandwidth = result.upper_band[39].sub(result.lower_band[39]).toFloat();

    //std.debug.print("Low vol bandwidth: {d:.2}, High vol bandwidth: {d:.2}\n", .{ low_vol_bandwidth, high_vol_bandwidth });

    // High volatility should produce wider bands
    try std.testing.expect(high_vol_bandwidth > low_vol_bandwidth);
}

test "Bollinger Bands: error cases" {
    const allocator = std.testing.allocator;

    // Invalid period (0)
    try std.testing.expectError(error.InvalidPeriod, BollingerBands.init(allocator, 0, 2.0));

    // Invalid multiplier (negative)
    try std.testing.expectError(error.InvalidMultiplier, BollingerBands.init(allocator, 20, -1.0));

    // Invalid multiplier (zero)
    try std.testing.expectError(error.InvalidMultiplier, BollingerBands.init(allocator, 20, 0.0));

    // Insufficient data
    {
        const candles = try createTestCandles(allocator, &[_]f64{ 100, 110, 120 });
        defer allocator.free(candles);

        const bb = try BollingerBands.initDefault(allocator);
        defer bb.deinit();

        try std.testing.expectError(error.InsufficientData, bb.calculate(candles));
    }
}

test "Bollinger Bands: no memory leak" {
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

    const bb = try BollingerBands.initDefault(allocator);
    defer bb.deinit();

    const result = try bb.calculate(candles);
    defer result.deinit();
}

test "Bollinger Bands: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles
    var prices = try allocator.alloc(f64, 1000);
    defer allocator.free(prices);
    for (0..1000) |i| {
        const base = @as(f64, @floatFromInt(i)) + 100.0;
        const noise = @sin(@as(f64, @floatFromInt(i)) * 0.1) * 5.0;
        prices[i] = base + noise;
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    const bb = try BollingerBands.initDefault(allocator);
    defer bb.deinit();

    const start = std.time.nanoTimestamp();
    const result = try bb.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer result.deinit();

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    //std.debug.print("BollingerBands(20,2.0) on 1000 candles: {d:.2}ms\n", .{elapsed_ms});

    // Performance requirement: < 50ms (relaxed to avoid flaky failures due to system load)
    try std.testing.expect(elapsed_ms < 50.0);
}
