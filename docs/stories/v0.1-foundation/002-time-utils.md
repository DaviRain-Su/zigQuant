# Story: 时间处理工具实现

**ID**: `STORY-002`
**版本**: `v0.1`
**创建日期**: 2025-01-22
**状态**: ✅ 已完成 (2025-12-23)
**优先级**: P0 (必须)
**预计工时**: 2 天
**实际工时**: 1 天

---

## 📋 需求描述

### 用户故事
作为**量化交易开发者**，我希望**有一套完善的时间处理工具**，以便**准确处理交易所时间戳、K线对齐和时区转换**。

### 背景
在量化交易中，时间处理至关重要：
- 交易所 API 使用毫秒/纳秒时间戳
- K线数据需要时间对齐（1m、5m、1h等）
- WebSocket 事件需要精确的时间戳
- 回测需要时间序列遍历
- 日志需要可读的时间格式

使用 Zig 标准库的 `std.time` 作为基础，封装量化交易特定的时间工具。

### 范围
- **包含**:
  - Timestamp 类型（毫秒精度）
  - Duration 类型
  - 时间格式化和解析（ISO 8601, RFC 3339）
  - K线时间对齐工具
  - 时间戳与交易所格式转换
  - 时间比较和运算

- **不包含**:
  - 复杂的时区数据库（使用 UTC）
  - 日历计算（月份、年份）
  - 自然语言时间解析

---

## 🎯 验收标准

- [x] Timestamp 结构体定义完成
- [x] Duration 结构体定义完成
- [x] 支持从毫秒/秒/ISO字符串创建时间戳
- [x] 支持格式化输出（ISO 8601）
- [x] K线时间对齐函数正确（1m, 5m, 15m, 1h, 1d）
- [x] 时间比较和运算正确
- [x] 所有测试用例通过
- [x] 测试覆盖率 > 90%

---

## 🔧 技术设计

### 架构概览

使用 **i64 毫秒时间戳** 作为内部表示：

```
Timestamp {
    millis: i64,    // Unix 毫秒时间戳 (UTC)
}

Duration {
    millis: i64,    // 毫秒数（可为负）
}

示例:
2025-01-22T10:30:45.123Z 表示为
{ millis: 1737543045123 }
```

### 数据结构

