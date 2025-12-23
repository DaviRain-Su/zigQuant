# Logger 正确使用方法 (Zig 0.15)

## ✅ 正确的 stdout/stderr 使用方式

### 错误示例 ❌

```zig
// 这在 Zig 0.15 中不存在！
var console = logger.ConsoleWriter.init(std.io.getStdErr().writer().any());
var json = logger.JSONWriter.init(std.io.getStdOut().writer().any());
```

**问题**: `std.io.getStdOut()` 和 `std.io.getStdErr()` 在 Zig 0.15 中不存在。

---

### 正确示例 ✅

#### 1. Console Writer (输出到 stderr)

```zig
const std = @import("std");
const logger = @import("core/logger.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 创建 stderr 缓冲 writer
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

    // 初始化 ConsoleWriter
    var console = logger.ConsoleWriter.init(&stderr_writer.interface);
    defer console.deinit();

    // 创建 Logger
    var log = logger.Logger.init(gpa.allocator(), console.writer(), .info);
    defer log.deinit();

    // 使用
    try log.info("Application started", .{});
    try log.warn("Warning", .{ .code = 123 });
}
```

#### 2. JSON Writer (输出到 stdout)

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 创建 stdout 缓冲 writer
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

    // 初始化 JSONWriter
    var json = logger.JSONWriter.init(&stdout_writer.interface);

    // 创建 Logger
    var log = logger.Logger.init(gpa.allocator(), json.writer(), .info);
    defer log.deinit();

    // 使用
    try log.info("Order created", .{
        .order_id = "ORD123",
        .price = 50000.0,
    });
}
```

#### 3. StdLogWriter 桥接

```zig
var logger_instance: logger.Logger = undefined;

pub const std_options = .{
    .logFn = logger.StdLogWriter.logFn,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 创建 stderr writer
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

    var console = logger.ConsoleWriter.init(&stderr_writer.interface);
    logger_instance = logger.Logger.init(gpa.allocator(), console.writer(), .debug);
    defer logger_instance.deinit();

    // 设置全局 logger
    logger.StdLogWriter.setLogger(&logger_instance);

    // 使用 std.log（会路由到我们的 Logger）
    std.log.info("Server started", .{});

    const db_log = std.log.scoped(.database);
    db_log.info("Connected", .{});
}
```

---

## 📝 关键要点

### 1. **获取 stdout/stderr**

```zig
// ✅ 正确
const stdout = std.fs.File.stdout();
const stderr = std.fs.File.stderr();

// ❌ 错误 - 这些函数不存在
const stdout = std.io.getStdOut();
const stderr = std.io.getStdErr();
```

### 2. **创建缓冲 Writer**

```zig
// ✅ 正确 - 需要提供缓冲区
var buffer: [4096]u8 = undefined;
var writer = std.fs.File.stderr().writer(&buffer);

// 然后传递 &writer.interface
var console = logger.ConsoleWriter.init(&writer.interface);
```

### 3. **缓冲区大小建议**

- **Console/文本日志**: 4096 字节 (4KB)
- **JSON 日志**: 4096-8192 字节
- **高频日志**: 8192-16384 字节

```zig
// 根据使用场景选择缓冲区大小
var small_buffer: [4096]u8 = undefined;    // 一般用途
var large_buffer: [16384]u8 = undefined;   // 高频日志
```

---

## 🔍 为什么需要缓冲？

1. **性能优化**: 减少系统调用次数
2. **批量写入**: 多条日志可以一次性刷新
3. **Zig API 要求**: File.writer() 需要缓冲区参数

---

## ✅ 测试代码

测试代码使用 `fixedBufferStream` 可以继续使用 `.any()`：

```zig
test "Logger basic" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    // 测试中使用 .any() 是可以的
    var console = ConsoleWriter.init(fbs.writer().any());
    defer console.deinit();

    var log = Logger.init(std.testing.allocator, console.writer(), .info);
    defer log.deinit();

    try log.info("Test message", .{});
}
```

**注意**: 测试和实际使用的 writer 初始化方式不同：
- **测试**: `fbs.writer().any()` ✅
- **实际**: `&stderr_writer.interface` ✅

---

## 📚 更新的文档

所有文档已更新为正确的使用方式：
- ✅ `docs/features/logger/README.md`
- ✅ `docs/features/logger/api.md`
- ✅ `docs/features/logger/implementation.md`

---

*Last updated: 2025-01-23*
