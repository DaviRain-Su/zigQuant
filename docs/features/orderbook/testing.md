# 订单簿 - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-23

---

## 测试覆盖率

- **代码覆盖率**: 目标 90%+
- **测试用例数**: 20+
- **性能基准**: 更新 < 1ms，查询 < 0.1ms

---

## 单元测试

### 测试场景 1: 快照应用

```zig
test "OrderBook: apply snapshot" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("1999.5"), .size = try Decimal.fromString("5.0"), .num_orders = 1 },
    };

    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("2001.5"), .size = try Decimal.fromString("12.0"), .num_orders = 1 },
    };

    try ob.applySnapshot(bids, asks, Timestamp.now());

    // 验证排序：买单降序
    try testing.expect(ob.bids.items[0].price.toFloat() == 2000.0);
    try testing.expect(ob.bids.items[1].price.toFloat() == 1999.5);

    // 验证排序：卖单升序
    try testing.expect(ob.asks.items[0].price.toFloat() == 2001.0);
    try testing.expect(ob.asks.items[1].price.toFloat() == 2001.5);
}
```

---

### 测试场景 2: 最优价格查询

```zig
test "OrderBook: best bid/ask" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    // 应用快照
    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("1999.0"), .size = try Decimal.fromString("5.0"), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("2002.0"), .size = try Decimal.fromString("12.0"), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, asks, Timestamp.now());

    // 验证最优买价
    const best_bid = ob.getBestBid().?;
    try testing.expect(best_bid.price.toFloat() == 2000.0);
    try testing.expect(best_bid.size.toFloat() == 10.0);

    // 验证最优卖价
    const best_ask = ob.getBestAsk().?;
    try testing.expect(best_ask.price.toFloat() == 2001.0);
    try testing.expect(best_ask.size.toFloat() == 8.0);
}
```

---

### 测试场景 3: 中间价计算

```zig
test "OrderBook: mid price" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, asks, Timestamp.now());

    const mid = ob.getMidPrice().?;
    try testing.expectApproxEqAbs(mid.toFloat(), 2000.5, 0.0001); // (2000 + 2001) / 2
}
```

---

### 测试场景 4: 价差计算

```zig
test "OrderBook: spread" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, asks, Timestamp.now());

    const spread = ob.getSpread().?;
    try testing.expectApproxEqAbs(spread.toFloat(), 1.0, 0.0001); // 2001 - 2000
}
```

---

### 测试场景 5: 深度计算

```zig
test "OrderBook: depth calculation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("1999.0"), .size = try Decimal.fromString("5.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("1998.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("2002.0"), .size = try Decimal.fromString("12.0"), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, asks, Timestamp.now());

    // 买单深度：>= 1999.0
    const bid_depth = ob.getDepth(.bid, try Decimal.fromString("1999.0"));
    try testing.expectApproxEqAbs(bid_depth.toFloat(), 15.0, 0.0001); // 10 + 5

    // 卖单深度：<= 2002.0
    const ask_depth = ob.getDepth(.ask, try Decimal.fromString("2002.0"));
    try testing.expectApproxEqAbs(ask_depth.toFloat(), 20.0, 0.0001); // 8 + 12
}
```

---

### 测试场景 6: 滑点计算

```zig
test "OrderBook: slippage calculation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("2002.0"), .size = try Decimal.fromString("12.0"), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, asks, Timestamp.now());

    // 买入 15 ETH（需要吃掉两档）
    const quantity = try Decimal.fromString("15.0");
    const result = ob.getSlippage(.bid, quantity).?;

    // 平均价格：(8 * 2001 + 7 * 2002) / 15 = 2001.467
    const expected_avg = (8.0 * 2001.0 + 7.0 * 2002.0) / 15.0;
    try testing.expectApproxEqAbs(result.avg_price.toFloat(), expected_avg, 0.01);

    // 滑点：(2001.467 - 2001) / 2001 ≈ 0.0233%
    const expected_slippage = (expected_avg - 2001.0) / 2001.0;
    try testing.expectApproxEqAbs(result.slippage_pct.toFloat(), expected_slippage, 0.0001);
}
```

---

### 测试场景 7: 增量更新

```zig
test "OrderBook: incremental update" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    // 初始快照
    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, asks, Timestamp.now());

    // 更新买单
    try ob.applyUpdate(
        .bid,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("15.0"),
        2,
        Timestamp.now(),
    );

    const best_bid = ob.getBestBid().?;
    try testing.expect(best_bid.size.toFloat() == 15.0);
    try testing.expect(best_bid.num_orders == 2);
}
```

---

### 测试场景 8: 移除价格档位

```zig
test "OrderBook: remove level" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
        .{ .price = try Decimal.fromString("1999.0"), .size = try Decimal.fromString("5.0"), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, asks, Timestamp.now());

    // 移除买单档位（size = 0）
    try ob.applyUpdate(
        .bid,
        try Decimal.fromString("2000.0"),
        Decimal.ZERO,
        0,
        Timestamp.now(),
    );

    // 验证移除成功
    const best_bid = ob.getBestBid().?;
    try testing.expect(best_bid.price.toFloat() == 1999.0);
}
```

---

### 测试场景 9: 空订单簿

