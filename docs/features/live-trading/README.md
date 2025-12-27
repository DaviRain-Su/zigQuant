# LiveTrading - 实时交易引擎

**版本**: v0.5.0
**状态**: 计划中
**层级**: Application Layer
**依赖**: MessageBus, Cache, DataEngine, ExecutionEngine, libxev

---

## 功能概述

LiveTrading 是 zigQuant 的实时交易引擎，基于 libxev 事件循环实现高性能异步 I/O，支持 WebSocket 实时数据和订单执行。

### 设计目标

- **高性能**: 基于 libxev 和 io_uring
- **低延迟**: WebSocket 延迟 < 5ms
- **可靠性**: 自动重连和订单恢复
- **灵活性**: 支持 Event-Driven 和 Clock-Driven 模式

---

## libxev 集成

### 为什么选择 libxev

| 特性 | 说明 |
|------|------|
| **Proactor 模式** | 工作完成通知（适合交易系统） |
| **io_uring 支持** | Linux 最快 I/O |
| **零运行时分配** | 性能可预测 |
| **Zig 原生** | 完美集成 |
| **生产就绪** | Ghostty 终端正在使用 |

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
│  ┌────────────────────┐  ┌────────────────────┐            │
│  │    DataEngine     │  │  ExecutionEngine   │            │
│  └────────────────────┘  └────────────────────┘            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 核心 API

### LiveTradingEngine

```zig
const xev = @import("xev");

pub const LiveTradingEngine = struct {
    /// 初始化
    pub fn init(
        allocator: Allocator,
        message_bus: *MessageBus,
        cache: *Cache,
        config: LiveTradingConfig,
    ) !LiveTradingEngine;

    /// 设置组件
    pub fn setDataEngine(self: *LiveTradingEngine, engine: *DataEngine) void;
    pub fn setExecutionEngine(self: *LiveTradingEngine, engine: *ExecutionEngine) void;

    /// 启动交易引擎
    pub fn start(self: *LiveTradingEngine) !void;

    /// 停止交易引擎
    pub fn stop(self: *LiveTradingEngine) void;

    /// 清理
    pub fn deinit(self: *LiveTradingEngine) void;
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
};
```

---

## 交易模式

### Event-Driven 模式

适合趋势策略，事件触发执行：

```zig
// 订阅市场数据事件
try message_bus.subscribe("market_data.*", strategy.onMarketData);
try message_bus.subscribe("orderbook.*", strategy.onOrderbook);

// 事件到来时触发策略
fn onMarketData(event: Event) void {
    // 策略逻辑
}
```

### Clock-Driven 模式

适合做市策略，定时执行：

```zig
const config = LiveTradingConfig{
    .tick_interval_ms = 1000,  // 每秒 Tick
};

// 每秒触发
try message_bus.subscribe("system.tick", strategy.onTick);

fn onTick(event: Event) void {
    // 更新报价逻辑
    updateQuotes();
}
```

---

## 使用示例

### 完整实时交易

```zig
const std = @import("std");
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
            .tick_interval_ms = 1000,  // 每秒 Tick
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

## WebSocket 连接

### 自动重连

采用指数退避策略：

```
初次重连: 1 秒
第 2 次: 2 秒
第 3 次: 4 秒
第 4 次: 8 秒
...
最大延迟: 60 秒
```

### 心跳机制

定时发送 Ping 保持连接活跃：

```zig
// 每 30 秒发送心跳
heartbeat_timer.set(loop, 30000, onHeartbeat);

fn onHeartbeat() {
    for (ws_connections) |conn| {
        conn.sendPing();
    }
}
```

---

## 性能指标

| 指标 | 目标 |
|------|------|
| WebSocket 延迟 | < 5ms |
| 订单提交延迟 | < 10ms |
| 消息吞吐量 | > 5000/s |
| CPU 使用率 | < 20% (空闲) |
| 内存分配 | 零运行时 |

---

## 文件结构

```
src/trading/
├── live_engine.zig          # LiveTradingEngine 实现
├── websocket.zig            # WebSocket 连接封装
├── timer.zig                # 定时器封装
└── config.zig               # 配置

examples/
└── 11_live_trading.zig      # 实时交易示例
```

---

## 相关文档

- [Story 027: libxev Integration](../../stories/v0.5.0/STORY_027_LIBXEV_INTEGRATION.md)
- [v0.5.0 Overview](../../stories/v0.5.0/OVERVIEW.md)
- [libxev 集成方案](../../architecture/LIBXEV_INTEGRATION.md)
- [DataEngine](../data-engine/README.md)
- [ExecutionEngine](../execution-engine/README.md)

---

**版本**: v0.5.0
**状态**: 计划中
**创建时间**: 2025-12-27
