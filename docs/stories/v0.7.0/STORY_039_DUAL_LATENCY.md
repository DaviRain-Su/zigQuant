# Story 039: Dual Latency Simulation 双向延迟模拟

**版本**: v0.7.0
**状态**: 待开发
**优先级**: P1
**预计时间**: 2-3 天
**依赖**: Story 033 (Clock-Driven)
**来源**: HFTBacktest

---

## 概述

实现双向延迟模拟：Feed Latency (市场数据延迟) 和 Order Latency (订单执行延迟)。真实交易中这两种延迟是不同的，必须分开建模才能获得准确的回测结果。

---

## 背景

### 为什么需要双向延迟？

```
┌─────────────────────────────────────────────────────────────────┐
│                     零延迟 vs 真实延迟                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  零延迟回测 (不现实):                                           │
│  ────────────────────────────────────────                       │
│  t=0: 市场价格变化 → 策略立即看到                               │
│  t=0: 策略下单 → 订单立即到达交易所                             │
│  t=0: 交易所确认 → 策略立即收到                                 │
│                                                                  │
│  结果: 策略表现虚高, 尤其是 HFT/做市策略                        │
│                                                                  │
│  双向延迟回测 (真实):                                           │
│  ────────────────────────────────────────                       │
│  t=0ms:  市场价格变化 (交易所)                                  │
│  t=10ms: 策略接收数据 (Feed Latency)                            │
│  t=11ms: 策略计算并下单                                         │
│  t=21ms: 订单到达交易所 (Entry Latency)                         │
│  t=21.1ms: 交易所处理订单                                       │
│  t=25ms: 策略收到确认 (Response Latency)                        │
│                                                                  │
│  总往返延迟: 25ms                                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 延迟类型

```
┌─────────────────────────────────────────────────────────────────┐
│                     延迟类型分解                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Feed Latency (数据延迟)                                     │
│     交易所 ─────(网络)─────→ 策略                               │
│     • 市场数据 (报价、成交)                                     │
│     • 订单簿更新                                                │
│     • 典型值: 5-50ms                                            │
│                                                                  │
│  2. Order Latency (订单延迟)                                    │
│     2a. Entry Latency (提交延迟)                                │
│         策略 ─────(网络)─────→ 交易所                           │
│         • 订单提交                                              │
│         • 典型值: 5-30ms                                        │
│                                                                  │
│     2b. Response Latency (响应延迟)                             │
│         交易所 ─────(网络)─────→ 策略                           │
│         • 确认消息                                              │
│         • 典型值: 5-30ms                                        │
│                                                                  │
│  关键点: Feed Latency ≠ Order Latency                           │
│         必须分开建模!                                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 技术设计

### 核心组件

```
┌─────────────────────────────────────────────────────────────────┐
│                   Dual Latency 架构                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  LatencyModel (基类)                      │  │
│  │  • model_type: Constant / Normal / Interpolated          │  │
│  │  • simulate(event_time) → delayed_time                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  FeedLatencyModel          OrderLatencyModel              │  │
│  │  (市场数据延迟)            (订单延迟)                     │  │
│  │                                                            │  │
│  │                            ├── entry_latency              │  │
│  │                            └── response_latency           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  LatencySimulator                         │  │
│  │  • feed_latency: FeedLatencyModel                        │  │
│  │  • order_latency: OrderLatencyModel                      │  │
│  │                                                            │  │
│  │  • simulateFeedEvent(event) → delayed_event              │  │
│  │  • simulateOrderFlow(order) → OrderTimeline              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 延迟模型实现

```zig
const std = @import("std");

/// 延迟模型类型
pub const LatencyModelType = enum {
    /// 固定延迟
    Constant,
    /// 正态分布
    Normal,
    /// 从历史数据插值
    Interpolated,
};

/// 基础延迟模型
pub const LatencyModel = struct {
    model_type: LatencyModelType,

    // Constant 参数
    constant_latency_ns: i64,

    // Normal 参数
    mean_ns: i64,
    std_ns: i64,

    // Interpolated 参数
    historical_data: ?[]const LatencyDataPoint,

    random: std.rand.Random,

    const Self = @This();

    /// 创建常数延迟模型
    pub fn constant(latency_ns: i64) Self {
        return .{
            .model_type = .Constant,
            .constant_latency_ns = latency_ns,
            .mean_ns = 0,
            .std_ns = 0,
            .historical_data = null,
            .random = std.rand.DefaultPrng.init(0).random(),
        };
    }

    /// 创建正态分布延迟模型
    pub fn normal(mean_ns: i64, std_ns: i64) Self {
        return .{
            .model_type = .Normal,
            .constant_latency_ns = 0,
            .mean_ns = mean_ns,
            .std_ns = std_ns,
            .historical_data = null,
            .random = std.rand.DefaultPrng.init(@intCast(std.time.nanoTimestamp())).random(),
        };
    }

    /// 模拟延迟
    pub fn simulate(self: *Self, event_time: i64) i64 {
        const latency = switch (self.model_type) {
            .Constant => self.constant_latency_ns,
            .Normal => blk: {
                // Box-Muller 变换生成正态分布
                const u1 = self.random.float(f64);
                const u2 = self.random.float(f64);
                const z = @sqrt(-2.0 * @log(u1)) * @cos(2.0 * std.math.pi * u2);
                const sample = @as(f64, @floatFromInt(self.mean_ns)) +
                              z * @as(f64, @floatFromInt(self.std_ns));
                break :blk @max(0, @as(i64, @intFromFloat(sample)));
            },
            .Interpolated => blk: {
                if (self.historical_data) |data| {
                    break :blk interpolateLatency(data, event_time);
                }
                break :blk self.mean_ns;  // fallback
            },
        };

        return event_time + latency;
    }
};