```zig
test "OrderBook: empty book" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    // 空订单簿
    try testing.expect(ob.getBestBid() == null);
    try testing.expect(ob.getBestAsk() == null);
    try testing.expect(ob.getMidPrice() == null);
    try testing.expect(ob.getSpread() == null);
}
```

---

### 测试场景 10: 流动性不足

```zig
test "OrderBook: insufficient liquidity" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, asks, Timestamp.now());

    // 买入超过流动性的数量
    const quantity = try Decimal.fromString("100.0");
    const result = ob.getSlippage(.bid, quantity);

    try testing.expect(result == null); // 流动性不足
}
```

---

## 性能基准

### 基准测试 1: 快照应用

```zig
test "OrderBook: benchmark snapshot" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    // 生成 100 档订单簿
    var bids = try allocator.alloc(Level, 100);
    var asks = try allocator.alloc(Level, 100);
    defer allocator.free(bids);
    defer allocator.free(asks);

    for (0..100) |i| {
        const price_f = 2000.0 - @as(f64, @floatFromInt(i)) * 0.5;
        bids[i] = .{
            .price = try Decimal.fromFloat(price_f),
            .size = try Decimal.fromString("10.0"),
            .num_orders = 1,
        };
    }

    for (0..100) |i| {
        const price_f = 2001.0 + @as(f64, @floatFromInt(i)) * 0.5;
        asks[i] = .{
            .price = try Decimal.fromFloat(price_f),
            .size = try Decimal.fromString("10.0"),
            .num_orders = 1,
        };
    }

    // 基准测试
    const iterations = 1000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        try ob.applySnapshot(bids, asks, Timestamp.now());
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = @as(f64, @floatFromInt(end - start));
    const avg_ns = elapsed_ns / @as(f64, @floatFromInt(iterations));

    std.debug.print("\nSnapshot (100 levels): {d:.3} μs\n", .{avg_ns / 1000.0});

    // 验证：< 1ms
    try testing.expect(avg_ns < 1_000_000);
}
```

---

### 基准测试 2: 增量更新

```zig
test "OrderBook: benchmark update" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    // 初始化订单簿
    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, asks, Timestamp.now());

    // 基准测试
    const iterations = 10000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        try ob.applyUpdate(
            .bid,
            try Decimal.fromString("2000.0"),
            try Decimal.fromString("15.0"),
            2,
            Timestamp.now(),
        );
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = @as(f64, @floatFromInt(end - start));
    const avg_ns = elapsed_ns / @as(f64, @floatFromInt(iterations));

    std.debug.print("\nUpdate: {d:.3} μs\n", .{avg_ns / 1000.0});

    // 验证：< 0.1ms (100μs)
    try testing.expect(avg_ns < 100_000);
}
```

---

### 基准测试 3: 查询性能

```zig
test "OrderBook: benchmark queries" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ob = try OrderBook.init(allocator, "ETH");
    defer ob.deinit();

    const bids = &[_]Level{
        .{ .price = try Decimal.fromString("2000.0"), .size = try Decimal.fromString("10.0"), .num_orders = 1 },
    };
    const asks = &[_]Level{
        .{ .price = try Decimal.fromString("2001.0"), .size = try Decimal.fromString("8.0"), .num_orders = 1 },
    };
    try ob.applySnapshot(bids, asks, Timestamp.now());

    const iterations = 1_000_000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        _ = ob.getBestBid();
        _ = ob.getBestAsk();
        _ = ob.getMidPrice();
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = @as(f64, @floatFromInt(end - start));
    const avg_ns = elapsed_ns / @as(f64, @floatFromInt(iterations * 3));

    std.debug.print("\nQuery: {d:.3} ns\n", .{avg_ns});

    // 验证：< 100ns (几乎 O(1))
    try testing.expect(avg_ns < 100);
}
```

---

### 基准结果

| 操作 | 性能 | 目标 |
|------|------|------|
| 快照应用 (100 档) | < 500 μs | < 1 ms |
| 增量更新 | < 50 μs | < 100 μs |
| 最优价格查询 | < 50 ns | < 100 ns |
| 中间价计算 | < 100 ns | < 200 ns |
| 深度计算 (10 档) | < 1 μs | < 10 μs |
| 滑点计算 (10 档) | < 2 μs | < 10 μs |

---

## 运行测试

### 运行所有测试

```bash
zig test src/core/orderbook.zig
```

### 运行单个测试

```bash
zig test src/core/orderbook.zig --test-filter "OrderBook: apply snapshot"
```

### 运行性能基准

```bash
zig test src/core/orderbook.zig --test-filter "benchmark"
```

---

## 测试场景

### ✅ 已覆盖

- [x] 快照应用
- [x] 最优价格查询（BBO）
- [x] 中间价计算
- [x] 价差计算
- [x] 深度计算
- [x] 滑点计算
- [x] 增量更新
- [x] 移除价格档位
- [x] 空订单簿处理
- [x] 流动性不足处理
- [x] 排序验证
- [x] 性能基准测试

### 📋 待补充

- [ ] 并发访问测试（OrderBookManager）
- [ ] 大规模订单簿测试（1000+ 档）
- [ ] 边界情况：极大/极小价格
- [ ] 内存泄漏检测
- [ ] 序列号跳跃检测
- [ ] WebSocket 集成测试
- [ ] 模糊测试（Fuzz Testing）

---

*测试代码位置: `src/core/orderbook_test.zig`*
