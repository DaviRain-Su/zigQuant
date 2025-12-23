# 订单簿 - 实现细节

> 深入了解内部实现

**最后更新**: 2025-12-23

---

## 内部表示

### 数据结构

#### Level (价格档位)

```zig
pub const Level = struct {
    price: Decimal,      // 价格
    size: Decimal,       // 该价格的总数量
    num_orders: u32,     // 该价格的订单数量

    pub fn lessThan(context: void, a: Level, b: Level) bool {
        _ = context;
        return a.price.cmp(b.price) == .lt;
    }

    pub fn greaterThan(context: void, a: Level, b: Level) bool {
        _ = context;
        return a.price.cmp(b.price) == .gt;
    }
};
```

**设计说明**:
- `price` 使用 `Decimal` 类型确保精确计算
- `num_orders` 可用于评估价格支撑强度
- 提供比较函数用于排序

#### OrderBook

```zig
pub const OrderBook = struct {
    allocator: std.mem.Allocator,
    symbol: []const u8,

    // 买单：从高到低排序（最高买价在前）
    bids: std.ArrayList(Level),

    // 卖单：从低到高排序（最低卖价在前）
    asks: std.ArrayList(Level),

    // 元数据
    last_update_time: Timestamp,
    sequence: u64,  // 序列号，用于检测丢失的更新
};
```

**设计说明**:
- 使用 `ArrayList` 存储价格档位，支持动态扩容
- `bids` 降序排列，`asks` 升序排列，保证最优价格在索引 0
- `sequence` 用于检测 WebSocket 更新丢失

#### OrderBookManager

```zig
pub const OrderBookManager = struct {
    allocator: std.mem.Allocator,
    orderbooks: std.StringHashMap(*OrderBook),
    mutex: std.Thread.Mutex,
};
```

**设计说明**:
- 使用 `StringHashMap` 管理多个币种的订单簿
- `Mutex` 提供线程安全的并发访问
- 集中管理订单簿的生命周期

---

## 核心算法

### 快照应用 (applySnapshot)

```zig
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
```

**复杂度**: O(n log n)
- `clearRetainingCapacity()`: O(1)，保留容量避免重新分配
- `appendSlice()`: O(n)
- `std.mem.sort()`: O(n log n)

**说明**:
- 完全替换订单簿内容
- 保留 ArrayList 容量以减少内存分配
- 确保正确排序

### 增量更新 (applyUpdate)

```zig
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
```

**复杂度**:
- 最坏情况: O(n log n) (需要插入并重新排序)
- 平均情况: O(n) (线性搜索 + 更新)

**说明**:
- `size = 0` 表示移除该价格档位
- `size > 0` 表示更新或插入新档位

### 档位更新 (upsertLevel)

```zig
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
```

**复杂度**: O(n) 搜索 + O(n log n) 排序 = O(n log n)

**优化方案**:
1. 使用二分查找: O(log n)
2. 插入排序: O(n) (如果接近有序)
3. 使用红黑树: O(log n) 插入和查询

### 档位移除 (removeLevel)

```zig
fn removeLevel(self: *OrderBook, levels: *std.ArrayList(Level), price: Decimal) !void {
    for (levels.items, 0..) |level, i| {
        if (level.price.eql(price)) {
            _ = levels.swapRemove(i);
            return;
        }
    }
}
```

**复杂度**: O(n)

**说明**:
- 使用 `swapRemove` 而非 `orderedRemove`
- 移除后需要重新排序（在 `upsertLevel` 中完成）

### 深度计算 (getDepth)

```zig
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
            break; // 已排序，可以提前退出
        }
    }

    return total;
}
```

**复杂度**: O(n)，n = 目标价格之前的档位数

**说明**:
- 利用排序特性提前退出循环
- 买单深度：所有 >= target_price 的档位
- 卖单深度：所有 <= target_price 的档位

### 滑点计算 (getSlippage)

```zig
pub fn getSlippage(
    self: *const OrderBook,
    side: Side,
    quantity: Decimal,
) ?SlippageResult {
    // 买单看 asks，卖单看 bids
    const levels = if (side == .bid) self.asks.items else self.bids.items;
    var remaining = quantity;
    var total_cost = Decimal.ZERO;

    for (levels) |level| {
        const fill_qty = if (remaining.cmp(level.size) == .gt)
            level.size
        else
            remaining;

        total_cost = total_cost.add(fill_qty.mul(level.price));
        remaining = remaining.sub(fill_qty);

        if (remaining.isZero()) {
            const avg_price = total_cost.div(quantity) catch return null;
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
    }

    // 流动性不足
    return null;
}
```

**复杂度**: O(n)，n = 需要的档位数

**说明**:
- 模拟市价单执行
- 计算加权平均价格
- 返回 `null` 表示流动性不足

---

## 性能优化

### 优化点 1: 预分配容量

