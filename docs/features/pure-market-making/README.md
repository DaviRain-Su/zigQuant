# Pure Market Making 策略

> 在中间价两侧放置买卖订单，通过买卖价差获取利润的基础做市策略

**状态**: 📋 待开发
**版本**: v0.7.0
**Story**: [Story 034](../../stories/v0.7.0/STORY_034_PURE_MM.md)
**依赖**: [Clock-Driven](../clock-driven/README.md)
**最后更新**: 2025-12-27

---

## 概述

Pure Market Making 是最基础的做市策略，通过在 mid price (中间价) 两侧同时放置买单和卖单来提供流动性，并从买卖价差中获取利润。

### 什么是做市 (Market Making)?

```
                    Order Book

  卖单 (Asks)
  ├── 2010.00  (我的卖单)  ←── Ask
  ├── 2009.50
  ├── 2009.00
  │
  │   2005.00  ←── Mid Price (中间价)
  │
  ├── 2001.00
  ├── 2000.50
  └── 2000.00  (我的买单)  ←── Bid
  买单 (Bids)

  价差 (Spread) = Ask - Bid = 2010 - 2000 = 10 (0.5%)
  利润来源: 低买高卖 (买入 2000, 卖出 2010)
```

### 核心特性

- **双边报价**: 同时在买卖两侧挂单
- **多层级订单**: 支持在不同价格层级放置订单
- **自动刷新**: 当价格变动超过阈值时自动更新报价
- **仓位限制**: 控制最大持仓防止风险累积
- **IClockStrategy**: 实现时钟驱动接口，定期更新报价

---

## 快速开始

### 基本使用

```zig
const std = @import("std");
const Clock = @import("market_making/clock.zig").Clock;
const PureMarketMaking = @import("market_making/pure_mm.zig").PureMarketMaking;
const PureMMConfig = @import("market_making/pure_mm.zig").PureMMConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建策略配置
    const config = PureMMConfig{
        .symbol = "ETH-USD",
        .spread_bps = 10,                         // 0.1% 价差
        .order_amount = Decimal.fromFloat(0.1),   // 每单 0.1 ETH
        .order_levels = 2,                        // 2 层报价
        .max_position = Decimal.fromFloat(1.0),   // 最大持仓 1 ETH
    };

    // 创建策略
    var mm = PureMarketMaking.init(allocator, config, &data_provider, &executor);
    defer mm.deinit();

    // 创建时钟 (1秒间隔)
    var clock = Clock.init(allocator, 1000);
    defer clock.deinit();

    // 注册策略
    try clock.addStrategy(&mm.asClockStrategy());

    // 启动
    try clock.start();
}
```

---

## 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 核心 API

### PureMMConfig 配置

```zig
pub const PureMMConfig = struct {
    /// 交易对
    symbol: []const u8,

    /// 价差 (basis points, 1 bp = 0.01%)
    spread_bps: u32 = 10,

    /// 单边订单数量
    order_amount: Decimal,

    /// 价格层级数 (每边)
    order_levels: u32 = 1,

    /// 层级间价差 (basis points)
    level_spread_bps: u32 = 5,

    /// 最小报价更新阈值
    min_refresh_bps: u32 = 2,

    /// 订单有效时间 (ticks)
    order_ttl_ticks: u32 = 60,

    /// 最大仓位
    max_position: Decimal,

    /// 是否启用两侧报价
    dual_side: bool = true,
};
```

### PureMarketMaking 结构

```zig
pub const PureMarketMaking = struct {
    allocator: Allocator,
    config: PureMMConfig,
    current_position: Decimal,
    active_bids: ArrayList(OrderInfo),
    active_asks: ArrayList(OrderInfo),

    /// 初始化策略
    pub fn init(allocator: Allocator, config: PureMMConfig,
                data_provider: *IDataProvider, executor: *IExecutionClient) PureMarketMaking;

    /// 释放资源
    pub fn deinit(self: *PureMarketMaking) void;

    /// 获取 IClockStrategy 接口
    pub fn asClockStrategy(self: *PureMarketMaking) IClockStrategy;

    /// 处理成交回报
    pub fn onFill(self: *PureMarketMaking, fill: OrderFill) void;

    /// 获取统计信息
    pub fn getStats(self: *PureMarketMaking) MMStats;
};
```

