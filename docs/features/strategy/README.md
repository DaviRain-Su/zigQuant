# Strategy Framework - 策略框架

**版本**: v0.3.0
**状态**: 设计阶段
**层级**: Strategy Layer
**依赖**: Core (Decimal, Time, Logger), Exchange (IExchange), Market (OrderBook)

---

## 📋 目录

1. [功能概述](#功能概述)
2. [核心特性](#核心特性)
3. [快速开始](#快速开始)
4. [架构设计](#架构设计)
5. [使用示例](#使用示例)
6. [性能指标](#性能指标)
7. [相关文档](#相关文档)

---

## 🎯 功能概述

Strategy Framework 是 zigQuant 的策略开发框架，提供统一的策略接口和执行环境。

### 设计目标

参考 **Hummingbot V2** 和 **Freqtrade** 的设计理念：

- **易用性**: 开发者可以快速创建和测试策略
- **模块化**: 策略组件可独立开发和测试
- **高性能**: Zig 的零成本抽象和内存安全
- **可回测**: 历史数据验证策略效果
- **可优化**: 自动寻找最佳参数组合

### 关键概念

```
┌─────────────────────────────────────────────────────────────┐
│                   Strategy Framework                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐      ┌──────────────┐                     │
│  │   IStrategy  │◄─────│  Strategy    │ (用户实现)           │
│  │  Interface   │      │  Impl        │                     │
│  └──────┬───────┘      └──────────────┘                     │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────────────────────────────────┐               │
│  │         Strategy Context                 │               │
│  ├──────────────────────────────────────────┤               │
│  │  - Market Data Provider                  │               │
│  │  - Indicator Manager                     │               │
│  │  - Order Executor                        │               │
│  │  - Position Manager                      │               │
│  │  - Risk Manager                          │               │
│  └──────────────────────────────────────────┘               │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Indicator   │  │   Signal     │  │   Executor   │      │
│  │   Library    │  │  Generator   │  │   Engine     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## ✨ 核心特性

### 1. IStrategy 接口

统一的策略接口，基于 VTable 模式：

- **populateIndicators**: 计算技术指标（类似 Freqtrade）
- **generateEntrySignal**: 生成入场信号
- **generateExitSignal**: 生成出场信号
- **calculatePositionSize**: 仓位大小计算
- **getParameters**: 策略参数（用于优化）
- **getMetadata**: 策略元数据

### 2. StrategyContext

策略执行上下文，提供所需资源（参考 Hummingbot Controller）：

- **MarketDataProvider**: 市场数据提供者
- **OrderExecutor**: 订单执行器
- **PositionManager**: 仓位管理器
- **RiskManager**: 风险管理器
- **IndicatorManager**: 指标管理器（缓存优化）

### 3. 内置策略

提供开箱即用的经典策略：

- **DualMAStrategy**: 双均线策略（趋势跟随）
- **RSIMeanReversionStrategy**: RSI 均值回归策略
- **BollingerBreakoutStrategy**: 布林带突破策略

### 4. 技术指标库

参考 TA-Lib，提供常用技术指标：

- **SMA**: 简单移动平均
- **EMA**: 指数移动平均
- **RSI**: 相对强弱指标
- **MACD**: 移动平均收敛散度
- **Bollinger Bands**: 布林带

### 5. 回测引擎

使用历史数据验证策略：

- **HistoricalDataFeed**: 历史数据提供
- **EventSimulator**: 事件模拟器
- **PerformanceAnalyzer**: 性能分析器

### 6. 参数优化

自动寻找最佳参数组合：

- **GridSearchOptimizer**: 网格搜索
- **GeneticOptimizer**: 遗传算法（可选）

---

## 🚀 快速开始

### 1. 使用内置策略

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

const IStrategy = zigQuant.IStrategy;
const StrategyContext = zigQuant.StrategyContext;
const BacktestEngine = zigQuant.BacktestEngine;
const DualMAStrategy = zigQuant.strategy.builtin.DualMAStrategy;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建策略
    const strategy = try DualMAStrategy.create(allocator);
    defer strategy.deinit();

    // 配置回测
    const config = BacktestConfig{
        .pair = .{ .base = "ETH", .quote = "USDC" },
        .timeframe = .m15,
        .start_time = try Timestamp.fromISO8601("2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.fromISO8601("2024-12-31T23:59:59Z"),
        .initial_capital = try Decimal.fromInt(10000),
        .commission_rate = try Decimal.fromFloat(0.001),
    };

    // 运行回测
    var engine = BacktestEngine.init(allocator, logger);
    defer engine.deinit();

    const result = try engine.run(strategy, config);

    // 查看结果
    std.debug.print("总交易次数: {}\n", .{result.total_trades});
    std.debug.print("胜率: {d:.2}%\n", .{result.win_rate * 100});
    std.debug.print("净利润: {}\n", .{result.net_profit});
    std.debug.print("夏普比率: {d:.2}\n", .{result.sharpe_ratio});
    std.debug.print("最大回撤: {d:.2}%\n", .{result.max_drawdown * 100});
}
```

### 2. 创建自定义策略

```zig
/// 自定义策略示例 - 简单的价格突破策略
pub const MyBreakoutStrategy = struct {
    allocator: std.mem.Allocator,
    ctx: StrategyContext,

    // 策略参数
    lookback_period: u32 = 20,
    breakout_threshold: f64 = 0.02,  // 2% 突破

    pub fn create(allocator: std.mem.Allocator) !IStrategy {
        const self = try allocator.create(MyBreakoutStrategy);
        self.* = .{
            .allocator = allocator,
            .ctx = undefined,
        };

        return IStrategy{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
        const self: *MyBreakoutStrategy = @ptrCast(@alignCast(ptr));

        // 计算最高价和最低价
        var highs = try self.allocator.alloc(Decimal, candles.data.len);
        var lows = try self.allocator.alloc(Decimal, candles.data.len);

        for (self.lookback_period..candles.data.len) |i| {
            var max_high = candles.data[i - self.lookback_period].high;
            var min_low = candles.data[i - self.lookback_period].low;

            for (i - self.lookback_period + 1..i) |j| {
                if (candles.data[j].high.gt(max_high)) max_high = candles.data[j].high;
                if (candles.data[j].low.lt(min_low)) min_low = candles.data[j].low;
            }

            highs[i] = max_high;
            lows[i] = min_low;
        }

        try candles.addIndicator("high_" ++ std.fmt.comptimePrint("{}", .{self.lookback_period}), highs);
        try candles.addIndicator("low_" ++ std.fmt.comptimePrint("{}", .{self.lookback_period}), lows);
    }

    fn generateEntrySignalImpl(ptr: *anyopaque, candles: *Candles, index: usize) !?Signal {
        const self: *MyBreakoutStrategy = @ptrCast(@alignCast(ptr));

        if (index < self.lookback_period) return null;

        const highs = candles.getIndicator("high_20") orelse return null;
        const lows = candles.getIndicator("low_20") orelse return null;

        const current_price = candles.data[index].close;
        const prev_high = highs[index - 1];
        const prev_low = lows[index - 1];

        // 向上突破
        if (current_price.gt(prev_high)) {
            const breakout_pct = try current_price.sub(prev_high).div(prev_high);
            if (breakout_pct.toFloat() >= self.breakout_threshold) {
                return Signal{
                    .type = .entry_long,
                    .pair = self.ctx.config.pair,
                    .side = .buy,
                    .price = current_price,
                    .strength = 0.8,
                    .timestamp = candles.data[index].timestamp,
                    .metadata = null,
                };
            }
        }

        // 向下突破
        if (current_price.lt(prev_low)) {
            const breakout_pct = try prev_low.sub(current_price).div(prev_low);
            if (breakout_pct.toFloat() >= self.breakout_threshold) {
                return Signal{
                    .type = .entry_short,
                    .pair = self.ctx.config.pair,
                    .side = .sell,
                    .price = current_price,
                    .strength = 0.8,
                    .timestamp = candles.data[index].timestamp,
                    .metadata = null,
                };
            }
        }

        return null;
    }

    // ... 其他 vtable 方法实现

    const vtable = IStrategy.VTable{
        .init = initImpl,
        .deinit = deinitImpl,
        .populateIndicators = populateIndicatorsImpl,
        .generateEntrySignal = generateEntrySignalImpl,
        .generateExitSignal = generateExitSignalImpl,
        .calculatePositionSize = calculatePositionSizeImpl,
        .getParameters = getParametersImpl,
        .getMetadata = getMetadataImpl,
    };
};
```

---

## 🏗️ 架构设计

### 目录结构

```
src/strategy/
├── interface.zig           # IStrategy 接口定义
├── context.zig             # StrategyContext
├── executor.zig            # OrderExecutor
├── signal.zig              # SignalGenerator
├── risk.zig                # RiskManager
├── types.zig               # 策略相关类型
│
├── indicators/             # 技术指标库
│   ├── sma.zig
│   ├── ema.zig
│   ├── rsi.zig
│   ├── macd.zig
│   ├── bollinger.zig
│   └── ...
│
└── builtin/                # 内置策略
    ├── dual_ma.zig         # 双均线策略
    ├── mean_reversion.zig  # 均值回归策略
    └── breakout.zig        # 突破策略
```

### 设计原则

1. **松耦合**: 通过事件队列通信（参考 Hummingbot）
2. **高内聚**: 每个组件职责单一
3. **可测试**: 所有组件可独立 mock
4. **可组合**: Lego 式组件拼接

---

## 📊 使用示例

### 参数优化

```zig
const optimizer = GridSearchOptimizer.init(allocator, backtest_engine);
defer optimizer.deinit();

// 定义参数范围
const params = [_]StrategyParameter{
    .{
        .name = "fast_period",
        .type = .integer,
        .default_value = .{ .integer = 10 },
        .range = .{ .integer = .{ .min = 5, .max = 20, .step = 1 } },
        .optimize = true,
    },
    .{
        .name = "slow_period",
        .type = .integer,
        .default_value = .{ .integer = 20 },
        .range = .{ .integer = .{ .min = 15, .max = 50, .step = 5 } },
        .optimize = true,
    },
};

// 运行优化
const result = try optimizer.optimize(
    DualMAStrategy.createWithParams,
    &params,
    backtest_config,
);

std.debug.print("最佳参数:\n", .{});
for (result.best_params) |param| {
    std.debug.print("  {s}: {}\n", .{ param.name, param.value });
}
std.debug.print("夏普比率: {d:.2}\n", .{result.best_result.sharpe_ratio});
```

---

## ⚡ 性能指标

### 目标

- **策略执行延迟**: < 1ms
- **回测速度**: > 1000 candles/s
- **内存占用**: < 100MB (10000 蜡烛 + 5 个指标)
- **零内存泄漏**: GeneralPurposeAllocator 验证

### 实测（预期）

| 操作 | 延迟/速度 | 说明 |
|------|-----------|------|
| populateIndicators (SMA) | < 500μs | 1000 蜡烛 |
| generateSignal | < 100μs | 单次信号生成 |
| 回测 (双均线) | > 2000 candles/s | 包含指标计算 |
| 网格搜索 (10x10) | < 30s | 100 个参数组合 |

---

## 📚 相关文档

### 本模块文档

- [API 参考](./api.md) - 完整 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试策略](./testing.md) - 测试方法和用例
- [已知问题](./bugs.md) - Bug 追踪
- [变更历史](./changelog.md) - 版本变更记录

### 相关模块

- [Indicators Library](../indicators/README.md) - 技术指标库
- [Backtest Engine](../backtest/README.md) - 回测引擎
- [OrderBook](../orderbook/README.md) - 订单簿管理
- [Order Manager](../order-manager/README.md) - 订单管理

### 设计文档

- [v0.3.0 策略框架设计](../../v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md) - 完整设计文档
- [架构设计](../../ARCHITECTURE.md) - 整体架构

### 示例代码

- `examples/05_strategy_backtest.zig` - 策略回测示例
- `examples/06_strategy_optimize.zig` - 参数优化示例

---

## 🎓 学习路径

1. **理解概念**: 阅读本 README 和设计文档
2. **运行示例**: 尝试内置策略回测
3. **修改参数**: 调整策略参数观察效果
4. **创建策略**: 实现自定义策略
5. **参数优化**: 使用优化器寻找最佳参数
6. **实盘测试**: 在 testnet 验证策略

---

**版本**: v0.3.0
**状态**: 设计阶段
**更新时间**: 2025-12-25
**参考框架**: Hummingbot V2, Freqtrade
