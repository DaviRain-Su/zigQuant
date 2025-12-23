# Story: 订单簿数据结构与维护

**ID**: `STORY-008`
**版本**: `v0.2`
**创建日期**: 2025-12-23
**状态**: 📋 计划中
**优先级**: P1 (重要)
**预计工时**: 3 天

---

## 📋 需求描述

### 用户故事
作为**量化交易开发者**，我希望**有一个高效的订单簿数据结构**，以便**维护市场深度并快速查询最优价格**。

### 背景
订单簿（Order Book）是交易所的核心数据结构，记录所有挂单信息：
- **买单（Bids）**: 从高到低排序
- **卖单（Asks）**: 从低到高排序

量化策略需要：
- 快速查询最优买/卖价
- 计算市场深度和流动性
- 检测价格变化和成交机会

### 范围
- **包含**:
  - 订单簿数据结构（L2 价格聚合）
  - 增量更新处理（WebSocket 数据）
  - 快照同步（REST API 数据）
  - 最优价格查询（BBO - Best Bid/Offer）
  - 深度计算
  - 中间价计算

- **不包含**:
  - L3 订单簿（逐单级别，Hyperliquid 不提供）
  - 订单簿可视化（UI）
  - 历史订单簿数据存储

---

## 🎯 验收标准

- [ ] 订单簿数据结构定义完成
- [ ] 支持增量更新（WebSocket L2 数据）
- [ ] 支持快照同步（REST API 数据）
- [ ] 最优价格查询正确（BBO）
- [ ] 深度计算正确（到指定价格的累计量）
- [ ] 中间价计算正确（(bid + ask) / 2）
- [ ] 更新性能满足要求（< 1ms）
- [ ] 所有测试用例通过

---

## 🔧 技术设计

### 架构概览

```
src/core/
├── orderbook.zig         # 订单簿核心
├── orderbook_level.zig   # 价格档位
└── orderbook_test.zig    # 测试
```

### 核心数据结构

#### 1. 订单簿

