# 订单系统 - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-23

---

## 类型定义

### Side (订单方向)

```zig
pub const Side = enum {
    buy,
    sell,

    pub fn toString(self: Side) []const u8;
};
```

**描述**: 订单买卖方向

**值**:
- `buy`: 买入
- `sell`: 卖出

**示例**:
```zig
const side = Side.buy;
std.debug.print("{s}\n", .{side.toString()}); // "BUY"
```

---

### OrderType (订单类型)

```zig
pub const OrderType = enum {
    limit,      // 限价单
    trigger,    // 触发单

    pub fn toString(self: OrderType) []const u8;
};
```

**描述**: 基于 Hyperliquid API 的订单类型

**值**:
- `limit`: 限价单，指定价格和时效（TIF）
- `trigger`: 触发单，用于止盈止损

**示例**:
```zig
const order_type = OrderType.limit;
std.debug.print("{s}\n", .{order_type.toString()}); // "LIMIT"
```

---

### TimeInForce (订单时效)

```zig
pub const TimeInForce = enum {
    gtc,  // Good-Til-Cancelled
    ioc,  // Immediate-Or-Cancel
    alo,  // Add-Liquidity-Only

    pub fn toString(self: TimeInForce) []const u8;
    pub fn fromString(s: []const u8) !TimeInForce;
};
```

**描述**: 订单有效期和执行策略

**值**:
- `gtc` (Gtc): 一直有效直到取消，默认选项
- `ioc` (Ioc): 立即成交，未成交部分取消
- `alo` (Alo): 只做 Maker，Post-only 模式

**示例**:
```zig
const tif = TimeInForce.gtc;
std.debug.print("{s}\n", .{tif.toString()}); // "Gtc"

const tif2 = try TimeInForce.fromString("Ioc"); // .ioc
```

---

### OrderStatus (订单状态)

```zig
pub const OrderStatus = enum {
    pending,          // 客户端待提交
    submitted,        // 已提交
    open,             // 已挂单
    filled,           // 完全成交
    canceled,         // 已取消
    triggered,        // 已触发
    rejected,         // 被拒绝
    marginCanceled,   // 保证金不足被取消

    pub fn toString(self: OrderStatus) []const u8;
    pub fn fromString(s: []const u8) !OrderStatus;
    pub fn isFinal(self: OrderStatus) bool;
    pub fn isActive(self: OrderStatus) bool;
};
```

**描述**: 订单状态枚举

**值**:
- `pending`: 本地创建，待提交
- `submitted`: 已提交到交易所
- `open`: 交易所已接受，处于活跃状态
- `filled`: 完全成交
- `canceled`: 已取消
- `triggered`: 触发单已触发
- `rejected`: 被交易所拒绝
- `marginCanceled`: 因保证金不足被取消

**方法**:
- `isFinal()`: 判断是否为终态（filled, canceled, rejected, marginCanceled）
- `isActive()`: 判断是否为活跃状态（open, triggered）

**示例**:
```zig
const status = OrderStatus.open;
std.debug.print("Active: {}\n", .{status.isActive()}); // true
std.debug.print("Final: {}\n", .{status.isFinal()});   // false
```

---

### PositionSide (仓位方向)

```zig
pub const PositionSide = enum {
    long,   // 多头
    short,  // 空头
    both,   // 双向持仓

    pub fn toString(self: PositionSide) []const u8;
};
```

**描述**: 合约交易的仓位方向

**值**:
- `long`: 做多
- `short`: 做空
- `both`: 双向持仓模式

---

### Order (订单结构)

```zig
pub const Order = struct {
    // 唯一标识
    id: ?u64,
    exchange_order_id: ?u64,
    client_order_id: []const u8,

    // 基本信息
    symbol: []const u8,
    side: OrderTypes.Side,
    order_type: OrderTypes.OrderType,
    time_in_force: OrderTypes.TimeInForce,

    // 价格和数量
    price: ?Decimal,
    quantity: Decimal,
    filled_quantity: Decimal,
    remaining_quantity: Decimal,

    // 止损参数
    stop_price: ?Decimal,
    trigger_price: ?Decimal,

    // 仓位参数
    position_side: ?OrderTypes.PositionSide,
    reduce_only: bool,

    // 状态
    status: OrderTypes.OrderStatus,
    error_message: ?[]const u8,

    // 时间戳
    created_at: Timestamp,
    submitted_at: ?Timestamp,
    updated_at: ?Timestamp,
    filled_at: ?Timestamp,

    // 成交信息
    avg_fill_price: ?Decimal,
    total_fee: Decimal,
    fee_currency: []const u8,

    // 元数据
    allocator: std.mem.Allocator,
};
```

**描述**: 订单核心数据结构

---

## 函数

### `Order.init`

```zig
pub fn init(
    allocator: std.mem.Allocator,
    symbol: []const u8,
    side: OrderTypes.Side,
    order_type: OrderTypes.OrderType,
    price: ?Decimal,
    quantity: Decimal,
) !Order
```

**描述**: 创建新订单

