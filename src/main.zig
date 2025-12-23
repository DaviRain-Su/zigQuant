const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== zigQuant - Time Module Demo ===\n\n", .{});

    // Get current timestamp
    const now = zigQuant.Timestamp.now();
    const now_iso = try now.toISO8601(allocator);
    defer allocator.free(now_iso);
    std.debug.print("Current timestamp: {} ms ({s})\n", .{ now.millis, now_iso });

    // Parse ISO 8601
    const parsed = try zigQuant.Timestamp.fromISO8601(allocator, "2024-01-15T10:30:00.500Z");
    const parsed_iso = try parsed.toISO8601(allocator);
    defer allocator.free(parsed_iso);
    std.debug.print("Parsed '2024-01-15T10:30:00.500Z': {} ms\n", .{parsed.millis});
    std.debug.print("  Roundtrip: {s}\n\n", .{parsed_iso});

    // Duration examples
    const one_hour = zigQuant.Duration.fromHours(1);
    const one_day = zigQuant.Duration.DAY;
    std.debug.print("One hour: {} ms ({}s)\n", .{ one_hour.millis, one_hour.toSeconds() });
    std.debug.print("One day: {} ms ({}s)\n\n", .{ one_day.millis, one_day.toSeconds() });

    // K-line alignment
    const ts = try zigQuant.Timestamp.fromISO8601(allocator, "2024-01-15T10:32:45Z");
    const aligned_5m = ts.alignToKline(.@"5m");
    const aligned_iso = try aligned_5m.toISO8601(allocator);
    defer allocator.free(aligned_iso);
    std.debug.print("Original: 2024-01-15T10:32:45Z\n", .{});
    std.debug.print("Aligned to 5m: {s}\n\n", .{aligned_iso});

    // K-line intervals
    std.debug.print("K-line intervals:\n", .{});
    inline for (@typeInfo(zigQuant.KlineInterval).@"enum".fields) |field| {
        const interval = @field(zigQuant.KlineInterval, field.name);
        std.debug.print("  {s}: {} ms\n", .{ interval.toString(), interval.toMillis() });
    }

    std.debug.print("\n=== zigQuant - Error System Demo ===\n\n", .{});

    // Error wrapping
    const ctx = zigQuant.ErrorContext.initWithCode(429, "Rate limit exceeded");
    std.debug.print("ErrorContext: code={?}, message={s}\n", .{ ctx.code, ctx.message });

    // Wrapped error with chain
    const wrapped1 = zigQuant.errors.wrap(zigQuant.NetworkError.Timeout, "Network timeout");
    const wrapped2 = zigQuant.errors.wrapWithSource(zigQuant.APIError.ServerError, "API call failed", &wrapped1);
    std.debug.print("Error chain depth: {}\n", .{wrapped2.chainDepth()});

    // Print error chain to buffer
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    try wrapped2.printChain(buf.writer(allocator));
    std.debug.print("{s}", .{buf.items});

    // Retry configuration
    const retry_config = zigQuant.RetryConfig{
        .max_retries = 3,
        .strategy = .exponential_backoff,
        .initial_delay_ms = 100,
        .max_delay_ms = 5000,
    };
    std.debug.print("\nRetry delays:\n", .{});
    for (0..4) |i| {
        const delay = retry_config.calculateDelay(@intCast(i));
        std.debug.print("  Attempt {}: {} ms\n", .{ i, delay });
    }

    // Error categorization
    std.debug.print("\nError categories:\n", .{});
    std.debug.print("  ConnectionFailed: {s}\n", .{zigQuant.errors.errorCategory(zigQuant.NetworkError.ConnectionFailed)});
    std.debug.print("  RateLimitExceeded: {s}\n", .{zigQuant.errors.errorCategory(zigQuant.APIError.RateLimitExceeded)});
    std.debug.print("  ParseError: {s}\n", .{zigQuant.errors.errorCategory(zigQuant.DataError.ParseError)});

    std.debug.print("\nRetryable errors:\n", .{});
    std.debug.print("  ConnectionFailed: {}\n", .{zigQuant.errors.isRetryable(zigQuant.NetworkError.ConnectionFailed)});
    std.debug.print("  Unauthorized: {}\n", .{zigQuant.errors.isRetryable(zigQuant.APIError.Unauthorized)});

    std.debug.print("\n=== zigQuant - Logger Module Demo ===\n\n", .{});

    // Demo 1: Console Logger with structured fields
    std.debug.print("Demo 1: Console Logger (stderr)\n", .{});
    {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

        var console = zigQuant.ConsoleWriter.init(&stderr_writer.interface);
        defer console.deinit();

        var log = zigQuant.Logger.init(allocator, console.writer(), .debug);
        defer log.deinit();

        try log.debug("应用程序启动", .{ .version = "0.1.0", .pid = 12345 });
        try log.info("交易系统初始化", .{ .symbols = 5, .exchanges = 2 });
        try log.warn("API 延迟较高", .{ .latency_ms = 250, .threshold_ms = 100 });
        try log.err("订单执行失败", .{ .order_id = "ORD001", .reason = "insufficient_balance" });

        // 刷新缓冲区
        try stderr_writer.interface.flush();
    }

    // Demo 2: JSON Logger
    std.debug.print("\nDemo 2: JSON Logger (stdout)\n", .{});
    {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

        var json = zigQuant.JSONWriter.init(&stdout_writer.interface);

        var log = zigQuant.Logger.init(allocator, json.writer(), .info);
        defer log.deinit();

        try log.info("订单创建", .{
            .order_id = "ORD001",
            .symbol = "BTC/USDT",
            .side = "buy",
            .price = 50000.0,
            .quantity = 1.5,
        });

        try log.info("交易执行", .{
            .trade_id = "TRD001",
            .order_id = "ORD001",
            .executed_price = 50100.0,
            .fee = 75.15,
        });

        // 刷新缓冲区
        try stdout_writer.interface.flush();
    }

    // Demo 3: File Logger
    std.debug.print("\nDemo 3: File Logger\n", .{});
    {
        var file_writer = try zigQuant.FileWriter.init(allocator, "/tmp/zigquant_demo.log");
        defer file_writer.deinit();

        var log = zigQuant.Logger.init(allocator, file_writer.writer(), .info);
        defer log.deinit();

        try log.info("系统启动", .{
            .timestamp = std.time.timestamp(),
            .mode = "production",
        });

        try log.info("策略加载", .{
            .strategy = "momentum",
            .parameters = 5,
        });

        std.debug.print("日志已写入 /tmp/zigquant_demo.log\n", .{});
    }

    // Demo 4: Log level filtering
    std.debug.print("\nDemo 4: 日志级别过滤 (只显示 warn 及以上)\n", .{});
    {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

        var console = zigQuant.ConsoleWriter.init(&stderr_writer.interface);
        defer console.deinit();

        var log = zigQuant.Logger.init(allocator, console.writer(), .warn);
        defer log.deinit();

        try log.debug("调试信息", .{}); // 不会显示
        try log.info("普通信息", .{}); // 不会显示
        try log.warn("警告信息", .{ .code = 404 }); // 会显示
        try log.err("错误信息", .{ .error_type = "NetworkError" }); // 会显示

        // 刷新缓冲区
        try stderr_writer.interface.flush();
    }

    // Demo 5: All log levels
    std.debug.print("\nDemo 5: 所有日志级别\n", .{});
    {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

        var console = zigQuant.ConsoleWriter.init(&stderr_writer.interface);
        defer console.deinit();

        var log = zigQuant.Logger.init(allocator, console.writer(), .trace);
        defer log.deinit();

        try log.trace("追踪信息", .{ .function = "processOrder" });
        try log.debug("调试信息", .{ .variable = "price", .value = 50000 });
        try log.info("一般信息", .{ .event = "order_created" });
        try log.warn("警告信息", .{ .memory_usage = 85 });
        try log.err("错误信息", .{ .error_code = 500 });
        try log.fatal("致命错误", .{ .reason = "system_crash" });

        // 刷新缓冲区
        try stderr_writer.interface.flush();
    }

    std.debug.print("\n=== Demo Complete ===\n", .{});
}