```zig
pub fn initWithCapacity(
    allocator: std.mem.Allocator,
    symbol: []const u8,
    capacity: usize,
) !OrderBook {
    var book = try OrderBook.init(allocator, symbol);
    try book.bids.ensureTotalCapacity(capacity);
    try book.asks.ensureTotalCapacity(capacity);
    return book;
}
```

**效果**: 减少动态扩容的内存分配次数

### 优化点 2: 使用 clearRetainingCapacity

```zig
// 在 applySnapshot 中
self.bids.clearRetainingCapacity();
self.asks.clearRetainingCapacity();
```

**效果**: 清空列表但保留容量，避免重新分配

### 优化点 3: 二分查找优化 (未来)

```zig
fn binarySearchLevel(levels: []Level, price: Decimal) ?usize {
    var left: usize = 0;
    var right: usize = levels.len;

    while (left < right) {
        const mid = left + (right - left) / 2;
        const cmp = levels[mid].price.cmp(price);

        switch (cmp) {
            .eq => return mid,
            .lt => left = mid + 1,
            .gt => right = mid,
        }
    }

    return null;
}
```

**效果**: O(log n) 查找，O(n) 插入

### 优化点 4: 使用有序插入代替排序

```zig
fn insertSorted(levels: *std.ArrayList(Level), new_level: Level, comptime cmp_fn: fn(void, Level, Level) bool) !void {
    var i: usize = 0;
    while (i < levels.items.len) : (i += 1) {
        if (cmp_fn({}, new_level, levels.items[i])) {
            break;
        }
    }
    try levels.insert(i, new_level);
}
```

**效果**: O(n) 插入，避免 O(n log n) 排序

---

## 内存管理

### 分配策略

```zig
pub fn init(allocator: std.mem.Allocator, symbol: []const u8) !OrderBook {
    return .{
        .allocator = allocator,
        .symbol = try allocator.dupe(u8, symbol),  // 拷贝字符串
        .bids = std.ArrayList(Level).init(allocator),
        .asks = std.ArrayList(Level).init(allocator),
        .last_update_time = Timestamp.now(),
        .sequence = 0,
    };
}
```

**说明**:
- `symbol` 被拷贝，确保生命周期独立
- `ArrayList` 使用提供的 allocator
- 初始容量为 0，按需扩容

### 清理策略

```zig
pub fn deinit(self: *OrderBook) void {
    self.allocator.free(self.symbol);  // 释放字符串
    self.bids.deinit();                // 释放 ArrayList
    self.asks.deinit();
}
```

**说明**:
- 必须调用 `deinit()` 避免内存泄漏
- 使用 `defer` 确保清理

### OrderBookManager 内存管理

```zig
pub fn deinit(self: *OrderBookManager) void {
    var iter = self.orderbooks.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.*.deinit();              // 清理 OrderBook
        self.allocator.destroy(entry.value_ptr.*); // 释放指针
    }
    self.orderbooks.deinit();  // 清理 HashMap
}
```

**说明**:
- 迭代清理所有订单簿
- 释放指针和数据结构

---

## 边界情况

### 情况 1: 空订单簿

```zig
pub fn getBestBid(self: *const OrderBook) ?Level {
    if (self.bids.items.len == 0) return null;
    return self.bids.items[0];
}
```

**处理**: 返回 `null`

### 情况 2: 流动性不足

```zig
pub fn getSlippage(self: *const OrderBook, side: Side, quantity: Decimal) ?SlippageResult {
    // ...
    for (levels) |level| {
        // ...
    } else {
        // 流动性不足
        return null;
    }
}
```

**处理**: 返回 `null` 表示无法完全成交

### 情况 3: 价格相等

```zig
fn upsertLevel(...) !void {
    for (levels.items, 0..) |*level, i| {
        if (level.price.eql(new_level.price)) {
            // 更新现有档位
            level.* = new_level;
            return;
        }
    }
    // 插入新档位
}
```

**处理**: 更新现有档位，不插入新档位

### 情况 4: 买卖价交叉

```zig
// 验证函数（可选）
pub fn validate(self: *const OrderBook) !void {
    if (self.getBestBid()) |bid| {
        if (self.getBestAsk()) |ask| {
            if (bid.price.cmp(ask.price) == .gt) {
                return error.CrossedBook;
            }
        }
    }
}
```

**处理**: 检测并报错（通常不应发生）

---

## 线程安全

### OrderBookManager 的线程安全访问

```zig
pub fn get(self: *OrderBookManager, symbol: []const u8) ?*OrderBook {
    self.mutex.lock();
    defer self.mutex.unlock();
    return self.orderbooks.get(symbol);
}

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
```

**说明**:
- 使用 `Mutex` 保护共享状态
- `defer unlock()` 确保异常安全

---

*完整实现请参考: `src/core/orderbook.zig`*
