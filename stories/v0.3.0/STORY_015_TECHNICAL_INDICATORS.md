# Story: 技术指标库实现 (SMA, EMA, RSI, MACD, BB)

**ID**: `STORY-015`
**版本**: `v0.3.0`
**创建日期**: 2025-12-25
**状态**: 📋 待开始
**优先级**: P0 (必须)
**预计工时**: 2 天

---

## 📋 需求描述

### 用户故事
作为策略开发者，我希望有一套经过验证的技术指标库，以便我可以在策略中使用常见的技术分析指标，而无需自己实现复杂的计算逻辑。

### 背景
技术指标是量化交易策略的基础。参考 TA-Lib（Technical Analysis Library），我们将实现 5 个最常用的核心指标：
- **SMA** (Simple Moving Average) - 简单移动平均
- **EMA** (Exponential Moving Average) - 指数移动平均
- **RSI** (Relative Strength Index) - 相对强弱指标
- **MACD** (Moving Average Convergence Divergence) - 平滑异同移动平均线
- **Bollinger Bands** - 布林带

这些指标的实现必须：
- 计算准确（与 TA-Lib 对比误差 < 0.01%）
- 性能高效（纯 Zig 实现，无依赖）
- 内存安全（无泄漏）
- 可扩展（统一的指标接口）

### 范围
- **包含**:
  - 5 个核心技术指标实现
  - 统一的 IIndicator 接口
  - 完整的单元测试（精度测试）
  - 性能基准测试
  - 与 TA-Lib 的对比测试数据

- **不包含**:
  - IndicatorManager 实现（Story 016）
  - 更多高级指标（ATR, Stochastic 等，后续版本）
  - 可视化功能
  - 实时数据订阅

---

## 🎯 验收标准

- [ ] **AC1**: IIndicator 接口定义完整
  - `calculate()` 方法
  - `getName()` 方法
  - `getRequiredCandles()` 方法

- [ ] **AC2**: SMA 实现正确
  - 支持任意周期参数
  - 滑动窗口计算高效
  - 与 TA-Lib 对比误差 < 0.01%

- [ ] **AC3**: EMA 实现正确
  - 正确的平滑因子计算 (α = 2 / (period + 1))
  - 递归计算逻辑正确
  - 与 TA-Lib 对比误差 < 0.01%

- [ ] **AC4**: RSI 实现正确
  - 价格变化计算准确
  - Wilder 平滑方法正确
  - 范围 [0, 100] 验证
  - 与 TA-Lib 对比误差 < 0.01%

- [ ] **AC5**: MACD 实现正确
  - MACD Line, Signal Line, Histogram 三条线计算准确
  - 默认参数 (12, 26, 9) 正确
  - 与 TA-Lib 对比误差 < 0.01%

- [ ] **AC6**: Bollinger Bands 实现正确
  - 上轨、中轨、下轨计算准确
  - 标准差计算正确
  - 与 TA-Lib 对比误差 < 0.01%

- [ ] **AC7**: 性能达标
  - 1000 根 K线计算时间 < 10ms（每个指标）
  - 内存使用合理（O(n) 空间复杂度）

- [ ] **AC8**: 单元测试覆盖率 > 90%
  - 每个指标至少 5 个测试用例
  - 边界条件测试
  - 精度对比测试
  - 内存泄漏测试

- [ ] **AC9**: 编译通过，无警告

---

## 🔧 技术设计

### 架构概览

```
indicators/
    ├── interface.zig        # IIndicator 接口
    ├── sma.zig             # 简单移动平均
    ├── ema.zig             # 指数移动平均
    ├── rsi.zig             # 相对强弱指标
    ├── macd.zig            # MACD
    ├── bollinger.zig       # 布林带
    └── utils.zig           # 辅助函数（标准差等）
```

### 数据结构

#### 1. IIndicator 接口 (interface.zig)

