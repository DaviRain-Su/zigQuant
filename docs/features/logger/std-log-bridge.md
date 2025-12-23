# StdLogWriter - std.log 桥接实现

## 概述

StdLogWriter 是一个桥接层，允许将 `std.log` 的调用路由到我们的自定义 Logger 系统。这样你可以享受 std.log 的便利性，同时保留自定义 Logger 的强大功能（文件输出、JSON 格式、结构化字段等）。

## 实现特点

### 1. 全局单例模式
```zig
pub const StdLogWriter = struct {
    var global_logger: ?*Logger = null;

    pub fn setLogger(logger: *Logger) void {
        global_logger = logger;
    }
};
```

- 使用全局变量存储 Logger 指针
- 通过 `setLogger()` 设置当前使用的 Logger

### 2. 级别映射
```zig
const our_level = switch (level) {
    .debug => Level.debug,
    .info => Level.info,
    .warn => Level.warn,
    .err => Level.err,
};
```

将 `std.log.Level` 映射到我们的 `Level` 枚举。

### 3. 消息格式化
```zig
var buf: [1024]u8 = undefined;
const message = std.fmt.bufPrint(&buf, format, args) catch blk: {
    // 如果消息太长，使用 fallback buffer
    fallback_fbs.reset();
    fallback_fbs.writer().print(format, args) catch {
        break :blk "<message too long>";
    };
    break :blk fallback_fbs.getWritten();
};
```

- 优先使用栈上的 1024 字节缓冲区
- 如果消息过长，使用 4096 字节的 fallback buffer
- 如果仍然失败，返回错误提示

### 4. Scope 支持
```zig
const scope_name = @tagName(scope);
logger.log(our_level, message, .{ .scope = scope_name })
```

- 自动提取 scope 名称
- 作为结构化字段传递给 Logger

### 5. 优雅降级
```zig
if (global_logger) |logger| {
    logger.log(our_level, message, .{ .scope = scope_name }) catch {
        std.debug.print("[{s}] ({s}) {s}\n", .{ our_level.toString(), scope_name, message });
    };
} else {
    std.debug.print("[{s}] ({s}) {s}\n", .{ our_level.toString(), scope_name, message });
}
```

- 如果 Logger 未设置，输出到 stderr
- 如果 Logger 失败，也降级到 stderr

## 使用方法

### 基本用法

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

// 1. 声明全局 Logger 实例
var logger_instance: zigQuant.Logger = undefined;

// 2. 配置 std_options
pub const std_options = .{
    .logFn = zigQuant.StdLogWriter.logFn,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 3. 初始化 Logger
    var console = zigQuant.ConsoleWriter.init(std.io.getStdErr().writer().any());
    logger_instance = zigQuant.Logger.init(gpa.allocator(), console.writer(), .debug);
    defer logger_instance.deinit();

    // 4. 设置 StdLogWriter 使用的 Logger
    zigQuant.StdLogWriter.setLogger(&logger_instance);

    // 5. 正常使用 std.log
    std.log.info("Hello from std.log", .{});
}
```

### Scoped Logging

```zig
const db_log = std.log.scoped(.database);
db_log.info("Connection established", .{});
// 输出: [info] 1234567890 Connection established scope=database

const api_log = std.log.scoped(.api);
api_log.warn("Rate limit exceeded", .{});
// 输出: [warn] 1234567891 Rate limit exceeded scope=api
```

### 与原生 Logger 混用

```zig
// 使用 std.log（会路由到我们的 Logger）
std.log.info("User login", .{});

// 直接使用我们的 Logger（支持结构化字段）
try logger_instance.info("User login", .{
    .user_id = 123,
    .ip = "192.168.1.1",
    .timestamp = std.time.timestamp(),
});
```

## 输出格式

### ConsoleWriter 输出
```
[info] 1735012345678 Connection established scope=database
[warn] 1735012345679 High latency detected: 150 ms scope=network
```

### JSONWriter 输出
```json
{"level":"info","msg":"Connection established","timestamp":1735012345678,"scope":"database"}
{"level":"warn","msg":"High latency detected: 150 ms","timestamp":1735012345679,"scope":"network"}
```

## 优势

### 1. 兼容性
- 可以使用任何使用 `std.log` 的第三方库
- 无需修改现有代码，只需配置 `std_options`

### 2. 渐进式迁移
- 可以先用 std.log 快速开发
- 需要高级功能时，直接调用自定义 Logger

### 3. 统一日志输出
- 所有日志（std.log + 自定义）输出到同一位置
- 统一的格式和配置

### 4. 零学习成本
- 熟悉 std.log 的开发者可以直接使用
- 保留 std.log 的简洁 API

## 限制

### 1. 全局单例
- 只能有一个全局 Logger 实例
- 如果需要多个 Logger，需要手动切换

### 2. 结构化字段限制
- std.log 不支持结构化字段
- 只能通过格式化字符串传递数据
- Scope 是唯一的结构化字段

### 3. 性能
- std.log 的编译时级别过滤不可用
- 级别过滤在运行时进行
- 需要格式化消息（即使被过滤）

## 测试

实现包含 2 个测试：

1. **StdLogWriter bridge** - 基本桥接功能
2. **StdLogWriter with formatting** - 格式化参数支持

测试覆盖：
- ✅ Level 转换
- ✅ Scope 提取
- ✅ 消息格式化
- ✅ 输出验证

## 总结

StdLogWriter 是一个轻量级的桥接层，让你可以：

1. **开发时**：使用 std.log 快速开发和调试
2. **生产时**：享受自定义 Logger 的强大功能（文件、JSON、轮转）
3. **集成时**：兼容使用 std.log 的第三方库
4. **混用时**：std.log 和自定义 Logger 可以共存

这是一个"两全其美"的解决方案，既保留了 std.log 的便利性，又提供了生产环境所需的高级功能。
