# ZigQuant 测试策略

> 全面的测试框架设计与测试覆盖率目标

---

## 🎯 测试目标

### 覆盖率目标
- **核心模块** (decimal, orderbook, order_manager): **≥ 95%**
- **策略模块** (indicators, signals): **≥ 85%**
- **交易所连接器**: **≥ 80%**
- **UI 模块**: **≥ 60%**
- **总体覆盖率**: **≥ 80%**

---

## 📂 测试目录结构

```
zigquant/
├── src/
│   └── (各模块包含内联测试)
├── tests/
│   ├── unit/                      # 单元测试
│   │   ├── core/
│   │   │   ├── decimal_test.zig
│   │   │   ├── time_test.zig
│   │   │   └── types_test.zig
│   │   ├── market/
│   │   │   ├── orderbook_test.zig
│   │   │   ├── ticker_test.zig
│   │   │   └── kline_test.zig
│   │   ├── order/
│   │   │   ├── manager_test.zig
│   │   │   └── tracker_test.zig
│   │   ├── strategy/
│   │   │   ├── indicators_test.zig
│   │   │   └── signal_test.zig
│   │   └── risk/
│   │       └── manager_test.zig
│   │
│   ├── integration/               # 集成测试
│   │   ├── exchange_integration_test.zig
│   │   ├── strategy_execution_test.zig
│   │   ├── backtest_integration_test.zig
│   │   └── event_flow_test.zig
│   │
│   ├── e2e/                       # 端到端测试
│   │   ├── full_trading_cycle_test.zig
│   │   ├── market_making_test.zig
│   │   └── arbitrage_test.zig
│   │
│   ├── fuzz/                      # 模糊测试
│   │   ├── orderbook_fuzz.zig
│   │   ├── decimal_fuzz.zig
│   │   └── parser_fuzz.zig
│   │
│   ├── benchmarks/                # 性能基准测试
│   │   ├── orderbook_bench.zig
│   │   ├── strategy_bench.zig
│   │   └── latency_bench.zig
│   │
│   └── fixtures/                  # 测试数据
│       ├── sample_klines.json
│       ├── sample_orderbook.json
│       └── mock_trades.json
```

---

## 1. 单元测试

### 1.1 核心类型测试

```zig
// tests/unit/core/decimal_test.zig

const std = @import("std");
const testing = std.testing;
const Decimal = @import("../../../src/core/decimal.zig").Decimal;

test "Decimal: basic arithmetic" {
    const a = try Decimal.fromString("100.50");
    const b = try Decimal.fromString("50.25");

    // 加法
    const sum = a.add(b);
    try testing.expectEqual(try Decimal.fromString("150.75"), sum);

    // 减法
    const diff = a.sub(b);
    try testing.expectEqual(try Decimal.fromString("50.25"), diff);

    // 乘法
    const product = a.mul(b);
    try testing.expectEqual(try Decimal.fromString("5050.125"), product);

    // 除法
    const quotient = try a.div(b);
    try testing.expectEqual(try Decimal.fromString("2.0"), quotient);
}

test "Decimal: precision handling" {
    const a = try Decimal.fromString("0.1");
    const b = try Decimal.fromString("0.2");
    const c = a.add(b);

    // 验证精度问题不存在
    try testing.expectEqual(try Decimal.fromString("0.3"), c);
}

test "Decimal: edge cases" {
    // 零值
    const zero = Decimal.ZERO;
    try testing.expect(zero.isZero());

    // 除以零
    const a = try Decimal.fromString("100");
    try testing.expectError(error.DivisionByZero, a.div(zero));

    // 溢出检测
    const max = Decimal{ .value = std.math.maxInt(i128), .scale = 18 };
    const one = Decimal.ONE;
    try testing.expectError(error.Overflow, max.add(one));

    // 负数
    const negative = try Decimal.fromString("-50.5");
    try testing.expect(negative.isNegative());
    try testing.expectEqual(try Decimal.fromString("50.5"), negative.abs());
}

test "Decimal: comparison" {
    const a = try Decimal.fromString("100");
    const b = try Decimal.fromString("50");
    const c = try Decimal.fromString("100");

    try testing.expect(a.cmp(b) == .gt);
    try testing.expect(b.cmp(a) == .lt);
    try testing.expect(a.cmp(c) == .eq);
}

test "Decimal: string conversion" {
    const value = try Decimal.fromString("123.456789");
    const str = try value.toString(testing.allocator);
    defer testing.allocator.free(str);

    try testing.expectEqualStrings("123.456789", str);
}
```

