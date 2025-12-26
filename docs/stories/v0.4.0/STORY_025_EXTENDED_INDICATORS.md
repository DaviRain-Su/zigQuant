# Story: 扩展技术指标库 (8+ 新指标)

**ID**: `STORY-025`
**版本**: `v0.4.0`
**创建日期**: 2024-12-26
**状态**: 📋 待开始
**优先级**: P1 (高优先级)
**预计工时**: 3-4 天
**依赖**: Story 015 (技术指标库基础)

---

## 📋 需求描述

### 用户故事
作为策略开发者，我希望有更丰富的技术指标库（15+ 指标），以便我可以实现更复杂和多样化的交易策略，而不仅限于基础的均线和RSI指标。

### 背景
v0.3.0 实现了 7 个核心指标（SMA, EMA, RSI, MACD, BB, ATR, Stochastic）。为了支持更高级的策略开发，我们需要扩展指标库到 15+ 指标，包括：
- 动量指标（Momentum Indicators）
- 波动率指标（Volatility Indicators）
- 成交量指标（Volume Indicators）
- 趋势指标（Trend Indicators）

参考平台：
- **TA-Lib**: 150+ 指标，行业标准
- **Pandas-TA**: 130+ 指标，Python 生态
- **Tulip Indicators**: 100+ 指标，C 语言高性能实现

### 范围
- **包含**:
  - 8 个新技术指标实现
  - 继续使用统一的指标接口
  - 完整的单元测试
  - 性能基准测试
  - 与 TA-Lib 的精度对比测试

- **不包含**:
  - 自定义指标组合（留待后续版本）
  - 实时指标更新优化（v0.5.0 事件驱动）
  - 指标可视化（v0.6.0）
  - 机器学习指标（v1.0+）

---

## 🎯 验收标准

### 动量指标 (Momentum Indicators)

- [ ] **AC1**: Williams %R 实现正确
  - 计算公式: %R = (Highest High - Close) / (Highest High - Lowest Low) × (-100)
  - 范围 [-100, 0]
  - 默认周期: 14
  - 与 TA-Lib 对比误差 < 0.01%

- [ ] **AC2**: CCI (Commodity Channel Index) 实现正确
  - 计算公式: CCI = (TP - SMA(TP)) / (0.015 × MD)
  - TP = (High + Low + Close) / 3
  - MD = Mean Deviation
  - 默认周期: 20
  - 与 TA-Lib 对比误差 < 0.01%

- [ ] **AC3**: ROC (Rate of Change) 实现正确
  - 计算公式: ROC = ((Close - Close[n]) / Close[n]) × 100
  - 默认周期: 12
  - 与 TA-Lib 对比误差 < 0.01%

### 趋势指标 (Trend Indicators)

- [ ] **AC4**: ADX (Average Directional Index) 实现正确
  - 计算 +DI, -DI, ADX 三条线
  - Wilder's smoothing method
  - 范围 [0, 100]
  - 默认周期: 14
  - 与 TA-Lib 对比误差 < 0.01%

- [ ] **AC5**: Parabolic SAR 实现正确
  - 加速因子正确计算
  - 趋势反转逻辑正确
  - 默认参数: AF=0.02, Max AF=0.2
  - 与 TA-Lib 对比误差 < 0.01%

### 成交量指标 (Volume Indicators)

- [ ] **AC6**: OBV (On Balance Volume) 实现正确
  - 累计成交量计算
  - 价格方向判断正确
  - 与 TA-Lib 对比误差 < 0.01%

- [ ] **AC7**: VWAP (Volume Weighted Average Price) 实现正确
  - 成交量加权平均价计算
  - 支持日内和跨日计算
  - 与 TA-Lib 对比误差 < 0.01%

### 其他高级指标

- [ ] **AC8**: Ichimoku Cloud 实现正确
  - 5 条线: Tenkan-sen, Kijun-sen, Senkou Span A, Senkou Span B, Chikou Span
  - 默认参数: (9, 26, 52)
  - 云层计算正确
  - 与 TA-Lib 对比误差 < 0.01%

### 性能和质量

- [ ] **AC9**: 性能达标
  - 每个指标 1000 根 K线计算时间 < 10ms
  - 内存使用合理（O(n) 空间复杂度）

- [ ] **AC10**: 单元测试覆盖率 > 90%
  - 每个指标至少 5 个测试用例
  - 边界条件测试
  - 精度对比测试
  - 内存泄漏测试

- [ ] **AC11**: 文档完整
  - 每个指标的 API 文档
  - 计算公式说明
  - 使用示例
  - 参数说明

---

## 🔧 技术设计

### 架构概览

