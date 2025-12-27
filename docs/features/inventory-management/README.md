# Inventory Management 库存管理

> 通过动态调整报价来管理做市策略的仓位风险

**状态**: 📋 待开发
**版本**: v0.7.0
**Story**: [Story 035](../../stories/v0.7.0/STORY_035_INVENTORY.md)
**依赖**: [Pure Market Making](../pure-market-making/README.md)
**最后更新**: 2025-12-27

---

## 概述

库存管理 (Inventory Management) 是做市策略的风险控制核心组件。通过库存偏斜 (Inventory Skew) 技术，根据当前持仓动态调整买卖报价，避免单边库存累积，降低市场风险。

### 为什么需要库存管理?

```
场景: 价格下跌时的做市

时间    价格     操作        库存
────────────────────────────────
T1      2000    买入 0.1    +0.1
T2      1990    买入 0.1    +0.2
T3      1980    买入 0.1    +0.3
T4      1970    买入 0.1    +0.4  ← 库存累积!
T5      1960    买入 0.1    +0.5

问题:
- 持续买入导致库存累积
- 价格下跌造成浮亏
- 单边持仓风险增大

解决方案: 库存偏斜 (Inventory Skew)
- 库存多 → 降低买价，提高卖价 → 鼓励卖出
- 库存少 → 提高买价，降低卖价 → 鼓励买入
```

### 核心特性

- **库存偏斜**: 根据持仓方向调整报价
- **多种偏斜模式**: 线性/指数/分段
- **再平衡机制**: 超过阈值主动平仓
- **紧急保护**: 极端情况停止交易

---

## 快速开始

```zig
const InventoryManager = @import("market_making/inventory.zig").InventoryManager;

// 配置
const config = InventoryConfig{
    .target_inventory = Decimal.zero,        // 目标持仓: 中性
    .max_inventory = Decimal.fromFloat(1.0), // 最大持仓
    .skew_factor = 0.5,                      // 偏斜系数
    .rebalance_threshold = 0.8,              // 再平衡阈值
    .skew_mode = .linear,                    // 线性偏斜
};

var manager = InventoryManager.init(config);

// 计算调整后的报价
const adjusted = manager.adjustQuotes(bid, ask, mid);
// adjusted.bid 和 adjusted.ask 包含偏斜调整
```

---

## 核心 API

### InventoryConfig

```zig
pub const InventoryConfig = struct {
    target_inventory: Decimal = Decimal.zero,  // 目标库存
    max_inventory: Decimal,                    // 最大库存
    skew_factor: f64 = 0.5,                    // 偏斜系数 (0-1)
    rebalance_threshold: f64 = 0.8,            // 再平衡阈值
    skew_mode: SkewMode = .linear,             // 偏斜模式
    emergency_threshold: f64 = 0.95,           // 紧急阈值
};

pub const SkewMode = enum {
    linear,       // 线性偏斜
    exponential,  // 指数偏斜
    tiered,       // 分段偏斜
};
```

### InventoryManager

```zig
pub const InventoryManager = struct {
    /// 计算偏斜值 (-1 到 +1)
    pub fn calculateSkew(self: *InventoryManager) f64;

    /// 调整报价
    pub fn adjustQuotes(self: *InventoryManager, bid: Decimal, ask: Decimal, mid: Decimal)
        struct { bid: Decimal, ask: Decimal };

    /// 检查是否需要再平衡
    pub fn needsRebalance(self: *InventoryManager) bool;

    /// 更新库存
    pub fn updateInventory(self: *InventoryManager, fill: OrderFill) void;
};
```

---

## 偏斜原理

```
正常报价 (库存 = 0):
       Bid ←────── Mid ──────→ Ask
      1999         2000        2001

正库存 (需要卖出):
   Bid ←────── Mid ──→ Ask
  1997        2000    2000.5   (整体下移，鼓励卖出)

负库存 (需要买入):
          Bid ←── Mid ──────→ Ask
        1999.5    2000        2003 (整体上移，鼓励买入)
```

---

## 相关文档

- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [Bug 追踪](./bugs.md)
- [变更日志](./changelog.md)

---

## 性能指标

| 指标 | 目标值 |
|------|--------|
| calculateSkew | < 100ns |
| adjustQuotes | < 200ns |
| 内存占用 | < 1KB |

---

*Last updated: 2025-12-27*
