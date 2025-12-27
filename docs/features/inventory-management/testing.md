# Inventory Management 测试文档

> 库存管理模块的测试策略和用例

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 测试概述

### 测试范围

| 类别 | 描述 | 优先级 |
|------|------|--------|
| 偏斜计算 | 三种模式的偏斜计算 | P0 |
| 报价调整 | adjustQuotes 正确性 | P0 |
| 库存更新 | 成交后库存变化 | P0 |
| 再平衡 | 阈值触发和动作 | P1 |
| 边界条件 | 极端库存值 | P1 |
| 集成测试 | 与做市策略集成 | P2 |

### 测试文件

```
src/market_making/tests/
├── inventory_test.zig        # 单元测试
├── skew_test.zig             # 偏斜计算测试
├── rebalance_test.zig        # 再平衡测试
└── inventory_integration_test.zig  # 集成测试
```

---

## 单元测试

### 偏斜计算测试

```zig
const testing = @import("std").testing;
const InventoryManager = @import("../inventory.zig").InventoryManager;
const Decimal = @import("decimal").Decimal;

test "linear skew: zero inventory" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_mode = .linear,
    });

    try testing.expectApproxEqAbs(@as(f64, 0.0), manager.calculateSkew(), 0.001);
}

test "linear skew: positive inventory" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_mode = .linear,
    });

    manager.current_inventory = Decimal.fromFloat(5.0);
    try testing.expectApproxEqAbs(@as(f64, 0.5), manager.calculateSkew(), 0.001);

    manager.current_inventory = Decimal.fromFloat(10.0);
    try testing.expectApproxEqAbs(@as(f64, 1.0), manager.calculateSkew(), 0.001);
}

test "linear skew: negative inventory" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_mode = .linear,
    });

    manager.current_inventory = Decimal.fromFloat(-5.0);
    try testing.expectApproxEqAbs(@as(f64, -0.5), manager.calculateSkew(), 0.001);
}

test "exponential skew: quadratic behavior" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_mode = .exponential,
    });

    // 50% 库存 → 25% 偏斜 (0.5^2)
    manager.current_inventory = Decimal.fromFloat(5.0);
    try testing.expectApproxEqAbs(@as(f64, 0.25), manager.calculateSkew(), 0.001);

    // 100% 库存 → 100% 偏斜 (1.0^2)
    manager.current_inventory = Decimal.fromFloat(10.0);
    try testing.expectApproxEqAbs(@as(f64, 1.0), manager.calculateSkew(), 0.001);
}

test "tiered skew: threshold transitions" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_mode = .tiered,
        .tiers = &[_]Tier{
            .{ .threshold = 0.0, .multiplier = 0.5 },
            .{ .threshold = 0.5, .multiplier = 1.0 },
            .{ .threshold = 0.8, .multiplier = 2.0 },
        },
    });

    // 30% 库存，第一层 (0.5x)
    manager.current_inventory = Decimal.fromFloat(3.0);
    try testing.expectApproxEqAbs(@as(f64, 0.15), manager.calculateSkew(), 0.001);

    // 60% 库存，第二层 (1.0x)
    manager.current_inventory = Decimal.fromFloat(6.0);
    try testing.expectApproxEqAbs(@as(f64, 0.6), manager.calculateSkew(), 0.001);

    // 90% 库存，第三层 (2.0x)
    manager.current_inventory = Decimal.fromFloat(9.0);
    try testing.expectApproxEqAbs(@as(f64, 1.8), manager.calculateSkew(), 0.001);
}
```

### 报价调整测试

