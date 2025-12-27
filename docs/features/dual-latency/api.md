# Dual Latency API 参考

> 双向延迟模拟模块的完整 API 文档

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 目录

1. [核心类型](#核心类型)
2. [LatencySimulator](#latencysimulator)
3. [辅助结构](#辅助结构)
4. [使用示例](#使用示例)

---

## 核心类型

### LatencyModelType

延迟模型类型枚举。

```zig
pub const LatencyModelType = enum {
    /// 固定延迟
    Constant,

    /// 正态分布延迟 N(μ, σ)
    Normal,

    /// 从历史数据插值
    Interpolated,
};
```

### LatencyModel

延迟模型配置。

```zig
pub const LatencyModel = struct {
    /// 模型类型
    model_type: LatencyModelType,

    /// 固定延迟值 (Constant 模式)
    value_ns: i64 = 0,

    /// 平均延迟 (Normal 模式)
    mean_ns: i64 = 0,

    /// 标准差 (Normal 模式)
    std_ns: i64 = 0,

    /// 历史数据 (Interpolated 模式)
    data: ?[]const i64 = null,

    /// 最小延迟限制
    min_ns: i64 = 0,

    /// 最大延迟限制
    max_ns: i64 = std.math.maxInt(i64),

    /// 采样延迟值
    pub fn sample(self: LatencyModel, rng: *Random) i64;

    /// 获取平均延迟
    pub fn getMean(self: LatencyModel) i64;

    /// 获取 p99 延迟
    pub fn getP99(self: LatencyModel) i64;
};
```

### OrderLatencyModel

订单延迟模型（包含入场和响应延迟）。

```zig
pub const OrderLatencyModel = struct {
    /// 订单提交延迟 (策略 → 交易所)
    entry: LatencyModel,

    /// 订单响应延迟 (交易所 → 策略)
    response: LatencyModel,

    /// 模拟完整订单时间线
    pub fn simulate(self: OrderLatencyModel, submit_time: i64, rng: *Random) OrderTimeline;

    /// 获取总往返延迟
    pub fn getRoundtrip(self: OrderLatencyModel, rng: *Random) i64;
};
```

### FeedLatencyModel

行情延迟模型。

```zig
pub const FeedLatencyModel = struct {
    /// 延迟模型
    model: LatencyModel,

    /// 是否按交易所分组
    per_exchange: bool = false,

    /// 各交易所延迟配置
    exchange_latencies: ?std.StringHashMap(LatencyModel) = null,

    /// 应用延迟
    pub fn apply(self: FeedLatencyModel, event: MarketEvent, rng: *Random) MarketEvent;
};
```

### OrderTimeline

订单时间线结构。

```zig
pub const OrderTimeline = struct {
    /// 策略提交时间
    strategy_submit: i64,

    /// 订单到达交易所时间
    exchange_arrive: i64,

    /// 交易所处理完成时间
    exchange_process: i64,

    /// 策略收到确认时间
    strategy_ack: i64,

    /// 总往返时间
    total_roundtrip: i64,

    /// 入场延迟
    pub fn entryLatency(self: OrderTimeline) i64 {
        return self.exchange_arrive - self.strategy_submit;
    }

    /// 响应延迟
    pub fn responseLatency(self: OrderTimeline) i64 {
        return self.strategy_ack - self.exchange_process;
    }
};
```

### LatencyConfig

延迟模拟配置。

```zig
pub const LatencyConfig = struct {
    /// 行情延迟配置
    feed_latency: FeedLatencyModel,

    /// 订单延迟配置
    order_latency: OrderLatencyModel,

    /// 是否启用延迟抖动
    enable_jitter: bool = true,

    /// 随机数种子
    seed: ?u64 = null,
};
```

---

## LatencySimulator

延迟模拟器主结构。

### init

```zig
pub fn init(config: LatencyConfig) LatencySimulator
```

创建延迟模拟器。

**参数**:
- `config`: 延迟配置

**示例**:
```zig
var simulator = LatencySimulator.init(.{
    .feed_latency = .{
        .model = .{
            .model_type = .Normal,
            .mean_ns = 2_000_000,   // 2ms
            .std_ns = 500_000,      // 0.5ms
        },
    },
    .order_latency = .{
        .entry = .{
            .model_type = .Constant,
            .value_ns = 1_000_000,  // 1ms
        },
        .response = .{
            .model_type = .Constant,
            .value_ns = 1_000_000,  // 1ms
        },
    },
});
```

### applyFeedLatency

```zig
pub fn applyFeedLatency(self: *LatencySimulator, event: MarketEvent) MarketEvent
```

应用行情延迟到市场事件。

**参数**:
- `event`: 原始市场事件

**返回**: 延迟后的市场事件

**说明**: 修改事件的时间戳以模拟策略收到事件的实际时间。

**示例**:
```zig
// 原始事件: 交易所时间 T0
const original_event = MarketEvent{
    .timestamp = exchange_time,
    .event_type = .trade,
    .trade = trade_data,
};

// 应用延迟后: 策略视角时间 T0 + latency
const delayed_event = simulator.applyFeedLatency(original_event);
// delayed_event.timestamp = exchange_time + feed_latency
```

### simulateOrderLatency

```zig
pub fn simulateOrderLatency(self: *LatencySimulator, submit_time: i64) OrderTimeline
```

模拟订单延迟时间线。

**参数**:
- `submit_time`: 策略提交订单的时间

**返回**: OrderTimeline 包含完整时间线

**示例**:
```zig
const timeline = simulator.simulateOrderLatency(strategy_time);

// 订单到达交易所的时间
const exchange_time = timeline.exchange_arrive;

// 策略收到确认的时间
const ack_time = timeline.strategy_ack;

// 总往返时间
std.debug.print("Roundtrip: {}ns\n", .{timeline.total_roundtrip});
```

### getExchangeArrivalTime

```zig
pub fn getExchangeArrivalTime(self: *LatencySimulator, submit_time: i64) i64
```

获取订单到达交易所的时间。

**参数**:
- `submit_time`: 策略提交时间

**返回**: 交易所收到订单的时间

### getStrategyAckTime

```zig
pub fn getStrategyAckTime(self: *LatencySimulator, exchange_time: i64) i64
```

获取策略收到确认的时间。

**参数**:
- `exchange_time`: 交易所处理完成时间

**返回**: 策略收到确认的时间

### getStats

```zig
pub fn getStats(self: *LatencySimulator) LatencyStats
```

获取延迟统计。

```zig
pub const LatencyStats = struct {
    /// 行情延迟统计
    feed: LatencyMetrics,

    /// 订单入场延迟统计
    order_entry: LatencyMetrics,

    /// 订单响应延迟统计
    order_response: LatencyMetrics,

    /// 总样本数
    sample_count: u64,

    pub const LatencyMetrics = struct {
        min_ns: i64,
        max_ns: i64,
        avg_ns: f64,
        p50_ns: i64,
        p99_ns: i64,
    };
};
```

### reset

```zig
pub fn reset(self: *LatencySimulator) void
```

重置模拟器状态和统计。

---

## 辅助结构

### DelayedEvent

延迟事件包装。

```zig
pub const DelayedEvent = struct {
    /// 原始事件
    original: MarketEvent,

    /// 交易所时间
    exchange_time: i64,

    /// 策略可见时间
    strategy_visible_time: i64,

    /// 延迟量
    latency_ns: i64,
};
```

### DelayedOrder

延迟订单包装。

```zig
pub const DelayedOrder = struct {
    /// 原始订单
    order: Order,

    /// 时间线
    timeline: OrderTimeline,

    /// 是否已到达交易所
    arrived_at_exchange: bool,

    /// 是否已收到确认
    acknowledged: bool,
};
```

---

## 使用示例

### 基本使用

```zig
const std = @import("std");
const LatencySimulator = @import("backtest/latency.zig").LatencySimulator;

pub fn main() !void {
    // 创建模拟器
    var simulator = LatencySimulator.init(.{
        .feed_latency = .{
            .model = .{
                .model_type = .Normal,
                .mean_ns = 2_000_000,
                .std_ns = 500_000,
            },
        },
        .order_latency = .{
            .entry = .{ .model_type = .Constant, .value_ns = 1_000_000 },
            .response = .{ .model_type = .Constant, .value_ns = 1_000_000 },
        },
    });

    // 模拟行情延迟
    const event = MarketEvent{
        .timestamp = 1000000000, // 交易所时间
        .event_type = .trade,
    };
    const delayed = simulator.applyFeedLatency(event);
    std.debug.print("原始时间: {}, 策略可见时间: {}\n", .{
        event.timestamp,
        delayed.timestamp,
    });

    // 模拟订单延迟
    const submit_time: i64 = 1000000000;
    const timeline = simulator.simulateOrderLatency(submit_time);
    std.debug.print("提交: {}, 到达: {}, 确认: {}\n", .{
        timeline.strategy_submit,
        timeline.exchange_arrive,
        timeline.strategy_ack,
    });
}
```

### 回测集成

```zig
pub const LatencyAwareBacktest = struct {
    simulator: LatencySimulator,
    event_queue: std.PriorityQueue(DelayedEvent, void, compareByVisibleTime),
    pending_orders: std.ArrayList(DelayedOrder),

    pub fn processMarketData(self: *LatencyAwareBacktest, event: MarketEvent) !void {
        // 应用行情延迟
        const delayed = self.simulator.applyFeedLatency(event);

        // 加入延迟事件队列
        try self.event_queue.add(.{
            .original = event,
            .exchange_time = event.timestamp,
            .strategy_visible_time = delayed.timestamp,
            .latency_ns = delayed.timestamp - event.timestamp,
        });
    }

    pub fn submitOrder(self: *LatencyAwareBacktest, order: Order, current_time: i64) !void {
        // 模拟订单延迟
        const timeline = self.simulator.simulateOrderLatency(current_time);

        try self.pending_orders.append(.{
            .order = order,
            .timeline = timeline,
            .arrived_at_exchange = false,
            .acknowledged = false,
        });
    }

    pub fn tick(self: *LatencyAwareBacktest, current_time: i64) !void {
        // 处理到达时间的事件
        while (self.event_queue.peek()) |event| {
            if (event.strategy_visible_time <= current_time) {
                const e = self.event_queue.remove();
                try self.onMarketEvent(e.original);
            } else {
                break;
            }
        }

        // 处理待处理订单
        for (self.pending_orders.items) |*pending| {
            // 检查订单是否到达交易所
            if (!pending.arrived_at_exchange and
                pending.timeline.exchange_arrive <= current_time)
            {
                pending.arrived_at_exchange = true;
                try self.onOrderArrived(&pending.order);
            }

            // 检查是否收到确认
            if (!pending.acknowledged and
                pending.timeline.strategy_ack <= current_time)
            {
                pending.acknowledged = true;
                try self.onOrderAcknowledged(&pending.order);
            }
        }
    }
};
```

### 使用历史延迟数据

```zig
// 从文件加载历史延迟数据
const latency_data = try loadLatencyData("latency_samples.csv");

var simulator = LatencySimulator.init(.{
    .feed_latency = .{
        .model = .{
            .model_type = .Interpolated,
            .data = latency_data,
        },
    },
    .order_latency = .{
        .entry = .{
            .model_type = .Interpolated,
            .data = order_entry_data,
        },
        .response = .{
            .model_type = .Interpolated,
            .data = order_response_data,
        },
    },
});
```

---

## 错误处理

```zig
pub const LatencyError = error{
    /// 配置无效
    InvalidConfig,

    /// 延迟数据为空
    EmptyData,

    /// 延迟值为负
    NegativeLatency,

    /// 超出最大延迟
    ExceedsMaxLatency,
};
```

---

## 性能说明

| 操作 | 时间复杂度 | 预期延迟 |
|------|------------|----------|
| sample (Constant) | O(1) | < 10ns |
| sample (Normal) | O(1) | < 50ns |
| sample (Interpolated) | O(log n) | < 100ns |
| applyFeedLatency | O(1) | < 100ns |
| simulateOrderLatency | O(1) | < 150ns |

---

*Last updated: 2025-12-27*
