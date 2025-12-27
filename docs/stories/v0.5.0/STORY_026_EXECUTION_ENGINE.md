# Story 026: ExecutionEngine - 执行引擎

**版本**: v0.5.0
**状态**: ✅ 核心功能已完成 (85%)
**完成时间**: 2025-12-27
**代码文件**: `src/core/execution_engine.zig` (~815 行)
**依赖**: Story 023 (MessageBus), Story 024 (Cache)

---

## 目标

实现订单执行引擎，支持订单前置追踪（Hummingbot 模式），确保零订单丢失。

## 背景

当前订单管理存在的问题：
- API 超时可能导致订单状态未知
- 没有订单前置追踪机制
- 缺乏可靠的订单恢复机制

参考 **Hummingbot** 的订单追踪设计：
- 提交前就开始追踪订单
- WebSocket 监听订单更新
- 超时自动查询订单状态

---

## 核心设计

### 订单生命周期

```
┌─────────────────────────────────────────────────────────────┐
│                   Order Lifecycle                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Strategy                                                    │
│     │                                                        │
│     │ 1. Create Order                                       │
│     ▼                                                        │
│  ┌──────────────┐                                           │
│  │   PENDING    │  ← 订单前置追踪                           │
│  │  (pre-track) │                                           │
│  └──────┬───────┘                                           │
│         │                                                    │
│         │ 2. Submit to Exchange                             │
│         ▼                                                    │
│  ┌──────────────┐       ┌──────────────┐                   │
│  │  SUBMITTED   │──────→│   REJECTED   │ (API 失败)        │
│  └──────┬───────┘       └──────────────┘                   │
│         │                                                    │
│         │ 3. Exchange Confirms                              │
│         ▼                                                    │
│  ┌──────────────┐       ┌──────────────┐                   │
│  │   ACCEPTED   │──────→│  CANCELLED   │ (撤单)            │
│  └──────┬───────┘       └──────────────┘                   │
│         │                                                    │
│         │ 4. Fill Events                                    │
│         ▼                                                    │
│  ┌──────────────┐       ┌──────────────┐                   │
│  │PARTIALLY_FILL│──────→│    FILLED    │ (完全成交)        │
│  └──────────────┘       └──────────────┘                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 接口定义

```zig
pub const ExecutionEngine = struct {
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    exchange: *IExchange,

    // 订单追踪
    pending_orders: StringHashMap(Order),    // 前置追踪 (提交前)
    tracked_orders: StringHashMap(Order),    // 已追踪 (已提交)
    pending_cancels: StringHashMap(i64),     // 待取消订单

    // 配置
    config: ExecutionConfig,

    /// 初始化
    pub fn init(
        allocator: Allocator,
        message_bus: *MessageBus,
        cache: *Cache,
        exchange: *IExchange,
        config: ExecutionConfig,
    ) !ExecutionEngine {
        var engine = ExecutionEngine{
            .allocator = allocator,
            .message_bus = message_bus,
            .cache = cache,
            .exchange = exchange,
            .pending_orders = StringHashMap(Order).init(allocator),
            .tracked_orders = StringHashMap(Order).init(allocator),
            .pending_cancels = StringHashMap(i64).init(allocator),
            .config = config,
        };

        // 注册命令处理器
        try message_bus.register("order.submit", engine.handleSubmitOrder);
        try message_bus.register("order.cancel", engine.handleCancelOrder);

        // 订阅交易所订单更新
        try message_bus.subscribe("exchange.order.*", engine.onExchangeOrderUpdate);

        return engine;
    }

    // ========== 订单提交 ==========

    /// 处理订单提交命令
    fn handleSubmitOrder(self: *ExecutionEngine, request: Request) !Response {
        const cmd = request.submit_order;

        // 1. 创建订单
        const order = Order{
            .id = try self.generateOrderId(),
            .client_order_id = try self.generateClientOrderId(),
            .instrument_id = cmd.instrument_id,
            .side = cmd.side,
            .order_type = cmd.order_type,
            .quantity = cmd.quantity,
            .price = cmd.price,
            .status = .pending,
            .created_at = std.time.milliTimestamp(),
        };

        // 2. 前置追踪
        try self.trackOrder(order);

        // 3. 提交到交易所
        try self.submitOrder(order);

        return .{ .order_id = order.id };
    }

    /// 步骤 1: 前置追踪 (提交前)
    pub fn trackOrder(self: *ExecutionEngine, order: Order) !void {
        try self.pending_orders.put(order.client_order_id, order);

        // 发布事件
        try self.message_bus.publish("order.pending", .{
            .order_pending = .{ .order = order },
        });

        log.debug("Order pre-tracked: {s}", .{order.client_order_id});
    }

    /// 步骤 2: 提交订单
    pub fn submitOrder(self: *ExecutionEngine, order: Order) !void {
        // 发布提交事件
        try self.message_bus.publish("order.submitting", .{
            .order_submitting = .{ .order = order },
        });

        // 提交到交易所 (可能超时)
        const result = self.exchange.submitOrder(order) catch |err| {
            // API 失败 - 但订单已在 pending_orders 中追踪
            // 等待 WebSocket 确认或超时查询
            log.warn("Order submit failed: {}, waiting for WS confirmation", .{err});

            // 设置超时检查
            try self.scheduleOrderCheck(order.client_order_id, self.config.submit_timeout_ms);

            return err;
        };

        // 成功 - 从 pending 移到 tracked
        _ = self.pending_orders.remove(order.client_order_id);

        var tracked_order = order;
        tracked_order.exchange_order_id = result.exchange_order_id;
        tracked_order.status = .submitted;

        try self.tracked_orders.put(order.client_order_id, tracked_order);
        try self.cache.updateOrder(tracked_order);

        // 发布提交成功事件
        try self.message_bus.publish("order.submitted", .{
            .order_submitted = .{ .order = tracked_order },
        });

        log.info("Order submitted: {s} -> {s}", .{
            order.client_order_id,
            result.exchange_order_id,
        });
    }

    // ========== 订单取消 ==========

    /// 处理订单取消命令
    fn handleCancelOrder(self: *ExecutionEngine, request: Request) !Response {
        const cmd = request.cancel_order;

        // 获取订单
        const order = self.tracked_orders.get(cmd.order_id) orelse
            return error.OrderNotFound;

        // 记录待取消
        try self.pending_cancels.put(order.client_order_id, std.time.milliTimestamp());

        // 发送取消请求
        try self.exchange.cancelOrder(order.exchange_order_id.?);

        return .{ .success = true };
    }

    // ========== 交易所事件处理 ==========

    /// 处理交易所订单更新
    fn onExchangeOrderUpdate(self: *ExecutionEngine, event: Event) void {
        const update = event.exchange_order_update;

        // 检查是否是 pending 订单 (API 超时但实际成功的情况)
        if (self.pending_orders.get(update.client_order_id)) |order| {
            log.info("Pending order confirmed via WS: {s}", .{order.client_order_id});

            // 从 pending 移到 tracked
            _ = self.pending_orders.remove(order.client_order_id);

            var tracked_order = order;
            tracked_order.exchange_order_id = update.exchange_order_id;
            tracked_order.status = update.status;

            self.tracked_orders.put(order.client_order_id, tracked_order) catch {};
            self.cache.updateOrder(tracked_order) catch {};
        }

        // 更新已追踪订单
        if (self.tracked_orders.getPtr(update.client_order_id)) |order| {
            order.status = update.status;
            order.filled_quantity = update.filled_quantity;
            order.updated_at = update.timestamp;

            self.cache.updateOrder(order.*) catch {};

            // 发布状态变更事件
            const topic = switch (update.status) {
                .accepted => "order.accepted",
                .partially_filled => "order.partially_filled",
                .filled => "order.filled",
                .cancelled => "order.cancelled",
                .rejected => "order.rejected",
                else => "order.updated",
            };

            self.message_bus.publish(topic, .{
                .order_event = .{ .order = order.* },
            }) catch {};

            // 如果订单完成，从追踪列表移除
            if (update.status == .filled or
                update.status == .cancelled or
                update.status == .rejected)
            {
                _ = self.tracked_orders.remove(update.client_order_id);
            }
        }
    }

    // ========== 订单恢复 ==========

    /// 检查超时订单
    fn checkPendingOrder(self: *ExecutionEngine, client_order_id: []const u8) !void {
        const order = self.pending_orders.get(client_order_id) orelse return;

        // 查询交易所订单状态
        const status = try self.exchange.queryOrder(client_order_id);

        if (status.found) {
            // 订单存在，从 pending 移到 tracked
            _ = self.pending_orders.remove(client_order_id);

            var tracked_order = order;
            tracked_order.exchange_order_id = status.exchange_order_id;
            tracked_order.status = status.status;

            try self.tracked_orders.put(client_order_id, tracked_order);
            try self.cache.updateOrder(tracked_order);

            log.info("Pending order recovered: {s}", .{client_order_id});
        } else {
            // 订单不存在，标记为失败
            _ = self.pending_orders.remove(client_order_id);

            var failed_order = order;
            failed_order.status = .rejected;

            try self.cache.updateOrder(failed_order);

            try self.message_bus.publish("order.rejected", .{
                .order_rejected = .{ .order = failed_order, .reason = "Not found on exchange" },
            });

            log.warn("Pending order not found: {s}", .{client_order_id});
        }
    }

    /// 启动时恢复订单状态
    pub fn recoverOrders(self: *ExecutionEngine) !void {
        log.info("Recovering orders from cache...");

        const open_orders = self.cache.getOpenOrders();

        for (open_orders) |order| {
            // 查询交易所确认状态
            const status = self.exchange.queryOrder(order.exchange_order_id.?) catch continue;

            if (status.status != order.status) {
                // 状态不一致，更新
                var updated_order = order.*;
                updated_order.status = status.status;
                updated_order.filled_quantity = status.filled_quantity;

                try self.cache.updateOrder(updated_order);
                try self.tracked_orders.put(order.client_order_id, updated_order);

                log.info("Order status recovered: {s} -> {}", .{
                    order.client_order_id,
                    status.status,
                });
            } else {
                // 状态一致，继续追踪
                try self.tracked_orders.put(order.client_order_id, order.*);
            }
        }

        log.info("Recovered {} orders", .{open_orders.len});
    }

    // ========== 辅助方法 ==========

    fn generateOrderId(self: *ExecutionEngine) ![]const u8 {
        _ = self;
        // UUID 或时间戳 + 随机数
        return try std.fmt.allocPrint(self.allocator, "ord_{d}_{d}", .{
            std.time.milliTimestamp(),
            std.crypto.random.int(u32),
        });
    }

    fn generateClientOrderId(self: *ExecutionEngine) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "cli_{d}_{d}", .{
            std.time.milliTimestamp(),
            std.crypto.random.int(u32),
        });
    }

    fn scheduleOrderCheck(self: *ExecutionEngine, client_order_id: []const u8, delay_ms: u64) !void {
        // 使用 libxev 定时器调度检查
        _ = self;
        _ = client_order_id;
        _ = delay_ms;
        // TODO: 实现定时器
    }

    pub fn deinit(self: *ExecutionEngine) void {
        self.pending_orders.deinit();
        self.tracked_orders.deinit();
        self.pending_cancels.deinit();
    }
};
```

---

## 配置

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
};
```

