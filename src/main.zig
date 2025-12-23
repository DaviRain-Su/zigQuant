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
