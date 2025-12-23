# Logger - 测试文档

> 测试覆盖、测试策略和基准测试

**最后更新**: 2025-01-22

---

## 单元测试

```zig
test "Level ordering" {
    try std.testing.expect(Level.trace.toInt() < Level.debug.toInt());
    try std.testing.expect(Level.debug.toInt() < Level.info.toInt());
    try std.testing.expect(Level.info.toInt() < Level.warn.toInt());
}

test "Level toString" {
    try std.testing.expectEqualStrings("info", Level.info.toString());
    try std.testing.expectEqualStrings("error", Level.err.toString());
}

test "Logger filters by level" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var console = ConsoleWriter.init(buffer.writer());
    var log = Logger.init(std.testing.allocator, console.writer(), .warn);

    try log.debug("Should not appear", .{});
    try log.info("Should not appear", .{});
    try log.warn("Should appear", .{});

    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Should appear") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Should not appear") == null);
}

test "Logger with fields" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var console = ConsoleWriter.init(buffer.writer());
    var log = Logger.init(std.testing.allocator, console.writer(), .info);

    try log.info("Test", .{
        .int_field = @as(i64, 123),
        .str_field = "hello",
        .bool_field = true,
    });

    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "int_field=123") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "str_field=hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bool_field=true") != null);
}

test "JSONWriter format" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var json = JSONWriter.init(buffer.writer());
    var log = Logger.init(std.testing.allocator, json.writer(), .info);

    try log.info("Test message", .{ .key = "value" });

    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "\"level\":\"info\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"msg\":\"Test message\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"key\":\"value\"") != null);
}

test "FileWriter creates file" {
    const allocator = std.testing.allocator;
    const test_file = "test_log.txt";
    defer std.fs.cwd().deleteFile(test_file) catch {};

    var file_writer = try FileWriter.init(allocator, test_file);
    defer file_writer.deinit();

    var log = Logger.init(allocator, file_writer.writer(), .info);
    defer log.deinit();

    try log.info("Test log", .{});

    const file = try std.fs.cwd().openFile(test_file, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "Test log") != null);
}

test "RotatingFileWriter rotates" {
    const allocator = std.testing.allocator;
    const test_file = "test_rotating.log";
    defer std.fs.cwd().deleteFile(test_file) catch {};
    defer std.fs.cwd().deleteFile("test_rotating.log.1") catch {};

    var rotating = try RotatingFileWriter.init(
        allocator,
        test_file,
        .{
            .max_size = 100,  // 小尺寸用于测试
            .max_backups = 2,
        },
    );
    defer rotating.deinit();

    var log = Logger.init(allocator, rotating.writer(), .info);
    defer log.deinit();

    // 写入足够多的日志触发轮转
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try log.info("Log message to trigger rotation", .{});
    }

    // 验证备份文件存在
    const backup = std.fs.cwd().openFile("test_rotating.log.1", .{}) catch null;
    try std.testing.expect(backup != null);
    if (backup) |f| f.close();
}
```

---

## 基准测试

```zig
pub fn benchmarkConsoleLogger() !void {
    const allocator = std.heap.page_allocator;
    const iterations = 100_000;

    var null_writer = std.io.null_writer;
    var console = ConsoleWriter.init(null_writer);
    var log = Logger.init(allocator, console.writer(), .info);
    defer log.deinit();

    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        try log.info("Test message", .{ .iteration = i });
    }

    const end = std.time.nanoTimestamp();
    const elapsed_s = @as(f64, @floatFromInt(end - start)) / std.time.ns_per_s;
    const logs_per_sec = @as(f64, @floatFromInt(iterations)) / elapsed_s;

    std.debug.print("Console Logger: {d:.0} logs/sec\n", .{logs_per_sec});
}

pub fn benchmarkJSONLogger() !void {
    const allocator = std.heap.page_allocator;
    const iterations = 100_000;

    var null_writer = std.io.null_writer;
    var json = JSONWriter.init(null_writer);
    var log = Logger.init(allocator, json.writer(), .info);
    defer log.deinit();

    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        try log.info("Test message", .{
            .iteration = i,
            .value = 123.45,
        });
    }

    const end = std.time.nanoTimestamp();
    const elapsed_s = @as(f64, @floatFromInt(end - start)) / std.time.ns_per_s;
    const logs_per_sec = @as(f64, @floatFromInt(iterations)) / elapsed_s;

    std.debug.print("JSON Logger: {d:.0} logs/sec\n", .{logs_per_sec});
}

pub fn benchmarkLevelFiltering() !void {
    const allocator = std.heap.page_allocator;
    const iterations = 1_000_000;

    var null_writer = std.io.null_writer;
    var console = ConsoleWriter.init(null_writer);
    var log = Logger.init(allocator, console.writer(), .warn);  // 过滤 debug
    defer log.deinit();

    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        try log.debug("Filtered message", .{});  // 应该被快速跳过
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = end - start;
    const ns_per_log = @divFloor(elapsed_ns, iterations);

    std.debug.print("Level filtering: {} ns/log\n", .{ns_per_log});
}
```

### 预期性能指标

| 操作 | 目标性能 |
|------|---------|
| Console Logger | >100K logs/sec |
| File Logger | >50K logs/sec |
| JSON Logger | >30K logs/sec |
| 级别过滤 | <10 ns/log |

---

## 测试运行

```bash
# 运行所有测试
zig test src/core/logger.zig

# 运行基准测试
zig build bench-logger
```

---

*Last updated: 2025-01-22*
