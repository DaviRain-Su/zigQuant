# Story 032: 策略热重载

**版本**: v0.6.0
**状态**: 规划中
**优先级**: P2
**预计时间**: 2-3 天
**前置条件**: Story 031 (Paper Trading)

---

## 目标

支持运行时策略参数更新，无需重启交易引擎即可调整策略行为，提高策略调优效率和系统可用性。

---

## 核心设计

### 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    HotReloadManager                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │  ConfigWatcher  │    │  ParamValidator │                │
│  │  (文件监控)     │    │  (参数验证)     │                │
│  └────────┬────────┘    └────────┬────────┘                │
│           │                      │                          │
│           ↓                      ↓                          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  ReloadScheduler                      │  │
│  │            (安全时机调度重载)                         │  │
│  └──────────────────────────────────────────────────────┘  │
│           │                                                 │
│           ↓                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │    Strategy     │    │   MessageBus    │                │
│  │  (参数更新)     │    │  (通知事件)     │                │
│  └─────────────────┘    └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### 核心接口

```zig
pub const HotReloadManager = struct {
    allocator: Allocator,
    config: Config,
    config_path: []const u8,
    last_modified: i64,
    strategy: *IStrategy,
    message_bus: *MessageBus,
    watcher_thread: ?std.Thread,
    running: std.atomic.Value(bool),

    pub const Config = struct {
        watch_interval_ms: u32 = 1000,
        validate_before_reload: bool = true,
        reload_on_tick: bool = true,  // 只在 tick 间隙重载
        backup_on_reload: bool = true,
    };

    /// 初始化
    pub fn init(
        allocator: Allocator,
        config_path: []const u8,
        strategy: *IStrategy,
        message_bus: *MessageBus,
        config: Config,
    ) !HotReloadManager {
        const stat = try std.fs.cwd().statFile(config_path);

        return .{
            .allocator = allocator,
            .config = config,
            .config_path = config_path,
            .last_modified = stat.mtime,
            .strategy = strategy,
            .message_bus = message_bus,
            .watcher_thread = null,
            .running = std.atomic.Value(bool).init(false),
        };
    }

    /// 启动监控
    pub fn start(self: *HotReloadManager) !void {
        self.running.store(true, .seq_cst);
        self.watcher_thread = try std.Thread.spawn(.{}, watchLoop, .{self});
    }

    /// 停止监控
    pub fn stop(self: *HotReloadManager) void {
        self.running.store(false, .seq_cst);
        if (self.watcher_thread) |thread| {
            thread.join();
        }
    }

    /// 监控循环
    fn watchLoop(self: *HotReloadManager) void {
        while (self.running.load(.seq_cst)) {
            std.time.sleep(self.config.watch_interval_ms * std.time.ns_per_ms);

            if (self.checkForChanges()) |_| {
                self.triggerReload() catch |err| {
                    log.err("Hot reload failed: {}", .{err});
                };
            } else |_| {}
        }
    }

    /// 检查配置文件变化
    fn checkForChanges(self: *HotReloadManager) !bool {
        const stat = try std.fs.cwd().statFile(self.config_path);

        if (stat.mtime > self.last_modified) {
            self.last_modified = stat.mtime;
            return true;
        }

        return false;
    }

    /// 触发重载
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
        try self.strategy.vtable.updateParams(self.strategy.ptr, new_config.params);

        // 5. 发布重载事件
        self.message_bus.publish("system.config_reloaded", .{
            .config_reloaded = .{
                .config_path = self.config_path,
                .timestamp = std.time.milliTimestamp() * 1_000_000,
            },
        });

        log.info("Configuration reloaded successfully", .{});
    }

    /// 加载配置
    fn loadConfig(self: *HotReloadManager) !StrategyConfig {
        const file = try std.fs.cwd().openFile(self.config_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        return try std.json.parseFromSlice(StrategyConfig, self.allocator, content, .{});
    }

    /// 验证参数
    fn validateParams(self: *HotReloadManager, config: StrategyConfig) !void {
        // 验证参数范围
        for (config.params) |param| {
            if (param.value < param.min or param.value > param.max) {
                return error.ParamOutOfRange;
            }
        }

        // 策略特定验证
        try self.strategy.vtable.validateParams(self.strategy.ptr, config.params);
    }

    /// 备份当前配置
    fn backupCurrentConfig(self: *HotReloadManager) !void {
        const backup_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}.backup.{d}",
            .{ self.config_path, std.time.milliTimestamp() },
        );
        defer self.allocator.free(backup_path);

        try std.fs.cwd().copyFile(self.config_path, std.fs.cwd(), backup_path, .{});
    }

    /// 手动重载
    pub fn reloadNow(self: *HotReloadManager) !void {
        try self.triggerReload();
    }
};
```

---

## IStrategy 接口扩展

