//! Simple Moving Average (SMA)
//!
//! Calculates the arithmetic mean of prices over a specified period.
//!
//! Formula: SMA = (P1 + P2 + ... + Pn) / n
//!
//! Features:
//! - Sliding window optimization for O(n) performance
//! - First (period-1) values are NaN
//! - Memory-safe implementation
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// Simple Moving Average (SMA)
pub const SMA = struct {
    allocator: std.mem.Allocator,
    period: u32,

    /// Initialize SMA indicator
    /// @param allocator - Memory allocator
    /// @param period - Number of periods for averaging (must be > 0)
    /// @return Pointer to new SMA instance
    pub fn init(allocator: std.mem.Allocator, period: u32) !*SMA {
        if (period == 0) return error.InvalidPeriod;

        const self = try allocator.create(SMA);
        self.* = .{
            .allocator = allocator,
            .period = period,
        };
        return self;
    }

    /// Convert to IIndicator interface
    pub fn toIndicator(self: *SMA) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Calculate SMA values
    /// Uses sliding window optimization: O(n) instead of O(n*period)
    /// @param candles - Input candle data
    /// @return Array of SMA values (same length as candles)
    pub fn calculate(self: *SMA, candles: []const Candle) ![]Decimal {
        if (candles.len < self.period) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // First period-1 values are NaN (not enough data)
        for (0..self.period - 1) |i| {
            result[i] = Decimal.NaN;
        }

        // Calculate first SMA (simple sum)
        var sum = Decimal.ZERO;
        for (0..self.period) |i| {
            sum = sum.add(candles[i].close);
        }
        result[self.period - 1] = try sum.div(Decimal.fromInt(@as(i64, @intCast(self.period))));

        // Sliding window: sum = sum - old_value + new_value
        // This is O(n) instead of O(n*period)
        for (self.period..candles.len) |i| {
            // Remove oldest value, add newest value
            sum = sum.sub(candles[i - self.period].close);
            sum = sum.add(candles[i].close);
            result[i] = try sum.div(Decimal.fromInt(@as(i64, @intCast(self.period))));
        }

        return result;
    }

    /// Clean up resources
    pub fn deinit(self: *SMA) void {
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *SMA = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "SMA";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        const self: *SMA = @ptrCast(@alignCast(ptr));
        return self.period;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *SMA = @ptrCast(@alignCast(ptr));
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
            .timestamp = .{ .millis = @intCast(i * 3600000) }, // 1 hour intervals
            .open = dec_price,
            .high = dec_price,
            .low = dec_price,
            .close = dec_price,
            .volume = Decimal.fromInt(100),
        };
    }
    return candles;
}

test "SMA: basic calculation" {
    const allocator = std.testing.allocator;

    // Test data: [1, 2, 3, 4, 5]
    const candles = try createTestCandles(allocator, &[_]f64{ 1, 2, 3, 4, 5 });
    defer allocator.free(candles);

    const sma = try SMA.init(allocator, 3);
    defer sma.deinit();

    const result = try sma.calculate(candles);
    defer allocator.free(result);

    // First 2 values should be NaN
    try std.testing.expect(result[0].isNaN());
    try std.testing.expect(result[1].isNaN());

    // SMA(3) of [1,2,3] = (1+2+3)/3 = 2
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result[2].toFloat(), 0.0001);

    // SMA(3) of [2,3,4] = (2+3+4)/3 = 3
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), result[3].toFloat(), 0.0001);

    // SMA(3) of [3,4,5] = (3+4+5)/3 = 4
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), result[4].toFloat(), 0.0001);
}

test "SMA: IIndicator interface" {
    const allocator = std.testing.allocator;

    const candles = try createTestCandles(allocator, &[_]f64{ 1, 2, 3, 4, 5 });
    defer allocator.free(candles);

    const sma = try SMA.init(allocator, 3);
    const indicator = sma.toIndicator();
    defer indicator.deinit();

    // Test getName
    try std.testing.expectEqualStrings("SMA", indicator.getName());

    // Test getRequiredCandles
    try std.testing.expectEqual(@as(u32, 3), indicator.getRequiredCandles());

    // Test calculate through interface
    const result = try indicator.calculate(candles);
    defer allocator.free(result);

    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result[2].toFloat(), 0.0001);
}

test "SMA: different periods" {
    const allocator = std.testing.allocator;

    const candles = try createTestCandles(allocator, &[_]f64{ 10, 20, 30, 40, 50 });
    defer allocator.free(candles);

    // Test period=2
    {
        const sma = try SMA.init(allocator, 2);
        defer sma.deinit();

        const result = try sma.calculate(candles);
        defer allocator.free(result);

        try std.testing.expect(result[0].isNaN());
        try std.testing.expectApproxEqAbs(@as(f64, 15.0), result[1].toFloat(), 0.0001); // (10+20)/2
        try std.testing.expectApproxEqAbs(@as(f64, 25.0), result[2].toFloat(), 0.0001); // (20+30)/2
        try std.testing.expectApproxEqAbs(@as(f64, 35.0), result[3].toFloat(), 0.0001); // (30+40)/2
        try std.testing.expectApproxEqAbs(@as(f64, 45.0), result[4].toFloat(), 0.0001); // (40+50)/2
    }

    // Test period=5
    {
        const sma = try SMA.init(allocator, 5);
        defer sma.deinit();

        const result = try sma.calculate(candles);
        defer allocator.free(result);

        try std.testing.expect(result[0].isNaN());
        try std.testing.expect(result[1].isNaN());
        try std.testing.expect(result[2].isNaN());
        try std.testing.expect(result[3].isNaN());
        // (10+20+30+40+50)/5 = 30
        try std.testing.expectApproxEqAbs(@as(f64, 30.0), result[4].toFloat(), 0.0001);
    }
}

test "SMA: error cases" {
    const allocator = std.testing.allocator;

    // Invalid period (0)
    try std.testing.expectError(error.InvalidPeriod, SMA.init(allocator, 0));

    // Insufficient data
    {
        const candles = try createTestCandles(allocator, &[_]f64{ 1, 2 });
        defer allocator.free(candles);

        const sma = try SMA.init(allocator, 5);
        defer sma.deinit();

        try std.testing.expectError(error.InsufficientData, sma.calculate(candles));
    }
}

test "SMA: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const candles = try createTestCandles(allocator, &[_]f64{ 1, 2, 3, 4, 5 });
    defer allocator.free(candles);

    const sma = try SMA.init(allocator, 3);
    defer sma.deinit();

    const result = try sma.calculate(candles);
    defer allocator.free(result);
}

test "SMA: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles
    var prices = try allocator.alloc(f64, 1000);
    defer allocator.free(prices);
    for (0..1000) |i| {
        prices[i] = @as(f64, @floatFromInt(i)) + 100.0;
    }

    const candles = try createTestCandles(allocator, prices);
    defer allocator.free(candles);

    const sma = try SMA.init(allocator, 20);
    defer sma.deinit();

    const start = std.time.nanoTimestamp();
    const result = try sma.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer allocator.free(result);

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    //std.debug.print("SMA(20) on 1000 candles: {d:.2}ms\n", .{elapsed_ms});

    // Performance requirement: < 10ms
    try std.testing.expect(elapsed_ms < 10.0);
}
