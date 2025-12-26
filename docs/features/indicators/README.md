# Technical Indicators Library - 技术指标库

**版本**: v0.3.0
**状态**: ✅ 已完成
**层级**: Strategy Layer
**依赖**: Core (Decimal, Time), Market (Candles)

---

## 📋 目录

1. [功能概述](#功能概述)
2. [支持的指标](#支持的指标)
3. [快速开始](#快速开始)
4. [指标详解](#指标详解)
5. [性能指标](#性能指标)
6. [相关文档](#相关文档)

---

## 🎯 功能概述

Technical Indicators Library 是 zigQuant 的技术指标计算库，提供常用的技术分析指标。

### 设计目标

参考 **TA-Lib** (Technical Analysis Library) 的设计理念：

- **准确性**: 指标计算与业界标准一致
- **高性能**: 优化的算法实现
- **易用性**: 简洁的 API 设计
- **可扩展**: 支持自定义指标
- **内存安全**: Zig 的内存管理保证

### 关键特性

- **统一接口**: 所有指标实现 IIndicator 接口
- **批量计算**: 一次计算所有蜡烛的指标值
- **缓存优化**: IndicatorManager 自动缓存计算结果
- **类型安全**: 编译时类型检查
- **零拷贝**: 尽可能避免数据复制

---

## 📊 支持的指标

### v0.3.0 核心指标

| 指标 | 全称 | 类型 | 描述 |
|------|------|------|------|
| **SMA** | Simple Moving Average | 趋势 | 简单移动平均 |
| **EMA** | Exponential Moving Average | 趋势 | 指数移动平均 |
| **RSI** | Relative Strength Index | 震荡 | 相对强弱指标 |
| **MACD** | Moving Average Convergence Divergence | 趋势+震荡 | 移动平均收敛散度 |
| **BB** | Bollinger Bands | 波动 | 布林带 |

### 计划中的指标（v0.4.0+）

| 指标 | 全称 | 类型 | 描述 |
|------|------|------|------|
| **ATR** | Average True Range | 波动 | 平均真实波幅 |
| **STOCH** | Stochastic Oscillator | 震荡 | 随机振荡器 |
| **ADX** | Average Directional Index | 趋势 | 平均趋向指标 |
| **OBV** | On Balance Volume | 成交量 | 能量潮指标 |
| **SAR** | Parabolic SAR | 趋势 | 抛物线转向 |
| **VWAP** | Volume Weighted Average Price | 成交量 | 成交量加权平均价 |

---

## 🚀 快速开始

### 1. 基本使用

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

const SMA = zigQuant.SMA;
const Candle = zigQuant.Candle;
const Decimal = zigQuant.Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 准备蜡烛数据
    const candles = [_]Candle{
        .{ .close = try Decimal.fromInt(100), ... },
        .{ .close = try Decimal.fromInt(102), ... },
        .{ .close = try Decimal.fromInt(101), ... },
        .{ .close = try Decimal.fromInt(103), ... },
        .{ .close = try Decimal.fromInt(105), ... },
    };

    // 计算 SMA(3)
    const sma = SMA.init(allocator, 3);
    const result = try sma.calculate(&candles);
    defer allocator.free(result);

    // 打印结果
    for (result, 0..) |value, i| {
        std.debug.print("Candle {}: SMA = {}\n", .{ i, value });
    }
}
```

### 2. 在策略中使用

```zig
// 在策略的 populateIndicators 中计算指标
fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));

    // 计算 SMA
    const sma_20 = try SMA.init(self.allocator, 20).calculate(candles.data);
    try candles.addIndicator("sma_20", sma_20);

    // 计算 EMA
    const ema_12 = try EMA.init(self.allocator, 12).calculate(candles.data);
    try candles.addIndicator("ema_12", ema_12);

    // 计算 RSI
    const rsi = try RSI.init(self.allocator, 14).calculate(candles.data);
    try candles.addIndicator("rsi", rsi);

    // 计算 MACD
    const macd_result = try MACD.init(self.allocator, 12, 26, 9).calculate(candles.data);
    try candles.addIndicator("macd_line", macd_result.macd_line);
    try candles.addIndicator("macd_signal", macd_result.signal_line);
    try candles.addIndicator("macd_histogram", macd_result.histogram);

    // 计算布林带
    const bb_result = try BollingerBands.init(self.allocator, 20, 2.0).calculate(candles.data);
    try candles.addIndicator("bb_upper", bb_result.upper);
    try candles.addIndicator("bb_middle", bb_result.middle);
    try candles.addIndicator("bb_lower", bb_result.lower);
}
```

### 3. 使用指标生成信号

```zig
fn generateEntrySignalImpl(ptr: *anyopaque, candles: *Candles, index: usize) !?Signal {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));

    // 获取指标
    const sma = candles.getIndicator("sma_20") orelse return null;
    const rsi = candles.getIndicator("rsi") orelse return null;
    const bb_lower = candles.getIndicator("bb_lower") orelse return null;

    const current_price = candles.data[index].close;
    const current_sma = sma[index];
    const current_rsi = rsi[index];
    const current_bb_lower = bb_lower[index];

    // 综合条件: 价格 > SMA + RSI 超卖 + 价格接近布林带下轨
    if (current_price.gt(current_sma) and
        current_rsi.lt(try Decimal.fromInt(30)) and
        current_price.lte(try current_bb_lower.mul(try Decimal.fromFloat(1.01))))
    {
        return Signal{
            .type = .entry_long,
            .pair = self.ctx.config.pair,
            .side = .buy,
            .price = current_price,
            .strength = 0.8,
            .timestamp = candles.data[index].timestamp,
            .metadata = null,
        };
    }

    return null;
}
```

---

## 📈 指标详解

### SMA (Simple Moving Average) - 简单移动平均

**用途**: 平滑价格波动，识别趋势方向

**计算公式**:
```
SMA(n) = (P₁ + P₂ + ... + Pₙ) / n
```

**参数**:
- `period`: 周期（默认 20）

**使用场景**:
- 趋势判断（价格在 SMA 上方为上升趋势）
- 支撑阻力位
- 双均线策略（快线与慢线交叉）

**示例**:
```zig
const sma = SMA.init(allocator, 20);
const result = try sma.calculate(candles);
```

---

### EMA (Exponential Moving Average) - 指数移动平均

**用途**: 对近期价格赋予更高权重，反应更灵敏

**计算公式**:
```
EMA(t) = α × P(t) + (1 - α) × EMA(t-1)
α = 2 / (period + 1)
```

**参数**:
- `period`: 周期（默认 12）

**使用场景**:
- MACD 指标的基础
- 快速趋势跟踪
- 支撑阻力位

**示例**:
```zig
const ema = EMA.init(allocator, 12);
const result = try ema.calculate(candles);
```

---

### RSI (Relative Strength Index) - 相对强弱指标

**用途**: 衡量价格涨跌动能，识别超买超卖

**计算公式**:
```
RSI = 100 - (100 / (1 + RS))
RS = Average Gain / Average Loss
```

**参数**:
- `period`: 周期（默认 14）

**解读**:
- RSI > 70: 超买，可能回调
- RSI < 30: 超卖，可能反弹
- RSI = 50: 中性

**使用场景**:
- 超买超卖判断
- 背离分析
- 趋势强度确认

**示例**:
```zig
const rsi = RSI.init(allocator, 14);
const result = try rsi.calculate(candles);
```

---

### MACD (Moving Average Convergence Divergence)

**用途**: 趋势跟随和动能分析

**计算公式**:
```
MACD Line = EMA(12) - EMA(26)
Signal Line = EMA(MACD Line, 9)
Histogram = MACD Line - Signal Line
```

**参数**:
- `fast_period`: 快速 EMA 周期（默认 12）
- `slow_period`: 慢速 EMA 周期（默认 26）
- `signal_period`: 信号线周期（默认 9）

**解读**:
- MACD Line 上穿 Signal Line: 金叉，买入信号
- MACD Line 下穿 Signal Line: 死叉，卖出信号
- Histogram > 0: 上升动能
- Histogram < 0: 下降动能

**使用场景**:
- 趋势转折识别
- 交叉信号交易
- 背离分析

**示例**:
```zig
const macd = MACD.init(allocator, 12, 26, 9);
const result = try macd.calculate(candles);
// result.macd_line, result.signal_line, result.histogram
```

---

### Bollinger Bands - 布林带

**用途**: 衡量价格波动性和超买超卖

**计算公式**:
```
Middle Band = SMA(n)
Upper Band = Middle + (k × σ)
Lower Band = Middle - (k × σ)
σ = Standard Deviation
```

**参数**:
- `period`: 周期（默认 20）
- `std_dev`: 标准差倍数（默认 2.0）

**解读**:
- 价格接近上轨: 超买
- 价格接近下轨: 超卖
- 带宽收窄: 波动性降低，可能突破
- 带宽扩张: 波动性增加

**使用场景**:
- 超买超卖判断
- 突破交易
- 波动性分析

**示例**:
```zig
const bb = BollingerBands.init(allocator, 20, 2.0);
const result = try bb.calculate(candles);
// result.upper, result.middle, result.lower
```

---

## ⚡ 性能指标

### 目标

- **计算速度**:
  - SMA: < 500μs (1000 蜡烛)
  - EMA: < 400μs (1000 蜡烛)
  - RSI: < 600μs (1000 蜡烛)
  - MACD: < 800μs (1000 蜡烛)
  - Bollinger Bands: < 700μs (1000 蜡烛)

- **内存占用**:
  - 每个指标 ~8KB (1000 蜡烛 × 8 bytes/Decimal)

- **精度**:
  - 与 TA-Lib 结果误差 < 0.01%

### 实测（预期）

| 指标 | 蜡烛数 | 计算时间 | 内存占用 |
|------|--------|----------|----------|
| SMA | 1000 | < 500μs | 8KB |
| EMA | 1000 | < 400μs | 8KB |
| RSI | 1000 | < 600μs | 24KB (中间数组) |
| MACD | 1000 | < 800μs | 32KB (3个结果数组) |
| BB | 1000 | < 700μs | 24KB (3个结果数组) |

---

## 🔧 高级用法

### 自定义指标

```zig
/// 自定义指标: Williams %R
pub const WilliamsR = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub fn init(allocator: std.mem.Allocator, period: u32) WilliamsR {
        return .{
            .allocator = allocator,
            .period = period,
        };
    }

    pub fn calculate(self: WilliamsR, candles: []const Candle) ![]Decimal {
        var result = try self.allocator.alloc(Decimal, candles.len);

        for (self.period..candles.len) |i| {
            // 找到最高价和最低价
            var highest = candles[i - self.period].high;
            var lowest = candles[i - self.period].low;

            for (i - self.period + 1..i + 1) |j| {
                if (candles[j].high.gt(highest)) highest = candles[j].high;
                if (candles[j].low.lt(lowest)) lowest = candles[j].low;
            }

            const close = candles[i].close;
            const range = try highest.sub(lowest);

            // Williams %R = (Highest High - Close) / (Highest High - Lowest Low) × -100
            const numerator = try highest.sub(close);
            const ratio = try numerator.div(range);
            result[i] = try ratio.mul(try Decimal.fromInt(-100));
        }

        // 前 period-1 个值为 NaN
        for (0..self.period) |i| {
            result[i] = Decimal.NaN;
        }

        return result;
    }
};
```

### 指标组合

```zig
/// 组合指标: 三重指标确认
pub fn tripleConfirmation(
    candles: *Candles,
    index: usize,
) !bool {
    const sma = candles.getIndicator("sma_20") orelse return false;
    const rsi = candles.getIndicator("rsi") orelse return false;
    const bb_lower = candles.getIndicator("bb_lower") orelse return false;

    const price = candles.data[index].close;

    // 条件 1: 价格 > SMA (趋势向上)
    const cond1 = price.gt(sma[index]);

    // 条件 2: RSI 超卖 (< 30)
    const cond2 = rsi[index].lt(try Decimal.fromInt(30));

    // 条件 3: 价格接近布林带下轨
    const cond3 = price.lte(try bb_lower[index].mul(try Decimal.fromFloat(1.02)));

    return cond1 and cond2 and cond3;
}
```

---

## 📚 相关文档

### 本模块文档

- [API 参考](./api.md) - 完整 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试策略](./testing.md) - 测试方法和用例
- [已知问题](./bugs.md) - Bug 追踪
- [变更历史](./changelog.md) - 版本变更记录

### 相关模块

- [Strategy Framework](../strategy/README.md) - 策略框架
- [Decimal](../decimal/README.md) - 高精度数值类型

### 设计文档

- [v0.3.0 策略框架设计](../../v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md) - 完整设计文档

### 外部参考

- [TA-Lib 文档](https://ta-lib.org/)
- [TradingView 指标介绍](https://www.tradingview.com/scripts/)

---

## 🎓 学习路径

1. **理解指标**: 学习各指标的计算原理和应用场景
2. **基本使用**: 计算单个指标
3. **组合使用**: 多个指标配合使用
4. **策略集成**: 在策略中使用指标
5. **自定义指标**: 实现自己的技术指标

---

## ✅ v0.3.0 完成情况

### 已实现指标 (7个)

- ✅ **SMA** - 简单移动平均 (`src/strategy/indicators/sma.zig`)
- ✅ **EMA** - 指数移动平均 (`src/strategy/indicators/ema.zig`)
- ✅ **RSI** - 相对强弱指标 (`src/strategy/indicators/rsi.zig`)
- ✅ **MACD** - 移动平均收敛散度 (`src/strategy/indicators/macd.zig`)
- ✅ **Bollinger Bands** - 布林带 (`src/strategy/indicators/bollinger.zig`)
- ✅ **ATR** - 平均真实波幅 (`src/strategy/indicators/atr.zig`)
- ✅ **Volume Profile** - 成交量分布 (`src/strategy/indicators/volume_profile.zig`)

### 核心组件

- ✅ **IIndicator 接口** - 统一的指标接口
- ✅ **IndicatorManager** - 指标缓存管理器
  - 自动缓存计算结果
  - > 90% 缓存命中率
  - < 0.1ms 缓存查询延迟
- ✅ **Indicator Helpers** - 便捷的辅助函数

**文件结构**:
```
src/strategy/indicators/
├── interface.zig       # IIndicator 接口
├── manager.zig         # IndicatorManager (缓存)
├── helpers.zig         # 辅助函数
├── sma.zig            # 简单移动平均
├── ema.zig            # 指数移动平均
├── rsi.zig            # 相对强弱指标
├── macd.zig           # MACD
├── bollinger.zig      # 布林带
├── atr.zig            # ATR
└── volume_profile.zig # 成交量分布
```

### 测试覆盖

所有指标都包含完整的单元测试：
- 计算准确性测试
- 边界条件测试
- 内存泄漏检测
- 性能基准测试

```bash
# 运行所有测试
zig build test

# 运行策略集成测试（包含指标测试）
zig build test-strategy-full
```

### 使用示例

参见：
- `examples/05_strategy_backtest.zig` - 策略中使用指标
- `examples/07_custom_strategy.zig` - 自定义策略使用 EMA
- 所有内置策略源码 (`src/strategy/builtin/`)

---

**版本**: v0.3.0
**状态**: ✅ 已完成 (2025-12-26)
**更新时间**: 2025-12-26
**参考**: TA-Lib, TradingView
