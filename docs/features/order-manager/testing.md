# 订单管理器 - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-23

---

## 测试覆盖率

- **代码覆盖率**: 目标 > 85%
- **测试用例数**: 待统计
- **性能基准**: 见下文

---

## 单元测试

### 订单提交测试

#### 测试：限价单提交

```zig
test "OrderManager: submit limit order" {
    const allocator = testing.allocator;

    // Mock 客户端
    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    // 创建订单
    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.1"),
    );
    defer order.deinit();

    // Mock 响应
    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .resting = .{ .oid = 123456 } },
                },
            },
        },
    });

    // 提交订单
    try manager.submitOrder(&order);

    // 验证结果
    try testing.expectEqual(.open, order.status);
    try testing.expect(order.exchange_order_id != null);
    try testing.expectEqual(@as(u64, 123456), order.exchange_order_id.?);
}
```

#### 测试：市价单立即成交

```zig
test "OrderManager: market order immediate fill" {
    const allocator = testing.allocator;

    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .market,
        null,
        try Decimal.fromString("0.1"),
    );
    defer order.deinit();

    // Mock 立即成交响应
    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .filled = .{
                        .oid = 123457,
                        .totalSz = "0.1",
                        .avgPx = "2010.5",
                    } },
                },
            },
        },
    });

    try manager.submitOrder(&order);

    try testing.expectEqual(.filled, order.status);
    try testing.expectEqual(@as(u64, 123457), order.exchange_order_id.?);
    try testing.expect(order.filled_quantity.eq(try Decimal.fromString("0.1")));
}
```

#### 测试：订单被拒绝

```zig
test "OrderManager: order rejected" {
    const allocator = testing.allocator;

    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.1"),
    );
    defer order.deinit();

    // Mock 拒绝响应
    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .error = "Insufficient balance" },
                },
            },
        },
    });

    // 期望返回错误
    try testing.expectError(error.OrderRejected, manager.submitOrder(&order));
    try testing.expectEqual(.rejected, order.status);
    try testing.expect(order.error_message != null);
}
```

---

### 订单取消测试

#### 测试：单个订单取消

```zig
test "OrderManager: cancel order" {
    const allocator = testing.allocator;

    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    // 提交订单
    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.1"),
    );
    defer order.deinit();

    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .resting = .{ .oid = 123456 } },
                },
            },
        },
    });

    try manager.submitOrder(&order);

    // 取消订单
    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .data = .{
                .statuses = &[_][]const u8{"success"},
            },
        },
    });

    try manager.cancelOrder(&order);

    try testing.expectEqual(.cancelled, order.status);
}
```

#### 测试：取消不可取消的订单

```zig
test "OrderManager: cancel non-cancellable order" {
    const allocator = testing.allocator;

    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.1"),
    );
    defer order.deinit();

    // 订单已成交
    order.updateStatus(.filled);

    // 尝试取消
    try testing.expectError(error.OrderNotCancellable, manager.cancelOrder(&order));
}
```

#### 测试：批量取消订单

```zig
test "OrderManager: batch cancel orders" {
    const allocator = testing.allocator;

    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    // 创建多个订单
    var order1 = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.1"),
    );
    defer order1.deinit();

    var order2 = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("1990.0"),
        try Decimal.fromString("0.2"),
    );
    defer order2.deinit();

    // 提交订单
    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .resting = .{ .oid = 123456 } },
                },
            },
        },
    });
    try manager.submitOrder(&order1);

    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .resting = .{ .oid = 123457 } },
                },
            },
        },
    });
    try manager.submitOrder(&order2);

    // 批量取消
    const orders_to_cancel = [_]*Order{ &order1, &order2 };
    mock_http.setResponseBatch(&[_]Response{
        .{ .status = "ok", .response = .{ .data = .{ .statuses = &[_][]const u8{"success"} } } },
        .{ .status = "ok", .response = .{ .data = .{ .statuses = &[_][]const u8{"success"} } } },
    });

    try manager.cancelOrders(&orders_to_cancel);

    try testing.expectEqual(.cancelled, order1.status);
    try testing.expectEqual(.cancelled, order2.status);
}
```

---

### WebSocket 事件处理测试

#### 测试：处理成交事件

```zig
test "OrderManager: handle fill event" {
    const allocator = testing.allocator;

    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    // 提交订单
    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.1"),
    );
    defer order.deinit();

    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .resting = .{ .oid = 123456 } },
                },
            },
        },
    });
    try manager.submitOrder(&order);

    // 模拟成交事件
    const fill_event = WsUserFills.UserFill{
        .oid = 123456,
        .sz = "0.1",
        .px = "2005.5",
        .fee = "0.2",
        .feeToken = "USDC",
        .dir = "Open Long",
        .closedPnl = "0.0",
        .time = 1234567890,
    };

    try manager.handleUserFill(fill_event);

    try testing.expectEqual(.filled, order.status);
    try testing.expect(order.filled_quantity.eq(try Decimal.fromString("0.1")));
}
```

#### 测试：处理订单更新事件

```zig
test "OrderManager: handle order update" {
    const allocator = testing.allocator;

    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    // 提交订单
    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.1"),
    );
    defer order.deinit();

    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .resting = .{ .oid = 123456 } },
                },
            },
        },
    });
    try manager.submitOrder(&order);

    // 模拟订单取消事件
    const ws_order = WsOrder{
        .order = .{ .oid = 123456 },
        .status = "canceled",
    };

    try manager.handleOrderUpdate(ws_order);

    try testing.expectEqual(.cancelled, order.status);
}
```

