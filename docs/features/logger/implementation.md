# Logger - 实现细节

> 内部实现说明和设计决策

**最后更新**: 2025-01-23

---

## 核心数据结构

### Level

```zig
pub const Level = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
    fatal = 5,

    pub fn toInt(self: Level) u8 {
        return @intFromEnum(self);
    }

    pub fn toString(self: Level) []const u8 {
        return switch (self) {
            .trace => "trace",
            .debug => "debug",
            .info => "info",
            .warn => "warn",
            .err => "error",
            .fatal => "fatal",
        };
    }
};
```

**设计决策**:
- 使用 `enum(u8)` 提供整数值便于比较
- 数值越大级别越高
- `toString()` 返回字符串常量（零分配）

---

### LogRecord

```zig
pub const LogRecord = struct {
    level: Level,
    message: []const u8,
    timestamp: i64,          // Unix 毫秒时间戳
    fields: []const Field,   // 额外字段
};
```

**设计决策**:
- 所有字段都是值类型或切片
- 不持有内存，调用方负责生命周期
- `fields` 使用切片支持可变数量字段

---

### Field 和 Value

```zig
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

    pub fn format(
        self: Value,
        writer: anytype,
    ) !void {
        switch (self) {
            .string => |s| try writer.writeAll(s),
            .int => |i| try writer.print("{}", .{i}),
            .uint => |u| try writer.print("{}", .{u}),
            .float => |f| try writer.print("{d}", .{f}),
            .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        }
    }
};
```

**设计决策**:
- 使用 tagged union 支持多种类型
- 实现 `format()` 支持 `std.fmt.print`
- 支持常见的基础类型

---

### LogWriter (vtable 模式)

```zig
pub const LogWriter = struct {
    ptr: *anyopaque,
    writeFn: *const fn (ptr: *anyopaque, record: LogRecord) anyerror!void,
    flushFn: *const fn (ptr: *anyopaque) anyerror!void,
    closeFn: *const fn (ptr: *anyopaque) void,

    pub fn write(self: LogWriter, record: LogRecord) !void {
        return self.writeFn(self.ptr, record);
    }

    pub fn flush(self: LogWriter) !void {
        return self.flushFn(self.ptr);
    }

    pub fn close(self: LogWriter) void {
        self.closeFn(self.ptr);
    }
};
```

**设计决策**:
- 使用 vtable 模式实现接口多态
- `*anyopaque` 类型擦除，支持任意 Writer
- 三个核心方法：write（写入）、flush（刷新）、close（关闭）

---

### Logger

```zig
pub const Logger = struct {
    allocator: Allocator,
    writer: LogWriter,
    min_level: Level,

    pub fn init(allocator: Allocator, writer: LogWriter, min_level: Level) Logger {
        return .{
            .allocator = allocator,
            .writer = writer,
            .min_level = min_level,
        };
    }

    pub fn deinit(self: *Logger) void {
        self.writer.close();
    }

    pub fn log(self: *Logger, level: Level, msg: []const u8, fields: anytype) !void {
        // 级别过滤（零分配快速路径）
        if (level.toInt() < self.min_level.toInt()) {
            return;
        }

        // 转换 fields 为 Field 数组
        const field_array = try self.convertFields(fields);
        defer self.allocator.free(field_array);

        const record = LogRecord{
            .level = level,
            .message = msg,
            .timestamp = std.time.milliTimestamp(),
            .fields = field_array,
        };

        try self.writer.write(record);
    }

    fn convertFields(self: *Logger, fields: anytype) ![]Field {
        const FieldsType = @TypeOf(fields);
        const fields_info = @typeInfo(FieldsType);

        switch (fields_info) {
            .@"struct" => |struct_info| {
                const struct_fields = struct_info.fields;
                var result = try self.allocator.alloc(Field, struct_fields.len);

                inline for (struct_fields, 0..) |field, i| {
                    const value = @field(fields, field.name);
                    result[i] = Field{
                        .key = field.name,
                        .value = try valueFromAny(value),
                    };
                }

                return result;
            },
            else => {
                return &[_]Field{};
            },
        }
    }

    // 便捷方法
    pub fn trace(self: *Logger, msg: []const u8, fields: anytype) !void {
        try self.log(.trace, msg, fields);
    }

    pub fn debug(self: *Logger, msg: []const u8, fields: anytype) !void {
        try self.log(.debug, msg, fields);
    }

    pub fn info(self: *Logger, msg: []const u8, fields: anytype) !void {
        try self.log(.info, msg, fields);
    }

    pub fn warn(self: *Logger, msg: []const u8, fields: anytype) !void {
        try self.log(.warn, msg, fields);
    }

    pub fn err(self: *Logger, msg: []const u8, fields: anytype) !void {
        try self.log(.err, msg, fields);
    }

    pub fn fatal(self: *Logger, msg: []const u8, fields: anytype) !void {
        try self.log(.fatal, msg, fields);
    }
};

/// Convert anytype value to Value
fn valueFromAny(value: anytype) !Value {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .@"int" => |int_info| {
            if (int_info.signedness == .signed) {
                return Value{ .int = @intCast(value) };
            } else {
                return Value{ .uint = @intCast(value) };
            }
        },
        .comptime_int => Value{ .int = value },
        .@"float", .comptime_float => Value{ .float = @floatCast(value) },
        .bool => Value{ .bool = value },
        .pointer => |ptr_info| {
            // Handle []const u8 slices
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                return Value{ .string = value };
            }
            // Handle string literals (*const [N:0]u8)
            if (ptr_info.size == .one) {
                if (@typeInfo(ptr_info.child) == .array) {
                    const array_info = @typeInfo(ptr_info.child).array;
                    if (array_info.child == u8) {
                        return Value{ .string = value };
                    }
                }
            }
            @compileError("Unsupported pointer type: " ++ @typeName(T));
        },
        else => @compileError("Unsupported type for logging: " ++ @typeName(T)),
    };
}
```

