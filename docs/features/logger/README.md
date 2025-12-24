# Logger - 日志系统

> 高性能、可扩展的结构化日志

**状态**: ✅ 已完成
**版本**: v0.1.1
**Story**: [004-logger](../../../stories/v0.1-foundation/004-logger.md)
**最后更新**: 2025-01-24

---

## 📋 概述

Logger 模块提供高性能的结构化日志系统，支持多种输出格式和日志分级，满足量化交易系统的日志需求。

### 为什么需要 Logger？

量化交易系统需要详细的日志记录：
- 调试问题时需要追踪执行流程
- 监控系统运行状态和性能
- 审计交易操作和决策过程
- 分析错误和异常情况
- 合规性要求保留操作记录

### 核心特性

- ✅ **6 个日志级别**: trace, debug, info, warn, error, fatal
- ✅ **彩色日志输出**: ANSI 颜色代码，可自定义每个级别的颜色
- ✅ **结构化日志**: 支持键值对字段
- ✅ **多种 Writer**: Console, File, JSON
- ✅ **std.log 桥接**: StdLogWriter 集成标准库日志
- ✅ **vtable 模式**: 可扩展的 Writer 接口
- ✅ **高性能**: >100K logs/sec (Console Writer)
- ✅ **零分配**: 日志级别过滤无内存分配

---

## 🚀 快速开始

### 基本使用（带彩色输出）

```zig
const std = @import("std");
const logger = @import("core/logger.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 创建 Console Writer（带彩色，默认启用）
    const stdout_file = std.fs.File.stdout();
    var console = logger.ConsoleWriter(std.fs.File).init(gpa.allocator(), stdout_file);
    defer console.deinit();

    // 创建 Logger
    var log = logger.Logger.init(
        gpa.allocator(),
        console.writer(),
        .info,  // 最低日志级别
    );
    defer log.deinit();

    // 记录日志（带彩色输出）
    try log.info("Application started", .{});        // 绿色
    try log.warn("Warning message", .{ .code = 123 });  // 黄色
    try log.err("Error occurred", .{ .error_code = "ERR001" });  // 红色
}
```

### 禁用彩色输出

```zig
// 在 CI 环境或重定向到文件时禁用颜色
const stderr_file = std.fs.File.stderr();
var console = logger.ConsoleWriter(std.fs.File).initWithColors(
    gpa.allocator(),
    stderr_file,
    false  // 禁用颜色
);
defer console.deinit();

var log = logger.Logger.init(gpa.allocator(), console.writer(), .info);
defer log.deinit();

try log.info("Plain text log", .{});  // 无颜色
```

### 文件日志

```zig
// 写入文件
var file_writer = try logger.FileWriter.init(
    allocator,
    "logs/app.log",
);
defer file_writer.deinit();

var log = logger.Logger.init(allocator, file_writer.writer(), .debug);
defer log.deinit();

try log.debug("Debug info", .{ .user_id = 12345 });
```

### JSON 日志

```zig
// JSON 格式输出到 stdout
const stdout_file = std.fs.File.stdout();
var json_writer = logger.JSONWriter(std.fs.File).init(allocator, stdout_file);
var log = logger.Logger.init(allocator, json_writer.writer(), .info);
defer log.deinit();

try log.info("Order created", .{
    .order_id = "ORD123",
    .symbol = "BTC/USDT",
    .price = 50000.0,
    .quantity = 1.5,
});
// 输出: {"level":"info","msg":"Order created","timestamp":1737541845000,"order_id":"ORD123","symbol":"BTC/USDT","price":50000.0,"quantity":1.5}
```

### std.log 桥接（带彩色）

```zig
// 使用 StdLogWriter 桥接标准库日志
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

    // 使用标准库日志（会路由到我们的 Logger，带彩色）
    std.log.info("Server started on port {}", .{8080});  // 绿色

    // Scoped logging
    const db_log = std.log.scoped(.database);
    db_log.info("Connected", .{});  // 绿色，输出包含 scope=database
}
```

---

## 📚 相关文档

- [使用指南](./usage-guide.md) - **⭐ 新手必读：Zig 0.15 正确用法**
- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [StdLogWriter 桥接](./std-log-bridge.md) - std.log 集成指南
- [对比说明](./comparison.md) - std.log vs 自定义 Logger
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史
- [示例代码](../../../examples/logger/) - 实际使用示例

---

## 🔧 核心 API

