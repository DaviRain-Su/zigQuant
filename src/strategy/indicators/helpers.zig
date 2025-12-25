//! Indicator Helper Functions
//!
//! Convenient wrapper functions for calculating indicators through IndicatorManager.
//! These functions automatically create indicator instances, calculate values,
//! and leverage caching for optimal performance.
//!
//! Usage:
//! ```zig
//! var manager = IndicatorManager.init(allocator);
//! defer manager.deinit();
//!
//! // Simple API - no need to create indicator instances
//! const sma = try helpers.getSMA(&manager, &candles, 20);
//! const ema = try helpers.getEMA(&manager, &candles, 12);
//! const rsi = try helpers.getRSI(&manager, &candles, 14);
//! ```

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candles = @import("../../root.zig").Candles;
const IndicatorManager = @import("manager.zig").IndicatorManager;
const SMA = @import("sma.zig").SMA;
const EMA = @import("ema.zig").EMA;
const RSI = @import("rsi.zig").RSI;
const MACD = @import("macd.zig").MACD;
const MACDResult = @import("macd.zig").MACDResult;
const BollingerBands = @import("bollinger.zig").BollingerBands;
const BollingerResult = @import("bollinger.zig").BollingerResult;

// ============================================================================
// Simple Moving Average (SMA)
// ============================================================================

/// Get or calculate SMA
/// @param manager - Indicator manager (handles caching)
/// @param candles - Candle data
/// @param period - SMA period
/// @return SMA values (cached if already calculated)
pub fn getSMA(
    manager: *IndicatorManager,
    candles: *Candles,
    period: u32,
) ![]Decimal {
    const sma = try SMA.init(manager.allocator, period);
    defer sma.deinit();

    const name = try std.fmt.allocPrint(manager.allocator, "sma_{d}", .{period});
    defer manager.allocator.free(name);

    return try manager.getOrCalculate(name, sma.toIndicator(), candles);
}

// ============================================================================
// Exponential Moving Average (EMA)
// ============================================================================

/// Get or calculate EMA
/// @param manager - Indicator manager (handles caching)
/// @param candles - Candle data
/// @param period - EMA period
/// @return EMA values (cached if already calculated)
pub fn getEMA(
    manager: *IndicatorManager,
    candles: *Candles,
    period: u32,
) ![]Decimal {
    const ema = try EMA.init(manager.allocator, period);
    defer ema.deinit();

    const name = try std.fmt.allocPrint(manager.allocator, "ema_{d}", .{period});
    defer manager.allocator.free(name);

    return try manager.getOrCalculate(name, ema.toIndicator(), candles);
}

// ============================================================================
// Relative Strength Index (RSI)
// ============================================================================

/// Get or calculate RSI
/// @param manager - Indicator manager (handles caching)
/// @param candles - Candle data
/// @param period - RSI period (typically 14)
/// @return RSI values [0-100] (cached if already calculated)
pub fn getRSI(
    manager: *IndicatorManager,
    candles: *Candles,
    period: u32,
) ![]Decimal {
    const rsi = try RSI.init(manager.allocator, period);
    defer rsi.deinit();

    const name = try std.fmt.allocPrint(manager.allocator, "rsi_{d}", .{period});
    defer manager.allocator.free(name);

    return try manager.getOrCalculate(name, rsi.toIndicator(), candles);
}

// ============================================================================
// MACD
// ============================================================================

/// Get or calculate MACD
/// Note: MACD returns a complex result with three lines, so caching is handled differently
/// @param manager - Indicator manager
/// @param candles - Candle data
/// @param fast - Fast EMA period (default: 12)
/// @param slow - Slow EMA period (default: 26)
/// @param signal - Signal EMA period (default: 9)
/// @return MACDResult with macd_line, signal_line, histogram
pub fn getMACD(
    manager: *IndicatorManager,
    candles: *Candles,
    fast: u32,
    slow: u32,
    signal: u32,
) !MACDResult {
    const macd = try MACD.init(manager.allocator, fast, slow, signal);
    defer macd.deinit();

    // Note: For MACD, we calculate directly instead of using cache
    // because MACDResult is a complex type with multiple arrays
    return try macd.calculate(candles.candles);
}

/// Get MACD with default parameters (12, 26, 9)
pub fn getMACDDefault(
    manager: *IndicatorManager,
    candles: *Candles,
) !MACDResult {
    return try getMACD(manager, candles, 12, 26, 9);
}

// ============================================================================
// Bollinger Bands
// ============================================================================

