# Story 024: Cache - 高性能内存缓存

**版本**: v0.5.0
**状态**: 计划中
**预计工期**: 1 周
**依赖**: Story 023 (MessageBus)

---

## 目标

实现高性能内存缓存系统，提供纳秒级访问常用对象（订单、仓位、账户、合约），作为系统的单一数据源。

## 背景

参考 **NautilusTrader** 的 Cache 设计：
- 内存缓存常用对象，避免重复查询
- 维护索引加速特定查询
- 与 MessageBus 集成，自动同步状态

---

## 核心设计

### 架构

```
┌─────────────────────────────────────────────────────────────┐
│                        Cache                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ Instruments │  │   Orders    │  │  Positions  │        │
│  │  HashMap    │  │   HashMap   │  │   HashMap   │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│                                                              │
│  ┌─────────────┐  ┌─────────────────────────────────┐      │
│  │  Accounts   │  │          Indexes                │      │
│  │  HashMap    │  │  - orders_open                  │      │
│  └─────────────┘  │  - orders_closed                │      │
│                    │  - orders_by_instrument        │      │
│                    └─────────────────────────────────┘      │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                 MessageBus Integration               │   │
│  │    subscribe("order.*") → auto-update cache          │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 接口定义

```zig
pub const Cache = struct {
    allocator: Allocator,
    message_bus: *MessageBus,

    // 核心数据
    instruments: StringHashMap(Instrument),
    orders: StringHashMap(Order),
    positions: StringHashMap(Position),
    accounts: StringHashMap(Account),

    // 索引 (加速查询)
    orders_open: StringHashMap(*Order),
    orders_closed: StringHashMap(*Order),
    orders_by_instrument: StringHashMap(ArrayList(*Order)),

    /// 初始化
    pub fn init(allocator: Allocator, message_bus: *MessageBus) !Cache {
        var cache = Cache{
            .allocator = allocator,
            .message_bus = message_bus,
            .instruments = StringHashMap(Instrument).init(allocator),
            .orders = StringHashMap(Order).init(allocator),
            .positions = StringHashMap(Position).init(allocator),
            .accounts = StringHashMap(Account).init(allocator),
            .orders_open = StringHashMap(*Order).init(allocator),
            .orders_closed = StringHashMap(*Order).init(allocator),
            .orders_by_instrument = StringHashMap(ArrayList(*Order)).init(allocator),
        };

        // 订阅订单事件自动更新缓存
        try message_bus.subscribe("order.*", cache.onOrderEvent);
        try message_bus.subscribe("position.*", cache.onPositionEvent);
        try message_bus.subscribe("account.*", cache.onAccountEvent);

        return cache;
    }

    // ========== 合约查询 ==========

    pub fn getInstrument(self: *Cache, instrument_id: []const u8) ?Instrument {
        return self.instruments.get(instrument_id);
    }

    pub fn getAllInstruments(self: *Cache) []const Instrument {
        var result = ArrayList(Instrument).init(self.allocator);
        var iter = self.instruments.valueIterator();
        while (iter.next()) |inst| {
            result.append(inst.*) catch unreachable;
        }
        return result.items;
    }

    // ========== 订单查询 ==========

    /// 获取订单 (O(1))
    pub fn getOrder(self: *Cache, order_id: []const u8) ?*Order {
        return self.orders.getPtr(order_id);
    }

    /// 获取所有开仓订单 (O(n))
    pub fn getOpenOrders(self: *Cache) []*Order {
        var result = ArrayList(*Order).init(self.allocator);
        var iter = self.orders_open.valueIterator();
        while (iter.next()) |order| {
            result.append(order.*) catch unreachable;
        }
        return result.items;
    }

    /// 获取特定合约的订单 (O(1) + O(k))
    pub fn getOrdersByInstrument(self: *Cache, instrument_id: []const u8) []*Order {
        if (self.orders_by_instrument.get(instrument_id)) |orders| {
            return orders.items;
        }
        return &[_]*Order{};
    }

    /// 订单数量
    pub fn orderCount(self: *Cache) usize {
        return self.orders.count();
    }

    /// 开仓订单数量
    pub fn openOrderCount(self: *Cache) usize {
        return self.orders_open.count();
    }

    // ========== 仓位查询 ==========

    /// 获取仓位 (O(1))
    pub fn getPosition(self: *Cache, instrument_id: []const u8) ?Position {
        return self.positions.get(instrument_id);
    }

    /// 获取所有仓位
    pub fn getAllPositions(self: *Cache) []const Position {
        var result = ArrayList(Position).init(self.allocator);
        var iter = self.positions.valueIterator();
        while (iter.next()) |pos| {
            result.append(pos.*) catch unreachable;
        }
        return result.items;
    }

    /// 是否有仓位
    pub fn hasPosition(self: *Cache, instrument_id: []const u8) bool {
        return self.positions.contains(instrument_id);
    }

    // ========== 账户查询 ==========

    /// 获取账户 (O(1))
    pub fn getAccount(self: *Cache, account_id: []const u8) ?Account {
        return self.accounts.get(account_id);
    }

    // ========== 更新操作 ==========

    /// 更新合约
    pub fn updateInstrument(self: *Cache, instrument: Instrument) !void {
        try self.instruments.put(instrument.id, instrument);
    }

    /// 更新订单
    pub fn updateOrder(self: *Cache, order: Order) !void {
        try self.orders.put(order.id, order);

        // 更新索引
        const order_ptr = self.orders.getPtr(order.id).?;

        switch (order.status) {
            .pending, .accepted, .partially_filled => {
                try self.orders_open.put(order.id, order_ptr);
                _ = self.orders_closed.remove(order.id);
            },
            .filled, .cancelled, .rejected, .expired => {
                try self.orders_closed.put(order.id, order_ptr);
                _ = self.orders_open.remove(order.id);
            },
        }

        // 更新按合约索引
        const entry = try self.orders_by_instrument.getOrPut(order.instrument_id);
        if (!entry.found_existing) {
            entry.value_ptr.* = ArrayList(*Order).init(self.allocator);
        }
        // 检查是否已存在
        var found = false;
        for (entry.value_ptr.items) |existing| {
            if (std.mem.eql(u8, existing.id, order.id)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try entry.value_ptr.append(order_ptr);
        }
    }

    /// 更新仓位
    pub fn updatePosition(self: *Cache, position: Position) !void {
        if (position.quantity.isZero()) {
            // 仓位已清空，移除
            _ = self.positions.remove(position.instrument_id);
        } else {
            try self.positions.put(position.instrument_id, position);
        }
    }

    /// 更新账户
    pub fn updateAccount(self: *Cache, account: Account) !void {
        try self.accounts.put(account.id, account);
    }

    // ========== 事件处理 ==========

    fn onOrderEvent(event: Event) void {
        const self = @fieldParentPtr(Cache, "message_bus", event.source);
        switch (event) {
            .order_submitted, .order_accepted, .order_filled, .order_cancelled => |order_event| {
                self.updateOrder(order_event.order) catch {};
            },
            else => {},
        }
    }

    fn onPositionEvent(event: Event) void {
        const self = @fieldParentPtr(Cache, "message_bus", event.source);
        if (event == .position_updated) |pos_event| {
            self.updatePosition(pos_event.position) catch {};
        }
    }

    fn onAccountEvent(event: Event) void {
        const self = @fieldParentPtr(Cache, "message_bus", event.source);
        if (event == .account_updated) |acc_event| {
            self.updateAccount(acc_event.account) catch {};
        }
    }

    // ========== 清理 ==========

    pub fn deinit(self: *Cache) void {
        self.instruments.deinit();
        self.orders.deinit();
        self.positions.deinit();
        self.accounts.deinit();
        self.orders_open.deinit();
        self.orders_closed.deinit();

        var iter = self.orders_by_instrument.valueIterator();
        while (iter.next()) |list| {
            list.deinit();
        }
        self.orders_by_instrument.deinit();
    }
};
```

---

## 数据结构

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

pub const OrderStatus = enum {
    pending,
    accepted,
    partially_filled,
    filled,
    cancelled,
    rejected,
    expired,
};
```

### Position

```zig
pub const Position = struct {
    instrument_id: []const u8,
    side: Side,
    quantity: Decimal,
    entry_price: Decimal,
    unrealized_pnl: Decimal,
    realized_pnl: Decimal,
    margin: Decimal,
    leverage: Decimal,
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

---

## 使用示例

### 策略查询仓位

```zig
pub fn generateSignal(self: *Strategy, market_data: MarketData) !?Signal {
    // 快速查询当前仓位 (纳秒级)
    const position = self.cache.getPosition(market_data.instrument_id);

    if (position) |pos| {
        // 已有仓位，检查是否需要平仓
        if (pos.unrealized_pnl.lt(self.stop_loss)) {
            return Signal{ .type = .exit, .side = pos.side.opposite() };
        }
    } else {
        // 无仓位，检查是否需要开仓
        if (self.shouldEnter(market_data)) {
            return Signal{ .type = .entry, .side = .buy };
        }
    }

    return null;
}
```

### 风险管理查询

```zig
pub fn checkRiskLimits(self: *RiskManager) !bool {
    // 获取所有开仓订单
    const open_orders = self.cache.getOpenOrders();

    // 计算总挂单量
    var total_pending: Decimal = Decimal.zero;
    for (open_orders) |order| {
        total_pending = total_pending.add(order.quantity.sub(order.filled_quantity));
    }

    // 获取账户
    const account = self.cache.getAccount(self.account_id) orelse return error.AccountNotFound;

    // 检查风险限制
    if (total_pending.gt(account.available.mul(self.max_exposure))) {
        return false;
    }

    return true;
}
```

---

## 测试计划

### 单元测试

| 测试 | 描述 |
|------|------|
| `test_order_crud` | 订单增删改查 |
| `test_order_index` | 订单索引正确性 |
| `test_position_update` | 仓位更新 |
| `test_account_update` | 账户更新 |
| `test_event_sync` | 事件自动同步 |
| `test_no_memory_leak` | 内存泄漏检测 |

### 性能测试

| 指标 | 目标 |
|------|------|
| 单次查询延迟 | < 100ns |
| 批量查询 (100 orders) | < 10μs |
| 更新延迟 | < 1μs |
| 内存占用 | < 1KB per order |

---

## 文件结构

```
src/core/
└── cache.zig                # Cache 实现

src/types/
├── order.zig                # Order 类型
├── position.zig             # Position 类型
└── account.zig              # Account 类型

tests/
└── core/
    └── cache_test.zig       # Cache 测试
```

---

## 验收标准

- [ ] 支持订单、仓位、账户、合约的 CRUD 操作
- [ ] 维护订单索引 (开仓/已平/按合约)
- [ ] 与 MessageBus 集成，自动同步状态
- [ ] 单次查询延迟 < 100ns
- [ ] 零内存泄漏
- [ ] 所有测试通过

---

## 相关文档

- [v0.5.0 Overview](./OVERVIEW.md)
- [Story 023: MessageBus](./STORY_023_MESSAGE_BUS.md)
- [Story 025: DataEngine](./STORY_025_DATA_ENGINE.md)

---

**版本**: v0.5.0
**状态**: 计划中
**创建时间**: 2025-12-27
