//! Hyperliquid HTTP Market Data Example
//!
//! Demonstrates how to:
//! - Create HTTP client
//! - Fetch market metadata
//! - Get all mid prices
//! - Get L2 orderbook
//! - Get candle data
//!
//! Run with: zig build run-example-http

const std = @import("std");
const zigQuant = @import("zigQuant");

const HyperliquidClient = zigQuant.hyperliquid.HyperliquidClient;
const InfoAPI = zigQuant.hyperliquid.InfoAPI;
const Logger = zigQuant.Logger;
const Decimal = zigQuant.Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║      Hyperliquid HTTP Market Data Example               ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════╝\n\n", .{});

    // ========================================================================
    // 1. Create Logger and HTTP Client
    // ========================================================================
    std.debug.print("1️⃣  Setting up HTTP client...\n", .{});

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

    var http_client = HyperliquidClient.init(allocator, false, logger);
    defer http_client.deinit();

    var info_api = InfoAPI.init(allocator, &http_client, logger);

    std.debug.print("✅ HTTP client ready!\n\n", .{});

    // ========================================================================
    // 2. Get Market Metadata
    // ========================================================================
    std.debug.print("2️⃣  Fetching market metadata...\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    const meta = try info_api.getMeta();
    defer meta.deinit();

    std.debug.print("\n📊 Universe: {} markets\n", .{meta.value.universe.len});
    std.debug.print("\nTop 5 Markets:\n", .{});

    const top_count = @min(5, meta.value.universe.len);
    for (meta.value.universe[0..top_count], 0..) |market, i| {
        const sz_dec = if (market.szDecimals) |d| d else 0;
        std.debug.print("  {d}. {s:8} - szDecimals: {}\n", .{
            i + 1,
            market.name,
            sz_dec,
        });
    }

    std.debug.print("\n", .{});

    // ========================================================================
    // 3. Get All Mid Prices
    // ========================================================================
    std.debug.print("3️⃣  Fetching all mid prices...\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    var mids = try info_api.getAllMids();
    defer {
        var iter = mids.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        mids.deinit();
    }

    std.debug.print("\n💰 Mid Prices ({} markets):\n", .{mids.count()});

    // Show some major coins
    const major_coins = [_][]const u8{ "BTC", "ETH", "SOL", "ATOM", "ARB" };
    for (major_coins) |coin| {
        if (mids.get(coin)) |price_str| {
            std.debug.print("  {s:6} : ${s}\n", .{ coin, price_str });
        }
    }

    std.debug.print("\n", .{});

    // ========================================================================
    // 4. Get L2 Orderbook
    // ========================================================================
    std.debug.print("4️⃣  Fetching ETH L2 orderbook...\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    const l2book = try info_api.getL2Book("ETH");
    defer l2book.deinit();

    std.debug.print("\n📖 ETH Orderbook:\n", .{});
    std.debug.print("  Coin: {s}\n", .{l2book.value.coin});
    std.debug.print("  Time: {}\n", .{l2book.value.time});
    std.debug.print("  Levels: {} bids, {} asks\n\n", .{
        l2book.value.levels[0].len,
        l2book.value.levels[1].len,
    });

    // Show top 5 bids and asks
    std.debug.print("  Top 5 Bids:\n", .{});
    const bid_count = @min(5, l2book.value.levels[0].len);
    for (l2book.value.levels[0][0..bid_count], 0..) |level, i| {
        std.debug.print("    {d}. ${s:12} x {s:8} ETH ({} orders)\n", .{
            i + 1,
            level.px,
            level.sz,
            level.n,
        });
    }

    std.debug.print("\n  Top 5 Asks:\n", .{});
    const ask_count = @min(5, l2book.value.levels[1].len);
    for (l2book.value.levels[1][0..ask_count], 0..) |level, i| {
        std.debug.print("    {d}. ${s:12} x {s:8} ETH ({} orders)\n", .{
            i + 1,
            level.px,
            level.sz,
            level.n,
        });
    }

    // Calculate spread
    if (l2book.value.levels[0].len > 0 and l2book.value.levels[1].len > 0) {
        const best_bid_str = l2book.value.levels[0][0].px;
        const best_ask_str = l2book.value.levels[1][0].px;
        const best_bid = try Decimal.fromString(best_bid_str);
        const best_ask = try Decimal.fromString(best_ask_str);
        const spread = best_ask.sub(best_bid);
        const hundred = try Decimal.fromString("100");
        const spread_pct = (try spread.div(best_bid)).mul(hundred);

        const spread_str = try spread.toString(allocator);
        defer allocator.free(spread_str);
        const spread_pct_str = try spread_pct.toString(allocator);
        defer allocator.free(spread_pct_str);

        std.debug.print("\n  Spread: ${s} ({s}%)\n", .{ spread_str, spread_pct_str });
    }

    std.debug.print("\n", .{});

    // ========================================================================
    // 5. Complete
    // ========================================================================
    std.debug.print("\n╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                   Example Complete!                      ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════╝\n\n", .{});
}