```
src/indicators/
    ├── interface.zig           # 指标接口（已存在）
    ├── sma.zig                 # 简单移动平均（已存在）
    ├── ema.zig                 # 指数移动平均（已存在）
    ├── rsi.zig                 # RSI（已存在）
    ├── macd.zig                # MACD（已存在）
    ├── bollinger.zig           # 布林带（已存在）
    ├── atr.zig                 # ATR（已存在）
    ├── stochastic.zig          # 随机指标（已存在）
    ├── williams_r.zig          # Williams %R（新增）✨
    ├── cci.zig                 # CCI（新增）✨
    ├── roc.zig                 # ROC（新增）✨
    ├── adx.zig                 # ADX（新增）✨
    ├── parabolic_sar.zig       # Parabolic SAR（新增）✨
    ├── obv.zig                 # OBV（新增）✨
    ├── vwap.zig                # VWAP（新增）✨
    ├── ichimoku.zig            # Ichimoku Cloud（新增）✨
    └── utils.zig               # 辅助函数（扩展）
```

### 数据结构

#### 1. Williams %R (williams_r.zig)

```zig
const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Candle = @import("../market/candle.zig").Candle;

/// Williams %R 指标
///
/// 计算公式:
/// %R = (Highest High - Close) / (Highest High - Lowest Low) × (-100)
///
/// 参数:
/// - period: 回看周期（默认 14）
///
/// 范围: [-100, 0]
/// - 超买: > -20
/// - 超卖: < -80
pub const WilliamsR = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub fn init(allocator: std.mem.Allocator, period: u32) !WilliamsR {
        if (period == 0) return error.InvalidPeriod;
        return .{
            .allocator = allocator,
            .period = period,
        };
    }

    pub fn deinit(self: *WilliamsR) void {
        _ = self;
    }

    pub fn calculate(self: *WilliamsR, candles: []const Candle) ![]Decimal {
        // 实现逻辑
    }
};
```

#### 2. CCI (cci.zig)

```zig
/// CCI (Commodity Channel Index) 指标
///
/// 计算公式:
/// 1. TP = (High + Low + Close) / 3
/// 2. SMA(TP) = TP的简单移动平均
/// 3. MD = Mean Deviation = 平均绝对偏差
/// 4. CCI = (TP - SMA(TP)) / (0.015 × MD)
///
/// 参数:
/// - period: 周期（默认 20）
///
/// 范围: 无界
/// - 超买: > +100
/// - 超卖: < -100
pub const CCI = struct {
    allocator: std.mem.Allocator,
    period: u32,
    constant: Decimal, // 通常为 0.015

    pub fn init(allocator: std.mem.Allocator, period: u32) !CCI {
        if (period == 0) return error.InvalidPeriod;
        return .{
            .allocator = allocator,
            .period = period,
            .constant = try Decimal.fromString("0.015"),
        };
    }

    pub fn calculate(self: *CCI, candles: []const Candle) ![]Decimal {
        // 实现逻辑
    }
};
```

#### 3. ADX (adx.zig)

```zig
/// ADX (Average Directional Index) 指标
///
/// 计算步骤:
/// 1. 计算 +DM, -DM (Directional Movement)
/// 2. 计算 +DI, -DI (Directional Indicators)
/// 3. 计算 DX (Directional Index)
/// 4. 计算 ADX (DX 的平滑移动平均)
///
/// 参数:
/// - period: 周期（默认 14）
///
/// 返回值:
/// - ADX: 趋势强度 [0, 100]
/// - +DI: 上升趋势强度
/// - -DI: 下降趋势强度
pub const ADX = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub const Result = struct {
        adx: []Decimal,
        plus_di: []Decimal,
        minus_di: []Decimal,

        pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
            allocator.free(self.adx);
            allocator.free(self.plus_di);
            allocator.free(self.minus_di);
        }
    };

    pub fn calculate(self: *ADX, candles: []const Candle) !Result {
        // 实现逻辑
    }
};
```

#### 4. Ichimoku Cloud (ichimoku.zig)