```zig
const std = @import("std");
const Decimal = @import("../../types/decimal.zig").Decimal;
const Candle = @import("../../types/market.zig").Candle;

/// 技术指标接口
pub const IIndicator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// 计算指标值
        /// @param ptr - 指标实例指针
        /// @param candles - K线数据
        /// @return 指标值数组（长度与 candles 相同，前面不足的部分为 NaN）
        calculate: *const fn (ptr: *anyopaque, candles: []const Candle) anyerror![]Decimal,

        /// 获取指标名称
        getName: *const fn (ptr: *anyopaque) []const u8,

        /// 获取所需的最小蜡烛数
        getRequiredCandles: *const fn (ptr: *anyopaque) u32,

        /// 释放资源
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn calculate(self: IIndicator, candles: []const Candle) ![]Decimal {
        return self.vtable.calculate(self.ptr, candles);
    }

    pub fn getName(self: IIndicator) []const u8 {
        return self.vtable.getName(self.ptr);
    }

    pub fn getRequiredCandles(self: IIndicator) u32 {
        return self.vtable.getRequiredCandles(self.ptr);
    }

    pub fn deinit(self: IIndicator) void {
        self.vtable.deinit(self.ptr);
    }
};
```

#### 2. SMA - 简单移动平均 (sma.zig)

```zig
const std = @import("std");
const Decimal = @import("../../types/decimal.zig").Decimal;
const Candle = @import("../../types/market.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// 简单移动平均 (Simple Moving Average)
/// 公式: SMA = (P1 + P2 + ... + Pn) / n
pub const SMA = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub fn init(allocator: std.mem.Allocator, period: u32) !*SMA {
        if (period == 0) return error.InvalidPeriod;

        const self = try allocator.create(SMA);
        self.* = .{
            .allocator = allocator,
            .period = period,
        };
        return self;
    }

    pub fn toIndicator(self: *SMA) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// 计算 SMA
    pub fn calculate(self: *SMA, candles: []const Candle) ![]Decimal {
        if (candles.len < self.period) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // 前 period-1 个值为 NaN
        for (0..self.period - 1) |i| {
            result[i] = Decimal.NaN;
        }

        // 计算第一个 SMA（使用简单求和）
        var sum = Decimal.ZERO;
        for (0..self.period) |i| {
            sum = try sum.add(candles[i].close);
        }
        result[self.period - 1] = try sum.div(try Decimal.fromInt(self.period));

        // 滑动窗口计算后续 SMA（优化性能）
        for (self.period..candles.len) |i| {
            // sum = sum - old_value + new_value
            sum = try sum.sub(candles[i - self.period].close);
            sum = try sum.add(candles[i].close);
            result[i] = try sum.div(try Decimal.fromInt(self.period));
        }

        return result;
    }

    fn calculateImpl(ptr: *anyopaque, candles: []const Candle) ![]Decimal {
        const self: *SMA = @ptrCast(@alignCast(ptr));
        return self.calculate(candles);
    }

    fn getNameImpl(ptr: *anyopaque) []const u8 {
        const self: *SMA = @ptrCast(@alignCast(ptr));
        _ = self;
        return "SMA";
    }

    fn getRequiredCandlesImpl(ptr: *anyopaque) u32 {
        const self: *SMA = @ptrCast(@alignCast(ptr));
        return self.period;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *SMA = @ptrCast(@alignCast(ptr));
        self.allocator.destroy(self);
    }

    const vtable = IIndicator.VTable{
        .calculate = calculateImpl,
        .getName = getNameImpl,
        .getRequiredCandles = getRequiredCandlesImpl,
        .deinit = deinitImpl,
    };
};
```

#### 3. EMA - 指数移动平均 (ema.zig)

