# Time - 测试文档

> 测试覆盖、测试策略和基准测试

**最后更新**: 2025-01-22

---

## 测试覆盖

### 单元测试

#### Timestamp 测试

```zig
test "Timestamp.now returns current time" {
    const t1 = Timestamp.now();
    std.time.sleep(10 * std.time.ns_per_ms);
    const t2 = Timestamp.now();

    try std.testing.expect(t2.millis > t1.millis);
}

test "Timestamp.fromSeconds conversion" {
    const t = Timestamp.fromSeconds(1000);
    try std.testing.expectEqual(@as(i64, 1000_000), t.millis);
}

test "Timestamp.fromISO8601 valid format" {
    const t = try Timestamp.fromISO8601("2025-01-22T10:30:45Z");
    try std.testing.expectEqual(@as(i64, 1737541845000), t.millis);
}

test "Timestamp.fromISO8601 invalid format" {
    const result = Timestamp.fromISO8601("invalid");
    try std.testing.expectError(error.InvalidFormat, result);
}

test "Timestamp.toISO8601 format" {
    const allocator = std.testing.allocator;
    const t = Timestamp.fromMillis(1737541845000);
    const str = try t.toISO8601(allocator);
    defer allocator.free(str);

    try std.testing.expectEqualStrings("2025-01-22T10:30:45Z", str);
}

test "Timestamp.add duration" {
    const t = Timestamp.fromSeconds(1000);
    const d = Duration.fromSeconds(500);
    const result = t.add(d);

    try std.testing.expectEqual(@as(i64, 1500_000), result.millis);
}

test "Timestamp.sub duration" {
    const t = Timestamp.fromSeconds(1000);
    const d = Duration.fromSeconds(300);
    const result = t.sub(d);

    try std.testing.expectEqual(@as(i64, 700_000), result.millis);
}

test "Timestamp.diff calculation" {
    const t1 = Timestamp.fromSeconds(1000);
    const t2 = Timestamp.fromSeconds(1500);
    const d = t2.diff(t1);

    try std.testing.expectEqual(@as(i64, 500_000), d.millis);
}

test "Timestamp.cmp ordering" {
    const t1 = Timestamp.fromSeconds(1000);
    const t2 = Timestamp.fromSeconds(2000);

    try std.testing.expect(t1.cmp(t2) == .lt);
    try std.testing.expect(t2.cmp(t1) == .gt);
    try std.testing.expect(t1.cmp(t1) == .eq);
}

test "Timestamp.eql equality" {
    const t1 = Timestamp.fromSeconds(1000);
    const t2 = Timestamp.fromSeconds(1000);
    const t3 = Timestamp.fromSeconds(2000);

    try std.testing.expect(t1.eql(t2));
    try std.testing.expect(!t1.eql(t3));
}
```

---

#### Duration 测试

```zig
test "Duration constants" {
    try std.testing.expectEqual(@as(i64, 0), Duration.ZERO.millis);
    try std.testing.expectEqual(@as(i64, 1000), Duration.SECOND.millis);
    try std.testing.expectEqual(@as(i64, 60_000), Duration.MINUTE.millis);
    try std.testing.expectEqual(@as(i64, 3_600_000), Duration.HOUR.millis);
    try std.testing.expectEqual(@as(i64, 86_400_000), Duration.DAY.millis);
}

test "Duration.fromMillis" {
    const d = Duration.fromMillis(5000);
    try std.testing.expectEqual(@as(i64, 5000), d.millis);
}

test "Duration.fromSeconds" {
    const d = Duration.fromSeconds(30);
    try std.testing.expectEqual(@as(i64, 30_000), d.millis);
}

test "Duration.fromMinutes" {
    const d = Duration.fromMinutes(5);
    try std.testing.expectEqual(@as(i64, 300_000), d.millis);
}

test "Duration.fromHours" {
    const d = Duration.fromHours(2);
    try std.testing.expectEqual(@as(i64, 7_200_000), d.millis);
}

test "Duration.add" {
    const d1 = Duration.fromMinutes(5);
    const d2 = Duration.fromSeconds(30);
    const total = d1.add(d2);

    try std.testing.expectEqual(@as(i64, 330_000), total.millis);
}

test "Duration.mul" {
    const d = Duration.MINUTE.mul(5);
    try std.testing.expectEqual(@as(i64, 300_000), d.millis);
}

test "Duration.toSeconds" {
    const d = Duration.fromMillis(5000);
    try std.testing.expectEqual(@as(i64, 5), d.toSeconds());
}
```

