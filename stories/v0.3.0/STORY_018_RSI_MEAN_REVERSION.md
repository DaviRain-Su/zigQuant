# Story 018: RSIMeanReversionStrategy 均值回归策略

**Story ID**: STORY-018
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
  - STORY-015: 技术指标库实现 (RSI)
  - STORY-016: IndicatorManager 和缓存优化
  - STORY-017: DualMAStrategy（作为参考实现）
- **后置影响**:
  - STORY-020: BacktestEngine 可使用此策略测试震荡市场
  - STORY-022: GridSearchOptimizer 可优化 RSI 参数

---

## 🎯 Story 描述

### 用户故事
作为一个**量化交易开发者**，我希望**使用 RSI 超买超卖均值回归策略**，以便**在震荡市场中捕捉反转机会**。

### 业务价值
- 提供与趋势跟随策略互补的均值回归策略
- 验证策略框架对不同策略类型的支持
- 展示如何使用振荡指标（RSI）生成交易信号
- RSI 策略在震荡市场表现优异，可与双均线策略组合使用

### 技术背景
RSI 均值回归策略（RSI Mean Reversion Strategy）基于价格会向均值回归的理论：
- **RSI（Relative Strength Index）**: 衡量价格变动速度和幅度的振荡指标
- **超卖区（Oversold）**: RSI < 30，价格可能被过度抛售 → 做多机会
- **超买区（Overbought）**: RSI > 70，价格可能被过度买入 → 做空机会
- **中位回归**: RSI 回到 50 附近 → 出场信号

**优点**:
- 在震荡市场表现优异
- 信号明确，易于执行
- 可结合其他指标过滤信号

**缺点**:
- 在强趋势市场容易频繁止损
- 超买超卖可能持续较长时间

