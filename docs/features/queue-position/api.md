# Queue Position API 参考

> 队列位置建模模块的完整 API 文档

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 目录

1. [核心类型](#核心类型)
2. [QueuePosition](#queueposition)
3. [Level3OrderBook](#level3orderbook)
4. [使用示例](#使用示例)

---

## 核心类型

### QueueModel

队列成交概率模型枚举。

```zig
pub const QueueModel = enum {
    /// 保守模型: 只有队头才能成交
    /// 公式: x < 0.01 ? 1.0 : 0.0
    RiskAverse,

    /// 概率模型: 线性递减
    /// 公式: 1.0 - x
    Probability,

    /// 幂函数模型: 中间位置概率更低
    /// 公式: 1.0 - x^2
    PowerLaw,

    /// 对数模型: 接近真实市场行为
    /// 公式: 1.0 - log(1 + x) / log(2)
    Logarithmic,

    /// 计算给定位置的成交概率
    pub fn probability(self: QueueModel, normalized_position: f64) f64;
};
```

### QueuePosition

队列位置结构。

```zig
pub const QueuePosition = struct {
    /// 订单 ID
    order_id: []const u8,

    /// 价格层级
    price_level: Decimal,

    /// 当前队列位置 (0 = 队头)
    position_in_queue: usize,

    /// 前方总订单数量
    total_quantity_ahead: Decimal,

    /// 初始前方数量 (用于计算进度)
    initial_quantity_ahead: Decimal,

    /// 订单自身数量
    order_quantity: Decimal,

    /// 进入队列时间
    queued_at: i64,

    /// 计算成交概率
    pub fn fillProbability(self: QueuePosition, model: QueueModel) f64;

    /// 推进队列位置
    pub fn advance(self: *QueuePosition, executed_qty: Decimal) void;

    /// 检查是否在队头
    pub fn isAtFront(self: QueuePosition) bool;

    /// 检查是否应该成交
    pub fn shouldFill(self: QueuePosition, model: QueueModel, random: f64) bool;

    /// 获取归一化位置 (0.0 - 1.0)
    pub fn normalizedPosition(self: QueuePosition) f64;

    /// 获取队列进度 (已消耗的前方数量比例)
    pub fn progress(self: QueuePosition) f64;
};
```

### Level3Order

Level-3 订单结构。

```zig
pub const Level3Order = struct {
    /// 订单 ID
    id: []const u8,

    /// 订单方向
    side: OrderSide,

    /// 价格
    price: Decimal,

    /// 数量
    quantity: Decimal,

    /// 剩余数量
    remaining_quantity: Decimal,

    /// 队列位置信息
    queue_position: QueuePosition,

    /// 是否是我的订单
    is_mine: bool,

    /// 时间戳
    timestamp: i64,
};
```

### PriceLevel

价格层级结构。

```zig
pub const PriceLevel = struct {
    /// 价格
    price: Decimal,

    /// 订单队列
    orders: std.ArrayList(Level3Order),

    /// 总数量
    total_quantity: Decimal,

    /// 订单数量
    order_count: usize,

    /// 获取队列长度
    pub fn queueLength(self: PriceLevel) usize;

    /// 获取指定订单的位置
    pub fn getPosition(self: *PriceLevel, order_id: []const u8) ?*QueuePosition;
};
```

---

## QueuePosition

### fillProbability

```zig
pub fn fillProbability(self: QueuePosition, model: QueueModel) f64
```

计算当前位置的成交概率。

**参数**:
- `model`: 使用的概率模型

**返回**: 成交概率 (0.0 - 1.0)

**示例**:
```zig
const pos = QueuePosition{
    .position_in_queue = 3,
    .total_quantity_ahead = Decimal.fromFloat(50.0),
    .initial_quantity_ahead = Decimal.fromFloat(100.0),
};

const prob = pos.fillProbability(.Probability);
// 归一化位置 = 50/100 = 0.5
// 概率 = 1 - 0.5 = 0.5
```

### advance

```zig
pub fn advance(self: *QueuePosition, executed_qty: Decimal) void
```

推进队列位置（前方订单成交后调用）。

**参数**:
- `executed_qty`: 前方成交的数量

**示例**:
```zig
var pos = QueuePosition{
    .position_in_queue = 5,
    .total_quantity_ahead = Decimal.fromFloat(50.0),
};

pos.advance(Decimal.fromFloat(10.0));
// 现在: position_in_queue = 4, total_quantity_ahead = 40.0
```

### shouldFill

```zig
pub fn shouldFill(self: QueuePosition, model: QueueModel, random: f64) bool
```

判断订单是否应该成交。

**参数**:
- `model`: 概率模型
- `random`: 随机数 (0.0 - 1.0)

**返回**: 是否成交

**示例**:
```zig
var rng = std.rand.DefaultPrng.init(seed);

if (pos.shouldFill(.Probability, rng.random().float(f64))) {
    // 执行成交逻辑
}
```

---

## Level3OrderBook

Level-3 订单簿（包含队列位置信息）。

### init

```zig
pub fn init(allocator: Allocator, symbol: []const u8) Level3OrderBook
```

创建 Level-3 订单簿。

**参数**:
- `allocator`: 内存分配器
- `symbol`: 交易对符号

### deinit

```zig
pub fn deinit(self: *Level3OrderBook) void
```

释放资源。

### addOrder

```zig
pub fn addOrder(self: *Level3OrderBook, order: *Order) !void
```

添加订单到订单簿（自动计算队列位置）。

**参数**:
- `order`: 订单指针（会设置 queue_position 字段）

**示例**:
```zig
var order = Order{
    .id = "order_123",
    .side = .buy,
    .price = Decimal.fromFloat(2000.0),
    .quantity = Decimal.fromFloat(1.0),
};

try book.addOrder(&order);

// order.queue_position 现在包含队列信息
std.debug.print("队列位置: {}, 前方数量: {}\n", .{
    order.queue_position.position_in_queue,
    order.queue_position.total_quantity_ahead,
});
```

### removeOrder

```zig
pub fn removeOrder(self: *Level3OrderBook, order_id: []const u8) !void
```

从订单簿移除订单。

### onTrade

```zig
pub fn onTrade(self: *Level3OrderBook, trade: Trade) !void
```

处理成交事件（更新队列位置）。

**参数**:
- `trade`: 成交信息

**说明**: 成交会消耗价格层级的订单，更新剩余订单的队列位置。

**示例**:
```zig
const trade = Trade{
    .price = Decimal.fromFloat(2000.0),
    .quantity = Decimal.fromFloat(5.0),
    .side = .buy,
};

try book.onTrade(trade);
// 所有 $2000 买单的队列位置会更新
```

### checkMyOrderFill

```zig
pub fn checkMyOrderFill(
    self: *Level3OrderBook,
    order: *Order,
    trade: Trade,
    model: QueueModel,
) bool
```

检查我的订单是否应该在此成交中被成交。

**参数**:
- `order`: 我的订单
- `trade`: 当前成交
- `model`: 概率模型

**返回**: 是否应该成交

**示例**:
```zig
if (book.checkMyOrderFill(&my_order, trade, .Probability)) {
    // 执行我的订单成交逻辑
    handleFill(&my_order, trade);
}
```

### getQueuePosition

```zig
pub fn getQueuePosition(
    self: *Level3OrderBook,
    order_id: []const u8,
) ?QueuePosition
```

获取指定订单的队列位置。

### getBestBid / getBestAsk

```zig
pub fn getBestBid(self: *Level3OrderBook) ?PriceLevel
pub fn getBestAsk(self: *Level3OrderBook) ?PriceLevel
```

获取最优买/卖价格层级。

### getDepth

```zig
pub fn getDepth(self: *Level3OrderBook, levels: u32) Depth
```

获取订单簿深度。

---

## 使用示例

### 基本使用

```zig
const std = @import("std");
const Level3OrderBook = @import("backtest/level3_orderbook.zig").Level3OrderBook;
const QueueModel = @import("backtest/queue_position.zig").QueueModel;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建订单簿
    var book = Level3OrderBook.init(allocator, "ETH-USD");
    defer book.deinit();

    // 添加一些市场订单
    try addMarketOrders(&book);

    // 添加我的订单
    var my_order = Order{
        .id = "my_order_1",
        .side = .buy,
        .price = Decimal.fromFloat(2000.0),
        .quantity = Decimal.fromFloat(1.0),
        .is_mine = true,
    };
    try book.addOrder(&my_order);

    std.debug.print("我的订单队列位置: {}\n", .{
        my_order.queue_position.position_in_queue,
    });
    std.debug.print("前方数量: {}\n", .{
        my_order.queue_position.total_quantity_ahead,
    });

    // 模拟成交
    const trade = Trade{
        .price = Decimal.fromFloat(2000.0),
        .quantity = Decimal.fromFloat(10.0),
        .side = .buy,
    };

    if (book.checkMyOrderFill(&my_order, trade, .Probability)) {
        std.debug.print("我的订单成交!\n", .{});
    } else {
        try book.onTrade(trade);
        std.debug.print("更新后队列位置: {}\n", .{
            my_order.queue_position.position_in_queue,
        });
    }
}
```

### 回测集成

```zig
pub const QueueAwareBacktest = struct {
    book: Level3OrderBook,
    model: QueueModel,
    rng: std.rand.DefaultPrng,

    pub fn processMarketData(self: *QueueAwareBacktest, event: MarketEvent) !void {
        switch (event.event_type) {
            .trade => {
                const trade = event.trade.?;

                // 检查我的订单是否成交
                for (self.my_orders.items) |*order| {
                    if (self.book.checkMyOrderFill(order, trade, self.model)) {
                        try self.onFill(order, trade);
                    }
                }

                // 更新订单簿
                try self.book.onTrade(trade);
            },
            .order_add => try self.book.addOrder(event.order.?),
            .order_cancel => try self.book.removeOrder(event.order_id.?),
            // ...
        }
    }
};
```

### 概率模型比较

```zig
pub fn compareModels(position: QueuePosition) void {
    const models = [_]QueueModel{ .RiskAverse, .Probability, .PowerLaw, .Logarithmic };

    std.debug.print("归一化位置: {d:.2}\n", .{position.normalizedPosition()});
    std.debug.print("\n模型比较:\n", .{});

    for (models) |model| {
        const prob = position.fillProbability(model);
        std.debug.print("  {s}: {d:.2}%\n", .{
            @tagName(model),
            prob * 100,
        });
    }
}
```

---

## 错误处理

```zig
pub const QueueError = error{
    /// 订单不存在
    OrderNotFound,

    /// 价格层级不存在
    PriceLevelNotFound,

    /// 无效的队列位置
    InvalidPosition,

    /// 订单簿状态不一致
    InconsistentState,
};
```

---

## 性能说明

| 操作 | 时间复杂度 | 预期延迟 |
|------|------------|----------|
| addOrder | O(1) amortized | < 500ns |
| removeOrder | O(n) | < 1μs |
| onTrade | O(k) | < 1μs |
| checkMyOrderFill | O(1) | < 100ns |
| fillProbability | O(1) | < 50ns |

其中:
- n = 价格层级的订单数
- k = 受影响的订单数

---

*Last updated: 2025-12-27*
