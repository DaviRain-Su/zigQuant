//! Candles - OHLCV candlestick data container
//!
//! This module provides data structures for storing and managing candlestick (OHLCV) data
//! along with technical indicators. It's designed to work efficiently with trading strategies
//! and the backtest engine.
//!
//! Design principles:
//! - Efficient memory layout for sequential access
//! - Support for technical indicator storage
//! - Type-safe indicator access
//! - Minimal allocations during iteration

const std = @import("std");
const Decimal = @import("../root.zig").Decimal;
const Timestamp = @import("../root.zig").Timestamp;
const TradingPair = @import("../root.zig").TradingPair;
const Timeframe = @import("../root.zig").Timeframe;

// ============================================================================
// Single Candle
// ============================================================================

/// Single OHLCV candlestick
pub const Candle = struct {
    timestamp: Timestamp,
    open: Decimal,
    high: Decimal,
    low: Decimal,
    close: Decimal,
    volume: Decimal,

    /// Validate candle data consistency
    /// - High must be >= Low
    /// - High must be >= Open and Close
    /// - Low must be <= Open and Close
    /// - Volume must be non-negative
    pub fn validate(self: Candle) !void {
        // High >= Low
        if (self.high.cmp(self.low) == .lt) {
            return error.HighLessThanLow;
        }

        // High >= Open
        if (self.high.cmp(self.open) == .lt) {
            return error.HighLessThanOpen;
        }

        // High >= Close
        if (self.high.cmp(self.close) == .lt) {
            return error.HighLessThanClose;
        }

        // Low <= Open
        if (self.low.cmp(self.open) == .gt) {
            return error.LowGreaterThanOpen;
        }

        // Low <= Close
        if (self.low.cmp(self.close) == .gt) {
            return error.LowGreaterThanClose;
        }

        // Volume >= 0
        if (self.volume.isNegative()) {
            return error.NegativeVolume;
        }
    }

    /// Check if candle is bullish (close > open)
    pub fn isBullish(self: Candle) bool {
        return self.close.cmp(self.open) == .gt;
    }

    /// Check if candle is bearish (close < open)
    pub fn isBearish(self: Candle) bool {
        return self.close.cmp(self.open) == .lt;
    }

    /// Get candle body size (abs(close - open))
    pub fn bodySize(self: Candle) Decimal {
        if (self.close.cmp(self.open) == .gt) {
            return self.close.sub(self.open);
        } else {
            return self.open.sub(self.close);
        }
    }

    /// Get candle range (high - low)
    pub fn range(self: Candle) Decimal {
        return self.high.sub(self.low);
    }

    /// Get typical price ((high + low + close) / 3)
    pub fn typicalPrice(self: Candle) !Decimal {
        const sum = self.high.add(self.low).add(self.close);
        return try sum.div(Decimal.fromInt(3));
    }
};

// ============================================================================
// Indicator Data
// ============================================================================

/// Indicator value for a single timestamp
/// Used to store technical indicator values (e.g., SMA, RSI)
pub const IndicatorValue = Decimal;

/// Indicator series (array of values aligned with candles)
pub const IndicatorSeries = struct {
    name: []const u8,
    values: []IndicatorValue,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, size: usize) !IndicatorSeries {
        const name_copy = try allocator.dupe(u8, name);
        errdefer allocator.free(name_copy);

        const values = try allocator.alloc(IndicatorValue, size);
        errdefer allocator.free(values);

        // Initialize with NaN to indicate unset values
        for (values) |*v| {
            v.* = Decimal.ZERO; // TODO: Use NaN when Decimal supports it
        }

        return .{
            .name = name_copy,
            .values = values,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *IndicatorSeries) void {
        self.allocator.free(self.name);
        self.allocator.free(self.values);
    }

    /// Set indicator value at index
    pub fn set(self: *IndicatorSeries, index: usize, value: IndicatorValue) !void {
        if (index >= self.values.len) {
            return error.IndexOutOfBounds;
        }
        self.values[index] = value;
    }

    /// Get indicator value at index
    pub fn get(self: *const IndicatorSeries, index: usize) ?IndicatorValue {
        if (index >= self.values.len) {
            return null;
        }
        return self.values[index];
    }
};

// ============================================================================
// Candles Container
// ============================================================================

