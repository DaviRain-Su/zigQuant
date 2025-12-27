# Story 027: libxev Integration - 事件循环集成

**版本**: v0.5.0
**状态**: 计划中
**预计工期**: 1 周
**依赖**: Story 025 (DataEngine), Story 026 (ExecutionEngine)

---

## 目标

集成 libxev 事件循环，实现高性能异步 I/O，为实时交易提供底层支持。

## 背景

**libxev** 是由 Mitchell Hashimoto (HashiCorp 创始人) 开发的 Zig 原生事件循环库：
- **Proactor 模式**: 工作完成通知（vs Reactor 的就绪通知）
- **io_uring 支持**: Linux 上最快的 I/O 机制
- **零运行时分配**: 性能可预测
- **生产就绪**: Ghostty 终端正在使用

---

## 核心设计

### 架构

```
┌─────────────────────────────────────────────────────────────┐
│                   LiveTradingEngine                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                 libxev Event Loop                     │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │   TCP/WS    │  │   Timer     │  │   Signal    │  │   │
│  │  │  Watcher    │  │  Watcher    │  │  Handler    │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
│                              │                               │
│                              ▼                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   Event Handlers                      │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │  onConnect  │  │  onMessage  │  │   onClose   │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
│                              │                               │
│                              ▼                               │
│  ┌────────────────────┐  ┌────────────────────┐            │
│  │    DataEngine     │  │  ExecutionEngine   │            │
│  └────────────────────┘  └────────────────────┘            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 接口定义

```zig
const xev = @import("xev");

