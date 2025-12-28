//! Request Logger Middleware
//!
//! Logs HTTP requests with timing information for debugging and monitoring.

const std = @import("std");

/// Log entry for a request
pub const LogEntry = struct {
    method: []const u8,
    path: []const u8,
    status: u16,
    duration_ms: f64,
    timestamp: i64,
};

/// Log level for request logging
pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,

    pub fn toStdLogLevel(self: LogLevel) std.log.Level {
        return switch (self) {
            .debug => .debug,
            .info => .info,
            .warn => .warn,
            .err => .err,
        };
    }
};

/// Logger configuration
pub const LoggerConfig = struct {
    /// Minimum log level
    level: LogLevel = .info,
    /// Include query parameters in log
    include_query: bool = false,
    /// Include request headers in log
    include_headers: bool = false,
    /// Paths to exclude from logging (e.g., health checks)
    exclude_paths: []const []const u8 = &.{},
};

/// Format a log entry as a string
pub fn formatLogEntry(
    allocator: std.mem.Allocator,
    entry: LogEntry,
) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{s} {s} -> {d} ({d:.2}ms)",
        .{
            entry.method,
            entry.path,
            entry.status,
            entry.duration_ms,
        },
    );
}

/// Log a request using std.log
pub fn logRequest(entry: LogEntry, level: LogLevel) void {
    switch (level) {
        .debug => std.log.debug("{s} {s} -> {d} ({d:.2}ms)", .{
            entry.method,
            entry.path,
            entry.status,
            entry.duration_ms,
        }),
        .info => std.log.info("{s} {s} -> {d} ({d:.2}ms)", .{
            entry.method,
            entry.path,
            entry.status,
            entry.duration_ms,
        }),
        .warn => std.log.warn("{s} {s} -> {d} ({d:.2}ms)", .{
            entry.method,
            entry.path,
            entry.status,
            entry.duration_ms,
        }),
        .err => std.log.err("{s} {s} -> {d} ({d:.2}ms)", .{
            entry.method,
            entry.path,
            entry.status,
            entry.duration_ms,
        }),
    }
}

/// Get log level based on status code
pub fn levelForStatus(status: u16) LogLevel {
    return if (status >= 500)
        .err
    else if (status >= 400)
        .warn
    else
        .info;
}

/// Check if a path should be excluded from logging
pub fn shouldExclude(path: []const u8, exclude_paths: []const []const u8) bool {
    for (exclude_paths) |exclude| {
        if (std.mem.eql(u8, path, exclude)) {
            return true;
        }
        // Support prefix matching with wildcard
        if (exclude.len > 0 and exclude[exclude.len - 1] == '*') {
            if (std.mem.startsWith(u8, path, exclude[0 .. exclude.len - 1])) {
                return true;
            }
        }
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "formatLogEntry" {
    const allocator = std.testing.allocator;
    const entry = LogEntry{
        .method = "GET",
        .path = "/api/v1/health",
        .status = 200,
        .duration_ms = 1.5,
        .timestamp = 1735344000,
    };

    const formatted = try formatLogEntry(allocator, entry);
    defer allocator.free(formatted);

    try std.testing.expectEqualStrings("GET /api/v1/health -> 200 (1.50ms)", formatted);
}

test "levelForStatus" {
    try std.testing.expectEqual(LogLevel.info, levelForStatus(200));
    try std.testing.expectEqual(LogLevel.info, levelForStatus(201));
    try std.testing.expectEqual(LogLevel.info, levelForStatus(204));
    try std.testing.expectEqual(LogLevel.warn, levelForStatus(400));
    try std.testing.expectEqual(LogLevel.warn, levelForStatus(404));
    try std.testing.expectEqual(LogLevel.err, levelForStatus(500));
    try std.testing.expectEqual(LogLevel.err, levelForStatus(503));
}

test "shouldExclude: exact match" {
    const excludes = &[_][]const u8{ "/health", "/ready" };
    try std.testing.expect(shouldExclude("/health", excludes));
    try std.testing.expect(shouldExclude("/ready", excludes));
    try std.testing.expect(!shouldExclude("/api/v1/health", excludes));
}

test "shouldExclude: wildcard match" {
    const excludes = &[_][]const u8{"/metrics*"};
    try std.testing.expect(shouldExclude("/metrics", excludes));
    try std.testing.expect(shouldExclude("/metrics/prometheus", excludes));
    try std.testing.expect(!shouldExclude("/api/metrics", excludes));
}
