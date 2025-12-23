# 订单簿 - 功能概览

> 高性能 L2 订单簿实现，支持快速查询和增量更新

**状态**: 🚧 开发中
**版本**: v0.2.0
**Story**: [STORY-008: 订单簿数据结构与维护](../../../stories/v0.2-mvp/008-orderbook.md)
**最后更新**: 2025-12-23

---

## 📋 概述

订单簿（Order Book）是交易系统的核心组件，维护实时的买卖盘数据。本模块提供高性能的 L2 订单簿实现，支持：

- 价格级别聚合（L2 Level）
- 快照同步和增量更新
- 最优价格查询（BBO - Best Bid/Offer）
- 深度和流动性计算
- 滑点预估

### 为什么需要订单簿？

量化交易策略需要：
- **实时价格发现**: 快速查询最优买/卖价，计算中间价和价差
- **流动性评估**: 计算市场深度，评估大单的市场冲击
- **交易决策**: 基于订单簿状态制定交易策略
- **滑点预估**: 在下单前预估执行价格和滑点

### 核心特性

- ✅ **L2 订单簿**: 按价格聚合的订单簿，每个价格级别包含价格、数量和订单数
- ✅ **快照同步**: 从 REST API 获取完整订单簿快照
- ✅ **增量更新**: 通过 WebSocket 实时更新订单簿
- ✅ **高性能查询**: 最优价格查询 O(1)，深度计算 O(n)
- ✅ **滑点计算**: 预估大单执行的平均价格和滑点
- ✅ **线程安全**: 支持多线程并发访问

---

## 🚀 快速开始

### 基本使用

```zig
const std = @import("std");
const OrderBook = @import("core/orderbook.zig").OrderBook;
const Decimal = @import("core/decimal.zig").Decimal;
const Timestamp = @import("core/time.zig").Timestamp;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建订单簿
    var orderbook = try OrderBook.init(allocator, "ETH");
    defer orderbook.deinit();

    // 应用快照
    const bids = &[_]OrderBook.Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("1999.5"), .size = try Decimal.fromString("5.0"), .num_orders = 1 },
    };

    const asks = &[_]OrderBook.Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("2001.5"), .size = try Decimal.fromString("12.0"), .num_orders = 1 },
    };

    try orderbook.applySnapshot(bids, asks, Timestamp.now());

    // 查询最优价格
    if (orderbook.getBestBid()) |best_bid| {
        std.debug.print("Best Bid: {} @ {}\n", .{
            best_bid.size.toFloat(),
            best_bid.price.toFloat(),
        });
    }

    // 获取中间价
    if (orderbook.getMidPrice()) |mid_price| {
        std.debug.print("Mid Price: {}\n", .{mid_price.toFloat()});
    }

    // 计算滑点
    const quantity = try Decimal.fromString("15.0");
    if (orderbook.getSlippage(.bid, quantity)) |slippage| {
        std.debug.print("Buy {} ETH - Avg Price: {}, Slippage: {}%\n", .{
            quantity.toFloat(),
            slippage.avg_price.toFloat(),
            slippage.slippage_pct.toFloat() * 100,
        });
    }
}
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 核心 API

### OrderBook

```zig
pub const OrderBook = struct {
    allocator: std.mem.Allocator,
    symbol: []const u8,
    bids: std.ArrayList(Level),  // 买单（降序）
    asks: std.ArrayList(Level),  // 卖单（升序）
    last_update_time: Timestamp,
    sequence: u64,

    pub const Level = struct {
        price: Decimal,
        size: Decimal,
        num_orders: u32,
    };

    // 初始化和清理
    pub fn init(allocator: std.mem.Allocator, symbol: []const u8) !OrderBook;
    pub fn deinit(self: *OrderBook) void;

    // 更新操作
    pub fn applySnapshot(self: *OrderBook, bids: []const Level, asks: []const Level, timestamp: Timestamp) !void;
    pub fn applyUpdate(self: *OrderBook, side: Side, price: Decimal, size: Decimal, num_orders: u32, timestamp: Timestamp) !void;

    // 查询操作
    pub fn getBestBid(self: *const OrderBook) ?Level;
    pub fn getBestAsk(self: *const OrderBook) ?Level;
    pub fn getMidPrice(self: *const OrderBook) ?Decimal;
    pub fn getSpread(self: *const OrderBook) ?Decimal;
    pub fn getDepth(self: *const OrderBook, side: Side, target_price: Decimal) Decimal;
    pub fn getSlippage(self: *const OrderBook, side: Side, quantity: Decimal) ?SlippageResult;
};
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 使用快照初始化订单簿
const snapshot = try InfoAPI.getL2Book(&client, "ETH");
try orderbook.applySnapshot(snapshot.bids, snapshot.asks, snapshot.time);

// 2. 检查返回值是否为 null
if (orderbook.getBestBid()) |bid| {
    // 使用 bid
} else {
    // 订单簿为空
}

// 3. 使用 defer 确保清理
var orderbook = try OrderBook.init(allocator, "ETH");
defer orderbook.deinit();

// 4. 在计算滑点前检查流动性
const quantity = try Decimal.fromString("100.0");
if (orderbook.getSlippage(.bid, quantity)) |result| {
    // 流动性充足
} else {
    // 流动性不足，无法完全成交
}
```

### ❌ DON'T

```zig
// 1. 不要忘记 deinit
var orderbook = try OrderBook.init(allocator, "ETH");
// 缺少 defer orderbook.deinit(); - 内存泄漏！

// 2. 不要直接访问内部数组
// orderbook.bids.items[0] = level; // 错误！破坏排序
// 使用 applyUpdate 代替

// 3. 不要假设订单簿非空
const bid = orderbook.getBestBid().?; // 可能 panic！
// 使用 if let 解包代替

// 4. 不要在多线程环境下直接访问
// 使用 OrderBookManager 的线程安全接口
```

---

## 🎯 使用场景

### ✅ 适用

- **做市策略**: 需要实时监控最优买卖价，计算价差
- **套利策略**: 需要快速查询多个市场的订单簿状态
- **大单执行**: 需要预估滑点，优化执行策略
- **流动性分析**: 需要计算市场深度，评估流动性
- **价格发现**: 需要实时获取中间价和市场状态

### ❌ 不适用

- **历史数据分析**: 订单簿不持久化历史数据，使用数据库代替
- **L3 订单簿**: 不支持逐单级别的订单簿（Hyperliquid 不提供）
- **订单簿可视化**: 本模块不提供 UI，使用独立的可视化工具

---

## 📊 性能指标

- **快照应用**: < 1ms (100 档)
- **增量更新**: < 0.1ms (单次更新)
- **最优价格查询**: O(1)
- **深度计算**: O(n)，n = 档位数
- **滑点计算**: O(n)，n = 需要的档位数
- **内存占用**: ~100KB (100 档双边)

---

## 💡 未来改进

- [ ] 支持 L3 订单簿（如果交易所提供）
- [ ] 实现订单簿快照持久化
- [ ] 添加订单簿回放功能（用于回测）
- [ ] 实现 VWAP 计算
- [ ] 支持订单簿差异检测
- [ ] 优化内存分配策略

---

*Last updated: 2025-12-23*
