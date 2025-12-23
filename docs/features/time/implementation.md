# Time - 实现细节

> 内部实现说明和设计决策

**最后更新**: 2025-01-22

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

    pub const ZERO: Duration = .{ .millis = 0 };
    pub const SECOND: Duration = .{ .millis = 1000 };
    pub const MINUTE: Duration = .{ .millis = 60_000 };
    pub const HOUR: Duration = .{ .millis = 3_600_000 };
    pub const DAY: Duration = .{ .millis = 86_400_000 };
};
```

**设计决策**:
- 使用 `i64` 存储毫秒，支持负数表示反向间隔
- 提供常用常量，避免魔法数字
- 支持算术运算（加法、乘法）

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

    pub fn toMillis(self: KlineInterval) i64 {
        return switch (self) {
            .@"1m" => 60_000,
            .@"5m" => 300_000,
            .@"15m" => 900_000,
            .@"30m" => 1_800_000,
            .@"1h" => 3_600_000,
            .@"4h" => 14_400_000,
            .@"1d" => 86_400_000,
            .@"1w" => 604_800_000,
        };
    }
};
```

**设计决策**:
- 使用 `enum` 确保类型安全，避免非法值
- 使用 `@"1m"` 语法支持数字开头的标识符
- 提供 `toMillis()` 方法避免重复计算

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

### 2. ISO 8601 解析

```zig
pub fn fromISO8601(s: []const u8) !Timestamp {
    // 示例: "2025-01-22T10:30:45Z"
    if (s.len < 20) return error.InvalidFormat;
    if (s[19] != 'Z') return error.InvalidFormat;

    const year = try std.fmt.parseInt(i32, s[0..4], 10);
    const month = try std.fmt.parseInt(u8, s[5..7], 10);
    const day = try std.fmt.parseInt(u8, s[8..10], 10);
    const hour = try std.fmt.parseInt(u8, s[11..13], 10);
    const minute = try std.fmt.parseInt(u8, s[14..16], 10);
    const second = try std.fmt.parseInt(u8, s[17..19], 10);

    // 验证范围
    if (month < 1 or month > 12) return error.InvalidMonth;
    if (day < 1 or day > 31) return error.InvalidDay;
    if (hour > 23) return error.InvalidHour;
    if (minute > 59) return error.InvalidMinute;
    if (second > 59) return error.InvalidSecond;

    // 转换为 Unix 时间戳
    const days_since_epoch = daysSinceEpoch(year, month, day);
    const seconds = days_since_epoch * 86400 + hour * 3600 + minute * 60 + second;

    return Timestamp{ .millis = seconds * 1000 };
}
```

**算法说明**:
1. 验证字符串长度和格式
2. 解析各个时间字段
3. 验证每个字段的有效范围
4. 计算自 Unix Epoch 以来的天数
5. 转换为毫秒时间戳

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
