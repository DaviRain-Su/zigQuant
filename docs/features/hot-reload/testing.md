# Hot Reload 测试文档

**版本**: v0.6.0
**状态**: 📋 待开始

---

## 测试覆盖

| 类别 | 测试数 | 覆盖率 |
|------|--------|--------|
| 配置加载 | - | - |
| 参数验证 | - | - |
| 安全调度 | - | - |
| 集成测试 | - | - |

---

## 单元测试

### 配置文件变化检测

```zig
test "detect config file changes" {
    const tmp_path = "test_config.json";

    // 创建初始配置
    const initial = \\{"strategy":"test","version":1,"params":{}}
    ;
    try std.fs.cwd().writeFile(tmp_path, initial);
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var manager = try HotReloadManager.init(
        testing.allocator,
        tmp_path,
        &mock_strategy,
        &mock_bus,
        .{},
    );
    defer manager.deinit();

    // 初始状态 - 无变化
    try testing.expect(!try manager.checkForChanges());

    // 等待一会确保时间戳不同
    std.time.sleep(1100 * std.time.ns_per_ms);

    // 修改文件
    const updated = \\{"strategy":"test","version":2,"params":{}}
    ;
    try std.fs.cwd().writeFile(tmp_path, updated);

    // 应检测到变化
    try testing.expect(try manager.checkForChanges());

    // 再次检查 - 不应有变化
    try testing.expect(!try manager.checkForChanges());
}
```

### 配置解析

```zig
test "parse strategy config" {
    const json =
        \\{
        \\  "strategy": "dual_ma",
        \\  "version": 1,
        \\  "params": {
        \\    "fast_period": {"value": 10, "min": 2, "max": 50},
        \\    "slow_period": {"value": 30, "min": 10, "max": 200}
        \\  }
        \\}
    ;

    const config = try parseConfig(testing.allocator, json);
    defer freeConfig(testing.allocator, config);

    try testing.expectEqualStrings("dual_ma", config.strategy);
    try testing.expectEqual(@as(u32, 1), config.version);
    try testing.expectEqual(@as(usize, 2), config.params.len);
}

test "parse config with risk settings" {
    const json =
        \\{
        \\  "strategy": "dual_ma",
        \\  "version": 1,
        \\  "params": {},
        \\  "risk": {
        \\    "stop_loss_pct": 0.02,
        \\    "take_profit_pct": 0.05,
        \\    "max_position_size": 1000
        \\  }
        \\}
    ;

    const config = try parseConfig(testing.allocator, json);
    defer freeConfig(testing.allocator, config);

    try testing.expect(config.risk != null);
    try testing.expectApproxEqAbs(@as(f64, 0.02), config.risk.?.stop_loss_pct, 0.001);
}
```

### 参数验证

```zig
test "param range validation - valid" {
    const params = [_]Param{
        .{ .name = "fast_period", .value = 10, .min = 2, .max = 50 },
        .{ .name = "slow_period", .value = 30, .min = 10, .max = 200 },
    };

    try validateParamRanges(&params);
}

test "param range validation - out of range" {
    const params = [_]Param{
        .{ .name = "fast_period", .value = 100, .min = 2, .max = 50 },  // 超出范围
    };

    try testing.expectError(error.ParamOutOfRange, validateParamRanges(&params));
}

test "dual ma strategy validation - valid" {
    const params = [_]Param{
        .{ .name = "fast_period", .value = 10, .min = 2, .max = 50 },
        .{ .name = "slow_period", .value = 30, .min = 10, .max = 200 },
    };

    var strategy = DualMAStrategy.init(.{});
    try strategy.validateParams(&params);
}

test "dual ma strategy validation - fast >= slow" {
    const params = [_]Param{
        .{ .name = "fast_period", .value = 50, .min = 2, .max = 50 },
        .{ .name = "slow_period", .value = 30, .min = 10, .max = 200 },
    };

    var strategy = DualMAStrategy.init(.{});
    try testing.expectError(error.InvalidParams, strategy.validateParams(&params));
}
```

### 安全调度

```zig
test "safe reload scheduler - request during tick" {
    var scheduler = SafeReloadScheduler.init();
    var strategy = MockStrategy.init();

    // 开始 tick
    scheduler.onTickStart();

    // 请求重载
    scheduler.requestReload(.{ .params = &[_]Param{} });

    // 验证重载被挂起
    try testing.expect(scheduler.pending_reload != null);

    // 策略参数未改变
    try testing.expectEqual(@as(u32, 10), strategy.fast_period);

    // 结束 tick
    try scheduler.onTickEnd(&strategy.asStrategy());

    // 验证重载已执行
    try testing.expect(scheduler.pending_reload == null);
}

test "safe reload scheduler - no pending reload" {
    var scheduler = SafeReloadScheduler.init();
    var strategy = MockStrategy.init();

    scheduler.onTickStart();
    try scheduler.onTickEnd(&strategy.asStrategy());

    // 无操作应成功
}
```

