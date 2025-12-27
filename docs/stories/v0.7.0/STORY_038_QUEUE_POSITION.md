# Story 038: Queue Position Modeling 队列位置建模

**版本**: v0.7.0
**状态**: 待开发
**优先级**: P1
**预计时间**: 3-4 天
**依赖**: Story 034 (Pure Market Making)
**来源**: HFTBacktest

---

## 概述

实现订单队列位置建模，真实反映限价单在订单簿中的成交概率。这是做市策略回测精度的关键，可使回测 Sharpe 与实盘差异从 20-30% 降低到 10% 以内。

---

## 背景

### 为什么需要队列位置建模？

```
┌─────────────────────────────────────────────────────────────────┐
│                     传统回测 vs 队列感知回测                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  传统回测 (过于乐观):                                           │
│  ────────────────────────────────────────                       │
│  1. 下限价买单 @ $2000                                          │
│  2. 市场价触及 $2000                                            │
│  3. ✅ 假设立即成交                                             │
│                                                                  │
│  问题: 实际上你的订单可能排在队列后面!                          │
│                                                                  │
│  队列感知回测 (真实):                                           │
│  ────────────────────────────────────────                       │
│  1. 下限价买单 @ $2000                                          │
│  2. 计算队列位置: 前方有 50 ETH 的订单                          │
│  3. 市场成交 30 ETH → 你的订单前进但未成交                      │
│  4. 市场再成交 25 ETH → 现在才成交!                             │
│                                                                  │
│  影响: Sharpe 比率差异 20-30%                                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 订单簿队列可视化

```
价格 $2000 的买单队列:
┌─────────────────────────────────────────────────────────────┐
│ [Order A: 10 ETH] [Order B: 15 ETH] [Order C: 25 ETH] [你: 5 ETH] │
│      队头 ←─────────────────────────────────────────→ 队尾        │
│                                                                   │
│ 你前方总量: 50 ETH                                                │
│ 你的位置: 第 4 位                                                 │
│                                                                   │
│ 成交优先级: A → B → C → 你                                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 技术设计

### 核心组件

```
┌─────────────────────────────────────────────────────────────────┐
│                   Queue Position 架构                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   QueuePosition                           │  │
│  │  • order_id: 订单 ID                                      │  │
│  │  • price_level: 价格层级                                  │  │
│  │  • position_in_queue: 队列位置 (0=队头)                   │  │
│  │  • total_quantity_ahead: 前方总量                         │  │
│  │                                                            │  │
│  │  Methods:                                                  │  │
│  │  • fillProbability(model) → f64                           │  │
│  │  • advance(executed_qty)                                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   Level3OrderBook                         │  │
│  │  • bids: BTreeMap(Decimal, PriceLevel)                   │  │
│  │  • asks: BTreeMap(Decimal, PriceLevel)                   │  │
│  │                                                            │  │
│  │  PriceLevel:                                              │  │
│  │  • price: Decimal                                         │  │
│  │  • orders: ArrayList(*Order)  ← Level-3 数据             │  │
│  │  • total_quantity: Decimal                                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 队列模型

```zig
/// 队列成交概率模型
pub const QueueModel = enum {
    /// 保守模型: 假设在队尾，几乎不成交
    RiskAverse,

    /// 概率模型: 线性分布，位置越靠前概率越高
    Probability,

    /// 幂函数模型: x^2，中间位置成交概率更低
    PowerLaw,

    /// 对数模型: log(1+x)，更接近真实市场
    Logarithmic,
};
```

### QueuePosition 实现

```zig
const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;

