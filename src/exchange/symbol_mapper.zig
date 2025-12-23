//! Symbol Mapper - Convert between unified TradingPair and exchange-specific formats
//!
//! Different exchanges use different symbol formats:
//! - Hyperliquid: "ETH" (only base asset, quote is always USDC)
//! - Binance: "ETHUSDT" (concatenated)
//! - OKX: "ETH-USDT" (dash separated)
//! - Bybit: "ETHUSDT" (concatenated)
//!
//! This module provides conversion functions for each exchange format.

const std = @import("std");
const TradingPair = @import("types.zig").TradingPair;

// ============================================================================
// Hyperliquid Symbol Mapping
// ============================================================================

/// Convert TradingPair to Hyperliquid format
///
/// Hyperliquid uses only the base asset symbol (quote is always USDC).
/// Examples:
/// - ETH-USDC -> "ETH"
/// - BTC-USDC -> "BTC"
/// - SOL-USDC -> "SOL"
///
/// Returns error.InvalidQuoteAsset if quote is not USDC.
pub fn toHyperliquid(pair: TradingPair) ![]const u8 {
    // Hyperliquid only supports USDC as quote
    if (!std.mem.eql(u8, pair.quote, "USDC")) {
        return error.InvalidQuoteAsset;
    }

    // Return the base asset directly
    return pair.base;
}

/// Convert Hyperliquid symbol to TradingPair
///
/// Hyperliquid symbols are just the base asset (quote is always USDC).
/// Examples:
/// - "ETH" -> ETH-USDC
/// - "BTC" -> BTC-USDC
/// - "SOL" -> SOL-USDC
pub fn fromHyperliquid(symbol: []const u8) TradingPair {
    return .{
        .base = symbol,
        .quote = "USDC",
    };
}

// ============================================================================
// Binance Symbol Mapping (for future use)
// ============================================================================

/// Convert TradingPair to Binance format
///
/// Binance uses concatenated format: BASEUSDT, BTCUSDT, etc.
/// This requires allocation to create the concatenated string.
pub fn toBinance(pair: TradingPair, allocator: std.mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ pair.base, pair.quote });
}

/// Convert Binance symbol to TradingPair
///
/// Binance format: ETHUSDT -> ETH-USDT
/// This is heuristic-based since there's no separator.
/// Common quote assets: USDT, USDC, BTC, ETH, BNB
pub fn fromBinance(symbol: []const u8) !TradingPair {
    // Try common quote assets
    const quote_assets = [_][]const u8{ "USDT", "USDC", "BUSD", "BTC", "ETH", "BNB" };

    for (quote_assets) |quote| {
        if (std.mem.endsWith(u8, symbol, quote)) {
            const base_end = symbol.len - quote.len;
            if (base_end > 0) {
                return .{
                    .base = symbol[0..base_end],
                    .quote = quote,
                };
            }
        }
    }

    return error.UnknownQuoteAsset;
}

// ============================================================================
// OKX Symbol Mapping (for future use)
// ============================================================================

/// Convert TradingPair to OKX format
///
/// OKX uses dash-separated format: ETH-USDT, BTC-USDT, etc.
pub fn toOKX(pair: TradingPair, allocator: std.mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}-{s}", .{ pair.base, pair.quote });
}

/// Convert OKX symbol to TradingPair
///
/// OKX format: ETH-USDT -> ETH-USDT
pub fn fromOKX(symbol: []const u8) !TradingPair {
    if (std.mem.indexOf(u8, symbol, "-")) |idx| {
        return .{
            .base = symbol[0..idx],
            .quote = symbol[idx + 1 ..],
        };
    }
    return error.InvalidSymbolFormat;
}

// ============================================================================
// Generic Conversion (auto-detect exchange)
// ============================================================================

/// Exchange type for auto-detection
pub const ExchangeType = enum {
    hyperliquid,
    binance,
    okx,
    bybit,

    pub fn toString(self: ExchangeType) []const u8 {
        return switch (self) {
            .hyperliquid => "hyperliquid",
            .binance => "binance",
            .okx => "okx",
            .bybit => "bybit",
        };
    }
};

/// Convert TradingPair to exchange-specific format
pub fn toExchange(
    pair: TradingPair,
    exchange: ExchangeType,
    allocator: std.mem.Allocator,
) ![]const u8 {
    return switch (exchange) {
        .hyperliquid => toHyperliquid(pair),
        .binance => toBinance(pair, allocator),
        .okx => toOKX(pair, allocator),
        .bybit => toBinance(pair, allocator), // Bybit uses same format as Binance
    };
}

