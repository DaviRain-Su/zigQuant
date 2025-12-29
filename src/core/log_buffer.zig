//! Log Buffer - Ring Buffer for Log Storage
//!
//! Provides a thread-safe ring buffer for storing log entries that can be
//! queried via API. This enables real-time log viewing in the web dashboard.
//!
//! Features:
//! - Fixed-size ring buffer (no memory allocation after init)
//! - Thread-safe with mutex protection
//! - Level filtering support
//! - Timestamp-based querying

const std = @import("std");
const Allocator = std.mem.Allocator;
const logger = @import("logger.zig");
const Level = logger.Level;
const LogRecord = logger.LogRecord;
const LogWriter = logger.LogWriter;

// ============================================================================
// Log Entry for Storage
// ============================================================================

/// A stored log entry with owned memory
pub const LogEntry = struct {
    /// Log level
    level: Level,
    /// Log message (owned)
    message: []const u8,
    /// Unix timestamp in milliseconds
    timestamp: i64,
    /// Source/scope (owned, optional)
    source: ?[]const u8,
    /// Additional context (owned, optional)
    context: ?[]const u8,
};

// ============================================================================
// Ring Buffer
// ============================================================================

/// Ring buffer for log storage
pub const LogBuffer = struct {
    allocator: Allocator,
    entries: []?LogEntry,
    capacity: usize,
    head: usize, // Next write position
    tail: usize, // Oldest entry position
    count: usize, // Current number of entries
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Initialize the log buffer with a given capacity
    pub fn init(allocator: Allocator, capacity: usize) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const entries = try allocator.alloc(?LogEntry, capacity);
        @memset(entries, null);

        self.* = .{
            .allocator = allocator,
            .entries = entries,
            .capacity = capacity,
            .head = 0,
            .tail = 0,
            .count = 0,
            .mutex = .{},
        };

        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        // Free all stored entries
        for (self.entries) |entry_opt| {
            if (entry_opt) |entry| {
                self.allocator.free(entry.message);
                if (entry.source) |src| self.allocator.free(src);
                if (entry.context) |ctx| self.allocator.free(ctx);
            }
        }
        self.allocator.free(self.entries);
        self.allocator.destroy(self);
    }

    /// Add a log entry to the buffer
    pub fn push(self: *Self, level: Level, message: []const u8, source: ?[]const u8, context: ?[]const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // If buffer is full, free the oldest entry
        if (self.count == self.capacity) {
            if (self.entries[self.tail]) |old_entry| {
                self.allocator.free(old_entry.message);
                if (old_entry.source) |src| self.allocator.free(src);
                if (old_entry.context) |ctx| self.allocator.free(ctx);
            }
            self.tail = (self.tail + 1) % self.capacity;
        } else {
            self.count += 1;
        }

        // Copy strings
        const msg_copy = try self.allocator.dupe(u8, message);
        errdefer self.allocator.free(msg_copy);

        var src_copy: ?[]const u8 = null;
        if (source) |src| {
            src_copy = try self.allocator.dupe(u8, src);
        }
        errdefer if (src_copy) |s| self.allocator.free(s);

        var ctx_copy: ?[]const u8 = null;
        if (context) |ctx| {
            ctx_copy = try self.allocator.dupe(u8, ctx);
        }

        // Store new entry
        self.entries[self.head] = .{
            .level = level,
            .message = msg_copy,
            .timestamp = std.time.milliTimestamp(),
            .source = src_copy,
            .context = ctx_copy,
        };

        self.head = (self.head + 1) % self.capacity;
    }

    /// Push a LogRecord directly
    pub fn pushRecord(self: *Self, record: LogRecord) !void {
        // Extract source from fields if available
        var source: ?[]const u8 = null;
        for (record.fields) |field| {
            if (std.mem.eql(u8, field.key, "scope") or std.mem.eql(u8, field.key, "source")) {
                source = switch (field.value) {
                    .string => |s| s,
                    else => null,
                };
                break;
            }
        }

        try self.push(record.level, record.message, source, null);
    }

    /// Get recent logs with optional filtering
    pub fn getRecent(
        self: *Self,
        allocator: Allocator,
        limit: usize,
        min_level: ?Level,
        since_timestamp: ?i64,
    ) ![]LogEntry {
        self.mutex.lock();
        defer self.mutex.unlock();

        var results = std.ArrayList(LogEntry){};
        errdefer {
            for (results.items) |entry| {
                allocator.free(entry.message);
                if (entry.source) |src| allocator.free(src);
                if (entry.context) |ctx| allocator.free(ctx);
            }
            results.deinit(allocator);
        }

        if (self.count == 0) {
            return results.toOwnedSlice(allocator);
        }

        // Iterate from newest to oldest
        var idx = if (self.head == 0) self.capacity - 1 else self.head - 1;
        var checked: usize = 0;

        while (checked < self.count and results.items.len < limit) {
            if (self.entries[idx]) |entry| {
                // Apply filters
                var include = true;

                if (min_level) |min| {
                    if (entry.level.toInt() < min.toInt()) {
                        include = false;
                    }
                }

                if (since_timestamp) |since| {
                    if (entry.timestamp < since) {
                        include = false;
                    }
                }

                if (include) {
                    // Copy entry
                    const msg_copy = try allocator.dupe(u8, entry.message);
                    errdefer allocator.free(msg_copy);

                    var src_copy: ?[]const u8 = null;
                    if (entry.source) |src| {
                        src_copy = try allocator.dupe(u8, src);
                    }

                    var ctx_copy: ?[]const u8 = null;
                    if (entry.context) |ctx| {
                        ctx_copy = try allocator.dupe(u8, ctx);
                    }

                    try results.append(allocator, .{
                        .level = entry.level,
                        .message = msg_copy,
                        .timestamp = entry.timestamp,
                        .source = src_copy,
                        .context = ctx_copy,
                    });
                }
            }

            checked += 1;
            idx = if (idx == 0) self.capacity - 1 else idx - 1;
        }

        return results.toOwnedSlice(allocator);
    }

    /// Get the total count of entries
    pub fn getCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.count;
    }

    /// Clear all entries
    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.entries) |entry_opt| {
            if (entry_opt) |entry| {
                self.allocator.free(entry.message);
                if (entry.source) |src| self.allocator.free(src);
                if (entry.context) |ctx| self.allocator.free(ctx);
            }
        }
        @memset(self.entries, null);
        self.head = 0;
        self.tail = 0;
        self.count = 0;
    }
};

