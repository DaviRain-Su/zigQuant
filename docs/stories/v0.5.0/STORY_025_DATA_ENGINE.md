# Story 025: DataEngine - 数据引擎重构

**版本**: v0.5.0
**状态**: 计划中
**预计工期**: 1 周
**依赖**: Story 023 (MessageBus), Story 024 (Cache)

---

## 目标

重构数据引擎，将市场数据处理与事件发布解耦，通过 MessageBus 发布标准化事件。

## 背景

当前数据引擎存在的问题：
- 直接调用策略方法，耦合度高
- 无法支持多订阅者
- 缺乏统一的事件格式

参考 **NautilusTrader** 的 DataEngine：
- 数据源抽象 (WebSocket, REST, Historical)
- 统一事件发布
- 自动缓存更新

---

## 核心设计

### 架构

```
┌─────────────────────────────────────────────────────────────┐
│                      DataEngine                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                Data Sources                          │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
│  │  │ WebSocket│  │  REST    │  │Historical│          │   │
│  │  │  Feed    │  │  Feed    │  │  Feed    │          │   │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘          │   │
│  └───────┼─────────────┼─────────────┼──────────────────┘   │
│          │             │             │                       │
│          ▼             ▼             ▼                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Data Processor                          │   │
│  │  - Parse raw data                                    │   │
│  │  - Normalize format                                  │   │
│  │  - Apply transformations                             │   │
│  └───────────────────────────┬─────────────────────────┘   │
│                              │                              │
│                              ▼                              │
│  ┌────────────────────┐  ┌────────────────────┐           │
│  │       Cache        │  │    MessageBus      │           │
│  │  (update state)    │  │  (publish events)  │           │
│  └────────────────────┘  └────────────────────┘           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 接口定义

```zig
pub const DataEngine = struct {
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,

    // 数据源
    ws_feeds: StringHashMap(*WebSocketFeed),
    rest_feeds: StringHashMap(*RESTFeed),

    // 配置
    config: DataEngineConfig,

    /// 初始化
    pub fn init(
        allocator: Allocator,
        message_bus: *MessageBus,
        cache: *Cache,
        config: DataEngineConfig,
    ) !DataEngine {
        return .{
            .allocator = allocator,
            .message_bus = message_bus,
            .cache = cache,
            .ws_feeds = StringHashMap(*WebSocketFeed).init(allocator),
            .rest_feeds = StringHashMap(*RESTFeed).init(allocator),
            .config = config,
        };
    }

    // ========== 数据源管理 ==========

    /// 添加 WebSocket 数据源
    pub fn addWebSocketFeed(self: *DataEngine, feed: *WebSocketFeed) !void {
        try self.ws_feeds.put(feed.id, feed);
        feed.setDataHandler(self.onWebSocketData);
    }

    /// 添加 REST 数据源
    pub fn addRESTFeed(self: *DataEngine, feed: *RESTFeed) !void {
        try self.rest_feeds.put(feed.id, feed);
    }

    /// 订阅合约
    pub fn subscribe(self: *DataEngine, instrument_id: []const u8, data_type: DataType) !void {
        // 获取合适的数据源
        const feed = self.selectFeed(instrument_id) orelse return error.NoFeedAvailable;

        // 发送订阅请求
        try feed.subscribe(instrument_id, data_type);
    }

    /// 取消订阅
    pub fn unsubscribe(self: *DataEngine, instrument_id: []const u8, data_type: DataType) !void {
        const feed = self.selectFeed(instrument_id) orelse return;
        try feed.unsubscribe(instrument_id, data_type);
    }

    // ========== 数据处理 ==========

    /// 处理 WebSocket 数据
    fn onWebSocketData(self: *DataEngine, raw_data: []const u8) !void {
        // 1. 解析数据
        const message = try self.parseMessage(raw_data);

        switch (message.type) {
            .trade => try self.processTrade(message.data),
            .orderbook_snapshot => try self.processOrderbookSnapshot(message.data),
            .orderbook_delta => try self.processOrderbookDelta(message.data),
            .ticker => try self.processTicker(message.data),
        }
    }

    /// 处理交易数据
    fn processTrade(self: *DataEngine, data: TradeData) !void {
        // 更新缓存
        try self.cache.updateLastTrade(data.instrument_id, data);

        // 发布事件
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

    /// 处理订单簿快照
    fn processOrderbookSnapshot(self: *DataEngine, data: OrderbookSnapshot) !void {
        // 更新缓存中的订单簿
        try self.cache.setOrderbook(data.instrument_id, data);

        // 发布事件
        try self.message_bus.publish("orderbook." ++ data.instrument_id ++ ".snapshot", .{
            .orderbook_snapshot = .{
                .instrument_id = data.instrument_id,
                .bids = data.bids,
                .asks = data.asks,
                .timestamp = data.timestamp,
            },
        });
    }

    /// 处理订单簿增量
    fn processOrderbookDelta(self: *DataEngine, data: OrderbookDelta) !void {
        // 更新缓存中的订单簿
        try self.cache.updateOrderbook(data.instrument_id, data);

        // 发布事件
        try self.message_bus.publish("orderbook." ++ data.instrument_id ++ ".delta", .{
            .orderbook_delta = .{
                .instrument_id = data.instrument_id,
                .bids = data.bids,
                .asks = data.asks,
                .timestamp = data.timestamp,
            },
        });
    }

    /// 处理 Ticker 数据
    fn processTicker(self: *DataEngine, data: TickerData) !void {
        // 更新缓存
        try self.cache.updateTicker(data.instrument_id, data);

        // 发布市场数据事件
        try self.message_bus.publish("market_data." ++ data.instrument_id, .{
            .market_data = .{
                .instrument_id = data.instrument_id,
                .bid = data.bid,
                .ask = data.ask,
                .last = data.last,
                .volume_24h = data.volume_24h,
                .timestamp = data.timestamp,
            },
        });
    }

    // ========== 历史数据 ==========

    /// 加载历史 K 线数据
    pub fn loadHistoricalCandles(
        self: *DataEngine,
        instrument_id: []const u8,
        timeframe: Timeframe,
        start: i64,
        end: i64,
    ) ![]Candle {
        // 从 REST API 获取
        const feed = self.rest_feeds.get(instrument_id) orelse return error.NoFeedAvailable;
        return try feed.getCandles(instrument_id, timeframe, start, end);
    }

    /// 回放历史数据 (用于回测)
    pub fn replayHistoricalData(
        self: *DataEngine,
        candles: []const Candle,
        speed: f64,  // 回放速度倍数
    ) !void {
        for (candles) |candle| {
            // 发布事件
            try self.message_bus.publish("candle." ++ candle.instrument_id, .{
                .candle = .{
                    .instrument_id = candle.instrument_id,
                    .open = candle.open,
                    .high = candle.high,
                    .low = candle.low,
                    .close = candle.close,
                    .volume = candle.volume,
                    .timestamp = candle.timestamp,
                },
            });

            // 控制回放速度
            if (speed < 1000) {  // 不是最快速度
                const delay_ns: u64 = @intFromFloat(@as(f64, @floatFromInt(candle.duration_ns)) / speed);
                std.time.sleep(delay_ns);
            }
        }
    }

    // ========== 启动/停止 ==========

    /// 启动数据引擎
    pub fn start(self: *DataEngine) !void {
        // 启动所有 WebSocket 连接
        var ws_iter = self.ws_feeds.valueIterator();
        while (ws_iter.next()) |feed| {
            try feed.*.connect();
        }
    }

    /// 停止数据引擎
    pub fn stop(self: *DataEngine) void {
        // 断开所有连接
        var ws_iter = self.ws_feeds.valueIterator();
        while (ws_iter.next()) |feed| {
            feed.*.disconnect();
        }
    }

    pub fn deinit(self: *DataEngine) void {
        self.stop();
        self.ws_feeds.deinit();
        self.rest_feeds.deinit();
    }
};
```

---

## 数据类型

### DataType

```zig
pub const DataType = enum {
    trade,           // 成交数据
    orderbook,       // 订单簿
    ticker,          // 行情摘要
    candle,          // K 线数据
    funding_rate,    // 资金费率
};
```

### 市场数据事件

```zig
pub const TradeEvent = struct {
    instrument_id: []const u8,
    price: Decimal,
    quantity: Decimal,
    side: Side,
    timestamp: i64,
};

pub const OrderbookEvent = struct {
    instrument_id: []const u8,
    bids: []const PriceLevel,
    asks: []const PriceLevel,
    timestamp: i64,
};

pub const MarketDataEvent = struct {
    instrument_id: []const u8,
    bid: ?Decimal,
    ask: ?Decimal,
    last: ?Decimal,
    volume_24h: ?Decimal,
    timestamp: i64,
};

pub const CandleEvent = struct {
    instrument_id: []const u8,
    timeframe: Timeframe,
    open: Decimal,
    high: Decimal,
    low: Decimal,
    close: Decimal,
    volume: Decimal,
    timestamp: i64,
};
```

---

## 使用示例

### 实时交易模式

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化核心组件
    var message_bus = try MessageBus.init(allocator);
    defer message_bus.deinit();

    var cache = try Cache.init(allocator, &message_bus);
    defer cache.deinit();

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
    try message_bus.subscribe("orderbook.BTC-USDT.*", strategy.onOrderbook);

    // 启动数据引擎
    try data_engine.start();
}
```

### 回测模式

```zig
pub fn runBacktest(allocator: Allocator, candles: []const Candle) !BacktestResult {
    var message_bus = try MessageBus.init(allocator);
    defer message_bus.deinit();

    var cache = try Cache.init(allocator, &message_bus);
    defer cache.deinit();

    var data_engine = try DataEngine.init(allocator, &message_bus, &cache, .{});
    defer data_engine.deinit();

    // 策略订阅
    var strategy = try MyStrategy.init(allocator, &cache);
    try message_bus.subscribe("candle.*", strategy.onCandle);

    // 回放历史数据 (最快速度)
    try data_engine.replayHistoricalData(candles, std.math.inf);

    return strategy.getResult();
}
```

---

## Code Parity 设计

回测代码与实盘代码完全相同：

```zig
// 策略代码 - 回测和实盘都使用相同的代码
pub const MyStrategy = struct {
    cache: *Cache,
    message_bus: *MessageBus,

    pub fn onMarketData(self: *MyStrategy, event: Event) void {
        const data = event.market_data;

        // 查询仓位
        const position = self.cache.getPosition(data.instrument_id);

        // 生成信号
        if (self.shouldEnter(data)) {
            // 发送订单命令
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

区别仅在于：
- **回测**: DataEngine 回放历史数据
- **实盘**: DataEngine 接收实时 WebSocket 数据

---

## 测试计划

### 单元测试

| 测试 | 描述 |
|------|------|
| `test_process_trade` | 处理交易数据 |
| `test_process_orderbook` | 处理订单簿数据 |
| `test_event_publish` | 事件发布到 MessageBus |
| `test_cache_update` | 缓存自动更新 |
| `test_historical_replay` | 历史数据回放 |
| `test_no_memory_leak` | 内存泄漏检测 |

### 集成测试

| 测试 | 描述 |
|------|------|
| `test_websocket_integration` | WebSocket 数据源集成 |
| `test_strategy_subscription` | 策略订阅事件 |
| `test_backtest_replay` | 回测模式回放 |

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

tests/
└── data/
    └── engine_test.zig      # DataEngine 测试
```

---

## 验收标准

- [ ] 支持 WebSocket 实时数据源
- [ ] 支持 REST 历史数据源
- [ ] 通过 MessageBus 发布标准化事件
- [ ] 自动更新 Cache
- [ ] 支持历史数据回放 (回测模式)
- [ ] Code Parity: 策略代码回测/实盘通用
- [ ] 零内存泄漏
- [ ] 所有测试通过

---

## 相关文档

- [v0.5.0 Overview](./OVERVIEW.md)
- [Story 023: MessageBus](./STORY_023_MESSAGE_BUS.md)
- [Story 024: Cache](./STORY_024_CACHE.md)
- [Story 026: ExecutionEngine](./STORY_026_EXECUTION_ENGINE.md)

---

**版本**: v0.5.0
**状态**: 计划中
**创建时间**: 2025-12-27
