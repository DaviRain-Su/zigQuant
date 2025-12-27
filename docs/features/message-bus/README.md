# MessageBus - 消息总线

**版本**: v0.5.0
**状态**: 计划中
**层级**: Core Layer
**依赖**: 无

---

## 功能概述

MessageBus 是 zigQuant 事件驱动架构的核心基础设施，提供高效的组件间通信机制。

### 设计目标

参考 **NautilusTrader** 的 MessageBus 设计：

- **解耦**: 组件间无直接依赖
- **高性能**: 单线程执行，无锁
- **灵活性**: 支持多种消息模式
- **可扩展**: 新组件只需订阅/发布

---

## 消息模式

### 1. Publish-Subscribe (发布-订阅)

一对多的消息广播模式。

```zig
// 发布者
message_bus.publish("market_data.BTC-USDT", event);

// 订阅者 (可以有多个)
message_bus.subscribe("market_data.BTC-USDT", onMarketData);
message_bus.subscribe("market_data.*", onAllMarketData);  // 通配符
```

**使用场景**:
- DataEngine → 发布市场数据事件
- Strategy → 订阅市场数据

### 2. Request-Response (请求-响应)

一对一的同步请求模式。

```zig
// 注册处理器
message_bus.register("order.validate", validateOrder);

// 发送请求
const response = try message_bus.request("order.validate", order);
```

**使用场景**:
- RiskEngine → 验证订单请求
- Cache → 查询数据

### 3. Command (命令)

一对一的异步命令模式 (Fire-and-Forget)。

```zig
// 发送命令
message_bus.send(.{ .submit_order = order });
```

**使用场景**:
- Strategy → 发送订单命令
- ExecutionEngine → 处理订单

---

## 核心 API

### MessageBus

```zig
pub const MessageBus = struct {
    /// 初始化
    pub fn init(allocator: Allocator) MessageBus;

    /// 发布事件
    pub fn publish(self: *MessageBus, topic: []const u8, event: Event) !void;

    /// 订阅主题
    pub fn subscribe(self: *MessageBus, topic: []const u8, handler: Handler) !void;

    /// 取消订阅
    pub fn unsubscribe(self: *MessageBus, topic: []const u8, handler: Handler) void;

    /// 发送请求
    pub fn request(self: *MessageBus, endpoint: []const u8, req: Request) !Response;

    /// 注册端点
    pub fn register(self: *MessageBus, endpoint: []const u8, handler: RequestHandler) !void;

    /// 发送命令
    pub fn send(self: *MessageBus, command: Command) void;

    /// 清理
    pub fn deinit(self: *MessageBus) void;
};
```

---

## 主题命名规范

```
市场数据:
  market_data.{instrument_id}           # 特定品种
  market_data.*                         # 所有市场数据

订单簿:
  orderbook.{instrument_id}.snapshot    # 快照
  orderbook.{instrument_id}.delta       # 增量

订单:
  order.submitted                       # 订单提交
  order.accepted                        # 订单接受
  order.filled                          # 订单成交

仓位:
  position.{instrument_id}              # 仓位更新

系统:
  system.tick                           # 定时 Tick
  system.shutdown                       # 关闭信号
```

---

## 使用示例

### 基本使用

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建 MessageBus
    var bus = try zigQuant.MessageBus.init(allocator);
    defer bus.deinit();

    // 订阅事件
    try bus.subscribe("market_data.*", onMarketData);

    // 发布事件
    try bus.publish("market_data.BTC-USDT", .{
        .market_data = .{
            .instrument_id = "BTC-USDT",
            .bid = 50000.0,
            .ask = 50001.0,
        },
    });
}

fn onMarketData(event: Event) void {
    const data = event.market_data;
    std.debug.print("收到: {s} bid={d}\n", .{ data.instrument_id, data.bid });
}
```

---

## 性能指标

| 指标 | 目标 |
|------|------|
| 发布延迟 | < 1μs |
| 吞吐量 | > 100,000 msg/s |
| 内存分配 | 仅初始化时 |

---

## 文件结构

```
src/core/
├── message_bus.zig          # MessageBus 实现
└── events/
    ├── types.zig            # 事件类型定义
    ├── market_events.zig    # 市场数据事件
    ├── order_events.zig     # 订单事件
    └── position_events.zig  # 仓位事件
```

---

## 相关文档

- [Story 023: MessageBus](../../stories/v0.5.0/STORY_023_MESSAGE_BUS.md)
- [v0.5.0 Overview](../../stories/v0.5.0/OVERVIEW.md)
- [架构模式参考](../../architecture/ARCHITECTURE_PATTERNS.md)

---

**版本**: v0.5.0
**状态**: 计划中
**创建时间**: 2025-12-27
