# Story 033: Clock-Driven 模式

**版本**: v0.7.0
**状态**: 待开发
**优先级**: P0
**预计时间**: 3-4 天
**依赖**: v0.6.0 完成

---

## 概述

实现 Clock-Driven (时钟驱动) 策略执行模式。与 Event-Driven 模式不同，Clock-Driven 模式按固定时间间隔触发策略，适合做市等需要定期更新报价的场景。

---

## 背景

### Event-Driven vs Clock-Driven

```
┌─────────────────────────────────────────────────────────────────┐
│                    策略执行模式对比                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Event-Driven (事件驱动):                                       │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐                       │
│  │ 事件 1  │→ │ 策略    │→ │ 信号?   │                        │
│  └─────────┘   └─────────┘   └─────────┘                       │
│       ↓                                                         │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐                       │
│  │ 事件 2  │→ │ 策略    │→ │ 信号?   │                        │
│  └─────────┘   └─────────┘   └─────────┘                       │
│  (每次事件都触发策略)                                           │
│                                                                  │
│  Clock-Driven (时钟驱动):                                       │
│  ┌─────┐ ┌─────┐ ┌─────┐                                       │
│  │Tick1│ │Tick2│ │Tick3│ ... (固定间隔)                        │
│  └──┬──┘ └──┬──┘ └──┬──┘                                       │
│     ↓       ↓       ↓                                           │
│  ┌─────────────────────────┐                                   │
│  │   策略.onTick()          │                                   │
│  │   - 读取最新市场数据     │                                   │
│  │   - 更新报价             │                                   │
│  └─────────────────────────┘                                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 为什么需要 Clock-Driven?

1. **做市策略**: 需要定期更新双边报价，而不是响应每个订单簿更新
2. **资源效率**: 避免高频事件导致的过度计算
3. **报价稳定**: 固定间隔更新，避免报价抖动
4. **Hummingbot 参考**: 成熟做市框架的标准模式

---

## 技术设计

### 核心组件

```
┌─────────────────────────────────────────────────────────────────┐
│                      Clock-Driven 架构                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                       Clock                               │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │  │
│  │  │ tick_interval│  │ tick_count  │  │  running    │      │  │
│  │  │    1000ms   │  │    12345    │  │   true      │      │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘      │  │
│  │                                                          │  │
│  │  ┌────────────────────────────────────────────────────┐ │  │
│  │  │               strategies: ArrayList                  │ │  │
│  │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐           │ │  │
│  │  │  │ Strategy1│ │ Strategy2│ │ Strategy3│           │ │  │
│  │  │  └──────────┘ └──────────┘ └──────────┘           │ │  │
│  │  └────────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  IClockStrategy                           │  │
│  │  • onTick(tick: u64, timestamp: i128)                    │  │
│  │  • onStart()                                              │  │
│  │  • onStop()                                               │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Clock 实现

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

