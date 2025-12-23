# 订单簿 - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-23

---

## 类型定义

### Level

价格档位，表示订单簿中某个价格级别的聚合数据。

```zig
pub const Level = struct {
    price: Decimal,      // 价格
    size: Decimal,       // 该价格的总数量
    num_orders: u32,     // 该价格的订单数量

    pub fn lessThan(context: void, a: Level, b: Level) bool;
    pub fn greaterThan(context: void, a: Level, b: Level) bool;
};
```

**字段**:
- `price`: 价格级别
- `size`: 该价格的总挂单量
- `num_orders`: 该价格的订单数量（用于评估价格支撑强度）

---

### Side

订单方向枚举。

```zig
pub const Side = enum {
    bid,  // 买单
    ask,  // 卖单
};
```

---

### SlippageResult

滑点计算结果。

```zig
pub const SlippageResult = struct {
    avg_price: Decimal,      // 平均成交价格
    slippage_pct: Decimal,   // 滑点百分比（0.01 = 1%）
    total_cost: Decimal,     // 总成本
};
```

---

### OrderBook

L2 订单簿主结构。

```zig
pub const OrderBook = struct {
    allocator: std.mem.Allocator,
    symbol: []const u8,
    bids: std.ArrayList(Level),      // 买单（降序）
    asks: std.ArrayList(Level),      // 卖单（升序）
    last_update_time: Timestamp,
    sequence: u64,

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

### OrderBookManager

多币种订单簿管理器，提供线程安全的并发访问。

```zig
pub const OrderBookManager = struct {
    allocator: std.mem.Allocator,
    orderbooks: std.StringHashMap(*OrderBook),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) OrderBookManager;
    pub fn deinit(self: *OrderBookManager) void;
    pub fn getOrCreate(self: *OrderBookManager, symbol: []const u8) !*OrderBook;
    pub fn get(self: *OrderBookManager, symbol: []const u8) ?*OrderBook;
};
```

---

## OrderBook 函数

### `init`

```zig
pub fn init(allocator: std.mem.Allocator, symbol: []const u8) !OrderBook
```

**描述**: 创建新的订单簿实例。

**参数**:
- `allocator`: 内存分配器
- `symbol`: 交易对符号（如 "ETH"、"BTC"）

**返回**: 初始化的 `OrderBook` 实例

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
var orderbook = try OrderBook.init(allocator, "ETH");
defer orderbook.deinit();
```

---

### `deinit`

```zig
pub fn deinit(self: *OrderBook) void
```

**描述**: 释放订单簿占用的资源。

**参数**:
- `self`: 订单簿实例指针

**示例**:
```zig
var orderbook = try OrderBook.init(allocator, "ETH");
defer orderbook.deinit();  // 推荐使用 defer
```

---

### `applySnapshot`

```zig
pub fn applySnapshot(
    self: *OrderBook,
    bids: []const Level,
    asks: []const Level,
    timestamp: Timestamp,
) !void
```

**描述**: 应用完整快照，替换当前订单簿内容。通常用于初始化或重新同步。

**参数**:
- `self`: 订单簿实例指针
- `bids`: 买单数组
- `asks`: 卖单数组
- `timestamp`: 快照时间戳

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
const bids = &[_]Level{
    .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
};
const asks = &[_]Level{
    .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
};
try orderbook.applySnapshot(bids, asks, Timestamp.now());
```

---

### `applyUpdate`

```zig
pub fn applyUpdate(
    self: *OrderBook,
    side: Side,
    price: Decimal,
    size: Decimal,
    num_orders: u32,
    timestamp: Timestamp,
) !void
```

**描述**: 应用增量更新。`size = 0` 表示移除该价格档位。

**参数**:
- `self`: 订单簿实例指针
- `side`: 买单 (`.bid`) 或卖单 (`.ask`)
- `price`: 价格
- `size`: 数量（0 表示移除）
- `num_orders`: 订单数量
- `timestamp`: 更新时间戳

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
// 更新买单
try orderbook.applyUpdate(
    .bid,
    try Decimal.fromString("2000.0"),
    try Decimal.fromString("15.0"),
    2,
    Timestamp.now(),
);

// 移除卖单
try orderbook.applyUpdate(
    .ask,
    try Decimal.fromString("2001.0"),
    Decimal.ZERO,
    0,
    Timestamp.now(),
);
```

