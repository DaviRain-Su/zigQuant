# Story: 扩展内置策略 (新增 2+ 策略)

**ID**: `STORY-026`
**版本**: `v0.4.0`
**创建日期**: 2024-12-26
**状态**: 📋 待开始
**优先级**: P1 (高优先级)
**预计工时**: 4-5 天
**依赖**: Story 025 (扩展技术指标库)

---

## 📋 需求描述

### 用户故事
作为量化交易者，我希望有更多经过验证的内置策略（5+ 策略），以便我可以学习不同的策略模式，并作为自定义策略的参考实现。

### 背景
v0.3.0 实现了 3 个基础策略（Dual MA, RSI Mean Reversion, Bollinger Breakout）。为了展示框架的能力和为用户提供更多参考，我们需要实现更多经典策略：

**已有策略 (v0.3.0)**:
1. Dual Moving Average - 双均线交叉
2. RSI Mean Reversion - RSI 均值回归
3. Bollinger Breakout - 布林带突破

**新增策略 (v0.4.0)**:
4. Triple MA Crossover - 三均线系统
5. MACD Histogram Divergence - MACD 柱状图背离
6. (可选) Trend Following with ADX - ADX 趋势跟随
7. (可选) Volume Confirmation Breakout - 成交量确认突破

参考来源：
- **Freqtrade**: 50+ 内置策略
- **Backtrader**: 多种经典策略实现
- **QuantConnect**: 策略库参考

### 范围
- **包含**:
  - 至少 2 个新策略实现
  - 使用新增的技术指标（Story 025）
  - JSON 配置文件
  - 回测验证（真实历史数据）
  - 完整的策略文档
  - 参数优化示例

- **不包含**:
  - 机器学习策略（v1.0+）
  - 做市策略（v0.7.0）
  - 套利策略（v0.7.0）
  - 组合策略（v1.0+）

---

## 🎯 验收标准

### 策略 1: Triple MA Crossover

- [ ] **AC1**: 三均线策略实现正确
  - 使用短期、中期、长期三条均线
  - 支持 SMA/EMA 切换
  - 多重信号确认机制
  - 完整的入场/出场逻辑

- [ ] **AC2**: 配置文件完整
  ```json
  {
    "strategy": "triple_ma",
    "parameters": {
      "fast_period": 5,
      "medium_period": 20,
      "slow_period": 50,
      "ma_type": "ema"
    }
  }
  ```

- [ ] **AC3**: 回测验证
  - 使用 BTC/USDT 2024 年数据
  - 至少 10 笔交易
  - 文档化回测结果

### 策略 2: MACD Histogram Divergence

- [ ] **AC4**: MACD 背离策略实现正确
  - 检测 MACD 柱状图与价格背离
  - 看涨背离：价格创新低，MACD 不创新低
  - 看跌背离：价格创新高，MACD 不创新高
  - 背离确认机制

- [ ] **AC5**: 配置文件完整
  ```json
  {
    "strategy": "macd_divergence",
    "parameters": {
      "fast_period": 12,
      "slow_period": 26,
      "signal_period": 9,
      "divergence_lookback": 14,
      "min_bars_between_peaks": 5
    }
  }
  ```

- [ ] **AC6**: 回测验证
  - 使用 ETH/USDT 2024 年数据
  - 至少 5 笔交易
  - 文档化背离信号

### (可选) 策略 3: Trend Following with ADX

- [ ] **AC7**: ADX 趋势跟随策略实现正确
  - ADX > 25 确认趋势强度
  - +DI 和 -DI 交叉确认方向
  - ATR 止损止盈
  - 完整的风险管理

- [ ] **AC8**: 配置文件完整
  ```json
  {
    "strategy": "adx_trend_following",
    "parameters": {
      "adx_period": 14,
      "adx_threshold": 25,
      "atr_period": 14,
      "atr_stop_multiplier": 2.0,
      "atr_profit_multiplier": 3.0
    }
  }
  ```

### 通用验收标准

