# Logger - 日志系统

> 高性能、可扩展的结构化日志

**状态**: ✅ 已完成
**版本**: v0.1.0
**Story**: [004-logger](../../../stories/v0.1-foundation/004-logger.md)
**最后更新**: 2025-01-23

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
- ✅ **结构化日志**: 支持键值对字段
- ✅ **多种 Writer**: Console, File, JSON
- ✅ **std.log 桥接**: StdLogWriter 集成标准库日志
- ✅ **vtable 模式**: 可扩展的 Writer 接口
- ✅ **高性能**: >100K logs/sec (Console Writer)
- ✅ **零分配**: 日志级别过滤无内存分配

---

## 🚀 快速开始

### 基本使用

```zig
const std = @import("std");
const logger = @import("core/logger.zig");

pub fn main() !void {
    // 创建 stderr writer
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

    // 创建 Console Writer
    var console = logger.ConsoleWriter.init(&stderr_writer.interface);
    defer console.deinit();

    // 创建 Logger
    var log = logger.Logger.init(
        std.heap.page_allocator,
        console.writer(),
        .info,  // 最低日志级别
    );
    defer log.deinit();

    // 记录日志
    try log.info("Application started", .{});
    try log.warn("Warning message", .{ .code = 123, .retry = true });
    try log.err("Error occurred", .{ .error_code = "ERR001" });
}
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
var stdout_buffer: [4096]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

var json_writer = logger.JSONWriter.init(&stdout_writer.interface);
var log = logger.Logger.init(allocator, json_writer.writer(), .info);

try log.info("Order created", .{
    .order_id = "ORD123",
    .symbol = "BTC/USDT",
    .price = 50000.0,
    .quantity = 1.5,
});
// 输出: {"level":"info","msg":"Order created","timestamp":1737541845000,"order_id":"ORD123","symbol":"BTC/USDT","price":50000.0,"quantity":1.5}
```

### std.log 桥接

```zig
// 使用 StdLogWriter 桥接标准库日志
var logger_instance: logger.Logger = undefined;

pub const std_options = .{
    .logFn = logger.StdLogWriter.logFn,
};

pub fn main() !void {
    // 创建 stderr writer
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

    var console = logger.ConsoleWriter.init(&stderr_writer.interface);
    logger_instance = logger.Logger.init(allocator, console.writer(), .debug);
    defer logger_instance.deinit();

    // 设置全局 logger
    logger.StdLogWriter.setLogger(&logger_instance);

    // 使用标准库日志（会路由到我们的 Logger）
    std.log.info("Server started on port {}", .{8080});

    // Scoped logging
    const db_log = std.log.scoped(.database);
    db_log.info("Connected", .{});  // 输出包含 scope=database
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

/// Console Writer
pub const ConsoleWriter = struct {
    pub fn init(underlying: anytype) ConsoleWriter;
    pub fn deinit(self: *ConsoleWriter) void;
    pub fn writer(self: *ConsoleWriter) LogWriter;
};

/// File Writer
pub const FileWriter = struct {
    pub fn init(allocator: Allocator, path: []const u8) !FileWriter;
    pub fn deinit(self: *FileWriter) void;
    pub fn writer(self: *FileWriter) LogWriter;
};

/// JSON Writer
pub const JSONWriter = struct {
    pub fn init(underlying: anytype) JSONWriter;
    pub fn writer(self: *JSONWriter) LogWriter;
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

*Last updated: 2025-01-23*
