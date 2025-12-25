//! Exponential Moving Average (EMA)
//!
//! Calculates exponentially weighted moving average, giving more weight to recent prices.
//!
//! Formula:
//!   α = 2 / (period + 1)
//!   EMA[0] = Price[0]
//!   EMA[t] = α × Price[t] + (1 - α) × EMA[t-1]
//!
//! Features:
//! - Recursive calculation for efficiency
//! - More responsive to recent price changes than SMA
//! - Memory-safe implementation
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// Exponential Moving Average (EMA)
pub const EMA = struct {
    allocator: std.mem.Allocator,
    period: u32,

    /// Initialize EMA indicator
    /// @param allocator - Memory allocator
    /// @param period - Number of periods for averaging (must be > 0)
    /// @return Pointer to new EMA instance
    pub fn init(allocator: std.mem.Allocator, period: u32) !*EMA {
        if (period == 0) return error.InvalidPeriod;

        const self = try allocator.create(EMA);
        self.* = .{
            .allocator = allocator,
            .period = period,
        };
        return self;
    }

    /// Convert to IIndicator interface
    pub fn toIndicator(self: *EMA) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Calculate EMA values
    /// Uses recursive formula for efficiency
    /// @param candles - Input candle data
    /// @return Array of EMA values (same length as candles)
    pub fn calculate(self: *EMA, candles: []const Candle) ![]Decimal {
        if (candles.len == 0) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // Calculate smoothing factor: α = 2 / (period + 1)
        const two = Decimal.fromInt(2);
        const period_plus_one = Decimal.fromInt(@as(i64, @intCast(self.period + 1)));
        const alpha = try two.div(period_plus_one);
        const one_minus_alpha = Decimal.ONE.sub(alpha);

        // EMA[0] = Price[0] (initial value)
        result[0] = candles[0].close;

        // Recursive calculation: EMA[t] = α × Price[t] + (1 - α) × EMA[t-1]
        for (1..candles.len) |i| {
            const term1 = alpha.mul(candles[i].close);
            const term2 = one_minus_alpha.mul(result[i - 1]);
            result[i] = term1.add(term2);
        }

        return result;
    }

    /// Clean up resources
    pub fn deinit(self: *EMA) void {
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *EMA = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "EMA";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        const self: *EMA = @ptrCast(@alignCast(ptr));
        return self.period;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *EMA = @ptrCast(@alignCast(ptr));
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

test "EMA: basic calculation" {
    const allocator = std.testing.allocator;

    // Test data: [10, 20, 30, 40, 50]
    const candles = try createTestCandles(allocator, &[_]f64{ 10, 20, 30, 40, 50 });
    defer allocator.free(candles);

    const ema = try EMA.init(allocator, 3);
    defer ema.deinit();

    const result = try ema.calculate(candles);
    defer allocator.free(result);

    // EMA[0] = 10 (initial value)
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), result[0].toFloat(), 0.0001);

    // α = 2/(3+1) = 0.5
    // EMA[1] = 0.5 × 20 + 0.5 × 10 = 15
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), result[1].toFloat(), 0.01);

    // EMA[2] = 0.5 × 30 + 0.5 × 15 = 22.5
    try std.testing.expectApproxEqAbs(@as(f64, 22.5), result[2].toFloat(), 0.01);

    // EMA[3] = 0.5 × 40 + 0.5 × 22.5 = 31.25
    try std.testing.expectApproxEqAbs(@as(f64, 31.25), result[3].toFloat(), 0.01);

    // EMA[4] = 0.5 × 50 + 0.5 × 31.25 = 40.625
    try std.testing.expectApproxEqAbs(@as(f64, 40.625), result[4].toFloat(), 0.01);
}

