# Queue Position 测试文档

> 队列位置建模模块的测试策略和用例

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 测试概述

### 测试范围

| 类别 | 描述 | 优先级 |
|------|------|--------|
| 概率模型 | 四种模型的计算正确性 | P0 |
| 队列位置 | 添加/更新/推进 | P0 |
| Level3 订单簿 | FIFO 行为 | P0 |
| 成交判定 | shouldFill 逻辑 | P0 |
| 边界条件 | 空队列、极端位置 | P1 |
| 性能测试 | 大规模订单簿 | P2 |

### 测试文件

```
src/backtest/tests/
├── queue_position_test.zig   # 队列位置测试
├── queue_model_test.zig      # 概率模型测试
├── level3_book_test.zig      # 订单簿测试
└── fill_test.zig             # 成交判定测试
```

---

## 单元测试

### 概率模型测试

```zig
const testing = @import("std").testing;
const QueueModel = @import("../queue_position.zig").QueueModel;

test "RiskAverse: only front fills" {
    // 队头 (x = 0)
    try testing.expectApproxEqAbs(@as(f64, 1.0), QueueModel.RiskAverse.probability(0.0), 0.001);

    // 接近队头 (x = 0.005)
    try testing.expectApproxEqAbs(@as(f64, 1.0), QueueModel.RiskAverse.probability(0.005), 0.001);

    // 非队头 (x = 0.1)
    try testing.expectApproxEqAbs(@as(f64, 0.0), QueueModel.RiskAverse.probability(0.1), 0.001);

    // 队尾 (x = 1.0)
    try testing.expectApproxEqAbs(@as(f64, 0.0), QueueModel.RiskAverse.probability(1.0), 0.001);
}

test "Probability: linear decrease" {
    // 队头
    try testing.expectApproxEqAbs(@as(f64, 1.0), QueueModel.Probability.probability(0.0), 0.001);

    // 中间
    try testing.expectApproxEqAbs(@as(f64, 0.5), QueueModel.Probability.probability(0.5), 0.001);

    // 队尾
    try testing.expectApproxEqAbs(@as(f64, 0.0), QueueModel.Probability.probability(1.0), 0.001);

    // 1/4 位置
    try testing.expectApproxEqAbs(@as(f64, 0.75), QueueModel.Probability.probability(0.25), 0.001);
}

test "PowerLaw: quadratic decrease" {
    // 队头
    try testing.expectApproxEqAbs(@as(f64, 1.0), QueueModel.PowerLaw.probability(0.0), 0.001);

    // 中间 (1 - 0.5^2 = 0.75)
    try testing.expectApproxEqAbs(@as(f64, 0.75), QueueModel.PowerLaw.probability(0.5), 0.001);

    // 队尾
    try testing.expectApproxEqAbs(@as(f64, 0.0), QueueModel.PowerLaw.probability(1.0), 0.001);

    // 1/4 位置 (1 - 0.25^2 = 0.9375)
    try testing.expectApproxEqAbs(@as(f64, 0.9375), QueueModel.PowerLaw.probability(0.25), 0.001);
}

test "Logarithmic: log decrease" {
    // 队头
    try testing.expectApproxEqAbs(@as(f64, 1.0), QueueModel.Logarithmic.probability(0.0), 0.001);

    // 中间 (1 - log(1.5)/log(2) ≈ 0.415)
    try testing.expectApproxEqAbs(@as(f64, 0.415), QueueModel.Logarithmic.probability(0.5), 0.01);

    // 队尾 (1 - log(2)/log(2) = 0)
    try testing.expectApproxEqAbs(@as(f64, 0.0), QueueModel.Logarithmic.probability(1.0), 0.001);
}

test "probability: clamping out of range" {
    // 负值应该被 clamp 到 0
    try testing.expectApproxEqAbs(@as(f64, 1.0), QueueModel.Probability.probability(-0.5), 0.001);

    // 超过 1 应该被 clamp 到 1
    try testing.expectApproxEqAbs(@as(f64, 0.0), QueueModel.Probability.probability(1.5), 0.001);
}
```

### 队列位置测试