### 1.2 订单簿测试

```zig
// tests/unit/market/orderbook_test.zig

const std = @import("std");
const testing = std.testing;
const Orderbook = @import("../../../src/market/orderbook.zig").Orderbook;
const Decimal = @import("../../../src/core/decimal.zig").Decimal;
const TradingPair = @import("../../../src/core/types.zig").TradingPair;

test "Orderbook: initialization" {
    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    var ob = Orderbook.init(testing.allocator, pair);
    defer ob.deinit();

    try testing.expect(ob.getBestBid() == null);
    try testing.expect(ob.getBestAsk() == null);
}

test "Orderbook: add and remove levels" {
    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    var ob = Orderbook.init(testing.allocator, pair);
    defer ob.deinit();

    // 添加买单
    try ob.update(.{
        .bids = &[_]Orderbook.PriceLevel{
            .{ .price = try Decimal.fromString("50000"), .quantity = try Decimal.fromString("1.0") },
            .{ .price = try Decimal.fromString("49999"), .quantity = try Decimal.fromString("2.0") },
        },
        .asks = &[_]Orderbook.PriceLevel{},
        .last_update_id = 1,
        .timestamp = std.time.milliTimestamp(),
    });

    // 验证最优买价
    const best_bid = ob.getBestBid().?;
    try testing.expectEqual(try Decimal.fromString("50000"), best_bid.price);
    try testing.expectEqual(try Decimal.fromString("1.0"), best_bid.quantity);

    // 删除价格档位 (数量设为0)
    try ob.update(.{
        .bids = &[_]Orderbook.PriceLevel{
            .{ .price = try Decimal.fromString("50000"), .quantity = Decimal.ZERO },
        },
        .asks = &[_]Orderbook.PriceLevel{},
        .last_update_id = 2,
        .timestamp = std.time.milliTimestamp(),
    });

    // 验证最优买价变化
    const new_best_bid = ob.getBestBid().?;
    try testing.expectEqual(try Decimal.fromString("49999"), new_best_bid.price);
}

test "Orderbook: spread calculation" {
    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    var ob = Orderbook.init(testing.allocator, pair);
    defer ob.deinit();

    try ob.update(.{
        .bids = &[_]Orderbook.PriceLevel{
            .{ .price = try Decimal.fromString("50000"), .quantity = try Decimal.fromString("1.0") },
        },
        .asks = &[_]Orderbook.PriceLevel{
            .{ .price = try Decimal.fromString("50010"), .quantity = try Decimal.fromString("1.0") },
        },
        .last_update_id = 1,
        .timestamp = std.time.milliTimestamp(),
    });

    const spread = ob.getSpread().?;
    try testing.expectEqual(try Decimal.fromString("10"), spread);

    const mid_price = ob.getMidPrice().?;
    try testing.expectEqual(try Decimal.fromString("50005"), mid_price);
}

test "Orderbook: sequence validation" {
    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    var ob = Orderbook.init(testing.allocator, pair);
    defer ob.deinit();

    // 正常更新
    try ob.update(.{
        .bids = &[_]Orderbook.PriceLevel{},
        .asks = &[_]Orderbook.PriceLevel{},
        .last_update_id = 100,
        .timestamp = std.time.milliTimestamp(),
    });

    // 旧序列号应被忽略
    try ob.update(.{
        .bids = &[_]Orderbook.PriceLevel{},
        .asks = &[_]Orderbook.PriceLevel{},
        .last_update_id = 99,
        .timestamp = std.time.milliTimestamp(),
    });

    try testing.expectEqual(@as(u64, 100), ob.last_update_id);
}
```

### 1.3 技术指标测试