```zig
const std = @import("std");
const Decimal = @import("../../types/decimal.zig").Decimal;
const Candle = @import("../../types/market.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// 指数移动平均 (Exponential Moving Average)
/// 公式:
///   α = 2 / (period + 1)
///   EMA[0] = Price[0]
///   EMA[t] = α × Price[t] + (1 - α) × EMA[t-1]
pub const EMA = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub fn init(allocator: std.mem.Allocator, period: u32) !*EMA {
        if (period == 0) return error.InvalidPeriod;

        const self = try allocator.create(EMA);
        self.* = .{
            .allocator = allocator,
            .period = period,
        };
        return self;
    }

    pub fn toIndicator(self: *EMA) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    pub fn calculate(self: *EMA, candles: []const Candle) ![]Decimal {
        if (candles.len == 0) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // 计算平滑因子 α = 2 / (period + 1)
        const alpha = try Decimal.fromInt(2).div(
            try Decimal.fromInt(self.period + 1)
        );
        const one_minus_alpha = try Decimal.ONE.sub(alpha);

        // EMA[0] = Price[0]
        result[0] = candles[0].close;

        // 递归计算 EMA
        for (1..candles.len) |i| {
            const term1 = try alpha.mul(candles[i].close);
            const term2 = try one_minus_alpha.mul(result[i - 1]);
            result[i] = try term1.add(term2);
        }

        return result;
    }

    // VTable 实现省略（与 SMA 类似）
    const vtable = IIndicator.VTable{
        .calculate = calculateImpl,
        .getName = getNameImpl,
        .getRequiredCandles = getRequiredCandlesImpl,
        .deinit = deinitImpl,
    };
};
```

#### 4. RSI - 相对强弱指标 (rsi.zig)

```zig
const std = @import("std");
const Decimal = @import("../../types/decimal.zig").Decimal;
const Candle = @import("../../types/market.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;

/// 相对强弱指标 (Relative Strength Index)
/// 公式:
///   RS = Average Gain / Average Loss (使用 Wilder 平滑)
///   RSI = 100 - (100 / (1 + RS))
pub const RSI = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub fn init(allocator: std.mem.Allocator, period: u32) !*RSI {
        if (period == 0) return error.InvalidPeriod;

        const self = try allocator.create(RSI);
        self.* = .{
            .allocator = allocator,
            .period = period,
        };
        return self;
    }

    pub fn toIndicator(self: *RSI) IIndicator {
        return IIndicator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    pub fn calculate(self: *RSI, candles: []const Candle) ![]Decimal {
        if (candles.len <= self.period) return error.InsufficientData;

        var result = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(result);

        // 初始化前 period 个值为 NaN
        for (0..self.period) |i| {
            result[i] = Decimal.NaN;
        }

        // 计算价格变化
        var gains = try self.allocator.alloc(Decimal, candles.len);
        defer self.allocator.free(gains);
        var losses = try self.allocator.alloc(Decimal, candles.len);
        defer self.allocator.free(losses);

        gains[0] = Decimal.ZERO;
        losses[0] = Decimal.ZERO;

        for (1..candles.len) |i| {
            const change = try candles[i].close.sub(candles[i - 1].close);
            if (change.isPositive()) {
                gains[i] = change;
                losses[i] = Decimal.ZERO;
            } else {
                gains[i] = Decimal.ZERO;
                losses[i] = try change.abs();
            }
        }

        // 计算第一个平均值（简单平均）
        var avg_gain = Decimal.ZERO;
        var avg_loss = Decimal.ZERO;
        for (1..self.period + 1) |i| {
            avg_gain = try avg_gain.add(gains[i]);
            avg_loss = try avg_loss.add(losses[i]);
        }
        avg_gain = try avg_gain.div(try Decimal.fromInt(self.period));
        avg_loss = try avg_loss.div(try Decimal.fromInt(self.period));

        // 计算第一个 RSI
        result[self.period] = try self.calculateRSI(avg_gain, avg_loss);

        // 使用 Wilder 平滑计算后续 RSI
        // Avg_Gain[t] = (Avg_Gain[t-1] * (period - 1) + Gain[t]) / period
        const period_minus_1 = try Decimal.fromInt(self.period - 1);
        const period_dec = try Decimal.fromInt(self.period);

        for (self.period + 1..candles.len) |i| {
            avg_gain = try avg_gain.mul(period_minus_1).add(gains[i]).div(period_dec);
            avg_loss = try avg_loss.mul(period_minus_1).add(losses[i]).div(period_dec);
            result[i] = try self.calculateRSI(avg_gain, avg_loss);
        }

        return result;
    }

    fn calculateRSI(self: *RSI, avg_gain: Decimal, avg_loss: Decimal) !Decimal {
        _ = self;

        if (avg_loss.isZero()) {
            return try Decimal.fromInt(100);  // 没有损失，RSI = 100
        }

        // RS = Average Gain / Average Loss
        const rs = try avg_gain.div(avg_loss);

        // RSI = 100 - (100 / (1 + RS))
        const denominator = try Decimal.ONE.add(rs);
        const rsi = try Decimal.fromInt(100).sub(
            try Decimal.fromInt(100).div(denominator)
        );

        return rsi;
    }

    // VTable 实现省略
    const vtable = IIndicator.VTable{
        .calculate = calculateImpl,
        .getName = getNameImpl,
        .getRequiredCandles = getRequiredCandlesImpl,
        .deinit = deinitImpl,
    };
};
```

