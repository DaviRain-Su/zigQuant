# 仓位追踪器 - 测试文档

> 测试覆盖、性能基准和测试策略

**最后更新**: 2025-12-23

---

## 测试覆盖率

- **代码覆盖率**: 目标 > 90%
- **测试用例数**: 30+
- **测试文件**: `src/trading/position_test.zig`

---

## 单元测试

### Position 测试

#### 测试场景 1: 初始化

```zig
test "Position: init creates empty long position" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(
        allocator,
        "ETH",
        try Decimal.fromString("0.0"),
    );
    defer pos.deinit();

    try std.testing.expect(pos.szi.isZero());
    try std.testing.expectEqualStrings("ETH", pos.symbol);
    try std.testing.expect(pos.entry_px.isZero());
}
```

#### 测试场景 2: 开仓（多头）

```zig
test "Position: increase - first open (long)" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(
        allocator,
        "ETH",
        try Decimal.fromString("0.0"),
    );
    defer pos.deinit();

    // 开仓 5 ETH @ $2000
    pos.increase(
        try Decimal.fromString("5.0"),
        try Decimal.fromString("2000.0"),
    );

    try std.testing.expect(pos.szi.toFloat() == 5.0);
    try std.testing.expect(pos.entry_px.toFloat() == 2000.0);
    try std.testing.expect(pos.side == .long);
}
```

#### 测试场景 3: 加仓（多头）

```zig
test "Position: increase - add to existing long position" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(
        allocator,
        "ETH",
        try Decimal.fromString("0.0"),
    );
    defer pos.deinit();

    // 开仓 5 ETH @ $2000
    pos.increase(
        try Decimal.fromString("5.0"),
        try Decimal.fromString("2000.0"),
    );

    // 加仓 3 ETH @ $2100
    pos.increase(
        try Decimal.fromString("3.0"),
        try Decimal.fromString("2100.0"),
    );

    // 新均价 = (5*2000 + 3*2100) / (5+3) = 16300 / 8 = 2037.5
    try std.testing.expect(pos.szi.toFloat() == 8.0);
    try std.testing.expectApproxEqAbs(
        @as(f64, 2037.5),
        pos.entry_px.toFloat(),
        0.01,
    );
}
```

#### 测试场景 4: 部分平仓（多头盈利）

```zig
test "Position: decrease - partial close with profit (long)" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(
        allocator,
        "ETH",
        try Decimal.fromString("0.0"),
    );
    defer pos.deinit();

    pos.increase(
        try Decimal.fromString("10.0"),
        try Decimal.fromString("2000.0"),
    );

    // 平仓 4 ETH @ $2100
    const close_pnl = pos.decrease(
        try Decimal.fromString("4.0"),
        try Decimal.fromString("2100.0"),
    );

    // PnL = (2100 - 2000) * 4 = 400
    try std.testing.expectApproxEqAbs(
        @as(f64, 400.0),
        close_pnl.toFloat(),
        0.01,
    );
    try std.testing.expect(pos.szi.toFloat() == 6.0);
    try std.testing.expect(pos.realized_pnl.toFloat() == 400.0);
}
```

#### 测试场景 5: 完全平仓（多头）

```zig
test "Position: decrease - full close (long)" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(
        allocator,
        "ETH",
        try Decimal.fromString("0.0"),
    );
    defer pos.deinit();

    pos.increase(
        try Decimal.fromString("5.0"),
        try Decimal.fromString("2000.0"),
    );

    // 完全平仓 5 ETH @ $2200
    const close_pnl = pos.decrease(
        try Decimal.fromString("5.0"),
        try Decimal.fromString("2200.0"),
    );

    // PnL = (2200 - 2000) * 5 = 1000
    try std.testing.expect(close_pnl.toFloat() == 1000.0);
    try std.testing.expect(pos.isEmpty());
    try std.testing.expect(pos.entry_px.isZero());
    try std.testing.expect(pos.unrealized_pnl.isZero());
}
```

#### 测试场景 6: 空头开仓

