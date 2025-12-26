//! Volume Weighted Average Price (VWAP)
//!
//! Benchmark indicator that gives the average price weighted by volume.
//!
//! Formula:
//!   VWAP = Cumulative(TP × Volume) / Cumulative(Volume)
//!   where TP (Typical Price) = (High + Low + Close) / 3
//!
//! Trading signals:
//!   - Price > VWAP: Bullish (buyers in control)
//!   - Price < VWAP: Bearish (sellers in control)
//!   - Price crossing VWAP: Potential trend change
//!
//! Features:
//!   - Commonly used for intraday trading
//!   - Shows fair value based on volume
//!   - Can be reset daily or continuously calculated
//!   - Used by institutional traders
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// Volume Weighted Average Price (VWAP)
pub const VWAP = struct {
    allocator: std.mem.Allocator,
    reset_daily: bool, // Whether to reset VWAP at each new day

    /// Initialize VWAP indicator
    /// @param allocator - Memory allocator
    /// @return Pointer to new VWAP instance (continuous calculation)
    pub fn init(allocator: std.mem.Allocator) !*VWAP {
        const self = try allocator.create(VWAP);
        self.* = .{
            .allocator = allocator,
            .reset_daily = false,
        };
        return self;
    }

    /// Initialize VWAP with daily reset option
    /// @param allocator - Memory allocator
    /// @param reset_daily - Whether to reset VWAP at each new trading day
    /// @return Pointer to new VWAP instance
    pub fn initWithReset(allocator: std.mem.Allocator, reset_daily: bool) !*VWAP {
        const self = try allocator.create(VWAP);
        self.* = .{
            .allocator = allocator,
            .reset_daily = reset_daily,
        };
        return self;
    }

    /// Convert to IIndicator interface
    pub fn toIndicator(self: *VWAP) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Check if a new trading day started
    fn isNewDay(prev_timestamp: i64, curr_timestamp: i64) bool {
        // Assuming millisecond timestamps
        const ms_per_day: i64 = 24 * 60 * 60 * 1000;
        const prev_day = @divFloor(prev_timestamp, ms_per_day);
        const curr_day = @divFloor(curr_timestamp, ms_per_day);
        return curr_day > prev_day;
    }

    /// Calculate VWAP values
    /// @param candles - Input candle data
    /// @return Array of VWAP values (same length as candles)
    pub fn calculate(self: *VWAP, candles: []const Candle) ![]Decimal {
        if (candles.len == 0) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        const three = Decimal.fromInt(3);
        var cumulative_tp_vol = Decimal.ZERO;
        var cumulative_vol = Decimal.ZERO;

        for (candles, 0..) |candle, i| {
            // Check for daily reset
            if (self.reset_daily and i > 0) {
                if (isNewDay(candles[i - 1].timestamp.millis, candle.timestamp.millis)) {
                    cumulative_tp_vol = Decimal.ZERO;
                    cumulative_vol = Decimal.ZERO;
                }
            }

            // Calculate Typical Price
            const tp = try candle.high.add(candle.low).add(candle.close).div(three);

            // Accumulate TP × Volume and Volume
            const tp_vol = tp.mul(candle.volume);
            cumulative_tp_vol = cumulative_tp_vol.add(tp_vol);
            cumulative_vol = cumulative_vol.add(candle.volume);

            // Calculate VWAP
            if (cumulative_vol.isZero()) {
                result[i] = tp; // Use TP if no volume
            } else {
                result[i] = try cumulative_tp_vol.div(cumulative_vol);
            }
        }

        return result;
    }

    /// Clean up resources
    pub fn deinit(self: *VWAP) void {
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *VWAP = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "VWAP";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        _ = ptr;
        return 1; // VWAP can start from first candle
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *VWAP = @ptrCast(@alignCast(ptr));
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

/// Helper function to create test candles with OHLCV data
fn createTestCandlesOHLCV(
    allocator: std.mem.Allocator,
    data: []const [5]f64, // [open, high, low, close, volume]
) ![]Candle {
    var candles = try allocator.alloc(Candle, data.len);
    for (data, 0..) |ohlcv, i| {
        candles[i] = Candle{
            .timestamp = .{ .millis = @intCast(i * 3600000) }, // 1 hour apart
            .open = Decimal.fromFloat(ohlcv[0]),
            .high = Decimal.fromFloat(ohlcv[1]),
            .low = Decimal.fromFloat(ohlcv[2]),
            .close = Decimal.fromFloat(ohlcv[3]),
            .volume = Decimal.fromFloat(ohlcv[4]),
        };
    }
    return candles;
}

test "VWAP: basic calculation" {
    const allocator = std.testing.allocator;

    // Test data: [open, high, low, close, volume]
    const data = [_][5]f64{
        .{ 100, 105, 95, 100, 1000 }, // TP = (105+95+100)/3 = 100
        .{ 100, 110, 95, 105, 1500 }, // TP = (110+95+105)/3 = 103.33
        .{ 105, 115, 100, 110, 2000 }, // TP = (115+100+110)/3 = 108.33
    };

    const candles = try createTestCandlesOHLCV(allocator, &data);
    defer allocator.free(candles);

    const vwap = try VWAP.init(allocator);
    defer vwap.deinit();

    const result = try vwap.calculate(candles);
    defer allocator.free(result);

    // First VWAP = TP1 = 100
    try std.testing.expectApproxEqAbs(@as(f64, 100), result[0].toFloat(), 0.01);

    // Second VWAP = (100*1000 + 103.33*1500) / (1000+1500) = (100000 + 155000) / 2500 = 102
    try std.testing.expectApproxEqAbs(@as(f64, 102), result[1].toFloat(), 0.5);

    // Third VWAP includes all three candles
    // = (100*1000 + 103.33*1500 + 108.33*2000) / (1000+1500+2000)
    // Should be around 104.44
    try std.testing.expectApproxEqAbs(@as(f64, 104.44), result[2].toFloat(), 0.5);
}

test "VWAP: volume weighting effect" {
    const allocator = std.testing.allocator;

    // High volume at high price should pull VWAP up
    const data = [_][5]f64{
        .{ 100, 100, 100, 100, 100 }, // TP = 100, low volume
        .{ 200, 200, 200, 200, 10000 }, // TP = 200, high volume
    };

    const candles = try createTestCandlesOHLCV(allocator, &data);
    defer allocator.free(candles);

    const vwap = try VWAP.init(allocator);
    defer vwap.deinit();

    const result = try vwap.calculate(candles);
    defer allocator.free(result);

    // VWAP should be much closer to 200 due to high volume
    // = (100*100 + 200*10000) / (100+10000) = 2010000 / 10100 ≈ 199
    try std.testing.expect(result[1].toFloat() > 195.0);
}

test "VWAP: equal volume" {
    const allocator = std.testing.allocator;

    // With equal volume, VWAP is just average of TPs
    const data = [_][5]f64{
        .{ 100, 100, 100, 100, 1000 }, // TP = 100
        .{ 200, 200, 200, 200, 1000 }, // TP = 200
        .{ 150, 150, 150, 150, 1000 }, // TP = 150
    };

    const candles = try createTestCandlesOHLCV(allocator, &data);
    defer allocator.free(candles);

    const vwap = try VWAP.init(allocator);
    defer vwap.deinit();

    const result = try vwap.calculate(candles);
    defer allocator.free(result);

    // Final VWAP = (100 + 200 + 150) / 3 = 150
    try std.testing.expectApproxEqAbs(@as(f64, 150), result[2].toFloat(), 0.01);
}

test "VWAP: IIndicator interface" {
    const allocator = std.testing.allocator;

    const data = [_][5]f64{
        .{ 100, 105, 95, 100, 1000 },
        .{ 100, 110, 95, 105, 1500 },
        .{ 105, 115, 100, 110, 2000 },
    };

    const candles = try createTestCandlesOHLCV(allocator, &data);
    defer allocator.free(candles);

    const vwap = try VWAP.init(allocator);
    const indicator = vwap.toIndicator();
    defer indicator.deinit();

    // Test getName
    try std.testing.expectEqualStrings("VWAP", indicator.getName());

    // Test getRequiredCandles
    try std.testing.expectEqual(@as(u32, 1), indicator.getRequiredCandles());

    // Test calculate through interface
    const result = try indicator.calculate(candles);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 3), result.len);
}

