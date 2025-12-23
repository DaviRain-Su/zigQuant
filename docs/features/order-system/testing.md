# 订单系统 - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-23

---

## 测试覆盖率

- **代码覆盖率**: 目标 90%+
- **测试用例数**: 30+
- **性能基准**: 见下文

---

## 单元测试

### 1. 订单创建测试

#### 测试场景: 创建限价买单

```zig
test "Order: create limit buy order" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    try testing.expectEqual(.buy, order.side);
    try testing.expectEqual(.limit, order.order_type);
    try testing.expectEqualStrings("ETH", order.symbol);
    try testing.expect(order.price.?.eq(try Decimal.fromString("2000.0")));
    try testing.expect(order.quantity.eq(try Decimal.fromString("1.0")));
    try testing.expectEqual(.pending, order.status);
}
```

#### 测试场景: 创建限价卖单

```zig
test "Order: create limit sell order" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "BTC",
        .sell,
        .limit,
        try Decimal.fromString("50000.0"),
        try Decimal.fromString("0.5"),
    );
    defer order.deinit();

    try testing.expectEqual(.sell, order.side);
    try testing.expectEqual(.limit, order.order_type);
    try testing.expectEqualStrings("BTC", order.symbol);
}
```

#### 测试场景: 创建触发单

```zig
test "Order: create trigger order" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .sell,
        .trigger,
        null,  // 触发单可以不指定价格
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    order.trigger_price = try Decimal.fromString("1900.0");
    try testing.expectEqual(.trigger, order.order_type);
    try testing.expect(order.price == null);
    try testing.expect(order.trigger_price != null);
}
```

---

### 2. 订单验证测试

#### 测试场景: 验证成功

```zig
test "Order: validation success" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    // 应该验证通过
    try order.validate();
}
```

#### 测试场景: 数量无效

```zig
test "Order: invalid quantity" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        Decimal.ZERO,  // ❌ 数量为 0
    );
    defer order.deinit();

    try testing.expectError(error.InvalidQuantity, order.validate());
}
```

#### 测试场景: 限价单缺少价格

```zig
test "Order: limit order missing price" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        null,  // ❌ 限价单必须有价格
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    try testing.expectError(error.MissingPrice, order.validate());
}
```

#### 测试场景: 价格无效

```zig
test "Order: invalid price" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("-100.0"),  // ❌ 负价格
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    try testing.expectError(error.InvalidPrice, order.validate());
}
```

#### 测试场景: 空符号

```zig
test "Order: empty symbol" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "",  // ❌ 空符号
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    try testing.expectError(error.EmptySymbol, order.validate());
}
```

---

### 3. 订单状态转换测试

#### 测试场景: 正常状态流转

```zig
test "Order: status transitions" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    // pending -> submitted
    try testing.expectEqual(.pending, order.status);
    order.updateStatus(.submitted);
    try testing.expectEqual(.submitted, order.status);
    try testing.expect(order.submitted_at != null);

    // submitted -> open
    order.updateStatus(.open);
    try testing.expectEqual(.open, order.status);

    // open -> filled
    order.updateStatus(.filled);
    try testing.expectEqual(.filled, order.status);
    try testing.expect(order.filled_at != null);
    try testing.expect(order.filled_quantity.eq(order.quantity));
    try testing.expect(order.remaining_quantity.eq(Decimal.ZERO));
}
```

#### 测试场景: 订单被拒绝

```zig
test "Order: status rejected" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    order.updateStatus(.submitted);
    order.updateStatus(.rejected);

    try testing.expectEqual(.rejected, order.status);
    try testing.expect(order.status.isFinal());
}
```

#### 测试场景: 订单被取消

```zig
test "Order: status canceled" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    order.updateStatus(.open);
    try testing.expect(order.isCancellable());

    order.updateStatus(.canceled);
    try testing.expectEqual(.canceled, order.status);
    try testing.expect(order.status.isFinal());
    try testing.expect(!order.isCancellable());
}
```

---

### 4. 订单成交更新测试

#### 测试场景: 部分成交

```zig
test "Order: partial fill" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("10.0"),
    );
    defer order.deinit();

    // 成交 5.0
    order.updateFill(
        try Decimal.fromString("5.0"),
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );

    try testing.expect(order.filled_quantity.eq(try Decimal.fromString("5.0")));
    try testing.expect(order.remaining_quantity.eq(try Decimal.fromString("5.0")));
    try testing.expect(order.avg_fill_price.?.eq(try Decimal.fromString("2000.0")));
    try testing.expect(order.total_fee.eq(try Decimal.fromString("1.0")));
}
```

