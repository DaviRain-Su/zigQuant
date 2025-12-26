//! Average Directional Index (ADX)
//!
//! Trend strength indicator developed by J. Welles Wilder Jr.
//!
//! Components:
//!   - +DM (Plus Directional Movement): Upward movement
//!   - -DM (Minus Directional Movement): Downward movement
//!   - +DI (Plus Directional Indicator): Normalized +DM
//!   - -DI (Minus Directional Indicator): Normalized -DM
//!   - ADX: Smoothed average of DX (Directional Index)
//!
//! Formulas:
//!   +DM = High - Previous High (if positive and > -DM)
//!   -DM = Previous Low - Low (if positive and > +DM)
//!   TR = True Range
//!   +DI = 100 × Smoothed(+DM) / Smoothed(TR)
//!   -DI = 100 × Smoothed(-DM) / Smoothed(TR)
//!   DX = 100 × |+DI - -DI| / (+DI + -DI)
//!   ADX = Smoothed(DX)
//!
//! Trading signals:
//!   - ADX > 25: Strong trend
//!   - ADX < 20: Weak/no trend
//!   - +DI > -DI: Bullish
//!   - -DI > +DI: Bearish
//!   - DI crossover: Potential trend change
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// ADX Result containing all three lines
pub const ADXResult = struct {
    allocator: std.mem.Allocator,
    adx: []Decimal,
    plus_di: []Decimal,
    minus_di: []Decimal,

    pub fn deinit(self: *ADXResult) void {
        self.allocator.free(self.adx);
        self.allocator.free(self.plus_di);
        self.allocator.free(self.minus_di);
    }
};

