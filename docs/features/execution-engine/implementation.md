# ExecutionEngine - 实现细节

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 架构设计

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    ExecutionEngine                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                 Order Tracker                         │   │
│  │  ┌─────────────────┐   ┌─────────────────┐           │   │
│  │  │ Pending Orders  │   │ Tracked Orders  │           │   │
│  │  │   (Pre-track)   │   │   (Confirmed)   │           │   │
│  │  └─────────────────┘   └─────────────────┘           │   │
│  └──────────────────────────────────────────────────────┘   │
│                            │                                 │
│                            ▼                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                Exchange Adapter                       │   │
│  │  - API 调用                                           │   │
│  │  - 重试逻辑                                           │   │
│  │  - 超时处理                                           │   │
│  └──────────────────────────────────────────────────────┘   │
│                            │                                 │
│                            ▼                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  Event Publisher                      │   │
│  │           发布到 MessageBus                           │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 订单前置追踪模式

```
订单提交流程:

┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  策略    │────→│  Track   │────→│  Submit  │────→│ Exchange │
│  下单    │     │ (Pending)│     │  (API)   │     │          │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
                      │                                  │
                      │                                  │
                      │    ┌──────────────────────────────┘
                      │    │ WebSocket 订单更新
                      │    ▼
                      │ ┌──────────┐
                      └→│  Confirm │────→ 移动到 Tracked
                        │          │
                        └──────────┘

失败恢复:
                      ┌──────────┐
API 超时/失败 ───────→│  Pending │
                      │  Orders  │
                      └────┬─────┘
                           │
                    WebSocket 确认
                           │
                           ▼
                      ┌──────────┐
                      │ Tracked  │
                      │  Orders  │
                      └──────────┘
```

---

## 核心数据结构

### ExecutionEngine 结构

```zig
pub const ExecutionEngine = struct {
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    exchange: *IExchange,
    config: ExecutionConfig,

    // 订单追踪
    pending_orders: std.StringHashMap(Order),   // 待确认
    tracked_orders: std.StringHashMap(Order),   // 已确认

    // 状态
    is_running: bool,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        message_bus: *MessageBus,
        cache: *Cache,
        exchange: *IExchange,
        config: ExecutionConfig,
    ) !Self {
        var engine = Self{
            .allocator = allocator,
            .message_bus = message_bus,
            .cache = cache,
            .exchange = exchange,
            .config = config,
            .pending_orders = std.StringHashMap(Order).init(allocator),
            .tracked_orders = std.StringHashMap(Order).init(allocator),
            .is_running = false,
        };

        // 注册 MessageBus 端点
        try message_bus.register("order.submit", engine.handleSubmitRequest);
        try message_bus.register("order.cancel", engine.handleCancelRequest);

        // 订阅交易所事件
        try message_bus.subscribe("exchange.order.*", engine.onExchangeOrderUpdate);

        return engine;
    }
};
```

---

## 订单追踪实现

### 前置追踪

```zig
pub fn trackOrder(self: *Self, order: Order) !void {
    // 生成订单 ID (如果没有)
    const order_id = order.id orelse try self.generateOrderId();

    var tracked_order = order;
    tracked_order.id = order_id;
    tracked_order.status = .pending;
    tracked_order.created_at = std.time.milliTimestamp();

    // 保存到 pending_orders
    try self.pending_orders.put(order_id, tracked_order);

    // 发布 pending 事件
    try self.message_bus.publish("order.pending", .{
        .order_pending = tracked_order,
    });

    // 更新 Cache
    try self.cache.updateOrder(tracked_order);
}
```

### 订单确认

```zig
fn onExchangeOrderUpdate(self: *Self, event: Event) void {
    const update = switch (event) {
        .order_accepted => |o| o,
        .order_filled => |f| f.order,
        .order_rejected => |r| r.order,
        .order_cancelled => |o| o,
        else => return,
    };

    const order_id = update.client_order_id orelse update.id;

    // 从 pending 移动到 tracked
    if (self.pending_orders.fetchRemove(order_id)) |kv| {
        var order = kv.value;
        order.status = update.status;
        order.updated_at = std.time.milliTimestamp();

        if (update.status != .rejected and update.status != .cancelled) {
            self.tracked_orders.put(order_id, order) catch {};
        }

        // 更新 Cache
        self.cache.updateOrder(order) catch {};

        // 发布事件
        self.publishOrderEvent(order, event) catch {};
    }
}
```

