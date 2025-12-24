# Logger - API 参考

> 完整的 API 文档和使用示例

**最后更新**: 2025-12-24

---

## Level

日志级别枚举

```zig
pub const Level = enum {
    trace,   // 0 - 最详细
    debug,   // 1 - 调试
    info,    // 2 - 信息
    warn,    // 3 - 警告
    err,     // 4 - 错误
    fatal,   // 5 - 致命
};
```

### `toInt() u8`

转换为整数值

```zig
const level = Level.info;
const num = level.toInt();  // 2
```

### `toString() []const u8`

转换为字符串

```zig
const level = Level.warn;
const str = level.toString();  // "warn"
```

---

## Logger

主日志记录器

```zig
pub const Logger = struct {
    allocator: Allocator,
    writer: LogWriter,
    min_level: Level,
};
```

### `init(allocator, writer, min_level) Logger`

创建 Logger

```zig
const stdout_file = std.fs.File.stdout();
var console = ConsoleWriter(std.fs.File).init(allocator, stdout_file);
var log = Logger.init(allocator, console.writer(), .info);
defer log.deinit();
```

### `log(level, msg, fields) !void`

记录日志（支持双模式）

**自动检测模式**：
- **结构化模式**：当 `fields` 为 struct 时（非 tuple），使用键值对结构化日志
- **Printf 模式**：当 `fields` 为 tuple 时，使用 printf 风格格式化

```zig
// 结构化模式（推荐用于业务日志）
try log.log(.info, "User login", .{
    .user_id = 12345,
    .ip = "192.168.1.1",
});
// 输出: [info] 1737541845000 User login user_id=12345 ip=192.168.1.1

// Printf 模式（推荐用于快速调试）
try log.log(.info, "User {} logged in from {s}", .{12345, "192.168.1.1"});
// 输出: [info] 1737541845000 User 12345 logged in from 192.168.1.1
```

**模式检测规则**：
- Tuple（`.{value1, value2}`）→ Printf 模式
- Struct（`.{.key1 = value1, .key2 = value2}`）→ 结构化模式
- 空 tuple（`.{}`）→ 无参数

### 便捷方法

所有便捷方法都支持双模式（结构化 / Printf）

```zig
// trace 级别
try log.trace("Trace message", .{});                          // 无参数
try log.trace("Value: {}", .{42});                            // Printf 模式

// debug 级别
try log.debug("Debug message", .{ .var1 = value1 });          // 结构化模式
try log.debug("Debug value: {}", .{value1});                  // Printf 模式

// info 级别
try log.info("Info message", .{ .key = "value" });            // 结构化模式
try log.info("User {} logged in", .{user_id});                // Printf 模式

// warn 级别
try log.warn("Warning", .{ .code = 123 });                    // 结构化模式
try log.warn("Warning: code={}", .{123});                     // Printf 模式

// error 级别
try log.err("Error occurred", .{ .error = err });             // 结构化模式
try log.err("Error: {s}", .{@errorName(err)});                // Printf 模式

// fatal 级别
try log.fatal("Fatal error", .{ .reason = "crash" });         // 结构化模式
try log.fatal("Fatal: {s}", .{"crash"});                      // Printf 模式
```

---

## 双模式日志详解

Logger 支持两种日志模式，自动检测参数类型：

### 1. 结构化模式（Structured Logging）

**使用场景**：
- 业务日志：订单、交易、用户操作
- 需要后续查询和分析的日志
- 需要字段名明确语义的场景

**语法**：使用命名字段的 struct
```zig
try log.info("Order created", .{
    .order_id = "ORD123",
    .user_id = 456,
    .price = 99.99,
    .status = "pending",
});
// 输出: [info] 1737541845000 Order created order_id=ORD123 user_id=456 price=99.99 status=pending
```

**优势**：
- 字段名清晰，易于查询和过滤
- 适合结构化日志系统（如 ELK、Splunk）
- 支持 JSON 格式输出

