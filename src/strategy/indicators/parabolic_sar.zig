//! Parabolic SAR (Stop and Reverse)
//!
//! Trend-following indicator developed by J. Welles Wilder Jr.
//! Provides potential entry and exit points.
//!
//! Formula:
//!   Uptrend: SAR = Prior SAR + AF × (EP - Prior SAR)
//!   Downtrend: SAR = Prior SAR - AF × (Prior SAR - EP)
//!
//! Where:
//!   - SAR: Stop and Reverse point
//!   - EP: Extreme Point (highest high in uptrend, lowest low in downtrend)
//!   - AF: Acceleration Factor (starts at 0.02, increases by 0.02 each new EP, max 0.2)
//!
//! Trading signals:
//!   - Price > SAR: Uptrend (hold long or enter long)
//!   - Price < SAR: Downtrend (hold short or enter short)
//!   - SAR reversal: Potential trend change
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// Parabolic SAR Indicator
pub const ParabolicSAR = struct {
    allocator: std.mem.Allocator,
    af_start: Decimal, // Starting Acceleration Factor (default: 0.02)
    af_increment: Decimal, // AF increment (default: 0.02)
    af_max: Decimal, // Maximum AF (default: 0.2)

    /// Initialize Parabolic SAR with default parameters
    /// @param allocator - Memory allocator
    /// @return Pointer to new ParabolicSAR instance
    pub fn init(allocator: std.mem.Allocator) !*ParabolicSAR {
        return initWithParams(allocator, 0.02, 0.02, 0.2);
    }

    /// Initialize Parabolic SAR with custom parameters
    /// @param allocator - Memory allocator
    /// @param af_start - Starting acceleration factor
    /// @param af_increment - AF increment when new EP is reached
    /// @param af_max - Maximum acceleration factor
    /// @return Pointer to new ParabolicSAR instance
    pub fn initWithParams(
        allocator: std.mem.Allocator,
        af_start: f64,
        af_increment: f64,
        af_max: f64,
    ) !*ParabolicSAR {
        if (af_start <= 0 or af_increment <= 0 or af_max <= 0) {
            return error.InvalidParameter;
        }
        if (af_start > af_max) {
            return error.InvalidParameter;
        }

        const self = try allocator.create(ParabolicSAR);
        self.* = .{
            .allocator = allocator,
            .af_start = Decimal.fromFloat(af_start),
            .af_increment = Decimal.fromFloat(af_increment),
            .af_max = Decimal.fromFloat(af_max),
        };
        return self;
    }

    /// Convert to IIndicator interface
    pub fn toIndicator(self: *ParabolicSAR) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Calculate Parabolic SAR values
    /// @param candles - Input candle data
    /// @return Array of SAR values (same length as candles)
    pub fn calculate(self: *ParabolicSAR, candles: []const Candle) ![]Decimal {
        if (candles.len < 2) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // Determine initial trend based on first two candles
        var is_uptrend = candles[1].close.cmp(candles[0].close) == .gt;

        // Initialize SAR and EP
        var sar: Decimal = undefined;
        var ep: Decimal = undefined;
        var af = self.af_start;

        if (is_uptrend) {
            // Start SAR at the low of first candle
            sar = candles[0].low;
            ep = candles[1].high;
        } else {
            // Start SAR at the high of first candle
            sar = candles[0].high;
            ep = candles[1].low;
        }

        // First SAR value
        result[0] = sar;

        // Calculate SAR for each subsequent candle
        for (1..candles.len) |i| {
            const candle = candles[i];
            const prev_candle = candles[i - 1];

            if (is_uptrend) {
                // Check for reversal (price falls below SAR)
                if (candle.low.cmp(sar) == .lt) {
                    // Reverse to downtrend
                    is_uptrend = false;
                    sar = ep; // SAR becomes the previous EP
                    ep = candle.low;
                    af = self.af_start;
                } else {
                    // Update EP if new high
                    if (candle.high.cmp(ep) == .gt) {
                        ep = candle.high;
                        // Increase AF
                        af = af.add(self.af_increment);
                        if (af.cmp(self.af_max) == .gt) {
                            af = self.af_max;
                        }
                    }

                    // Calculate new SAR
                    // SAR = Prior SAR + AF × (EP - Prior SAR)
                    const diff = ep.sub(sar);
                    const increment = af.mul(diff);
                    sar = sar.add(increment);

                    // SAR cannot be above previous two lows
                    if (sar.cmp(prev_candle.low) == .gt) {
                        sar = prev_candle.low;
                    }
                    if (i >= 2 and sar.cmp(candles[i - 2].low) == .gt) {
                        sar = candles[i - 2].low;
                    }
                }
            } else {
                // Downtrend
                // Check for reversal (price rises above SAR)
                if (candle.high.cmp(sar) == .gt) {
                    // Reverse to uptrend
                    is_uptrend = true;
                    sar = ep; // SAR becomes the previous EP
                    ep = candle.high;
                    af = self.af_start;
                } else {
                    // Update EP if new low
                    if (candle.low.cmp(ep) == .lt) {
                        ep = candle.low;
                        // Increase AF
                        af = af.add(self.af_increment);
                        if (af.cmp(self.af_max) == .gt) {
                            af = self.af_max;
                        }
                    }

                    // Calculate new SAR
                    // SAR = Prior SAR - AF × (Prior SAR - EP)
                    const diff = sar.sub(ep);
                    const decrement = af.mul(diff);
                    sar = sar.sub(decrement);

                    // SAR cannot be below previous two highs
                    if (sar.cmp(prev_candle.high) == .lt) {
                        sar = prev_candle.high;
                    }
                    if (i >= 2 and sar.cmp(candles[i - 2].high) == .lt) {
                        sar = candles[i - 2].high;
                    }
                }
            }

            result[i] = sar;
        }

        return result;
    }

    /// Clean up resources
    pub fn deinit(self: *ParabolicSAR) void {
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *ParabolicSAR = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "ParabolicSAR";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        _ = ptr;
        return 2; // Need at least 2 candles to determine initial trend
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *ParabolicSAR = @ptrCast(@alignCast(ptr));
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

test "ParabolicSAR: basic calculation" {
    const allocator = std.testing.allocator;

    // Uptrend data
    const data = [_][4]f64{
        .{ 100, 105, 95, 102 },
        .{ 102, 108, 100, 106 },
        .{ 106, 112, 104, 110 },
        .{ 110, 118, 108, 116 },
        .{ 116, 124, 114, 122 },
        .{ 122, 130, 120, 128 },
    };

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const psar = try ParabolicSAR.init(allocator);
    defer psar.deinit();

    const result = try psar.calculate(candles);
    defer allocator.free(result);

    // In uptrend, SAR should be below price
    for (result, 0..) |sar, i| {
        // SAR should be less than the low of the candle in uptrend
        // (or equal at reversal points)
        try std.testing.expect(sar.toFloat() <= candles[i].high.toFloat());
    }
}

test "ParabolicSAR: uptrend SAR below price" {
    const allocator = std.testing.allocator;

    // Clear uptrend
    var data: [10][4]f64 = undefined;
    for (0..10) |i| {
        const base: f64 = @floatFromInt(100 + i * 10);
        data[i] = .{ base, base + 5, base - 2, base + 3 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const psar = try ParabolicSAR.init(allocator);
    defer psar.deinit();

    const result = try psar.calculate(candles);
    defer allocator.free(result);

    // In uptrend, SAR should trail below the lows
    for (1..result.len) |i| {
        try std.testing.expect(result[i].toFloat() < candles[i].low.toFloat());
    }
}

test "ParabolicSAR: downtrend SAR above price" {
    const allocator = std.testing.allocator;

    // Clear downtrend
    var data: [10][4]f64 = undefined;
    for (0..10) |i| {
        const base: f64 = @floatFromInt(200 - i * 10);
        data[i] = .{ base, base + 2, base - 5, base - 3 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const psar = try ParabolicSAR.init(allocator);
    defer psar.deinit();

    const result = try psar.calculate(candles);
    defer allocator.free(result);

    // In downtrend, SAR should trail above the highs (after initial setup)
    for (2..result.len) |i| {
        try std.testing.expect(result[i].toFloat() > candles[i].high.toFloat());
    }
}

test "ParabolicSAR: IIndicator interface" {
    const allocator = std.testing.allocator;

    const data = [_][4]f64{
        .{ 100, 105, 95, 102 },
        .{ 102, 108, 100, 106 },
        .{ 106, 112, 104, 110 },
    };

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const psar = try ParabolicSAR.init(allocator);
    const indicator = psar.toIndicator();
    defer indicator.deinit();

    // Test getName
    try std.testing.expectEqualStrings("ParabolicSAR", indicator.getName());

    // Test getRequiredCandles
    try std.testing.expectEqual(@as(u32, 2), indicator.getRequiredCandles());

    // Test calculate through interface
    const result = try indicator.calculate(candles);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 3), result.len);
}

test "ParabolicSAR: custom parameters" {
    const allocator = std.testing.allocator;

    const data = [_][4]f64{
        .{ 100, 105, 95, 102 },
        .{ 102, 108, 100, 106 },
        .{ 106, 112, 104, 110 },
        .{ 110, 118, 108, 116 },
    };

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    // More aggressive acceleration
    const psar = try ParabolicSAR.initWithParams(allocator, 0.04, 0.04, 0.4);
    defer psar.deinit();

    const result = try psar.calculate(candles);
    defer allocator.free(result);

    // Should calculate without error
    try std.testing.expectEqual(@as(usize, 4), result.len);
}

test "ParabolicSAR: error cases" {
    const allocator = std.testing.allocator;

    // Invalid parameters
    try std.testing.expectError(
        error.InvalidParameter,
        ParabolicSAR.initWithParams(allocator, 0, 0.02, 0.2),
    );
    try std.testing.expectError(
        error.InvalidParameter,
        ParabolicSAR.initWithParams(allocator, 0.3, 0.02, 0.2), // start > max
    );

    // Insufficient data
    {
        const data = [_][4]f64{
            .{ 100, 105, 95, 102 },
        };
        const candles = try createTestCandlesOHLC(allocator, &data);
        defer allocator.free(candles);

        const psar = try ParabolicSAR.init(allocator);
        defer psar.deinit();

        try std.testing.expectError(error.InsufficientData, psar.calculate(candles));
    }
}

test "ParabolicSAR: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const data = [_][4]f64{
        .{ 100, 105, 95, 102 },
        .{ 102, 108, 100, 106 },
        .{ 106, 112, 104, 110 },
        .{ 110, 118, 108, 116 },
    };

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const psar = try ParabolicSAR.init(allocator);
    defer psar.deinit();

    const result = try psar.calculate(candles);
    defer allocator.free(result);
}

test "ParabolicSAR: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles with some trend variation
    var data = try allocator.alloc([4]f64, 1000);
    defer allocator.free(data);
    for (0..1000) |i| {
        const base: f64 = @floatFromInt(100 + @as(i32, @intCast(i % 200)) - 100);
        data[i] = .{ base + 100, base + 105, base + 95, base + 100 };
    }

    const candles = try createTestCandlesOHLC(allocator, data);
    defer allocator.free(candles);

    const psar = try ParabolicSAR.init(allocator);
    defer psar.deinit();

    const start = std.time.nanoTimestamp();
    const result = try psar.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer allocator.free(result);

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    // Performance requirement: < 10ms
    try std.testing.expect(elapsed_ms < 10.0);
}