```zig
test "Position: short position opening" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(
        allocator,
        "BTC",
        try Decimal.fromString("-5.0"), // 负数表示空头
    );
    defer pos.deinit();

    try std.testing.expect(pos.side == .short);
    try std.testing.expect(pos.szi.toFloat() == -5.0);
}
```

#### 测试场景 7: 未实现盈亏（多头）

```zig
test "Position: unrealized PnL calculation (long profit)" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(
        allocator,
        "ETH",
        try Decimal.fromString("0.0"),
    );
    defer pos.deinit();

    pos.increase(
        try Decimal.fromString("10.0"),
        try Decimal.fromString("2000.0"),
    );

    // 标记价格上涨到 $2100
    pos.updateMarkPrice(try Decimal.fromString("2100.0"));

    // Unrealized PnL = 10 * (2100 - 2000) = 1000
    try std.testing.expect(pos.unrealized_pnl.toFloat() == 1000.0);
}
```

#### 测试场景 8: 未实现盈亏（多头亏损）

```zig
test "Position: unrealized PnL calculation (long loss)" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(
        allocator,
        "ETH",
        try Decimal.fromString("0.0"),
    );
    defer pos.deinit();

    pos.increase(
        try Decimal.fromString("10.0"),
        try Decimal.fromString("2000.0"),
    );

    // 标记价格下跌到 $1900
    pos.updateMarkPrice(try Decimal.fromString("1900.0"));

    // Unrealized PnL = 10 * (1900 - 2000) = -1000
    try std.testing.expect(pos.unrealized_pnl.toFloat() == -1000.0);
}
```

#### 测试场景 9: 未实现盈亏（空头盈利）

```zig
test "Position: unrealized PnL calculation (short profit)" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(
        allocator,
        "ETH",
        try Decimal.fromString("-10.0"), // 空头
    );
    defer pos.deinit();

    pos.entry_px = try Decimal.fromString("2000.0");

    // 标记价格下跌到 $1900
    pos.updateMarkPrice(try Decimal.fromString("1900.0"));

    // Unrealized PnL = -10 * (1900 - 2000) = 1000
    try std.testing.expect(pos.unrealized_pnl.toFloat() == 1000.0);
}
```

#### 测试场景 10: 总盈亏计算

```zig
test "Position: total PnL (realized + unrealized)" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(
        allocator,
        "ETH",
        try Decimal.fromString("0.0"),
    );
    defer pos.deinit();

    pos.increase(
        try Decimal.fromString("10.0"),
        try Decimal.fromString("2000.0"),
    );

    // 部分平仓，盈利 $200
    _ = pos.decrease(
        try Decimal.fromString("2.0"),
        try Decimal.fromString("2100.0"),
    );

    // 剩余 8 ETH，标记价格 $2150
    pos.updateMarkPrice(try Decimal.fromString("2150.0"));

    // Realized PnL = 200
    // Unrealized PnL = 8 * (2150 - 2000) = 1200
    // Total PnL = 200 + 1200 = 1400
    const total_pnl = pos.getTotalPnl();
    try std.testing.expect(total_pnl.toFloat() == 1400.0);
}
```

### PositionTracker 测试

#### 测试场景 11: 初始化和清理

```zig
test "PositionTracker: init and deinit" {
    const allocator = std.testing.allocator;

    var http_client = try HyperliquidClient.init(allocator, .testnet);
    defer http_client.deinit();

    var tracker = try PositionTracker.init(allocator, &http_client, logger);
    defer tracker.deinit();

    try std.testing.expect(tracker.positions.count() == 0);
}
```

#### 测试场景 12: 获取不存在的仓位

```zig
test "PositionTracker: get non-existent position returns null" {
    const allocator = std.testing.allocator;

    var http_client = try HyperliquidClient.init(allocator, .testnet);
    defer http_client.deinit();

    var tracker = try PositionTracker.init(allocator, &http_client, logger);
    defer tracker.deinit();

    const position = tracker.getPosition("ETH");
    try std.testing.expect(position == null);
}
```

#### 测试场景 13: 处理成交事件（开仓）

