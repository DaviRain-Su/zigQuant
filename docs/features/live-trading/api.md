# LiveTrading - API 参考

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 核心类型

### LiveTradingEngine

实时交易引擎主结构体。

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

    // libxev 事件循环
    loop: xev.Loop,

    // WebSocket 连接
    ws_connections: ArrayList(WebSocketConnection),

    // 定时器
    heartbeat_timer: ?xev.Timer,
    tick_timer: ?xev.Timer,

    // 状态
    is_running: bool,
};
```

### LiveTradingConfig

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

    /// 最大重连次数 (0 = 无限)
    max_reconnect_attempts: u32 = 0,
};
```

### WebSocketEndpoint

```zig
pub const WebSocketEndpoint = struct {
    /// WebSocket URL
    url: []const u8,

    /// 主机名
    host: []const u8,

    /// 端口
    port: u16 = 443,

    /// 路径
    path: []const u8 = "/ws",

    /// 是否使用 TLS
    use_tls: bool = true,

    /// 订阅消息列表
    subscriptions: []const []const u8 = &.{},
};
```

---

## 初始化与销毁

### init

初始化 LiveTradingEngine。

```zig
pub fn init(
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    config: LiveTradingConfig,
) !LiveTradingEngine
```

**参数**:
- `allocator`: 内存分配器
- `message_bus`: MessageBus 实例引用
- `cache`: Cache 实例引用
- `config`: 实时交易配置

**返回**: LiveTradingEngine 实例

**示例**:
```zig
var engine = try LiveTradingEngine.init(
    allocator,
    &message_bus,
    &cache,
    .{
        .ws_endpoints = &[_]WebSocketEndpoint{
            .{
                .url = "wss://api.hyperliquid.xyz/ws",
                .host = "api.hyperliquid.xyz",
                .subscriptions = &.{
                    "{\"method\":\"subscribe\",\"subscription\":{\"type\":\"allMids\"}}",
                },
            },
        },
        .tick_interval_ms = 1000,
        .auto_reconnect = true,
    },
);
defer engine.deinit();
```

### deinit

释放 LiveTradingEngine 资源。

```zig
pub fn deinit(self: *LiveTradingEngine) void
```

---

## 组件设置

### setDataEngine

设置数据引擎。

```zig
pub fn setDataEngine(self: *LiveTradingEngine, engine: *DataEngine) void
```

### setExecutionEngine

设置执行引擎。

```zig
pub fn setExecutionEngine(self: *LiveTradingEngine, engine: *ExecutionEngine) void
```

---

## 运行控制

### start

启动实时交易引擎。

```zig
pub fn start(self: *LiveTradingEngine) !void
```

**说明**:
1. 建立所有 WebSocket 连接
2. 启动心跳定时器
3. 启动 tick 定时器（如果配置）
4. 恢复订单状态（如果启用）
5. 运行事件循环

**示例**:
```zig
std.debug.print("Starting live trading...\n", .{});
try engine.start();
// 阻塞直到 stop() 被调用
```

### stop

停止实时交易引擎。

```zig
pub fn stop(self: *LiveTradingEngine) void
```

### restart

重启引擎（重新连接所有 WebSocket）。

```zig
pub fn restart(self: *LiveTradingEngine) !void
```

---

## WebSocket 管理

### connectWebSocket

手动连接 WebSocket。

```zig
pub fn connectWebSocket(
    self: *LiveTradingEngine,
    endpoint: WebSocketEndpoint,
) !*WebSocketConnection
```

### disconnectWebSocket

断开 WebSocket 连接。

```zig
pub fn disconnectWebSocket(
    self: *LiveTradingEngine,
    connection: *WebSocketConnection,
) void
```

### sendWebSocketMessage

发送 WebSocket 消息。

```zig
pub fn sendWebSocketMessage(
    self: *LiveTradingEngine,
    connection: *WebSocketConnection,
    message: []const u8,
) !void
```

### getConnectionStatus

获取连接状态。

```zig
pub fn getConnectionStatus(self: *LiveTradingEngine) []ConnectionStatus
```

---

## 定时器

### setTickInterval

设置 tick 间隔。

```zig
pub fn setTickInterval(self: *LiveTradingEngine, interval_ms: u64) void
```

### setHeartbeatInterval

设置心跳间隔。

```zig
pub fn setHeartbeatInterval(self: *LiveTradingEngine, interval_ms: u64) void
```

---

## 交易模式

### Event-Driven 模式

事件驱动，适合趋势策略：

```zig
// 订阅市场数据事件
try message_bus.subscribe("market_data.*", strategy.onMarketData);

// 策略处理事件
fn onMarketData(self: *Strategy, event: Event) void {
    const data = event.market_data;
    if (self.shouldBuy(data)) {
        self.submitBuyOrder(data.instrument_id);
    }
}
```

### Clock-Driven 模式

定时驱动，适合做市策略：

```zig
const config = LiveTradingConfig{
    .tick_interval_ms = 1000,  // 每秒 tick
};

// 订阅 tick 事件
try message_bus.subscribe("system.tick", strategy.onTick);

// 每秒更新报价
fn onTick(self: *Strategy, event: Event) void {
    self.updateQuotes();
}
```

---

## 发布的事件

LiveTradingEngine 通过 MessageBus 发布以下事件：

| 事件主题 | 事件类型 | 触发条件 |
|----------|----------|----------|
| `system.tick` | TickEvent | 定时 tick |
| `system.connected` | ConnectionEvent | WebSocket 连接成功 |
| `system.disconnected` | ConnectionEvent | WebSocket 断开 |
| `system.reconnecting` | ConnectionEvent | 正在重连 |
| `system.shutdown` | ShutdownEvent | 引擎停止 |

---

## 数据类型

### WebSocketConnection

```zig
pub const WebSocketConnection = struct {
    endpoint: WebSocketEndpoint,
    socket: xev.TCP,
    state: ConnectionState,
    reconnect_attempts: u32,
    last_message_time: i64,
};
```

### ConnectionState

```zig
pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    reconnecting,
    failed,
};
```

### ConnectionStatus

```zig
pub const ConnectionStatus = struct {
    endpoint: []const u8,
    state: ConnectionState,
    latency_ms: ?u64,
    messages_received: u64,
    last_error: ?[]const u8,
};
```

### TickEvent

```zig
pub const TickEvent = struct {
    timestamp: i64,
    tick_number: u64,
};
```

### ShutdownEvent

```zig
pub const ShutdownEvent = struct {
    reason: ShutdownReason,
    message: ?[]const u8,
};

pub const ShutdownReason = enum {
    user_request,
    error,
    signal,
    backtest_complete,
};
```

---

## 错误处理

### LiveTradingError

```zig
pub const LiveTradingError = error{
    ConnectionFailed,
    AllConnectionsFailed,
    WebSocketError,
    TlsError,
    Timeout,
    MaxReconnectAttempts,
    NotRunning,
    AlreadyRunning,
};
```

---

## 相关文档

- [功能概览](./README.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)

---

**版本**: v0.5.0
**状态**: 计划中