### 备份机制

```zig
test "config backup" {
    const tmp_path = "test_backup.json";
    const content = \\{"test": true}
    ;

    try std.fs.cwd().writeFile(tmp_path, content);
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var manager = try HotReloadManager.init(
        testing.allocator,
        tmp_path,
        &mock_strategy,
        &mock_bus,
        .{ .backup_on_reload = true },
    );
    defer manager.deinit();

    try manager.backupCurrentConfig();

    // 验证备份文件存在
    const backup_pattern = "test_backup.json.backup.*";
    var found_backup = false;

    var dir = try std.fs.cwd().openIterableDir(".", .{});
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (std.mem.startsWith(u8, entry.name, "test_backup.json.backup.")) {
            found_backup = true;
            try std.fs.cwd().deleteFile(entry.name);
            break;
        }
    }

    try testing.expect(found_backup);
}
```

### 策略参数更新

```zig
test "strategy updateParams" {
    var strategy = DualMAStrategy.init(.{ .fast = 10, .slow = 30 });

    const new_params = [_]Param{
        .{ .name = "fast_period", .value = 15 },
        .{ .name = "slow_period", .value = 50 },
    };

    try strategy.updateParams(&new_params);

    try testing.expectEqual(@as(u32, 15), strategy.fast_period);
    try testing.expectEqual(@as(u32, 50), strategy.slow_period);
}
```

---

## 集成测试

```zig
test "integration: full hot reload cycle" {
    const tmp_path = "integration_test.json";

    // 创建初始配置
    const initial =
        \\{"strategy":"dual_ma","version":1,"params":{
        \\  "fast_period":{"value":10,"min":2,"max":50},
        \\  "slow_period":{"value":30,"min":10,"max":200}
        \\}}
    ;
    try std.fs.cwd().writeFile(tmp_path, initial);
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var strategy = DualMAStrategy.init(.{ .fast = 10, .slow = 30 });
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var reloaded = false;
    bus.subscribe("system.config_reloaded", struct {
        fn callback() void {
            reloaded = true;
        }
    }.callback);

    var manager = try HotReloadManager.init(
        testing.allocator,
        tmp_path,
        &strategy.asStrategy(),
        &bus,
        .{ .watch_interval_ms = 100 },
    );
    defer manager.deinit();

    try manager.start();

    // 等待启动
    std.time.sleep(200 * std.time.ns_per_ms);

    // 修改配置
    const updated =
        \\{"strategy":"dual_ma","version":2,"params":{
        \\  "fast_period":{"value":15,"min":2,"max":50},
        \\  "slow_period":{"value":45,"min":10,"max":200}
        \\}}
    ;
    try std.fs.cwd().writeFile(tmp_path, updated);

    // 等待重载
    std.time.sleep(500 * std.time.ns_per_ms);

    manager.stop();

    // 验证参数已更新
    try testing.expectEqual(@as(u32, 15), strategy.fast_period);
    try testing.expectEqual(@as(u32, 45), strategy.slow_period);
    try testing.expect(reloaded);
}
```

---

## 性能基准

```zig
test "benchmark: config parsing" {
    const json =
        \\{"strategy":"dual_ma","version":1,"params":{
        \\  "fast_period":{"value":10,"min":2,"max":50},
        \\  "slow_period":{"value":30,"min":10,"max":200},
        \\  "position_size":{"value":0.1,"min":0.01,"max":1.0}
        \\}}
    ;

    var timer = std.time.Timer{};
    timer.reset();

    const iterations = 10000;
    for (0..iterations) |_| {
        const config = try parseConfig(testing.allocator, json);
        freeConfig(testing.allocator, config);
    }

    const elapsed_ns = timer.read();
    const avg_us = elapsed_ns / iterations / 1000;

    std.debug.print("Average parse time: {d}us\n", .{avg_us});

    // 目标: < 100us per parse
    try testing.expect(avg_us < 100);
}

test "benchmark: param validation" {
    const params = [_]Param{
        .{ .name = "fast_period", .value = 10, .min = 2, .max = 50 },
        .{ .name = "slow_period", .value = 30, .min = 10, .max = 200 },
        .{ .name = "position_size", .value = 0.1, .min = 0.01, .max = 1.0 },
    };

    var timer = std.time.Timer{};
    timer.reset();

    const iterations = 100000;
    for (0..iterations) |_| {
        try validateParamRanges(&params);
    }

    const elapsed_ns = timer.read();
    const avg_ns = elapsed_ns / iterations;

    std.debug.print("Average validation time: {d}ns\n", .{avg_ns});

    // 目标: < 1000ns per validation
    try testing.expect(avg_ns < 1000);
}
```

---

## 运行测试

```bash
# 运行所有热重载测试
zig build test-hot-reload

# 运行集成测试
zig build test-hot-reload-integration

# 运行性能基准
zig build bench-hot-reload
```

---

*Last updated: 2025-12-27*
