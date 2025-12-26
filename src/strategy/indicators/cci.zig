//! Commodity Channel Index (CCI)
//!
//! Momentum oscillator that measures the variation of a price from its statistical mean.
//!
//! Formula:
//!   1. TP (Typical Price) = (High + Low + Close) / 3
//!   2. SMA(TP) = Simple Moving Average of TP
//!   3. MD (Mean Deviation) = Average of |TP - SMA(TP)|
//!   4. CCI = (TP - SMA(TP)) / (0.015 × MD)
//!
//! Trading signals:
//! - Overbought: > +100
//! - Oversold: < -100
//! - Trend confirmation when crossing zero line
//!
//! Features:
//! - Identifies cyclical trends
//! - Good for commodity and stock trading
//! - Can signal trend strength and reversals
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// Commodity Channel Index (CCI)
pub const CCI = struct {
    allocator: std.mem.Allocator,
    period: u32,
    constant: Decimal, // Lambert constant, typically 0.015

    /// Initialize CCI indicator
    /// @param allocator - Memory allocator
    /// @param period - Lookback period (typically 20)
    /// @return Pointer to new CCI instance
    pub fn init(allocator: std.mem.Allocator, period: u32) !*CCI {
        if (period == 0) return error.InvalidPeriod;

        const self = try allocator.create(CCI);
        self.* = .{
            .allocator = allocator,
            .period = period,
            .constant = Decimal.fromFloat(0.015),
        };
        return self;
    }

    /// Initialize CCI with custom constant
    /// @param allocator - Memory allocator
    /// @param period - Lookback period
    /// @param constant - Lambert constant (default 0.015)
    /// @return Pointer to new CCI instance
    pub fn initWithConstant(allocator: std.mem.Allocator, period: u32, constant: f64) !*CCI {
        if (period == 0) return error.InvalidPeriod;

        const self = try allocator.create(CCI);
        self.* = .{
            .allocator = allocator,
            .period = period,
            .constant = Decimal.fromFloat(constant),
        };
        return self;
    }

    /// Convert to IIndicator interface
    pub fn toIndicator(self: *CCI) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Calculate CCI values
    /// @param candles - Input candle data
    /// @return Array of CCI values (same length as candles)
    pub fn calculate(self: *CCI, candles: []const Candle) ![]Decimal {
        if (candles.len < self.period) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // Calculate Typical Prices
        var tp = try self.allocator.alloc(Decimal, candles.len);
        defer self.allocator.free(tp);

        const three = Decimal.fromInt(3);
        for (candles, 0..) |candle, i| {
            const sum = candle.high.add(candle.low).add(candle.close);
            tp[i] = try sum.div(three);
        }

        // First period-1 values are NaN
        for (0..self.period - 1) |i| {
            result[i] = Decimal.NaN;
        }

        const period_decimal = Decimal.fromInt(@as(i64, @intCast(self.period)));

        // Calculate CCI for each point
        for (self.period - 1..candles.len) |i| {
            const start_idx = i - (self.period - 1);
            const end_idx = i + 1;

            // Calculate SMA of TP
            var tp_sum = Decimal.ZERO;
            for (start_idx..end_idx) |j| {
                tp_sum = tp_sum.add(tp[j]);
            }
            const sma_tp = try tp_sum.div(period_decimal);

            // Calculate Mean Deviation
            var md_sum = Decimal.ZERO;
            for (start_idx..end_idx) |j| {
                const deviation = tp[j].sub(sma_tp).abs();
                md_sum = md_sum.add(deviation);
            }
            const mean_deviation = try md_sum.div(period_decimal);

            // Calculate CCI
            const current_tp = tp[i];
            const tp_diff = current_tp.sub(sma_tp);

            // Handle zero mean deviation
            if (mean_deviation.isZero()) {
                result[i] = Decimal.ZERO;
                continue;
            }

            // CCI = (TP - SMA(TP)) / (constant × MD)
            const denominator = self.constant.mul(mean_deviation);
            const cci = try tp_diff.div(denominator);

            result[i] = cci;
        }

        return result;
    }

    /// Clean up resources
    pub fn deinit(self: *CCI) void {
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *CCI = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "CCI";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        const self: *CCI = @ptrCast(@alignCast(ptr));
        return self.period;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *CCI = @ptrCast(@alignCast(ptr));
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

test "CCI: basic calculation" {
    const allocator = std.testing.allocator;

    // Create 25 candles for period 20
    var data: [25][4]f64 = undefined;
    for (0..25) |i| {
        const base: f64 = @floatFromInt(100 + i * 2);
        data[i] = .{ base, base + 3, base - 2, base + 1 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const cci = try CCI.init(allocator, 20);
    defer cci.deinit();

    const result = try cci.calculate(candles);
    defer allocator.free(result);

    // First 19 values should be NaN
    for (0..19) |i| {
        try std.testing.expect(result[i].isNaN());
    }

    // CCI should be calculated for remaining values
    for (19..result.len) |i| {
        try std.testing.expect(!result[i].isNaN());
    }
}

test "CCI: overbought/oversold detection" {
    const allocator = std.testing.allocator;

    // Create data with strong uptrend (should show positive CCI)
    var data: [25][4]f64 = undefined;
    for (0..25) |i| {
        const base: f64 = @floatFromInt(100 + i * 5); // Strong uptrend
        data[i] = .{ base, base + 3, base - 2, base + 2 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const cci = try CCI.init(allocator, 20);
    defer cci.deinit();

    const result = try cci.calculate(candles);
    defer allocator.free(result);

    // With strong uptrend, later CCI values should be positive
    const last_cci = result[result.len - 1].toFloat();
    try std.testing.expect(last_cci > 0);
}

test "CCI: stable prices" {
    const allocator = std.testing.allocator;

    // Create data with stable prices (CCI should be near 0)
    var data: [25][4]f64 = undefined;
    for (0..25) |_| {
        data[0] = .{ 100, 102, 98, 100 }; // Same candle repeated
    }
    for (0..25) |i| {
        data[i] = .{ 100, 102, 98, 100 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const cci = try CCI.init(allocator, 20);
    defer cci.deinit();

    const result = try cci.calculate(candles);
    defer allocator.free(result);

    // With stable prices, CCI should be near 0
    const last_cci = result[result.len - 1].toFloat();
    try std.testing.expectApproxEqAbs(@as(f64, 0), last_cci, 5.0);
}

test "CCI: IIndicator interface" {
    const allocator = std.testing.allocator;

    var data: [25][4]f64 = undefined;
    for (0..25) |i| {
        const base: f64 = @floatFromInt(100 + i * 2);
        data[i] = .{ base, base + 3, base - 2, base + 1 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const cci = try CCI.init(allocator, 20);
    const indicator = cci.toIndicator();
    defer indicator.deinit();

    // Test getName
    try std.testing.expectEqualStrings("CCI", indicator.getName());

    // Test getRequiredCandles
    try std.testing.expectEqual(@as(u32, 20), indicator.getRequiredCandles());

    // Test calculate through interface
    const result = try indicator.calculate(candles);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 25), result.len);
}

test "CCI: error cases" {
    const allocator = std.testing.allocator;

    // Invalid period (0)
    try std.testing.expectError(error.InvalidPeriod, CCI.init(allocator, 0));

    // Insufficient data
    {
        var data: [10][4]f64 = undefined;
        for (0..10) |i| {
            const base: f64 = @floatFromInt(100 + i);
            data[i] = .{ base, base + 3, base - 2, base + 1 };
        }

        const candles = try createTestCandlesOHLC(allocator, &data);
        defer allocator.free(candles);

        const cci = try CCI.init(allocator, 20);
        defer cci.deinit();

        try std.testing.expectError(error.InsufficientData, cci.calculate(candles));
    }
}

test "CCI: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var data: [25][4]f64 = undefined;
    for (0..25) |i| {
        const base: f64 = @floatFromInt(100 + i * 2);
        data[i] = .{ base, base + 3, base - 2, base + 1 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const cci = try CCI.init(allocator, 20);
    defer cci.deinit();

    const result = try cci.calculate(candles);
    defer allocator.free(result);
}

test "CCI: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles
    var data = try allocator.alloc([4]f64, 1000);
    defer allocator.free(data);
    for (0..1000) |i| {
        const base: f64 = @floatFromInt(i + 100);
        const variation: f64 = @floatFromInt(i % 10);
        data[i] = .{
            base,
            base + 5 + variation,
            base - 5 + variation,
            base + variation - 2,
        };
    }

    const candles = try createTestCandlesOHLC(allocator, data);
    defer allocator.free(candles);

    const cci = try CCI.init(allocator, 20);
    defer cci.deinit();

    const start = std.time.nanoTimestamp();
    const result = try cci.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer allocator.free(result);

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    // Performance requirement: < 10ms
    try std.testing.expect(elapsed_ms < 10.0);
}
