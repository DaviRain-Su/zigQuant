# Story 019: BollingerBreakoutStrategy 布林带突破策略

**Story ID**: STORY-019
**版本**: v0.3.0
**优先级**: P1
**工作量**: 1天
**状态**: 待开始
**创建时间**: 2025-12-25

---

## 📋 基本信息

### 所属版本
v0.3.0 - Week 2: 内置策略 + 回测引擎

### 依赖关系
- **前置依赖**:
  - STORY-013: IStrategy 接口和核心类型
  - STORY-014: StrategyContext 和辅助组件
  - STORY-015: 技术指标库实现 (Bollinger Bands)
  - STORY-016: IndicatorManager 和缓存优化
  - STORY-017: DualMAStrategy（参考实现）
- **后置影响**:
  - STORY-020: BacktestEngine 可使用此策略测试波动突破
  - STORY-022: GridSearchOptimizer 可优化布林带参数

---

## 🎯 Story 描述

### 用户故事
作为一个**量化交易开发者**，我希望**使用布林带突破策略**，以便**在价格突破波动区间时捕捉趋势机会**。

### 业务价值
- 提供波动突破类型的策略示例
- 展示如何使用统计指标（标准差）生成信号
- 验证策略框架对复杂指标（多条线）的支持
- 布林带突破策略在波动扩张期表现优异

### 技术背景
布林带突破策略（Bollinger Bands Breakout Strategy）利用价格波动的统计特性：
- **布林带（Bollinger Bands）**: 由中轨（SMA）、上轨（+2σ）、下轨（-2σ）组成
- **突破上轨**: 价格突破上轨 → 强势信号，可能继续上涨
- **突破下轨**: 价格突破下轨 → 弱势信号，可能继续下跌
- **回归中轨**: 价格回到中轨附近 → 出场信号

**两种交易逻辑**:
1. **突破交易**: 突破上轨做多，突破下轨做空（趋势延续）
2. **反转交易**: 突破上轨做空，突破下轨做多（均值回归）

本策略实现**突破交易逻辑**（趋势延续）。

**优点**:
- 自适应市场波动（波动大时通道宽，波动小时通道窄）
- 突破信号明确
- 可结合成交量过滤假突破

**缺点**:
- 在震荡市场容易产生假突破
- 参数敏感，需要优化

