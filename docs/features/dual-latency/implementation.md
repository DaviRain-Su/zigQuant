# Dual Latency 实现细节

> 双向延迟模拟模块的内部实现文档

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 目录

1. [架构概述](#架构概述)
2. [延迟模型](#延迟模型)
3. [时间线模拟](#时间线模拟)
4. [与回测引擎集成](#与回测引擎集成)
5. [性能优化](#性能优化)

---

## 架构概述

### 模块结构

```
src/backtest/
├── latency.zig           # 延迟模拟主模块
├── latency_model.zig     # 延迟模型
├── order_timeline.zig    # 订单时间线
└── tests/
    └── latency_test.zig  # 测试
```

### 组件关系

```
┌─────────────────────────────────────────────────────────────┐
│                    BacktestEngine                            │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  LatencySimulator                     │   │
│  │                                                       │   │
│  │  ┌─────────────────────┐  ┌─────────────────────┐   │   │
│  │  │   FeedLatency       │  │   OrderLatency      │   │   │
│  │  │                     │  │                     │   │   │
│  │  │  ┌───────────────┐  │  │  ┌───────────────┐  │   │   │
│  │  │  │ LatencyModel  │  │  │  │  Entry Model  │  │   │   │
│  │  │  └───────────────┘  │  │  └───────────────┘  │   │   │
│  │  │                     │  │  ┌───────────────┐  │   │   │
│  │  │                     │  │  │Response Model │  │   │   │
│  │  │                     │  │  └───────────────┘  │   │   │
│  │  └─────────────────────┘  └─────────────────────┘   │   │
│  └──────────────────────────────────────────────────────┘   │
│                              │                               │
│  ┌───────────────────────────┴─────────────────────────┐    │
│  │                    Event Queue                       │    │
│  │  [E1@T1] [E2@T2] [E3@T3] ... (按可见时间排序)        │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 时间线可视化

```
真实世界时间 →

Exchange    ────●────────────────●────────────────────●────
Time          T0                T0+1ms            T0+2ms

              │                  │                    │
              │ Feed Latency     │                    │
              │ (2ms)            │                    │
              ▼                  │                    │
Strategy    ──────────●─────────│────────────────────│────
See Event            T0+2ms     │                    │
                                │                    │
                     Strategy   │ Entry Latency      │
                     Decides    │ (1ms)              │
                                ▼                    │
Exchange    ──────────────────────●──────────────────│────
Receives                        T0+3ms               │
Order                                                │
                                                     │
                                   Response Latency  │
                                   (1ms)             │
                                                     ▼
Strategy    ──────────────────────────────────────────●────
Gets Ack                                           T0+4ms
```

---

## 延迟模型

### Constant 模型

最简单的模型，返回固定值。

```zig
pub fn sampleConstant(self: LatencyModel) i64 {
    return self.value_ns;
}
```

**特点**:
- 确定性，适合单元测试
- 不反映真实延迟波动
- 计算最快

### Normal 模型

正态分布延迟，更接近实际情况。

```zig
pub fn sampleNormal(self: LatencyModel, rng: *Random) i64 {
    // Box-Muller 变换生成正态分布
    const u1 = rng.random().float(f64);
    const u2 = rng.random().float(f64);

    const z = @sqrt(-2.0 * @log(u1)) * @cos(2.0 * std.math.pi * u2);

    const mean = @as(f64, @floatFromInt(self.mean_ns));
    const std_dev = @as(f64, @floatFromInt(self.std_ns));

    const sample = mean + z * std_dev;

    // 确保非负并限制范围
    const clamped = std.math.clamp(
        @as(i64, @intFromFloat(sample)),
        self.min_ns,
        self.max_ns,
    );

    return @max(0, clamped);
}
```

**特点**:
- 模拟真实延迟波动
- 可配置均值和标准差
- 需要随机数生成器

### Interpolated 模型

从历史数据插值，最精确。

```zig
pub fn sampleInterpolated(self: LatencyModel, rng: *Random) i64 {
    const data = self.data orelse return 0;
    if (data.len == 0) return 0;

    // 随机选择历史样本
    const idx = rng.random().uintLessThan(usize, data.len);
    return data[idx];
}
```

**高级插值**:

```zig
pub fn sampleInterpolatedWithPercentile(self: LatencyModel, percentile: f64) i64 {
    const data = self.data orelse return 0;
    if (data.len == 0) return 0;

    // 数据应该已排序
    const idx_f = percentile * @as(f64, @floatFromInt(data.len - 1));
    const idx_low = @as(usize, @intFromFloat(@floor(idx_f)));
    const idx_high = @min(idx_low + 1, data.len - 1);
    const t = idx_f - @floor(idx_f);

    // 线性插值
    const low = @as(f64, @floatFromInt(data[idx_low]));
    const high = @as(f64, @floatFromInt(data[idx_high]));

    return @intFromFloat(low + t * (high - low));
}
```

### 统一采样接口

```zig
pub fn sample(self: LatencyModel, rng: *Random) i64 {
    const raw = switch (self.model_type) {
        .Constant => self.sampleConstant(),
        .Normal => self.sampleNormal(rng),
        .Interpolated => self.sampleInterpolated(rng),
    };

    // 应用限制
    return std.math.clamp(raw, self.min_ns, self.max_ns);
}
```

---

## 时间线模拟

### 行情延迟处理

```zig
pub fn applyFeedLatency(self: *LatencySimulator, event: MarketEvent) MarketEvent {
    // 采样延迟
    const latency = self.config.feed_latency.model.sample(&self.rng);

    // 更新统计
    self.stats.feed.update(latency);

    // 创建延迟后的事件
    var delayed = event;
    delayed.timestamp = event.timestamp + latency;

    return delayed;
}
```

### 订单延迟处理

```zig
pub fn simulateOrderLatency(self: *LatencySimulator, submit_time: i64) OrderTimeline {
    // 采样入场延迟
    const entry_latency = self.config.order_latency.entry.sample(&self.rng);

    // 采样响应延迟
    const response_latency = self.config.order_latency.response.sample(&self.rng);

    // 更新统计
    self.stats.order_entry.update(entry_latency);
    self.stats.order_response.update(response_latency);

    // 构建时间线
    const exchange_arrive = submit_time + entry_latency;
    const exchange_process = exchange_arrive; // 假设处理瞬时
    const strategy_ack = exchange_process + response_latency;

    return OrderTimeline{
        .strategy_submit = submit_time,
        .exchange_arrive = exchange_arrive,
        .exchange_process = exchange_process,
        .strategy_ack = strategy_ack,
        .total_roundtrip = entry_latency + response_latency,
    };
}
```

### 处理时间模拟

如果需要模拟交易所处理时间:

```zig
pub const OrderLatencyModel = struct {
    entry: LatencyModel,
    processing: ?LatencyModel = null, // 可选的处理时间
    response: LatencyModel,

    pub fn simulate(self: OrderLatencyModel, submit_time: i64, rng: *Random) OrderTimeline {
        const entry = self.entry.sample(rng);
        const processing = if (self.processing) |p| p.sample(rng) else 0;
        const response = self.response.sample(rng);

        const exchange_arrive = submit_time + entry;
        const exchange_process = exchange_arrive + processing;
        const strategy_ack = exchange_process + response;

        return OrderTimeline{
            .strategy_submit = submit_time,
            .exchange_arrive = exchange_arrive,
            .exchange_process = exchange_process,
            .strategy_ack = strategy_ack,
            .total_roundtrip = entry + processing + response,
        };
    }
};
```

---

## 与回测引擎集成

### 事件队列管理

```zig
pub const EventQueue = struct {
    heap: std.PriorityQueue(TimedEvent, void, compareByVisibleTime),

    pub const TimedEvent = struct {
        event: MarketEvent,
        visible_time: i64, // 策略可见时间
    };

    fn compareByVisibleTime(a: TimedEvent, b: TimedEvent) std.math.Order {
        return std.math.order(a.visible_time, b.visible_time);
    }

    pub fn push(self: *EventQueue, event: MarketEvent, delay: i64) !void {
        try self.heap.add(.{
            .event = event,
            .visible_time = event.timestamp + delay,
        });
    }

    pub fn popIfReady(self: *EventQueue, current_time: i64) ?MarketEvent {
        if (self.heap.peek()) |top| {
            if (top.visible_time <= current_time) {
                return self.heap.remove().event;
            }
        }
        return null;
    }
};
```

### 订单管理

```zig
pub const PendingOrderManager = struct {
    orders: std.ArrayList(PendingOrder),

    pub const PendingOrder = struct {
        order: *Order,
        timeline: OrderTimeline,
        state: OrderState,

        pub const OrderState = enum {
            submitted,       // 已提交，未到达交易所
            at_exchange,     // 在交易所等待处理
            processed,       // 已处理，等待响应
            acknowledged,    // 策略已收到确认
        };
    };

    pub fn tick(self: *PendingOrderManager, current_time: i64) !void {
        for (self.orders.items) |*pending| {
            switch (pending.state) {
                .submitted => {
                    if (current_time >= pending.timeline.exchange_arrive) {
                        pending.state = .at_exchange;
                        try self.onOrderArrived(pending.order);
                    }
                },
                .at_exchange => {
                    if (current_time >= pending.timeline.exchange_process) {
                        pending.state = .processed;
                    }
                },
                .processed => {
                    if (current_time >= pending.timeline.strategy_ack) {
                        pending.state = .acknowledged;
                        try self.onOrderAcknowledged(pending.order);
                    }
                },
                .acknowledged => {},
            }
        }
    }
};
```

### 完整回测引擎

```zig
pub const LatencyAwareEngine = struct {
    latency_sim: LatencySimulator,
    event_queue: EventQueue,
    order_manager: PendingOrderManager,
    current_time: i64,
    strategy: *Strategy,

    pub fn run(self: *LatencyAwareEngine, events: []const MarketEvent) !void {
        // 将所有事件加入延迟队列
        for (events) |event| {
            const latency = self.latency_sim.config.feed_latency.model.sample(&self.latency_sim.rng);
            try self.event_queue.push(event, latency);
        }

        // 主循环
        while (true) {
            // 获取下一个事件时间
            const next_event = self.event_queue.heap.peek();
            if (next_event == null) break;

            // 推进时间
            self.current_time = next_event.?.visible_time;

            // 处理订单状态
            try self.order_manager.tick(self.current_time);

            // 处理市场事件
            while (self.event_queue.popIfReady(self.current_time)) |event| {
                try self.strategy.onMarketEvent(event);
            }
        }
    }
};
```

---

## 性能优化

### 预计算常量

```zig
pub const LatencySimulator = struct {
    // 预计算的常量
    const_feed_latency: ?i64 = null,
    const_entry_latency: ?i64 = null,
    const_response_latency: ?i64 = null,

    pub fn init(config: LatencyConfig) LatencySimulator {
        var self = LatencySimulator{ .config = config };

        // 预计算常量延迟
        if (config.feed_latency.model.model_type == .Constant) {
            self.const_feed_latency = config.feed_latency.model.value_ns;
        }
        if (config.order_latency.entry.model_type == .Constant) {
            self.const_entry_latency = config.order_latency.entry.value_ns;
        }
        if (config.order_latency.response.model_type == .Constant) {
            self.const_response_latency = config.order_latency.response.value_ns;
        }

        return self;
    }

    pub fn applyFeedLatency(self: *LatencySimulator, event: MarketEvent) MarketEvent {
        // 使用预计算值
        const latency = self.const_feed_latency orelse
            self.config.feed_latency.model.sample(&self.rng);

        var delayed = event;
        delayed.timestamp += latency;
        return delayed;
    }
};
```

### 批量处理

```zig
pub fn applyFeedLatencyBatch(
    self: *LatencySimulator,
    events: []const MarketEvent,
    out: []MarketEvent,
) void {
    std.debug.assert(events.len == out.len);

    // 批量采样 (可能有 SIMD 优化)
    for (events, 0..) |event, i| {
        out[i] = self.applyFeedLatency(event);
    }
}
```

### 使用快速随机数

```zig
// 使用 Xoshiro256** 替代默认 RNG
pub const FastRng = std.rand.Xoshiro256;

pub const LatencySimulator = struct {
    rng: FastRng,
    // ...
};
```

---

## 测试要点

### 延迟分布验证

```zig
test "Normal distribution statistics" {
    const model = LatencyModel{
        .model_type = .Normal,
        .mean_ns = 1_000_000,
        .std_ns = 100_000,
    };

    var rng = std.rand.DefaultPrng.init(42);
    var sum: i64 = 0;
    const n = 10000;

    for (0..n) |_| {
        sum += model.sample(&rng);
    }

    const avg = @as(f64, @floatFromInt(sum)) / n;

    // 平均值应该接近 1ms
    try testing.expect(@abs(avg - 1_000_000) < 50_000);
}
```

---

*Last updated: 2025-12-27*
