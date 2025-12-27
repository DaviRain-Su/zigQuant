# Cache - 实现细节

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 架构设计

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                         Cache                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  Order Cache                          │   │
│  │  HashMap<OrderId, Order>  |  O(1) lookup             │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                Position Cache                         │   │
│  │  HashMap<InstrumentId, Position>  |  O(1) lookup     │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                Account Cache                          │   │
│  │  HashMap<AccountId, Account>  |  O(1) lookup         │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                 Quote Cache                           │   │
│  │  HashMap<InstrumentId, Quote>  |  O(1) lookup        │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│                          │                                   │
│                          ▼                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │               MessageBus Subscriber                   │   │
│  │  自动订阅事件并更新缓存                                │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 设计原则

1. **O(1) 查询**: 所有查询操作使用 HashMap，纳秒级响应
2. **事件驱动更新**: 通过 MessageBus 事件自动更新
3. **零拷贝读取**: 返回指针引用，避免数据拷贝
4. **单一数据源**: Cache 是运行时状态的唯一真实来源

---

## 核心数据结构

### HashMap 选择

使用 Zig 标准库的 StringHashMap：

```zig
const std = @import("std");

pub const Cache = struct {
    allocator: Allocator,
    message_bus: *MessageBus,

    // O(1) 查找的 HashMap
    orders: std.StringHashMap(Order),
    positions: std.StringHashMap(Position),
    accounts: std.StringHashMap(Account),
    quotes: std.StringHashMap(Quote),
    instruments: std.StringHashMap(Instrument),

    // 索引 (可选优化)
    orders_by_instrument: std.StringHashMap(std.ArrayList([]const u8)),
};
```

### 索引结构

为支持按交易对查询订单，维护二级索引：

```zig
// 主存储: order_id -> Order
orders: StringHashMap(Order),

// 二级索引: instrument_id -> [order_ids]
orders_by_instrument: StringHashMap(ArrayList([]const u8)),
```

---

## MessageBus 集成

### 自动订阅

初始化时自动订阅相关事件：

```zig
pub fn init(
    allocator: Allocator,
    message_bus: *MessageBus,
    config: CacheConfig,
) !Cache {
    var cache = Cache{
        .allocator = allocator,
        .message_bus = message_bus,
        .orders = StringHashMap(Order).init(allocator),
        .positions = StringHashMap(Position).init(allocator),
        .accounts = StringHashMap(Account).init(allocator),
        .quotes = StringHashMap(Quote).init(allocator),
    };

    if (config.auto_subscribe) {
        // 订阅所有相关事件
        try message_bus.subscribe("order.*", cache.onOrderEvent);
        try message_bus.subscribe("position.*", cache.onPositionEvent);
        try message_bus.subscribe("account.*", cache.onAccountEvent);
        try message_bus.subscribe("market_data.*", cache.onMarketDataEvent);
    }

    return cache;
}
```

### 事件处理器

```zig
fn onOrderEvent(self: *Cache, event: Event) void {
    switch (event) {
        .order_submitted => |order| self.updateOrder(order) catch {},
        .order_accepted => |order| self.updateOrder(order) catch {},
        .order_filled => |fill| self.handleOrderFill(fill) catch {},
        .order_cancelled => |order| self.updateOrder(order) catch {},
        .order_rejected => |reject| self.handleOrderReject(reject) catch {},
        else => {},
    }
}

fn onPositionEvent(self: *Cache, event: Event) void {
    switch (event) {
        .position_opened => |pos| self.updatePosition(pos) catch {},
        .position_updated => |pos| self.updatePosition(pos) catch {},
        .position_closed => |pos| self.removePosition(pos.instrument_id) catch {},
        else => {},
    }
}

fn onMarketDataEvent(self: *Cache, event: Event) void {
    switch (event) {
        .market_data => |data| self.updateQuote(data) catch {},
        else => {},
    }
}
```

---

## 查询实现

### O(1) 单项查询

```zig
pub fn getOrder(self: *Cache, order_id: []const u8) ?*const Order {
    return self.orders.getPtr(order_id);
}

pub fn getPosition(self: *Cache, instrument_id: []const u8) ?*const Position {
    return self.positions.getPtr(instrument_id);
}

pub fn getQuote(self: *Cache, instrument_id: []const u8) ?*const Quote {
    return self.quotes.getPtr(instrument_id);
}
```

### 批量查询

```zig
pub fn getOrdersByInstrument(
    self: *Cache,
    allocator: Allocator,
    instrument_id: []const u8,
) ![]*const Order {
    var result = std.ArrayList(*const Order).init(allocator);

    // 使用二级索引
    if (self.orders_by_instrument.get(instrument_id)) |order_ids| {
        for (order_ids.items) |order_id| {
            if (self.orders.getPtr(order_id)) |order| {
                try result.append(order);
            }
        }
    }

    return result.toOwnedSlice();
}

pub fn getOpenOrders(self: *Cache, allocator: Allocator) ![]*const Order {
    var result = std.ArrayList(*const Order).init(allocator);

    var iter = self.orders.iterator();
    while (iter.next()) |entry| {
        const order = entry.value_ptr;
        if (order.status == .accepted or order.status == .partially_filled) {
            try result.append(order);
        }
    }

    return result.toOwnedSlice();
}
```

---

## 更新实现

### 订单更新

