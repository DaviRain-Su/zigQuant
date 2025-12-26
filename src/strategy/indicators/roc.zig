//! Rate of Change (ROC) Indicator
//!
//! Momentum oscillator that measures the percentage change between current price
//! and the price n periods ago.
//!
//! Formula:
//!   ROC = ((Close - Close[n]) / Close[n]) × 100
//!
//! Trading signals:
//! - Positive ROC: Upward momentum
//! - Negative ROC: Downward momentum
//! - Zero line crossover: Momentum shift
//! - Divergence: Potential trend reversal
//!
//! Features:
//! - Simple and effective momentum indicator
//! - Can identify overbought/oversold conditions
//! - Good for trend confirmation
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// Rate of Change (ROC) Indicator
pub const ROC = struct {
    allocator: std.mem.Allocator,
    period: u32,

    /// Initialize ROC indicator
    /// @param allocator - Memory allocator
    /// @param period - Lookback period (typically 12)
    /// @return Pointer to new ROC instance
    pub fn init(allocator: std.mem.Allocator, period: u32) !*ROC {
        if (period == 0) return error.InvalidPeriod;

        const self = try allocator.create(ROC);
        self.* = .{
            .allocator = allocator,
            .period = period,
        };
        return self;
    }

    /// Convert to IIndicator interface
    pub fn toIndicator(self: *ROC) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Calculate ROC values
    /// @param candles - Input candle data
    /// @return Array of ROC values in percentage (same length as candles)
    pub fn calculate(self: *ROC, candles: []const Candle) ![]Decimal {
        if (candles.len <= self.period) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // First period values are NaN (not enough data)
        for (0..self.period) |i| {
            result[i] = Decimal.NaN;
        }

        const hundred = Decimal.fromInt(100);

        // Calculate ROC for each point
        for (self.period..candles.len) |i| {
            const current_close = candles[i].close;
            const previous_close = candles[i - self.period].close;

            // Handle zero previous close
            if (previous_close.isZero()) {
                result[i] = Decimal.ZERO;
                continue;
            }

            // ROC = ((Close - Close[n]) / Close[n]) × 100
            const change = current_close.sub(previous_close);
            const ratio = try change.div(previous_close);
            const roc = ratio.mul(hundred);

            result[i] = roc;
        }

        return result;
    }

    /// Clean up resources
    pub fn deinit(self: *ROC) void {
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *ROC = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "ROC";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        const self: *ROC = @ptrCast(@alignCast(ptr));
        return self.period + 1; // Need one extra candle for comparison
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *ROC = @ptrCast(@alignCast(ptr));
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

/// Helper function to create test candles from close prices
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

test "ROC: basic calculation" {
    const allocator = std.testing.allocator;

    // Test with known values
    // If price goes from 100 to 110 in 12 periods, ROC = 10%
    const prices = [_]f64{
        100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112,
    };

    const candles = try createTestCandles(allocator, &prices);
    defer allocator.free(candles);

    const roc = try ROC.init(allocator, 12);
    defer roc.deinit();

    const result = try roc.calculate(candles);
    defer allocator.free(result);

    // First 12 values should be NaN
    for (0..12) |i| {
        try std.testing.expect(result[i].isNaN());
    }

    // ROC at index 12: (112 - 100) / 100 × 100 = 12%
    const expected_roc: f64 = 12.0;
    const actual_roc = result[12].toFloat();
    try std.testing.expectApproxEqAbs(expected_roc, actual_roc, 0.01);
}

test "ROC: uptrend positive values" {
    const allocator = std.testing.allocator;

    // Consistent uptrend
    var prices: [20]f64 = undefined;
    for (0..20) |i| {
        prices[i] = @floatFromInt(100 + i * 5); // +5 each period
    }

    const candles = try createTestCandles(allocator, &prices);
    defer allocator.free(candles);

    const roc = try ROC.init(allocator, 10);
    defer roc.deinit();

    const result = try roc.calculate(candles);
    defer allocator.free(result);

    // All non-NaN values should be positive (uptrend)
    for (10..result.len) |i| {
        const value = result[i].toFloat();
        try std.testing.expect(value > 0);
    }
}

test "ROC: downtrend negative values" {
    const allocator = std.testing.allocator;

    // Consistent downtrend
    var prices: [20]f64 = undefined;
    for (0..20) |i| {
        prices[i] = @floatFromInt(200 - i * 5); // -5 each period
    }

    const candles = try createTestCandles(allocator, &prices);
    defer allocator.free(candles);

    const roc = try ROC.init(allocator, 10);
    defer roc.deinit();

    const result = try roc.calculate(candles);
    defer allocator.free(result);

    // All non-NaN values should be negative (downtrend)
    for (10..result.len) |i| {
        const value = result[i].toFloat();
        try std.testing.expect(value < 0);
    }
}

test "ROC: zero change" {
    const allocator = std.testing.allocator;

    // Flat prices
    var prices: [15]f64 = undefined;
    for (0..15) |_| {
        prices[0] = 100;
    }
    for (0..15) |i| {
        prices[i] = 100;
    }

    const candles = try createTestCandles(allocator, &prices);
    defer allocator.free(candles);

    const roc = try ROC.init(allocator, 10);
    defer roc.deinit();

    const result = try roc.calculate(candles);
    defer allocator.free(result);

    // All non-NaN values should be zero (no change)
    for (10..result.len) |i| {
        try std.testing.expectApproxEqAbs(@as(f64, 0), result[i].toFloat(), 0.01);
    }
}

test "ROC: IIndicator interface" {
    const allocator = std.testing.allocator;

    const prices = [_]f64{
        100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112,
    };

    const candles = try createTestCandles(allocator, &prices);
    defer allocator.free(candles);

    const roc = try ROC.init(allocator, 12);
    const indicator = roc.toIndicator();
    defer indicator.deinit();

    // Test getName
    try std.testing.expectEqualStrings("ROC", indicator.getName());

    // Test getRequiredCandles
    try std.testing.expectEqual(@as(u32, 13), indicator.getRequiredCandles());

    // Test calculate through interface
    const result = try indicator.calculate(candles);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 13), result.len);
}

test "ROC: error cases" {
    const allocator = std.testing.allocator;

    // Invalid period (0)
    try std.testing.expectError(error.InvalidPeriod, ROC.init(allocator, 0));

    // Insufficient data
    {
        const candles = try createTestCandles(allocator, &[_]f64{ 100, 101, 102 });
        defer allocator.free(candles);

        const roc = try ROC.init(allocator, 12);
        defer roc.deinit();

        try std.testing.expectError(error.InsufficientData, roc.calculate(candles));
    }
}

test "ROC: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const prices = [_]f64{
        100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112,
    };

    const candles = try createTestCandles(allocator, &prices);
    defer allocator.free(candles);

    const roc = try ROC.init(allocator, 12);
    defer roc.deinit();

    const result = try roc.calculate(candles);
    defer allocator.free(result);
}

test "ROC: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles
    var prices = try allocator.alloc(f64, 1000);
    defer allocator.free(prices);
    for (0..1000) |i| {
        prices[i] = @as(f64, @floatFromInt(i)) + 100.0;
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    const roc = try ROC.init(allocator, 12);
    defer roc.deinit();

    const start = std.time.nanoTimestamp();
    const result = try roc.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer allocator.free(result);

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    // Performance requirement: < 5ms
    try std.testing.expect(elapsed_ms < 5.0);
}