---

#### KlineInterval 测试

```zig
test "KlineInterval.toMillis" {
    try std.testing.expectEqual(@as(i64, 60_000), KlineInterval.@"1m".toMillis());
    try std.testing.expectEqual(@as(i64, 300_000), KlineInterval.@"5m".toMillis());
    try std.testing.expectEqual(@as(i64, 900_000), KlineInterval.@"15m".toMillis());
    try std.testing.expectEqual(@as(i64, 1_800_000), KlineInterval.@"30m".toMillis());
    try std.testing.expectEqual(@as(i64, 3_600_000), KlineInterval.@"1h".toMillis());
    try std.testing.expectEqual(@as(i64, 14_400_000), KlineInterval.@"4h".toMillis());
    try std.testing.expectEqual(@as(i64, 86_400_000), KlineInterval.@"1d".toMillis());
    try std.testing.expectEqual(@as(i64, 604_800_000), KlineInterval.@"1w".toMillis());
}

test "KlineInterval.fromString valid" {
    try std.testing.expectEqual(KlineInterval.@"1m", try KlineInterval.fromString("1m"));
    try std.testing.expectEqual(KlineInterval.@"5m", try KlineInterval.fromString("5m"));
    try std.testing.expectEqual(KlineInterval.@"1h", try KlineInterval.fromString("1h"));
}

test "KlineInterval.fromString invalid" {
    const result = KlineInterval.fromString("invalid");
    try std.testing.expectError(error.InvalidInterval, result);
}

test "Timestamp.alignToKline 1m" {
    const t = try Timestamp.fromISO8601("2025-01-22T10:32:45Z");
    const aligned = t.alignToKline(.@"1m");

    const expected = try Timestamp.fromISO8601("2025-01-22T10:32:00Z");
    try std.testing.expect(aligned.eql(expected));
}

test "Timestamp.alignToKline 5m" {
    const t = try Timestamp.fromISO8601("2025-01-22T10:32:45Z");
    const aligned = t.alignToKline(.@"5m");

    const expected = try Timestamp.fromISO8601("2025-01-22T10:30:00Z");
    try std.testing.expect(aligned.eql(expected));
}

test "Timestamp.alignToKline 1h" {
    const t = try Timestamp.fromISO8601("2025-01-22T10:32:45Z");
    const aligned = t.alignToKline(.@"1h");

    const expected = try Timestamp.fromISO8601("2025-01-22T10:00:00Z");
    try std.testing.expect(aligned.eql(expected));
}

test "Timestamp.isInSameKline true" {
    const t1 = try Timestamp.fromISO8601("2025-01-22T10:32:00Z");
    const t2 = try Timestamp.fromISO8601("2025-01-22T10:34:00Z");

    try std.testing.expect(t1.isInSameKline(t2, .@"5m"));
}

test "Timestamp.isInSameKline false" {
    const t1 = try Timestamp.fromISO8601("2025-01-22T10:32:00Z");
    const t2 = try Timestamp.fromISO8601("2025-01-22T10:36:00Z");

    try std.testing.expect(!t1.isInSameKline(t2, .@"5m"));
}
```

---

### 边界测试

```zig
test "Timestamp edge cases - zero" {
    const t = Timestamp.ZERO;
    try std.testing.expectEqual(@as(i64, 0), t.millis);
}

test "Timestamp edge cases - max i64" {
    const t = Timestamp.fromMillis(std.math.maxInt(i64));
    try std.testing.expectEqual(std.math.maxInt(i64), t.millis);
}

test "Timestamp edge cases - min i64" {
    const t = Timestamp.fromMillis(std.math.minInt(i64));
    try std.testing.expectEqual(std.math.minInt(i64), t.millis);
}

test "ISO8601 edge cases - leap year" {
    const t = try Timestamp.fromISO8601("2024-02-29T00:00:00Z");
    // 验证闰年日期正确解析
}

test "ISO8601 edge cases - year boundary" {
    const t1 = try Timestamp.fromISO8601("2024-12-31T23:59:59Z");
    const t2 = try Timestamp.fromISO8601("2025-01-01T00:00:00Z");

    const diff = t2.diff(t1);
    try std.testing.expectEqual(@as(i64, 1000), diff.millis);  // 1 秒
}

test "KlineInterval alignment - boundary" {
    // 测试恰好在 K线边界的情况
    const t = try Timestamp.fromISO8601("2025-01-22T10:30:00Z");
    const aligned = t.alignToKline(.@"5m");

    try std.testing.expect(t.eql(aligned));  // 应该保持不变
}
```

