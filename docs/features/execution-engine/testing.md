# ExecutionEngine - 测试文档

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 测试策略

### 测试层级

| 层级 | 描述 | 覆盖率目标 |
|------|------|------------|
| 单元测试 | 订单追踪和状态管理 | > 90% |
| 集成测试 | 交易所模拟集成 | > 80% |
| 恢复测试 | 故障恢复场景 | 100% |
| 性能测试 | 订单吞吐量 | 基准达标 |

---

## 单元测试

### 1. 订单前置追踪测试

```zig
test "track order - adds to pending" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var mock_exchange = MockExchange.init();
    var engine = try ExecutionEngine.init(
        testing.allocator,
        &bus,
        &cache,
        &mock_exchange,
        .{},
    );
    defer engine.deinit();

    const order = Order{
        .id = "order-123",
        .instrument_id = "BTC-USDT",
        .side = .buy,
        .quantity = 1.0,
    };

    try engine.trackOrder(order);

    try testing.expect(engine.isOrderPending("order-123"));
    try testing.expect(cache.getOrder("order-123") != null);
}

test "track order - publishes pending event" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var pending_received = false;
    try bus.subscribe("order.pending", struct {
        fn handler(_: Event) void { pending_received = true; }
    }.handler);

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var mock_exchange = MockExchange.init();
    var engine = try ExecutionEngine.init(
        testing.allocator,
        &bus,
        &cache,
        &mock_exchange,
        .{},
    );
    defer engine.deinit();

    try engine.trackOrder(.{ .id = "order-123" });

    try testing.expect(pending_received);
}
```

### 2. 订单提交测试

```zig
test "submit order - success" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var mock_exchange = MockExchange.init();
    mock_exchange.submit_result = .success;

    var engine = try ExecutionEngine.init(
        testing.allocator,
        &bus,
        &cache,
        &mock_exchange,
        .{},
    );
    defer engine.deinit();

    const order = Order{ .id = "order-123" };
    try engine.trackOrder(order);
    try engine.submitOrder(order);

    // 验证订单状态
    const cached = cache.getOrder("order-123");
    try testing.expect(cached != null);
    try testing.expectEqual(OrderStatus.submitted, cached.?.status);
}

test "submit order - retry on timeout" {
    var mock_exchange = MockExchange.init();
    mock_exchange.fail_count = 2;  // 前两次失败
    mock_exchange.submit_result = .timeout;

    // ... 初始化 engine ...

    const order = Order{ .id = "order-123" };
    try engine.trackOrder(order);
    try engine.submitOrder(order);

    // 验证重试次数
    try testing.expectEqual(@as(u32, 3), mock_exchange.call_count);
}

test "submit order - max retries exceeded" {
    var mock_exchange = MockExchange.init();
    mock_exchange.submit_result = .timeout;

    // ... 初始化 engine (max_retries = 3) ...

    const order = Order{ .id = "order-123" };
    try engine.trackOrder(order);

    const result = engine.submitOrder(order);
    try testing.expectError(error.MaxRetriesExceeded, result);
}
```

### 3. 订单取消测试

```zig
test "cancel order - success" {
    // ... 初始化 ...

    const order = Order{ .id = "order-123" };
    try engine.trackOrder(order);
    try engine.submitOrder(order);

    // 模拟订单被接受
    engine.onExchangeOrderUpdate(.{
        .order_accepted = .{ .client_order_id = "order-123" },
    });

    try engine.cancelOrder("order-123");

    const cached = cache.getOrder("order-123");
    try testing.expectEqual(OrderStatus.cancelled, cached.?.status);
}

test "cancel order - not found" {
    // ... 初始化 ...

    const result = engine.cancelOrder("nonexistent");
    try testing.expectError(error.OrderNotFound, result);
}

test "cancel all orders - with filter" {
    // ... 初始化 ...

    // 添加多个订单
    try engine.trackOrder(.{ .id = "btc-1", .instrument_id = "BTC-USDT" });
    try engine.trackOrder(.{ .id = "btc-2", .instrument_id = "BTC-USDT" });
    try engine.trackOrder(.{ .id = "eth-1", .instrument_id = "ETH-USDT" });

    // 取消 BTC 订单
    const result = try engine.cancelAllOrders(.{ .instrument_id = "BTC-USDT" });

    try testing.expectEqual(@as(u32, 2), result.cancelled_count);
}
```

### 4. 订单确认测试

```zig
test "order confirmation - moves to tracked" {
    // ... 初始化 ...

    const order = Order{ .id = "order-123" };
    try engine.trackOrder(order);
    try engine.submitOrder(order);

    try testing.expect(engine.isOrderPending("order-123"));

    // 模拟交易所确认
    engine.onExchangeOrderUpdate(.{
        .order_accepted = .{
            .client_order_id = "order-123",
            .status = .accepted,
        },
    });

    try testing.expect(!engine.isOrderPending("order-123"));
    try testing.expect(engine.tracked_orders.contains("order-123"));
}

test "order fill - updates quantity" {
    // ... 初始化 ...

    const order = Order{
        .id = "order-123",
        .quantity = 1.0,
        .filled_quantity = 0,
    };
    try engine.trackOrder(order);

    // 部分成交
    engine.onExchangeOrderUpdate(.{
        .order_filled = .{
            .order = .{
                .client_order_id = "order-123",
                .filled_quantity = 0.5,
                .status = .partially_filled,
            },
            .fill_price = 50000,
            .fill_quantity = 0.5,
        },
    });

    const cached = cache.getOrder("order-123");
    try testing.expectEqual(@as(f64, 0.5), cached.?.filled_quantity);
}
```