```zig
// tests/unit/strategy/indicators_test.zig

const std = @import("std");
const testing = std.testing;
const SMA = @import("../../../src/strategy/indicators/sma.zig").SMA;
const RSI = @import("../../../src/strategy/indicators/rsi.zig").RSI;
const Decimal = @import("../../../src/core/decimal.zig").Decimal;

test "SMA: calculation" {
    var sma = SMA.init(testing.allocator, 3);
    defer sma.deinit();

    // 未满周期返回 null
    try testing.expect(sma.update(try Decimal.fromString("10")) == null);
    try testing.expect(sma.update(try Decimal.fromString("20")) == null);

    // 满周期返回平均值
    const result = sma.update(try Decimal.fromString("30")).?;
    try testing.expectEqual(try Decimal.fromString("20"), result);  // (10+20+30)/3 = 20

    // 滑动窗口
    const result2 = sma.update(try Decimal.fromString("40")).?;
    try testing.expectEqual(try Decimal.fromString("30"), result2);  // (20+30+40)/3 = 30
}

test "RSI: calculation" {
    var rsi = RSI.init(testing.allocator, 14);
    defer rsi.deinit();

    // 模拟价格序列
    const prices = [_]f64{
        44.34, 44.09, 43.61, 44.33, 44.83,
        45.10, 45.42, 45.84, 46.08, 45.89,
        46.03, 45.61, 46.28, 46.28, 46.00,
    };

    var result: ?Decimal = null;
    for (prices) |price| {
        result = rsi.update(try Decimal.fromFloat(price));
    }

    // 验证 RSI 在合理范围内 (0-100)
    try testing.expect(result != null);
    const rsi_value = result.?.toFloat();
    try testing.expect(rsi_value >= 0 and rsi_value <= 100);

    // 根据实际计算验证具体值 (约 70)
    try testing.expectApproxEqAbs(70.0, rsi_value, 5.0);
}

test "MACD: signal generation" {
    const MACD = @import("../../../src/strategy/indicators/macd.zig").MACD;

    var macd = MACD.init(testing.allocator, 12, 26, 9);
    defer macd.deinit();

    // 需要足够的数据点
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        const price = try Decimal.fromFloat(100.0 + @as(f64, @floatFromInt(i)));
        _ = macd.update(price);
    }

    const result = macd.update(try Decimal.fromFloat(150)).?;

    try testing.expect(result.macd.toFloat() != 0);
    try testing.expect(result.signal.toFloat() != 0);
    try testing.expect(result.histogram.toFloat() != 0);
}
```

---

## 2. 集成测试

### 2.1 交易所集成测试

```zig
// tests/integration/exchange_integration_test.zig

const std = @import("std");
const testing = std.testing;
const BinanceConnector = @import("../../src/exchange/binance/connector.zig").BinanceConnector;

test "Binance: full flow integration" {
    // 使用测试网凭证
    const api_key = std.os.getenv("BINANCE_TESTNET_API_KEY") orelse return error.SkipTest;
    const api_secret = std.os.getenv("BINANCE_TESTNET_API_SECRET") orelse return error.SkipTest;

    var binance = try BinanceConnector.init(testing.allocator, api_key, api_secret);
    defer binance.deinit();

    binance.config.testnet = true;

    // 1. 连接测试
    try binance.connect();

    // 2. 获取行情
    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    const ticker = try binance.getTicker(pair);
    try testing.expect(ticker.price.isPositive());

    // 3. 获取订单簿
    const orderbook = try binance.getOrderbook(pair, 10);
    try testing.expect(orderbook.getBestBid() != null);
    try testing.expect(orderbook.getBestAsk() != null);

    // 4. 查询余额
    const balance = try binance.getBalance();
    try testing.expect(balance.count() > 0);

    // 5. 下单测试 (小额测试订单)
    const order = try binance.createOrder(.{
        .pair = pair,
        .side = .buy,
        .order_type = .limit,
        .amount = try Decimal.fromString("0.001"),
        .price = ticker.price.mul(try Decimal.fromString("0.9")),  // 远低于市价，不会成交
    });

    try testing.expect(order.status == .open);

    // 6. 查询订单
    const queried_order = try binance.getOrder(order.id);
    try testing.expectEqualStrings(order.id, queried_order.id);

    // 7. 取消订单
    try binance.cancelOrder(order.id);

    // 8. 验证取消
    const cancelled_order = try binance.getOrder(order.id);
    try testing.expect(cancelled_order.status == .cancelled);
}

test "Exchange: WebSocket stream" {
    const api_key = std.os.getenv("BINANCE_TESTNET_API_KEY") orelse return error.SkipTest;
    const api_secret = std.os.getenv("BINANCE_TESTNET_API_SECRET") orelse return error.SkipTest;

    var binance = try BinanceConnector.init(testing.allocator, api_key, api_secret);
    defer binance.deinit();

    var event_bus = EventBus.init(testing.allocator);
    defer event_bus.deinit();

    var ws = try BinanceWebSocket.init(testing.allocator, &event_bus);
    defer ws.deinit();

    try ws.connect();

    // 订阅行情
    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    try ws.subscribeTicker(pair);

    // 等待接收数据
    var received = false;
    const callback = struct {
        fn onTicker(event: Event) void {
            received = true;
        }
    }.onTicker;

    try event_bus.subscribe(.ticker_update, callback);

    // 等待最多5秒
    var i: u32 = 0;
    while (i < 50 and !received) : (i += 1) {
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    try testing.expect(received);
}
```

