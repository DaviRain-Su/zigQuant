# Time - 实现细节

> 内部实现说明和设计决策
> 基于 Zig 标准库 `std.time` 和 `std.time.epoch`

**最后更新**: 2025-12-23

---

## 设计原则

Time 模块采用**薄包装 + 扩展**的设计：

1. **充分利用标准库**: 使用 `std.time` 的时间获取和常量，使用 `std.time.epoch` 的日期转换
2. **最小化重复**: 仅在标准库不提供的地方实现自定义逻辑（如日期到epoch的反向转换）
3. **量化交易特定扩展**: K线对齐、交易时间间隔等领域特定功能

---

## 核心数据结构

### Timestamp

```zig
pub const Timestamp = struct {
    millis: i64,  // Unix 毫秒时间戳 (UTC)

    pub const ZERO: Timestamp = .{ .millis = 0 };
};
```

**设计决策**:
- 使用 `i64` 存储毫秒时间戳，范围足够覆盖所有实际应用场景
- 统一使用 UTC 时区，避免时区转换的复杂性
- 零成本抽象：`Timestamp` 在内存中就是一个 `i64`

### Duration

```zig
pub const Duration = struct {
    millis: i64,  // 时间间隔（毫秒）

    // 常量使用 std.time 提供的标准值
    pub const ZERO = Duration{ .millis = 0 };
    pub const MILLISECOND = Duration{ .millis = 1 };
    pub const SECOND = Duration{ .millis = std.time.ms_per_s };
    pub const MINUTE = Duration{ .millis = std.time.s_per_min * std.time.ms_per_s };
    pub const HOUR = Duration{ .millis = std.time.s_per_hour * std.time.ms_per_s };
    pub const DAY = Duration{ .millis = std.time.s_per_day * std.time.ms_per_s };
    pub const WEEK = Duration{ .millis = std.time.s_per_week * std.time.ms_per_s };
};
```

**设计决策**:
- 使用 `i64` 存储毫秒，支持负数表示反向间隔
- **常量基于 `std.time`**: 确保与标准库一致性，避免计算错误
- 支持算术运算（加法、减法、乘法）

### KlineInterval

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

    // 使用 std.time 常量计算毫秒值
    pub fn toMillis(self: KlineInterval) i64 {
        return switch (self) {
            .@"1m" => std.time.s_per_min * std.time.ms_per_s,
            .@"5m" => 5 * std.time.s_per_min * std.time.ms_per_s,
            .@"15m" => 15 * std.time.s_per_min * std.time.ms_per_s,
            .@"30m" => 30 * std.time.s_per_min * std.time.ms_per_s,
            .@"1h" => std.time.s_per_hour * std.time.ms_per_s,
            .@"4h" => 4 * std.time.s_per_hour * std.time.ms_per_s,
            .@"1d" => std.time.s_per_day * std.time.ms_per_s,
            .@"1w" => std.time.s_per_week * std.time.ms_per_s,
        };
    }
};
```

**设计决策**:
- 使用 `enum` 确保类型安全，避免非法值
- 使用 `@"1m"` 语法支持数字开头的标识符
- **使用 `std.time` 常量**: 避免硬编码魔法数字，确保正确性

---

## 核心算法

### 1. K线时间对齐

```zig
pub fn alignToKline(self: Timestamp, interval: KlineInterval) Timestamp {
    const interval_ms = interval.toMillis();
    const aligned_ms = @divFloor(self.millis, interval_ms) * interval_ms;
    return Timestamp{ .millis = aligned_ms };
}
```

**算法说明**:
1. 获取 K线间隔的毫秒数
2. 使用 `@divFloor` 向下取整除法
3. 乘以间隔得到对齐后的时间戳

**示例**:
```
原始时间: 2025-01-22 10:32:45.123 (1737541965123 ms)
5 分钟 K线间隔: 300000 ms

aligned_ms = divFloor(1737541965123, 300000) * 300000
           = 5791806 * 300000
           = 1737541800000 ms
           = 2025-01-22 10:30:00.000
```

### 2. ISO 8601 解析和格式化

#### 解析 (fromISO8601)

```zig
pub fn fromISO8601(allocator: Allocator, iso_str: []const u8) !Timestamp {
    // 解析 ISO 8601 字符串: "2025-01-22T10:30:45.123Z"
    // 1. 解析年月日时分秒
    const year = try std.fmt.parseInt(i32, iso_str[0..4], 10);
    const month = try std.fmt.parseInt(u8, iso_str[5..7], 10);
    // ...

    // 2. 使用辅助函数转换为 epoch 秒
    // (标准库 std.time.epoch 不提供日期到epoch的反向转换)
    const timestamp_seconds = dateToEpochSeconds(year, month, day, hour, minute, second);

    return .{ .millis = timestamp_seconds * std.time.ms_per_s + millis_part };
}

