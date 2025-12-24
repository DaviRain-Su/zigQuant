const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Logger 彩色输出示例 ===\n\n", .{});

    // 示例 5a: 彩色输出（默认启用）
    std.debug.print("示例 5a: 彩色控制台输出\n", .{});
    {
        const ConsoleWriterType = zigQuant.ConsoleWriter(std.fs.File);
        var console = ConsoleWriterType.init(allocator, std.fs.File.stderr());
        defer console.deinit();

        var log = zigQuant.Logger.init(allocator, console.writer(), .trace);
        defer log.deinit();

        try log.trace("Trace message - 灰色", .{ .level = "trace" });
        try log.debug("Debug message - 青色", .{ .level = "debug" });
        try log.info("Info message - 绿色", .{ .level = "info" });
        try log.warn("Warning message - 黄色", .{ .level = "warn" });
        try log.err("Error message - 红色", .{ .level = "error" });
        try log.fatal("Fatal message - 粗体红色", .{ .level = "fatal" });
    }

    std.debug.print("\n示例 5b: 禁用彩色输出\n", .{});
    {
        const ConsoleWriterType = zigQuant.ConsoleWriter(std.fs.File);
        var console = ConsoleWriterType.initWithColors(allocator, std.fs.File.stderr(), false);
        defer console.deinit();

        var log = zigQuant.Logger.init(allocator, console.writer(), .trace);
        defer log.deinit();

        try log.trace("Trace message - 无颜色", .{});
        try log.debug("Debug message - 无颜色", .{});
        try log.info("Info message - 无颜色", .{});
        try log.warn("Warning message - 无颜色", .{});
        try log.err("Error message - 无颜色", .{});
        try log.fatal("Fatal message - 无颜色", .{});
    }

    std.debug.print("\n示例 5c: 实际使用场景 - 交易系统日志\n", .{});
    {
        const ConsoleWriterType = zigQuant.ConsoleWriter(std.fs.File);
        var console = ConsoleWriterType.init(allocator, std.fs.File.stderr());
        defer console.deinit();

        var log = zigQuant.Logger.init(allocator, console.writer(), .debug);
        defer log.deinit();

        // 模拟交易系统日志
        try log.info("Trading system started", .{
            .version = "0.1.0",
            .exchange = "Binance",
        });

        try log.debug("Market data received", .{
            .symbol = "BTC/USDT",
            .price = 50000.0,
            .volume = 1234.5,
        });

        try log.info("Order placed", .{
            .order_id = "ORD12345",
            .side = "buy",
            .price = 49950.0,
            .quantity = 0.5,
        });

        try log.warn("Low balance warning", .{
            .available = 1000.0,
            .required = 25000.0,
        });

        try log.err("Order execution failed", .{
            .order_id = "ORD12345",
            .reason = "Insufficient funds",
        });

        try log.info("Trading system shutdown", .{
            .uptime_seconds = 3600,
        });
    }

    std.debug.print("\n示例 5d: 彩色方案说明\n", .{});
    std.debug.print("TRACE: 灰色 (BRIGHT_BLACK) - 详细跟踪信息\n", .{});
    std.debug.print("DEBUG: 青色 (CYAN) - 调试信息\n", .{});
    std.debug.print("INFO:  绿色 (GREEN) - 正常信息\n", .{});
    std.debug.print("WARN:  黄色 (YELLOW) - 警告信息\n", .{});
    std.debug.print("ERROR: 红色 (RED) - 错误信息\n", .{});
    std.debug.print("FATAL: 粗体红色 (BOLD + BRIGHT_RED) - 严重错误\n", .{});

    std.debug.print("\n=== 示例完成 ===\n", .{});
}
