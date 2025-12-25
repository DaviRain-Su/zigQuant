# Technical Indicators Library 实现细节

**版本**: v0.3.0
**更新时间**: 2025-12-25

---

## 📋 目录

1. [文件组织](#文件组织)
2. [算法实现](#算法实现)
3. [优化技术](#优化技术)
4. [内存管理](#内存管理)
5. [性能考量](#性能考量)
6. [IndicatorManager 缓存策略](#indicatormanager-缓存策略)
7. [测试和验证](#测试和验证)

---

## 📂 文件组织

### 目录结构

```
src/strategy/indicators/
├── interface.zig       # IIndicator 接口定义
├── manager.zig         # IndicatorManager 缓存管理
├── utils.zig           # 公共工具函数
│
├── sma.zig             # Simple Moving Average
├── ema.zig             # Exponential Moving Average
├── rsi.zig             # Relative Strength Index
├── macd.zig            # MACD
└── bollinger.zig       # Bollinger Bands
```

### IIndicator 接口

```zig
// src/strategy/indicators/interface.zig
const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Candle = @import("../types.zig").Candle;

/// 通用指标接口
pub const IIndicator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// 计算指标值
        calculate: *const fn (*anyopaque, []const Candle) anyerror![]Decimal,
        /// 获取预热周期（需要多少蜡烛才能开始计算）
        warmupPeriod: *const fn (*anyopaque) u32,
        /// 释放资源
        deinit: *const fn (*anyopaque) void,
    };

    pub fn calculate(self: IIndicator, candles: []const Candle) ![]Decimal {
        return self.vtable.calculate(self.ptr, candles);
    }

    pub fn warmupPeriod(self: IIndicator) u32 {
        return self.vtable.warmupPeriod(self.ptr);
    }

    pub fn deinit(self: IIndicator) void {
        self.vtable.deinit(self.ptr);
    }
};

/// 指标计算结果
pub const IndicatorResult = struct {
    values: []Decimal,
    valid_from: usize,  // 从哪个索引开始有效（前面为 NaN）
};
```

### 工具函数

```zig
// src/strategy/indicators/utils.zig
const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Candle = @import("../types.zig").Candle;

/// 计算标准差
pub fn standardDeviation(
    allocator: std.mem.Allocator,
    values: []const Decimal,
    period: u32,
) ![]Decimal {
    var result = try allocator.alloc(Decimal, values.len);

    for (period..values.len) |i| {
        // 1. 计算均值
        var sum = try Decimal.fromInt(0);
        for (i - period + 1..i + 1) |j| {
            sum = try sum.add(values[j]);
        }
        const mean = try sum.div(try Decimal.fromInt(period));

        // 2. 计算方差
        var variance_sum = try Decimal.fromInt(0);
        for (i - period + 1..i + 1) |j| {
            const diff = try values[j].sub(mean);
            const squared = try diff.mul(diff);
            variance_sum = try variance_sum.add(squared);
        }
        const variance = try variance_sum.div(try Decimal.fromInt(period));

        // 3. 计算标准差
        result[i] = try variance.sqrt();
    }

    // 前 period-1 个值为 NaN
    for (0..period) |i| {
        result[i] = Decimal.NaN;
    }

    return result;
}

/// 计算平均值
pub fn average(values: []const Decimal) !Decimal {
    var sum = try Decimal.fromInt(0);
    for (values) |value| {
        sum = try sum.add(value);
    }
    return try sum.div(try Decimal.fromInt(values.len));
}

/// 提取收盘价
pub fn extractCloses(
    allocator: std.mem.Allocator,
    candles: []const Candle,
) ![]Decimal {
    var closes = try allocator.alloc(Decimal, candles.len);
    for (candles, 0..) |candle, i| {
        closes[i] = candle.close;
    }
    return closes;
}

/// 填充 NaN 值
pub fn fillNaN(values: []Decimal, start: usize) void {
    for (0..start) |i| {
        values[i] = Decimal.NaN;
    }
}
```

---

## 🧮 算法实现

### SMA (Simple Moving Average)

#### 算法原理

```
SMA(n) = (P₁ + P₂ + ... + Pₙ) / n

其中:
- n: 周期
- P: 价格（通常是收盘价）
```

#### 实现代码

```zig
// src/strategy/indicators/sma.zig
const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Candle = @import("../types.zig").Candle;
const utils = @import("utils.zig");

pub const SMA = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub fn init(allocator: std.mem.Allocator, period: u32) SMA {
        return .{
            .allocator = allocator,
            .period = period,
        };
    }

    /// 计算 SMA
    pub fn calculate(self: SMA, candles: []const Candle) ![]Decimal {
        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // 方法 1: 简单累加（O(n×m) 复杂度）
        // for (self.period..candles.len) |i| {
        //     var sum = try Decimal.fromInt(0);
        //     for (i - self.period + 1..i + 1) |j| {
        //         sum = try sum.add(candles[j].close);
        //     }
        //     result[i] = try sum.div(try Decimal.fromInt(self.period));
        // }

        // 方法 2: 滑动窗口（O(n) 复杂度，优化版）
        // 首先计算第一个 SMA
        var sum = try Decimal.fromInt(0);
        for (0..self.period) |i| {
            sum = try sum.add(candles[i].close);
        }
        result[self.period - 1] = try sum.div(try Decimal.fromInt(self.period));

        // 后续 SMA：移除最旧值，添加最新值
        for (self.period..candles.len) |i| {
            sum = try sum.sub(candles[i - self.period].close);
            sum = try sum.add(candles[i].close);
            result[i] = try sum.div(try Decimal.fromInt(self.period));
        }

        // 前 period-1 个值为 NaN
        utils.fillNaN(result, self.period - 1);

        return result;
    }

    pub fn warmupPeriod(self: SMA) u32 {
        return self.period;
    }
};
```

**时间复杂度**: O(n)（滑动窗口优化）
**空间复杂度**: O(n)（结果数组）

---

### EMA (Exponential Moving Average)

#### 算法原理

```
EMA(t) = α × P(t) + (1 - α) × EMA(t-1)

其中:
- α = 2 / (period + 1)  (平滑系数)
- P(t): 当前价格
- EMA(t-1): 上一个 EMA 值
- 初始 EMA(0) = SMA(period)
```

#### 实现代码

```zig
// src/strategy/indicators/ema.zig
const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Candle = @import("../types.zig").Candle;
const utils = @import("utils.zig");

pub const EMA = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub fn init(allocator: std.mem.Allocator, period: u32) EMA {
        return .{
            .allocator = allocator,
            .period = period,
        };
    }

    /// 计算 EMA
    pub fn calculate(self: EMA, candles: []const Candle) ![]Decimal {
        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // 计算平滑系数 α = 2 / (period + 1)
        const alpha = try Decimal.fromInt(2).div(
            try Decimal.fromInt(self.period + 1)
        );
        const one_minus_alpha = try Decimal.fromInt(1).sub(alpha);

        // 初始 EMA = 前 period 个价格的 SMA
        var sum = try Decimal.fromInt(0);
        for (0..self.period) |i| {
            sum = try sum.add(candles[i].close);
        }
        var ema = try sum.div(try Decimal.fromInt(self.period));
        result[self.period - 1] = ema;

        // 递推计算后续 EMA
        // EMA(t) = α × Price(t) + (1 - α) × EMA(t-1)
        for (self.period..candles.len) |i| {
            const price = candles[i].close;
            const term1 = try alpha.mul(price);
            const term2 = try one_minus_alpha.mul(ema);
            ema = try term1.add(term2);
            result[i] = ema;
        }

        // 前 period-1 个值为 NaN
        utils.fillNaN(result, self.period - 1);

        return result;
    }

    pub fn warmupPeriod(self: EMA) u32 {
        return self.period;
    }

    /// 计算多个 EMA（用于 MACD）
    pub fn calculateMultiple(
        allocator: std.mem.Allocator,
        candles: []const Candle,
        periods: []const u32,
    ) ![][]Decimal {
        var results = try allocator.alloc([]Decimal, periods.len);
        errdefer {
            for (results[0..periods.len]) |result| {
                allocator.free(result);
            }
            allocator.free(results);
        }

        for (periods, 0..) |period, i| {
            const ema = EMA.init(allocator, period);
            results[i] = try ema.calculate(candles);
        }

        return results;
    }
};
```

**时间复杂度**: O(n)（单次遍历）
**空间复杂度**: O(n)

---

### RSI (Relative Strength Index)

#### 算法原理

```
1. 计算涨跌幅:
   Up(i) = max(Price(i) - Price(i-1), 0)
   Down(i) = max(Price(i-1) - Price(i), 0)

2. 计算平均涨跌幅 (使用 Wilder's Smoothing):
   Avg Up = EMA(Up, period)
   Avg Down = EMA(Down, period)

3. 计算 RS 和 RSI:
   RS = Avg Up / Avg Down
   RSI = 100 - (100 / (1 + RS))
```

#### 实现代码

```zig
// src/strategy/indicators/rsi.zig
const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Candle = @import("../types.zig").Candle;
const utils = @import("utils.zig");

pub const RSI = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub fn init(allocator: std.mem.Allocator, period: u32) RSI {
        return .{
            .allocator = allocator,
            .period = period,
        };
    }

    /// 计算 RSI
    pub fn calculate(self: RSI, candles: []const Candle) ![]Decimal {
        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // 临时数组：涨幅和跌幅
        var gains = try self.allocator.alloc(Decimal, candles.len);
        defer self.allocator.free(gains);
        var losses = try self.allocator.alloc(Decimal, candles.len);
        defer self.allocator.free(losses);

        // 1. 计算涨跌幅
        gains[0] = try Decimal.fromInt(0);
        losses[0] = try Decimal.fromInt(0);

        for (1..candles.len) |i| {
            const change = try candles[i].close.sub(candles[i - 1].close);
            if (change.isPositive()) {
                gains[i] = change;
                losses[i] = try Decimal.fromInt(0);
            } else {
                gains[i] = try Decimal.fromInt(0);
                losses[i] = try change.abs();
            }
        }

        // 2. 计算初始平均涨跌幅 (SMA)
        var avg_gain = try Decimal.fromInt(0);
        var avg_loss = try Decimal.fromInt(0);
        for (1..self.period + 1) |i| {
            avg_gain = try avg_gain.add(gains[i]);
            avg_loss = try avg_loss.add(losses[i]);
        }
        avg_gain = try avg_gain.div(try Decimal.fromInt(self.period));
        avg_loss = try avg_loss.div(try Decimal.fromInt(self.period));

        // 3. 计算第一个 RSI
        const rs_first = if (avg_loss.isZero())
            try Decimal.fromInt(100)  // 避免除以零
        else
            try avg_gain.div(avg_loss);
        const rsi_first = try Decimal.fromInt(100).sub(
            try Decimal.fromInt(100).div(
                try Decimal.fromInt(1).add(rs_first)
            )
        );
        result[self.period] = rsi_first;

        // 4. 使用 Wilder's Smoothing 计算后续 RSI
        // Avg Gain(t) = (Avg Gain(t-1) × (period-1) + Gain(t)) / period
        // Avg Loss(t) = (Avg Loss(t-1) × (period-1) + Loss(t)) / period
        const period_decimal = try Decimal.fromInt(self.period);
        const period_minus_1 = try Decimal.fromInt(self.period - 1);

        for (self.period + 1..candles.len) |i| {
            // 更新平均涨跌幅
            const gain_term = try avg_gain.mul(period_minus_1).add(gains[i]);
            avg_gain = try gain_term.div(period_decimal);

            const loss_term = try avg_loss.mul(period_minus_1).add(losses[i]);
            avg_loss = try loss_term.div(period_decimal);

            // 计算 RSI
            if (avg_loss.isZero()) {
                result[i] = try Decimal.fromInt(100);
            } else {
                const rs = try avg_gain.div(avg_loss);
                result[i] = try Decimal.fromInt(100).sub(
                    try Decimal.fromInt(100).div(
                        try Decimal.fromInt(1).add(rs)
                    )
                );
            }
        }

        // 前 period 个值为 NaN
        utils.fillNaN(result, self.period);

        return result;
    }

    pub fn warmupPeriod(self: RSI) u32 {
        return self.period + 1;  // 需要额外一个蜡烛计算涨跌幅
    }
};
```

**时间复杂度**: O(n)
**空间复杂度**: O(n)（需要中间数组存储涨跌幅）

---

### MACD

#### 算法原理

```
MACD Line = EMA(12) - EMA(26)
Signal Line = EMA(MACD Line, 9)
Histogram = MACD Line - Signal Line
```

#### 实现代码

```zig
// src/strategy/indicators/macd.zig
const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Candle = @import("../types.zig").Candle;
const EMA = @import("ema.zig").EMA;
const utils = @import("utils.zig");

pub const MACDResult = struct {
    macd_line: []Decimal,
    signal_line: []Decimal,
    histogram: []Decimal,

    pub fn deinit(self: MACDResult, allocator: std.mem.Allocator) void {
        allocator.free(self.macd_line);
        allocator.free(self.signal_line);
        allocator.free(self.histogram);
    }
};

pub const MACD = struct {
    allocator: std.mem.Allocator,
    fast_period: u32,   // 默认 12
    slow_period: u32,   // 默认 26
    signal_period: u32, // 默认 9

    pub fn init(
        allocator: std.mem.Allocator,
        fast_period: u32,
        slow_period: u32,
        signal_period: u32,
    ) MACD {
        return .{
            .allocator = allocator,
            .fast_period = fast_period,
            .slow_period = slow_period,
            .signal_period = signal_period,
        };
    }

    /// 计算 MACD
    pub fn calculate(self: MACD, candles: []const Candle) !MACDResult {
        // 1. 计算快速和慢速 EMA
        const fast_ema_calc = EMA.init(self.allocator, self.fast_period);
        const fast_ema = try fast_ema_calc.calculate(candles);
        defer self.allocator.free(fast_ema);

        const slow_ema_calc = EMA.init(self.allocator, self.slow_period);
        const slow_ema = try slow_ema_calc.calculate(candles);
        defer self.allocator.free(slow_ema);

        // 2. 计算 MACD Line = Fast EMA - Slow EMA
        var macd_line = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(macd_line);

        for (0..candles.len) |i| {
            if (fast_ema[i].isNaN() or slow_ema[i].isNaN()) {
                macd_line[i] = Decimal.NaN;
            } else {
                macd_line[i] = try fast_ema[i].sub(slow_ema[i]);
            }
        }

        // 3. 计算 Signal Line = EMA(MACD Line, signal_period)
        // 注意: 需要将 MACD Line 转换为 Candle 格式
        var macd_candles = try self.allocator.alloc(Candle, candles.len);
        defer self.allocator.free(macd_candles);

        for (0..candles.len) |i| {
            macd_candles[i] = Candle{
                .timestamp = candles[i].timestamp,
                .open = macd_line[i],
                .high = macd_line[i],
                .low = macd_line[i],
                .close = macd_line[i],
                .volume = try Decimal.fromInt(0),
            };
        }

        const signal_ema_calc = EMA.init(self.allocator, self.signal_period);
        const signal_line = try signal_ema_calc.calculate(macd_candles);
        errdefer self.allocator.free(signal_line);

        // 4. 计算 Histogram = MACD Line - Signal Line
        var histogram = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(histogram);

        for (0..candles.len) |i| {
            if (macd_line[i].isNaN() or signal_line[i].isNaN()) {
                histogram[i] = Decimal.NaN;
            } else {
                histogram[i] = try macd_line[i].sub(signal_line[i]);
            }
        }

        return MACDResult{
            .macd_line = macd_line,
            .signal_line = signal_line,
            .histogram = histogram,
        };
    }

    pub fn warmupPeriod(self: MACD) u32 {
        return self.slow_period + self.signal_period;
    }
};
```

**时间复杂度**: O(n)（三次 EMA 计算）
**空间复杂度**: O(n)（三个结果数组）

---

### Bollinger Bands

#### 算法原理

```
Middle Band = SMA(n)
Upper Band = Middle + (k × σ)
Lower Band = Middle - (k × σ)

其中:
- n: 周期（默认 20）
- k: 标准差倍数（默认 2）
- σ: 标准差
```

#### 实现代码

```zig
// src/strategy/indicators/bollinger.zig
const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Candle = @import("../types.zig").Candle;
const SMA = @import("sma.zig").SMA;
const utils = @import("utils.zig");

pub const BollingerBandsResult = struct {
    upper: []Decimal,
    middle: []Decimal,
    lower: []Decimal,

    pub fn deinit(self: BollingerBandsResult, allocator: std.mem.Allocator) void {
        allocator.free(self.upper);
        allocator.free(self.middle);
        allocator.free(self.lower);
    }
};

pub const BollingerBands = struct {
    allocator: std.mem.Allocator,
    period: u32,      // 默认 20
    std_dev: f64,     // 默认 2.0

    pub fn init(
        allocator: std.mem.Allocator,
        period: u32,
        std_dev: f64,
    ) BollingerBands {
        return .{
            .allocator = allocator,
            .period = period,
            .std_dev = std_dev,
        };
    }

    /// 计算布林带
    pub fn calculate(self: BollingerBands, candles: []const Candle) !BollingerBandsResult {
        // 1. 计算中轨 (SMA)
        const sma_calc = SMA.init(self.allocator, self.period);
        const middle = try sma_calc.calculate(candles);
        errdefer self.allocator.free(middle);

        // 2. 提取收盘价
        const closes = try utils.extractCloses(self.allocator, candles);
        defer self.allocator.free(closes);

        // 3. 计算标准差
        const std_devs = try utils.standardDeviation(
            self.allocator,
            closes,
            self.period,
        );
        defer self.allocator.free(std_devs);

        // 4. 计算上下轨
        var upper = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(upper);

        var lower = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(lower);

        const k = try Decimal.fromFloat(self.std_dev);

        for (0..candles.len) |i| {
            if (middle[i].isNaN() or std_devs[i].isNaN()) {
                upper[i] = Decimal.NaN;
                lower[i] = Decimal.NaN;
            } else {
                // Upper = Middle + k × σ
                const offset = try k.mul(std_devs[i]);
                upper[i] = try middle[i].add(offset);
                lower[i] = try middle[i].sub(offset);
            }
        }

        return BollingerBandsResult{
            .upper = upper,
            .middle = middle,
            .lower = lower,
        };
    }

    pub fn warmupPeriod(self: BollingerBands) u32 {
        return self.period;
    }

    /// 计算带宽 (Bandwidth)
    /// Bandwidth = (Upper - Lower) / Middle
    pub fn calculateBandwidth(
        self: BollingerBands,
        result: BollingerBandsResult,
    ) ![]Decimal {
        var bandwidth = try self.allocator.alloc(Decimal, result.upper.len);
        errdefer self.allocator.free(bandwidth);

        for (0..result.upper.len) |i| {
            if (result.upper[i].isNaN() or
                result.lower[i].isNaN() or
                result.middle[i].isNaN() or
                result.middle[i].isZero())
            {
                bandwidth[i] = Decimal.NaN;
            } else {
                const range = try result.upper[i].sub(result.lower[i]);
                bandwidth[i] = try range.div(result.middle[i]);
            }
        }

        return bandwidth;
    }

    /// 计算 %B 指标
    /// %B = (Price - Lower) / (Upper - Lower)
    pub fn calculatePercentB(
        self: BollingerBands,
        candles: []const Candle,
        result: BollingerBandsResult,
    ) ![]Decimal {
        var percent_b = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(percent_b);

        for (0..candles.len) |i| {
            if (result.upper[i].isNaN() or result.lower[i].isNaN()) {
                percent_b[i] = Decimal.NaN;
            } else {
                const numerator = try candles[i].close.sub(result.lower[i]);
                const denominator = try result.upper[i].sub(result.lower[i]);

                if (denominator.isZero()) {
                    percent_b[i] = try Decimal.fromFloat(0.5);
                } else {
                    percent_b[i] = try numerator.div(denominator);
                }
            }
        }

        return percent_b;
    }
};
```

**时间复杂度**: O(n)
**空间复杂度**: O(n)（三个结果数组）

---

## ⚡ 优化技术

### 1. SIMD 向量化

#### 概念

使用 SIMD (Single Instruction Multiple Data) 指令可以并行处理多个数据，显著提升性能。

#### 潜在实现

```zig
// 未来优化：使用 @Vector 进行 SIMD 计算
pub fn calculateSIMD(self: SMA, candles: []const Candle) ![]Decimal {
    const Vec4 = @Vector(4, f64);

    var result = try self.allocator.alloc(Decimal, candles.len);

    // 将 Decimal 转换为 f64 向量
    const vec_len = candles.len / 4 * 4;  // 对齐到 4 的倍数

    var i: usize = self.period;
    while (i < vec_len) : (i += 4) {
        // 加载 4 个价格
        const prices: Vec4 = .{
            candles[i].close.toFloat(),
            candles[i+1].close.toFloat(),
            candles[i+2].close.toFloat(),
            candles[i+3].close.toFloat(),
        };

        // 并行计算 4 个 SMA
        // ... SIMD 计算逻辑

        // 存储结果
        result[i] = try Decimal.fromFloat(prices[0]);
        result[i+1] = try Decimal.fromFloat(prices[1]);
        result[i+2] = try Decimal.fromFloat(prices[2]);
        result[i+3] = try Decimal.fromFloat(prices[3]);
    }

    // 处理剩余的元素
    while (i < candles.len) : (i += 1) {
        // 标量计算
    }

    return result;
}
```

#### 性能提升

- **理论加速**: 2-4x（取决于 CPU 和数据对齐）
- **适用指标**: SMA, EMA（涉及大量算术运算）
- **限制**: Decimal 类型需要转换为浮点数

### 2. 缓存优化

#### CPU 缓存友好

```zig
// 改进前：跨步访问（缓存不友好）
for (0..result.len) |i| {
    result[i] = try calculate(candles[i], candles[i+period]);
}

// 改进后：连续访问（缓存友好）
var sum = try Decimal.fromInt(0);
for (0..period) |i| {
    sum = try sum.add(candles[i].close);  // 连续访问
}
```

#### 预分配内存

```zig
// 改进前：多次分配
pub fn calculate(self: RSI, candles: []const Candle) ![]Decimal {
    var gains = std.ArrayList(Decimal).init(self.allocator);
    var losses = std.ArrayList(Decimal).init(self.allocator);
    // ... 逐个添加，可能多次扩容
}

// 改进后：预分配
pub fn calculate(self: RSI, candles: []const Candle) ![]Decimal {
    var gains = try self.allocator.alloc(Decimal, candles.len);  // 一次分配
    var losses = try self.allocator.alloc(Decimal, candles.len);
    // ... 直接赋值
}
```

### 3. 计算复用

#### 避免重复计算

```zig
// 改进前：重复计算 EMA
const fast_ema = try EMA.calculate(candles, 12);
const slow_ema = try EMA.calculate(candles, 26);  // 重复遍历

// 改进后：批量计算
const emas = try EMA.calculateMultiple(candles, &[_]u32{12, 26});
```

#### 中间结果复用

```zig
// Bollinger Bands 复用 SMA
pub fn calculate(self: BollingerBands, candles: []const Candle) !BollingerBandsResult {
    // 计算 SMA 作为中轨
    const middle = try SMA.calculate(candles, self.period);

    // 直接使用 middle，不需要重新计算均值
    const std_dev = try calculateStdDevFromMean(candles, middle, self.period);

    // ...
}
```

### 4. 滑动窗口算法

SMA 的优化是典型例子：

```zig
// O(n×m) → O(n)
// 移除: sum -= old_value
// 添加: sum += new_value
for (self.period..candles.len) |i| {
    sum = try sum.sub(candles[i - self.period].close);
    sum = try sum.add(candles[i].close);
    result[i] = try sum.div(period_decimal);
}
```

### 5. 早期终止

```zig
pub fn calculate(self: RSI, candles: []const Candle) ![]Decimal {
    // 数据不足，直接返回全 NaN
    if (candles.len < self.warmupPeriod()) {
        var result = try self.allocator.alloc(Decimal, candles.len);
        utils.fillNaN(result, candles.len);
        return result;
    }

    // ... 正常计算
}
```

---

## 💾 内存管理

### 内存所有权模型

```
┌─────────────────────────────────────────┐
│          Candles (Backtest Engine)      │
│  (拥有蜡烛数据和指标结果)                 │
├─────────────────────────────────────────┤
│                                          │
│  data: []Candle           (owned)       │
│  indicators: HashMap      (owned)       │
│      │                                   │
│      ├─> "sma_20": []Decimal (owned)    │
│      ├─> "ema_12": []Decimal (owned)    │
│      └─> "rsi": []Decimal    (owned)    │
│                                          │
└─────────────────────────────────────────┘
         ▲
         │ 临时借用
         │
┌─────────────────────────┐
│   Indicator (SMA/EMA)   │
│  (不拥有数据)            │
├─────────────────────────┤
│ - allocator             │
│ - period                │
│                          │
│ calculate() {            │
│   result = alloc()       │
│   ... 计算 ...           │
│   return result  ← 转移所有权
│ }                        │
└─────────────────────────┘
```

### 内存分配策略

#### 1. 指标计算器（无状态）

```zig
pub const SMA = struct {
    allocator: std.mem.Allocator,  // 仅存储 allocator
    period: u32,                   // 配置参数

    // 不持有任何动态分配的内存
    // 计算时临时分配，结果转移给调用者
};
```

#### 2. 结果数组（转移所有权）

```zig
pub fn calculate(self: SMA, candles: []const Candle) ![]Decimal {
    // 分配结果数组
    var result = try self.allocator.alloc(Decimal, candles.len);
    errdefer self.allocator.free(result);  // 出错时自动释放

    // ... 计算 ...

    return result;  // 所有权转移给调用者
}
```

#### 3. 中间数组（临时）

```zig
pub fn calculate(self: RSI, candles: []const Candle) ![]Decimal {
    var result = try self.allocator.alloc(Decimal, candles.len);
    errdefer self.allocator.free(result);

    // 临时数组
    var gains = try self.allocator.alloc(Decimal, candles.len);
    defer self.allocator.free(gains);  // 函数结束时自动释放

    var losses = try self.allocator.alloc(Decimal, candles.len);
    defer self.allocator.free(losses);

    // ... 计算 ...

    return result;  // 只返回结果，中间数组已释放
}
```

#### 4. 复合结果（调用者负责释放）

```zig
pub const MACDResult = struct {
    macd_line: []Decimal,
    signal_line: []Decimal,
    histogram: []Decimal,

    pub fn deinit(self: MACDResult, allocator: std.mem.Allocator) void {
        allocator.free(self.macd_line);
        allocator.free(self.signal_line);
        allocator.free(self.histogram);
    }
};

// 使用示例
const macd_result = try macd.calculate(candles);
defer macd_result.deinit(allocator);  // 调用者负责释放
```

### 内存泄漏检测

```zig
test "indicator memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try std.testing.expect(leaked == .ok);  // 确保无泄漏
    }
    const allocator = gpa.allocator();

    const candles = try generateTestCandles(allocator, 100);
    defer allocator.free(candles);

    // 测试 SMA
    {
        const sma = SMA.init(allocator, 20);
        const result = try sma.calculate(candles);
        defer allocator.free(result);  // 必须释放
    }

    // 测试 MACD
    {
        const macd = MACD.init(allocator, 12, 26, 9);
        const result = try macd.calculate(candles);
        defer result.deinit(allocator);  // 必须释放
    }
}
```

---

## 🚀 性能考量

### 性能基准

#### 测试环境

- **CPU**: AMD Ryzen / Intel Core
- **编译**: Release mode (`-O ReleaseFast`)
- **数据**: 1000 蜡烛

#### 目标性能

| 指标 | 目标时间 | 内存占用 |
|------|----------|----------|
| SMA | < 500μs | 8KB |
| EMA | < 400μs | 8KB |
| RSI | < 600μs | 24KB |
| MACD | < 800μs | 32KB |
| Bollinger Bands | < 700μs | 24KB |

### 性能瓶颈分析

#### 1. Decimal 运算开销

```zig
// Decimal 操作比浮点慢 10-100x
const a = try Decimal.fromInt(10);
const b = try Decimal.fromInt(20);
const c = try a.add(b);  // 涉及字符串解析、大数运算

// 优化: 批量转换
const a_f64 = a.toFloat();
const b_f64 = b.toFloat();
const c_f64 = a_f64 + b_f64;  // 快速浮点运算
const c = try Decimal.fromFloat(c_f64);
```

#### 2. 内存分配

```zig
// 慢: 频繁小分配
for (0..candles.len) |i| {
    var value = try allocator.create(Decimal);  // 每次分配
    defer allocator.destroy(value);
}

// 快: 批量分配
var values = try allocator.alloc(Decimal, candles.len);  // 一次分配
defer allocator.free(values);
```

#### 3. 分支预测

```zig
// 改进前: 不可预测的分支
for (values) |value| {
    if (value.isNaN()) {  // 分支
        result = Decimal.NaN;
    } else {
        result = try calculate(value);
    }
}

// 改进后: 减少分支
for (period..values.len) |i| {
    result[i] = try calculate(values[i]);  // 无分支
}
// 统一填充 NaN
utils.fillNaN(result, period);
```

### 性能测试

```zig
// tests/indicators/benchmark.zig
const std = @import("std");
const Timer = std.time.Timer;
const SMA = @import("../../src/strategy/indicators/sma.zig").SMA;

test "benchmark SMA 1000 candles" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const candles = try generateTestCandles(allocator, 1000);
    defer allocator.free(candles);

    const sma = SMA.init(allocator, 20);

    // 预热
    _ = try sma.calculate(candles);

    // 测试
    var timer = try Timer.start();
    const start = timer.lap();

    const iterations = 1000;
    for (0..iterations) |_| {
        const result = try sma.calculate(candles);
        allocator.free(result);
    }

    const end = timer.read();
    const elapsed = end - start;
    const avg_ns = elapsed / iterations;
    const avg_us = avg_ns / 1000;

    std.debug.print("SMA(20) avg time: {}μs\n", .{avg_us});

    // 断言性能目标
    try std.testing.expect(avg_us < 500);  // < 500μs
}
```

---

## 📦 IndicatorManager 缓存策略

### 设计目标

- **避免重复计算**: 相同参数的指标只计算一次
- **自动失效**: 蜡烛数据变化时自动重新计算
- **参数区分**: 相同类型但不同参数的指标分别缓存

### 缓存键设计

```zig
// 缓存键格式: "indicator_type:param1:param2:..."
// 示例:
//   "sma:20"
//   "ema:12"
//   "rsi:14"
//   "macd:12:26:9"
//   "bb:20:2.0"

fn getCacheKey(
    allocator: std.mem.Allocator,
    indicator_type: []const u8,
    params: anytype,
) ![]u8 {
    var key = std.ArrayList(u8).init(allocator);
    try key.appendSlice(indicator_type);

    inline for (std.meta.fields(@TypeOf(params))) |field| {
        try key.append(':');
        const value = @field(params, field.name);
        try std.fmt.format(key.writer(), "{}", .{value});
    }

    return key.toOwnedSlice();
}
```

### 缓存实现

```zig
// src/strategy/indicators/manager.zig
const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Candle = @import("../types.zig").Candle;

pub const CachedIndicator = struct {
    values: []Decimal,
    candle_count: usize,     // 蜡烛数量
    candle_hash: u64,        // 蜡烛数据哈希（可选）
};

pub const IndicatorManager = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap(CachedIndicator),

    pub fn init(allocator: std.mem.Allocator) IndicatorManager {
        return .{
            .allocator = allocator,
            .cache = std.StringHashMap(CachedIndicator).init(allocator),
        };
    }

    pub fn deinit(self: *IndicatorManager) void {
        var it = self.cache.valueIterator();
        while (it.next()) |cached| {
            self.allocator.free(cached.values);
        }
        self.cache.deinit();
    }

    /// 获取或计算指标
    pub fn getOrCalculate(
        self: *IndicatorManager,
        key: []const u8,
        candles: []const Candle,
        calculate_fn: *const fn ([]const Candle) anyerror![]Decimal,
    ) ![]Decimal {
        // 1. 检查缓存
        if (self.cache.get(key)) |cached| {
            // 验证缓存有效性
            if (cached.candle_count == candles.len) {
                // 可选: 检查最后几个蜡烛的哈希
                if (self.isCandle DataUnchanged(candles, cached.candle_hash)) {
                    return cached.values;  // 缓存命中
                }
            }

            // 缓存失效，释放旧数据
            self.allocator.free(cached.values);
            _ = self.cache.remove(key);
        }

        // 2. 计算新值
        const values = try calculate_fn(candles);

        // 3. 存入缓存
        const candle_hash = self.hashCandleData(candles);
        try self.cache.put(key, CachedIndicator{
            .values = values,
            .candle_count = candles.len,
            .candle_hash = candle_hash,
        });

        return values;
    }

    /// 清除所有缓存
    pub fn clearCache(self: *IndicatorManager) void {
        var it = self.cache.valueIterator();
        while (it.next()) |cached| {
            self.allocator.free(cached.values);
        }
        self.cache.clearRetainingCapacity();
    }

    /// 移除特定缓存
    pub fn invalidate(self: *IndicatorManager, key: []const u8) void {
        if (self.cache.fetchRemove(key)) |entry| {
            self.allocator.free(entry.value.values);
        }
    }

    /// 计算蜡烛数据哈希（快速验证）
    fn hashCandleData(self: *IndicatorManager, candles: []const Candle) u64 {
        _ = self;

        // 简化版: 只哈希最后几个蜡烛
        const hash_count = @min(candles.len, 10);
        const start = candles.len - hash_count;

        var hasher = std.hash.Wyhash.init(0);
        for (candles[start..]) |candle| {
            const close_bytes = std.mem.asBytes(&candle.close);
            hasher.update(close_bytes);
        }

        return hasher.final();
    }

    /// 检查蜡烛数据是否未变化
    fn isCandleDataUnchanged(
        self: *IndicatorManager,
        candles: []const Candle,
        cached_hash: u64,
    ) bool {
        return self.hashCandleData(candles) == cached_hash;
    }
};
```

### 使用示例

```zig
// 在策略的 StrategyContext 中使用
pub const StrategyContext = struct {
    allocator: std.mem.Allocator,
    indicator_manager: *IndicatorManager,
    // ...
};

// 在 populateIndicators 中
fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));

    // 构造缓存键
    const sma_key = try std.fmt.allocPrint(
        self.allocator,
        "sma:{}",
        .{self.sma_period},
    );
    defer self.allocator.free(sma_key);

    // 获取或计算 SMA
    const sma_values = try self.ctx.indicator_manager.getOrCalculate(
        sma_key,
        candles.data,
        struct {
            fn calc(candles_data: []const Candle) ![]Decimal {
                const sma = SMA.init(self.allocator, self.sma_period);
                return try sma.calculate(candles_data);
            }
        }.calc,
    );

    // 添加到 Candles（不拥有，仅引用）
    try candles.addIndicatorRef("sma", sma_values);
}
```

### 缓存策略

#### 回测模式

```
1. 第一次 populateIndicators():
   - 计算所有指标
   - 存入缓存

2. 后续 populateIndicators() (如果蜡烛数据未变):
   - 直接从缓存返回
   - 零计算开销
```

#### 实时模式

```
1. 每次新蜡烛到达:
   - candles.len 变化
   - 缓存失效
   - 重新计算指标

2. 增量计算优化 (未来):
   - 检测只有最后一个蜡烛变化
   - 只重新计算受影响的部分
   - 复用之前的计算结果
```

---

## 🧪 测试和验证

### 正确性验证

#### 1. 与 TA-Lib 对比

```zig
test "SMA matches TA-Lib" {
    const talib_result = [_]f64{
        // TA-Lib 的输出
        100.5, 101.2, 102.1, ...
    };

    const sma = SMA.init(allocator, 20);
    const result = try sma.calculate(candles);
    defer allocator.free(result);

    for (result, 0..) |value, i| {
        if (!value.isNaN()) {
            const diff = @abs(value.toFloat() - talib_result[i]);
            const error_pct = diff / talib_result[i];
            try std.testing.expect(error_pct < 0.0001);  // < 0.01% 误差
        }
    }
}
```

#### 2. 手工计算验证

```zig
test "RSI calculation correctness" {
    const candles = [_]Candle{
        .{ .close = try Decimal.fromInt(100), ... },
        .{ .close = try Decimal.fromInt(102), ... },  // +2
        .{ .close = try Decimal.fromInt(101), ... },  // -1
        .{ .close = try Decimal.fromInt(103), ... },  // +2
        .{ .close = try Decimal.fromInt(105), ... },  // +2
    };

    // 手工计算:
    // Avg Gain = (2 + 0 + 2 + 2) / 4 = 1.5
    // Avg Loss = (0 + 1 + 0 + 0) / 4 = 0.25
    // RS = 1.5 / 0.25 = 6
    // RSI = 100 - (100 / (1 + 6)) = 85.71

    const rsi = RSI.init(allocator, 4);
    const result = try rsi.calculate(&candles);
    defer allocator.free(result);

    const expected = try Decimal.fromFloat(85.71);
    const actual = result[4];

    const diff = try actual.sub(expected).abs();
    try std.testing.expect(diff.lt(try Decimal.fromFloat(0.01)));
}
```

### 边界条件测试

```zig
test "SMA with insufficient data" {
    const candles = [_]Candle{
        .{ .close = try Decimal.fromInt(100), ... },
        .{ .close = try Decimal.fromInt(102), ... },
    };

    const sma = SMA.init(allocator, 20);  // period > data
    const result = try sma.calculate(&candles);
    defer allocator.free(result);

    // 所有值应该是 NaN
    for (result) |value| {
        try std.testing.expect(value.isNaN());
    }
}

test "Bollinger Bands with zero deviation" {
    const candles = try generateConstantPriceCandles(100);  // 所有价格相同

    const bb = BollingerBands.init(allocator, 20, 2.0);
    const result = try bb.calculate(candles);
    defer result.deinit(allocator);

    // 标准差为 0，上下轨应该等于中轨
    for (result.upper, result.middle, result.lower) |upper, middle, lower| {
        if (!upper.isNaN()) {
            try std.testing.expect(upper.eq(middle));
            try std.testing.expect(lower.eq(middle));
        }
    }
}
```

### 性能回归测试

```zig
test "performance regression" {
    const candles = try generateTestCandles(allocator, 1000);
    defer allocator.free(candles);

    // 记录基准性能
    const benchmarks = .{
        .{ "SMA", SMA.init(allocator, 20), 500 },
        .{ "EMA", EMA.init(allocator, 12), 400 },
        .{ "RSI", RSI.init(allocator, 14), 600 },
    };

    inline for (benchmarks) |bench| {
        const name = bench[0];
        const indicator = bench[1];
        const max_us = bench[2];

        var timer = try Timer.start();
        const start = timer.lap();

        const result = try indicator.calculate(candles);
        allocator.free(result);

        const elapsed = timer.read();
        const elapsed_us = elapsed / 1000;

        std.debug.print("{s}: {}μs (max: {}μs)\n", .{name, elapsed_us, max_us});
        try std.testing.expect(elapsed_us < max_us);
    }
}
```

---

**版本**: v0.3.0
**状态**: 设计阶段
**更新时间**: 2025-12-25