---

## 恢复测试

### 订单恢复场景

```zig
test "recovery - pending orders confirmed by exchange" {
    // ... 初始化 ...

    // 添加 pending 订单
    try engine.trackOrder(.{ .id = "order-123" });

    // 模拟交易所返回已确认订单
    mock_exchange.open_orders = &[_]ExchangeOrder{
        .{ .client_order_id = "order-123", .status = .accepted },
    };

    const result = try engine.recoverOrders();

    try testing.expectEqual(@as(u32, 1), result.recovered_count);
    try testing.expect(!engine.isOrderPending("order-123"));
    try testing.expect(engine.tracked_orders.contains("order-123"));
}

test "recovery - stale orders on exchange" {
    // ... 初始化 ...

    // 交易所有订单但本地没有
    mock_exchange.open_orders = &[_]ExchangeOrder{
        .{ .id = "unknown-order", .status = .accepted },
    };

    const result = try engine.recoverOrders();

    try testing.expectEqual(@as(u32, 1), result.stale_count);
}

test "recovery - expired pending orders" {
    // ... 初始化 ...

    // 添加过期的 pending 订单
    var old_order = Order{ .id = "order-123" };
    old_order.created_at = std.time.milliTimestamp() - 60000;  // 1 分钟前
    engine.pending_orders.put("order-123", old_order);

    _ = try engine.recoverOrders();

    // 过期订单应该被清理
    try testing.expect(!engine.isOrderPending("order-123"));
}
```

---

## 集成测试

### MessageBus 集成

```zig
test "integration - submit via message bus" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = try Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var mock_exchange = MockExchange.init();
    var engine = try ExecutionEngine.init(
        testing.allocator,
        &bus,
        &cache,
        &mock_exchange,
        .{},
    );
    defer engine.deinit();

    // 通过 MessageBus 提交订单
    const response = try bus.request("order.submit", .{
        .submit_order = .{
            .instrument_id = "BTC-USDT",
            .side = .buy,
            .quantity = 1.0,
        },
    });

    try testing.expect(response.order_submitted.order_id.len > 0);
}

test "integration - order events flow" {
    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var events = std.ArrayList([]const u8).init(testing.allocator);
    defer events.deinit();

    try bus.subscribe("order.*", struct {
        fn handler(event: Event) void {
            events.append(@tagName(event)) catch {};
        }
    }.handler);

    // ... 初始化 engine ...

    const order = Order{ .id = "order-123" };
    try engine.trackOrder(order);
    try engine.submitOrder(order);

    // 模拟交易所确认
    engine.onExchangeOrderUpdate(.{ .order_accepted = .{ .client_order_id = "order-123" } });

    // 验证事件顺序
    try testing.expectEqual(@as(usize, 3), events.items.len);
    try testing.expectEqualStrings("order_pending", events.items[0]);
    try testing.expectEqualStrings("order_submitted", events.items[1]);
    try testing.expectEqualStrings("order_accepted", events.items[2]);
}
```

---

## 性能测试

### 订单吞吐量测试

```zig
test "order throughput" {
    // ... 初始化 ...

    const iterations: u64 = 10_000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const id = try std.fmt.allocPrint(testing.allocator, "order-{}", .{i});
        defer testing.allocator.free(id);

        try engine.trackOrder(.{ .id = id });
        try engine.submitOrder(.{ .id = id });
    }

    const elapsed_ns = std.time.nanoTimestamp() - start;
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const throughput = @as(f64, @floatFromInt(iterations)) / (elapsed_ms / 1000.0);

    std.debug.print("Order throughput: {d:.0} orders/sec\n", .{throughput});

    // 目标: > 10,000 orders/sec
    try testing.expect(throughput > 10_000);
}
```

---

## Mock 交易所

```zig
const MockExchange = struct {
    submit_result: SubmitResult = .success,
    cancel_result: CancelResult = .success,
    fail_count: u32 = 0,
    call_count: u32 = 0,
    open_orders: []const ExchangeOrder = &.{},

    pub fn submitOrder(self: *MockExchange, order: OrderRequest) SubmitResult {
        self.call_count += 1;
        if (self.call_count <= self.fail_count) {
            return self.submit_result;
        }
        return .success;
    }

    pub fn cancelOrder(self: *MockExchange, order_id: []const u8) CancelResult {
        _ = order_id;
        return self.cancel_result;
    }

    pub fn getOpenOrders(self: *MockExchange) []const ExchangeOrder {
        return self.open_orders;
    }
};
```

---

## 测试矩阵

| 测试类别 | 测试数量 | 状态 |
|----------|----------|------|
| 订单追踪 | 4 | 📋 计划中 |
| 订单提交 | 5 | 📋 计划中 |
| 订单取消 | 4 | 📋 计划中 |
| 订单确认 | 4 | 📋 计划中 |
| 订单恢复 | 4 | 📋 计划中 |
| MessageBus 集成 | 3 | 📋 计划中 |
| 性能测试 | 2 | 📋 计划中 |

---

## 运行测试

```bash
# 运行所有 ExecutionEngine 测试
zig build test -- --test-filter="execution"

# 运行恢复测试
zig build test -- --test-filter="execution.*recovery"

# 运行性能测试
zig build test -- --test-filter="execution.*throughput"
```

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [实现细节](./implementation.md)

---

**版本**: v0.5.0
**状态**: 计划中
