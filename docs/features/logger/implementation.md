# Logger - 实现细节

> 内部实现说明和设计决策

**最后更新**: 2025-01-22

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
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
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
            .timestamp = std.time.timestamp() * 1000,
            .fields = field_array,
        };

        try self.writer.write(record);
    }

    fn convertFields(self: *Logger, fields: anytype) ![]Field {
        const FieldsType = @TypeOf(fields);
        const fields_info = @typeInfo(FieldsType);

        if (fields_info != .Struct) {
            return &[_]Field{};
        }

        const struct_fields = fields_info.Struct.fields;
        var result = try self.allocator.alloc(Field, struct_fields.len);

        inline for (struct_fields, 0..) |field, i| {
            const value = @field(fields, field.name);
            result[i] = Field{
                .key = field.name,
                .value = try self.valueFromAny(value),
            };
        }

        return result;
    }

    fn valueFromAny(self: *Logger, value: anytype) !Value {
        const T = @TypeOf(value);
        return switch (@typeInfo(T)) {
            .Int => if (T == i64 or T == i32 or T == i16 or T == i8)
                Value{ .int = value }
            else
                Value{ .uint = value },
            .Float => Value{ .float = @floatCast(value) },
            .Bool => Value{ .bool = value },
            .Pointer => |ptr_info| blk: {
                if (ptr_info.size == .Slice and ptr_info.child == u8) {
                    break :blk Value{ .string = value };
                }
                @compileError("Unsupported pointer type");
            },
            else => @compileError("Unsupported type: " ++ @typeName(T)),
        };
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
```

**关键算法**:

1. **级别过滤**: 提前返回，避免不必要的分配
2. **编译时字段转换**: 使用 `inline for` 和 `@field`
3. **类型推导**: 使用 `@typeInfo` 自动转换 anytype

---

## Writer 实现

### ConsoleWriter

```zig
pub const ConsoleWriter = struct {
    underlying_writer: std.io.AnyWriter,
    mutex: std.Thread.Mutex = .{},

    pub fn init(writer: anytype) ConsoleWriter {
        return .{
            .underlying_writer = writer,
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
            try field.value.format("", .{}, w);
        }

        try w.writeAll("\n");
    }

    fn flushFn(ptr: *anyopaque) anyerror!void {
        const self: *ConsoleWriter = @ptrCast(@alignCast(ptr));
        // Console writer 通常自动刷新
        _ = self;
    }

    fn closeFn(ptr: *anyopaque) void {
        const self: *ConsoleWriter = @ptrCast(@alignCast(ptr));
        _ = self;
    }
};
```

**设计决策**:
- 使用 `Mutex` 保证线程安全
- 简单的键值对格式，易于阅读
- 自动添加换行符

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
            try field.value.format("", .{}, w);
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

    pub fn init(writer: anytype) JSONWriter {
        return .{
            .underlying_writer = writer,
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

---

### RotatingFileWriter

```zig
pub const RotatingFileWriter = struct {
    allocator: Allocator,
    path: []const u8,
    config: Config,
    current_file: std.fs.File,
    current_size: usize,
    mutex: std.Thread.Mutex = .{},

    pub const Config = struct {
        max_size: usize,
        max_backups: u32,
    };

    pub fn init(allocator: Allocator, path: []const u8, config: Config) !RotatingFileWriter {
        const path_copy = try allocator.dupe(u8, path);
        const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
        const stat = try file.stat();

        return .{
            .allocator = allocator,
            .path = path_copy,
            .config = config,
            .current_file = file,
            .current_size = stat.size,
        };
    }

    pub fn deinit(self: *RotatingFileWriter) void {
        self.current_file.close();
        self.allocator.free(self.path);
    }

    fn rotate(self: *RotatingFileWriter) !void {
        self.current_file.close();

        // 轮转备份文件
        var i = self.config.max_backups;
        while (i > 0) : (i -= 1) {
            const old_name = if (i == 1)
                try std.fmt.allocPrint(self.allocator, "{s}", .{self.path})
            else
                try std.fmt.allocPrint(self.allocator, "{s}.{}", .{ self.path, i - 1 });
            defer self.allocator.free(old_name);

            const new_name = try std.fmt.allocPrint(self.allocator, "{s}.{}", .{ self.path, i });
            defer self.allocator.free(new_name);

            std.fs.cwd().rename(old_name, new_name) catch {};
        }

        // 创建新文件
        self.current_file = try std.fs.cwd().createFile(self.path, .{ .truncate = true });
        self.current_size = 0;
    }

    fn writeFn(ptr: *anyopaque, record: LogRecord) anyerror!void {
        const self: *RotatingFileWriter = @ptrCast(@alignCast(ptr));
        self.mutex.lock();
        defer self.mutex.unlock();

        // 检查是否需要轮转
        if (self.current_size >= self.config.max_size) {
            try self.rotate();
        }

        const w = self.current_file.writer();

        const start_pos = try self.current_file.getPos();

        try w.print("[{s}] {} {s}", .{
            record.level.toString(),
            record.timestamp,
            record.message,
        });

        for (record.fields) |field| {
            try w.print(" {s}=", .{field.key});
            try field.value.format("", .{}, w);
        }

        try w.writeAll("\n");

        const end_pos = try self.current_file.getPos();
        self.current_size += end_pos - start_pos;
    }

    // ...
};
```

**设计决策**:
- 达到最大大小时自动轮转
- 保留指定数量的备份文件
- 文件命名: `app.log`, `app.log.1`, `app.log.2`, ...

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

*Last updated: 2025-01-22*
