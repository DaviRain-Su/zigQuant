# 订单管理器 - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-23

---

## 类型定义

### OrderManager

```zig
pub const OrderManager = struct {
    allocator: std.mem.Allocator,
    http_client: *HyperliquidClient,
    ws_client: *HyperliquidWS,
    order_store: OrderStore,
    logger: Logger,
    mutex: std.Thread.Mutex,

    on_order_update: ?*const fn (order: *Order) void,
    on_order_fill: ?*const fn (order: *Order) void,
};
```

**字段说明**:
- `allocator`: 内存分配器
- `http_client`: Hyperliquid HTTP 客户端，用于订单操作
- `ws_client`: Hyperliquid WebSocket 客户端，用于实时事件
- `order_store`: 订单存储，管理订单索引和列表
- `logger`: 日志记录器
- `mutex`: 互斥锁，保护并发访问
- `on_order_update`: 订单状态更新回调
- `on_order_fill`: 订单成交回调

### OrderStore

```zig
pub const OrderStore = struct {
    allocator: std.mem.Allocator,
    orders_by_client_id: std.StringHashMap(*Order),
    orders_by_exchange_id: std.AutoHashMap(u64, *Order),
    active_orders: std.ArrayList(*Order),
    history_orders: std.ArrayList(*Order),
};
```

**字段说明**:
- `orders_by_client_id`: 按客户端订单 ID 索引
- `orders_by_exchange_id`: 按交易所订单 ID 索引
- `active_orders`: 活跃订单列表
- `history_orders`: 历史订单列表

---

## OrderManager 函数

### `init`

```zig
pub fn init(
    allocator: std.mem.Allocator,
    http_client: *HyperliquidClient,
    ws_client: *HyperliquidWS,
    logger: Logger,
) !OrderManager
```

**描述**: 初始化订单管理器

**参数**:
- `allocator`: 内存分配器
- `http_client`: HTTP 客户端指针
- `ws_client`: WebSocket 客户端指针
- `logger`: 日志记录器

**返回**: 初始化的 `OrderManager` 实例

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
var manager = try OrderManager.init(
    allocator,
    &http_client,
    &ws_client,
    logger,
);
defer manager.deinit();
```

---

### `deinit`

```zig
pub fn deinit(self: *OrderManager) void
```

**描述**: 清理订单管理器资源

**参数**:
- `self`: OrderManager 实例指针

**示例**:
```zig
manager.deinit();
```

---

### `submitOrder`

```zig
pub fn submitOrder(self: *OrderManager, order: *Order) !void
```

**描述**: 提交订单到交易所

**参数**:
- `self`: OrderManager 实例指针
- `order`: 要提交的订单指针

**错误**:
- `error.OrderRejected`: 订单被交易所拒绝
- `error.InvalidOrderParams`: 订单参数无效
- `error.NetworkError`: 网络请求失败
- `error.OutOfMemory`: 内存分配失败

**副作用**:
- 订单被添加到 `order_store`
- 订单状态更新为 `.open` 或 `.filled`
- 设置 `exchange_order_id`
- 触发 `on_order_update` 回调（如果设置）

**示例**:
```zig
var order = try Order.init(
    allocator,
    "ETH",
    .buy,
    .limit,
    try Decimal.fromString("2000.0"),
    try Decimal.fromString("0.1"),
);
defer order.deinit();

try manager.submitOrder(&order);

