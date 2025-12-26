# CLI 策略命令使用指南

本文档详细介绍如何使用 zigQuant CLI 的策略相关命令进行回测、参数优化和实盘交易。

---

## 📋 目录

- [概述](#概述)
- [Backtest 命令](#backtest-命令)
- [Optimize 命令](#optimize-命令)
- [Run-Strategy 命令](#run-strategy-命令)
- [配置文件格式](#配置文件格式)
- [示例场景](#示例场景)
- [常见问题](#常见问题)

---

## 概述

zigQuant 提供三个核心策略命令：

| 命令 | 用途 | 状态 |
|------|------|------|
| `strategy backtest` | 运行策略回测 | ✅ 可用 |
| `strategy optimize` | 参数优化（网格搜索） | ✅ 可用 |
| `strategy run-strategy` | 实盘运行策略 | ⏳ 计划中 (v0.4.0) |

---

## Backtest 命令

### 基本用法

```bash
zig build run -- strategy backtest \
  --strategy <STRATEGY_NAME> \
  --config <CONFIG_FILE> \
  [OPTIONS]
```

### 参数说明

#### 必需参数

| 参数 | 短选项 | 说明 | 示例 |
|------|--------|------|------|
| `--strategy` | `-s` | 策略名称 | `dual_ma`, `rsi_mean_reversion`, `bollinger_breakout` |
| `--config` | `-c` | 策略配置 JSON 文件 | `config.json` |

#### 可选参数

| 参数 | 短选项 | 说明 | 默认值 |
|------|--------|------|--------|
| `--data` | `-d` | 历史数据 CSV 文件 | (从配置文件读取) |
| `--start` | - | 开始时间戳 | (从数据文件读取) |
| `--end` | - | 结束时间戳 | (从数据文件读取) |
| `--capital` | - | 初始资金 | `10000` |
| `--commission` | - | 手续费率 | `0.001` (0.1%) |
| `--slippage` | - | 滑点 | `0.0005` (0.05%) |
| `--output` | `-o` | 保存结果到 JSON 文件 | (不保存) |
| `--help` | `-h` | 显示帮助信息 | - |

### 示例

#### 1. 基本回测

```bash
zig build run -- strategy backtest \
  --strategy dual_ma \
  --config examples/strategies/dual_ma.json
```

#### 2. 使用外部数据文件

```bash
zig build run -- strategy backtest \
  --strategy dual_ma \
  --config examples/strategies/dual_ma.json \
  --data data/BTCUSDT_h1_2024.csv
```

#### 3. 自定义回测参数

```bash
zig build run -- strategy backtest \
  --strategy rsi_mean_reversion \
  --config examples/strategies/rsi_mr.json \
  --capital 50000 \
  --commission 0.002 \
  --slippage 0.001
```

#### 4. 保存回测结果

```bash
zig build run -- strategy backtest \
  --strategy bollinger_breakout \
  --config examples/strategies/bb_breakout.json \
  --output results/bb_backtest_2024.json
```

### 输出示例

```
=== Strategy Backtest ===
Strategy: Dual Moving Average Strategy
Pair: BTC-USDT
Timeframe: h1 (1 hour)
Period: 2024-01-01 00:00:00 to 2024-12-31 23:59:59 (365 days)

Loading data from: data/BTCUSDT_h1_2024.csv
Loaded 8760 candles

Running backtest...

================================================================================
                          Backtest Results
================================================================================

Trading Performance
────────────────────────────────────────────────────────────────────────────────
  Total Trades:              42
  Winning Trades:            28 (66.67%)
  Losing Trades:             14 (33.33%)

Profit & Loss
────────────────────────────────────────────────────────────────────────────────
  Initial Capital:           $10,000.00
  Final Capital:             $11,600.00
  Net Profit:                $1,600.00
  Total Return:              16.00%

  Gross Profit:              $2,300.00
  Gross Loss:                -$700.00
  Profit Factor:             3.29

Risk Metrics
────────────────────────────────────────────────────────────────────────────────
  Sharpe Ratio:              1.85
  Sortino Ratio:             2.43
  Maximum Drawdown:          -8.5% ($850.00)

  Average Win:               $82.14
  Average Loss:              -$50.00
  Win/Loss Ratio:            1.64

Trade Statistics
────────────────────────────────────────────────────────────────────────────────
  Best Trade:                $245.00 (2.45%)
  Worst Trade:               -$125.00 (-1.25%)
  Average Trade:             $38.10

  Average Trade Duration:    18.5 hours
  Max Consecutive Wins:      7
  Max Consecutive Losses:    3

================================================================================
Backtest completed in 1.23s
Results saved to: results/dual_ma_backtest.json
================================================================================
```

---

## Optimize 命令

### 基本用法

```bash
zig build run -- strategy optimize \
  --strategy <STRATEGY_NAME> \
  --config <CONFIG_FILE> \
  [OPTIONS]
```

### 参数说明

#### 必需参数

| 参数 | 短选项 | 说明 | 示例 |
|------|--------|------|------|
| `--strategy` | `-s` | 策略名称 | `dual_ma` |
| `--config` | `-c` | 包含参数范围的配置文件 | `optimize_config.json` |

#### 可选参数

| 参数 | 短选项 | 说明 | 默认值 |
|------|--------|------|--------|
| `--data` | `-d` | 历史数据 CSV 文件 | (从配置读取) |
| `--start` | - | 开始时间戳 | (从数据读取) |
| `--end` | - | 结束时间戳 | (从数据读取) |
| `--capital` | - | 初始资金 | `10000` |
| `--commission` | - | 手续费率 | `0.001` |
| `--slippage` | - | 滑点 | `0.0005` |
| `--objective` | - | 优化目标 | `sharpe` |
| `--top` | - | 显示前 N 个结果 | `10` |
| `--output` | `-o` | 保存结果到 JSON | (不保存) |
| `--help` | `-h` | 显示帮助 | - |

#### 优化目标 (--objective)

| 值 | 说明 | 适用场景 |
|-----|------|---------|
| `sharpe` | 最大化 Sharpe 比率 | 风险调整后收益 (默认推荐) |
| `profit` | 最大化盈利因子 | 盈利交易 vs 亏损交易比率 |
| `winrate` | 最大化胜率 | 提高交易成功率 |
| `drawdown` | 最小化最大回撤 | 降低风险 |
| `netprofit` | 最大化净利润 | 绝对收益 |
| `return` | 最大化总回报率 | 百分比收益 |

### 示例

#### 1. 基本参数优化

```bash
zig build run -- strategy optimize \
  --strategy dual_ma \
  --config examples/strategies/dual_ma_optimize.json
```

#### 2. 自定义优化目标

```bash
# 优化盈利因子
zig build run -- strategy optimize \
  --strategy dual_ma \
  --config examples/strategies/dual_ma_optimize.json \
  --objective profit

# 最小化回撤
zig build run -- strategy optimize \
  --strategy dual_ma \
  --config examples/strategies/dual_ma_optimize.json \
  --objective drawdown
```

#### 3. 显示更多结果

```bash
zig build run -- strategy optimize \
  --strategy dual_ma \
  --config examples/strategies/dual_ma_optimize.json \
  --top 20
```

#### 4. 保存优化结果

```bash
zig build run -- strategy optimize \
  --strategy dual_ma \
  --config examples/strategies/dual_ma_optimize.json \
  --output results/dual_ma_optimization.json
```

### 输出示例

```
=== Parameter Optimization ===
Strategy: Dual Moving Average Strategy
Pair: BTC-USDT
Timeframe: h1
Optimization Objective: Sharpe Ratio

Parameter Ranges:
  fast_period: 5 to 15 (step: 5)
  slow_period: 20 to 40 (step: 10)

Total Combinations: 9

Loading data from: data/BTCUSDT_h1_2024.csv
Loaded 8760 candles

Running grid search optimization...
Progress: [=========================================] 9/9 (100%)

================================================================================
                     Optimization Results (Top 10)
================================================================================

Rank | fast_period | slow_period | Sharpe | Profit Factor | Win Rate | Net Profit
─────┼─────────────┼─────────────┼────────┼───────────────┼──────────┼────────────
  1  |     10      |      30     |  2.15  |      3.45     |  68.5%   |  $2,450.00
  2  |     15      |      40     |  2.03  |      3.12     |  65.2%   |  $2,180.00
  3  |     10      |      40     |  1.95  |      2.98     |  64.8%   |  $2,050.00
  4  |      5      |      30     |  1.87  |      2.85     |  63.1%   |  $1,920.00
  5  |     15      |      30     |  1.76  |      2.67     |  61.5%   |  $1,780.00
  6  |      5      |      40     |  1.65  |      2.52     |  59.8%   |  $1,650.00
  7  |     10      |      20     |  1.52  |      2.34     |  58.2%   |  $1,480.00
  8  |     15      |      20     |  1.38  |      2.18     |  56.5%   |  $1,320.00
  9  |      5      |      20     |  1.24  |      2.05     |  54.8%   |  $1,180.00

================================================================================
Best Parameters:
  fast_period: 10
  slow_period: 30

Performance:
  Sharpe Ratio: 2.15
  Profit Factor: 3.45
  Win Rate: 68.5%
  Net Profit: $2,450.00
  Total Return: 24.5%
  Max Drawdown: -6.8%

Optimization completed in 2.45s (avg 272ms per combination)
Results saved to: results/dual_ma_optimization.json
================================================================================
```

---

## Run-Strategy 命令

### 状态

⏳ **计划中** - 此命令将在 v0.4.0 版本中实现。

### 计划用法

```bash
# 实盘交易 (未来版本)
zig build run -- strategy run-strategy \
  --strategy dual_ma \
  --config config.json \
  --live

# 模拟交易 (未来版本)
zig build run -- strategy run-strategy \
  --strategy dual_ma \
  --config config.json \
  --paper
```

### 当前行为

运行此命令会显示提示信息:

```
⚠️  实盘交易功能尚未实现

此功能需要完整的实盘交易基础设施，计划在 v0.4.0 版本中实现。

当前可用功能:
  - strategy backtest  : 运行策略回测
  - strategy optimize  : 参数优化

请使用 backtest 命令测试您的策略。
```

---

## 配置文件格式

### Backtest 配置文件

**文件**: `dual_ma.json`

```json
{
  "strategy": "dual_ma",
  "pair": {
    "base": "BTC",
    "quote": "USDT"
  },
  "timeframe": "h1",
  "parameters": {
    "fast_period": 10,
    "slow_period": 20,
    "ma_type": "sma"
  },
  "backtest": {
    "data_file": "data/BTCUSDT_h1_2024.csv",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z",
    "initial_capital": 10000,
    "commission_rate": 0.001,
    "slippage": 0.0005
  }
}
```

### Optimize 配置文件

**文件**: `dual_ma_optimize.json`

```json
{
  "strategy": "dual_ma",
  "parameters": {
    "ma_type": "sma"
  },
  "backtest": {
    "pair": {
      "base": "BTC",
      "quote": "USDT"
    },
    "timeframe": "h1",
    "data_file": "data/BTCUSDT_h1_2024.csv",
    "initial_capital": 10000,
    "commission_rate": 0.001,
    "slippage": 0.0005
  },
  "optimization": {
    "parameters": {
      "fast_period": {
        "min": 5,
        "max": 15,
        "step": 5
      },
      "slow_period": {
        "min": 20,
        "max": 40,
        "step": 10
      }
    }
  }
}
```

### 配置字段说明

#### 通用字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `strategy` | string | ✅ | 策略名称 |
| `pair.base` | string | ✅ | 基础货币 |
| `pair.quote` | string | ✅ | 计价货币 |
| `timeframe` | string | ✅ | 时间周期 (`m1`, `m5`, `m15`, `m30`, `h1`, `h4`, `d1`, `w1`) |
| `parameters` | object | ✅ | 策略参数 (固定值) |

#### Backtest 配置字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `backtest.data_file` | string | ⏳ | CSV 数据文件路径 |
| `backtest.start_time` | string | ⏳ | 开始时间 (ISO 8601) |
| `backtest.end_time` | string | ⏳ | 结束时间 (ISO 8601) |
| `backtest.initial_capital` | number | ⏳ | 初始资金 |
| `backtest.commission_rate` | number | ⏳ | 手续费率 |
| `backtest.slippage` | number | ⏳ | 滑点 |

#### Optimization 配置字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `optimization.parameters.<name>.min` | number | ✅ | 最小值 |
| `optimization.parameters.<name>.max` | number | ✅ | 最大值 |
| `optimization.parameters.<name>.step` | number | ✅ | 步长 |

---

## 示例场景

### 场景 1: 快速回测验证

**目标**: 验证策略在历史数据上的表现

```bash
# 1. 使用默认配置运行回测
zig build run -- strategy backtest \
  --strategy dual_ma \
  --config examples/strategies/dual_ma.json

# 2. 查看结果并调整参数
# 编辑 dual_ma.json，修改 fast_period 和 slow_period

# 3. 重新运行回测
zig build run -- strategy backtest \
  --strategy dual_ma \
  --config examples/strategies/dual_ma.json
```

### 场景 2: 参数优化工作流

**目标**: 找到最优参数组合

```bash
# 1. 创建优化配置文件
cat > my_optimize.json <<EOF
{
  "strategy": "dual_ma",
  "parameters": {"ma_type": "ema"},
  "backtest": {
    "pair": {"base": "ETH", "quote": "USDT"},
    "timeframe": "h4",
    "data_file": "data/ETHUSDT_h4_2024.csv"
  },
  "optimization": {
    "parameters": {
      "fast_period": {"min": 8, "max": 20, "step": 4},
      "slow_period": {"min": 25, "max": 50, "step": 5}
    }
  }
}
EOF

# 2. 运行优化
zig build run -- strategy optimize \
  --strategy dual_ma \
  --config my_optimize.json \
  --objective sharpe \
  --top 5

# 3. 使用最优参数回测
# 从优化结果中获取最优参数，更新 backtest 配置
cat > my_backtest.json <<EOF
{
  "strategy": "dual_ma",
  "pair": {"base": "ETH", "quote": "USDT"},
  "timeframe": "h4",
  "parameters": {
    "fast_period": 12,
    "slow_period": 35,
    "ma_type": "ema"
  }
}
EOF

# 4. 验证最优参数
zig build run -- strategy backtest \
  --strategy dual_ma \
  --config my_backtest.json \
  --data data/ETHUSDT_h4_2024.csv
```

### 场景 3: 多策略对比

**目标**: 对比不同策略的表现

```bash
# 测试双均线策略
zig build run -- strategy backtest \
  --strategy dual_ma \
  --config examples/strategies/dual_ma.json \
  --output results/dual_ma_results.json

# 测试 RSI 均值回归策略
zig build run -- strategy backtest \
  --strategy rsi_mean_reversion \
  --config examples/strategies/rsi_mr.json \
  --output results/rsi_mr_results.json

# 测试布林带突破策略
zig build run -- strategy backtest \
  --strategy bollinger_breakout \
  --config examples/strategies/bb_breakout.json \
  --output results/bb_breakout_results.json

# 对比结果 (手动或使用脚本)
cat results/*_results.json | jq '.performance'
```

---

## 常见问题

### Q1: 如何准备历史数据?

**A**: 历史数据应为 CSV 格式，包含以下列:

```csv
timestamp,open,high,low,close,volume
1704067200000,42150.5,42380.2,42050.0,42250.8,1250.5
1704070800000,42250.8,42450.0,42180.0,42380.5,1350.2
...
```

- `timestamp`: Unix 毫秒时间戳
- `open/high/low/close`: OHLC 价格
- `volume`: 成交量 (可选)

### Q2: 优化器运行很慢怎么办?

**A**: 优化性能取决于:
1. 参数组合数量 (减小范围或增大步长)
2. 数据量 (使用较短时间段或更大时间周期)
3. 策略复杂度

**优化建议**:
```json
// 较快: 9 种组合
"fast_period": {"min": 5, "max": 15, "step": 5},
"slow_period": {"min": 20, "max": 40, "step": 10}

// 较慢: 55 种组合
"fast_period": {"min": 5, "max": 15, "step": 1},
"slow_period": {"min": 20, "max": 40, "step": 1}
```

### Q3: 如何选择优化目标?

**A**: 根据交易目标选择:

- **Sharpe Ratio** (推荐): 平衡收益和风险
- **Profit Factor**: 重视盈亏比
- **Win Rate**: 重视成功率 (可能牺牲盈亏比)
- **Drawdown**: 保守策略，控制风险
- **Net Profit**: 追求绝对收益
- **Total Return**: 追求百分比收益

### Q4: 配置文件中哪些字段可以被命令行参数覆盖?

**A**: 以下字段可以被命令行参数覆盖:

| 配置字段 | 命令行参数 |
|---------|-----------|
| `backtest.data_file` | `--data` |
| `backtest.start_time` | `--start` |
| `backtest.end_time` | `--end` |
| `backtest.initial_capital` | `--capital` |
| `backtest.commission_rate` | `--commission` |
| `backtest.slippage` | `--slippage` |
| - | `--objective` (仅 optimize) |

### Q5: 错误 "Strategy not found" 如何解决?

**A**: 确保策略名称正确:

可用策略:
- `dual_ma` - 双均线策略
- `rsi_mean_reversion` - RSI 均值回归策略
- `bollinger_breakout` - 布林带突破策略

检查配置文件中的 `strategy` 字段和命令行 `--strategy` 参数是否匹配。

### Q6: 如何调试策略?

**A**: 使用回测命令并检查详细输出:

```bash
# 运行回测
zig build run -- strategy backtest \
  --strategy dual_ma \
  --config config.json

# 查看交易详情
# 检查输出中的 "Trade Statistics" 部分
# 必要时保存结果到 JSON 进行详细分析

zig build run -- strategy backtest \
  --strategy dual_ma \
  --config config.json \
  --output debug_results.json

# 分析结果
cat debug_results.json | jq '.trades[] | select(.profit < 0)'
```

---

## 相关文档

- [参数优化器使用指南](../optimizer/usage-guide.md) - 详细的优化器使用说明
- [策略开发教程](../../tutorials/strategy-development.md) - 创建自定义策略
- [Backtest Engine API](../backtest/api.md) - 回测引擎 API 文档
- [Strategy Framework](../strategy/README.md) - 策略框架概述

---

**更新时间**: 2024-12-26
**版本**: v0.3.0
