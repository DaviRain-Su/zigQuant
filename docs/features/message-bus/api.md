# MessageBus - API 参考

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 核心类型

### MessageBus

消息总线主结构体。

```zig
pub const MessageBus = struct {
    allocator: Allocator,
    subscribers: StringHashMap(ArrayList(Handler)),
    endpoints: StringHashMap(RequestHandler),

    // 类型定义
    pub const Handler = *const fn(Event) void;
    pub const RequestHandler = *const fn(Request) anyerror!Response;
};
```

### Event

事件联合类型。

```zig
pub const Event = union(enum) {
    // 市场数据事件
    market_data: MarketDataEvent,
    orderbook_update: OrderbookEvent,
    trade: TradeEvent,
    candle: CandleEvent,

    // 订单事件
    order_pending: OrderEvent,
    order_submitted: OrderEvent,
    order_accepted: OrderEvent,
    order_rejected: OrderRejectEvent,
    order_filled: OrderFillEvent,
    order_cancelled: OrderEvent,

    // 仓位事件
    position_opened: PositionEvent,
    position_updated: PositionEvent,
    position_closed: PositionEvent,

    // 账户事件
    account_updated: AccountEvent,

    // 系统事件
    tick: TickEvent,
    shutdown: ShutdownEvent,
};
```

---

## 初始化与销毁

### init

初始化 MessageBus。

```zig
pub fn init(allocator: Allocator) MessageBus
```

**参数**:
- `allocator`: 内存分配器

**返回**: MessageBus 实例

**示例**:
```zig
var bus = MessageBus.init(allocator);
defer bus.deinit();
```

### deinit

释放 MessageBus 资源。

```zig
pub fn deinit(self: *MessageBus) void
```

---

## Publish-Subscribe 模式

### publish

发布事件到指定主题。

```zig
pub fn publish(self: *MessageBus, topic: []const u8, event: Event) !void
```

**参数**:
- `topic`: 主题名称
- `event`: 要发布的事件

**错误**:
- `OutOfMemory`: 内存分配失败

**示例**:
```zig
try bus.publish("market_data.BTC-USDT", .{
    .market_data = .{
        .instrument_id = "BTC-USDT",
        .bid = 50000.0,
        .ask = 50001.0,
        .timestamp = std.time.milliTimestamp(),
    },
});
```

### subscribe

订阅指定主题。

```zig
pub fn subscribe(self: *MessageBus, topic: []const u8, handler: Handler) !void
```

**参数**:
- `topic`: 主题名称（支持通配符 `*`）
- `handler`: 事件处理函数

**示例**:
```zig
try bus.subscribe("market_data.BTC-USDT", onMarketData);
try bus.subscribe("market_data.*", onAllMarketData);  // 通配符
try bus.subscribe("order.*", onOrderEvent);
```

### unsubscribe

取消订阅。

```zig
pub fn unsubscribe(self: *MessageBus, topic: []const u8, handler: Handler) void
```

**参数**:
- `topic`: 主题名称
- `handler`: 要移除的处理函数

---

## Request-Response 模式

### register

注册请求端点。

```zig
pub fn register(self: *MessageBus, endpoint: []const u8, handler: RequestHandler) !void
```

**参数**:
- `endpoint`: 端点名称
- `handler`: 请求处理函数

**示例**:
```zig
try bus.register("order.validate", validateOrder);
try bus.register("risk.check", checkRisk);
```

### request

发送请求并等待响应。

```zig
pub fn request(self: *MessageBus, endpoint: []const u8, req: Request) !Response
```

**参数**:
- `endpoint`: 端点名称
- `req`: 请求数据

**返回**: Response

**错误**:
- `EndpointNotFound`: 端点不存在
- 处理函数返回的错误

**示例**:
```zig
const response = try bus.request("order.validate", .{
    .validate_order = .{
        .instrument_id = "BTC-USDT",
        .side = .buy,
        .quantity = 0.1,
    },
});
```

---

## Command 模式

### send

发送命令（Fire-and-Forget）。

```zig
pub fn send(self: *MessageBus, command: Command) void
```

**参数**:
- `command`: 命令数据

**示例**:
```zig
bus.send(.{
    .submit_order = .{
        .instrument_id = "BTC-USDT",
        .side = .buy,
        .quantity = 0.1,
        .price = 50000.0,
    },
});
```

---

## 事件类型详解

### MarketDataEvent

```zig
pub const MarketDataEvent = struct {
    instrument_id: []const u8,
    timestamp: i64,
    bid: ?Decimal,
    ask: ?Decimal,
    last: ?Decimal,
    volume_24h: ?Decimal,
};
```

### OrderEvent

```zig
pub const OrderEvent = struct {
    order_id: []const u8,
    client_order_id: []const u8,
    instrument_id: []const u8,
    side: Side,
    order_type: OrderType,
    quantity: Decimal,
    price: ?Decimal,
    status: OrderStatus,
    timestamp: i64,
};
```

### OrderFillEvent

```zig
pub const OrderFillEvent = struct {
    order: OrderEvent,
    fill_price: Decimal,
    fill_quantity: Decimal,
    commission: Decimal,
};
```

### PositionEvent

```zig
pub const PositionEvent = struct {
    instrument_id: []const u8,
    side: Side,
    quantity: Decimal,
    entry_price: Decimal,
    unrealized_pnl: Decimal,
    timestamp: i64,
};
```

---

## 主题命名规范

| 前缀 | 描述 | 示例 |
|------|------|------|
| `market_data.` | 市场数据 | `market_data.BTC-USDT` |
| `orderbook.` | 订单簿 | `orderbook.BTC-USDT.snapshot` |
| `trade.` | 成交数据 | `trade.BTC-USDT` |
| `order.` | 订单事件 | `order.submitted` |
| `position.` | 仓位事件 | `position.BTC-USDT` |
| `account.` | 账户事件 | `account.main` |
| `system.` | 系统事件 | `system.tick` |

---

## 相关文档

- [功能概览](./README.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)

---

**版本**: v0.5.0
**状态**: 计划中
