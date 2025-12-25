//! Relative Strength Index (RSI)
//!
//! Momentum oscillator that measures the speed and magnitude of price changes.
//!
//! Formula:
//!   RS = Average Gain / Average Loss (using Wilder smoothing)
//!   RSI = 100 - (100 / (1 + RS))
//!   Range: [0, 100]
//!
//! Wilder Smoothing:
//!   First Avg = Sum(values) / period
//!   Subsequent Avg = (Previous Avg × (period - 1) + Current Value) / period
//!
//! Features:
//! - Identifies overbought (>70) and oversold (<30) conditions
//! - Wilder smoothing for consistency
//! - Memory-safe implementation
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// Relative Strength Index (RSI)
pub const RSI = struct {
    allocator: std.mem.Allocator,
    period: u32,

    /// Initialize RSI indicator
    /// @param allocator - Memory allocator
    /// @param period - Number of periods (typically 14)
    /// @return Pointer to new RSI instance
    pub fn init(allocator: std.mem.Allocator, period: u32) !*RSI {
        if (period == 0) return error.InvalidPeriod;

        const self = try allocator.create(RSI);
        self.* = .{
            .allocator = allocator,
            .period = period,
        };
        return self;
    }

    /// Convert to IIndicator interface
    pub fn toIndicator(self: *RSI) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Calculate RSI values
    /// Uses Wilder smoothing method
    /// @param candles - Input candle data
    /// @return Array of RSI values [0-100] (same length as candles)
    pub fn calculate(self: *RSI, candles: []const Candle) ![]Decimal {
        if (candles.len <= self.period) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // First period values are NaN (not enough data)
        for (0..self.period) |i| {
            result[i] = Decimal.NaN;
        }

        // Calculate price changes and separate gains/losses
        var gains = try self.allocator.alloc(Decimal, candles.len);
        defer self.allocator.free(gains);
        var losses = try self.allocator.alloc(Decimal, candles.len);
        defer self.allocator.free(losses);

        gains[0] = Decimal.ZERO;
        losses[0] = Decimal.ZERO;

        for (1..candles.len) |i| {
            const change = candles[i].close.sub(candles[i - 1].close);
            if (change.cmp(Decimal.ZERO) == .gt) {
                // Price went up
                gains[i] = change;
                losses[i] = Decimal.ZERO;
            } else {
                // Price went down or stayed same
                gains[i] = Decimal.ZERO;
                losses[i] = change.abs();
            }
        }

        // Calculate first average gain/loss (simple average)
        var avg_gain = Decimal.ZERO;
        var avg_loss = Decimal.ZERO;
        for (1..self.period + 1) |i| {
            avg_gain = avg_gain.add(gains[i]);
            avg_loss = avg_loss.add(losses[i]);
        }
        const period_decimal = Decimal.fromInt(@as(i64, @intCast(self.period)));
        avg_gain = try avg_gain.div(period_decimal);
        avg_loss = try avg_loss.div(period_decimal);

        // Calculate first RSI
        result[self.period] = try self.calculateRSI(avg_gain, avg_loss);

        // Use Wilder smoothing for subsequent RSI values
        // Avg[t] = (Avg[t-1] × (period - 1) + Value[t]) / period
        const period_minus_1 = Decimal.fromInt(@as(i64, @intCast(self.period - 1)));

        for (self.period + 1..candles.len) |i| {
            // Wilder smoothing formula
            const prev_gain_weighted = avg_gain.mul(period_minus_1);
            const prev_loss_weighted = avg_loss.mul(period_minus_1);

            avg_gain = try prev_gain_weighted.add(gains[i]).div(period_decimal);
            avg_loss = try prev_loss_weighted.add(losses[i]).div(period_decimal);

            result[i] = try self.calculateRSI(avg_gain, avg_loss);
        }

        return result;
    }

    /// Calculate RSI from average gain and loss
    /// Formula: RSI = 100 - (100 / (1 + RS))
    fn calculateRSI(self: *RSI, avg_gain: Decimal, avg_loss: Decimal) !Decimal {
        _ = self;

        // Special case: no losses means RSI = 100
        if (avg_loss.isZero()) {
            return Decimal.fromInt(100);
        }

        // Special case: no gains means RSI = 0
        if (avg_gain.isZero()) {
            return Decimal.ZERO;
        }

        // RS = Average Gain / Average Loss
        const rs = try avg_gain.div(avg_loss);

        // RSI = 100 - (100 / (1 + RS))
        const one_plus_rs = Decimal.ONE.add(rs);
        const hundred = Decimal.fromInt(100);
        const fraction = try hundred.div(one_plus_rs);
        const rsi = hundred.sub(fraction);

        return rsi;
    }

    /// Clean up resources
    pub fn deinit(self: *RSI) void {
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *RSI = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "RSI";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        const self: *RSI = @ptrCast(@alignCast(ptr));
        return self.period;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *RSI = @ptrCast(@alignCast(ptr));
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

test "RSI: basic calculation" {
    const allocator = std.testing.allocator;

    // Simple test: prices going up consistently
    const candles = try createTestCandles(allocator, &[_]f64{
        100, 105, 110, 115, 120, 125, 130, 135, 140, 145,
        150, 155, 160, 165, 170,
    });
    defer allocator.free(candles);

    const rsi = try RSI.init(allocator, 14);
    defer rsi.deinit();

    const result = try rsi.calculate(candles);
    defer allocator.free(result);

    // First 14 values should be NaN
    for (0..14) |i| {
        try std.testing.expect(result[i].isNaN());
    }

    // Prices consistently going up should give high RSI (close to 100)
    const rsi_value = result[14].toFloat();
    try std.testing.expect(rsi_value > 90.0);
    try std.testing.expect(rsi_value <= 100.0);
    //std.debug.print("RSI (all gains): {d:.2}\n", .{rsi_value});
}

test "RSI: boundary conditions" {
    const allocator = std.testing.allocator;

    // Test all gains (RSI should be 100)
    {
        var prices = try allocator.alloc(f64, 20);
        defer allocator.free(prices);
        for (0..20) |i| {
            prices[i] = @as(f64, @floatFromInt(i)) * 10.0 + 100.0; // Increasing
        }

        const candles = try createTestCandles(allocator, prices);
        defer allocator.free(candles);

        const rsi = try RSI.init(allocator, 14);
        defer rsi.deinit();

        const result = try rsi.calculate(candles);
        defer allocator.free(result);

        // With all gains, RSI should be 100
        try std.testing.expectApproxEqAbs(@as(f64, 100.0), result[14].toFloat(), 0.01);
    }

    // Test all losses (RSI should be 0)
    {
        var prices = try allocator.alloc(f64, 20);
        defer allocator.free(prices);
        for (0..20) |i| {
            prices[i] = @as(f64, @floatFromInt(20 - i)) * 10.0 + 100.0; // Decreasing
        }

        const candles = try createTestCandles(allocator, prices);
        defer allocator.free(candles);

        const rsi = try RSI.init(allocator, 14);
        defer rsi.deinit();

        const result = try rsi.calculate(candles);
        defer allocator.free(result);

        // With all losses, RSI should be 0
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), result[14].toFloat(), 0.01);
    }
}

