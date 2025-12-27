# Inventory Management 实现细节

> 库存管理模块的内部实现文档

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 目录

1. [架构概述](#架构概述)
2. [数据结构](#数据结构)
3. [核心算法](#核心算法)
4. [偏斜计算](#偏斜计算)
5. [报价调整](#报价调整)
6. [再平衡机制](#再平衡机制)
7. [性能优化](#性能优化)

---

## 架构概述

### 模块结构

```
src/market_making/
├── inventory.zig          # 库存管理主模块
├── skew.zig               # 偏斜计算
├── rebalance.zig          # 再平衡逻辑
└── tests/
    └── inventory_test.zig # 测试
```

### 组件关系

```
┌─────────────────────────────────────────────────────────────┐
│                    PureMarketMaking                         │
│                                                             │
│  ┌─────────────┐    ┌─────────────────┐    ┌─────────────┐ │
│  │ QuoteCalc   │───▶│ InventoryManager│───▶│ OrderPlacer │ │
│  └─────────────┘    └─────────────────┘    └─────────────┘ │
│         │                   │                    │          │
│         ▼                   ▼                    ▼          │
│  ┌─────────────┐    ┌─────────────────┐    ┌─────────────┐ │
│  │ MarketData  │    │  SkewCalculator │    │  Executor   │ │
│  └─────────────┘    └─────────────────┘    └─────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 数据结构

### InventoryManager 内部结构

```zig
pub const InventoryManager = struct {
    /// 配置
    config: InventoryConfig,

    /// 当前库存
    current_inventory: Decimal,

    /// 历史峰值库存
    peak_inventory: Decimal,

    /// 偏斜计算器
    skew_calculator: SkewCalculator,

    /// 统计
    stats: InventoryStats,

    /// 状态
    state: State,

    const State = enum {
        normal,
        warning,
        rebalancing,
        emergency,
    };
};
```

### SkewCalculator

```zig
pub const SkewCalculator = struct {
    mode: SkewMode,
    factor: f64,
    min_skew: f64,
    tiers: ?[]const Tier,

    pub const Tier = struct {
        threshold: f64,  // 归一化库存阈值
        multiplier: f64, // 偏斜乘数
    };
};
```

### InventoryStats

```zig
pub const InventoryStats = struct {
    /// 总成交买入量
    total_bought: Decimal,

    /// 总成交卖出量
    total_sold: Decimal,

    /// 再平衡次数
    rebalance_count: u64,

    /// 紧急停止次数
    emergency_count: u64,

    /// 库存周转率
    turnover_rate: f64,

    /// 平均库存
    avg_inventory: Decimal,
};
```

---

## 核心算法

### 库存更新流程

```
OrderFill 到达
      │
      ▼
┌──────────────┐
│ 验证成交信息  │
└──────────────┘
      │
      ▼
┌──────────────┐
│ 更新库存数量  │
│ buy: +qty    │
│ sell: -qty   │
└──────────────┘
      │
      ▼
┌──────────────┐
│ 更新统计信息  │
└──────────────┘
      │
      ▼
┌──────────────┐
│ 检查状态阈值  │
│ warning?     │
│ emergency?   │
└──────────────┘
      │
      ▼
┌──────────────┐
│ 触发回调     │
│ (如果需要)   │
└──────────────┘
```

### 库存更新实现

```zig
pub fn updateInventory(self: *InventoryManager, fill: OrderFill) void {
    // 更新库存
    switch (fill.side) {
        .buy => {
            self.current_inventory = self.current_inventory.add(fill.quantity);
            self.stats.total_bought = self.stats.total_bought.add(fill.quantity);
        },
        .sell => {
            self.current_inventory = self.current_inventory.sub(fill.quantity);
            self.stats.total_sold = self.stats.total_sold.add(fill.quantity);
        },
    }

    // 更新峰值
    const abs_inv = self.current_inventory.abs();
    if (abs_inv.greaterThan(self.peak_inventory)) {
        self.peak_inventory = abs_inv;
    }

    // 检查状态
    self.updateState();
}
```

---

## 偏斜计算

### 偏斜值含义

```
偏斜值范围: -1.0 到 +1.0

+1.0  ─────────────────  最大正库存 (需要卖出)
      │
+0.5  ─────────────────  中等正库存
      │
 0.0  ─────────────────  中性 (目标状态)
      │
-0.5  ─────────────────  中等负库存
      │
-1.0  ─────────────────  最大负库存 (需要买入)
```

### 线性偏斜

最简单的偏斜模型，库存与偏斜线性相关。

```zig
pub fn linearSkew(normalized_inv: f64) f64 {
    // skew = inventory / max_inventory
    return std.math.clamp(normalized_inv, -1.0, 1.0);
}
```

**特点**:
- 计算简单
- 对所有库存水平同等对待
- 适合低波动市场

### 指数偏斜

对高库存水平惩罚更重。

```zig
pub fn exponentialSkew(normalized_inv: f64) f64 {
    // skew = sign(x) * x^2
    const sign: f64 = if (normalized_inv >= 0) 1.0 else -1.0;
    const abs_inv = @abs(normalized_inv);
    return sign * abs_inv * abs_inv;
}
```

**特点**:
- 小库存时调整温和
- 大库存时调整激进
- 适合高波动市场

### 分段偏斜

根据不同库存区间使用不同调整力度。

```zig
pub fn tieredSkew(normalized_inv: f64, tiers: []const Tier) f64 {
    const abs_inv = @abs(normalized_inv);
    const sign: f64 = if (normalized_inv >= 0) 1.0 else -1.0;

    var multiplier: f64 = 1.0;
    for (tiers) |tier| {
        if (abs_inv >= tier.threshold) {
            multiplier = tier.multiplier;
        }
    }

    return sign * abs_inv * multiplier;
}

// 默认分段配置
const default_tiers = [_]Tier{
    .{ .threshold = 0.0, .multiplier = 0.5 },   // 0-50%: 温和
    .{ .threshold = 0.5, .multiplier = 1.0 },   // 50-80%: 正常
    .{ .threshold = 0.8, .multiplier = 2.0 },   // 80-100%: 激进
};
```

### 偏斜可视化

```
        偏斜值
          │
    1.0   │              ╱ exponential
          │            ╱╱
          │          ╱╱
    0.5   │        ╱╱ ─────── linear
          │      ╱╱ ╱
          │    ╱╱╱╱    tiered (阶梯状)
          │  ╱╱╱
    0.0   ├─────────────────── 归一化库存
          0    0.5    1.0
```

---

## 报价调整

### 调整原理

```
库存正 (多头) → 希望卖出 → 降低卖价 (更有吸引力)
                        → 降低买价 (减少买入)

库存负 (空头) → 希望买入 → 提高买价 (更有吸引力)
                        → 提高卖价 (减少卖出)
```

### 调整算法

```zig
pub fn adjustQuotes(
    self: *InventoryManager,
    bid: Decimal,
    ask: Decimal,
    mid: Decimal,
) AdjustedQuotes {
    // 计算偏斜
    const skew = self.calculateSkew();

    // 计算调整量
    const spread = ask.sub(bid);
    const half_spread = spread.div(Decimal.two);

    // 偏斜调整 = 偏斜值 * 偏斜系数 * 半价差
    const adjustment = half_spread.mulF64(skew * self.config.skew_factor);

    // 应用调整
    // 正偏斜: 整体下移 (bid 和 ask 都降低)
    // 负偏斜: 整体上移 (bid 和 ask 都提高)
    return AdjustedQuotes{
        .bid = bid.sub(adjustment),
        .ask = ask.sub(adjustment),
        .skew_applied = skew,
        .bid_adjustment = adjustment.neg(),
        .ask_adjustment = adjustment.neg(),
    };
}
```

### 调整示例

```
原始报价: Bid=1999, Ask=2001, Mid=2000, Spread=2

场景1: 库存 = +5 (最大10), skew_factor = 0.5
  normalized = 0.5
  skew = 0.5 (linear)
  adjustment = 1 * 0.5 * 0.5 = 0.25
  调整后: Bid=1998.75, Ask=2000.75

场景2: 库存 = -8 (最大10), skew_factor = 0.5
  normalized = -0.8
  skew = -0.8 (linear)
  adjustment = 1 * (-0.8) * 0.5 = -0.4
  调整后: Bid=1999.4, Ask=2001.4
```

---

## 再平衡机制

### 状态机

```
        ┌─────────┐
        │ NORMAL  │
        └────┬────┘
             │ inventory > warning_threshold
             ▼
        ┌─────────┐
        │ WARNING │
        └────┬────┘
             │ inventory > rebalance_threshold
             ▼
     ┌───────────────┐
     │  REBALANCING  │
     └───────┬───────┘
             │ inventory > emergency_threshold
             ▼
       ┌───────────┐
       │ EMERGENCY │
       └───────────┘
```

### 再平衡动作决策

```zig
pub fn getRebalanceAction(self: *InventoryManager) RebalanceAction {
    const state = self.getState();

    // 紧急状态
    if (state.is_emergency) {
        return RebalanceAction{
            .action_type = .emergency_stop,
            .side = if (state.normalized > 0) .sell else .buy,
            .quantity = state.current.abs(),
            .urgency = 1.0,
        };
    }

    // 需要再平衡
    if (state.needs_rebalance) {
        const excess = state.deviation.abs().sub(
            self.config.max_inventory.mulF64(self.config.rebalance_threshold)
        );

        return RebalanceAction{
            .action_type = if (state.normalized > 0.9) .market_order else .limit_order,
            .side = if (state.normalized > 0) .sell else .buy,
            .quantity = excess,
            .urgency = @abs(state.normalized),
        };
    }

    return RebalanceAction{
        .action_type = .none,
        .side = .buy,
        .quantity = Decimal.zero,
        .urgency = 0,
    };
}
```

---

## 性能优化

### 避免重复计算

```zig
pub const InventoryManager = struct {
    // 缓存
    cached_skew: ?f64 = null,
    cache_valid: bool = false,

    pub fn calculateSkew(self: *InventoryManager) f64 {
        if (self.cache_valid) {
            return self.cached_skew.?;
        }

        const skew = self.computeSkew();
        self.cached_skew = skew;
        self.cache_valid = true;
        return skew;
    }

    pub fn updateInventory(self: *InventoryManager, fill: OrderFill) void {
        // 更新库存后使缓存失效
        self.cache_valid = false;
        // ... 更新逻辑
    }
};
```

### 使用定点数

所有金额计算使用 Decimal 类型避免浮点误差:

```zig
// 好的做法
const adjustment = half_spread.mulF64(skew * factor);
const new_bid = bid.sub(adjustment);

// 避免的做法
// const adjustment = spread_float * skew * factor;
// const new_bid = bid_float - adjustment;
```

### 内联关键路径

```zig
// 关键路径函数使用 inline
pub inline fn calculateSkew(self: *InventoryManager) f64 {
    const normalized = self.current_inventory.toFloat() /
                       self.config.max_inventory.toFloat();
    return switch (self.config.skew_mode) {
        .linear => normalized,
        .exponential => exponentialSkew(normalized),
        .tiered => tieredSkew(normalized, self.tiers),
    };
}
```

---

## 测试覆盖

### 单元测试

```zig
test "linear skew calculation" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_mode = .linear,
    });

    // 0库存 → 0偏斜
    try testing.expectEqual(@as(f64, 0), manager.calculateSkew());

    // +5库存 → +0.5偏斜
    manager.current_inventory = Decimal.fromFloat(5.0);
    try testing.expectApproxEqAbs(@as(f64, 0.5), manager.calculateSkew(), 0.001);

    // -10库存 → -1.0偏斜
    manager.current_inventory = Decimal.fromFloat(-10.0);
    try testing.expectApproxEqAbs(@as(f64, -1.0), manager.calculateSkew(), 0.001);
}
```

---

*Last updated: 2025-12-27*
