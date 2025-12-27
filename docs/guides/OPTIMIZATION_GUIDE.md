# Optimization Guide - 参数优化指南

**版本**: v0.4.0
**更新时间**: 2025-12-27

---

## 目录

1. [快速开始](#快速开始)
2. [优化目标](#优化目标)
3. [参数配置](#参数配置)
4. [Walk-Forward 分析](#walk-forward-分析)
5. [并行优化](#并行优化)
6. [过拟合检测](#过拟合检测)
7. [最佳实践](#最佳实践)

---

## 快速开始

### 1. 运行基本优化

```bash
zig build run -- optimize \
  --strategy dual_ma \
  --data data/BTCUSDT_1h_2024.csv \
  --objective sharpe
```

### 2. 查看优化结果

```
╔════════════════════════════════════════════════╗
║           Optimization Results                  ║
╠════════════════════════════════════════════════╣
║ Tested Combinations: 64                         ║
║ Best Parameters:                                ║
║   fast_period: 10                               ║
║   slow_period: 30                               ║
║ Best Sharpe Ratio: 1.92                         ║
╚════════════════════════════════════════════════╝
```

---

## 优化目标

### 基础目标 (v0.3.0)

| 目标 | 说明 | 适用场景 |
|------|------|---------|
| `sharpe` | 夏普比率 | 平衡收益与风险 |
| `profit_factor` | 盈亏比 | 关注交易质量 |
| `win_rate` | 胜率 | 追求高胜率 |
| `max_drawdown` | 最大回撤 | 控制风险 |
| `net_profit` | 净利润 | 追求绝对收益 |
| `total_return` | 总收益率 | 追求百分比收益 |

### 高级目标 (v0.4.0 NEW)

| 目标 | 说明 | 公式 |
|------|------|------|
| `sortino` | 索提诺比率 | 只考虑下行风险 |
| `calmar` | 卡尔玛比率 | 年化收益/最大回撤 |
| `omega` | 欧米茄比率 | 收益/损失概率 |
| `tail` | 尾部比率 | 极端收益/极端损失 |
| `stability` | 稳定性得分 | 权益曲线R² |
| `risk_adjusted` | 风险调整收益 | 收益×(1-回撤) |

### 使用方法

```bash
# 最大化夏普比率
zig build run -- optimize --objective sharpe

# 最大化索提诺比率 (v0.4.0)
zig build run -- optimize --objective sortino

# 最大化稳定性 (v0.4.0)
zig build run -- optimize --objective stability
```

---

## 参数配置

### 参数定义文件

创建 JSON 配置文件定义参数范围：

```json
{
  "strategy": "dual_ma",
  "parameters": {
    "fast_period": {
      "type": "integer",
      "min": 5,
      "max": 20,
      "step": 5
    },
    "slow_period": {
      "type": "integer",
      "min": 20,
      "max": 60,
      "step": 10
    }
  }
}
```

### 参数类型

| 类型 | 说明 | 示例 |
|------|------|------|
| `integer` | 整数 | `5, 10, 15, 20` |
| `decimal` | 小数 | `0.1, 0.2, 0.3` |
| `boolean` | 布尔值 | `true, false` |
| `discrete` | 离散值 | `["sma", "ema"]` |

### 组合数计算

```
总组合数 = ∏ (max - min) / step + 1

示例:
fast_period: (20-5)/5 + 1 = 4 个值
slow_period: (60-20)/10 + 1 = 5 个值
总组合: 4 × 5 = 20 组合
```

---

## Walk-Forward 分析

### 概念

Walk-Forward 分析将数据分为训练集和测试集，避免过拟合：

```
|-------- Training --------|-- Test --|
|-------- Training --------|-- Test --|
|-------- Training --------|-- Test --|
```

### 使用方法 (v0.4.0)

```bash
zig build run -- optimize \
  --strategy dual_ma \
  --data data/BTCUSDT_1h_2024.csv \
  --walk-forward \
  --train-ratio 0.7 \
  --windows 5
```

### 数据分割模式

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| `fixed` | 固定窗口 | 稳定市场 |
| `rolling` | 滚动窗口 | 持续验证 |
| `expanding` | 扩展窗口 | 增量学习 |
| `anchored` | 锚定窗口 | 长期验证 |

### 代码示例

```zig
const walk_forward = zigQuant.WalkForwardAnalyzer.init(allocator, .{
    .split_mode = .rolling,
    .train_ratio = 0.7,
    .num_windows = 5,
});

const results = try walk_forward.analyze(optimizer, strategy, data);

// 检查过拟合
if (results.overfitting_detected) {
    std.debug.print("Warning: Overfitting detected!\n", .{});
}
```

---

## 并行优化

### 启用并行 (v0.4.0)

```bash
zig build run -- optimize \
  --strategy dual_ma \
  --data data/BTCUSDT_1h_2024.csv \
  --parallel \
  --threads 8
```

### 性能对比

| 组合数 | 顺序执行 | 8线程并行 | 加速比 |
|--------|----------|-----------|--------|
| 100 | 10s | 1.3s | 7.7x |
| 500 | 50s | 6.5s | 7.7x |
| 1000 | 100s | 13s | 7.7x |

### 代码示例

```zig
// 创建带线程池的优化器
var optimizer = try zigQuant.GridSearchOptimizer.initWithThreads(
    allocator,
    config,
    8,  // 使用 8 个线程
);
defer optimizer.deinit();

// 运行并行优化
const result = try optimizer.optimizeParallelTyped(
    createStrategy,
    progressCallback,  // 进度回调
);
```

### 进度跟踪

```zig
fn progressCallback(completed: usize, total: usize) void {
    const pct = @as(f64, @floatFromInt(completed)) /
                @as(f64, @floatFromInt(total)) * 100.0;
    std.debug.print("\rProgress: {d}/{d} ({d:.1}%)", .{ completed, total, pct });
}
```

---

## 过拟合检测

### 检测方法 (v0.4.0)

1. **训练/测试差距分析**
   - 比较训练集和测试集性能
   - 差距过大表示过拟合

2. **稳定性分析**
   - 计算权益曲线的 R² 值
   - R² < 0.8 可能存在问题

3. **参数敏感度**
   - 检查相邻参数的性能变化
   - 变化过大表示不稳定

### 使用方法

```zig
const detector = zigQuant.OverfittingDetector.init(allocator, .{
    .max_performance_gap = 0.3,  // 最大允许差距 30%
    .min_stability = 0.8,        // 最小稳定性
});

const report = try detector.analyze(train_result, test_result);

if (report.is_overfitted) {
    std.debug.print("Overfitting detected:\n", .{});
    std.debug.print("  Performance gap: {d:.1}%\n", .{ report.gap * 100 });
    std.debug.print("  Stability score: {d:.2}\n", .{ report.stability });
}
```

### 报告指标

| 指标 | 说明 | 警告阈值 |
|------|------|---------|
| `performance_gap` | 训练/测试性能差距 | > 30% |
| `stability_score` | 权益曲线稳定性 | < 0.8 |
| `parameter_sensitivity` | 参数敏感度 | > 0.5 |

---

## 最佳实践

### 1. 数据分割

```
总数据
├── 训练集 (60%) - 用于优化
├── 验证集 (20%) - 用于验证
└── 测试集 (20%) - 最终评估
```

### 2. 参数范围

- 使用合理的参数范围
- 避免极端值
- 步长不要太小

```json
{
  "fast_period": {
    "min": 5,      // 不要太小
    "max": 50,     // 不要太大
    "step": 5      // 合理步长
  }
}
```

### 3. 组合数控制

- 建议 < 1000 组合
- 超过 1000 使用并行优化
- 超过 10000 考虑采样

### 4. 验证策略

1. 先用 Walk-Forward 验证
2. 检查过拟合指标
3. 在独立测试集上验证
4. 考虑不同市场周期

### 5. 文档记录

记录每次优化的：
- 使用的数据范围
- 参数配置
- 最佳结果
- 验证结果

---

## 常见问题

### Q: 优化结果在实盘表现不佳?

可能原因：
- 过拟合历史数据
- 市场条件变化
- 交易成本未充分考虑

解决方案：
- 使用 Walk-Forward 分析
- 增加样本外测试
- 设置真实交易成本

### Q: 优化速度太慢?

解决方案：
- 使用并行优化
- 减少参数组合数
- 增大参数步长

### Q: 如何选择优化目标?

建议：
- 一般情况用 `sharpe`
- 控制风险用 `max_drawdown`
- 追求稳定用 `stability`

---

## 相关文档

- [回测指南](./BACKTEST_GUIDE.md) - 回测使用
- [优化器文档](../features/optimizer/README.md) - 详细API
- [Walk-Forward 详解](../stories/v0.4.0/STORY_022_OPTIMIZER_ENHANCEMENT.md) - 实现细节

---

**版本**: v0.4.0
**状态**: ✅ 完成
**更新时间**: 2025-12-27