test "VWAP: daily reset" {
    const allocator = std.testing.allocator;

    // Create candles spanning two days
    var candles = try allocator.alloc(Candle, 4);
    defer allocator.free(candles);

    const ms_per_day: i64 = 24 * 60 * 60 * 1000;

    // Day 1 candles
    candles[0] = Candle{
        .timestamp = .{ .millis = 0 },
        .open = Decimal.fromInt(100),
        .high = Decimal.fromInt(100),
        .low = Decimal.fromInt(100),
        .close = Decimal.fromInt(100),
        .volume = Decimal.fromInt(1000),
    };
    candles[1] = Candle{
        .timestamp = .{ .millis = 3600000 }, // 1 hour later
        .open = Decimal.fromInt(110),
        .high = Decimal.fromInt(110),
        .low = Decimal.fromInt(110),
        .close = Decimal.fromInt(110),
        .volume = Decimal.fromInt(1000),
    };

    // Day 2 candles
    candles[2] = Candle{
        .timestamp = .{ .millis = ms_per_day }, // Next day
        .open = Decimal.fromInt(200),
        .high = Decimal.fromInt(200),
        .low = Decimal.fromInt(200),
        .close = Decimal.fromInt(200),
        .volume = Decimal.fromInt(1000),
    };
    candles[3] = Candle{
        .timestamp = .{ .millis = ms_per_day + 3600000 },
        .open = Decimal.fromInt(220),
        .high = Decimal.fromInt(220),
        .low = Decimal.fromInt(220),
        .close = Decimal.fromInt(220),
        .volume = Decimal.fromInt(1000),
    };

    // Test with daily reset
    const vwap = try VWAP.initWithReset(allocator, true);
    defer vwap.deinit();

    const result = try vwap.calculate(candles);
    defer allocator.free(result);

    // Day 1: VWAP at candle[1] = (100 + 110) / 2 = 105
    try std.testing.expectApproxEqAbs(@as(f64, 105), result[1].toFloat(), 0.01);

    // Day 2: VWAP reset, at candle[2] = 200
    try std.testing.expectApproxEqAbs(@as(f64, 200), result[2].toFloat(), 0.01);

    // Day 2: VWAP at candle[3] = (200 + 220) / 2 = 210
    try std.testing.expectApproxEqAbs(@as(f64, 210), result[3].toFloat(), 0.01);
}

test "VWAP: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    const data = [_][5]f64{
        .{ 100, 105, 95, 100, 1000 },
        .{ 100, 110, 95, 105, 1500 },
        .{ 105, 115, 100, 110, 2000 },
    };

    const candles = try createTestCandlesOHLCV(allocator, &data);
    defer allocator.free(candles);

    const vwap = try VWAP.init(allocator);
    defer vwap.deinit();

    const result = try vwap.calculate(candles);
    defer allocator.free(result);
}

test "VWAP: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles
    var data = try allocator.alloc([5]f64, 1000);
    defer allocator.free(data);
    for (0..1000) |i| {
        const base: f64 = @floatFromInt(100 + i);
        data[i] = .{ base, base + 5, base - 5, base, 1000 };
    }

    const candles = try createTestCandlesOHLCV(allocator, data);
    defer allocator.free(candles);

    const vwap = try VWAP.init(allocator);
    defer vwap.deinit();

    const start = std.time.nanoTimestamp();
    const result = try vwap.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer allocator.free(result);

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    // Performance requirement: < 5ms
    try std.testing.expect(elapsed_ms < 5.0);
}