// 检查结果
if (order.status == .open) {
    std.debug.print("Order OID: {}\n", .{order.exchange_order_id.?});
}
```

---

### `cancelOrder`

```zig
pub fn cancelOrder(self: *OrderManager, order: *Order) !void
```

**描述**: 取消单个订单

**参数**:
- `self`: OrderManager 实例指针
- `order`: 要取消的订单指针

**错误**:
- `error.OrderNotCancellable`: 订单不可取消（已成交或已取消）
- `error.CancelOrderFailed`: 取消请求失败
- `error.NetworkError`: 网络请求失败

**副作用**:
- 订单状态更新为 `.cancelled`
- 触发 `on_order_update` 回调（如果设置）

**示例**:
```zig
if (order.isCancellable()) {
    try manager.cancelOrder(&order);
    std.debug.print("Order cancelled\n", .{});
} else {
    std.debug.print("Order cannot be cancelled\n", .{});
}
```

---

### `cancelOrderByCloid`

```zig
pub fn cancelOrderByCloid(
    self: *OrderManager,
    coin: []const u8,
    cloid: []const u8,
) !void
```

**描述**: 通过客户端订单 ID 取消订单

**参数**:
- `self`: OrderManager 实例指针
- `coin`: 交易对符号（如 "ETH"）
- `cloid`: 客户端订单 ID

**错误**:
- `error.CancelOrderFailed`: 取消请求失败
- `error.NetworkError`: 网络请求失败

**副作用**:
- 如果本地存在该订单，状态更新为 `.cancelled`

**示例**:
```zig
try manager.cancelOrderByCloid("ETH", "my-order-123");
```

---

### `cancelOrders`

```zig
pub fn cancelOrders(self: *OrderManager, orders: []const *Order) !void
```

**描述**: 批量取消多个订单

**参数**:
- `self`: OrderManager 实例指针
- `orders`: 要取消的订单数组

**错误**:
- `error.NetworkError`: 网络请求失败
- `error.OutOfMemory`: 内存分配失败

**副作用**:
- 成功取消的订单状态更新为 `.cancelled`
- 不可取消的订单会被跳过

**示例**:
```zig
const orders_to_cancel = [_]*Order{ &order1, &order2, &order3 };
try manager.cancelOrders(&orders_to_cancel);

for (orders_to_cancel) |order| {
    std.debug.print("Order {s}: {s}\n", .{
        order.client_order_id,
        order.status.toString(),
    });
}
```

---

### `queryOrderStatus`

```zig
pub fn queryOrderStatus(self: *OrderManager, order: *Order) !void
```

**描述**: 查询订单最新状态

**参数**:
- `self`: OrderManager 实例指针
- `order`: 要查询的订单指针

**错误**:
- `error.OrderNotSubmitted`: 订单未提交（没有 exchange_order_id）
- `error.NetworkError`: 网络请求失败

**副作用**:
- 订单状态更新为最新状态

**示例**:
```zig
try manager.queryOrderStatus(&order);
std.debug.print("Current status: {s}\n", .{order.status.toString()});
```

---

### `getActiveOrders`

```zig
pub fn getActiveOrders(self: *OrderManager) ![]const *Order
```

**描述**: 获取所有活跃订单

**参数**:
- `self`: OrderManager 实例指针

**返回**: 活跃订单数组（调用者必须释放）

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
const active_orders = try manager.getActiveOrders();
defer allocator.free(active_orders);

std.debug.print("Active orders: {}\n", .{active_orders.len});
for (active_orders) |order| {
    std.debug.print("  {s}: {s} {} @ {?}\n", .{
        order.client_order_id,
        order.symbol,
        order.quantity.toFloat(),
        if (order.price) |p| p.toFloat() else null,
    });
}
```

---

### `getOrderHistory`

```zig
pub fn getOrderHistory(
    self: *OrderManager,
    symbol: ?[]const u8,
    limit: ?usize,
) ![]const *Order
```

**描述**: 获取历史订单

**参数**:
- `self`: OrderManager 实例指针
- `symbol`: 可选，按交易对过滤（传 `null` 获取所有）
- `limit`: 可选，限制返回数量（传 `null` 获取所有）

**返回**: 历史订单数组（调用者必须释放）

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
// 获取所有历史订单
const all_history = try manager.getOrderHistory(null, null);
defer allocator.free(all_history);

// 获取 ETH 的最近 10 个订单
const eth_history = try manager.getOrderHistory("ETH", 10);
defer allocator.free(eth_history);

