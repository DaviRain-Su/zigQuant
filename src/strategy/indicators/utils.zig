//! Indicator Utility Functions
//!
//! Common mathematical functions used by technical indicators:
//! - Standard deviation
//! - Variance
//! - Average/mean calculations
//!
//! Design principles:
//! - Accurate calculations using Decimal type
//! - Memory-safe implementations
//! - Efficient algorithms

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;

/// Calculate standard deviation for a sliding window
/// @param allocator - Memory allocator
/// @param candles - Input candle data
/// @param mean - Pre-calculated mean values (e.g., from SMA)
/// @param period - Window size
/// @return Array of standard deviation values
pub fn calculateStdDev(
    allocator: std.mem.Allocator,
    candles: []const Candle,
    mean: []const Decimal,
    period: u32,
) ![]Decimal {
    if (candles.len != mean.len) {
        return error.LengthMismatch;
    }
    if (period == 0) {
        return error.InvalidPeriod;
    }

    var result = try allocator.alloc(Decimal, candles.len);
    errdefer allocator.free(result);

    // First period-1 values are NaN (not enough data)
    for (0..@min(period - 1, candles.len)) |i| {
        result[i] = Decimal.NaN;
    }

    // Calculate standard deviation for each window
    for (period - 1..candles.len) |i| {
        var variance = Decimal.ZERO;

        // Calculate variance: sum of squared differences from mean
        const start_idx = i - (period - 1);
        const end_idx = i + 1;
        for (start_idx..end_idx) |j| {
            const diff = candles[j].close.sub(mean[i]);
            const squared = diff.mul(diff);
            variance = variance.add(squared);
        }

        // Divide by period to get variance
        variance = try variance.div(Decimal.fromInt(@as(i64, period)));

        // Standard deviation is square root of variance
        result[i] = try variance.sqrt();
    }

    return result;
}

/// Calculate simple sum of candle close prices
/// @param candles - Input candle data
/// @param start - Start index (inclusive)
/// @param end - End index (exclusive)
/// @return Sum of close prices
pub fn sumClose(candles: []const Candle, start: usize, end: usize) Decimal {
    var sum = Decimal.ZERO;
    for (start..end) |i| {
        sum = sum.add(candles[i].close);
    }
    return sum;
}

/// Calculate average of Decimal values
/// @param values - Array of Decimal values
/// @param start - Start index (inclusive)
/// @param end - End index (exclusive)
/// @return Average value
pub fn average(values: []const Decimal, start: usize, end: usize) !Decimal {
    if (start >= end) {
        return error.InvalidRange;
    }

    var sum = Decimal.ZERO;
    for (start..end) |i| {
        sum = sum.add(values[i]);
    }

    const count = end - start;
    return try sum.div(Decimal.fromInt(@as(i64, @intCast(count))));
}

// ============================================================================
// Tests
// ============================================================================

test "utils: calculateStdDev basic" {
    const allocator = std.testing.allocator;

    // Create test candles: prices = [1, 2, 3, 4, 5]
    var candles = try allocator.alloc(Candle, 5);
    defer allocator.free(candles);

    for (0..5) |i| {
        const price = Decimal.fromInt(@as(i64, @intCast(i + 1)));
        candles[i] = Candle{
            .timestamp = .{ .millis = @intCast(i) },
            .open = price,
            .high = price,
            .low = price,
            .close = price,
            .volume = Decimal.fromInt(100),
        };
    }

    // Mean values (for period=3): [NaN, NaN, 2, 3, 4]
    var mean = try allocator.alloc(Decimal, 5);
    defer allocator.free(mean);
    mean[0] = Decimal.NaN;
    mean[1] = Decimal.NaN;
    mean[2] = Decimal.fromInt(2); // (1+2+3)/3 = 2
    mean[3] = Decimal.fromInt(3); // (2+3+4)/3 = 3
    mean[4] = Decimal.fromInt(4); // (3+4+5)/3 = 4

    const std_dev = try calculateStdDev(allocator, candles, mean, 3);
    defer allocator.free(std_dev);

    // First 2 values should be NaN
    try std.testing.expect(std_dev[0].isNaN());
    try std.testing.expect(std_dev[1].isNaN());

    // Std dev of [1,2,3] with mean 2:
    // variance = ((1-2)^2 + (2-2)^2 + (3-2)^2) / 3 = (1+0+1)/3 = 2/3
    // std_dev = sqrt(2/3) ≈ 0.8165
    const expected_std = 0.8165;
    const actual_std = std_dev[2].toFloat();
    try std.testing.expectApproxEqAbs(expected_std, actual_std, 0.01);
}

test "utils: sumClose" {
    const allocator = std.testing.allocator;

    var candles = try allocator.alloc(Candle, 3);
    defer allocator.free(candles);

    for (0..3) |i| {
        const price = Decimal.fromInt(@as(i64, @intCast(i + 1)));
        candles[i] = Candle{
            .timestamp = .{ .millis = @intCast(i) },
            .open = price,
            .high = price,
            .low = price,
            .close = price,
            .volume = Decimal.fromInt(100),
        };
    }

    // Sum of [1, 2, 3] = 6
    const sum = sumClose(candles, 0, 3);
    try std.testing.expect(sum.eql(Decimal.fromInt(6)));
}

test "utils: average" {
    const allocator = std.testing.allocator;

    var values = try allocator.alloc(Decimal, 5);
    defer allocator.free(values);

    for (0..5) |i| {
        values[i] = Decimal.fromInt(@as(i64, @intCast(i + 1)));
    }

    // Average of [1, 2, 3] = 2
    const avg = try average(values, 0, 3);
    try std.testing.expect(avg.eql(Decimal.fromInt(2)));

    // Average of [3, 4, 5] = 4
    const avg2 = try average(values, 2, 5);
    try std.testing.expect(avg2.eql(Decimal.fromInt(4)));
}

test "utils: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var candles = try allocator.alloc(Candle, 5);
    defer allocator.free(candles);

    for (0..5) |i| {
        const price = Decimal.fromInt(@as(i64, @intCast(i + 1)));
        candles[i] = Candle{
            .timestamp = .{ .millis = @intCast(i) },
            .open = price,
            .high = price,
            .low = price,
            .close = price,
            .volume = Decimal.fromInt(100),
        };
    }

    var mean = try allocator.alloc(Decimal, 5);
    defer allocator.free(mean);
    for (0..5) |i| {
        mean[i] = Decimal.fromInt(@as(i64, @intCast(i + 1)));
    }

    const std_dev = try calculateStdDev(allocator, candles, mean, 3);
    defer allocator.free(std_dev);
}
