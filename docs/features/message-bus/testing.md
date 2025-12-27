# MessageBus - 测试文档

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 测试策略

### 测试层级

| 层级 | 描述 | 覆盖率目标 |
|------|------|------------|
| 单元测试 | 核心功能测试 | > 90% |
| 集成测试 | 组件交互测试 | > 80% |
| 性能测试 | 吞吐量和延迟 | 基准达标 |

---

## 单元测试

### 1. Publish-Subscribe 测试

```zig
test "publish to single subscriber" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var received = false;
    try bus.subscribe("test.topic", struct {
        fn handler(_: Event) void {
            received = true;
        }
    }.handler);

    try bus.publish("test.topic", .{ .tick = .{} });
    try testing.expect(received);
}

test "publish to multiple subscribers" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var count: u32 = 0;
    const handler = struct {
        fn handler(_: Event) void {
            count += 1;
        }
    }.handler;

    try bus.subscribe("test.topic", handler);
    try bus.subscribe("test.topic", handler);

    try bus.publish("test.topic", .{ .tick = .{} });
    try testing.expectEqual(@as(u32, 2), count);
}

test "no subscribers - no error" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    // 没有订阅者，发布不应出错
    try bus.publish("test.topic", .{ .tick = .{} });
}
```

### 2. 通配符匹配测试

```zig
test "wildcard subscription - match" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var received = false;
    try bus.subscribe("market_data.*", struct {
        fn handler(_: Event) void {
            received = true;
        }
    }.handler);

    try bus.publish("market_data.BTC-USDT", .{ .market_data = .{} });
    try testing.expect(received);
}

test "wildcard subscription - no match" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var received = false;
    try bus.subscribe("order.*", struct {
        fn handler(_: Event) void {
            received = true;
        }
    }.handler);

    try bus.publish("market_data.BTC-USDT", .{ .market_data = .{} });
    try testing.expect(!received);
}

test "exact match priority" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var exact_count: u32 = 0;
    var wildcard_count: u32 = 0;

    try bus.subscribe("market_data.BTC-USDT", struct {
        fn handler(_: Event) void {
            exact_count += 1;
        }
    }.handler);

    try bus.subscribe("market_data.*", struct {
        fn handler(_: Event) void {
            wildcard_count += 1;
        }
    }.handler);

    try bus.publish("market_data.BTC-USDT", .{ .market_data = .{} });

    // 两个都应该收到
    try testing.expectEqual(@as(u32, 1), exact_count);
    try testing.expectEqual(@as(u32, 1), wildcard_count);
}
```

### 3. Request-Response 测试

```zig
test "request-response success" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    try bus.register("order.validate", struct {
        fn handler(req: Request) !Response {
            return .{ .order_validated = .{ .valid = true } };
        }
    }.handler);

    const response = try bus.request("order.validate", .{
        .validate_order = .{ .quantity = 1.0 },
    });

    try testing.expect(response.order_validated.valid);
}

test "request to unregistered endpoint" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    const result = bus.request("nonexistent.endpoint", .{});
    try testing.expectError(error.EndpointNotFound, result);
}

test "request handler error propagation" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    try bus.register("order.validate", struct {
        fn handler(req: Request) !Response {
            return error.ValidationFailed;
        }
    }.handler);

    const result = bus.request("order.validate", .{});
    try testing.expectError(error.ValidationFailed, result);
}
```

### 4. 取消订阅测试

```zig
test "unsubscribe handler" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var count: u32 = 0;
    const handler = struct {
        fn handler(_: Event) void {
            count += 1;
        }
    }.handler;

    try bus.subscribe("test.topic", handler);
    try bus.publish("test.topic", .{ .tick = .{} });
    try testing.expectEqual(@as(u32, 1), count);

    bus.unsubscribe("test.topic", handler);
    try bus.publish("test.topic", .{ .tick = .{} });
    try testing.expectEqual(@as(u32, 1), count);  // 不再增加
}
```

---

## 集成测试

### 1. 策略集成测试