/// 延迟数据点 (用于插值)
pub const LatencyDataPoint = struct {
    timestamp: i64,
    latency_ns: i64,
};

/// 从历史数据插值延迟
fn interpolateLatency(data: []const LatencyDataPoint, event_time: i64) i64 {
    // 找到最接近的两个数据点进行线性插值
    var prev: ?LatencyDataPoint = null;
    var next: ?LatencyDataPoint = null;

    for (data) |point| {
        if (point.timestamp <= event_time) {
            prev = point;
        } else {
            next = point;
            break;
        }
    }

    if (prev == null) return data[0].latency_ns;
    if (next == null) return prev.?.latency_ns;

    // 线性插值
    const t = @as(f64, @floatFromInt(event_time - prev.?.timestamp)) /
              @as(f64, @floatFromInt(next.?.timestamp - prev.?.timestamp));
    const latency = @as(f64, @floatFromInt(prev.?.latency_ns)) * (1.0 - t) +
                   @as(f64, @floatFromInt(next.?.latency_ns)) * t;

    return @intFromFloat(latency);
}
```

### 订单延迟模型

```zig
/// 订单时间线
pub const OrderTimeline = struct {
    strategy_submit: i64,    // 策略提交时间
    exchange_arrive: i64,    // 到达交易所时间
    exchange_process: i64,   // 交易所处理完成时间
    strategy_ack: i64,       // 策略收到确认时间
    total_roundtrip: i64,    // 总往返延迟

    pub fn format(self: OrderTimeline) void {
        std.log.info("Order Timeline:", .{});
        std.log.info("  Submit:    {d}ns", .{self.strategy_submit});
        std.log.info("  Arrive:    {d}ns (+{d}ms)", .{
            self.exchange_arrive,
            @divFloor(self.exchange_arrive - self.strategy_submit, 1_000_000),
        });
        std.log.info("  Process:   {d}ns", .{self.exchange_process});
        std.log.info("  Ack:       {d}ns (+{d}ms)", .{
            self.strategy_ack,
            @divFloor(self.strategy_ack - self.exchange_process, 1_000_000),
        });
        std.log.info("  Roundtrip: {d}ms", .{@divFloor(self.total_roundtrip, 1_000_000)});
    }
};

