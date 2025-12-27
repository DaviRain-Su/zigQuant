# DataEngine - 数据引擎

**版本**: v0.5.0
**状态**: 计划中
**层级**: Data Layer
**依赖**: MessageBus, Cache

---

## 功能概述

DataEngine 是 zigQuant 的数据引擎，负责接收、处理和分发市场数据，实现回测与实盘代码的统一 (Code Parity)。

### 设计目标

参考 **NautilusTrader** 的 DataEngine 设计：

- **统一接口**: 回测和实盘使用相同的策略代码
- **多数据源**: 支持 WebSocket、REST、历史数据
- **事件发布**: 通过 MessageBus 分发标准化事件
- **自动缓存**: 自动更新 Cache 状态

---

## 核心功能

### 数据源类型

| 数据源 | 描述 | 模式 |
|--------|------|------|
| **WebSocketFeed** | 实时 WebSocket 数据 | 实盘 |
| **RESTFeed** | REST API 数据 | 实盘/历史 |
| **HistoricalFeed** | 历史数据文件 | 回测 |

### 数据类型

| 类型 | 描述 |
|------|------|
| **Trade** | 成交数据 |
| **Orderbook** | 订单簿数据 |
| **Ticker** | 行情摘要 |
| **Candle** | K 线数据 |

---

## 核心 API

### DataEngine

```zig
pub const DataEngine = struct {
    /// 初始化
    pub fn init(
        allocator: Allocator,
        message_bus: *MessageBus,
        cache: *Cache,
        config: DataEngineConfig,
    ) !DataEngine;

    // ========== 数据源管理 ==========
    pub fn addWebSocketFeed(self: *DataEngine, feed: *WebSocketFeed) !void;
    pub fn addRESTFeed(self: *DataEngine, feed: *RESTFeed) !void;

    // ========== 订阅管理 ==========
    pub fn subscribe(self: *DataEngine, instrument_id: []const u8, data_type: DataType) !void;
    pub fn unsubscribe(self: *DataEngine, instrument_id: []const u8, data_type: DataType) !void;

    // ========== 历史数据 ==========
    pub fn loadHistoricalCandles(
        self: *DataEngine,
        instrument_id: []const u8,
        timeframe: Timeframe,
        start: i64,
        end: i64,
    ) ![]Candle;

    /// 回放历史数据 (用于回测)
    pub fn replayHistoricalData(
        self: *DataEngine,
        candles: []const Candle,
        speed: f64,
    ) !void;

    // ========== 生命周期 ==========
    pub fn start(self: *DataEngine) !void;
    pub fn stop(self: *DataEngine) void;
    pub fn deinit(self: *DataEngine) void;
};
```

---

## Code Parity 设计

策略代码在回测和实盘模式下完全相同：

```zig
// 策略代码 - 回测和实盘通用
pub const MyStrategy = struct {
    cache: *Cache,
    message_bus: *MessageBus,

    pub fn onMarketData(self: *MyStrategy, event: Event) void {
        const data = event.market_data;

        // 查询仓位
        const position = self.cache.getPosition(data.instrument_id);

        // 生成信号
        if (self.shouldEnter(data)) {
            self.message_bus.send(.{
                .submit_order = .{
                    .instrument_id = data.instrument_id,
                    .side = .buy,
                    .quantity = self.calculateSize(),
                },
            });
        }
    }
};
```

**区别仅在于数据来源**：
- **回测**: `DataEngine.replayHistoricalData(candles)`
- **实盘**: `DataEngine` 接收实时 WebSocket 数据

---

## 事件发布

DataEngine 通过 MessageBus 发布标准化事件：

```zig
// 处理交易数据
fn processTrade(self: *DataEngine, data: TradeData) !void {
    // 1. 更新缓存
    try self.cache.updateLastTrade(data.instrument_id, data);

    // 2. 发布事件
    try self.message_bus.publish("trade." ++ data.instrument_id, .{
        .trade = .{
            .instrument_id = data.instrument_id,
            .price = data.price,
            .quantity = data.quantity,
            .side = data.side,
            .timestamp = data.timestamp,
        },
    });
}
```

---

## 使用示例

### 实时交易模式

```zig
// 创建数据引擎
var data_engine = try DataEngine.init(allocator, &message_bus, &cache, .{});
defer data_engine.deinit();

// 添加 Hyperliquid WebSocket 数据源
var hl_feed = try HyperliquidWebSocketFeed.init(allocator, .mainnet);
try data_engine.addWebSocketFeed(&hl_feed);

// 订阅 BTC-USDT
try data_engine.subscribe("BTC-USDT", .orderbook);
try data_engine.subscribe("BTC-USDT", .trade);

// 策略订阅事件
try message_bus.subscribe("trade.BTC-USDT", strategy.onTrade);

// 启动
try data_engine.start();
```

### 回测模式

```zig
// 创建数据引擎
var data_engine = try DataEngine.init(allocator, &message_bus, &cache, .{});
defer data_engine.deinit();

// 策略订阅事件
try message_bus.subscribe("candle.*", strategy.onCandle);

// 回放历史数据 (最快速度)
try data_engine.replayHistoricalData(candles, std.math.inf);
```

---

## 性能指标

| 指标 | 目标 |
|------|------|
| 数据处理延迟 | < 1ms |
| 事件发布延迟 | < 100μs |
| 吞吐量 | > 10,000 msg/s |

---

## 文件结构

```
src/data/
├── engine.zig               # DataEngine 实现
├── feeds/
│   ├── websocket_feed.zig   # WebSocket 数据源
│   ├── rest_feed.zig        # REST 数据源
│   └── historical_feed.zig  # 历史数据源
├── processors/
│   ├── trade_processor.zig  # 交易数据处理
│   ├── orderbook_processor.zig  # 订单簿处理
│   └── candle_processor.zig # K 线处理
└── types.zig                # 数据类型定义
```

---

## 相关文档

- [Story 025: DataEngine](../../stories/v0.5.0/STORY_025_DATA_ENGINE.md)
- [v0.5.0 Overview](../../stories/v0.5.0/OVERVIEW.md)
- [MessageBus](../message-bus/README.md)
- [Cache](../cache/README.md)

---

**版本**: v0.5.0
**状态**: 计划中
**创建时间**: 2025-12-27
