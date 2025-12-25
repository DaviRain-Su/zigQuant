# Backtest Engine Testing Strategy

**Version**: v0.4.0
**Status**: Planned
**Last Updated**: 2025-12-25

---

## 📋 Table of Contents

1. [Testing Objectives](#testing-objectives)
2. [Unit Tests](#unit-tests)
3. [Integration Tests](#integration-tests)
4. [End-to-End Tests](#end-to-end-tests)
5. [Performance Tests](#performance-tests)
6. [Accuracy Validation](#accuracy-validation)
7. [Test Coverage](#test-coverage)

---

## 🎯 Testing Objectives

### Functional Testing

- ✅ Event-driven loop executes correctly
- ✅ Order execution simulation is accurate
- ✅ Slippage and commission calculation correct
- ✅ Position management works properly
- ✅ Account balance tracking accurate
- ✅ Performance metrics calculated correctly

### Quality Testing

- ✅ Zero memory leaks
- ✅ No data races
- ✅ Complete error handling
- ✅ Edge case handling
- ✅ No future function (look-ahead bias)

### Performance Testing

- ✅ Backtest speed > 1000 candles/s
- ✅ Memory usage < 50MB for 10,000 candles
- ✅ Metric calculation < 100ms for 1000 trades
- ✅ Zero performance regression

---

## 🧪 Unit Tests

### Test File Organization

```
src/backtest/
├── engine_test.zig         # BacktestEngine tests
├── event_test.zig          # Event system tests
├── executor_test.zig       # OrderExecutor tests
├── account_test.zig        # Account management tests
├── position_test.zig       # Position management tests
├── analyzer_test.zig       # PerformanceAnalyzer tests
├── metrics_test.zig        # Metrics calculation tests
└── data_feed_test.zig      # HistoricalDataFeed tests
```

### Event System Tests

```zig
// src/backtest/event_test.zig
const std = @import("std");
const testing = std.testing;
const Event = @import("event.zig").Event;
const EventQueue = @import("event.zig").EventQueue;
const MarketEvent = @import("event.zig").MarketEvent;

test "EventQueue: FIFO ordering" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    var queue = EventQueue.init(allocator);
    defer queue.deinit();

    // Push events
    const event1 = Event{ .market = MarketEvent{ .timestamp = 1000, ... } };
    const event2 = Event{ .market = MarketEvent{ .timestamp = 2000, ... } };
    const event3 = Event{ .market = MarketEvent{ .timestamp = 3000, ... } };

    try queue.push(event1);
    try queue.push(event2);
    try queue.push(event3);

    // Pop events - should be in FIFO order
    const e1 = queue.pop().?;
    const e2 = queue.pop().?;
    const e3 = queue.pop().?;

    try testing.expectEqual(1000, e1.market.timestamp);
    try testing.expectEqual(2000, e2.market.timestamp);
    try testing.expectEqual(3000, e3.market.timestamp);

    // Queue should be empty
    try testing.expect(queue.isEmpty());
    try testing.expect(queue.pop() == null);
}

test "EventQueue: clear" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var queue = EventQueue.init(allocator);
    defer queue.deinit();

    // Add events
    try queue.push(Event{ .market = MarketEvent{ .timestamp = 1000, ... } });
    try queue.push(Event{ .market = MarketEvent{ .timestamp = 2000, ... } });

    try testing.expect(!queue.isEmpty());

    // Clear
    queue.clear();
    try testing.expect(queue.isEmpty());
}
```

### Order Executor Tests

```zig
// src/backtest/executor_test.zig
const std = @import("std");
const testing = std.testing;
const Decimal = @import("../core/decimal.zig").Decimal;
const OrderExecutor = @import("executor.zig").OrderExecutor;
const OrderEvent = @import("event.zig").OrderEvent;
const Candle = @import("../market/candle.zig").Candle;
const BacktestConfig = @import("types.zig").BacktestConfig;

test "OrderExecutor: market order buy with slippage" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup config with 0.05% slippage and 0.1% commission
    const config = BacktestConfig{
        .pair = TradingPair.fromString("ETH/USDC"),
        .timeframe = .m15,
        .start_time = 0,
        .end_time = 0,
        .initial_capital = try Decimal.fromInt(10000),
        .commission_rate = try Decimal.fromFloat(0.001),
        .slippage = try Decimal.fromFloat(0.0005),
    };

    var executor = OrderExecutor.init(allocator, config);

    // Create buy order
    const order = OrderEvent{
        .id = 1,
        .timestamp = 1000,
        .pair = config.pair,
        .side = .buy,
        .type = .market,
        .price = try Decimal.fromInt(2000),
        .size = try Decimal.fromFloat(1.0),
    };

    // Current candle with close = 2000
    const candle = Candle{
        .timestamp = 1000,
        .open = try Decimal.fromInt(1995),
        .high = try Decimal.fromInt(2005),
        .low = try Decimal.fromInt(1990),
        .close = try Decimal.fromInt(2000),
        .volume = try Decimal.fromInt(100),
    };

    // Execute
    const fill = try executor.executeMarketOrder(order, candle);

    // Verify fill price with slippage
    // buy: close × (1 + slippage) = 2000 × 1.0005 = 2001
    const expected_price = try Decimal.fromFloat(2001.0);
    try testing.expect(fill.fill_price.eq(expected_price));

    // Verify commission
    // commission = price × size × rate = 2001 × 1.0 × 0.001 = 2.001
    const expected_commission = try Decimal.fromFloat(2.001);
    try testing.expect(fill.commission.eq(expected_commission));
}

test "OrderExecutor: market order sell with slippage" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = BacktestConfig{
        .pair = TradingPair.fromString("ETH/USDC"),
        .timeframe = .m15,
        .start_time = 0,
        .end_time = 0,
        .initial_capital = try Decimal.fromInt(10000),
        .commission_rate = try Decimal.fromFloat(0.001),
        .slippage = try Decimal.fromFloat(0.0005),
    };

    var executor = OrderExecutor.init(allocator, config);

    const order = OrderEvent{
        .id = 1,
        .timestamp = 1000,
        .pair = config.pair,
        .side = .sell,
        .type = .market,
        .price = try Decimal.fromInt(2000),
        .size = try Decimal.fromFloat(1.0),
    };

    const candle = Candle{
        .timestamp = 1000,
        .close = try Decimal.fromInt(2000),
        // ... other fields ...
    };

    const fill = try executor.executeMarketOrder(order, candle);

    // Verify fill price with slippage
    // sell: close × (1 - slippage) = 2000 × 0.9995 = 1999
    const expected_price = try Decimal.fromFloat(1999.0);
    try testing.expect(fill.fill_price.eq(expected_price));
}
```

### Position Management Tests

```zig
// src/backtest/position_test.zig
const std = @import("std");
const testing = std.testing;
const Decimal = @import("../core/decimal.zig").Decimal;
const Position = @import("position.zig").Position;

test "Position: long P&L calculation" {
    const position = Position.init(
        TradingPair.fromString("ETH/USDC"),
        .long,
        try Decimal.fromFloat(1.0),         // size
        try Decimal.fromInt(2000),          // entry price
        1000,                                // entry time
    );

    // Price goes up to 2100
    const exit_price = try Decimal.fromInt(2100);
    const pnl = try position.calculatePnL(exit_price);

    // Expected: (2100 - 2000) × 1.0 = 100
    const expected = try Decimal.fromInt(100);
    try testing.expect(pnl.eq(expected));
}

test "Position: short P&L calculation" {
    const position = Position.init(
        TradingPair.fromString("ETH/USDC"),
        .short,
        try Decimal.fromFloat(1.0),
        try Decimal.fromInt(2000),
        1000,
    );

    // Price goes down to 1900
    const exit_price = try Decimal.fromInt(1900);
    const pnl = try position.calculatePnL(exit_price);

    // Expected: (2000 - 1900) × 1.0 = 100
    const expected = try Decimal.fromInt(100);
    try testing.expect(pnl.eq(expected));
}

test "Position: unrealized P&L update" {
    var position = Position.init(
        TradingPair.fromString("ETH/USDC"),
        .long,
        try Decimal.fromFloat(1.0),
        try Decimal.fromInt(2000),
        1000,
    );

    // Initially zero
    try testing.expect(position.unrealized_pnl.isZero());

    // Update with new price
    try position.updateUnrealizedPnL(try Decimal.fromInt(2050));

    // Expected: (2050 - 2000) × 1.0 = 50
    const expected = try Decimal.fromInt(50);
    try testing.expect(position.unrealized_pnl.eq(expected));
}
```

### Performance Analyzer Tests

```zig
// src/backtest/analyzer_test.zig
const std = @import("std");
const testing = std.testing;
const PerformanceAnalyzer = @import("analyzer.zig").PerformanceAnalyzer;
const BacktestResult = @import("types.zig").BacktestResult;
const Trade = @import("types.zig").Trade;

test "PerformanceAnalyzer: profit factor calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var analyzer = PerformanceAnalyzer.init(allocator);

    // Create trades with known P&L
    var trades = [_]Trade{
        // Winning trades: +100, +200
        .{ .pnl = try Decimal.fromInt(100), ... },
        .{ .pnl = try Decimal.fromInt(200), ... },
        // Losing trades: -50, -100
        .{ .pnl = try Decimal.fromInt(-50), ... },
        .{ .pnl = try Decimal.fromInt(-100), ... },
    };

    const profit_metrics = try analyzer.calculateProfitMetrics(&trades);

    // Total profit = 300, Total loss = 150
    try testing.expect(profit_metrics.total_profit.eq(try Decimal.fromInt(300)));
    try testing.expect(profit_metrics.total_loss.eq(try Decimal.fromInt(150)));

    // Profit factor = 300 / 150 = 2.0
    try testing.expectApproxEqAbs(2.0, profit_metrics.profit_factor, 0.01);
}

test "PerformanceAnalyzer: win rate calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var analyzer = PerformanceAnalyzer.init(allocator);

    var trades = [_]Trade{
        .{ .pnl = try Decimal.fromInt(100), ... },   // Win
        .{ .pnl = try Decimal.fromInt(50), ... },    // Win
        .{ .pnl = try Decimal.fromInt(-30), ... },   // Loss
        .{ .pnl = try Decimal.fromInt(-20), ... },   // Loss
        .{ .pnl = try Decimal.fromInt(150), ... },   // Win
    };

    const win_metrics = try analyzer.calculateWinMetrics(&trades);

    // 3 wins out of 5 trades = 60%
    try testing.expectEqual(3, win_metrics.winning_trades);
    try testing.expectEqual(2, win_metrics.losing_trades);
    try testing.expectApproxEqAbs(0.6, win_metrics.win_rate, 0.01);
}

test "PerformanceAnalyzer: max drawdown calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var analyzer = PerformanceAnalyzer.init(allocator);

    // Create equity curve: 10000 -> 11000 -> 10500 -> 9000 -> 12000
    var equity_curve = [_]BacktestResult.EquitySnapshot{
        .{ .timestamp = 0, .equity = try Decimal.fromInt(10000), ... },
        .{ .timestamp = 1, .equity = try Decimal.fromInt(11000), ... },  // Peak
        .{ .timestamp = 2, .equity = try Decimal.fromInt(10500), ... },
        .{ .timestamp = 3, .equity = try Decimal.fromInt(9000), ... },   // Trough
        .{ .timestamp = 4, .equity = try Decimal.fromInt(12000), ... },
    };

    const dd = try analyzer.calculateMaxDrawdown(&equity_curve);

    // Max drawdown = (11000 - 9000) / 11000 = 18.18%
    try testing.expectApproxEqAbs(0.1818, dd.max_drawdown, 0.01);
}
```

---

## 🔗 Integration Tests

### Backtest Engine Integration

```zig
// tests/integration/backtest_integration_test.zig
const std = @import("std");
const testing = std.testing;
const BacktestEngine = @import("backtest/engine.zig").BacktestEngine;
const DualMAStrategy = @import("strategy/builtin/dual_ma.zig").DualMAStrategy;

test "Integration: Complete backtest flow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    // Create backtest engine
    var engine = try BacktestEngine.init(allocator);
    defer engine.deinit();

    // Create strategy
    var strategy = try DualMAStrategy.create(allocator, .{
        .fast_period = 5,
        .slow_period = 10,
    });
    defer strategy.deinit();

    // Configure backtest
    const config = BacktestConfig{
        .pair = TradingPair.fromString("ETH/USDC"),
        .timeframe = .m15,
        .start_time = try Timestamp.fromDate(2024, 1, 1, 0, 0, 0),
        .end_time = try Timestamp.fromDate(2024, 1, 31, 23, 59, 59),
        .initial_capital = try Decimal.fromInt(10000),
    };

    // Run backtest
    const result = try engine.run(strategy, config);
    defer result.deinit();

    // Verify result structure
    try testing.expect(result.total_trades >= 0);
    try testing.expect(result.trades.len == result.total_trades);
    try testing.expect(result.equity_curve.len > 0);

    // Verify trade consistency
    var calculated_trades: u32 = 0;
    for (result.trades) |trade| {
        try testing.expect(trade.entry_time < trade.exit_time);
        calculated_trades += 1;
    }
    try testing.expectEqual(result.total_trades, calculated_trades);

    // Verify win rate consistency
    const calculated_win_rate = @as(f64, @floatFromInt(result.winning_trades)) /
        @as(f64, @floatFromInt(result.total_trades));
    try testing.expectApproxEqAbs(result.win_rate, calculated_win_rate, 0.01);
}

test "Integration: Zero trades scenario" {
    // Test backtest with strategy that generates no signals
    // Verify proper handling of edge case
}

test "Integration: Single trade scenario" {
    // Test backtest with strategy that generates exactly one trade
    // Verify metrics are calculated correctly
}
```

---

## 🚀 End-to-End Tests

### E2E Test with Real Data

```zig
// tests/e2e/backtest_e2e_test.zig
test "E2E: DualMA strategy on historical data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load real historical data
    var data_feed = HistoricalDataFeed.init(allocator);
    const candles = try data_feed.load(
        TradingPair.fromString("ETH/USDC"),
        .m15,
        try Timestamp.fromDate(2024, 1, 1, 0, 0, 0),
        try Timestamp.fromDate(2024, 12, 31, 23, 59, 59),
    );
    defer candles.deinit();

    // Ensure we have enough data
    try testing.expect(candles.data.len > 1000);

    // Create and run backtest
    var engine = try BacktestEngine.init(allocator);
    defer engine.deinit();

    var strategy = try DualMAStrategy.create(allocator, .{
        .fast_period = 10,
        .slow_period = 20,
    });
    defer strategy.deinit();

    const config = BacktestConfig{
        .pair = TradingPair.fromString("ETH/USDC"),
        .timeframe = .m15,
        .start_time = candles.data[0].timestamp,
        .end_time = candles.data[candles.data.len - 1].timestamp,
        .initial_capital = try Decimal.fromInt(10000),
    };

    const result = try engine.run(strategy, config);
    defer result.deinit();

    // Analyze performance
    var analyzer = PerformanceAnalyzer.init(allocator);
    const metrics = try analyzer.analyze(result);

    // Verify metrics are reasonable
    try testing.expect(metrics.total_trades > 0);
    try testing.expect(metrics.win_rate >= 0.0 and metrics.win_rate <= 1.0);
    try testing.expect(metrics.profit_factor >= 0.0);
    try testing.expect(metrics.max_drawdown >= 0.0 and metrics.max_drawdown <= 1.0);
    try testing.expect(metrics.sharpe_ratio >= -10.0 and metrics.sharpe_ratio <= 10.0);

    // Log results for manual inspection
    std.debug.print("\n=== E2E Test Results ===\n", .{});
    std.debug.print("Total Trades: {}\n", .{metrics.total_trades});
    std.debug.print("Win Rate: {d:.2}%\n", .{metrics.win_rate * 100});
    std.debug.print("Profit Factor: {d:.2}\n", .{metrics.profit_factor});
    std.debug.print("Max Drawdown: {d:.2}%\n", .{metrics.max_drawdown * 100});
    std.debug.print("Sharpe Ratio: {d:.2}\n", .{metrics.sharpe_ratio});
}
```

---

## ⚡ Performance Tests

### Backtest Speed Benchmark

```zig
// tests/perf/backtest_perf_test.zig
test "Performance: Backtest 10,000 candles < 10s" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create 10,000 test candles
    var candles = try allocator.alloc(Candle, 10000);
    defer allocator.free(candles);
    for (candles, 0..) |*candle, i| {
        candle.* = generateTestCandle(i);
    }

    var engine = try BacktestEngine.init(allocator);
    defer engine.deinit();

    var strategy = try DualMAStrategy.create(allocator, .{
        .fast_period = 10,
        .slow_period = 20,
    });
    defer strategy.deinit();

    // Measure time
    const start = std.time.milliTimestamp();

    const result = try engine.run(strategy, config);
    defer result.deinit();

    const elapsed = std.time.milliTimestamp() - start;

    // Should complete in < 10 seconds
    std.debug.print("Backtest time: {}ms\n", .{elapsed});
    try testing.expect(elapsed < 10000);

    // Calculate candles/second
    const candles_per_second = @as(f64, @floatFromInt(10000)) /
        (@as(f64, @floatFromInt(elapsed)) / 1000.0);
    std.debug.print("Speed: {d:.0} candles/s\n", .{candles_per_second});

    // Target: > 1000 candles/s
    try testing.expect(candles_per_second > 1000);
}

test "Performance: Memory usage < 50MB for 10,000 candles" {
    // Track memory allocation during backtest
    var tracking_allocator = std.testing.allocator;

    var engine = try BacktestEngine.init(tracking_allocator);
    defer engine.deinit();

    // Create test data
    var candles = try tracking_allocator.alloc(Candle, 10000);
    defer tracking_allocator.free(candles);

    // Run backtest
    const result = try engine.run(strategy, config);
    defer result.deinit();

    // Verify memory usage (implementation depends on tracking allocator)
    // Should be < 50MB
}

test "Performance: Analyzer processes 1000 trades < 100ms" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var analyzer = PerformanceAnalyzer.init(allocator);

    // Create 1000 test trades
    var trades = try allocator.alloc(Trade, 1000);
    defer allocator.free(trades);
    for (trades, 0..) |*trade, i| {
        trade.* = generateTestTrade(i);
    }

    // Create test result
    var result = createTestResult(trades);
    defer result.deinit();

    // Measure time
    const start = std.time.milliTimestamp();
    const metrics = try analyzer.analyze(result);
    const elapsed = std.time.milliTimestamp() - start;

    std.debug.print("Analysis time: {}ms\n", .{elapsed});
    try testing.expect(elapsed < 100);
}
```

---

## ✅ Accuracy Validation

### Validation Against Reference Implementation

```zig
test "Accuracy: Compare with Freqtrade results" {
    // Use same historical data and strategy parameters as Freqtrade
    // Compare key metrics:
    // - Total trades (should match exactly)
    // - Win rate (should match within 0.1%)
    // - Net profit (should match within 0.1%)
    // - Max drawdown (should match within 1%)
}

test "Accuracy: Manual calculation verification" {
    // Create simple test case with known outcome
    // Manually calculate expected P&L
    // Verify backtest matches manual calculation
}

test "Accuracy: No look-ahead bias" {
    // Verify strategy only uses data available at each time point
    // Check that signals use index and not index+1
    // Ensure indicators don't peek into future
}
```

---

## 📊 Test Coverage

### Coverage Requirements

**Minimum Coverage Targets**:
- Overall: > 85%
- Critical paths: 100%
  - Order execution
  - Position management
  - P&L calculation
  - Account updates

### Running Coverage

```bash
# Generate coverage report
zig build test --summary all

# View detailed coverage
zig build test-coverage
```

### Coverage Exclusions

Exclude from coverage requirements:
- Test helper functions
- Debug logging code
- Error message strings

---

## 🎯 Test Execution

### Run All Tests

```bash
# Unit tests
zig build test

# Integration tests
zig build test-integration

# E2E tests
zig build test-e2e

# Performance tests
zig build test-perf

# All tests
zig build test-all
```

### Continuous Integration

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
      - name: Run tests
        run: zig build test-all
      - name: Check coverage
        run: zig build test-coverage
```

---

**Version**: v0.4.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-25
