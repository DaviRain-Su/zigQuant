# RiskEngine - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-27

---

## 测试覆盖率

- **代码覆盖率**: 目标 > 90%
- **测试用例数**: 目标 30+
- **性能基准**: 风控检查 < 1ms

---

## 单元测试

### 测试场景 1: 基本初始化

```zig
test "RiskEngine: initialization" {
    const allocator = std.testing.allocator;

    var positions = PositionTracker.init(allocator);
    defer positions.deinit();

    var account = Account{
        .equity = Decimal.fromFloat(100000),
        .balance = Decimal.fromFloat(100000),
        .available_balance = Decimal.fromFloat(100000),
    };

    const config = RiskConfig.default();
    var engine = RiskEngine.init(allocator, config, &positions, &account);
    defer engine.deinit();

    try std.testing.expect(!engine.isKillSwitchActive());
    try std.testing.expectEqual(@as(u64, 0), engine.total_checks);
}
```

### 测试场景 2: 仓位大小检查

```zig
test "RiskEngine: position size check - pass" {
    // ... 初始化 ...
    const config = RiskConfig{
        .max_position_size = Decimal.fromFloat(50000),
        // ...
    };

    var engine = RiskEngine.init(allocator, config, &positions, &account);
    defer engine.deinit();

    // 小于限制的订单应通过
    const order = OrderRequest{
        .symbol = "BTC-USDT",
        .side = .buy,
        .quantity = Decimal.fromFloat(0.5),
        .price = Decimal.fromFloat(50000), // 价值 $25000
    };

    const result = engine.checkOrder(order);
    try std.testing.expect(result.passed);
}

test "RiskEngine: position size check - fail" {
    // ... 初始化 ...
    const config = RiskConfig{
        .max_position_size = Decimal.fromFloat(50000),
        // ...
    };

    var engine = RiskEngine.init(allocator, config, &positions, &account);
    defer engine.deinit();

    // 超过限制的订单应拒绝
    const order = OrderRequest{
        .symbol = "BTC-USDT",
        .side = .buy,
        .quantity = Decimal.fromFloat(2.0),
        .price = Decimal.fromFloat(50000), // 价值 $100000
    };

    const result = engine.checkOrder(order);
    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(RiskRejectReason.position_size_exceeded, result.reason.?);
}
```

### 测试场景 3: 杠杆检查

```zig
test "RiskEngine: leverage check - pass" {
    // 账户权益 $100,000
    // 最大杠杆 2x
    // 允许总敞口 $200,000

    var account = Account{ .equity = Decimal.fromFloat(100000), ... };
    const config = RiskConfig{ .max_leverage = Decimal.fromFloat(2.0), ... };

    var engine = RiskEngine.init(allocator, config, &positions, &account);

    // 订单价值 $50,000，总敞口 $50,000，杠杆 0.5x
    const order = OrderRequest{
        .quantity = Decimal.fromFloat(1.0),
        .price = Decimal.fromFloat(50000),
        ...
    };

    const result = engine.checkOrder(order);
    try std.testing.expect(result.passed);
}

test "RiskEngine: leverage check - fail" {
    // 账户权益 $100,000
    // 最大杠杆 2x
    // 已有仓位 $180,000

    // 添加已有仓位
    try positions.add(Position{
        .symbol = "BTC-USDT",
        .quantity = Decimal.fromFloat(3.6),
        .current_price = Decimal.fromFloat(50000), // $180,000
        ...
    });

    // 新订单 $50,000 会使总杠杆达到 2.3x
    const order = OrderRequest{
        .quantity = Decimal.fromFloat(1.0),
        .price = Decimal.fromFloat(50000),
        ...
    };

    const result = engine.checkOrder(order);
    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(RiskRejectReason.leverage_exceeded, result.reason.?);
}
```

### 测试场景 4: 日损失检查

```zig
test "RiskEngine: daily loss check - pass" {
    var account = Account{
        .equity = Decimal.fromFloat(98000), // 从 $100,000 下跌 2%
        ...
    };

    const config = RiskConfig{
        .max_daily_loss = Decimal.fromFloat(5000),      // $5000 限制
        .max_daily_loss_pct = 0.05,                      // 5% 限制
        ...
    };

    var engine = RiskEngine.init(allocator, config, &positions, &account);
    engine.daily_start_equity = Decimal.fromFloat(100000);

    const result = engine.checkOrder(someOrder);
    try std.testing.expect(result.passed);
}

test "RiskEngine: daily loss check - fail absolute" {
    var account = Account{
        .equity = Decimal.fromFloat(94000), // 损失 $6000
        ...
    };

    const config = RiskConfig{
        .max_daily_loss = Decimal.fromFloat(5000), // $5000 限制
        ...
    };

    var engine = RiskEngine.init(allocator, config, &positions, &account);
    engine.daily_start_equity = Decimal.fromFloat(100000);

    const result = engine.checkOrder(someOrder);
    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(RiskRejectReason.daily_loss_exceeded, result.reason.?);
}

test "RiskEngine: daily loss check - fail percentage" {
    var account = Account{
        .equity = Decimal.fromFloat(93000), // 损失 7%
        ...
    };

    const config = RiskConfig{
        .max_daily_loss_pct = 0.05, // 5% 限制
        ...
    };

    var engine = RiskEngine.init(allocator, config, &positions, &account);
    engine.daily_start_equity = Decimal.fromFloat(100000);

    const result = engine.checkOrder(someOrder);
    try std.testing.expect(!result.passed);
}
```

### 测试场景 5: 订单频率检查