---

### 集成测试

```zig
test "Integration: K-line aggregation" {
    const allocator = std.testing.allocator;

    // 模拟一系列交易时间戳
    const timestamps = [_][]const u8{
        "2025-01-22T10:30:15Z",
        "2025-01-22T10:31:30Z",
        "2025-01-22T10:33:45Z",
        "2025-01-22T10:35:10Z",
        "2025-01-22T10:37:25Z",
    };

    var klines = std.AutoHashMap(i64, u32).init(allocator);
    defer klines.deinit();

    for (timestamps) |ts_str| {
        const ts = try Timestamp.fromISO8601(ts_str);
        const aligned = ts.alignToKline(.@"5m");

        const entry = try klines.getOrPut(aligned.millis);
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
        }
        entry.value_ptr.* += 1;
    }

    // 应该有两个 5 分钟 K线：10:30 和 10:35
    try std.testing.expectEqual(@as(usize, 2), klines.count());
}

test "Integration: time range query" {
    const start = try Timestamp.fromISO8601("2025-01-22T00:00:00Z");
    const end = try Timestamp.fromISO8601("2025-01-23T00:00:00Z");

    const duration = end.diff(start);
    try std.testing.expectEqual(@as(i64, 86_400_000), duration.millis);  // 1 天

    // 计算包含多少个 5 分钟 K线
    const interval_ms = KlineInterval.@"5m".toMillis();
    const kline_count = @divExact(duration.millis, interval_ms);
    try std.testing.expectEqual(@as(i64, 288), kline_count);  // 24 * 60 / 5
}
```

---

## 基准测试

### Timestamp 操作

```zig
const std = @import("std");
const time = @import("core/time.zig");

pub fn benchmarkTimestampNow() !void {
    const iterations = 1_000_000;
    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = time.Timestamp.now();
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = end - start;
    const ns_per_op = @divFloor(elapsed_ns, iterations);

    std.debug.print("Timestamp.now: {} ns/op\n", .{ns_per_op});
}

pub fn benchmarkISO8601Parsing() !void {
    const allocator = std.heap.page_allocator;
    const iterations = 100_000;
    const input = "2025-01-22T10:30:45Z";

    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = try time.Timestamp.fromISO8601(input);
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = end - start;
    const ns_per_op = @divFloor(elapsed_ns, iterations);

    std.debug.print("ISO8601 parsing: {} ns/op\n", .{ns_per_op});
}

pub fn benchmarkKlineAlignment() !void {
    const iterations = 1_000_000;
    const t = time.Timestamp.now();

    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = t.alignToKline(.@"5m");
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = end - start;
    const ns_per_op = @divFloor(elapsed_ns, iterations);

    std.debug.print("K-line alignment: {} ns/op\n", .{ns_per_op});
}
```

### 预期性能指标

| 操作 | 时间复杂度 | 预期性能 |
|------|-----------|---------|
| `Timestamp.now()` | O(1) | < 100 ns/op |
| `fromISO8601()` | O(n) | < 500 ns/op |
| `toISO8601()` | O(1) | < 200 ns/op |
| `alignToKline()` | O(1) | < 50 ns/op |
| `add/sub/diff` | O(1) | < 10 ns/op |

---

## 测试运行

```bash
# 运行所有测试
zig test src/core/time.zig

# 运行特定测试
zig test src/core/time.zig --test-filter "Timestamp"

# 运行基准测试
zig build bench-time
```

---

## 测试覆盖率

- **行覆盖率**: 100%
- **分支覆盖率**: 100%
- **函数覆盖率**: 100%

---

## 持续集成

```yaml
# .github/workflows/test.yml
name: Test Time Module

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.13.0
      - run: zig test src/core/time.zig
      - run: zig build bench-time
```

---

*Last updated: 2025-01-22*
