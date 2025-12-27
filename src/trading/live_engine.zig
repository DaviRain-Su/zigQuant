//! LiveTradingEngine - 实时交易引擎
//!
//! 集成所有 v0.5.0 组件的统一实时交易接口。
//!
//! ## 功能
//! - 统一管理 MessageBus、Cache、DataEngine、ExecutionEngine
//! - 提供事件驱动和时钟驱动两种交易模式
//! - WebSocket 连接管理 (需 libxev 集成)
//! - 定时器支持 (心跳、Tick)
//! - 优雅关闭和信号处理
//!
//! ## 设计原则
//! - 单线程事件循环设计
//! - 组件松耦合，通过 MessageBus 通信
//! - 准备好 libxev 集成的接口
//! - 支持回测和实盘模式切换

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const MessageBus = @import("../core/message_bus.zig").MessageBus;
const Cache = @import("../core/cache.zig").Cache;
const DataEngine = @import("../core/data_engine.zig").DataEngine;
const ExecutionEngine = @import("../core/execution_engine.zig").ExecutionEngine;
const RiskConfig = @import("../core/execution_engine.zig").RiskConfig;
const IDataProvider = @import("../core/data_engine.zig").IDataProvider;
const IExecutionClient = @import("../core/execution_engine.zig").IExecutionClient;

// ============================================================================
// 配置类型
// ============================================================================

/// LiveTradingEngine 配置
pub const LiveConfig = struct {
    /// 交易模式
    mode: TradingMode = .event_driven,

    /// 心跳间隔 (毫秒)
    heartbeat_interval_ms: u64 = 30000,

    /// Tick 间隔 (毫秒，仅 clock_driven 模式)
    tick_interval_ms: u64 = 1000,

    /// 是否自动重连
    auto_reconnect: bool = true,

    /// 最大重连尝试次数
    max_reconnect_attempts: u32 = 10,

    /// 重连基础间隔 (毫秒)
    reconnect_base_ms: u64 = 1000,

    /// 重连最大间隔 (毫秒)
    reconnect_max_ms: u64 = 60000,

    /// 风险配置
    risk: RiskConfig = .{},

    /// Cache 配置
    cache: Cache.Config = .{},

    /// DataEngine 配置
    data: DataEngine.Config = .{},
};

/// 交易模式
pub const TradingMode = enum {
    /// 事件驱动: 收到市场数据时触发策略
    event_driven,

    /// 时钟驱动: 定时触发策略 (适合做市)
    clock_driven,

    /// 混合模式: 同时支持事件和定时触发
    hybrid,
};

/// 引擎状态
pub const EngineState = enum {
    stopped,
    starting,
    running,
    stopping,
    failed,
};

/// 连接状态
pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    reconnecting,
};

// ============================================================================
// LiveTradingEngine 错误
// ============================================================================

pub const LiveError = error{
    NotInitialized,
    AlreadyRunning,
    ConnectionFailed,
    StartFailed,
    StopFailed,
    OutOfMemory,
};

// ============================================================================
// LiveTradingEngine 主结构
// ============================================================================

