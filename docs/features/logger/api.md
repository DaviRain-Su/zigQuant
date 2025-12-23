# Logger - API 参考

> 完整的 API 文档和使用示例

**最后更新**: 2025-01-22

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
var console = ConsoleWriter.init(std.io.getStdOut().writer());
var log = Logger.init(allocator, console.writer(), .info);
defer log.deinit();
```

### `log(level, msg, fields) !void`

记录日志

```zig
try log.log(.info, "User login", .{
    .user_id = 12345,
    .ip = "192.168.1.1",
});
```

### 便捷方法

```zig
// trace 级别
try log.trace("Trace message", .{});

// debug 级别
try log.debug("Debug message", .{ .var1 = value1 });

// info 级别
try log.info("Info message", .{ .key = "value" });

// warn 级别
try log.warn("Warning", .{ .code = 123 });

// error 级别
try log.err("Error occurred", .{ .error = err });

// fatal 级别
try log.fatal("Fatal error", .{ .reason = "crash" });
```

---

## ConsoleWriter

控制台输出

```zig
pub const ConsoleWriter = struct {
    pub fn init(writer: anytype) ConsoleWriter;
    pub fn deinit(self: *ConsoleWriter) void;
    pub fn writer(self: *ConsoleWriter) LogWriter;
};
```

### 示例

```zig
var console = ConsoleWriter.init(std.io.getStdOut().writer());
defer console.deinit();

var log = Logger.init(allocator, console.writer(), .info);
try log.info("Console output", .{});
// 输出: [info] 1737541845000 Console output
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

```zig
pub const JSONWriter = struct {
    pub fn init(writer: anytype) JSONWriter;
    pub fn writer(self: *JSONWriter) LogWriter;
};
```

### 示例

```zig
var json = JSONWriter.init(std.io.getStdOut().writer());
var log = Logger.init(allocator, json.writer(), .info);

try log.info("Order created", .{
    .order_id = "ORD123",
    .price = 50000.0,
});
// 输出: {"level":"info","msg":"Order created","timestamp":1737541845000,"order_id":"ORD123","price":50000.0}
```

---

## RotatingFileWriter

自动轮转的文件输出

```zig
pub const RotatingFileWriter = struct {
    pub const Config = struct {
        max_size: usize,      // 最大文件大小（字节）
        max_backups: u32,     // 保留备份数量
    };

    pub fn init(allocator: Allocator, path: []const u8, config: Config) !RotatingFileWriter;
    pub fn deinit(self: *RotatingFileWriter) void;
    pub fn writer(self: *RotatingFileWriter) LogWriter;
};
```

### 示例

```zig
var rotating = try RotatingFileWriter.init(
    allocator,
    "logs/app.log",
    .{
        .max_size = 10 * 1024 * 1024,  // 10MB
        .max_backups = 5,
    },
);
defer rotating.deinit();

var log = Logger.init(allocator, rotating.writer(), .info);
try log.info("Rotating log", .{});
// 文件达到 10MB 时自动轮转为 app.log.1, app.log.2, ...
```

---

## 完整示例

### 示例 1: 多层日志

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Console logger (debug 及以上)
    var console = ConsoleWriter.init(std.io.getStdOut().writer());
    defer console.deinit();
    var console_log = Logger.init(allocator, console.writer(), .debug);
    defer console_log.deinit();

    // File logger (info 及以上)
    var file = try FileWriter.init(allocator, "app.log");
    defer file.deinit();
    var file_log = Logger.init(allocator, file.writer(), .info);
    defer file_log.deinit();

    // 同时写入两个 logger
    try console_log.debug("Debug info", .{});  // 只在 console
    try console_log.info("Important", .{});
    try file_log.info("Important", .{});       // 在 console 和 file
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

*Last updated: 2025-01-22*
