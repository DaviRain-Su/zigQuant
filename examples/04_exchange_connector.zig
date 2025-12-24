//! Exchange Connector Example
//!
//! Demonstrates how to use the exchange abstraction layer:
//! - Create HyperliquidConnector
//! - Use IExchange interface
//! - Get ticker data
//! - Get orderbook
//! - Symbol mapping
//!
//! Run with: zig build run-example-connector

const std = @import("std");
const zigQuant = @import("zigQuant");

const HyperliquidConnector = zigQuant.HyperliquidConnector;
const IExchange = zigQuant.IExchange;
const TradingPair = zigQuant.TradingPair;
const ExchangeConfig = zigQuant.ExchangeConfig;
const Logger = zigQuant.Logger;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║          Exchange Connector Example                      ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════╝\n\n", .{});

    // ========================================================================
    // 1. Create Logger
    // ========================================================================
    std.debug.print("1️⃣  Setting up logger...\n", .{});

    const DummyWriter = struct {
        fn write(_: *anyopaque, record: zigQuant.logger.LogRecord) anyerror!void {
            const level_str = switch (record.level) {
                .trace => "TRACE",
                .debug => "DEBUG",
                .info => "INFO ",
                .warn => "WARN ",
                .err => "ERROR",
                .fatal => "FATAL",
            };
            std.debug.print("[{s}] {s}\n", .{ level_str, record.message });
        }
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const dummy = struct {};
    const log_writer = zigQuant.logger.LogWriter{
        .ptr = @constCast(@ptrCast(&dummy)),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    const logger = Logger.init(allocator, log_writer, .info);

    // ========================================================================
    // 2. Create Exchange Connector
    // ========================================================================
    std.debug.print("2️⃣  Creating Hyperliquid connector...\n", .{});

    const exchange_config = ExchangeConfig{
        .name = "hyperliquid",
        .api_key = "", // Not needed for public endpoints
        .api_secret = "",
        .testnet = false,
    };

    const connector = try HyperliquidConnector.create(allocator, exchange_config, logger);
    defer connector.destroy();
    const exchange = connector.interface();

    std.debug.print("✅ Connector created!\n", .{});
    std.debug.print("   Exchange: {s}\n", .{exchange.getName()});
    std.debug.print("   Testnet: {}\n\n", .{exchange_config.testnet});

    // ========================================================================
    // 3. Connect to Exchange
    // ========================================================================
    std.debug.print("3️⃣  Connecting to exchange...\n", .{});

    try exchange.connect();

    std.debug.print("✅ Connected: {}\n\n", .{exchange.isConnected()});

    // ========================================================================
    // 4. Get Ticker Data
    // ========================================================================
    std.debug.print("4️⃣  Fetching ticker data...\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    // Create trading pairs
    const eth_usdc = TradingPair{ .base = "ETH", .quote = "USDC" };
    const btc_usdc = TradingPair{ .base = "BTC", .quote = "USDC" };
    const sol_usdc = TradingPair{ .base = "SOL", .quote = "USDC" };

    const pairs = [_]TradingPair{ eth_usdc, btc_usdc, sol_usdc };

    std.debug.print("📊 Ticker Data:\n\n", .{});
    std.debug.print("  Pair         Bid             Ask             Last            Volume (24h)\n", .{});
    std.debug.print("  ───────────────────────────────────────────────────────────────────────────\n", .{});

    for (pairs) |pair| {
        const ticker = try exchange.getTicker(pair);

        const bid_str = try ticker.bid.toString(allocator);
        defer allocator.free(bid_str);
        const ask_str = try ticker.ask.toString(allocator);
        defer allocator.free(ask_str);
        const last_str = try ticker.last.toString(allocator);
        defer allocator.free(last_str);
        const vol_str = try ticker.volume_24h.toString(allocator);
        defer allocator.free(vol_str);

        std.debug.print("  {s:3}-{s:4}   ${s:12}   ${s:12}   ${s:12}   {s:12}\n", .{
            pair.base,
            pair.quote,
            bid_str,
            ask_str,
            last_str,
            vol_str,
        });
    }

    std.debug.print("\n", .{});

    // ========================================================================
    // 5. Get Orderbook
    // ========================================================================
    std.debug.print("5️⃣  Fetching ETH orderbook...\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    const orderbook = try exchange.getOrderbook(eth_usdc, 5);
    defer orderbook.deinit(allocator);

    std.debug.print("📖 ETH-USDC Orderbook (Top 5):\n\n", .{});

    // Bids
    std.debug.print("  Bids:\n", .{});
    for (orderbook.bids, 0..) |level, i| {
        const price_str = try level.price.toString(allocator);
        defer allocator.free(price_str);
        const qty_str = try level.quantity.toString(allocator);
        defer allocator.free(qty_str);

        std.debug.print("    {d}. ${s:12} x {s:8} ETH\n", .{ i + 1, price_str, qty_str });
    }

    std.debug.print("\n  Asks:\n", .{});
    for (orderbook.asks, 0..) |level, i| {
        const price_str = try level.price.toString(allocator);
        defer allocator.free(price_str);
        const qty_str = try level.quantity.toString(allocator);
        defer allocator.free(qty_str);

        std.debug.print("    {d}. ${s:12} x {s:8} ETH\n", .{ i + 1, price_str, qty_str });
    }

    // Calculate mid price
    if (orderbook.bids.len > 0 and orderbook.asks.len > 0) {
        const best_bid = orderbook.bids[0].price;
        const best_ask = orderbook.asks[0].price;
        const sum = best_bid.add(best_ask);
        const two = try zigQuant.Decimal.fromString("2");
        const mid = try sum.div(two);

        const mid_str = try mid.toString(allocator);
        defer allocator.free(mid_str);

        std.debug.print("\n  Mid Price: ${s}\n", .{mid_str});
    }

    std.debug.print("\n", .{});

    // ========================================================================
    // 6. Symbol Mapping Example
    // ========================================================================
    std.debug.print("6️⃣  Symbol mapping example...\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    std.debug.print("  Unified Format → Hyperliquid Format:\n", .{});
    for (pairs) |pair| {
        const hl_symbol = try zigQuant.SymbolMapper.toHyperliquid(pair);
        std.debug.print("    {s}-{s:4} → {s}\n", .{ pair.base, pair.quote, hl_symbol });
    }

    std.debug.print("\n  Hyperliquid Format → Unified Format:\n", .{});
    const hl_symbols = [_][]const u8{ "ETH", "BTC", "SOL" };
    for (hl_symbols) |symbol| {
        const pair = zigQuant.SymbolMapper.fromHyperliquid(symbol);
        std.debug.print("    {s:4} → {s}-{s}\n", .{ symbol, pair.base, pair.quote });
    }

    std.debug.print("\n", .{});

    // ========================================================================
    // 7. Disconnect
    // ========================================================================
    std.debug.print("7️⃣  Disconnecting...\n", .{});

    exchange.disconnect();

    std.debug.print("✅ Disconnected: {}\n\n", .{!exchange.isConnected()});

    std.debug.print("╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                   Example Complete!                      ║\n", .{});
    std.debug.print("║                                                          ║\n", .{});
    std.debug.print("║  This example showed how to use the exchange            ║\n", .{});
    std.debug.print("║  abstraction layer. The same code works with any        ║\n", .{});
    std.debug.print("║  exchange that implements the IExchange interface!      ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════╝\n\n", .{});
}
