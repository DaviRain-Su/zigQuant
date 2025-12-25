//! Market Data Provider
//!
//! Provides market data access for strategies:
//! - Latest price queries
//! - Historical candle data
//! - Data caching for performance
//! - Exchange abstraction
//!
//! Design principles:
//! - Efficient caching to minimize API calls
//! - Support both live and backtest modes
//! - Clean interface for strategies

const std = @import("std");
const Decimal = @import("../root.zig").Decimal;
const TradingPair = @import("../root.zig").TradingPair;
const Timeframe = @import("../root.zig").Timeframe;
const Timestamp = @import("../root.zig").Timestamp;
const Candle = @import("../root.zig").Candle;
const Candles = @import("../root.zig").Candles;
const IExchange = @import("../root.zig").IExchange;

// ============================================================================
// Market Data Provider
// ============================================================================

/// Market data provider for strategies
pub const MarketDataProvider = struct {
    allocator: std.mem.Allocator,
    exchange: ?IExchange,

    // Price cache: "BTC-USDT" -> price
    price_cache: std.StringHashMap(Decimal),

    // Candle cache: "BTC-USDT_h1_1234567890_1234567900" -> Candles
    candle_cache: std.StringHashMap(*Candles),

    /// Initialize market data provider
    pub fn init(allocator: std.mem.Allocator, exchange: ?IExchange) MarketDataProvider {
        return MarketDataProvider{
            .allocator = allocator,
            .exchange = exchange,
            .price_cache = std.StringHashMap(Decimal).init(allocator),
            .candle_cache = std.StringHashMap(*Candles).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *MarketDataProvider) void {
        // Free price cache keys and values
        var price_iter = self.price_cache.keyIterator();
        while (price_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.price_cache.deinit();

        // Free candle cache keys and values
        var candle_iter = self.candle_cache.iterator();
        while (candle_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.candle_cache.deinit();
    }

    /// Get latest price for a trading pair
    pub fn getLatestPrice(self: *MarketDataProvider, pair: TradingPair) !Decimal {
        // Check cache first
        const key = try self.makePairKey(pair);
        defer self.allocator.free(key);

        if (self.price_cache.get(key)) |cached_price| {
            return cached_price;
        }

        // Fetch from exchange if available
        if (self.exchange) |exchange| {
            const ticker = try exchange.getTicker(pair);
            const price = ticker.last;

            // Cache the price
            const owned_key = try self.allocator.dupe(u8, key);
            try self.price_cache.put(owned_key, price);

            return price;
        }

        return error.NoExchangeConnected;
    }

    /// Update cached price (useful for backtesting)
    pub fn updatePrice(self: *MarketDataProvider, pair: TradingPair, price: Decimal) !void {
        const key = try self.makePairKey(pair);
        defer self.allocator.free(key);

        // Check if key already exists and free it if so
        if (self.price_cache.fetchRemove(key)) |old_entry| {
            self.allocator.free(old_entry.key);
        }

        const owned_key = try self.allocator.dupe(u8, key);
        try self.price_cache.put(owned_key, price);
    }

    /// Get historical candles
    pub fn getCandles(
        self: *MarketDataProvider,
        pair: TradingPair,
        timeframe: Timeframe,
        start: Timestamp,
        end: Timestamp,
    ) !*Candles {
        // Check cache first
        const cache_key = try self.makeCandleKey(pair, timeframe, start, end);
        defer self.allocator.free(cache_key);

        if (self.candle_cache.get(cache_key)) |cached_candles| {
            return cached_candles;
        }

        // Fetch from exchange if available
        if (self.exchange) |exchange| {
            // Get candles from exchange
            const candle_list = try exchange.getCandles(pair, timeframe, start, end);
            defer self.allocator.free(candle_list);

            // Create Candles container
            const candles = try self.allocator.create(Candles);
            candles.* = Candles.init(self.allocator, pair, timeframe);

            // Add candles to container
            for (candle_list) |candle| {
                try candles.add(candle);
            }

            // Cache the candles
            const owned_key = try self.allocator.dupe(u8, cache_key);
            try self.candle_cache.put(owned_key, candles);

            return candles;
        }

        return error.NoExchangeConnected;
    }

    /// Set candles directly (useful for backtesting)
    pub fn setCandles(
        self: *MarketDataProvider,
        pair: TradingPair,
        timeframe: Timeframe,
        candles: *Candles,
    ) !void {
        // Use first and last candle timestamps as range
        const candle_list = candles.candles;
        if (candle_list.len == 0) {
            return error.EmptyCandleList;
        }

        const start = candle_list[0].timestamp;
        const end = candle_list[candle_list.len - 1].timestamp;

        const cache_key = try self.makeCandleKey(pair, timeframe, start, end);
        defer self.allocator.free(cache_key);

        // Check if key already exists and free it if so
        if (self.candle_cache.fetchRemove(cache_key)) |old_entry| {
            self.allocator.free(old_entry.key);
            old_entry.value.deinit();
            self.allocator.destroy(old_entry.value);
        }

        const owned_key = try self.allocator.dupe(u8, cache_key);
        try self.candle_cache.put(owned_key, candles);
    }

    /// Clear all caches
    pub fn clearCache(self: *MarketDataProvider) void {
        // Clear price cache
        var price_iter = self.price_cache.keyIterator();
        while (price_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.price_cache.clearRetainingCapacity();

        // Clear candle cache
        var candle_iter = self.candle_cache.iterator();
        while (candle_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.candle_cache.clearRetainingCapacity();
    }

    /// Make cache key for pair
    fn makePairKey(self: *MarketDataProvider, pair: TradingPair) ![]const u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}-{s}",
            .{ pair.base, pair.quote },
        );
    }

    /// Make cache key for candles
    fn makeCandleKey(
        self: *MarketDataProvider,
        pair: TradingPair,
        timeframe: Timeframe,
        start: Timestamp,
        end: Timestamp,
    ) ![]const u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}-{s}_{s}_{d}_{d}",
            .{ pair.base, pair.quote, timeframe.toString(), start.millis, end.millis },
        );
    }
};