for (eth_history) |order| {
    std.debug.print("{s}: {s}\n", .{
        order.client_order_id,
        order.status.toString(),
    });
}
```

---

### `handleUserEvent`

```zig
pub fn handleUserEvent(self: *OrderManager, event: WsUserEvent) !void
```

**描述**: 处理 WebSocket 用户事件

**参数**:
- `self`: OrderManager 实例指针
- `event`: WebSocket 用户事件（fills, funding, liquidation, nonUserCancel）

**错误**:
- `error.OutOfMemory`: 内存分配失败

**副作用**:
- 根据事件类型更新订单状态
- 触发相应的回调函数

**示例**:
```zig
// 在 WebSocket 消息处理循环中
const event = try ws_client.readUserEvent();
try manager.handleUserEvent(event);
```

---

### `handleUserFill`

```zig
pub fn handleUserFill(self: *OrderManager, fill: WsUserFills.UserFill) !void
```

**描述**: 处理订单成交事件

**参数**:
- `self`: OrderManager 实例指针
- `fill`: 成交信息

**错误**:
- `error.OutOfMemory`: 内存分配失败

**副作用**:
- 更新订单成交数量和平均价格
- 触发 `on_order_fill` 回调（如果设置）

**示例**:
```zig
// 通常由 handleUserEvent 内部调用
// 也可以直接使用：
try manager.handleUserFill(fill);
```

---

### `handleOrderUpdate`

```zig
pub fn handleOrderUpdate(self: *OrderManager, ws_order: WsOrder) !void
```

**描述**: 处理订单状态更新事件

**参数**:
- `self`: OrderManager 实例指针
- `ws_order`: WebSocket 订单更新消息

**副作用**:
- 更新订单状态
- 触发 `on_order_update` 回调（如果设置）

**示例**:
```zig
// 在 WebSocket 订单更新频道中
const ws_order = try ws_client.readOrderUpdate();
try manager.handleOrderUpdate(ws_order);
```

---

## OrderStore 函数

### `init`

```zig
pub fn init(allocator: std.mem.Allocator) OrderStore
```

**描述**: 初始化订单存储

**参数**:
- `allocator`: 内存分配器

**返回**: 初始化的 `OrderStore` 实例

---

### `deinit`

```zig
pub fn deinit(self: *OrderStore) void
```

**描述**: 清理订单存储资源

---

### `add`

```zig
pub fn add(self: *OrderStore, order: *Order) !void
```

**描述**: 添加订单到存储

**参数**:
- `self`: OrderStore 实例指针
- `order`: 订单指针

**错误**:
- `error.OutOfMemory`: 内存分配失败

---

### `update`

```zig
pub fn update(self: *OrderStore, order: *Order) !void
```

**描述**: 更新订单状态和索引

**参数**:
- `self`: OrderStore 实例指针
- `order`: 订单指针

**错误**:
- `error.OutOfMemory`: 内存分配失败

**副作用**:
- 如果订单完成（status.isFinal()），从 active_orders 移到 history_orders
- 更新 orders_by_exchange_id 索引

---

### `getByClientId`

```zig
pub fn getByClientId(self: *OrderStore, client_order_id: []const u8) ?*Order
```

**描述**: 按客户端订单 ID 查询订单

**参数**:
- `self`: OrderStore 实例指针
- `client_order_id`: 客户端订单 ID

**返回**: 订单指针，如果不存在返回 `null`

**复杂度**: O(1)

---

### `getByExchangeId`

```zig
pub fn getByExchangeId(self: *OrderStore, exchange_order_id: u64) ?*Order
```

**描述**: 按交易所订单 ID 查询订单

**参数**:
- `self`: OrderStore 实例指针
- `exchange_order_id`: 交易所订单 ID

**返回**: 订单指针，如果不存在返回 `null`

**复杂度**: O(1)

---

### `getActive`

```zig
pub fn getActive(self: *OrderStore) ![]const *Order
```

**描述**: 获取所有活跃订单

**参数**:
- `self`: OrderStore 实例指针

**返回**: 活跃订单数组（调用者必须释放）

**错误**:
- `error.OutOfMemory`: 内存分配失败

---

### `getHistory`

```zig
pub fn getHistory(
    self: *OrderStore,
    symbol: ?[]const u8,
    limit: ?usize,
) ![]const *Order
```

**描述**: 获取历史订单

**参数**:
- `self`: OrderStore 实例指针
- `symbol`: 可选，按交易对过滤
- `limit`: 可选，限制返回数量

**返回**: 历史订单数组（调用者必须释放）

**错误**:
- `error.OutOfMemory`: 内存分配失败

---

## 完整示例

```zig
const std = @import("std");
const OrderManager = @import("trading/order_manager.zig").OrderManager;
const Order = @import("core/order.zig").Order;
const Decimal = @import("core/decimal.zig").Decimal;
const HyperliquidClient = @import("exchange/hyperliquid/http.zig").HyperliquidClient;
const HyperliquidWS = @import("exchange/hyperliquid/websocket.zig").HyperliquidWS;
const Logger = @import("core/logger.zig").Logger;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化日志
    var logger = try Logger.init(allocator, .info);
    defer logger.deinit();

    // 初始化客户端
    var http_client = try HyperliquidClient.init(allocator, .testnet);
    defer http_client.deinit();

    var ws_client = try HyperliquidWS.init(allocator, .testnet);
    defer ws_client.deinit();

    // 初始化订单管理器
    var manager = try OrderManager.init(
        allocator,
        &http_client,
        &ws_client,
        logger,
    );
    defer manager.deinit();

    // 设置回调
    manager.on_order_update = onOrderUpdate;
    manager.on_order_fill = onOrderFill;

    // 创建限价单
    var order1 = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.1"),
    );
    defer order1.deinit();

    // 提交订单
    try manager.submitOrder(&order1);
    std.debug.print("Order submitted: {s}\n", .{order1.client_order_id});

    // 等待一段时间
    std.time.sleep(5 * std.time.ns_per_s);

    // 查询活跃订单
    const active_orders = try manager.getActiveOrders();
    defer allocator.free(active_orders);
    std.debug.print("Active orders: {}\n", .{active_orders.len});

    // 取消订单
    if (order1.isCancellable()) {
        try manager.cancelOrder(&order1);
        std.debug.print("Order cancelled\n", .{});
    }

    // 查询历史
    const history = try manager.getOrderHistory("ETH", 10);
    defer allocator.free(history);
    std.debug.print("History orders: {}\n", .{history.len});
}