**关键算法**:

1. **级别过滤**: 提前返回，避免不必要的分配
2. **编译时字段转换**: 使用 `inline for` 和 `@field`
3. **类型推导**: 使用 `@typeInfo` 自动转换 anytype
4. **字符串字面量支持**: 处理 `*const [N:0]u8` 类型
5. **Comptime 类型支持**: 支持 `comptime_int` 和 `comptime_float`

---

## Writer 实现

### ConsoleWriter

```zig
pub const ConsoleWriter = struct {
    underlying_writer: std.io.AnyWriter,
    mutex: std.Thread.Mutex = .{},

    pub fn init(underlying: anytype) ConsoleWriter {
        return .{
            .underlying_writer = underlying,  // 接受 &writer.interface
        };
    }

    pub fn deinit(self: *ConsoleWriter) void {
        _ = self;
    }

    pub fn writer(self: *ConsoleWriter) LogWriter {
        return LogWriter{
            .ptr = self,
            .writeFn = writeFn,
            .flushFn = flushFn,
            .closeFn = closeFn,
        };
    }

    fn writeFn(ptr: *anyopaque, record: LogRecord) anyerror!void {
        const self: *ConsoleWriter = @ptrCast(@alignCast(ptr));
        self.mutex.lock();
        defer self.mutex.unlock();

        const w = self.underlying_writer;

        // 格式: [LEVEL] timestamp message key1=value1 key2=value2
        try w.print("[{s}] {} {s}", .{
            record.level.toString(),
            record.timestamp,
            record.message,
        });

        for (record.fields) |field| {
            try w.print(" {s}=", .{field.key});
            try field.value.format(w);
        }

        try w.writeAll("\n");
    }

    fn flushFn(ptr: *anyopaque) anyerror!void {
        _ = ptr;
    }

    fn closeFn(ptr: *anyopaque) void {
        _ = ptr;
    }
};
```

**设计决策**:
- 使用 `Mutex` 保证线程安全
- 简单的键值对格式，易于阅读
- 自动添加换行符

**使用示例**:
```zig
var stderr_buffer: [4096]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
var console = ConsoleWriter.init(&stderr_writer.interface);
```

---

### FileWriter

```zig
pub const FileWriter = struct {
    allocator: Allocator,
    file: std.fs.File,
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: Allocator, path: []const u8) !FileWriter {
        const file = try std.fs.cwd().createFile(path, .{
            .truncate = false,
            .read = false,
        });

        // Seek to end for append
        try file.seekFromEnd(0);

        return .{
            .allocator = allocator,
            .file = file,
        };
    }

    pub fn deinit(self: *FileWriter) void {
        self.file.close();
    }

    pub fn writer(self: *FileWriter) LogWriter {
        return LogWriter{
            .ptr = self,
            .writeFn = writeFn,
            .flushFn = flushFn,
            .closeFn = closeFn,
        };
    }

    fn writeFn(ptr: *anyopaque, record: LogRecord) anyerror!void {
        const self: *FileWriter = @ptrCast(@alignCast(ptr));
        self.mutex.lock();
        defer self.mutex.unlock();

        const w = self.file.writer();

        try w.print("[{s}] {} {s}", .{
            record.level.toString(),
            record.timestamp,
            record.message,
        });

        for (record.fields) |field| {
            try w.print(" {s}=", .{field.key});
            try field.value.format(w);
        }

        try w.writeAll("\n");
    }

    fn flushFn(ptr: *anyopaque) anyerror!void {
        const self: *FileWriter = @ptrCast(@alignCast(ptr));
        try self.file.sync();
    }

    fn closeFn(ptr: *anyopaque) void {
        const self: *FileWriter = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
```

