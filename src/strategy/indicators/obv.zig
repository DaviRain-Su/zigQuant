//! On Balance Volume (OBV)
//!
//! Volume-based momentum indicator that uses volume flow to predict price changes.
//!
//! Formula:
//!   If Close > Previous Close: OBV = Previous OBV + Volume
//!   If Close < Previous Close: OBV = Previous OBV - Volume
//!   If Close = Previous Close: OBV = Previous OBV
//!
//! Trading signals:
//!   - Rising OBV with rising price: Uptrend confirmed
//!   - Falling OBV with falling price: Downtrend confirmed
//!   - OBV divergence from price: Potential reversal
//!   - OBV breakout: Volume-confirmed price movement
//!
//! Features:
//!   - Cumulative volume indicator
//!   - Shows buying/selling pressure
//!   - Useful for confirming price trends
//!   - Can signal divergences before price moves
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// On Balance Volume (OBV)
pub const OBV = struct {
    allocator: std.mem.Allocator,

    /// Initialize OBV indicator
    /// @param allocator - Memory allocator
    /// @return Pointer to new OBV instance
    pub fn init(allocator: std.mem.Allocator) !*OBV {
        const self = try allocator.create(OBV);
        self.* = .{
            .allocator = allocator,
        };
        return self;
    }

    /// Convert to IIndicator interface
    pub fn toIndicator(self: *OBV) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Calculate OBV values
    /// @param candles - Input candle data
    /// @return Array of OBV values (same length as candles)
    pub fn calculate(self: *OBV, candles: []const Candle) ![]Decimal {
        if (candles.len == 0) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // First OBV is just the first volume (or 0)
        result[0] = candles[0].volume;

        // Calculate OBV for each subsequent candle
        for (1..candles.len) |i| {
            const current_close = candles[i].close;
            const previous_close = candles[i - 1].close;
            const volume = candles[i].volume;

            const cmp_result = current_close.cmp(previous_close);
            if (cmp_result == .gt) {
                // Close > Previous Close: Add volume
                result[i] = result[i - 1].add(volume);
            } else if (cmp_result == .lt) {
                // Close < Previous Close: Subtract volume
                result[i] = result[i - 1].sub(volume);
            } else {
                // Close = Previous Close: Keep same
                result[i] = result[i - 1];
            }
        }

        return result;
    }

    /// Clean up resources
    pub fn deinit(self: *OBV) void {
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *OBV = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "OBV";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        _ = ptr;
        return 1; // OBV can start from first candle
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *OBV = @ptrCast(@alignCast(ptr));
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

/// Helper function to create test candles
fn createTestCandlesWithVolume(
    allocator: std.mem.Allocator,
    data: []const [2]f64, // [close, volume]
) ![]Candle {
    var candles = try allocator.alloc(Candle, data.len);
    for (data, 0..) |cv, i| {
        const close = Decimal.fromFloat(cv[0]);
        const volume = Decimal.fromFloat(cv[1]);
        candles[i] = Candle{
            .timestamp = .{ .millis = @intCast(i * 3600000) },
            .open = close,
            .high = close,
            .low = close,
            .close = close,
            .volume = volume,
        };
    }
    return candles;
}

test "OBV: basic calculation" {
    const allocator = std.testing.allocator;

    // Test data: [close, volume]
    // Price up: add volume
    // Price down: subtract volume
    // Price same: keep same
    const data = [_][2]f64{
        .{ 100, 1000 }, // Initial OBV = 1000
        .{ 105, 1500 }, // Up: OBV = 1000 + 1500 = 2500
        .{ 103, 1200 }, // Down: OBV = 2500 - 1200 = 1300
        .{ 103, 800 }, // Same: OBV = 1300
        .{ 110, 2000 }, // Up: OBV = 1300 + 2000 = 3300
        .{ 108, 1000 }, // Down: OBV = 3300 - 1000 = 2300
    };

    const candles = try createTestCandlesWithVolume(allocator, &data);
    defer allocator.free(candles);

    const obv = try OBV.init(allocator);
    defer obv.deinit();

    const result = try obv.calculate(candles);
    defer allocator.free(result);

    // Verify OBV values
    try std.testing.expectApproxEqAbs(@as(f64, 1000), result[0].toFloat(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 2500), result[1].toFloat(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 1300), result[2].toFloat(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 1300), result[3].toFloat(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 3300), result[4].toFloat(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 2300), result[5].toFloat(), 0.01);
}

test "OBV: uptrend accumulation" {
    const allocator = std.testing.allocator;

    // Consistent uptrend - OBV should accumulate
    var data: [10][2]f64 = undefined;
    for (0..10) |i| {
        data[i] = .{ @floatFromInt(100 + i * 5), 1000 };
    }

    const candles = try createTestCandlesWithVolume(allocator, &data);
    defer allocator.free(candles);

    const obv = try OBV.init(allocator);
    defer obv.deinit();

    const result = try obv.calculate(candles);
    defer allocator.free(result);

    // OBV should increase with each candle (except first)
    // Expected: 1000, 2000, 3000, 4000, ...
    for (1..result.len) |i| {
        try std.testing.expect(result[i].toFloat() > result[i - 1].toFloat());
    }

    // Final OBV should be 1000 + 9 * 1000 = 10000
    try std.testing.expectApproxEqAbs(@as(f64, 10000), result[9].toFloat(), 0.01);
}

test "OBV: downtrend distribution" {
    const allocator = std.testing.allocator;

    // Consistent downtrend - OBV should decrease
    var data: [10][2]f64 = undefined;
    for (0..10) |i| {
        data[i] = .{ @floatFromInt(200 - i * 5), 1000 };
    }

    const candles = try createTestCandlesWithVolume(allocator, &data);
    defer allocator.free(candles);

    const obv = try OBV.init(allocator);
    defer obv.deinit();

    const result = try obv.calculate(candles);
    defer allocator.free(result);

    // OBV should decrease with each candle (except first)
    for (1..result.len) |i| {
        try std.testing.expect(result[i].toFloat() < result[i - 1].toFloat());
    }

    // Final OBV should be 1000 - 9 * 1000 = -8000
    try std.testing.expectApproxEqAbs(@as(f64, -8000), result[9].toFloat(), 0.01);
}

test "OBV: IIndicator interface" {
    const allocator = std.testing.allocator;

    const data = [_][2]f64{
        .{ 100, 1000 },
        .{ 105, 1500 },
        .{ 103, 1200 },
    };

    const candles = try createTestCandlesWithVolume(allocator, &data);
    defer allocator.free(candles);

    const obv = try OBV.init(allocator);
    const indicator = obv.toIndicator();
    defer indicator.deinit();

    // Test getName
    try std.testing.expectEqualStrings("OBV", indicator.getName());

    // Test getRequiredCandles
    try std.testing.expectEqual(@as(u32, 1), indicator.getRequiredCandles());

    // Test calculate through interface
    const result = try indicator.calculate(candles);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 3), result.len);
}

test "OBV: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const data = [_][2]f64{
        .{ 100, 1000 },
        .{ 105, 1500 },
        .{ 103, 1200 },
        .{ 110, 2000 },
    };

    const candles = try createTestCandlesWithVolume(allocator, &data);
    defer allocator.free(candles);

    const obv = try OBV.init(allocator);
    defer obv.deinit();

    const result = try obv.calculate(candles);
    defer allocator.free(result);
}

test "OBV: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles
    var data = try allocator.alloc([2]f64, 1000);
    defer allocator.free(data);
    for (0..1000) |i| {
        const price: f64 = @floatFromInt(100 + (i % 100));
        data[i] = .{ price, 1000 };
    }

    const candles = try createTestCandlesWithVolume(allocator, data);
    defer allocator.free(candles);

    const obv = try OBV.init(allocator);
    defer obv.deinit();

    const start = std.time.nanoTimestamp();
    const result = try obv.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer allocator.free(result);

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    // Performance requirement: < 5ms
    try std.testing.expect(elapsed_ms < 5.0);
}
