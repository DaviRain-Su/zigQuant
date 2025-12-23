# Time - API 参考

> 完整的 API 文档和使用示例

**最后更新**: 2025-01-22

---

## Timestamp

Unix 时间戳（毫秒精度，UTC）

### 常量

```zig
pub const ZERO: Timestamp = .{ .millis = 0 };
```

表示 Unix Epoch (1970-01-01 00:00:00 UTC)

---

### 构造函数

#### `now() Timestamp`

获取当前时间戳

```zig
const now = Timestamp.now();
std.debug.print("Current time: {}\n", .{now.millis});
```

**返回**: 当前系统时间（UTC）
**时间复杂度**: O(1)

---

#### `fromSeconds(secs: i64) Timestamp`

从秒数创建时间戳

```zig
const t = Timestamp.fromSeconds(1737541800);
// 等价于 2025-01-22 10:30:00 UTC
```

**参数**:
- `secs`: Unix 秒时间戳

**返回**: Timestamp 实例
**时间复杂度**: O(1)

---

#### `fromMillis(millis: i64) Timestamp`

从毫秒数创建时间戳

```zig
const t = Timestamp.fromMillis(1737541800000);
```

**参数**:
- `millis`: Unix 毫秒时间戳

**返回**: Timestamp 实例
**时间复杂度**: O(1)

---

#### `fromISO8601(s: []const u8) !Timestamp`

从 ISO 8601 字符串创建时间戳

```zig
const t = try Timestamp.fromISO8601("2025-01-22T10:30:45Z");
```

**参数**:
- `s`: ISO 8601 格式字符串 (YYYY-MM-DDTHH:MM:SSZ)

**返回**: Timestamp 实例
**错误**:
- `error.InvalidFormat`: 格式不正确
- `error.InvalidYear/Month/Day/Hour/Minute/Second`: 字段值非法
- `error.OutOfRange`: 超出有效范围

**时间复杂度**: O(n), n 为字符串长度
**支持格式**: `YYYY-MM-DDTHH:MM:SSZ` (必须以 'Z' 结尾表示 UTC)

---

### 转换方法

#### `toSeconds(self: Timestamp) i64`

转换为秒时间戳

```zig
const secs = timestamp.toSeconds();
```

**返回**: Unix 秒时间戳
**时间复杂度**: O(1)

---

#### `toMillis(self: Timestamp) i64`

转换为毫秒时间戳

```zig
const millis = timestamp.toMillis();
```

**返回**: Unix 毫秒时间戳
**时间复杂度**: O(1)

---

#### `toISO8601(self: Timestamp, allocator: Allocator) ![]const u8`

转换为 ISO 8601 字符串

```zig
const str = try timestamp.toISO8601(allocator);
defer allocator.free(str);
std.debug.print("Time: {s}\n", .{str});
```

**参数**:
- `allocator`: 内存分配器

**返回**: ISO 8601 格式字符串 (调用方负责释放)
**错误**: 内存分配失败
**时间复杂度**: O(1)
**格式**: `YYYY-MM-DDTHH:MM:SSZ`

---

### 运算方法

#### `add(self: Timestamp, duration: Duration) Timestamp`

加上时间间隔

```zig
const now = Timestamp.now();
const future = now.add(Duration.fromMinutes(5));
```

**参数**:
- `duration`: 要添加的时间间隔

**返回**: 新的时间戳
**时间复杂度**: O(1)

---

#### `sub(self: Timestamp, duration: Duration) Timestamp`

减去时间间隔

```zig
const past = now.sub(Duration.fromHours(1));
```

**参数**:
- `duration`: 要减去的时间间隔

**返回**: 新的时间戳
**时间复杂度**: O(1)

---

#### `diff(self: Timestamp, other: Timestamp) Duration`

计算两个时间戳之间的间隔

```zig
const t1 = Timestamp.fromSeconds(1000);
const t2 = Timestamp.fromSeconds(2000);
const duration = t2.diff(t1);  // 1000 秒
```

**参数**:
- `other`: 另一个时间戳

**返回**: 时间间隔 (self - other)
**时间复杂度**: O(1)

---

### 比较方法

#### `cmp(self: Timestamp, other: Timestamp) std.math.Order`

比较两个时间戳

```zig
const order = t1.cmp(t2);
switch (order) {
    .lt => std.debug.print("t1 < t2\n", .{}),
    .eq => std.debug.print("t1 == t2\n", .{}),
    .gt => std.debug.print("t1 > t2\n", .{}),
}
```

**参数**:
- `other`: 另一个时间戳

**返回**: `.lt` (小于), `.eq` (等于), 或 `.gt` (大于)
**时间复杂度**: O(1)

---

#### `eql(self: Timestamp, other: Timestamp) bool`

判断两个时间戳是否相等

```zig
if (t1.eql(t2)) {
    std.debug.print("Timestamps are equal\n", .{});
}
```

**参数**:
- `other`: 另一个时间戳

**返回**: 相等返回 `true`，否则 `false`
**时间复杂度**: O(1)