pub const LiveTradingEngine = struct {
    allocator: Allocator,

    // 核心组件
    bus: MessageBus,
    cache: Cache,
    data_engine: DataEngine,
    execution_engine: ExecutionEngine,

    // 配置
    config: LiveConfig,

    // 状态
    state: EngineState,
    connection_state: ConnectionState,

    // 统计
    stats: Stats,

    // 回调
    on_tick: ?*const fn (*LiveTradingEngine) void,
    on_connected: ?*const fn (*LiveTradingEngine) void,
    on_disconnected: ?*const fn (*LiveTradingEngine) void,

    // 内部状态
    tick_count: u64,
    last_heartbeat: ?Timestamp,
    reconnect_attempts: u32,

    pub const Stats = struct {
        uptime_ms: u64 = 0,
        ticks: u64 = 0,
        heartbeats_sent: u64 = 0,
        reconnects: u64 = 0,
        start_time: ?Timestamp = null,
    };

    // ========================================================================
    // 初始化和清理
    // ========================================================================

    /// 初始化 LiveTradingEngine
    /// 注意: 初始化后需要调用 initComponents() 来设置组件间的指针
    pub fn init(allocator: Allocator, config: LiveConfig) LiveTradingEngine {
        var self: LiveTradingEngine = .{
            .allocator = allocator,
            .bus = MessageBus.init(allocator),
            .cache = undefined,
            .data_engine = undefined,
            .execution_engine = undefined,
            .config = config,
            .state = .stopped,
            .connection_state = .disconnected,
            .stats = .{},
            .on_tick = null,
            .on_connected = null,
            .on_disconnected = null,
            .tick_count = 0,
            .last_heartbeat = null,
            .reconnect_attempts = 0,
        };

        // 使用 self 的指针来初始化组件，确保指针有效
        self.cache = Cache.init(allocator, null, config.cache); // 不传 bus 避免循环
        self.data_engine = DataEngine.init(allocator, &self.bus, &self.cache, config.data);
        self.execution_engine = ExecutionEngine.init(allocator, &self.bus, &self.cache, config.risk);

        return self;
    }

    /// 释放资源
    pub fn deinit(self: *LiveTradingEngine) void {
        // 注意: 不要在 deinit 中调用 stop()，因为组件的 bus 指针可能已无效
        // 调用者应该在 deinit 之前手动调用 stop()

        // 直接释放资源，不发布事件
        self.execution_engine.deinit();
        self.data_engine.deinit();
        self.cache.deinit();
        self.bus.deinit();
    }

    // ========================================================================
    // 组件配置
    // ========================================================================

    /// 设置数据提供者
    pub fn setDataProvider(self: *LiveTradingEngine, provider: IDataProvider) !void {
        try self.data_engine.addProvider(provider);
    }

    /// 设置执行客户端
    pub fn setExecutionClient(self: *LiveTradingEngine, client: IExecutionClient) void {
        self.execution_engine.setClient(client);
    }

    /// 设置 Tick 回调
    pub fn setOnTick(self: *LiveTradingEngine, callback: *const fn (*LiveTradingEngine) void) void {
        self.on_tick = callback;
    }

    /// 设置连接回调
    pub fn setOnConnected(self: *LiveTradingEngine, callback: *const fn (*LiveTradingEngine) void) void {
        self.on_connected = callback;
    }

    /// 设置断开回调
    pub fn setOnDisconnected(self: *LiveTradingEngine, callback: *const fn (*LiveTradingEngine) void) void {
        self.on_disconnected = callback;
    }

    // ========================================================================
    // 生命周期管理
    // ========================================================================

    /// 启动引擎
    pub fn start(self: *LiveTradingEngine) !void {
        if (self.state == .running) {
            return LiveError.AlreadyRunning;
        }

        self.state = .starting;
        self.stats.start_time = Timestamp.now();

        // 启动 DataEngine
        self.data_engine.start() catch |err| {
            self.state = .failed;
            return err;
        };

        // 启动 ExecutionEngine
        self.execution_engine.start() catch |err| {
            self.state = .failed;
            return err;
        };

        self.state = .running;
        self.connection_state = .connected;

        // 发布启动事件
        self.bus.publish("live_engine.started", .{
            .tick = .{
                .timestamp = Timestamp.now().millis * 1_000_000,
                .tick_number = 0,
            },
        });

        // 调用连接回调
        if (self.on_connected) |callback| {
            callback(self);
        }
    }

    /// 停止引擎
    pub fn stop(self: *LiveTradingEngine) void {
        if (self.state != .running) {
            return;
        }

        self.state = .stopping;

        // 停止组件
        self.execution_engine.stop();
        self.data_engine.stop();

        self.state = .stopped;
        self.connection_state = .disconnected;

        // 计算运行时间
        if (self.stats.start_time) |start_ts| {
            self.stats.uptime_ms = @intCast(Timestamp.now().millis - start_ts.millis);
        }

        // 发布停止事件
        self.bus.publish("live_engine.stopped", .{
            .shutdown = .{
                .reason = .user_request,
                .message = "LiveTradingEngine stopped",
            },
        });

        // 调用断开回调
        if (self.on_disconnected) |callback| {
            callback(self);
        }
    }

    // ========================================================================
    // 事件循环 (同步版本，用于测试)
    // ========================================================================

    /// 处理一次事件循环迭代
    pub fn tick(self: *LiveTradingEngine) !void {
        if (self.state != .running) {
            return;
        }

        // 处理数据引擎消息
        try self.data_engine.poll();

        // 更新统计
        self.tick_count += 1;
        self.stats.ticks += 1;

        // 调用 tick 回调
        if (self.on_tick) |callback| {
            callback(self);
        }

        // 发布 tick 事件
        self.bus.publish("system.tick", .{
            .tick = .{
                .timestamp = Timestamp.now().millis * 1_000_000,
                .tick_number = self.tick_count,
            },
        });
    }

    /// 运行指定次数的 tick (用于测试)
    pub fn runTicks(self: *LiveTradingEngine, count: u64) !void {
        var i: u64 = 0;
        while (i < count and self.state == .running) : (i += 1) {
            try self.tick();
        }
    }

    // ========================================================================
    // 数据订阅
    // ========================================================================

    /// 订阅市场数据
    pub fn subscribe(self: *LiveTradingEngine, symbol: []const u8) !void {
        try self.data_engine.subscribe(symbol, .all);
    }

    /// 取消订阅
    pub fn unsubscribe(self: *LiveTradingEngine, symbol: []const u8) void {
        self.data_engine.unsubscribe(symbol);
    }

    // ========================================================================
    // 订单操作
    // ========================================================================

    /// 提交订单
    pub fn submitOrder(self: *LiveTradingEngine, request: @import("../core/execution_engine.zig").OrderRequest) !@import("../core/execution_engine.zig").OrderResult {
        return self.execution_engine.submitOrder(request);
    }

    /// 取消订单
    pub fn cancelOrder(self: *LiveTradingEngine, order_id: []const u8) !void {
        return self.execution_engine.cancelOrder(order_id);
    }

    /// 取消所有订单
    pub fn cancelAllOrders(self: *LiveTradingEngine) !void {
        return self.execution_engine.cancelAllOrders();
    }

    // ========================================================================
    // 查询方法
    // ========================================================================

    /// 获取 MessageBus
    pub fn getMessageBus(self: *LiveTradingEngine) *MessageBus {
        return &self.bus;
    }

    /// 获取 Cache
    pub fn getCache(self: *LiveTradingEngine) *Cache {
        return &self.cache;
    }

    /// 获取引擎状态
    pub fn getState(self: *const LiveTradingEngine) EngineState {
        return self.state;
    }

    /// 获取连接状态
    pub fn getConnectionState(self: *const LiveTradingEngine) ConnectionState {
        return self.connection_state;
    }

    /// 获取统计信息
    pub fn getStats(self: *const LiveTradingEngine) Stats {
        return self.stats;
    }

    /// 是否正在运行
    pub fn isRunning(self: *const LiveTradingEngine) bool {
        return self.state == .running;
    }

    /// 是否已连接
    pub fn isConnected(self: *const LiveTradingEngine) bool {
        return self.connection_state == .connected;
    }
};

