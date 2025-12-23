// Time Module - Timestamp, Duration, and K-line Interval Management
//
// Provides high-precision time handling for quantitative trading:
// - Timestamp: Millisecond-precision timestamps
// - Duration: Time intervals and arithmetic
// - KlineInterval: Candlestick intervals (1m, 5m, 15m, etc.)
// - ISO 8601 parsing and formatting
// - K-line alignment algorithms

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Timestamp represents a point in time with millisecond precision
pub const Timestamp = struct {
    millis: i64,

    /// Get current timestamp
    pub fn now() Timestamp {
        return .{ .millis = std.time.milliTimestamp() };
    }

    /// Create timestamp from seconds
    pub fn fromSeconds(seconds: i64) Timestamp {
        return .{ .millis = seconds * 1000 };
    }

    /// Create timestamp from milliseconds
    pub fn fromMillis(millis: i64) Timestamp {
        return .{ .millis = millis };
    }

    /// Create timestamp from ISO 8601 string (e.g., "2024-01-15T10:30:00Z")
    pub fn fromISO8601(allocator: Allocator, iso_str: []const u8) !Timestamp {
        _ = allocator;

        // Parse ISO 8601: YYYY-MM-DDTHH:MM:SSZ or YYYY-MM-DDTHH:MM:SS.sssZ
        if (iso_str.len < 20) return error.InvalidISO8601Format;

        // Extract components
        const year = try std.fmt.parseInt(i32, iso_str[0..4], 10);
        const month = try std.fmt.parseInt(u8, iso_str[5..7], 10);
        const day = try std.fmt.parseInt(u8, iso_str[8..10], 10);
        const hour = try std.fmt.parseInt(u8, iso_str[11..13], 10);
        const minute = try std.fmt.parseInt(u8, iso_str[14..16], 10);
        const second = try std.fmt.parseInt(u8, iso_str[17..19], 10);

        // Optional milliseconds
        var millis_part: i64 = 0;
        if (iso_str.len > 20 and iso_str[19] == '.') {
            // Find the end of milliseconds (before 'Z' or '+' or '-')
            var end_idx: usize = 20;
            while (end_idx < iso_str.len and iso_str[end_idx] >= '0' and iso_str[end_idx] <= '9') {
                end_idx += 1;
            }
            const millis_str = iso_str[20..end_idx];
            if (millis_str.len > 0) {
                millis_part = try std.fmt.parseInt(i64, millis_str, 10);
                // Normalize to milliseconds (could be microseconds or nanoseconds)
                if (millis_str.len == 1) millis_part *= 100;
                if (millis_str.len == 2) millis_part *= 10;
                // If more than 3 digits, truncate
                if (millis_str.len > 3) millis_part = @divFloor(millis_part, std.math.pow(i64, 10, @as(i64, @intCast(millis_str.len - 3))));
            }
        }

        // Validate ranges
        if (month < 1 or month > 12) return error.InvalidMonth;
        if (day < 1 or day > 31) return error.InvalidDay;
        if (hour > 23) return error.InvalidHour;
        if (minute > 59) return error.InvalidMinute;
        if (second > 59) return error.InvalidSecond;

        // Convert to Unix timestamp using Gregorian calendar algorithm
        const timestamp_seconds = dateTimeToUnixTimestamp(year, month, day, hour, minute, second);
        return .{ .millis = timestamp_seconds * 1000 + millis_part };
    }

    /// Convert to ISO 8601 string
    pub fn toISO8601(self: Timestamp, allocator: Allocator) ![]const u8 {
        const seconds = @divFloor(self.millis, 1000);
        const millis = @mod(self.millis, 1000);

        const dt = unixTimestampToDateTime(seconds);

        // Handle negative milliseconds for formatting
        const abs_millis = if (millis < 0) -millis else millis;

        // Cast to unsigned to avoid + sign with padding format
        const year_u: u32 = @intCast(dt.year);
        const millis_u: u64 = @intCast(abs_millis);

        var buf: [30]u8 = undefined;
        const result = try std.fmt.bufPrint(
            &buf,
            "{:0>4}-{:0>2}-{:0>2}T{:0>2}:{:0>2}:{:0>2}.{:0>3}Z",
            .{ year_u, dt.month, dt.day, dt.hour, dt.minute, dt.second, millis_u },
        );
        return allocator.dupe(u8, result);
    }

    /// Convert to seconds
    pub fn toSeconds(self: Timestamp) i64 {
        return @divFloor(self.millis, 1000);
    }

    /// Convert to milliseconds
    pub fn toMillis(self: Timestamp) i64 {
        return self.millis;
    }

    /// Add duration
    pub fn add(self: Timestamp, duration: Duration) Timestamp {
        return .{ .millis = self.millis + duration.millis };
    }

    /// Subtract duration
    pub fn sub(self: Timestamp, duration: Duration) Timestamp {
        return .{ .millis = self.millis - duration.millis };
    }

    /// Calculate difference between two timestamps
    pub fn diff(self: Timestamp, other: Timestamp) Duration {
        return .{ .millis = self.millis - other.millis };
    }

    /// Compare timestamps
    pub fn cmp(self: Timestamp, other: Timestamp) std.math.Order {
        return std.math.order(self.millis, other.millis);
    }

    /// Check equality
    pub fn eql(self: Timestamp, other: Timestamp) bool {
        return self.millis == other.millis;
    }

    /// Align timestamp to K-line interval
    pub fn alignToKline(self: Timestamp, interval: KlineInterval) Timestamp {
        const interval_ms = interval.toMillis();
        const aligned_ms = @divFloor(self.millis, interval_ms) * interval_ms;
        return .{ .millis = aligned_ms };
    }

    /// Check if two timestamps are in the same K-line
    pub fn isInSameKline(self: Timestamp, other: Timestamp, interval: KlineInterval) bool {
        const aligned1 = self.alignToKline(interval);
        const aligned2 = other.alignToKline(interval);
        return aligned1.eql(aligned2);
    }

    /// Format for display
    pub fn format(
        self: Timestamp,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Timestamp({d}ms)", .{self.millis});
    }
};