**参数**:
- `allocator`: 内存分配器
- `symbol`: 交易对符号（如 "ETH", "BTC"）
- `side`: 买卖方向
- `order_type`: 订单类型
- `price`: 价格（限价单必需，触发单可选）
- `quantity`: 数量

**返回**: 初始化的订单实例

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
var order = try Order.init(
    allocator,
    "ETH",
    .buy,
    .limit,
    try Decimal.fromString("2000.0"),
    try Decimal.fromString("1.0"),
);
defer order.deinit();
```

---

### `Order.deinit`

```zig
pub fn deinit(self: *Order) void
```

**描述**: 释放订单占用的内存

**参数**:
- `self`: 订单实例指针

**示例**:
```zig
defer order.deinit();
```

---

### `Order.validate`

```zig
pub fn validate(self: *const Order) !void
```

**描述**: 验证订单参数合法性

**参数**:
- `self`: 订单实例指针

**返回**: void（验证成功）

**错误**:
- `error.InvalidQuantity`: 数量无效（≤ 0）
- `error.MissingPrice`: 限价单缺少价格
- `error.InvalidPrice`: 价格无效（≤ 0）
- `error.MissingTriggerPrice`: 触发单缺少触发价
- `error.EmptySymbol`: 交易对符号为空

**示例**:
```zig
try order.validate();
```

---

### `Order.updateStatus`

```zig
pub fn updateStatus(self: *Order, new_status: OrderTypes.OrderStatus) void
```

**描述**: 更新订单状态

**参数**:
- `self`: 订单实例指针
- `new_status`: 新状态

**副作用**:
- 更新 `updated_at` 时间戳
- 如果状态为 `filled`，设置 `filled_at` 和成交数量
- 如果状态为 `submitted`，设置 `submitted_at`

**示例**:
```zig
order.updateStatus(.open);
```

---

### `Order.updateFill`

```zig
pub fn updateFill(
    self: *Order,
    filled_qty: Decimal,
    fill_price: Decimal,
    fee: Decimal,
) void
```

**描述**: 更新订单成交信息

**参数**:
- `self`: 订单实例指针
- `filled_qty`: 本次成交数量
- `fill_price`: 本次成交价格
- `fee`: 本次手续费

**副作用**:
- 累加 `filled_quantity`
- 更新 `remaining_quantity`
- 计算加权平均成交价 `avg_fill_price`
- 累加 `total_fee`
- 如果完全成交，更新状态为 `filled`

**示例**:
```zig
order.updateFill(
    try Decimal.fromString("0.5"),   // 成交 0.5
    try Decimal.fromString("2000.0"), // 价格 2000.0
    try Decimal.fromString("1.0"),    // 手续费 1.0
);
```

---

### `Order.getFillPercentage`

```zig
pub fn getFillPercentage(self: *const Order) Decimal
```

**描述**: 计算成交百分比

**参数**:
- `self`: 订单实例指针

**返回**: 成交百分比（0.0 - 1.0）

**示例**:
```zig
const percentage = order.getFillPercentage();
std.debug.print("Filled: {d}%\n", .{percentage.toFloat() * 100});
```

---

### `Order.isFilled`

```zig
pub fn isFilled(self: *const Order) bool
```

**描述**: 判断订单是否完全成交

**参数**:
- `self`: 订单实例指针

**返回**: true 如果状态为 `filled`

**示例**:
```zig
if (order.isFilled()) {
    std.debug.print("Order completed\n", .{});
}
```

---

### `Order.isCancellable`

```zig
pub fn isCancellable(self: *const Order) bool
```

**描述**: 判断订单是否可取消

**参数**:
- `self`: 订单实例指针

**返回**: true 如果状态为活跃状态（open, triggered）

**示例**:
```zig
if (order.isCancellable()) {
    // 执行取消操作
}
```

---

### `OrderBuilder.init`

```zig
pub fn init(
    allocator: std.mem.Allocator,
    symbol: []const u8,
    side: OrderTypes.Side,
) !OrderBuilder
```

**描述**: 创建订单构建器

**参数**:
- `allocator`: 内存分配器
- `symbol`: 交易对符号
- `side`: 买卖方向

**返回**: 订单构建器实例

**示例**:
```zig
var builder = try OrderBuilder.init(allocator, "ETH", .buy);
```

---

### `OrderBuilder.withOrderType`

```zig
pub fn withOrderType(self: *OrderBuilder, order_type: OrderTypes.OrderType) *OrderBuilder
```

**描述**: 设置订单类型

**参数**:
- `self`: 构建器实例指针
- `order_type`: 订单类型

**返回**: 构建器实例指针（支持链式调用）

**示例**:
```zig
_ = builder.withOrderType(.limit);
```

---

### `OrderBuilder.withPrice`

```zig
pub fn withPrice(self: *OrderBuilder, price: Decimal) *OrderBuilder
```

**描述**: 设置订单价格

**参数**:
- `self`: 构建器实例指针
- `price`: 价格

**返回**: 构建器实例指针（支持链式调用）

---

### `OrderBuilder.withQuantity`

```zig
pub fn withQuantity(self: *OrderBuilder, quantity: Decimal) *OrderBuilder
```

**描述**: 设置订单数量

**参数**:
- `self`: 构建器实例指针
- `quantity`: 数量

**返回**: 构建器实例指针（支持链式调用）

---

### `OrderBuilder.withTimeInForce`

```zig
pub fn withTimeInForce(self: *OrderBuilder, tif: OrderTypes.TimeInForce) *OrderBuilder
```

**描述**: 设置订单时效

**参数**:
- `self`: 构建器实例指针
- `tif`: 时效类型

**返回**: 构建器实例指针（支持链式调用）

---

### `OrderBuilder.withStopPrice`

```zig
pub fn withStopPrice(self: *OrderBuilder, stop_price: Decimal) *OrderBuilder
```

**描述**: 设置止损价格

**参数**:
- `self`: 构建器实例指针
- `stop_price`: 止损价

**返回**: 构建器实例指针（支持链式调用）

---

### `OrderBuilder.withReduceOnly`

```zig
pub fn withReduceOnly(self: *OrderBuilder, reduce_only: bool) *OrderBuilder
```

**描述**: 设置只减仓标志

**参数**:
- `self`: 构建器实例指针
- `reduce_only`: 是否只减仓

**返回**: 构建器实例指针（支持链式调用）

---

### `OrderBuilder.build`

```zig
pub fn build(self: *OrderBuilder) !Order
```

**描述**: 构建并验证订单

**参数**:
- `self`: 构建器实例指针

**返回**: 验证通过的订单实例

**错误**:
- 所有 `validate()` 可能返回的错误

**示例**:
```zig
var order = try builder
    .withOrderType(.limit)
    .withPrice(try Decimal.fromString("2000.0"))
    .withQuantity(try Decimal.fromString("1.0"))
    .build();
