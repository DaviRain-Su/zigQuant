# Dual Latency Simulation 双向延迟模拟

> 分别模拟行情延迟和订单延迟，真实反映 HFT/做市策略的延迟影响

**状态**: 📋 待开发
**版本**: v0.7.0
**Story**: [Story 039](../../stories/v0.7.0/STORY_039_DUAL_LATENCY.md)
**依赖**: [Queue Position](../queue-position/README.md)
**来源**: HFTBacktest
**最后更新**: 2025-12-27

---

## 概述

双向延迟模拟 (Dual Latency Simulation) 是高频交易回测的关键技术。它将延迟分为两类：行情延迟 (Feed Latency) 和订单延迟 (Order Latency)，真实模拟策略的时序行为。

### 为什么需要双向延迟?

```
传统回测 (不考虑延迟):
  T0: 收到行情 → 策略决策 → 订单提交 → 成交
  假设一切即时完成

真实世界:
  T0:        市场发生变化
  T0 + 1ms:  交易所发送行情
  T0 + 2ms:  你收到行情 (Feed Latency = 2ms)
  T0 + 3ms:  策略计算完成
  T0 + 4ms:  订单发送
  T0 + 5ms:  订单到达交易所 (Order Entry Latency = 1ms)
  T0 + 6ms:  交易所处理订单
  T0 + 7ms:  你收到确认 (Order Response Latency = 1ms)

总延迟: 7ms，期间市场可能已经变化!
```

### 延迟类型

```
┌─────────────────────────────────────────────────────────────────┐
│                    双向延迟模型                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Feed Latency (行情延迟):                                       │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐           │
│  │ 交易所   │ ──2ms──▶│ 网络    │ ──1ms──▶│ 策略    │           │
│  │ 产生事件 │         │ 传输    │         │ 收到    │           │
│  └─────────┘         └─────────┘         └─────────┘           │
│                                                                  │
│  Order Latency (订单延迟):                                      │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐           │
│  │ 策略    │ ──1ms──▶│ 交易所  │ ──1ms──▶│ 策略    │           │
│  │ 发送    │ (Entry) │ 处理    │ (Resp)  │ 确认    │           │
│  └─────────┘         └─────────┘         └─────────┘           │
│                                                                  │
│  总 Roundtrip = Entry Latency + Response Latency               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 核心特性

- **Feed Latency**: 行情从交易所到策略的延迟
- **Order Latency**: 订单往返延迟 (提交 + 响应)
- **3 种延迟模型**: Constant/Normal/Interpolated
- **纳秒级精度**: 精确时间模拟

---

## 快速开始

```zig
const LatencySimulator = @import("backtest/latency.zig").LatencySimulator;

// 创建延迟模拟器
var simulator = LatencySimulator.init(.{
    .feed_latency = .{
        .model = .Normal,
        .mean_ns = 2_000_000,   // 2ms
        .std_ns = 500_000,      // 0.5ms
    },
    .order_latency = .{
        .entry = .{
            .model = .Constant,
            .value_ns = 1_000_000,  // 1ms
        },
        .response = .{
            .model = .Constant,
            .value_ns = 1_000_000,  // 1ms
        },
    },
});

// 模拟行情延迟
const delayed_event = simulator.applyFeedLatency(market_event);

// 模拟订单延迟
const timeline = simulator.simulateOrderLatency(submit_time);
// timeline.exchange_arrive: 订单到达交易所时间
// timeline.strategy_ack: 策略收到确认时间
```

---

## 核心 API

### LatencyModelType

```zig
pub const LatencyModelType = enum {
    /// 固定延迟
    Constant,

    /// 正态分布延迟
    Normal,

    /// 从历史数据插值
    Interpolated,
};
```

### LatencyModel

```zig
pub const LatencyModel = struct {
    model_type: LatencyModelType,
    value_ns: i64 = 0,          // Constant 模式
    mean_ns: i64 = 0,           // Normal 模式
    std_ns: i64 = 0,            // Normal 模式
    data: ?[]const i64 = null,  // Interpolated 模式

    /// 采样延迟值
    pub fn sample(self: LatencyModel, rng: *Random) i64;
};
```

### OrderLatencyModel

```zig
pub const OrderLatencyModel = struct {
    /// 订单提交延迟 (策略 → 交易所)
    entry: LatencyModel,

    /// 订单响应延迟 (交易所 → 策略)
    response: LatencyModel,

    /// 模拟完整订单时间线
    pub fn simulate(self: OrderLatencyModel, submit_time: i64) OrderTimeline;
};
```

### OrderTimeline

```zig
pub const OrderTimeline = struct {
    strategy_submit: i64,   // 策略提交时间
    exchange_arrive: i64,   // 到达交易所时间
    exchange_process: i64,  // 交易所处理时间
    strategy_ack: i64,      // 策略收到确认时间
    total_roundtrip: i64,   // 总往返时间
};
```

### LatencySimulator

```zig
pub const LatencySimulator = struct {
    /// 应用行情延迟
    pub fn applyFeedLatency(self: *LatencySimulator, event: MarketEvent) MarketEvent;

    /// 模拟订单延迟
    pub fn simulateOrderLatency(self: *LatencySimulator, submit_time: i64) OrderTimeline;

    /// 获取统计
    pub fn getStats(self: *LatencySimulator) LatencyStats;
};
```

---

## 延迟模型对比

| 模型 | 描述 | 适用场景 |
|------|------|----------|
| Constant | 固定延迟值 | 简单测试 |
| Normal | 正态分布 N(μ,σ) | 一般模拟 |
| Interpolated | 历史数据插值 | 精确回测 |

---

## 相关文档

- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [Bug 追踪](./bugs.md)
- [变更日志](./changelog.md)

---

## 性能指标

| 指标 | 目标值 |
|------|--------|
| 延迟计算 | < 100ns |
| 时间精度 | 纳秒级 |
| 内存开销 | < 1KB |

---

## 参考资料

- [HFTBacktest](https://github.com/nkaz001/hftbacktest) - 原始实现参考
- [Order Latency in HFT](https://www.sciencedirect.com/science/article/pii/S0304405X17301290)

---

*Last updated: 2025-12-27*