#### 5. MACD (macd.zig)

```zig
const std = @import("std");
const Decimal = @import("../../types/decimal.zig").Decimal;
const Candle = @import("../../types/market.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;
const EMA = @import("ema.zig").EMA;

/// MACD 结果
pub const MACDResult = struct {
    macd_line: []Decimal,
    signal_line: []Decimal,
    histogram: []Decimal,
    allocator: std.mem.Allocator,

    pub fn deinit(self: MACDResult) void {
        self.allocator.free(self.macd_line);
        self.allocator.free(self.signal_line);
        self.allocator.free(self.histogram);
    }
};

/// MACD (Moving Average Convergence Divergence)
/// 公式:
///   MACD Line = EMA(fast) - EMA(slow)
///   Signal Line = EMA(MACD Line, signal_period)
///   Histogram = MACD Line - Signal Line
pub const MACD = struct {
    allocator: std.mem.Allocator,
    fast_period: u32,
    slow_period: u32,
    signal_period: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        fast_period: u32,
        slow_period: u32,
        signal_period: u32,
    ) !*MACD {
        if (fast_period >= slow_period) return error.InvalidPeriods;

        const self = try allocator.create(MACD);
        self.* = .{
            .allocator = allocator,
            .fast_period = fast_period,
            .slow_period = slow_period,
            .signal_period = signal_period,
        };
        return self;
    }

    pub fn initDefault(allocator: std.mem.Allocator) !*MACD {
        return init(allocator, 12, 26, 9);
    }

    pub fn calculate(self: *MACD, candles: []const Candle) !MACDResult {
        if (candles.len < self.slow_period) return error.InsufficientData;

        // 计算快速 EMA
        const fast_ema = try EMA.init(self.allocator, self.fast_period);
        defer fast_ema.toIndicator().deinit();
        const fast_values = try fast_ema.calculate(candles);
        defer self.allocator.free(fast_values);

        // 计算慢速 EMA
        const slow_ema = try EMA.init(self.allocator, self.slow_period);
        defer slow_ema.toIndicator().deinit();
        const slow_values = try slow_ema.calculate(candles);
        defer self.allocator.free(slow_values);

        // 计算 MACD Line = fast_ema - slow_ema
        var macd_line = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(macd_line);

        for (0..candles.len) |i| {
            macd_line[i] = try fast_values[i].sub(slow_values[i]);
        }

        // 创建 MACD Line 的 Candle 数组用于计算 Signal Line
        var macd_candles = try self.allocator.alloc(Candle, candles.len);
        defer self.allocator.free(macd_candles);

        for (0..candles.len) |i| {
            macd_candles[i] = candles[i];
            macd_candles[i].close = macd_line[i];
        }

        // 计算 Signal Line = EMA(MACD Line)
        const signal_ema = try EMA.init(self.allocator, self.signal_period);
        defer signal_ema.toIndicator().deinit();
        const signal_line = try signal_ema.calculate(macd_candles);

        // 计算 Histogram = MACD Line - Signal Line
        var histogram = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(histogram);

        for (0..candles.len) |i| {
            histogram[i] = try macd_line[i].sub(signal_line[i]);
        }

        return MACDResult{
            .macd_line = macd_line,
            .signal_line = signal_line,
            .histogram = histogram,
            .allocator = self.allocator,
        };
    }

    pub fn deinit(self: *MACD) void {
        self.allocator.destroy(self);
    }
};
```

#### 6. Bollinger Bands (bollinger.zig)