---

### JSONWriter

```zig
pub const JSONWriter = struct {
    underlying_writer: std.io.AnyWriter,
    mutex: std.Thread.Mutex = .{},

    pub fn init(underlying: anytype) JSONWriter {
        return .{
            .underlying_writer = underlying,
        };
    }

    pub fn writer(self: *JSONWriter) LogWriter {
        return LogWriter{
            .ptr = self,
            .writeFn = writeFn,
            .flushFn = flushFn,
            .closeFn = closeFn,
        };
    }

    fn writeFn(ptr: *anyopaque, record: LogRecord) anyerror!void {
        const self: *JSONWriter = @ptrCast(@alignCast(ptr));
        self.mutex.lock();
        defer self.mutex.unlock();

        const w = self.underlying_writer;

        try w.writeAll("{");
        try w.print("\"level\":\"{s}\",", .{record.level.toString()});
        try w.print("\"msg\":\"{s}\",", .{record.message});
        try w.print("\"timestamp\":{}", .{record.timestamp});

        for (record.fields) |field| {
            try w.print(",\"{s}\":", .{field.key});
            switch (field.value) {
                .string => |s| try w.print("\"{s}\"", .{s}),
                .int => |i| try w.print("{}", .{i}),
                .uint => |u| try w.print("{}", .{u}),
                .float => |f| try w.print("{d}", .{f}),
                .bool => |b| try w.writeAll(if (b) "true" else "false"),
            }
        }

        try w.writeAll("}\n");
    }

    fn flushFn(ptr: *anyopaque) anyerror!void {
        _ = ptr;
    }

    fn closeFn(ptr: *anyopaque) void {
        _ = ptr;
    }
};
```

**设计决策**:
- 每条日志一行 JSON
- 字符串需要转义（简化版未实现完整转义）
- 便于日志解析工具处理

**使用示例**:
```zig
var stdout_buffer: [4096]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
var json = JSONWriter.init(&stdout_writer.interface);
```

---

### StdLogWriter

std.log 桥接，允许将标准库日志路由到自定义 Logger

```zig
pub const StdLogWriter = struct {
    var global_logger: ?*Logger = null;
    var fallback_buffer: [4096]u8 = undefined;
    var fallback_fbs = std.io.fixedBufferStream(&fallback_buffer);

    /// 设置全局 Logger 实例
    pub fn setLogger(logger: *Logger) void {
        global_logger = logger;
    }

    /// std.log 兼容的日志函数
    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        // 转换 std.log.Level 到我们的 Level
        const our_level = switch (level) {
            .debug => Level.debug,
            .info => Level.info,
            .warn => Level.warn,
            .err => Level.err,
        };

        // 格式化消息
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, format, args) catch blk: {
            // 消息太长，使用 fallback buffer
            fallback_fbs.reset();
            fallback_fbs.writer().print(format, args) catch {
                break :blk "<message too long>";
            };
            break :blk fallback_fbs.getWritten();
        };

        // 获取 scope 名称
        const scope_name = @tagName(scope);

        // 记录日志（包含 scope 字段）
        if (global_logger) |logger| {
            logger.log(our_level, message, .{ .scope = scope_name }) catch {
                // 失败时降级到 stderr
                std.debug.print("[{s}] ({s}) {s}\n", .{ our_level.toString(), scope_name, message });
            };
        } else {
            // Logger 未设置，输出到 stderr
            std.debug.print("[{s}] ({s}) {s}\n", .{ our_level.toString(), scope_name, message });
        }
    }
};
```

**设计决策**:
- 全局单例模式，通过 `setLogger()` 设置 Logger
- 支持消息格式化，带 fallback 机制
- 自动提取 scope 并作为结构化字段
- 优雅降级：未设置 Logger 或失败时输出到 stderr
- 兼容 `std.log` API，可通过 `std_options.logFn` 配置

---

## 性能优化

### 1. 级别过滤快速路径

```zig
if (level.toInt() < self.min_level.toInt()) {
    return;  // 立即返回，零分配
}
```

### 2. 编译时字段转换

```zig
inline for (struct_fields, 0..) |field, i| {
    // 编译时展开，避免运行时反射
}
```

### 3. 字符串常量

```zig
pub fn toString(self: Level) []const u8 {
    return switch (self) {
        .info => "info",  // 字符串常量，零分配
        // ...
    };
}
```

---

## 线程安全

- 所有 Writer 使用 `Mutex` 保证线程安全
- 多个线程可以安全地写入同一个 Logger
- `LogRecord` 是不可变的，传递安全

---

*Last updated: 2025-01-23*