- [ ] **AC9**: 所有策略符合 IStrategy 接口
  - `init()` 方法实现
  - `onCandle()` 方法实现
  - `getName()` 方法实现
  - `getDescription()` 方法实现
  - `deinit()` 方法实现

- [ ] **AC10**: 性能达标
  - 策略执行时间 < 10ms/candle
  - 内存使用合理
  - 无内存泄漏

- [ ] **AC11**: 单元测试覆盖率 > 80%
  - 策略逻辑测试
  - 边界条件测试
  - 参数验证测试

- [ ] **AC12**: 文档完整
  - 策略描述
  - 交易逻辑说明
  - 参数说明
  - 使用示例
  - 回测结果分析

---

## 🔧 技术设计

### 架构概览

```
src/strategy/builtin/
    ├── dual_ma.zig                 # 双均线（已存在）
    ├── rsi_mean_reversion.zig      # RSI 均值回归（已存在）
    ├── bollinger_breakout.zig      # 布林带突破（已存在）
    ├── triple_ma.zig               # 三均线交叉（新增）✨
    ├── macd_divergence.zig         # MACD 背离（新增）✨
    ├── adx_trend_following.zig     # ADX 趋势跟随（新增，可选）✨
    └── volume_breakout.zig         # 成交量突破（新增，可选）✨

examples/strategies/
    ├── dual_ma.json                # 已存在
    ├── rsi_mean_reversion.json     # 已存在
    ├── bollinger_breakout.json     # 已存在
    ├── triple_ma.json              # 新增 ✨
    ├── triple_ma_optimize.json     # 新增 ✨
    ├── macd_divergence.json        # 新增 ✨
    └── macd_divergence_optimize.json # 新增 ✨
```

### 数据结构

#### 1. Triple MA Crossover (triple_ma.zig)

