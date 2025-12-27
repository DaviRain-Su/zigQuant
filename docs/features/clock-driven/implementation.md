# Clock-Driven - 实现细节

> 深入了解内部实现

**最后更新**: 2025-12-27

---

## 内部表示

### 数据结构

```zig
pub const Clock = struct {
    allocator: Allocator,

    // 配置
    tick_interval_ns: u64,           // Tick 间隔 (纳秒)

    // 策略管理
    strategies: std.ArrayList(*IClockStrategy),

    // 状态 (原子操作保证线程安全)
    running: std.atomic.Value(bool),
    tick_count: u64,

    // 统计
    total_tick_time_ns: u64,
    max_tick_time_ns: u64,
};
```

### 内存布局

```
Clock (64 bytes):
┌─────────────────────────────────────┐
│ allocator     (8 bytes)             │
├─────────────────────────────────────┤
│ tick_interval_ns (8 bytes)          │
├─────────────────────────────────────┤
│ strategies    (ArrayList, 24 bytes) │
│   ├─ items: []*IClockStrategy       │
│   ├─ capacity: usize                │
│   └─ allocator: *Allocator          │
├─────────────────────────────────────┤
│ running       (atomic bool, 1 byte) │
├─────────────────────────────────────┤
│ tick_count    (8 bytes)             │
├─────────────────────────────────────┤
│ total_tick_time_ns (8 bytes)        │
├─────────────────────────────────────┤
│ max_tick_time_ns   (8 bytes)        │
└─────────────────────────────────────┘
```

---

## 核心算法

### 主循环

```zig
pub fn start(self: *Clock) !void {
    // 1. 原子状态检查和设置
    if (self.running.load(.seq_cst)) {
        return error.AlreadyRunning;
    }
    self.running.store(true, .seq_cst);

    // 2. 通知策略启动
    for (self.strategies.items) |strategy| {
        try strategy.vtable.onStart(strategy.ptr);
    }

    // 3. 主 tick 循环
    while (self.running.load(.seq_cst)) {
        const tick_start = std.time.nanoTimestamp();
        self.tick_count += 1;

        // 触发所有策略
        for (self.strategies.items) |strategy| {
            strategy.vtable.onTick(strategy.ptr, self.tick_count, tick_start) catch |err| {
                std.log.err("Strategy tick error: {}", .{err});
            };
        }

        // 更新统计
        const tick_duration = std.time.nanoTimestamp() - tick_start;
        self.updateStats(@intCast(tick_duration));

        // 精确睡眠
        self.preciseSleep(@intCast(tick_duration));
    }

    // 4. 通知策略停止
    for (self.strategies.items) |strategy| {
        strategy.vtable.onStop(strategy.ptr);
    }
}
```

**复杂度**: O(n) per tick，n = 策略数量

---

### 精确睡眠算法

```zig
fn preciseSleep(self: *Clock, elapsed_ns: u64) void {
    if (elapsed_ns >= self.tick_interval_ns) {
        // 超时警告，不睡眠
        std.log.warn("Tick took {}ms, exceeds interval {}ms", .{
            elapsed_ns / 1_000_000,
            self.tick_interval_ns / 1_000_000,
        });
        return;
    }

    const sleep_time = self.tick_interval_ns - elapsed_ns;

    // Zig 的 std.time.sleep 提供纳秒级精度
    std.time.sleep(sleep_time);
}
```

**说明**: 使用系统原生睡眠，Linux 下通过 nanosleep 实现

---

### VTable 多态实现

```zig
pub const IClockStrategy = struct {
    ptr: *anyopaque,           // 类型擦除的实例指针
    vtable: *const VTable,     // 函数指针表

    pub const VTable = struct {
        onTick: *const fn (ptr: *anyopaque, tick: u64, timestamp: i128) anyerror!void,
        onStart: *const fn (ptr: *anyopaque) anyerror!void,
        onStop: *const fn (ptr: *anyopaque) void,
    };

    // 便捷方法封装 vtable 调用
    pub fn onTick(self: IClockStrategy, tick: u64, timestamp: i128) !void {
        return self.vtable.onTick(self.ptr, tick, timestamp);
    }
};
```

**优势**:
- 编译时确定函数指针，零运行时开销
- 支持任意类型实现接口
- 无需堆分配 vtable (静态 const)

---

## 性能优化

### 1. 原子状态管理

```zig
running: std.atomic.Value(bool),

// 使用 SeqCst 保证跨线程可见性
self.running.store(true, .seq_cst);
if (self.running.load(.seq_cst)) { ... }
```

**原因**: 多线程环境下的 start/stop 需要原子操作保证正确性

### 2. 内联函数调用

VTable 函数指针在编译时已知，编译器可以内联优化热点路径。

### 3. 避免策略数组拷贝

```zig
// 直接遍历 slice，不拷贝
for (self.strategies.items) |strategy| {
    // ...
}
```

### 4. 批量统计更新

```zig
fn updateStats(self: *Clock, tick_duration: u64) void {
    self.total_tick_time_ns += tick_duration;
    if (tick_duration > self.max_tick_time_ns) {
        self.max_tick_time_ns = tick_duration;
    }
}
```

---

## 内存管理

### 分配策略

| 组件 | 分配时机 | 释放时机 |
|------|----------|----------|
| Clock | init() | deinit() |
| strategies ArrayList | init() | deinit() |
| strategy 指针 | addStrategy() | removeStrategy() 或 deinit() |

### 所有权模型

```
Clock (拥有)
  └─ strategies: ArrayList (拥有)
       └─ []*IClockStrategy (借用)
            └─ 策略实例由调用者管理
```

**注意**: Clock 不拥有策略实例，只持有指针。策略生命周期由调用者管理。

---

## 边界情况

### 情况 1: 策略 onTick 抛出错误

```zig
for (self.strategies.items) |strategy| {
    strategy.vtable.onTick(strategy.ptr, self.tick_count, tick_start) catch |err| {
        // 捕获错误，记录日志，继续执行其他策略
        std.log.err("Strategy tick error: {}", .{err});
    };
}
```

**处理**: 单个策略错误不影响其他策略和时钟运行

### 情况 2: Tick 超时

```zig
if (tick_duration >= self.tick_interval_ns) {
    std.log.warn("Tick {} took {}ms, exceeds interval", .{...});
    // 不睡眠，立即执行下一个 tick
}
```

**处理**: 记录警告，跳过睡眠

### 情况 3: 重复启动

```zig
if (self.running.load(.seq_cst)) {
    return error.AlreadyRunning;
}
```

**处理**: 返回错误

### 情况 4: 空策略列表

```zig
// 主循环仍然运行，只是 for 循环不执行
for (self.strategies.items) |strategy| {
    // 空列表不会进入循环体
}
```

**处理**: 正常运行，等待策略注册

---

## 线程安全

| 操作 | 线程安全 | 说明 |
|------|----------|------|
| start() | 是 | 原子状态检查 |
| stop() | 是 | 原子状态设置 |
| addStrategy() | 否 | 需在 start() 前调用 |
| removeStrategy() | 否 | 需在 stop() 后调用 |
| getStats() | 部分 | 读取可能不一致 |

**建议**: 在时钟运行期间不要修改策略列表

---

*完整实现请参考: `src/market_making/clock.zig`*