### 2. Printf 模式（Format String）

**使用场景**：
- 快速调试
- 简单的日志消息
- 临时跟踪代码执行

**语法**：使用匿名字段的 tuple
```zig
try log.info("User {} logged in from {s}", .{user_id, ip_address});
// 输出: [info] 1737541845000 User 456 logged in from 192.168.1.1
```

**优势**：
- 语法简洁，类似 printf
- 适合快速调试
- 减少代码冗余

### 3. 模式选择指南

| 场景 | 推荐模式 | 示例 |
|------|---------|------|
| 业务日志 | 结构化 | `.{.order_id = "123", .amount = 100.0}` |
| 性能监控 | 结构化 | `.{.operation = "query", .elapsed_ms = 42}` |
| 快速调试 | Printf | `.{user_id, status}` |
| 简单消息 | Printf | `.{"Server started on port {}", .{8080}}` |
| 错误跟踪 | 结构化 | `.{.error = err, .context = "db_query"}` |

### 4. 技术实现

Logger 在编译时检测 `fields` 参数类型：
```zig
// 实现原理（src/core/logger.zig: 150-174）
const FieldsType = @TypeOf(fields);
const fields_info = @typeInfo(FieldsType);

if (fields_info == .@"struct" and fields_info.@"struct".is_tuple) {
    // Printf 模式：使用 std.fmt.allocPrint 格式化消息
    formatted_msg = try std.fmt.allocPrint(allocator, msg, fields);
} else {
    // 结构化模式：保持消息不变，转换字段为 Field 数组
    formatted_msg = try allocator.dupe(u8, msg);
}
```

### 5. 混合使用示例

```zig
pub fn processOrder(log: *Logger, order: Order) !void {
    // Printf 模式：快速记录开始
    try log.debug("Processing order {s}", .{order.id});

    // 结构化模式：记录详细信息
    try log.info("Order details", .{
        .order_id = order.id,
        .symbol = order.symbol,
        .quantity = order.quantity,
        .price = order.price,
    });

    const result = executeOrder(order) catch |err| {
        // 结构化模式：记录错误
        try log.err("Order execution failed", .{
            .order_id = order.id,
            .error = @errorName(err),
        });
        return err;
    };

    // Printf 模式：快速记录完成
    try log.debug("Order {s} completed", .{order.id});
}
```

---

## AnsiColors

ANSI 颜色代码，用于终端彩色输出

```zig
pub const AnsiColors = struct {
    // 重置
    pub const RESET = "\x1b[0m";

    // 前景色
    pub const BLACK = "\x1b[30m";
    pub const RED = "\x1b[31m";
    pub const GREEN = "\x1b[32m";
    pub const YELLOW = "\x1b[33m";
    pub const BLUE = "\x1b[34m";
    pub const MAGENTA = "\x1b[35m";
    pub const CYAN = "\x1b[36m";
    pub const WHITE = "\x1b[37m";

    // 亮色前景色
    pub const BRIGHT_BLACK = "\x1b[90m";   // 灰色
    pub const BRIGHT_RED = "\x1b[91m";
    pub const BRIGHT_GREEN = "\x1b[92m";
    pub const BRIGHT_YELLOW = "\x1b[93m";
    pub const BRIGHT_BLUE = "\x1b[94m";
    pub const BRIGHT_MAGENTA = "\x1b[95m";
    pub const BRIGHT_CYAN = "\x1b[96m";
    pub const BRIGHT_WHITE = "\x1b[97m";

    // 样式
    pub const BOLD = "\x1b[1m";
    pub const DIM = "\x1b[2m";
};
```

### `forLevel(level) []const u8`

获取日志级别对应的颜色代码

```zig
const color = AnsiColors.forLevel(.info);  // 返回 GREEN
const color = AnsiColors.forLevel(.err);   // 返回 RED
```

### 颜色映射

