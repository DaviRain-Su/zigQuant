# v0.5.0 Overview - 事件驱动架构

**版本**: v0.5.0
**状态**: 计划中
**预计**: 2025 Q1
**前置版本**: v0.4.0 (已完成)

---

## 目标

将 zigQuant 从同步模式重构为事件驱动架构，实现回测代码与实盘代码的统一（Code Parity），为生产级部署奠定基础。

## 核心理念

参考 **NautilusTrader** 和 **Hummingbot** 的设计：

```
┌─────────────────────────────────────────────────────────────┐
│                   zigQuant v0.5.0                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   MessageBus                          │   │
│  │  (Pub/Sub + Request/Response + Command)              │   │
│  └──────────────────────────────────────────────────────┘   │
│           ↑              ↑              ↑                    │
│           │              │              │                    │
│  ┌────────┴──────┐ ┌─────┴──────┐ ┌────┴────────┐          │
│  │  DataEngine   │ │  Strategy  │ │ Execution   │          │
│  │ (市场数据)     │ │  (策略)    │ │  Engine     │          │
│  └───────────────┘ └────────────┘ └─────────────┘          │
│           ↑                              ↑                   │
│           │                              │                   │
│  ┌────────┴──────────────────────────────┴──────┐          │
│  │                   Cache                       │          │
│  │  (Orders, Positions, Accounts, Instruments)  │          │
│  └───────────────────────────────────────────────┘          │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   libxev Event Loop                   │   │
│  │  (io_uring on Linux, kqueue on macOS)                │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Stories 规划

| Story | 名称 | 描述 | 预计工期 |
|-------|------|------|---------|
| **023** | MessageBus | 消息总线系统 (Pub/Sub, Request/Response) | 1 周 |
| **024** | Cache | 高性能内存缓存 (Orders, Positions, Accounts) | 1 周 |
| **025** | DataEngine | 数据引擎重构 (事件发布) | 1 周 |
| **026** | ExecutionEngine | 执行引擎 (订单前置追踪) | 1 周 |
| **027** | libxev Integration | 事件循环集成 (io_uring) | 1 周 |

**总预计**: 5 周

---

## Story 023: MessageBus

### 目标
实现单线程高效消息传递系统，类似 Actor 模型但无线程切换开销。

### 核心功能

```zig
pub const MessageBus = struct {
    // Publish-Subscribe 模式
    pub fn publish(topic: []const u8, event: Event) void;
    pub fn subscribe(topic: []const u8, handler: Handler) void;

    // Request-Response 模式
    pub fn request(endpoint: []const u8, req: Request) Response;
    pub fn register(endpoint: []const u8, handler: RequestHandler) void;

    // Command 模式 (fire-and-forget)
    pub fn send(command: Command) void;
};
```

### 使用场景
- DataEngine → 发布 `market_data.orderbook_update` 事件
- Strategy → 订阅 `market_data.*` 事件
- ExecutionEngine → 处理 `order.submit` 命令

### 详细文档
- [STORY_023_MESSAGE_BUS.md](./STORY_023_MESSAGE_BUS.md)

---

## Story 024: Cache

### 目标
实现高性能内存缓存，提供纳秒级访问常用对象。

### 核心功能

```zig
pub const Cache = struct {
    // 核心缓存
    instruments: StringHashMap(Instrument),
    orders: StringHashMap(Order),
    positions: StringHashMap(Position),
    accounts: StringHashMap(Account),

    // 索引
    orders_open: StringHashMap(*Order),
    orders_closed: StringHashMap(*Order),

    // 快速访问
    pub fn getOrder(order_id: []const u8) ?*Order;
    pub fn getOpenOrders() []const *Order;
    pub fn getPosition(instrument_id: []const u8) ?Position;
};
```

### 使用场景
- Strategy → 快速查询当前仓位
- ExecutionEngine → 检查订单状态
- RiskEngine → 计算账户总风险敞口

### 详细文档
- [STORY_024_CACHE.md](./STORY_024_CACHE.md)

---

## Story 025: DataEngine

### 目标
重构数据引擎，发布市场数据事件到 MessageBus。

### 核心功能

```zig
pub const DataEngine = struct {
    message_bus: *MessageBus,
    cache: *Cache,

    pub fn processMarketData(data: MarketData) void {
        // 1. 更新缓存
        self.cache.updateInstrument(data.instrument);

        // 2. 发布事件
        self.message_bus.publish("market_data.update", .{
            .instrument = data.instrument,
            .timestamp = data.timestamp,
        });
    }

    pub fn processOrderbookSnapshot(snapshot: Snapshot) void {
        // 发布订单簿更新事件
        self.message_bus.publish("market_data.orderbook", snapshot);
    }
};
```

### 详细文档
- [STORY_025_DATA_ENGINE.md](./STORY_025_DATA_ENGINE.md)

---

## Story 026: ExecutionEngine

### 目标
实现订单执行引擎，支持订单前置追踪（Hummingbot 模式）。

### 核心功能

```zig
pub const ExecutionEngine = struct {
    message_bus: *MessageBus,
    cache: *Cache,

    // 订单前置追踪
    pending_orders: StringHashMap(Order),
    tracked_orders: StringHashMap(Order),

    /// 步骤 1: 前置追踪
    pub fn trackOrder(order: Order) void {
        self.pending_orders.put(order.client_order_id, order);
    }

    /// 步骤 2: 提交订单
    pub fn submitOrder(order: Order) !void {
        defer self.pending_orders.remove(order.client_order_id);

        const exchange_order_id = try self.exchange.submitOrder(order);
        order.exchange_order_id = exchange_order_id;

        try self.tracked_orders.put(order.client_order_id, order);
        try self.cache.updateOrder(order);
    }
};
```

### 订单前置追踪流程

```
传统流程 (有丢单风险):
1. submitOrder() → API 调用
2. API 超时 → 订单状态未知
3. 可能重复下单或遗漏订单