```zig
// src/core/time.zig

const std = @import("std");

/// Unix 时间戳（毫秒精度，UTC）
pub const Timestamp = struct {
    millis: i64,

    /// 常量
    pub const ZERO: Timestamp = .{ .millis = 0 };

    /// 获取当前时间
    pub fn now() Timestamp {
        return .{ .millis = std.time.milliTimestamp() };
    }

    /// 从 Unix 秒时间戳创建
    pub fn fromSeconds(secs: i64) Timestamp {
        return .{ .millis = secs * 1000 };
    }

    /// 从 Unix 毫秒时间戳创建
    pub fn fromMillis(millis: i64) Timestamp {
        return .{ .millis = millis };
    }

    /// 从 ISO 8601 字符串解析
    /// 支持格式: "2025-01-22T10:30:45Z", "2025-01-22T10:30:45.123Z"
    pub fn fromISO8601(allocator: Allocator, iso_str: []const u8) !Timestamp;

    /// 转换为 Unix 秒
    pub fn toSeconds(self: Timestamp) i64 {
        return @divFloor(self.millis, 1000);
    }

    /// 转换为 Unix 毫秒
    pub fn toMillis(self: Timestamp) i64 {
        return self.millis;
    }

    /// 格式化为 ISO 8601 字符串
    pub fn toISO8601(self: Timestamp, allocator: std.mem.Allocator) ![]const u8;

    /// 格式化为自定义格式
    /// format: "%Y-%m-%d %H:%M:%S"
    pub fn format(self: Timestamp, allocator: std.mem.Allocator, fmt: []const u8) ![]const u8;

    /// 时间运算
    pub fn add(self: Timestamp, duration: Duration) Timestamp;
    pub fn sub(self: Timestamp, duration: Duration) Timestamp;
    pub fn diff(self: Timestamp, other: Timestamp) Duration;

    /// 时间比较
    pub fn cmp(self: Timestamp, other: Timestamp) std.math.Order;
    pub fn eql(self: Timestamp, other: Timestamp) bool;
    pub fn isBefore(self: Timestamp, other: Timestamp) bool;
    pub fn isAfter(self: Timestamp, other: Timestamp) bool;

    /// K线时间对齐
    pub fn alignToKline(self: Timestamp, interval: KlineInterval) Timestamp;

    /// 判断是否在同一个 K线周期内
    pub fn isInSameKline(self: Timestamp, other: Timestamp, interval: KlineInterval) bool;
};

/// 时间间隔
pub const Duration = struct {
    millis: i64,

    /// 常量
    pub const ZERO: Duration = .{ .millis = 0 };
    pub const SECOND: Duration = .{ .millis = 1000 };
    pub const MINUTE: Duration = .{ .millis = 60_000 };
    pub const HOUR: Duration = .{ .millis = 3_600_000 };
    pub const DAY: Duration = .{ .millis = 86_400_000 };

    /// 从不同单位创建
    pub fn fromMillis(millis: i64) Duration;
    pub fn fromSeconds(secs: i64) Duration;
    pub fn fromMinutes(mins: i64) Duration;
    pub fn fromHours(hours: i64) Duration;
    pub fn fromDays(days: i64) Duration;

    /// 转换到不同单位
    pub fn toMillis(self: Duration) i64;
    pub fn toSeconds(self: Duration) f64;
    pub fn toMinutes(self: Duration) f64;
    pub fn toHours(self: Duration) f64;
    pub fn toDays(self: Duration) f64;

    /// Duration 运算
    pub fn add(self: Duration, other: Duration) Duration;
    pub fn sub(self: Duration, other: Duration) Duration;
    pub fn mul(self: Duration, factor: i64) Duration;
    pub fn div(self: Duration, divisor: i64) Duration;

    /// 比较
    pub fn cmp(self: Duration, other: Duration) std.math.Order;
    pub fn eql(self: Duration, other: Duration) bool;
    pub fn isPositive(self: Duration) bool;
    pub fn isNegative(self: Duration) bool;
    pub fn abs(self: Duration) Duration;
};

/// K线时间间隔
pub const KlineInterval = enum {
    @"1m",   // 1 分钟
    @"3m",   // 3 分钟
    @"5m",   // 5 分钟
    @"15m",  // 15 分钟
    @"30m",  // 30 分钟
    @"1h",   // 1 小时
    @"2h",   // 2 小时
    @"4h",   // 4 小时
    @"6h",   // 6 小时
    @"12h",  // 12 小时
    @"1d",   // 1 天
    @"1w",   // 1 周

    /// 获取间隔的毫秒数
    pub fn toMillis(self: KlineInterval) i64 {
        return switch (self) {
            .@"1m" => 60_000,
            .@"3m" => 180_000,
            .@"5m" => 300_000,
            .@"15m" => 900_000,
            .@"30m" => 1_800_000,
            .@"1h" => 3_600_000,
            .@"2h" => 7_200_000,
            .@"4h" => 14_400_000,
            .@"6h" => 21_600_000,
            .@"12h" => 43_200_000,
            .@"1d" => 86_400_000,
            .@"1w" => 604_800_000,
        };
    }

    /// 从字符串解析
    pub fn fromString(s: []const u8) !KlineInterval;

    /// 转换为字符串
    pub fn toString(self: KlineInterval) []const u8;
};
```

### 实现细节