```zig
const std = @import("std");
const Decimal = @import("../../types/decimal.zig").Decimal;
const Candle = @import("../../types/market.zig").Candle;
const IIndicator = @import("interface.zig").IIndicator;
const SMA = @import("sma.zig").SMA;
const utils = @import("utils.zig");

/// 布林带结果
pub const BollingerBandsResult = struct {
    upper: []Decimal,
    middle: []Decimal,
    lower: []Decimal,
    allocator: std.mem.Allocator,

    pub fn deinit(self: BollingerBandsResult) void {
        self.allocator.free(self.upper);
        self.allocator.free(self.middle);
        self.allocator.free(self.lower);
    }
};

/// 布林带 (Bollinger Bands)
/// 公式:
///   Middle Band = SMA(period)
///   Upper Band = Middle + (std_dev × σ)
///   Lower Band = Middle - (std_dev × σ)
pub const BollingerBands = struct {
    allocator: std.mem.Allocator,
    period: u32,
    std_dev: f64,  // 标准差倍数

    pub fn init(allocator: std.mem.Allocator, period: u32, std_dev: f64) !*BollingerBands {
        const self = try allocator.create(BollingerBands);
        self.* = .{
            .allocator = allocator,
            .period = period,
            .std_dev = std_dev,
        };
        return self;
    }

    pub fn initDefault(allocator: std.mem.Allocator) !*BollingerBands {
        return init(allocator, 20, 2.0);
    }

    pub fn calculate(self: *BollingerBands, candles: []const Candle) !BollingerBandsResult {
        if (candles.len < self.period) return error.InsufficientData;

        // 计算中轨（SMA）
        const sma = try SMA.init(self.allocator, self.period);
        defer sma.toIndicator().deinit();
        const middle = try sma.calculate(candles);

        // 计算标准差
        var std = try utils.calculateStdDev(self.allocator, candles, middle, self.period);
        defer self.allocator.free(std);

        // 计算上轨和下轨
        var upper = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(upper);
        var lower = try self.allocator.alloc(Decimal, candles.len);
        errdefer self.allocator.free(lower);

        const multiplier = try Decimal.fromFloat(self.std_dev);

        for (0..candles.len) |i| {
            const offset = try std[i].mul(multiplier);
            upper[i] = try middle[i].add(offset);
            lower[i] = try middle[i].sub(offset);
        }

        return BollingerBandsResult{
            .upper = upper,
            .middle = middle,
            .lower = lower,
            .allocator = self.allocator,
        };
    }

    pub fn deinit(self: *BollingerBands) void {
        self.allocator.destroy(self);
    }
};
```

#### 7. 辅助函数 (utils.zig)

```zig
const std = @import("std");
const Decimal = @import("../../types/decimal.zig").Decimal;
const Candle = @import("../../types/market.zig").Candle;

/// 计算标准差
pub fn calculateStdDev(
    allocator: std.mem.Allocator,
    candles: []const Candle,
    mean: []Decimal,
    period: u32,
) ![]Decimal {
    var result = try allocator.alloc(Decimal, candles.len);
    errdefer allocator.free(result);

    // 前 period-1 个值为 NaN
    for (0..period - 1) |i| {
        result[i] = Decimal.NaN;
    }

    // 计算标准差
    for (period - 1..candles.len) |i| {
        var variance = Decimal.ZERO;

        // 计算方差
        for (i - period + 1..i + 1) |j| {
            const diff = try candles[j].close.sub(mean[i]);
            const squared = try diff.mul(diff);
            variance = try variance.add(squared);
        }

        variance = try variance.div(try Decimal.fromInt(period));
        result[i] = try variance.sqrt();
    }

    return result;
}
```

### 文件结构

```
src/strategy/indicators/
├── interface.zig          # IIndicator 接口
├── sma.zig               # 简单移动平均
├── ema.zig               # 指数移动平均
├── rsi.zig               # RSI
├── macd.zig              # MACD
├── bollinger.zig         # 布林带
├── utils.zig             # 辅助函数
├── sma_test.zig          # SMA 测试
├── ema_test.zig          # EMA 测试
├── rsi_test.zig          # RSI 测试
├── macd_test.zig         # MACD 测试
└── bollinger_test.zig    # 布林带测试
```

---

## 📝 任务分解

### Phase 1: 基础指标实现 (1天)
- [ ] 任务 1.1: 实现 IIndicator 接口和 utils
  - 接口定义
  - 标准差计算等辅助函数
