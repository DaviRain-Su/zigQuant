# Inventory Management API 参考

> 库存管理模块的完整 API 文档

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 目录

1. [核心类型](#核心类型)
2. [InventoryManager](#inventorymanager)
3. [辅助函数](#辅助函数)
4. [使用示例](#使用示例)

---

## 核心类型

### SkewMode

偏斜计算模式枚举。

```zig
pub const SkewMode = enum {
    /// 线性偏斜: skew = inventory / max_inventory
    linear,

    /// 指数偏斜: skew = sign(inv) * (inv/max)^2
    exponential,

    /// 分段偏斜: 不同区间使用不同系数
    tiered,
};
```

### InventoryConfig

库存管理配置结构。

```zig
pub const InventoryConfig = struct {
    /// 目标库存 (通常为 0 表示中性)
    target_inventory: Decimal = Decimal.zero,

    /// 最大允许库存
    max_inventory: Decimal,

    /// 偏斜系数 (0.0 - 1.0)
    /// 0 = 不调整, 1 = 完全调整
    skew_factor: f64 = 0.5,

    /// 再平衡阈值 (库存/最大库存)
    /// 超过此值触发主动再平衡
    rebalance_threshold: f64 = 0.8,

    /// 偏斜计算模式
    skew_mode: SkewMode = .linear,

    /// 紧急停止阈值
    emergency_threshold: f64 = 0.95,

    /// 最小偏斜值 (避免过小调整)
    min_skew: f64 = 0.001,

    /// 验证配置
    pub fn validate(self: InventoryConfig) !void;
};
```

### InventoryState

库存状态结构。

```zig
pub const InventoryState = struct {
    /// 当前库存
    current: Decimal,

    /// 目标库存
    target: Decimal,

    /// 库存偏差 (current - target)
    deviation: Decimal,

    /// 归一化偏差 (-1 到 +1)
    normalized: f64,

    /// 是否需要再平衡
    needs_rebalance: bool,

    /// 是否处于紧急状态
    is_emergency: bool,
};
```

### AdjustedQuotes

调整后的报价结构。

```zig
pub const AdjustedQuotes = struct {
    /// 调整后的买价
    bid: Decimal,

    /// 调整后的卖价
    ask: Decimal,

    /// 应用的偏斜值
    skew_applied: f64,

    /// 买价调整量
    bid_adjustment: Decimal,

    /// 卖价调整量
    ask_adjustment: Decimal,
};
```

### RebalanceAction

再平衡动作结构。

```zig
pub const RebalanceAction = struct {
    /// 动作类型
    action_type: ActionType,

    /// 交易方向
    side: OrderSide,

    /// 建议数量
    quantity: Decimal,

    /// 紧急程度 (0-1)
    urgency: f64,

    pub const ActionType = enum {
        none,           // 无需动作
        adjust_quotes,  // 调整报价
        market_order,   // 市价单平仓
        limit_order,    // 限价单平仓
        emergency_stop, // 紧急停止
    };
};
```

---

## InventoryManager

库存管理器主结构。

### 初始化

```zig
pub fn init(config: InventoryConfig) InventoryManager
```

创建库存管理器实例。

**参数**:
- `config`: 库存管理配置

**返回**: InventoryManager 实例

**示例**:
```zig
const config = InventoryConfig{
    .target_inventory = Decimal.zero,
    .max_inventory = Decimal.fromFloat(10.0),
    .skew_factor = 0.5,
    .skew_mode = .linear,
};

var manager = InventoryManager.init(config);
```

### calculateSkew

```zig
pub fn calculateSkew(self: *InventoryManager) f64
```

计算当前偏斜值。

**返回**: 偏斜值 (-1.0 到 +1.0)
- 正值: 库存过多，需要卖出
- 负值: 库存过少，需要买入
- 0: 库存平衡

**示例**:
```zig
const skew = manager.calculateSkew();
if (skew > 0.5) {
    std.debug.print("库存过多，偏斜: {d:.2}\n", .{skew});
}
```

### adjustQuotes

```zig
pub fn adjustQuotes(
    self: *InventoryManager,
    bid: Decimal,
    ask: Decimal,
    mid: Decimal,
) AdjustedQuotes
```

根据库存状态调整报价。

**参数**:
- `bid`: 原始买价
- `ask`: 原始卖价
- `mid`: 中间价

**返回**: AdjustedQuotes 包含调整后的报价

**调整逻辑**:
- 库存正 (多头): 降低买价，降低卖价 → 鼓励卖出
- 库存负 (空头): 提高买价，提高卖价 → 鼓励买入

**示例**:
```zig
const adjusted = manager.adjustQuotes(
    Decimal.fromFloat(1999.0),  // bid
    Decimal.fromFloat(2001.0),  // ask
    Decimal.fromFloat(2000.0),  // mid
);

std.debug.print("调整后: bid={}, ask={}\n", .{
    adjusted.bid,
    adjusted.ask,
});
```

### getState

```zig
pub fn getState(self: *InventoryManager) InventoryState
```

获取当前库存状态。

**返回**: InventoryState 包含完整状态信息

### updateInventory

```zig
pub fn updateInventory(self: *InventoryManager, fill: OrderFill) void
```

根据成交更新库存。

**参数**:
- `fill`: 成交信息

**示例**:
```zig
manager.updateInventory(.{
    .side = .buy,
    .quantity = Decimal.fromFloat(0.1),
    .price = Decimal.fromFloat(2000.0),
});
```

### needsRebalance

```zig
pub fn needsRebalance(self: *InventoryManager) bool
```

检查是否需要再平衡。

**返回**: 是否需要再平衡

### getRebalanceAction

```zig
pub fn getRebalanceAction(self: *InventoryManager) RebalanceAction
```

获取建议的再平衡动作。

**返回**: RebalanceAction 包含建议的操作

### isEmergency

```zig
pub fn isEmergency(self: *InventoryManager) bool
```

检查是否处于紧急状态。

**返回**: 是否紧急

### reset

```zig
pub fn reset(self: *InventoryManager) void
```

重置库存到目标值。

---

## 辅助函数

### linearSkew

```zig
pub fn linearSkew(normalized_inventory: f64) f64
```

线性偏斜计算。

**公式**: `skew = normalized_inventory`

### exponentialSkew

```zig
pub fn exponentialSkew(normalized_inventory: f64) f64
```

指数偏斜计算。

**公式**: `skew = sign(x) * x^2`

### tieredSkew

```zig
pub fn tieredSkew(normalized_inventory: f64, tiers: []const Tier) f64
```

分段偏斜计算。

**参数**:
- `normalized_inventory`: 归一化库存
- `tiers`: 分段配置

---

## 使用示例

### 基本使用

```zig
const std = @import("std");
const InventoryManager = @import("market_making/inventory.zig").InventoryManager;

pub fn main() !void {
    // 配置
    const config = InventoryConfig{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_factor = 0.5,
        .rebalance_threshold = 0.8,
    };

    var manager = InventoryManager.init(config);

    // 模拟成交
    manager.updateInventory(.{
        .side = .buy,
        .quantity = Decimal.fromFloat(2.0),
        .price = Decimal.fromFloat(2000.0),
    });

    // 检查状态
    const state = manager.getState();
    std.debug.print("库存: {}, 偏斜: {d:.3}\n", .{
        state.current,
        state.normalized,
    });

    // 调整报价
    const quotes = manager.adjustQuotes(
        Decimal.fromFloat(1999.0),
        Decimal.fromFloat(2001.0),
        Decimal.fromFloat(2000.0),
    );

    std.debug.print("调整后报价: bid={}, ask={}\n", .{
        quotes.bid,
        quotes.ask,
    });
}
```

### 与做市策略集成

```zig
pub fn onTick(self: *PureMarketMaking) !void {
    // 获取市场数据
    const mid = self.getMidPrice();
    const spread = self.calculateSpread();

    // 计算基础报价
    var bid = mid.sub(spread.div(Decimal.two));
    var ask = mid.add(spread.div(Decimal.two));

    // 应用库存偏斜
    const adjusted = self.inventory_manager.adjustQuotes(bid, ask, mid);
    bid = adjusted.bid;
    ask = adjusted.ask;

    // 检查是否需要再平衡
    if (self.inventory_manager.needsRebalance()) {
        const action = self.inventory_manager.getRebalanceAction();
        try self.handleRebalance(action);
    }

    // 检查紧急状态
    if (self.inventory_manager.isEmergency()) {
        try self.cancelAllOrders();
        return;
    }

    // 下单
    try self.placeOrders(bid, ask);
}
```

---

## 错误处理

```zig
pub const InventoryError = error{
    /// 配置无效
    InvalidConfig,

    /// 库存超限
    InventoryExceeded,

    /// 紧急状态
    EmergencyState,

    /// 计算溢出
    Overflow,
};
```

---

## 性能说明

| 方法 | 时间复杂度 | 预期延迟 |
|------|------------|----------|
| calculateSkew | O(1) | < 100ns |
| adjustQuotes | O(1) | < 200ns |
| updateInventory | O(1) | < 50ns |
| needsRebalance | O(1) | < 20ns |

---

*Last updated: 2025-12-27*
