# ExecutionEngine - API 参考

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 核心类型

### ExecutionEngine

执行引擎主结构体。

```zig
pub const ExecutionEngine = struct {
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    exchange: *IExchange,
    config: ExecutionConfig,

    // 订单追踪
    pending_orders: StringHashMap(Order),
    tracked_orders: StringHashMap(Order),
};
```

### ExecutionConfig

```zig
pub const ExecutionConfig = struct {
    /// 订单提交超时 (毫秒)
    submit_timeout_ms: u64 = 5000,

    /// 订单取消超时 (毫秒)
    cancel_timeout_ms: u64 = 3000,

    /// 最大重试次数
    max_retries: u32 = 3,

    /// 重试间隔 (毫秒)
    retry_interval_ms: u64 = 1000,

    /// 是否启用订单恢复
    enable_recovery: bool = true,

    /// 是否启用订单前置追踪
    enable_pre_tracking: bool = true,
};
```

---

## 初始化与销毁

### init

初始化 ExecutionEngine。

```zig
pub fn init(
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    exchange: *IExchange,
    config: ExecutionConfig,
) !ExecutionEngine
```

**参数**:
- `allocator`: 内存分配器
- `message_bus`: MessageBus 实例引用
- `cache`: Cache 实例引用
- `exchange`: 交易所接口
- `config`: 执行配置

**返回**: ExecutionEngine 实例

**示例**:
```zig
var execution_engine = try ExecutionEngine.init(
    allocator,
    &message_bus,
    &cache,
    &exchange,
    .{
        .submit_timeout_ms = 5000,
        .enable_recovery = true,
    },
);
defer execution_engine.deinit();
```

### deinit

释放 ExecutionEngine 资源。

```zig
pub fn deinit(self: *ExecutionEngine) void
```

---

## 订单操作

### trackOrder

前置追踪订单（提交前调用）。

```zig
pub fn trackOrder(self: *ExecutionEngine, order: Order) !void
```

**说明**: 将订单添加到 pending_orders，确保即使 API 调用失败也能追踪订单状态。

**示例**:
```zig
const order = Order{
    .id = uuid.generate(),
    .client_order_id = "my-order-001",
    .instrument_id = "BTC-USDT",
    .side = .buy,
    .order_type = .limit,
    .quantity = 0.1,
    .price = 50000,
};

// 前置追踪
try execution_engine.trackOrder(order);

// 然后提交
try execution_engine.submitOrder(order);
```

### submitOrder

提交订单到交易所。

```zig
pub fn submitOrder(self: *ExecutionEngine, order: Order) !void
```

**错误**:
- `SubmitTimeout`: 提交超时
- `ExchangeError`: 交易所返回错误
- `OutOfMemory`: 内存分配失败

**示例**:
```zig
try execution_engine.submitOrder(.{
    .instrument_id = "BTC-USDT",
    .side = .buy,
    .order_type = .limit,
    .quantity = 0.1,
    .price = 50000,
});
```

### cancelOrder

取消订单。

```zig
pub fn cancelOrder(self: *ExecutionEngine, order_id: []const u8) !void
```

**错误**:
- `OrderNotFound`: 订单不存在
- `CancelTimeout`: 取消超时
- `CancelRejected`: 取消被拒绝

**示例**:
```zig
try execution_engine.cancelOrder("order-123");
```

### cancelAllOrders

取消所有订单（可选过滤）。

```zig
pub fn cancelAllOrders(
    self: *ExecutionEngine,
    filter: ?OrderFilter,
) !CancelResult
```

**参数**:
- `filter`: 可选过滤器

**返回**: 取消结果

**示例**:
```zig
// 取消所有 BTC-USDT 订单
const result = try execution_engine.cancelAllOrders(.{
    .instrument_id = "BTC-USDT",
});

std.debug.print("Cancelled: {}, Failed: {}\n", .{
    result.cancelled_count,
    result.failed_count,
});
```

### modifyOrder

修改订单。

```zig
pub fn modifyOrder(
    self: *ExecutionEngine,
    order_id: []const u8,
    modifications: OrderModification,
) !void
```

**示例**:
```zig
try execution_engine.modifyOrder("order-123", .{
    .new_price = 50500,
    .new_quantity = 0.2,
});
```