#### 测试场景: 完全成交

```zig
test "Order: full fill" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("10.0"),
    );
    defer order.deinit();

    order.updateStatus(.open);

    // 完全成交
    order.updateFill(
        try Decimal.fromString("10.0"),
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("2.0"),
    );

    try testing.expect(order.isFilled());
    try testing.expectEqual(.filled, order.status);
    try testing.expect(order.remaining_quantity.eq(Decimal.ZERO));
}
```

#### 测试场景: 多次成交平均价计算

```zig
test "Order: multiple fills average price" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("10.0"),
    );
    defer order.deinit();

    // 第一次成交: 5.0 @ 2000.0
    order.updateFill(
        try Decimal.fromString("5.0"),
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );

    // 第二次成交: 5.0 @ 2010.0
    order.updateFill(
        try Decimal.fromString("5.0"),
        try Decimal.fromString("2010.0"),
        try Decimal.fromString("1.0"),
    );

    // 平均价应该是 (5.0 * 2000.0 + 5.0 * 2010.0) / 10.0 = 2005.0
    const expected_avg = try Decimal.fromString("2005.0");
    try testing.expect(order.avg_fill_price.?.eq(expected_avg));
    try testing.expect(order.total_fee.eq(try Decimal.fromString("2.0")));
}
```

#### 测试场景: 成交百分比

```zig
test "Order: fill percentage" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("10.0"),
    );
    defer order.deinit();

    // 成交 3.0 / 10.0 = 30%
    order.updateFill(
        try Decimal.fromString("3.0"),
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("0.5"),
    );

    const percentage = order.getFillPercentage();
    const expected = try Decimal.fromString("0.3");
    try testing.expect(percentage.eq(expected));
}
```

---

### 5. OrderBuilder 测试

#### 测试场景: Builder 基本使用

```zig
test "OrderBuilder: basic usage" {
    const allocator = testing.allocator;

    var builder = try OrderBuilder.init(allocator, "ETH", .buy);
    var order = try builder
        .withOrderType(.limit)
        .withPrice(try Decimal.fromString("2000.0"))
        .withQuantity(try Decimal.fromString("1.0"))
        .build();
    defer order.deinit();

    try testing.expectEqual(.buy, order.side);
    try testing.expectEqualStrings("ETH", order.symbol);
    try testing.expectEqual(.limit, order.order_type);
}
```

#### 测试场景: Builder 设置时效

```zig
test "OrderBuilder: with time in force" {
    const allocator = testing.allocator;

    var builder = try OrderBuilder.init(allocator, "ETH", .buy);
    var order = try builder
        .withOrderType(.limit)
        .withPrice(try Decimal.fromString("2000.0"))
        .withQuantity(try Decimal.fromString("1.0"))
        .withTimeInForce(.ioc)
        .build();
    defer order.deinit();

    try testing.expectEqual(.ioc, order.time_in_force);
}
```

#### 测试场景: Builder 设置只减仓

```zig
test "OrderBuilder: with reduce only" {
    const allocator = testing.allocator;

    var builder = try OrderBuilder.init(allocator, "BTC", .sell);
    var order = try builder
        .withOrderType(.limit)
        .withPrice(try Decimal.fromString("50000.0"))
        .withQuantity(try Decimal.fromString("0.1"))
        .withReduceOnly(true)
        .build();
    defer order.deinit();

    try testing.expect(order.reduce_only);
}
```

#### 测试场景: Builder 验证失败

```zig
test "OrderBuilder: validation fails" {
    const allocator = testing.allocator;

    var builder = try OrderBuilder.init(allocator, "ETH", .buy);
    // 不设置价格和数量，应该验证失败
    try testing.expectError(error.InvalidQuantity, builder.build());
}
```

---

### 6. 枚举类型测试

#### 测试场景: TimeInForce 转换

```zig
test "TimeInForce: string conversion" {
    try testing.expectEqualStrings("Gtc", TimeInForce.gtc.toString());
    try testing.expectEqualStrings("Ioc", TimeInForce.ioc.toString());
    try testing.expectEqualStrings("Alo", TimeInForce.alo.toString());

    try testing.expectEqual(.gtc, try TimeInForce.fromString("Gtc"));
    try testing.expectEqual(.ioc, try TimeInForce.fromString("Ioc"));
    try testing.expectEqual(.alo, try TimeInForce.fromString("Alo"));

    try testing.expectError(error.InvalidTimeInForce, TimeInForce.fromString("Invalid"));
}
```

#### 测试场景: OrderStatus 状态判断