// ============================================================================
// Buffer Writer - Bridges Logger to LogBuffer
// ============================================================================

/// A LogWriter that writes to a LogBuffer
pub const BufferWriter = struct {
    buffer: *LogBuffer,
    min_level: Level,

    const Self = @This();

    pub fn init(buffer: *LogBuffer, min_level: Level) Self {
        return .{
            .buffer = buffer,
            .min_level = min_level,
        };
    }

    pub fn writer(self: *Self) LogWriter {
        return LogWriter{
            .ptr = self,
            .writeFn = writeFn,
            .flushFn = flushFn,
            .closeFn = closeFn,
        };
    }

    fn writeFn(ptr: *anyopaque, record: LogRecord) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // Level filtering
        if (record.level.toInt() < self.min_level.toInt()) {
            return;
        }

        try self.buffer.pushRecord(record);
    }

    fn flushFn(_: *anyopaque) anyerror!void {
        // Nothing to flush for in-memory buffer
    }

    fn closeFn(_: *anyopaque) void {
        // Nothing to close
    }
};

// ============================================================================
// Multi Writer - Write to multiple destinations
// ============================================================================

/// Writes to multiple LogWriters simultaneously
pub const MultiWriter = struct {
    writers: []LogWriter,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, writers: []const LogWriter) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const writers_copy = try allocator.alloc(LogWriter, writers.len);
        @memcpy(writers_copy, writers);

        self.* = .{
            .writers = writers_copy,
            .allocator = allocator,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.writers);
        self.allocator.destroy(self);
    }

    pub fn writer(self: *Self) LogWriter {
        return LogWriter{
            .ptr = self,
            .writeFn = writeFn,
            .flushFn = flushFn,
            .closeFn = closeFn,
        };
    }

    fn writeFn(ptr: *anyopaque, record: LogRecord) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        for (self.writers) |w| {
            try w.write(record);
        }
    }

    fn flushFn(ptr: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        for (self.writers) |w| {
            try w.flush();
        }
    }

    fn closeFn(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        for (self.writers) |w| {
            w.close();
        }
    }
};

