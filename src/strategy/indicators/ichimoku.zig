//! Ichimoku Cloud (一目均衡表)
//!
//! Comprehensive trend and momentum indicator developed by Goichi Hosoda.
//!
//! Components:
//!   1. Tenkan-sen (Conversion Line): (9-period high + 9-period low) / 2
//!   2. Kijun-sen (Base Line): (26-period high + 26-period low) / 2
//!   3. Senkou Span A (Leading Span A): (Tenkan-sen + Kijun-sen) / 2, plotted 26 periods ahead
//!   4. Senkou Span B (Leading Span B): (52-period high + 52-period low) / 2, plotted 26 periods ahead
//!   5. Chikou Span (Lagging Span): Close price plotted 26 periods behind
//!
//! Cloud (Kumo):
//!   - Area between Senkou Span A and Senkou Span B
//!   - Green Cloud: Span A > Span B (bullish)
//!   - Red Cloud: Span A < Span B (bearish)
//!
//! Trading signals:
//!   - Price above cloud: Bullish
//!   - Price below cloud: Bearish
//!   - Tenkan crosses above Kijun: Bullish signal
//!   - Cloud twist (color change): Trend change
//!
//! Performance: O(n) time, O(n) space

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candle = @import("../../root.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// Ichimoku Cloud Result containing all five lines
pub const IchimokuResult = struct {
    allocator: std.mem.Allocator,
    tenkan_sen: []Decimal, // Conversion Line
    kijun_sen: []Decimal, // Base Line
    senkou_span_a: []Decimal, // Leading Span A
    senkou_span_b: []Decimal, // Leading Span B
    chikou_span: []Decimal, // Lagging Span

    pub fn deinit(self: *IchimokuResult) void {
        self.allocator.free(self.tenkan_sen);
        self.allocator.free(self.kijun_sen);
        self.allocator.free(self.senkou_span_a);
        self.allocator.free(self.senkou_span_b);
        self.allocator.free(self.chikou_span);
    }
};

/// Ichimoku Cloud Indicator
pub const Ichimoku = struct {
    allocator: std.mem.Allocator,
    tenkan_period: u32, // Default: 9
    kijun_period: u32, // Default: 26
    senkou_b_period: u32, // Default: 52
    displacement: u32, // Default: 26 (for Senkou and Chikou)

    /// Initialize Ichimoku with default parameters (9, 26, 52)
    /// @param allocator - Memory allocator
    /// @return Pointer to new Ichimoku instance
    pub fn init(allocator: std.mem.Allocator) !*Ichimoku {
        return initWithParams(allocator, 9, 26, 52, 26);
    }

    /// Initialize Ichimoku with custom parameters
    /// @param allocator - Memory allocator
    /// @param tenkan_period - Tenkan-sen period (default: 9)
    /// @param kijun_period - Kijun-sen period (default: 26)
    /// @param senkou_b_period - Senkou Span B period (default: 52)
    /// @param displacement - Forward/backward displacement (default: 26)
    /// @return Pointer to new Ichimoku instance
    pub fn initWithParams(
        allocator: std.mem.Allocator,
        tenkan_period: u32,
        kijun_period: u32,
        senkou_b_period: u32,
        displacement: u32,
    ) !*Ichimoku {
        if (tenkan_period == 0 or kijun_period == 0 or senkou_b_period == 0 or displacement == 0) {
            return error.InvalidPeriod;
        }

        const self = try allocator.create(Ichimoku);
        self.* = .{
            .allocator = allocator,
            .tenkan_period = tenkan_period,
            .kijun_period = kijun_period,
            .senkou_b_period = senkou_b_period,
            .displacement = displacement,
        };
        return self;
    }

    /// Convert to IIndicator interface (returns Tenkan-sen only)
    pub fn toIndicator(self: *Ichimoku) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Calculate highest high and lowest low for a period
    fn calculateDonchian(
        candles: []const Candle,
        start: usize,
        end: usize,
    ) struct { high: Decimal, low: Decimal } {
        var highest = candles[start].high;
        var lowest = candles[start].low;

        for (start + 1..end) |i| {
            if (candles[i].high.cmp(highest) == .gt) {
                highest = candles[i].high;
            }
            if (candles[i].low.cmp(lowest) == .lt) {
                lowest = candles[i].low;
            }
        }

        return .{ .high = highest, .low = lowest };
    }

    /// Calculate full Ichimoku Cloud
    /// @param candles - Input candle data
    /// @return IchimokuResult with all five lines
    pub fn calculateFull(self: *Ichimoku, candles: []const Candle) !IchimokuResult {
        const min_required = @max(self.senkou_b_period, self.kijun_period);
        if (candles.len < min_required) return error.InsufficientData;

        // Allocate arrays for all five lines
        var tenkan_sen = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(tenkan_sen);
        var kijun_sen = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(kijun_sen);
        var senkou_span_a = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(senkou_span_a);
        var senkou_span_b = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(senkou_span_b);
        var chikou_span = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(chikou_span);

        const two = Decimal.fromInt(2);

        // Calculate each line
        for (0..candles.len) |i| {
            // Tenkan-sen (Conversion Line)
            if (i >= self.tenkan_period - 1) {
                const start = i - (self.tenkan_period - 1);
                const donchian = calculateDonchian(candles, start, i + 1);
                tenkan_sen[i] = try donchian.high.add(donchian.low).div(two);
            } else {
                tenkan_sen[i] = Decimal.NaN;
            }

            // Kijun-sen (Base Line)
            if (i >= self.kijun_period - 1) {
                const start = i - (self.kijun_period - 1);
                const donchian = calculateDonchian(candles, start, i + 1);
                kijun_sen[i] = try donchian.high.add(donchian.low).div(two);
            } else {
                kijun_sen[i] = Decimal.NaN;
            }

            // Senkou Span B (calculated from current, but would be plotted forward)
            if (i >= self.senkou_b_period - 1) {
                const start = i - (self.senkou_b_period - 1);
                const donchian = calculateDonchian(candles, start, i + 1);
                senkou_span_b[i] = try donchian.high.add(donchian.low).div(two);
            } else {
                senkou_span_b[i] = Decimal.NaN;
            }

            // Chikou Span (current close, would be plotted backward)
            // In our representation, we show what the Chikou would look like at this position
            chikou_span[i] = candles[i].close;
        }

        // Senkou Span A (average of Tenkan and Kijun)
        for (0..candles.len) |i| {
            if (!tenkan_sen[i].isNaN() and !kijun_sen[i].isNaN()) {
                senkou_span_a[i] = try tenkan_sen[i].add(kijun_sen[i]).div(two);
            } else {
                senkou_span_a[i] = Decimal.NaN;
            }
        }

        return IchimokuResult{
            .allocator = self.allocator,
            .tenkan_sen = tenkan_sen,
            .kijun_sen = kijun_sen,
            .senkou_span_a = senkou_span_a,
            .senkou_span_b = senkou_span_b,
            .chikou_span = chikou_span,
        };
    }

    /// Calculate Tenkan-sen only (for IIndicator interface)
    /// @param candles - Input candle data
    /// @return Array of Tenkan-sen values
    pub fn calculate(self: *Ichimoku, candles: []const Candle) ![]Decimal {
        const result = try self.calculateFull(candles);
        // Free all but tenkan_sen
        self.allocator.free(result.kijun_sen);
        self.allocator.free(result.senkou_span_a);
        self.allocator.free(result.senkou_span_b);
        self.allocator.free(result.chikou_span);
        return result.tenkan_sen;
    }

    /// Clean up resources
    pub fn deinit(self: *Ichimoku) void {
        self.allocator.destroy(self);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *Ichimoku = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "Ichimoku";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        const self: *Ichimoku = @ptrCast(@alignCast(ptr));
        return @max(self.senkou_b_period, self.kijun_period);
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Ichimoku = @ptrCast(@alignCast(ptr));
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

test "Ichimoku: basic calculation" {
    const allocator = std.testing.allocator;

    // Create 60 candles (enough for all Ichimoku calculations)
    var data: [60][4]f64 = undefined;
    for (0..60) |i| {
        const base: f64 = @floatFromInt(100 + i);
        data[i] = .{ base, base + 5, base - 3, base + 2 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const ichimoku = try Ichimoku.init(allocator);
    defer ichimoku.deinit();

    var result = try ichimoku.calculateFull(candles);
    defer result.deinit();

    // Check array lengths
    try std.testing.expectEqual(@as(usize, 60), result.tenkan_sen.len);
    try std.testing.expectEqual(@as(usize, 60), result.kijun_sen.len);
    try std.testing.expectEqual(@as(usize, 60), result.senkou_span_a.len);
    try std.testing.expectEqual(@as(usize, 60), result.senkou_span_b.len);
    try std.testing.expectEqual(@as(usize, 60), result.chikou_span.len);

    // First few values should be NaN for Tenkan
    try std.testing.expect(result.tenkan_sen[0].isNaN());
    try std.testing.expect(!result.tenkan_sen[10].isNaN()); // Should have value after period-1

    // First more values should be NaN for Kijun
    try std.testing.expect(result.kijun_sen[20].isNaN());
    try std.testing.expect(!result.kijun_sen[30].isNaN()); // Should have value after period-1
}

test "Ichimoku: Tenkan-sen calculation" {
    const allocator = std.testing.allocator;

    // Create simple data where we can verify Tenkan-sen
    // Tenkan = (9-period high + 9-period low) / 2
    // Need at least 52 candles for Ichimoku with default params
    var data: [60][4]f64 = undefined;
    for (0..60) |i| {
        const base: f64 = @floatFromInt(i * 10 + 100);
        data[i] = .{ base, base + 5, base - 5, base };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    // Use smaller periods for this test
    const ichimoku = try Ichimoku.initWithParams(allocator, 9, 10, 15, 10);
    defer ichimoku.deinit();

    var result = try ichimoku.calculateFull(candles);
    defer result.deinit();

    // At index 8 (after 9 candles):
    // Highs: 105, 115, 125, 135, 145, 155, 165, 175, 185 -> max = 185
    // Lows: 95, 105, 115, 125, 135, 145, 155, 165, 175 -> min = 95
    // Tenkan = (185 + 95) / 2 = 140
    try std.testing.expectApproxEqAbs(@as(f64, 140), result.tenkan_sen[8].toFloat(), 0.1);
}

test "Ichimoku: Senkou Span A is average of Tenkan and Kijun" {
    const allocator = std.testing.allocator;

    // Create enough data
    var data: [60][4]f64 = undefined;
    for (0..60) |i| {
        const base: f64 = @floatFromInt(100 + i);
        data[i] = .{ base, base + 5, base - 3, base + 2 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const ichimoku = try Ichimoku.init(allocator);
    defer ichimoku.deinit();

    var result = try ichimoku.calculateFull(candles);
    defer result.deinit();

    // Verify Senkou Span A = (Tenkan + Kijun) / 2 where both are valid
    for (30..result.senkou_span_a.len) |i| {
        if (!result.tenkan_sen[i].isNaN() and !result.kijun_sen[i].isNaN()) {
            const expected = (result.tenkan_sen[i].toFloat() + result.kijun_sen[i].toFloat()) / 2.0;
            try std.testing.expectApproxEqAbs(expected, result.senkou_span_a[i].toFloat(), 0.01);
        }
    }
}

test "Ichimoku: IIndicator interface" {
    const allocator = std.testing.allocator;

    var data: [60][4]f64 = undefined;
    for (0..60) |i| {
        const base: f64 = @floatFromInt(100 + i);
        data[i] = .{ base, base + 5, base - 3, base + 2 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const ichimoku = try Ichimoku.init(allocator);
    const indicator = ichimoku.toIndicator();
    defer indicator.deinit();

    // Test getName
    try std.testing.expectEqualStrings("Ichimoku", indicator.getName());

    // Test getRequiredCandles (should be max of senkou_b and kijun = 52)
    try std.testing.expectEqual(@as(u32, 52), indicator.getRequiredCandles());

    // Test calculate through interface (returns Tenkan-sen)
    const result = try indicator.calculate(candles);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 60), result.len);
}

test "Ichimoku: error cases" {
    const allocator = std.testing.allocator;

    // Invalid period
    try std.testing.expectError(
        error.InvalidPeriod,
        Ichimoku.initWithParams(allocator, 0, 26, 52, 26),
    );

    // Insufficient data
    {
        var data: [30][4]f64 = undefined;
        for (0..30) |i| {
            const base: f64 = @floatFromInt(100 + i);
            data[i] = .{ base, base + 5, base - 3, base + 2 };
        }

        const candles = try createTestCandlesOHLC(allocator, &data);
        defer allocator.free(candles);

        const ichimoku = try Ichimoku.init(allocator);
        defer ichimoku.deinit();

        try std.testing.expectError(error.InsufficientData, ichimoku.calculateFull(candles));
    }
}

test "Ichimoku: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var data: [60][4]f64 = undefined;
    for (0..60) |i| {
        const base: f64 = @floatFromInt(100 + i);
        data[i] = .{ base, base + 5, base - 3, base + 2 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const ichimoku = try Ichimoku.init(allocator);
    defer ichimoku.deinit();

    var result = try ichimoku.calculateFull(candles);
    defer result.deinit();
}

test "Ichimoku: no memory leak with calculate" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var data: [60][4]f64 = undefined;
    for (0..60) |i| {
        const base: f64 = @floatFromInt(100 + i);
        data[i] = .{ base, base + 5, base - 3, base + 2 };
    }

    const candles = try createTestCandlesOHLC(allocator, &data);
    defer allocator.free(candles);

    const ichimoku = try Ichimoku.init(allocator);
    defer ichimoku.deinit();

    const result = try ichimoku.calculate(candles);
    defer allocator.free(result);
}

test "Ichimoku: performance on large dataset" {
    const allocator = std.testing.allocator;

    // Create 1000 candles
    var data = try allocator.alloc([4]f64, 1000);
    defer allocator.free(data);
    for (0..1000) |i| {
        const base: f64 = @floatFromInt(100 + (i % 100));
        data[i] = .{ base, base + 10, base - 5, base + 5 };
    }

    const candles = try createTestCandlesOHLC(allocator, data);
    defer allocator.free(candles);

    const ichimoku = try Ichimoku.init(allocator);
    defer ichimoku.deinit();

    const start = std.time.nanoTimestamp();
    var result = try ichimoku.calculateFull(candles);
    const end = std.time.nanoTimestamp();
    defer result.deinit();

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    // Performance requirement: < 15ms
    try std.testing.expect(elapsed_ms < 15.0);
}
