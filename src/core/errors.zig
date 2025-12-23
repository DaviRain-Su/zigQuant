// Error System - Unified Error Handling
//
// Provides a comprehensive error handling framework for quantitative trading:
// - 5 error categories: Network, API, Data, Business, System
// - Error context with rich metadata
// - Error wrapping and chaining
// - Automatic retry mechanisms
//
// Design principles:
// - Use Zig's error union types for type safety
// - Provide structured error information for debugging
// - Support retry logic for transient failures
// - Keep error handling overhead minimal

const std = @import("std");
const Allocator = std.mem.Allocator;
const time = @import("time.zig");

// ============================================================================
// Error Categories
// ============================================================================

/// Network-related errors
pub const NetworkError = error{
    ConnectionFailed,
    Timeout,
    DNSResolutionFailed,
    SSLError,
    HttpError,
    RequestFailed,
    ResponseFailed,
};

/// API-related errors
pub const APIError = error{
    Unauthorized,
    RateLimitExceeded,
    InvalidRequest,
    ServerError,
    BadRequest,
    NotFound,
};

/// Data parsing and validation errors
pub const DataError = error{
    InvalidFormat,
    ParseError,
    ValidationFailed,
    MissingField,
    TypeMismatch,
};

/// Business logic errors
pub const BusinessError = error{
    InsufficientBalance,
    OrderNotFound,
    InvalidOrderStatus,
    PositionNotFound,
    InvalidQuantity,
    MarketClosed,
};

/// System-level errors
pub const SystemError = error{
    OutOfMemory,
    FileNotFound,
    PermissionDenied,
    ResourceExhausted,
};

/// Combined error set for all trading errors
pub const TradingError = NetworkError || APIError || DataError || BusinessError || SystemError;

// ============================================================================
// Error Context
// ============================================================================

/// Rich error context with metadata
pub const ErrorContext = struct {
    /// Optional error code (e.g., HTTP status code)
    code: ?i32 = null,

    /// Human-readable error message
    message: []const u8,

    /// Source location (file:line)
    location: ?[]const u8 = null,

    /// Additional details
    details: ?[]const u8 = null,

    /// Timestamp when error occurred (Unix seconds)
    timestamp: i64,

    /// Create error context with current timestamp
    pub fn init(message: []const u8) ErrorContext {
        return .{
            .message = message,
            .timestamp = std.time.timestamp(),
        };
    }

    /// Create error context with code
    pub fn initWithCode(code: i32, message: []const u8) ErrorContext {
        return .{
            .code = code,
            .message = message,
            .timestamp = std.time.timestamp(),
        };
    }

    /// Format error context for display
    pub fn format(
        self: ErrorContext,
        writer: anytype,
    ) !void {
        try writer.print("Error", .{});
        if (self.code) |code| {
            try writer.print("[{d}]", .{code});
        }
        try writer.print(": {s}", .{self.message});

        if (self.location) |loc| {
            try writer.print(" at {s}", .{loc});
        }

        if (self.details) |details| {
            try writer.print(" - {s}", .{details});
        }

        try writer.print(" (ts={d})", .{self.timestamp});
    }
};

// ============================================================================
// Wrapped Error (Error Chain)
// ============================================================================

/// Wrapped error with source error tracking
pub const WrappedError = struct {
    /// The error type
    error_type: anyerror,

    /// Error context
    context: ErrorContext,

    /// Source error (forms error chain)
    source: ?*const WrappedError = null,

    /// Create wrapped error
    pub fn init(err: anyerror, context: ErrorContext) WrappedError {
        return .{
            .error_type = err,
            .context = context,
        };
    }

    /// Create wrapped error with source
    pub fn initWithSource(err: anyerror, context: ErrorContext, source: *const WrappedError) WrappedError {
        return .{
            .error_type = err,
            .context = context,
            .source = source,
        };
    }

    /// Get error chain depth
    pub fn chainDepth(self: *const WrappedError) usize {
        var depth: usize = 1;
        var current = self.source;
        while (current) |src| {
            depth += 1;
            current = src.source;
        }
        return depth;
    }

    /// Print error chain
    pub fn printChain(self: *const WrappedError, writer: anytype) !void {
        try writer.print("Error chain:\n", .{});
        try writer.print("  [0] {s}: {f}\n", .{ @errorName(self.error_type), self.context });

        var depth: usize = 1;
        var current = self.source;
        while (current) |src| {
            try writer.print("  [{d}] {s}: {f}\n", .{ depth, @errorName(src.error_type), src.context });
            depth += 1;
            current = src.source;
        }
    }
};

