# 订单管理器 - 功能概览

> 统一管理订单生命周期，包括订单提交、取消、状态追踪和事件处理

**状态**: 🚧 开发中
**版本**: v0.2.0
**Story**: [010-order-manager](../../../stories/v0.2-mvp/010-order-manager.md)
**最后更新**: 2025-12-23

---

## 📋 概述

订单管理器（Order Manager）是 zigQuant 交易系统的核心组件，负责管理所有订单的生命周期。它提供了统一的接口来提交订单、取消订单、查询订单状态，并通过 WebSocket 实时同步订单更新。

### 为什么需要订单管理器？

在量化交易系统中，订单管理是最关键的环节：
- **订单状态一致性**: 确保本地订单状态与交易所保持同步
- **并发安全**: 支持多线程安全地访问和操作订单
- **错误处理**: 提供完善的错误处理和重试机制
- **审计追踪**: 记录所有订单操作，便于审计和回溯
- **事件驱动**: 通过回调机制响应订单状态变化

### 核心特性

- ✅ **订单提交**: 支持限价单和市价单，支持客户端订单 ID
- ✅ **订单取消**: 支持单个取消、批量取消、按 CLOID 取消
- ✅ **状态同步**: 通过 WebSocket 实时同步订单状态和成交信息
- ✅ **订单存储**: 多索引订单存储，支持按客户端 ID 和交易所 ID 查询
- ✅ **并发安全**: 使用 Mutex 保护订单状态，确保线程安全
- ✅ **事件回调**: 支持订单更新和成交事件的回调处理

---

## 🚀 快速开始

### 基本使用

```zig
const std = @import("std");
const OrderManager = @import("trading/order_manager.zig").OrderManager;
const Order = @import("core/order.zig").Order;
const Decimal = @import("core/decimal.zig").Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化 HTTP 和 WebSocket 客户端
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

    // 创建并提交订单
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
    std.debug.print("Order submitted: {s}\n", .{order.client_order_id});

    // 查询活跃订单
    const active_orders = try manager.getActiveOrders();
    defer allocator.free(active_orders);
    std.debug.print("Active orders: {}\n", .{active_orders.len});

    // 取消订单
    try manager.cancelOrder(&order);
}

fn onOrderUpdate(order: *Order) void {
    std.debug.print("Order updated: {s} -> {s}\n", .{
        order.client_order_id,
        order.status.toString(),
    });
}

fn onOrderFill(order: *Order) void {
    std.debug.print("Order filled: {} @ {}\n", .{
        order.filled_quantity.toFloat(),
        order.avg_fill_price.?.toFloat(),
    });
}
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 核心 API

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

    // 初始化和清理
    pub fn init(
        allocator: std.mem.Allocator,
        http_client: *HyperliquidClient,
        ws_client: *HyperliquidWS,
        logger: Logger,
    ) !OrderManager;
    pub fn deinit(self: *OrderManager) void;

    // 订单操作
    pub fn submitOrder(self: *OrderManager, order: *Order) !void;
    pub fn cancelOrder(self: *OrderManager, order: *Order) !void;
    pub fn cancelOrderByCloid(self: *OrderManager, coin: []const u8, cloid: []const u8) !void;
    pub fn cancelOrders(self: *OrderManager, orders: []const *Order) !void;

    // 查询操作
    pub fn queryOrderStatus(self: *OrderManager, order: *Order) !void;
    pub fn getActiveOrders(self: *OrderManager) ![]const *Order;
    pub fn getOrderHistory(self: *OrderManager, symbol: ?[]const u8, limit: ?usize) ![]const *Order;

    // 事件处理
    pub fn handleUserEvent(self: *OrderManager, event: WsUserEvent) !void;
    pub fn handleUserFill(self: *OrderManager, fill: WsUserFills.UserFill) !void;
    pub fn handleOrderUpdate(self: *OrderManager, ws_order: WsOrder) !void;
};
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 始终使用 defer 清理资源
var manager = try OrderManager.init(allocator, &http_client, &ws_client, logger);
defer manager.deinit();

// 2. 设置回调处理订单事件
manager.on_order_update = handleOrderUpdate;
manager.on_order_fill = handleOrderFill;

// 3. 使用客户端订单 ID 追踪订单
order.client_order_id = "my-order-123";
try manager.submitOrder(&order);

// 4. 检查订单状态再执行操作
if (order.isCancellable()) {
    try manager.cancelOrder(&order);
}

// 5. 批量取消订单以提高效率
try manager.cancelOrders(orders_to_cancel);
```

### ❌ DON'T

```zig
// 1. 不要在多线程中不加锁地直接访问订单
// 错误：直接修改订单状态
order.status = .cancelled; // 应通过 OrderManager 操作

// 2. 不要忘记处理错误
manager.submitOrder(&order); // 缺少 try

// 3. 不要取消已经成交或取消的订单
try manager.cancelOrder(&order); // 应先检查 isCancellable()

// 4. 不要忽略 WebSocket 事件
// 应及时处理 handleUserEvent 和 handleOrderUpdate

// 5. 不要泄漏内存
const orders = try manager.getActiveOrders();
// 缺少: defer allocator.free(orders);
```

---

## 🎯 使用场景

### ✅ 适用

- 量化交易策略中的订单管理
- 需要实时订单状态同步的交易系统
- 多线程并发交易场景
- 需要审计和历史记录的交易应用
- 需要完善错误处理的生产环境

### ❌ 不适用

- 简单的单次交易脚本（可直接使用 HTTP 客户端）
- 不需要状态管理的场景
- 只读的订单查询场景
- 非 Hyperliquid 交易所（需要其他实现）

---

## 📊 性能指标

- **订单提交延迟**: < 50ms（网络正常情况）
- **状态同步延迟**: < 100ms（WebSocket 实时）
- **并发支持**: 支持多线程并发访问
- **内存占用**: 每个订单约 1KB
- **订单查询**: O(1) 时间复杂度（基于哈希表）

---

## 💡 未来改进

- [ ] 实现订单修改（amend order）功能
- [ ] 支持条件订单（止损、止盈）
- [ ] 实现订单持久化到数据库
- [ ] 添加订单审计日志系统
- [ ] 实现订单性能统计和分析
- [ ] 支持订单路由到多个交易所
- [ ] 添加订单风险控制预检查

---

*Last updated: 2025-12-23*