```zig
// src/core/orderbook.zig

const std = @import("std");
const Decimal = @import("decimal.zig").Decimal;
const Timestamp = @import("time.zig").Timestamp;

/// 价格档位（Level）
pub const Level = struct {
    price: Decimal,
    size: Decimal,
    num_orders: u32, // 该价位的订单数量

    pub fn lessThan(context: void, a: Level, b: Level) bool {
        _ = context;
        return a.price.cmp(b.price) == .lt;
    }

    pub fn greaterThan(context: void, a: Level, b: Level) bool {
        _ = context;
        return a.price.cmp(b.price) == .gt;
    }
};

/// 订单簿（L2）
pub const OrderBook = struct {
    allocator: std.mem.Allocator,
    symbol: []const u8,

    // 买单：从高到低排序（最高买价在前）
    bids: std.ArrayList(Level),

    // 卖单：从低到高排序（最低卖价在前）
    asks: std.ArrayList(Level),

    // 元数据
    last_update_time: Timestamp,
    sequence: u64, // 序列号，用于检测丢失的更新

    pub fn init(allocator: std.mem.Allocator, symbol: []const u8) !OrderBook {
        return .{
            .allocator = allocator,
            .symbol = try allocator.dupe(u8, symbol),
            .bids = std.ArrayList(Level).init(allocator),
            .asks = std.ArrayList(Level).init(allocator),
            .last_update_time = Timestamp.now(),
            .sequence = 0,
        };
    }

    pub fn deinit(self: *OrderBook) void {
        self.allocator.free(self.symbol);
        self.bids.deinit();
        self.asks.deinit();
    }

    /// 应用快照（完全替换）
    pub fn applySnapshot(
        self: *OrderBook,
        bids: []const Level,
        asks: []const Level,
        timestamp: Timestamp,
    ) !void {
        // 清空现有数据
        self.bids.clearRetainingCapacity();
        self.asks.clearRetainingCapacity();

        // 插入买单（从高到低排序）
        try self.bids.appendSlice(bids);
        std.mem.sort(Level, self.bids.items, {}, Level.greaterThan);

        // 插入卖单（从低到高排序）
        try self.asks.appendSlice(asks);
        std.mem.sort(Level, self.asks.items, {}, Level.lessThan);

        self.last_update_time = timestamp;
    }

    /// 应用增量更新
    pub fn applyUpdate(
        self: *OrderBook,
        side: Side,
        price: Decimal,
        size: Decimal,
        num_orders: u32,
        timestamp: Timestamp,
    ) !void {
        const levels = if (side == .bid) &self.bids else &self.asks;

        if (size.isZero()) {
            // 移除该价位
            try self.removeLevel(levels, price);
        } else {
            // 更新或插入
            try self.upsertLevel(levels, .{
                .price = price,
                .size = size,
                .num_orders = num_orders,
            }, side);
        }

        self.last_update_time = timestamp;
        self.sequence += 1;
    }

    /// 获取最优买价（Best Bid）
    pub fn getBestBid(self: *const OrderBook) ?Level {
        if (self.bids.items.len == 0) return null;
        return self.bids.items[0];
    }

    /// 获取最优卖价（Best Ask）
    pub fn getBestAsk(self: *const OrderBook) ?Level {
        if (self.asks.items.len == 0) return null;
        return self.asks.items[0];
    }

    /// 获取中间价
    pub fn getMidPrice(self: *const OrderBook) ?Decimal {
        const bid = self.getBestBid() orelse return null;
        const ask = self.getBestAsk() orelse return null;

        return bid.price.add(ask.price).div(Decimal.fromInt(2)) catch unreachable;
    }

    /// 获取价差（Spread）
    pub fn getSpread(self: *const OrderBook) ?Decimal {
        const bid = self.getBestBid() orelse return null;
        const ask = self.getBestAsk() orelse return null;

        return ask.price.sub(bid.price);
    }

    /// 计算深度（到指定价格的累计量）
    pub fn getDepth(self: *const OrderBook, side: Side, target_price: Decimal) Decimal {
        const levels = if (side == .bid) self.bids.items else self.asks.items;
        var total = Decimal.ZERO;

        for (levels) |level| {
            const should_include = switch (side) {
                .bid => level.price.cmp(target_price) != .lt, // >= target_price
                .ask => level.price.cmp(target_price) != .gt, // <= target_price
            };

            if (should_include) {
                total = total.add(level.size);
            } else {
                break;
            }
        }

        return total;
    }

    /// 计算滑点（执行指定数量的预期平均价格）
    pub fn getSlippage(
        self: *const OrderBook,
        side: Side,
        quantity: Decimal,
    ) ?SlippageResult {
        const levels = if (side == .bid) self.asks.items else self.bids.items;
        var remaining = quantity;
        var total_cost = Decimal.ZERO;
        var avg_price: Decimal = undefined;

        for (levels) |level| {
            const fill_qty = if (remaining.cmp(level.size) == .gt)
                level.size
            else
                remaining;

            total_cost = total_cost.add(fill_qty.mul(level.price));
            remaining = remaining.sub(fill_qty);

            if (remaining.isZero()) {
                avg_price = total_cost.div(quantity) catch return null;
                break;
            }
        } else {
            // 流动性不足
            return null;
        }

        const best_price = if (side == .bid)
            self.getBestAsk().?.price
        else
            self.getBestBid().?.price;

        const slippage = avg_price.sub(best_price).div(best_price) catch unreachable;

        return SlippageResult{
            .avg_price = avg_price,
            .slippage_pct = slippage,
            .total_cost = total_cost,
        };
    }

    // 内部辅助函数
    fn removeLevel(self: *OrderBook, levels: *std.ArrayList(Level), price: Decimal) !void {
        for (levels.items, 0..) |level, i| {
            if (level.price.eql(price)) {
                _ = levels.swapRemove(i);
                return;
            }
        }
    }

    fn upsertLevel(
        self: *OrderBook,
        levels: *std.ArrayList(Level),
        new_level: Level,
        side: Side,
    ) !void {
        // 查找是否存在
        for (levels.items, 0..) |*level, i| {
            if (level.price.eql(new_level.price)) {
                // 更新
                level.* = new_level;
                return;
            }
        }

        // 插入新档位
        try levels.append(new_level);

        // 重新排序
        const cmp_fn = if (side == .bid) Level.greaterThan else Level.lessThan;
        std.mem.sort(Level, levels.items, {}, cmp_fn);
    }
};

pub const Side = enum {
    bid,
    ask,
};

pub const SlippageResult = struct {
    avg_price: Decimal,
    slippage_pct: Decimal, // 百分比（0.01 = 1%）
    total_cost: Decimal,
};
```

