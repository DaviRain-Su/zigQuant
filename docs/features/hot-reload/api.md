# Hot Reload API 参考

**模块**: `zigQuant.trading.hot_reload`
**版本**: v0.6.0
**状态**: 📋 待开始

---

## HotReloadManager

热重载管理器，监控配置文件变化并触发策略参数更新。

### 类型定义

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
};
```

### Config

```zig
pub const Config = struct {
    /// 监控间隔 (毫秒)
    watch_interval_ms: u32 = 1000,

    /// 重载前验证参数
    validate_before_reload: bool = true,

    /// 只在 tick 间隙重载
    reload_on_tick: bool = true,

    /// 重载前备份配置
    backup_on_reload: bool = true,
};
```

### 方法

#### init

```zig
pub fn init(
    allocator: Allocator,
    config_path: []const u8,
    strategy: *IStrategy,
    message_bus: *MessageBus,
    config: Config,
) !HotReloadManager
```

初始化热重载管理器。

**参数**:
- `allocator`: 内存分配器
- `config_path`: 配置文件路径
- `strategy`: 策略接口引用
- `message_bus`: 消息总线引用
- `config`: 配置选项

**返回**: 初始化的管理器实例

**错误**:
- `FileNotFound`: 配置文件不存在

---

#### deinit

```zig
pub fn deinit(self: *HotReloadManager) void
```

停止监控并释放资源。

---

#### start

```zig
pub fn start(self: *HotReloadManager) !void
```

启动配置文件监控线程。

---

#### stop

```zig
pub fn stop(self: *HotReloadManager) void
```

停止监控线程。

---

#### reloadNow

```zig
pub fn reloadNow(self: *HotReloadManager) !void
```

立即触发重载 (不等待文件变化)。

**错误**:
- `InvalidConfig`: 配置格式错误
- `ParamOutOfRange`: 参数超出范围
- `InvalidParams`: 参数逻辑错误 (如 fast > slow)

---

#### isWatching

```zig
pub fn isWatching(self: *HotReloadManager) bool
```

检查是否正在监控。

---

## SafeReloadScheduler

安全重载调度器，确保在安全时机执行参数更新。

### 类型定义

```zig
pub const SafeReloadScheduler = struct {
    pending_reload: ?ReloadRequest,
    in_tick: std.atomic.Value(bool),
};

pub const ReloadRequest = struct {
    config: StrategyConfig,
    requested_at: i64,
};
```

### 方法

#### requestReload

```zig
pub fn requestReload(self: *SafeReloadScheduler, config: StrategyConfig) void
```

请求重载 (将在安全时机执行)。

---

#### onTickStart

```zig
pub fn onTickStart(self: *SafeReloadScheduler) void
```

在 tick 开始时调用，标记进入 tick 处理。

---

#### onTickEnd

```zig
pub fn onTickEnd(self: *SafeReloadScheduler, strategy: *IStrategy) !void
```

在 tick 结束时调用，执行待处理的重载。

---

## StrategyConfig

策略配置结构。

```zig
pub const StrategyConfig = struct {
    strategy: []const u8,
    version: u32,
    params: []Param,
    risk: ?RiskConfig,
};

pub const Param = struct {
    name: []const u8,
    value: f64,
    min: f64,
    max: f64,
    description: ?[]const u8,
};

pub const RiskConfig = struct {
    stop_loss_pct: f64,
    take_profit_pct: f64,
    max_position_size: f64,
};
```

---

## IStrategy 扩展接口

策略需要实现这些方法以支持热重载。

### updateParams

```zig
pub fn updateParams(ctx: *anyopaque, params: []const Param) anyerror!void
```

更新策略参数。

**参数**:
- `params`: 新参数列表

**职责**:
- 解析参数值
- 更新内部状态
- 重新初始化指标 (如需要)

---

### validateParams

```zig
pub fn validateParams(ctx: *anyopaque, params: []const Param) anyerror!void
```

验证参数有效性。

**参数**:
- `params`: 待验证的参数列表

**错误**:
- `InvalidParams`: 参数逻辑错误

---

### getParams

```zig
pub fn getParams(ctx: *anyopaque) []const Param
```

获取当前参数列表。

---

## 事件

### config_reloaded

配置重载成功时发布。

```zig
.config_reloaded = .{
    .config_path = "path/to/config.json",
    .timestamp = 1704067200000000000,
}
```

---

*Last updated: 2025-12-27*