| 级别 | 颜色 | ANSI 代码 |
|------|------|-----------|
| TRACE | 灰色 | `BRIGHT_BLACK` |
| DEBUG | 青色 | `CYAN` |
| INFO | 绿色 | `GREEN` |
| WARN | 黄色 | `YELLOW` |
| ERROR | 红色 | `RED` |
| FATAL | 粗体红色 | `BOLD + BRIGHT_RED` |

---

## ConsoleWriter

控制台输出（支持彩色）

**注意**: ConsoleWriter 是泛型函数，需要指定底层 Writer 类型。

```zig
pub fn ConsoleWriter(comptime WriterType: type) type {
    return struct {
        underlying_writer: WriterType,
        allocator: Allocator,
        mutex: std.Thread.Mutex,
        use_colors: bool,  // 默认 true

        pub fn init(allocator: Allocator, underlying: WriterType) Self;
        pub fn initWithColors(allocator: Allocator, underlying: WriterType, use_colors: bool) Self;
        pub fn deinit(self: *Self) void;
        pub fn writer(self: *Self) LogWriter;
    };
}
```

### `init(allocator, underlying) Self`

创建 ConsoleWriter，默认启用彩色输出

```zig
const stdout_file = std.fs.File.stdout();
var console = ConsoleWriter(std.fs.File).init(allocator, stdout_file);
defer console.deinit();

var log = Logger.init(allocator, console.writer(), .info);
try log.info("Colored output", .{});  // 绿色输出
// 输出: [info] 1737541845000 Colored output (整行绿色)
```

### `initWithColors(allocator, underlying, use_colors) Self`

创建 ConsoleWriter，显式控制是否启用彩色

```zig
const stderr_file = std.fs.File.stderr();

// 启用彩色
var console_colored = ConsoleWriter(std.fs.File).initWithColors(allocator, stderr_file, true);
defer console_colored.deinit();

// 禁用彩色（用于 CI 环境或重定向到文件）
var console_plain = ConsoleWriter(std.fs.File).initWithColors(allocator, stderr_file, false);
defer console_plain.deinit();

var log = Logger.init(allocator, console_plain.writer(), .info);
try log.info("Plain text", .{});  // 无颜色
// 输出: [info] 1737541845000 Plain text
```

### 示例：测试中使用 FixedBufferStream

```zig
test "ConsoleWriter with buffer" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const WriterType = @TypeOf(fbs.writer());
    var console = ConsoleWriter(WriterType).initWithColors(
        std.testing.allocator,
        fbs.writer(),
        false  // 测试中禁用颜色
    );
    defer console.deinit();

    var log = Logger.init(std.testing.allocator, console.writer(), .info);
    defer log.deinit();

    try log.info("Test", .{});
    const output = fbs.getWritten();
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "[info]"));
}
```

---

## FileWriter

文件输出

```zig
pub const FileWriter = struct {
    pub fn init(allocator: Allocator, path: []const u8) !FileWriter;
    pub fn deinit(self: *FileWriter) void;
    pub fn writer(self: *FileWriter) LogWriter;
};
```

### 示例

```zig
var file_writer = try FileWriter.init(allocator, "app.log");
defer file_writer.deinit();

var log = Logger.init(allocator, file_writer.writer(), .debug);
try log.debug("File log", .{ .key = "value" });
```

---

## JSONWriter

JSON 格式输出

**注意**: JSONWriter 是泛型函数，需要指定底层 Writer 类型。

```zig
pub fn JSONWriter(comptime WriterType: type) type {
    return struct {
        underlying_writer: WriterType,
        allocator: Allocator,
        mutex: std.Thread.Mutex,

        pub fn init(allocator: Allocator, underlying: WriterType) Self;
        pub fn writer(self: *Self) LogWriter;
    };
}
```

### `init(allocator, underlying) Self`

创建 JSONWriter

