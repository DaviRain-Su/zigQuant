# Story 035: Inventory Management 库存管理

**版本**: v0.7.0
**状态**: 待开发
**优先级**: P1
**预计时间**: 2-3 天
**依赖**: Story 034 (Pure Market Making)

---

## 概述

实现做市策略的库存风险管理。通过动态调整报价来管理仓位风险，避免单边累积过多库存，同时在价格有利时积极平仓。

---

## 背景

### 为什么需要库存管理?

```
┌─────────────────────────────────────────────────────────────────┐
│                      库存风险问题                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  场景: 价格下跌时的做市                                         │
│                                                                  │
│  时间    价格     我的操作        库存                          │
│  ────────────────────────────────────────                       │
│  T1      2000    买入 0.1       +0.1                           │
│  T2      1990    买入 0.1       +0.2                           │
│  T3      1980    买入 0.1       +0.3                           │
│  T4      1970    买入 0.1       +0.4  ← 库存累积!              │
│  T5      1960    买入 0.1       +0.5                           │
│                                                                  │
│  问题:                                                          │
│  - 持续买入导致库存累积                                         │
│  - 价格下跌造成浮亏                                             │
│  - 单边持仓风险增大                                             │
│                                                                  │
│  解决方案: 库存偏斜 (Inventory Skew)                            │
│  - 库存多 → 降低买价，提高卖价 → 鼓励卖出                      │
│  - 库存少 → 提高买价，降低卖价 → 鼓励买入                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 库存偏斜原理

```
┌─────────────────────────────────────────────────────────────────┐
│                    Inventory Skew 原理                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│                    正常报价 (库存 = 0)                          │
│                                                                  │
│           Bid ←────── Mid ──────→ Ask                           │
│          1999         2000        2001                          │
│                                                                  │
│                    正库存 (库存 > 0, 需要卖出)                  │
│                                                                  │
│       Bid ←────── Mid ──→ Ask                                   │
│      1997        2000    2000.5   (整体下移)                    │
│                                                                  │
│                    负库存 (库存 < 0, 需要买入)                  │
│                                                                  │
│              Bid ←── Mid ──────→ Ask                            │
│            1999.5    2000        2003 (整体上移)                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 技术设计

### 核心组件

```
┌─────────────────────────────────────────────────────────────────┐
│                   Inventory Management 架构                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  InventoryManager                         │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │                     配置                             │ │  │
│  │  │  target_inventory: 0                                 │ │  │
│  │  │  max_inventory: 1.0                                  │ │  │
│  │  │  inventory_skew_factor: 0.5                          │ │  │
│  │  │  rebalance_threshold: 0.8                            │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │                     状态                             │ │  │
│  │  │  current_inventory: 0.3                              │ │  │
│  │  │  inventory_ratio: 0.3 (30% of max)                   │ │  │
│  │  │  skew_direction: positive                            │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │                     方法                             │ │  │
│  │  │  • calculateSkew() → f64                             │ │  │
│  │  │  • adjustQuotes(bid, ask, mid) → (bid, ask)          │ │  │
│  │  │  • needsRebalance() → bool                           │ │  │
│  │  │  • updateInventory(fill)                             │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 配置结构

```zig
/// 库存管理配置
pub const InventoryConfig = struct {
    /// 目标库存 (通常为 0，表示中性持仓)
    target_inventory: Decimal = Decimal.zero,

    /// 最大库存绝对值
    max_inventory: Decimal,

    /// 库存偏斜系数 (0.0 - 1.0)
    /// 越大偏斜越强
    skew_factor: f64 = 0.5,

    /// 再平衡阈值 (库存/最大库存)
    /// 超过此值触发主动平仓
    rebalance_threshold: f64 = 0.8,

    /// 偏斜模式
    skew_mode: SkewMode = .linear,

    /// 紧急平仓阈值
    emergency_threshold: f64 = 0.95,
};

pub const SkewMode = enum {
    /// 线性偏斜
    linear,
    /// 指数偏斜 (库存大时偏斜更强)
    exponential,
    /// 分段偏斜 (阈值触发)
    tiered,
};
```

### 核心实现

```zig
const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;