---

### K线相关方法

#### `alignToKline(self: Timestamp, interval: KlineInterval) Timestamp`

对齐到 K线开始时间

```zig
const now = Timestamp.now();
const aligned = now.alignToKline(.@"5m");
// 如果 now = 10:32:45, aligned = 10:30:00
```

**参数**:
- `interval`: K线时间间隔

**返回**: 对齐后的时间戳（向下取整到最近的 K线开始时间）
**时间复杂度**: O(1)

**算法**: `aligned = floor(timestamp / interval) * interval`

---

#### `isInSameKline(self: Timestamp, other: Timestamp, interval: KlineInterval) bool`

判断两个时间戳是否在同一个 K线内

```zig
const t1 = try Timestamp.fromISO8601("2025-01-22T10:32:00Z");
const t2 = try Timestamp.fromISO8601("2025-01-22T10:34:00Z");
const same = t1.isInSameKline(t2, .@"5m");  // true (both in 10:30-10:35)
```

**参数**:
- `other`: 另一个时间戳
- `interval`: K线时间间隔

**返回**: 在同一 K线内返回 `true`，否则 `false`
**时间复杂度**: O(1)

---

## Duration

时间间隔（毫秒精度）

### 常量

```zig
pub const ZERO: Duration = .{ .millis = 0 };
pub const SECOND: Duration = .{ .millis = 1000 };
pub const MINUTE: Duration = .{ .millis = 60_000 };
pub const HOUR: Duration = .{ .millis = 3_600_000 };
pub const DAY: Duration = .{ .millis = 86_400_000 };
```

---

### 构造函数

#### `fromMillis(millis: i64) Duration`

```zig
const d = Duration.fromMillis(5000);  // 5 秒
```

---

#### `fromSeconds(secs: i64) Duration`

```zig
const d = Duration.fromSeconds(30);  // 30 秒
```

---

#### `fromMinutes(mins: i64) Duration`

```zig
const d = Duration.fromMinutes(5);  // 5 分钟
```

---

#### `fromHours(hours: i64) Duration`

```zig
const d = Duration.fromHours(1);  // 1 小时
```

---

### 转换方法

#### `toMillis(self: Duration) i64`

```zig
const millis = duration.toMillis();
```

---

#### `toSeconds(self: Duration) i64`

```zig
const secs = duration.toSeconds();
```

---

#### `toMinutes(self: Duration) i64`

```zig
const mins = duration.toMinutes();
```

---

### 运算方法

#### `add(self: Duration, other: Duration) Duration`

```zig
const d1 = Duration.fromMinutes(5);
const d2 = Duration.fromSeconds(30);
const total = d1.add(d2);  // 5 分 30 秒
```

---

#### `mul(self: Duration, factor: i64) Duration`

```zig
const d = Duration.MINUTE.mul(5);  // 5 分钟
```

---

## KlineInterval

K线时间间隔

### 枚举值

```zig
pub const KlineInterval = enum {
    @"1m",   // 1 分钟
    @"5m",   // 5 分钟
    @"15m",  // 15 分钟
    @"30m",  // 30 分钟
    @"1h",   // 1 小时
    @"4h",   // 4 小时
    @"1d",   // 1 天
    @"1w",   // 1 周
};
```

---

### 方法

#### `toMillis(self: KlineInterval) i64`

转换为毫秒数

```zig
const millis = KlineInterval.@"5m".toMillis();  // 300000
```

---

#### `fromString(s: []const u8) !KlineInterval`

从字符串创建

```zig
const interval = try KlineInterval.fromString("5m");  // .@"5m"
```

**支持的字符串**: `"1m"`, `"5m"`, `"15m"`, `"30m"`, `"1h"`, `"4h"`, `"1d"`, `"1w"`

---

## 完整示例

### 示例 1: K线数据处理

```zig
const std = @import("std");
const time = @import("core/time.zig");

pub fn processKlineData(klines: []Kline) !void {
    for (klines) |kline| {
        // 对齐到 5 分钟 K线
        const aligned = kline.timestamp.alignToKline(.@"5m");

        // 转换为可读格式
        const str = try aligned.toISO8601(allocator);
        defer allocator.free(str);

        std.debug.print("Kline start: {s}\n", .{str});
    }
}
```

### 示例 2: 时间范围查询

```zig
pub fn queryByTimeRange(start_str: []const u8, end_str: []const u8) ![]Data {
    const start = try Timestamp.fromISO8601(start_str);
    const end = try Timestamp.fromISO8601(end_str);

    const duration = end.diff(start);
    std.debug.print("Query range: {} seconds\n", .{duration.toSeconds()});

    // 执行查询...
}
```

### 示例 3: 定时任务

```zig
pub fn scheduleTask() !void {
    const now = Timestamp.now();
    const next_run = now.add(Duration.fromMinutes(5));

    const delay = next_run.diff(now);
    std.time.sleep(@intCast(delay.toMillis() * std.time.ns_per_ms));

    // 执行任务...
}
```

---

*Last updated: 2025-01-22*