```zig
const stdout_file = std.fs.File.stdout();
var json = JSONWriter(std.fs.File).init(allocator, stdout_file);
var log = Logger.init(allocator, json.writer(), .info);
defer log.deinit();

try log.info("Order created", .{
    .order_id = "ORD123",
    .price = 50000.0,
});
// 输出: {"level":"info","msg":"Order created","timestamp":1737541845000,"order_id":"ORD123","price":50000.0}
```

### 示例：使用 FixedBufferStream

```zig
test "JSONWriter with buffer" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const WriterType = @TypeOf(fbs.writer());
    var json = JSONWriter(WriterType).init(std.testing.allocator, fbs.writer());
    var log = Logger.init(std.testing.allocator, json.writer(), .info);
    defer log.deinit();

    try log.info("Order created", .{ .order_id = "ORD123", .price = 50000.0 });
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "\"level\":\"info\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "\"order_id\":\"ORD123\""));
}
```

---

## StdLogWriter

std.log 桥接，允许将标准库日志路由到自定义 Logger

```zig
pub const StdLogWriter = struct {
    /// 设置全局 Logger 实例
    pub fn setLogger(logger: *Logger) void;

    /// std.log 兼容的日志函数
    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void;
};
```

### 示例

```zig
// 1. 声明全局 Logger 实例
var logger_instance: Logger = undefined;

// 2. 配置 std_options
pub const std_options = .{
    .logFn = StdLogWriter.logFn,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 3. 初始化 Logger（带彩色）
    const stderr_file = std.fs.File.stderr();
    var console = ConsoleWriter(std.fs.File).init(gpa.allocator(), stderr_file);
    logger_instance = Logger.init(gpa.allocator(), console.writer(), .debug);
    defer logger_instance.deinit();

    // 4. 设置全局 Logger
    StdLogWriter.setLogger(&logger_instance);

    // 5. 使用 std.log（会路由到我们的 Logger，带彩色）
    std.log.info("Server started on port {}", .{8080});  // 绿色

    // 6. Scoped logging
    const db_log = std.log.scoped(.database);
    db_log.info("Connected", .{});  // 绿色
    // 输出: [info] 1737541845000 Connected scope=database
}
```

---

## 完整示例

### 示例 1: 多层日志

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Console logger (debug 及以上，带彩色)
    const stdout_file = std.fs.File.stdout();
    var console = ConsoleWriter(std.fs.File).init(allocator, stdout_file);
    defer console.deinit();
    var console_log = Logger.init(allocator, console.writer(), .debug);
    defer console_log.deinit();

    // File logger (info 及以上)
    var file = try FileWriter.init(allocator, "app.log");
    defer file.deinit();
    var file_log = Logger.init(allocator, file.writer(), .info);
    defer file_log.deinit();

    // 同时写入两个 logger
    try console_log.debug("Debug info", .{});  // 只在 console（青色）
    try console_log.info("Important", .{});    // console（绿色）
    try file_log.info("Important", .{});       // file（无颜色）
}
```

### 示例 2: 业务日志

```zig
pub fn processOrder(log: *Logger, order: Order) !void {
    try log.info("Processing order", .{
        .order_id = order.id,
        .symbol = order.symbol,
    });

    const result = executeOrder(order) catch |err| {
        try log.err("Order execution failed", .{
            .order_id = order.id,
            .error = @errorName(err),
        });
        return err;
    };

    try log.info("Order executed", .{
        .order_id = order.id,
        .price = result.price,
        .quantity = result.quantity,
    });
}
```

### 示例 3: 性能监控

```zig
pub fn benchmarkOperation(log: *Logger) !void {
    const start = std.time.nanoTimestamp();

    // 执行操作...
    try performOperation();

    const end = std.time.nanoTimestamp();
    const elapsed_ms = @divFloor(end - start, std.time.ns_per_ms);

    try log.info("Operation completed", .{
        .elapsed_ms = elapsed_ms,
    });

    if (elapsed_ms > 1000) {
        try log.warn("Slow operation detected", .{
            .elapsed_ms = elapsed_ms,
        });
    }
}
```

---

*Last updated: 2025-12-24*
