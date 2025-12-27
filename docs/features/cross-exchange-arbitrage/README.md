# Cross-Exchange Arbitrage 跨交易所套利

> 监测不同交易所价格差异，执行同时买卖获取无风险利润

**状态**: 📋 待开发
**版本**: v0.7.0
**Story**: [Story 037](../../stories/v0.7.0/STORY_037_ARBITRAGE.md)
**依赖**: [Clock-Driven](../clock-driven/README.md), [SQLite Storage](../sqlite-storage/README.md)
**最后更新**: 2025-12-27

---

## 概述

跨交易所套利 (Cross-Exchange Arbitrage) 是一种低风险策略，通过在价格较低的交易所买入，同时在价格较高的交易所卖出，获取价差利润。

### 套利原理

```
Exchange A              Exchange B
┌─────────────┐        ┌─────────────┐
│ ETH/USDT    │        │ ETH/USDT    │
│             │        │             │
│ Bid: 1995   │        │ Bid: 2005   │ ← 更高
│ Ask: 2000   │ ← 更低 │ Ask: 2010   │
└─────────────┘        └─────────────┘

套利操作:
  在 A 买入 @ 2000
  在 B 卖出 @ 2005
  毛利润 = 5 USDT (0.25%)

扣除费用后:
  A 买入费用: 2000 * 0.1% = 2 USDT
  B 卖出费用: 2005 * 0.1% = 2 USDT
  净利润: 5 - 4 = 1 USDT (0.05%)
```

### 核心特性

- **价差监测**: 实时比较多交易所报价
- **利润计算**: 自动扣除费用和滑点
- **同步执行**: 双边同时下单降低风险
- **风险控制**: 仓位限制和超时保护

---

## 快速开始

```zig
const CrossExchangeArbitrage = @import("arbitrage/cross_exchange.zig").CrossExchangeArbitrage;

// 配置
const config = ArbitrageConfig{
    .symbol = "ETH-USD",
    .min_profit_bps = 10,                     // 最小净利润 0.1%
    .trade_amount = Decimal.fromFloat(0.1),   // 每次 0.1 ETH
    .fee_bps_a = 10,                          // 交易所 A 费率 0.1%
    .fee_bps_b = 10,                          // 交易所 B 费率 0.1%
    .max_slippage_bps = 5,                    // 最大滑点 0.05%
};

// 创建策略
var arb = CrossExchangeArbitrage.init(
    allocator,
    config,
    &provider_a, &executor_a,
    &provider_b, &executor_b,
);
defer arb.deinit();

// 注册到 Clock
try clock.addStrategy(&arb.asClockStrategy());
```

---

## 核心 API

### ArbitrageConfig

```zig
pub const ArbitrageConfig = struct {
    symbol: []const u8,              // 交易对
    min_profit_bps: u32 = 10,        // 最小利润 (bps)
    trade_amount: Decimal,           // 交易数量
    max_slippage_bps: u32 = 5,       // 最大滑点
    fee_bps_a: u32 = 10,             // A 交易所费率
    fee_bps_b: u32 = 10,             // B 交易所费率
    max_position: Decimal,           // 最大仓位
    order_timeout_ms: u32 = 5000,    // 订单超时
    cooldown_ms: u32 = 1000,         // 冷却时间
};
```

### CrossExchangeArbitrage

```zig
pub const CrossExchangeArbitrage = struct {
    /// 检测套利机会
    pub fn detectOpportunity(self: *CrossExchangeArbitrage) ?ArbitrageOpportunity;

    /// 计算净利润 (扣除费用)
    pub fn calculateNetProfit(self: *CrossExchangeArbitrage,
                              buy_price: Decimal, sell_price: Decimal) Decimal;

    /// 执行套利
    pub fn executeArbitrage(self: *CrossExchangeArbitrage,
                            opportunity: ArbitrageOpportunity) !void;

    /// 获取统计
    pub fn getStats(self: *CrossExchangeArbitrage) ArbitrageStats;
};

pub const ArbitrageOpportunity = struct {
    buy_exchange: ExchangeId,        // 买入交易所
    sell_exchange: ExchangeId,       // 卖出交易所
    buy_price: Decimal,              // 买入价
    sell_price: Decimal,             // 卖出价
    gross_profit_bps: u32,           // 毛利润
    net_profit_bps: u32,             // 净利润
    amount: Decimal,                 // 交易量
};
```

---

## 套利类型

| 类型 | 描述 | 本版本 |
|------|------|--------|
| 空间套利 | 不同交易所价差 | ✅ 支持 |
| 三角套利 | 同交易所多币对 | ❌ 未来 |
| 统计套利 | 价格回归配对 | ❌ 未来 |

---

## 相关文档

- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [Bug 追踪](./bugs.md)
- [变更日志](./changelog.md)

---

## 风险提示

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 执行风险 | 单边成交 | 订单超时取消 |
| 滑点风险 | 实际成交价差异 | max_slippage 限制 |
| 延迟风险 | 机会消失 | 快速执行 |
| 仓位风险 | 库存累积 | max_position 限制 |

---

## 性能指标

| 指标 | 目标值 |
|------|--------|
| 机会检测 | < 1ms |
| 订单执行 | < 50ms |
| 捕获率 | > 80% |

---

*Last updated: 2025-12-27*