```

---

## Hyperliquid API 类型

### `HyperliquidOrderType`

```zig
pub const HyperliquidOrderType = struct {
    limit: ?LimitOrderType = null,
    trigger: ?TriggerOrderType = null,

    pub const LimitOrderType = struct {
        tif: TimeInForce,
    };

    pub const TriggerOrderType = struct {
        triggerPx: []const u8,
        isMarket: bool,
        tpsl: TriggerDirection,

        pub const TriggerDirection = enum {
            tp,  // Take Profit
            sl,  // Stop Loss

            pub fn toString(self: TriggerDirection) []const u8;
        };
    };
};
```

**描述**: Hyperliquid 交易所的订单类型表示

**用法**: 用于与 Hyperliquid API 交互时的序列化

**示例（限价单）**:
```zig
const hl_order_type = HyperliquidOrderType{
    .limit = .{ .tif = .gtc },
};
```

**示例（止损单）**:
```zig
const hl_order_type = HyperliquidOrderType{
    .trigger = .{
        .triggerPx = "2000.0",
        .isMarket = true,
        .tpsl = .sl,
    },
};
```

---

## 完整示例

### 示例 1: 创建简单限价单

```zig
const std = @import("std");
const Order = @import("core/order.zig").Order;
const Decimal = @import("decimal.zig").Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建限价买单
    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    // 验证订单
    try order.validate();

    std.debug.print("Order created: {s} {s}\n", .{
        order.side.toString(),
        order.symbol,
    });
}
```

### 示例 2: 使用 Builder 创建复杂订单

```zig
const std = @import("std");
const OrderBuilder = @import("core/order.zig").OrderBuilder;
const Decimal = @import("decimal.zig").Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 使用 Builder 创建订单
    var builder = try OrderBuilder.init(allocator, "BTC", .sell);
    var order = try builder
        .withOrderType(.limit)
        .withPrice(try Decimal.fromString("50000.0"))
        .withQuantity(try Decimal.fromString("0.1"))
        .withTimeInForce(.ioc)
        .withReduceOnly(true)
        .build();
    defer order.deinit();

    std.debug.print("Order: {s} {} @ {}\n", .{
        order.symbol,
        order.quantity.toFloat(),
        order.price.?.toFloat(),
    });
}
```

### 示例 3: 订单生命周期管理

```zig
const std = @import("std");
const Order = @import("core/order.zig").Order;
const Decimal = @import("decimal.zig").Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    // 提交订单
    order.updateStatus(.submitted);
    std.debug.print("Status: {s}\n", .{order.status.toString()});

    // 订单被接受
    order.updateStatus(.open);

    // 部分成交
    order.updateFill(
        try Decimal.fromString("0.5"),
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    std.debug.print("Filled: {d}%\n", .{
        order.getFillPercentage().toFloat() * 100,
    });

    // 完全成交
    order.updateFill(
        try Decimal.fromString("0.5"),
        try Decimal.fromString("2001.0"),
        try Decimal.fromString("1.0"),
    );
    std.debug.print("Order filled: {}\n", .{order.isFilled()});
    std.debug.print("Avg price: {}\n", .{
        order.avg_fill_price.?.toFloat(),
    });
}
```

---

*完整 API 文档基于 Story 009 和实际实现*