/// Average Directional Index (ADX)
pub const ADX = struct {
    allocator: std.mem.Allocator,
    period: u32,

    /// Initialize ADX indicator
    /// @param allocator - Memory allocator
    /// @param period - Smoothing period (typically 14)
    /// @return Pointer to new ADX instance
    pub fn init(allocator: std.mem.Allocator, period: u32) !*ADX {
        if (period == 0) return error.InvalidPeriod;

        const self = try allocator.create(ADX);
        self.* = .{
            .allocator = allocator,
            .period = period,
        };
        return self;
    }

    /// Convert to IIndicator interface (returns ADX line only)
    pub fn toIndicator(self: *ADX) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Calculate True Range for a single candle
    fn calculateTR(candle: Candle, prev_close: Decimal) Decimal {
        // TR = max(High - Low, |High - Prev Close|, |Low - Prev Close|)
        const hl = candle.high.sub(candle.low);
        const hc = candle.high.sub(prev_close).abs();
        const lc = candle.low.sub(prev_close).abs();

        var tr = hl;
        if (hc.cmp(tr) == .gt) tr = hc;
        if (lc.cmp(tr) == .gt) tr = lc;

        return tr;
    }

    /// Calculate full ADX with +DI and -DI
    /// @param candles - Input candle data
    /// @return ADXResult with adx, plus_di, minus_di arrays
    pub fn calculateFull(self: *ADX, candles: []const Candle) !ADXResult {
        if (candles.len < 2 * self.period) return error.InsufficientData;

        var adx = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(adx);
        var plus_di = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(plus_di);
        var minus_di = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(minus_di);

        // First value is NaN
        adx[0] = Decimal.NaN;
        plus_di[0] = Decimal.NaN;
        minus_di[0] = Decimal.NaN;

        // Calculate +DM, -DM, and TR for each candle
        var plus_dm = try self.allocator.alloc(Decimal, candles.len);
        defer self.allocator.free(plus_dm);
        var minus_dm = try self.allocator.alloc(Decimal, candles.len);
        defer self.allocator.free(minus_dm);
        var tr = try self.allocator.alloc(Decimal, candles.len);
        defer self.allocator.free(tr);

        plus_dm[0] = Decimal.ZERO;
        minus_dm[0] = Decimal.ZERO;
        tr[0] = candles[0].high.sub(candles[0].low);

        for (1..candles.len) |i| {
            const up_move = candles[i].high.sub(candles[i - 1].high);
            const down_move = candles[i - 1].low.sub(candles[i].low);

            // +DM
            if (up_move.cmp(down_move) == .gt and up_move.cmp(Decimal.ZERO) == .gt) {
                plus_dm[i] = up_move;
            } else {
                plus_dm[i] = Decimal.ZERO;
            }

            // -DM
            if (down_move.cmp(up_move) == .gt and down_move.cmp(Decimal.ZERO) == .gt) {
                minus_dm[i] = down_move;
            } else {
                minus_dm[i] = Decimal.ZERO;
            }

            // True Range
            tr[i] = calculateTR(candles[i], candles[i - 1].close);
        }

        // Initial smoothed values (first period)
        // Before we can calculate DI values, need period+1 candles
        for (1..self.period) |i| {
            adx[i] = Decimal.NaN;
            plus_di[i] = Decimal.NaN;
            minus_di[i] = Decimal.NaN;
        }

        // Calculate initial sums for smoothing
        var smoothed_plus_dm = Decimal.ZERO;
        var smoothed_minus_dm = Decimal.ZERO;
        var smoothed_tr = Decimal.ZERO;

        for (1..self.period + 1) |i| {
            smoothed_plus_dm = smoothed_plus_dm.add(plus_dm[i]);
            smoothed_minus_dm = smoothed_minus_dm.add(minus_dm[i]);
            smoothed_tr = smoothed_tr.add(tr[i]);
        }

        const period_decimal = Decimal.fromInt(@as(i64, @intCast(self.period)));
        const hundred = Decimal.fromInt(100);

        // Calculate first +DI and -DI
        if (!smoothed_tr.isZero()) {
            const plus_di_ratio = try smoothed_plus_dm.div(smoothed_tr);
            plus_di[self.period] = plus_di_ratio.mul(hundred);
            const minus_di_ratio = try smoothed_minus_dm.div(smoothed_tr);
            minus_di[self.period] = minus_di_ratio.mul(hundred);
        } else {
            plus_di[self.period] = Decimal.ZERO;
            minus_di[self.period] = Decimal.ZERO;
        }
        adx[self.period] = Decimal.NaN; // Not enough DX values yet

        // Storage for DX values for ADX calculation
        var dx_values = try self.allocator.alloc(Decimal, candles.len);
        defer self.allocator.free(dx_values);
        for (0..candles.len) |i| {
            dx_values[i] = Decimal.NaN;
        }

        // Calculate DX at first position
        const di_diff = plus_di[self.period].sub(minus_di[self.period]).abs();
        const di_sum = plus_di[self.period].add(minus_di[self.period]);
        if (!di_sum.isZero()) {
            const dx_ratio = try di_diff.div(di_sum);
            dx_values[self.period] = dx_ratio.mul(hundred);
        } else {
            dx_values[self.period] = Decimal.ZERO;
        }

        // Use Wilder smoothing for subsequent values
        // Smoothed = Previous Smoothed - (Previous Smoothed / period) + Current Value
        for (self.period + 1..candles.len) |i| {
            // Smooth +DM, -DM, TR using Wilder's method
            smoothed_plus_dm = smoothed_plus_dm.sub(try smoothed_plus_dm.div(period_decimal)).add(plus_dm[i]);
            smoothed_minus_dm = smoothed_minus_dm.sub(try smoothed_minus_dm.div(period_decimal)).add(minus_dm[i]);
            smoothed_tr = smoothed_tr.sub(try smoothed_tr.div(period_decimal)).add(tr[i]);

            // Calculate +DI and -DI
            if (!smoothed_tr.isZero()) {
                plus_di[i] = try smoothed_plus_dm.div(smoothed_tr);
                plus_di[i] = plus_di[i].mul(hundred);
                minus_di[i] = try smoothed_minus_dm.div(smoothed_tr);
                minus_di[i] = minus_di[i].mul(hundred);
            } else {
                plus_di[i] = Decimal.ZERO;
                minus_di[i] = Decimal.ZERO;
            }

            // Calculate DX
            const diff = plus_di[i].sub(minus_di[i]).abs();
            const sum = plus_di[i].add(minus_di[i]);
            if (!sum.isZero()) {
                dx_values[i] = try diff.div(sum);
                dx_values[i] = dx_values[i].mul(hundred);
            } else {
                dx_values[i] = Decimal.ZERO;
            }
        }

        // Calculate ADX (smoothed DX)
        // Need period more values after first DI calculation
        const adx_start = 2 * self.period - 1;
        if (adx_start >= candles.len) {
            // Not enough data for ADX
            for (self.period + 1..candles.len) |i| {
                adx[i] = Decimal.NaN;
            }
        } else {
            // First ADX is simple average of first period DX values
            var dx_sum = Decimal.ZERO;
            for (self.period..adx_start + 1) |i| {
                if (!dx_values[i].isNaN()) {
                    dx_sum = dx_sum.add(dx_values[i]);
                }
            }
            adx[adx_start] = try dx_sum.div(period_decimal);

            // Fill NaN for values before ADX start
            for (self.period + 1..adx_start) |i| {
                adx[i] = Decimal.NaN;
            }

            // Smooth ADX using Wilder's method
            for (adx_start + 1..candles.len) |i| {
                const prev_adx = adx[i - 1];
                const smoothed_term = try prev_adx.mul(period_decimal.sub(Decimal.ONE)).div(period_decimal);
                const current_term = try dx_values[i].div(period_decimal);
                adx[i] = smoothed_term.add(current_term);
            }
        }

        return ADXResult{
            .allocator = self.allocator,
            .adx = adx,
            .plus_di = plus_di,
            .minus_di = minus_di,
        };
    }

    /// Calculate ADX values only (for IIndicator interface)
    /// @param candles - Input candle data
    /// @return Array of ADX values (same length as candles)
    pub fn calculate(self: *ADX, candles: []const Candle) ![]Decimal {
        const result = try self.calculateFull(candles);
        // Free the DI arrays since we only need ADX
        self.allocator.free(result.plus_di);
        self.allocator.free(result.minus_di);
        return result.adx;
    }

    /// Clean up resources
    pub fn deinit(self: *ADX) void {
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *ADX = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "ADX";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        const self: *ADX = @ptrCast(@alignCast(ptr));
        return 2 * self.period; // Need 2 × period for ADX calculation
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *ADX = @ptrCast(@alignCast(ptr));
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

test "ADX: basic calculation" {
    const allocator = std.testing.allocator;

    // Create 30 candles for period 14
    var data: [30][4]f64 = undefined;
    for (0..30) |i| {
        const base: f64 = @floatFromInt(100 + i * 2);
        data[i] = .{ base, base + 5, base - 3, base + 2 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const adx = try ADX.init(allocator, 14);
    defer adx.deinit();

    var result = try adx.calculateFull(candles);
    defer result.deinit();

    // Check array lengths
    try std.testing.expectEqual(@as(usize, 30), result.adx.len);
    try std.testing.expectEqual(@as(usize, 30), result.plus_di.len);
    try std.testing.expectEqual(@as(usize, 30), result.minus_di.len);

    // First values should be NaN
    try std.testing.expect(result.adx[0].isNaN());
    try std.testing.expect(result.plus_di[0].isNaN());
    try std.testing.expect(result.minus_di[0].isNaN());
}

test "ADX: strong uptrend" {
    const allocator = std.testing.allocator;

    // Create strong uptrend data
    var data: [35][4]f64 = undefined;
    for (0..35) |i| {
        const base: f64 = @floatFromInt(100 + i * 5); // Strong uptrend
        data[i] = .{ base, base + 3, base - 1, base + 2 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const adx = try ADX.init(allocator, 14);
    defer adx.deinit();

    var result = try adx.calculateFull(candles);
    defer result.deinit();

    // In strong uptrend, +DI should be greater than -DI
    const last_idx = result.plus_di.len - 1;
    if (!result.plus_di[last_idx].isNaN() and !result.minus_di[last_idx].isNaN()) {
        const plus = result.plus_di[last_idx].toFloat();
        const minus = result.minus_di[last_idx].toFloat();
        try std.testing.expect(plus > minus);
    }
}

test "ADX: ADX range" {
    const allocator = std.testing.allocator;

    var data: [35][4]f64 = undefined;
    for (0..35) |i| {
        const base: f64 = @floatFromInt(100 + i * 2);
        const variation: f64 = @floatFromInt(i % 5);
        data[i] = .{ base, base + 5 + variation, base - 3 - variation, base + 1 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const adx = try ADX.init(allocator, 14);
    defer adx.deinit();

    var result = try adx.calculateFull(candles);
    defer result.deinit();

    // ADX should be in range [0, 100]
    for (result.adx) |val| {
        if (!val.isNaN()) {
            const v = val.toFloat();
            try std.testing.expect(v >= 0);
            try std.testing.expect(v <= 100);
        }
    }
}

test "ADX: IIndicator interface" {
    const allocator = std.testing.allocator;

    var data: [35][4]f64 = undefined;
    for (0..35) |i| {
        const base: f64 = @floatFromInt(100 + i * 2);
        data[i] = .{ base, base + 5, base - 3, base + 2 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const adx = try ADX.init(allocator, 14);
    const indicator = adx.toIndicator();
    defer indicator.deinit();

    // Test getName
    try std.testing.expectEqualStrings("ADX", indicator.getName());

    // Test getRequiredCandles
    try std.testing.expectEqual(@as(u32, 28), indicator.getRequiredCandles());

    // Test calculate through interface
    const result = try indicator.calculate(candles);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 35), result.len);
}

test "ADX: error cases" {
    const allocator = std.testing.allocator;

    // Invalid period (0)
    try std.testing.expectError(error.InvalidPeriod, ADX.init(allocator, 0));

    // Insufficient data
    {
        var data: [20][4]f64 = undefined;
        for (0..20) |i| {
            const base: f64 = @floatFromInt(100 + i);
            data[i] = .{ base, base + 3, base - 2, base + 1 };
        }

        const candles = try createTestCandlesOHLC(allocator, &data);
        defer allocator.free(candles);

        const adx = try ADX.init(allocator, 14);
        defer adx.deinit();

        try std.testing.expectError(error.InsufficientData, adx.calculate(candles));
    }
}

test "ADX: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var data: [35][4]f64 = undefined;
    for (0..35) |i| {
        const base: f64 = @floatFromInt(100 + i * 2);
        data[i] = .{ base, base + 5, base - 3, base + 2 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const adx = try ADX.init(allocator, 14);
    defer adx.deinit();

    const result = try adx.calculate(candles);
    defer allocator.free(result);
}

test "ADX: no memory leak with full calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var data: [35][4]f64 = undefined;
    for (0..35) |i| {
        const base: f64 = @floatFromInt(100 + i * 2);
        data[i] = .{ base, base + 5, base - 3, base + 2 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const adx = try ADX.init(allocator, 14);
    defer adx.deinit();

    var result = try adx.calculateFull(candles);
    defer result.deinit();
}