/// Convert exchange-specific symbol to TradingPair
pub fn fromExchange(symbol: []const u8, exchange: ExchangeType) !TradingPair {
    return switch (exchange) {
        .hyperliquid => fromHyperliquid(symbol),
        .binance => fromBinance(symbol),
        .okx => fromOKX(symbol),
        .bybit => fromBinance(symbol), // Bybit uses same format as Binance
    };
}

// ============================================================================
// Symbol Cache (for future optimization)
// ============================================================================

/// Symbol cache for frequently used conversions
/// This can significantly improve performance for hot paths
pub const SymbolCache = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap(TradingPair),

    pub fn init(allocator: std.mem.Allocator) SymbolCache {
        return .{
            .allocator = allocator,
            .cache = std.StringHashMap(TradingPair).init(allocator),
        };
    }

    pub fn deinit(self: *SymbolCache) void {
        self.cache.deinit();
    }

    /// Get TradingPair from cache, or convert and cache it
    pub fn get(
        self: *SymbolCache,
        symbol: []const u8,
        exchange: ExchangeType,
    ) !TradingPair {
        // Check cache first
        if (self.cache.get(symbol)) |pair| {
            return pair;
        }

        // Convert and cache
        const pair = try fromExchange(symbol, exchange);
        try self.cache.put(symbol, pair);
        return pair;
    }

    /// Clear cache
    pub fn clear(self: *SymbolCache) void {
        self.cache.clearRetainingCapacity();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Hyperliquid: toHyperliquid" {
    const pair = TradingPair{ .base = "ETH", .quote = "USDC" };
    const symbol = try toHyperliquid(pair);
    try std.testing.expectEqualStrings("ETH", symbol);
}

test "Hyperliquid: toHyperliquid invalid quote" {
    const pair = TradingPair{ .base = "ETH", .quote = "USDT" };
    try std.testing.expectError(error.InvalidQuoteAsset, toHyperliquid(pair));
}

test "Hyperliquid: fromHyperliquid" {
    const pair = fromHyperliquid("BTC");
    try std.testing.expectEqualStrings("BTC", pair.base);
    try std.testing.expectEqualStrings("USDC", pair.quote);
}

test "Binance: toBinance" {
    const pair = TradingPair{ .base = "ETH", .quote = "USDT" };
    const symbol = try toBinance(pair, std.testing.allocator);
    defer std.testing.allocator.free(symbol);
    try std.testing.expectEqualStrings("ETHUSDT", symbol);
}

test "Binance: fromBinance" {
    const pair = try fromBinance("ETHUSDT");
    try std.testing.expectEqualStrings("ETH", pair.base);
    try std.testing.expectEqualStrings("USDT", pair.quote);

    const pair2 = try fromBinance("BTCUSDC");
    try std.testing.expectEqualStrings("BTC", pair2.base);
    try std.testing.expectEqualStrings("USDC", pair2.quote);
}

test "OKX: toOKX" {
    const pair = TradingPair{ .base = "ETH", .quote = "USDT" };
    const symbol = try toOKX(pair, std.testing.allocator);
    defer std.testing.allocator.free(symbol);
    try std.testing.expectEqualStrings("ETH-USDT", symbol);
}

test "OKX: fromOKX" {
    const pair = try fromOKX("BTC-USDT");
    try std.testing.expectEqualStrings("BTC", pair.base);
    try std.testing.expectEqualStrings("USDT", pair.quote);
}

test "Generic: toExchange/fromExchange" {
    const pair = TradingPair{ .base = "ETH", .quote = "USDC" };

    // Hyperliquid
    const hl_symbol = try toExchange(pair, .hyperliquid, std.testing.allocator);
    try std.testing.expectEqualStrings("ETH", hl_symbol);
    const hl_pair = try fromExchange(hl_symbol, .hyperliquid);
    try std.testing.expect(pair.eql(hl_pair));

    // Binance
    const bn_symbol = try toExchange(pair, .binance, std.testing.allocator);
    defer std.testing.allocator.free(bn_symbol);
    try std.testing.expectEqualStrings("ETHUSDC", bn_symbol);

    // OKX
    const okx_symbol = try toExchange(pair, .okx, std.testing.allocator);
    defer std.testing.allocator.free(okx_symbol);
    try std.testing.expectEqualStrings("ETH-USDC", okx_symbol);
}

test "SymbolCache: basic operations" {
    var cache = SymbolCache.init(std.testing.allocator);
    defer cache.deinit();

    // First call should convert and cache
    const pair1 = try cache.get("ETH", .hyperliquid);
    try std.testing.expectEqualStrings("ETH", pair1.base);
    try std.testing.expectEqualStrings("USDC", pair1.quote);

    // Second call should hit cache
    const pair2 = try cache.get("ETH", .hyperliquid);
    try std.testing.expect(pair1.eql(pair2));

    // Clear and verify
    cache.clear();
}