// 辅助函数：日期转换为 epoch 秒
fn dateToEpochSeconds(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8) i64 {
    // 使用 std.time.epoch.isLeapYear() 判断闰年
    // 使用 std.time 常量计算秒数
    if (epoch.isLeapYear(@intCast(y))) leap_days += 1;

    const day_secs = @as(i64, total_days) * std.time.s_per_day;
    const time_secs = @as(i64, hour) * std.time.s_per_hour + ...;
}
```

#### 格式化 (toISO8601)

```zig
pub fn toISO8601(self: Timestamp, allocator: Allocator) ![]const u8 {
    // 使用 std.time.epoch 进行日期转换
    const epoch_seconds = epoch.EpochSeconds{ .secs = seconds };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    // 提取各个字段
    const year = year_day.year;
    const month = month_day.month.numeric();
    const day = month_day.day_index + 1;
    const hour = day_seconds.getHoursIntoDay();
    const minute = day_seconds.getMinutesIntoHour();
    const second = day_seconds.getSecondsIntoMinute();

    // 格式化输出
    return std.fmt.allocPrint(allocator, "{:0>4}-{:0>2}-{:0>2}T...", ...);
}
```

**设计说明**:
- **解析**: 标准库不提供日期→epoch转换，需自定义实现，但使用 `epoch.isLeapYear()` 和 `std.time` 常量
- **格式化**: 充分利用 `std.time.epoch` 的 epoch→日期转换功能
- 两个方向互为逆运算，确保往返一致性

### 3. 日期计算（辅助函数）

```zig
fn daysSinceEpoch(year: i32, month: u8, day: u8) i64 {
    // 使用 Gregorian 日历算法
    var y = year;
    var m = @as(i32, month);

    // 调整 1 月和 2 月
    if (m <= 2) {
        y -= 1;
        m += 12;
    }

    // 计算天数
    const a = @divFloor(y, 100);
    const b = @divFloor(a, 4);
    const c = 2 - a + b;
    const e = @as(i64, @divFloor(36525 * (y + 4716), 100));
    const f = @as(i64, @divFloor(306001 * (m + 1), 10000));

    return c + day + e + f - 2484336;
}
```

**算法说明**:
- 使用 Gregorian 日历公式
- 支持闰年计算
- 返回自 Unix Epoch (1970-01-01) 以来的天数

---

## 性能优化

### 1. 零成本抽象

```zig
// Timestamp 和 i64 在内存中完全相同
const t1 = Timestamp{ .millis = 1000 };
const t2: i64 = 1000;
// sizeof(t1) == sizeof(t2) == 8 bytes
```

### 2. 常量折叠

```zig
// 编译时计算
const FIVE_MINUTES = Duration.MINUTE.mul(5);
// 运行时直接使用 300000，无额外计算
```

### 3. 内联优化

```zig
// 小函数建议编译器内联
pub inline fn toMillis(self: Timestamp) i64 {
    return self.millis;
}
```

---

## 错误处理

### 错误类型

```zig
pub const TimeError = error{
    InvalidFormat,
    InvalidYear,
    InvalidMonth,
    InvalidDay,
    InvalidHour,
    InvalidMinute,
    InvalidSecond,
    OutOfRange,
};
```

### 错误传播

```zig
// 使用 Zig 的错误联合类型
pub fn fromISO8601(s: []const u8) !Timestamp {
    // 错误会自动传播到调用方
    const year = try std.fmt.parseInt(i32, s[0..4], 10);
    // ...
}
```

---

## 内存管理

### 栈分配

```zig
// Timestamp 和 Duration 都是值类型，分配在栈上
const now = Timestamp.now();  // 栈分配，8 bytes
```

### 堆分配（仅在必要时）

```zig
// 只有字符串转换需要分配内存
const str = try timestamp.toISO8601(allocator);
defer allocator.free(str);  // 调用方负责释放
```

---

## 线程安全

- `Timestamp` 和 `Duration` 都是**不可变值类型**
- `Timestamp.now()` 调用系统 API，线程安全
- 无共享状态，无需加锁

---

## 边界情况

### 1. 时间戳范围

```zig
// i64 范围: -2^63 到 2^63-1
// 毫秒时间戳范围: 约 -292,471,208,677 年到 292,471,208,677 年
// 实际应用场景完全覆盖
```

### 2. 闰秒

当前实现**不处理闰秒**：
- Unix 时间戳定义不包含闰秒
- 交易所 API 通常也忽略闰秒
- 简化实现，避免复杂性

### 3. 时区

- 统一使用 **UTC** 时区
- 不支持本地时区转换
- 在展示层处理时区转换

---

## 测试覆盖

详见 [testing.md](./testing.md)

- 单元测试: 100%
- 集成测试: K线对齐、时间运算
- 边界测试: 极值、闰年、跨月

---

## 未来改进

- [ ] 支持纳秒精度 (`i128`)
- [ ] 支持时区转换
- [ ] 支持更多时间格式（RFC 3339, Unix timestamp）
- [ ] SIMD 优化批量时间处理

---

*Last updated: 2025-01-22*