/// Duration represents a time interval
pub const Duration = struct {
    millis: i64,

    // Common constants
    pub const ZERO = Duration{ .millis = 0 };
    pub const SECOND = Duration{ .millis = 1000 };
    pub const MINUTE = Duration{ .millis = 60 * 1000 };
    pub const HOUR = Duration{ .millis = 60 * 60 * 1000 };
    pub const DAY = Duration{ .millis = 24 * 60 * 60 * 1000 };

    /// Create from milliseconds
    pub fn fromMillis(millis: i64) Duration {
        return .{ .millis = millis };
    }

    /// Create from seconds
    pub fn fromSeconds(seconds: i64) Duration {
        return .{ .millis = seconds * 1000 };
    }

    /// Create from minutes
    pub fn fromMinutes(minutes: i64) Duration {
        return .{ .millis = minutes * 60 * 1000 };
    }

    /// Create from hours
    pub fn fromHours(hours: i64) Duration {
        return .{ .millis = hours * 60 * 60 * 1000 };
    }

    /// Create from days
    pub fn fromDays(days: i64) Duration {
        return .{ .millis = days * 24 * 60 * 60 * 1000 };
    }

    /// Convert to milliseconds
    pub fn toMillis(self: Duration) i64 {
        return self.millis;
    }

    /// Convert to seconds
    pub fn toSeconds(self: Duration) i64 {
        return @divFloor(self.millis, 1000);
    }

    /// Add durations
    pub fn add(self: Duration, other: Duration) Duration {
        return .{ .millis = self.millis + other.millis };
    }

    /// Subtract durations
    pub fn sub(self: Duration, other: Duration) Duration {
        return .{ .millis = self.millis - other.millis };
    }

    /// Multiply duration
    pub fn mul(self: Duration, factor: i64) Duration {
        return .{ .millis = self.millis * factor };
    }

    /// Format for display
    pub fn format(
        self: Duration,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const abs_millis = if (self.millis < 0) -self.millis else self.millis;
        const sign = if (self.millis < 0) "-" else "";

        const days = @divFloor(abs_millis, 24 * 60 * 60 * 1000);
        const hours = @divFloor(@mod(abs_millis, 24 * 60 * 60 * 1000), 60 * 60 * 1000);
        const minutes = @divFloor(@mod(abs_millis, 60 * 60 * 1000), 60 * 1000);
        const seconds = @divFloor(@mod(abs_millis, 60 * 1000), 1000);
        const millis = @mod(abs_millis, 1000);

        if (days > 0) {
            try writer.print("{s}{d}d{d}h{d}m{d}.{d:0>3}s", .{ sign, days, hours, minutes, seconds, millis });
        } else if (hours > 0) {
            try writer.print("{s}{d}h{d}m{d}.{d:0>3}s", .{ sign, hours, minutes, seconds, millis });
        } else if (minutes > 0) {
            try writer.print("{s}{d}m{d}.{d:0>3}s", .{ sign, minutes, seconds, millis });
        } else {
            try writer.print("{s}{d}.{d:0>3}s", .{ sign, seconds, millis });
        }
    }
};