```zig
/// 日志级别
pub const Level = enum {
    trace,   // 最详细的跟踪信息
    debug,   // 调试信息
    info,    // 一般信息
    warn,    // 警告
    err,     // 错误
    fatal,   // 致命错误

    pub fn toInt(self: Level) u8;
    pub fn toString(self: Level) []const u8;
};

/// 日志记录
pub const LogRecord = struct {
    level: Level,
    message: []const u8,
    timestamp: i64,
    fields: []const Field,
};

/// 日志字段
pub const Field = struct {
    key: []const u8,
    value: Value,
};

pub const Value = union(enum) {
    string: []const u8,
    int: i64,
    uint: u64,
    float: f64,
    bool: bool,
};

/// Writer 接口（vtable 模式）
pub const LogWriter = struct {
    ptr: *anyopaque,
    writeFn: *const fn (ptr: *anyopaque, record: LogRecord) anyerror!void,
    flushFn: *const fn (ptr: *anyopaque) anyerror!void,
    closeFn: *const fn (ptr: *anyopaque) void,

    pub fn write(self: LogWriter, record: LogRecord) !void;
    pub fn flush(self: LogWriter) !void;
    pub fn close(self: LogWriter) void;
};

/// Logger 实例
pub const Logger = struct {
    allocator: Allocator,
    writer: LogWriter,
    min_level: Level,

    pub fn init(allocator: Allocator, writer: LogWriter, min_level: Level) Logger;
    pub fn deinit(self: *Logger) void;

    pub fn log(self: *Logger, level: Level, msg: []const u8, fields: anytype) !void;

    pub fn trace(self: *Logger, msg: []const u8, fields: anytype) !void;
    pub fn debug(self: *Logger, msg: []const u8, fields: anytype) !void;
    pub fn info(self: *Logger, msg: []const u8, fields: anytype) !void;
    pub fn warn(self: *Logger, msg: []const u8, fields: anytype) !void;
    pub fn err(self: *Logger, msg: []const u8, fields: anytype) !void;
    pub fn fatal(self: *Logger, msg: []const u8, fields: anytype) !void;
};

/// Console Writer (泛型，支持彩色)
pub fn ConsoleWriter(comptime WriterType: type) type {
    return struct {
        pub fn init(allocator: Allocator, underlying: WriterType) Self;
        pub fn initWithColors(allocator: Allocator, underlying: WriterType, use_colors: bool) Self;
        pub fn deinit(self: *Self) void;
        pub fn writer(self: *Self) LogWriter;
    };
}

/// ANSI 颜色代码
pub const AnsiColors = struct {
    pub const RESET = "\x1b[0m";
    pub const RED = "\x1b[31m";
    pub const GREEN = "\x1b[32m";
    pub const YELLOW = "\x1b[33m";
    pub const CYAN = "\x1b[36m";
    pub const BRIGHT_BLACK = "\x1b[90m";  // 灰色
    pub const BRIGHT_RED = "\x1b[91m";
    pub const BOLD = "\x1b[1m";

    /// 获取日志级别对应的颜色
    pub fn forLevel(level: Level) []const u8;
};

/// File Writer
pub const FileWriter = struct {
    pub fn init(allocator: Allocator, path: []const u8) !FileWriter;
    pub fn deinit(self: *FileWriter) void;
    pub fn writer(self: *FileWriter) LogWriter;
};

/// JSON Writer (泛型)
pub fn JSONWriter(comptime WriterType: type) type {
    return struct {
        pub fn init(allocator: Allocator, underlying: WriterType) Self;
        pub fn writer(self: *Self) LogWriter;
    };
};

/// StdLogWriter - std.log 桥接
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

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 使用合适的日志级别
try log.debug("Processing order", .{ .order_id = id });  // 调试信息
try log.info("Order completed", .{ .order_id = id });    // 重要信息
try log.err("Order failed", .{ .error = err });          // 错误

// 2. 包含上下文信息
try log.info("Trade executed", .{
    .symbol = "BTC/USDT",
    .side = "buy",
    .price = 50000.0,
    .quantity = 1.5,
});

// 3. 使用 defer 确保资源释放
var log = logger.Logger.init(allocator, writer, .info);
defer log.deinit();

// 4. 生产环境使用 info 或更高级别
const min_level = if (is_production) .info else .debug;
```

### ❌ DON'T

```zig
// 1. 避免在循环中频繁日志
for (orders) |order| {
    try log.debug("Processing", .{ .id = order.id });  // ❌ 性能问题
}

// 2. 避免记录敏感信息
try log.info("User login", .{
    .username = username,
    .password = password,  // ❌ 安全风险
});

// 3. 避免日志消息过长
try log.info("Very long message...", .{});  // ❌ 难以阅读

// 4. 避免忘记设置最低级别
var log = logger.Logger.init(allocator, writer, .trace);  // ❌ 生产环境会太慢
```

---

## 🎯 使用场景

### ✅ 适用

- **应用程序日志**: 启动、关闭、配置加载
- **业务日志**: 订单、交易、持仓变化
- **性能监控**: 关键操作耗时
- **错误追踪**: 异常、错误、警告
- **审计日志**: 用户操作、API 调用

### ❌ 不适用

- 高频交易的 tick 数据（使用专门的数据记录）
- 调试时的临时打印（使用 `std.debug.print`）
- 性能关键路径（日志有开销）

---

## 📊 性能指标

- **日志写入**: >100K logs/sec（Console Writer）
- **文件写入**: >50K logs/sec（File Writer）
- **JSON 格式化**: >30K logs/sec（JSON Writer）
- **内存占用**: 每条日志 <1KB
- **零分配**: 日志级别过滤无分配

---

## 💡 未来改进

- [ ] 滚动日志文件（RotatingFileWriter）
- [ ] 异步日志（后台线程写入）
- [ ] 日志压缩（gzip）
- [ ] 远程日志（HTTP/gRPC）
- [ ] 日志采样（高频场景）
- [ ] 结构化查询（基于字段过滤）
- [ ] 日志聚合（多个 Logger 合并）

---

---

## 🎨 彩色日志说明

Logger 支持 ANSI 颜色代码，每个日志级别使用不同颜色：

| 级别 | 颜色 | ANSI 代码 |
|------|------|-----------|
| TRACE | 灰色 | `BRIGHT_BLACK` |
| DEBUG | 青色 | `CYAN` |
| INFO | 绿色 | `GREEN` |
| WARN | 黄色 | `YELLOW` |
| ERROR | 红色 | `RED` |
| FATAL | 粗体红色 | `BOLD + BRIGHT_RED` |

**注意**: 彩色输出默认启用，可以使用 `initWithColors(allocator, writer, false)` 禁用。

---

*Last updated: 2025-01-24*
