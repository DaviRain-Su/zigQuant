//! HotReloadManager - 策略热重载管理器
//!
//! 支持运行时策略参数更新，无需重启交易引擎即可调整策略行为。
//!
//! ## 功能
//! - 监控配置文件变化
//! - 验证参数有效性
//! - 安全时机执行重载 (tick 间隙)
//! - 自动备份配置
//! - 发布重载事件
//!
//! ## 使用示例
//! ```zig
//! var manager = try HotReloadManager.init(allocator, "strategy.json", &strategy, &bus, .{});
//! defer manager.deinit();
//!
//! try manager.start();
//! // ... 运行交易引擎 ...
//! manager.stop();
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Timestamp = @import("../core/time.zig").Timestamp;
const MessageBus = @import("../core/message_bus.zig").MessageBus;
const Decimal = @import("../core/decimal.zig").Decimal;

// ============================================================================
// 配置参数类型
// ============================================================================

/// 配置参数 (带范围验证)
pub const ConfigParam = struct {
    name: []const u8,
    value: f64,
    min: f64,
    max: f64,
    description: []const u8,

    /// 验证参数值是否在范围内
    pub fn isValid(self: ConfigParam) bool {
        return self.value >= self.min and self.value <= self.max;
    }

    /// 验证并返回错误
    pub fn validate(self: ConfigParam) !void {
        if (self.value < self.min) {
            return error.ParamBelowMin;
        }
        if (self.value > self.max) {
            return error.ParamAboveMax;
        }
    }
};

/// 风险配置
pub const RiskConfig = struct {
    stop_loss_pct: f64 = 0.02,
    take_profit_pct: f64 = 0.05,
    max_position_size: f64 = 1000,

    /// 验证风险配置
    pub fn validate(self: RiskConfig) !void {
        if (self.stop_loss_pct <= 0 or self.stop_loss_pct > 1) {
            return error.InvalidStopLoss;
        }
        if (self.take_profit_pct <= 0) {
            return error.InvalidTakeProfit;
        }
        if (self.max_position_size <= 0) {
            return error.InvalidMaxPosition;
        }
    }
};

/// 热重载配置文件结构
pub const HotReloadConfig = struct {
    strategy: []const u8,
    version: u32,
    params: std.StringHashMap(ConfigParam),
    risk: RiskConfig,

    allocator: Allocator,

    const Self = @This();

    /// 初始化
    pub fn init(allocator: Allocator) Self {
        return .{
            .strategy = "",
            .version = 1,
            .params = std.StringHashMap(ConfigParam).init(allocator),
            .risk = .{},
            .allocator = allocator,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        // 释放参数名称字符串
        var iter = self.params.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.description);
        }
        self.params.deinit();

        if (self.strategy.len > 0) {
            self.allocator.free(self.strategy);
        }
    }

    /// 获取参数
    pub fn getParam(self: *const Self, name: []const u8) ?ConfigParam {
        return self.params.get(name);
    }

    /// 获取参数值
    pub fn getParamValue(self: *const Self, name: []const u8) ?f64 {
        if (self.params.get(name)) |param| {
            return param.value;
        }
        return null;
    }

    /// 验证所有参数
    pub fn validate(self: *const Self) !void {
        var iter = self.params.iterator();
        while (iter.next()) |entry| {
            try entry.value_ptr.validate();
        }
        try self.risk.validate();
    }

    /// 获取参数数量
    pub fn paramCount(self: *const Self) usize {
        return self.params.count();
    }
};

// ============================================================================
// IHotReloadable 接口
// ============================================================================

/// 热重载接口 - 策略可选实现
pub const IHotReloadable = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// 更新参数
        updateParams: *const fn (ptr: *anyopaque, params: *const HotReloadConfig) anyerror!void,
        /// 验证参数
        validateParams: *const fn (ptr: *anyopaque, params: *const HotReloadConfig) anyerror!void,
        /// 获取当前参数
        getCurrentParams: *const fn (ptr: *anyopaque, allocator: Allocator) anyerror!HotReloadConfig,
    };

    /// 更新参数
    pub fn updateParams(self: IHotReloadable, params: *const HotReloadConfig) !void {
        return self.vtable.updateParams(self.ptr, params);
    }

    /// 验证参数
    pub fn validateParams(self: IHotReloadable, params: *const HotReloadConfig) !void {
        return self.vtable.validateParams(self.ptr, params);
    }

    /// 获取当前参数
    pub fn getCurrentParams(self: IHotReloadable, allocator: Allocator) !HotReloadConfig {
        return self.vtable.getCurrentParams(self.ptr, allocator);
    }
};