/// Container for multiple candles with indicator support
pub const Candles = struct {
    pair: TradingPair,
    timeframe: Timeframe,
    candles: []Candle,
    indicators: std.StringHashMap(*IndicatorSeries),
    allocator: std.mem.Allocator,

    /// Initialize empty candles container
    pub fn init(
        allocator: std.mem.Allocator,
        pair: TradingPair,
        timeframe: Timeframe,
    ) Candles {
        return .{
            .pair = pair,
            .timeframe = timeframe,
            .candles = &[_]Candle{},
            .indicators = std.StringHashMap(*IndicatorSeries).init(allocator),
            .allocator = allocator,
        };
    }

    /// Initialize with pre-allocated candle array
    pub fn initWithCandles(
        allocator: std.mem.Allocator,
        pair: TradingPair,
        timeframe: Timeframe,
        candles: []Candle,
    ) Candles {
        return .{
            .pair = pair,
            .timeframe = timeframe,
            .candles = candles,
            .indicators = std.StringHashMap(*IndicatorSeries).init(allocator),
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Candles) void {
        // Free candles array (if owned)
        if (self.candles.len > 0) {
            self.allocator.free(self.candles);
        }

        // Free all indicators
        var iter = self.indicators.valueIterator();
        while (iter.next()) |indicator_ptr| {
            var indicator = indicator_ptr.*;
            indicator.deinit();
            self.allocator.destroy(indicator);
        }
        self.indicators.deinit();
    }

    /// Get number of candles
    pub fn len(self: *const Candles) usize {
        return self.candles.len;
    }

    /// Get candle at index
    pub fn get(self: *const Candles, index: usize) ?Candle {
        if (index >= self.candles.len) {
            return null;
        }
        return self.candles[index];
    }

    /// Get last candle (most recent)
    pub fn getLast(self: *const Candles) ?Candle {
        if (self.candles.len == 0) {
            return null;
        }
        return self.candles[self.candles.len - 1];
    }

    /// Get candle at index from end (0 = last, 1 = second to last, etc.)
    pub fn getFromEnd(self: *const Candles, offset: usize) ?Candle {
        if (offset >= self.candles.len) {
            return null;
        }
        return self.candles[self.candles.len - 1 - offset];
    }

    /// Add or update indicator series
    /// Takes ownership of the indicator series
    pub fn addIndicator(self: *Candles, indicator: *IndicatorSeries) !void {
        // Check if indicator length matches candles length
        if (indicator.values.len != self.candles.len) {
            return error.IndicatorLengthMismatch;
        }

        // Add to hashmap (overwrites if exists)
        try self.indicators.put(indicator.name, indicator);
    }

    /// Get indicator series by name
    pub fn getIndicator(self: *const Candles, name: []const u8) ?*IndicatorSeries {
        return self.indicators.get(name);
    }

    /// Get indicator value at specific index
    pub fn getIndicatorValue(self: *const Candles, name: []const u8, index: usize) ?IndicatorValue {
        const indicator = self.getIndicator(name) orelse return null;
        return indicator.get(index);
    }

    /// Validate all candles
    pub fn validate(self: *const Candles) !void {
        for (self.candles) |candle| {
            try candle.validate();
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Candle: validation - valid candle" {
    const candle = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(100),
        .high = Decimal.fromInt(110),
        .low = Decimal.fromInt(95),
        .close = Decimal.fromInt(105),
        .volume = Decimal.fromInt(1000),
    };

    try candle.validate();
}

test "Candle: validation - high less than low" {
    const candle = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(100),
        .high = Decimal.fromInt(90), // Invalid: high < low
        .low = Decimal.fromInt(95),
        .close = Decimal.fromInt(100),
        .volume = Decimal.fromInt(1000),
    };

    try std.testing.expectError(error.HighLessThanLow, candle.validate());
}

test "Candle: bullish/bearish detection" {
    const bullish = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(100),
        .high = Decimal.fromInt(110),
        .low = Decimal.fromInt(95),
        .close = Decimal.fromInt(105),
        .volume = Decimal.fromInt(1000),
    };

    try std.testing.expect(bullish.isBullish());
    try std.testing.expect(!bullish.isBearish());

    const bearish = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(100),
        .high = Decimal.fromInt(105),
        .low = Decimal.fromInt(90),
        .close = Decimal.fromInt(95),
        .volume = Decimal.fromInt(1000),
    };

    try std.testing.expect(!bearish.isBullish());
    try std.testing.expect(bearish.isBearish());
}

test "Candle: calculations" {
    const candle = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(100),
        .high = Decimal.fromInt(110),
        .low = Decimal.fromInt(95),
        .close = Decimal.fromInt(105),
        .volume = Decimal.fromInt(1000),
    };

    // Body size = |105 - 100| = 5
    const body = candle.bodySize();
    try std.testing.expect((Decimal.fromInt(5)).eql(body));

    // Range = 110 - 95 = 15
    const r = candle.range();
    try std.testing.expect((Decimal.fromInt(15)).eql(r));

    // Typical price = (110 + 95 + 105) / 3 = 103.33...
    const typical = try candle.typicalPrice();
    try std.testing.expect(typical.cmp(Decimal.fromInt(103)) == .gt);
    try std.testing.expect(typical.cmp(Decimal.fromInt(104)) == .lt);
}