### 2.2 策略执行集成测试

```zig
// tests/integration/strategy_execution_test.zig

test "Strategy: complete execution flow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建模拟交易所
    var mock_exchange = MockExchange.init(allocator);
    defer mock_exchange.deinit();

    var event_bus = EventBus.init(allocator);
    defer event_bus.deinit();

    var order_manager = OrderManager.init(allocator, mock_exchange.connector(), &event_bus);
    defer order_manager.deinit();

    // 创建策略
    var strategy = DualMAStrategy.init(allocator, .{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .fast_period = 5,
        .slow_period = 10,
        .position_size = try Decimal.fromString("0.1"),
    });
    defer strategy.deinit();

    var ctx = StrategyContext{
        .allocator = allocator,
        .exchange = mock_exchange.connector(),
        .order_manager = &order_manager,
        .event_bus = &event_bus,
        .config = .{},
    };

    // 初始化策略
    try strategy.strategy().init(&ctx);

    // 模拟K线数据触发策略
    const klines = [_]Kline{
        .{ .close = try Decimal.fromString("50000"), .timestamp = 1000 },
        .{ .close = try Decimal.fromString("50100"), .timestamp = 2000 },
        .{ .close = try Decimal.fromString("50200"), .timestamp = 3000 },
        .{ .close = try Decimal.fromString("50300"), .timestamp = 4000 },
        .{ .close = try Decimal.fromString("50400"), .timestamp = 5000 },
        .{ .close = try Decimal.fromString("50500"), .timestamp = 6000 },
    };

    for (klines) |kline| {
        strategy.strategy().onKline(kline);
    }

    // 验证订单已创建
    try testing.expect(order_manager.orders.count() > 0);
}
```

---

## 3. 端到端测试

### 3.1 完整交易周期测试

```zig
// tests/e2e/full_trading_cycle_test.zig

test "E2E: complete trading cycle" {
    // 此测试需要真实测试网环境
    if (std.os.getenv("E2E_TESTS_ENABLED") == null) {
        return error.SkipTest;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 初始化引擎
    var engine = try TradingEngine.init(allocator, "config/test_config.json");
    defer engine.deinit();

    // 2. 启动引擎
    try engine.start();
    defer engine.stop();

    // 3. 加载策略
    try engine.loadStrategy("dual_ma", .{
        .pair = "BTC/USDT",
        .fast_period = 10,
        .slow_period = 20,
    });

    // 4. 启动策略
    try engine.startStrategy("dual_ma");

    // 5. 运行一段时间
    std.time.sleep(60 * std.time.ns_per_s);  // 1分钟

    // 6. 获取性能指标
    const metrics = engine.getMetrics();

    // 7. 验证基本指标
    try testing.expect(metrics.total_trades >= 0);
    try testing.expect(metrics.uptime > 0);

    // 8. 停止策略
    try engine.stopStrategy("dual_ma");

    // 9. 验证订单已全部关闭
    const open_orders = try engine.getOpenOrders();
    try testing.expectEqual(@as(usize, 0), open_orders.len);
}
```

---

## 4. 模糊测试

### 4.1 订单簿模糊测试