pub const LiveTradingEngine = struct {
    allocator: Allocator,
    loop: xev.Loop,

    // 核心组件
    message_bus: *MessageBus,
    cache: *Cache,
    data_engine: *DataEngine,
    execution_engine: *ExecutionEngine,

    // WebSocket 连接
    ws_connections: ArrayList(*WebSocketConnection),

    // 定时器
    tick_timer: ?xev.Timer = null,
    heartbeat_timer: ?xev.Timer = null,

    // 配置
    config: LiveTradingConfig,

    /// 初始化
    pub fn init(
        allocator: Allocator,
        message_bus: *MessageBus,
        cache: *Cache,
        config: LiveTradingConfig,
    ) !LiveTradingEngine {
        return .{
            .allocator = allocator,
            .loop = try xev.Loop.init(.{}),
            .message_bus = message_bus,
            .cache = cache,
            .data_engine = undefined,  // 后续设置
            .execution_engine = undefined,
            .ws_connections = ArrayList(*WebSocketConnection).init(allocator),
            .config = config,
        };
    }

    /// 启动交易引擎
    pub fn start(self: *LiveTradingEngine) !void {
        log.info("Starting live trading engine...");

        // 1. 恢复订单状态
        if (self.config.enable_recovery) {
            try self.execution_engine.recoverOrders();
        }

        // 2. 连接 WebSocket 数据源
        for (self.config.ws_endpoints) |endpoint| {
            try self.connectWebSocket(endpoint);
        }

        // 3. 启动心跳定时器
        try self.startHeartbeat();

        // 4. 启动策略 Tick 定时器 (如果启用)
        if (self.config.tick_interval_ms) |interval| {
            try self.startTickTimer(interval);
        }

        log.info("Live trading engine started");

        // 5. 运行事件循环
        try self.loop.run(.until_done);
    }

    /// 停止交易引擎
    pub fn stop(self: *LiveTradingEngine) void {
        log.info("Stopping live trading engine...");

        // 停止定时器
        if (self.tick_timer) |*timer| {
            timer.cancel(&self.loop);
        }
        if (self.heartbeat_timer) |*timer| {
            timer.cancel(&self.loop);
        }

        // 关闭 WebSocket 连接
        for (self.ws_connections.items) |conn| {
            conn.close();
        }

        log.info("Live trading engine stopped");
    }

    // ========== WebSocket 连接 ==========

    /// 连接 WebSocket
    fn connectWebSocket(self: *LiveTradingEngine, endpoint: WebSocketEndpoint) !void {
        var conn = try self.allocator.create(WebSocketConnection);
        conn.* = try WebSocketConnection.init(
            self.allocator,
            &self.loop,
            endpoint,
            self.onWebSocketMessage,
            self.onWebSocketClose,
        );

        try self.ws_connections.append(conn);
        try conn.connect();
    }

    /// WebSocket 消息回调
    fn onWebSocketMessage(
        self_: ?*LiveTradingEngine,
        _: *xev.Loop,
        _: *xev.Completion,
        socket: xev.TCP,
        buf: []const u8,
        result: xev.TCP.ReadError!usize,
    ) xev.CallbackAction {
        const self = self_.?;
        const n = result catch |err| {
            log.err("WebSocket read error: {}", .{err});
            return .disarm;
        };

        if (n == 0) {
            // 连接关闭
            return .disarm;
        }

        // 处理消息
        self.data_engine.processWebSocketMessage(buf[0..n]) catch |err| {
            log.err("Failed to process WS message: {}", .{err});
        };

        // 继续读取
        return .rearm;
    }

    /// WebSocket 关闭回调
    fn onWebSocketClose(
        self_: ?*LiveTradingEngine,
        _: *xev.Loop,
        conn: *WebSocketConnection,
    ) void {
        const self = self_.?;
        log.warn("WebSocket disconnected: {s}", .{conn.endpoint.url});

        // 自动重连
        if (self.config.auto_reconnect) {
            self.scheduleReconnect(conn) catch {};
        }
    }

    // ========== 定时器 ==========

    /// 启动心跳定时器
    fn startHeartbeat(self: *LiveTradingEngine) !void {
        self.heartbeat_timer = try xev.Timer.init();
        self.heartbeat_timer.?.set(
            &self.loop,
            self.config.heartbeat_interval_ms,
            LiveTradingEngine,
            self,
            onHeartbeat,
        );
    }

    /// 心跳回调
    fn onHeartbeat(
        self_: ?*LiveTradingEngine,
        loop: *xev.Loop,
        timer: *xev.Timer,
        _: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        const self = self_.?;

        // 发送心跳
        for (self.ws_connections.items) |conn| {
            conn.sendPing() catch {};
        }

        // 重新调度
        timer.set(loop, self.config.heartbeat_interval_ms, LiveTradingEngine, self, onHeartbeat);
        return .rearm;
    }

    /// 启动策略 Tick 定时器
    fn startTickTimer(self: *LiveTradingEngine, interval_ms: u64) !void {
        self.tick_timer = try xev.Timer.init();
        self.tick_timer.?.set(
            &self.loop,
            interval_ms,
            LiveTradingEngine,
            self,
            onTick,
        );
    }

    /// Tick 回调 (Clock-Driven 模式)
    fn onTick(
        self_: ?*LiveTradingEngine,
        loop: *xev.Loop,
        timer: *xev.Timer,
        _: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        const self = self_.?;

        // 发布 Tick 事件
        self.message_bus.publish("system.tick", .{
            .tick = .{ .timestamp = std.time.milliTimestamp() },
        }) catch {};

        // 重新调度
        if (self.config.tick_interval_ms) |interval| {
            timer.set(loop, interval, LiveTradingEngine, self, onTick);
            return .rearm;
        }

        return .disarm;
    }

    // ========== 重连逻辑 ==========

    /// 调度重连
    fn scheduleReconnect(self: *LiveTradingEngine, conn: *WebSocketConnection) !void {
        const delay_ms = self.calculateBackoff(conn.reconnect_attempts);

        var reconnect_timer = try xev.Timer.init();
        reconnect_timer.set(
            &self.loop,
            delay_ms,
            struct {
                fn callback(
                    ctx: ?*anyopaque,
                    _: *xev.Loop,
                    _: *xev.Timer,
                    _: xev.Timer.RunError!void,
                ) xev.CallbackAction {
                    const c: *WebSocketConnection = @ptrCast(@alignCast(ctx));
                    c.connect() catch {};
                    return .disarm;
                }
            }.callback,
        );
    }

    fn calculateBackoff(self: *LiveTradingEngine, attempts: u32) u64 {
        const base = self.config.reconnect_base_ms;
        const max = self.config.reconnect_max_ms;
        const delay = base * std.math.pow(u64, 2, attempts);
        return @min(delay, max);
    }

    pub fn deinit(self: *LiveTradingEngine) void {
        self.stop();

        for (self.ws_connections.items) |conn| {
            conn.deinit();
            self.allocator.destroy(conn);
        }
        self.ws_connections.deinit();

        self.loop.deinit();
    }
};
```

---

## WebSocket 连接封装

```zig
pub const WebSocketConnection = struct {
    allocator: Allocator,
    loop: *xev.Loop,
    endpoint: WebSocketEndpoint,
    socket: ?xev.TCP = null,

    // 回调
    on_message: MessageCallback,
    on_close: CloseCallback,

    // 状态
    connected: bool = false,
    reconnect_attempts: u32 = 0,

    // 缓冲区
    read_buffer: [65536]u8 = undefined,

    pub const MessageCallback = *const fn(
        ?*LiveTradingEngine,
        *xev.Loop,
        *xev.Completion,
        xev.TCP,
        []const u8,
        xev.TCP.ReadError!usize,
    ) xev.CallbackAction;

    pub const CloseCallback = *const fn(
        ?*LiveTradingEngine,
        *xev.Loop,
        *WebSocketConnection,
    ) void;

    pub fn init(
        allocator: Allocator,
        loop: *xev.Loop,
        endpoint: WebSocketEndpoint,
        on_message: MessageCallback,
        on_close: CloseCallback,
    ) !WebSocketConnection {
        return .{
            .allocator = allocator,
            .loop = loop,
            .endpoint = endpoint,
            .on_message = on_message,
            .on_close = on_close,
        };
    }

    pub fn connect(self: *WebSocketConnection) !void {
        log.info("Connecting to {s}...", .{self.endpoint.url});

        // 解析地址
        const address = try std.net.Address.parseIp(self.endpoint.host, self.endpoint.port);

        // 创建 TCP socket
        self.socket = try xev.TCP.init(self.loop, address);

        // 异步连接
        var c: xev.Completion = undefined;
        self.socket.?.connect(
            self.loop,
            &c,
            address,
            WebSocketConnection,
            self,
            onConnected,
        );
    }

    fn onConnected(
        self_: ?*WebSocketConnection,
        loop: *xev.Loop,
        c: *xev.Completion,
        socket: xev.TCP,
        result: xev.TCP.ConnectError!void,
    ) xev.CallbackAction {
        const self = self_.?;

        _ = result catch |err| {
            log.err("Connection failed: {}", .{err});
            self.reconnect_attempts += 1;
            return .disarm;
        };

        log.info("Connected to {s}", .{self.endpoint.url});
        self.connected = true;
        self.reconnect_attempts = 0;

        // 发送 WebSocket 握手
        self.sendHandshake() catch {};

        // 开始读取
        socket.read(loop, c, .{ .slice = &self.read_buffer }, self.on_message);

        return .rearm;
    }

    fn sendHandshake(self: *WebSocketConnection) !void {
        const handshake = try std.fmt.allocPrint(self.allocator,
            \\GET {s} HTTP/1.1\r\n
            \\Host: {s}\r\n
            \\Upgrade: websocket\r\n
            \\Connection: Upgrade\r\n
            \\Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n
            \\Sec-WebSocket-Version: 13\r\n
            \\\r\n
        , .{ self.endpoint.path, self.endpoint.host });
        defer self.allocator.free(handshake);

        var c: xev.Completion = undefined;
        self.socket.?.write(self.loop, &c, .{ .slice = handshake }, null);
    }

    pub fn send(self: *WebSocketConnection, data: []const u8) !void {
        if (!self.connected) return error.NotConnected;

        var c: xev.Completion = undefined;
        self.socket.?.write(self.loop, &c, .{ .slice = data }, null);
    }

    pub fn sendPing(self: *WebSocketConnection) !void {
        // WebSocket ping frame
        try self.send(&[_]u8{ 0x89, 0x00 });
    }

    pub fn close(self: *WebSocketConnection) void {
        if (self.socket) |*socket| {
            socket.close(self.loop, null);
        }
        self.connected = false;
    }

    pub fn deinit(self: *WebSocketConnection) void {
        self.close();
    }
};
```

---

## 配置

```zig
pub const LiveTradingConfig = struct {
    /// WebSocket 端点列表
    ws_endpoints: []const WebSocketEndpoint = &[_]WebSocketEndpoint{},

    /// 心跳间隔 (毫秒)
    heartbeat_interval_ms: u64 = 30000,

    /// Tick 间隔 (毫秒, null = 禁用 Clock-Driven)
    tick_interval_ms: ?u64 = null,

    /// 是否启用订单恢复
    enable_recovery: bool = true,

    /// 是否自动重连
    auto_reconnect: bool = true,

    /// 重连基础延迟 (毫秒)
    reconnect_base_ms: u64 = 1000,

    /// 重连最大延迟 (毫秒)
    reconnect_max_ms: u64 = 60000,
};