```zig
test "strategy receives market data" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var strategy = TestStrategy.init(&bus);
    defer strategy.deinit();

    // 发布市场数据
    try bus.publish("market_data.BTC-USDT", .{
        .market_data = .{
            .instrument_id = "BTC-USDT",
            .bid = 50000.0,
            .ask = 50001.0,
        },
    });

    try testing.expect(strategy.data_received);
}

test "order lifecycle events" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var events_received = std.ArrayList([]const u8).init(testing.allocator);
    defer events_received.deinit();

    // 订阅所有订单事件
    try bus.subscribe("order.*", struct {
        fn handler(event: Event) void {
            events_received.append(event.getTypeName()) catch {};
        }
    }.handler);

    // 模拟订单生命周期
    try bus.publish("order.submitted", .{ .order_submitted = .{} });
    try bus.publish("order.accepted", .{ .order_accepted = .{} });
    try bus.publish("order.filled", .{ .order_filled = .{} });

    try testing.expectEqual(@as(usize, 3), events_received.items.len);
}
```

### 2. Cache 集成测试

```zig
test "cache updates on events" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(testing.allocator, &bus);
    defer cache.deinit();

    // 发布仓位更新事件
    try bus.publish("position.updated", .{
        .position_updated = .{
            .instrument_id = "BTC-USDT",
            .quantity = 1.0,
        },
    });

    // 验证 Cache 已更新
    const position = cache.getPosition("BTC-USDT");
    try testing.expect(position != null);
    try testing.expectEqual(@as(f64, 1.0), position.?.quantity);
}
```

---

## 性能测试

### 1. 吞吐量测试

```zig
test "publish throughput" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var count: u64 = 0;
    try bus.subscribe("test.topic", struct {
        fn handler(_: Event) void {
            count += 1;
        }
    }.handler);

    const start = std.time.nanoTimestamp();
    const iterations: u64 = 100_000;

    for (0..iterations) |_| {
        try bus.publish("test.topic", .{ .tick = .{} });
    }

    const elapsed_ns = std.time.nanoTimestamp() - start;
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const throughput = @as(f64, @floatFromInt(iterations)) / (elapsed_ms / 1000.0);

    std.debug.print("Throughput: {d:.0} events/sec\n", .{throughput});

    // 目标: > 100,000 events/sec
    try testing.expect(throughput > 100_000);
}
```

### 2. 延迟测试

```zig
test "publish latency" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var latencies = std.ArrayList(i64).init(testing.allocator);
    defer latencies.deinit();

    try bus.subscribe("test.topic", struct {
        fn handler(event: Event) void {
            const now = std.time.nanoTimestamp();
            const latency = now - event.tick.timestamp;
            latencies.append(latency) catch {};
        }
    }.handler);

    for (0..1000) |_| {
        try bus.publish("test.topic", .{
            .tick = .{ .timestamp = std.time.nanoTimestamp() },
        });
    }

    // 计算 P50, P99
    std.sort.sort(i64, latencies.items, {}, std.sort.asc(i64));
    const p50 = latencies.items[latencies.items.len / 2];
    const p99 = latencies.items[@as(usize, @intFromFloat(@as(f64, @floatFromInt(latencies.items.len)) * 0.99))];

    std.debug.print("P50 latency: {} ns\n", .{p50});
    std.debug.print("P99 latency: {} ns\n", .{p99});

    // 目标: P99 < 1ms (1,000,000 ns)
    try testing.expect(p99 < 1_000_000);
}
```

### 3. 内存测试

```zig
test "zero allocation during publish" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    try bus.subscribe("test.topic", struct {
        fn handler(_: Event) void {}
    }.handler);

    // 使用 FailingAllocator 确保发布时无分配
    const failing_allocator = testing.FailingAllocator.init(testing.allocator, 0);

    // 发布应该不需要分配
    try bus.publish("test.topic", .{ .tick = .{} });
}
```

---

## 测试矩阵

| 测试类别 | 测试数量 | 状态 |
|----------|----------|------|
| Publish-Subscribe | 8 | 📋 计划中 |
| Wildcard Matching | 5 | 📋 计划中 |
| Request-Response | 6 | 📋 计划中 |
| Unsubscribe | 3 | 📋 计划中 |
| 集成测试 | 5 | 📋 计划中 |
| 性能测试 | 4 | 📋 计划中 |

---

## 运行测试

```bash
# 运行所有 MessageBus 测试
zig build test -- --test-filter="message_bus"

# 运行性能测试
zig build test -- --test-filter="message_bus.*throughput"

# 运行带详细输出
zig build test -- --test-filter="message_bus" -Dlog
```

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [实现细节](./implementation.md)

---

**版本**: v0.5.0
**状态**: 计划中