// ============================================================================
// ParamValidator - 参数验证器
// ============================================================================

/// 参数验证器
pub const ParamValidator = struct {
    allocator: Allocator,

    const Self = @This();

    /// 初始化
    pub fn init(allocator: Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// 验证配置参数
    pub fn validateConfig(self: *Self, config: *const HotReloadConfig) !void {
        _ = self;
        try config.validate();
    }

    /// 验证单个参数范围
    pub fn validateParamRange(self: *Self, param: ConfigParam) !void {
        _ = self;
        try param.validate();
    }

    /// 比较两个配置的差异
    pub fn compareConfigs(
        self: *Self,
        old_config: *const HotReloadConfig,
        new_config: *const HotReloadConfig,
    ) ![]const []const u8 {
        var changed = std.ArrayList([]const u8).init(self.allocator);
        errdefer changed.deinit();

        // 比较参数
        var iter = new_config.params.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const new_value = entry.value_ptr.value;

            if (old_config.params.get(name)) |old_param| {
                if (old_param.value != new_value) {
                    const name_copy = try self.allocator.dupe(u8, name);
                    try changed.append(name_copy);
                }
            } else {
                // 新参数
                const name_copy = try self.allocator.dupe(u8, name);
                try changed.append(name_copy);
            }
        }

        return changed.toOwnedSlice();
    }
};

// ============================================================================
// SafeReloadScheduler - 安全重载调度器
// ============================================================================

/// 重载请求
pub const ReloadRequest = struct {
    config: HotReloadConfig,
    requested_at: i64,
};

/// 安全重载调度器 - 确保在 tick 间隙执行重载
pub const SafeReloadScheduler = struct {
    pending_reload: ?ReloadRequest,
    in_tick: std.atomic.Value(bool),
    reload_count: u64,
    last_reload_time: ?i64,

    const Self = @This();

    /// 初始化
    pub fn init() Self {
        return .{
            .pending_reload = null,
            .in_tick = std.atomic.Value(bool).init(false),
            .reload_count = 0,
            .last_reload_time = null,
        };
    }

    /// 请求重载 (将在安全时机执行)
    pub fn requestReload(self: *Self, config: HotReloadConfig) void {
        self.pending_reload = .{
            .config = config,
            .requested_at = std.time.milliTimestamp(),
        };
    }

    /// 标记 tick 开始
    pub fn onTickStart(self: *Self) void {
        self.in_tick.store(true, .seq_cst);
    }

    /// 标记 tick 结束并检查待处理的重载
    /// 返回是否有重载被执行
    pub fn onTickEnd(self: *Self, reloadable: ?IHotReloadable) !bool {
        self.in_tick.store(false, .seq_cst);

        if (self.pending_reload) |reload| {
            if (reloadable) |r| {
                try r.updateParams(&reload.config);
                self.reload_count += 1;
                self.last_reload_time = std.time.milliTimestamp();
                self.pending_reload = null;
                return true;
            }
        }

        return false;
    }

    /// 检查是否在 tick 中
    pub fn isInTick(self: *const Self) bool {
        return self.in_tick.load(.seq_cst);
    }

    /// 检查是否有待处理的重载
    pub fn hasPendingReload(self: *const Self) bool {
        return self.pending_reload != null;
    }

    /// 取消待处理的重载
    pub fn cancelPendingReload(self: *Self) void {
        self.pending_reload = null;
    }

    /// 获取重载统计
    pub fn getStats(self: *const Self) struct { count: u64, last_time: ?i64 } {
        return .{
            .count = self.reload_count,
            .last_time = self.last_reload_time,
        };
    }
};

// ============================================================================
// HotReloadManager - 热重载管理器
// ============================================================================

/// 热重载管理器配置
pub const HotReloadManagerConfig = struct {
    /// 监控间隔 (毫秒)
    watch_interval_ms: u32 = 1000,
    /// 重载前验证参数
    validate_before_reload: bool = true,
    /// 只在 tick 间隙重载
    reload_on_tick: bool = true,
    /// 重载前备份配置
    backup_on_reload: bool = true,
    /// 最大备份数量
    max_backups: u32 = 10,
};