/// K-line interval (candlestick interval)
pub const KlineInterval = enum {
    @"1m",
    @"5m",
    @"15m",
    @"30m",
    @"1h",
    @"4h",
    @"1d",
    @"1w",

    /// Convert to milliseconds
    pub fn toMillis(self: KlineInterval) i64 {
        return switch (self) {
            .@"1m" => 60 * 1000,
            .@"5m" => 5 * 60 * 1000,
            .@"15m" => 15 * 60 * 1000,
            .@"30m" => 30 * 60 * 1000,
            .@"1h" => 60 * 60 * 1000,
            .@"4h" => 4 * 60 * 60 * 1000,
            .@"1d" => 24 * 60 * 60 * 1000,
            .@"1w" => 7 * 24 * 60 * 60 * 1000,
        };
    }

    /// Parse from string
    pub fn fromString(str: []const u8) !KlineInterval {
        if (std.mem.eql(u8, str, "1m")) return .@"1m";
        if (std.mem.eql(u8, str, "5m")) return .@"5m";
        if (std.mem.eql(u8, str, "15m")) return .@"15m";
        if (std.mem.eql(u8, str, "30m")) return .@"30m";
        if (std.mem.eql(u8, str, "1h")) return .@"1h";
        if (std.mem.eql(u8, str, "4h")) return .@"4h";
        if (std.mem.eql(u8, str, "1d")) return .@"1d";
        if (std.mem.eql(u8, str, "1w")) return .@"1w";
        return error.InvalidKlineInterval;
    }

    /// Convert to string
    pub fn toString(self: KlineInterval) []const u8 {
        return switch (self) {
            .@"1m" => "1m",
            .@"5m" => "5m",
            .@"15m" => "15m",
            .@"30m" => "30m",
            .@"1h" => "1h",
            .@"4h" => "4h",
            .@"1d" => "1d",
            .@"1w" => "1w",
        };
    }
};

// Helper structures for date-time conversion
const DateTime = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
};

/// Convert date-time to Unix timestamp (seconds since 1970-01-01 00:00:00 UTC)
/// Using simplified Gregorian calendar algorithm
fn dateTimeToUnixTimestamp(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8) i64 {
    // Days in each month (non-leap year)
    const days_in_month = [_]i32{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    // Calculate years since epoch (1970)
    const years_since_epoch: i32 = year - 1970;

    // Count leap years between 1970 and year (exclusive)
    var leap_days: i32 = 0;
    var y: i32 = 1970;
    while (y < year) : (y += 1) {
        if (isLeapYear(y)) leap_days += 1;
    }

    // Calculate days from years
    var days: i32 = years_since_epoch * 365 + leap_days;

    // Add days from months in current year
    var m: usize = 0;
    while (m < month - 1) : (m += 1) {
        days += days_in_month[m];
        // Add extra day for February in leap year
        if (m == 1 and isLeapYear(year)) {
            days += 1;
        }
    }

    // Add remaining days
    days += @as(i32, day) - 1;

    const seconds_in_day = @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);
    return @as(i64, days) * 86400 + seconds_in_day;
}

