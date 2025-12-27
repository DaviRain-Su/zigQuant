# Cache - 测试文档

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 测试策略

### 测试层级

| 层级 | 描述 | 覆盖率目标 |
|------|------|------------|
| 单元测试 | 核心查询和更新 | > 90% |
| 集成测试 | MessageBus 集成 | > 80% |
| 性能测试 | 查询延迟 | 基准达标 |

---

## 单元测试

### 1. 订单缓存测试

```zig
test "get order - exists" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    const order = Order{
        .id = "order-123",
        .instrument_id = "BTC-USDT",
        .status = .accepted,
        // ...
    };
    try cache.updateOrder(order);

    const result = cache.getOrder("order-123");
    try testing.expect(result != null);
    try testing.expectEqualStrings("order-123", result.?.id);
}

test "get order - not exists" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    const result = cache.getOrder("nonexistent");
    try testing.expect(result == null);
}

test "get orders by instrument" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    // 添加多个订单
    try cache.updateOrder(.{ .id = "order-1", .instrument_id = "BTC-USDT" });
    try cache.updateOrder(.{ .id = "order-2", .instrument_id = "BTC-USDT" });
    try cache.updateOrder(.{ .id = "order-3", .instrument_id = "ETH-USDT" });

    const btc_orders = try cache.getOrdersByInstrument("BTC-USDT");
    defer testing.allocator.free(btc_orders);

    try testing.expectEqual(@as(usize, 2), btc_orders.len);
}

test "get open orders" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    try cache.updateOrder(.{ .id = "order-1", .status = .accepted });
    try cache.updateOrder(.{ .id = "order-2", .status = .filled });
    try cache.updateOrder(.{ .id = "order-3", .status = .partially_filled });

    const open_orders = try cache.getOpenOrders();
    defer testing.allocator.free(open_orders);

    try testing.expectEqual(@as(usize, 2), open_orders.len);
}
```

### 2. 仓位缓存测试

```zig
test "get position - exists" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    try cache.updatePosition(.{
        .instrument_id = "BTC-USDT",
        .quantity = 1.5,
        .entry_price = 50000.0,
    });

    const result = cache.getPosition("BTC-USDT");
    try testing.expect(result != null);
    try testing.expectEqual(@as(f64, 1.5), result.?.quantity);
}

test "get all positions" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    try cache.updatePosition(.{ .instrument_id = "BTC-USDT" });
    try cache.updatePosition(.{ .instrument_id = "ETH-USDT" });

    const positions = try cache.getAllPositions();
    defer testing.allocator.free(positions);

    try testing.expectEqual(@as(usize, 2), positions.len);
}

test "position removal" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    try cache.updatePosition(.{ .instrument_id = "BTC-USDT" });
    try testing.expect(cache.getPosition("BTC-USDT") != null);

    cache.removePosition("BTC-USDT");
    try testing.expect(cache.getPosition("BTC-USDT") == null);
}
```

### 3. 报价缓存测试

```zig
test "get quote" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    try cache.updateQuote(.{
        .instrument_id = "BTC-USDT",
        .bid = 50000.0,
        .ask = 50001.0,
    });

    const quote = cache.getQuote("BTC-USDT");
    try testing.expect(quote != null);
    try testing.expectEqual(@as(f64, 50000.0), quote.?.bid);
    try testing.expectEqual(@as(f64, 50001.0), quote.?.ask);
}

test "get mid price" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    try cache.updateQuote(.{
        .instrument_id = "BTC-USDT",
        .bid = 50000.0,
        .ask = 50002.0,
    });

    const mid = cache.getMidPrice("BTC-USDT");
    try testing.expect(mid != null);
    try testing.expectEqual(@as(f64, 50001.0), mid.?);
}
```

---

## 集成测试

### 1. MessageBus 事件集成