test "EMA: IIndicator interface" {
    const allocator = std.testing.allocator;

    const candles = try createTestCandles(allocator, &[_]f64{ 10, 20, 30, 40, 50 });
    defer allocator.free(candles);

    const ema = try EMA.init(allocator, 3);
    const indicator = ema.toIndicator();
    defer indicator.deinit();

    // Test getName
    try std.testing.expectEqualStrings("EMA", indicator.getName());

    // Test getRequiredCandles
    try std.testing.expectEqual(@as(u32, 3), indicator.getRequiredCandles());

    // Test calculate through interface
    const result = try indicator.calculate(candles);
    defer allocator.free(result);

    try std.testing.expectApproxEqAbs(@as(f64, 10.0), result[0].toFloat(), 0.0001);
}

test "EMA: compare with SMA - more responsive" {
    const allocator = std.testing.allocator;
    const SMA = @import("sma.zig").SMA;

    // Test data with a sudden price jump
    const candles = try createTestCandles(allocator, &[_]f64{ 10, 10, 10, 50, 50 });
    defer allocator.free(candles);

    const ema = try EMA.init(allocator, 3);
    defer ema.deinit();
    const ema_result = try ema.calculate(candles);
    defer allocator.free(ema_result);

    const sma = try SMA.init(allocator, 3);
    defer sma.deinit();
    const sma_result = try sma.calculate(candles);
    defer allocator.free(sma_result);

    // After price jump, EMA should respond faster than SMA
    // EMA gives more weight to recent prices
    const ema_value = ema_result[4].toFloat();
    const sma_value = sma_result[4].toFloat();

    // EMA should be closer to 50 than SMA
    try std.testing.expect(ema_value > sma_value);
    //std.debug.print("EMA: {d:.2}, SMA: {d:.2}\n", .{ ema_value, sma_value });
}

test "EMA: different periods" {
    const allocator = std.testing.allocator;

    const candles = try createTestCandles(allocator, &[_]f64{ 100, 110, 120, 130, 140 });
    defer allocator.free(candles);

    // Shorter period (2) - more responsive
    {
        const ema = try EMA.init(allocator, 2);
        defer ema.deinit();

        const result = try ema.calculate(candles);
        defer allocator.free(result);

        // α = 2/(2+1) = 2/3 ≈ 0.667
        try std.testing.expectApproxEqAbs(@as(f64, 100.0), result[0].toFloat(), 0.01);
    }

    // Longer period (10) - smoother
    {
        const ema = try EMA.init(allocator, 10);
        defer ema.deinit();

        const result = try ema.calculate(candles);
        defer allocator.free(result);

        // α = 2/(10+1) ≈ 0.182
        try std.testing.expectApproxEqAbs(@as(f64, 100.0), result[0].toFloat(), 0.01);
    }
}

test "EMA: error cases" {
    const allocator = std.testing.allocator;

    // Invalid period (0)
    try std.testing.expectError(error.InvalidPeriod, EMA.init(allocator, 0));

    // Empty candle array
    {
        const candles = try allocator.alloc(Candle, 0);
        defer allocator.free(candles);

        const ema = try EMA.init(allocator, 3);
        defer ema.deinit();

        try std.testing.expectError(error.InsufficientData, ema.calculate(candles));
    }
}

test "EMA: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const candles = try createTestCandles(allocator, &[_]f64{ 10, 20, 30, 40, 50 });
    defer allocator.free(candles);

    const ema = try EMA.init(allocator, 3);
    defer ema.deinit();

    const result = try ema.calculate(candles);
    defer allocator.free(result);
}

test "EMA: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles
    var prices = try allocator.alloc(f64, 1000);
    defer allocator.free(prices);
    for (0..1000) |i| {
        prices[i] = @as(f64, @floatFromInt(i)) + 100.0;
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    const ema = try EMA.init(allocator, 20);
    defer ema.deinit();

    const start = std.time.nanoTimestamp();
    const result = try ema.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer allocator.free(result);

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    //std.debug.print("EMA(20) on 1000 candles: {d:.2}ms\n", .{elapsed_ms});

    // Performance requirement: < 10ms
    try std.testing.expect(elapsed_ms < 10.0);
}