```zig
/// Ichimoku Cloud (一目均衡表) 指标
///
/// 5 条线:
/// 1. Tenkan-sen (转换线) = (9日最高 + 9日最低) / 2
/// 2. Kijun-sen (基准线) = (26日最高 + 26日最低) / 2
/// 3. Senkou Span A (先行带A) = (转换线 + 基准线) / 2，向前位移 26 周期
/// 4. Senkou Span B (先行带B) = (52日最高 + 52日最低) / 2，向前位移 26 周期
/// 5. Chikou Span (迟行带) = 当前收盘价，向后位移 26 周期
///
/// 云层:
/// - 云层 = Senkou Span A 和 Senkou Span B 之间的区域
/// - 绿云 (看涨): Span A > Span B
/// - 红云 (看跌): Span A < Span B
pub const Ichimoku = struct {
    allocator: std.mem.Allocator,
    tenkan_period: u32,   // 默认 9
    kijun_period: u32,    // 默认 26
    senkou_period: u32,   // 默认 52

    pub const Result = struct {
        tenkan_sen: []Decimal,
        kijun_sen: []Decimal,
        senkou_span_a: []Decimal,
        senkou_span_b: []Decimal,
        chikou_span: []Decimal,

        pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
            allocator.free(self.tenkan_sen);
            allocator.free(self.kijun_sen);
            allocator.free(self.senkou_span_a);
            allocator.free(self.senkou_span_b);
            allocator.free(self.chikou_span);
        }
    };

    pub fn init(allocator: std.mem.Allocator) !Ichimoku {
        return .{
            .allocator = allocator,
            .tenkan_period = 9,
            .kijun_period = 26,
            .senkou_period = 52,
        };
    }

    pub fn calculate(self: *Ichimoku, candles: []const Candle) !Result {
        // 实现逻辑
    }
};
```

### 实现优先级

**Week 1 (Day 1-2)**: 动量指标
1. Williams %R (4 小时)
2. CCI (4 小时)
3. ROC (2 小时)

**Week 1 (Day 3)**: 趋势指标
4. ADX (6 小时)
5. Parabolic SAR (4 小时)

**Week 2 (Day 4)**: 成交量指标
6. OBV (2 小时)
7. VWAP (4 小时)

**Week 2 (Day 5)**: 高级指标
8. Ichimoku Cloud (6 小时)

**Week 2 (Day 6)**: 测试和文档
- 集成测试
- 性能测试
- 文档编写

---

## 📊 测试策略

### 单元测试

每个指标需要以下测试：

```zig
test "Williams %R - basic calculation" {
    // 基本计算测试
}

test "Williams %R - boundary conditions" {
    // 边界条件：周期 = 1, 周期 = candles.len
}

test "Williams %R - precision vs TA-Lib" {
    // 精度对比测试
}

test "Williams %R - memory leak" {
    // 内存泄漏测试（使用 GPA）
}

test "Williams %R - invalid parameters" {
    // 无效参数测试
}
```

### 精度测试数据

使用真实的 BTC/USDT 历史数据（1000 根 K线），与 TA-Lib 对比：

```python
# Python TA-Lib 生成参考数据
import talib
import pandas as pd

# 加载数据
df = pd.read_csv('data/BTCUSDT_1h_2024.csv')

# 计算指标
willr = talib.WILLR(df['high'], df['low'], df['close'], timeperiod=14)
cci = talib.CCI(df['high'], df['low'], df['close'], timeperiod=20)
roc = talib.ROC(df['close'], timeperiod=12)
adx = talib.ADX(df['high'], df['low'], df['close'], timeperiod=14)

# 保存参考数据
willr.to_csv('tests/data/willr_reference.csv')
```

### 性能基准

目标性能（1000 根 K线）：
- Williams %R: < 5ms
- CCI: < 8ms
- ROC: < 3ms
- ADX: < 12ms
- Parabolic SAR: < 10ms
- OBV: < 3ms
- VWAP: < 5ms
- Ichimoku: < 15ms

---

## 📚 文档要求

### API 文档

每个指标需要包含：
1. 功能描述
2. 计算公式
3. 参数说明
4. 返回值说明
5. 使用示例
6. 交易信号解读

### 示例代码

```zig
// 在策略中使用 Williams %R
const willr = try WilliamsR.init(allocator, 14);
defer willr.deinit();

const values = try willr.calculate(candles);
defer allocator.free(values);

// 检测超卖
if (values[values.len - 1].toFloat() < -80.0) {
    // 超卖信号，考虑买入
}
```

---

## 🔗 相关文档

- [Story 015: 技术指标库基础](./STORY_015_TECHNICAL_INDICATORS.md)
- [Indicators API 文档](../../features/indicators/api.md)
- [TA-Lib 参考文档](https://ta-lib.org/function.html)
- [Pandas-TA 文档](https://github.com/twopirllc/pandas-ta)

---

## ✅ 完成标准

- [ ] 所有 8 个指标实现完成
- [ ] 所有单元测试通过（覆盖率 > 90%）
- [ ] 性能基准测试通过
- [ ] 精度测试通过（误差 < 0.01%）
- [ ] 内存泄漏测试通过
- [ ] API 文档完成
- [ ] 使用示例完成
- [ ] 集成到 IndicatorManager
- [ ] 更新 indicators feature 文档

---

**创建时间**: 2024-12-26
**最后更新**: 2024-12-26
**作者**: Claude (Sonnet 4.5)