/// Get or calculate Bollinger Bands
/// Note: Like MACD, Bollinger Bands returns a complex result
/// @param manager - Indicator manager
/// @param candles - Candle data
/// @param period - SMA period (default: 20)
/// @param std_dev - Standard deviation multiplier (default: 2.0)
/// @return BollingerResult with upper, middle, lower bands
pub fn getBollingerBands(
    manager: *IndicatorManager,
    candles: *Candles,
    period: u32,
    std_dev: f64,
) !BollingerResult {
    const bb = try BollingerBands.init(manager.allocator, period, std_dev);
    defer bb.deinit();

    // Calculate directly (complex result type)
    return try bb.calculate(candles.candles);
}

/// Get Bollinger Bands with default parameters (20, 2.0)
pub fn getBollingerBandsDefault(
    manager: *IndicatorManager,
    candles: *Candles,
) !BollingerResult {
    return try getBollingerBands(manager, candles, 20, 2.0);
}

// ============================================================================
// Tests
// ============================================================================

test "helpers: getSMA with caching" {
    const testing = std.testing;

    var manager = IndicatorManager.init(testing.allocator);
    defer manager.deinit();

    const candles_data = try testing.allocator.alloc(@import("../../root.zig").Candle, 100);
    // Note: candles_data will be freed by candles.deinit()

    for (candles_data, 0..) |*c, i| {
        const price = Decimal.fromInt(@as(i64, @intCast(100 + i)));
        c.* = .{
            .timestamp = .{ .millis = @intCast(i * 3600000) },
            .open = price,
            .high = price,
            .low = price,
            .close = price,
            .volume = Decimal.fromInt(100),
        };
    }

    var candles = Candles.initWithCandles(
        testing.allocator,
        @import("../../root.zig").TradingPair{ .base = "BTC", .quote = "USDT" },
        .m15,
        candles_data,
    );
    defer candles.deinit();

    // First call - cache miss
    const sma1 = try getSMA(&manager, &candles, 20);
    try testing.expectEqual(@as(u64, 0), manager.stats.cache_hits);

    // Second call - cache hit
    const sma2 = try getSMA(&manager, &candles, 20);
    try testing.expectEqual(@as(u64, 1), manager.stats.cache_hits);

    // Should be same pointer
    try testing.expectEqual(sma1.ptr, sma2.ptr);
}

test "helpers: multiple indicators" {
    const testing = std.testing;

    var manager = IndicatorManager.init(testing.allocator);
    defer manager.deinit();

    const candles_data = try testing.allocator.alloc(@import("../../root.zig").Candle, 100);
    // Note: candles_data will be freed by candles.deinit()

    for (candles_data, 0..) |*c, i| {
        const price = Decimal.fromInt(@as(i64, @intCast(100 + i)));
        c.* = .{
            .timestamp = .{ .millis = @intCast(i * 3600000) },
            .open = price,
            .high = price,
            .low = price,
            .close = price,
            .volume = Decimal.fromInt(100),
        };
    }

    var candles = Candles.initWithCandles(
        testing.allocator,
        @import("../../root.zig").TradingPair{ .base = "BTC", .quote = "USDT" },
        .m15,
        candles_data,
    );
    defer candles.deinit();

    // Calculate multiple indicators
    const sma = try getSMA(&manager, &candles, 20);
    const ema = try getEMA(&manager, &candles, 12);
    const rsi = try getRSI(&manager, &candles, 14);

    // Verify all calculated
    try testing.expectEqual(@as(usize, 100), sma.len);
    try testing.expectEqual(@as(usize, 100), ema.len);
    try testing.expectEqual(@as(usize, 100), rsi.len);

    // Verify cache has 3 entries
    try testing.expectEqual(@as(usize, 3), manager.getCacheSize());
}

test "helpers: MACD default" {
    const testing = std.testing;

    var manager = IndicatorManager.init(testing.allocator);
    defer manager.deinit();

    const candles_data = try testing.allocator.alloc(@import("../../root.zig").Candle, 100);
    // Note: candles_data will be freed by candles.deinit()

    for (candles_data, 0..) |*c, i| {
        const price = Decimal.fromInt(@as(i64, @intCast(100 + i)));
        c.* = .{
            .timestamp = .{ .millis = @intCast(i * 3600000) },
            .open = price,
            .high = price,
            .low = price,
            .close = price,
            .volume = Decimal.fromInt(100),
        };
    }

    var candles = Candles.initWithCandles(
        testing.allocator,
        @import("../../root.zig").TradingPair{ .base = "BTC", .quote = "USDT" },
        .m15,
        candles_data,
    );
    defer candles.deinit();

    const macd = try getMACDDefault(&manager, &candles);
    defer macd.deinit();

    try testing.expectEqual(@as(usize, 100), macd.macd_line.len);
    try testing.expectEqual(@as(usize, 100), macd.signal_line.len);
    try testing.expectEqual(@as(usize, 100), macd.histogram.len);
}