// ============================================================================
// Tests
// ============================================================================

test "MarketDataProvider: init and deinit" {
    const allocator = std.testing.allocator;
    var provider = MarketDataProvider.init(allocator, null);
    defer provider.deinit();

    try std.testing.expect(provider.exchange == null);
    try std.testing.expectEqual(@as(usize, 0), provider.price_cache.count());
    try std.testing.expectEqual(@as(usize, 0), provider.candle_cache.count());
}

test "MarketDataProvider: update and get price" {
    const allocator = std.testing.allocator;
    var provider = MarketDataProvider.init(allocator, null);
    defer provider.deinit();

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    const price = Decimal.fromInt(50000);

    // Update price
    try provider.updatePrice(pair, price);

    // Get price from cache
    const cached_price = try provider.getLatestPrice(pair);
    try std.testing.expect(cached_price.eql(price));
}

test "MarketDataProvider: price cache key generation" {
    const allocator = std.testing.allocator;
    var provider = MarketDataProvider.init(allocator, null);
    defer provider.deinit();

    const pair1 = TradingPair{ .base = "BTC", .quote = "USDT" };
    const pair2 = TradingPair{ .base = "ETH", .quote = "USDT" };

    const key1 = try provider.makePairKey(pair1);
    defer allocator.free(key1);
    const key2 = try provider.makePairKey(pair2);
    defer allocator.free(key2);

    try std.testing.expectEqualStrings("BTC-USDT", key1);
    try std.testing.expectEqualStrings("ETH-USDT", key2);
}

test "MarketDataProvider: candle cache key generation" {
    const allocator = std.testing.allocator;
    var provider = MarketDataProvider.init(allocator, null);
    defer provider.deinit();

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    const start = Timestamp{ .millis = 1000000 };
    const end = Timestamp{ .millis = 2000000 };

    const key = try provider.makeCandleKey(pair, .h1, start, end);
    defer allocator.free(key);

    try std.testing.expectEqualStrings("BTC-USDT_1h_1000000_2000000", key);
}

test "MarketDataProvider: set and get candles" {
    const allocator = std.testing.allocator;
    var provider = MarketDataProvider.init(allocator, null);
    defer provider.deinit();

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };

    // Create candle array
    var candle_list = try allocator.alloc(Candle, 2);
    candle_list[0] = Candle{
        .timestamp = Timestamp{ .millis = 1000000 },
        .open = Decimal.fromInt(50000),
        .high = Decimal.fromInt(51000),
        .low = Decimal.fromInt(49000),
        .close = Decimal.fromInt(50500),
        .volume = Decimal.fromInt(100),
    };
    candle_list[1] = Candle{
        .timestamp = Timestamp{ .millis = 2000000 },
        .open = Decimal.fromInt(50500),
        .high = Decimal.fromInt(52000),
        .low = Decimal.fromInt(50000),
        .close = Decimal.fromInt(51500),
        .volume = Decimal.fromInt(150),
    };

    // Create Candles with array
    const candles = Candles.initWithCandles(allocator, pair, .h1, candle_list);

    // Set candles in provider (transfer ownership)
    const candles_ptr = try allocator.create(Candles);
    candles_ptr.* = candles;
    try provider.setCandles(pair, .h1, candles_ptr);

    // Verify candles are cached
    try std.testing.expectEqual(@as(usize, 1), provider.candle_cache.count());
}

test "MarketDataProvider: clear cache" {
    const allocator = std.testing.allocator;
    var provider = MarketDataProvider.init(allocator, null);
    defer provider.deinit();

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };

    // Add price to cache
    try provider.updatePrice(pair, Decimal.fromInt(50000));
    try std.testing.expectEqual(@as(usize, 1), provider.price_cache.count());

    // Clear cache
    provider.clearCache();
    try std.testing.expectEqual(@as(usize, 0), provider.price_cache.count());
    try std.testing.expectEqual(@as(usize, 0), provider.candle_cache.count());
}

test "MarketDataProvider: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var provider = MarketDataProvider.init(allocator, null);
    defer provider.deinit();

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };

    // Add some data
    try provider.updatePrice(pair, Decimal.fromInt(50000));
    try provider.updatePrice(pair, Decimal.fromInt(51000));

    // Clear cache
    provider.clearCache();
}

test "MarketDataProvider: no exchange error" {
    const allocator = std.testing.allocator;
    var provider = MarketDataProvider.init(allocator, null);
    defer provider.deinit();

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };

    // Should fail without exchange
    const result = provider.getLatestPrice(pair);
    try std.testing.expectError(error.NoExchangeConnected, result);
}
