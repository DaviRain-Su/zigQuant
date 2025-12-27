# Clock-Driven 时钟驱动模式

> 按固定时间间隔触发策略执行，适合做市等定期更新报价的场景

**状态**: 📋 待开发
**版本**: v0.7.0
**Story**: [Story 033](../../stories/v0.7.0/STORY_033_CLOCK_DRIVEN.md)
**最后更新**: 2025-12-27

---

## 概述

Clock-Driven (时钟驱动) 是一种策略执行模式，与 Event-Driven 模式不同，它按固定时间间隔触发策略，而不是响应每个市场事件。这种模式特别适合做市策略，需要定期更新双边报价。

### 为什么需要 Clock-Driven？

**Event-Driven vs Clock-Driven**:

```
Event-Driven (事件驱动):
┌─────────┐   ┌─────────┐   ┌─────────┐
│ 事件 1  │→ │ 策略    │→ │ 信号?   │
└─────────┘   └─────────┘   └─────────┘
(每次事件都触发策略，高频场景开销大)

Clock-Driven (时钟驱动):
┌─────┐ ┌─────┐ ┌─────┐
│Tick1│ │Tick2│ │Tick3│ ... (固定间隔)
└──┬──┘ └──┬──┘ └──┬──┘
   ↓       ↓       ↓
策略.onTick() → 读取最新数据 → 更新报价
```

**核心优势**:

1. **做市场景**: 定期更新双边报价，避免响应每个订单簿更新
2. **资源效率**: 固定频率执行，避免高频事件导致的过度计算
3. **报价稳定**: 固定间隔更新，减少报价抖动
4. **Hummingbot 验证**: 成熟做市框架的标准模式

### 核心特性

- **固定间隔触发**: 支持毫秒级 tick 间隔配置
- **多策略管理**: 同时运行多个 Clock-Driven 策略
- **IClockStrategy 接口**: 统一的策略接口 (onTick/onStart/onStop)
- **Tick 精度**: 抖动 < 10ms (99th percentile)
- **统计监控**: tick 计数、平均耗时、最大耗时

---

## 快速开始

### 基本使用

```zig
const std = @import("std");
const Clock = @import("market_making/clock.zig").Clock;
const SimpleMMStrategy = @import("market_making/strategies.zig").SimpleMMStrategy;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建时钟 (1秒 tick 间隔)
    var clock = Clock.init(allocator, 1000);
    defer clock.deinit();

    // 创建做市策略
    var strategy = SimpleMMStrategy.init(allocator, "ETH-USD", 10);  // 10 bps spread

    // 注册策略
    try clock.addStrategy(&strategy.asClockStrategy());

    // 启动时钟 (阻塞)
    try clock.start();
}
```

### 使用线程启动

```zig
// 后台线程启动
const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});

// 主线程继续其他工作...
std.time.sleep(60_000_000_000);  // 运行 60 秒

// 停止时钟
clock.stop();
thread.join();

// 查看统计
const stats = clock.getStats();
std.debug.print("Total ticks: {}, Avg time: {}ns\n", .{
    stats.tick_count,
    stats.avg_tick_time_ns,
});
```

---

## 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 核心 API

### Clock 结构

```zig
pub const Clock = struct {
    allocator: Allocator,
    tick_interval_ns: u64,           // Tick 间隔 (纳秒)
    strategies: ArrayList(*IClockStrategy),
    running: atomic.Value(bool),
    tick_count: u64,

    // 统计
    total_tick_time_ns: u64,
    max_tick_time_ns: u64,

    /// 初始化时钟
    pub fn init(allocator: Allocator, tick_interval_ms: u64) Clock;

    /// 释放资源
    pub fn deinit(self: *Clock) void;

    /// 注册策略
    pub fn addStrategy(self: *Clock, strategy: *IClockStrategy) !void;

    /// 移除策略
    pub fn removeStrategy(self: *Clock, strategy: *IClockStrategy) void;

    /// 启动时钟 (阻塞)
    pub fn start(self: *Clock) !void;

    /// 停止时钟
    pub fn stop(self: *Clock) void;

    /// 获取统计信息
    pub fn getStats(self: *Clock) ClockStats;
};
```

### IClockStrategy 接口

```zig
pub const IClockStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// 每个 tick 触发
        onTick: *const fn (ptr: *anyopaque, tick: u64, timestamp: i128) anyerror!void,
        /// 时钟启动时调用
        onStart: *const fn (ptr: *anyopaque) anyerror!void,
        /// 时钟停止时调用
        onStop: *const fn (ptr: *anyopaque) void,
    };
};
```

### ClockStats 统计

```zig
pub const ClockStats = struct {
    tick_count: u64,        // 总 tick 数
    avg_tick_time_ns: u64,  // 平均 tick 耗时
    max_tick_time_ns: u64,  // 最大 tick 耗时
    strategy_count: usize,  // 策略数量
};
```

---

## 最佳实践

### DO

```zig
// 在 onTick 中只做必要的工作
fn onTickImpl(ptr: *anyopaque, tick: u64, timestamp: i128) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));

    // 1. 读取最新市场数据 (快速)
    const mid_price = self.cache.getMidPrice(self.symbol);

    // 2. 计算新报价 (快速)
    const bid = mid_price.mul(Decimal.fromFloat(1.0 - self.spread));
    const ask = mid_price.mul(Decimal.fromFloat(1.0 + self.spread));

    // 3. 提交订单 (异步)
    try self.executor.updateQuotes(bid, ask);
}
```

### DON'T

```zig
// 不要在 onTick 中做耗时操作
fn onTickImpl(ptr: *anyopaque, tick: u64, timestamp: i128) !void {
    // 耗时操作会导致 tick 超时!
    const data = try http.fetch("https://api.example.com/data");  // 网络请求
    try db.query("SELECT * FROM large_table");  // 数据库查询
    try file.readAll();  // 文件读取
}
```

---

## 使用场景

### 适用

- **做市策略**: 定期更新双边报价
- **再平衡策略**: 按固定间隔检查仓位并调整
- **监控策略**: 定期检查市场状态并告警
- **数据采集**: 定期保存市场快照

### 不适用

- **趋势跟踪**: 需要立即响应价格突破
- **套利策略**: 需要极低延迟响应价差机会
- **高频交易**: 需要微秒级响应

---

## 性能指标

| 指标 | 目标值 | 说明 |
|------|--------|------|
| Tick 精度 | < 10ms 抖动 | 99% tick 在 ±10ms 内 |
| 单策略 onTick | < 1ms | 策略执行耗时 |
| 多策略扩展 | 线性 | 10 策略 < 10ms |
| 内存使用 | 稳定 | 运行 1 小时无泄漏 |

---

## 文件结构

```
src/market_making/
├── mod.zig           # 模块导出
├── clock.zig         # Clock 实现
└── interfaces.zig    # IClockStrategy 接口

docs/features/clock-driven/
├── README.md         # 本文档
├── api.md            # API 参考
├── implementation.md # 实现细节
├── testing.md        # 测试文档
├── bugs.md           # Bug 追踪
└── changelog.md      # 变更日志
```

---

## 未来改进

- [ ] 支持可变 tick 间隔
- [ ] 策略优先级排序
- [ ] Tick 超时自动跳过
- [ ] 与 libxev 事件循环集成

---

*Last updated: 2025-12-27*