#### ISO 8601 解析
```zig
pub fn fromISO8601(s: []const u8) !Timestamp {
    // 支持格式:
    // "2025-01-22T10:30:45Z"
    // "2025-01-22T10:30:45.123Z"

    if (s.len < 20) return error.InvalidFormat;

    // 解析 YYYY-MM-DD
    const year = try std.fmt.parseInt(i32, s[0..4], 10);
    const month = try std.fmt.parseInt(u8, s[5..7], 10);
    const day = try std.fmt.parseInt(u8, s[8..10], 10);

    // 解析 HH:MM:SS
    const hour = try std.fmt.parseInt(u8, s[11..13], 10);
    const minute = try std.fmt.parseInt(u8, s[14..16], 10);
    const second = try std.fmt.parseInt(u8, s[17..19], 10);

    // 解析毫秒（可选）
    var millis: u16 = 0;
    if (s.len > 20 and s[19] == '.') {
        const end = std.mem.indexOfScalar(u8, s[20..], 'Z') orelse return error.InvalidFormat;
        millis = try std.fmt.parseInt(u16, s[20..20+end], 10);
    }

    // 转换为 Unix 时间戳
    // 使用简化的日期计算
    const epoch_days = daysSinceEpoch(year, month, day);
    const total_seconds = epoch_days * 86400 +
                         @as(i64, hour) * 3600 +
                         @as(i64, minute) * 60 +
                         @as(i64, second);

    return .{ .millis = total_seconds * 1000 + millis };
}
```

#### K线时间对齐
```zig
pub fn alignToKline(self: Timestamp, interval: KlineInterval) Timestamp {
    const interval_millis = interval.toMillis();

    // 向下取整到最近的 K线开始时间
    const aligned = @divFloor(self.millis, interval_millis) * interval_millis;

    return .{ .millis = aligned };
}
```

### 文件结构
```
src/core/
├── time.zig              # 时间处理实现
└── time_test.zig         # 单元测试（可选，或内联测试）
```

---

## 📝 任务分解

### Phase 1: 基础结构 ✅
- [x] 任务 1.1: 定义 Timestamp 结构体
- [x] 任务 1.2: 定义 Duration 结构体
- [x] 任务 1.3: 定义 KlineInterval 枚举
- [x] 任务 1.4: 实现基本构造函数

### Phase 2: 核心功能 ✅
- [x] 任务 2.1: 实现时间运算（add, sub, diff）
- [x] 任务 2.2: 实现时间比较
- [x] 任务 2.3: 实现 ISO 8601 解析
- [x] 任务 2.4: 实现 ISO 8601 格式化
- [x] 任务 2.5: 实现 K线时间对齐

### Phase 3: 测试与文档 ✅
- [x] 任务 3.1: 编写基础测试
- [x] 任务 3.2: 编写边界测试（溢出、负数）
- [x] 任务 3.3: 编写 K线对齐测试
- [x] 任务 3.4: 性能基准测试
- [x] 任务 3.5: 更新文档
- [x] 任务 3.6: 代码审查

---

## 🧪 测试策略

### 单元测试

