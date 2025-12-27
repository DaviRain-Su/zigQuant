# Queue Position Modeling 队列位置建模

> 真实模拟限价单在订单簿中的成交概率，提升做市策略回测精度

**状态**: 📋 待开发
**版本**: v0.7.0
**Story**: [Story 038](../../stories/v0.7.0/STORY_038_QUEUE_POSITION.md)
**依赖**: [Pure Market Making](../pure-market-making/README.md)
**来源**: HFTBacktest
**最后更新**: 2025-12-27

---

## 概述

队列位置建模 (Queue Position Modeling) 是高频/做市策略回测的关键技术。传统回测假设限价单只要价格触及就能成交，但实际上你的订单可能排在队列后面，需要等待前方订单成交。

### 为什么需要队列位置建模?

```
传统回测 (过于乐观):
  1. 下限价买单 @ $2000
  2. 市场价触及 $2000
  3. 假设立即成交 ✅

问题: 实际上你的订单可能排在队列后面!

队列感知回测 (真实):
  1. 下限价买单 @ $2000
  2. 计算队列位置: 前方有 50 ETH 的订单
  3. 市场成交 30 ETH → 你的订单前进但未成交
  4. 市场再成交 25 ETH → 现在才成交!

影响: Sharpe 比率差异可达 20-30%
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
│ 成交优先级: A → B → C → 你                                       │
└─────────────────────────────────────────────────────────────┘
```

### 核心特性

- **Level-3 订单簿**: 追踪每个订单的位置
- **4 种成交概率模型**: RiskAverse/Probability/PowerLaw/Logarithmic
- **队列位置追踪**: 自动更新前方订单量
- **回测精度提升**: Sharpe 差异从 20-30% 降至 <10%

---

## 快速开始

```zig
const QueuePosition = @import("backtest/queue_position.zig").QueuePosition;
const Level3OrderBook = @import("backtest/level3_orderbook.zig").Level3OrderBook;

// 创建 Level-3 订单簿
var book = Level3OrderBook.init(allocator, "ETH");
defer book.deinit();

// 添加订单 (自动计算队列位置)
try book.addOrder(&my_order);

// 查看队列位置
const pos = my_order.queue_position;
std.debug.print("Position: {}, Ahead: {}\n", .{
    pos.position_in_queue,
    pos.total_quantity_ahead,
});

// 计算成交概率
const prob = pos.fillProbability(.Probability);
```

---

## 核心 API

### QueueModel

```zig
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

### QueuePosition

```zig
pub const QueuePosition = struct {
    order_id: []const u8,
    price_level: Decimal,
    position_in_queue: usize,       // 当前位置 (0 = 队头)
    total_quantity_ahead: Decimal,  // 前方总量
    initial_quantity_ahead: Decimal,

    /// 计算成交概率
    pub fn fillProbability(self: QueuePosition, model: QueueModel) f64;

    /// 推进队列位置 (前方订单成交)
    pub fn advance(self: *QueuePosition, executed_qty: Decimal) void;

    /// 检查是否在队头
    pub fn isAtFront(self: QueuePosition) bool;

    /// 检查是否应该成交
    pub fn shouldFill(self: QueuePosition, model: QueueModel, random: f64) bool;
};
```

### Level3OrderBook

```zig
pub const Level3OrderBook = struct {
    /// 添加订单 (自动计算队列位置)
    pub fn addOrder(self: *Level3OrderBook, order: *Order) !void;

    /// 处理成交事件 (更新队列位置)
    pub fn onTrade(self: *Level3OrderBook, trade: Trade) !void;

    /// 检查我的订单是否应该成交
    pub fn checkMyOrderFill(self: *Level3OrderBook, order: *Order,
                            trade: Trade, model: QueueModel) bool;
};
```

---

## 成交概率模型对比

| 模型 | 公式 | 特点 | 适用场景 |
|------|------|------|----------|
| RiskAverse | x<0.01 ? 1 : 0 | 只有队头成交 | 保守估计 |
| Probability | 1-x | 线性递减 | 一般场景 |
| PowerLaw | 1-x² | 中间更低 | 竞争激烈 |
| Logarithmic | 1-log(1+x)/log(2) | 接近真实 | 高频交易 |

(x = 归一化位置，0=队头，1=队尾)

---

## 相关文档

- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [Bug 追踪](./bugs.md)
- [变更日志](./changelog.md)

---

## 性能指标

| 指标 | 目标值 |
|------|--------|
| 队列操作 | < 1μs |
| 内存开销 | < 10% |
| 回测精度提升 | > 10% |

---

## 参考资料

- [HFTBacktest](https://github.com/nkaz001/hftbacktest) - 原始实现参考

---

*Last updated: 2025-12-27*