fn onOrderUpdate(order: *Order) void {
    std.debug.print("Order updated: {s} -> {s}\n", .{
        order.client_order_id,
        order.status.toString(),
    });
}

fn onOrderFill(order: *Order) void {
    std.debug.print("Order filled: {s} - {} @ {}\n", .{
        order.client_order_id,
        order.filled_quantity.toFloat(),
        order.avg_fill_price.?.toFloat(),
    });
}
```

---

## 错误处理示例

```zig
// 处理订单提交错误
try manager.submitOrder(&order) catch |err| switch (err) {
    error.OrderRejected => {
        std.debug.print("Order rejected: {s}\n", .{order.error_message.?});
    },
    error.InvalidOrderParams => {
        std.debug.print("Invalid order parameters\n", .{});
    },
    error.NetworkError => {
        std.debug.print("Network error, retrying...\n", .{});
        // 实现重试逻辑
    },
    else => return err,
};

// 处理取消错误
try manager.cancelOrder(&order) catch |err| switch (err) {
    error.OrderNotCancellable => {
        std.debug.print("Order cannot be cancelled (status: {s})\n", .{
            order.status.toString(),
        });
    },
    error.CancelOrderFailed => {
        std.debug.print("Failed to cancel order\n", .{});
    },
    else => return err,
};
```
