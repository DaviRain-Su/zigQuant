// Time Module - Timestamp, Duration, and K-line Interval Management
//
// Provides high-precision time handling for quantitative trading by wrapping
// and extending Zig's standard library time utilities.
//
// Features:
// - Timestamp: Millisecond-precision timestamps (wraps std.time)
// - Duration: Time intervals and arithmetic
// - KlineInterval: Candlestick intervals (1m, 5m, 15m, etc.)
// - ISO 8601 parsing and formatting (uses std.time.epoch)
// - K-line alignment algorithms

const std = @import("std");
const Allocator = std.mem.Allocator;
const epoch = std.time.epoch;

/// Timestamp represents a point in time with millisecond precision
/// Wraps std.time.milliTimestamp with additional trading-specific functionality
pub const Timestamp = struct {
    millis: i64,

    /// Get current timestamp using std.time
    pub fn now() Timestamp {
        return .{ .millis = std.time.milliTimestamp() };
    }

    /// Create timestamp from seconds
    pub fn fromSeconds(seconds: i64) Timestamp {
        return .{ .millis = seconds * std.time.ms_per_s };
    }

    /// Create timestamp from milliseconds
    pub fn fromMillis(millis: i64) Timestamp {
        return .{ .millis = millis };
    }

    /// Create timestamp from ISO 8601 string (e.g., "2024-01-15T10:30:00Z")
    /// Uses manual date calculation since std.time.epoch doesn't provide reverse conversion
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
            var end_idx: usize = 20;
            while (end_idx < iso_str.len and iso_str[end_idx] >= '0' and iso_str[end_idx] <= '9') {
                end_idx += 1;
            }
            const millis_str = iso_str[20..end_idx];
            if (millis_str.len > 0) {
                millis_part = try std.fmt.parseInt(i64, millis_str, 10);
                // Normalize to milliseconds
                if (millis_str.len == 1) millis_part *= 100;
                if (millis_str.len == 2) millis_part *= 10;
                if (millis_str.len > 3) millis_part = @divFloor(millis_part, std.math.pow(i64, 10, @as(i64, @intCast(millis_str.len - 3))));
            }
        }

        // Validate ranges
        if (month < 1 or month > 12) return error.InvalidMonth;
        if (day < 1 or day > 31) return error.InvalidDay;
        if (hour > 23) return error.InvalidHour;
        if (minute > 59) return error.InvalidMinute;
        if (second > 59) return error.InvalidSecond;

        // Convert to Unix timestamp using manual calculation
        // (std.time.epoch doesn't provide reverse conversion)
        const timestamp_seconds = dateToEpochSeconds(year, month, day, hour, minute, second);

        return .{ .millis = timestamp_seconds * std.time.ms_per_s + millis_part };
    }

    /// Convert to ISO 8601 string
    /// Uses std.time.epoch for date formatting
    pub fn toISO8601(self: Timestamp, allocator: Allocator) ![]const u8 {
        const seconds: u64 = @intCast(@divFloor(self.millis, std.time.ms_per_s));
        const millis = @mod(self.millis, std.time.ms_per_s);

        // Use std.time.epoch to convert from Unix timestamp
        const epoch_seconds = epoch.EpochSeconds{ .secs = seconds };
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = epoch_seconds.getDaySeconds();

        const year: u32 = @intCast(year_day.year);
        const month: u8 = month_day.month.numeric();
        const day: u8 = month_day.day_index + 1;
        const hour: u8 = @intCast(day_seconds.getHoursIntoDay());
        const minute: u8 = @intCast(day_seconds.getMinutesIntoHour());
        const second: u8 = @intCast(day_seconds.getSecondsIntoMinute());

        // Handle negative milliseconds for formatting
        const abs_millis: u64 = @intCast(if (millis < 0) -millis else millis);

        return std.fmt.allocPrint(
            allocator,
            "{:0>4}-{:0>2}-{:0>2}T{:0>2}:{:0>2}:{:0>2}.{:0>3}Z",
            .{ year, month, day, hour, minute, second, abs_millis },
        );
    }

    /// Convert to seconds
    pub fn toSeconds(self: Timestamp) i64 {
        return @divFloor(self.millis, std.time.ms_per_s);
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
    /// Algorithm: aligned = floor(timestamp / interval) * interval
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
/// Uses std.time constants for standard durations
pub const Duration = struct {
    millis: i64,

    // Common constants using std.time
    pub const ZERO = Duration{ .millis = 0 };
    pub const MILLISECOND = Duration{ .millis = 1 };
    pub const SECOND = Duration{ .millis = std.time.ms_per_s };
    pub const MINUTE = Duration{ .millis = std.time.s_per_min * std.time.ms_per_s };
    pub const HOUR = Duration{ .millis = std.time.s_per_hour * std.time.ms_per_s };
    pub const DAY = Duration{ .millis = std.time.s_per_day * std.time.ms_per_s };
    pub const WEEK = Duration{ .millis = std.time.s_per_week * std.time.ms_per_s };

    /// Create from milliseconds
    pub fn fromMillis(millis: i64) Duration {
        return .{ .millis = millis };
    }

    /// Create from seconds
    pub fn fromSeconds(seconds: i64) Duration {
        return .{ .millis = seconds * std.time.ms_per_s };
    }

    /// Create from minutes
    pub fn fromMinutes(minutes: i64) Duration {
        return .{ .millis = minutes * std.time.s_per_min * std.time.ms_per_s };
    }

    /// Create from hours
    pub fn fromHours(hours: i64) Duration {
        return .{ .millis = hours * std.time.s_per_hour * std.time.ms_per_s };
    }

    /// Create from days
    pub fn fromDays(days: i64) Duration {
        return .{ .millis = days * std.time.s_per_day * std.time.ms_per_s };
    }

    /// Convert to milliseconds
    pub fn toMillis(self: Duration) i64 {
        return self.millis;
    }

    /// Convert to seconds
    pub fn toSeconds(self: Duration) i64 {
        return @divFloor(self.millis, std.time.ms_per_s);
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

        const days = @divFloor(abs_millis, std.time.s_per_day * std.time.ms_per_s);
        const hours = @divFloor(@mod(abs_millis, std.time.s_per_day * std.time.ms_per_s), std.time.s_per_hour * std.time.ms_per_s);
        const minutes = @divFloor(@mod(abs_millis, std.time.s_per_hour * std.time.ms_per_s), std.time.s_per_min * std.time.ms_per_s);
        const seconds = @divFloor(@mod(abs_millis, std.time.s_per_min * std.time.ms_per_s), std.time.ms_per_s);
        const millis = @mod(abs_millis, std.time.ms_per_s);

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

// Helper functions

/// Convert date-time to Unix epoch seconds
/// Uses std.time.epoch.isLeapYear for leap year detection
fn dateToEpochSeconds(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8) i64 {
    // Days before each month (non-leap year)
    const days_before_month = [_]u16{ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };

    // Calculate years since epoch (1970)
    const years_since_epoch: i32 = year - epoch.epoch_year;

    // Count leap days between epoch and year (exclusive)
    var leap_days: i32 = 0;
    var y: i32 = epoch.epoch_year;
    while (y < year) : (y += 1) {
        if (epoch.isLeapYear(@intCast(y))) leap_days += 1;
    }

    // Calculate total days
    var total_days: i32 = years_since_epoch * 365 + leap_days;

    // Add days from months in current year
    total_days += days_before_month[month - 1];

    // Add extra day if leap year and after February
    if (epoch.isLeapYear(@intCast(year)) and month > 2) {
        total_days += 1;
    }

    // Add remaining days (day is 1-indexed)
    total_days += @as(i32, day) - 1;

    // Calculate total seconds using std.time constants
    const day_secs = @as(i64, total_days) * std.time.s_per_day;
    const time_secs = @as(i64, hour) * std.time.s_per_hour +
        @as(i64, minute) * std.time.s_per_min +
        @as(i64, second);

    return day_secs + time_secs;
}

/// K-line interval (candlestick interval)
/// 支持所有币安时间周期
pub const KlineInterval = enum {
    @"1s", // 1秒
    @"1m", // 1分钟
    @"3m", // 3分钟
    @"5m", // 5分钟
    @"15m", // 15分钟
    @"30m", // 30分钟
    @"1h", // 1小时
    @"2h", // 2小时
    @"4h", // 4小时
    @"6h", // 6小时
    @"8h", // 8小时
    @"12h", // 12小时
    @"1d", // 1天
    @"3d", // 3天
    @"1w", // 1周
    @"1M", // 1月

    /// Convert to milliseconds using std.time constants
    pub fn toMillis(self: KlineInterval) i64 {
        return switch (self) {
            .@"1s" => std.time.ms_per_s,
            .@"1m" => std.time.s_per_min * std.time.ms_per_s,
            .@"3m" => 3 * std.time.s_per_min * std.time.ms_per_s,
            .@"5m" => 5 * std.time.s_per_min * std.time.ms_per_s,
            .@"15m" => 15 * std.time.s_per_min * std.time.ms_per_s,
            .@"30m" => 30 * std.time.s_per_min * std.time.ms_per_s,
            .@"1h" => std.time.s_per_hour * std.time.ms_per_s,
            .@"2h" => 2 * std.time.s_per_hour * std.time.ms_per_s,
            .@"4h" => 4 * std.time.s_per_hour * std.time.ms_per_s,
            .@"6h" => 6 * std.time.s_per_hour * std.time.ms_per_s,
            .@"8h" => 8 * std.time.s_per_hour * std.time.ms_per_s,
            .@"12h" => 12 * std.time.s_per_hour * std.time.ms_per_s,
            .@"1d" => std.time.s_per_day * std.time.ms_per_s,
            .@"3d" => 3 * std.time.s_per_day * std.time.ms_per_s,
            .@"1w" => std.time.s_per_week * std.time.ms_per_s,
            .@"1M" => 30 * std.time.s_per_day * std.time.ms_per_s, // 约30天
        };
    }

    /// Parse from string
    pub fn fromString(str: []const u8) !KlineInterval {
        if (std.mem.eql(u8, str, "1s")) return .@"1s";
        if (std.mem.eql(u8, str, "1m")) return .@"1m";
        if (std.mem.eql(u8, str, "3m")) return .@"3m";
        if (std.mem.eql(u8, str, "5m")) return .@"5m";
        if (std.mem.eql(u8, str, "15m")) return .@"15m";
        if (std.mem.eql(u8, str, "30m")) return .@"30m";
        if (std.mem.eql(u8, str, "1h")) return .@"1h";
        if (std.mem.eql(u8, str, "2h")) return .@"2h";
        if (std.mem.eql(u8, str, "4h")) return .@"4h";
        if (std.mem.eql(u8, str, "6h")) return .@"6h";
        if (std.mem.eql(u8, str, "8h")) return .@"8h";
        if (std.mem.eql(u8, str, "12h")) return .@"12h";
        if (std.mem.eql(u8, str, "1d")) return .@"1d";
        if (std.mem.eql(u8, str, "3d")) return .@"3d";
        if (std.mem.eql(u8, str, "1w")) return .@"1w";
        if (std.mem.eql(u8, str, "1M") or std.mem.eql(u8, str, "1mo")) return .@"1M";
        return error.InvalidKlineInterval;
    }

    /// Convert to string
    pub fn toString(self: KlineInterval) []const u8 {
        return switch (self) {
            .@"1s" => "1s",
            .@"1m" => "1m",
            .@"3m" => "3m",
            .@"5m" => "5m",
            .@"15m" => "15m",
            .@"30m" => "30m",
            .@"1h" => "1h",
            .@"2h" => "2h",
            .@"4h" => "4h",
            .@"6h" => "6h",
            .@"8h" => "8h",
            .@"12h" => "12h",
            .@"1d" => "1d",
            .@"3d" => "3d",
            .@"1w" => "1w",
            .@"1M" => "1M",
        };
    }
};

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

test "Duration constants using std.time" {
    try std.testing.expectEqual(@as(i64, 0), Duration.ZERO.millis);
    try std.testing.expectEqual(@as(i64, 1), Duration.MILLISECOND.millis);
    try std.testing.expectEqual(@as(i64, std.time.ms_per_s), Duration.SECOND.millis);
    try std.testing.expectEqual(@as(i64, std.time.s_per_min * std.time.ms_per_s), Duration.MINUTE.millis);
    try std.testing.expectEqual(@as(i64, std.time.s_per_hour * std.time.ms_per_s), Duration.HOUR.millis);
    try std.testing.expectEqual(@as(i64, std.time.s_per_day * std.time.ms_per_s), Duration.DAY.millis);
    try std.testing.expectEqual(@as(i64, std.time.s_per_week * std.time.ms_per_s), Duration.WEEK.millis);
}

test "KlineInterval conversion using std.time" {
    try std.testing.expectEqual(@as(i64, std.time.s_per_min * std.time.ms_per_s), KlineInterval.@"1m".toMillis());
    try std.testing.expectEqual(@as(i64, 5 * std.time.s_per_min * std.time.ms_per_s), KlineInterval.@"5m".toMillis());
    try std.testing.expectEqual(@as(i64, std.time.s_per_hour * std.time.ms_per_s), KlineInterval.@"1h".toMillis());
    try std.testing.expectEqual(@as(i64, std.time.s_per_day * std.time.ms_per_s), KlineInterval.@"1d".toMillis());
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