/// 库存管理器
pub const InventoryManager = struct {
    config: InventoryConfig,
    current_inventory: Decimal,

    // 统计
    peak_inventory: Decimal,
    rebalance_count: u32,

    const Self = @This();

    pub fn init(config: InventoryConfig) Self {
        return .{
            .config = config,
            .current_inventory = Decimal.zero,
            .peak_inventory = Decimal.zero,
            .rebalance_count = 0,
        };
    }

    /// 计算库存比率 (-1.0 到 1.0)
    pub fn inventoryRatio(self: *Self) f64 {
        const max = self.config.max_inventory.toFloat();
        if (max == 0) return 0;
        return self.current_inventory.toFloat() / max;
    }

    /// 计算库存偏斜量
    pub fn calculateSkew(self: *Self) f64 {
        const ratio = self.inventoryRatio();

        return switch (self.config.skew_mode) {
            .linear => ratio * self.config.skew_factor,
            .exponential => blk: {
                const sign: f64 = if (ratio >= 0) 1.0 else -1.0;
                const abs_ratio = @abs(ratio);
                break :blk sign * std.math.pow(f64, abs_ratio, 2) * self.config.skew_factor;
            },
            .tiered => blk: {
                const abs_ratio = @abs(ratio);
                const tier_factor: f64 = if (abs_ratio > 0.7) 2.0 else if (abs_ratio > 0.4) 1.5 else 1.0;
                break :blk ratio * self.config.skew_factor * tier_factor;
            },
        };
    }

    /// 调整报价
    pub fn adjustQuotes(
        self: *Self,
        base_bid: Decimal,
        base_ask: Decimal,
        mid: Decimal,
    ) struct { bid: Decimal, ask: Decimal } {
        const skew = self.calculateSkew();
        const skew_amount = mid.mul(Decimal.fromFloat(@abs(skew)));

        if (skew > 0) {
            // 正库存 → 鼓励卖出
            // 降低买价，降低卖价 (更容易成交卖单)
            return .{
                .bid = base_bid.sub(skew_amount),
                .ask = base_ask.sub(skew_amount.mul(Decimal.fromFloat(0.5))),
            };
        } else if (skew < 0) {
            // 负库存 → 鼓励买入
            // 提高买价，提高卖价 (更容易成交买单)
            return .{
                .bid = base_bid.add(skew_amount.mul(Decimal.fromFloat(0.5))),
                .ask = base_ask.add(skew_amount),
            };
        } else {
            return .{ .bid = base_bid, .ask = base_ask };
        }
    }

    /// 检查是否需要再平衡
    pub fn needsRebalance(self: *Self) bool {
        const abs_ratio = @abs(self.inventoryRatio());
        return abs_ratio > self.config.rebalance_threshold;
    }

    /// 检查是否需要紧急平仓
    pub fn needsEmergencyClose(self: *Self) bool {
        const abs_ratio = @abs(self.inventoryRatio());
        return abs_ratio > self.config.emergency_threshold;
    }

    /// 获取再平衡建议
    pub fn getRebalanceAction(self: *Self) ?RebalanceAction {
        if (!self.needsRebalance()) return null;

        const ratio = self.inventoryRatio();
        const excess = self.current_inventory.sub(self.config.target_inventory);

        return .{
            .direction = if (ratio > 0) .sell else .buy,
            .amount = excess.abs(),
            .urgency = if (self.needsEmergencyClose()) .emergency else .normal,
        };
    }

    /// 更新库存 (成交回调)
    pub fn updateInventory(self: *Self, fill: OrderFill) void {
        if (fill.side == .buy) {
            self.current_inventory = self.current_inventory.add(fill.quantity);
        } else {
            self.current_inventory = self.current_inventory.sub(fill.quantity);
        }

        // 更新峰值
        if (self.current_inventory.abs().compare(self.peak_inventory) == .gt) {
            self.peak_inventory = self.current_inventory.abs();
        }
    }

    /// 获取统计信息
    pub fn getStats(self: *Self) InventoryStats {
        return .{
            .current = self.current_inventory,
            .ratio = self.inventoryRatio(),
            .skew = self.calculateSkew(),
            .peak = self.peak_inventory,
            .rebalance_count = self.rebalance_count,
        };
    }
};

pub const RebalanceAction = struct {
    direction: enum { buy, sell },
    amount: Decimal,
    urgency: enum { normal, emergency },
};

