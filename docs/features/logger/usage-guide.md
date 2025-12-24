# Logger 正确使用方法 (Zig 0.15)

## ✅ 正确的 stdout/stderr 使用方式

### 错误示例 ❌

```zig
// 这在 Zig 0.15.2 中不存在！
var console = logger.ConsoleWriter.init(std.io.getStdErr().writer().any());
var json = logger.JSONWriter.init(std.io.getStdOut().writer().any());
```

**问题**: `std.io.getStdOut()` 和 `std.io.getStdErr()` 在 Zig 0.15.2 中不存在。

---

### 正确示例 ✅

#### 1. Console Writer (输出到 stderr，带彩色 - 默认)

```zig
const std = @import("std");
const logger = @import("core/logger.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 初始化 ConsoleWriter（泛型，默认启用彩色）
    const stderr_file = std.fs.File.stderr();
    var console = logger.ConsoleWriter(std.fs.File).init(gpa.allocator(), stderr_file);
    defer console.deinit();

    // 创建 Logger
    var log = logger.Logger.init(gpa.allocator(), console.writer(), .info);
    defer log.deinit();

    // 使用（彩色输出）
    try log.trace("Trace message", .{});       // 灰色
    try log.debug("Debug message", .{});       // 青色
    try log.info("Application started", .{});  // 绿色
    try log.warn("Warning", .{ .code = 123 }); // 黄色
    try log.err("Error occurred", .{});        // 红色
    try log.fatal("Fatal error", .{});         // 粗体红色
}
```

#### 1b. Console Writer (禁用彩色)

```zig
// 在 CI 环境或输出到文件时禁用颜色
const stderr_file = std.fs.File.stderr();
var console = logger.ConsoleWriter(std.fs.File).initWithColors(
    gpa.allocator(),
    stderr_file,
    false  // 禁用颜色
);
defer console.deinit();

var log = logger.Logger.init(gpa.allocator(), console.writer(), .info);
defer log.deinit();

try log.info("No colors", .{});  // 纯文本
```

#### 1c. Console Writer (条件启用彩色)

```zig
// 根据环境变量或是否为 TTY 决定是否启用彩色
const is_tty = std.io.tty.detectConfig(std.fs.File.stderr());
const use_colors = is_tty != .no_color;

const stderr_file = std.fs.File.stderr();
var console = logger.ConsoleWriter(std.fs.File).initWithColors(
    gpa.allocator(),
    stderr_file,
    use_colors
);
defer console.deinit();
```

#### 2. JSON Writer (输出到 stdout)

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 初始化 JSONWriter（泛型）
    const stdout_file = std.fs.File.stdout();
    var json = logger.JSONWriter(std.fs.File).init(gpa.allocator(), stdout_file);

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

#### 3. StdLogWriter 桥接（带彩色）

```zig
var logger_instance: logger.Logger = undefined;

pub const std_options = .{
    .logFn = logger.StdLogWriter.logFn,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 创建带彩色的 Console Writer
    const stderr_file = std.fs.File.stderr();
    var console = logger.ConsoleWriter(std.fs.File).init(gpa.allocator(), stderr_file);
    logger_instance = logger.Logger.init(gpa.allocator(), console.writer(), .debug);
    defer logger_instance.deinit();

    // 设置全局 logger
    logger.StdLogWriter.setLogger(&logger_instance);

    // 使用 std.log（会路由到我们的 Logger，带彩色）
    std.log.info("Server started", .{});  // 绿色

    const db_log = std.log.scoped(.database);
    db_log.info("Connected", .{});  // 绿色，包含 scope=database
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

### 2. **使用泛型 Writer**

```zig
// ✅ 正确 - ConsoleWriter 和 JSONWriter 是泛型函数
const stderr_file = std.fs.File.stderr();
var console = logger.ConsoleWriter(std.fs.File).init(allocator, stderr_file);

const stdout_file = std.fs.File.stdout();
var json = logger.JSONWriter(std.fs.File).init(allocator, stdout_file);
```

### 3. **控制彩色输出**

```zig
const stderr_file = std.fs.File.stderr();

// ✅ 默认启用彩色
var console = logger.ConsoleWriter(std.fs.File).init(allocator, stderr_file);

// ✅ 显式控制彩色
var console_colored = logger.ConsoleWriter(std.fs.File).initWithColors(allocator, stderr_file, true);
var console_plain = logger.ConsoleWriter(std.fs.File).initWithColors(allocator, stderr_file, false);
```

**彩色方案**:
- **TRACE**: 灰色 (`BRIGHT_BLACK`) - 用于最详细的跟踪信息
- **DEBUG**: 青色 (`CYAN`) - 用于调试信息
- **INFO**: 绿色 (`GREEN`) - 用于一般信息
- **WARN**: 黄色 (`YELLOW`) - 用于警告
- **ERROR**: 红色 (`RED`) - 用于错误
- **FATAL**: 粗体红色 (`BOLD + BRIGHT_RED`) - 用于致命错误

**注意**: 整个日志行都会应用颜色（包括时间戳、消息和字段），不仅仅是级别标签。

---

## ✅ 测试代码

测试代码使用 `fixedBufferStream`：

```zig
test "Logger basic" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    // 测试中使用泛型 ConsoleWriter
    const WriterType = @TypeOf(fbs.writer());
    const ConsoleWriterType = ConsoleWriter(WriterType);
    var console = ConsoleWriterType.initWithColors(std.testing.allocator, fbs.writer(), false);
    defer console.deinit();

    var log = Logger.init(std.testing.allocator, console.writer(), .info);
    defer log.deinit();

    try log.info("Test message", .{});

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "[info]"));
}
```

---

## 📚 更新的文档

所有文档已更新为正确的使用方式：
- ✅ `docs/features/logger/README.md`
- ✅ `docs/features/logger/api.md`
- ✅ `docs/features/logger/implementation.md`

---

*Last updated: 2025-01-24*