---

## 使用示例

### 策略提交订单

```zig
pub fn onSignal(self: *Strategy, signal: Signal) !void {
    // 通过 MessageBus 发送订单命令
    const response = try self.message_bus.request("order.submit", .{
        .submit_order = .{
            .instrument_id = signal.instrument_id,
            .side = signal.side,
            .order_type = .limit,
            .quantity = signal.quantity,
            .price = signal.price,
        },
    });

    log.info("Order submitted: {s}", .{response.order_id});
}

pub fn onOrderFilled(self: *Strategy, event: Event) void {
    const order = event.order_filled.order;
    log.info("Order filled: {s} @ {}", .{order.id, order.fill_price});

    // 更新策略状态
    self.updatePosition(order);
}
```

### 系统启动恢复

```zig
pub fn main() !void {
    // ... 初始化代码 ...

    // 创建执行引擎
    var execution_engine = try ExecutionEngine.init(
        allocator,
        &message_bus,
        &cache,
        &exchange,
        .{ .enable_recovery = true },
    );
    defer execution_engine.deinit();

    // 恢复订单状态 (Crash Recovery)
    try execution_engine.recoverOrders();

    // 启动交易
    try run_trading_loop();
}
```

---

## 测试计划

### 单元测试

| 测试 | 描述 |
|------|------|
| `test_order_pre_track` | 订单前置追踪 |
| `test_order_submit_success` | 订单提交成功 |
| `test_order_submit_timeout` | 订单提交超时处理 |
| `test_order_cancel` | 订单取消 |
| `test_order_recovery` | 订单恢复 |
| `test_ws_confirmation` | WebSocket 确认 |

