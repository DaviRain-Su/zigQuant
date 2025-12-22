# Time - 时间处理工具

> 高精度时间处理、K线对齐、时间运算

**状态**: 📋 待开始
**版本**: v0.1.0
**Story**: [002-time-utils](../../../stories/v0.1-foundation/002-time-utils.md)
**最后更新**: 2025-01-22

---

## 📋 概述

Time 模块提供量化交易所需的时间处理能力，包括高精度时间戳、时间间隔计算、K线时间对齐等核心功能。

### 为什么需要 Time 模块？

量化交易对时间处理有严格要求：
- 交易所 API 使用毫秒级时间戳
- K线数据需要精确的时间对齐
- 回测需要准确的时间序列
- 日志需要可读的时间格式

### 核心特性

- ✅ **毫秒精度**: Timestamp 提供毫秒级精度
- ✅ **K线对齐**: 支持 1m, 5m, 1h 等常用时间间隔
- ✅ **ISO 8601**: 标准时间格式支持
- ✅ **时间运算**: 加减、比较、间隔计算
- ✅ **零成本**: 基于 i64 整数，无额外开销

---

## 🚀 快速开始

### 基本使用

```zig
const std = @import("std");
const time = @import("core/time.zig");

pub fn main() !void {
    // 获取当前时间
    const now = time.Timestamp.now();

    // 从字符串创建
    const t = try time.Timestamp.fromISO8601("2025-01-22T10:30:45Z");

    // 时间运算
    const duration = time.Duration.fromMinutes(5);
    const future = now.add(duration);

    // K线对齐
    const aligned = now.alignToKline(.@"1m");
}
```

### K线时间对齐示例

```zig
// 当前时间: 2025-01-22 10:32:45
const now = try time.Timestamp.fromISO8601("2025-01-22T10:32:45Z");

// 对齐到 1 分钟 K线 -> 2025-01-22 10:32:00
const aligned_1m = now.alignToKline(.@"1m");

// 对齐到 5 分钟 K线 -> 2025-01-22 10:30:00
const aligned_5m = now.alignToKline(.@"5m");

// 检查两个时间是否在同一个 K线内
const in_same_kline = now.isInSameKline(other, .@"5m");
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 核心 API

```zig
/// Unix 时间戳（毫秒精度，UTC）
pub const Timestamp = struct {
    millis: i64,

    pub const ZERO: Timestamp;

    // 构造
    pub fn now() Timestamp;
    pub fn fromSeconds(secs: i64) Timestamp;
    pub fn fromMillis(millis: i64) Timestamp;
    pub fn fromISO8601(s: []const u8) !Timestamp;

    // 转换
    pub fn toSeconds(self: Timestamp) i64;
    pub fn toMillis(self: Timestamp) i64;
    pub fn toISO8601(self: Timestamp, allocator: Allocator) ![]const u8;

    // 运算
    pub fn add(self: Timestamp, duration: Duration) Timestamp;
    pub fn sub(self: Timestamp, duration: Duration) Timestamp;
    pub fn diff(self: Timestamp, other: Timestamp) Duration;

    // 比较
    pub fn cmp(self: Timestamp, other: Timestamp) std.math.Order;
    pub fn eql(self: Timestamp, other: Timestamp) bool;

    // K线相关
    pub fn alignToKline(self: Timestamp, interval: KlineInterval) Timestamp;
    pub fn isInSameKline(self: Timestamp, other: Timestamp, interval: KlineInterval) bool;
};

/// 时间间隔
pub const Duration = struct {
    millis: i64,

    pub const ZERO: Duration;
    pub const SECOND: Duration;
    pub const MINUTE: Duration;
    pub const HOUR: Duration;
    pub const DAY: Duration;

    // 构造
    pub fn fromMillis(millis: i64) Duration;
    pub fn fromSeconds(secs: i64) Duration;
    pub fn fromMinutes(mins: i64) Duration;
    pub fn fromHours(hours: i64) Duration;

    // 运算
    pub fn add(self: Duration, other: Duration) Duration;
    pub fn mul(self: Duration, factor: i64) Duration;
};

/// K线时间间隔
pub const KlineInterval = enum {
    @"1m", @"5m", @"15m", @"30m",
    @"1h", @"4h", @"1d", @"1w",

    pub fn toMillis(self: KlineInterval) i64;
    pub fn fromString(s: []const u8) !KlineInterval;
};
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 使用 ISO 8601 格式（明确且标准）
const t = try Timestamp.fromISO8601("2025-01-22T10:30:45Z");

// 2. 使用 Duration 常量
const delay = Duration.MINUTE.mul(5);  // 5 分钟

// 3. 使用 defer 释放内存
const str = try timestamp.toISO8601(allocator);
defer allocator.free(str);

// 4. K线对齐避免时间误差
const kline_start = timestamp.alignToKline(.@"5m");
```

### ❌ DON'T

```zig
// 1. 避免硬编码毫秒数
const delay = Duration.fromMillis(300000);  // 难以理解

// 2. 避免忘记时区
// 所有时间统一使用 UTC，在展示层转换

// 3. 避免频繁转换
// 内部统一使用 Timestamp/Duration，减少字符串转换
```

---

## 🎯 使用场景

### ✅ 适用

- **K线数据处理**: 时间对齐、聚合
- **订单时间戳**: 创建时间、更新时间
- **回测引擎**: 时间序列遍历
- **日志时间**: 可读的时间格式
- **API 请求**: 时间戳签名

### ❌ 不适用

- 复杂时区计算（使用专门的时区库）
- 日历计算（月份、年份）
- 自然语言时间解析

---

## 📊 性能指标

- **时间戳创建**: O(1)
- **时间运算**: O(1)
- **ISO 8601 解析**: O(n)，n 为字符串长度
- **K线对齐**: O(1)
- **内存占用**: 8 bytes (i64)

---

## 💡 未来改进

- [ ] 支持更多时区
- [ ] 支持自然语言解析（"1 hour ago"）
- [ ] 支持更多时间格式
- [ ] TimeRange 类型（时间范围）
- [ ] SIMD 优化批量时间处理

---

*Last updated: 2025-01-22*