参考实现：
- [Freqtrade Bollinger Strategy](https://www.freqtrade.io/en/stable/strategy-customization/)
- [TradingView BB Breakout](https://www.tradingview.com/scripts/bollingerbands/)

---

## 📝 详细需求

### 功能需求

#### FR-019-1: 策略参数配置
- **参数列表**:
  - `bb_period: u32` - 布林带周期（默认：20）
  - `bb_std_dev: f64` - 标准差倍数（默认：2.0）
  - `breakout_threshold: f64` - 突破确认阈值（默认：0.001，即 0.1%）
  - `enable_long: bool` - 启用做多（默认：true）
  - `enable_short: bool` - 启用做空（默认：true）
  - `use_volume_filter: bool` - 使用成交量过滤（默认：false）
  - `volume_multiplier: f64` - 成交量倍数（默认：1.5）
- **参数约束**:
  - `bb_period >= 5 and <= 100`
  - `bb_std_dev >= 1.0 and <= 3.0`
  - `breakout_threshold >= 0.0 and <= 0.05`
  - `volume_multiplier >= 1.0`
- **参数优化支持**: bb_period, bb_std_dev, breakout_threshold

#### FR-019-2: 指标计算（populateIndicators）
- 计算布林带三条线：upper, middle, lower
- 可选：计算成交量均线（用于过滤）
- 将所有指标添加到 Candles 数据结构
- 使用 IndicatorManager 缓存结果

#### FR-019-3: 入场信号生成（generateEntrySignal）
- **做多信号（entry_long）**:
  - 条件 1: `close[i] > upper[i] * (1 + breakout_threshold)`（突破上轨）
  - 条件 2: `close[i-1] <= upper[i-1]`（前一根未突破）
  - 条件 3（可选）: `volume[i] > volume_avg[i] * volume_multiplier`（放量）
  - 条件 4: `enable_long == true`
  - 信号强度: 根据突破幅度计算（0.7-0.95）
- **做空信号（entry_short）**:
  - 条件 1: `close[i] < lower[i] * (1 - breakout_threshold)`（突破下轨）
  - 条件 2: `close[i-1] >= lower[i-1]`（前一根未突破）
  - 条件 3（可选）: 放量确认
  - 条件 4: `enable_short == true`
  - 信号强度: 根据突破幅度计算（0.7-0.95）

#### FR-019-4: 出场信号生成（generateExitSignal）
- **多单出场（exit_long）**:
  - 方式 1: 价格回到中轨（获利出场）
  - 方式 2: 价格跌破下轨（止损出场）
  - 方式 3: 布林带收窄至一定程度（波动减弱）
- **空单出场（exit_short）**:
  - 方式 1: 价格回到中轨（获利出场）
  - 方式 2: 价格升破上轨（止损出场）
  - 方式 3: 布林带收窄（波动减弱）

#### FR-019-5: 仓位大小计算（calculatePositionSize）
- 根据布林带宽度（波动性）动态调整仓位
- 波动大（带宽宽）→ 仓位小（风险高）
- 波动小（带宽窄）→ 仓位正常
- 基础仓位: 85% 资金
- 最小仓位: 50% 资金（高波动）

#### FR-019-6: 策略元数据（getMetadata）
- **名称**: "Bollinger Bands Breakout Strategy"
- **版本**: "1.0.0"
- **作者**: "zigQuant"
- **描述**: "Breakout strategy based on Bollinger Bands expansion"
- **类型**: `StrategyType.breakout`
- **时间周期**: 支持所有周期（推荐 15m/1h/4h）
- **启动蜡烛数**: `bb_period`
- **最小 ROI**:
  - 0 分钟: 2.5%
  - 20 分钟: 1.5%
  - 40 分钟: 1%
  - 60 分钟: 0.5%
- **止损**: -4%
- **追踪止损**:
  - 启用
  - 正收益偏移: 1%
  - 追踪距离: 1.5%

### 非功能需求

#### NFR-019-1: 性能要求
- 单次信号生成延迟 < 150μs（布林带计算复杂度高）
- 支持 10,000+ 根蜡烛的回测
- 内存占用 < 15MB（需存储多条指标线）

#### NFR-019-2: 代码质量
- 遵循 Zig 编程规范
- 所有公共 API 有文档注释
- 单元测试覆盖率 > 85%
- 零内存泄漏（GPA 验证）

#### NFR-019-3: 数值稳定性
- 标准差计算使用稳定算法
- 避免除零错误
- 处理极端波动情况

---

## ✅ 验收标准

### AC-019-1: 策略逻辑正确性
- [ ] 能正确识别上轨突破做多信号
- [ ] 能正确识别下轨突破做空信号
- [ ] 突破确认机制有效（避免假突破）
- [ ] 成交量过滤功能正常（如启用）

### AC-019-2: 布林带计算准确性
- [ ] 中轨（SMA）计算准确
- [ ] 上下轨计算准确（与 TA-Lib 误差 < 0.1%）
- [ ] 标准差计算数值稳定
- [ ] 边界条件处理正确

### AC-019-3: 信号强度计算
- [ ] 强度随突破幅度增加
- [ ] 强度范围在 0.7-0.95 之间
- [ ] 放量突破获得更高强度（如启用）

### AC-019-4: 出场机制
- [ ] 回归中轨出场准确
- [ ] 反向突破止损有效
- [ ] 带宽收窄出场合理

### AC-019-5: 单元测试完整性
- [ ] 测试上轨突破信号
- [ ] 测试下轨突破信号
- [ ] 测试假突破过滤
- [ ] 测试成交量过滤
- [ ] 测试动态仓位计算
- [ ] 测试覆盖率 > 85%

### AC-019-6: 回测表现
- [ ] 在趋势市场产生合理交易
- [ ] 在震荡市场不会过度亏损
- [ ] 假突破率 < 40%
- [ ] 性能指标计算正确

---

## 📂 涉及文件

### 新建文件
- `src/strategy/builtin/breakout.zig` - 布林带突破策略（~400 行）
- `src/strategy/builtin/breakout_test.zig` - 单元测试（~300 行）
- `docs/features/strategy/builtin/breakout.md` - 策略文档

### 修改文件
- `src/strategy/builtin/mod.zig` - 添加 breakout 模块导出
- `build.zig` - 添加测试模块

### 参考文件
- `src/strategy/interface.zig` - IStrategy 接口
- `src/strategy/indicators/bollinger.zig` - 布林带指标实现
- `src/strategy/builtin/dual_ma.zig` - 参考实现
- `docs/v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md` - 设计文档

---

## 🔨 技术实现

### 实现步骤

#### Step 1: 创建策略结构体（30分钟）
```zig
pub const BollingerBreakoutStrategy = struct {
    allocator: std.mem.Allocator,
    ctx: StrategyContext,

    // 策略参数
    bb_period: u32 = 20,
    bb_std_dev: f64 = 2.0,
    breakout_threshold: f64 = 0.001,  // 0.1%
    enable_long: bool = true,
    enable_short: bool = true,
    use_volume_filter: bool = false,
    volume_multiplier: f64 = 1.5,

    pub const Config = struct {
        bb_period: u32 = 20,
        bb_std_dev: f64 = 2.0,
        breakout_threshold: f64 = 0.001,
        enable_long: bool = true,
        enable_short: bool = true,
        use_volume_filter: bool = false,
        volume_multiplier: f64 = 1.5,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !*BollingerBreakoutStrategy {
        const self = try allocator.create(BollingerBreakoutStrategy);
        self.* = .{
            .allocator = allocator,
            .ctx = undefined,
            .bb_period = config.bb_period,
            .bb_std_dev = config.bb_std_dev,
            .breakout_threshold = config.breakout_threshold,
            .enable_long = config.enable_long,
            .enable_short = config.enable_short,
            .use_volume_filter = config.use_volume_filter,
            .volume_multiplier = config.volume_multiplier,
        };

        try self.validateParameters();
        return self;
    }

    fn validateParameters(self: *BollingerBreakoutStrategy) !void {
        if (self.bb_period < 5 or self.bb_period > 100) {
            return error.InvalidBBPeriod;
        }
        if (self.bb_std_dev < 1.0 or self.bb_std_dev > 3.0) {
            return error.InvalidStdDev;
        }
        if (self.breakout_threshold < 0.0 or self.breakout_threshold > 0.05) {
            return error.InvalidThreshold;
        }
    }
};
```

#### Step 2: 实现指标计算（1小时）
```zig
fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
    const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));

    // 计算布林带
    const bb = try BollingerBands.init(self.allocator, .{
        .period = self.bb_period,
        .std_dev = self.bb_std_dev,
    }).calculate(candles.data);

    try candles.addIndicator("bb_upper", bb.upper);
    try candles.addIndicator("bb_middle", bb.middle);
    try candles.addIndicator("bb_lower", bb.lower);

    // 计算带宽（用于波动性判断）
    const bandwidth = try self.calculateBandwidth(bb.upper, bb.lower, bb.middle);
    try candles.addIndicator("bb_bandwidth", bandwidth);

    // 可选：计算成交量均线
    if (self.use_volume_filter) {
        const volume_avg = try SMA.init(self.allocator, self.bb_period)
            .calculateFromVolume(candles.data);
        try candles.addIndicator("volume_avg", volume_avg);
    }
}

fn calculateBandwidth(
    self: *BollingerBreakoutStrategy,
    upper: []Decimal,
    lower: []Decimal,
    middle: []Decimal,
) ![]Decimal {
    var bandwidth = try self.allocator.alloc(Decimal, upper.len);
    for (0..upper.len) |i| {
        // bandwidth = (upper - lower) / middle * 100
        const diff = try upper[i].sub(lower[i]);
        bandwidth[i] = try diff.div(middle[i]).mul(try Decimal.fromInt(100));
    }
    return bandwidth;
}
```

#### Step 3: 实现突破信号检测（2.5小时）
```zig
fn generateEntrySignalImpl(ptr: *anyopaque, candles: *Candles, index: usize) !?Signal {
    const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));

    if (index < self.bb_period + 1) return null;

    const upper = candles.getIndicator("bb_upper") orelse return null;
    const lower = candles.getIndicator("bb_lower") orelse return null;
    const close = candles.data[index].close;
    const prev_close = candles.data[index - 1].close;

    // 做多信号：突破上轨
    if (self.enable_long) {
        const upper_threshold = try upper[index].mul(
            try Decimal.fromFloat(1.0 + self.breakout_threshold)
        );

        // 检查突破
        const is_breakout = close.gt(upper_threshold);
        const was_below = prev_close.lte(upper[index - 1]);

        if (is_breakout and was_below) {
            // 可选：成交量确认
            if (self.use_volume_filter) {
                const volume_confirmed = try self.checkVolumeConfirmation(candles, index);
                if (!volume_confirmed) return null;
            }

            // 计算突破强度
            const strength = try self.calculateBreakoutStrength(
                close, upper[index], .long
            );

            return Signal{
                .type = .entry_long,
                .pair = self.ctx.config.pair,
                .side = .buy,
                .price = close,
                .strength = strength,
                .timestamp = candles.data[index].timestamp,
                .metadata = SignalMetadata{
                    .reason = "Breakout above upper Bollinger Band",
                    .indicators = &[_]IndicatorValue{
                        .{ .name = "bb_upper", .value = upper[index] },
                        .{ .name = "close", .value = close },
                    },
                },
            };
        }
    }

    // 做空信号：突破下轨
    if (self.enable_short) {
        const lower_threshold = try lower[index].mul(
            try Decimal.fromFloat(1.0 - self.breakout_threshold)
        );

        const is_breakout = close.lt(lower_threshold);
        const was_above = prev_close.gte(lower[index - 1]);

        if (is_breakout and was_above) {
            if (self.use_volume_filter) {
                const volume_confirmed = try self.checkVolumeConfirmation(candles, index);
                if (!volume_confirmed) return null;
            }

            const strength = try self.calculateBreakoutStrength(
                close, lower[index], .short
            );

            return Signal{
                .type = .entry_short,
                .pair = self.ctx.config.pair,
                .side = .sell,
                .price = close,
                .strength = strength,
                .timestamp = candles.data[index].timestamp,
                .metadata = SignalMetadata{
                    .reason = "Breakout below lower Bollinger Band",
                    .indicators = &[_]IndicatorValue{
                        .{ .name = "bb_lower", .value = lower[index] },
                        .{ .name = "close", .value = close },
                    },
                },
            };
        }
    }

    return null;
}

fn calculateBreakoutStrength(
    self: *BollingerBreakoutStrategy,
    price: Decimal,
    band: Decimal,
    direction: enum { long, short },
) !f64 {
    // 计算突破幅度百分比
    const diff = if (direction == .long)
        try price.sub(band)
    else
        try band.sub(price);

    const percent = try diff.div(band).toFloat();

    // 突破幅度 0-2% 映射到强度 0.7-0.95
    const normalized = @min(percent / 0.02, 1.0);
    return 0.7 + (normalized * 0.25);
}

fn checkVolumeConfirmation(
    self: *BollingerBreakoutStrategy,
    candles: *Candles,
    index: usize,
) !bool {
    const volume_avg = candles.getIndicator("volume_avg") orelse return true;
    const curr_volume = candles.data[index].volume;
    const avg_volume = volume_avg[index];

    const threshold = try avg_volume.mul(
        try Decimal.fromFloat(self.volume_multiplier)
    );

    return curr_volume.gte(threshold);
}
```

#### Step 4: 实现出场信号（1.5小时）
```zig
fn generateExitSignalImpl(ptr: *anyopaque, candles: *Candles, pos: Position) !?Signal {
    const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));

    const index = candles.data.len - 1;
    const middle = candles.getIndicator("bb_middle") orelse return null;
    const upper = candles.getIndicator("bb_upper") orelse return null;
    const lower = candles.getIndicator("bb_lower") orelse return null;
    const close = candles.data[index].close;

    // 多单出场
    if (pos.side == .long) {
        // 方式1: 回到中轨
        if (close.lte(middle[index])) {
            return Signal{
                .type = .exit_long,
                .pair = pos.pair,
                .side = .sell,
                .price = close,
                .strength = 0.75,
                .timestamp = candles.data[index].timestamp,
                .metadata = SignalMetadata{
                    .reason = "Price returned to middle band",
                    .indicators = &[_]IndicatorValue{
                        .{ .name = "bb_middle", .value = middle[index] },
                    },
                },
            };
        }

        // 方式2: 跌破下轨（止损）
        if (close.lt(lower[index])) {
            return Signal{
                .type = .exit_long,
                .pair = pos.pair,
                .side = .sell,
                .price = close,
                .strength = 0.95,
                .timestamp = candles.data[index].timestamp,
                .metadata = SignalMetadata{
                    .reason = "Stop loss: broke below lower band",
                    .indicators = &[_]IndicatorValue{
                        .{ .name = "bb_lower", .value = lower[index] },
                    },
                },
            };
        }

        // 方式3: 带宽收窄（波动减弱）
        const bandwidth = candles.getIndicator("bb_bandwidth") orelse return null;
        const avg_bandwidth = try self.calculateAverageBandwidth(bandwidth, index);
        if (bandwidth[index].lt(try avg_bandwidth.mul(try Decimal.fromFloat(0.7)))) {
            return Signal{
                .type = .exit_long,
                .pair = pos.pair,
                .side = .sell,
                .price = close,
                .strength = 0.6,
                .timestamp = candles.data[index].timestamp,
                .metadata = SignalMetadata{
                    .reason = "Bandwidth contraction: volatility decreased",
                    .indicators = &[_]IndicatorValue{
                        .{ .name = "bb_bandwidth", .value = bandwidth[index] },
                    },
                },
            };
        }
    }

    // 空单出场（类似逻辑）
    if (pos.side == .short) {
        // ...
    }

    return null;
}
```

#### Step 5: 实现动态仓位管理（1小时）
```zig
fn calculatePositionSizeImpl(ptr: *anyopaque, signal: Signal, account: Account) !Decimal {
    const self: *BollingerBreakoutStrategy = @ptrCast(@alignCast(ptr));

    // 获取当前带宽（波动性）
    const bandwidth = signal.metadata.?.getIndicator("bb_bandwidth") orelse {
        // 如果无法获取，使用默认仓位
        return try account.balance.mul(try Decimal.fromFloat(0.85))
            .div(signal.price);
    };

    // 带宽 -> 风险系数
    // 高波动（带宽 > 平均）-> 降低仓位
    // 低波动（带宽 < 平均）-> 正常仓位
    var position_ratio: f64 = 0.85;  // 基础 85%

    const bandwidth_float = try bandwidth.toFloat();
    if (bandwidth_float > 5.0) {  // 高波动
        position_ratio = 0.50;  // 降至 50%
    } else if (bandwidth_float > 3.0) {
        position_ratio = 0.70;
    }

    // 根据信号强度微调
    position_ratio += (signal.strength - 0.8) * 0.1;

    const final_ratio = try Decimal.fromFloat(position_ratio);
    const position_value = try account.balance.mul(final_ratio);
    return try position_value.div(signal.price);
}
```

#### Step 6: 编写单元测试（2小时）
```zig
test "BollingerBreakout: upper band breakout" {
    const allocator = std.testing.allocator;

    // 创建突破上轨测试数据
    var candles = try createBBBreakoutData(allocator);
    defer candles.deinit();

    var strategy = try BollingerBreakoutStrategy.init(allocator, .{
        .bb_period = 20,
        .bb_std_dev = 2.0,
    });
    defer strategy.deinit();

    try strategy.populateIndicators(&candles);
    const signal = try strategy.generateEntrySignal(&candles, 25);

    try std.testing.expect(signal != null);
    try std.testing.expectEqual(SignalType.entry_long, signal.?.type);
}

test "BollingerBreakout: volume filter" {
    // 测试成交量过滤...
}

test "BollingerBreakout: bandwidth calculation" {
    // 测试带宽计算...
}

test "BollingerBreakout: dynamic position sizing" {
    // 测试动态仓位...
}
```

#### Step 7: 文档编写（1小时）
- 布林带原理
- 突破交易逻辑
- 参数优化建议
- 风险控制要点

### 技术决策

#### 决策 1: 突破确认阈值
- **选择**: 增加 0.1% 的确认阈值
- **理由**: 减少假突破（价格刚好触及就回落）
- **权衡**: 可能错过部分真突破，但提高胜率

#### 决策 2: 三重出场机制
- **选择**: 中轨回归 + 反向突破 + 带宽收窄
- **理由**: 适应不同市场节奏
- **权衡**: 复杂度增加，但灵活性提升

#### 决策 3: 动态仓位（基于波动性）
- **选择**: 根据带宽调整仓位
- **理由**: 高波动=高风险，应降低仓位
- **权衡**: 可能错过高波动的大行情

---

## 🧪 测试计划

### 单元测试

#### UT-019-1: 布林带计算测试
- 验证中轨、上轨、下轨准确性
- 对比 TA-Lib 结果

#### UT-019-2: 上轨突破信号测试
- 价格突破上轨 → entry_long
- 价格未突破 → null

#### UT-019-3: 下轨突破信号测试
- 价格突破下轨 → entry_short

#### UT-019-4: 假突破过滤测试
- 前一根已突破 → null（避免追高）
- 突破幅度不足 → null

#### UT-019-5: 成交量过滤测试
- 放量突破 → 通过
- 缩量突破 → 过滤

#### UT-019-6: 出场信号测试
- 回归中轨 → 出场
- 反向突破 → 止损

### 集成测试

#### IT-019-1: 趋势市场回测
- 使用强趋势数据
- 验证能捕捉趋势

#### IT-019-2: 震荡市场回测
- 验证假突破过滤有效

---

## 📊 成功指标

### 功能指标
- ✅ 所有验收标准通过
- ✅ 单元测试覆盖率 > 85%

### 回测指标（趋势市场）
- ✅ 胜率 > 35%
- ✅ 盈亏比 > 1.8
- ✅ 假突破率 < 40%

---

## 📖 参考资料

### 技术文档
- [v0.3.0 策略框架设计](../../v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md)
- [Bollinger Bands 文档](../../features/indicators/bollinger.md)

### 外部资源
- [Bollinger Bands - Investopedia](https://www.investopedia.com/terms/b/bollingerbands.asp)
- [BB Breakout Strategy](https://www.tradingview.com/scripts/bollingerbands/)

---

**创建时间**: 2025-12-25
**预计开始**: Week 2 Day 3
**预计完成**: Week 2 Day 3

---

Generated with Claude Code