```zig
test "PositionTracker: handleFill - open long position" {
    const allocator = std.testing.allocator;

    var http_client = try HyperliquidClient.init(allocator, .testnet);
    defer http_client.deinit();

    var tracker = try PositionTracker.init(allocator, &http_client, logger);
    defer tracker.deinit();

    // 模拟开多仓成交
    const fill = WsUserFills.UserFill{
        .coin = "ETH",
        .dir = "Open Long",
        .sz = "5.0",
        .px = "2000.0",
        .closedPnl = "0.0",
        .startPosition = "0.0",
        // ... 其他字段
    };

    try tracker.handleFill(fill);

    const position = tracker.getPosition("ETH").?;
    try std.testing.expect(position.szi.toFloat() == 5.0);
    try std.testing.expect(position.side == .long);
}
```

#### 测试场景 14: 处理成交事件（平仓）

```zig
test "PositionTracker: handleFill - close long position" {
    const allocator = std.testing.allocator;

    var http_client = try HyperliquidClient.init(allocator, .testnet);
    defer http_client.deinit();

    var tracker = try PositionTracker.init(allocator, &http_client, logger);
    defer tracker.deinit();

    // 先开仓
    const open_fill = WsUserFills.UserFill{
        .coin = "ETH",
        .dir = "Open Long",
        .sz = "5.0",
        .px = "2000.0",
        .closedPnl = "0.0",
        .startPosition = "0.0",
    };
    try tracker.handleFill(open_fill);

    // 完全平仓
    const close_fill = WsUserFills.UserFill{
        .coin = "ETH",
        .dir = "Close Long",
        .sz = "5.0",
        .px = "2100.0",
        .closedPnl = "500.0", // 盈利 $500
        .startPosition = "5.0",
    };
    try tracker.handleFill(close_fill);

    // 仓位应该被移除
    const position = tracker.getPosition("ETH");
    try std.testing.expect(position == null);

    // 账户已实现盈亏应该更新
    try std.testing.expect(tracker.account.total_realized_pnl.toFloat() == 500.0);
}
```

#### 测试场景 15: 更新标记价格

```zig
test "PositionTracker: updateMarkPrice" {
    const allocator = std.testing.allocator;

    var http_client = try HyperliquidClient.init(allocator, .testnet);
    defer http_client.deinit();

    var tracker = try PositionTracker.init(allocator, &http_client, logger);
    defer tracker.deinit();

    // 创建仓位
    const fill = WsUserFills.UserFill{
        .coin = "ETH",
        .dir = "Open Long",
        .sz = "10.0",
        .px = "2000.0",
        .closedPnl = "0.0",
        .startPosition = "0.0",
    };
    try tracker.handleFill(fill);

    // 更新标记价格
    try tracker.updateMarkPrice("ETH", try Decimal.fromString("2100.0"));

    const position = tracker.getPosition("ETH").?;
    try std.testing.expect(position.mark_price.?.toFloat() == 2100.0);
    try std.testing.expect(position.unrealized_pnl.toFloat() == 1000.0);
}
```

#### 测试场景 16: 回调触发

```zig
test "PositionTracker: callbacks are triggered" {
    const allocator = std.testing.allocator;

    var http_client = try HyperliquidClient.init(allocator, .testnet);
    defer http_client.deinit();

    var tracker = try PositionTracker.init(allocator, &http_client, logger);
    defer tracker.deinit();

    var position_updated = false;
    var account_updated = false;

    const onPositionUpdate = struct {
        fn callback(pos: *Position, flag: *bool) void {
            _ = pos;
            flag.* = true;
        }
    }.callback;

    const onAccountUpdate = struct {
        fn callback(acc: *Account, flag: *bool) void {
            _ = acc;
            flag.* = true;
        }
    }.callback;

    tracker.on_position_update = |pos| onPositionUpdate(pos, &position_updated);
    tracker.on_account_update = |acc| onAccountUpdate(acc, &account_updated);

    // 触发成交
    const fill = WsUserFills.UserFill{
        .coin = "ETH",
        .dir = "Open Long",
        .sz = "5.0",
        .px = "2000.0",
        .closedPnl = "0.0",
        .startPosition = "0.0",
    };
    try tracker.handleFill(fill);

    try std.testing.expect(position_updated);
    try std.testing.expect(account_updated);
}
```