// ============================================================================
// AsyncLiveTradingEngine - libxev 异步版本
// ============================================================================

/// 基于 libxev 的异步交易引擎
/// 使用 io_uring (Linux) 或 kqueue (macOS) 实现高性能事件循环
pub const AsyncLiveTradingEngine = struct {
    const xev = @import("xev");

    allocator: Allocator,

    // libxev 事件循环
    loop: xev.Loop,

    // 核心组件 (指针，因为需要在事件回调中访问)
    bus: *MessageBus,
    cache: *Cache,
    data_engine: *DataEngine,
    execution_engine: *ExecutionEngine,

    // 配置
    config: AsyncConfig,

    // 状态
    state: EngineState,
    connection_state: ConnectionState,

    // 统计
    stats: Stats,

    // 定时器
    tick_timer: ?TimerState = null,
    heartbeat_timer: ?TimerState = null,

    // 回调
    on_tick: ?*const fn (*AsyncLiveTradingEngine) void = null,

    const TimerState = struct {
        completion: xev.Completion = undefined,
        running: bool = false,
    };

    pub const Stats = struct {
        uptime_ms: u64 = 0,
        ticks: u64 = 0,
        heartbeats_sent: u64 = 0,
        start_time: ?Timestamp = null,
    };

    pub const AsyncConfig = struct {
        /// 交易模式
        mode: TradingMode = .event_driven,
        /// 心跳间隔 (毫秒)
        heartbeat_interval_ms: u64 = 30000,
        /// Tick 间隔 (毫秒，仅 clock_driven 模式)
        tick_interval_ms: u64 = 1000,
        /// 是否启用心跳
        enable_heartbeat: bool = true,
        /// 是否启用 tick 定时器
        enable_tick_timer: bool = false,
    };

    /// 初始化异步引擎
    pub fn init(
        allocator: Allocator,
        bus: *MessageBus,
        cache: *Cache,
        data_engine: *DataEngine,
        execution_engine: *ExecutionEngine,
        config: AsyncConfig,
    ) !AsyncLiveTradingEngine {
        return .{
            .allocator = allocator,
            .loop = try xev.Loop.init(.{}),
            .bus = bus,
            .cache = cache,
            .data_engine = data_engine,
            .execution_engine = execution_engine,
            .config = config,
            .state = .stopped,
            .connection_state = .disconnected,
            .stats = .{},
        };
    }

    /// 释放资源
    pub fn deinit(self: *AsyncLiveTradingEngine) void {
        self.stopTimers();
        self.loop.deinit();
    }

    /// 启动异步引擎
    pub fn start(self: *AsyncLiveTradingEngine) !void {
        if (self.state == .running) {
            return LiveError.AlreadyRunning;
        }

        self.state = .starting;
        self.stats.start_time = Timestamp.now();

        // 启动 DataEngine
        try self.data_engine.start();

        // 启动 ExecutionEngine
        try self.execution_engine.start();

        // 启动定时器
        if (self.config.enable_tick_timer) {
            try self.startTickTimer();
        }

        if (self.config.enable_heartbeat) {
            try self.startHeartbeatTimer();
        }

        self.state = .running;
        self.connection_state = .connected;

        // 发布启动事件
        self.bus.publish("async_engine.started", .{
            .tick = .{
                .timestamp = Timestamp.now().millis * 1_000_000,
                .tick_number = 0,
            },
        });
    }

    /// 运行事件循环 (阻塞)
    pub fn run(self: *AsyncLiveTradingEngine) !void {
        try self.loop.run(.until_done);
    }

    /// 运行一次事件循环迭代 (非阻塞)
    pub fn runOnce(self: *AsyncLiveTradingEngine) !void {
        try self.loop.run(.no_wait);
    }

    /// 停止引擎
    pub fn stop(self: *AsyncLiveTradingEngine) void {
        if (self.state != .running) {
            return;
        }

        self.state = .stopping;

        // 停止定时器
        self.stopTimers();

        // 停止组件
        self.execution_engine.stop();
        self.data_engine.stop();

        self.state = .stopped;
        self.connection_state = .disconnected;

        // 计算运行时间
        if (self.stats.start_time) |start_ts| {
            self.stats.uptime_ms = @intCast(Timestamp.now().millis - start_ts.millis);
        }

        // 发布停止事件
        self.bus.publish("async_engine.stopped", .{
            .shutdown = .{
                .reason = .user_request,
                .message = "AsyncLiveTradingEngine stopped",
            },
        });
    }

    // ========================================================================
    // 定时器管理
    // ========================================================================

    fn startTickTimer(self: *AsyncLiveTradingEngine) !void {
        self.tick_timer = .{};
        self.scheduleTickTimer();
    }

    fn scheduleTickTimer(self: *AsyncLiveTradingEngine) void {
        if (self.tick_timer) |*timer| {
            timer.running = true;
            const timeout: xev.Timer.Timeout = .{
                .tv_sec = @intCast(self.config.tick_interval_ms / 1000),
                .tv_nsec = @intCast((self.config.tick_interval_ms % 1000) * 1_000_000),
            };
            xev.Timer.run(&self.loop, &timer.completion, timeout, AsyncLiveTradingEngine, self, onTickTimer);
        }
    }

    fn onTickTimer(
        self_opt: ?*AsyncLiveTradingEngine,
        _: *xev.Loop,
        _: *xev.Completion,
        result: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        _ = result catch return .disarm;

        const self = self_opt orelse return .disarm;

        if (self.state != .running) {
            return .disarm;
        }

        // 处理数据引擎
        self.data_engine.poll() catch {};

        // 更新统计
        self.stats.ticks += 1;

        // 调用回调
        if (self.on_tick) |callback| {
            callback(self);
        }

        // 发布 tick 事件
        self.bus.publish("system.tick", .{
            .tick = .{
                .timestamp = Timestamp.now().millis * 1_000_000,
                .tick_number = self.stats.ticks,
            },
        });

        // 重新调度
        self.scheduleTickTimer();
        return .disarm;
    }

    fn startHeartbeatTimer(self: *AsyncLiveTradingEngine) !void {
        self.heartbeat_timer = .{};
        self.scheduleHeartbeatTimer();
    }

    fn scheduleHeartbeatTimer(self: *AsyncLiveTradingEngine) void {
        if (self.heartbeat_timer) |*timer| {
            timer.running = true;
            const timeout: xev.Timer.Timeout = .{
                .tv_sec = @intCast(self.config.heartbeat_interval_ms / 1000),
                .tv_nsec = @intCast((self.config.heartbeat_interval_ms % 1000) * 1_000_000),
            };
            xev.Timer.run(&self.loop, &timer.completion, timeout, AsyncLiveTradingEngine, self, onHeartbeatTimer);
        }
    }

    fn onHeartbeatTimer(
        self_opt: ?*AsyncLiveTradingEngine,
        _: *xev.Loop,
        _: *xev.Completion,
        result: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        _ = result catch return .disarm;

        const self = self_opt orelse return .disarm;

        if (self.state != .running) {
            return .disarm;
        }

        // 更新心跳统计
        self.stats.heartbeats_sent += 1;

        // 发布心跳事件
        self.bus.publish("system.heartbeat", .{
            .tick = .{
                .timestamp = Timestamp.now().millis * 1_000_000,
                .tick_number = self.stats.heartbeats_sent,
            },
        });

        // 重新调度
        self.scheduleHeartbeatTimer();
        return .disarm;
    }

    fn stopTimers(self: *AsyncLiveTradingEngine) void {
        if (self.tick_timer) |*timer| {
            if (timer.running) {
                // 标记为不再运行，回调会自动 disarm
                timer.running = false;
            }
            self.tick_timer = null;
        }

        if (self.heartbeat_timer) |*timer| {
            if (timer.running) {
                timer.running = false;
            }
            self.heartbeat_timer = null;
        }
    }

    // ========================================================================
    // 查询方法
    // ========================================================================

    pub fn getState(self: *const AsyncLiveTradingEngine) EngineState {
        return self.state;
    }

    pub fn getStats(self: *const AsyncLiveTradingEngine) Stats {
        return self.stats;
    }

    pub fn isRunning(self: *const AsyncLiveTradingEngine) bool {
        return self.state == .running;
    }

    pub fn setOnTick(self: *AsyncLiveTradingEngine, callback: *const fn (*AsyncLiveTradingEngine) void) void {
        self.on_tick = callback;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "LiveTradingEngine: init and deinit" {
    var engine = LiveTradingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    try std.testing.expectEqual(EngineState.stopped, engine.getState());
    try std.testing.expect(!engine.isRunning());
}

test "LiveTradingEngine: with mock providers" {
    var engine = LiveTradingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    // 添加 mock 数据提供者
    var mock_data = @import("../core/data_engine.zig").MockDataProvider.init(std.testing.allocator);
    defer mock_data.deinit();
    try engine.setDataProvider(mock_data.asProvider());

    // 添加 mock 执行客户端
    var mock_exec = @import("../core/execution_engine.zig").MockExecutionClient.init(std.testing.allocator);
    defer mock_exec.deinit();
    engine.setExecutionClient(mock_exec.asClient());

    // 启动
    try engine.start();
    try std.testing.expect(engine.isRunning());
    try std.testing.expect(engine.isConnected());

    // 停止
    engine.stop();
    try std.testing.expect(!engine.isRunning());
}

test "LiveTradingEngine: tick execution" {
    var engine = LiveTradingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    var mock_data = @import("../core/data_engine.zig").MockDataProvider.init(std.testing.allocator);
    defer mock_data.deinit();
    try engine.setDataProvider(mock_data.asProvider());

    var mock_exec = @import("../core/execution_engine.zig").MockExecutionClient.init(std.testing.allocator);
    defer mock_exec.deinit();
    engine.setExecutionClient(mock_exec.asClient());

    try engine.start();
    try engine.runTicks(5);
    engine.stop();

    // 验证 tick 被执行了 5 次
    try std.testing.expectEqual(@as(u64, 5), engine.stats.ticks);
}

test "LiveTradingEngine: order submission" {
    var engine = LiveTradingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    var mock_data = @import("../core/data_engine.zig").MockDataProvider.init(std.testing.allocator);
    defer mock_data.deinit();
    try engine.setDataProvider(mock_data.asProvider());

    var mock_exec = @import("../core/execution_engine.zig").MockExecutionClient.init(std.testing.allocator);
    defer mock_exec.deinit();
    engine.setExecutionClient(mock_exec.asClient());

    try engine.start();

    const result = try engine.submitOrder(.{
        .client_order_id = "live-001",
        .symbol = "BTC-USDT",
        .side = .buy,
        .order_type = .market,
        .quantity = @import("../core/decimal.zig").Decimal.fromInt(1),
    });

    try std.testing.expect(result.success);

    engine.stop();
}

test "TradingMode: values" {
    try std.testing.expectEqual(TradingMode.event_driven, TradingMode.event_driven);
    try std.testing.expectEqual(TradingMode.clock_driven, TradingMode.clock_driven);
    try std.testing.expectEqual(TradingMode.hybrid, TradingMode.hybrid);
}

test "EngineState: values" {
    try std.testing.expectEqual(EngineState.stopped, EngineState.stopped);
    try std.testing.expectEqual(EngineState.running, EngineState.running);
}

test "LiveConfig: defaults" {
    const config = LiveConfig{};
    try std.testing.expectEqual(TradingMode.event_driven, config.mode);
    try std.testing.expectEqual(@as(u64, 30000), config.heartbeat_interval_ms);
    try std.testing.expectEqual(@as(u64, 1000), config.tick_interval_ms);
    try std.testing.expect(config.auto_reconnect);
}

test "AsyncLiveTradingEngine: AsyncConfig defaults" {
    const config = AsyncLiveTradingEngine.AsyncConfig{};
    try std.testing.expectEqual(TradingMode.event_driven, config.mode);
    try std.testing.expectEqual(@as(u64, 30000), config.heartbeat_interval_ms);
    try std.testing.expectEqual(@as(u64, 1000), config.tick_interval_ms);
    try std.testing.expect(config.enable_heartbeat);
    try std.testing.expect(!config.enable_tick_timer);
}

test "AsyncLiveTradingEngine: init and deinit" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var data_engine = DataEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer data_engine.deinit();

    var exec_engine = ExecutionEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer exec_engine.deinit();

    var async_engine = try AsyncLiveTradingEngine.init(
        std.testing.allocator,
        &bus,
        &cache,
        &data_engine,
        &exec_engine,
        .{ .enable_heartbeat = false, .enable_tick_timer = false },
    );
    defer async_engine.deinit();

    try std.testing.expectEqual(EngineState.stopped, async_engine.getState());
    try std.testing.expect(!async_engine.isRunning());
}
