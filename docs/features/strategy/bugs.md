# Strategy Framework 已知问题

**版本**: v0.3.0
**更新时间**: 2025-12-25

---

## 📋 Bug 追踪

当前无已知 Bug（模块尚未实现）。

此文件将记录策略框架实现过程中发现的 Bug。

---

## Bug 报告模板

```markdown
### BUG-XXX: [简短描述]

**严重程度**: Critical / High / Medium / Low
**状态**: Open / In Progress / Fixed / Won't Fix
**发现时间**: YYYY-MM-DD
**报告人**: [姓名]

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

#### 环境

- Zig 版本: 0.15.2
- OS: Linux/macOS/Windows
- 平台: x86_64

#### 相关代码

```zig
// 相关代码片段
```

#### 临时解决方案

[如果有临时解决方案]

#### 根本原因

[分析根本原因]

#### 修复方案

[修复计划]

#### 修复提交

Commit: `[commit hash]`
PR: `[PR number]`
Fixed in: `v0.3.x`

---
```

## 历史 Bug

### BUG-001: [示例] 指标缓存未失效

**严重程度**: High
**状态**: Fixed
**发现时间**: 2025-12-25
**报告人**: 示例

#### 描述

IndicatorManager 的缓存在蜡烛数据更新后未失效，导致策略使用旧的指标值。

#### 重现步骤

1. 创建策略并计算指标
2. 添加新蜡烛
3. 再次调用 `populateIndicators()`
4. 指标值仍然是旧的

#### 预期行为

新蜡烛添加后，指标应该重新计算。

#### 实际行为

指标值来自缓存，未包含新蜡烛。

#### 根本原因

IndicatorManager 只检查 `last_candle_count`，但在实时模式下，蜡烛数组长度可能不变（只是最后一根蜡烛更新）。

#### 修复方案

添加蜡烛哈希检查：

```zig
const CachedIndicator = struct {
    values: []Decimal,
    last_candle_count: usize,
    candles_hash: u64,  // 新增: 蜡烛数据哈希
};

pub fn getIndicator(...) ![]Decimal {
    const current_hash = hashCandles(candles);

    if (self.cache.get(name)) |cached| {
        if (cached.last_candle_count == candles.len and cached.candles_hash == current_hash) {
            return cached.values;
        }
        // ...
    }
    // ...
}
```

#### 修复提交

Commit: `abc123def`
Fixed in: `v0.3.1`

---

**注意**: 以上为示例，实际 Bug 将在实现过程中记录。

---

**版本**: v0.3.0
**状态**: 设计阶段
**更新时间**: 2025-12-25