/// Check if a year is a leap year
fn isLeapYear(year: i32) bool {
    if (@mod(year, 400) == 0) return true;
    if (@mod(year, 100) == 0) return false;
    if (@mod(year, 4) == 0) return true;
    return false;
}

/// Convert Unix timestamp to date-time
fn unixTimestampToDateTime(timestamp: i64) DateTime {
    const seconds_in_day = @mod(timestamp, 86400);
    var days_since_epoch = @divFloor(timestamp, 86400);

    // Calculate time components
    const hour: u8 = @intCast(@divFloor(seconds_in_day, 3600));
    const minute: u8 = @intCast(@divFloor(@mod(seconds_in_day, 3600), 60));
    const second: u8 = @intCast(@mod(seconds_in_day, 60));

    // Calculate year
    var year: i32 = 1970;
    while (true) {
        const days_in_year: i32 = if (isLeapYear(year)) 366 else 365;
        if (days_since_epoch < days_in_year) break;
        days_since_epoch -= days_in_year;
        year += 1;
    }

    // Calculate month and day
    const days_in_month = [_]i32{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var month: u8 = 1;
    var m: usize = 0;
    while (m < 12) : (m += 1) {
        var days_this_month = days_in_month[m];
        if (m == 1 and isLeapYear(year)) {
            days_this_month += 1;
        }
        if (days_since_epoch < days_this_month) {
            month = @intCast(m + 1);
            break;
        }
        days_since_epoch -= days_this_month;
    }

    const day: u8 = @intCast(days_since_epoch + 1);

    return .{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

// Tests
test "Timestamp creation and conversion" {
    const ts1 = Timestamp.fromSeconds(1705314600); // 2024-01-15 10:30:00 UTC
    try std.testing.expectEqual(@as(i64, 1705314600000), ts1.millis);
    try std.testing.expectEqual(@as(i64, 1705314600), ts1.toSeconds());

    const ts2 = Timestamp.fromMillis(1705315800500);
    try std.testing.expectEqual(@as(i64, 1705315800500), ts2.millis);
}

test "Timestamp arithmetic" {
    const ts = Timestamp.fromSeconds(1000);
    const dur = Duration.fromSeconds(100);

    const added = ts.add(dur);
    try std.testing.expectEqual(@as(i64, 1100000), added.millis);

    const subtracted = ts.sub(dur);
    try std.testing.expectEqual(@as(i64, 900000), subtracted.millis);

    const diff = added.diff(subtracted);
    try std.testing.expectEqual(@as(i64, 200000), diff.millis);
}

test "Timestamp comparison" {
    const ts1 = Timestamp.fromSeconds(1000);
    const ts2 = Timestamp.fromSeconds(2000);
    const ts3 = Timestamp.fromSeconds(1000);

    try std.testing.expect(ts1.cmp(ts2) == .lt);
    try std.testing.expect(ts2.cmp(ts1) == .gt);
    try std.testing.expect(ts1.cmp(ts3) == .eq);
    try std.testing.expect(ts1.eql(ts3));
    try std.testing.expect(!ts1.eql(ts2));
}

test "ISO 8601 parsing" {
    const allocator = std.testing.allocator;

    const ts1 = try Timestamp.fromISO8601(allocator, "2024-01-15T10:30:00Z");
    try std.testing.expectEqual(@as(i64, 1705314600000), ts1.millis);

    const ts2 = try Timestamp.fromISO8601(allocator, "2024-01-15T10:30:00.500Z");
    try std.testing.expectEqual(@as(i64, 1705314600500), ts2.millis);
}

test "ISO 8601 formatting" {
    const allocator = std.testing.allocator;

    const ts = Timestamp.fromMillis(1705314600500);
    const iso_str = try ts.toISO8601(allocator);
    defer allocator.free(iso_str);

    try std.testing.expectEqualStrings("2024-01-15T10:30:00.500Z", iso_str);
}

test "K-line alignment" {
    const ts = Timestamp.fromISO8601(std.testing.allocator, "2024-01-15T10:32:45Z") catch unreachable;

    const aligned_1m = ts.alignToKline(.@"1m");
    const expected_1m = Timestamp.fromISO8601(std.testing.allocator, "2024-01-15T10:32:00Z") catch unreachable;
    try std.testing.expect(aligned_1m.eql(expected_1m));

    const aligned_5m = ts.alignToKline(.@"5m");
    const expected_5m = Timestamp.fromISO8601(std.testing.allocator, "2024-01-15T10:30:00Z") catch unreachable;
    try std.testing.expect(aligned_5m.eql(expected_5m));
}

test "K-line same interval check" {
    const ts1 = Timestamp.fromISO8601(std.testing.allocator, "2024-01-15T10:32:45Z") catch unreachable;
    const ts2 = Timestamp.fromISO8601(std.testing.allocator, "2024-01-15T10:33:15Z") catch unreachable;
    const ts3 = Timestamp.fromISO8601(std.testing.allocator, "2024-01-15T10:37:00Z") catch unreachable;

    try std.testing.expect(ts1.isInSameKline(ts2, .@"5m"));
    try std.testing.expect(!ts1.isInSameKline(ts3, .@"5m"));
}

test "Duration creation and conversion" {
    const dur1 = Duration.fromSeconds(100);
    try std.testing.expectEqual(@as(i64, 100000), dur1.millis);
    try std.testing.expectEqual(@as(i64, 100), dur1.toSeconds());

    const dur2 = Duration.fromMinutes(5);
    try std.testing.expectEqual(@as(i64, 300000), dur2.millis);

    const dur3 = Duration.fromHours(2);
    try std.testing.expectEqual(@as(i64, 7200000), dur3.millis);
}

test "Duration arithmetic" {
    const dur1 = Duration.fromSeconds(100);
    const dur2 = Duration.fromSeconds(50);

    const added = dur1.add(dur2);
    try std.testing.expectEqual(@as(i64, 150000), added.millis);

    const subtracted = dur1.sub(dur2);
    try std.testing.expectEqual(@as(i64, 50000), subtracted.millis);

    const multiplied = dur1.mul(3);
    try std.testing.expectEqual(@as(i64, 300000), multiplied.millis);
}

test "Duration constants" {
    try std.testing.expectEqual(@as(i64, 0), Duration.ZERO.millis);
    try std.testing.expectEqual(@as(i64, 1000), Duration.SECOND.millis);
    try std.testing.expectEqual(@as(i64, 60000), Duration.MINUTE.millis);
    try std.testing.expectEqual(@as(i64, 3600000), Duration.HOUR.millis);
    try std.testing.expectEqual(@as(i64, 86400000), Duration.DAY.millis);
}

test "KlineInterval conversion" {
    try std.testing.expectEqual(@as(i64, 60000), KlineInterval.@"1m".toMillis());
    try std.testing.expectEqual(@as(i64, 300000), KlineInterval.@"5m".toMillis());
    try std.testing.expectEqual(@as(i64, 3600000), KlineInterval.@"1h".toMillis());
    try std.testing.expectEqual(@as(i64, 86400000), KlineInterval.@"1d".toMillis());
}

test "KlineInterval parsing" {
    try std.testing.expectEqual(KlineInterval.@"1m", try KlineInterval.fromString("1m"));
    try std.testing.expectEqual(KlineInterval.@"5m", try KlineInterval.fromString("5m"));
    try std.testing.expectEqual(KlineInterval.@"1h", try KlineInterval.fromString("1h"));
    try std.testing.expectEqual(KlineInterval.@"1d", try KlineInterval.fromString("1d"));

    try std.testing.expectError(error.InvalidKlineInterval, KlineInterval.fromString("invalid"));
}

test "KlineInterval toString" {
    try std.testing.expectEqualStrings("1m", KlineInterval.@"1m".toString());
    try std.testing.expectEqualStrings("5m", KlineInterval.@"5m".toString());
    try std.testing.expectEqualStrings("1h", KlineInterval.@"1h".toString());
    try std.testing.expectEqualStrings("1d", KlineInterval.@"1d".toString());
}