test "IndicatorSeries: basic operations" {
    const allocator = std.testing.allocator;

    var series = try IndicatorSeries.init(allocator, "test_sma", 5);
    defer series.deinit();

    try std.testing.expectEqualStrings("test_sma", series.name);
    try std.testing.expectEqual(@as(usize, 5), series.values.len);

    // Set and get values
    try series.set(0, Decimal.fromInt(10));
    try series.set(1, Decimal.fromInt(20));

    const val0 = series.get(0).?;
    try std.testing.expect((Decimal.fromInt(10)).eql(val0));

    const val1 = series.get(1).?;
    try std.testing.expect((Decimal.fromInt(20)).eql(val1));

    // Out of bounds
    const val_oob = series.get(10);
    try std.testing.expect(val_oob == null);
}

test "Candles: initialization and basic access" {
    const allocator = std.testing.allocator;

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    var candles = Candles.init(allocator, pair, .m15);
    defer candles.deinit();

    try std.testing.expectEqual(@as(usize, 0), candles.len());
    try std.testing.expect(candles.getLast() == null);
}

test "Candles: with candle data" {
    const allocator = std.testing.allocator;

    var candle_data = try allocator.alloc(Candle, 3);
    candle_data[0] = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(100),
        .high = Decimal.fromInt(105),
        .low = Decimal.fromInt(98),
        .close = Decimal.fromInt(102),
        .volume = Decimal.fromInt(1000),
    };
    candle_data[1] = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(102),
        .high = Decimal.fromInt(108),
        .low = Decimal.fromInt(101),
        .close = Decimal.fromInt(106),
        .volume = Decimal.fromInt(1200),
    };
    candle_data[2] = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(106),
        .high = Decimal.fromInt(110),
        .low = Decimal.fromInt(104),
        .close = Decimal.fromInt(108),
        .volume = Decimal.fromInt(1500),
    };

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    var candles = Candles.initWithCandles(allocator, pair, .m15, candle_data);
    defer candles.deinit();

    try std.testing.expectEqual(@as(usize, 3), candles.len());

    // Get last candle
    const last = candles.getLast().?;
    try std.testing.expect((Decimal.fromInt(108)).eql(last.close));

    // Get from end
    const second_last = candles.getFromEnd(1).?;
    try std.testing.expect((Decimal.fromInt(106)).eql(second_last.close));

    // Get by index
    const first = candles.get(0).?;
    try std.testing.expect((Decimal.fromInt(102)).eql(first.close));
}

test "Candles: indicator management" {
    const allocator = std.testing.allocator;

    var candle_data = try allocator.alloc(Candle, 3);
    candle_data[0] = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(100),
        .high = Decimal.fromInt(105),
        .low = Decimal.fromInt(98),
        .close = Decimal.fromInt(102),
        .volume = Decimal.fromInt(1000),
    };
    candle_data[1] = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(102),
        .high = Decimal.fromInt(108),
        .low = Decimal.fromInt(101),
        .close = Decimal.fromInt(106),
        .volume = Decimal.fromInt(1200),
    };
    candle_data[2] = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(106),
        .high = Decimal.fromInt(110),
        .low = Decimal.fromInt(104),
        .close = Decimal.fromInt(108),
        .volume = Decimal.fromInt(1500),
    };

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    var candles = Candles.initWithCandles(allocator, pair, .m15, candle_data);
    defer candles.deinit();

    // Create indicator series
    var sma_series = try allocator.create(IndicatorSeries);
    sma_series.* = try IndicatorSeries.init(allocator, "sma_20", 3);

    try sma_series.set(0, Decimal.fromInt(100));
    try sma_series.set(1, Decimal.fromInt(105));
    try sma_series.set(2, Decimal.fromInt(110));

    // Add indicator to candles
    try candles.addIndicator(sma_series);

    // Retrieve indicator
    const retrieved = candles.getIndicator("sma_20").?;
    try std.testing.expectEqualStrings("sma_20", retrieved.name);

    // Get indicator value at index
    const val = candles.getIndicatorValue("sma_20", 1).?;
    try std.testing.expect((Decimal.fromInt(105)).eql(val));

    // Non-existent indicator
    try std.testing.expect(candles.getIndicator("non_existent") == null);
}

test "Candles: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var candle_data = try allocator.alloc(Candle, 2);
    candle_data[0] = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(100),
        .high = Decimal.fromInt(105),
        .low = Decimal.fromInt(98),
        .close = Decimal.fromInt(102),
        .volume = Decimal.fromInt(1000),
    };
    candle_data[1] = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromInt(102),
        .high = Decimal.fromInt(108),
        .low = Decimal.fromInt(101),
        .close = Decimal.fromInt(106),
        .volume = Decimal.fromInt(1200),
    };

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    var candles = Candles.initWithCandles(allocator, pair, .m15, candle_data);
    defer candles.deinit();

    // Add indicator
    const indicator = try allocator.create(IndicatorSeries);
    indicator.* = try IndicatorSeries.init(allocator, "test", 2);
    try candles.addIndicator(indicator);

    _ = candles.getLast();
    _ = candles.getIndicator("test");
}
