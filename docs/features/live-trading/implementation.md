# LiveTrading - 实现细节

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 架构设计

### 整体架构

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
│  ┌───────────────────────────┼───────────────────────────┐  │
│  │                           ▼                           │  │
│  │  ┌─────────────┐    ┌─────────────┐                  │  │
│  │  │  DataEngine │    │  Execution  │                  │  │
│  │  │             │    │   Engine    │                  │  │
│  │  └─────────────┘    └─────────────┘                  │  │
│  └───────────────────────────────────────────────────────┘  │
│                              │                               │
│                              ▼                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    MessageBus                         │   │
│  │              事件发布和处理                            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### libxev 集成

```
libxev Event Loop (Proactor 模式)
        │
        ├──→ TCP Completion (WebSocket 数据)
        │        └──→ 解析消息 → 发布到 MessageBus
        │
        ├──→ Timer Completion (心跳/Tick)
        │        └──→ 发送 Ping / 发布 Tick 事件
        │
        └──→ Signal Completion (SIGINT/SIGTERM)
                 └──→ 优雅关闭
```

---

## 核心数据结构

### LiveTradingEngine 结构

```zig
const xev = @import("xev");

pub const LiveTradingEngine = struct {
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    config: LiveTradingConfig,

    // 组件
    data_engine: ?*DataEngine,
    execution_engine: ?*ExecutionEngine,

    // libxev
    loop: xev.Loop,

    // WebSocket 连接
    connections: std.ArrayList(WebSocketConnection),

    // 定时器
    heartbeat_completion: xev.Completion,
    tick_completion: xev.Completion,

    // 状态
    is_running: bool,
    tick_count: u64,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        message_bus: *MessageBus,
        cache: *Cache,
        config: LiveTradingConfig,
    ) !Self {
        return Self{
            .allocator = allocator,
            .message_bus = message_bus,
            .cache = cache,
            .config = config,
            .data_engine = null,
            .execution_engine = null,
            .loop = try xev.Loop.init(.{}),
            .connections = std.ArrayList(WebSocketConnection).init(allocator),
            .heartbeat_completion = undefined,
            .tick_completion = undefined,
            .is_running = false,
            .tick_count = 0,
        };
    }
};
```

---

## WebSocket 实现

### 连接建立

```zig
fn connectWebSocket(self: *Self, endpoint: WebSocketEndpoint) !*WebSocketConnection {
    // 创建 TCP socket
    var socket = try xev.TCP.init(.{
        .domain = .ipv4,
    });

    // DNS 解析
    const address = try std.net.Address.resolveIp(endpoint.host, endpoint.port);

    // 异步连接
    var completion: xev.Completion = undefined;
    socket.connect(&self.loop, address, &completion, self, onConnect);

    // 创建连接对象
    const conn = WebSocketConnection{
        .endpoint = endpoint,
        .socket = socket,
        .state = .connecting,
        .reconnect_attempts = 0,
        .last_message_time = std.time.milliTimestamp(),
    };

    try self.connections.append(conn);
    return &self.connections.items[self.connections.items.len - 1];
}

fn onConnect(
    self: *Self,
    completion: *xev.Completion,
    socket: xev.TCP,
    result: xev.TCP.ConnectError!void,
) void {
    _ = result catch |err| {
        self.handleConnectionError(socket, err);
        return;
    };

    // 发送 WebSocket 握手
    self.sendHandshake(socket) catch {};

    // 开始接收数据
    self.startReceiving(socket);
}
```

### 数据接收

```zig
fn startReceiving(self: *Self, socket: xev.TCP) void {
    var buffer: [4096]u8 = undefined;
    var completion: xev.Completion = undefined;

    socket.recv(&self.loop, &buffer, &completion, self, onReceive);
}

fn onReceive(
    self: *Self,
    completion: *xev.Completion,
    socket: xev.TCP,
    buffer: []u8,
    result: xev.TCP.RecvError!usize,
) void {
    const bytes_read = result catch |err| {
        self.handleReceiveError(socket, err);
        return;
    };

    if (bytes_read == 0) {
        // 连接关闭
        self.handleDisconnect(socket);
        return;
    }

    // 解析 WebSocket 帧
    const data = buffer[0..bytes_read];
    self.parseWebSocketFrame(data) catch {};

    // 继续接收
    self.startReceiving(socket);
}

fn parseWebSocketFrame(self: *Self, data: []const u8) !void {
    // 解析 WebSocket 帧头
    const frame = try WebSocketFrame.parse(data);

    if (frame.opcode == .text) {
        // 解析 JSON 并发布事件
        const event = try self.parseMessage(frame.payload);
        try self.publishEvent(event);
    } else if (frame.opcode == .ping) {
        // 响应 Pong
        try self.sendPong(frame.payload);
    }
}
```

### 自动重连