### 集成测试

| 测试 | 描述 |
|------|------|
| `test_full_order_lifecycle` | 完整订单生命周期 |
| `test_crash_recovery` | 崩溃恢复 |
| `test_api_failure_handling` | API 失败处理 |

---

## 文件结构

```
src/execution/
├── engine.zig               # ExecutionEngine 实现
├── order_tracker.zig        # 订单追踪器
├── recovery.zig             # 订单恢复
└── types.zig                # 执行相关类型

tests/
└── execution/
    └── engine_test.zig      # ExecutionEngine 测试
```

---

## 验收标准

- [x] IExecutionClient 接口定义 (VTable 模式)
- [x] 订单提交 (`submitOrder`)
- [x] 订单取消 (`cancelOrder`, `cancelAllOrders`)
- [x] 风险检查 (`checkRisk`) - 订单大小、挂单数量、下单间隔
- [x] 订单追踪 (`pending_orders`, `active_orders`)
- [x] 与 MessageBus 和 Cache 集成
- [x] MockExecutionClient 用于测试
- [x] 零内存泄漏 (测试验证)
- [x] 所有测试通过 (5+ 测试用例)

### 待实现功能

- [ ] 订单恢复 (`recoverOrders`)
- [ ] 超时订单检查 (`scheduleOrderCheck`) - 需 libxev 定时器
- [ ] WebSocket 订单更新处理 (需 libxev)

---

## 相关文档

- [v0.5.0 Overview](./OVERVIEW.md)
- [Story 023: MessageBus](./STORY_023_MESSAGE_BUS.md)
- [Story 024: Cache](./STORY_024_CACHE.md)
- [Story 027: libxev Integration](./STORY_027_LIBXEV_INTEGRATION.md)
- [架构模式: 订单前置追踪](../../architecture/ARCHITECTURE_PATTERNS.md#订单前置追踪)

---

**版本**: v0.5.0
**状态**: ✅ 核心功能已完成 (85%)
**创建时间**: 2025-12-27
**完成时间**: 2025-12-27

## 实现亮点

- **IExecutionClient 接口**: VTable 模式实现多态，支持任意交易所
- **RiskConfig**: 可配置风险检查 (max_position_size, max_order_size, max_daily_loss 等)
- **订单追踪**: pending_orders (待确认) 和 active_orders (已确认) 分离
- **MockExecutionClient**: 用于测试的 mock 实现，模拟立即成交
- **状态管理**: stopped, running, paused 状态机
- **统计信息**: 跟踪 orders_submitted, orders_filled, orders_rejected 等