```zig
test "adjustQuotes: zero skew no adjustment" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_factor = 0.5,
    });

    const bid = Decimal.fromFloat(1999.0);
    const ask = Decimal.fromFloat(2001.0);
    const mid = Decimal.fromFloat(2000.0);

    const adjusted = manager.adjustQuotes(bid, ask, mid);

    try testing.expect(adjusted.bid.eq(bid));
    try testing.expect(adjusted.ask.eq(ask));
}

test "adjustQuotes: positive skew lowers prices" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_factor = 1.0,
        .skew_mode = .linear,
    });

    manager.current_inventory = Decimal.fromFloat(5.0); // 50% 偏斜

    const bid = Decimal.fromFloat(1999.0);
    const ask = Decimal.fromFloat(2001.0);
    const mid = Decimal.fromFloat(2000.0);

    const adjusted = manager.adjustQuotes(bid, ask, mid);

    // 正偏斜应该降低价格
    try testing.expect(adjusted.bid.lessThan(bid));
    try testing.expect(adjusted.ask.lessThan(ask));
}

test "adjustQuotes: negative skew raises prices" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_factor = 1.0,
        .skew_mode = .linear,
    });

    manager.current_inventory = Decimal.fromFloat(-5.0); // -50% 偏斜

    const bid = Decimal.fromFloat(1999.0);
    const ask = Decimal.fromFloat(2001.0);
    const mid = Decimal.fromFloat(2000.0);

    const adjusted = manager.adjustQuotes(bid, ask, mid);

    // 负偏斜应该提高价格
    try testing.expect(adjusted.bid.greaterThan(bid));
    try testing.expect(adjusted.ask.greaterThan(ask));
}

test "adjustQuotes: skew_factor=0 no adjustment" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_factor = 0.0, // 禁用偏斜
    });

    manager.current_inventory = Decimal.fromFloat(10.0);

    const bid = Decimal.fromFloat(1999.0);
    const ask = Decimal.fromFloat(2001.0);
    const mid = Decimal.fromFloat(2000.0);

    const adjusted = manager.adjustQuotes(bid, ask, mid);

    try testing.expect(adjusted.bid.eq(bid));
    try testing.expect(adjusted.ask.eq(ask));
}
```

### 库存更新测试

```zig
test "updateInventory: buy increases inventory" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
    });

    manager.updateInventory(.{
        .side = .buy,
        .quantity = Decimal.fromFloat(2.0),
        .price = Decimal.fromFloat(2000.0),
    });

    try testing.expect(manager.current_inventory.eq(Decimal.fromFloat(2.0)));
}

test "updateInventory: sell decreases inventory" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
    });

    manager.current_inventory = Decimal.fromFloat(5.0);

    manager.updateInventory(.{
        .side = .sell,
        .quantity = Decimal.fromFloat(2.0),
        .price = Decimal.fromFloat(2000.0),
    });

    try testing.expect(manager.current_inventory.eq(Decimal.fromFloat(3.0)));
}

test "updateInventory: stats tracking" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
    });

    manager.updateInventory(.{ .side = .buy, .quantity = Decimal.fromFloat(3.0), .price = Decimal.fromFloat(100.0) });
    manager.updateInventory(.{ .side = .sell, .quantity = Decimal.fromFloat(1.0), .price = Decimal.fromFloat(100.0) });

    try testing.expect(manager.stats.total_bought.eq(Decimal.fromFloat(3.0)));
    try testing.expect(manager.stats.total_sold.eq(Decimal.fromFloat(1.0)));
}
```

### 再平衡测试

```zig
test "needsRebalance: below threshold" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .rebalance_threshold = 0.8,
    });

    manager.current_inventory = Decimal.fromFloat(7.0); // 70%
    try testing.expect(!manager.needsRebalance());
}

test "needsRebalance: above threshold" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .rebalance_threshold = 0.8,
    });

    manager.current_inventory = Decimal.fromFloat(9.0); // 90%
    try testing.expect(manager.needsRebalance());
}

test "isEmergency: threshold trigger" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .emergency_threshold = 0.95,
    });

    manager.current_inventory = Decimal.fromFloat(9.6); // 96%
    try testing.expect(manager.isEmergency());
}

test "getRebalanceAction: normal state" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .rebalance_threshold = 0.8,
    });

    manager.current_inventory = Decimal.fromFloat(5.0);
    const action = manager.getRebalanceAction();

    try testing.expect(action.action_type == .none);
}

test "getRebalanceAction: rebalance needed" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .rebalance_threshold = 0.8,
    });

    manager.current_inventory = Decimal.fromFloat(9.0);
    const action = manager.getRebalanceAction();

    try testing.expect(action.action_type == .limit_order or action.action_type == .market_order);
    try testing.expect(action.side == .sell);
}

test "getRebalanceAction: emergency" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .emergency_threshold = 0.95,
    });

    manager.current_inventory = Decimal.fromFloat(9.8);
    const action = manager.getRebalanceAction();

    try testing.expect(action.action_type == .emergency_stop);
}
```

---

## 边界条件测试

