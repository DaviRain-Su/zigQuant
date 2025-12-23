# Story: 订单管理器

**ID**: `STORY-010`
**版本**: `v0.2`
**创建日期**: 2025-12-23
**状态**: 📋 计划中
**优先级**: P0 (必须)
**预计工时**: 4 天

---

## 📋 需求描述

### 用户故事
作为**量化交易开发者**，我希望**有一个订单管理器来统一管理所有订单**，以便**下单、撤单、查询订单状态并追踪订单生命周期**。

### 背景
订单管理器是交易系统的核心组件，负责：
- 订单提交和验证
- 订单状态同步
- 订单取消和修改
- 订单历史记录
- 与交易所 API 交互

需要实现一个可靠的订单管理器，确保：
- 订单状态一致性
- 错误处理和重试
- 并发安全
- 审计和日志

### 范围
- **包含**:
  - 订单生命周期管理
  - 下单接口（限价单、市价单）
  - 撤单接口（单个、批量）
  - 订单状态查询
  - 订单历史记录
  - WebSocket 事件处理
  - 错误处理和重试

- **不包含**:
  - 策略逻辑（见后续 Stories）
  - 风险控制（见后续 Stories）
  - 订单路由（多交易所）

---

## 🎯 验收标准

- [ ] 订单管理器实现完成
- [ ] 支持下单（限价单、市价单）
- [ ] 支持撤单（单个、批量）
- [ ] 订单状态自动同步（WebSocket）
- [ ] 订单历史记录可查询
- [ ] 错误处理完善，失败订单可重试
- [ ] 并发安全（多线程访问）
- [ ] 所有测试用例通过
- [ ] 集成测试通过（连接测试网）

---

## 🔧 技术设计

### 架构概览

```
src/trading/
├── order_manager.zig     # 订单管理器核心
├── order_store.zig       # 订单存储
└── order_manager_test.zig # 测试
```

### 核心数据结构

#### 1. 订单管理器