---

## 订单提交实现

### 提交流程

```zig
pub fn submitOrder(self: *Self, order: Order) !void {
    // 确保已前置追踪
    if (!self.pending_orders.contains(order.id)) {
        try self.trackOrder(order);
    }

    // 更新状态为 submitted
    if (self.pending_orders.getPtr(order.id)) |o| {
        o.status = .submitted;
        o.updated_at = std.time.milliTimestamp();
    }

    // 发布 submitted 事件
    try self.message_bus.publish("order.submitted", .{
        .order_submitted = self.pending_orders.get(order.id).?,
    });

    // 调用交易所 API
    try self.submitToExchange(order);
}

fn submitToExchange(self: *Self, order: Order) !void {
    var retries: u32 = 0;

    while (retries < self.config.max_retries) : (retries += 1) {
        const result = self.exchange.submitOrder(.{
            .client_order_id = order.id,
            .instrument_id = order.instrument_id,
            .side = order.side,
            .order_type = order.order_type,
            .quantity = order.quantity,
            .price = order.price,
        });

        switch (result) {
            .success => return,
            .error => |e| {
                if (e == .rate_limit or e == .timeout) {
                    std.time.sleep(self.config.retry_interval_ms * std.time.ns_per_ms);
                    continue;
                }
                return error.ExchangeError;
            },
        }
    }

    return error.MaxRetriesExceeded;
}
```

---

## 订单取消实现

```zig
pub fn cancelOrder(self: *Self, order_id: []const u8) !void {
    // 检查订单存在
    const order = self.tracked_orders.get(order_id) orelse
        self.pending_orders.get(order_id) orelse
        return error.OrderNotFound;

    // 调用交易所取消 API
    try self.cancelOnExchange(order_id);

    // 更新状态
    if (self.tracked_orders.getPtr(order_id)) |o| {
        o.status = .cancelled;
        o.updated_at = std.time.milliTimestamp();
    }
}

pub fn cancelAllOrders(self: *Self, filter: ?OrderFilter) !CancelResult {
    var cancelled: u32 = 0;
    var failed: u32 = 0;

    var iter = self.tracked_orders.iterator();
    while (iter.next()) |entry| {
        const order = entry.value_ptr;

        // 应用过滤器
        if (filter) |f| {
            if (f.instrument_id) |id| {
                if (!std.mem.eql(u8, order.instrument_id, id)) continue;
            }
            if (f.side) |s| {
                if (order.side != s) continue;
            }
        }

        if (self.cancelOrder(entry.key_ptr.*)) {
            cancelled += 1;
        } else |_| {
            failed += 1;
        }
    }

    return CancelResult{
        .cancelled_count = cancelled,
        .failed_count = failed,
    };
}
```

---

## 订单恢复实现

### 恢复流程

```zig
pub fn recoverOrders(self: *Self) !RecoveryResult {
    var recovered: u32 = 0;
    var stale: u32 = 0;

    // 从交易所获取当前订单
    const exchange_orders = try self.exchange.getOpenOrders();

    for (exchange_orders) |ex_order| {
        // 检查是否在本地追踪
        if (self.pending_orders.contains(ex_order.client_order_id)) {
            // 从 pending 移动到 tracked
            if (self.pending_orders.fetchRemove(ex_order.client_order_id)) |kv| {
                var order = kv.value;
                order.status = ex_order.status;
                order.id = ex_order.id;
                try self.tracked_orders.put(order.id, order);
                recovered += 1;
            }
        } else {
            // 交易所有但本地没有 - 可能是之前的订单
            stale += 1;
        }
    }

    // 清理过期的 pending 订单
    var pending_iter = self.pending_orders.iterator();
    while (pending_iter.next()) |entry| {
        const order = entry.value_ptr;
        const age = std.time.milliTimestamp() - order.created_at;

        if (age > self.config.submit_timeout_ms * 10) {
            // 订单过期，标记为失败
            var failed_order = order.*;
            failed_order.status = .rejected;
            try self.cache.updateOrder(failed_order);
            _ = self.pending_orders.remove(entry.key_ptr.*);
        }
    }

    return RecoveryResult{
        .recovered_count = recovered,
        .stale_count = stale,
    };
}
```