pub const WebSocketEndpoint = struct {
    url: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8,
};
```

---

## 使用示例

### 完整实时交易示例

```zig
const std = @import("std");
const xev = @import("xev");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化核心组件
    var message_bus = try zigQuant.MessageBus.init(allocator);
    defer message_bus.deinit();

    var cache = try zigQuant.Cache.init(allocator, &message_bus);
    defer cache.deinit();

    // 创建策略
    var strategy = try MyStrategy.init(allocator, &cache, &message_bus);
    defer strategy.deinit();

    // 订阅事件
    try message_bus.subscribe("market_data.*", strategy.onMarketData);
    try message_bus.subscribe("order.*", strategy.onOrderEvent);

    // 创建实时交易引擎
    var engine = try zigQuant.LiveTradingEngine.init(
        allocator,
        &message_bus,
        &cache,
        .{
            .ws_endpoints = &[_]zigQuant.WebSocketEndpoint{
                .{
                    .url = "wss://api.hyperliquid.xyz/ws",
                    .host = "api.hyperliquid.xyz",
                    .port = 443,
                    .path = "/ws",
                },
            },
            .tick_interval_ms = 1000,  // 每秒 Tick (做市模式)
            .enable_recovery = true,
            .auto_reconnect = true,
        },
    );
    defer engine.deinit();

    // 启动交易
    std.debug.print("Starting live trading...\n", .{});
    try engine.start();
}
```

---

## 性能目标

| 指标 | 目标 | 说明 |
|------|------|------|
| WebSocket 延迟 | < 5ms | 消息接收到处理完成 |
| 订单提交延迟 | < 10ms | 信号到订单发出 |
| 消息吞吐量 | > 5000/s | 高频行情处理 |
| CPU 使用率 | < 20% | 空闲时基线 |
| 内存分配 | 零运行时 | libxev 保证 |

---

## 测试计划

### 单元测试

| 测试 | 描述 |
|------|------|
| `test_event_loop_init` | 事件循环初始化 |
| `test_timer_scheduling` | 定时器调度 |
| `test_tcp_connection` | TCP 连接 |
| `test_websocket_handshake` | WebSocket 握手 |

### 集成测试

| 测试 | 描述 |
|------|------|
| `test_live_data_feed` | 实时数据接收 |
| `test_order_execution` | 订单执行 |
| `test_reconnect` | 断线重连 |
| `test_graceful_shutdown` | 优雅关闭 |

### 性能测试

| 测试 | 描述 |
|------|------|
| `benchmark_message_latency` | 消息延迟基准 |
| `benchmark_throughput` | 吞吐量基准 |
| `stress_test_connections` | 连接压力测试 |

---

## 文件结构

```
src/trading/
├── live_engine.zig          # LiveTradingEngine 实现
├── websocket.zig            # WebSocket 连接封装
├── timer.zig                # 定时器封装
└── config.zig               # 配置

tests/
└── trading/
    ├── live_engine_test.zig # 引擎测试
    └── websocket_test.zig   # WebSocket 测试
```

---

## 验收标准

- [ ] libxev 事件循环集成
- [ ] WebSocket 异步连接
- [ ] 定时器支持 (心跳/Tick)
- [ ] 断线自动重连
- [ ] 优雅关闭
- [ ] WebSocket 延迟 < 5ms
- [ ] 吞吐量 > 5000 msg/s
- [ ] 零内存泄漏
- [ ] 所有测试通过

---

## 相关文档

- [v0.5.0 Overview](./OVERVIEW.md)
- [libxev 集成方案](../../architecture/LIBXEV_INTEGRATION.md)
- [Story 025: DataEngine](./STORY_025_DATA_ENGINE.md)
- [Story 026: ExecutionEngine](./STORY_026_EXECUTION_ENGINE.md)

---

**版本**: v0.5.0
**状态**: 计划中
**创建时间**: 2025-12-27