```zig
// src/trading/order_manager.zig

const std = @import("std");
const Order = @import("../core/order.zig").Order;
const OrderTypes = @import("../core/order_types.zig");
const HyperliquidClient = @import("../exchange/hyperliquid/http.zig").HyperliquidClient;
const HyperliquidWS = @import("../exchange/hyperliquid/websocket.zig").HyperliquidWS;
const ExchangeAPI = @import("../exchange/hyperliquid/exchange_api.zig");
const Logger = @import("../core/logger.zig").Logger;
const Error = @import("../core/error.zig").Error;

pub const OrderManager = struct {
    allocator: std.mem.Allocator,
    http_client: *HyperliquidClient,
    ws_client: *HyperliquidWS,
    order_store: OrderStore,
    logger: Logger,
    mutex: std.Thread.Mutex,

    // 回调
    on_order_update: ?*const fn (order: *Order) void,
    on_order_fill: ?*const fn (order: *Order) void,

    pub fn init(
        allocator: std.mem.Allocator,
        http_client: *HyperliquidClient,
        ws_client: *HyperliquidWS,
        logger: Logger,
    ) !OrderManager {
        return .{
            .allocator = allocator,
            .http_client = http_client,
            .ws_client = ws_client,
            .order_store = OrderStore.init(allocator),
            .logger = logger,
            .mutex = std.Thread.Mutex{},
            .on_order_update = null,
            .on_order_fill = null,
        };
    }

    pub fn deinit(self: *OrderManager) void {
        self.order_store.deinit();
    }

    /// 提交订单
    pub fn submitOrder(self: *OrderManager, order: *Order) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 验证订单
        try order.validate();

        // 记录订单
        try self.order_store.add(order);

        self.logger.info("Submitting order: {s} {s} {} @ {?}", .{
            order.side.toString(),
            order.symbol,
            order.quantity.toFloat(),
            if (order.price) |p| p.toFloat() else null,
        });

        // 构造请求
        const request = ExchangeAPI.OrderRequest{
            .coin = order.symbol,
            .is_buy = (order.side == .buy),
            .sz = order.quantity,
            .limit_px = order.price orelse Decimal.ZERO,
            .order_type = .{
                .limit = if (order.order_type == .limit) .{
                    .tif = order.time_in_force.toString(),
                } else null,
            },
            .reduce_only = order.reduce_only,
        };

        // 提交到交易所
        const response = try ExchangeAPI.placeOrder(self.http_client, request);

        // 处理响应
        if (std.mem.eql(u8, response.status, "ok")) {
            if (response.response.data.data.statuses.len > 0) {
                const status = response.response.data.data.statuses[0];

                if (status.resting) |resting| {
                    order.exchange_order_id = resting.oid;
                    order.updateStatus(.open);
                    self.logger.info("Order placed successfully: OID={}", .{resting.oid});
                } else if (status.filled) |filled| {
                    order.exchange_order_id = filled.oid;
                    order.updateFill(filled.total_sz, filled.avg_px, Decimal.ZERO);
                    self.logger.info("Order filled immediately: OID={}", .{filled.oid});
                } else if (status.error) |err_msg| {
                    order.updateStatus(.rejected);
                    order.error_message = try self.allocator.dupe(u8, err_msg);
                    self.logger.err("Order rejected: {s}", .{err_msg});
                    return Error.OrderRejected;
                }
            }

            order.submitted_at = Timestamp.now();
            try self.order_store.update(order);

            if (self.on_order_update) |callback| {
                callback(order);
            }
        } else {
            order.updateStatus(.rejected);
            const err_msg = response.response.error;
            order.error_message = try self.allocator.dupe(u8, err_msg);
            self.logger.err("Order submission failed: {s}", .{err_msg});
            return Error.OrderRejected;
        }
    }

    /// 取消订单
    pub fn cancelOrder(self: *OrderManager, order: *Order) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!order.isCancellable()) {
            return Error.OrderNotCancellable;
        }

        self.logger.info("Cancelling order: OID={?}", .{order.exchange_order_id});

        const request = ExchangeAPI.CancelRequest{
            .coin = order.symbol,
            .oid = order.exchange_order_id.?,
        };

        const response = try ExchangeAPI.cancelOrder(self.http_client, request);

        if (std.mem.eql(u8, response.status, "ok")) {
            order.updateStatus(.cancelled);
            try self.order_store.update(order);

            self.logger.info("Order cancelled successfully: OID={?}", .{order.exchange_order_id});

            if (self.on_order_update) |callback| {
                callback(order);
            }
        } else {
            self.logger.err("Failed to cancel order: OID={?}", .{order.exchange_order_id});
            return Error.CancelOrderFailed;
        }
    }

    /// 批量取消订单
    pub fn cancelOrders(self: *OrderManager, orders: []const *Order) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var cancel_requests = std.ArrayList(ExchangeAPI.CancelRequest).init(self.allocator);
        defer cancel_requests.deinit();

        for (orders) |order| {
            if (order.isCancellable()) {
                try cancel_requests.append(.{
                    .coin = order.symbol,
                    .oid = order.exchange_order_id.?,
                });
            }
        }

        if (cancel_requests.items.len == 0) {
            return;
        }

        self.logger.info("Cancelling {} orders", .{cancel_requests.items.len});

        const responses = try ExchangeAPI.cancelOrders(
            self.http_client,
            cancel_requests.items,
        );
        defer self.allocator.free(responses);

        for (responses, 0..) |response, i| {
            if (std.mem.eql(u8, response.status, "ok")) {
                orders[i].updateStatus(.cancelled);
                try self.order_store.update(orders[i]);
            }
        }
    }

    /// 查询订单状态
    pub fn queryOrderStatus(self: *OrderManager, order: *Order) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (order.exchange_order_id == null) {
            return Error.OrderNotSubmitted;
        }

        const status = try ExchangeAPI.getOrderStatus(
            self.http_client,
            order.exchange_order_id.?,
        );

        // 更新订单状态
        // ... (根据 status 更新 order)
    }

    /// 获取所有活跃订单
    pub fn getActiveOrders(self: *OrderManager) ![]const *Order {
        self.mutex.lock();
        defer self.mutex.unlock();

        return try self.order_store.getActive();
    }

    /// 获取订单历史
    pub fn getOrderHistory(
        self: *OrderManager,
        symbol: ?[]const u8,
        limit: ?usize,
    ) ![]const *Order {
        self.mutex.lock();
        defer self.mutex.unlock();

        return try self.order_store.getHistory(symbol, limit);
    }

    /// 处理 WebSocket 订单事件
    pub fn handleUserEvent(self: *OrderManager, event: UserEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const order = self.order_store.getByExchangeId(event.order.?.oid) orelse {
            self.logger.warn("Received event for unknown order: OID={}", .{event.order.?.oid});
            return;
        };

        switch (event.event_type) {
            .order_placed => {
                order.updateStatus(.open);
            },
            .order_cancelled => {
                order.updateStatus(.cancelled);
            },
            .order_filled => {
                order.updateStatus(.filled);
            },
            .order_rejected => {
                order.updateStatus(.rejected);
            },
        }

        try self.order_store.update(order);

        if (self.on_order_update) |callback| {
            callback(order);
        }
    }

    /// 处理 WebSocket 成交事件
    pub fn handleUserFill(self: *OrderManager, fill: UserFill) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const order = self.order_store.getByExchangeId(fill.oid) orelse {
            self.logger.warn("Received fill for unknown order: OID={}", .{fill.oid});
            return;
        };

        order.updateFill(fill.sz, fill.px, fill.fee);
        try self.order_store.update(order);

        self.logger.info("Order fill: OID={} {} @ {}", .{
            fill.oid, fill.sz.toFloat(), fill.px.toFloat(),
        });

        if (self.on_order_fill) |callback| {
            callback(order);
        }
    }
};
```

