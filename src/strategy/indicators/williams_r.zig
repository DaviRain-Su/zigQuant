//! Williams %R Indicator
//!
//! Momentum oscillator that measures overbought and oversold levels.
//!
//! Formula:
//!   %R = (Highest High - Close) / (Highest High - Lowest Low) × (-100)
//!   Range: [-100, 0]
//!
//! Trading signals:
//! - Overbought: > -20 (price near the top of range)
//! - Oversold: < -80 (price near the bottom of range)
//!
//! Features:
//! - Similar to Stochastic %K but inverted
//! - Fast-moving oscillator
//! - Good for timing entry/exit points
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// Williams %R Indicator
pub const WilliamsR = struct {
    allocator: std.mem.Allocator,
    period: u32,

    /// Initialize Williams %R indicator
    /// @param allocator - Memory allocator
    /// @param period - Lookback period (typically 14)
    /// @return Pointer to new WilliamsR instance
    pub fn init(allocator: std.mem.Allocator, period: u32) !*WilliamsR {
        if (period == 0) return error.InvalidPeriod;

        const self = try allocator.create(WilliamsR);
        self.* = .{
            .allocator = allocator,
            .period = period,
        };
        return self;
    }

    /// Convert to IIndicator interface
    pub fn toIndicator(self: *WilliamsR) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Calculate Williams %R values
    /// @param candles - Input candle data
    /// @return Array of %R values [-100 to 0] (same length as candles)
    pub fn calculate(self: *WilliamsR, candles: []const Candle) ![]Decimal {
        if (candles.len < self.period) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // First period-1 values are NaN (not enough data)
        for (0..self.period - 1) |i| {
            result[i] = Decimal.NaN;
        }

        // Calculate Williams %R for each point
        for (self.period - 1..candles.len) |i| {
            const start_idx = i - (self.period - 1);
            const end_idx = i + 1;

            // Find highest high and lowest low in the period
            var highest_high = candles[start_idx].high;
            var lowest_low = candles[start_idx].low;

            for (start_idx + 1..end_idx) |j| {
                if (candles[j].high.cmp(highest_high) == .gt) {
                    highest_high = candles[j].high;
                }
                if (candles[j].low.cmp(lowest_low) == .lt) {
                    lowest_low = candles[j].low;
                }
            }

            const close = candles[i].close;
            const range = highest_high.sub(lowest_low);

            // Handle zero range (price hasn't moved)
            if (range.isZero()) {
                result[i] = Decimal.fromInt(-50); // Neutral
                continue;
            }

            // %R = (Highest High - Close) / (Highest High - Lowest Low) × (-100)
            const diff = highest_high.sub(close);
            const ratio = try diff.div(range);
            const percent_r = ratio.mul(Decimal.fromInt(-100));

            result[i] = percent_r;
        }

        return result;
    }

    /// Clean up resources
    pub fn deinit(self: *WilliamsR) void {
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *WilliamsR = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "Williams%R";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        const self: *WilliamsR = @ptrCast(@alignCast(ptr));
        return self.period;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *WilliamsR = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    const vtable = IIndicator.VTable{
        .calculate = calculateImpl,
        .getName = getNameImpl,
        .getRequiredCandles = getRequiredCandlesImpl,
        .deinit = deinitImpl,
    };
};

// ============================================================================
// Tests
// ============================================================================

/// Helper function to create test candles from OHLC data
fn createTestCandlesOHLC(
    allocator: std.mem.Allocator,
    data: []const [4]f64, // [open, high, low, close]
) ![]Candle {
    var candles = try allocator.alloc(Candle, data.len);
    for (data, 0..) |ohlc, i| {
        candles[i] = Candle{
            .timestamp = .{ .millis = @intCast(i * 3600000) },
            .open = Decimal.fromFloat(ohlc[0]),
            .high = Decimal.fromFloat(ohlc[1]),
            .low = Decimal.fromFloat(ohlc[2]),
            .close = Decimal.fromFloat(ohlc[3]),
            .volume = Decimal.fromInt(100),
        };
    }
    return candles;
}

test "WilliamsR: basic calculation" {
    const allocator = std.testing.allocator;

    // Test data with clear high/low/close pattern
    const data = [_][4]f64{
        .{ 100, 105, 95, 100 },
        .{ 100, 110, 90, 105 },
        .{ 105, 115, 100, 110 },
        .{ 110, 120, 105, 115 },
        .{ 115, 125, 110, 120 },
        .{ 120, 130, 115, 125 },
        .{ 125, 135, 120, 130 },
        .{ 130, 140, 125, 135 },
        .{ 135, 145, 130, 140 },
        .{ 140, 150, 135, 145 },
        .{ 145, 155, 140, 150 },
        .{ 150, 160, 145, 155 },
        .{ 155, 165, 150, 160 },
        .{ 160, 170, 155, 165 },
        .{ 165, 175, 160, 170 },
    };

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const willr = try WilliamsR.init(allocator, 14);
    defer willr.deinit();

    const result = try willr.calculate(candles);
    defer allocator.free(result);

    // First 13 values should be NaN
    for (0..13) |i| {
        try std.testing.expect(result[i].isNaN());
    }

    // Williams %R should be in range [-100, 0]
    for (13..result.len) |i| {
        const value = result[i].toFloat();
        try std.testing.expect(value >= -100.0);
        try std.testing.expect(value <= 0.0);
    }
}

test "WilliamsR: overbought condition" {
    const allocator = std.testing.allocator;

    // Price at highest high - should be near 0 (overbought)
    var data: [14][4]f64 = undefined;
    for (0..14) |i| {
        const base: f64 = @floatFromInt(i * 10 + 100);
        data[i] = .{ base, base + 5, base - 5, base + 5 }; // Close at high
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const willr = try WilliamsR.init(allocator, 14);
    defer willr.deinit();

    const result = try willr.calculate(candles);
    defer allocator.free(result);

    // When close is at highest high, %R should be 0 (or near 0)
    const last_value = result[13].toFloat();
    try std.testing.expect(last_value >= -10.0); // Near overbought
}

test "WilliamsR: oversold condition" {
    const allocator = std.testing.allocator;

    // Price at lowest low - should be near -100 (oversold)
    var data: [14][4]f64 = undefined;
    for (0..14) |i| {
        const base: f64 = @floatFromInt(200 - i * 10); // Decreasing
        data[i] = .{ base, base + 5, base - 5, base - 5 }; // Close at low
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const willr = try WilliamsR.init(allocator, 14);
    defer willr.deinit();

    const result = try willr.calculate(candles);
    defer allocator.free(result);

    // When close is at lowest low, %R should be -100 (or near -100)
    const last_value = result[13].toFloat();
    try std.testing.expect(last_value <= -90.0); // Near oversold
}

test "WilliamsR: IIndicator interface" {
    const allocator = std.testing.allocator;

    const data = [_][4]f64{
        .{ 100, 105, 95, 100 },
        .{ 100, 110, 90, 105 },
        .{ 105, 115, 100, 110 },
        .{ 110, 120, 105, 115 },
        .{ 115, 125, 110, 120 },
        .{ 120, 130, 115, 125 },
        .{ 125, 135, 120, 130 },
        .{ 130, 140, 125, 135 },
        .{ 135, 145, 130, 140 },
        .{ 140, 150, 135, 145 },
        .{ 145, 155, 140, 150 },
        .{ 150, 160, 145, 155 },
        .{ 155, 165, 150, 160 },
        .{ 160, 170, 155, 165 },
        .{ 165, 175, 160, 170 },
    };

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const willr = try WilliamsR.init(allocator, 14);
    const indicator = willr.toIndicator();
    defer indicator.deinit();

    // Test getName
    try std.testing.expectEqualStrings("Williams%R", indicator.getName());

    // Test getRequiredCandles
    try std.testing.expectEqual(@as(u32, 14), indicator.getRequiredCandles());

    // Test calculate through interface
    const result = try indicator.calculate(candles);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 15), result.len);
}

test "WilliamsR: error cases" {
    const allocator = std.testing.allocator;

    // Invalid period (0)
    try std.testing.expectError(error.InvalidPeriod, WilliamsR.init(allocator, 0));

    // Insufficient data
    {
        const data = [_][4]f64{
            .{ 100, 105, 95, 100 },
            .{ 100, 110, 90, 105 },
            .{ 105, 115, 100, 110 },
        };
        const candles = try createTestCandlesOHLC(allocator, &data);
        defer allocator.free(candles);

        const willr = try WilliamsR.init(allocator, 14);
        defer willr.deinit();

        try std.testing.expectError(error.InsufficientData, willr.calculate(candles));
    }
}

test "WilliamsR: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const data = [_][4]f64{
        .{ 100, 105, 95, 100 },
        .{ 100, 110, 90, 105 },
        .{ 105, 115, 100, 110 },
        .{ 110, 120, 105, 115 },
        .{ 115, 125, 110, 120 },
        .{ 120, 130, 115, 125 },
        .{ 125, 135, 120, 130 },
        .{ 130, 140, 125, 135 },
        .{ 135, 145, 130, 140 },
        .{ 140, 150, 135, 145 },
        .{ 145, 155, 140, 150 },
        .{ 150, 160, 145, 155 },
        .{ 155, 165, 150, 160 },
        .{ 160, 170, 155, 165 },
        .{ 165, 175, 160, 170 },
    };

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const willr = try WilliamsR.init(allocator, 14);
    defer willr.deinit();

    const result = try willr.calculate(candles);
    defer allocator.free(result);
}

test "WilliamsR: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles with some variation
    var data = try allocator.alloc([4]f64, 1000);
    defer allocator.free(data);
    for (0..1000) |i| {
        const base: f64 = @floatFromInt(i + 100);
        const variation: f64 = @floatFromInt(i % 10);
        data[i] = .{
            base,
            base + 10 + variation,
            base - 10 + variation,
            base + variation - 5,
        };
    }

    const candles = try createTestCandlesOHLC(allocator, data);
    defer allocator.free(candles);

    const willr = try WilliamsR.init(allocator, 14);
    defer willr.deinit();

    const start = std.time.nanoTimestamp();
    const result = try willr.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer allocator.free(result);

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    // Performance requirement: < 10ms
    try std.testing.expect(elapsed_ms < 10.0);
}
