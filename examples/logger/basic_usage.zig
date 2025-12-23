const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Logger 基本使用示例 ===\n\n", .{});

    // 示例 1: Console Writer (输出到 stderr)
    std.debug.print("示例 1: Console Writer\n", .{});
    {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

        var console = zigQuant.ConsoleWriter.init(&stderr_writer.interface);
        defer console.deinit();

        var log = zigQuant.Logger.init(allocator, console.writer(), .debug);
        defer log.deinit();

        try log.debug("调试信息", .{ .user_id = 123 });
        try log.info("应用启动", .{ .version = "0.1.0" });
        try log.warn("警告信息", .{ .code = 404 });
        try log.err("错误发生", .{ .error_type = "NetworkError" });
    }

    std.debug.print("\n示例 2: JSON Writer (输出到 stdout)\n", .{});
    {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

        var json = zigQuant.JSONWriter.init(&stdout_writer.interface);

        var log = zigQuant.Logger.init(allocator, json.writer(), .info);
        defer log.deinit();

        try log.info("订单创建", .{
            .order_id = "ORD001",
            .symbol = "BTC/USDT",
            .price = 50000.0,
            .quantity = 1.5,
        });

        try log.info("交易执行", .{
            .trade_id = "TRD001",
            .side = "buy",
            .executed_price = 50100.0,
        });
    }

    std.debug.print("\n示例 3: File Writer\n", .{});
    {
        var file_writer = try zigQuant.FileWriter.init(allocator, "/tmp/zigquant.log");
        defer file_writer.deinit();

        var log = zigQuant.Logger.init(allocator, file_writer.writer(), .info);
        defer log.deinit();

        try log.info("文件日志测试", .{
            .timestamp = std.time.timestamp(),
            .message = "This is written to file",
        });

        std.debug.print("日志已写入 /tmp/zigquant.log\n", .{});
    }

    std.debug.print("\n示例 4: 日志级别过滤\n", .{});
    {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

        var console = zigQuant.ConsoleWriter.init(&stderr_writer.interface);
        defer console.deinit();

        // 设置最低级别为 warn，debug 和 info 会被过滤
        var log = zigQuant.Logger.init(allocator, console.writer(), .warn);
        defer log.deinit();

        try log.debug("不会显示", .{});
        try log.info("不会显示", .{});
        try log.warn("会显示", .{});
        try log.err("会显示", .{});
    }

    std.debug.print("\n=== 示例完成 ===\n", .{});
}