```zig
test "boundary: zero max_inventory" {
    // 应该返回错误
    const result = InventoryConfig.validate(.{
        .max_inventory = Decimal.zero,
    });
    try testing.expectError(error.InvalidConfig, result);
}

test "boundary: skew_factor out of range" {
    const result = InventoryConfig.validate(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_factor = 1.5, // > 1.0
    });
    try testing.expectError(error.InvalidConfig, result);
}

test "boundary: inventory exceeds max" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
    });

    manager.current_inventory = Decimal.fromFloat(15.0);

    // 偏斜应该被限制在 ±1.0
    const skew = manager.calculateSkew();
    try testing.expect(skew <= 1.0);
    try testing.expect(skew >= -1.0);
}

test "boundary: very small inventory" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .min_skew = 0.001,
    });

    manager.current_inventory = Decimal.fromFloat(0.005);

    const skew = manager.calculateSkew();
    // 过小的偏斜应该被忽略
    try testing.expect(@abs(skew) < 0.001 or @abs(skew) >= 0.001);
}
```

---

## 集成测试

### 与做市策略集成

```zig
test "integration: inventory affects quotes" {
    const allocator = testing.allocator;

    // 创建做市策略 (包含库存管理)
    var mm = try PureMarketMaking.init(allocator, .{
        .symbol = "ETH-USD",
        .spread_bps = 10,
        .order_size = Decimal.fromFloat(1.0),
        .inventory_config = .{
            .max_inventory = Decimal.fromFloat(10.0),
            .skew_factor = 0.5,
        },
    });
    defer mm.deinit();

    // 模拟多次买入
    for (0..5) |_| {
        mm.onFill(.{
            .side = .buy,
            .quantity = Decimal.fromFloat(1.0),
            .price = Decimal.fromFloat(2000.0),
        });
    }

    // 检查报价是否向下偏移
    const quotes = mm.getQuotes();
    const mid = Decimal.fromFloat(2000.0);

    // 卖价应该更接近中间价 (鼓励卖出)
    try testing.expect(quotes.ask.sub(mid).lessThan(Decimal.fromFloat(10.0)));
}
```

### 多周期模拟

```zig
test "integration: inventory mean reversion" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
        .skew_factor = 0.5,
    });

    var rng = std.rand.DefaultPrng.init(42);

    // 模拟 100 次随机成交
    var buy_count: u32 = 0;
    var sell_count: u32 = 0;

    for (0..100) |_| {
        // 偏斜影响成交概率
        const skew = manager.calculateSkew();
        const buy_prob = 0.5 - skew * 0.25; // 偏斜高时买入概率低

        if (rng.random().float(f64) < buy_prob) {
            manager.updateInventory(.{ .side = .buy, .quantity = Decimal.fromFloat(0.1), .price = Decimal.zero });
            buy_count += 1;
        } else {
            manager.updateInventory(.{ .side = .sell, .quantity = Decimal.fromFloat(0.1), .price = Decimal.zero });
            sell_count += 1;
        }
    }

    // 库存应该趋向于0
    const final_inv = manager.current_inventory.toFloat();
    try testing.expect(@abs(final_inv) < 5.0); // 不应该极端偏向一边
}
```

---

## 性能测试

```zig
test "performance: calculateSkew latency" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
    });

    const iterations: u64 = 100_000;
    var timer = std.time.Timer{};
    timer.reset();

    for (0..iterations) |_| {
        _ = manager.calculateSkew();
    }

    const elapsed = timer.read();
    const per_call_ns = elapsed / iterations;

    // 每次调用应该 < 100ns
    try testing.expect(per_call_ns < 100);
}

test "performance: adjustQuotes latency" {
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(10.0),
    });

    const bid = Decimal.fromFloat(1999.0);
    const ask = Decimal.fromFloat(2001.0);
    const mid = Decimal.fromFloat(2000.0);

    const iterations: u64 = 100_000;
    var timer = std.time.Timer{};
    timer.reset();

    for (0..iterations) |_| {
        _ = manager.adjustQuotes(bid, ask, mid);
    }

    const elapsed = timer.read();
    const per_call_ns = elapsed / iterations;

    // 每次调用应该 < 200ns
    try testing.expect(per_call_ns < 200);
}
```

---

## 测试覆盖率目标

| 模块 | 目标覆盖率 |
|------|------------|
| inventory.zig | > 90% |
| skew.zig | > 95% |
| rebalance.zig | > 85% |

---

## 运行测试

```bash
# 运行所有库存管理测试
zig build test -- --test-filter="inventory"

# 运行特定测试
zig build test -- --test-filter="linear skew"

# 生成覆盖率报告
zig build test -Dcoverage
```

---

*Last updated: 2025-12-27*
