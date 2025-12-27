# Hot Reload 实现细节

**版本**: v0.6.0
**状态**: 📋 待开始

---

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                    HotReloadManager                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   WatcherThread                      │   │
│  │              (后台监控线程)                          │   │
│  └────────────────────────┬────────────────────────────┘   │
│                           │                                  │
│                           ↓ 检测到变化                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    loadConfig()                      │   │
│  │              (读取 JSON 配置)                        │   │
│  └────────────────────────┬────────────────────────────┘   │
│                           │                                  │
│                           ↓                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  validateParams()                    │   │
│  │              (验证参数范围和逻辑)                    │   │
│  └────────────────────────┬────────────────────────────┘   │
│                           │                                  │
│                           ↓                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │               SafeReloadScheduler                    │   │
│  │            (等待 tick 结束后执行)                    │   │
│  └────────────────────────┬────────────────────────────┘   │
│                           │                                  │
│                           ↓                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              strategy.updateParams()                 │   │
│  │              (应用新参数)                            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 文件监控

### 监控循环

```zig
fn watchLoop(self: *HotReloadManager) void {
    while (self.running.load(.seq_cst)) {
        // 等待监控间隔
        std.time.sleep(self.config.watch_interval_ms * std.time.ns_per_ms);

        // 检查文件变化
        const changed = self.checkForChanges() catch |err| {
            log.warn("Failed to check config: {}", .{err});
            continue;
        };

        if (changed) {
            self.triggerReload() catch |err| {
                log.err("Hot reload failed: {}", .{err});
                self.notifyReloadFailed(err);
            };
        }
    }
}
```

### 变化检测

```zig
fn checkForChanges(self: *HotReloadManager) !bool {
    const stat = try std.fs.cwd().statFile(self.config_path);

    if (stat.mtime > self.last_modified) {
        self.last_modified = stat.mtime;
        return true;
    }

    return false;
}
```

---

## 配置加载

### JSON 解析

```zig
fn loadConfig(self: *HotReloadManager) !StrategyConfig {
    const file = try std.fs.cwd().openFile(self.config_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
    defer self.allocator.free(content);

    const parsed = try std.json.parseFromSlice(
        StrategyConfigJson,
        self.allocator,
        content,
        .{},
    );
    defer parsed.deinit();

    return try self.convertToStrategyConfig(parsed.value);
}

fn convertToStrategyConfig(self: *HotReloadManager, json: StrategyConfigJson) !StrategyConfig {
    var params = std.ArrayList(Param).init(self.allocator);

    var it = json.params.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        const param_json = entry.value_ptr.*;

        try params.append(.{
            .name = try self.allocator.dupe(u8, name),
            .value = param_json.value,
            .min = param_json.min,
            .max = param_json.max,
            .description = if (param_json.description) |d|
                try self.allocator.dupe(u8, d)
            else
                null,
        });
    }

    return .{
        .strategy = try self.allocator.dupe(u8, json.strategy),
        .version = json.version,
        .params = params.toOwnedSlice(),
        .risk = json.risk,
    };
}
```

---

## 参数验证

### 范围验证

```zig
fn validateParams(self: *HotReloadManager, config: StrategyConfig) !void {
    // 1. 范围验证
    for (config.params) |param| {
        if (param.value < param.min or param.value > param.max) {
            log.err("Param '{s}' out of range: {d} not in [{d}, {d}]", .{
                param.name,
                param.value,
                param.min,
                param.max,
            });
            return error.ParamOutOfRange;
        }
    }

    // 2. 策略特定验证
    try self.strategy.vtable.validateParams(self.strategy.ptr, config.params);
}
```

### 策略特定验证示例

```zig
// DualMAStrategy 的验证实现
pub fn validateParams(ctx: *anyopaque, params: []const Param) !void {
    var fast: ?f64 = null;
    var slow: ?f64 = null;

    for (params) |param| {
        if (std.mem.eql(u8, param.name, "fast_period")) {
            fast = param.value;
        } else if (std.mem.eql(u8, param.name, "slow_period")) {
            slow = param.value;
        }
    }

    // 验证 fast < slow
    if (fast != null and slow != null) {
        if (fast.? >= slow.?) {
            log.err("fast_period ({d}) must be less than slow_period ({d})", .{
                fast.?,
                slow.?,
            });
            return error.InvalidParams;
        }
    }
}
```

---

## 安全重载调度

### 调度器实现