/// 热重载管理器
pub const HotReloadManager = struct {
    allocator: Allocator,
    config: HotReloadManagerConfig,
    config_path: []const u8,
    last_modified: i128,
    reloadable: ?IHotReloadable,
    message_bus: ?*MessageBus,
    validator: ParamValidator,
    scheduler: SafeReloadScheduler,

    // 线程控制
    watcher_thread: ?std.Thread,
    running: std.atomic.Value(bool),

    // 统计
    check_count: u64,
    reload_count: u64,
    error_count: u64,

    const Self = @This();

    /// 初始化
    pub fn init(
        allocator: Allocator,
        config_path: []const u8,
        reloadable: ?IHotReloadable,
        message_bus: ?*MessageBus,
        config: HotReloadManagerConfig,
    ) !Self {
        // 获取文件修改时间
        const file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
            // 如果文件不存在，使用当前时间
            if (err == error.FileNotFound) {
                return Self{
                    .allocator = allocator,
                    .config = config,
                    .config_path = try allocator.dupe(u8, config_path),
                    .last_modified = std.time.nanoTimestamp(),
                    .reloadable = reloadable,
                    .message_bus = message_bus,
                    .validator = ParamValidator.init(allocator),
                    .scheduler = SafeReloadScheduler.init(),
                    .watcher_thread = null,
                    .running = std.atomic.Value(bool).init(false),
                    .check_count = 0,
                    .reload_count = 0,
                    .error_count = 0,
                };
            }
            return err;
        };
        defer file.close();

        const stat = try file.stat();

        return Self{
            .allocator = allocator,
            .config = config,
            .config_path = try allocator.dupe(u8, config_path),
            .last_modified = stat.mtime,
            .reloadable = reloadable,
            .message_bus = message_bus,
            .validator = ParamValidator.init(allocator),
            .scheduler = SafeReloadScheduler.init(),
            .watcher_thread = null,
            .running = std.atomic.Value(bool).init(false),
            .check_count = 0,
            .reload_count = 0,
            .error_count = 0,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        self.stop();
        self.allocator.free(self.config_path);
    }

    /// 启动监控
    pub fn start(self: *Self) !void {
        if (self.running.load(.seq_cst)) {
            return; // 已经在运行
        }

        self.running.store(true, .seq_cst);
        self.watcher_thread = try std.Thread.spawn(.{}, watchLoop, .{self});
    }

    /// 停止监控
    pub fn stop(self: *Self) void {
        if (!self.running.load(.seq_cst)) {
            return; // 没有在运行
        }

        self.running.store(false, .seq_cst);

        if (self.watcher_thread) |thread| {
            thread.join();
            self.watcher_thread = null;
        }
    }

    /// 检查是否正在运行
    pub fn isRunning(self: *const Self) bool {
        return self.running.load(.seq_cst);
    }

    /// 手动触发重载
    pub fn reloadNow(self: *Self) !void {
        try self.triggerReload();
    }

    /// 获取调度器引用 (用于 tick 回调)
    pub fn getScheduler(self: *Self) *SafeReloadScheduler {
        return &self.scheduler;
    }

    /// 获取统计信息
    pub fn getStats(self: *const Self) struct {
        check_count: u64,
        reload_count: u64,
        error_count: u64,
        scheduler_stats: struct { count: u64, last_time: ?i64 },
    } {
        return .{
            .check_count = self.check_count,
            .reload_count = self.reload_count,
            .error_count = self.error_count,
            .scheduler_stats = self.scheduler.getStats(),
        };
    }

    // ========================================================================
    // 内部方法
    // ========================================================================

    /// 监控循环
    fn watchLoop(self: *Self) void {
        while (self.running.load(.seq_cst)) {
            std.time.sleep(@as(u64, self.config.watch_interval_ms) * std.time.ns_per_ms);

            self.check_count += 1;

            if (self.checkForChanges()) {
                self.triggerReload() catch |err| {
                    self.error_count += 1;
                    std.debug.print("[HotReload] Reload failed: {}\n", .{err});
                };
            }
        }
    }

    /// 检查配置文件变化
    fn checkForChanges(self: *Self) bool {
        const file = std.fs.cwd().openFile(self.config_path, .{}) catch {
            return false;
        };
        defer file.close();

        const stat = file.stat() catch {
            return false;
        };

        if (stat.mtime > self.last_modified) {
            self.last_modified = stat.mtime;
            return true;
        }

        return false;
    }

    /// 触发重载
    fn triggerReload(self: *Self) !void {
        std.debug.print("[HotReload] Configuration change detected, reloading...\n", .{});

        // 1. 加载新配置
        var new_config = try self.loadConfig();
        errdefer new_config.deinit();

        // 2. 验证参数
        if (self.config.validate_before_reload) {
            try self.validator.validateConfig(&new_config);

            if (self.reloadable) |r| {
                try r.validateParams(&new_config);
            }
        }

        // 3. 备份当前配置
        if (self.config.backup_on_reload) {
            self.backupCurrentConfig() catch |err| {
                std.debug.print("[HotReload] Backup failed: {}\n", .{err});
            };
        }

        // 4. 应用新参数
        if (self.config.reload_on_tick) {
            // 通过调度器在安全时机重载
            self.scheduler.requestReload(new_config);
        } else {
            // 直接重载
            if (self.reloadable) |r| {
                try r.updateParams(&new_config);
            }
            new_config.deinit();
        }

        self.reload_count += 1;

        // 5. 发布重载事件
        if (self.message_bus) |bus| {
            _ = bus; // TODO: 发布 config_reloaded 事件
        }

        std.debug.print("[HotReload] Configuration reloaded successfully\n", .{});
    }

    /// 加载配置文件
    fn loadConfig(self: *Self) !HotReloadConfig {
        const file = try std.fs.cwd().openFile(self.config_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        return try parseJsonConfig(self.allocator, content);
    }

    /// 备份当前配置
    fn backupCurrentConfig(self: *Self) !void {
        const timestamp = std.time.milliTimestamp();
        const backup_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}.backup.{d}",
            .{ self.config_path, timestamp },
        );
        defer self.allocator.free(backup_path);

        try std.fs.cwd().copyFile(self.config_path, std.fs.cwd(), backup_path, .{});

        std.debug.print("[HotReload] Backup created: {s}\n", .{backup_path});
    }
};

