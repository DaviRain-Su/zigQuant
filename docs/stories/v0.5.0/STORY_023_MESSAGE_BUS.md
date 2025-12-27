# Story 023: MessageBus - 消息总线系统

**版本**: v0.5.0
**状态**: 计划中
**预计工期**: 1 周
**依赖**: 无

---

## 目标

实现单线程高效消息传递系统，作为 zigQuant 事件驱动架构的核心基础设施。

## 背景

参考 **NautilusTrader** 的 MessageBus 设计：
- 单线程执行，避免锁和线程切换开销
- 支持 Pub/Sub、Request/Response、Command 三种模式
- 解耦系统组件，提高可扩展性

---

## 核心设计

### 消息模式

```
┌─────────────────────────────────────────────────────────────┐
│                      MessageBus                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Publish-Subscribe (一对多)                              │
│     Publisher ──→ Topic ──→ Subscriber 1                   │
│                        ├──→ Subscriber 2                   │
│                        └──→ Subscriber N                   │
│                                                              │
│  2. Request-Response (一对一)                               │
│     Requester ──→ Endpoint ──→ Handler ──→ Response        │
│                                                              │
│  3. Command (Fire-and-Forget)                               │
│     Sender ──→ Command ──→ Executor                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 接口定义

```zig
pub const MessageBus = struct {
    allocator: Allocator,
    subscribers: StringHashMap(ArrayList(Handler)),
    endpoints: StringHashMap(RequestHandler),

    pub const Handler = *const fn(Event) void;
    pub const RequestHandler = *const fn(Request) anyerror!Response;

    /// 初始化
    pub fn init(allocator: Allocator) MessageBus {
        return .{
            .allocator = allocator,
            .subscribers = StringHashMap(ArrayList(Handler)).init(allocator),
            .endpoints = StringHashMap(RequestHandler).init(allocator),
        };
    }

    /// 发布事件 (Pub-Sub)
    pub fn publish(self: *MessageBus, topic: []const u8, event: Event) !void {
        if (self.subscribers.get(topic)) |handlers| {
            for (handlers.items) |handler| {
                handler(event);
            }
        }
    }

    /// 订阅主题 (Pub-Sub)
    pub fn subscribe(self: *MessageBus, topic: []const u8, handler: Handler) !void {
        const entry = try self.subscribers.getOrPut(topic);
        if (!entry.found_existing) {
            entry.value_ptr.* = ArrayList(Handler).init(self.allocator);
        }
        try entry.value_ptr.append(handler);
    }

    /// 取消订阅
    pub fn unsubscribe(self: *MessageBus, topic: []const u8, handler: Handler) void {
        if (self.subscribers.getPtr(topic)) |handlers| {
            for (handlers.items, 0..) |h, i| {
                if (h == handler) {
                    _ = handlers.swapRemove(i);
                    break;
                }
            }
        }
    }

    /// 发送请求 (Request-Response)
    pub fn request(self: *MessageBus, endpoint: []const u8, req: Request) !Response {
        if (self.endpoints.get(endpoint)) |handler| {
            return try handler(req);
        }
        return error.EndpointNotFound;
    }

    /// 注册端点 (Request-Response)
    pub fn register(self: *MessageBus, endpoint: []const u8, handler: RequestHandler) !void {
        try self.endpoints.put(endpoint, handler);
    }

    /// 发送命令 (Fire-and-Forget)
    pub fn send(self: *MessageBus, command: Command) void {
        command.execute();
    }

    /// 清理资源
    pub fn deinit(self: *MessageBus) void {
        var iter = self.subscribers.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.subscribers.deinit();
        self.endpoints.deinit();
    }
};
```

---

## 事件类型

```zig
pub const Event = union(enum) {
    // 市场数据事件
    market_data: MarketDataEvent,
    orderbook_update: OrderbookEvent,
    trade: TradeEvent,

    // 订单事件
    order_submitted: OrderEvent,
    order_accepted: OrderEvent,
    order_rejected: OrderEvent,
    order_filled: OrderFillEvent,
    order_cancelled: OrderEvent,

    // 仓位事件
    position_opened: PositionEvent,
    position_updated: PositionEvent,
    position_closed: PositionEvent,

    // 账户事件
    account_updated: AccountEvent,
};