// ============================================================================
// Global Log Buffer Instance
// ============================================================================

/// Global log buffer for API access
var global_log_buffer: ?*LogBuffer = null;

/// Initialize the global log buffer
pub fn initGlobalBuffer(allocator: Allocator, capacity: usize) !*LogBuffer {
    if (global_log_buffer != null) {
        return error.AlreadyInitialized;
    }
    global_log_buffer = try LogBuffer.init(allocator, capacity);
    return global_log_buffer.?;
}

/// Get the global log buffer
pub fn getGlobalBuffer() ?*LogBuffer {
    return global_log_buffer;
}

/// Deinitialize the global log buffer
pub fn deinitGlobalBuffer() void {
    if (global_log_buffer) |buffer| {
        buffer.deinit();
        global_log_buffer = null;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "LogBuffer basic operations" {
    const allocator = std.testing.allocator;

    const buffer = try LogBuffer.init(allocator, 10);
    defer buffer.deinit();

    // Push some entries
    try buffer.push(.info, "Test message 1", "test", null);
    try buffer.push(.warn, "Test message 2", null, null);
    try buffer.push(.err, "Test message 3", "error_source", "error context");

    try std.testing.expectEqual(@as(usize, 3), buffer.getCount());

    // Get recent logs
    const logs = try buffer.getRecent(allocator, 10, null, null);
    defer {
        for (logs) |entry| {
            allocator.free(entry.message);
            if (entry.source) |src| allocator.free(src);
            if (entry.context) |ctx| allocator.free(ctx);
        }
        allocator.free(logs);
    }

    try std.testing.expectEqual(@as(usize, 3), logs.len);
    // Newest first
    try std.testing.expectEqualStrings("Test message 3", logs[0].message);
    try std.testing.expectEqualStrings("Test message 2", logs[1].message);
    try std.testing.expectEqualStrings("Test message 1", logs[2].message);
}

test "LogBuffer ring buffer overflow" {
    const allocator = std.testing.allocator;

    const buffer = try LogBuffer.init(allocator, 3);
    defer buffer.deinit();

    // Push 5 entries (overflow by 2)
    try buffer.push(.info, "Message 1", null, null);
    try buffer.push(.info, "Message 2", null, null);
    try buffer.push(.info, "Message 3", null, null);
    try buffer.push(.info, "Message 4", null, null);
    try buffer.push(.info, "Message 5", null, null);

    // Should only have 3 entries
    try std.testing.expectEqual(@as(usize, 3), buffer.getCount());

    const logs = try buffer.getRecent(allocator, 10, null, null);
    defer {
        for (logs) |entry| {
            allocator.free(entry.message);
            if (entry.source) |src| allocator.free(src);
            if (entry.context) |ctx| allocator.free(ctx);
        }
        allocator.free(logs);
    }

    // Should have newest 3
    try std.testing.expectEqual(@as(usize, 3), logs.len);
    try std.testing.expectEqualStrings("Message 5", logs[0].message);
    try std.testing.expectEqualStrings("Message 4", logs[1].message);
    try std.testing.expectEqualStrings("Message 3", logs[2].message);
}

test "LogBuffer level filtering" {
    const allocator = std.testing.allocator;

    const buffer = try LogBuffer.init(allocator, 10);
    defer buffer.deinit();

    try buffer.push(.debug, "Debug message", null, null);
    try buffer.push(.info, "Info message", null, null);
    try buffer.push(.warn, "Warn message", null, null);
    try buffer.push(.err, "Error message", null, null);

    // Filter: only warn and above
    const logs = try buffer.getRecent(allocator, 10, .warn, null);
    defer {
        for (logs) |entry| {
            allocator.free(entry.message);
            if (entry.source) |src| allocator.free(src);
            if (entry.context) |ctx| allocator.free(ctx);
        }
        allocator.free(logs);
    }

    try std.testing.expectEqual(@as(usize, 2), logs.len);
    try std.testing.expectEqualStrings("Error message", logs[0].message);
    try std.testing.expectEqualStrings("Warn message", logs[1].message);
}