```zig
fn handleDisconnect(self: *Self, socket: xev.TCP) void {
    const conn = self.findConnection(socket) orelse return;

    conn.state = .disconnected;

    // 发布断开事件
    self.message_bus.publish("system.disconnected", .{
        .connection = .{ .endpoint = conn.endpoint.url },
    }) catch {};

    if (self.config.auto_reconnect) {
        self.scheduleReconnect(conn);
    }
}

fn scheduleReconnect(self: *Self, conn: *WebSocketConnection) void {
    if (self.config.max_reconnect_attempts > 0 and
        conn.reconnect_attempts >= self.config.max_reconnect_attempts)
    {
        conn.state = .failed;
        return;
    }

    conn.state = .reconnecting;
    conn.reconnect_attempts += 1;

    // 指数退避
    const delay = @min(
        self.config.reconnect_base_ms * std.math.pow(u64, 2, conn.reconnect_attempts),
        self.config.reconnect_max_ms,
    );

    // 设置重连定时器
    var timer = xev.Timer.init();
    timer.set(&self.loop, delay, self, onReconnect);
}

fn onReconnect(self: *Self, completion: *xev.Completion) void {
    const conn = self.getReconnectingConnection() orelse return;

    self.message_bus.publish("system.reconnecting", .{
        .connection = .{
            .endpoint = conn.endpoint.url,
            .attempt = conn.reconnect_attempts,
        },
    }) catch {};

    // 重新连接
    self.connectWebSocket(conn.endpoint) catch |err| {
        self.scheduleReconnect(conn);
    };
}
```

---

## 定时器实现

### 心跳定时器

```zig
fn startHeartbeat(self: *Self) void {
    var timer = xev.Timer.init();
    timer.set(
        &self.loop,
        self.config.heartbeat_interval_ms,
        self,
        onHeartbeat,
    );
}

fn onHeartbeat(self: *Self, completion: *xev.Completion) void {
    // 发送 Ping 到所有连接
    for (self.connections.items) |*conn| {
        if (conn.state == .connected) {
            self.sendPing(conn) catch {};

            // 检查连接活跃度
            const now = std.time.milliTimestamp();
            const idle_time = now - conn.last_message_time;
            if (idle_time > self.config.heartbeat_interval_ms * 2) {
                // 连接可能死了
                self.handleDisconnect(conn.socket);
            }
        }
    }

    // 重新设置定时器
    self.startHeartbeat();
}
```

### Tick 定时器

```zig
fn startTickTimer(self: *Self) void {
    if (self.config.tick_interval_ms) |interval| {
        var timer = xev.Timer.init();
        timer.set(&self.loop, interval, self, onTick);
    }
}

fn onTick(self: *Self, completion: *xev.Completion) void {
    self.tick_count += 1;

    // 发布 Tick 事件
    self.message_bus.publish("system.tick", .{
        .tick = .{
            .timestamp = std.time.milliTimestamp(),
            .tick_number = self.tick_count,
        },
    }) catch {};

    // 重新设置定时器
    self.startTickTimer();
}
```

---

## 事件循环

### 主循环

```zig
pub fn start(self: *Self) !void {
    if (self.is_running) return error.AlreadyRunning;
    self.is_running = true;

    // 1. 恢复订单状态
    if (self.config.enable_recovery) {
        if (self.execution_engine) |engine| {
            try engine.recoverOrders();
        }
    }

    // 2. 连接所有 WebSocket
    for (self.config.ws_endpoints) |endpoint| {
        _ = self.connectWebSocket(endpoint) catch |err| {
            std.log.err("Failed to connect to {s}: {}", .{ endpoint.url, err });
        };
    }

    // 3. 启动定时器
    self.startHeartbeat();
    self.startTickTimer();

    // 4. 设置信号处理
    self.setupSignalHandler();

    // 5. 运行事件循环
    while (self.is_running) {
        try self.loop.run(.once);
    }

    // 6. 清理
    self.cleanup();
}

pub fn stop(self: *Self) void {
    self.is_running = false;

    // 发布关闭事件
    self.message_bus.publish("system.shutdown", .{
        .shutdown = .{ .reason = .user_request },
    }) catch {};
}
```

### 信号处理

```zig
fn setupSignalHandler(self: *Self) void {
    var signal = xev.Signal.init();
    signal.register(&self.loop, .SIGINT, self, onSignal);
    signal.register(&self.loop, .SIGTERM, self, onSignal);
}

fn onSignal(self: *Self, signal: i32) void {
    std.log.info("Received signal {}, shutting down...", .{signal});

    // 发布关闭事件
    self.message_bus.publish("system.shutdown", .{
        .shutdown = .{ .reason = .signal },
    }) catch {};

    self.is_running = false;
}
```

---

## 性能优化

### 1. 零拷贝接收

```zig
// 使用固定缓冲区，避免每次分配
const recv_buffer: [65536]u8 = undefined;

fn onReceive(self: *Self, data: []u8) void {
    // 直接在缓冲区解析，不复制
    const frame = WebSocketFrame.parseInPlace(data);
    // ...
}
```

### 2. 批量事件处理

```zig
fn processBatch(self: *Self, events: []Event) void {
    // 批量发布减少锁竞争
    for (events) |event| {
        self.message_bus.publish(event.topic, event) catch {};
    }
}
```

### 3. 连接池

```zig
// 预分配连接对象
var connection_pool: [16]WebSocketConnection = undefined;
var pool_index: usize = 0;

fn acquireConnection(self: *Self) *WebSocketConnection {
    const conn = &self.connection_pool[self.pool_index];
    self.pool_index = (self.pool_index + 1) % self.connection_pool.len;
    return conn;
}
```

---

## 文件结构

```
src/trading/
├── live_engine.zig          # LiveTradingEngine 实现
├── websocket.zig            # WebSocket 连接封装
├── timer.zig                # 定时器封装
├── signal.zig               # 信号处理
└── config.zig               # 配置

examples/
└── 11_live_trading.zig      # 实时交易示例
```

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [测试文档](./testing.md)

---

**版本**: v0.5.0
**状态**: 计划中
