//! Hyperliquid WebSocket Integration Test
//!
//! This test demonstrates how to use the WebSocket client to connect
//! to Hyperliquid and subscribe to market data.
//!
//! NOTE: This requires network access and will connect to the real API.
//! Run with: zig build test-integration

const std = @import("std");
const zigQuant = @import("zigQuant");

const HyperliquidWS = zigQuant.hyperliquid.HyperliquidWS;
const Subscription = zigQuant.hyperliquid.Subscription;
const Channel = zigQuant.hyperliquid.Channel;
const Message = zigQuant.hyperliquid.Message;
const Logger = zigQuant.Logger;

// Dummy log writer for integration test
const DummyWriter = struct {
    fn write(_: *anyopaque, record: @import("zigQuant").logger.LogRecord) anyerror!void {
        // Print to stderr for visibility
        const level_str = switch (record.level) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };

        // Print message
        std.debug.print("[{s}] {s}", .{ level_str, record.message });

        // Print fields if any
        if (record.fields.len > 0) {
            std.debug.print(" |", .{});
            for (record.fields) |field| {
                std.debug.print(" {s}=", .{field.key});
                // Print field value based on type
                switch (field.value) {
                    .string => |s| std.debug.print("{s}", .{s}),
                    .int => |i| std.debug.print("{}", .{i}),
                    .uint => |u| std.debug.print("{}", .{u}),
                    .float => |f| std.debug.print("{d}", .{f}),
                    .bool => |b| std.debug.print("{}", .{b}),
                }
            }
        }

        std.debug.print("\n", .{});
    }
    fn flush(_: *anyopaque) anyerror!void {}
    fn close(_: *anyopaque) void {}
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger
    const dummy = struct{};
    const log_writer = @import("zigQuant").logger.LogWriter{
        .ptr = @constCast(@ptrCast(&dummy)),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };
    const logger = Logger.init(allocator, log_writer, .debug);

    // Create WebSocket client
    const config = HyperliquidWS.Config{
        .ws_url = "wss://api.hyperliquid.xyz/ws",
        .host = "api.hyperliquid.xyz",
        .port = 443,
        .path = "/ws",
        .use_tls = true,
    };

    var ws = HyperliquidWS.init(allocator, config, logger);
    defer ws.deinit();

    // Set message callback
    ws.on_message = messageCallback;

    // Connect
    std.debug.print("Connecting to Hyperliquid WebSocket...\n", .{});
    try ws.connect();

    // Subscribe to allMids
    std.debug.print("Subscribing to allMids...\n", .{});
    try ws.subscribe(.{ .channel = .allMids });

    // Subscribe to ETH L2 book
    std.debug.print("Subscribing to ETH l2Book...\n", .{});
    try ws.subscribe(.{ .channel = .l2Book, .coin = "ETH" });

    // Keep running for 30 seconds
    std.debug.print("Receiving messages for 30 seconds...\n", .{});
    std.Thread.sleep(30 * std.time.ns_per_s);

    std.debug.print("Test completed successfully!\n", .{});

    // Disable reconnection before disconnecting to avoid spurious warnings
    ws.should_reconnect.store(false, .release);

    std.debug.print("Disconnecting...\n", .{});
    ws.disconnect();
}

fn messageCallback(msg: Message) void {
    switch (msg) {
        .allMids => |data| {
            std.debug.print("Received allMids: {} markets\n", .{data.mids.len});
        },
        .l2Book => |data| {
            std.debug.print("Received l2Book for {s}: {} bids, {} asks\n", .{
                data.coin,
                data.levels.bids.len,
                data.levels.asks.len,
            });
        },
        .trades => |data| {
            std.debug.print("Received trades for {s}: {} trades\n", .{
                data.coin,
                data.trades.len,
            });
        },
        .subscriptionResponse => |data| {
            std.debug.print("Subscription {s}: {s}\n", .{ data.method, data.subscription.type });
        },
        .error_msg => |data| {
            std.debug.print("Error: {} - {s}\n", .{ data.code, data.msg });
        },
        .unknown => |data| {
            std.debug.print("Unknown message: {s}\n", .{data});
        },
        else => {
            std.debug.print("Received message: {}\n", .{msg});
        },
    }
}