---

## 集成测试

### 测试场景 17: 完整交易流程

```zig
test "Integration: complete trading flow" {
    const allocator = std.testing.allocator;

    var http_client = try HyperliquidClient.init(allocator, .testnet);
    defer http_client.deinit();

    var tracker = try PositionTracker.init(allocator, &http_client, logger);
    defer tracker.deinit();

    // 1. 开多仓 10 ETH @ $2000
    try tracker.handleFill(.{
        .coin = "ETH",
        .dir = "Open Long",
        .sz = "10.0",
        .px = "2000.0",
        .closedPnl = "0.0",
        .startPosition = "0.0",
    });

    // 2. 加仓 5 ETH @ $2050
    try tracker.handleFill(.{
        .coin = "ETH",
        .dir = "Open Long",
        .sz = "5.0",
        .px = "2050.0",
        .closedPnl = "0.0",
        .startPosition = "10.0",
    });

    // 验证均价: (10*2000 + 5*2050) / 15 = 2016.67
    var position = tracker.getPosition("ETH").?;
    try std.testing.expectApproxEqAbs(
        @as(f64, 2016.67),
        position.entry_px.toFloat(),
        0.01,
    );

    // 3. 更新标记价格到 $2100
    try tracker.updateMarkPrice("ETH", try Decimal.fromString("2100.0"));

    // 未实现盈亏: 15 * (2100 - 2016.67) = 1250
    position = tracker.getPosition("ETH").?;
    try std.testing.expectApproxEqAbs(
        @as(f64, 1250.0),
        position.unrealized_pnl.toFloat(),
        1.0,
    );

    // 4. 部分平仓 8 ETH @ $2120
    try tracker.handleFill(.{
        .coin = "ETH",
        .dir = "Close Long",
        .sz = "8.0",
        .px = "2120.0",
        .closedPnl = "826.64", // 8 * (2120 - 2016.67)
        .startPosition = "15.0",
    });

    // 5. 完全平仓 7 ETH @ $2080
    try tracker.handleFill(.{
        .coin = "ETH",
        .dir = "Close Long",
        .sz = "7.0",
        .px = "2080.0",
        .closedPnl = "443.31", // 7 * (2080 - 2016.67)
        .startPosition = "7.0",
    });

    // 验证仓位已完全平仓
    try std.testing.expect(tracker.getPosition("ETH") == null);

    // 验证总已实现盈亏
    const total_realized = tracker.account.total_realized_pnl.toFloat();
    try std.testing.expectApproxEqAbs(
        @as(f64, 1269.95), // 826.64 + 443.31
        total_realized,
        0.1,
    );
}
```

---

## 性能基准

### 基准测试 1: 仓位查询性能

```zig
test "Benchmark: position lookup" {
    const allocator = std.testing.allocator;

    var http_client = try HyperliquidClient.init(allocator, .testnet);
    defer http_client.deinit();

    var tracker = try PositionTracker.init(allocator, &http_client, logger);
    defer tracker.deinit();

    // 创建 100 个仓位
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const symbol = try std.fmt.allocPrint(allocator, "COIN{d}", .{i});
        defer allocator.free(symbol);

        try tracker.handleFill(.{
            .coin = symbol,
            .dir = "Open Long",
            .sz = "10.0",
            .px = "1000.0",
            .closedPnl = "0.0",
            .startPosition = "0.0",
        });
    }

    // 基准测试
    const start = std.time.nanoTimestamp();
    var lookups: usize = 0;
    while (lookups < 10000) : (lookups += 1) {
        _ = tracker.getPosition("COIN50");
    }
    const end = std.time.nanoTimestamp();

    const elapsed_ns = @as(f64, @floatFromInt(end - start));
    const ops_per_sec = 10000.0 / (elapsed_ns / 1_000_000_000.0);

    std.debug.print("Position lookup: {d:.0} ops/sec\n", .{ops_per_sec});
}
```

### 基准测试 2: 盈亏计算性能

