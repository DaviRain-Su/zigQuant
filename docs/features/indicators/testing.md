# Technical Indicators Library 测试策略

**版本**: v0.3.0
**更新时间**: 2025-12-25

---

## 📋 目录

1. [测试目标](#测试目标)
2. [单元测试](#单元测试)
3. [准确性测试](#准确性测试)
4. [边界测试](#边界测试)
5. [性能测试](#性能测试)
6. [测试覆盖率](#测试覆盖率)

---

## 🎯 测试目标

### 功能测试

- ✅ 指标计算正确性
- ✅ IIndicator 接口实现完整
- ✅ 参数验证有效
- ✅ 与 TA-Lib 结果一致性
- ✅ 边界情况处理正确

### 质量测试

- ✅ 零内存泄漏
- ✅ 无数据竞争
- ✅ 错误处理完整
- ✅ 浮点精度处理正确
- ✅ NaN 和无效值处理

### 性能测试

- ✅ SMA 计算 < 500μs (1000 蜡烛)
- ✅ EMA 计算 < 400μs (1000 蜡烛)
- ✅ RSI 计算 < 600μs (1000 蜡烛)
- ✅ MACD 计算 < 800μs (1000 蜡烛)
- ✅ Bollinger Bands 计算 < 700μs (1000 蜡烛)
- ✅ 内存占用合理 (< 50KB per 1000 candles)

---

## 🧪 单元测试

### 测试文件组织

```
src/indicators/
├── sma_test.zig              # SMA 测试
├── ema_test.zig              # EMA 测试
├── rsi_test.zig              # RSI 测试
├── macd_test.zig             # MACD 测试
├── bollinger_test.zig        # Bollinger Bands 测试
├── atr_test.zig              # ATR 测试 (v0.4.0+)
└── interface_test.zig        # IIndicator 接口测试
```

---

## 📊 指标测试示例

### SMA (Simple Moving Average) 测试

```zig
// src/indicators/sma_test.zig
const std = @import("std");
const testing = std.testing;
const Decimal = @import("../core/decimal.zig").Decimal;
const Candle = @import("../market/candle.zig").Candle;
const SMA = @import("sma.zig").SMA;

test "SMA: basic calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    // 测试数据: [1, 2, 3, 4, 5]
    const prices = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{
            .open = try Decimal.fromFloat(price),
            .high = try Decimal.fromFloat(price),
            .low = try Decimal.fromFloat(price),
            .close = try Decimal.fromFloat(price),
            .volume = try Decimal.fromInt(1000),
            .timestamp = 1640000000 + @as(i64, @intCast(i)) * 900,
        };
    }

    // 计算 SMA(3)
    const sma = SMA.init(allocator, 3);
    const result = try sma.calculate(candles);
    defer allocator.free(result);

    // 验证结果长度
    try testing.expectEqual(prices.len, result.len);

    // 前两个值应该是 NaN (不足 period)
    try testing.expect(result[0].isNaN());
    try testing.expect(result[1].isNaN());

    // result[2] = (1 + 2 + 3) / 3 = 2.0
    try testing.expectApproxEqAbs(
        2.0,
        try result[2].toFloat(),
        0.0001,
    );

    // result[3] = (2 + 3 + 4) / 3 = 3.0
    try testing.expectApproxEqAbs(
        3.0,
        try result[3].toFloat(),
        0.0001,
    );

    // result[4] = (3 + 4 + 5) / 3 = 4.0
    try testing.expectApproxEqAbs(
        4.0,
        try result[4].toFloat(),
        0.0001,
    );
}

test "SMA: insufficient data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const prices = [_]f64{ 1.0, 2.0 };
    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{
            .close = try Decimal.fromFloat(price),
            .timestamp = @intCast(i),
            // ... other fields
        };
    }

    const sma = SMA.init(allocator, 3);
    const result = try sma.calculate(candles);
    defer allocator.free(result);

    // 所有值应该是 NaN
    try testing.expect(result[0].isNaN());
    try testing.expect(result[1].isNaN());
}

test "SMA: period equals 1" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const prices = [_]f64{ 10.0, 20.0, 30.0 };
    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{
            .close = try Decimal.fromFloat(price),
            .timestamp = @intCast(i),
            // ... other fields
        };
    }

    const sma = SMA.init(allocator, 1);
    const result = try sma.calculate(candles);
    defer allocator.free(result);

    // SMA(1) 应该等于原值
    for (prices, 0..) |expected, i| {
        try testing.expectApproxEqAbs(
            expected,
            try result[i].toFloat(),
            0.0001,
        );
    }
}

test "SMA: large dataset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const n = 1000;
    var candles = try allocator.alloc(Candle, n);
    defer allocator.free(candles);

    // 生成测试数据
    for (0..n) |i| {
        candles[i] = .{
            .close = try Decimal.fromFloat(@as(f64, @floatFromInt(i))),
            .timestamp = @intCast(i),
            // ... other fields
        };
    }

    const sma = SMA.init(allocator, 20);
    const result = try sma.calculate(candles);
    defer allocator.free(result);

    try testing.expectEqual(n, result.len);

    // 验证最后一个值
    // SMA(20) 的最后值 = (980 + 981 + ... + 999) / 20 = 989.5
    try testing.expectApproxEqAbs(
        989.5,
        try result[n - 1].toFloat(),
        0.0001,
    );
}

test "SMA: invalid period zero" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // period = 0 应该返回错误
    const sma = SMA.init(allocator, 0);
    try testing.expectError(error.InvalidPeriod, sma.validate());
}
```

---

### EMA (Exponential Moving Average) 测试

```zig
// src/indicators/ema_test.zig
test "EMA: basic calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试数据
    const prices = [_]f64{ 22.27, 22.19, 22.08, 22.17, 22.18, 22.13, 22.23, 22.43, 22.24, 22.29 };
    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{
            .close = try Decimal.fromFloat(price),
            .timestamp = @intCast(i),
            // ... other fields
        };
    }

    // 计算 EMA(5)
    const ema = EMA.init(allocator, 5);
    const result = try ema.calculate(candles);
    defer allocator.free(result);

    // EMA 公式: EMA = Price(t) * k + EMA(t-1) * (1 - k)
    // k = 2 / (period + 1) = 2 / 6 = 0.333...

    // 第一个 EMA 通常用 SMA 初始化
    // EMA[4] = SMA(5) = (22.27 + 22.19 + 22.08 + 22.17 + 22.18) / 5 = 22.178
    try testing.expectApproxEqAbs(
        22.178,
        try result[4].toFloat(),
        0.001,
    );

    // 验证前 4 个值为 NaN
    for (0..4) |i| {
        try testing.expect(result[i].isNaN());
    }
}

test "EMA: comparison with SMA" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 在稳定数据上,EMA 和 SMA 应该接近
    const prices = [_]f64{ 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0 };
    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const ema = EMA.init(allocator, 5);
    const ema_result = try ema.calculate(candles);
    defer allocator.free(ema_result);

    const sma = SMA.init(allocator, 5);
    const sma_result = try sma.calculate(candles);
    defer allocator.free(sma_result);

    // 稳定数据下,EMA 和 SMA 应该都等于 10.0
    try testing.expectApproxEqAbs(
        10.0,
        try ema_result[prices.len - 1].toFloat(),
        0.0001,
    );
    try testing.expectApproxEqAbs(
        10.0,
        try sma_result[prices.len - 1].toFloat(),
        0.0001,
    );
}

test "EMA: trend responsiveness" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // EMA 应该比 SMA 更快响应价格变化
    // 价格从 10 突然跳到 20
    const prices = [_]f64{ 10.0, 10.0, 10.0, 10.0, 10.0, 20.0, 20.0, 20.0, 20.0, 20.0 };
    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const ema = EMA.init(allocator, 5);
    const ema_result = try ema.calculate(candles);
    defer allocator.free(ema_result);

    const sma = SMA.init(allocator, 5);
    const sma_result = try sma.calculate(candles);
    defer allocator.free(sma_result);

    // 在 index 7 时 (价格变化后两根蜡烛)
    // EMA 应该更接近新价格 20
    const ema_val = try ema_result[7].toFloat();
    const sma_val = try sma_result[7].toFloat();

    try testing.expect(ema_val > sma_val);
    try testing.expect(ema_val > 15.0); // EMA 更快上升
}
```

---

### RSI (Relative Strength Index) 测试

```zig
// src/indicators/rsi_test.zig
test "RSI: calculation with known values (TA-Lib reference)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // TA-Lib 标准测试数据
    const prices = [_]f64{
        44.34, 44.09, 44.15, 43.61, 44.33,
        44.83, 45.10, 45.42, 45.84, 46.08,
        45.89, 46.03, 45.61, 46.28, 46.28,
        46.00, 46.03, 46.41, 46.22, 45.64,
    };

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{
            .close = try Decimal.fromFloat(price),
            .timestamp = @intCast(i),
            // ... other fields
        };
    }

    const rsi = RSI.init(allocator, 14);
    const result = try rsi.calculate(candles);
    defer allocator.free(result);

    // TA-Lib 参考值 (14 周期 RSI):
    // index 14: RSI ≈ 70.46
    // index 19: RSI ≈ 66.25
    try testing.expectApproxEqAbs(
        70.46,
        try result[14].toFloat(),
        0.5, // 允许 0.5 的误差
    );

    try testing.expectApproxEqAbs(
        66.25,
        try result[19].toFloat(),
        0.5,
    );
}

test "RSI: overbought level (>70)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 构造持续上涨的数据
    var prices: [30]f64 = undefined;
    for (0..30) |i| {
        prices[i] = 100.0 + @as(f64, @floatFromInt(i)) * 2.0; // 从 100 涨到 158
    }

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const rsi = RSI.init(allocator, 14);
    const result = try rsi.calculate(candles);
    defer allocator.free(result);

    // 持续上涨,RSI 应该接近 100
    const last_rsi = try result[prices.len - 1].toFloat();
    try testing.expect(last_rsi > 70.0); // 超买
    try testing.expect(last_rsi <= 100.0); // 不超过上限
}

test "RSI: oversold level (<30)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 构造持续下跌的数据
    var prices: [30]f64 = undefined;
    for (0..30) |i| {
        prices[i] = 200.0 - @as(f64, @floatFromInt(i)) * 2.0; // 从 200 跌到 142
    }

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const rsi = RSI.init(allocator, 14);
    const result = try rsi.calculate(candles);
    defer allocator.free(result);

    // 持续下跌,RSI 应该接近 0
    const last_rsi = try result[prices.len - 1].toFloat();
    try testing.expect(last_rsi < 30.0); // 超卖
    try testing.expect(last_rsi >= 0.0); // 不低于下限
}

test "RSI: neutral market (RSI ≈ 50)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 构造震荡数据 (上下波动但总体持平)
    const prices = [_]f64{
        100.0, 102.0, 99.0, 101.0, 98.0,
        103.0, 97.0, 102.0, 99.0, 101.0,
        100.0, 102.0, 98.0, 101.0, 99.0,
        102.0, 100.0, 101.0, 99.0, 100.0,
    };

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const rsi = RSI.init(allocator, 14);
    const result = try rsi.calculate(candles);
    defer allocator.free(result);

    // 震荡市场,RSI 应该在 40-60 之间
    const last_rsi = try result[prices.len - 1].toFloat();
    try testing.expect(last_rsi > 40.0 and last_rsi < 60.0);
}

test "RSI: division by zero handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 所有价格相同 (无涨跌)
    const prices = [_]f64{ 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0 };

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const rsi = RSI.init(allocator, 14);
    const result = try rsi.calculate(candles);
    defer allocator.free(result);

    // 价格不变时,RSI 应该是 50 或 NaN (取决于实现)
    // 通常定义为 50 (中性)
    const last_rsi = try result[prices.len - 1].toFloat();
    try testing.expectApproxEqAbs(50.0, last_rsi, 0.1);
}
```

---

### MACD (Moving Average Convergence Divergence) 测试

```zig
// src/indicators/macd_test.zig
test "MACD: basic calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 生成测试数据
    var prices: [50]f64 = undefined;
    for (0..50) |i| {
        // 模拟价格波动
        prices[i] = 100.0 + @sin(@as(f64, @floatFromInt(i)) * 0.2) * 10.0;
    }

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    // 计算 MACD (12, 26, 9)
    const macd = MACD.init(allocator, 12, 26, 9);
    const result = try macd.calculate(candles);
    defer {
        allocator.free(result.macd_line);
        allocator.free(result.signal_line);
        allocator.free(result.histogram);
    }

    // 验证结果长度
    try testing.expectEqual(prices.len, result.macd_line.len);
    try testing.expectEqual(prices.len, result.signal_line.len);
    try testing.expectEqual(prices.len, result.histogram.len);

    // 前 25 个值 (slow_period - 1) 应该是 NaN
    for (0..25) |i| {
        try testing.expect(result.macd_line[i].isNaN());
    }

    // 前 33 个值 (slow_period + signal_period - 2) 的 signal 应该是 NaN
    for (0..33) |i| {
        try testing.expect(result.signal_line[i].isNaN());
    }

    // Histogram = MACD Line - Signal Line
    for (34..prices.len) |i| {
        const expected_hist = try result.macd_line[i].sub(result.signal_line[i]);
        try testing.expectApproxEqAbs(
            try expected_hist.toFloat(),
            try result.histogram[i].toFloat(),
            0.0001,
        );
    }
}

test "MACD: golden cross" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 构造金叉场景: 价格从下跌转为上涨
    var prices: [60]f64 = undefined;
    for (0..30) |i| {
        prices[i] = 100.0 - @as(f64, @floatFromInt(i)); // 下跌
    }
    for (30..60) |i| {
        prices[i] = 70.0 + @as(f64, @floatFromInt(i - 30)) * 1.5; // 上涨
    }

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const macd = MACD.init(allocator, 12, 26, 9);
    const result = try macd.calculate(candles);
    defer {
        allocator.free(result.macd_line);
        allocator.free(result.signal_line);
        allocator.free(result.histogram);
    }

    // 在趋势转折后,应该出现金叉 (Histogram > 0)
    var found_golden_cross = false;
    for (40..prices.len) |i| {
        if (!result.histogram[i].isNaN()) {
            const hist_val = try result.histogram[i].toFloat();
            if (hist_val > 0) {
                found_golden_cross = true;
                break;
            }
        }
    }

    try testing.expect(found_golden_cross);
}

test "MACD: death cross" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 构造死叉场景: 价格从上涨转为下跌
    var prices: [60]f64 = undefined;
    for (0..30) |i| {
        prices[i] = 70.0 + @as(f64, @floatFromInt(i)) * 1.5; // 上涨
    }
    for (30..60) |i| {
        prices[i] = 115.0 - @as(f64, @floatFromInt(i - 30)); // 下跌
    }

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const macd = MACD.init(allocator, 12, 26, 9);
    const result = try macd.calculate(candles);
    defer {
        allocator.free(result.macd_line);
        allocator.free(result.signal_line);
        allocator.free(result.histogram);
    }

    // 在趋势转折后,应该出现死叉 (Histogram < 0)
    var found_death_cross = false;
    for (40..prices.len) |i| {
        if (!result.histogram[i].isNaN()) {
            const hist_val = try result.histogram[i].toFloat();
            if (hist_val < 0) {
                found_death_cross = true;
                break;
            }
        }
    }

    try testing.expect(found_death_cross);
}

test "MACD: parameters validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // fast_period 必须小于 slow_period
    const macd1 = MACD.init(allocator, 26, 12, 9);
    try testing.expectError(error.InvalidParameter, macd1.validate());

    // period 不能为 0
    const macd2 = MACD.init(allocator, 0, 26, 9);
    try testing.expectError(error.InvalidParameter, macd2.validate());

    const macd3 = MACD.init(allocator, 12, 26, 0);
    try testing.expectError(error.InvalidParameter, macd3.validate());
}
```

---

### Bollinger Bands 测试

```zig
// src/indicators/bollinger_test.zig
test "BollingerBands: basic calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 使用简单数据: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    var prices: [10]f64 = undefined;
    for (0..10) |i| {
        prices[i] = @as(f64, @floatFromInt(i + 1));
    }

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    // 计算 BB (5, 2.0)
    const bb = BollingerBands.init(allocator, 5, 2.0);
    const result = try bb.calculate(candles);
    defer {
        allocator.free(result.upper);
        allocator.free(result.middle);
        allocator.free(result.lower);
    }

    // 验证结果长度
    try testing.expectEqual(prices.len, result.upper.len);
    try testing.expectEqual(prices.len, result.middle.len);
    try testing.expectEqual(prices.len, result.lower.len);

    // 前 4 个值应该是 NaN
    for (0..4) |i| {
        try testing.expect(result.middle[i].isNaN());
    }

    // index 4: [1,2,3,4,5]
    // Middle = SMA = 3.0
    // StdDev = sqrt(((1-3)² + (2-3)² + (3-3)² + (4-3)² + (5-3)²) / 5)
    //        = sqrt((4 + 1 + 0 + 1 + 4) / 5)
    //        = sqrt(2) ≈ 1.414
    // Upper = 3.0 + 2 * 1.414 = 5.828
    // Lower = 3.0 - 2 * 1.414 = 0.172

    try testing.expectApproxEqAbs(
        3.0,
        try result.middle[4].toFloat(),
        0.001,
    );

    try testing.expectApproxEqAbs(
        5.828,
        try result.upper[4].toFloat(),
        0.01,
    );

    try testing.expectApproxEqAbs(
        0.172,
        try result.lower[4].toFloat(),
        0.01,
    );
}

test "BollingerBands: band squeeze" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 低波动性数据 (价格接近恒定)
    const prices = [_]f64{ 100.0, 100.1, 99.9, 100.2, 99.8, 100.1, 100.0, 99.9, 100.1, 100.0, 99.9, 100.0, 100.1, 99.9, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0 };

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const bb = BollingerBands.init(allocator, 20, 2.0);
    const result = try bb.calculate(candles);
    defer {
        allocator.free(result.upper);
        allocator.free(result.middle);
        allocator.free(result.lower);
    }

    // 低波动性时,带宽应该很窄
    const last_idx = prices.len - 1;
    const bandwidth = try result.upper[last_idx].sub(result.lower[last_idx]);
    const bandwidth_val = try bandwidth.toFloat();

    try testing.expect(bandwidth_val < 1.0); // 带宽很小
}

test "BollingerBands: band expansion" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 高波动性数据 (价格剧烈波动)
    var prices: [30]f64 = undefined;
    for (0..30) |i| {
        // 大幅波动
        prices[i] = 100.0 + @sin(@as(f64, @floatFromInt(i)) * 0.5) * 20.0;
    }

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const bb = BollingerBands.init(allocator, 20, 2.0);
    const result = try bb.calculate(candles);
    defer {
        allocator.free(result.upper);
        allocator.free(result.middle);
        allocator.free(result.lower);
    }

    // 高波动性时,带宽应该较宽
    const last_idx = prices.len - 1;
    const bandwidth = try result.upper[last_idx].sub(result.lower[last_idx]);
    const bandwidth_val = try bandwidth.toFloat();

    try testing.expect(bandwidth_val > 10.0); // 带宽较大
}

test "BollingerBands: price touches bands" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 构造价格触及上轨的场景
    var prices: [25]f64 = undefined;
    for (0..20) |i| {
        prices[i] = 100.0; // 稳定价格
    }
    for (20..25) |i| {
        prices[i] = 110.0; // 突然上涨
    }

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const bb = BollingerBands.init(allocator, 20, 2.0);
    const result = try bb.calculate(candles);
    defer {
        allocator.free(result.upper);
        allocator.free(result.middle);
        allocator.free(result.lower);
    }

    // 最后的价格应该接近或超过上轨
    const last_idx = prices.len - 1;
    const last_price = prices[last_idx];
    const upper_band = try result.upper[last_idx].toFloat();

    try testing.expect(last_price >= upper_band * 0.9); // 接近上轨
}
```

---

## 🎯 准确性测试

### 与 TA-Lib 结果对比

```zig
// tests/accuracy/talib_comparison_test.zig
const std = @import("std");
const testing = std.testing;

test "Accuracy: SMA vs TA-Lib" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 加载 TA-Lib 参考数据
    const talib_data = try loadTALibReferenceData(
        allocator,
        "test_data/talib_sma_20.json",
    );
    defer talib_data.deinit();

    // 使用相同的输入数据计算 SMA
    const sma = SMA.init(allocator, 20);
    const our_result = try sma.calculate(talib_data.candles);
    defer allocator.free(our_result);

    // 逐点比较
    for (talib_data.expected_output, 0..) |expected, i| {
        if (expected.isNaN()) {
            try testing.expect(our_result[i].isNaN());
        } else {
            const expected_val = try expected.toFloat();
            const actual_val = try our_result[i].toFloat();
            const diff = @abs(expected_val - actual_val);
            const relative_error = diff / @max(@abs(expected_val), 0.0001);

            // 允许 0.01% 的相对误差
            try testing.expect(relative_error < 0.0001);
        }
    }
}

test "Accuracy: RSI vs TA-Lib" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const talib_data = try loadTALibReferenceData(
        allocator,
        "test_data/talib_rsi_14.json",
    );
    defer talib_data.deinit();

    const rsi = RSI.init(allocator, 14);
    const our_result = try rsi.calculate(talib_data.candles);
    defer allocator.free(our_result);

    for (talib_data.expected_output, 0..) |expected, i| {
        if (expected.isNaN()) {
            try testing.expect(our_result[i].isNaN());
        } else {
            const expected_val = try expected.toFloat();
            const actual_val = try our_result[i].toFloat();
            const diff = @abs(expected_val - actual_val);

            // RSI 允许 0.5 的绝对误差
            try testing.expect(diff < 0.5);
        }
    }
}

test "Accuracy: MACD vs TA-Lib" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const talib_data = try loadTALibReferenceData(
        allocator,
        "test_data/talib_macd_12_26_9.json",
    );
    defer talib_data.deinit();

    const macd = MACD.init(allocator, 12, 26, 9);
    const our_result = try macd.calculate(talib_data.candles);
    defer {
        allocator.free(our_result.macd_line);
        allocator.free(our_result.signal_line);
        allocator.free(our_result.histogram);
    }

    // 比较 MACD Line
    for (talib_data.expected_macd_line, 0..) |expected, i| {
        if (!expected.isNaN()) {
            const expected_val = try expected.toFloat();
            const actual_val = try our_result.macd_line[i].toFloat();
            const diff = @abs(expected_val - actual_val);
            const relative_error = diff / @max(@abs(expected_val), 0.0001);

            try testing.expect(relative_error < 0.001); // 0.1% 误差
        }
    }

    // 比较 Signal Line
    for (talib_data.expected_signal_line, 0..) |expected, i| {
        if (!expected.isNaN()) {
            const expected_val = try expected.toFloat();
            const actual_val = try our_result.signal_line[i].toFloat();
            const diff = @abs(expected_val - actual_val);
            const relative_error = diff / @max(@abs(expected_val), 0.0001);

            try testing.expect(relative_error < 0.001);
        }
    }
}
```

---

## 🔍 边界测试

### 边界情况和错误处理

```zig
// tests/edge_cases/indicator_edge_test.zig
test "Edge: empty candles array" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const candles = try allocator.alloc(Candle, 0);
    defer allocator.free(candles);

    const sma = SMA.init(allocator, 20);
    const result = sma.calculate(candles);

    try testing.expectError(error.InsufficientData, result);
}

test "Edge: single candle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const candles = [_]Candle{
        .{ .close = try Decimal.fromFloat(100.0), .timestamp = 0 },
    };

    const sma = SMA.init(allocator, 1);
    const result = try sma.calculate(&candles);
    defer allocator.free(result);

    try testing.expectApproxEqAbs(
        100.0,
        try result[0].toFloat(),
        0.0001,
    );
}

test "Edge: extreme price values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试极大值
    const large_prices = [_]f64{ 1e10, 1e10, 1e10, 1e10, 1e10 };
    var candles_large = try allocator.alloc(Candle, large_prices.len);
    defer allocator.free(candles_large);

    for (large_prices, 0..) |price, i| {
        candles_large[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const sma1 = SMA.init(allocator, 3);
    const result1 = try sma1.calculate(candles_large);
    defer allocator.free(result1);

    try testing.expect(!result1[4].isNaN());
    try testing.expect(!result1[4].isInf());

    // 测试极小值
    const small_prices = [_]f64{ 1e-10, 1e-10, 1e-10, 1e-10, 1e-10 };
    var candles_small = try allocator.alloc(Candle, small_prices.len);
    defer allocator.free(candles_small);

    for (small_prices, 0..) |price, i| {
        candles_small[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const sma2 = SMA.init(allocator, 3);
    const result2 = try sma2.calculate(candles_small);
    defer allocator.free(result2);

    try testing.expect(!result2[4].isNaN());
    try testing.expect(!result2[4].isInf());
}

test "Edge: zero prices" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const prices = [_]f64{ 0.0, 0.0, 0.0, 0.0, 0.0 };
    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const sma = SMA.init(allocator, 3);
    const result = try sma.calculate(candles);
    defer allocator.free(result);

    // 零价格的 SMA 应该是 0
    try testing.expectApproxEqAbs(
        0.0,
        try result[4].toFloat(),
        0.0001,
    );
}

test "Edge: negative prices" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const prices = [_]f64{ -10.0, -20.0, -30.0, -40.0, -50.0 };
    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const sma = SMA.init(allocator, 3);
    const result = try sma.calculate(candles);
    defer allocator.free(result);

    // 负价格的 SMA 应该也是负数
    try testing.expectApproxEqAbs(
        -40.0,
        try result[4].toFloat(),
        0.0001,
    );
}

test "Edge: NaN in input data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const prices = [_]f64{ 10.0, 20.0, std.math.nan(f64), 40.0, 50.0 };
    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const sma = SMA.init(allocator, 3);
    const result = sma.calculate(candles);

    // 输入包含 NaN 应该返回错误
    try testing.expectError(error.InvalidInput, result);
}

test "Edge: period larger than data size" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const prices = [_]f64{ 10.0, 20.0, 30.0, 40.0, 50.0 };
    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const sma = SMA.init(allocator, 100);
    const result = try sma.calculate(candles);
    defer allocator.free(result);

    // 所有值应该是 NaN
    for (result) |value| {
        try testing.expect(value.isNaN());
    }
}

test "Edge: maximum period value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试最大周期值
    const max_period = 1000;
    var prices: [2000]f64 = undefined;
    for (0..2000) |i| {
        prices[i] = @as(f64, @floatFromInt(i + 1));
    }

    var candles = try allocator.alloc(Candle, prices.len);
    defer allocator.free(candles);

    for (prices, 0..) |price, i| {
        candles[i] = .{ .close = try Decimal.fromFloat(price), .timestamp = @intCast(i) };
    }

    const sma = SMA.init(allocator, max_period);
    const result = try sma.calculate(candles);
    defer allocator.free(result);

    // 应该成功计算
    try testing.expect(!result[max_period].isNaN());
}
```

---

## ⚡ 性能测试

### Benchmark 测试

```zig
// benchmarks/indicator_benchmark.zig
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

    std.debug.print("SMA(20) calculation (1000 candles): {d:.2} μs\n", .{elapsed_us});

    // 目标: < 500μs
    try std.testing.expect(elapsed_us < 500.0);
}

test "Benchmark: EMA calculation (1000 candles)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const candles = try generateRandomCandles(allocator, 1000);
    defer allocator.free(candles);

    const ema = EMA.init(allocator, 12);

    var timer = try Timer.start();
    const start = timer.read();

    const result = try ema.calculate(candles);
    defer allocator.free(result);

    const end = timer.read();
    const elapsed_ns = end - start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;

    std.debug.print("EMA(12) calculation (1000 candles): {d:.2} μs\n", .{elapsed_us});

    // 目标: < 400μs
    try std.testing.expect(elapsed_us < 400.0);
}

test "Benchmark: RSI calculation (1000 candles)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const candles = try generateRandomCandles(allocator, 1000);
    defer allocator.free(candles);

    const rsi = RSI.init(allocator, 14);

    var timer = try Timer.start();
    const start = timer.read();

    const result = try rsi.calculate(candles);
    defer allocator.free(result);

    const end = timer.read();
    const elapsed_ns = end - start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;

    std.debug.print("RSI(14) calculation (1000 candles): {d:.2} μs\n", .{elapsed_us});

    // 目标: < 600μs
    try std.testing.expect(elapsed_us < 600.0);
}

test "Benchmark: MACD calculation (1000 candles)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const candles = try generateRandomCandles(allocator, 1000);
    defer allocator.free(candles);

    const macd = MACD.init(allocator, 12, 26, 9);

    var timer = try Timer.start();
    const start = timer.read();

    const result = try macd.calculate(candles);
    defer {
        allocator.free(result.macd_line);
        allocator.free(result.signal_line);
        allocator.free(result.histogram);
    }

    const end = timer.read();
    const elapsed_ns = end - start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;

    std.debug.print("MACD(12,26,9) calculation (1000 candles): {d:.2} μs\n", .{elapsed_us});

    // 目标: < 800μs
    try std.testing.expect(elapsed_us < 800.0);
}

test "Benchmark: Bollinger Bands calculation (1000 candles)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const candles = try generateRandomCandles(allocator, 1000);
    defer allocator.free(candles);

    const bb = BollingerBands.init(allocator, 20, 2.0);

    var timer = try Timer.start();
    const start = timer.read();

    const result = try bb.calculate(candles);
    defer {
        allocator.free(result.upper);
        allocator.free(result.middle);
        allocator.free(result.lower);
    }

    const end = timer.read();
    const elapsed_ns = end - start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;

    std.debug.print("BollingerBands(20,2.0) calculation (1000 candles): {d:.2} μs\n", .{elapsed_us});

    // 目标: < 700μs
    try std.testing.expect(elapsed_us < 700.0);
}

test "Benchmark: memory allocation overhead" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const candles = try generateRandomCandles(allocator, 1000);
    defer allocator.free(candles);

    // 测试多次计算的内存分配开销
    const iterations = 100;
    var timer = try Timer.start();
    const start = timer.read();

    for (0..iterations) |_| {
        const sma = SMA.init(allocator, 20);
        const result = try sma.calculate(candles);
        allocator.free(result);
    }

    const end = timer.read();
    const elapsed_ns = end - start;
    const avg_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0 / @as(f64, @floatFromInt(iterations));

    std.debug.print("Average SMA calculation time ({} iterations): {d:.2} μs\n", .{ iterations, avg_us });

    // 平均时间应该仍然 < 500μs
    try std.testing.expect(avg_us < 500.0);
}

// 辅助函数: 生成随机蜡烛数据
fn generateRandomCandles(allocator: std.mem.Allocator, count: usize) ![]Candle {
    var candles = try allocator.alloc(Candle, count);
    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();

    var price: f64 = 100.0;
    for (0..count) |i| {
        // 随机价格变动 -5% ~ +5%
        price = price * (1.0 + (random.float(f64) - 0.5) * 0.1);

        candles[i] = .{
            .open = try Decimal.fromFloat(price * 0.99),
            .high = try Decimal.fromFloat(price * 1.01),
            .low = try Decimal.fromFloat(price * 0.98),
            .close = try Decimal.fromFloat(price),
            .volume = try Decimal.fromInt(1000 + random.intRangeAtMost(i64, 0, 5000)),
            .timestamp = @intCast(i * 900), // 15分钟间隔
        };
    }

    return candles;
}
```

---

## 📈 测试覆盖率

### 目标覆盖率

- **核心指标 (SMA, EMA, RSI, MACD, BB)**: 100%
- **边界情况处理**: 100%
- **错误处理**: 100%
- **辅助函数**: > 95%
- **性能基准**: 100%

### 覆盖率分类

#### 功能覆盖

- ✅ 正常计算流程
- ✅ 参数验证
- ✅ 数据不足处理
- ✅ NaN 值处理
- ✅ 内存分配/释放

#### 边界覆盖

- ✅ 空数组
- ✅ 单元素数组
- ✅ 极大/极小值
- ✅ 零值
- ✅ 负值
- ✅ period = 1
- ✅ period > data.len

#### 错误覆盖

- ✅ InvalidParameter
- ✅ InsufficientData
- ✅ InvalidInput
- ✅ OutOfMemory
- ✅ DivisionByZero (隐式)

### 运行测试

```bash
# 运行所有指标测试
zig build test-indicators --summary all

# 运行特定指标测试
zig build test-sma
zig build test-ema
zig build test-rsi
zig build test-macd
zig build test-bollinger

# 运行准确性测试 (需要 TA-Lib 参考数据)
zig build test-indicators-accuracy

# 运行边界测试
zig build test-indicators-edge

# 运行性能测试
zig build bench-indicators

# 生成覆盖率报告
zig build test-indicators --summary all --test-coverage
```

### 测试报告

```
预期输出:

================================================================================
Technical Indicators Library Tests
================================================================================
Unit Tests:
  ✅ SMA                          12/12 passed
  ✅ EMA                          10/10 passed
  ✅ RSI                          15/15 passed
  ✅ MACD                         12/12 passed
  ✅ Bollinger Bands              10/10 passed
  ✅ IIndicator Interface          5/5 passed

Accuracy Tests (vs TA-Lib):
  ✅ SMA accuracy                  1/1 passed   (max error: 0.001%)
  ✅ EMA accuracy                  1/1 passed   (max error: 0.002%)
  ✅ RSI accuracy                  1/1 passed   (max error: 0.3)
  ✅ MACD accuracy                 1/1 passed   (max error: 0.05%)
  ✅ BB accuracy                   1/1 passed   (max error: 0.01%)

Edge Cases:
  ✅ Empty/insufficient data      10/10 passed
  ✅ Extreme values                8/8 passed
  ✅ Invalid parameters            6/6 passed
  ✅ Special values (NaN, 0)       7/7 passed

Performance Tests:
  ✅ SMA (1000 candles)            287 μs       ✅ (target: < 500μs)
  ✅ EMA (1000 candles)            231 μs       ✅ (target: < 400μs)
  ✅ RSI (1000 candles)            412 μs       ✅ (target: < 600μs)
  ✅ MACD (1000 candles)           623 μs       ✅ (target: < 800μs)
  ✅ BB (1000 candles)             534 μs       ✅ (target: < 700μs)

Total: 97/97 tests passed
Memory: No leaks detected
Coverage: 98.7%
================================================================================
```

---

## 🧩 测试数据管理

### TA-Lib 参考数据格式

```json
// test_data/talib_sma_20.json
{
  "indicator": "SMA",
  "parameters": {
    "period": 20
  },
  "input": {
    "prices": [44.34, 44.09, 44.15, /* ... 更多价格 */]
  },
  "expected_output": [null, null, /* ... */, 44.22, 44.18, /* ... */]
}
```

### 测试数据生成器

```zig
// tests/data/generator.zig
pub fn generateTALibTestData(
    allocator: std.mem.Allocator,
    indicator: []const u8,
    params: anytype,
) !TestData {
    // 调用 Python TA-Lib 生成参考数据
    // 或从预先生成的 JSON 文件加载
    // ...
}
```

---

## 📝 测试最佳实践

1. **AAA 模式**: Arrange-Act-Assert
   - Arrange: 准备测试数据
   - Act: 执行指标计算
   - Assert: 验证结果

2. **独立性**: 每个测试独立运行，不依赖其他测试

3. **可重复**: 使用固定种子的随机数生成器

4. **清晰命名**: 测试名称清晰描述测试内容
   - `test "SMA: basic calculation"` ✅
   - `test "test1"` ❌

5. **边界优先**: 优先测试边界条件和错误情况

6. **内存检查**: 使用 GeneralPurposeAllocator 检测内存泄漏

7. **精度控制**: 浮点比较使用 `expectApproxEqAbs`

8. **性能监控**: 定期运行 benchmark 确保性能不降级

9. **TA-Lib 对齐**: 与 TA-Lib 结果对比验证准确性

10. **文档化**: 复杂测试用例添加注释说明

---

## 🐛 已知问题

测试过程中发现的问题会记录到 [bugs.md](./bugs.md)。

---

**版本**: v0.3.0
**状态**: 设计阶段
**更新时间**: 2025-12-25