#### 2. 订单簿管理器

```zig
// src/core/orderbook_manager.zig

const std = @import("std");
const OrderBook = @import("orderbook.zig").OrderBook;

/// 管理多个币种的订单簿
pub const OrderBookManager = struct {
    allocator: std.mem.Allocator,
    orderbooks: std.StringHashMap(*OrderBook),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) OrderBookManager {
        return .{
            .allocator = allocator,
            .orderbooks = std.StringHashMap(*OrderBook).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *OrderBookManager) void {
        var iter = self.orderbooks.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.orderbooks.deinit();
    }

    /// 获取或创建订单簿
    pub fn getOrCreate(self: *OrderBookManager, symbol: []const u8) !*OrderBook {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.orderbooks.get(symbol)) |ob| {
            return ob;
        }

        const ob = try self.allocator.create(OrderBook);
        ob.* = try OrderBook.init(self.allocator, symbol);
        try self.orderbooks.put(symbol, ob);

        return ob;
    }

    /// 获取订单簿（只读）
    pub fn get(self: *OrderBookManager, symbol: []const u8) ?*OrderBook {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.orderbooks.get(symbol);
    }
};
```

---

## 📝 任务分解

### Phase 1: 核心数据结构 📋
- [ ] 任务 1.1: 定义 Level 结构体
- [ ] 任务 1.2: 定义 OrderBook 结构体
- [ ] 任务 1.3: 实现快照同步（applySnapshot）
- [ ] 任务 1.4: 实现增量更新（applyUpdate）

### Phase 2: 查询功能 📋
- [ ] 任务 2.1: 实现最优价格查询（BBO）
- [ ] 任务 2.2: 实现中间价计算
- [ ] 任务 2.3: 实现价差计算
- [ ] 任务 2.4: 实现深度计算
- [ ] 任务 2.5: 实现滑点计算

### Phase 3: 订单簿管理器 📋
- [ ] 任务 3.1: 实现 OrderBookManager
- [ ] 任务 3.2: 实现多币种管理
- [ ] 任务 3.3: 实现线程安全访问

### Phase 4: 测试与优化 📋
- [ ] 任务 4.1: 编写单元测试
- [ ] 任务 4.2: 性能测试（更新速度）
- [ ] 任务 4.3: 内存优化
- [ ] 任务 4.4: 更新文档
- [ ] 任务 4.5: 代码审查

---

## 🧪 测试策略

### 单元测试