// ============================================================================
// JSON 解析
// ============================================================================

/// 解析 JSON 配置
pub fn parseJsonConfig(allocator: Allocator, json_content: []const u8) !HotReloadConfig {
    var config = HotReloadConfig.init(allocator);
    errdefer config.deinit();

    // 使用 std.json 解析
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_content, .{}) catch {
        return error.InvalidJson;
    };
    defer parsed.deinit();

    const root = parsed.value;

    // 获取 strategy
    if (root.object.get("strategy")) |strategy_val| {
        if (strategy_val == .string) {
            config.strategy = try allocator.dupe(u8, strategy_val.string);
        }
    }

    // 获取 version
    if (root.object.get("version")) |version_val| {
        if (version_val == .integer) {
            config.version = @intCast(version_val.integer);
        }
    }

    // 获取 params
    if (root.object.get("params")) |params_val| {
        if (params_val == .object) {
            var params_iter = params_val.object.iterator();
            while (params_iter.next()) |entry| {
                const param_name = entry.key_ptr.*;
                const param_obj = entry.value_ptr.*;

                if (param_obj == .object) {
                    var param = ConfigParam{
                        .name = try allocator.dupe(u8, param_name),
                        .value = 0,
                        .min = std.math.floatMin(f64),
                        .max = std.math.floatMax(f64),
                        .description = try allocator.dupe(u8, ""),
                    };

                    if (param_obj.object.get("value")) |v| {
                        param.value = switch (v) {
                            .integer => |i| @floatFromInt(i),
                            .float => |f| f,
                            else => 0,
                        };
                    }

                    if (param_obj.object.get("min")) |v| {
                        param.min = switch (v) {
                            .integer => |i| @floatFromInt(i),
                            .float => |f| f,
                            else => std.math.floatMin(f64),
                        };
                    }

                    if (param_obj.object.get("max")) |v| {
                        param.max = switch (v) {
                            .integer => |i| @floatFromInt(i),
                            .float => |f| f,
                            else => std.math.floatMax(f64),
                        };
                    }

                    if (param_obj.object.get("description")) |v| {
                        if (v == .string) {
                            allocator.free(param.description);
                            param.description = try allocator.dupe(u8, v.string);
                        }
                    }

                    const key_copy = try allocator.dupe(u8, param_name);
                    try config.params.put(key_copy, param);
                }
            }
        }
    }

    // 获取 risk
    if (root.object.get("risk")) |risk_val| {
        if (risk_val == .object) {
            if (risk_val.object.get("stop_loss_pct")) |v| {
                config.risk.stop_loss_pct = switch (v) {
                    .integer => |i| @floatFromInt(i),
                    .float => |f| f,
                    else => 0.02,
                };
            }
            if (risk_val.object.get("take_profit_pct")) |v| {
                config.risk.take_profit_pct = switch (v) {
                    .integer => |i| @floatFromInt(i),
                    .float => |f| f,
                    else => 0.05,
                };
            }
            if (risk_val.object.get("max_position_size")) |v| {
                config.risk.max_position_size = switch (v) {
                    .integer => |i| @floatFromInt(i),
                    .float => |f| f,
                    else => 1000,
                };
            }
        }
    }

    return config;
}