#### 2. 订单存储

```zig
// src/trading/order_store.zig

const std = @import("std");
const Order = @import("../core/order.zig").Order;

pub const OrderStore = struct {
    allocator: std.mem.Allocator,

    // 按 client_order_id 索引
    orders_by_client_id: std.StringHashMap(*Order),

    // 按 exchange_order_id 索引
    orders_by_exchange_id: std.AutoHashMap(u64, *Order),

    // 活跃订单列表
    active_orders: std.ArrayList(*Order),

    // 历史订单列表
    history_orders: std.ArrayList(*Order),

    pub fn init(allocator: std.mem.Allocator) OrderStore {
        return .{
            .allocator = allocator,
            .orders_by_client_id = std.StringHashMap(*Order).init(allocator),
            .orders_by_exchange_id = std.AutoHashMap(u64, *Order).init(allocator),
            .active_orders = std.ArrayList(*Order).init(allocator),
            .history_orders = std.ArrayList(*Order).init(allocator),
        };
    }

    pub fn deinit(self: *OrderStore) void {
        self.orders_by_client_id.deinit();
        self.orders_by_exchange_id.deinit();
        self.active_orders.deinit();
        self.history_orders.deinit();
    }

    /// 添加订单
    pub fn add(self: *OrderStore, order: *Order) !void {
        try self.orders_by_client_id.put(order.client_order_id, order);
        try self.active_orders.append(order);
    }

    /// 更新订单
    pub fn update(self: *OrderStore, order: *Order) !void {
        // 更新交易所订单 ID 索引
        if (order.exchange_order_id) |oid| {
            try self.orders_by_exchange_id.put(oid, order);
        }

        // 如果订单完成，从活跃列表移到历史列表
        if (order.status.isFinal()) {
            for (self.active_orders.items, 0..) |active_order, i| {
                if (active_order == order) {
                    _ = self.active_orders.swapRemove(i);
                    try self.history_orders.append(order);
                    break;
                }
            }
        }
    }

    /// 按 client_order_id 查询
    pub fn getByClientId(self: *OrderStore, client_order_id: []const u8) ?*Order {
        return self.orders_by_client_id.get(client_order_id);
    }

    /// 按 exchange_order_id 查询
    pub fn getByExchangeId(self: *OrderStore, exchange_order_id: u64) ?*Order {
        return self.orders_by_exchange_id.get(exchange_order_id);
    }

    /// 获取所有活跃订单
    pub fn getActive(self: *OrderStore) ![]const *Order {
        return try self.allocator.dupe(*Order, self.active_orders.items);
    }

    /// 获取历史订单
    pub fn getHistory(
        self: *OrderStore,
        symbol: ?[]const u8,
        limit: ?usize,
    ) ![]const *Order {
        var result = std.ArrayList(*Order).init(self.allocator);
        defer result.deinit();

        for (self.history_orders.items) |order| {
            if (symbol) |s| {
                if (!std.mem.eql(u8, order.symbol, s)) continue;
            }
            try result.append(order);

            if (limit) |l| {
                if (result.items.len >= l) break;
            }
        }

        return try result.toOwnedSlice();
    }
};
```

---

## 📝 任务分解

### Phase 1: 基础结构 📋
- [ ] 任务 1.1: 实现 OrderStore
- [ ] 任务 1.2: 实现 OrderManager 基础类
- [ ] 任务 1.3: 实现订单索引（client ID / exchange ID）
- [ ] 任务 1.4: 实现线程安全机制

### Phase 2: 订单操作 📋
- [ ] 任务 2.1: 实现 submitOrder
- [ ] 任务 2.2: 实现 cancelOrder
- [ ] 任务 2.3: 实现 cancelOrders（批量）
- [ ] 任务 2.4: 实现 queryOrderStatus

### Phase 3: 事件处理 📋
- [ ] 任务 3.1: 实现 WebSocket 事件处理
- [ ] 任务 3.2: 实现订单状态同步
- [ ] 任务 3.3: 实现成交事件处理
- [ ] 任务 3.4: 实现回调机制

### Phase 4: 查询功能 📋
- [ ] 任务 4.1: 实现 getActiveOrders
- [ ] 任务 4.2: 实现 getOrderHistory
- [ ] 任务 4.3: 实现订单过滤和排序

### Phase 5: 测试与文档 📋
- [ ] 任务 5.1: 编写单元测试
- [ ] 任务 5.2: 编写集成测试
- [ ] 任务 5.3: 错误处理测试
- [ ] 任务 5.4: 并发测试
- [ ] 任务 5.5: 更新文档
- [ ] 任务 5.6: 代码审查

