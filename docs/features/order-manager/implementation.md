# 订单管理器 - 实现细节

> 深入了解订单管理器的内部实现

**最后更新**: 2025-12-23

---

## 内部表示

### 核心数据结构

#### OrderManager

```zig
pub const OrderManager = struct {
    allocator: std.mem.Allocator,
    http_client: *HyperliquidClient,
    ws_client: *HyperliquidWS,
    order_store: OrderStore,
    logger: Logger,
    mutex: std.Thread.Mutex,

    // 回调函数
    on_order_update: ?*const fn (order: *Order) void,
    on_order_fill: ?*const fn (order: *Order) void,
};
```

#### OrderStore

```zig
pub const OrderStore = struct {
    allocator: std.mem.Allocator,

    // 双索引结构：按客户端 ID 和交易所 ID 索引
    orders_by_client_id: std.StringHashMap(*Order),
    orders_by_exchange_id: std.AutoHashMap(u64, *Order),

    // 订单列表：活跃订单和历史订单分离
    active_orders: std.ArrayList(*Order),
    history_orders: std.ArrayList(*Order),
};
```

---

## 订单提交流程

### 1. 订单验证

提交订单前进行完整性检查：

```zig
pub fn submitOrder(self: *OrderManager, order: *Order) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    // 验证订单参数
    try order.validate();

    // 记录到本地存储
    try self.order_store.add(order);

    // ... 提交到交易所
}
```

### 2. 构造请求

基于 Hyperliquid 真实 API 格式：

```zig
const request = ExchangeAPI.OrderRequest{
    .coin = order.symbol,                    // a: 交易对
    .is_buy = (order.side == .buy),         // b: 买卖方向
    .sz = order.quantity,                    // s: 数量
    .limit_px = order.price orelse Decimal.ZERO, // p: 价格
    .order_type = .{
        .limit = if (order.order_type == .limit) .{
            .tif = order.time_in_force.toString(), // t: Gtc/Ioc/Alo
        } else null,
    },
    .reduce_only = order.reduce_only,        // r: 只减仓
    .cloid = order.client_order_id,          // c: 客户端订单 ID
};
```

### 3. 处理响应

Hyperliquid API 返回三种状态：

```zig
switch (status) {
    .resting => |resting| {
        // 订单挂单成功
        order.exchange_order_id = resting.oid;
        order.updateStatus(.open);
    },
    .filled => |filled| {
        // 订单立即成交
        order.exchange_order_id = filled.oid;
        const total_sz = try Decimal.fromString(filled.totalSz);
        const avg_px = try Decimal.fromString(filled.avgPx);
        order.updateFill(total_sz, avg_px, Decimal.ZERO);
    },
    .error => |err_msg| {
        // 订单被拒绝
        order.updateStatus(.rejected);
        order.error_message = try self.allocator.dupe(u8, err_msg);
        return Error.OrderRejected;
    },
}
```

**复杂度**: O(1) - 哈希表插入
**说明**: 订单提交包括验证、存储、网络请求和响应处理

---

## 订单取消逻辑

### 单个订单取消

```zig
pub fn cancelOrder(self: *OrderManager, order: *Order) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    // 检查可取消性
    if (!order.isCancellable()) {
        return Error.OrderNotCancellable;
    }

    // 构造取消请求
    const request = ExchangeAPI.CancelRequest{
        .coin = order.symbol,
        .oid = order.exchange_order_id.?,
    };

    // 提交到交易所
    const response = try ExchangeAPI.cancelOrder(self.http_client, request);

    // 处理响应
    if (std.mem.eql(u8, response.status, "ok")) {
        order.updateStatus(.cancelled);
        try self.order_store.update(order);
    }
}
```

### 按 CLOID 取消

支持通过客户端订单 ID 取消：

```zig
pub fn cancelOrderByCloid(
    self: *OrderManager,
    coin: []const u8,
    cloid: []const u8,
) !void {
    const response = try ExchangeAPI.cancelByCloid(self.http_client, coin, cloid);

    if (std.mem.eql(u8, response.status, "ok")) {
        // 更新本地订单状态
        if (self.order_store.getByClientId(cloid)) |order| {
            order.updateStatus(.cancelled);
            try self.order_store.update(order);
        }
    }
}
```

### 批量取消