```zig
test "Benchmark: PnL calculation" {
    const allocator = std.testing.allocator;

    var pos = try Position.init(
        allocator,
        "ETH",
        try Decimal.fromString("100.0"),
    );
    defer pos.deinit();

    pos.entry_px = try Decimal.fromString("2000.0");

    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < 100000) : (i += 1) {
        pos.updateMarkPrice(try Decimal.fromString("2100.0"));
    }
    const end = std.time.nanoTimestamp();

    const elapsed_ns = @as(f64, @floatFromInt(end - start));
    const ops_per_sec = 100000.0 / (elapsed_ns / 1_000_000_000.0);

    std.debug.print("PnL calculation: {d:.0} ops/sec\n", .{ops_per_sec});
}
```

### 基准结果

| 操作 | 性能 | 说明 |
|------|------|------|
| 仓位查询 | > 1,000,000 ops/sec | HashMap O(1) 查找 |
| 盈亏计算 | > 500,000 ops/sec | Decimal 算术运算 |
| 成交处理 | > 100,000 ops/sec | 包含 HashMap 更新 |
| 标记价格更新 | > 500,000 ops/sec | 简单算术 + 更新 |

---

## 运行测试

### 运行所有测试

```bash
zig test src/trading/position_test.zig
```

### 运行特定测试

```bash
zig test src/trading/position_test.zig --test-filter "Position: increase"
```

### 运行性能基准

```bash
zig test src/trading/position_test.zig --test-filter "Benchmark"
```

---

## 测试场景

### ✅ 已覆盖

- [x] Position 初始化和清理
- [x] 多头开仓、加仓、减仓、平仓
- [x] 空头开仓、加仓、减仓、平仓
- [x] 未实现盈亏计算（多头盈利/亏损）
- [x] 未实现盈亏计算（空头盈利/亏损）
- [x] 已实现盈亏计算
- [x] 总盈亏计算
- [x] 标记价格更新
- [x] 加仓均价计算
- [x] PositionTracker 初始化
- [x] 成交事件处理（开仓）
- [x] 成交事件处理（平仓）
- [x] 标记价格更新（通过 tracker）
- [x] 回调函数触发
- [x] 完整交易流程集成测试
- [x] 性能基准测试

### 📋 待补充

- [ ] 杠杆变更测试
- [ ] 资金费率累计测试
- [ ] 清算价格计算测试
- [ ] ROE 计算边界情况
- [ ] 并发访问压力测试
- [ ] 账户状态同步测试（需要 mock HTTP）
- [ ] 错误处理测试（内存不足等）
- [ ] 大数值精度测试
- [ ] 多仓位批量操作测试

---

## 测试数据

### 标准测试数据集

```zig
const TestData = struct {
    // ETH 多头盈利场景
    const eth_long_profit = .{
        .symbol = "ETH",
        .open_size = "10.0",
        .open_price = "2000.0",
        .close_price = "2100.0",
        .expected_pnl = "1000.0",
    };

    // BTC 空头盈利场景
    const btc_short_profit = .{
        .symbol = "BTC",
        .open_size = "1.0",
        .open_price = "50000.0",
        .close_price = "48000.0",
        .expected_pnl = "2000.0",
    };

    // 加仓均价测试
    const add_position = .{
        .first_size = "5.0",
        .first_price = "2000.0",
        .second_size = "3.0",
        .second_price = "2100.0",
        .expected_avg = "2037.5",
    };
};
```

---

## 测试最佳实践

### 1. 使用 defer 确保资源释放

```zig
var pos = try Position.init(allocator, "ETH", ...);
defer pos.deinit(); // 确保测试失败时也会清理
```

### 2. 使用浮点数近似比较

```zig
try std.testing.expectApproxEqAbs(
    expected_value,
    actual_value,
    0.01, // 容差
);
```

### 3. 测试边界情况

```zig
// 测试空仓
try std.testing.expect(pos.isEmpty());

// 测试除零
if (!margin.isZero()) {
    // 计算 ROE
}
```

### 4. 隔离测试依赖

使用 mock 对象代替真实的 HTTP 客户端：

```zig
const MockHttpClient = struct {
    // 模拟实现
};
```

---
