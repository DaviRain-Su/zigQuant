# Clock-Driven - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-27

---

## 类型定义

### Clock

时钟驱动调度器，按固定间隔触发策略执行。

```zig
pub const Clock = struct {
    allocator: Allocator,
    tick_interval_ns: u64,
    strategies: std.ArrayList(*IClockStrategy),
    running: std.atomic.Value(bool),
    tick_count: u64,
    total_tick_time_ns: u64,
    max_tick_time_ns: u64,
};
```

### IClockStrategy

Clock-Driven 策略接口，使用 VTable 实现多态。

```zig
pub const IClockStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        onTick: *const fn (ptr: *anyopaque, tick: u64, timestamp: i128) anyerror!void,
        onStart: *const fn (ptr: *anyopaque) anyerror!void,
        onStop: *const fn (ptr: *anyopaque) void,
    };
};
```

### ClockStats

时钟统计信息。

```zig
pub const ClockStats = struct {
    tick_count: u64,
    avg_tick_time_ns: u64,
    max_tick_time_ns: u64,
    strategy_count: usize,
};
```

---

## Clock 函数

### `init`

```zig
pub fn init(allocator: Allocator, tick_interval_ms: u64) Clock
```

**描述**: 初始化时钟调度器

**参数**:
- `allocator`: 内存分配器
- `tick_interval_ms`: tick 间隔 (毫秒)

**返回**: 初始化的 Clock 实例

**示例**:
```zig
var clock = Clock.init(allocator, 1000);  // 1秒间隔
defer clock.deinit();
```

---

### `deinit`

```zig
pub fn deinit(self: *Clock) void
```

**描述**: 释放时钟资源

**参数**:
- `self`: Clock 实例指针

**示例**:
```zig
defer clock.deinit();
```

---

### `addStrategy`

```zig
pub fn addStrategy(self: *Clock, strategy: *IClockStrategy) !void
```

**描述**: 注册策略到时钟

**参数**:
- `self`: Clock 实例指针
- `strategy`: 策略接口指针

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
var strategy = MyStrategy.init(allocator);
try clock.addStrategy(&strategy.asClockStrategy());
```

---

### `removeStrategy`

```zig
pub fn removeStrategy(self: *Clock, strategy: *IClockStrategy) void
```

**描述**: 从时钟移除策略

**参数**:
- `self`: Clock 实例指针
- `strategy`: 要移除的策略

**示例**:
```zig
clock.removeStrategy(&strategy.asClockStrategy());
```

---

### `start`

```zig
pub fn start(self: *Clock) !void
```

**描述**: 启动时钟 (阻塞调用)

**参数**:
- `self`: Clock 实例指针

**错误**:
- `error.AlreadyRunning`: 时钟已在运行

**注意**: 此方法会阻塞直到 `stop()` 被调用

**示例**:
```zig
// 在单独线程启动
const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});
```

---

### `stop`

```zig
pub fn stop(self: *Clock) void
```

**描述**: 停止时钟

**参数**:
- `self`: Clock 实例指针

**示例**:
```zig
clock.stop();
thread.join();
```

---

### `getStats`

```zig
pub fn getStats(self: *Clock) ClockStats
```

**描述**: 获取时钟统计信息

**参数**:
- `self`: Clock 实例指针

**返回**: ClockStats 结构

**示例**:
```zig
const stats = clock.getStats();
std.debug.print("Tick count: {}\n", .{stats.tick_count});
```

---

## IClockStrategy 函数

### `onTick`

```zig
pub fn onTick(self: IClockStrategy, tick: u64, timestamp: i128) !void
```

**描述**: 每个 tick 触发的回调

**参数**:
- `tick`: 当前 tick 编号
- `timestamp`: 纳秒级时间戳

---

### `onStart`

```zig
pub fn onStart(self: IClockStrategy) !void
```

**描述**: 时钟启动时调用

---

### `onStop`

```zig
pub fn onStop(self: IClockStrategy) void
```

**描述**: 时钟停止时调用

---

## 完整示例

```zig
const std = @import("std");
const Clock = @import("market_making/clock.zig").Clock;
const IClockStrategy = @import("market_making/interfaces.zig").IClockStrategy;

/// 自定义策略实现
pub const MyStrategy = struct {
    name: []const u8,
    tick_count: u64,

    const vtable = IClockStrategy.VTable{
        .onTick = onTickImpl,
        .onStart = onStartImpl,
        .onStop = onStopImpl,
    };

    pub fn init(name: []const u8) MyStrategy {
        return .{ .name = name, .tick_count = 0 };
    }

    pub fn asClockStrategy(self: *MyStrategy) IClockStrategy {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn onTickImpl(ptr: *anyopaque, tick: u64, timestamp: i128) !void {
        const self: *MyStrategy = @ptrCast(@alignCast(ptr));
        self.tick_count = tick;
        std.log.info("[{}] Tick {}", .{ self.name, tick });
    }

    fn onStartImpl(ptr: *anyopaque) !void {
        const self: *MyStrategy = @ptrCast(@alignCast(ptr));
        std.log.info("[{}] Started", .{self.name});
    }

    fn onStopImpl(ptr: *anyopaque) void {
        const self: *MyStrategy = @ptrCast(@alignCast(ptr));
        std.log.info("[{}] Stopped after {} ticks", .{ self.name, self.tick_count });
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建时钟
    var clock = Clock.init(allocator, 1000);
    defer clock.deinit();

    // 创建策略
    var strategy1 = MyStrategy.init("Strategy-1");
    var strategy2 = MyStrategy.init("Strategy-2");

    // 注册策略
    try clock.addStrategy(&strategy1.asClockStrategy());
    try clock.addStrategy(&strategy2.asClockStrategy());

    // 后台启动
    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});

    // 运行 10 秒
    std.time.sleep(10_000_000_000);

    // 停止
    clock.stop();
    thread.join();

    // 打印统计
    const stats = clock.getStats();
    std.debug.print("\nStats:\n", .{});
    std.debug.print("  Tick count: {}\n", .{stats.tick_count});
    std.debug.print("  Avg tick time: {}ns\n", .{stats.avg_tick_time_ns});
    std.debug.print("  Max tick time: {}ns\n", .{stats.max_tick_time_ns});
}
```

---

*完整实现请参考: `src/market_making/clock.zig`*
