# Technical Indicators Library 已知问题

**版本**: v0.3.0
**更新时间**: 2025-12-25

---

## 📋 Bug 追踪

当前无已知 Bug（模块尚未实现）。

此文件将记录技术指标库实现过程中发现的 Bug。

---

## Bug 报告模板

```markdown
### BUG-IND-XXX: [简短描述]

**严重程度**: Critical / High / Medium / Low
**状态**: Open / In Progress / Fixed / Won't Fix
**发现时间**: YYYY-MM-DD
**报告人**: [姓名]
**影响指标**: SMA / EMA / RSI / MACD / BB / All

#### 描述

[详细描述问题]

#### 重现步骤

1. 步骤 1
2. 步骤 2
3. ...

#### 预期行为

[应该发生什么]

#### 实际行为

[实际发生了什么]

#### 测试数据

```zig
const candles = [_]Candle{
    .{ .close = try Decimal.fromInt(100), ... },
    // ...
};
```

#### 预期结果 vs 实际结果

| Index | 预期值 | 实际值 | 误差 |
|-------|--------|--------|------|
| 0 | NaN | NaN | - |
| 10 | 100.5 | 100.3 | 0.2% |

#### 参考值来源

- TA-Lib
- TradingView
- 手工计算

#### 根本原因

[分析根本原因]

#### 修复方案

[修复计划]

#### 修复提交

Commit: `[commit hash]`
Fixed in: `v0.3.x`

---
```

## 历史 Bug

### BUG-IND-001: [示例] RSI 计算精度问题

**严重程度**: Medium
**状态**: Fixed
**发现时间**: 2025-12-25
**报告人**: 示例
**影响指标**: RSI

#### 描述

RSI 计算结果与 TA-Lib 参考值存在 1-2% 的误差。

#### 重现步骤

1. 使用标准测试数据（14 个连续上涨的价格）
2. 计算 RSI(14)
3. 与 TA-Lib 结果对比

#### 预期行为

RSI 值应与 TA-Lib 结果误差 < 0.1%

#### 实际行为

最后一个 RSI 值: 72.3（TA-Lib: 70.5），误差 2.5%

#### 根本原因

使用简单平均计算 Average Gain/Loss，而非指数移动平均（EMA）。

标准 RSI 计算应使用 Wilder's Smoothing（一种特殊的 EMA）：

```
First Average Gain = Sum(Gains) / period
First Average Loss = Sum(Losses) / period

Subsequent Average Gain = (Previous Average Gain × (period - 1) + Current Gain) / period
Subsequent Average Loss = (Previous Average Loss × (period - 1) + Current Loss) / period
```

#### 修复方案

将 `calculateEMA()` 改为 `calculateWildersSmoothing()`:

```zig
fn calculateWildersSmoothing(self: RSI, values: []Decimal) ![]Decimal {
    var result = try self.allocator.alloc(Decimal, values.len);

    // 第一个值使用简单平均
    var sum = Decimal.ZERO;
    for (0..self.period) |i| {
        sum = try sum.add(values[i]);
    }
    result[self.period - 1] = try sum.div(try Decimal.fromInt(self.period));

    // 后续值使用 Wilder's Smoothing
    const period_dec = try Decimal.fromInt(self.period);
    const period_minus_1 = try Decimal.fromInt(self.period - 1);

    for (self.period..values.len) |i| {
        const prev_avg = result[i - 1];
        const curr_value = values[i];

        const term1 = try prev_avg.mul(period_minus_1);
        const term2 = try term1.add(curr_value);
        result[i] = try term2.div(period_dec);
    }

    return result;
}
```

#### 修复提交

Commit: `abc123def`
Fixed in: `v0.3.1`

---

## 常见问题

### Q1: 为什么前几个指标值是 NaN？

**A**: 大多数指标需要一定数量的历史数据才能计算。例如 SMA(20) 需要至少 20 根蜡烛。前 19 个值无法计算，因此返回 NaN。

这是正常行为，与 TA-Lib 一致。

### Q2: 指标值与 TradingView 有细微差异？

**A**: 可能的原因：
1. TradingView 使用不同的默认参数
2. 数据源不同（不同交易所的价格可能有差异）
3. 时间对齐问题（蜡烛的开始/结束时间）

建议使用 TA-Lib 作为权威参考。

### Q3: 如何验证指标计算的正确性？

**A**:
1. 使用标准测试数据（来自 TA-Lib 文档）
2. 对比 TA-Lib 的计算结果
3. 手工计算小样本数据
4. 使用多个数据源交叉验证

---

## 性能问题追踪

### PERF-IND-001: [示例] MACD 计算过慢

**状态**: Optimized
**优化前**: 1200μs (1000 candles)
**优化后**: 750μs (1000 candles)
**提升**: 37.5%

#### 优化方法

重用 EMA 计算结果，避免重复计算：

```zig
// 优化前: 分别计算 fast_ema 和 slow_ema
const fast_ema = try EMA.init(allocator, 12).calculate(candles);
const slow_ema = try EMA.init(allocator, 26).calculate(candles);

// 优化后: 一次遍历计算两个 EMA
const ema_result = try calculateDualEMA(candles, 12, 26);
```

---

**注意**: 以上为示例，实际 Bug 和性能问题将在实现过程中记录。

---

**版本**: v0.3.0
**状态**: 设计阶段
**更新时间**: 2025-12-25
