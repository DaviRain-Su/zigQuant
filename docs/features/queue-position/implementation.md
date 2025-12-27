# Queue Position 实现细节

> 队列位置建模模块的内部实现文档

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 目录

1. [架构概述](#架构概述)
2. [数据结构](#数据结构)
3. [概率模型](#概率模型)
4. [队列管理](#队列管理)
5. [成交判定](#成交判定)
6. [性能优化](#性能优化)

---

## 架构概述

### 模块结构

```
src/backtest/
├── queue_position.zig     # 队列位置核心
├── level3_orderbook.zig   # Level-3 订单簿
├── fill_model.zig         # 成交概率模型
└── tests/
    └── queue_test.zig     # 测试
```

### 组件关系

```
┌─────────────────────────────────────────────────────────────┐
│                     BacktestEngine                           │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  Level3OrderBook                      │   │
│  │  ┌─────────────────────────────────────────────────┐ │   │
│  │  │                  Bid Side                        │ │   │
│  │  │  ┌───────────┐ ┌───────────┐ ┌───────────┐     │ │   │
│  │  │  │ Level 2000│ │ Level 1999│ │ Level 1998│ ... │ │   │
│  │  │  │ [O1][O2]  │ │ [O3][O4]  │ │ [O5]      │     │ │   │
│  │  │  └───────────┘ └───────────┘ └───────────┘     │ │   │
│  │  └─────────────────────────────────────────────────┘ │   │
│  │  ┌─────────────────────────────────────────────────┐ │   │
│  │  │                  Ask Side                        │ │   │
│  │  │  ┌───────────┐ ┌───────────┐ ┌───────────┐     │ │   │
│  │  │  │ Level 2001│ │ Level 2002│ │ Level 2003│ ... │ │   │
│  │  │  │ [O6][O7]  │ │ [O8]      │ │ [O9][O10] │     │ │   │
│  │  │  └───────────┘ └───────────┘ └───────────┘     │ │   │
│  │  └─────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
│                              │                               │
│                              ▼                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   QueuePosition                       │   │
│  │  • position_in_queue                                  │   │
│  │  • total_quantity_ahead                               │   │
│  │  • fillProbability(model)                             │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 数据结构

### Level3OrderBook 内部结构

```zig
pub const Level3OrderBook = struct {
    allocator: Allocator,
    symbol: []const u8,

    /// 买单价格层级 (按价格降序)
    bid_levels: std.AutoArrayHashMap(Decimal, PriceLevel),

    /// 卖单价格层级 (按价格升序)
    ask_levels: std.AutoArrayHashMap(Decimal, PriceLevel),

    /// 订单 ID 到订单的映射
    orders: std.StringHashMap(*Level3Order),

    /// 我的订单列表
    my_orders: std.ArrayList(*Level3Order),

    /// 统计
    stats: BookStats,
};

pub const BookStats = struct {
    total_orders: u64,
    my_orders: u64,
    trades_processed: u64,
    fills_generated: u64,
};
```

### PriceLevel 内部结构

```zig
pub const PriceLevel = struct {
    price: Decimal,

    /// 订单队列 (FIFO)
    orders: std.DoublyLinkedList(Level3Order),

    /// 总数量
    total_quantity: Decimal,

    /// 快速查找
    order_index: std.StringHashMap(*std.DoublyLinkedList(Level3Order).Node),
};
```

### QueuePosition 内部结构

```zig
pub const QueuePosition = struct {
    order_id: []const u8,
    price_level: Decimal,
    position_in_queue: usize,
    total_quantity_ahead: Decimal,
    initial_quantity_ahead: Decimal,
    order_quantity: Decimal,
    queued_at: i64,

    // 缓存的归一化位置
    cached_normalized: ?f64 = null,
};
```

---

## 概率模型

### 模型数学定义

设 `x` 为归一化队列位置 (0 = 队头, 1 = 队尾):

```
RiskAverse:
  P(fill) = 1.0  if x < 0.01
          = 0.0  otherwise

Probability (线性):
  P(fill) = 1.0 - x

PowerLaw (平方):
  P(fill) = 1.0 - x²

Logarithmic (对数):
  P(fill) = 1.0 - log(1 + x) / log(2)
```

### 概率曲线可视化

```
P(fill)
1.0 ┤━━━━━━━━━━━━━━━━━━━
    │ ╲                   RiskAverse (阶跃)
    │  ╲
0.8 ┤   ╲╲                Logarithmic
    │    ╲ ╲
    │     ╲  ╲            Probability (线性)
0.6 ┤      ╲   ╲
    │       ╲    ╲
    │        ╲     ╲      PowerLaw (平方)
0.4 ┤         ╲      ╲
    │          ╲       ╲
    │           ╲        ╲
0.2 ┤            ╲         ╲
    │             ╲          ╲
    │              ╲           ╲
0.0 ┼──────────────────────────────
    0.0   0.2   0.4   0.6   0.8   1.0
                    x (队列位置)
```

### 模型实现

```zig
pub const QueueModel = enum {
    RiskAverse,
    Probability,
    PowerLaw,
    Logarithmic,

    pub fn probability(self: QueueModel, x: f64) f64 {
        // 限制 x 在 [0, 1]
        const clamped = std.math.clamp(x, 0.0, 1.0);

        return switch (self) {
            .RiskAverse => if (clamped < 0.01) 1.0 else 0.0,
            .Probability => 1.0 - clamped,
            .PowerLaw => 1.0 - clamped * clamped,
            .Logarithmic => 1.0 - @log(1.0 + clamped) / @log(2.0),
        };
    }
};
```

### 归一化位置计算

```zig
pub fn normalizedPosition(self: QueuePosition) f64 {
    if (self.cached_normalized) |cached| {
        return cached;
    }

    const initial = self.initial_quantity_ahead.toFloat();
    if (initial <= 0) {
        self.cached_normalized = 0.0;
        return 0.0;
    }

    const ahead = self.total_quantity_ahead.toFloat();
    const normalized = ahead / initial;
    self.cached_normalized = std.math.clamp(normalized, 0.0, 1.0);
    return self.cached_normalized.?;
}
```

---

## 队列管理

### 添加订单

```zig
pub fn addOrder(self: *Level3OrderBook, order: *Order) !void {
    // 获取或创建价格层级
    const level = try self.getOrCreateLevel(order.side, order.price);

    // 计算队列位置
    const position_in_queue = level.orders.len;
    const quantity_ahead = level.total_quantity;

    // 创建 Level3Order
    const l3_order = Level3Order{
        .id = order.id,
        .side = order.side,
        .price = order.price,
        .quantity = order.quantity,
        .remaining_quantity = order.quantity,
        .queue_position = QueuePosition{
            .order_id = order.id,
            .price_level = order.price,
            .position_in_queue = position_in_queue,
            .total_quantity_ahead = quantity_ahead,
            .initial_quantity_ahead = quantity_ahead,
            .order_quantity = order.quantity,
            .queued_at = std.time.nanoTimestamp(),
        },
        .is_mine = order.is_mine,
        .timestamp = order.timestamp,
    };

    // 添加到队列
    const node = try level.orders.append(l3_order);
    try level.order_index.put(order.id, node);

    // 更新总量
    level.total_quantity = level.total_quantity.add(order.quantity);

    // 添加到全局索引
    try self.orders.put(order.id, &node.data);

    if (order.is_mine) {
        try self.my_orders.append(&node.data);
    }

    // 设置原始订单的队列位置引用
    order.queue_position = &node.data.queue_position;
}
```

### 处理成交

```zig
pub fn onTrade(self: *Level3OrderBook, trade: Trade) !void {
    const side = if (trade.aggressor_side == .buy) .ask else .bid;
    const levels = if (side == .bid) &self.bid_levels else &self.ask_levels;

    const level = levels.get(trade.price) orelse return;

    var remaining = trade.quantity;

    // 按 FIFO 消耗订单
    while (remaining.greaterThan(Decimal.zero)) {
        const node = level.orders.first() orelse break;
        const order = &node.data;

        if (order.remaining_quantity.lessThanOrEqual(remaining)) {
            // 完全成交
            remaining = remaining.sub(order.remaining_quantity);
            try self.removeOrderNode(level, node);
        } else {
            // 部分成交
            order.remaining_quantity = order.remaining_quantity.sub(remaining);
            remaining = Decimal.zero;
        }
    }

    // 更新剩余订单的队列位置
    self.updateQueuePositions(level, trade.quantity);

    self.stats.trades_processed += 1;
}
```

### 更新队列位置

```zig
fn updateQueuePositions(self: *Level3OrderBook, level: *PriceLevel, executed: Decimal) void {
    var position: usize = 0;
    var quantity_ahead = Decimal.zero;

    var it = level.orders.first();
    while (it) |node| : (it = node.next) {
        const order = &node.data;
        order.queue_position.position_in_queue = position;
        order.queue_position.total_quantity_ahead = quantity_ahead;
        order.queue_position.cached_normalized = null; // 使缓存失效

        quantity_ahead = quantity_ahead.add(order.remaining_quantity);
        position += 1;
    }

    level.total_quantity = quantity_ahead;
}
```

---

## 成交判定

### 检查我的订单成交

```zig
pub fn checkMyOrderFill(
    self: *Level3OrderBook,
    order: *Level3Order,
    trade: Trade,
    model: QueueModel,
) bool {
    // 检查方向和价格匹配
    if (order.side != trade.side or !order.price.eq(trade.price)) {
        return false;
    }

    // 获取成交概率
    const prob = order.queue_position.fillProbability(model);

    // 概率为 0 直接返回
    if (prob <= 0.0) {
        return false;
    }

    // 概率为 1 直接成交
    if (prob >= 1.0) {
        return true;
    }

    // 随机判定
    const random = self.rng.random().float(f64);
    return random < prob;
}
```

### shouldFill 实现

```zig
pub fn shouldFill(self: QueuePosition, model: QueueModel, random: f64) bool {
    // 队头总是成交
    if (self.isAtFront()) {
        return true;
    }

    // 计算概率
    const prob = self.fillProbability(model);

    // 与随机数比较
    return random < prob;
}
```

### 部分成交处理

```zig
pub fn partialFill(self: *Level3Order, filled_qty: Decimal) void {
    self.remaining_quantity = self.remaining_quantity.sub(filled_qty);

    // 如果是队头且未完全成交，不更新队列位置
    // 否则更新以反映部分消耗
}
```

---

## 性能优化

### 哈希表优化

使用订单 ID 哈希表实现 O(1) 查找:

```zig
pub const Level3OrderBook = struct {
    // 订单 ID → 订单指针
    orders: std.StringHashMap(*Level3Order),

    pub fn getOrder(self: *Level3OrderBook, id: []const u8) ?*Level3Order {
        return self.orders.get(id);
    }
};
```

### 缓存归一化位置

避免重复计算:

```zig
pub fn fillProbability(self: QueuePosition, model: QueueModel) f64 {
    // 使用缓存的归一化位置
    const normalized = self.normalizedPosition();
    return model.probability(normalized);
}
```

### 批量更新优化

```zig
pub fn onTrades(self: *Level3OrderBook, trades: []const Trade) !void {
    // 按价格分组
    var by_price = std.AutoHashMap(Decimal, Decimal).init(self.allocator);
    defer by_price.deinit();

    for (trades) |trade| {
        const entry = try by_price.getOrPutValue(trade.price, Decimal.zero);
        entry.value_ptr.* = entry.value_ptr.*.add(trade.quantity);
    }

    // 批量处理每个价格层级
    var it = by_price.iterator();
    while (it.next()) |entry| {
        try self.processTradesAtPrice(entry.key_ptr.*, entry.value_ptr.*);
    }
}
```

---

## 测试要点

### 关键测试场景

1. **队列位置计算**: 验证添加订单后位置正确
2. **成交后更新**: 验证成交消耗后队列推进
3. **概率模型**: 验证各模型概率计算
4. **边界条件**: 空队列、单订单、满队列

```zig
test "queue position after trade" {
    var book = Level3OrderBook.init(allocator, "TEST");
    defer book.deinit();

    // 添加 3 个订单
    try book.addOrder(&order1); // position: 0
    try book.addOrder(&order2); // position: 1
    try book.addOrder(&order3); // position: 2

    // 模拟成交消耗 order1
    const trade = Trade{ .quantity = order1.quantity, ... };
    try book.onTrade(trade);

    // order2 现在应该在队头
    try testing.expectEqual(@as(usize, 0), order2.queue_position.position_in_queue);
}
```

---

*Last updated: 2025-12-27*