```zig
pub const SafeReloadScheduler = struct {
    pending_reload: ?ReloadRequest,
    in_tick: std.atomic.Value(bool),
    mutex: std.Thread.Mutex,

    pub fn init() SafeReloadScheduler {
        return .{
            .pending_reload = null,
            .in_tick = std.atomic.Value(bool).init(false),
            .mutex = .{},
        };
    }

    /// 请求重载 (线程安全)
    pub fn requestReload(self: *SafeReloadScheduler, config: StrategyConfig) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.pending_reload = .{
            .config = config,
            .requested_at = std.time.milliTimestamp(),
        };

        log.info("Reload requested, waiting for safe moment...", .{});
    }

    /// 在 tick 开始时调用
    pub fn onTickStart(self: *SafeReloadScheduler) void {
        self.in_tick.store(true, .seq_cst);
    }

    /// 在 tick 结束时调用 - 检查并执行待处理的重载
    pub fn onTickEnd(self: *SafeReloadScheduler, strategy: *IStrategy) !void {
        self.in_tick.store(false, .seq_cst);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.pending_reload) |reload| {
            log.info("Executing pending reload...", .{});

            try strategy.vtable.updateParams(strategy.ptr, reload.config.params);

            self.pending_reload = null;
            log.info("Parameters updated successfully", .{});
        }
    }
};
```

### 与交易引擎集成

```zig
// 在 TradingEngine 中
pub fn runTick(self: *TradingEngine) void {
    // 标记 tick 开始
    self.reload_scheduler.onTickStart();

    // 处理市场数据和策略逻辑
    self.processMarketData();
    self.executeStrategy();

    // 标记 tick 结束，执行待处理的重载
    self.reload_scheduler.onTickEnd(self.strategy) catch |err| {
        log.err("Reload failed: {}", .{err});
    };
}
```

---

## 备份机制

```zig
fn backupCurrentConfig(self: *HotReloadManager) !void {
    const backup_path = try std.fmt.allocPrint(
        self.allocator,
        "{s}.backup.{d}",
        .{ self.config_path, std.time.milliTimestamp() },
    );
    defer self.allocator.free(backup_path);

    try std.fs.cwd().copyFile(self.config_path, std.fs.cwd(), backup_path, .{});

    log.info("Config backed up to: {s}", .{backup_path});
}
```

---

## 重载流程

```zig
fn triggerReload(self: *HotReloadManager) !void {
    log.info("Configuration change detected, reloading...", .{});

    // 1. 读取新配置
    const new_config = try self.loadConfig();

    // 2. 验证参数
    if (self.config.validate_before_reload) {
        try self.validateParams(new_config);
    }

    // 3. 备份当前配置
    if (self.config.backup_on_reload) {
        try self.backupCurrentConfig();
    }

    // 4. 应用新参数
    if (self.config.reload_on_tick) {
        // 使用安全调度器
        self.reload_scheduler.requestReload(new_config);
    } else {
        // 直接更新
        try self.strategy.vtable.updateParams(self.strategy.ptr, new_config.params);
    }

    // 5. 发布重载事件
    self.message_bus.publish("system.config_reloaded", .{
        .config_reloaded = .{
            .config_path = self.config_path,
            .timestamp = std.time.milliTimestamp() * 1_000_000,
        },
    });

    log.info("Configuration reloaded successfully", .{});
}
```

---

## 策略参数更新示例

```zig
// DualMAStrategy 的 updateParams 实现
pub fn updateParams(ctx: *anyopaque, params: []const Param) !void {
    const self = @ptrCast(*DualMAStrategy, @alignCast(@alignOf(DualMAStrategy), ctx));

    for (params) |param| {
        if (std.mem.eql(u8, param.name, "fast_period")) {
            const old = self.fast_period;
            self.fast_period = @intFromFloat(param.value);
            log.info("fast_period: {d} -> {d}", .{ old, self.fast_period });
        } else if (std.mem.eql(u8, param.name, "slow_period")) {
            const old = self.slow_period;
            self.slow_period = @intFromFloat(param.value);
            log.info("slow_period: {d} -> {d}", .{ old, self.slow_period });
        } else if (std.mem.eql(u8, param.name, "position_size")) {
            self.position_size = Decimal.fromFloat(param.value);
        }
    }

    // 重新初始化指标
    self.reinitIndicators();
}

fn reinitIndicators(self: *DualMAStrategy) void {
    // 清除旧的 MA 缓存
    self.fast_ma.reset();
    self.slow_ma.reset();

    // 用新周期重新初始化
    self.fast_ma = SMA.init(self.fast_period);
    self.slow_ma = SMA.init(self.slow_period);
}
```

---

## 文件结构

```
src/trading/
├── hot_reload.zig              # HotReloadManager
├── config_watcher.zig          # 文件监控
├── param_validator.zig         # 参数验证
├── safe_reload_scheduler.zig   # 安全调度
└── tests/
    └── hot_reload_test.zig     # 测试
```

---

*Last updated: 2025-12-27*