zigQuant 流程 (零丢单):
1. trackOrder() → 立即保存到 pending_orders
2. submitOrder() → API 调用
3. API 超时:
   - WebSocket 监听订单更新
   - 收到确认 → 从 pending 移到 tracked
   - 超时未确认 → 查询订单状态
4. 零订单丢失
```

### 详细文档
- [STORY_026_EXECUTION_ENGINE.md](./STORY_026_EXECUTION_ENGINE.md)

---

## Story 027: libxev Integration

### 目标
集成 libxev 事件循环，实现高性能异步 I/O。

### 核心功能

```zig
const xev = @import("xev");

pub const LiveTradingEngine = struct {
    loop: xev.Loop,
    ws_handler: WebSocketHandler,
    message_bus: *MessageBus,

    pub fn start(self: *LiveTradingEngine) !void {
        self.loop = try xev.Loop.init();
        defer self.loop.deinit();

        // 连接 WebSocket
        try self.ws_handler.connect(&self.loop);

        // 运行事件循环
        try self.loop.run(.until_done);
    }
};
```

### libxev 优势

| 特性 | 说明 |
|------|------|
| io_uring 支持 | Linux 最快 I/O |
| 零运行时分配 | 性能可预测 |
| Zig 原生 | 完美集成 |
| 跨平台 | Linux/macOS/WASI |

### 详细文档
- [STORY_027_LIBXEV_INTEGRATION.md](./STORY_027_LIBXEV_INTEGRATION.md)

---

## 验收标准

### 功能验收

- [ ] MessageBus 支持 Pub/Sub、Request/Response、Command 模式
- [ ] Cache 提供纳秒级订单/仓位查询
- [ ] DataEngine 通过 MessageBus 发布市场数据事件
- [ ] ExecutionEngine 实现订单前置追踪
- [ ] libxev 集成完成，WebSocket 连接正常

### 性能验收

| 指标 | 目标 |
|------|------|
| MessageBus 吞吐量 | > 100,000 msg/s |
| Cache 查询延迟 | < 100ns |
| WebSocket 延迟 | < 5ms |
| 订单提交延迟 | < 10ms |

### 代码验收

- [ ] 所有测试通过 (目标: 500+ 测试)
- [ ] 零内存泄漏 (GeneralPurposeAllocator 验证)
- [ ] 代码覆盖率 > 80%
- [ ] 文档完整性 100%

---

## 依赖关系

```
Story 023 (MessageBus)
    ↓
Story 024 (Cache)
    ↓
Story 025 (DataEngine) ──→ Story 027 (libxev)
    ↓
Story 026 (ExecutionEngine)
```

---

## 相关文档

- [架构模式参考](../../architecture/ARCHITECTURE_PATTERNS.md)
- [libxev 集成方案](../../architecture/LIBXEV_INTEGRATION.md)
- [竞争分析](../../architecture/COMPETITIVE_ANALYSIS.md)
- [Roadmap](../../../roadmap.md)

---

**版本**: v0.5.0
**状态**: 计划中
**创建时间**: 2025-12-27