```zig
const std = @import("std");
const zigQuant = @import("../../root.zig");

const IStrategy = zigQuant.IStrategy;
const StrategyContext = zigQuant.strategy_interface.StrategyContext;
const Signal = zigQuant.strategy_interface.Signal;
const SignalType = zigQuant.strategy_interface.SignalType;
const Decimal = zigQuant.Decimal;
const Logger = zigQuant.Logger;

/// Triple Moving Average Crossover Strategy
///
/// 交易逻辑:
/// 1. 买入信号:
///    - 短期均线 > 中期均线 > 长期均线（多头排列）
///    - 短期均线向上穿越中期均线
/// 2. 卖出信号:
///    - 短期均线 < 中期均线 < 长期均线（空头排列）
///    - 短期均线向下穿越中期均线
///
/// 优势:
/// - 多重确认，减少假信号
/// - 趋势跟随能力强
/// - 适合中长期趋势
///
/// 风险:
/// - 震荡市场表现差
/// - 信号滞后
/// - 参数敏感
pub const TripleMAStrategy = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    // 参数
    fast_period: u32,      // 默认 5
    medium_period: u32,    // 默认 20
    slow_period: u32,      // 默认 50
    ma_type: MAType,       // SMA 或 EMA

    // 状态
    in_position: bool,

    pub const MAType = enum {
        sma,
        ema,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        fast_period: u32,
        medium_period: u32,
        slow_period: u32,
        ma_type: MAType,
    ) !TripleMAStrategy {
        // 参数验证
        if (fast_period >= medium_period) {
            return error.InvalidFastPeriod;
        }
        if (medium_period >= slow_period) {
            return error.InvalidMediumPeriod;
        }

        return .{
            .allocator = allocator,
            .logger = logger,
            .fast_period = fast_period,
            .medium_period = medium_period,
            .slow_period = slow_period,
            .ma_type = ma_type,
            .in_position = false,
        };
    }

    pub fn deinit(self: *TripleMAStrategy) void {
        _ = self;
    }

    pub fn toInterface(self: *TripleMAStrategy) IStrategy {
        return .{
            .ptr = self,
            .vtable = &.{
                .init = initFn,
                .onCandle = onCandleFn,
                .getName = getNameFn,
                .getDescription = getDescriptionFn,
                .deinit = deinitFn,
            },
        };
    }

    fn initFn(ptr: *anyopaque, _: *StrategyContext) anyerror!void {
        const self: *TripleMAStrategy = @ptrCast(@alignCast(ptr));
        self.in_position = false;
    }

    fn onCandleFn(
        ptr: *anyopaque,
        ctx: *StrategyContext,
    ) anyerror!?Signal {
        const self: *TripleMAStrategy = @ptrCast(@alignCast(ptr));

        // 计算三条均线
        const fast_ma = try self.calculateMA(ctx, self.fast_period);
        const medium_ma = try self.calculateMA(ctx, self.medium_period);
        const slow_ma = try self.calculateMA(ctx, self.slow_period);

        // 检查是否有足够的历史数据
        if (ctx.candles.len < self.slow_period + 1) {
            return null;
        }

        const idx = ctx.candles.len - 1;
        const prev_idx = idx - 1;

        // 买入信号：多头排列 + 金叉
        if (!self.in_position) {
            const bullish_alignment = fast_ma[idx].gt(medium_ma[idx]) and
                                     medium_ma[idx].gt(slow_ma[idx]);
            const golden_cross = fast_ma[prev_idx].lte(medium_ma[prev_idx]) and
                               fast_ma[idx].gt(medium_ma[idx]);

            if (bullish_alignment and golden_cross) {
                self.in_position = true;
                return Signal{
                    .signal_type = .buy,
                    .price = ctx.current_candle.close,
                    .quantity = try Decimal.fromInt(1),
                    .reason = "Triple MA golden cross + bullish alignment",
                };
            }
        }

        // 卖出信号：空头排列 + 死叉
        if (self.in_position) {
            const bearish_alignment = fast_ma[idx].lt(medium_ma[idx]) and
                                     medium_ma[idx].lt(slow_ma[idx]);
            const death_cross = fast_ma[prev_idx].gte(medium_ma[prev_idx]) and
                              fast_ma[idx].lt(medium_ma[idx]);

            if (bearish_alignment and death_cross) {
                self.in_position = false;
                return Signal{
                    .signal_type = .sell,
                    .price = ctx.current_candle.close,
                    .quantity = try Decimal.fromInt(1),
                    .reason = "Triple MA death cross + bearish alignment",
                };
            }
        }

        return null;
    }

    fn calculateMA(
        self: *TripleMAStrategy,
        ctx: *StrategyContext,
        period: u32,
    ) ![]Decimal {
        return switch (self.ma_type) {
            .sma => try ctx.getSMA(period),
            .ema => try ctx.getEMA(period),
        };
    }

    fn getNameFn(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "Triple Moving Average Crossover";
    }

    fn getDescriptionFn(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "Trend following strategy using three moving averages with alignment confirmation";
    }

    fn deinitFn(ptr: *anyopaque) void {
        const self: *TripleMAStrategy = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
```

#### 2. MACD Divergence (macd_divergence.zig)

```zig
/// MACD Histogram Divergence Strategy
///
/// 交易逻辑:
/// 1. 看涨背离（买入信号）:
///    - 价格创出新低（Lower Low）
///    - MACD 柱状图未创新低（Higher Low）
///    - 确认：价格反弹突破前高
///
/// 2. 看跌背离（卖出信号）:
///    - 价格创出新高（Higher High）
///    - MACD 柱状图未创新高（Lower High）
///    - 确认：价格回落突破前低
///
/// 优势:
/// - 捕捉趋势反转点
/// - 高胜率信号
/// - 适合震荡市场
///
/// 风险:
/// - 信号频率低
/// - 需要耐心等待
/// - 假背离可能
pub const MACDDivergenceStrategy = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    // MACD 参数
    fast_period: u32,        // 默认 12
    slow_period: u32,        // 默认 26
    signal_period: u32,      // 默认 9

    // 背离检测参数
    divergence_lookback: u32,      // 回看周期（默认 14）
    min_bars_between_peaks: u32,   // 峰值之间最小间隔（默认 5）

    // 状态
    in_position: bool,
    last_peak_idx: ?usize,
    last_trough_idx: ?usize,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        fast_period: u32,
        slow_period: u32,
        signal_period: u32,
        divergence_lookback: u32,
        min_bars_between_peaks: u32,
    ) !MACDDivergenceStrategy {
        return .{
            .allocator = allocator,
            .logger = logger,
            .fast_period = fast_period,
            .slow_period = slow_period,
            .signal_period = signal_period,
            .divergence_lookback = divergence_lookback,
            .min_bars_between_peaks = min_bars_between_peaks,
            .in_position = false,
            .last_peak_idx = null,
            .last_trough_idx = null,
        };
    }

    fn detectBullishDivergence(
        self: *MACDDivergenceStrategy,
        ctx: *StrategyContext,
        macd_hist: []Decimal,
    ) !bool {
        // 实现看涨背离检测逻辑
        // 1. 找到价格的两个低点
        // 2. 检查 MACD 柱状图的对应低点
        // 3. 判断是否形成背离
    }

    fn detectBearishDivergence(
        self: *MACDDivergenceStrategy,
        ctx: *StrategyContext,
        macd_hist: []Decimal,
    ) !bool {
        // 实现看跌背离检测逻辑
    }
};
```