```zig
test "QueuePosition: initialization" {
    const pos = QueuePosition{
        .order_id = "order_1",
        .price_level = Decimal.fromFloat(2000.0),
        .position_in_queue = 5,
        .total_quantity_ahead = Decimal.fromFloat(50.0),
        .initial_quantity_ahead = Decimal.fromFloat(50.0),
        .order_quantity = Decimal.fromFloat(1.0),
        .queued_at = 0,
    };

    try testing.expectEqual(@as(usize, 5), pos.position_in_queue);
    try testing.expect(pos.total_quantity_ahead.eq(Decimal.fromFloat(50.0)));
}

test "QueuePosition: normalizedPosition" {
    const pos = QueuePosition{
        .order_id = "order_1",
        .price_level = Decimal.fromFloat(2000.0),
        .position_in_queue = 0,
        .total_quantity_ahead = Decimal.fromFloat(25.0),
        .initial_quantity_ahead = Decimal.fromFloat(100.0),
        .order_quantity = Decimal.fromFloat(1.0),
        .queued_at = 0,
    };

    // 25 / 100 = 0.25
    try testing.expectApproxEqAbs(@as(f64, 0.25), pos.normalizedPosition(), 0.001);
}

test "QueuePosition: advance" {
    var pos = QueuePosition{
        .order_id = "order_1",
        .price_level = Decimal.fromFloat(2000.0),
        .position_in_queue = 3,
        .total_quantity_ahead = Decimal.fromFloat(30.0),
        .initial_quantity_ahead = Decimal.fromFloat(100.0),
        .order_quantity = Decimal.fromFloat(1.0),
        .queued_at = 0,
    };

    pos.advance(Decimal.fromFloat(10.0));

    try testing.expect(pos.total_quantity_ahead.eq(Decimal.fromFloat(20.0)));
}

test "QueuePosition: isAtFront" {
    var pos = QueuePosition{
        .order_id = "order_1",
        .price_level = Decimal.fromFloat(2000.0),
        .position_in_queue = 0,
        .total_quantity_ahead = Decimal.zero,
        .initial_quantity_ahead = Decimal.fromFloat(100.0),
        .order_quantity = Decimal.fromFloat(1.0),
        .queued_at = 0,
    };

    try testing.expect(pos.isAtFront());

    pos.position_in_queue = 1;
    pos.total_quantity_ahead = Decimal.fromFloat(10.0);
    try testing.expect(!pos.isAtFront());
}

test "QueuePosition: progress" {
    const pos = QueuePosition{
        .order_id = "order_1",
        .price_level = Decimal.fromFloat(2000.0),
        .position_in_queue = 0,
        .total_quantity_ahead = Decimal.fromFloat(25.0),
        .initial_quantity_ahead = Decimal.fromFloat(100.0),
        .order_quantity = Decimal.fromFloat(1.0),
        .queued_at = 0,
    };

    // 消耗了 75%
    try testing.expectApproxEqAbs(@as(f64, 0.75), pos.progress(), 0.001);
}
```

### Level3OrderBook 测试