// ============================================================================
// 测试
// ============================================================================

test "ConfigParam: validation" {
    const valid = ConfigParam{
        .name = "fast_period",
        .value = 10,
        .min = 2,
        .max = 50,
        .description = "Fast MA period",
    };
    try valid.validate();
    try std.testing.expect(valid.isValid());

    const below_min = ConfigParam{
        .name = "fast_period",
        .value = 1,
        .min = 2,
        .max = 50,
        .description = "Fast MA period",
    };
    try std.testing.expectError(error.ParamBelowMin, below_min.validate());
    try std.testing.expect(!below_min.isValid());

    const above_max = ConfigParam{
        .name = "fast_period",
        .value = 100,
        .min = 2,
        .max = 50,
        .description = "Fast MA period",
    };
    try std.testing.expectError(error.ParamAboveMax, above_max.validate());
    try std.testing.expect(!above_max.isValid());
}

test "RiskConfig: validation" {
    const valid = RiskConfig{
        .stop_loss_pct = 0.02,
        .take_profit_pct = 0.05,
        .max_position_size = 1000,
    };
    try valid.validate();

    const invalid_stop_loss = RiskConfig{
        .stop_loss_pct = -0.02,
        .take_profit_pct = 0.05,
        .max_position_size = 1000,
    };
    try std.testing.expectError(error.InvalidStopLoss, invalid_stop_loss.validate());
}

test "HotReloadConfig: init and deinit" {
    const allocator = std.testing.allocator;

    var config = HotReloadConfig.init(allocator);
    defer config.deinit();

    try std.testing.expectEqual(@as(u32, 1), config.version);
    try std.testing.expectEqual(@as(usize, 0), config.paramCount());
}

test "SafeReloadScheduler: tick lifecycle" {
    var scheduler = SafeReloadScheduler.init();

    try std.testing.expect(!scheduler.isInTick());
    try std.testing.expect(!scheduler.hasPendingReload());

    scheduler.onTickStart();
    try std.testing.expect(scheduler.isInTick());

    _ = try scheduler.onTickEnd(null);
    try std.testing.expect(!scheduler.isInTick());
}

test "ParamValidator: validateParamRange" {
    const allocator = std.testing.allocator;

    var validator = ParamValidator.init(allocator);

    const valid_param = ConfigParam{
        .name = "period",
        .value = 20,
        .min = 5,
        .max = 100,
        .description = "Period",
    };
    try validator.validateParamRange(valid_param);

    const invalid_param = ConfigParam{
        .name = "period",
        .value = 200,
        .min = 5,
        .max = 100,
        .description = "Period",
    };
    try std.testing.expectError(error.ParamAboveMax, validator.validateParamRange(invalid_param));
}

test "parseJsonConfig: basic parsing" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "strategy": "dual_ma",
        \\  "version": 2,
        \\  "params": {
        \\    "fast_period": {
        \\      "value": 10,
        \\      "min": 2,
        \\      "max": 50,
        \\      "description": "Fast MA period"
        \\    },
        \\    "slow_period": {
        \\      "value": 30,
        \\      "min": 10,
        \\      "max": 200,
        \\      "description": "Slow MA period"
        \\    }
        \\  },
        \\  "risk": {
        \\    "stop_loss_pct": 0.02,
        \\    "take_profit_pct": 0.05,
        \\    "max_position_size": 1000
        \\  }
        \\}
    ;

    var config = try parseJsonConfig(allocator, json);
    defer config.deinit();

    try std.testing.expectEqualStrings("dual_ma", config.strategy);
    try std.testing.expectEqual(@as(u32, 2), config.version);
    try std.testing.expectEqual(@as(usize, 2), config.paramCount());

    const fast = config.getParam("fast_period").?;
    try std.testing.expectEqual(@as(f64, 10), fast.value);
    try std.testing.expectEqual(@as(f64, 2), fast.min);
    try std.testing.expectEqual(@as(f64, 50), fast.max);

    const slow = config.getParam("slow_period").?;
    try std.testing.expectEqual(@as(f64, 30), slow.value);

    try std.testing.expectEqual(@as(f64, 0.02), config.risk.stop_loss_pct);
    try std.testing.expectEqual(@as(f64, 0.05), config.risk.take_profit_pct);
}

test "HotReloadManager: init without file" {
    const allocator = std.testing.allocator;

    var manager = try HotReloadManager.init(
        allocator,
        "nonexistent_config.json",
        null,
        null,
        .{},
    );
    defer manager.deinit();

    try std.testing.expect(!manager.isRunning());
}