---

## 🧪 测试策略

### 单元测试

```zig
test "OrderManager: submit order" {
    // Mock HTTP client
    var manager = try OrderManager.init(
        testing.allocator,
        &mock_http_client,
        &mock_ws_client,
        logger,
    );
    defer manager.deinit();

    var order = try Order.init(
        testing.allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    try manager.submitOrder(&order);

    try testing.expectEqual(.open, order.status);
    try testing.expect(order.exchange_order_id != null);
}

test "OrderManager: cancel order" {
    // ... setup ...

    try manager.cancelOrder(&order);

    try testing.expectEqual(.cancelled, order.status);
}
```

### 集成测试

```zig
test "Integration: full order lifecycle" {
    // 连接测试网
    var http_client = try HyperliquidClient.init(...);
    defer http_client.deinit();

    var ws_client = try HyperliquidWS.init(...);
    defer ws_client.deinit();

    var manager = try OrderManager.init(
        testing.allocator,
        &http_client,
        &ws_client,
        logger,
    );
    defer manager.deinit();

    // 1. 提交订单
    var order = try Order.init(...);
    try manager.submitOrder(&order);

    // 2. 等待订单确认
    std.time.sleep(2 * std.time.ns_per_s);

    // 3. 查询订单状态
    try manager.queryOrderStatus(&order);

    // 4. 取消订单
    try manager.cancelOrder(&order);

    try testing.expect(order.status == .cancelled);
}
```

---

## 📚 相关文档

### 设计文档
- [ ] `docs/features/order-manager/README.md` - 订单管理器概览
- [ ] `docs/features/order-manager/api-reference.md` - API 参考
- [ ] `docs/features/order-manager/error-handling.md` - 错误处理

### 参考资料
- Hyperliquid API Documentation

---

## 🔗 依赖关系

### 前置条件
- [x] Story 001: Decimal 类型
- [x] Story 002: Time Utils
- [x] Story 003: Error System
- [x] Story 004: Logger
- [ ] Story 006: Hyperliquid HTTP 客户端
- [ ] Story 007: Hyperliquid WebSocket 客户端
- [ ] Story 009: 订单类型定义

### 被依赖
- Story 011: 仓位追踪器
- Story 012: CLI 界面
- 未来: 策略引擎、风险管理

---

## ⚠️ 风险与挑战

### 已识别风险
1. **状态同步**: HTTP 和 WebSocket 状态可能不一致
   - **影响**: 高
   - **缓解措施**: 以 WebSocket 为准，HTTP 仅用于提交

2. **并发冲突**: 多线程访问订单
   - **影响**: 中
   - **缓解措施**: 使用 Mutex 保护

### 技术挑战
1. **错误恢复**: 网络故障时订单状态恢复
   - **解决方案**: 重连后查询所有活跃订单

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
- [ ] 集成测试通过
- [ ] 并发测试通过
- [ ] 文档已更新
- [ ] 代码已审查

---

## 📸 演示

### 使用示例

```zig
const std = @import("std");
const OrderManager = @import("trading/order_manager.zig").OrderManager;
const OrderBuilder = @import("core/order.zig").OrderBuilder;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化客户端
    var http_client = try HyperliquidClient.init(...);
    defer http_client.deinit();

    var ws_client = try HyperliquidWS.init(...);
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
    manager.on_order_update = handleOrderUpdate;
    manager.on_order_fill = handleOrderFill;

    // 创建订单
    var builder = try OrderBuilder.init(allocator, "ETH", .buy);
    var order = try builder
        .withPrice(try Decimal.fromString("2000.0"))
        .withQuantity(try Decimal.fromString("0.1"))
        .withTimeInForce(.gtc)
        .build();

    // 提交订单
    try manager.submitOrder(&order);

    std.debug.print("Order submitted: {s}\n", .{order.client_order_id});

    // 查询活跃订单
    const active_orders = try manager.getActiveOrders();
    defer allocator.free(active_orders);

    std.debug.print("Active orders: {}\n", .{active_orders.len});

    // 取消订单
    try manager.cancelOrder(&order);
}

fn handleOrderUpdate(order: *Order) void {
    std.debug.print("Order updated: {s} -> {s}\n", .{
        order.client_order_id,
        order.status.toString(),
    });
}

fn handleOrderFill(order: *Order) void {
    std.debug.print("Order filled: {} @ {}\n", .{
        order.filled_quantity.toFloat(),
        order.avg_fill_price.?.toFloat(),
    });
}
```

---

## 💡 未来改进

- [ ] 实现订单修改（amend order）
- [ ] 支持条件订单
- [ ] 实现订单持久化
- [ ] 添加订单审计日志
- [ ] 实现订单性能统计

---

*Last updated: 2025-12-23*
*Assignee: TBD*
*Status: 📋 Planning*