pub const InventoryStats = struct {
    current: Decimal,
    ratio: f64,
    skew: f64,
    peak: Decimal,
    rebalance_count: u32,
};
```

### 与 PureMarketMaking 集成

```zig
/// 带库存管理的做市策略
pub const ManagedMarketMaking = struct {
    mm: PureMarketMaking,
    inventory: InventoryManager,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        mm_config: PureMMConfig,
        inv_config: InventoryConfig,
        data_provider: *IDataProvider,
        executor: *IExecutionClient,
    ) Self {
        return .{
            .mm = PureMarketMaking.init(allocator, mm_config, data_provider, executor),
            .inventory = InventoryManager.init(inv_config),
        };
    }

    /// IClockStrategy 实现
    fn onTickImpl(ptr: *anyopaque, tick: u64, timestamp: i128) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // 检查紧急平仓
        if (self.inventory.needsEmergencyClose()) {
            try self.emergencyClose();
            return;
        }

        // 获取基础报价
        const mid = self.mm.getMidPrice() orelse return;
        const base_quotes = self.mm.calculateBaseQuotes(mid);

        // 应用库存偏斜
        const adjusted = self.inventory.adjustQuotes(
            base_quotes.bid,
            base_quotes.ask,
            mid,
        );

        // 下单
        try self.mm.placeQuotesWithPrices(adjusted.bid, adjusted.ask);

        _ = tick;
        _ = timestamp;
    }

    fn onFill(self: *Self, fill: OrderFill) void {
        self.mm.onFill(fill);
        self.inventory.updateInventory(fill);
    }

    fn emergencyClose(self: *Self) !void {
        const action = self.inventory.getRebalanceAction() orelse return;
        std.log.warn("[ManagedMM] Emergency close: {} {}", .{
            action.direction,
            action.amount,
        });
        // 市价单平仓
        try self.mm.executor.submitOrder(.{
            .symbol = self.mm.config.symbol,
            .side = if (action.direction == .sell) .sell else .buy,
            .order_type = .market,
            .quantity = action.amount,
            .price = null,
        });
    }
};
```

---

## 实现任务

### Task 1: InventoryManager 核心 (Day 1)

- [ ] 创建 `src/market_making/inventory.zig`
- [ ] 实现 InventoryConfig
- [ ] 实现 calculateSkew (线性模式)
- [ ] 实现 adjustQuotes
- [ ] 添加基础测试

### Task 2: 偏斜模式 (Day 1-2)

- [ ] 实现指数偏斜模式
- [ ] 实现分段偏斜模式
- [ ] 参数调优接口
- [ ] 模式对比测试

### Task 3: 再平衡逻辑 (Day 2)

- [ ] 实现 needsRebalance
- [ ] 实现 getRebalanceAction
- [ ] 实现紧急平仓
- [ ] 添加告警机制

### Task 4: 集成和测试 (Day 2-3)

- [ ] 与 PureMarketMaking 集成
- [ ] ManagedMarketMaking 封装
- [ ] Paper Trading 测试
- [ ] 性能测试

---

## 测试计划

### 单元测试

```zig
test "InventoryManager skew calculation" {
    var inv = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
        .skew_factor = 0.5,
        .skew_mode = .linear,
    });

    // 无库存
    inv.current_inventory = Decimal.zero;
    try testing.expectEqual(@as(f64, 0.0), inv.calculateSkew());

    // 50% 正库存
    inv.current_inventory = Decimal.fromFloat(0.5);
    try testing.expectApproxEqAbs(@as(f64, 0.25), inv.calculateSkew(), 0.01);

    // 满仓
    inv.current_inventory = Decimal.fromFloat(1.0);
    try testing.expectApproxEqAbs(@as(f64, 0.5), inv.calculateSkew(), 0.01);
}

test "InventoryManager quote adjustment" {
    var inv = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
        .skew_factor = 0.5,
    });

    const mid = Decimal.fromInt(2000);
    const bid = Decimal.fromInt(1999);
    const ask = Decimal.fromInt(2001);

    // 正库存 → 报价下移
    inv.current_inventory = Decimal.fromFloat(0.5);
    const adjusted = inv.adjustQuotes(bid, ask, mid);

    try testing.expect(adjusted.bid.toFloat() < bid.toFloat());
    try testing.expect(adjusted.ask.toFloat() < ask.toFloat());
}

test "InventoryManager rebalance trigger" {
    var inv = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(1.0),
        .rebalance_threshold = 0.8,
    });

    // 低于阈值
    inv.current_inventory = Decimal.fromFloat(0.7);
    try testing.expect(!inv.needsRebalance());

    // 高于阈值
    inv.current_inventory = Decimal.fromFloat(0.85);
    try testing.expect(inv.needsRebalance());
}
```

### 场景测试

| 场景 | 初始库存 | 预期行为 |
|------|----------|----------|
| 正常做市 | 0 | 无偏斜 |
| 轻度正库存 | 0.3 | 轻微下移报价 |
| 重度正库存 | 0.8 | 大幅下移，触发再平衡 |
| 满仓 | 1.0 | 紧急平仓 |

---

## 验收标准

### 功能验收

- [ ] 线性偏斜正确计算
- [ ] 报价调整正确
- [ ] 再平衡触发准确
- [ ] 紧急平仓工作

### 性能验收

- [ ] 计算延迟 < 0.1ms
- [ ] 无额外内存分配

### 代码验收

- [ ] 完整单元测试
- [ ] 集成测试通过
- [ ] 文档完整

---

## 文件结构

```
src/market_making/
├── mod.zig           # 模块导出
├── clock.zig         # Clock (Story 033)
├── pure_mm.zig       # Pure MM (Story 034)
├── inventory.zig     # 库存管理
└── managed_mm.zig    # 集成策略

tests/
└── inventory_test.zig
```

---

**Story**: 035
**版本**: v0.7.0
**创建时间**: 2025-12-27