### MMStats 统计

```zig
pub const MMStats = struct {
    total_trades: u64,         // 总成交笔数
    total_volume: Decimal,     // 总成交量
    current_position: Decimal, // 当前持仓
    realized_pnl: Decimal,     // 已实现盈亏
    active_bids: usize,        // 活跃买单数
    active_asks: usize,        // 活跃卖单数
};
```

---

## 策略风险

| 风险类型 | 描述 | 缓解措施 |
|----------|------|----------|
| **库存风险** | 单边成交导致仓位累积 | max_position 限制 |
| **逆向选择** | 知情交易者利用信息优势 | 扩大价差，减少订单量 |
| **市场风险** | 价格剧烈波动 | 快速更新报价 |
| **执行风险** | 订单延迟或部分成交 | 超时取消重下 |

---

## 参数调优

### 参数影响矩阵

| 参数 | 增大影响 | 减小影响 |
|------|----------|----------|
| spread_bps | 利润高，成交少 | 利润低，成交多 |
| order_amount | 风险大，收益大 | 风险小，收益小 |
| order_levels | 成交概率高 | 资金利用高 |
| min_refresh_bps | 更新少，稳定 | 更新多，敏感 |

### 推荐配置

```zig
// 保守配置 (适合初学者)
const conservative = PureMMConfig{
    .symbol = "ETH-USD",
    .spread_bps = 20,                         // 0.2% 价差
    .order_amount = Decimal.fromFloat(0.01),  // 小订单量
    .order_levels = 1,                        // 单层报价
    .max_position = Decimal.fromFloat(0.1),   // 严格仓位限制
};

// 激进配置 (适合经验丰富者)
const aggressive = PureMMConfig{
    .symbol = "ETH-USD",
    .spread_bps = 5,                          // 0.05% 紧密价差
    .order_amount = Decimal.fromFloat(0.1),   // 大订单量
    .order_levels = 3,                        // 多层报价
    .max_position = Decimal.fromFloat(1.0),   // 较大仓位限制
};
```

---

## 使用场景

### 适用

- **高流动性市场**: 买卖价差较窄的主流交易对
- **低波动期**: 价格相对稳定时期
- **有足够资金**: 能够维持双边报价

### 不适用

- **低流动性市场**: 容易被套牢
- **高波动期**: 库存风险太大
- **资金有限**: 无法覆盖仓位风险

---

## 性能指标

| 指标 | 目标值 | 说明 |
|------|--------|------|
| onTick 执行 | < 1ms | 每次 tick 处理时间 |
| 订单延迟 | < 10ms | 下单到确认时间 |
| 内存使用 | < 10MB | 稳定运行内存 |
| 报价更新频率 | 1/s | 默认每秒更新 |

---

## 文件结构

```
src/market_making/
├── mod.zig           # 模块导出
├── clock.zig         # Clock (Story 033)
├── pure_mm.zig       # Pure Market Making
├── types.zig         # 共享类型
└── config.zig        # 配置处理

docs/features/pure-market-making/
├── README.md         # 本文档
├── api.md            # API 参考
├── implementation.md # 实现细节
├── testing.md        # 测试文档
├── bugs.md           # Bug 追踪
└── changelog.md      # 变更日志
```

---

## 未来改进

- [ ] 动态价差调整 (基于波动率)
- [ ] 库存偏斜集成 (Story 035)
- [ ] 多交易对并行做市
- [ ] 机器学习优化参数

---

*Last updated: 2025-12-27*