/// 订单队列位置
pub const QueuePosition = struct {
    order_id: []const u8,
    price_level: Decimal,
    position_in_queue: usize,       // 当前位置 (0 = 队头)
    total_quantity_ahead: Decimal,  // 前方总量
    initial_quantity_ahead: Decimal, // 初始前方总量 (用于计算)

    const Self = @This();

    /// 计算成交概率
    pub fn fillProbability(self: Self, model: QueueModel) f64 {
        if (self.total_quantity_ahead.isZero()) {
            return 1.0;  // 队头，100% 成交
        }

        // 归一化位置 (0.0 = 队头, 1.0 = 队尾)
        const x = self.total_quantity_ahead.toFloat() /
                  self.initial_quantity_ahead.toFloat();

        return switch (model) {
            .RiskAverse => if (x < 0.01) 1.0 else 0.0,
            .Probability => 1.0 - x,
            .PowerLaw => 1.0 - std.math.pow(f64, x, 2.0),
            .Logarithmic => 1.0 - (@log(1.0 + x) / @log(2.0)),
        };
    }

    /// 推进队列位置 (当前方订单成交/撤单)
    pub fn advance(self: *Self, executed_qty: Decimal) void {
        if (executed_qty.compare(self.total_quantity_ahead) != .lt) {
            // 前方订单全部清空
            self.position_in_queue = 0;
            self.total_quantity_ahead = Decimal.zero;
        } else {
            // 部分推进
            self.total_quantity_ahead = self.total_quantity_ahead.sub(executed_qty);
            // 估算位置变化
            if (self.position_in_queue > 0) {
                self.position_in_queue -= 1;
            }
        }
    }

    /// 检查是否在队头
    pub fn isAtFront(self: Self) bool {
        return self.position_in_queue == 0 or self.total_quantity_ahead.isZero();
    }

    /// 检查是否应该成交 (基于模型和随机数)
    pub fn shouldFill(self: Self, model: QueueModel, random: f64) bool {
        return random < self.fillProbability(model);
    }
};
```

### Level-3 OrderBook 实现

```zig
/// Level-3 订单簿 (Market-By-Order)
pub const Level3OrderBook = struct {
    allocator: Allocator,
    symbol: []const u8,
    bids: std.AutoArrayHashMap(i64, PriceLevel),  // price → level
    asks: std.AutoArrayHashMap(i64, PriceLevel),

    pub const PriceLevel = struct {
        price: Decimal,
        orders: std.ArrayList(*Order),
        total_quantity: Decimal,

        /// 添加订单到队尾
        pub fn addOrder(self: *PriceLevel, order: *Order) !void {
            // 计算队列位置
            var qty_ahead = Decimal.zero;
            for (self.orders.items) |existing| {
                qty_ahead = qty_ahead.add(existing.remaining_quantity);
            }

            // 设置队列位置
            order.queue_position = QueuePosition{
                .order_id = order.client_order_id,
                .price_level = self.price,
                .position_in_queue = self.orders.items.len,
                .total_quantity_ahead = qty_ahead,
                .initial_quantity_ahead = qty_ahead,
            };

            try self.orders.append(order);
            self.total_quantity = self.total_quantity.add(order.quantity);
        }

        /// 移除订单
        pub fn removeOrder(self: *PriceLevel, order_id: []const u8) ?*Order {
            for (self.orders.items, 0..) |order, i| {
                if (std.mem.eql(u8, order.client_order_id, order_id)) {
                    const removed = self.orders.orderedRemove(i);
                    self.total_quantity = self.total_quantity.sub(removed.quantity);

                    // 更新后续订单的队列位置
                    for (self.orders.items[i..]) |subsequent| {
                        subsequent.queue_position.position_in_queue -= 1;
                        subsequent.queue_position.total_quantity_ahead =
                            subsequent.queue_position.total_quantity_ahead.sub(removed.quantity);
                    }

                    return removed;
                }
            }
            return null;
        }
    };

    const Self = @This();

    pub fn init(allocator: Allocator, symbol: []const u8) Self {
        return .{
            .allocator = allocator,
            .symbol = symbol,
            .bids = std.AutoArrayHashMap(i64, PriceLevel).init(allocator),
            .asks = std.AutoArrayHashMap(i64, PriceLevel).init(allocator),
        };
    }

    /// 添加订单
    pub fn addOrder(self: *Self, order: *Order) !void {
        const book = if (order.side == .buy) &self.bids else &self.asks;
        const price_key = order.price.toRawInt();

        const level = book.getPtr(price_key) orelse blk: {
            try book.put(price_key, PriceLevel{
                .price = order.price,
                .orders = std.ArrayList(*Order).init(self.allocator),
                .total_quantity = Decimal.zero,
            });
            break :blk book.getPtr(price_key).?;
        };

        try level.addOrder(order);
    }

    /// 处理成交事件 (更新队列位置)
    pub fn onTrade(self: *Self, trade: Trade) !void {
        const book = if (trade.side == .buy) &self.asks else &self.bids;
        const price_key = trade.price.toRawInt();

        if (book.getPtr(price_key)) |level| {
            var remaining = trade.quantity;

            // 从队头开始成交
            while (remaining.toFloat() > 0 and level.orders.items.len > 0) {
                const front_order = level.orders.items[0];
                const fill_qty = if (remaining.compare(front_order.remaining_quantity) == .lt)
                    remaining
                else
                    front_order.remaining_quantity;

                // 更新订单
                front_order.remaining_quantity = front_order.remaining_quantity.sub(fill_qty);
                remaining = remaining.sub(fill_qty);

                // 订单完全成交，移除
                if (front_order.remaining_quantity.isZero()) {
                    _ = level.orders.orderedRemove(0);

                    // 更新后续订单队列位置
                    for (level.orders.items) |order| {
                        order.queue_position.advance(fill_qty);
                    }
                }
            }

            level.total_quantity = level.total_quantity.sub(trade.quantity);
        }
    }

    /// 检查我的订单是否应该成交
    pub fn checkMyOrderFill(
        self: *Self,
        order: *Order,
        trade: Trade,
        model: QueueModel,
    ) bool {
        // 只有价格匹配才可能成交
        if (!order.price.equals(trade.price)) return false;

        // 只有对手方成交才影响我的订单
        if (order.side == trade.side) return false;

        // 基于队列位置计算成交概率
        const prob = order.queue_position.fillProbability(model);

        // 使用确定性判断 (或随机数)
        return order.queue_position.isAtFront() or prob > 0.9;
    }
};
```

---

## 实现任务

### Task 1: QueuePosition 结构 (Day 1)

- [ ] 创建 `src/backtest/queue_position.zig`
- [ ] 实现 QueuePosition struct
- [ ] 实现 4 种队列模型
- [ ] 添加单元测试

### Task 2: Level3OrderBook (Day 1-2)

- [ ] 创建 `src/backtest/level3_orderbook.zig`
- [ ] 实现 PriceLevel 结构
- [ ] 实现 addOrder/removeOrder
- [ ] 实现队列位置自动计算

### Task 3: 成交模拟 (Day 2-3)

- [ ] 实现 onTrade 事件处理
- [ ] 实现队列推进逻辑
- [ ] 实现 checkMyOrderFill
- [ ] 集成到回测引擎

### Task 4: 测试和验证 (Day 3-4)

- [ ] 与传统回测对比测试
- [ ] Sharpe 差异验证
- [ ] 性能基准测试
- [ ] 文档编写

---

## 测试计划

### 单元测试

```zig
test "QueuePosition fill probability" {
    var pos = QueuePosition{
        .order_id = "test",
        .price_level = Decimal.fromInt(2000),
        .position_in_queue = 5,
        .total_quantity_ahead = Decimal.fromFloat(50.0),
        .initial_quantity_ahead = Decimal.fromFloat(50.0),
    };

    // 队列中间位置
    const prob = pos.fillProbability(.Probability);
    try testing.expect(prob < 1.0 and prob > 0.0);

    // 推进到队头
    pos.advance(Decimal.fromFloat(50.0));
    try testing.expect(pos.isAtFront());
    try testing.expect(pos.fillProbability(.Probability) == 1.0);
}