```zig
pub fn cancelOrders(self: *OrderManager, orders: []const *Order) !void {
    var cancel_requests = std.ArrayList(ExchangeAPI.CancelRequest).init(self.allocator);
    defer cancel_requests.deinit();

    // 收集可取消的订单
    for (orders) |order| {
        if (order.isCancellable()) {
            try cancel_requests.append(.{
                .coin = order.symbol,
                .oid = order.exchange_order_id.?,
            });
        }
    }

    // 批量提交
    const responses = try ExchangeAPI.cancelOrders(
        self.http_client,
        cancel_requests.items,
    );
    defer self.allocator.free(responses);

    // 更新订单状态
    for (responses, 0..) |response, i| {
        if (std.mem.eql(u8, response.status, "ok")) {
            orders[i].updateStatus(.cancelled);
            try self.order_store.update(orders[i]);
        }
    }
}
```

**复杂度**: O(n) - n 为订单数量
**说明**: 批量取消减少网络往返，提高效率

---

## 订单状态追踪

### 状态机

订单状态转换：

```
pending -> open -> (partially_filled) -> filled
       \-> rejected
       \-> cancelled

open -> cancelled
partially_filled -> cancelled
```

### 状态同步

通过 WebSocket 实时同步：

```zig
pub fn handleOrderUpdate(self: *OrderManager, ws_order: WsOrder) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const order = self.order_store.getByExchangeId(ws_order.order.oid) orelse {
        self.logger.warn("Received update for unknown order: OID={}", .{ws_order.order.oid});
        return;
    };

    // 根据 WebSocket 状态更新本地订单
    if (std.mem.eql(u8, ws_order.status, "resting")) {
        order.updateStatus(.open);
    } else if (std.mem.eql(u8, ws_order.status, "filled")) {
        order.updateStatus(.filled);
    } else if (std.mem.eql(u8, ws_order.status, "canceled")) {
        order.updateStatus(.cancelled);
    } else if (std.mem.eql(u8, ws_order.status, "triggered")) {
        order.updateStatus(.triggered);
    } else if (std.mem.eql(u8, ws_order.status, "rejected")) {
        order.updateStatus(.rejected);
    }

    try self.order_store.update(order);

    // 触发回调
    if (self.on_order_update) |callback| {
        callback(order);
    }
}
```

---

## 成交事件处理

### 处理 WebSocket 成交事件

```zig
pub fn handleUserFill(self: *OrderManager, fill: WsUserFills.UserFill) !void {
    const order = self.order_store.getByExchangeId(fill.oid) orelse {
        self.logger.warn("Received fill for unknown order: OID={}", .{fill.oid});
        return;
    };

    // 解析成交数据（Hyperliquid 返回字符串格式）
    const sz = try Decimal.fromString(fill.sz);
    const px = try Decimal.fromString(fill.px);
    const fee = try Decimal.fromString(fill.fee);

    // 更新订单成交信息
    order.updateFill(sz, px, fee);
    try self.order_store.update(order);

    // 记录已实现盈亏
    if (!std.mem.eql(u8, fill.closedPnl, "0.0")) {
        const closed_pnl = try Decimal.fromString(fill.closedPnl);
        self.logger.info("Closed PnL: {}", .{closed_pnl.toFloat()});
    }

    // 触发回调
    if (self.on_order_fill) |callback| {
        callback(order);
    }
}
```

### 成交方向识别

Hyperliquid 的 `dir` 字段：

- `"Open Long"`: 开多仓
- `"Close Long"`: 平多仓
- `"Open Short"`: 开空仓
- `"Close Short"`: 平空仓

```zig
const is_opening = std.mem.indexOf(u8, fill.dir, "Open") != null;
```

---

## 错误处理机制

### 错误类型

```zig
pub const OrderError = error{
    OrderRejected,           // 订单被交易所拒绝
    OrderNotCancellable,     // 订单不可取消
    OrderNotSubmitted,       // 订单未提交
    CancelOrderFailed,       // 取消订单失败
    NetworkError,            // 网络错误
    InvalidOrderParams,      // 订单参数无效
};
```

### 错误处理策略

#### 1. 订单拒绝

```zig
.error => |err_msg| {
    order.updateStatus(.rejected);
    order.error_message = try self.allocator.dupe(u8, err_msg);
    self.logger.err("Order rejected: {s}", .{err_msg});
    return Error.OrderRejected;
}
```

常见拒绝原因：
- 价格超出限制
- 数量不符合规则
- 余额不足
- 市场暂停交易

#### 2. 网络错误

