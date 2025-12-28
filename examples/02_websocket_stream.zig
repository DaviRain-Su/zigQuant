//! Hyperliquid WebSocket Streaming Example
//!
//! Demonstrates how to:
//! - Connect to Hyperliquid WebSocket
//! - Subscribe to market data (allMids, l2Book, trades)
//! - Handle real-time messages
//! - Gracefully disconnect
//!
//! Run with: zig build run-example-websocket

const std = @import("std");
const zigQuant = @import("zigQuant");

const HyperliquidWS = zigQuant.hyperliquid.HyperliquidWS;
const Subscription = zigQuant.hyperliquid.Subscription;
const Channel = zigQuant.hyperliquid.Channel;
const Message = zigQuant.hyperliquid.Message;
const Logger = zigQuant.Logger;

// Message counter for statistics
var message_count = std.atomic.Value(u64).init(0);
var allmids_count = std.atomic.Value(u64).init(0);
var l2book_count = std.atomic.Value(u64).init(0);
var trades_count = std.atomic.Value(u64).init(0);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║      Hyperliquid WebSocket Streaming Example            ║\n", .{});
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
    // 2. Configure WebSocket Client
    // ========================================================================
    std.debug.print("2️⃣  Configuring WebSocket client...\n", .{});

    const config = HyperliquidWS.Config{
        .ws_url = "wss://api.hyperliquid.xyz/ws",
        .host = "api.hyperliquid.xyz",
        .port = 443,
        .path = "/ws",
        .use_tls = true,
        .ping_interval_ms = 30000, // 30 seconds
        .reconnect_interval_ms = 5000, // 5 seconds
        .max_reconnect_attempts = 5,
    };

    var ws = HyperliquidWS.init(allocator, config, logger);
    defer ws.deinit();

    // Set message callback (no context needed for this example)
    ws.setMessageCallback(messageCallback, null);

    // ========================================================================
    // 3. Connect to WebSocket
    // ========================================================================
    std.debug.print("3️⃣  Connecting to Hyperliquid WebSocket...\n", .{});
    try ws.connect();
    std.debug.print("✅ Connected!\n\n", .{});

    // ========================================================================
    // 4. Subscribe to Channels
    // ========================================================================
    std.debug.print("4️⃣  Subscribing to channels...\n", .{});

    // Subscribe to all market mid prices
    std.debug.print("   • Subscribing to allMids...\n", .{});
    try ws.subscribe(.{ .channel = .allMids });

    // Subscribe to ETH L2 orderbook
    std.debug.print("   • Subscribing to ETH l2Book...\n", .{});
    try ws.subscribe(.{ .channel = .l2Book, .coin = "ETH" });

    // Subscribe to BTC trades
    std.debug.print("   • Subscribing to BTC trades...\n", .{});
    try ws.subscribe(.{ .channel = .trades, .coin = "BTC" });

    std.debug.print("✅ Subscribed to all channels!\n\n", .{});

    // ========================================================================
    // 5. Receive Messages
    // ========================================================================
    std.debug.print("5️⃣  Receiving real-time market data (30 seconds)...\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    // Run for 30 seconds
    const start_time = std.time.milliTimestamp();
    const duration_ms = 30 * 1000;

    while (std.time.milliTimestamp() - start_time < duration_ms) {
        std.Thread.sleep(1000 * std.time.ns_per_ms);

        // Print statistics every second
        const elapsed = std.time.milliTimestamp() - start_time;
        const total = message_count.load(.acquire);
        const allmids = allmids_count.load(.acquire);
        const l2book = l2book_count.load(.acquire);
        const trades = trades_count.load(.acquire);

        std.debug.print("\r[{d:2}s] Messages: {d:4} | AllMids: {d:3} | L2Book: {d:3} | Trades: {d:3}", .{
            @divTrunc(elapsed, 1000),
            total,
            allmids,
            l2book,
            trades,
        });
    }

    std.debug.print("\n\n", .{});

    // ========================================================================
    // 6. Unsubscribe and Disconnect
    // ========================================================================
    std.debug.print("6️⃣  Cleaning up...\n", .{});

    // Disable auto-reconnect before disconnecting
    ws.should_reconnect.store(false, .release);

    std.debug.print("   • Disconnecting...\n", .{});
    ws.disconnect();

    // ========================================================================
    // 7. Print Final Statistics
    // ========================================================================
    std.debug.print("\n╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                  Final Statistics                        ║\n", .{});
    std.debug.print("╠══════════════════════════════════════════════════════════╣\n", .{});

    const final_total = message_count.load(.acquire);
    const final_allmids = allmids_count.load(.acquire);
    const final_l2book = l2book_count.load(.acquire);
    const final_trades = trades_count.load(.acquire);

    std.debug.print("║  Total Messages:   {d:6}                                 ║\n", .{final_total});
    std.debug.print("║  AllMids:          {d:6}                                 ║\n", .{final_allmids});
    std.debug.print("║  L2 Book Updates:  {d:6}                                 ║\n", .{final_l2book});
    std.debug.print("║  Trades:           {d:6}                                 ║\n", .{final_trades});
    std.debug.print("╚══════════════════════════════════════════════════════════╝\n\n", .{});

    std.debug.print("✅ Example completed successfully!\n\n", .{});
}

/// Message callback - called for each WebSocket message
fn messageCallback(ctx: ?*anyopaque, msg: Message) void {
    _ = ctx; // Not used in this example

    _ = message_count.fetchAdd(1, .monotonic);

    switch (msg) {
        .allMids => |data| {
            _ = allmids_count.fetchAdd(1, .monotonic);
            // Uncomment to see details:
            // std.debug.print("\n📊 AllMids: {} markets\n", .{data.mids.len});
            _ = data;
        },
        .l2Book => |data| {
            _ = l2book_count.fetchAdd(1, .monotonic);
            // Uncomment to see details:
            // std.debug.print("\n📖 L2Book [{s}]: {} bids, {} asks\n", .{
            //     data.coin,
            //     data.levels.bids.len,
            //     data.levels.asks.len,
            // });
            _ = data;
        },
        .trades => |data| {
            _ = trades_count.fetchAdd(1, .monotonic);
            // Uncomment to see details:
            // std.debug.print("\n💱 Trades [{s}]: {} trades\n", .{
            //     data.coin,
            //     data.trades.len,
            // });
            _ = data;
        },
        .subscriptionResponse => |data| {
            std.debug.print("\n✅ Subscription {s}: {s}\n", .{ data.method, data.subscription.type });
        },
        .error_msg => |data| {
            std.debug.print("\n❌ Error {}: {s}\n", .{ data.code, data.msg });
        },
        else => {
            // Other message types
        },
    }
}
