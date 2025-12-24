//! Colored Logging Example
//!
//! Demonstrates how to use colored log output:
//! - Different colors for different log levels
//! - Enable/disable colors
//! - ANSI color codes
//!
//! Run with: zig build run-example-colored-logging

const std = @import("std");
const zigQuant = @import("zigQuant");

const Logger = zigQuant.Logger;
const ConsoleWriter = zigQuant.logger.ConsoleWriter;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║          Colored Logging Example                        ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════╝\n\n", .{});

    // ========================================================================
    // 1. Create Console Writer with Colors (Default)
    // ========================================================================
    std.debug.print("1️⃣  Creating logger with colored output (default)...\n\n", .{});

    const stdout_file = std.fs.File.stdout();
    var console_writer = ConsoleWriter(std.fs.File).init(allocator, stdout_file);
    var logger = Logger.init(allocator, console_writer.writer(), .trace);
    defer logger.deinit();

    // ========================================================================
    // 2. Demonstrate All Log Levels with Colors
    // ========================================================================
    std.debug.print("2️⃣  Demonstrating all log levels with colors:\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    try logger.trace("This is a TRACE message (Gray)", .{});
    try logger.debug("This is a DEBUG message (Cyan)", .{});
    try logger.info("This is an INFO message (Green)", .{});
    try logger.warn("This is a WARN message (Yellow)", .{});
    try logger.err("This is an ERROR message (Red)", .{});
    try logger.fatal("This is a FATAL message (Bold Red)", .{});

    std.debug.print("\n", .{});

    // ========================================================================
    // 3. Structured Logging with Colors
    // ========================================================================
    std.debug.print("3️⃣  Structured logging with colors:\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    try logger.info("Order placed", .{
        .order_id = 12345,
        .symbol = "BTC-USDC",
        .price = 50000.5,
        .quantity = 0.1,
    });

    try logger.warn("High latency detected", .{
        .latency_ms = 250,
        .threshold_ms = 100,
        .exchange = "hyperliquid",
    });

    try logger.err("Connection failed", .{
        .error_code = 500,
        .endpoint = "wss://api.hyperliquid.xyz/ws",
        .retry_count = 3,
    });

    std.debug.print("\n", .{});

    // ========================================================================
    // 4. Without Colors (for comparison)
    // ========================================================================
    std.debug.print("4️⃣  Same logs without colors (for comparison):\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    // Create a new console writer with colors disabled
    var console_writer_no_color = ConsoleWriter(std.fs.File).initWithColors(allocator, stdout_file, false);
    var logger_no_color = Logger.init(allocator, console_writer_no_color.writer(), .trace);
    defer logger_no_color.deinit();

    try logger_no_color.trace("This is a TRACE message (no color)", .{});
    try logger_no_color.debug("This is a DEBUG message (no color)", .{});
    try logger_no_color.info("This is an INFO message (no color)", .{});
    try logger_no_color.warn("This is a WARN message (no color)", .{});
    try logger_no_color.err("This is an ERROR message (no color)", .{});
    try logger_no_color.fatal("This is a FATAL message (no color)", .{});

    std.debug.print("\n", .{});

    // ========================================================================
    // 5. Trading Scenario Example
    // ========================================================================
    std.debug.print("5️⃣  Trading scenario example with colored logs:\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    try logger.info("Bot started", .{
        .strategy = "market_making",
        .exchange = "hyperliquid",
    });

    try logger.debug("Fetching orderbook", .{
        .symbol = "ETH-USDC",
        .depth = 20,
    });

    try logger.info("Orderbook received", .{
        .best_bid = 3500.25,
        .best_ask = 3500.75,
        .spread = 0.5,
    });

    try logger.warn("Spread too wide", .{
        .spread = 0.5,
        .max_spread = 0.2,
        .action = "skipping",
    });

    try logger.info("Placing order", .{
        .side = "buy",
        .price = 3500.0,
        .quantity = 1.0,
    });

    try logger.err("Order rejected", .{
        .reason = "insufficient_balance",
        .required = 3500.0,
        .available = 3000.0,
    });

    try logger.info("Bot stopped", .{
        .uptime_seconds = 3600,
        .orders_placed = 42,
        .pnl = 125.5,
    });

    std.debug.print("\n╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                   Example Complete!                      ║\n", .{});
    std.debug.print("║                                                          ║\n", .{});
    std.debug.print("║  Notice how different log levels have different colors: ║\n", .{});
    std.debug.print("║  - TRACE: Gray (dim/subtle)                             ║\n", .{});
    std.debug.print("║  - DEBUG: Cyan (technical info)                         ║\n", .{});
    std.debug.print("║  - INFO:  Green (normal operations)                     ║\n", .{});
    std.debug.print("║  - WARN:  Yellow (attention needed)                     ║\n", .{});
    std.debug.print("║  - ERROR: Red (errors)                                  ║\n", .{});
    std.debug.print("║  - FATAL: Bold Red (critical failures)                  ║\n", .{});
    std.debug.print("║                                                          ║\n", .{});
    std.debug.print("║  You can disable colors by using:                       ║\n", .{});
    std.debug.print("║  ConsoleWriter.initWithColors(allocator, writer, false) ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════╝\n\n", .{});
}