```zig
// tests/fuzz/orderbook_fuzz.zig

const std = @import("std");
const Orderbook = @import("../../src/market/orderbook.zig").Orderbook;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    var ob = Orderbook.init(allocator, pair);
    defer ob.deinit();

    // 模糊测试：随机订单簿更新
    var i: u32 = 0;
    while (i < 10000) : (i += 1) {
        const num_bids = random.intRangeAtMost(u32, 0, 100);
        const num_asks = random.intRangeAtMost(u32, 0, 100);

        var bids = std.ArrayList(Orderbook.PriceLevel).init(allocator);
        defer bids.deinit();

        var j: u32 = 0;
        while (j < num_bids) : (j += 1) {
            const price = random.float(f64) * 100000.0;
            const quantity = random.float(f64) * 10.0;

            try bids.append(.{
                .price = try Decimal.fromFloat(price),
                .quantity = try Decimal.fromFloat(quantity),
            });
        }

        var asks = std.ArrayList(Orderbook.PriceLevel).init(allocator);
        defer asks.deinit();

        j = 0;
        while (j < num_asks) : (j += 1) {
            const price = random.float(f64) * 100000.0 + 50000.0;
            const quantity = random.float(f64) * 10.0;

            try asks.append(.{
                .price = try Decimal.fromFloat(price),
                .quantity = try Decimal.fromFloat(quantity),
            });
        }

        // 应该不会崩溃
        ob.update(.{
            .bids = bids.items,
            .asks = asks.items,
            .last_update_id = i,
            .timestamp = std.time.milliTimestamp(),
        }) catch |err| {
            std.debug.print("Error at iteration {d}: {}\n", .{ i, err });
            return err;
        };

        // 验证不变量
        if (ob.getBestBid()) |bid| {
            if (ob.getBestAsk()) |ask| {
                // 最优买价应该小于最优卖价
                if (bid.price.cmp(ask.price) != .lt) {
                    std.debug.print("Invariant violated: bid >= ask\n", .{});
                    return error.InvariantViolation;
                }
            }
        }
    }

    std.debug.print("Fuzz test passed: 10000 iterations\n", .{});
}
```

---

## 5. 性能基准测试

### 5.1 订单簿性能测试

```zig
// tests/benchmarks/orderbook_bench.zig

const std = @import("std");
const Orderbook = @import("../../src/market/orderbook.zig").Orderbook;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    var ob = Orderbook.init(allocator, pair);
    defer ob.deinit();

    // 预热
    {
        var i: u32 = 0;
        while (i < 1000) : (i += 1) {
            try ob.update(.{
                .bids = &[_]Orderbook.PriceLevel{
                    .{ .price = try Decimal.fromFloat(50000.0), .quantity = try Decimal.fromFloat(1.0) },
                },
                .asks = &[_]Orderbook.PriceLevel{},
                .last_update_id = i,
                .timestamp = std.time.milliTimestamp(),
            });
        }
    }

    // 基准测试：10万次更新
    const iterations = 100_000;
    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        try ob.update(.{
            .bids = &[_]Orderbook.PriceLevel{
                .{ .price = try Decimal.fromFloat(50000.0 + @as(f64, @floatFromInt(i))), .quantity = try Decimal.fromFloat(1.0) },
            },
            .asks = &[_]Orderbook.PriceLevel{
                .{ .price = try Decimal.fromFloat(50100.0 + @as(f64, @floatFromInt(i))), .quantity = try Decimal.fromFloat(1.0) },
            },
            .last_update_id = i + 1000,
            .timestamp = std.time.milliTimestamp(),
        });
    }

    const end = std.time.nanoTimestamp();
    const duration_ns = end - start;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const updates_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.debug.print("Orderbook Performance:\n", .{});
    std.debug.print("  Total updates: {d}\n", .{iterations});
    std.debug.print("  Duration: {d:.2} ms\n", .{duration_ms});
    std.debug.print("  Throughput: {d:.0} updates/sec\n", .{updates_per_sec});
    std.debug.print("  Avg latency: {d:.2} µs\n", .{duration_ms * 1000.0 / @as(f64, @floatFromInt(iterations))});
}
```

### 5.2 延迟基准测试

```zig
// tests/benchmarks/latency_bench.zig

pub fn main() !void {
    // 测试端到端延迟
    const LatencyBenchmark = struct {
        fn measureOrderLatency() !void {
            var latencies = std.ArrayList(u64).init(allocator);
            defer latencies.deinit();

            var i: u32 = 0;
            while (i < 1000) : (i += 1) {
                const start = std.time.nanoTimestamp();

                // 模拟订单提交流程
                const order = try order_manager.submitOrder(.{
                    .pair = pair,
                    .side = .buy,
                    .order_type = .limit,
                    .amount = try Decimal.fromString("0.001"),
                    .price = try Decimal.fromString("50000"),
                });

                const end = std.time.nanoTimestamp();
                const latency = @as(u64, @intCast(end - start));
                try latencies.append(latency);

                try order_manager.cancelOrder(order.id);
            }

            // 计算统计数据
            std.sort.sort(u64, latencies.items, {}, comptime std.sort.asc(u64));

            const p50 = latencies.items[latencies.items.len / 2];
            const p95 = latencies.items[latencies.items.len * 95 / 100];
            const p99 = latencies.items[latencies.items.len * 99 / 100];

            std.debug.print("Order Latency:\n", .{});
            std.debug.print("  P50: {d} µs\n", .{p50 / 1000});
            std.debug.print("  P95: {d} µs\n", .{p95 / 1000});
            std.debug.print("  P99: {d} µs\n", .{p99 / 1000});
        }
    };

    try LatencyBenchmark.measureOrderLatency();
}
```