---

## 订单查询

### getPendingOrders

获取待处理订单（已追踪但未确认）。

```zig
pub fn getPendingOrders(self: *ExecutionEngine) []*const Order
```

### getTrackedOrders

获取已追踪订单（已确认的活跃订单）。

```zig
pub fn getTrackedOrders(self: *ExecutionEngine) []*const Order
```

### getOrderStatus

获取订单状态。

```zig
pub fn getOrderStatus(
    self: *ExecutionEngine,
    order_id: []const u8,
) !OrderStatus
```

### isOrderPending

检查订单是否在待处理状态。

```zig
pub fn isOrderPending(self: *ExecutionEngine, order_id: []const u8) bool
```

---

## 订单恢复

### recoverOrders

恢复订单状态（系统重启后调用）。

```zig
pub fn recoverOrders(self: *ExecutionEngine) !RecoveryResult
```

**返回**: 恢复结果

**示例**:
```zig
const result = try execution_engine.recoverOrders();
std.debug.print("Recovered: {}, Stale: {}\n", .{
    result.recovered_count,
    result.stale_count,
});
```

### syncWithExchange

与交易所同步订单状态。

```zig
pub fn syncWithExchange(self: *ExecutionEngine) !void
```

---

## MessageBus 集成

### 注册的端点

ExecutionEngine 注册以下请求端点：

| 端点 | 请求类型 | 响应类型 |
|------|----------|----------|
| `order.submit` | SubmitOrderRequest | SubmitOrderResponse |
| `order.cancel` | CancelOrderRequest | CancelOrderResponse |
| `order.modify` | ModifyOrderRequest | ModifyOrderResponse |
| `order.query` | QueryOrderRequest | QueryOrderResponse |

**示例**:
```zig
// 通过 MessageBus 提交订单
const response = try message_bus.request("order.submit", .{
    .submit_order = .{
        .instrument_id = "BTC-USDT",
        .side = .buy,
        .quantity = 0.1,
        .price = 50000,
    },
});

std.debug.print("Order ID: {s}\n", .{response.order_id});
```

### 发布的事件

ExecutionEngine 发布以下事件：

| 事件主题 | 事件类型 | 触发条件 |
|----------|----------|----------|
| `order.pending` | OrderEvent | 订单前置追踪 |
| `order.submitted` | OrderEvent | 订单已提交 |
| `order.accepted` | OrderEvent | 订单被接受 |
| `order.rejected` | OrderRejectEvent | 订单被拒绝 |
| `order.filled` | OrderFillEvent | 订单成交 |
| `order.partially_filled` | OrderFillEvent | 部分成交 |
| `order.cancelled` | OrderEvent | 订单已取消 |

---

## 数据类型

### Order

```zig
pub const Order = struct {
    id: []const u8,
    client_order_id: []const u8,
    instrument_id: []const u8,
    side: Side,
    order_type: OrderType,
    quantity: Decimal,
    filled_quantity: Decimal,
    price: ?Decimal,
    stop_price: ?Decimal,
    time_in_force: TimeInForce,
    status: OrderStatus,
    created_at: i64,
    updated_at: i64,
};
```

### OrderStatus

```zig
pub const OrderStatus = enum {
    pending,           // 前置追踪中
    submitted,         // 已提交
    accepted,          // 已接受
    partially_filled,  // 部分成交
    filled,            // 完全成交
    cancelled,         // 已取消
    rejected,          // 被拒绝
    expired,           // 已过期
};
```

### OrderType

```zig
pub const OrderType = enum {
    market,
    limit,
    stop_market,
    stop_limit,
    trailing_stop,
};
```

### TimeInForce

```zig
pub const TimeInForce = enum {
    gtc,  // Good Till Cancel
    ioc,  // Immediate or Cancel
    fok,  // Fill or Kill
    day,  // Day Order
};
```

### OrderFilter

```zig
pub const OrderFilter = struct {
    instrument_id: ?[]const u8 = null,
    side: ?Side = null,
    status: ?OrderStatus = null,
};
```

---

## 相关文档

- [功能概览](./README.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)

---

**版本**: v0.5.0
**状态**: 计划中
