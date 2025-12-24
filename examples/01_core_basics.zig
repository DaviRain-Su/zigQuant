//! Core Modules Example
//!
//! Demonstrates how to use core modules:
//! - Logger (console, file, JSON output)
//! - Decimal (high-precision arithmetic)
//! - Time (timestamps, durations, intervals)
//!
//! Run with: zig build run-example-core

const std = @import("std");
const zigQuant = @import("zigQuant");

const Logger = zigQuant.Logger;
const Decimal = zigQuant.Decimal;
const Timestamp = zigQuant.Timestamp;
const Duration = zigQuant.Duration;
const KlineInterval = zigQuant.KlineInterval;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║           zigQuant Core Modules Example                 ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════╝\n\n", .{});

    // ========================================================================
    // 1. Logger Example
    // ========================================================================
    std.debug.print("1️⃣  Logger Example\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    // Create a simple logger using debug print
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

    var logger = Logger.init(allocator, log_writer, .debug);

    // Log messages at different levels
    try logger.debug("This is a debug message", .{});
    try logger.info("Application started", .{ .version = "1.0.0" });
    try logger.warn("This is a warning", .{ .code = 1001 });
    try logger.err("An error occurred", .{ .error_code = 500, .message = "Connection failed" });

    std.debug.print("\n", .{});

    // ========================================================================
    // 2. Decimal Arithmetic Example
    // ========================================================================
    std.debug.print("2️⃣  Decimal Arithmetic Example\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    // Create decimals from strings (18 decimal precision)
    const price = try Decimal.fromString("50000.25"); // BTC price
    const quantity = try Decimal.fromString("0.5"); // 0.5 BTC
    const fee_rate = try Decimal.fromString("0.001"); // 0.1% fee

    {
        const price_str = try price.toString(allocator);
        defer allocator.free(price_str);
        std.debug.print("Price:    {s}\n", .{price_str});
    }
    {
        const quantity_str = try quantity.toString(allocator);
        defer allocator.free(quantity_str);
        std.debug.print("Quantity: {s}\n", .{quantity_str});
    }
    {
        const fee_rate_str = try fee_rate.toString(allocator);
        defer allocator.free(fee_rate_str);
        std.debug.print("Fee Rate: {s}\n", .{fee_rate_str});
    }
    std.debug.print("\n", .{});

    // Calculate total value
    const total = price.mul(quantity);
    {
        const total_str = try total.toString(allocator);
        defer allocator.free(total_str);
        std.debug.print("Total Value: {s} USDC\n", .{total_str});
    }

    // Calculate fee
    const fee = total.mul(fee_rate);
    {
        const fee_str = try fee.toString(allocator);
        defer allocator.free(fee_str);
        std.debug.print("Fee:         {s} USDC\n", .{fee_str});
    }

    // Calculate final amount
    const final_amount = total.sub(fee);
    {
        const final_str = try final_amount.toString(allocator);
        defer allocator.free(final_str);
        std.debug.print("Final:       {s} USDC\n", .{final_str});
    }

    std.debug.print("\n", .{});

    // Comparison operations
    const price2 = try Decimal.fromString("51000.00");
    std.debug.print("Price comparison:\n", .{});
    {
        const price2_str = try price2.toString(allocator);
        defer allocator.free(price2_str);
        const price_str = try price.toString(allocator);
        defer allocator.free(price_str);
        std.debug.print("  {s} > {s}? {}\n", .{ price2_str, price_str, price2.cmp(price) == .gt });
    }
    {
        const price_str = try price.toString(allocator);
        defer allocator.free(price_str);
        const price2_str = try price2.toString(allocator);
        defer allocator.free(price2_str);
        std.debug.print("  {s} < {s}? {}\n", .{ price_str, price2_str, price.cmp(price2) == .lt });
    }

    std.debug.print("\n", .{});

    // ========================================================================
    // 3. Time and Timestamp Example
    // ========================================================================
    std.debug.print("3️⃣  Time and Timestamp Example\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    // Get current timestamp
    const now = Timestamp.now();
    std.debug.print("Current timestamp: {} ms\n", .{now.millis});
    {
        const iso_str = try now.toISO8601(allocator);
        defer allocator.free(iso_str);
        std.debug.print("ISO 8601: {s}\n", .{iso_str});
    }

    // Create duration
    const one_hour = Duration.fromHours(1);
    const one_day = Duration.fromDays(1);
    std.debug.print("\nDurations:\n", .{});
    std.debug.print("  1 hour = {} ms\n", .{one_hour.millis});
    std.debug.print("  1 day  = {} ms\n", .{one_day.millis});

    // Timestamp arithmetic
    const tomorrow = now.add(one_day);
    std.debug.print("\nTimestamp arithmetic:\n", .{});
    std.debug.print("  Now:      {}\n", .{now.millis});
    std.debug.print("  Tomorrow: {}\n", .{tomorrow.millis});

    // Kline intervals
    std.debug.print("\nKline Intervals:\n", .{});
    std.debug.print("  1 minute:  {} ms\n", .{KlineInterval.@"1m".toMillis()});
    std.debug.print("  5 minutes: {} ms\n", .{KlineInterval.@"5m".toMillis()});
    std.debug.print("  1 hour:    {} ms\n", .{KlineInterval.@"1h".toMillis()});
    std.debug.print("  1 day:     {} ms\n", .{KlineInterval.@"1d".toMillis()});

    std.debug.print("\n", .{});

    // ========================================================================
    // 4. Error Handling Example
    // ========================================================================
    std.debug.print("4️⃣  Error Handling Example\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    // Demonstrate error context
    const ctx = zigQuant.ErrorContext.init(
        "Failed to submit order due to insufficient balance",
    );

    std.debug.print("Error Context:\n", .{});
    std.debug.print("  Message:   {s}\n", .{ctx.message});
    std.debug.print("  Timestamp: {}\n", .{ctx.timestamp});

    // Demonstrate error wrapping
    const network_err = zigQuant.NetworkError.ConnectionFailed;
    std.debug.print("\nError Type: {}\n", .{network_err});

    std.debug.print("\n╔══════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                    Example Complete!                     ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════╝\n\n", .{});
}
