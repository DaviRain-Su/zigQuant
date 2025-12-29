# Paper Trading - 模拟交易

> 使用真实市场数据的无风险策略验证环境

**状态**: ✅ 已完成
**版本**: v0.6.0 (v0.9.1 架构更新)
**Story**: [Story 031](../../stories/v0.6.0/STORY_031_PAPER_TRADING.md)
**最后更新**: 2025-12-29

---

## 概述

Paper Trading (模拟交易) 是 zigQuant v0.6.0 的核心功能，提供一个使用真实市场数据但不实际执行订单的测试环境。这使得策略开发者可以在无风险的情况下验证策略逻辑，并获得与实盘接近的性能评估。

### 核心特性

- **真实数据**: 使用 Hyperliquid 实时市场数据
- **模拟执行**: 订单不发送到交易所，本地模拟成交
- **滑点模拟**: 模拟真实交易中的滑点影响
- **手续费计算**: 准确计算交易成本
- **实时统计**: PnL、胜率、回撤等指标实时更新

---

## 快速开始

### 代码使用

```zig
const PaperTradingEngine = @import("zigQuant").PaperTradingEngine;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建 Paper Trading 引擎
    var engine = try PaperTradingEngine.init(allocator, .{
        .initial_balance = Decimal.fromInt(10000),
        .commission_rate = Decimal.fromFloat(0.0005),  // 0.05%
        .slippage = Decimal.fromFloat(0.0001),         // 0.01%
        .symbols = &[_][]const u8{ "BTC", "ETH" },
    });
    defer engine.deinit();

    // 设置策略
    const strategy = DualMAStrategy.init(.{ .fast = 10, .slow = 30 });
    engine.setStrategy(strategy.asStrategy());

    // 启动
    try engine.start();

    // 运行 1 小时
    std.time.sleep(3600 * std.time.ns_per_s);

    // 停止并查看结果
    engine.stop();
}
```

### CLI 使用

```bash
# 基本使用
zigquant run-strategy --strategy dual_ma --paper

# 指定初始资金
zigquant run-strategy --strategy dual_ma --paper --balance 50000

# 指定交易对
zigquant run-strategy --strategy dual_ma --paper --symbol BTC --symbol ETH

# 详细日志
zigquant run-strategy --strategy dual_ma --paper --verbose
```

---

## 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 模拟执行逻辑
- [测试文档](./testing.md) - 测试用例
- [Bug 追踪](./bugs.md) - 已知问题
- [变更日志](./changelog.md) - 版本历史

---

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                    PaperTradingEngine                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           HyperliquidDataProvider                    │   │
│  │              (真实市场数据)                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                         ↓                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   Strategy                           │   │
│  │              (交易策略执行)                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                         ↓                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              SimulatedExecutor                       │   │
│  │         (模拟订单执行 - 不连接交易所)                │   │
│  └─────────────────────────────────────────────────────┘   │
│                         ↓                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              SimulatedAccount                        │   │
│  │        (模拟账户余额、仓位、PnL)                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 架构说明 (v0.9.1)

> **PaperTradingEngine vs StrategyRunner/LiveRunner**
>
> - **PaperTradingEngine** (`src/trading/paper_trading.zig`): 独立的模拟交易引擎，使用真实市场数据但模拟订单执行。适合策略验证和无风险测试。
>
> - **LiveRunner** (`src/engine/runners/live_runner.zig`): 统一引擎管理器中的实盘交易封装，包装 `LiveTradingEngine`，提供线程安全的生命周期管理。
>
> - **StrategyRunner** (`src/engine/runners/strategy_runner.zig`): 通用策略执行器，支持所有策略类型（包括 Grid Trading），提供统一的 tick 驱动执行。
>
> 三者服务于不同的使用场景，保持独立设计。`PaperTradingEngine` 专注于模拟环境，而 `LiveRunner` 和 `StrategyRunner` 由 `EngineManager` 统一管理。

---

## 配置选项

```zig
pub const Config = struct {
    /// 初始账户余额
    initial_balance: Decimal = Decimal.fromInt(10000),

    /// 手续费率 (0.0005 = 0.05%)
    commission_rate: Decimal = Decimal.fromFloat(0.0005),

    /// 滑点 (0.0001 = 0.01%)
    slippage: Decimal = Decimal.fromFloat(0.0001),

    /// 订阅的交易对
    symbols: []const []const u8,

    /// tick 间隔 (毫秒)
    tick_interval_ms: u32 = 1000,

    /// 是否记录交易日志
    log_trades: bool = true,
};
```

---

## 输出示例

```
═══════════════════════════════════════════════════
              Paper Trading Summary
═══════════════════════════════════════════════════
  Initial Balance:  10000.00 USDT
  Final Balance:    10523.45 USDT
  Total PnL:        523.45 USDT (5.23%)
  Total Trades:     47
  Win Rate:         61.7%
  Max Drawdown:     3.21%
═══════════════════════════════════════════════════
```

---

## 与回测的区别

| 特性 | Paper Trading | 回测 |
|------|---------------|------|
| 数据源 | 实时市场数据 | 历史数据 |
| 执行方式 | 实时模拟 | 批量处理 |
| 滑点模拟 | 基于实时订单簿 | 固定或随机 |
| 时间尺度 | 实时 | 快速回放 |
| 用途 | 最终验证 | 初步测试 |

---

## 最佳实践

### DO

```zig
// 使用合理的初始资金
.initial_balance = Decimal.fromFloat(10000),

// 设置合理的手续费和滑点
.commission_rate = Decimal.fromFloat(0.0005),
.slippage = Decimal.fromFloat(0.0001),

// 运行足够长的时间以获得统计显著性
std.time.sleep(86400 * std.time.ns_per_s);  // 至少 24 小时
```

### DON'T

```zig
// 避免使用不切实际的参数
.initial_balance = Decimal.fromFloat(1000000000),  // 10亿太不现实
.commission_rate = Decimal.zero(),  // 忽略手续费
.slippage = Decimal.zero(),         // 忽略滑点

// 避免短时间测试得出结论
std.time.sleep(60 * std.time.ns_per_s);  // 1分钟太短
```

---

## 性能指标

| 指标 | 目标 | 说明 |
|------|------|------|
| 数据延迟 | < 10ms | 使用真实市场数据 |
| 模拟精度 | > 99% | 考虑滑点和手续费 |
| 内存占用 | < 50MB | 长时间运行稳定 |
| 统计准确性 | 100% | 与回测结果可比较 |

---

*Last updated: 2025-12-29*