```zig
test "OrderBook: apply snapshot" {
    var ob = try OrderBook.init(testing.allocator, "ETH");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("1999.5"), .size = try Decimal.fromString("5.0"), .num_orders = 1 },
    };

    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("2001.5"), .size = try Decimal.fromString("12.0"), .num_orders = 1 },
    };

    try ob.applySnapshot(bids, asks, Timestamp.now());

    // 验证排序
    try testing.expect(ob.bids.items[0].price.toFloat() == 2000.0);
    try testing.expect(ob.asks.items[0].price.toFloat() == 2001.0);
}

test "OrderBook: best bid/ask" {
    var ob = try OrderBook.init(testing.allocator, "ETH");
    defer ob.deinit();

    // ... 应用快照 ...

    const best_bid = ob.getBestBid().?;
    const best_ask = ob.getBestAsk().?;

    try testing.expect(best_bid.price.toFloat() == 2000.0);
    try testing.expect(best_ask.price.toFloat() == 2001.0);
}

test "OrderBook: mid price" {
    var ob = try OrderBook.init(testing.allocator, "ETH");
    defer ob.deinit();

    // ... 应用快照 ...

    const mid = ob.getMidPrice().?;
    try testing.expect(mid.toFloat() == 2000.5); // (2000 + 2001) / 2
}

test "OrderBook: slippage calculation" {
    var ob = try OrderBook.init(testing.allocator, "ETH");
    defer ob.deinit();

    // ... 应用快照 ...

    const quantity = try Decimal.fromString("15.0");
    const result = ob.getSlippage(.bid, quantity).?;

    // 验证平均价格和滑点
    std.debug.print("Avg Price: {}, Slippage: {}%\n", .{
        result.avg_price.toFloat(),
        result.slippage_pct.toFloat() * 100,
    });
}
```

---

## 📚 相关文档

### 设计文档
- [ ] `docs/features/orderbook/README.md` - 订单簿概览
- [ ] `docs/features/orderbook/api-reference.md` - API 参考
- [ ] `docs/features/orderbook/performance.md` - 性能优化

### 参考资料
- [Order Book Design Patterns](https://web.archive.org/web/20110219163448/http://howtohft.wordpress.com/2011/02/15/how-to-build-a-fast-limit-order-book/)
- Hyperliquid L2 Book Format

---

## 🔗 依赖关系

### 前置条件
- [x] Story 001: Decimal 类型
- [x] Story 002: Time Utils
- [ ] Story 007: Hyperliquid WebSocket（提供增量更新）
- [ ] Story 006: Hyperliquid HTTP（提供快照数据）

### 被依赖
- Story 010: 订单管理器（查询最优价格）
- 未来: 做市策略、套利策略

---

## ⚠️ 风险与挑战

### 已识别风险
1. **更新性能**: 高频更新可能影响性能
   - **影响**: 中
   - **缓解措施**: 使用高效的数据结构，优化插入/删除

2. **内存占用**: 深度订单簿占用内存大
   - **影响**: 低
   - **缓解措施**: 限制保留的深度档位数量

### 技术挑战
1. **排序效率**: 每次更新都需要保持排序
   - **解决方案**: 使用二分查找插入

---

## 📊 进度追踪

### 时间线
- 开始日期: 待定
- 预计完成: 待定

---

## ✅ 验收检查清单

- [ ] 所有验收标准已满足
- [ ] 所有任务已完成
- [ ] 单元测试通过
- [ ] 性能测试通过（< 1ms 更新）
- [ ] 代码已审查
- [ ] 文档已更新

---

## 📸 演示

### 使用示例

```zig
const std = @import("std");
const OrderBook = @import("core/orderbook.zig").OrderBook;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    // 应用快照
    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, asks, Timestamp.now());

    // 查询最优价格
    const best_bid = ob.getBestBid().?;
    const best_ask = ob.getBestAsk().?;
    const mid = ob.getMidPrice().?;

    std.debug.print("Best Bid: {}\n", .{best_bid.price.toFloat()});
    std.debug.print("Best Ask: {}\n", .{best_ask.price.toFloat()});
    std.debug.print("Mid Price: {}\n", .{mid.toFloat()});

    // 计算滑点
    const quantity = try Decimal.fromString("5.0");
    const slippage = ob.getSlippage(.bid, quantity).?;
    std.debug.print("Slippage for 5.0: {}%\n", .{slippage.slippage_pct.toFloat() * 100});
}
```

---

## 💡 未来改进

- [ ] 支持 L3 订单簿（逐单级别）
- [ ] 实现订单簿快照持久化
- [ ] 添加订单簿可视化接口
- [ ] 实现 VWAP 计算
- [ ] 支持订单簿回放（用于回测）

---

*Last updated: 2025-12-23*
*Assignee: TBD*
*Status: 📋 Planning*