```zig
test "Level3OrderBook: addOrder queue position" {
    const allocator = testing.allocator;
    var book = Level3OrderBook.init(allocator, "ETH-USD");
    defer book.deinit();

    // 添加第一个订单
    var order1 = createTestOrder("o1", .buy, 2000.0, 10.0);
    try book.addOrder(&order1);

    try testing.expectEqual(@as(usize, 0), order1.queue_position.position_in_queue);
    try testing.expect(order1.queue_position.total_quantity_ahead.eq(Decimal.zero));

    // 添加第二个订单
    var order2 = createTestOrder("o2", .buy, 2000.0, 5.0);
    try book.addOrder(&order2);

    try testing.expectEqual(@as(usize, 1), order2.queue_position.position_in_queue);
    try testing.expect(order2.queue_position.total_quantity_ahead.eq(Decimal.fromFloat(10.0)));

    // 添加第三个订单
    var order3 = createTestOrder("o3", .buy, 2000.0, 8.0);
    try book.addOrder(&order3);

    try testing.expectEqual(@as(usize, 2), order3.queue_position.position_in_queue);
    try testing.expect(order3.queue_position.total_quantity_ahead.eq(Decimal.fromFloat(15.0)));
}

test "Level3OrderBook: onTrade updates positions" {
    const allocator = testing.allocator;
    var book = Level3OrderBook.init(allocator, "ETH-USD");
    defer book.deinit();

    // 添加订单
    var order1 = createTestOrder("o1", .buy, 2000.0, 10.0);
    var order2 = createTestOrder("o2", .buy, 2000.0, 5.0);
    var order3 = createTestOrder("o3", .buy, 2000.0, 8.0);

    try book.addOrder(&order1);
    try book.addOrder(&order2);
    try book.addOrder(&order3);

    // 成交消耗 order1
    const trade = Trade{
        .price = Decimal.fromFloat(2000.0),
        .quantity = Decimal.fromFloat(10.0),
        .side = .buy,
    };
    try book.onTrade(trade);

    // order2 现在在队头
    try testing.expectEqual(@as(usize, 0), order2.queue_position.position_in_queue);
    try testing.expect(order2.queue_position.total_quantity_ahead.eq(Decimal.zero));

    // order3 前进一位
    try testing.expectEqual(@as(usize, 1), order3.queue_position.position_in_queue);
    try testing.expect(order3.queue_position.total_quantity_ahead.eq(Decimal.fromFloat(5.0)));
}

test "Level3OrderBook: partial trade" {
    const allocator = testing.allocator;
    var book = Level3OrderBook.init(allocator, "ETH-USD");
    defer book.deinit();

    var order1 = createTestOrder("o1", .buy, 2000.0, 10.0);
    var order2 = createTestOrder("o2", .buy, 2000.0, 5.0);

    try book.addOrder(&order1);
    try book.addOrder(&order2);

    // 部分成交
    const trade = Trade{
        .price = Decimal.fromFloat(2000.0),
        .quantity = Decimal.fromFloat(3.0),
        .side = .buy,
    };
    try book.onTrade(trade);

    // order1 部分成交，剩余 7
    const o1 = book.orders.get("o1").?;
    try testing.expect(o1.remaining_quantity.eq(Decimal.fromFloat(7.0)));

    // order2 前方数量减少
    try testing.expect(order2.queue_position.total_quantity_ahead.eq(Decimal.fromFloat(7.0)));
}

test "Level3OrderBook: different price levels" {
    const allocator = testing.allocator;
    var book = Level3OrderBook.init(allocator, "ETH-USD");
    defer book.deinit();

    var order1 = createTestOrder("o1", .buy, 2000.0, 10.0);
    var order2 = createTestOrder("o2", .buy, 1999.0, 5.0);

    try book.addOrder(&order1);
    try book.addOrder(&order2);

    // 不同价格层级，各自队头
    try testing.expectEqual(@as(usize, 0), order1.queue_position.position_in_queue);
    try testing.expectEqual(@as(usize, 0), order2.queue_position.position_in_queue);
}
```

### 成交判定测试

```zig
test "shouldFill: at front always fills" {
    var pos = QueuePosition{
        .order_id = "o1",
        .price_level = Decimal.fromFloat(2000.0),
        .position_in_queue = 0,
        .total_quantity_ahead = Decimal.zero,
        .initial_quantity_ahead = Decimal.fromFloat(100.0),
        .order_quantity = Decimal.fromFloat(1.0),
        .queued_at = 0,
    };

    // 队头总是成交，无论随机数
    try testing.expect(pos.shouldFill(.RiskAverse, 0.0));
    try testing.expect(pos.shouldFill(.RiskAverse, 0.5));
    try testing.expect(pos.shouldFill(.RiskAverse, 0.99));
}

test "shouldFill: probability model" {
    var pos = QueuePosition{
        .order_id = "o1",
        .price_level = Decimal.fromFloat(2000.0),
        .position_in_queue = 5,
        .total_quantity_ahead = Decimal.fromFloat(50.0),
        .initial_quantity_ahead = Decimal.fromFloat(100.0),
        .order_quantity = Decimal.fromFloat(1.0),
        .queued_at = 0,
    };

    // normalized = 0.5, prob = 0.5
    // random < 0.5 → fill
    try testing.expect(pos.shouldFill(.Probability, 0.3));
    try testing.expect(pos.shouldFill(.Probability, 0.49));

    // random >= 0.5 → no fill
    try testing.expect(!pos.shouldFill(.Probability, 0.5));
    try testing.expect(!pos.shouldFill(.Probability, 0.8));
}

test "checkMyOrderFill: price mismatch" {
    const allocator = testing.allocator;
    var book = Level3OrderBook.init(allocator, "ETH-USD");
    defer book.deinit();

    var order = createTestOrder("o1", .buy, 2000.0, 1.0);
    order.is_mine = true;
    try book.addOrder(&order);

    // 不同价格的成交
    const trade = Trade{
        .price = Decimal.fromFloat(1999.0), // 不匹配
        .quantity = Decimal.fromFloat(1.0),
        .side = .buy,
    };

    try testing.expect(!book.checkMyOrderFill(&order, trade, .Probability));
}
```