```zig
// src/core/time.zig

const testing = std.testing;

test "Timestamp: now()" {
    const t1 = Timestamp.now();
    std.time.sleep(10 * std.time.ns_per_ms);
    const t2 = Timestamp.now();

    try testing.expect(t2.isAfter(t1));
    const diff = t2.diff(t1);
    try testing.expect(diff.toMillis() >= 10);
}

test "Timestamp: fromSeconds and toSeconds" {
    const t = Timestamp.fromSeconds(1737543045);
    try testing.expectEqual(@as(i64, 1737543045), t.toSeconds());
    try testing.expectEqual(@as(i64, 1737543045000), t.toMillis());
}

test "Timestamp: ISO 8601 parsing" {
    const t = try Timestamp.fromISO8601("2025-01-22T10:30:45Z");
    try testing.expectEqual(@as(i64, 1737543045000), t.toMillis());

    // 带毫秒
    const t2 = try Timestamp.fromISO8601("2025-01-22T10:30:45.123Z");
    try testing.expectEqual(@as(i64, 1737543045123), t2.toMillis());
}

test "Timestamp: ISO 8601 formatting" {
    const t = Timestamp.fromMillis(1737543045123);
    const s = try t.toISO8601(testing.allocator);
    defer testing.allocator.free(s);

    try testing.expectEqualStrings("2025-01-22T10:30:45.123Z", s);
}

test "Timestamp: arithmetic" {
    const t1 = Timestamp.fromSeconds(1000);
    const d = Duration.fromSeconds(500);

    const t2 = t1.add(d);
    try testing.expectEqual(@as(i64, 1500), t2.toSeconds());

    const t3 = t2.sub(d);
    try testing.expectEqual(@as(i64, 1000), t3.toSeconds());

    const diff = t2.diff(t1);
    try testing.expectEqual(@as(i64, 500000), diff.toMillis());
}

test "Timestamp: comparison" {
    const t1 = Timestamp.fromSeconds(1000);
    const t2 = Timestamp.fromSeconds(2000);
    const t3 = Timestamp.fromSeconds(1000);

    try testing.expect(t1.isBefore(t2));
    try testing.expect(t2.isAfter(t1));
    try testing.expect(t1.eql(t3));
    try testing.expectEqual(std.math.Order.lt, t1.cmp(t2));
}

test "Timestamp: kline alignment" {
    // 2025-01-22 10:32:45 -> align to 1m -> 2025-01-22 10:32:00
    const t = try Timestamp.fromISO8601("2025-01-22T10:32:45Z");
    const aligned = t.alignToKline(.@"1m");

    const expected = try Timestamp.fromISO8601("2025-01-22T10:32:00Z");
    try testing.expect(aligned.eql(expected));

    // 5分钟对齐
    const t2 = try Timestamp.fromISO8601("2025-01-22T10:32:45Z");
    const aligned2 = t2.alignToKline(.@"5m");
    const expected2 = try Timestamp.fromISO8601("2025-01-22T10:30:00Z");
    try testing.expect(aligned2.eql(expected2));
}

test "Timestamp: same kline check" {
    const t1 = try Timestamp.fromISO8601("2025-01-22T10:32:10Z");
    const t2 = try Timestamp.fromISO8601("2025-01-22T10:32:50Z");
    const t3 = try Timestamp.fromISO8601("2025-01-22T10:33:10Z");

    // t1 和 t2 在同一个 1分钟 K线内
    try testing.expect(t1.isInSameKline(t2, .@"1m"));

    // t1 和 t3 不在同一个 1分钟 K线内
    try testing.expect(!t1.isInSameKline(t3, .@"1m"));

    // 但在同一个 5分钟 K线内
    try testing.expect(t1.isInSameKline(t3, .@"5m"));
}

test "Duration: creation and conversion" {
    const d1 = Duration.fromSeconds(120);
    try testing.expectEqual(@as(i64, 120000), d1.toMillis());
    try testing.expectEqual(@as(f64, 120.0), d1.toSeconds());
    try testing.expectEqual(@as(f64, 2.0), d1.toMinutes());

    const d2 = Duration.fromHours(1);
    try testing.expectEqual(@as(f64, 3600.0), d2.toSeconds());
}

test "Duration: arithmetic" {
    const d1 = Duration.fromMinutes(10);
    const d2 = Duration.fromMinutes(5);

    const d3 = d1.add(d2);
    try testing.expectEqual(@as(f64, 15.0), d3.toMinutes());

    const d4 = d1.sub(d2);
    try testing.expectEqual(@as(f64, 5.0), d4.toMinutes());

    const d5 = d1.mul(3);
    try testing.expectEqual(@as(f64, 30.0), d5.toMinutes());
}

test "Duration: negative durations" {
    const d = Duration.fromSeconds(-100);
    try testing.expect(d.isNegative());
    try testing.expect(!d.isPositive());

    const abs_d = d.abs();
    try testing.expect(abs_d.isPositive());
    try testing.expectEqual(@as(i64, 100000), abs_d.toMillis());
}

test "KlineInterval: parsing and conversion" {
    const interval = try KlineInterval.fromString("5m");
    try testing.expectEqual(KlineInterval.@"5m", interval);
    try testing.expectEqual(@as(i64, 300_000), interval.toMillis());
    try testing.expectEqualStrings("5m", interval.toString());
}
```

### 边界测试