test "Level3OrderBook queue management" {
    var book = Level3OrderBook.init(testing.allocator, "ETH");
    defer book.deinit();

    // 添加三个订单
    var order1 = Order{ .quantity = Decimal.fromFloat(10.0), ... };
    var order2 = Order{ .quantity = Decimal.fromFloat(15.0), ... };
    var order3 = Order{ .quantity = Decimal.fromFloat(25.0), ... };

    try book.addOrder(&order1);
    try book.addOrder(&order2);
    try book.addOrder(&order3);

    // 验证队列位置
    try testing.expect(order1.queue_position.position_in_queue == 0);
    try testing.expect(order2.queue_position.position_in_queue == 1);
    try testing.expect(order3.queue_position.position_in_queue == 2);
    try testing.expect(order3.queue_position.total_quantity_ahead.toFloat() == 25.0);
}
```

### 场景测试

| 场景 | 传统回测 | 队列感知 | 验证 |
|------|----------|----------|------|
| 队头订单 | 成交 | 成交 | ✓ |
| 队中订单 | 成交 | 可能不成交 | ✓ |
| 队尾订单 | 成交 | 很可能不成交 | ✓ |

---

## 验收标准

### 功能验收

- [ ] 4 种队列模型正确实现
- [ ] 队列位置自动追踪
- [ ] 成交事件正确推进队列
- [ ] 与回测引擎集成

### 性能验收

- [ ] 队列操作 < 1μs
- [ ] 内存开销 < 10%
- [ ] 不影响回测速度

### 精度验收

- [ ] 回测 vs 实盘 Sharpe 差异 < 10%
- [ ] 做市策略收益预测更准确

---

## 参考资料

- [HFTBacktest - Queue Position](https://github.com/nkaz001/hftbacktest)
- [架构模式文档](../../architecture/ARCHITECTURE_PATTERNS.md#queue-position-modeling-队列位置建模)

---

**Story**: 038
**版本**: v0.7.0
**创建时间**: 2025-12-27
