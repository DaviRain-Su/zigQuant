# 策略开发完整教程

本教程将指导你从零开始开发、测试和优化一个完整的交易策略。

---

## 📋 目录

- [概述](#概述)
- [策略开发流程](#策略开发流程)
- [示例: KDJ 随机指标策略](#示例-kdj-随机指标策略)
- [回测验证](#回测验证)
- [参数优化](#参数优化)
- [实盘准备](#实盘准备)
- [最佳实践](#最佳实践)
- [常见问题](#常见问题)

---

## 概述

### 策略开发完整流程

```
1. 策略设计
   ├─ 定义交易逻辑
   ├─ 选择技术指标
   └─ 确定参数

2. 代码实现
   ├─ 实现 IStrategy 接口
   ├─ 配置参数
   └─ 编写信号逻辑

3. 回测验证
   ├─ 准备历史数据
   ├─ 运行回测
   └─ 分析结果

4. 参数优化
   ├─ 定义优化范围
   ├─ 运行网格搜索
   └─ 验证泛化能力

5. 实盘准备
   ├─ 风险管理
   ├─ 监控告警
   └─ 逐步放大
```

### 前置知识

在开始之前，你应该了解:
- ✅ Zig 语言基础
- ✅ 技术分析指标原理
- ✅ 回测概念
- ✅ zigQuant 框架基础 (见 [README.md](../../README.md))

### 工具准备

```bash
# 1. 确保项目可以构建
zig build

# 2. 准备历史数据
# 下载或准备 CSV 格式数据
# data/BTCUSDT_h1_2024.csv

# 3. 了解内置策略
ls src/strategy/builtin/
# dual_ma.zig, mean_reversion.zig, breakout.zig
```

---

## 策略开发流程

### 第 1 步: 策略设计

#### 定义交易逻辑

以 KDJ 随机指标策略为例:

**交易规则**:
- **做多信号**: K 线上穿 D 线，且 J < 超卖阈值
- **做空信号**: K 线下穿 D 线，且 J > 超买阈值
- **平多仓**: K 线下穿 D 线
- **平空仓**: K 线上穿 D 线

**参数**:
- `k_period`: K 线周期 (默认: 9)
- `d_period`: D 线平滑周期 (默认: 3)
- `oversold`: 超卖阈值 (默认: 20)
- `overbought`: 超买阈值 (默认: 80)

#### 技术指标选择

KDJ 策略需要:
- ✅ Stochastic Oscillator (已内置)

#### 画出策略流程图

```
市场数据 (Candle)
    ↓
计算 Stochastic (K, D, J)
    ↓
┌─────────────┬─────────────┐
│ Entry Signal│ Exit Signal │
├─────────────┼─────────────┤
│ K 上穿 D    │ K 下穿 D   │
│ AND J < 20  │             │
│ → LONG      │ → CLOSE     │
│             │             │
│ K 下穿 D    │ K 上穿 D   │
│ AND J > 80  │             │
│ → SHORT     │ → CLOSE     │
└─────────────┴─────────────┘
```

---

### 第 2 步: 代码实现

#### 创建策略文件

**文件**: `src/strategy/builtin/kdj.zig`

```zig
//! KDJ Stochastic Strategy
//!
//! Trading Signals:
//! - Long: K crosses above D and J < oversold
//! - Short: K crosses below D and J > overbought
//! - Close Long: K crosses below D
//! - Close Short: K crosses above D

const std = @import("std");
const root = @import("../../root.zig");

const IStrategy = root.IStrategy;
const StrategyMetadata = root.StrategyMetadata;
const StrategyParameter = root.StrategyParameter;
const ParameterType = root.ParameterType;
const ParameterValue = root.ParameterValue;
const Signal = root.Signal;
const SignalType = root.SignalType;
const StrategyContext = root.strategy_interface.StrategyContext;
const Stochastic = root.indicator_helpers.Stochastic;
const Decimal = root.Decimal;

pub const KDJStrategy = struct {
    allocator: std.mem.Allocator,

    // Parameters
    k_period: u32,
    d_period: u32,
    oversold: f64,
    overbought: f64,

    // Indicators
    stoch: ?Stochastic,

    // Previous state for crossover detection
    prev_k: ?f64,
    prev_d: ?f64,

    pub fn init(allocator: std.mem.Allocator) !KDJStrategy {
        return .{
            .allocator = allocator,
            .k_period = 9,
            .d_period = 3,
            .oversold = 20.0,
            .overbought = 80.0,
            .stoch = null,
            .prev_k = null,
            .prev_d = null,
        };
    }

    pub fn deinit(self: *KDJStrategy) void {
        if (self.stoch) |*s| {
            s.deinit();
        }
    }

    pub fn interface(self: *KDJStrategy) IStrategy {
        return IStrategy.init(self);
    }

    // IStrategy interface implementation
    pub fn metadata(self: *KDJStrategy) StrategyMetadata {
        _ = self;
        return StrategyMetadata{
            .name = "KDJ Stochastic Strategy",
            .version = "1.0.0",
            .description = "Crossover strategy using KDJ stochastic indicator",
            .author = "zigQuant",
        };
    }

    pub fn parameters(self: *KDJStrategy) []const StrategyParameter {
        _ = self;
        const params = &[_]StrategyParameter{
            .{
                .name = "k_period",
                .type = .integer,
                .default_value = ParameterValue{ .integer = 9 },
                .description = "K line period",
                .optimize = true,
                .range = .{ .integer = .{ .min = 5, .max = 14, .step = 1 } },
            },
            .{
                .name = "d_period",
                .type = .integer,
                .default_value = ParameterValue{ .integer = 3 },
                .description = "D line smoothing period",
                .optimize = true,
                .range = .{ .integer = .{ .min = 2, .max = 5, .step = 1 } },
            },
            .{
                .name = "oversold",
                .type = .decimal,
                .default_value = ParameterValue{ .decimal = 20.0 },
                .description = "Oversold threshold",
                .optimize = true,
                .range = .{ .decimal = .{ .min = 15.0, .max = 30.0, .step = 5.0 } },
            },
            .{
                .name = "overbought",
                .type = .decimal,
                .default_value = ParameterValue{ .decimal = 80.0 },
                .description = "Overbought threshold",
                .optimize = true,
                .range = .{ .decimal = .{ .min = 70.0, .max = 85.0, .step = 5.0 } },
            },
        };
        return params;
    }

    pub fn initialize(self: *KDJStrategy, ctx: *StrategyContext) !void {
        // Load parameters from context
        if (ctx.getParameter("k_period")) |p| {
            self.k_period = @intCast(p.integer);
        }
        if (ctx.getParameter("d_period")) |p| {
            self.d_period = @intCast(p.integer);
        }
        if (ctx.getParameter("oversold")) |p| {
            self.oversold = p.decimal;
        }
        if (ctx.getParameter("overbought")) |p| {
            self.overbought = p.decimal;
        }
    }

    pub fn populateIndicators(self: *KDJStrategy, ctx: *StrategyContext) !void {
        // Initialize Stochastic indicator
        self.stoch = try Stochastic.init(
            ctx.allocator,
            self.k_period,
            self.d_period,
        );
    }

    pub fn populateEntryTrend(self: *KDJStrategy, ctx: *StrategyContext) !void {
        // Calculate Stochastic
        const candles = ctx.candles.items;
        if (candles.len < self.k_period + self.d_period) return;

        var stoch = self.stoch.?;
        const result = try stoch.calculate(candles);
        defer result.deinit();

        const k = result.k;
        const d = result.d;
        const j = result.j;

        // Detect crossovers
        if (self.prev_k != null and self.prev_d != null) {
            const k_cross_above_d = self.prev_k.? < self.prev_d.? and k > d;
            const k_cross_below_d = self.prev_k.? > self.prev_d.? and k < d;

            // Long signal: K crosses above D and J < oversold
            if (k_cross_above_d and j < self.oversold) {
                try ctx.addSignal(Signal{
                    .type = .long,
                    .strength = @min(1.0, (self.oversold - j) / 10.0),
                    .indicators = null,
                });
            }

            // Short signal: K crosses below D and J > overbought
            if (k_cross_below_d and j > self.overbought) {
                try ctx.addSignal(Signal{
                    .type = .short,
                    .strength = @min(1.0, (j - self.overbought) / 10.0),
                    .indicators = null,
                });
            }
        }

        // Update previous values
        self.prev_k = k;
        self.prev_d = d;
    }

    pub fn populateExitTrend(self: *KDJStrategy, ctx: *StrategyContext) !void {
        const candles = ctx.candles.items;
        if (candles.len < self.k_period + self.d_period) return;

        var stoch = self.stoch.?;
        const result = try stoch.calculate(candles);
        defer result.deinit();

        const k = result.k;
        const d = result.d;

        // Detect crossovers for exit
        if (self.prev_k != null and self.prev_d != null) {
            const k_cross_above_d = self.prev_k.? < self.prev_d.? and k > d;
            const k_cross_below_d = self.prev_k.? > self.prev_d.? and k < d;

            // Exit long: K crosses below D
            if (k_cross_below_d and ctx.hasOpenPosition(.long)) {
                try ctx.addSignal(Signal{
                    .type = .close_long,
                    .strength = 1.0,
                    .indicators = null,
                });
            }

            // Exit short: K crosses above D
            if (k_cross_above_d and ctx.hasOpenPosition(.short)) {
                try ctx.addSignal(Signal{
                    .type = .close_short,
                    .strength = 1.0,
                    .indicators = null,
                });
            }
        }
    }
};
```

#### 注册策略

**文件**: `src/root.zig`

在文件中添加:

```zig
pub const strategy_kdj = @import("strategy/builtin/kdj.zig");
pub const KDJStrategy = strategy_kdj.KDJStrategy;
```

#### 创建配置文件

**文件**: `examples/strategies/kdj.json`

```json
{
  "strategy": "kdj",
  "pair": {
    "base": "BTC",
    "quote": "USDT"
  },
  "timeframe": "h1",
  "parameters": {
    "k_period": 9,
    "d_period": 3,
    "oversold": 20,
    "overbought": 80
  }
}
```

---

### 第 3 步: 回测验证

#### 准备数据

确保有历史数据文件:

```bash
ls data/BTCUSDT_h1_2024.csv
# timestamp,open,high,low,close,volume
# 1704067200000,42150.5,42380.2,42050.0,42250.8,1250.5
# ...
```

#### 运行回测

```bash
zig build run -- strategy backtest \
  --strategy kdj \
  --config examples/strategies/kdj.json \
  --data data/BTCUSDT_h1_2024.csv \
  --output results/kdj_backtest.json
```

#### 分析结果

查看回测输出:

```
================================================================================
                          Backtest Results
================================================================================

Trading Performance
────────────────────────────────────────────────────────────────────────────────
  Total Trades:              32
  Winning Trades:            20 (62.5%)
  Losing Trades:             12 (37.5%)

Profit & Loss
────────────────────────────────────────────────────────────────────────────────
  Initial Capital:           $10,000.00
  Final Capital:             $11,250.00
  Net Profit:                $1,250.00
  Total Return:              12.5%

  Gross Profit:              $1,950.00
  Gross Loss:                -$700.00
  Profit Factor:             2.79

Risk Metrics
────────────────────────────────────────────────────────────────────────────────
  Sharpe Ratio:              1.65
  Sortino Ratio:             2.18
  Maximum Drawdown:          -9.2% ($920.00)

  Average Win:               $97.50
  Average Loss:              -$58.33
  Win/Loss Ratio:            1.67
```

**评估要点**:
- ✅ Sharpe > 1.0: 策略可行
- ✅ Profit Factor > 1.5: 盈亏比合理
- ✅ Win Rate > 50%: 胜率可接受
- ⚠️ Max Drawdown < 15%: 风险可控

---

### 第 4 步: 参数优化

#### 创建优化配置

**文件**: `examples/strategies/kdj_optimize.json`

```json
{
  "strategy": "kdj",
  "parameters": {},
  "backtest": {
    "pair": {"base": "BTC", "quote": "USDT"},
    "timeframe": "h1",
    "data_file": "data/BTCUSDT_h1_2024.csv",
    "initial_capital": 10000,
    "commission_rate": 0.001,
    "slippage": 0.0005
  },
  "optimization": {
    "parameters": {
      "k_period": {
        "min": 7,
        "max": 14,
        "step": 1
      },
      "d_period": {
        "min": 2,
        "max": 5,
        "step": 1
      },
      "oversold": {
        "min": 15,
        "max": 30,
        "step": 5
      },
      "overbought": {
        "min": 70,
        "max": 85,
        "step": 5
      }
    }
  }
}
```

**组合数**: 8 × 4 × 4 × 4 = 512 种组合

#### 运行优化

```bash
zig build run -- strategy optimize \
  --strategy kdj \
  --config examples/strategies/kdj_optimize.json \
  --objective sharpe \
  --top 10 \
  --output results/kdj_optimization.json
```

#### 分析优化结果

```
Rank | k_period | d_period | oversold | overbought | Sharpe | Win Rate
─────┼──────────┼──────────┼──────────┼────────────┼────────┼──────────
  1  |    11    |     3    |    20    |     80     |  1.95  |  65.2%
  2  |    10    |     3    |    20    |     75     |  1.88  |  63.8%
  3  |    12    |     3    |    25    |     80     |  1.82  |  64.5%
  4  |    11    |     4    |    20    |     80     |  1.78  |  62.9%
  5  |     9    |     3    |    15    |     80     |  1.72  |  61.5%
```

**观察**:
- k_period 在 10-12 之间表现较好
- d_period = 3 是最优值
- oversold = 20, overbought = 80 是经典值，表现良好

**选择参数**: k=11, d=3, oversold=20, overbought=80

#### 样本外验证

将数据分为训练集和测试集:

```bash
# 训练集: 2023 年数据
zig build run -- strategy optimize \
  --strategy kdj \
  --config examples/strategies/kdj_optimize.json \
  --data data/BTCUSDT_h1_2023.csv \
  --output results/kdj_train.json

# 测试集: 2024 年数据
# 使用训练集得到的最优参数
zig build run -- strategy backtest \
  --strategy kdj \
  --config examples/strategies/kdj_optimized.json \
  --data data/BTCUSDT_h1_2024.csv \
  --output results/kdj_test.json
```

**对比**:
- 训练集 Sharpe: 1.95
- 测试集 Sharpe: 1.72 (-11.8%)
- ✅ 性能下降 < 20%，泛化能力良好

---

### 第 5 步: 实盘准备 (v0.4.0+)

#### 风险管理

在配置中添加风险参数:

```json
{
  "strategy": "kdj",
  "risk_management": {
    "max_position_size": 0.1,
    "stop_loss": 0.02,
    "take_profit": 0.05,
    "max_daily_loss": 0.05
  }
}
```

#### 监控和告警

设置告警规则:

```json
{
  "alerts": {
    "drawdown_threshold": 0.10,
    "daily_loss_threshold": 0.03,
    "consecutive_losses": 5
  }
}
```

#### 逐步放大

**阶段 1**: 小资金测试 (1-2 周)
```json
{"initial_capital": 100}
```

**阶段 2**: 增加资金 (1 个月)
```json
{"initial_capital": 1000}
```

**阶段 3**: 正式运行
```json
{"initial_capital": 10000}
```

---

## 最佳实践

### 1. 策略设计原则

**KISS 原则** (Keep It Simple, Stupid):
- ✅ 简单清晰的交易逻辑
- ✅ 参数不宜过多 (2-4 个)
- ❌ 避免过度复杂化

**示例**:

```zig
// 好: 简单清晰
if (k_cross_above_d and j < oversold) {
    return Signal.long;
}

// 差: 过度复杂
if (k_cross_above_d and j < oversold and volume > avg_volume * 1.5
    and price > sma50 and rsi < 40 and macd > 0) {
    return Signal.long;
}
```

### 2. 参数范围设置

**合理范围**:
- 基于指标理论
- 基于市场经验
- 避免极端值

**示例**:

```json
// 好: 合理范围
"k_period": {"min": 7, "max": 14, "step": 1}

// 差: 过宽范围
"k_period": {"min": 2, "max": 100, "step": 1}
```

### 3. 避免过拟合

**方法**:
1. 使用足够长的历史数据
2. 样本外验证
3. 减少参数数量
4. 增大参数步长
5. Walk-Forward 分析

### 4. 回测陷阱

**常见陷阱**:
- ❌ 未来函数 (使用未来数据)
- ❌ 忽略滑点和手续费
- ❌ 数据偏差 (幸存者偏差)
- ❌ 过度优化 (曲线拟合)

**避免方法**:
- ✅ 严格的时间顺序
- ✅ 真实的交易成本
- ✅ 样本外测试
- ✅ 参数稳定性分析

### 5. 文档和版本控制

**记录内容**:
- 策略设计文档
- 参数优化记录
- 回测结果
- 实盘表现

**版本控制**:

```bash
git add src/strategy/builtin/kdj.zig
git add examples/strategies/kdj*.json
git commit -m "Add KDJ Stochastic Strategy v1.0"
git tag kdj-v1.0
```

---

## 常见问题

### Q1: 策略在回测中表现好，实盘表现差?

**A**: 可能原因:

1. **过拟合**: 样本外验证性能下降 > 30%
2. **滑点和手续费**: 回测设置不真实
3. **流动性**: 回测未考虑订单簿深度
4. **市场环境变化**: 策略不适应新环境

**解决方案**:
- 样本外测试
- 真实成本设置
- 模拟交易验证
- 持续监控和调整

### Q2: 如何选择技术指标?

**A**: 考虑因素:

1. **策略类型**:
   - 趋势: MA, MACD, ADX
   - 震荡: RSI, Stochastic, Bollinger Bands
   - 动量: MACD, RSI

2. **互补性**: 避免重复信号
   ```
   好: SMA (趋势) + RSI (超买超卖)
   差: SMA + EMA (重复)
   ```

3. **计算效率**: 简单指标优先

### Q3: 参数多少个合适?

**A**: 推荐 2-4 个可优化参数。

**原因**:
- 参数越多，过拟合风险越大
- 优化时间指数增长
- 难以理解和调试

**示例**:
```
2 参数 (10×10): 100 组合 ✅
3 参数 (10×10×10): 1000 组合 ⚠️
4 参数 (10×10×10×10): 10000 组合 ❌
```

### Q4: 如何处理多时间框架?

**A**: v0.3.0 暂不直接支持，可以使用变通方法:

**方法 1**: 手动重采样
```zig
// 将 h1 数据聚合为 h4
pub fn resampleTo4H(candles: []Candle) ![]Candle {
    // Implementation
}
```

**方法 2**: 分别运行不同时间框架
```bash
# h1 短期信号
zig build run -- strategy backtest \
  --config kdj_h1.json

# h4 长期趋势
zig build run -- strategy backtest \
  --config kdj_h4.json
```

### Q5: 策略收益率多少算好?

**A**: 取决于市场和时间框架:

**参考标准** (Sharpe Ratio):
- Sharpe > 2.0: 优秀
- Sharpe > 1.5: 良好
- Sharpe > 1.0: 可接受
- Sharpe > 0.5: 一般
- Sharpe < 0.5: 较差

**其他指标**:
- 年化收益 > 20%: 优秀
- 最大回撤 < 15%: 可控
- 胜率 > 55%: 良好

### Q6: 如何调试策略?

**A**: 调试技巧:

**1. 日志输出**:
```zig
pub fn populateEntryTrend(self: *KDJStrategy, ctx: *StrategyContext) !void {
    const k = result.k;
    const d = result.d;
    const j = result.j;

    std.debug.print("K={d:.2}, D={d:.2}, J={d:.2}\n", .{k, d, j});

    if (k_cross_above_d and j < self.oversold) {
        std.debug.print("LONG SIGNAL!\n", .{});
        // ...
    }
}
```

**2. 保存详细结果**:
```bash
zig build run -- strategy backtest \
  --config config.json \
  --output results/debug.json
```

**3. 分析交易**:
```bash
cat results/debug.json | jq '.trades[] | select(.profit < 0)'
```

---

## 总结

策略开发是一个迭代过程:

```
设计 → 实现 → 回测 → 优化 → 验证 → 实盘
  ↑                                      ↓
  └──────────── 持续改进 ────────────────┘
```

**关键要点**:
1. ✅ 简单清晰的策略逻辑
2. ✅ 充分的回测验证
3. ✅ 严格的参数优化
4. ✅ 样本外测试
5. ✅ 风险管理
6. ✅ 持续监控和改进

**下一步**:
- 尝试实现自己的策略
- 对比不同策略表现
- 组合多个策略 (未来版本)

---

## 相关文档

- [Strategy Framework API](../features/strategy/api.md) - IStrategy 接口详细说明
- [Indicators Library](../features/indicators/README.md) - 内置指标使用
- [CLI Usage Guide](../features/cli/usage-guide.md) - 命令行工具使用
- [Optimizer Guide](../features/optimizer/usage-guide.md) - 参数优化详解

---

**更新时间**: 2024-12-26
**版本**: v0.3.0