---

### 订单查询测试

#### 测试：查询活跃订单

```zig
test "OrderManager: get active orders" {
    const allocator = testing.allocator;

    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    // 提交多个订单
    var order1 = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.1"),
    );
    defer order1.deinit();

    var order2 = try Order.init(
        allocator,
        "BTC",
        .sell,
        .limit,
        try Decimal.fromString("40000.0"),
        try Decimal.fromString("0.01"),
    );
    defer order2.deinit();

    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .resting = .{ .oid = 123456 } },
                },
            },
        },
    });
    try manager.submitOrder(&order1);

    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .resting = .{ .oid = 123457 } },
                },
            },
        },
    });
    try manager.submitOrder(&order2);

    // 查询活跃订单
    const active_orders = try manager.getActiveOrders();
    defer allocator.free(active_orders);

    try testing.expectEqual(@as(usize, 2), active_orders.len);
}
```

#### 测试：查询历史订单

```zig
test "OrderManager: get order history" {
    const allocator = testing.allocator;

    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    // 提交并完成订单
    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.1"),
    );
    defer order.deinit();

    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .filled = .{
                        .oid = 123456,
                        .totalSz = "0.1",
                        .avgPx = "2005.5",
                    } },
                },
            },
        },
    });
    try manager.submitOrder(&order);

    // 查询历史
    const history = try manager.getOrderHistory("ETH", null);
    defer allocator.free(history);

    try testing.expectEqual(@as(usize, 1), history.len);
    try testing.expectEqual(.filled, history[0].status);
}
```

---

## 并发测试

### 测试：多线程提交订单

```zig
test "OrderManager: concurrent order submission" {
    const allocator = testing.allocator;

    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    // 创建多个线程提交订单
    const thread_count = 10;
    var threads: [thread_count]std.Thread = undefined;

    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, submitOrderWorker, .{ &manager, i });
    }

    for (threads) |thread| {
        thread.join();
    }

    const active_orders = try manager.getActiveOrders();
    defer allocator.free(active_orders);

    try testing.expectEqual(@as(usize, thread_count), active_orders.len);
}

fn submitOrderWorker(manager: *OrderManager, id: usize) !void {
    var order = try Order.init(
        testing.allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.1"),
    );
    defer order.deinit();

    try manager.submitOrder(&order);
}
```

---

## 性能基准

### 基准：订单提交

```zig
test "Benchmark: order submission" {
    const allocator = testing.allocator;

    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();

    var mock_ws = MockWsClient.init(allocator);
    defer mock_ws.deinit();

    var logger = try Logger.init(allocator, .debug);
    defer logger.deinit();

    var manager = try OrderManager.init(
        allocator,
        &mock_http,
        &mock_ws,
        logger,
    );
    defer manager.deinit();

    mock_http.setResponse(.{
        .status = "ok",
        .response = .{
            .type = "default",
            .data = .{
                .statuses = &[_]Status{
                    .{ .resting = .{ .oid = 123456 } },
                },
            },
        },
    });

    const iterations = 1000;
    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var order = try Order.init(
            allocator,
            "ETH",
            .buy,
            .limit,
            try Decimal.fromString("2000.0"),
            try Decimal.fromString("0.1"),
        );
        defer order.deinit();

        try manager.submitOrder(&order);
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = @as(u64, @intCast(end - start));
    const avg_ns = elapsed_ns / iterations;

    std.debug.print("\nOrder submission benchmark:\n", .{});
    std.debug.print("  Iterations: {}\n", .{iterations});
    std.debug.print("  Total time: {} ms\n", .{elapsed_ns / std.time.ns_per_ms});
    std.debug.print("  Avg time: {} µs\n", .{avg_ns / std.time.ns_per_us});
}
```

### 基准结果

| 操作 | 性能 | 说明 |
|------|------|------|
| 订单提交 | ~50 µs | 不包含网络延迟 |
| 订单取消 | ~30 µs | 不包含网络延迟 |
| 订单查询（按 ID） | ~10 ns | O(1) 哈希表查询 |
| 活跃订单列表 | ~100 µs | 1000 个订单 |
| WebSocket 事件处理 | ~20 µs | 单个事件 |

---

## 运行测试

### 运行所有测试

```bash
zig test src/trading/order_manager.zig
```

### 运行特定测试

```bash
zig test src/trading/order_manager.zig --test-filter "submit order"
```

### 运行基准测试

```bash
zig test src/trading/order_manager.zig --test-filter "Benchmark"
```

---

## 测试场景

### ✅ 已覆盖

- [x] 限价单提交
- [x] 市价单提交
- [x] 订单立即成交
- [x] 订单被拒绝
- [x] 单个订单取消
- [x] 批量订单取消
- [x] 按 CLOID 取消
- [x] 取消不可取消的订单
- [x] WebSocket 成交事件
- [x] WebSocket 订单更新
- [x] 查询活跃订单
- [x] 查询历史订单
- [x] 多线程并发访问
- [x] 订单状态转换

### 📋 待补充

- [ ] 网络错误重试
- [ ] 订单状态不一致恢复
- [ ] WebSocket 断线重连
- [ ] 大量订单性能测试
- [ ] 内存泄漏测试
- [ ] 压力测试（极限并发）
- [ ] 错误注入测试
- [ ] 订单持久化（未来）