/// 时钟驱动调度器
pub const Clock = struct {
    allocator: Allocator,
    tick_interval_ns: u64,  // 纳秒
    strategies: std.ArrayList(*IClockStrategy),
    running: std.atomic.Value(bool),
    tick_count: u64,

    // 统计
    total_tick_time_ns: u64,
    max_tick_time_ns: u64,

    const Self = @This();

    pub fn init(allocator: Allocator, tick_interval_ms: u64) Self {
        return .{
            .allocator = allocator,
            .tick_interval_ns = tick_interval_ms * 1_000_000,
            .strategies = std.ArrayList(*IClockStrategy).init(allocator),
            .running = std.atomic.Value(bool).init(false),
            .tick_count = 0,
            .total_tick_time_ns = 0,
            .max_tick_time_ns = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.strategies.deinit();
    }

    /// 注册策略
    pub fn addStrategy(self: *Self, strategy: *IClockStrategy) !void {
        try self.strategies.append(strategy);
    }

    /// 移除策略
    pub fn removeStrategy(self: *Self, strategy: *IClockStrategy) void {
        for (self.strategies.items, 0..) |s, i| {
            if (s == strategy) {
                _ = self.strategies.orderedRemove(i);
                break;
            }
        }
    }

    /// 启动时钟
    pub fn start(self: *Self) !void {
        if (self.running.load(.seq_cst)) {
            return error.AlreadyRunning;
        }

        self.running.store(true, .seq_cst);

        // 通知所有策略启动
        for (self.strategies.items) |strategy| {
            try strategy.vtable.onStart(strategy.ptr);
        }

        // 主循环
        while (self.running.load(.seq_cst)) {
            const tick_start = std.time.nanoTimestamp();
            self.tick_count += 1;

            // 触发所有策略
            for (self.strategies.items) |strategy| {
                strategy.vtable.onTick(strategy.ptr, self.tick_count, tick_start) catch |err| {
                    std.log.err("Strategy tick error: {}", .{err});
                };
            }

            // 统计
            const tick_duration: u64 = @intCast(std.time.nanoTimestamp() - tick_start);
            self.total_tick_time_ns += tick_duration;
            if (tick_duration > self.max_tick_time_ns) {
                self.max_tick_time_ns = tick_duration;
            }

            // 等待下一个 tick
            if (tick_duration < self.tick_interval_ns) {
                const sleep_time = self.tick_interval_ns - tick_duration;
                std.time.sleep(sleep_time);
            } else {
                // Tick 超时警告
                std.log.warn("Tick {} took {}ms, exceeds interval {}ms", .{
                    self.tick_count,
                    tick_duration / 1_000_000,
                    self.tick_interval_ns / 1_000_000,
                });
            }
        }

        // 通知所有策略停止
        for (self.strategies.items) |strategy| {
            strategy.vtable.onStop(strategy.ptr);
        }
    }

    /// 停止时钟
    pub fn stop(self: *Self) void {
        self.running.store(false, .seq_cst);
    }

    /// 获取统计信息
    pub fn getStats(self: *Self) ClockStats {
        return .{
            .tick_count = self.tick_count,
            .avg_tick_time_ns = if (self.tick_count > 0)
                self.total_tick_time_ns / self.tick_count
            else 0,
            .max_tick_time_ns = self.max_tick_time_ns,
            .strategy_count = self.strategies.items.len,
        };
    }
};

pub const ClockStats = struct {
    tick_count: u64,
    avg_tick_time_ns: u64,
    max_tick_time_ns: u64,
    strategy_count: usize,
};
```

### IClockStrategy 接口

```zig
/// Clock-Driven 策略接口
pub const IClockStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        onTick: *const fn (ptr: *anyopaque, tick: u64, timestamp: i128) anyerror!void,
        onStart: *const fn (ptr: *anyopaque) anyerror!void,
        onStop: *const fn (ptr: *anyopaque) void,
    };

    /// 便捷方法
    pub fn onTick(self: IClockStrategy, tick: u64, timestamp: i128) !void {
        return self.vtable.onTick(self.ptr, tick, timestamp);
    }

    pub fn onStart(self: IClockStrategy) !void {
        return self.vtable.onStart(self.ptr);
    }

    pub fn onStop(self: IClockStrategy) void {
        self.vtable.onStop(self.ptr);
    }
};
```

### 示例策略实现

```zig
/// 简单做市策略示例
pub const SimpleMMStrategy = struct {
    allocator: Allocator,
    symbol: []const u8,
    spread_bps: u32,
    last_update_tick: u64,

    // 接口实现
    const vtable = IClockStrategy.VTable{
        .onTick = onTickImpl,
        .onStart = onStartImpl,
        .onStop = onStopImpl,
    };

    const Self = @This();

    pub fn init(allocator: Allocator, symbol: []const u8, spread_bps: u32) Self {
        return .{
            .allocator = allocator,
            .symbol = symbol,
            .spread_bps = spread_bps,
            .last_update_tick = 0,
        };
    }

    pub fn asClockStrategy(self: *Self) IClockStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn onTickImpl(ptr: *anyopaque, tick: u64, timestamp: i128) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = timestamp;

        // 做市逻辑
        std.log.info("Tick {}: Updating quotes for {}", .{ tick, self.symbol });
        self.last_update_tick = tick;

        // TODO: 实际的报价更新逻辑
    }

    fn onStartImpl(ptr: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        std.log.info("Starting market making for {}", .{self.symbol});
    }

    fn onStopImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        std.log.info("Stopping market making for {}", .{self.symbol});
    }
};
```

---

## 实现任务

### Task 1: Clock 核心结构 (Day 1)

- [ ] 创建 `src/market_making/clock.zig`
- [ ] 实现 Clock struct
- [ ] 实现 start/stop 方法
- [ ] 实现原子状态管理
- [ ] 添加基础单元测试

### Task 2: IClockStrategy 接口 (Day 1)

- [ ] 定义 IClockStrategy 接口
- [ ] 实现 VTable 结构
- [ ] 创建便捷方法
- [ ] 添加文档注释

### Task 3: Tick 精度优化 (Day 2)

- [ ] 实现高精度睡眠
- [ ] 添加 tick 超时检测
- [ ] 实现 tick 统计
- [ ] 测试 tick 抖动 (目标 < 10ms)

### Task 4: 策略管理 (Day 2-3)

- [ ] 实现策略注册/注销
- [ ] 支持动态添加策略
- [ ] 实现策略优先级
- [ ] 添加错误处理

### Task 5: 集成测试 (Day 3-4)

- [ ] 与 MessageBus 集成
- [ ] 与 Paper Trading 集成
- [ ] 性能基准测试
- [ ] 端到端测试

---

## 测试计划

### 单元测试

```zig
test "Clock start and stop" {
    var clock = Clock.init(testing.allocator, 100);  // 100ms tick
    defer clock.deinit();

    // 启动时钟 (后台线程)
    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});

    // 等待几个 tick
    std.time.sleep(350_000_000);  // 350ms

    // 停止
    clock.stop();
    thread.join();

    // 验证
    try testing.expect(clock.tick_count >= 3);
}