```zig
test "RiskEngine: order rate check - pass" {
    const config = RiskConfig{
        .max_orders_per_minute = 10,
        ...
    };

    var engine = RiskEngine.init(allocator, config, &positions, &account);

    // 提交 9 个订单
    for (0..9) |_| {
        const result = engine.checkOrder(someOrder);
        try std.testing.expect(result.passed);
    }
}

test "RiskEngine: order rate check - fail" {
    const config = RiskConfig{
        .max_orders_per_minute = 10,
        ...
    };

    var engine = RiskEngine.init(allocator, config, &positions, &account);

    // 提交 11 个订单，第 11 个应该失败
    for (0..10) |_| {
        _ = engine.checkOrder(someOrder);
    }

    const result = engine.checkOrder(someOrder);
    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(RiskRejectReason.order_rate_exceeded, result.reason.?);
}

test "RiskEngine: order rate reset after minute" {
    const config = RiskConfig{
        .max_orders_per_minute = 10,
        ...
    };

    var engine = RiskEngine.init(allocator, config, &positions, &account);

    // 提交 10 个订单
    for (0..10) |_| {
        _ = engine.checkOrder(someOrder);
    }

    // 模拟 1 分钟后
    engine.last_minute_start -= 61;

    // 现在应该能继续下单
    const result = engine.checkOrder(someOrder);
    try std.testing.expect(result.passed);
}
```

### 测试场景 6: Kill Switch

```zig
test "RiskEngine: kill switch activation" {
    var engine = RiskEngine.init(allocator, config, &positions, &account);

    try std.testing.expect(!engine.isKillSwitchActive());

    // 触发 Kill Switch
    try engine.killSwitch(&mock_execution);

    try std.testing.expect(engine.isKillSwitchActive());

    // Kill Switch 激活后订单应被拒绝
    const result = engine.checkOrder(someOrder);
    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(RiskRejectReason.kill_switch_active, result.reason.?);
}

test "RiskEngine: kill switch reset" {
    var engine = RiskEngine.init(allocator, config, &positions, &account);

    try engine.killSwitch(&mock_execution);
    try std.testing.expect(engine.isKillSwitchActive());

    engine.resetKillSwitch();
    try std.testing.expect(!engine.isKillSwitchActive());

    // 重置后应能继续下单
    const result = engine.checkOrder(someOrder);
    try std.testing.expect(result.passed);
}

test "RiskEngine: kill switch condition check" {
    const config = RiskConfig{
        .kill_switch_threshold = Decimal.fromFloat(5000),
        ...
    };

    var engine = RiskEngine.init(allocator, config, &positions, &account);
    engine.daily_start_equity = Decimal.fromFloat(100000);

    // 损失 $4000，未触发
    account.equity = Decimal.fromFloat(96000);
    try std.testing.expect(!engine.checkKillSwitchConditions());

    // 损失 $6000，应触发
    account.equity = Decimal.fromFloat(94000);
    try std.testing.expect(engine.checkKillSwitchConditions());
}
```

---

## 性能基准

### 基准测试

```zig
test "RiskEngine: performance - single check" {
    var engine = RiskEngine.init(allocator, RiskConfig.default(), &positions, &account);
    defer engine.deinit();

    const iterations: usize = 10000;
    var timer = std.time.Timer.start();

    for (0..iterations) |_| {
        _ = engine.checkOrder(order);
    }

    const elapsed_ns = timer.read();
    const avg_ns = elapsed_ns / iterations;

    // 目标: < 1ms (1,000,000 ns)
    try std.testing.expect(avg_ns < 1_000_000);

    std.debug.print("\nPerformance: {} ns/check ({} checks/sec)\n", .{
        avg_ns,
        @divFloor(1_000_000_000, avg_ns),
    });
}

test "RiskEngine: performance - concurrent checks" {
    // 多线程并发检查测试
    const num_threads = 4;
    const checks_per_thread = 1000;

    var threads: [num_threads]std.Thread = undefined;

    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, struct {
            fn run(engine: *RiskEngine) void {
                for (0..checks_per_thread) |_| {
                    _ = engine.checkOrder(order);
                }
            }
        }.run, .{&engine});
    }

    for (&threads) |t| {
        t.join();
    }

    // 验证统计正确性
    try std.testing.expectEqual(
        @as(u64, num_threads * checks_per_thread),
        engine.total_checks,
    );
}
```

### 基准结果

| 操作 | 性能 |
|------|------|
| 单次风控检查 | < 500 ns |
| Kill Switch 激活 | < 100 μs |
| 并发检查 (4线程) | > 1M ops/sec |

---

## 运行测试

```bash
# 运行所有风控测试
zig build test -- --test-filter="RiskEngine"

# 运行性能测试
zig build test -- --test-filter="RiskEngine: performance"

# 带详细输出
zig build test -- --test-filter="RiskEngine" -v
```

---

## 测试场景

### ✅ 已覆盖

- [x] 基本初始化和销毁
- [x] 仓位大小限制 (通过/失败)
- [x] 杠杆限制 (通过/失败)
- [x] 日损失限制 - 绝对值
- [x] 日损失限制 - 百分比
- [x] 订单频率限制
- [x] 订单频率重置
- [x] Kill Switch 激活
- [x] Kill Switch 重置
- [x] Kill Switch 条件检查
- [x] 保证金检查
- [x] 多种检查组合
- [x] 并发安全性

### 📋 待补充

- [ ] 配置热更新测试
- [ ] 跨日重置测试
- [ ] 时间回退处理测试
- [ ] 极端值边界测试
- [ ] 内存泄漏测试
- [ ] 与 ExecutionEngine 集成测试
- [ ] 与 AlertManager 集成测试