```zig
pub fn updateOrder(self: *Cache, order: Order) !void {
    // 更新主存储
    try self.orders.put(order.id, order);

    // 更新二级索引
    const order_list = try self.orders_by_instrument.getOrPut(order.instrument_id);
    if (!order_list.found_existing) {
        order_list.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
    }

    // 检查是否已存在
    for (order_list.value_ptr.items) |existing_id| {
        if (std.mem.eql(u8, existing_id, order.id)) {
            return; // 已存在，不重复添加
        }
    }
    try order_list.value_ptr.append(order.id);
}
```

### 仓位更新

```zig
pub fn updatePosition(self: *Cache, position: Position) !void {
    try self.positions.put(position.instrument_id, position);
}

pub fn removePosition(self: *Cache, instrument_id: []const u8) void {
    _ = self.positions.remove(instrument_id);
}
```

### 报价更新

```zig
pub fn updateQuote(self: *Cache, data: MarketDataEvent) !void {
    const quote = Quote{
        .instrument_id = data.instrument_id,
        .bid = data.bid orelse return,
        .ask = data.ask orelse return,
        .bid_size = data.bid_size orelse 0,
        .ask_size = data.ask_size orelse 0,
        .last = data.last,
        .volume_24h = data.volume_24h,
        .timestamp = data.timestamp,
    };
    try self.quotes.put(data.instrument_id, quote);
}
```

---

## 内存管理

### 分配策略

```zig
// 字符串键需要复制（生命周期管理）
fn putWithOwnedKey(
    self: *Cache,
    map: anytype,
    key: []const u8,
    value: anytype,
) !void {
    const owned_key = try self.allocator.dupe(u8, key);
    errdefer self.allocator.free(owned_key);
    try map.put(owned_key, value);
}
```

### 清理流程

```zig
pub fn deinit(self: *Cache) void {
    // 清理订单缓存
    var order_iter = self.orders.iterator();
    while (order_iter.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }
    self.orders.deinit();

    // 清理二级索引
    var index_iter = self.orders_by_instrument.iterator();
    while (index_iter.next()) |entry| {
        entry.value_ptr.deinit();
        self.allocator.free(entry.key_ptr.*);
    }
    self.orders_by_instrument.deinit();

    // 清理其他缓存...
    self.positions.deinit();
    self.accounts.deinit();
    self.quotes.deinit();
}
```

---

## 快照机制

### 创建快照

```zig
pub const CacheSnapshot = struct {
    orders: []Order,
    positions: []Position,
    accounts: []Account,
    timestamp: i64,
};

pub fn takeSnapshot(self: *Cache, allocator: Allocator) !CacheSnapshot {
    var orders = std.ArrayList(Order).init(allocator);
    var positions = std.ArrayList(Position).init(allocator);
    var accounts = std.ArrayList(Account).init(allocator);

    // 复制所有订单
    var order_iter = self.orders.iterator();
    while (order_iter.next()) |entry| {
        try orders.append(entry.value_ptr.*);
    }

    // 复制所有仓位
    var pos_iter = self.positions.iterator();
    while (pos_iter.next()) |entry| {
        try positions.append(entry.value_ptr.*);
    }

    // 复制所有账户
    var acc_iter = self.accounts.iterator();
    while (acc_iter.next()) |entry| {
        try accounts.append(entry.value_ptr.*);
    }

    return CacheSnapshot{
        .orders = orders.toOwnedSlice(),
        .positions = positions.toOwnedSlice(),
        .accounts = accounts.toOwnedSlice(),
        .timestamp = std.time.milliTimestamp(),
    };
}
```

### 从快照恢复

```zig
pub fn restoreFromSnapshot(self: *Cache, snapshot: CacheSnapshot) !void {
    // 清空现有缓存
    self.orders.clearRetainingCapacity();
    self.positions.clearRetainingCapacity();
    self.accounts.clearRetainingCapacity();

    // 恢复订单
    for (snapshot.orders) |order| {
        try self.updateOrder(order);
    }

    // 恢复仓位
    for (snapshot.positions) |position| {
        try self.updatePosition(position);
    }

    // 恢复账户
    for (snapshot.accounts) |account| {
        try self.accounts.put(account.id, account);
    }
}
```

---

## 性能优化

### 1. 预分配容量

```zig
pub fn initWithCapacity(
    allocator: Allocator,
    message_bus: *MessageBus,
    capacity: struct {
        orders: usize = 1000,
        positions: usize = 100,
        accounts: usize = 10,
        quotes: usize = 100,
    },
) !Cache {
    var cache = Cache{...};
    try cache.orders.ensureTotalCapacity(capacity.orders);
    try cache.positions.ensureTotalCapacity(capacity.positions);
    try cache.accounts.ensureTotalCapacity(capacity.accounts);
    try cache.quotes.ensureTotalCapacity(capacity.quotes);
    return cache;
}
```

### 2. 批量更新

```zig
pub fn updateOrdersBatch(self: *Cache, orders: []const Order) !void {
    for (orders) |order| {
        try self.updateOrder(order);
    }
}
```

---

## 文件结构

```
src/core/
├── cache.zig                # Cache 实现
├── cache/
│   ├── order_cache.zig      # 订单缓存
│   ├── position_cache.zig   # 仓位缓存
│   ├── account_cache.zig    # 账户缓存
│   ├── quote_cache.zig      # 报价缓存
│   └── snapshot.zig         # 快照功能
└── types/
    ├── order.zig            # 订单类型
    ├── position.zig         # 仓位类型
    └── account.zig          # 账户类型
```

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [测试文档](./testing.md)

---

**版本**: v0.5.0
**状态**: 计划中