/// 订单延迟模型
pub const OrderLatencyModel = struct {
    entry_latency: LatencyModel,     // 提交延迟
    response_latency: LatencyModel,  // 响应延迟
    exchange_process_ns: i64,        // 交易所处理时间 (通常很小)

    const Self = @This();

    /// 创建默认模型 (10ms 往返)
    pub fn default() Self {
        return .{
            .entry_latency = LatencyModel.constant(5_000_000),     // 5ms
            .response_latency = LatencyModel.constant(5_000_000),  // 5ms
            .exchange_process_ns = 100_000,                        // 100μs
        };
    }

    /// 创建正态分布模型
    pub fn normalDistribution(entry_mean_ms: i64, entry_std_ms: i64, response_mean_ms: i64, response_std_ms: i64) Self {
        return .{
            .entry_latency = LatencyModel.normal(entry_mean_ms * 1_000_000, entry_std_ms * 1_000_000),
            .response_latency = LatencyModel.normal(response_mean_ms * 1_000_000, response_std_ms * 1_000_000),
            .exchange_process_ns = 100_000,
        };
    }

    /// 模拟完整订单流程
    pub fn simulateOrderFlow(self: *Self, submit_time: i64) OrderTimeline {
        const arrive_time = self.entry_latency.simulate(submit_time);
        const process_time = arrive_time + self.exchange_process_ns;
        const ack_time = self.response_latency.simulate(process_time);

        return .{
            .strategy_submit = submit_time,
            .exchange_arrive = arrive_time,
            .exchange_process = process_time,
            .strategy_ack = ack_time,
            .total_roundtrip = ack_time - submit_time,
        };
    }
};
```

### 延迟模拟器

```zig
/// 完整延迟模拟器
pub const LatencySimulator = struct {
    feed_latency: LatencyModel,
    order_latency: OrderLatencyModel,

    const Self = @This();

    /// 创建默认模拟器
    pub fn default() Self {
        return .{
            .feed_latency = LatencyModel.constant(10_000_000),  // 10ms feed latency
            .order_latency = OrderLatencyModel.default(),
        };
    }

    /// 模拟市场数据事件延迟
    pub fn simulateFeedEvent(self: *Self, event: *MarketEvent) void {
        event.local_timestamp = self.feed_latency.simulate(event.exchange_timestamp);
    }

    /// 模拟订单提交
    pub fn simulateOrderSubmit(self: *Self, order: *Order, submit_time: i64) OrderTimeline {
        const timeline = self.order_latency.simulateOrderFlow(submit_time);
        order.submit_time = timeline.strategy_submit;
        order.exchange_time = timeline.exchange_arrive;
        order.ack_time = timeline.strategy_ack;
        return timeline;
    }
};
```

### 回测引擎集成

```zig
/// 带延迟的回测引擎
pub const LatencyAwareBacktester = struct {
    latency_sim: LatencySimulator,
    event_queue: EventQueue,
    current_time: i64,

    const Self = @This();

    /// 处理市场数据 (带延迟)
    pub fn onMarketData(self: *Self, event: MarketEvent) !void {
        // 应用 Feed Latency
        var delayed_event = event;
        self.latency_sim.simulateFeedEvent(&delayed_event);

        // 调度到延迟后的时间
        try self.event_queue.schedule(delayed_event.local_timestamp, delayed_event);
    }

    /// 提交订单 (带延迟)
    pub fn submitOrder(self: *Self, order: *Order) !void {
        // 应用 Order Latency
        const timeline = self.latency_sim.simulateOrderSubmit(order, self.current_time);

        // 调度到达交易所事件
        try self.event_queue.schedule(timeline.exchange_arrive, .{
            .type = .OrderArrive,
            .order = order,
        });

        // 调度确认事件
        try self.event_queue.schedule(timeline.strategy_ack, .{
            .type = .OrderAck,
            .order = order,
        });
    }
};
```

---

## 实现任务

### Task 1: LatencyModel (Day 1)

- [ ] 创建 `src/backtest/latency_model.zig`
- [ ] 实现 Constant 模型
- [ ] 实现 Normal 模型
- [ ] 实现 Interpolated 模型

### Task 2: OrderLatencyModel (Day 1)

- [ ] 实现 OrderTimeline
- [ ] 实现 OrderLatencyModel
- [ ] 实现 simulateOrderFlow

### Task 3: LatencySimulator (Day 2)

- [ ] 实现完整的 LatencySimulator
- [ ] 与 EventQueue 集成
- [ ] 与回测引擎集成

### Task 4: 测试和校准 (Day 2-3)

- [ ] 单元测试
- [ ] 延迟分布验证
- [ ] 从实盘日志拟合模型
- [ ] 文档编写

---

## 测试计划

### 单元测试

```zig
test "LatencyModel constant" {
    var model = LatencyModel.constant(10_000_000);  // 10ms
    const delayed = model.simulate(1000);
    try testing.expect(delayed == 1000 + 10_000_000);
}

test "LatencyModel normal distribution" {
    var model = LatencyModel.normal(10_000_000, 2_000_000);  // 10ms ± 2ms

    var total: i64 = 0;
    const samples = 1000;
    for (0..samples) |_| {
        const latency = model.simulate(0);
        total += latency;
    }

    const avg = @divFloor(total, samples);
    // 平均值应该接近 10ms
    try testing.expect(avg > 8_000_000 and avg < 12_000_000);
}

test "OrderLatencyModel roundtrip" {
    var model = OrderLatencyModel.default();
    const timeline = model.simulateOrderFlow(0);

    // 往返延迟应该在合理范围内
    try testing.expect(timeline.total_roundtrip > 0);
    try testing.expect(timeline.exchange_arrive > timeline.strategy_submit);
    try testing.expect(timeline.strategy_ack > timeline.exchange_process);
}
```

---

## 验收标准

### 功能验收

- [ ] 3 种延迟模型正确实现
- [ ] Feed/Order 延迟分开模拟
- [ ] 与回测引擎集成

### 性能验收

- [ ] 延迟计算 < 100ns
- [ ] 不影响回测速度

### 精度验收

- [ ] 延迟分布符合实盘特征
- [ ] 支持从实盘日志拟合

---

## 配置示例

```zig
// 快速测试 (固定延迟)
const sim = LatencySimulator{
    .feed_latency = LatencyModel.constant(10_000_000),  // 10ms
    .order_latency = OrderLatencyModel.default(),
};

// 真实模拟 (正态分布)
const sim = LatencySimulator{
    .feed_latency = LatencyModel.normal(10_000_000, 3_000_000),  // 10ms ± 3ms
    .order_latency = OrderLatencyModel.normalDistribution(
        8, 2,   // entry: 8ms ± 2ms
        7, 2,   // response: 7ms ± 2ms
    ),
};
```

---

## 参考资料

- [HFTBacktest - Latency Model](https://github.com/nkaz001/hftbacktest)
- [架构模式文档](../../architecture/ARCHITECTURE_PATTERNS.md#dual-latency-双向延迟模拟)

---

**Story**: 039
**版本**: v0.7.0
**创建时间**: 2025-12-27
