// Logger System - Structured Logging
//
// Provides a high-performance structured logging framework for quantitative trading:
// - 6 log levels: trace, debug, info, warn, error, fatal
// - Structured fields with key-value pairs
// - Multiple writers: Console, File, JSON, Rotating File
// - vtable pattern for extensibility
// - Thread-safe with mutex protection
//
// Design principles:
// - Zero allocation for level filtering
// - Type-safe field conversion using comptime
// - Pluggable writers via vtable interface
// - Minimal overhead for disabled log levels

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Log Levels
// ============================================================================

/// Log level enumeration
pub const Level = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
    fatal = 5,

    /// Convert to integer
    pub fn toInt(self: Level) u8 {
        return @intFromEnum(self);
    }

    /// Convert to string
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

// ============================================================================
// Field Types
// ============================================================================

/// Field value (tagged union)
pub const Value = union(enum) {
    string: []const u8,
    int: i64,
    uint: u64,
    float: f64,
    bool: bool,

    /// Format value for output
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

/// Log field (key-value pair)
pub const Field = struct {
    key: []const u8,
    value: Value,
};

// ============================================================================
// Log Record
// ============================================================================

/// A single log record
pub const LogRecord = struct {
    level: Level,
    message: []const u8,
    timestamp: i64, // Unix milliseconds
    fields: []const Field,
};

// ============================================================================
// Log Writer Interface (vtable pattern)
// ============================================================================

/// Log writer interface
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

// ============================================================================
// Logger
// ============================================================================

/// Main logger instance
pub const Logger = struct {
    allocator: Allocator,
    writer: LogWriter,
    min_level: Level,

    /// Create logger
    pub fn init(allocator: Allocator, writer: LogWriter, min_level: Level) Logger {
        return .{
            .allocator = allocator,
            .writer = writer,
            .min_level = min_level,
        };
    }

    /// Cleanup logger
    pub fn deinit(self: *Logger) void {
        self.writer.close();
    }

    /// Log a message with fields
    pub fn log(self: *Logger, level: Level, msg: []const u8, fields: anytype) !void {
        // Fast path: level filtering (zero allocation)
        if (level.toInt() < self.min_level.toInt()) {
            return;
        }

        // Convert fields to Field array
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

    /// Convert anytype fields to Field array
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

    /// Convenience methods
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

// ============================================================================
// Console Writer
// ============================================================================

/// Console writer (outputs to stdout/stderr)
pub const ConsoleWriter = struct {
    underlying_writer: *std.io.Writer,
    mutex: std.Thread.Mutex = .{},

    pub fn init(underlying: *std.io.Writer) ConsoleWriter {
        return .{
            .underlying_writer = underlying,
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

        // Format: [LEVEL] timestamp message key1=value1 key2=value2
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
        // Console typically auto-flushes
    }

    fn closeFn(ptr: *anyopaque) void {
        _ = ptr;
    }
};

// ============================================================================
// File Writer
// ============================================================================

/// File writer (outputs to a file)
pub const FileWriter = struct {
    allocator: Allocator,
    file: std.fs.File,
    buffer: [4096]u8,
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
            .buffer = undefined,
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

        var file_writer = self.file.writer(&self.buffer);
        const w = &file_writer.interface;

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
        // Don't close here - let the user call deinit() explicitly
        _ = ptr;
    }
};

// ============================================================================
// JSON Writer
// ============================================================================

/// JSON writer (outputs JSON format)
pub const JSONWriter = struct {
    underlying_writer: *std.io.Writer,
    mutex: std.Thread.Mutex = .{},

    pub fn init(underlying: *std.io.Writer) JSONWriter {
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

// ============================================================================
// StdLogWriter - Bridge to std.log
// ============================================================================

/// StdLogWriter bridges std.log calls to our Logger
///
/// Usage in your application:
/// ```zig
/// var logger_instance: Logger = undefined;
///
/// pub const std_options = .{
///     .logFn = StdLogWriter.logFn,
/// };
///
/// pub fn main() !void {
///     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
///     defer _ = gpa.deinit();
///
///     var console = ConsoleWriter.init(std.io.getStdErr().writer().any());
///     logger_instance = Logger.init(gpa.allocator(), console.writer(), .debug);
///     defer logger_instance.deinit();
///
///     StdLogWriter.setLogger(&logger_instance);
///
///     std.log.info("Hello from std.log", .{});
/// }
/// ```
pub const StdLogWriter = struct {
    var global_logger: ?*Logger = null;
    var fallback_buffer: [4096]u8 = undefined;
    var fallback_fbs = std.io.fixedBufferStream(&fallback_buffer);

    /// Set the global logger instance
    pub fn setLogger(logger: *Logger) void {
        global_logger = logger;
    }

    /// Log function compatible with std.log
    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        // Convert std.log.Level to our Level
        const our_level = switch (level) {
            .debug => Level.debug,
            .info => Level.info,
            .warn => Level.warn,
            .err => Level.err,
        };

        // Format the message
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, format, args) catch blk: {
            // If message is too long, use fallback buffer
            fallback_fbs.reset();
            fallback_fbs.writer().print(format, args) catch {
                // Even fallback failed, just use error message
                break :blk "<message too long>";
            };
            break :blk fallback_fbs.getWritten();
        };

        // Get scope name
        const scope_name = @tagName(scope);

        // Log with scope field
        if (global_logger) |logger| {
            logger.log(our_level, message, .{ .scope = scope_name }) catch {
                // If logging fails, fall back to stderr
                std.debug.print("[{s}] ({s}) {s}\n", .{ our_level.toString(), scope_name, message });
            };
        } else {
            // No logger set, output to stderr
            std.debug.print("[{s}] ({s}) {s}\n", .{ our_level.toString(), scope_name, message });
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Level enum" {
    try std.testing.expectEqual(@as(u8, 0), Level.trace.toInt());
    try std.testing.expectEqual(@as(u8, 5), Level.fatal.toInt());
    try std.testing.expectEqualStrings("info", Level.info.toString());
    try std.testing.expectEqualStrings("error", Level.err.toString());
}

test "Value format" {
    var buf: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();

    const v1 = Value{ .string = "test" };
    try v1.format(w);
    try std.testing.expectEqualStrings("test", fbs.getWritten());

    fbs.reset();
    const v2 = Value{ .int = 123 };
    try v2.format(w);
    try std.testing.expectEqualStrings("123", fbs.getWritten());

    fbs.reset();
    const v3 = Value{ .bool = true };
    try v3.format(w);
    try std.testing.expectEqualStrings("true", fbs.getWritten());
}

test "Logger basic" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var console = ConsoleWriter.init(fbs.writer().any());
    defer console.deinit();

    var log = Logger.init(std.testing.allocator, console.writer(), .info);
    defer log.deinit();

    try log.info("Test message", .{});
    const output = fbs.getWritten();
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "[info]"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "Test message"));
}

test "Logger with fields" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var console = ConsoleWriter.init(fbs.writer().any());
    var log = Logger.init(std.testing.allocator, console.writer(), .debug);
    defer log.deinit();

    try log.info("User login", .{ .user_id = 123, .active = true });
    const output = fbs.getWritten();
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "user_id=123"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "active=true"));
}