/// Wrap an error with additional context
pub fn wrap(err: anyerror, message: []const u8) WrappedError {
    return WrappedError.init(err, ErrorContext.init(message));
}

/// Wrap an error with code and message
pub fn wrapWithCode(err: anyerror, code: i32, message: []const u8) WrappedError {
    return WrappedError.init(err, ErrorContext.initWithCode(code, message));
}

/// Wrap an error with source error (create error chain)
pub fn wrapWithSource(err: anyerror, message: []const u8, source: *const WrappedError) WrappedError {
    return WrappedError.initWithSource(err, ErrorContext.init(message), source);
}

// ============================================================================
// Retry Mechanism
// ============================================================================

/// Retry strategy
pub const RetryStrategy = enum {
    /// Fixed delay between retries
    fixed_interval,

    /// Exponential backoff (delay doubles each retry)
    exponential_backoff,
};

/// Retry configuration
pub const RetryConfig = struct {
    /// Maximum number of retry attempts
    max_retries: u32 = 3,

    /// Retry strategy
    strategy: RetryStrategy = .exponential_backoff,

    /// Initial delay in milliseconds
    initial_delay_ms: u64 = 1000,

    /// Maximum delay in milliseconds (for exponential backoff)
    max_delay_ms: u64 = 60000,

    /// Calculate delay for given attempt number (0-indexed)
    pub fn calculateDelay(self: RetryConfig, attempt: u32) u64 {
        return switch (self.strategy) {
            .fixed_interval => self.initial_delay_ms,
            .exponential_backoff => blk: {
                // delay = initial_delay * 2^attempt, capped at max_delay
                const multiplier = std.math.pow(u64, 2, attempt);
                const delay = self.initial_delay_ms * multiplier;
                break :blk @min(delay, self.max_delay_ms);
            },
        };
    }
};