---

## 统计测试

### 模型准确性验证

```zig
test "model statistical accuracy" {
    var rng = std.rand.DefaultPrng.init(42);
    const iterations: u32 = 10000;

    // 测试 normalized = 0.5 时，Probability 模型应该 ~50% 成交
    var fills: u32 = 0;
    var pos = QueuePosition{
        .order_id = "o1",
        .price_level = Decimal.fromFloat(2000.0),
        .position_in_queue = 5,
        .total_quantity_ahead = Decimal.fromFloat(50.0),
        .initial_quantity_ahead = Decimal.fromFloat(100.0),
        .order_quantity = Decimal.fromFloat(1.0),
        .queued_at = 0,
    };

    for (0..iterations) |_| {
        if (pos.shouldFill(.Probability, rng.random().float(f64))) {
            fills += 1;
        }
    }

    const fill_rate = @as(f64, @floatFromInt(fills)) / @as(f64, @floatFromInt(iterations));

    // 允许 5% 误差
    try testing.expect(fill_rate > 0.45 and fill_rate < 0.55);
}
```

---

## 性能测试

```zig
test "benchmark: add 10000 orders" {
    const allocator = testing.allocator;
    var book = Level3OrderBook.init(allocator, "ETH-USD");
    defer book.deinit();

    var timer = std.time.Timer{};
    timer.reset();

    for (0..10000) |i| {
        var order = Order{
            .id = try std.fmt.allocPrint(allocator, "o{}", .{i}),
            .side = .buy,
            .price = Decimal.fromFloat(2000.0),
            .quantity = Decimal.fromFloat(1.0),
        };
        try book.addOrder(&order);
    }

    const elapsed_ms = timer.read() / 1_000_000;
    std.debug.print("\n10000 orders added in {}ms\n", .{elapsed_ms});

    try testing.expect(elapsed_ms < 1000); // < 1秒
}

test "benchmark: fillProbability" {
    const pos = QueuePosition{
        .order_id = "o1",
        .price_level = Decimal.fromFloat(2000.0),
        .position_in_queue = 5,
        .total_quantity_ahead = Decimal.fromFloat(50.0),
        .initial_quantity_ahead = Decimal.fromFloat(100.0),
        .order_quantity = Decimal.fromFloat(1.0),
        .queued_at = 0,
    };

    const iterations: u64 = 1_000_000;
    var timer = std.time.Timer{};
    timer.reset();

    for (0..iterations) |_| {
        _ = pos.fillProbability(.Probability);
    }

    const elapsed_ns = timer.read();
    const per_call_ns = elapsed_ns / iterations;

    std.debug.print("\nfillProbability: {}ns/call\n", .{per_call_ns});
    try testing.expect(per_call_ns < 100); // < 100ns
}
```

---

## 运行测试

```bash
# 运行所有队列位置测试
zig build test -- --test-filter="queue"

# 运行模型测试
zig build test -- --test-filter="QueueModel"

# 运行性能测试
zig build test -- --test-filter="benchmark"
```

---

*Last updated: 2025-12-27*