---

### `getBestBid`

```zig
pub fn getBestBid(self: *const OrderBook) ?Level
```

**描述**: 获取最优买价（Bid）。

**参数**:
- `self`: 订单簿实例指针

**返回**: 最优买单档位，如果没有买单则返回 `null`

**示例**:
```zig
if (orderbook.getBestBid()) |bid| {
    std.debug.print("Best Bid: {} @ {}\n", .{
        bid.size.toFloat(),
        bid.price.toFloat(),
    });
} else {
    std.debug.print("No bids\n", .{});
}
```

---

### `getBestAsk`

```zig
pub fn getBestAsk(self: *const OrderBook) ?Level
```

**描述**: 获取最优卖价（Ask）。

**参数**:
- `self`: 订单簿实例指针

**返回**: 最优卖单档位，如果没有卖单则返回 `null`

**示例**:
```zig
if (orderbook.getBestAsk()) |ask| {
    std.debug.print("Best Ask: {} @ {}\n", .{
        ask.size.toFloat(),
        ask.price.toFloat(),
    });
}
```

---

### `getMidPrice`

```zig
pub fn getMidPrice(self: *const OrderBook) ?Decimal
```

**描述**: 获取中间价（买一和卖一的平均价格）。

**参数**:
- `self`: 订单簿实例指针

**返回**: 中间价，如果买卖盘为空则返回 `null`

**公式**: `(best_bid + best_ask) / 2`

**示例**:
```zig
if (orderbook.getMidPrice()) |mid| {
    std.debug.print("Mid Price: {}\n", .{mid.toFloat()});
}
```

---

### `getSpread`

```zig
pub fn getSpread(self: *const OrderBook) ?Decimal
```

**描述**: 获取买卖价差。

**参数**:
- `self`: 订单簿实例指针

**返回**: 价差，如果买卖盘为空则返回 `null`

**公式**: `best_ask - best_bid`

**示例**:
```zig
if (orderbook.getSpread()) |spread| {
    std.debug.print("Spread: {}\n", .{spread.toFloat()});
}
```

---

### `getDepth`

```zig
pub fn getDepth(self: *const OrderBook, side: Side, target_price: Decimal) Decimal
```

**描述**: 计算到指定价格的累计深度。

**参数**:
- `self`: 订单簿实例指针
- `side`: 买单 (`.bid`) 或卖单 (`.ask`)
- `target_price`: 目标价格

**返回**: 累计数量

**说明**:
- 买单深度：所有价格 >= `target_price` 的买单总量
- 卖单深度：所有价格 <= `target_price` 的卖单总量

**示例**:
```zig
const target = try Decimal.fromString("2000.0");
const depth = orderbook.getDepth(.bid, target);
std.debug.print("Bid depth at {}: {}\n", .{
    target.toFloat(),
    depth.toFloat(),
});
```

---

### `getSlippage`

```zig
pub fn getSlippage(
    self: *const OrderBook,
    side: Side,
    quantity: Decimal,
) ?SlippageResult
```

**描述**: 计算执行指定数量的预期平均价格和滑点。

**参数**:
- `self`: 订单簿实例指针
- `side`: `.bid` 表示买入（吃 ask），`.ask` 表示卖出（吃 bid）
- `quantity`: 成交数量

**返回**: 滑点结果，如果流动性不足则返回 `null`

**示例**:
```zig
const quantity = try Decimal.fromString("100.0");
if (orderbook.getSlippage(.bid, quantity)) |result| {
    std.debug.print("Avg Price: {}\n", .{result.avg_price.toFloat()});
    std.debug.print("Slippage: {}%\n", .{result.slippage_pct.toFloat() * 100});
    std.debug.print("Total Cost: {}\n", .{result.total_cost.toFloat()});
} else {
    std.debug.print("Insufficient liquidity\n", .{});
}
```

