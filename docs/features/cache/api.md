# Cache - API 参考

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 核心类型

### Cache

高性能状态缓存主结构体。

```zig
pub const Cache = struct {
    allocator: Allocator,
    message_bus: *MessageBus,

    // 缓存存储
    orders: StringHashMap(Order),
    positions: StringHashMap(Position),
    accounts: StringHashMap(Account),
    instruments: StringHashMap(Instrument),
    quotes: StringHashMap(Quote),
};
```

### CacheConfig

```zig
pub const CacheConfig = struct {
    /// 是否自动订阅 MessageBus 事件
    auto_subscribe: bool = true,

    /// 订单历史保留数量
    order_history_limit: usize = 10000,

    /// 是否启用快照
    enable_snapshots: bool = false,
};
```

---

## 初始化与销毁

### init

初始化 Cache。

```zig
pub fn init(
    allocator: Allocator,
    message_bus: *MessageBus,
    config: CacheConfig,
) !Cache
```

**参数**:
- `allocator`: 内存分配器
- `message_bus`: MessageBus 实例引用
- `config`: 缓存配置

**返回**: Cache 实例

**示例**:
```zig
var cache = try Cache.init(
    allocator,
    &message_bus,
    .{ .auto_subscribe = true },
);
defer cache.deinit();
```

### deinit

释放 Cache 资源。

```zig
pub fn deinit(self: *Cache) void
```

---

## 订单缓存

### getOrder

获取订单（O(1) 查找）。

```zig
pub fn getOrder(self: *Cache, order_id: []const u8) ?*const Order
```

**参数**:
- `order_id`: 订单 ID

**返回**: 订单指针，不存在则返回 null

**示例**:
```zig
if (cache.getOrder("order-123")) |order| {
    std.debug.print("Order status: {}\n", .{order.status});
}
```

### getOrdersByInstrument

获取指定交易对的所有订单。

```zig
pub fn getOrdersByInstrument(
    self: *Cache,
    instrument_id: []const u8,
) ![]*const Order
```

**示例**:
```zig
const orders = try cache.getOrdersByInstrument("BTC-USDT");
for (orders) |order| {
    std.debug.print("Order: {s}\n", .{order.id});
}
```

### getOpenOrders

获取所有未成交订单。

```zig
pub fn getOpenOrders(self: *Cache) ![]*const Order
```

### updateOrder

更新订单状态（内部使用）。

```zig
pub fn updateOrder(self: *Cache, order: Order) !void
```

---

## 仓位缓存

### getPosition

获取仓位（O(1) 查找）。

```zig
pub fn getPosition(self: *Cache, instrument_id: []const u8) ?*const Position
```

**参数**:
- `instrument_id`: 交易对 ID

**返回**: 仓位指针，不存在则返回 null

**示例**:
```zig
if (cache.getPosition("BTC-USDT")) |position| {
    std.debug.print("Position size: {}\n", .{position.quantity});
    std.debug.print("Unrealized PnL: {}\n", .{position.unrealized_pnl});
}
```

### getAllPositions

获取所有仓位。

```zig
pub fn getAllPositions(self: *Cache) ![]*const Position
```

### getPositionValue

获取仓位价值。

```zig
pub fn getPositionValue(self: *Cache, instrument_id: []const u8) ?Decimal
```

### getTotalPositionValue

获取总仓位价值。

```zig
pub fn getTotalPositionValue(self: *Cache) Decimal
```

---

## 账户缓存

### getAccount

获取账户信息（O(1) 查找）。

```zig
pub fn getAccount(self: *Cache, account_id: []const u8) ?*const Account
```

**示例**:
```zig
if (cache.getAccount("main")) |account| {
    std.debug.print("Balance: {}\n", .{account.balance});
    std.debug.print("Available: {}\n", .{account.available});
}
```

### getDefaultAccount

获取默认账户。

```zig
pub fn getDefaultAccount(self: *Cache) ?*const Account
```

### getAccountEquity

获取账户权益。

```zig
pub fn getAccountEquity(self: *Cache, account_id: []const u8) ?Decimal
```

---

## 行情缓存

### getQuote

获取最新报价（O(1) 查找）。

```zig
pub fn getQuote(self: *Cache, instrument_id: []const u8) ?*const Quote
```

**示例**:
```zig
if (cache.getQuote("BTC-USDT")) |quote| {
    std.debug.print("Bid: {} Ask: {}\n", .{quote.bid, quote.ask});
    std.debug.print("Spread: {}\n", .{quote.ask - quote.bid});
}
```

### getBidAsk

获取买卖价。

```zig
pub fn getBidAsk(self: *Cache, instrument_id: []const u8) ?struct { bid: Decimal, ask: Decimal }
```

### getMidPrice

获取中间价。

```zig
pub fn getMidPrice(self: *Cache, instrument_id: []const u8) ?Decimal
```

---

## 交易对缓存

### getInstrument

获取交易对信息。

```zig
pub fn getInstrument(self: *Cache, instrument_id: []const u8) ?*const Instrument
```

**示例**:
```zig
if (cache.getInstrument("BTC-USDT")) |inst| {
    std.debug.print("Min size: {}\n", .{inst.min_order_size});
    std.debug.print("Tick size: {}\n", .{inst.tick_size});
}
```

### getAllInstruments

获取所有交易对。

```zig
pub fn getAllInstruments(self: *Cache) ![]*const Instrument
```

---

## 快照与恢复

### takeSnapshot

创建缓存快照。

```zig
pub fn takeSnapshot(self: *Cache) !CacheSnapshot
```

### restoreFromSnapshot

从快照恢复。

```zig
pub fn restoreFromSnapshot(self: *Cache, snapshot: CacheSnapshot) !void
```

---

## 数据类型

### Order

```zig
pub const Order = struct {
    id: []const u8,
    client_order_id: []const u8,
    instrument_id: []const u8,
    side: Side,
    order_type: OrderType,
    quantity: Decimal,
    filled_quantity: Decimal,
    price: ?Decimal,
    status: OrderStatus,
    created_at: i64,
    updated_at: i64,
};
```

### Position

```zig
pub const Position = struct {
    instrument_id: []const u8,
    side: Side,
    quantity: Decimal,
    entry_price: Decimal,
    mark_price: Decimal,
    unrealized_pnl: Decimal,
    realized_pnl: Decimal,
    leverage: Decimal,
    liquidation_price: ?Decimal,
    updated_at: i64,
};
```

### Account

```zig
pub const Account = struct {
    id: []const u8,
    balance: Decimal,
    available: Decimal,
    margin_used: Decimal,
    unrealized_pnl: Decimal,
    realized_pnl: Decimal,
    updated_at: i64,
};
```

### Quote

```zig
pub const Quote = struct {
    instrument_id: []const u8,
    bid: Decimal,
    ask: Decimal,
    bid_size: Decimal,
    ask_size: Decimal,
    last: ?Decimal,
    volume_24h: ?Decimal,
    timestamp: i64,
};
```

---

## MessageBus 集成

Cache 自动订阅以下事件并更新状态：

| 事件 | 更新内容 |
|------|----------|
| `order.*` | 订单状态 |
| `position.*` | 仓位信息 |
| `account.*` | 账户余额 |
| `market_data.*` | 报价信息 |

---

## 相关文档

- [功能概览](./README.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)

---

**版本**: v0.5.0
**状态**: 计划中
