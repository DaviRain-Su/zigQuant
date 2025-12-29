# LiveTrading - 实时交易引擎

**版本**: v0.9.1 (原 v0.5.0)
**状态**: ✅ 已完成
**层级**: Application Layer
**依赖**: MessageBus, Cache, DataEngine, ExecutionEngine, EngineManager

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
├── live_engine.zig          # LiveTradingEngine 核心实现
├── websocket.zig            # WebSocket 连接封装
├── timer.zig                # 定时器封装
└── config.zig               # 配置

src/engine/
├── manager.zig              # EngineManager (管理所有 runners)
├── mod.zig                  # 模块导出
└── runners/
    ├── live_runner.zig      # LiveRunner (v0.9.1 新增)
    ├── strategy_runner.zig  # StrategyRunner
    └── backtest_runner.zig  # BacktestRunner

examples/
└── 17_paper_trading.zig     # Paper Trading 示例
```

---

## LiveRunner (v0.9.1 新增)

### 概述

`LiveRunner` 是 v0.9.1 新增的统一实盘交易封装，包装 `LiveTradingEngine` 并提供线程安全的生命周期管理。它由 `EngineManager` 统一管理，并通过 REST API (`/api/v2/live`) 暴露控制接口。

### 核心类型

```zig
// src/engine/runners/live_runner.zig

pub const LiveRequest = struct {
    session_id: []const u8,       // 唯一会话标识
    strategy_type: []const u8,    // 策略类型
    exchange: []const u8,         // 交易所名称
    symbol: []const u8,           // 交易对
    mode: LiveTradingMode,        // paper 或 live
    initial_capital: f64,         // 初始资金
    params: ?std.json.ObjectMap,  // 策略参数
};

pub const LiveStatus = enum {
    stopped,
    starting,
    running,
    paused,
    stopping,
    @"error",
};

pub const LiveStats = struct {
    ticks_processed: u64,
    orders_placed: u32,
    orders_filled: u32,
    current_pnl: f64,
    start_time: i64,
    uptime_seconds: u64,
};

pub const LiveRunner = struct {
    pub fn init(allocator: Allocator, request: LiveRequest, engine: *LiveTradingEngine) !*LiveRunner;
    pub fn start(self: *LiveRunner) !void;
    pub fn stop(self: *LiveRunner) void;
    pub fn pause(self: *LiveRunner) !void;
    pub fn resume(self: *LiveRunner) !void;
    pub fn getStatus(self: *LiveRunner) LiveStatus;
    pub fn getStats(self: *LiveRunner) LiveStats;
    pub fn deinit(self: *LiveRunner) void;
};
```

### 使用示例

```zig
// 通过 EngineManager 管理 LiveRunner
var manager = try EngineManager.init(allocator);
defer manager.deinit();

// 启动实盘会话
try manager.startLive(.{
    .session_id = "btc_dual_ma",
    .strategy_type = "dual_ma",
    .exchange = "hyperliquid",
    .symbol = "BTC",
    .mode = .paper,
    .initial_capital = 10000.0,
    .params = null,
});

// 查询状态
const status = manager.getLiveStatus("btc_dual_ma");
const stats = manager.getLiveStats("btc_dual_ma");

// 暂停/恢复
try manager.pauseLive("btc_dual_ma");
try manager.resumeLive("btc_dual_ma");

// 停止
try manager.stopLive("btc_dual_ma");
```

### REST API

```bash
# 列出所有会话
GET /api/v2/live

# 启动新会话
POST /api/v2/live
{
  "session_id": "btc_dual_ma",
  "strategy_type": "dual_ma",
  "exchange": "hyperliquid",
  "symbol": "BTC",
  "mode": "paper",
  "initial_capital": 10000.0
}

# 会话详情
GET /api/v2/live/:id

# 停止会话
DELETE /api/v2/live/:id

# 暂停/恢复
POST /api/v2/live/:id/pause
POST /api/v2/live/:id/resume
```

---

## 架构对比

### LiveTradingEngine vs LiveRunner vs PaperTradingEngine

| 组件 | 文件位置 | 用途 | 管理方式 |
|------|----------|------|----------|
| **LiveTradingEngine** | `src/trading/live_engine.zig` | 核心实盘交易逻辑 | 底层引擎 |
| **LiveRunner** | `src/engine/runners/live_runner.zig` | 统一封装，线程安全 | EngineManager |
| **PaperTradingEngine** | `src/trading/paper_trading.zig` | 独立模拟交易 | 独立使用 |

---

## 相关文档

- [Story 027: libxev Integration](../../stories/v0.5.0/STORY_027_LIBXEV_INTEGRATION.md)
- [Story 047: REST API](../../stories/v1.0.0/STORY_047_REST_API.md)
- [Paper Trading](../paper-trading/README.md)
- [DataEngine](../data-engine/README.md)

---

**版本**: v0.9.1
**状态**: ✅ 已完成
**最后更新**: 2025-12-29