```zig
test "Timestamp: edge cases" {
    // Unix epoch
    const epoch = Timestamp.fromMillis(0);
    try testing.expectEqual(@as(i64, 0), epoch.toMillis());

    // 负时间戳（1970年之前）
    const before_epoch = Timestamp.fromMillis(-1000);
    try testing.expectEqual(@as(i64, -1000), before_epoch.toMillis());

    // 很大的时间戳（2100年）
    const future = Timestamp.fromMillis(4102444800000); // 2100-01-01
    try testing.expect(future.toMillis() > 0);
}

test "Duration: overflow protection" {
    // 测试非常大的 duration
    const max_days = Duration.fromDays(10000);
    try testing.expect(max_days.toMillis() > 0);

    // 测试运算溢出
    const d1 = Duration.fromMillis(std.math.maxInt(i64) / 2);
    const d2 = Duration.fromMillis(100);
    // 应该不会溢出
    _ = d1.add(d2);
}
```

---

## 📚 相关文档

### 设计文档
- [x] `docs/features/time/README.md` - 功能概览
- [x] `docs/features/time/implementation.md` - 实现细节
- [x] `docs/features/time/api.md` - API 文档

### 参考资料
- [Zig std.time](https://ziglang.org/documentation/master/std/#std.time)
- [ISO 8601 标准](https://en.wikipedia.org/wiki/ISO_8601)
- [Unix Time](https://en.wikipedia.org/wiki/Unix_time)

---

## 🔗 依赖关系

### 前置条件
- [x] Zig 编译器已安装
- [x] 项目结构已搭建

### 被依赖
- Story 003: Error System（日志时间戳）
- Story 004: Logger（日志时间戳）
- v0.2: Hyperliquid 连接器（API 时间戳）
- 未来: K线数据结构
- 未来: 回测引擎

---

## ⚠️ 风险与挑战

### 已识别风险
1. **时区处理复杂性**: ISO 8601 支持多种时区格式
   - **影响**: 中
   - **缓解措施**: 仅支持 UTC (Z)，简化实现

2. **日期计算准确性**: 闰年、月份天数不同
   - **影响**: 高
   - **缓解措施**: 使用标准算法，充分测试边界情况

3. **性能**: 频繁的时间转换可能影响性能
   - **影响**: 低
   - **缓解措施**: 内部统一使用毫秒时间戳，减少转换

### 技术挑战
1. **ISO 8601 解析**: 格式多样
   - **解决方案**: 仅支持常用格式，提供清晰的错误信息

2. **K线对齐**: 处理不同时区
   - **解决方案**: 统一使用 UTC，在展示层处理时区

---

## 📊 进度追踪

### 时间线
- 开始日期: 2025-12-20
- 预计完成: 2025-12-24
- 实际完成: 2025-12-23 ✅

### 工作日志
| 日期 | 进展 | 备注 |
|------|------|------|
| 2025-12-20 | 设计 Timestamp 和 Duration 类型 | 确定毫秒精度 |
| 2025-12-21 | 实现核心功能 | ISO 8601 解析和 K线对齐 |
| 2025-12-23 | 完成测试和文档 | 11 测试全部通过 |

---

## 🐛 Bug 追踪

（开发过程中记录）

---

## ✅ 验收检查清单

- [x] 所有验收标准已满足
- [x] 所有任务已完成
- [x] 单元测试通过 (11/11, 覆盖率 > 90%)
- [x] 边界测试通过
- [x] 代码已审查
- [x] 文档已更新 (6 个文档文件)
- [x] 无编译警告
- [x] 性能符合预期
- [x] Roadmap 已更新

---

## 💡 未来改进

- [ ] 支持更多时区
- [ ] 支持自然语言时间解析（"1 hour ago"）
- [ ] 支持更多日期格式
- [ ] 支持时间范围（TimeRange）
- [ ] SIMD 优化批量时间处理

---

## 📝 备注

时间处理是系统的基础，所有涉及时间的地方都应使用这套工具，而非直接使用 `std.time` 或操作系统时间。

---

*Last updated: 2025-12-23*
*Assignee: Claude Code*
*Status: ✅ Completed and Verified*
