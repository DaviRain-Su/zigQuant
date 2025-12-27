# DataEngine - API 参考

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 核心类型

### DataEngine

数据引擎主结构体，统一回测和实盘数据接口。

```zig
pub const DataEngine = struct {
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    mode: DataMode,

    // 数据源
    sources: ArrayList(DataSource),

    // 当前状态
    current_timestamp: i64,
    is_running: bool,
};
```

### DataMode

```zig
pub const DataMode = enum {
    /// 回测模式 - 读取历史数据
    backtest,

    /// 实盘模式 - 接收实时数据
    live,
};
```

### DataSource

```zig
pub const DataSource = union(enum) {
    /// CSV 文件数据源
    csv: CsvDataSource,

    /// WebSocket 数据源
    websocket: WebSocketDataSource,

    /// 自定义数据源
    custom: *IDataSource,
};
```

---

## 初始化与销毁

### init

初始化 DataEngine。

```zig
pub fn init(
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    config: DataEngineConfig,
) !DataEngine
```

**参数**:
- `allocator`: 内存分配器
- `message_bus`: MessageBus 实例引用
- `cache`: Cache 实例引用
- `config`: 数据引擎配置

**返回**: DataEngine 实例

**示例**:
```zig
var data_engine = try DataEngine.init(
    allocator,
    &message_bus,
    &cache,
    .{ .mode = .backtest },
);
defer data_engine.deinit();
```

### deinit

释放 DataEngine 资源。

```zig
pub fn deinit(self: *DataEngine) void
```

---

## 数据源管理

### addSource

添加数据源。

```zig
pub fn addSource(self: *DataEngine, source: DataSource) !void
```

**示例**:
```zig
// 添加 CSV 数据源
try data_engine.addSource(.{
    .csv = .{
        .path = "data/BTC-USDT-1m.csv",
        .instrument_id = "BTC-USDT",
        .timeframe = .m1,
    },
});

// 添加 WebSocket 数据源
try data_engine.addSource(.{
    .websocket = .{
        .url = "wss://api.hyperliquid.xyz/ws",
        .instrument_id = "BTC-USDT",
    },
});
```

### removeSource

移除数据源。

```zig
pub fn removeSource(self: *DataEngine, source_id: []const u8) void
```

### getSources

获取所有数据源。

```zig
pub fn getSources(self: *DataEngine) []const DataSource
```

---

## 数据订阅

### subscribe

订阅交易对数据。

```zig
pub fn subscribe(
    self: *DataEngine,
    instrument_id: []const u8,
    data_types: DataTypes,
) !void
```

**参数**:
- `instrument_id`: 交易对 ID
- `data_types`: 订阅的数据类型

**示例**:
```zig
try data_engine.subscribe("BTC-USDT", .{
    .trades = true,
    .orderbook = true,
    .candles = .{ .m1 = true, .h1 = true },
});
```

### unsubscribe

取消订阅。

```zig
pub fn unsubscribe(self: *DataEngine, instrument_id: []const u8) void
```

### DataTypes

```zig
pub const DataTypes = struct {
    /// 逐笔成交
    trades: bool = false,

    /// 订单簿
    orderbook: bool = false,

    /// K线数据
    candles: CandleSubscription = .{},

    /// 行情快照
    quotes: bool = false,
};

pub const CandleSubscription = struct {
    m1: bool = false,
    m5: bool = false,
    m15: bool = false,
    h1: bool = false,
    h4: bool = false,
    d1: bool = false,
};
```

---

## 运行控制

### start

启动数据引擎。

```zig
pub fn start(self: *DataEngine) !void
```

**说明**:
- 回测模式: 开始按时间顺序回放历史数据
- 实盘模式: 建立 WebSocket 连接，开始接收数据

### stop

停止数据引擎。

```zig
pub fn stop(self: *DataEngine) void
```

### pause / resume

暂停/恢复数据流。

```zig
pub fn pause(self: *DataEngine) void
pub fn resume(self: *DataEngine) void
```

---

## 回测专用 API

### setTimeRange

设置回测时间范围。

```zig
pub fn setTimeRange(
    self: *DataEngine,
    start_time: i64,
    end_time: i64,
) void
```

**示例**:
```zig
data_engine.setTimeRange(
    1704067200000, // 2024-01-01 00:00:00
    1706745600000, // 2024-02-01 00:00:00
);
```

### setPlaybackSpeed

设置回放速度（回测模式）。

```zig
pub fn setPlaybackSpeed(self: *DataEngine, speed: f64) void
```

**参数**:
- `speed`: 回放速度倍数 (1.0 = 实时, 0 = 最快)

### step

单步执行（调试用）。

```zig
pub fn step(self: *DataEngine) !?Event
```

---

## 数据查询

### getHistoricalBars

获取历史 K 线数据。

```zig
pub fn getHistoricalBars(
    self: *DataEngine,
    instrument_id: []const u8,
    timeframe: Timeframe,
    count: usize,
) ![]const Bar
```

**示例**:
```zig
const bars = try data_engine.getHistoricalBars("BTC-USDT", .h1, 100);
for (bars) |bar| {
    std.debug.print("Close: {}\n", .{bar.close});
}
```

### getCurrentBar

获取当前 K 线。

```zig
pub fn getCurrentBar(
    self: *DataEngine,
    instrument_id: []const u8,
    timeframe: Timeframe,
) ?*const Bar
```

### getOrderbook

获取当前订单簿。

```zig
pub fn getOrderbook(
    self: *DataEngine,
    instrument_id: []const u8,
) ?*const Orderbook
```

---

## 配置

### DataEngineConfig

```zig
pub const DataEngineConfig = struct {
    /// 数据模式
    mode: DataMode = .backtest,

    /// 回测开始时间
    start_time: ?i64 = null,

    /// 回测结束时间
    end_time: ?i64 = null,

    /// 回放速度 (0 = 最快)
    playback_speed: f64 = 0,

    /// 是否预加载数据
    preload_data: bool = true,

    /// 数据缓冲区大小
    buffer_size: usize = 10000,
};
```

---

## 数据类型

### Bar

```zig
pub const Bar = struct {
    instrument_id: []const u8,
    timestamp: i64,
    open: Decimal,
    high: Decimal,
    low: Decimal,
    close: Decimal,
    volume: Decimal,
    turnover: ?Decimal,
};
```

### Trade

```zig
pub const Trade = struct {
    instrument_id: []const u8,
    timestamp: i64,
    price: Decimal,
    quantity: Decimal,
    side: Side,
    trade_id: ?[]const u8,
};
```

### Orderbook

```zig
pub const Orderbook = struct {
    instrument_id: []const u8,
    timestamp: i64,
    bids: []const Level,
    asks: []const Level,

    pub const Level = struct {
        price: Decimal,
        quantity: Decimal,
    };
};
```

---

## 事件发布

DataEngine 通过 MessageBus 发布以下事件：

| 事件主题 | 事件类型 | 触发条件 |
|----------|----------|----------|
| `market_data.<instrument_id>` | MarketDataEvent | 行情更新 |
| `trade.<instrument_id>` | TradeEvent | 成交发生 |
| `orderbook.<instrument_id>` | OrderbookEvent | 订单簿更新 |
| `candle.<instrument_id>.<timeframe>` | CandleEvent | K线完成 |
| `system.tick` | TickEvent | 每个时间步 |

---

## 相关文档

- [功能概览](./README.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)

---

**版本**: v0.5.0
**状态**: 计划中