---

## MessageBus 集成

### 请求处理器

```zig
fn handleSubmitRequest(self: *Self, req: Request) !Response {
    const submit_req = req.submit_order;

    const order = Order{
        .id = submit_req.client_order_id orelse try self.generateOrderId(),
        .instrument_id = submit_req.instrument_id,
        .side = submit_req.side,
        .order_type = submit_req.order_type,
        .quantity = submit_req.quantity,
        .price = submit_req.price,
    };

    try self.trackOrder(order);
    try self.submitOrder(order);

    return Response{
        .order_submitted = .{
            .order_id = order.id,
            .status = .submitted,
        },
    };
}

fn handleCancelRequest(self: *Self, req: Request) !Response {
    const cancel_req = req.cancel_order;

    try self.cancelOrder(cancel_req.order_id);

    return Response{
        .order_cancelled = .{
            .order_id = cancel_req.order_id,
        },
    };
}
```

### 事件发布

```zig
fn publishOrderEvent(self: *Self, order: Order, event_type: EventType) !void {
    const topic = switch (event_type) {
        .accepted => "order.accepted",
        .rejected => "order.rejected",
        .filled => "order.filled",
        .partially_filled => "order.partially_filled",
        .cancelled => "order.cancelled",
        else => return,
    };

    try self.message_bus.publish(topic, .{
        .order = order,
    });
}
```

---

## 错误处理

### 错误类型

```zig
pub const ExecutionError = error{
    OrderNotFound,
    SubmitTimeout,
    CancelTimeout,
    CancelRejected,
    MaxRetriesExceeded,
    ExchangeError,
    InvalidOrder,
    InsufficientBalance,
    OutOfMemory,
};
```

### 重试策略

```zig
const RetryPolicy = struct {
    max_retries: u32,
    base_delay_ms: u64,
    max_delay_ms: u64,

    fn getDelay(self: RetryPolicy, attempt: u32) u64 {
        // 指数退避
        const delay = self.base_delay_ms * std.math.pow(u64, 2, attempt);
        return @min(delay, self.max_delay_ms);
    }
};
```

---

## 性能优化

### 1. 批量订单提交

```zig
pub fn submitOrdersBatch(self: *Self, orders: []const Order) ![]SubmitResult {
    var results = try self.allocator.alloc(SubmitResult, orders.len);

    // 批量前置追踪
    for (orders) |order| {
        try self.trackOrder(order);
    }

    // 批量提交到交易所
    const exchange_results = try self.exchange.submitOrdersBatch(orders);

    for (exchange_results, 0..) |result, i| {
        results[i] = .{
            .order_id = orders[i].id,
            .success = result.success,
            .error_message = result.error_message,
        };
    }

    return results;
}
```

### 2. 异步确认

```zig
// WebSocket 订单更新是异步的
// 不阻塞等待确认，通过事件通知
fn onOrderConfirmed(self: *Self, order: Order) void {
    // 异步更新状态
    self.pending_orders.remove(order.id);
    self.tracked_orders.put(order.id, order) catch {};
}
```

---

## 文件结构

```
src/execution/
├── engine.zig               # ExecutionEngine 实现
├── order_tracker.zig        # 订单追踪器
├── recovery.zig             # 订单恢复
├── retry.zig                # 重试策略
└── types.zig                # 执行相关类型
```

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [测试文档](./testing.md)

---

**版本**: v0.5.0
**状态**: 计划中
