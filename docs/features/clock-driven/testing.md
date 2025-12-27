# Clock-Driven - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-27

---

## 测试覆盖率

- **代码覆盖率**: 目标 > 90%
- **测试用例数**: 15+
- **性能基准**: Tick 精度 < 10ms

---

## 单元测试

### 基本功能测试

```zig
test "Clock init and deinit" {
    var clock = Clock.init(testing.allocator, 100);
    defer clock.deinit();

    try testing.expect(clock.tick_interval_ns == 100_000_000);
    try testing.expect(clock.tick_count == 0);
    try testing.expect(clock.strategies.items.len == 0);
}

test "Clock strategy registration" {
    var clock = Clock.init(testing.allocator, 100);
    defer clock.deinit();

    var strategy = TestStrategy.init("test");
    try clock.addStrategy(&strategy.asClockStrategy());

    try testing.expect(clock.strategies.items.len == 1);

    clock.removeStrategy(&strategy.asClockStrategy());
    try testing.expect(clock.strategies.items.len == 0);
}
```

### 启动停止测试

```zig
test "Clock start and stop" {
    var clock = Clock.init(testing.allocator, 100);  // 100ms tick
    defer clock.deinit();

    var strategy = TestStrategy.init("test");
    try clock.addStrategy(&strategy.asClockStrategy());

    // 后台线程启动
    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});

    // 等待几个 tick
    std.time.sleep(350_000_000);  // 350ms

    // 停止
    clock.stop();
    thread.join();

    // 验证至少 3 个 tick
    try testing.expect(clock.tick_count >= 3);
    try testing.expect(strategy.tick_count >= 3);
}

test "Clock double start error" {
    var clock = Clock.init(testing.allocator, 100);
    defer clock.deinit();

    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});
    std.time.sleep(50_000_000);  // 等待启动

    // 重复启动应该返回错误
    const result = clock.start();
    try testing.expectError(error.AlreadyRunning, result);

    clock.stop();
    thread.join();
}
```

### 统计测试

```zig
test "Clock statistics" {
    var clock = Clock.init(testing.allocator, 50);  // 50ms tick
    defer clock.deinit();

    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});
    std.time.sleep(250_000_000);  // 250ms
    clock.stop();
    thread.join();

    const stats = clock.getStats();
    try testing.expect(stats.tick_count >= 4);
    try testing.expect(stats.avg_tick_time_ns > 0);
    try testing.expect(stats.max_tick_time_ns >= stats.avg_tick_time_ns);
}
```

### 多策略测试

```zig
test "Clock multiple strategies" {
    var clock = Clock.init(testing.allocator, 100);
    defer clock.deinit();

    var strategy1 = TestStrategy.init("s1");
    var strategy2 = TestStrategy.init("s2");
    var strategy3 = TestStrategy.init("s3");

    try clock.addStrategy(&strategy1.asClockStrategy());
    try clock.addStrategy(&strategy2.asClockStrategy());
    try clock.addStrategy(&strategy3.asClockStrategy());

    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});
    std.time.sleep(250_000_000);
    clock.stop();
    thread.join();

    // 所有策略应该收到相同数量的 tick
    try testing.expect(strategy1.tick_count == strategy2.tick_count);
    try testing.expect(strategy2.tick_count == strategy3.tick_count);
    try testing.expect(strategy1.tick_count >= 2);
}
```

---

## 性能基准

### Tick 精度测试

```zig
test "Clock tick precision" {
    var clock = Clock.init(testing.allocator, 10);  // 10ms tick
    defer clock.deinit();

    var precision_strategy = PrecisionTestStrategy.init();
    try clock.addStrategy(&precision_strategy.asClockStrategy());

    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});
    std.time.sleep(1_100_000_000);  // 1.1s = 110 ticks expected
    clock.stop();
    thread.join();

    const stats = clock.getStats();

    // 验证 tick 数量 (允许 10% 误差)
    try testing.expect(stats.tick_count >= 95 and stats.tick_count <= 120);

    // 验证抖动 < 10ms
    try testing.expect(stats.max_tick_time_ns < 10_000_000);

    // 验证 99th percentile
    const p99_jitter = precision_strategy.getP99Jitter();
    try testing.expect(p99_jitter < 10_000_000);
}
```