test "RSI: IIndicator interface" {
    const allocator = std.testing.allocator;

    const candles = try createTestCandles(allocator, &[_]f64{
        100, 105, 110, 115, 120, 125, 130, 135, 140, 145,
        150, 155, 160, 165, 170,
    });
    defer allocator.free(candles);

    const rsi = try RSI.init(allocator, 14);
    const indicator = rsi.toIndicator();
    defer indicator.deinit();

    // Test getName
    try std.testing.expectEqualStrings("RSI", indicator.getName());

    // Test getRequiredCandles
    try std.testing.expectEqual(@as(u32, 14), indicator.getRequiredCandles());

    // Test calculate through interface
    const result = try indicator.calculate(candles);
    defer allocator.free(result);

    // Verify RSI is in valid range [0, 100]
    for (14..result.len) |i| {
        const value = result[i].toFloat();
        try std.testing.expect(value >= 0.0);
        try std.testing.expect(value <= 100.0);
    }
}

test "RSI: error cases" {
    const allocator = std.testing.allocator;

    // Invalid period (0)
    try std.testing.expectError(error.InvalidPeriod, RSI.init(allocator, 0));

    // Insufficient data
    {
        const candles = try createTestCandles(allocator, &[_]f64{ 100, 110, 120 });
        defer allocator.free(candles);

        const rsi = try RSI.init(allocator, 14);
        defer rsi.deinit();

        try std.testing.expectError(error.InsufficientData, rsi.calculate(candles));
    }
}

test "RSI: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const candles = try createTestCandles(allocator, &[_]f64{
        100, 105, 110, 115, 120, 125, 130, 135, 140, 145,
        150, 155, 160, 165, 170,
    });
    defer allocator.free(candles);

    const rsi = try RSI.init(allocator, 14);
    defer rsi.deinit();

    const result = try rsi.calculate(candles);
    defer allocator.free(result);
}

test "RSI: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles with some variation
    var prices = try allocator.alloc(f64, 1000);
    defer allocator.free(prices);
    for (0..1000) |i| {
        const base = @as(f64, @floatFromInt(i)) + 100.0;
        const variation = @as(f64, @floatFromInt(i % 10)) - 5.0;
        prices[i] = base + variation;
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    const rsi = try RSI.init(allocator, 14);
    defer rsi.deinit();

    const start = std.time.nanoTimestamp();
    const result = try rsi.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer allocator.free(result);

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    //std.debug.print("RSI(14) on 1000 candles: {d:.2}ms\n", .{elapsed_ms});

    // Performance requirement: < 10ms
    try std.testing.expect(elapsed_ms < 10.0);
}