/// Retry a function with automatic retries
///
/// Example:
/// ```zig
/// const config = RetryConfig{ .max_retries = 3 };
/// const result = try retry(config, fetchData, .{url});
/// ```
pub fn retry(
    config: RetryConfig,
    comptime func: anytype,
    args: anytype,
) @TypeOf(@call(.auto, func, args)) {
    var attempt: u32 = 0;
    while (attempt <= config.max_retries) : (attempt += 1) {
        // Try to execute the function
        if (@call(.auto, func, args)) |result| {
            return result;
        } else |err| {
            // If this is the last attempt, return the error
            if (attempt >= config.max_retries) {
                return err;
            }

            // Calculate delay and sleep
            const delay_ms = config.calculateDelay(attempt);
            std.Thread.sleep(delay_ms * std.time.ns_per_ms);
        }
    }

    unreachable; // Should never reach here
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if an error is retryable
pub fn isRetryable(err: anyerror) bool {
    return switch (err) {
        // Network errors are typically retryable
        NetworkError.ConnectionFailed,
        NetworkError.Timeout,
        NetworkError.DNSResolutionFailed,
        => true,

        // Some API errors are retryable
        APIError.RateLimitExceeded,
        APIError.ServerError,
        => true,

        // System errors might be retryable
        SystemError.ResourceExhausted,
        => true,

        // Other errors are not retryable
        else => false,
    };
}

/// Get error category name
pub fn errorCategory(err: anyerror) []const u8 {
    // Check each error set
    inline for (@typeInfo(NetworkError).error_set.?) |e| {
        if (err == @field(NetworkError, e.name)) return "Network";
    }
    inline for (@typeInfo(APIError).error_set.?) |e| {
        if (err == @field(APIError, e.name)) return "API";
    }
    inline for (@typeInfo(DataError).error_set.?) |e| {
        if (err == @field(DataError, e.name)) return "Data";
    }
    inline for (@typeInfo(BusinessError).error_set.?) |e| {
        if (err == @field(BusinessError, e.name)) return "Business";
    }
    inline for (@typeInfo(SystemError).error_set.?) |e| {
        if (err == @field(SystemError, e.name)) return "System";
    }

    return "Unknown";
}

// ============================================================================
// Tests
// ============================================================================

test "Error categories" {
    // Network errors
    const net_err: NetworkError = NetworkError.ConnectionFailed;
    try std.testing.expectEqual(NetworkError.ConnectionFailed, net_err);

    // API errors
    const api_err: APIError = APIError.RateLimitExceeded;
    try std.testing.expectEqual(APIError.RateLimitExceeded, api_err);

    // Data errors
    const data_err: DataError = DataError.ParseError;
    try std.testing.expectEqual(DataError.ParseError, data_err);

    // Business errors
    const biz_err: BusinessError = BusinessError.InsufficientBalance;
    try std.testing.expectEqual(BusinessError.InsufficientBalance, biz_err);

    // System errors
    const sys_err: SystemError = SystemError.OutOfMemory;
    try std.testing.expectEqual(SystemError.OutOfMemory, sys_err);
}

test "ErrorContext creation" {
    const ctx1 = ErrorContext.init("Test error");
    try std.testing.expectEqualStrings("Test error", ctx1.message);
    try std.testing.expect(ctx1.code == null);
    try std.testing.expect(ctx1.timestamp > 0);

    const ctx2 = ErrorContext.initWithCode(404, "Not found");
    try std.testing.expectEqual(@as(i32, 404), ctx2.code.?);
    try std.testing.expectEqualStrings("Not found", ctx2.message);
}

test "WrappedError basic" {
    const ctx = ErrorContext.init("Connection failed");
    const wrapped = WrappedError.init(NetworkError.ConnectionFailed, ctx);

    try std.testing.expectEqual(NetworkError.ConnectionFailed, wrapped.error_type);
    try std.testing.expectEqualStrings("Connection failed", wrapped.context.message);
    try std.testing.expect(wrapped.source == null);
    try std.testing.expectEqual(@as(usize, 1), wrapped.chainDepth());
}

test "WrappedError chain" {
    const ctx1 = ErrorContext.init("Root cause");
    const wrapped1 = WrappedError.init(NetworkError.Timeout, ctx1);

    const ctx2 = ErrorContext.init("Intermediate error");
    const wrapped2 = WrappedError.initWithSource(APIError.ServerError, ctx2, &wrapped1);

    const ctx3 = ErrorContext.init("Top-level error");
    const wrapped3 = WrappedError.initWithSource(DataError.ParseError, ctx3, &wrapped2);

    try std.testing.expectEqual(@as(usize, 3), wrapped3.chainDepth());
    try std.testing.expectEqual(@as(usize, 2), wrapped2.chainDepth());
    try std.testing.expectEqual(@as(usize, 1), wrapped1.chainDepth());
}

test "wrap helpers" {
    const wrapped1 = wrap(NetworkError.ConnectionFailed, "Failed to connect");
    try std.testing.expectEqual(NetworkError.ConnectionFailed, wrapped1.error_type);
    try std.testing.expectEqualStrings("Failed to connect", wrapped1.context.message);

    const wrapped2 = wrapWithCode(APIError.RateLimitExceeded, 429, "Rate limit");
    try std.testing.expectEqual(APIError.RateLimitExceeded, wrapped2.error_type);
    try std.testing.expectEqual(@as(i32, 429), wrapped2.context.code.?);

    const wrapped3 = wrapWithSource(DataError.ParseError, "Parse failed", &wrapped1);
    try std.testing.expectEqual(@as(usize, 2), wrapped3.chainDepth());
}

test "RetryConfig delay calculation" {
    const fixed_config = RetryConfig{
        .strategy = .fixed_interval,
        .initial_delay_ms = 1000,
    };

    try std.testing.expectEqual(@as(u64, 1000), fixed_config.calculateDelay(0));
    try std.testing.expectEqual(@as(u64, 1000), fixed_config.calculateDelay(1));
    try std.testing.expectEqual(@as(u64, 1000), fixed_config.calculateDelay(5));

    const exp_config = RetryConfig{
        .strategy = .exponential_backoff,
        .initial_delay_ms = 1000,
        .max_delay_ms = 10000,
    };

    try std.testing.expectEqual(@as(u64, 1000), exp_config.calculateDelay(0)); // 1000 * 2^0 = 1000
    try std.testing.expectEqual(@as(u64, 2000), exp_config.calculateDelay(1)); // 1000 * 2^1 = 2000
    try std.testing.expectEqual(@as(u64, 4000), exp_config.calculateDelay(2)); // 1000 * 2^2 = 4000
    try std.testing.expectEqual(@as(u64, 8000), exp_config.calculateDelay(3)); // 1000 * 2^3 = 8000
    try std.testing.expectEqual(@as(u64, 10000), exp_config.calculateDelay(4)); // capped at max_delay
}

test "retry mechanism - success on first try" {
    var call_count: u32 = 0;

    const testFunc = struct {
        fn func(count: *u32) !u32 {
            count.* += 1;
            return 42;
        }
    }.func;

    const config = RetryConfig{ .max_retries = 3, .initial_delay_ms = 1 };
    const result = try retry(config, testFunc, .{&call_count});

    try std.testing.expectEqual(@as(u32, 42), result);
    try std.testing.expectEqual(@as(u32, 1), call_count);
}

test "retry mechanism - success after retries" {
    var call_count: u32 = 0;

    const testFunc = struct {
        fn func(count: *u32) !u32 {
            count.* += 1;
            if (count.* < 3) {
                return NetworkError.Timeout;
            }
            return 42;
        }
    }.func;

    const config = RetryConfig{ .max_retries = 5, .initial_delay_ms = 1 };
    const result = try retry(config, testFunc, .{&call_count});

    try std.testing.expectEqual(@as(u32, 42), result);
    try std.testing.expectEqual(@as(u32, 3), call_count);
}

test "retry mechanism - fail after max retries" {
    var call_count: u32 = 0;

    const testFunc = struct {
        fn func(count: *u32) !u32 {
            count.* += 1;
            return NetworkError.Timeout;
        }
    }.func;

    const config = RetryConfig{ .max_retries = 3, .initial_delay_ms = 1 };
    const result = retry(config, testFunc, .{&call_count});

    try std.testing.expectError(NetworkError.Timeout, result);
    try std.testing.expectEqual(@as(u32, 4), call_count); // Initial + 3 retries
}

test "isRetryable" {
    // Retryable errors
    try std.testing.expect(isRetryable(NetworkError.ConnectionFailed));
    try std.testing.expect(isRetryable(NetworkError.Timeout));
    try std.testing.expect(isRetryable(APIError.RateLimitExceeded));
    try std.testing.expect(isRetryable(APIError.ServerError));

    // Non-retryable errors
    try std.testing.expect(!isRetryable(APIError.Unauthorized));
    try std.testing.expect(!isRetryable(DataError.InvalidFormat));
    try std.testing.expect(!isRetryable(BusinessError.InsufficientBalance));
}

test "errorCategory" {
    try std.testing.expectEqualStrings("Network", errorCategory(NetworkError.ConnectionFailed));
    try std.testing.expectEqualStrings("API", errorCategory(APIError.RateLimitExceeded));
    try std.testing.expectEqualStrings("Data", errorCategory(DataError.ParseError));
    try std.testing.expectEqualStrings("Business", errorCategory(BusinessError.OrderNotFound));
    try std.testing.expectEqualStrings("System", errorCategory(SystemError.OutOfMemory));
}