---

## OrderBookManager 函数

### `init`

```zig
pub fn init(allocator: std.mem.Allocator) OrderBookManager
```

**描述**: 创建订单簿管理器。

**参数**:
- `allocator`: 内存分配器

**返回**: 初始化的 `OrderBookManager` 实例

**示例**:
```zig
var manager = OrderBookManager.init(allocator);
defer manager.deinit();
```

---

### `deinit`

```zig
pub fn deinit(self: *OrderBookManager) void
```

**描述**: 释放管理器及所有订单簿的资源。

**参数**:
- `self`: 管理器实例指针

**示例**:
```zig
var manager = OrderBookManager.init(allocator);
defer manager.deinit();
```

---

### `getOrCreate`

```zig
pub fn getOrCreate(self: *OrderBookManager, symbol: []const u8) !*OrderBook
```

**描述**: 获取或创建指定币种的订单簿（线程安全）。

**参数**:
- `self`: 管理器实例指针
- `symbol`: 交易对符号

**返回**: 订单簿指针

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
const eth_book = try manager.getOrCreate("ETH");
const btc_book = try manager.getOrCreate("BTC");
```

---

### `get`

```zig
pub fn get(self: *OrderBookManager, symbol: []const u8) ?*OrderBook
```

**描述**: 获取指定币种的订单簿（线程安全）。

**参数**:
- `self`: 管理器实例指针
- `symbol`: 交易对符号

**返回**: 订单簿指针，如果不存在则返回 `null`

**示例**:
```zig
if (manager.get("ETH")) |book| {
    const mid = book.getMidPrice();
    // ...
}
```

---

## 完整示例

### 示例 1: 基本使用

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

    // 查询
    if (orderbook.getMidPrice()) |mid| {
        std.debug.print("Mid Price: {}\n", .{mid.toFloat()});
    }
}
```

### 示例 2: WebSocket 增量更新

```zig
// WebSocket 消息处理
fn onL2Update(orderbook: *OrderBook, update: L2Update) !void {
    try orderbook.applyUpdate(
        update.side,
        update.price,
        update.size,
        update.num_orders,
        update.timestamp,
    );

    // 打印最优价格
    if (orderbook.getBestBid()) |bid| {
        if (orderbook.getBestAsk()) |ask| {
            std.debug.print("BBO: {} / {}\n", .{
                bid.price.toFloat(),
                ask.price.toFloat(),
            });
        }
    }
}
```

### 示例 3: 滑点分析

```zig
fn analyzeSlippage(orderbook: *const OrderBook) !void {
    const quantities = [_]f64{ 1.0, 10.0, 50.0, 100.0 };

    std.debug.print("=== Slippage Analysis ===\n", .{});
    for (quantities) |qty| {
        const quantity = try Decimal.fromString(qty);

        if (orderbook.getSlippage(.bid, quantity)) |result| {
            std.debug.print("Buy {}: Avg Price = {}, Slippage = {}%\n", .{
                qty,
                result.avg_price.toFloat(),
                result.slippage_pct.toFloat() * 100,
            });
        } else {
            std.debug.print("Buy {}: Insufficient liquidity\n", .{qty});
        }
    }
}
```

### 示例 4: 多币种管理

```zig
const std = @import("std");
const OrderBookManager = @import("core/orderbook.zig").OrderBookManager;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = OrderBookManager.init(allocator);
    defer manager.deinit();

    // 创建多个订单簿
    const eth_book = try manager.getOrCreate("ETH");
    const btc_book = try manager.getOrCreate("BTC");

    // 在多线程环境中安全访问
    const symbols = [_][]const u8{ "ETH", "BTC", "SOL" };
    for (symbols) |symbol| {
        if (manager.get(symbol)) |book| {
            if (book.getMidPrice()) |mid| {
                std.debug.print("{s}: {}\n", .{ symbol, mid.toFloat() });
            }
        }
    }
}
```
