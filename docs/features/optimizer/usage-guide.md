# 参数优化器使用指南

本文档详细介绍 zigQuant 参数优化器的使用方法，包括网格搜索原理、参数配置和结果分析。

---

## 📋 目录

- [概述](#概述)
- [网格搜索原理](#网格搜索原理)
- [快速开始](#快速开始)
- [参数配置](#参数配置)
- [优化目标](#优化目标)
- [结果分析](#结果分析)
- [最佳实践](#最佳实践)
- [高级用法](#高级用法)
- [性能优化](#性能优化)
- [常见问题](#常见问题)

---

## 概述

### 什么是参数优化?

参数优化是通过系统化地测试不同参数组合，找到策略在历史数据上表现最佳的参数配置的过程。

### GridSearchOptimizer

zigQuant 使用网格搜索 (Grid Search) 算法进行参数优化:

**特点**:
- ✅ 全面搜索参数空间 (不会遗漏任何组合)
- ✅ 简单直观，易于理解
- ✅ 支持多种数据类型 (integer, decimal, string)
- ✅ 支持多个优化目标
- ⚠️ 参数多时计算量大 (指数增长)

**适用场景**:
- 参数数量较少 (2-4 个)
- 参数范围明确
- 需要全面了解参数空间
- 对计算时间要求不严格

---

## 网格搜索原理

### 基本概念

网格搜索通过创建参数值的"网格"，测试所有可能的组合。

**示例**:

```
参数 A: [1, 2, 3]
参数 B: [10, 20]

网格:
(A=1, B=10), (A=1, B=20)
(A=2, B=10), (A=2, B=20)
(A=3, B=10), (A=3, B=20)

总共: 3 × 2 = 6 种组合
```

### 算法流程

```
1. 生成参数网格
   ├─ 参数 A: min=5, max=15, step=5 → [5, 10, 15]
   ├─ 参数 B: min=20, max=40, step=10 → [20, 30, 40]
   └─ 笛卡尔积 → 9 种组合

2. 对每种组合运行回测
   ├─ 创建策略实例 (使用当前参数)
   ├─ 运行回测引擎
   └─ 计算性能指标

3. 根据优化目标排序
   └─ 返回 Top N 结果
```

### 计算复杂度

组合数量 = ∏ (参数范围 / 步长 + 1)

**示例**:

| 参数配置 | 组合数 | 预计时间 (假设 100ms/次) |
|---------|-------|------------------------|
| 1 参数 (10 values) | 10 | 1 秒 |
| 2 参数 (10 × 10) | 100 | 10 秒 |
| 3 参数 (10 × 10 × 10) | 1,000 | 100 秒 (~1.7 分钟) |
| 4 参数 (10 × 10 × 10 × 10) | 10,000 | 1,000 秒 (~16.7 分钟) |

---

## 快速开始

### 1. 创建优化配置

**文件**: `dual_ma_optimize.json`

```json
{
  "strategy": "dual_ma",
  "parameters": {
    "ma_type": "sma"
  },
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

### 2. 运行优化

```bash
zig build run -- strategy optimize \
  --strategy dual_ma \
  --config dual_ma_optimize.json
```

### 3. 查看结果

```
=== Parameter Optimization ===
...
Rank | fast_period | slow_period | Sharpe | Net Profit
─────┼─────────────┼─────────────┼────────┼────────────
  1  |     10      |      30     |  2.15  |  $2,450.00
  2  |     15      |      40     |  2.03  |  $2,180.00
  3  |     10      |      40     |  1.95  |  $2,050.00
...

Best Parameters:
  fast_period: 10
  slow_period: 30
```

### 4. 使用最优参数

将最优参数应用到回测配置:

**文件**: `dual_ma_optimized.json`

```json
{
  "strategy": "dual_ma",
  "pair": {"base": "BTC", "quote": "USDT"},
  "timeframe": "h1",
  "parameters": {
    "fast_period": 10,
    "slow_period": 30,
    "ma_type": "sma"
  }
}
```

验证:

```bash
zig build run -- strategy backtest \
  --strategy dual_ma \
  --config dual_ma_optimized.json
```

---

## 参数配置

### 配置结构

```json
{
  "strategy": "...",
  "parameters": {
    // 固定参数 (不优化)
    "param1": value1
  },
  "backtest": {
    // 回测配置
  },
  "optimization": {
    "parameters": {
      // 优化参数
      "param2": {
        "min": ...,
        "max": ...,
        "step": ...
      }
    }
  }
}
```

### 参数类型

#### Integer 参数

用于整数值参数 (周期、阈值等)。

```json
"fast_period": {
  "min": 5,      // 最小值 (包含)
  "max": 20,     // 最大值 (包含)
  "step": 5      // 步长
}
// 生成: [5, 10, 15, 20]
```

**示例参数**:
- MA 周期: `period`
- RSI 周期: `rsi_period`
- 布林带周期: `bb_period`
- K 线数量: `lookback`

#### Decimal 参数

用于小数值参数 (阈值、比率等)。

```json
"rsi_oversold": {
  "min": 20,
  "max": 40,
  "step": 5
}
// 生成: [20.0, 25.0, 30.0, 35.0, 40.0]
```

**示例参数**:
- RSI 阈值: `rsi_oversold`, `rsi_overbought`
- 止损: `stop_loss`
- 止盈: `take_profit`
- 波动率阈值: `volatility_threshold`

#### String 参数

用于枚举类型参数 (类型选择等)。

```json
"ma_type": {
  "values": ["sma", "ema", "wma"]
}
// 生成: ["sma", "ema", "wma"]
```

**注意**: String 参数目前通过固定参数指定，优化时保持不变。如需优化，需要为每种类型创建单独的优化配置。

### 参数范围设置指南

#### 选择合适的范围

**原则**:
1. 基于经验和理论设定初始范围
2. 避免无意义的值 (如 MA 周期 < 2)
3. 考虑计算时间和组合数量平衡

**示例**:

```json
// 双均线策略
{
  "fast_period": {
    "min": 5,      // 短期均线不宜太短
    "max": 20,     // 不宜与慢速均线重叠
    "step": 5      // 粗粒度搜索
  },
  "slow_period": {
    "min": 20,     // 应大于快速均线
    "max": 60,     // 不宜过长
    "step": 10     // 粗粒度搜索
  }
}
// 组合数: 4 × 5 = 20
```

#### 步长选择

**粗粒度搜索** (快速探索):
```json
"period": {"min": 10, "max": 50, "step": 10}
// [10, 20, 30, 40, 50] - 5 个值
```

**细粒度搜索** (精确优化):
```json
"period": {"min": 10, "max": 50, "step": 2}
// [10, 12, 14, ..., 50] - 21 个值
```

**推荐策略**:
1. 先粗粒度搜索找到大致范围
2. 再细粒度搜索精确优化

```bash
# 第一轮: 粗粒度
# fast_period: 5-20 (step 5) → 最优 10
# slow_period: 20-60 (step 10) → 最优 30

# 第二轮: 细粒度
# fast_period: 8-12 (step 1)
# slow_period: 25-35 (step 2)
```

---

## 优化目标

### 可用目标

| 目标 | 说明 | 计算公式 | 适用场景 |
|------|------|---------|---------|
| **sharpe** | Sharpe 比率 | (年化收益 - 无风险利率) / 年化波动率 | 风险调整后收益 (推荐) |
| **profit** | 盈利因子 | 总盈利 / 总亏损 | 盈亏比优化 |
| **winrate** | 胜率 | 盈利交易数 / 总交易数 | 提高成功率 |
| **drawdown** | 最大回撤 | max(峰值 - 谷值) / 峰值 | 风险控制 |
| **netprofit** | 净利润 | 总盈利 - 总亏损 | 绝对收益 |
| **return** | 总回报率 | (最终资金 - 初始资金) / 初始资金 | 百分比收益 |

### 目标详解

#### Sharpe Ratio (推荐)

**公式**:
```
Sharpe = (年化收益率 - 无风险利率) / 年化波动率
```

**优点**:
- 平衡收益和风险
- 适用于大多数策略
- 业界标准指标

**缺点**:
- 假设收益正态分布
- 对异常值敏感

**何时使用**: 默认推荐，适合大多数情况。

**示例**:
```bash
zig build run -- strategy optimize \
  --strategy dual_ma \
  --config config.json \
  --objective sharpe
```

#### Profit Factor

**公式**:
```
Profit Factor = 总盈利 / 总亏损
```

**解读**:
- PF > 2.0: 优秀
- PF > 1.5: 良好
- PF > 1.0: 盈利
- PF < 1.0: 亏损

**优点**:
- 直观易懂
- 关注盈亏比

**缺点**:
- 不考虑风险
- 可能产生高风险策略

**何时使用**: 关注盈亏比，可接受较高风险。

#### Win Rate

**公式**:
```
Win Rate = 盈利交易数 / 总交易数
```

**优点**:
- 简单直观
- 提高心理舒适度

**缺点**:
- 忽略盈亏幅度
- 高胜率可能低盈利

**警告**: 单独优化胜率可能导致"小赚大亏"。

**何时使用**: 配合其他指标，作为辅助参考。

#### Max Drawdown

**公式**:
```
Drawdown = (峰值资金 - 谷值资金) / 峰值资金
```

**优点**:
- 风险度量
- 保护资金

**缺点**:
- 可能牺牲收益
- 过度保守

**何时使用**: 风险厌恶型交易者，资金保护优先。

**示例**:
```bash
zig build run -- strategy optimize \
  --strategy dual_ma \
  --config config.json \
  --objective drawdown  # 最小化回撤
```

#### Net Profit

**公式**:
```
Net Profit = 最终资金 - 初始资金
```

**优点**:
- 直接反映绝对收益
- 易于理解

**缺点**:
- 不考虑风险
- 不考虑资金使用效率

**何时使用**: 关注绝对收益，忽略风险考量。

#### Total Return

**公式**:
```
Total Return = (最终资金 - 初始资金) / 初始资金
```

**优点**:
- 百分比收益
- 便于比较

**缺点**:
- 不考虑风险
- 不考虑时间因素

**何时使用**: 关注百分比收益。

### 目标选择决策树

```
需要风险调整? ──┐
                │
        ┌───YES───┐
        │         │
    时间因素? ──┐
                │
        ┌───YES───→ Sharpe Ratio (推荐)
        │
        └───NO────→ Profit Factor

    风险厌恶? ──┐
                │
        ┌───YES───→ Drawdown
        │
        └───NO────┐
                  │
            绝对收益? ──┐
                        │
                ┌───YES───→ Net Profit
                │
                └───NO────→ Total Return
```

---

## 结果分析

### 结果输出格式

```
================================================================================
                     Optimization Results (Top 10)
================================================================================

Rank | fast_period | slow_period | Sharpe | Profit Factor | Win Rate | Net Profit
─────┼─────────────┼─────────────┼────────┼───────────────┼──────────┼────────────
  1  |     10      |      30     |  2.15  |      3.45     |  68.5%   |  $2,450.00
  2  |     15      |      40     |  2.03  |      3.12     |  65.2%   |  $2,180.00
  3  |     10      |      40     |  1.95  |      2.98     |  64.8%   |  $2,050.00
...
```

### 关键指标解读

#### 1. Rank (排名)

按优化目标排序的序号。

**注意**: 仅根据选定的优化目标排序，其他指标仅供参考。

#### 2. 参数值

显示每组参数的具体值。

**分析要点**:
- 最优参数是否稳定? (多个相近参数表现相似)
- 是否触及边界? (可能需要扩大搜索范围)
- 参数关系? (如快慢均线比例)

#### 3. 性能指标

- **Sharpe**: > 1.5 优秀, > 1.0 良好, < 0.5 较差
- **Profit Factor**: > 2.0 优秀, > 1.5 良好, < 1.2 较差
- **Win Rate**: > 60% 优秀, > 50% 良好, < 45% 较差
- **Net Profit**: 绝对值，结合初始资金评估

### 过拟合检测

#### 什么是过拟合?

策略在历史数据上表现优秀，但在未来数据或实盘交易中表现差。

#### 识别方法

**1. 参数敏感度分析**

检查 Top 10 结果:

```
Rank 1: fast=10, slow=30, Sharpe=2.15
Rank 2: fast=11, slow=31, Sharpe=2.12  ← 参数相近，表现相近 (好)
Rank 3: fast=10, slow=32, Sharpe=2.10  ← 稳定性高

vs

Rank 1: fast=10, slow=30, Sharpe=2.15
Rank 2: fast=18, slow=22, Sharpe=1.25  ← 参数差异大 (可能过拟合)
Rank 3: fast=5, slow=50, Sharpe=0.95
```

**稳定参数**: 相近参数有相近表现 → 泛化能力强
**不稳定参数**: 参数微小变化导致性能剧变 → 可能过拟合

**2. 样本外测试**

将数据分为训练集和测试集:

```bash
# 训练集: 2023-01-01 to 2023-12-31
zig build run -- strategy optimize \
  --config config.json \
  --start "2023-01-01T00:00:00Z" \
  --end "2023-12-31T23:59:59Z"

# 获得最优参数: fast=10, slow=30

# 测试集: 2024-01-01 to 2024-12-31
zig build run -- strategy backtest \
  --config optimized_config.json \
  --start "2024-01-01T00:00:00Z" \
  --end "2024-12-31T23:59:59Z"

# 比较性能下降程度
```

**判断标准**:
- 性能下降 < 20%: 良好泛化
- 性能下降 20-40%: 一定过拟合
- 性能下降 > 40%: 严重过拟合

**3. Walk-Forward 分析** (未来版本)

滚动窗口优化和测试:

```
Training ──→ Testing
[Month 1-6] → [Month 7]
   [Month 2-7] → [Month 8]
      [Month 3-8] → [Month 9]
         ...
```

### 最优参数选择建议

**不要盲目选择 Rank 1!**

**综合考虑**:
1. **稳定性**: 选择 Top 5 中参数相近的组合
2. **一致性**: 多个指标都表现良好
3. **合理性**: 参数符合策略逻辑

**示例**:

```
Rank | fast | slow | Sharpe | Profit | Drawdown
─────┼──────┼──────┼────────┼────────┼──────────
  1  |  10  |  30  |  2.15  |  3.45  |  -6.8%   ← 最优
  2  |  12  |  32  |  2.10  |  3.38  |  -7.2%   ← 相近参数
  3  |  10  |  35  |  2.05  |  3.25  |  -6.5%   ← 相近参数
  4  |  8   |  28  |  2.00  |  3.18  |  -7.5%   ← 相近参数
  5  |  15  |  40  |  1.95  |  3.05  |  -8.2%

推荐: fast=10-12, slow=30-35 (参数稳定区间)
```

---

## 最佳实践

### 1. 分阶段优化

**阶段 1: 粗粒度探索**

```json
{
  "fast_period": {"min": 5, "max": 20, "step": 5},
  "slow_period": {"min": 20, "max": 60, "step": 10}
}
// 组合数: 4 × 5 = 20
```

**阶段 2: 细粒度精化**

基于阶段 1 结果 (假设最优: fast=10, slow=30):

```json
{
  "fast_period": {"min": 8, "max": 12, "step": 1},
  "slow_period": {"min": 25, "max": 35, "step": 2}
}
// 组合数: 5 × 6 = 30
```

### 2. 参数约束

某些参数有逻辑约束 (如快慢均线):

**方法 1**: 手动设置合理范围

```json
{
  "fast_period": {"min": 5, "max": 15, "step": 5},
  "slow_period": {"min": 20, "max": 40, "step": 10}
}
// 确保 slow > fast (通过范围设置)
```

**方法 2**: 后处理过滤无效组合

目前优化器会测试所有组合，包括 fast >= slow 的无效组合。可以在结果中手动过滤。

### 3. 多目标优化

虽然只能选择一个主要优化目标，但可以手动分析多个指标:

```bash
# 优化 Sharpe
zig build run -- strategy optimize \
  --config config.json \
  --objective sharpe \
  --output results_sharpe.json

# 优化 Profit Factor
zig build run -- strategy optimize \
  --config config.json \
  --objective profit \
  --output results_profit.json

# 对比结果，找到平衡点
```

### 4. 样本分割

**时间分割**:

```
全部数据: 2020-2024 (5 年)
├─ 训练集: 2020-2023 (4 年, 80%)
└─ 测试集: 2024 (1 年, 20%)
```

**交叉验证** (手动):

```
Fold 1: Train[2020-2022], Test[2023]
Fold 2: Train[2021-2023], Test[2024]
Fold 3: Train[2020-2021,2023], Test[2022]
```

### 5. 文档记录

记录优化过程和结果:

```markdown
## 优化记录 - Dual MA Strategy

**日期**: 2024-12-26
**数据**: BTCUSDT h1, 2023-01-01 to 2023-12-31
**优化目标**: Sharpe Ratio

### 阶段 1: 粗粒度
- fast: 5-20 (step 5)
- slow: 20-60 (step 10)
- 最优: fast=10, slow=30, Sharpe=2.15

### 阶段 2: 细粒度
- fast: 8-12 (step 1)
- slow: 25-35 (step 2)
- 最优: fast=10, slow=32, Sharpe=2.18

### 测试集验证 (2024-01-01 to 2024-12-31)
- Sharpe: 1.95 (-10.6%, 可接受)
- Profit Factor: 3.12
- Max Drawdown: -7.8%

### 结论
推荐参数: fast=10, slow=32
泛化能力: 良好
```

---

## 高级用法

### 1. 批量优化多个策略

```bash
# 创建脚本
cat > optimize_all.sh <<'EOF'
#!/bin/bash
strategies=("dual_ma" "rsi_mean_reversion" "bollinger_breakout")

for strategy in "${strategies[@]}"; do
  echo "Optimizing $strategy..."
  zig build run -- strategy optimize \
    --strategy "$strategy" \
    --config "configs/${strategy}_optimize.json" \
    --output "results/${strategy}_optimization.json"
done
EOF

chmod +x optimize_all.sh
./optimize_all.sh
```

### 2. 参数空间可视化

优化后，使用脚本生成热力图:

```python
# visualize_results.py
import json
import matplotlib.pyplot as plt
import numpy as np

# 加载结果
with open('results/optimization.json') as f:
    data = json.load(f)

# 提取参数和性能
results = data['all_results']
fast_periods = sorted(set(r['params']['fast_period'] for r in results))
slow_periods = sorted(set(r['params']['slow_period'] for r in results))

# 创建热力图数据
heatmap = np.zeros((len(slow_periods), len(fast_periods)))
for r in results:
    i = slow_periods.index(r['params']['slow_period'])
    j = fast_periods.index(r['params']['fast_period'])
    heatmap[i, j] = r['score']

# 绘制
plt.imshow(heatmap, cmap='RdYlGn', aspect='auto')
plt.colorbar(label='Sharpe Ratio')
plt.xticks(range(len(fast_periods)), fast_periods)
plt.yticks(range(len(slow_periods)), slow_periods)
plt.xlabel('Fast Period')
plt.ylabel('Slow Period')
plt.title('Parameter Optimization Heatmap')
plt.savefig('heatmap.png')
```

### 3. 自动样本外验证

```bash
# optimize_and_validate.sh
#!/bin/bash

STRATEGY="dual_ma"
TRAIN_START="2023-01-01T00:00:00Z"
TRAIN_END="2023-12-31T23:59:59Z"
TEST_START="2024-01-01T00:00:00Z"
TEST_END="2024-12-31T23:59:59Z"

# 1. 训练集优化
echo "Running optimization on training set..."
zig build run -- strategy optimize \
  --strategy "$STRATEGY" \
  --config config.json \
  --start "$TRAIN_START" \
  --end "$TRAIN_END" \
  --output train_results.json

# 2. 提取最优参数 (手动或使用 jq)
# 假设最优: fast=10, slow=30

# 3. 测试集验证
echo "Validating on test set..."
zig build run -- strategy backtest \
  --strategy "$STRATEGY" \
  --config optimized_config.json \
  --start "$TEST_START" \
  --end "$TEST_END" \
  --output test_results.json

# 4. 比较性能
echo "Performance comparison:"
echo "Training Sharpe: $(jq '.best_sharpe' train_results.json)"
echo "Testing Sharpe: $(jq '.performance.sharpe_ratio' test_results.json)"
```

---

## 性能优化

### 减少计算时间

#### 1. 减少参数组合

**方法 A: 增大步长**

```json
// 慢 (121 组合)
{"min": 5, "max": 15, "step": 1}

// 快 (3 组合)
{"min": 5, "max": 15, "step": 5}
```

**方法 B: 缩小范围**

```json
// 大范围
{"min": 5, "max": 50, "step": 5}  // 10 values

// 小范围
{"min": 8, "max": 12, "step": 1}  // 5 values
```

#### 2. 使用较短数据

```bash
# 全年数据 (慢)
--start "2024-01-01T00:00:00Z" --end "2024-12-31T23:59:59Z"

# 半年数据 (快)
--start "2024-07-01T00:00:00Z" --end "2024-12-31T23:59:59Z"
```

**注意**: 数据太少可能导致不可靠的结果。

#### 3. 使用更大时间周期

```bash
# h1 (小时线): 8760 根/年
--timeframe h1

# h4 (4小时线): 2190 根/年
--timeframe h4

# d1 (日线): 365 根/年
--timeframe d1
```

### 预计时间计算

```
总时间 ≈ 组合数 × 单次回测时间

单次回测时间 ≈ K线数量 × 策略复杂度

示例:
- K线: 8760 (h1, 1年)
- 策略: 双均线 (简单)
- 单次: ~100ms
- 组合: 20
- 总时间: 20 × 100ms = 2秒
```

---

## 常见问题

### Q1: 优化结果不稳定怎么办?

**A**: 参数不稳定通常表示过拟合。

**解决方案**:
1. 使用更长时间段数据
2. 增大参数步长
3. 样本外验证
4. 选择稳定参数区间而非单一最优值

### Q2: 所有参数组合表现都很差?

**A**: 可能原因:

1. **策略不适合当前市场**: 尝试其他策略
2. **数据质量问题**: 检查数据完整性
3. **参数范围不合理**: 调整搜索范围
4. **优化目标不匹配**: 尝试其他优化目标

### Q3: 训练集表现好，测试集表现差?

**A**: 典型的过拟合问题。

**解决方案**:
1. 简化策略 (减少参数)
2. 使用更长训练周期
3. 增大参数步长 (减少过拟合风险)
4. Walk-Forward 验证

### Q4: 如何选择数据时间段?

**A**: 建议:

**最小**:
- 日线: 1 年
- 小时线: 6 个月
- 分钟线: 3 个月

**推荐**:
- 日线: 3-5 年
- 小时线: 1-2 年
- 分钟线: 6-12 个月

**原则**:
- 包含不同市场环境 (牛市、熊市、震荡)
- 足够多的交易样本 (> 100 笔)

### Q5: 优化目标应该选择哪个?

**A**: 默认推荐 **Sharpe Ratio**。

**场景选择**:
- 风险厌恶: Drawdown
- 追求高胜率: Win Rate (谨慎)
- 绝对收益: Net Profit
- 盈亏比: Profit Factor

### Q6: 优化后的参数可以直接用于实盘吗?

**A**: **不建议**。

**正确流程**:
1. 历史数据优化 → 找到候选参数
2. 样本外测试 → 验证泛化能力
3. 模拟交易 → 实时环境测试
4. 小资金实盘 → 逐步放大
5. 持续监控 → 定期重新优化

### Q7: 多久重新优化一次?

**A**: 取决于市场和策略:

**趋势策略**:
- 市场环境变化时 (如从牛市转熊市)
- 性能显著下降时
- 季度或半年度审查

**均值回归策略**:
- 更频繁 (如每月)
- 波动率显著变化时

**推荐**: 季度审查，重大市场变化时额外优化。

---

## 相关文档

- [CLI 使用指南](../cli/usage-guide.md) - optimize 命令详细说明
- [Optimizer API](api.md) - GridSearchOptimizer API 文档
- [Backtest Engine](../backtest/README.md) - 回测引擎原理
- [Strategy Framework](../strategy/README.md) - 策略框架概述

---

**更新时间**: 2024-12-26
**版本**: v0.3.0