```zig
test "cache updates on order event" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{ .auto_subscribe = true });
    defer cache.deinit();

    // 发布订单事件
    try bus.publish("order.accepted", .{
        .order_accepted = .{
            .id = "order-123",
            .instrument_id = "BTC-USDT",
            .status = .accepted,
        },
    });

    // 验证缓存已更新
    const order = cache.getOrder("order-123");
    try testing.expect(order != null);
    try testing.expectEqual(OrderStatus.accepted, order.?.status);
}

test "cache updates on position event" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{ .auto_subscribe = true });
    defer cache.deinit();

    // 发布仓位事件
    try bus.publish("position.opened", .{
        .position_opened = .{
            .instrument_id = "BTC-USDT",
            .quantity = 1.0,
        },
    });

    // 验证缓存已更新
    const position = cache.getPosition("BTC-USDT");
    try testing.expect(position != null);
}

test "cache updates on market data event" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{ .auto_subscribe = true });
    defer cache.deinit();

    // 发布市场数据事件
    try bus.publish("market_data.BTC-USDT", .{
        .market_data = .{
            .instrument_id = "BTC-USDT",
            .bid = 50000.0,
            .ask = 50001.0,
        },
    });

    // 验证缓存已更新
    const quote = cache.getQuote("BTC-USDT");
    try testing.expect(quote != null);
}
```

### 2. 快照测试

```zig
test "snapshot and restore" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    // 添加数据
    try cache.updateOrder(.{ .id = "order-1" });
    try cache.updatePosition(.{ .instrument_id = "BTC-USDT" });

    // 创建快照
    const snapshot = try cache.takeSnapshot(testing.allocator);
    defer {
        testing.allocator.free(snapshot.orders);
        testing.allocator.free(snapshot.positions);
    }

    // 清空缓存
    cache.orders.clearRetainingCapacity();
    cache.positions.clearRetainingCapacity();

    try testing.expect(cache.getOrder("order-1") == null);

    // 从快照恢复
    try cache.restoreFromSnapshot(snapshot);

    try testing.expect(cache.getOrder("order-1") != null);
    try testing.expect(cache.getPosition("BTC-USDT") != null);
}
```

---

## 性能测试

### 1. 查询延迟测试

```zig
test "order lookup latency" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    // 预填充大量订单
    for (0..10000) |i| {
        const id = try std.fmt.allocPrint(testing.allocator, "order-{}", .{i});
        defer testing.allocator.free(id);
        try cache.updateOrder(.{ .id = id });
    }

    // 测量查询延迟
    var latencies = std.ArrayList(i64).init(testing.allocator);
    defer latencies.deinit();

    for (0..1000) |_| {
        const start = std.time.nanoTimestamp();
        _ = cache.getOrder("order-5000");
        const elapsed = std.time.nanoTimestamp() - start;
        try latencies.append(elapsed);
    }

    // 计算平均延迟
    var total: i64 = 0;
    for (latencies.items) |l| {
        total += l;
    }
    const avg = @divTrunc(total, @as(i64, @intCast(latencies.items.len)));

    std.debug.print("Average lookup latency: {} ns\n", .{avg});

    // 目标: < 100ns
    try testing.expect(avg < 100);
}
```

### 2. 更新吞吐量测试

```zig
test "update throughput" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    const iterations: u64 = 100_000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const id = try std.fmt.allocPrint(testing.allocator, "order-{}", .{i % 1000});
        defer testing.allocator.free(id);
        try cache.updateOrder(.{ .id = id });
    }

    const elapsed_ns = std.time.nanoTimestamp() - start;
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const throughput = @as(f64, @floatFromInt(iterations)) / (elapsed_ms / 1000.0);

    std.debug.print("Update throughput: {d:.0} updates/sec\n", .{throughput});

    // 目标: > 100,000 updates/sec
    try testing.expect(throughput > 100_000);
}
```

---

## 测试矩阵

| 测试类别 | 测试数量 | 状态 |
|----------|----------|------|
| 订单缓存 | 6 | 📋 计划中 |
| 仓位缓存 | 4 | 📋 计划中 |
| 账户缓存 | 3 | 📋 计划中 |
| 报价缓存 | 4 | 📋 计划中 |
| MessageBus 集成 | 5 | 📋 计划中 |
| 快照功能 | 3 | 📋 计划中 |
| 性能测试 | 4 | 📋 计划中 |

---

## 运行测试

```bash
# 运行所有 Cache 测试
zig build test -- --test-filter="cache"

# 运行性能测试
zig build test -- --test-filter="cache.*latency"

# 运行集成测试
zig build test -- --test-filter="cache.*integration"
```

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [实现细节](./implementation.md)

---

**版本**: v0.5.0
**状态**: 计划中