- [ ] 任务 1.2: 实现 SMA
  - 基础算法实现
  - 滑动窗口优化
  - 单元测试
- [ ] 任务 1.3: 实现 EMA
  - 递归算法实现
  - 平滑因子计算
  - 单元测试
- [ ] 任务 1.4: 实现 RSI
  - Wilder 平滑算法
  - 边界条件处理
  - 单元测试

### Phase 2: 复合指标实现 (0.5天)
- [ ] 任务 2.1: 实现 MACD
  - 三条线计算
  - 组合 EMA 使用
  - 单元测试
- [ ] 任务 2.2: 实现 Bollinger Bands
  - 标准差计算
  - 三条带计算
  - 单元测试

### Phase 3: 精度验证和性能优化 (0.5天)
- [ ] 任务 3.1: TA-Lib 对比测试
  - 准备测试数据
  - 精度对比（误差 < 0.01%）
- [ ] 任务 3.2: 性能基准测试
  - 1000 根 K线性能测试
  - 内存使用分析
- [ ] 任务 3.3: 更新文档
  - API 文档
  - 使用示例

---

## 🧪 测试策略

### 单元测试

#### sma_test.zig

```zig
const std = @import("std");
const testing = std.testing;
const SMA = @import("sma.zig").SMA;
const Decimal = @import("../../types/decimal.zig").Decimal;
const Candle = @import("../../types/market.zig").Candle;

test "SMA: basic calculation" {
    const allocator = testing.allocator;

    // 准备测试数据: [1, 2, 3, 4, 5]
    const candles = try createTestCandles(allocator, &[_]f64{ 1, 2, 3, 4, 5 });
    defer allocator.free(candles);

    const sma = try SMA.init(allocator, 3);
    defer sma.toIndicator().deinit();

    const result = try sma.calculate(candles);
    defer allocator.free(result);

    // 前 2 个值应该是 NaN
    try testing.expect(result[0].isNaN());
    try testing.expect(result[1].isNaN());

    // SMA(3) = (1+2+3)/3 = 2
    try testing.expect(result[2].approxEqual(try Decimal.fromFloat(2.0), 0.0001));

    // SMA(3) = (2+3+4)/3 = 3
    try testing.expect(result[3].approxEqual(try Decimal.fromFloat(3.0), 0.0001));

    // SMA(3) = (3+4+5)/3 = 4
    try testing.expect(result[4].approxEqual(try Decimal.fromFloat(4.0), 0.0001));
}

test "SMA: TA-Lib comparison" {
    const allocator = testing.allocator;

    // 使用真实市场数据
    const candles = try loadRealMarketData(allocator, "test_data/btc_usdt_1h.csv");
    defer allocator.free(candles);

    const sma = try SMA.init(allocator, 20);
    defer sma.toIndicator().deinit();

    const result = try sma.calculate(candles);
    defer allocator.free(result);

    // 加载 TA-Lib 计算的参考值
    const talib_values = try loadTALibReference(allocator, "test_data/talib_sma20.csv");
    defer allocator.free(talib_values);

    // 对比精度（误差 < 0.01%）
    for (20..candles.len) |i| {
        const error_rate = try calculateErrorRate(result[i], talib_values[i]);
        try testing.expect(error_rate < 0.0001);  // < 0.01%
    }
}

test "SMA: performance benchmark" {
    const allocator = testing.allocator;

    // 生成 1000 根 K线
    const candles = try generateRandomCandles(allocator, 1000);
    defer allocator.free(candles);

    const sma = try SMA.init(allocator, 20);
    defer sma.toIndicator().deinit();

    const start = std.time.nanoTimestamp();
    const result = try sma.calculate(candles);
    const end = std.time.nanoTimestamp();
    defer allocator.free(result);

    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    std.debug.print("SMA(20) on 1000 candles: {d:.2}ms\n", .{elapsed_ms});

    // 性能要求: < 10ms
    try testing.expect(elapsed_ms < 10.0);
}

test "SMA: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak detected!");
    }
    const allocator = gpa.allocator();

    const candles = try createTestCandles(allocator, &[_]f64{ 1, 2, 3, 4, 5 });
    defer allocator.free(candles);

    const sma = try SMA.init(allocator, 3);
    defer sma.toIndicator().deinit();

    const result = try sma.calculate(candles);
    defer allocator.free(result);
}
```

