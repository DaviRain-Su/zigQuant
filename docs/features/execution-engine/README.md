# ExecutionEngine - 执行引擎

**版本**: v0.5.0
**状态**: 计划中
**层级**: Execution Layer
**依赖**: MessageBus, Cache

---

## 功能概述

ExecutionEngine 是 zigQuant 的订单执行引擎，负责订单提交、取消和状态追踪，采用订单前置追踪模式确保零订单丢失。

### 设计目标

参考 **Hummingbot** 的订单追踪设计：

- **零丢单**: 订单前置追踪，防止 API 失败导致订单丢失
- **可靠性**: Reliability > Simplicity
- **状态恢复**: 系统重启后自动恢复订单状态
- **事件驱动**: 与 MessageBus 集成

---

## 订单前置追踪

### 传统模式 vs 前置追踪

```
传统模式 (有丢单风险):
1. submitOrder() → API 调用
2. API 超时/失败 → 订单状态未知
3. 可能重复下单或遗漏订单

前置追踪模式 (零丢单):
1. trackOrder() → 立即保存到 pending_orders
2. submitOrder() → API 调用
3. API 超时:
   - WebSocket 监听订单更新
   - 收到确认 → 从 pending 移到 tracked
   - 超时未确认 → 查询订单状态
4. 零订单丢失
```

### 订单生命周期

```
┌──────────────┐
│   PENDING    │  ← 订单前置追踪 (提交前)
└──────┬───────┘
       │ Submit to Exchange
       ▼
┌──────────────┐       ┌──────────────┐
│  SUBMITTED   │──────→│   REJECTED   │
└──────┬───────┘       └──────────────┘
       │ Exchange Confirms
       ▼
┌──────────────┐       ┌──────────────┐
│   ACCEPTED   │──────→│  CANCELLED   │
└──────┬───────┘       └──────────────┘
       │ Fill Events
       ▼
┌──────────────┐       ┌──────────────┐
│PARTIALLY_FILL│──────→│    FILLED    │
└──────────────┘       └──────────────┘
```

---

## 核心 API

### ExecutionEngine

```zig
pub const ExecutionEngine = struct {
    /// 初始化
    pub fn init(
        allocator: Allocator,
        message_bus: *MessageBus,
        cache: *Cache,
        exchange: *IExchange,
        config: ExecutionConfig,
    ) !ExecutionEngine;

    // ========== 订单操作 ==========

    /// 前置追踪订单
    pub fn trackOrder(self: *ExecutionEngine, order: Order) !void;

    /// 提交订单
    pub fn submitOrder(self: *ExecutionEngine, order: Order) !void;

    /// 取消订单
    pub fn cancelOrder(self: *ExecutionEngine, order_id: []const u8) !void;

    // ========== 状态查询 ==========

    /// 获取待处理订单
    pub fn getPendingOrders(self: *ExecutionEngine) []*Order;

    /// 获取已追踪订单
    pub fn getTrackedOrders(self: *ExecutionEngine) []*Order;

    // ========== 恢复 ==========

    /// 恢复订单状态 (系统重启)
    pub fn recoverOrders(self: *ExecutionEngine) !void;

    /// 清理
    pub fn deinit(self: *ExecutionEngine) void;
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
```

### 订单事件处理

```zig
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
    // ... 初始化 ...

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

## MessageBus 集成

ExecutionEngine 注册命令处理器并订阅交易所事件：

```zig
// 注册命令处理器
try message_bus.register("order.submit", handleSubmitOrder);
try message_bus.register("order.cancel", handleCancelOrder);

// 订阅交易所事件
try message_bus.subscribe("exchange.order.*", onExchangeOrderUpdate);
```

---

## 性能指标

| 指标 | 目标 |
|------|------|
| 订单提交延迟 | < 10ms |
| 订单取消延迟 | < 5ms |
| 状态恢复时间 | < 1s |

---

## 文件结构

```
src/execution/
├── engine.zig               # ExecutionEngine 实现
├── order_tracker.zig        # 订单追踪器
├── recovery.zig             # 订单恢复
└── types.zig                # 执行相关类型
```

---

## 相关文档

- [Story 026: ExecutionEngine](../../stories/v0.5.0/STORY_026_EXECUTION_ENGINE.md)
- [v0.5.0 Overview](../../stories/v0.5.0/OVERVIEW.md)
- [MessageBus](../message-bus/README.md)
- [Cache](../cache/README.md)
- [架构模式: 订单前置追踪](../../architecture/ARCHITECTURE_PATTERNS.md#订单前置追踪)

---

**版本**: v0.5.0
**状态**: 计划中
**创建时间**: 2025-12-27