pub const MarketDataEvent = struct {
    instrument_id: []const u8,
    timestamp: i64,
    bid: ?Decimal,
    ask: ?Decimal,
    last: ?Decimal,
};

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

---

## 主题命名规范

```
市场数据:
  market_data.{instrument_id}           # 特定品种数据
  market_data.*                         # 所有市场数据

订单簿:
  orderbook.{instrument_id}.snapshot    # 订单簿快照
  orderbook.{instrument_id}.delta       # 订单簿增量

订单:
  order.submitted                       # 订单提交
  order.accepted                        # 订单接受
  order.rejected                        # 订单拒绝
  order.filled                          # 订单成交
  order.cancelled                       # 订单取消

仓位:
  position.{instrument_id}              # 仓位更新

账户:
  account.{account_id}                  # 账户更新
```

---

## 使用示例

### 策略订阅市场数据

```zig
const strategy = struct {
    pub fn onMarketData(event: Event) void {
        const data = event.market_data;
        std.debug.print("收到市场数据: {s} bid={} ask={}\n", .{
            data.instrument_id,
            data.bid,
            data.ask,
        });
    }
};

// 订阅
try message_bus.subscribe("market_data.BTC-USDT", strategy.onMarketData);
try message_bus.subscribe("market_data.*", strategy.onMarketData);  // 通配符
```

### DataEngine 发布事件

```zig
pub fn processMarketData(self: *DataEngine, raw_data: []const u8) !void {
    const data = try self.parseMarketData(raw_data);

    // 发布到 MessageBus
    try self.message_bus.publish("market_data." ++ data.instrument_id, .{
        .market_data = .{
            .instrument_id = data.instrument_id,
            .timestamp = data.timestamp,
            .bid = data.bid,
            .ask = data.ask,
            .last = data.last,
        },
    });
}
```

### ExecutionEngine 处理订单请求

```zig
// 注册端点
try message_bus.register("order.submit", ExecutionEngine.handleOrderSubmit);

// 发送请求
const response = try message_bus.request("order.submit", .{
    .order = .{
        .instrument_id = "BTC-USDT",
        .side = .buy,
        .quantity = Decimal.fromFloat(0.1),
        .price = Decimal.fromFloat(50000),
    },
});
```

---

## 测试计划

### 单元测试

| 测试 | 描述 |
|------|------|
| `test_subscribe_publish` | 订阅和发布基本功能 |
| `test_multiple_subscribers` | 多订阅者接收同一事件 |
| `test_unsubscribe` | 取消订阅 |
| `test_request_response` | 请求响应模式 |
| `test_wildcard_subscription` | 通配符订阅 |
| `test_no_memory_leak` | 内存泄漏检测 |

### 性能测试

| 指标 | 目标 |
|------|------|
| 发布延迟 | < 1μs |
| 吞吐量 | > 100,000 msg/s |
| 内存分配 | 仅初始化时分配 |

---

## 文件结构

```
src/core/
└── message_bus.zig          # MessageBus 实现

src/events/
├── types.zig                # 事件类型定义
├── market_events.zig        # 市场数据事件
├── order_events.zig         # 订单事件
└── position_events.zig      # 仓位事件

tests/
└── core/
    └── message_bus_test.zig # MessageBus 测试
```

---

## 验收标准

- [ ] MessageBus 支持 Pub/Sub 模式
- [ ] MessageBus 支持 Request/Response 模式
- [ ] MessageBus 支持 Command 模式
- [ ] 支持通配符订阅
- [ ] 吞吐量 > 100,000 msg/s
- [ ] 零内存泄漏
- [ ] 所有测试通过

---

## 相关文档

- [v0.5.0 Overview](./OVERVIEW.md)
- [架构模式参考](../../architecture/ARCHITECTURE_PATTERNS.md)
- [Story 024: Cache](./STORY_024_CACHE.md)

---

**版本**: v0.5.0
**状态**: 计划中
**创建时间**: 2025-12-27