```zig
// 为 IStrategy 添加热重载支持
pub const IStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        // 现有方法...
        onData: *const fn (*anyopaque, MarketData) Signal,

        // 热重载支持
        updateParams: *const fn (*anyopaque, []const Param) anyerror!void,
        validateParams: *const fn (*anyopaque, []const Param) anyerror!void,
        getParams: *const fn (*anyopaque) []const Param,
    };
};

// 策略实现示例
pub const DualMAStrategy = struct {
    fast_period: u32,
    slow_period: u32,
    // ...

    pub fn updateParams(ctx: *anyopaque, params: []const Param) !void {
        const self = @ptrCast(*DualMAStrategy, ctx);

        for (params) |param| {
            if (std.mem.eql(u8, param.name, "fast_period")) {
                self.fast_period = @intFromFloat(param.value);
                // 重新初始化指标
                self.reinitIndicators();
            } else if (std.mem.eql(u8, param.name, "slow_period")) {
                self.slow_period = @intFromFloat(param.value);
                self.reinitIndicators();
            }
        }
    }

    pub fn validateParams(ctx: *anyopaque, params: []const Param) !void {
        var fast: ?u32 = null;
        var slow: ?u32 = null;

        for (params) |param| {
            if (std.mem.eql(u8, param.name, "fast_period")) {
                fast = @intFromFloat(param.value);
            } else if (std.mem.eql(u8, param.name, "slow_period")) {
                slow = @intFromFloat(param.value);
            }
        }

        // 验证 fast < slow
        if (fast != null and slow != null and fast.? >= slow.?) {
            return error.InvalidParams;
        }
    }
};
```

---

## 配置文件格式

```json
{
  "strategy": "dual_ma",
  "version": 2,
  "params": {
    "fast_period": {
      "value": 10,
      "min": 2,
      "max": 50,
      "description": "Fast MA period"
    },
    "slow_period": {
      "value": 30,
      "min": 10,
      "max": 200,
      "description": "Slow MA period"
    },
    "position_size": {
      "value": 0.1,
      "min": 0.01,
      "max": 1.0,
      "description": "Position size as fraction of balance"
    }
  },
  "risk": {
    "stop_loss_pct": 0.02,
    "take_profit_pct": 0.05,
    "max_position_size": 1000
  }
}
```

---

## 安全重载机制

```zig
pub const SafeReloadScheduler = struct {
    pending_reload: ?ReloadRequest,
    in_tick: std.atomic.Value(bool),

    pub const ReloadRequest = struct {
        config: StrategyConfig,
        requested_at: i64,
    };

    /// 请求重载 (在安全时机执行)
    pub fn requestReload(self: *SafeReloadScheduler, config: StrategyConfig) void {
        self.pending_reload = .{
            .config = config,
            .requested_at = std.time.milliTimestamp(),
        };
    }

    /// 在 tick 开始时调用
    pub fn onTickStart(self: *SafeReloadScheduler) void {
        self.in_tick.store(true, .seq_cst);
    }

    /// 在 tick 结束时调用 - 检查并执行待处理的重载
    pub fn onTickEnd(self: *SafeReloadScheduler, strategy: *IStrategy) !void {
        self.in_tick.store(false, .seq_cst);

        if (self.pending_reload) |reload| {
            try strategy.vtable.updateParams(strategy.ptr, reload.config.params);
            self.pending_reload = null;

            log.info("Parameters updated between ticks", .{});
        }
    }
};
```

---

## CLI 集成

```bash
# 启动时启用热重载
zigquant run-strategy --strategy dual_ma --paper --hot-reload

# 指定配置文件
zigquant run-strategy --strategy dual_ma --paper --config strategy.json --hot-reload

# 手动触发重载 (通过信号)
kill -USR1 <pid>
```

---

## 测试计划

### 单元测试

```zig
test "config change detection" {
    const tmp_file = try createTempConfig();
    defer std.fs.cwd().deleteFile(tmp_file);

    var manager = try HotReloadManager.init(allocator, tmp_file, &strategy, &bus, .{});

    // 修改文件
    try modifyConfig(tmp_file);

    // 检查变化
    try testing.expect(try manager.checkForChanges());
}

test "param validation" {
    const invalid_config = StrategyConfig{
        .params = &[_]Param{
            .{ .name = "fast_period", .value = 50 },
            .{ .name = "slow_period", .value = 30 },  // slow < fast!
        },
    };

    try testing.expectError(error.InvalidParams, manager.validateParams(invalid_config));
}
```

---

## 成功指标

| 指标 | 目标 | 说明 |
|------|------|------|
| 重载延迟 | < 100ms | 检测到变化到应用 |
| 验证完整性 | 100% | 无效参数被拒绝 |
| 安全性 | 100% | 不在 tick 中间重载 |
| 回滚能力 | 支持 | 保留备份 |

---

## 文件结构

```
src/trading/
├── hot_reload.zig              # HotReloadManager
├── config_watcher.zig          # 文件监控
├── param_validator.zig         # 参数验证
└── tests/
    └── hot_reload_test.zig     # 测试
```

---

**Story**: 032
**状态**: 规划中
**创建时间**: 2025-12-27