test "Logger level filtering" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var console = ConsoleWriter.init(fbs.writer().any());
    var log = Logger.init(std.testing.allocator, console.writer(), .warn);
    defer log.deinit();

    // These should be filtered out
    try log.debug("Debug message", .{});
    try log.info("Info message", .{});

    // This should appear
    try log.warn("Warning message", .{});

    const output = fbs.getWritten();
    try std.testing.expect(!std.mem.containsAtLeast(u8, output, 1, "Debug"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, output, 1, "Info"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "Warning"));
}

test "JSONWriter" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var json = JSONWriter.init(fbs.writer().any());
    var log = Logger.init(std.testing.allocator, json.writer(), .info);
    defer log.deinit();

    try log.info("Order created", .{ .order_id = "ORD123", .price = 50000.0 });
    const output = fbs.getWritten();

    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "\"level\":\"info\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "\"msg\":\"Order created\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "\"order_id\":\"ORD123\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "\"price\":50000"));
}

test "StdLogWriter bridge" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var console = ConsoleWriter.init(fbs.writer().any());
    var log = Logger.init(std.testing.allocator, console.writer(), .debug);
    defer log.deinit();

    // Set the global logger
    StdLogWriter.setLogger(&log);

    // Call through std.log interface
    StdLogWriter.logFn(.info, .database, "Connection established", .{});

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "[info]"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "Connection established"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "scope=database"));
}

test "StdLogWriter with formatting" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var console = ConsoleWriter.init(fbs.writer().any());
    var log = Logger.init(std.testing.allocator, console.writer(), .debug);
    defer log.deinit();

    StdLogWriter.setLogger(&log);

    // Test with format arguments
    StdLogWriter.logFn(.warn, .network, "Connection timeout after {} seconds", .{30});

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "[warn]"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "Connection timeout after 30 seconds"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "scope=network"));
}
