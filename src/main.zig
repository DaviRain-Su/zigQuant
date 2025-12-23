const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== zigQuant - Time Module Demo ===\n\n", .{});

    // Get current timestamp
    const now = zigQuant.Timestamp.now();
    const now_iso = try now.toISO8601(allocator);
    defer allocator.free(now_iso);
    std.debug.print("Current timestamp: {} ms ({s})\n", .{ now.millis, now_iso });

    // Parse ISO 8601
    const parsed = try zigQuant.Timestamp.fromISO8601(allocator, "2024-01-15T10:30:00.500Z");
    const parsed_iso = try parsed.toISO8601(allocator);
    defer allocator.free(parsed_iso);
    std.debug.print("Parsed '2024-01-15T10:30:00.500Z': {} ms\n", .{parsed.millis});
    std.debug.print("  Roundtrip: {s}\n\n", .{parsed_iso});

    // Duration examples
    const one_hour = zigQuant.Duration.fromHours(1);
    const one_day = zigQuant.Duration.DAY;
    std.debug.print("One hour: {} ms ({}s)\n", .{ one_hour.millis, one_hour.toSeconds() });
    std.debug.print("One day: {} ms ({}s)\n\n", .{ one_day.millis, one_day.toSeconds() });

    // K-line alignment
    const ts = try zigQuant.Timestamp.fromISO8601(allocator, "2024-01-15T10:32:45Z");
    const aligned_5m = ts.alignToKline(.@"5m");
    const aligned_iso = try aligned_5m.toISO8601(allocator);
    defer allocator.free(aligned_iso);
    std.debug.print("Original: 2024-01-15T10:32:45Z\n", .{});
    std.debug.print("Aligned to 5m: {s}\n\n", .{aligned_iso});

    // K-line intervals
    std.debug.print("K-line intervals:\n", .{});
    inline for (@typeInfo(zigQuant.KlineInterval).@"enum".fields) |field| {
        const interval = @field(zigQuant.KlineInterval, field.name);
        std.debug.print("  {s}: {} ms\n", .{ interval.toString(), interval.toMillis() });
    }

    std.debug.print("\n=== zigQuant - Error System Demo ===\n\n", .{});

    // Error wrapping
    const ctx = zigQuant.ErrorContext.initWithCode(429, "Rate limit exceeded");
    std.debug.print("ErrorContext: code={?}, message={s}\n", .{ ctx.code, ctx.message });

    // Wrapped error with chain
    const wrapped1 = zigQuant.errors.wrap(zigQuant.NetworkError.Timeout, "Network timeout");
    const wrapped2 = zigQuant.errors.wrapWithSource(zigQuant.APIError.ServerError, "API call failed", &wrapped1);
    std.debug.print("Error chain depth: {}\n", .{wrapped2.chainDepth()});

    // Print error chain to buffer
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    try wrapped2.printChain(buf.writer(allocator));
    std.debug.print("{s}", .{buf.items});

    // Retry configuration
    const retry_config = zigQuant.RetryConfig{
        .max_retries = 3,
        .strategy = .exponential_backoff,
        .initial_delay_ms = 100,
        .max_delay_ms = 5000,
    };
    std.debug.print("\nRetry delays:\n", .{});
    for (0..4) |i| {
        const delay = retry_config.calculateDelay(@intCast(i));
        std.debug.print("  Attempt {}: {} ms\n", .{ i, delay });
    }

    // Error categorization
    std.debug.print("\nError categories:\n", .{});
    std.debug.print("  ConnectionFailed: {s}\n", .{zigQuant.errors.errorCategory(zigQuant.NetworkError.ConnectionFailed)});
    std.debug.print("  RateLimitExceeded: {s}\n", .{zigQuant.errors.errorCategory(zigQuant.APIError.RateLimitExceeded)});
    std.debug.print("  ParseError: {s}\n", .{zigQuant.errors.errorCategory(zigQuant.DataError.ParseError)});

    std.debug.print("\nRetryable errors:\n", .{});
    std.debug.print("  ConnectionFailed: {}\n", .{zigQuant.errors.isRetryable(zigQuant.NetworkError.ConnectionFailed)});
    std.debug.print("  Unauthorized: {}\n", .{zigQuant.errors.isRetryable(zigQuant.APIError.Unauthorized)});

    std.debug.print("\n=== Demo Complete ===\n", .{});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