```zig
const response = ExchangeAPI.placeOrder(self.http_client, request) catch |err| {
    order.updateStatus(.error);
    self.logger.err("Network error submitting order: {}", .{err});
    return err;
};
```

#### 3. 状态不一致

使用 WebSocket 作为真实状态源：

```zig
// HTTP 响应仅用于初始确认
// WebSocket 更新作为权威状态
pub fn handleUserEvent(self: *OrderManager, event: WsUserEvent) !void {
    // ... 处理 fills, nonUserCancel 等事件
}
```

### 重试机制

对于网络错误，可以实现重试：

```zig
var retries: usize = 0;
const max_retries = 3;

while (retries < max_retries) : (retries += 1) {
    const response = ExchangeAPI.placeOrder(self.http_client, request) catch |err| {
        if (retries == max_retries - 1) return err;
        std.time.sleep(std.time.ns_per_s * (retries + 1)); // 指数退避
        continue;
    };
    break;
}
```

---

## 并发安全

### Mutex 保护

所有公共方法使用 Mutex 保护：

```zig
pub fn submitOrder(self: *OrderManager, order: *Order) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    // ... 操作订单
}
```

### 线程安全的订单存储

OrderStore 本身不是线程安全的，依赖 OrderManager 的 Mutex 保护：

```zig
// OrderManager 确保所有对 order_store 的访问都在锁保护下
try self.order_store.add(order);        // 在 mutex.lock() 内
try self.order_store.update(order);     // 在 mutex.lock() 内
```

---

## 内存管理

### 订单生命周期

```zig
// 1. 订单创建（调用者管理）
var order = try Order.init(allocator, "ETH", .buy, .limit, price, qty);
defer order.deinit();

// 2. 订单提交（OrderManager 持有指针）
try manager.submitOrder(&order);

// 3. 订单完成（从 active 移到 history）
// OrderStore 内部管理，不释放 Order 对象
```

### 内存所有权

- **Order 对象**: 调用者拥有，OrderManager 只保存指针
- **查询结果**: 调用者负责释放

```zig
const active_orders = try manager.getActiveOrders();
defer allocator.free(active_orders);  // 调用者必须释放
```

---

## 性能优化

### 1. 双索引结构

O(1) 查询复杂度：

```zig
// 按客户端 ID 查询
pub fn getByClientId(self: *OrderStore, client_order_id: []const u8) ?*Order {
    return self.orders_by_client_id.get(client_order_id);  // O(1)
}

// 按交易所 ID 查询
pub fn getByExchangeId(self: *OrderStore, exchange_order_id: u64) ?*Order {
    return self.orders_by_exchange_id.get(exchange_order_id);  // O(1)
}
```

### 2. 订单列表分离

活跃订单和历史订单分离，减少查询范围：

```zig
pub fn getActive(self: *OrderStore) ![]const *Order {
    return try self.allocator.dupe(*Order, self.active_orders.items);
}
```

### 3. 批量操作

批量取消减少网络往返：

```zig
// 单个取消：n 次网络请求
for (orders) |order| {
    try manager.cancelOrder(order);  // 每次都发送请求
}

// 批量取消：1 次网络请求
try manager.cancelOrders(orders);  // 一次性发送所有请求
```

---

## 边界情况

### 1. 未知订单的 WebSocket 事件

```zig
const order = self.order_store.getByExchangeId(fill.oid) orelse {
    self.logger.warn("Received fill for unknown order: OID={}", .{fill.oid});
    return;  // 忽略未知订单的事件
};
```

### 2. 重复的成交事件

订单累积成交数量，不会重复计算：

```zig
pub fn updateFill(self: *Order, sz: Decimal, px: Decimal, fee: Decimal) void {
    self.filled_quantity = self.filled_quantity.add(sz);  // 累加
    // 更新平均成交价
    // ...
}
```

### 3. 订单取消后收到成交

以 WebSocket 事件为准：

```zig
// 如果先收到取消确认，后收到成交事件
// WebSocket 的最新状态会覆盖本地状态
```

### 4. 网络断开重连

重连后查询所有活跃订单：

```zig
pub fn syncActiveOrders(self: *OrderManager) !void {
    // 查询交易所所有活跃订单
    const exchange_orders = try ExchangeAPI.getOpenOrders(self.http_client);

    // 与本地状态对比，更新差异
    // ...
}
```

---

*完整实现请参考: `src/trading/order_manager.zig`, `src/trading/order_store.zig`*