test "Clock strategy registration" {
    var clock = Clock.init(testing.allocator, 100);
    defer clock.deinit();

    var strategy = SimpleMMStrategy.init(testing.allocator, "ETH", 10);
    try clock.addStrategy(&strategy.asClockStrategy());

    try testing.expect(clock.strategies.items.len == 1);
}

test "Clock tick precision" {
    var clock = Clock.init(testing.allocator, 10);  // 10ms tick
    defer clock.deinit();

    // 运行 100 ticks
    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});
    std.time.sleep(1_100_000_000);  // 1.1s
    clock.stop();
    thread.join();

    const stats = clock.getStats();

    // 验证 tick 数量
    try testing.expect(stats.tick_count >= 95 and stats.tick_count <= 110);

    // 验证抖动 (< 10ms)
    try testing.expect(stats.max_tick_time_ns < 10_000_000);
}
```

### 性能测试

| 测试项 | 目标 | 验收标准 |
|--------|------|----------|
| Tick 精度 | < 10ms 抖动 | 99% tick 在 ±10ms 内 |
| 策略执行 | < 1ms | 单策略 onTick < 1ms |
| 多策略 | 线性扩展 | 10 策略 < 10ms |
| 内存 | 稳定 | 运行 1 小时无泄漏 |

---

## 验收标准

### 功能验收

- [ ] Clock 可以按固定间隔触发 tick
- [ ] 策略可以注册和注销
- [ ] start/stop 正常工作
- [ ] 统计信息准确

### 性能验收

- [ ] Tick 抖动 < 10ms (99th percentile)
- [ ] 单 tick 处理 < 1ms
- [ ] 内存使用稳定

### 代码验收

- [ ] 完整的单元测试
- [ ] 零内存泄漏
- [ ] 代码文档完整

---

## 文件结构

```
src/market_making/
├── mod.zig           # 模块导出
├── clock.zig         # Clock 实现
└── interfaces.zig    # IClockStrategy 接口

tests/
└── clock_test.zig    # Clock 测试
```

---

## 参考资料

- [Hummingbot Clock](https://github.com/hummingbot/hummingbot/blob/master/hummingbot/core/clock.pyx)
- [Zig Atomics](https://ziglang.org/documentation/master/#Atomics)
- [High-precision timing](https://en.cppreference.com/w/cpp/chrono)

---

**Story**: 033
**版本**: v0.7.0
**创建时间**: 2025-12-27