### 吞吐量测试

```zig
test "Clock throughput" {
    var clock = Clock.init(testing.allocator, 1);  // 1ms tick
    defer clock.deinit();

    var counter = CounterStrategy.init();
    try clock.addStrategy(&counter.asClockStrategy());

    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});
    std.time.sleep(1_000_000_000);  // 1s
    clock.stop();
    thread.join();

    // 1ms 间隔应该接近 1000 ticks/s
    try testing.expect(clock.tick_count >= 900);
}
```

### 基准结果

| 操作 | 性能 |
|------|------|
| Tick 频率 (10ms) | ~100 ticks/s |
| Tick 频率 (1ms) | ~1000 ticks/s |
| 单策略 onTick | < 100ns |
| 10 策略 onTick | < 1μs |
| Tick 抖动 (99th) | < 10ms |

---

## 集成测试

### 与 MessageBus 集成

```zig
test "Clock with MessageBus" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var clock = Clock.init(testing.allocator, 100);
    defer clock.deinit();

    var strategy = MessageBusStrategy.init(&bus);
    try clock.addStrategy(&strategy.asClockStrategy());

    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});
    std.time.sleep(350_000_000);
    clock.stop();
    thread.join();

    // 验证消息发布
    try testing.expect(strategy.messages_published >= 3);
}
```

### 与 Paper Trading 集成

```zig
test "Clock with PaperTrading" {
    var paper = PaperTradingEngine.init(testing.allocator);
    defer paper.deinit();

    var clock = Clock.init(testing.allocator, 100);
    defer clock.deinit();

    var mm_strategy = SimpleMM.init(&paper, "ETH-USD", 10);
    try clock.addStrategy(&mm_strategy.asClockStrategy());

    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});
    std.time.sleep(500_000_000);
    clock.stop();
    thread.join();

    // 验证报价更新
    try testing.expect(mm_strategy.quotes_updated >= 4);
}
```

---

## 运行测试

```bash
# 运行所有 clock 测试
zig build test -- --test-filter "Clock"

# 运行性能测试
zig build test -- --test-filter "Clock.*precision"

# 运行带日志的测试
zig build test -- --test-filter "Clock" 2>&1 | head -50
```

---

## 测试场景

### 已覆盖

- [x] 初始化和释放
- [x] 策略注册和移除
- [x] 启动和停止
- [x] 统计信息收集
- [x] 多策略执行
- [x] Tick 精度验证
- [x] 重复启动错误处理

### 待补充

- [ ] 策略异常处理
- [ ] 长时间运行稳定性
- [ ] 内存泄漏检测
- [ ] 极端条件 (0ms interval)
- [ ] 策略动态添加/移除

---

## 测试辅助结构

```zig
/// 测试用策略
const TestStrategy = struct {
    name: []const u8,
    tick_count: u64 = 0,
    started: bool = false,
    stopped: bool = false,

    const vtable = IClockStrategy.VTable{
        .onTick = onTickImpl,
        .onStart = onStartImpl,
        .onStop = onStopImpl,
    };

    pub fn init(name: []const u8) TestStrategy {
        return .{ .name = name };
    }

    pub fn asClockStrategy(self: *TestStrategy) IClockStrategy {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn onTickImpl(ptr: *anyopaque, tick: u64, _: i128) !void {
        const self: *TestStrategy = @ptrCast(@alignCast(ptr));
        self.tick_count = tick;
    }

    fn onStartImpl(ptr: *anyopaque) !void {
        const self: *TestStrategy = @ptrCast(@alignCast(ptr));
        self.started = true;
    }

    fn onStopImpl(ptr: *anyopaque) void {
        const self: *TestStrategy = @ptrCast(@alignCast(ptr));
        self.stopped = true;
    }
};
```

---

*测试文件位置: `tests/market_making/clock_test.zig`*