---

## 6. 测试工具与辅助

### 6.1 Mock 交易所

```zig
// tests/mocks/mock_exchange.zig

pub const MockExchange = struct {
    allocator: std.mem.Allocator,
    orders: std.StringHashMap(Order),
    balance: std.StringHashMap(Decimal),

    pub fn init(allocator: std.mem.Allocator) MockExchange {
        var balance = std.StringHashMap(Decimal).init(allocator);

        // 初始余额
        balance.put("USDT", try Decimal.fromString("10000")) catch {};
        balance.put("BTC", try Decimal.fromString("1.0")) catch {};

        return .{
            .allocator = allocator,
            .orders = std.StringHashMap(Order).init(allocator),
            .balance = balance,
        };
    }

    pub fn connector(self: *MockExchange) ExchangeConnector {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn createOrder(ptr: *anyopaque, request: OrderRequest) !Order {
        const self: *MockExchange = @ptrCast(@alignCast(ptr));

        const order = Order{
            .id = try generateOrderId(self.allocator),
            .pair = request.pair,
            .side = request.side,
            .order_type = request.order_type,
            .amount = request.amount,
            .price = request.price,
            .status = .open,
            .created_at = std.time.milliTimestamp(),
        };

        try self.orders.put(order.id, order);
        return order;
    }

    // ... 其他方法实现

    const vtable = ExchangeConnector.VTable{
        .getTicker = getTicker,
        .getOrderbook = getOrderbook,
        .createOrder = createOrder,
        // ...
    };
};
```

### 6.2 测试数据生成器

```zig
// tests/fixtures/generator.zig

pub const DataGenerator = struct {
    pub fn generateKlines(
        allocator: std.mem.Allocator,
        count: u32,
        start_price: f64,
    ) ![]Kline {
        var klines = std.ArrayList(Kline).init(allocator);

        var i: u32 = 0;
        var price = start_price;
        while (i < count) : (i += 1) {
            const volatility = 0.01;  // 1% 波动
            const change = (std.rand.float(f64) - 0.5) * volatility * price;
            price += change;

            try klines.append(.{
                .timestamp = i * 60_000,  // 1分钟间隔
                .open = try Decimal.fromFloat(price),
                .high = try Decimal.fromFloat(price * 1.005),
                .low = try Decimal.fromFloat(price * 0.995),
                .close = try Decimal.fromFloat(price),
                .volume = try Decimal.fromFloat(std.rand.float(f64) * 100),
            });
        }

        return klines.toOwnedSlice();
    }
};
```

---

## 7. 持续集成配置

### 7.1 GitHub Actions

```yaml
# .github/workflows/test.yml

name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: master

      - name: Run Unit Tests
        run: zig build test

      - name: Run Integration Tests
        env:
          BINANCE_TESTNET_API_KEY: ${{ secrets.BINANCE_TESTNET_API_KEY }}
          BINANCE_TESTNET_API_SECRET: ${{ secrets.BINANCE_TESTNET_API_SECRET }}
        run: zig build test-integration

      - name: Generate Coverage Report
        run: zig build coverage

      - name: Upload Coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.xml
```

---

## 8. 测试最佳实践

### 8.1 测试原则
1. **Fast**: 单元测试应在毫秒级完成
2. **Independent**: 测试之间互不依赖
3. **Repeatable**: 任何环境都能重复执行
4. **Self-Validating**: 自动判断通过/失败
5. **Timely**: 与开发同步编写

### 8.2 命名规范
```zig
test "ModuleName: specific behavior being tested" {
    // Arrange
    // Act
    // Assert
}
```

### 8.3 测试数据管理
- 使用 fixtures 目录存放测试数据
- 避免硬编码测试数据
- 使用数据生成器创建随机测试数据

---

*Last updated: 2025-01*