### 策略工厂更新

需要在 `src/strategy/factory.zig` 中注册新策略：

```zig
const strategies = [_]struct {
    name: []const u8,
    create_fn: *const fn(std.mem.Allocator, std.json.Value) anyerror!StrategyWrapper,
}{
    .{ .name = "dual_ma", .create_fn = createDualMA },
    .{ .name = "rsi_mean_reversion", .create_fn = createRSIMeanReversion },
    .{ .name = "bollinger_breakout", .create_fn = createBollingerBreakout },
    .{ .name = "triple_ma", .create_fn = createTripleMA },              // 新增
    .{ .name = "macd_divergence", .create_fn = createMACDDivergence },  // 新增
};
```

---

## 📊 回测验证

### Triple MA 策略回测

**数据**: BTC/USDT 1h, 2024-01-01 至 2024-12-31

**参数**:
- Fast: 5-period EMA
- Medium: 20-period EMA
- Slow: 50-period EMA

**预期结果**:
- 总交易数: 10-20 笔
- 胜率: > 50%
- 盈亏比: > 1.5
- 最大回撤: < 20%

### MACD Divergence 策略回测

**数据**: ETH/USDT 4h, 2024-01-01 至 2024-12-31

**参数**:
- MACD: (12, 26, 9)
- Divergence Lookback: 14
- Min Bars Between Peaks: 5

**预期结果**:
- 总交易数: 5-10 笔
- 胜率: > 60%
- 盈亏比: > 2.0
- 最大回撤: < 15%

---

## 📚 文档要求

### 策略文档结构

每个策略需要包含：

1. **概述**
   - 策略名称
   - 策略类型（趋势/均值回归/动量）
   - 适用市场（趋势/震荡）

2. **交易逻辑**
   - 入场条件
   - 出场条件
   - 风险管理

3. **参数说明**
   - 参数列表
   - 默认值
   - 推荐范围

4. **使用示例**
   - JSON 配置
   - 回测命令
   - 优化命令

5. **回测结果**
   - 历史表现
   - 市场分析
   - 优化建议

### 示例文档

参见 `docs/features/strategy/builtin/triple_ma.md`

---

## 🔗 相关文档

- [Story 017-019: 基础策略实现](../v0.3.0/)
- [Strategy Framework 文档](../../features/strategy/README.md)
- [IStrategy 接口文档](../../features/strategy/api.md)
- [回测引擎文档](../../features/backtest/README.md)

---

## ✅ 完成标准

- [ ] 至少 2 个新策略实现完成
- [ ] 所有策略通过单元测试（覆盖率 > 80%）
- [ ] 回测验证完成并文档化
- [ ] JSON 配置文件完成
- [ ] 优化配置文件完成
- [ ] 集成到 StrategyFactory
- [ ] 策略文档完成
- [ ] 更新 strategy feature 文档
- [ ] 添加到 CLI 帮助信息

---

**创建时间**: 2024-12-26
**最后更新**: 2024-12-26
**作者**: Claude (Sonnet 4.5)