```zig
test "OrderStatus: state checks" {
    // 终态测试
    try testing.expect(OrderStatus.filled.isFinal());
    try testing.expect(OrderStatus.canceled.isFinal());
    try testing.expect(OrderStatus.rejected.isFinal());
    try testing.expect(OrderStatus.marginCanceled.isFinal());
    try testing.expect(!OrderStatus.open.isFinal());
    try testing.expect(!OrderStatus.pending.isFinal());

    // 活跃状态测试
    try testing.expect(OrderStatus.open.isActive());
    try testing.expect(OrderStatus.triggered.isActive());
    try testing.expect(!OrderStatus.filled.isActive());
    try testing.expect(!OrderStatus.pending.isActive());
}
```

#### 测试场景: OrderStatus 字符串转换

```zig
test "OrderStatus: string conversion" {
    try testing.expectEqualStrings("open", OrderStatus.open.toString());
    try testing.expectEqualStrings("filled", OrderStatus.filled.toString());
    try testing.expectEqualStrings("canceled", OrderStatus.canceled.toString());

    try testing.expectEqual(.open, try OrderStatus.fromString("open"));
    try testing.expectEqual(.filled, try OrderStatus.fromString("filled"));
    try testing.expectEqual(.rejected, try OrderStatus.fromString("rejected"));

    try testing.expectError(error.InvalidOrderStatus, OrderStatus.fromString("invalid"));
}
```

---

## 性能基准

### 基准测试

#### 基准 1: 订单创建性能

```zig
test "Benchmark: order creation" {
    const allocator = testing.allocator;
    const iterations = 10000;

    const start = std.time.milliTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var order = try Order.init(
            allocator,
            "ETH",
            .buy,
            .limit,
            try Decimal.fromString("2000.0"),
            try Decimal.fromString("1.0"),
        );
        order.deinit();
    }

    const end = std.time.milliTimestamp();
    const elapsed = end - start;

    std.debug.print("Created {d} orders in {d}ms\n", .{ iterations, elapsed });
    std.debug.print("Avg: {d}μs per order\n", .{ elapsed * 1000 / iterations });
}
```

#### 基准 2: 订单验证性能

```zig
test "Benchmark: order validation" {
    const allocator = testing.allocator;
    const iterations = 100000;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    const start = std.time.milliTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        try order.validate();
    }

    const end = std.time.milliTimestamp();
    const elapsed = end - start;

    std.debug.print("Validated {d} times in {d}ms\n", .{ iterations, elapsed });
    std.debug.print("Avg: {d}ns per validation\n", .{ elapsed * 1000000 / iterations });
}
```

#### 基准 3: 成交更新性能

```zig
test "Benchmark: fill update" {
    const allocator = testing.allocator;
    const iterations = 50000;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("10000.0"),  // 大数量
    );
    defer order.deinit();

    const start = std.time.milliTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        order.updateFill(
            try Decimal.fromString("0.1"),
            try Decimal.fromString("2000.0"),
            try Decimal.fromString("0.02"),
        );
    }

    const end = std.time.milliTimestamp();
    const elapsed = end - start;

    std.debug.print("Updated {d} fills in {d}ms\n", .{ iterations, elapsed });
    std.debug.print("Avg: {d}μs per fill\n", .{ elapsed * 1000 / iterations });
}
```

### 基准结果（目标）

| 操作 | 性能 | 说明 |
|------|------|------|
| 订单创建 | < 100μs | 包含内存分配 |
| 订单验证 | < 1μs | 纯计算，O(1) |
| 成交更新 | < 5μs | 包含平均价计算 |
| Builder 构建 | < 150μs | 链式调用 + 验证 |

---

## 运行测试

### 运行所有测试

```bash
zig test src/core/order_test.zig
```

### 运行特定测试

```bash
zig test src/core/order_test.zig --test-filter "Order: validation"
```

### 运行基准测试

```bash
zig test src/core/order_test.zig --test-filter "Benchmark"
```

---

## 测试场景

### ✅ 已覆盖

- [x] 订单创建（各种类型）
- [x] 订单验证（正常和异常）
- [x] 状态转换（所有路径）
- [x] 成交更新（部分/完全成交）
- [x] 平均成交价计算
- [x] OrderBuilder 流畅 API
- [x] 枚举类型转换
- [x] 状态判断辅助函数
- [x] 内存管理（无泄漏）
- [x] 边界情况处理

### 📋 待补充

- [ ] 并发访问测试（多线程场景）
- [ ] 大数量订单压力测试
- [ ] 异常恢复测试
- [ ] JSON 序列化/反序列化测试
- [ ] Hyperliquid API 适配测试

---

*测试文件位置: `src/core/order_test.zig`*