#### rsi_test.zig

```zig
test "RSI: basic calculation" {
    // 测试 RSI 基础计算
    // 验证范围 [0, 100]
}

test "RSI: TA-Lib comparison" {
    // 与 TA-Lib 对比
    // 精度误差 < 0.01%
}

test "RSI: boundary conditions" {
    // 测试边界条件
    // 全部上涨: RSI = 100
    // 全部下跌: RSI = 0
}
```

#### macd_test.zig

```zig
test "MACD: basic calculation" {
    // 测试 MACD 三条线计算
}

test "MACD: TA-Lib comparison" {
    // 与 TA-Lib 对比 (12, 26, 9)
}

test "MACD: crossover detection" {
    // 测试金叉死叉检测
}
```

### 测试数据准备

```bash
# 下载真实市场数据用于测试
$ python scripts/download_market_data.py --pair BTCUSDT --timeframe 1h --days 30

# 使用 TA-Lib 生成参考值
$ python scripts/generate_talib_reference.py --indicator SMA --period 20
$ python scripts/generate_talib_reference.py --indicator RSI --period 14
```

---

## 📚 相关文档

### 设计文档
- [ ] `docs/features/strategy/indicators/README.md` - 指标库概览
- [ ] `docs/features/strategy/indicators/api.md` - API 文档
- [ ] `docs/features/strategy/indicators/algorithms.md` - 算法说明

### 参考资料
- [Story 013]: `STORY_013_ISTRATEGY_INTERFACE.md`
- [TA-Lib Documentation]: https://ta-lib.org/function.html
- [Investopedia - Technical Indicators]: https://www.investopedia.com/terms/t/technicalindicator.asp

---

## 🔗 依赖关系

### 前置条件
- [x] Story 013: IStrategy 接口定义
- [x] `src/types/decimal.zig` - Decimal 类型
- [x] `src/types/market.zig` - Candle 类型

### 被依赖
- Story 016: IndicatorManager 需要使用这些指标
- Story 017-019: 内置策略需要使用这些指标

---

## ⚠️ 风险与挑战

### 已识别风险

1. **风险 1**: 精度误差累积
   - **影响**: 高
   - **缓解措施**:
     - 使用 Decimal 类型避免浮点误差
     - 与 TA-Lib 严格对比验证
     - 每个指标编写精度测试

2. **风险 2**: 性能不达标
   - **影响**: 中
   - **缓解措施**:
     - 使用滑动窗口优化 SMA
     - 避免重复计算
     - 性能基准测试

### 技术挑战

1. **挑战 1**: Wilder 平滑算法实现
   - **解决方案**: 参考 TA-Lib 源码，使用递归公式

2. **挑战 2**: 标准差计算精度
   - **解决方案**: 使用 Decimal 类型，避免浮点数精度问题

---

## 📊 进度追踪

### 时间线
- 开始日期: 待定
- 预计完成: 开始后 2 天
- 实际完成: -

### 工作日志
| 日期 | 进展 | 备注 |
|------|------|------|
| - | - | - |

---

## ✅ 验收检查清单

Story 完成前的最终检查：

- [ ] 所有验收标准已满足
- [ ] 所有任务已完成
- [ ] 单元测试通过 (覆盖率 > 90%)
- [ ] TA-Lib 对比测试通过（误差 < 0.01%）
- [ ] 性能测试通过（1000 candles < 10ms）
- [ ] 代码已审查
- [ ] 文档已更新
- [ ] 无编译警告
- [ ] 内存泄漏测试通过
- [ ] API 文档注释完整
- [ ] 相关 OVERVIEW 已更新

---

## 💡 未来改进

完成此 Story 后可以考虑的优化方向:

- 优化 1: SIMD 加速计算
- 优化 2: 增量计算支持（实时数据场景）
- 扩展 1: 更多指标（ATR, Stochastic, ADX 等）
- 扩展 2: 自定义指标接口

---

*Last updated: 2025-12-25*
*Assignee: Claude*