参考实现：
- [Freqtrade RSI Strategy](https://www.freqtrade.io/en/stable/strategy-customization/)
- [TradingView RSI Divergence](https://www.tradingview.com/scripts/rsi/)

---

## 📝 详细需求

### 功能需求

#### FR-018-1: 策略参数配置
- **参数列表**:
  - `rsi_period: u32` - RSI 周期（默认：14）
  - `oversold_threshold: u32` - 超卖阈值（默认：30）
  - `overbought_threshold: u32` - 超买阈值（默认：70）
  - `exit_rsi_level: u32` - 出场 RSI 水平（默认：50）
  - `enable_long: bool` - 启用做多（默认：true）
  - `enable_short: bool` - 启用做空（默认：true）
- **参数约束**:
  - `rsi_period >= 2 and <= 50`
  - `oversold_threshold < 50`
  - `overbought_threshold > 50`
  - `oversold_threshold < exit_rsi_level < overbought_threshold`
- **参数优化支持**: rsi_period, oversold_threshold, overbought_threshold

#### FR-018-2: 指标计算（populateIndicators）
- 计算 RSI 指标
- 将 RSI 值添加到 Candles 数据结构
- 使用 IndicatorManager 缓存结果

#### FR-018-3: 入场信号生成（generateEntrySignal）
- **做多信号（entry_long）**:
  - 条件 1: `RSI[i] < oversold_threshold`（超卖）
  - 条件 2: `RSI[i] > RSI[i-1]`（开始反弹）
  - 条件 3: `enable_long == true`
  - 信号强度: 根据超卖程度计算（0.6-0.9）
- **做空信号（entry_short）**:
  - 条件 1: `RSI[i] > overbought_threshold`（超买）
  - 条件 2: `RSI[i] < RSI[i-1]`（开始回落）
  - 条件 3: `enable_short == true`
  - 信号强度: 根据超买程度计算（0.6-0.9）

#### FR-018-4: 出场信号生成（generateExitSignal）
- **多单出场（exit_long）**:
  - 方式 1: RSI 回到 exit_rsi_level 以上（获利出场）
  - 方式 2: RSI 进入超买区（反转出场）
- **空单出场（exit_short）**:
  - 方式 1: RSI 回到 exit_rsi_level 以下（获利出场）
  - 方式 2: RSI 进入超卖区（反转出场）

#### FR-018-5: 仓位大小计算（calculatePositionSize）
- 根据 RSI 超买超卖程度动态调整仓位
- RSI 越极端，仓位越大（在风险限制内）
- 基础仓位: 80% 资金
- 最大仓位: 95% 资金

#### FR-018-6: 策略元数据（getMetadata）
- **名称**: "RSI Mean Reversion Strategy"
- **版本**: "1.0.0"
- **作者**: "zigQuant"
- **描述**: "Mean reversion strategy based on RSI overbought/oversold levels"
- **类型**: `StrategyType.mean_reversion`
- **时间周期**: 支持所有周期（推荐 15m/1h）
- **启动蜡烛数**: `rsi_period + 1`
- **最小 ROI**:
  - 0 分钟: 1.5%
  - 15 分钟: 1%
  - 30 分钟: 0.5%
- **止损**: -3%
- **追踪止损**:
  - 启用
  - 正收益偏移: 0.5%
  - 追踪距离: 1%

### 非功能需求

#### NFR-018-1: 性能要求
- 单次信号生成延迟 < 100μs
- 支持 10,000+ 根蜡烛的回测
- 内存占用 < 10MB（不含蜡烛数据）

#### NFR-018-2: 代码质量
- 遵循 Zig 编程规范
- 所有公共 API 有文档注释
- 单元测试覆盖率 > 90%
- 零内存泄漏（GPA 验证）

#### NFR-018-3: 可维护性
- 清晰的 RSI 计算逻辑
- 信号生成逻辑模块化
- 详细的策略参数说明

---

## ✅ 验收标准

### AC-018-1: 策略逻辑正确性
- [ ] 能正确识别超卖做多信号
- [ ] 能正确识别超买做空信号
- [ ] RSI 反弹/回落确认机制有效
- [ ] 出场信号触发准确

### AC-018-2: RSI 计算准确性
- [ ] RSI 计算结果与 TA-Lib 一致（误差 < 0.1%）
- [ ] 边界条件处理正确（前 N 根 K 线）
- [ ] 缓存机制正常工作

### AC-018-3: 信号强度计算
- [ ] 信号强度随 RSI 极端程度变化
- [ ] 强度范围在 0.6-0.9 之间
- [ ] 计算公式合理

### AC-018-4: 单元测试完整性
- [ ] 测试超卖做多信号
- [ ] 测试超买做空信号
- [ ] 测试出场信号
- [ ] 测试参数验证
- [ ] 测试边界条件
- [ ] 测试覆盖率 > 90%

### AC-018-5: 回测表现
- [ ] 在震荡市场产生合理交易
- [ ] 在趋势市场不会过度亏损
- [ ] 胜率 > 40%（震荡市场）
- [ ] 性能指标计算正确

---

## 📂 涉及文件

### 新建文件
- `src/strategy/builtin/mean_reversion.zig` - RSI 均值回归策略（~350 行）
- `src/strategy/builtin/mean_reversion_test.zig` - 单元测试（~250 行）
- `docs/features/strategy/builtin/mean_reversion.md` - 策略文档

### 修改文件
- `src/strategy/builtin/mod.zig` - 添加 mean_reversion 模块导出
- `build.zig` - 添加测试模块

### 参考文件
- `src/strategy/interface.zig` - IStrategy 接口
- `src/strategy/indicators/rsi.zig` - RSI 指标实现
- `src/strategy/builtin/dual_ma.zig` - 参考实现
- `docs/v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md` - 设计文档

---

## 🔨 技术实现

### 实现步骤

#### Step 1: 创建策略结构体（30分钟）
```zig
pub const RSIMeanReversionStrategy = struct {
    allocator: std.mem.Allocator,
    ctx: StrategyContext,

    // 策略参数
    rsi_period: u32 = 14,
    oversold_threshold: u32 = 30,
    overbought_threshold: u32 = 70,
    exit_rsi_level: u32 = 50,
    enable_long: bool = true,
    enable_short: bool = true,

    pub const Config = struct {
        rsi_period: u32 = 14,
        oversold_threshold: u32 = 30,
        overbought_threshold: u32 = 70,
        exit_rsi_level: u32 = 50,
        enable_long: bool = true,
        enable_short: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !*RSIMeanReversionStrategy {
        const self = try allocator.create(RSIMeanReversionStrategy);
        self.* = .{
            .allocator = allocator,
            .ctx = undefined,
            .rsi_period = config.rsi_period,
            .oversold_threshold = config.oversold_threshold,
            .overbought_threshold = config.overbought_threshold,
            .exit_rsi_level = config.exit_rsi_level,
            .enable_long = config.enable_long,
            .enable_short = config.enable_short,
        };

        // 参数验证
        try self.validateParameters();

        return self;
    }

    fn validateParameters(self: *RSIMeanReversionStrategy) !void {
        if (self.rsi_period < 2 or self.rsi_period > 50) {
            return error.InvalidRSIPeriod;
        }
        if (self.oversold_threshold >= 50) {
            return error.InvalidOversoldThreshold;
        }
        if (self.overbought_threshold <= 50) {
            return error.InvalidOverboughtThreshold;
        }
        if (self.exit_rsi_level <= self.oversold_threshold or
            self.exit_rsi_level >= self.overbought_threshold) {
            return error.InvalidExitLevel;
        }
    }
};
```

#### Step 2: 实现指标计算（1小时）
```zig
fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
    const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));

    // 计算 RSI
    const rsi = try RSI.init(self.allocator, self.rsi_period).calculate(candles.data);
    try candles.addIndicator("rsi", rsi);
}
```

#### Step 3: 实现入场信号生成（2小时）
```zig
fn generateEntrySignalImpl(ptr: *anyopaque, candles: *Candles, index: usize) !?Signal {
    const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));

    // 检查数据充足性
    if (index < self.rsi_period + 1) return null;

    const rsi_values = candles.getIndicator("rsi") orelse return null;
    const curr_rsi = rsi_values[index];
    const prev_rsi = rsi_values[index - 1];

    // 做多信号：超卖反弹
    if (self.enable_long) {
        if (curr_rsi.lt(try Decimal.fromInt(self.oversold_threshold)) and
            curr_rsi.gt(prev_rsi)) {

            // 计算信号强度：RSI 越低，强度越高
            const strength = try self.calculateLongStrength(curr_rsi);

            return Signal{
                .type = .entry_long,
                .pair = self.ctx.config.pair,
                .side = .buy,
                .price = candles.data[index].close,
                .strength = strength,
                .timestamp = candles.data[index].timestamp,
                .metadata = SignalMetadata{
                    .reason = "RSI oversold bounce",
                    .indicators = &[_]IndicatorValue{
                        .{ .name = "rsi", .value = curr_rsi },
                    },
                },
            };
        }
    }

    // 做空信号：超买回落
    if (self.enable_short) {
        if (curr_rsi.gt(try Decimal.fromInt(self.overbought_threshold)) and
            curr_rsi.lt(prev_rsi)) {

            const strength = try self.calculateShortStrength(curr_rsi);

            return Signal{
                .type = .entry_short,
                .pair = self.ctx.config.pair,
                .side = .sell,
                .price = candles.data[index].close,
                .strength = strength,
                .timestamp = candles.data[index].timestamp,
                .metadata = SignalMetadata{
                    .reason = "RSI overbought pullback",
                    .indicators = &[_]IndicatorValue{
                        .{ .name = "rsi", .value = curr_rsi },
                    },
                },
            };
        }
    }

    return null;
}

fn calculateLongStrength(self: *RSIMeanReversionStrategy, rsi: Decimal) !f64 {
    // RSI 0-30: strength 0.9-0.6
    // strength = 0.9 - (rsi / 30) * 0.3
    const rsi_float = try rsi.toFloat();
    const normalized = rsi_float / @as(f64, @floatFromInt(self.oversold_threshold));
    return 0.9 - (normalized * 0.3);
}

fn calculateShortStrength(self: *RSIMeanReversionStrategy, rsi: Decimal) !f64 {
    // RSI 70-100: strength 0.6-0.9
    const rsi_float = try rsi.toFloat();
    const overbought = @as(f64, @floatFromInt(self.overbought_threshold));
    const normalized = (rsi_float - overbought) / (100.0 - overbought);
    return 0.6 + (normalized * 0.3);
}
```

#### Step 4: 实现出场信号生成（1.5小时）
```zig
fn generateExitSignalImpl(ptr: *anyopaque, candles: *Candles, pos: Position) !?Signal {
    const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));

    const index = candles.data.len - 1;
    const rsi_values = candles.getIndicator("rsi") orelse return null;
    const curr_rsi = rsi_values[index];
    const exit_level = try Decimal.fromInt(self.exit_rsi_level);

    // 多单出场
    if (pos.side == .long) {
        // 方式1: RSI 回到中位以上（获利）
        if (curr_rsi.gte(exit_level)) {
            return Signal{
                .type = .exit_long,
                .pair = pos.pair,
                .side = .sell,
                .price = candles.data[index].close,
                .strength = 0.7,
                .timestamp = candles.data[index].timestamp,
                .metadata = SignalMetadata{
                    .reason = "RSI returned to neutral zone",
                    .indicators = &[_]IndicatorValue{
                        .{ .name = "rsi", .value = curr_rsi },
                    },
                },
            };
        }

        // 方式2: RSI 进入超买区（反转风险）
        const overbought = try Decimal.fromInt(self.overbought_threshold);
        if (curr_rsi.gte(overbought)) {
            return Signal{
                .type = .exit_long,
                .pair = pos.pair,
                .side = .sell,
                .price = candles.data[index].close,
                .strength = 0.9,
                .timestamp = candles.data[index].timestamp,
                .metadata = SignalMetadata{
                    .reason = "RSI entered overbought zone",
                    .indicators = &[_]IndicatorValue{
                        .{ .name = "rsi", .value = curr_rsi },
                    },
                },
            };
        }
    }

    // 空单出场（类似逻辑）
    if (pos.side == .short) {
        if (curr_rsi.lte(exit_level)) {
            // 出场信号...
        }

        const oversold = try Decimal.fromInt(self.oversold_threshold);
        if (curr_rsi.lte(oversold)) {
            // 反转出场...
        }
    }

    return null;
}
```

#### Step 5: 实现动态仓位计算（1小时）
```zig
fn calculatePositionSizeImpl(ptr: *anyopaque, signal: Signal, account: Account) !Decimal {
    const self: *RSIMeanReversionStrategy = @ptrCast(@alignCast(ptr));

    // 基础仓位: 80%
    var base_ratio = try Decimal.fromFloat(0.80);

    // 根据信号强度调整: strength 0.6-0.9 -> ratio 0.80-0.95
    const strength_bonus = (signal.strength - 0.6) / 0.3 * 0.15;
    const final_ratio = try base_ratio.add(try Decimal.fromFloat(strength_bonus));

    // 计算仓位大小
    const available = account.balance;
    const position_value = try available.mul(final_ratio);
    const position_size = try position_value.div(signal.price);

    return position_size;
}
```

#### Step 6: 编写单元测试（2小时）
```zig
test "RSIMeanReversion: oversold long signal" {
    const allocator = std.testing.allocator;

    // 创建超卖反弹测试数据
    var candles = try createTestCandles(allocator, &[_]f64{
        100, 98, 95, 92, 90,  // 下跌至超卖
        88, 86, 85, 86, 88,   // 开始反弹
    });
    defer candles.deinit();

    var strategy = try RSIMeanReversionStrategy.init(allocator, .{
        .rsi_period = 6,
        .oversold_threshold = 30,
    });
    defer strategy.deinit();

    try strategy.populateIndicators(&candles);

    // 验证超卖反弹信号
    const signal = try strategy.generateEntrySignal(&candles, 9);
    try std.testing.expect(signal != null);
    try std.testing.expectEqual(SignalType.entry_long, signal.?.type);
    try std.testing.expect(signal.?.strength >= 0.6 and signal.?.strength <= 0.9);
}

test "RSIMeanReversion: overbought short signal" {
    // 测试超买做空信号...
}

test "RSIMeanReversion: exit at neutral zone" {
    // 测试中位出场...
}

test "RSIMeanReversion: dynamic position sizing" {
    // 测试动态仓位计算...
}
```

#### Step 7: 文档编写（1小时）
- RSI 指标原理
- 均值回归理论
- 参数调优指南
- 适用市场条件
- 风险提示

### 技术决策

#### 决策 1: 反弹/回落确认机制
- **选择**: 要求 RSI 开始反向移动（`RSI[i] > RSI[i-1]`）
- **理由**: 避免在下跌趋势中过早入场（"抄底被套"）
- **权衡**: 可能错过最低点，但提高成功率

#### 决策 2: 双重出场机制
- **选择**: 中位出场 + 反转出场
- **理由**: 灵活应对不同市场情况
- **权衡**: 增加复杂度，但提高适应性

#### 决策 3: 动态信号强度
- **选择**: 根据 RSI 极端程度计算强度
- **理由**: 反映信号质量，用于动态仓位管理
- **权衡**: 计算略复杂，但提供更精细的风险控制

---

## 🧪 测试计划

### 单元测试

#### UT-018-1: 参数验证测试
- 测试无效的 RSI 周期
- 测试无效的阈值设置
- 测试无效的出场水平

#### UT-018-2: 超卖做多信号测试
- RSI < 30 且开始反弹 → entry_long
- RSI < 30 但继续下跌 → null
- RSI > 30 → null

#### UT-018-3: 超买做空信号测试
- RSI > 70 且开始回落 → entry_short
- RSI > 70 但继续上涨 → null

#### UT-018-4: 出场信号测试
- 多单，RSI 回到 50 → exit_long
- 多单，RSI 进入 70+ → exit_long（强度更高）
- 空单，RSI 回到 50 → exit_short

#### UT-018-5: 信号强度计算测试
- RSI = 20 → strength ≈ 0.83
- RSI = 30 → strength ≈ 0.60
- RSI = 70 → strength ≈ 0.60
- RSI = 80 → strength ≈ 0.75

#### UT-018-6: 动态仓位测试
- 高强度信号 → 仓位接近 95%
- 低强度信号 → 仓位约 80%

### 集成测试

#### IT-018-1: 震荡市场回测
- 使用横盘震荡数据（如 2024-02 某段时期）
- 验证能产生多次交易
- 胜率应 > 40%

#### IT-018-2: 趋势市场回测
- 使用强趋势数据
- 验证不会过度亏损
- 止损机制有效

---

## 📊 成功指标

### 功能指标
- ✅ 所有验收标准通过
- ✅ 单元测试覆盖率 > 90%
- ✅ 集成测试全部通过

### 质量指标
- ✅ 零内存泄漏
- ✅ 无编译警告
- ✅ 代码通过 lint 检查

### 性能指标
- ✅ 信号生成延迟 < 100μs
- ✅ 回测速度 > 1000 candles/s

### 回测指标（震荡市场）
- ✅ 胜率 > 40%
- ✅ 盈亏比 > 1.2
- ✅ 最大回撤 < 15%

---

## 📖 参考资料

### 技术文档
- [v0.3.0 策略框架设计](../../v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md)
- [RSI 指标文档](../../features/indicators/rsi.md)

### 外部资源
- [RSI - Investopedia](https://www.investopedia.com/terms/r/rsi.asp)
- [Mean Reversion Trading](https://www.investopedia.com/articles/trading/08/mean-reversion.asp)
- [Freqtrade RSI Strategy](https://github.com/freqtrade/freqtrade-strategies)

---

## 📝 实施笔记

### 开发时间分配
- 结构设计: 0.5小时
- 指标计算: 1小时
- 信号生成: 2小时
- 出场逻辑: 1.5小时
- 仓位计算: 1小时
- 单元测试: 2小时
- 文档编写: 1小时
- **总计**: 9小时（约1天）

### 潜在风险
1. **风险**: RSI 指标实现可能有 bug
   - **缓解**: 对比 TA-Lib 验证准确性

2. **风险**: 信号强度计算公式需调优
   - **缓解**: 通过回测数据优化公式

---

## ✅ 完成检查清单

### 开发阶段
- [ ] 创建策略文件
- [ ] 实现参数验证
- [ ] 实现 RSI 计算
- [ ] 实现入场信号
- [ ] 实现出场信号
- [ ] 实现动态仓位

### 测试阶段
- [ ] 参数验证测试
- [ ] 超卖信号测试
- [ ] 超买信号测试
- [ ] 出场信号测试
- [ ] 信号强度测试
- [ ] 集成测试

### 文档阶段
- [ ] 策略原理文档
- [ ] API 文档
- [ ] 使用示例
- [ ] 参数调优指南

### 验收阶段
- [ ] 所有测试通过
- [ ] 代码审查完成
- [ ] 回测验证完成

---

**创建时间**: 2025-12-25
**预计开始**: Week 2 Day 2
**预计完成**: Week 2 Day 2

---

Generated with Claude Code
