# Strategy Framework 测试策略

**版本**: v0.3.0
**更新时间**: 2025-12-25

---

## 📋 目录

1. [测试目标](#测试目标)
2. [单元测试](#单元测试)
3. [集成测试](#集成测试)
4. [回测验证](#回测验证)
5. [性能测试](#性能测试)
6. [测试覆盖率](#测试覆盖率)

---

## 🎯 测试目标

### 功能测试

- ✅ IStrategy 接口实现正确
- ✅ 指标计算准确
- ✅ 信号生成逻辑正确
- ✅ 仓位大小计算合理
- ✅ 风险管理规则有效

### 质量测试

- ✅ 零内存泄漏
- ✅ 无数据竞争
- ✅ 错误处理完整
- ✅ 边界情况处理正确

### 性能测试

- ✅ 策略执行延迟 < 1ms
- ✅ 回测速度 > 1000 candles/s
- ✅ 内存占用 < 100MB

---

## 🧪 单元测试

### 测试文件组织

```
src/strategy/
├── interface_test.zig          # IStrategy 接口测试
├── context_test.zig            # StrategyContext 测试
├── signal_test.zig             # Signal 类型测试
├── risk_test.zig               # RiskManager 测试
│
├── indicators/
│   ├── sma_test.zig            # SMA 测试
│   ├── ema_test.zig            # EMA 测试
│   ├── rsi_test.zig            # RSI 测试
│   ├── macd_test.zig           # MACD 测试
│   └── bollinger_test.zig      # Bollinger Bands 测试
│
└── builtin/
    ├── dual_ma_test.zig        # 双均线策略测试
    ├── mean_reversion_test.zig # 均值回归策略测试
    └── breakout_test.zig       # 突破策略测试
```

### 指标测试示例

#### SMA 测试

```zig
// src/strategy/indicators/sma_test.zig
const std = @import("std");
const testing = std.testing;
const Decimal = @import("../../core/decimal.zig").Decimal;
const Candle = @import("../candles.zig").Candle;
const SMA = @import("sma.zig").SMA;

test "SMA: basic calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    // 准备测试数据: [1, 2, 3, 4, 5]
    const candles = [_]Candle{
        .{ .close = try Decimal.fromInt(1), ... },
        .{ .close = try Decimal.fromInt(2), ... },
        .{ .close = try Decimal.fromInt(3), ... },
        .{ .close = try Decimal.fromInt(4), ... },
        .{ .close = try Decimal.fromInt(5), ... },
    };

    // 计算 SMA(3)
    const sma = SMA.init(allocator, 3);
    const result = try sma.calculate(&candles);
    defer allocator.free(result);

    // 验证结果
    // result[0], result[1] 应该是 NaN
    try testing.expect(result[0].isNaN());
    try testing.expect(result[1].isNaN());

    // result[2] = (1 + 2 + 3) / 3 = 2
    try testing.expectEqual(try Decimal.fromInt(2), result[2]);

    // result[3] = (2 + 3 + 4) / 3 = 3
    try testing.expectEqual(try Decimal.fromInt(3), result[3]);

    // result[4] = (3 + 4 + 5) / 3 = 4
    try testing.expectEqual(try Decimal.fromInt(4), result[4]);
}

test "SMA: insufficient data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const candles = [_]Candle{
        .{ .close = try Decimal.fromInt(1), ... },
        .{ .close = try Decimal.fromInt(2), ... },
    };

    const sma = SMA.init(allocator, 3);
    const result = sma.calculate(&candles);

    // 应该返回 InsufficientData 错误
    try testing.expectError(error.InsufficientData, result);
}

test "SMA: edge case - period 1" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const candles = [_]Candle{
        .{ .close = try Decimal.fromInt(10), ... },
        .{ .close = try Decimal.fromInt(20), ... },
        .{ .close = try Decimal.fromInt(30), ... },
    };

    const sma = SMA.init(allocator, 1);
    const result = try sma.calculate(&candles);
    defer allocator.free(result);

    // SMA(1) 应该等于原值
    try testing.expectEqual(try Decimal.fromInt(10), result[0]);
    try testing.expectEqual(try Decimal.fromInt(20), result[1]);
    try testing.expectEqual(try Decimal.fromInt(30), result[2]);
}
```

#### RSI 测试

```zig
// src/strategy/indicators/rsi_test.zig
test "RSI: calculation with known values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 使用标准测试数据（来自 TA-Lib 参考）
    const prices = [_]Decimal{
        try Decimal.fromFloat(44.34),
        try Decimal.fromFloat(44.09),
        try Decimal.fromFloat(44.15),
        try Decimal.fromFloat(43.61),
        try Decimal.fromFloat(44.33),
        try Decimal.fromFloat(44.83),
        try Decimal.fromFloat(45.10),
        try Decimal.fromFloat(45.42),
        try Decimal.fromFloat(45.84),
        try Decimal.fromFloat(46.08),
        try Decimal.fromFloat(45.89),
        try Decimal.fromFloat(46.03),
        try Decimal.fromFloat(45.61),
        try Decimal.fromFloat(46.28),
        try Decimal.fromFloat(46.28),
        try Decimal.fromFloat(46.00),
    };

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);
    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = price, ... };
    }

    const rsi = RSI.init(allocator, 14);
    const result = try rsi.calculate(candles);
    defer allocator.free(result);

    // 验证最后一个 RSI 值（约 70.46）
    const last_rsi = result[result.len - 1];
    try testing.expectApproxEqAbs(70.46, last_rsi.toFloat(), 0.1);
}

test "RSI: overbought and oversold levels" {
    // 测试 RSI 边界值识别
    // ...
}
```

### 策略测试示例

#### 双均线策略测试

```zig
// src/strategy/builtin/dual_ma_test.zig
test "DualMAStrategy: golden cross signal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建策略
    const strategy = try DualMAStrategy.create(allocator, 3, 5);
    defer strategy.deinit();

    // 创建 mock context
    var mock_ctx = MockStrategyContext.init(allocator);
    defer mock_ctx.deinit();

    try strategy.init(mock_ctx.context());

    // 准备测试数据: 模拟金叉场景
    // 价格从下跌转为上涨，快线上穿慢线
    const candles_data = [_]Candle{
        .{ .close = try Decimal.fromInt(100), ... },
        .{ .close = try Decimal.fromInt(98), ... },
        .{ .close = try Decimal.fromInt(96), ... },
        .{ .close = try Decimal.fromInt(97), ... },
        .{ .close = try Decimal.fromInt(99), ... },
        .{ .close = try Decimal.fromInt(102), ... },  // 金叉发生
        .{ .close = try Decimal.fromInt(105), ... },
    };

    var candles = Candles.init(allocator, &candles_data);
    defer candles.deinit();

    // 计算指标
    try strategy.populateIndicators(&candles);

    // 检查金叉信号（index = 5）
    const signal = try strategy.generateEntrySignal(&candles, 5);

    try testing.expect(signal != null);
    try testing.expectEqual(.entry_long, signal.?.type);
    try testing.expectEqual(.buy, signal.?.side);
    try testing.expect(signal.?.strength >= 0.5);
}

test "DualMAStrategy: no signal when conditions not met" {
    // 测试无信号场景
    // ...
}

test "DualMAStrategy: exit signal on death cross" {
    // 测试出场信号
    // ...
}

test "DualMAStrategy: parameters validation" {
    // 测试参数验证
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // fast_period 必须小于 slow_period
    const result = DualMAStrategy.create(allocator, 20, 10);
    try testing.expectError(error.InvalidParameter, result);
}
```

### RiskManager 测试

```zig
// src/strategy/risk_test.zig
test "RiskManager: stop loss triggered" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try MockLogger.init(allocator);
    defer logger.deinit();

    const config = RiskManager.RiskConfig{
        .max_position_size = try Decimal.fromInt(1000),
        .max_leverage = 10,
        .max_drawdown = 0.2,
        .max_daily_loss = try Decimal.fromInt(500),
    };

    var risk_mgr = RiskManager.init(allocator, logger, config);
    defer risk_mgr.deinit();

    // 创建持仓
    const position = Position{
        .pair = .{ .base = "ETH", .quote = "USDC" },
        .side = .long,
        .size = try Decimal.fromInt(10),
        .entry_price = try Decimal.fromInt(2000),  // 入场价 2000
        .timestamp = Timestamp.now(),
    };

    // 策略元数据: 5% 止损
    const metadata = StrategyMetadata{
        .stoploss = try Decimal.fromFloat(-0.05),
        // ...
    };

    // 当前价格 1900（下跌 5%）
    const current_price = try Decimal.fromInt(1900);

    // 检查止损
    const signal = try risk_mgr.checkStopLoss(position, current_price, metadata);

    // 应该触发止损
    try testing.expect(signal != null);
    try testing.expectEqual(.exit_long, signal.?.type);
    try testing.expectEqual(.sell, signal.?.side);
}

test "RiskManager: take profit triggered" {
    // 测试止盈触发
    // ...
}

test "RiskManager: order validation - exceeds max position size" {
    // 测试订单验证
    // ...
}
```

---

## 🔗 集成测试

### 策略端到端测试

```zig
// tests/integration/strategy_e2e_test.zig
test "Strategy E2E: DualMA backtest on historical data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 加载历史数据
    const candles = try loadHistoricalCandles(
        allocator,
        "ETH-USDC",
        .m15,
        "2024-01-01",
        "2024-01-31",
    );
    defer allocator.free(candles);

    // 2. 创建策略
    const strategy = try DualMAStrategy.create(allocator, 10, 20);
    defer strategy.deinit();

    // 3. 创建回测引擎
    var engine = BacktestEngine.init(allocator, logger);
    defer engine.deinit();

    // 4. 运行回测
    const config = BacktestConfig{
        .pair = .{ .base = "ETH", .quote = "USDC" },
        .timeframe = .m15,
        .start_time = try Timestamp.fromISO8601("2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.fromISO8601("2024-01-31T23:59:59Z"),
        .initial_capital = try Decimal.fromInt(10000),
        .commission_rate = try Decimal.fromFloat(0.001),
    };

    const result = try engine.run(strategy, config);

    // 5. 验证结果
    try testing.expect(result.total_trades > 0);
    try testing.expect(result.win_rate >= 0.0 and result.win_rate <= 1.0);
    try testing.expect(result.sharpe_ratio > -5.0 and result.sharpe_ratio < 5.0);
    try testing.expect(result.max_drawdown >= 0.0 and result.max_drawdown <= 1.0);

    // 6. 检查无内存泄漏
    // (由 GeneralPurposeAllocator 自动检查)
}
```

### Mock 组件

```zig
// tests/mocks/mock_strategy_context.zig
pub const MockStrategyContext = struct {
    allocator: std.mem.Allocator,
    logger: MockLogger,
    market_data: MockMarketDataProvider,
    executor: MockOrderExecutor,
    position_manager: MockPositionManager,
    risk_manager: MockRiskManager,
    indicator_manager: IndicatorManager,

    pub fn init(allocator: std.mem.Allocator) !MockStrategyContext {
        return .{
            .allocator = allocator,
            .logger = try MockLogger.init(allocator),
            .market_data = MockMarketDataProvider.init(),
            .executor = MockOrderExecutor.init(),
            .position_manager = MockPositionManager.init(),
            .risk_manager = MockRiskManager.init(),
            .indicator_manager = IndicatorManager.init(allocator),
        };
    }

    pub fn deinit(self: *MockStrategyContext) void {
        self.logger.deinit();
        self.indicator_manager.deinit();
    }

    pub fn context(self: *MockStrategyContext) StrategyContext {
        return StrategyContext{
            .allocator = self.allocator,
            .logger = self.logger.logger(),
            .market_data = &self.market_data,
            .executor = &self.executor,
            .position_manager = &self.position_manager,
            .risk_manager = &self.risk_manager,
            .indicator_manager = &self.indicator_manager,
            .exchange = MockExchange.interface(),
            .config = .{
                .pair = .{ .base = "ETH", .quote = "USDC" },
                .timeframe = .m15,
            },
        };
    }
};
```

---

## 📊 回测验证

### 回测正确性验证

```zig
test "Backtest: manual verification against known results" {
    // 使用已知的历史数据和策略参数
    // 验证回测结果与手工计算一致

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 简单场景: 3 个蜡烛，产生 1 次交易
    const candles_data = [_]Candle{
        .{ .close = try Decimal.fromInt(100), .timestamp = try Timestamp.fromISO8601("2024-01-01T00:00:00Z"), ... },
        .{ .close = try Decimal.fromInt(105), .timestamp = try Timestamp.fromISO8601("2024-01-01T00:15:00Z"), ... },  // 入场
        .{ .close = try Decimal.fromInt(110), .timestamp = try Timestamp.fromISO8601("2024-01-01T00:30:00Z"), ... },  // 出场
    };

    // ... 运行回测

    // 验证:
    // - 总交易次数 = 1
    // - 入场价 = 105
    // - 出场价 = 110
    // - 收益 = (110 - 105) / 105 = 4.76%
    // - 净利润 = 初始资金 * 4.76% - 手续费
}
```

---

## ⚡ 性能测试

### Benchmark 测试

```zig
// benchmarks/strategy_benchmark.zig
const std = @import("std");
const Timer = std.time.Timer;

test "Benchmark: SMA calculation (1000 candles)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const candles = try generateRandomCandles(allocator, 1000);
    defer allocator.free(candles);

    const sma = SMA.init(allocator, 20);

    var timer = try Timer.start();
    const start = timer.read();

    const result = try sma.calculate(candles);
    defer allocator.free(result);

    const end = timer.read();
    const elapsed_ns = end - start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;

    std.debug.print("SMA calculation (1000 candles, period=20): {d:.2} μs\n", .{elapsed_us});

    // 目标: < 500μs
    try std.testing.expect(elapsed_us < 500.0);
}

test "Benchmark: strategy signal generation (1000 iterations)" {
    // 测试信号生成延迟
    // 目标: < 100μs per signal
}

test "Benchmark: backtest speed (10000 candles)" {
    // 测试回测速度
    // 目标: > 1000 candles/s
}
```

---

## 📈 测试覆盖率

### 目标覆盖率

- **核心接口**: 100%
- **指标库**: > 95%
- **内置策略**: > 90%
- **风险管理**: 100%
- **回测引擎**: > 85%

### 运行测试

```bash
# 运行所有测试
zig build test --summary all

# 运行策略测试
zig build test-strategy

# 运行指标测试
zig build test-indicators

# 运行集成测试
zig build test-strategy-integration

# 运行性能测试
zig build bench-strategy
```

### 测试报告

```
预期输出:

================================================================================
Strategy Framework Tests
================================================================================
Unit Tests:
  ✅ IStrategy interface          15/15 passed
  ✅ Indicators (SMA, EMA, etc.)  25/25 passed
  ✅ Built-in strategies          18/18 passed
  ✅ RiskManager                  12/12 passed
  ✅ StrategyContext               8/8 passed

Integration Tests:
  ✅ Strategy E2E                  5/5 passed
  ✅ Backtest validation           3/3 passed

Performance Tests:
  ✅ SMA calculation               < 500μs  ✅
  ✅ Signal generation             < 100μs  ✅
  ✅ Backtest speed                > 1000 candles/s  ✅

Total: 91/91 tests passed
Memory: No leaks detected
Coverage: 93.5%
================================================================================
```

---

## 🐛 测试发现的问题

测试过程中发现的问题会记录到 [bugs.md](./bugs.md)。

---

## 📝 测试最佳实践

1. **AAA 模式**: Arrange-Act-Assert
2. **独立性**: 每个测试独立运行
3. **可重复**: 测试结果可重复
4. **清晰命名**: 测试名称描述测试内容
5. **边界测试**: 覆盖边界条件
6. **内存检查**: 使用 GeneralPurposeAllocator
7. **Mock 隔离**: 使用 mock 隔离依赖

---

**版本**: v0.3.0
**状态**: 设计阶段
**更新时间**: 2025-12-25
