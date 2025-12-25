# Story 017: DualMAStrategy 双均线策略实现

**Story ID**: STORY-017
**版本**: v0.3.0
**优先级**: P0
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
  - STORY-015: 技术指标库实现 (SMA/EMA)
  - STORY-016: IndicatorManager 和缓存优化
- **后置影响**:
  - STORY-020: BacktestEngine 需要使用此策略进行测试
  - STORY-022: GridSearchOptimizer 可以优化此策略参数

---

## 🎯 Story 描述

### 用户故事
作为一个**量化交易开发者**，我希望**使用经典的双均线交叉策略**，以便**快速验证策略框架的完整性和回测引擎的准确性**。

### 业务价值
- 提供第一个完整的内置策略示例
- 验证 IStrategy 接口设计的合理性
- 为其他策略开发提供参考模板
- 双均线策略是最经典的趋势跟随策略，易于理解和验证

### 技术背景
双均线策略（Dual Moving Average Strategy）是最经典的技术分析策略之一：
- **金叉（Golden Cross）**: 快速均线上穿慢速均线 → 做多信号
- **死叉（Death Cross）**: 快速均线下穿慢速均线 → 做空信号
- **优点**: 简单、易懂、在趋势市场表现良好
- **缺点**: 在震荡市场容易产生假信号

参考实现：
- [Freqtrade SMA Cross Strategy](https://www.freqtrade.io/en/stable/strategy-customization/)
- [Hummingbot Directional Strategy](https://hummingbot.org/v2-strategies/)

---

## 📝 详细需求

### 功能需求

#### FR-017-1: 策略参数配置
- **参数列表**:
  - `fast_period: u32` - 快速均线周期（默认：10）
  - `slow_period: u32` - 慢速均线周期（默认：20）
  - `ma_type: MAType` - 均线类型（SMA/EMA，默认：SMA）
- **参数约束**:
  - `fast_period < slow_period`
  - `fast_period >= 2`
  - `slow_period <= 200`
- **参数优化支持**: 所有参数都支持网格搜索优化

#### FR-017-2: 指标计算（populateIndicators）
- 计算快速移动平均线（ma_fast）
- 计算慢速移动平均线（ma_slow）
- 将指标添加到 Candles 数据结构中
- 使用 IndicatorManager 缓存结果

#### FR-017-3: 入场信号生成（generateEntrySignal）
- **做多信号（entry_long）**:
  - 前一根 K 线: `ma_fast[i-1] <= ma_slow[i-1]`
  - 当前 K 线: `ma_fast[i] > ma_slow[i]`
  - 信号强度: 0.8
- **做空信号（entry_short）**:
  - 前一根 K 线: `ma_fast[i-1] >= ma_slow[i-1]`
  - 当前 K 线: `ma_fast[i] < ma_slow[i]`
  - 信号强度: 0.8
- **无信号**: 其他情况返回 null

#### FR-017-4: 出场信号生成（generateExitSignal）
- **多单出场（exit_long）**:
  - 持有多单时，检测到死叉 → 平仓
- **空单出场（exit_short）**:
  - 持有空单时，检测到金叉 → 平仓
- **出场逻辑**: 反向交叉即为出场信号

#### FR-017-5: 仓位大小计算（calculatePositionSize）
- 使用固定资金比例（默认：95%）
- 考虑杠杆倍数（默认：1x）
- 返回建议的仓位大小（Decimal）

#### FR-017-6: 策略元数据（getMetadata）
- **名称**: "Dual Moving Average Strategy"
- **版本**: "1.0.0"
- **作者**: "zigQuant"
- **描述**: "Classic dual MA crossover trend following strategy"
- **类型**: `StrategyType.trend_following`
- **时间周期**: 支持所有周期（推荐 15m/1h/4h）
- **启动蜡烛数**: `slow_period`
- **最小 ROI**:
  - 0 分钟: 2%
  - 30 分钟: 1%
- **止损**: -5%
- **追踪止损**: 可选

### 非功能需求

#### NFR-017-1: 性能要求
- 单次信号生成延迟 < 100μs
- 支持 10,000+ 根蜡烛的回测
- 内存占用 < 10MB（不含蜡烛数据）

#### NFR-017-2: 代码质量
- 遵循 Zig 编程规范
- 所有公共 API 有文档注释
- 单元测试覆盖率 > 90%
- 零内存泄漏（GPA 验证）

#### NFR-017-3: 可维护性
- 代码清晰易读
- 使用清晰的变量命名
- 添加必要的注释说明策略逻辑

---

## ✅ 验收标准

### AC-017-1: 策略逻辑正确性
- [ ] 能正确识别金叉做多信号
- [ ] 能正确识别死叉做空信号
- [ ] 不会在非交叉点产生错误信号
- [ ] 出场信号与入场信号方向相反

### AC-017-2: 指标计算准确性
- [ ] SMA 计算结果与 TA-Lib 一致（误差 < 0.01%）
- [ ] EMA 计算结果与 TA-Lib 一致（误差 < 0.01%）
- [ ] 指标缓存功能正常工作

### AC-017-3: 单元测试完整性
- [ ] 测试金叉信号生成
- [ ] 测试死叉信号生成
- [ ] 测试边界条件（数据不足、参数错误）
- [ ] 测试内存管理（无泄漏）
- [ ] 测试覆盖率 > 90%

### AC-017-4: 回测可用性
- [ ] 可以成功加载到回测引擎
- [ ] 能够完成完整回测流程
- [ ] 回测结果合理（有交易产生）
- [ ] 性能指标计算正确

### AC-017-5: 文档完整性
- [ ] 策略原理文档完整
- [ ] API 文档完整
- [ ] 使用示例代码可运行
- [ ] 参数说明清晰

---

## 📂 涉及文件

### 新建文件
- `src/strategy/builtin/dual_ma.zig` - 双均线策略实现（~300 行）
- `src/strategy/builtin/dual_ma_test.zig` - 单元测试（~200 行）
- `docs/features/strategy/builtin/dual_ma.md` - 策略文档

### 修改文件
- `src/strategy/builtin/mod.zig` - 添加 dual_ma 模块导出
- `build.zig` - 添加测试模块

### 参考文件
- `src/strategy/interface.zig` - IStrategy 接口定义
- `src/strategy/indicators/sma.zig` - SMA 指标实现
- `src/strategy/indicators/ema.zig` - EMA 指标实现
- `docs/v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md` - 设计文档

---

## 🔨 技术实现

### 实现步骤

#### Step 1: 创建策略结构体（30分钟）
```zig
pub const DualMAStrategy = struct {
    allocator: std.mem.Allocator,
    ctx: StrategyContext,

    // 策略参数
    fast_period: u32 = 10,
    slow_period: u32 = 20,
    ma_type: MAType = .sma,

    pub const MAType = enum {
        sma,
        ema,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !*DualMAStrategy {
        const self = try allocator.create(DualMAStrategy);
        self.* = .{
            .allocator = allocator,
            .ctx = undefined,
            .fast_period = config.fast_period,
            .slow_period = config.slow_period,
            .ma_type = config.ma_type,
        };

        // 验证参数
        if (self.fast_period >= self.slow_period) {
            return error.InvalidParameters;
        }

        return self;
    }

    pub fn deinit(self: *DualMAStrategy) void {
        self.allocator.destroy(self);
    }
};
```

#### Step 2: 实现 IStrategy 接口（2小时）
```zig
pub fn create(allocator: std.mem.Allocator, config: Config) !IStrategy {
    const self = try init(allocator, config);

    return IStrategy{
        .ptr = self,
        .vtable = &vtable,
    };
}

const vtable = IStrategy.VTable{
    .init = initImpl,
    .deinit = deinitImpl,
    .populateIndicators = populateIndicatorsImpl,
    .generateEntrySignal = generateEntrySignalImpl,
    .generateExitSignal = generateExitSignalImpl,
    .calculatePositionSize = calculatePositionSizeImpl,
    .getParameters = getParametersImpl,
    .getMetadata = getMetadataImpl,
};
```

#### Step 3: 实现指标计算（1小时）
```zig
fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
    const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

    // 根据配置选择均线类型
    const ma_fast = switch (self.ma_type) {
        .sma => try SMA.init(self.allocator, self.fast_period).calculate(candles.data),
        .ema => try EMA.init(self.allocator, self.slow_period).calculate(candles.data),
    };

    const ma_slow = switch (self.ma_type) {
        .sma => try SMA.init(self.allocator, self.slow_period).calculate(candles.data),
        .ema => try EMA.init(self.allocator, self.slow_period).calculate(candles.data),
    };

    try candles.addIndicator("ma_fast", ma_fast);
    try candles.addIndicator("ma_slow", ma_slow);
}
```

#### Step 4: 实现信号生成逻辑（2小时）
```zig
fn generateEntrySignalImpl(ptr: *anyopaque, candles: *Candles, index: usize) !?Signal {
    const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

    // 检查数据充足性
    if (index < self.slow_period) return null;

    const ma_fast = candles.getIndicator("ma_fast") orelse return null;
    const ma_slow = candles.getIndicator("ma_slow") orelse return null;

    const prev_fast = ma_fast[index - 1];
    const prev_slow = ma_slow[index - 1];
    const curr_fast = ma_fast[index];
    const curr_slow = ma_slow[index];

    // 金叉检测
    if (prev_fast.lte(prev_slow) and curr_fast.gt(curr_slow)) {
        return Signal{
            .type = .entry_long,
            .pair = self.ctx.config.pair,
            .side = .buy,
            .price = candles.data[index].close,
            .strength = 0.8,
            .timestamp = candles.data[index].timestamp,
            .metadata = SignalMetadata{
                .reason = "Golden Cross: MA(10) crossed above MA(20)",
                .indicators = &[_]IndicatorValue{
                    .{ .name = "ma_fast", .value = curr_fast },
                    .{ .name = "ma_slow", .value = curr_slow },
                },
            },
        };
    }

    // 死叉检测
    if (prev_fast.gte(prev_slow) and curr_fast.lt(curr_slow)) {
        return Signal{
            .type = .entry_short,
            .pair = self.ctx.config.pair,
            .side = .sell,
            .price = candles.data[index].close,
            .strength = 0.8,
            .timestamp = candles.data[index].timestamp,
            .metadata = SignalMetadata{
                .reason = "Death Cross: MA(10) crossed below MA(20)",
                .indicators = &[_]IndicatorValue{
                    .{ .name = "ma_fast", .value = curr_fast },
                    .{ .name = "ma_slow", .value = curr_slow },
                },
            },
        };
    }

    return null;
}
```

#### Step 5: 编写单元测试（2小时）
```zig
test "DualMAStrategy: golden cross signal" {
    const allocator = std.testing.allocator;

    // 准备测试数据（模拟金叉）
    var candles = try createTestCandles(allocator, &[_]f64{
        100, 101, 102, 103, 104, // 上升趋势
        105, 106, 107, 108, 109, // 继续上升
        110, 111, 112, 113, 114, // 金叉发生
    });
    defer candles.deinit();

    var strategy = try DualMAStrategy.init(allocator, .{
        .fast_period = 5,
        .slow_period = 10,
    });
    defer strategy.deinit();

    try strategy.populateIndicators(&candles);

    // 验证金叉信号
    const signal = try strategy.generateEntrySignal(&candles, 14);
    try std.testing.expect(signal != null);
    try std.testing.expectEqual(SignalType.entry_long, signal.?.type);
}
```

#### Step 6: 集成测试（1小时）
- 使用真实历史数据进行回测
- 验证策略在不同市场条件下的表现
- 性能基准测试

#### Step 7: 文档编写（1小时）
- 策略原理说明
- API 使用文档
- 参数调优建议
- 使用示例代码

### 技术决策

#### 决策 1: 均线类型支持
- **选择**: 同时支持 SMA 和 EMA
- **理由**: 提高策略灵活性，EMA 对近期价格更敏感
- **权衡**: 增加少量复杂度，但提供更多优化空间

#### 决策 2: 信号强度设置
- **选择**: 固定强度 0.8
- **理由**: 双均线信号相对可靠，但不是 100% 确定
- **权衡**: 未来可以根据交叉角度动态调整强度

#### 决策 3: 出场策略
- **选择**: 反向交叉出场
- **理由**: 简单、经典，与趋势跟随理念一致
- **权衡**: 可能错过部分利润，但避免过早出场

---

## 🧪 测试计划

### 单元测试

#### UT-017-1: 参数验证测试
```zig
test "DualMAStrategy: invalid parameters" {
    const allocator = std.testing.allocator;

    // fast_period >= slow_period 应该失败
    try std.testing.expectError(
        error.InvalidParameters,
        DualMAStrategy.init(allocator, .{
            .fast_period = 20,
            .slow_period = 10,
        })
    );
}
```

#### UT-017-2: 金叉信号测试
- 测试数据: 上升趋势，快线上穿慢线
- 预期结果: entry_long 信号
- 验证字段: type, side, strength, metadata

#### UT-017-3: 死叉信号测试
- 测试数据: 下降趋势，快线下穿慢线
- 预期结果: entry_short 信号

#### UT-017-4: 无信号测试
- 测试数据: 均线平行移动
- 预期结果: null（无信号）

#### UT-017-5: 出场信号测试
- 测试场景: 持有多单，遇到死叉
- 预期结果: exit_long 信号

#### UT-017-6: 内存泄漏测试
```zig
test "DualMAStrategy: no memory leaks" {
    const allocator = std.testing.allocator;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try std.testing.expect(leaked == .ok);
    }

    // 运行策略完整流程
    // ...
}
```

### 集成测试

#### IT-017-1: 回测集成测试
- 使用 BTC/USDT 历史数据（2024年1月-3月）
- 验证能够产生交易
- 验证胜率在合理范围（30%-60%）

#### IT-017-2: 性能基准测试
- 测试 10,000 根蜡烛的回测速度
- 目标: < 1秒完成
- 内存占用: < 10MB

---

## 📊 成功指标

### 功能指标
- ✅ 所有验收标准通过
- ✅ 单元测试覆盖率 > 90%
- ✅ 集成测试全部通过

### 质量指标
- ✅ 零内存泄漏
- ✅ 无编译警告
- ✅ 代码通过 zig fmt 检查

### 性能指标
- ✅ 信号生成延迟 < 100μs
- ✅ 回测速度 > 1000 candles/s
- ✅ 内存占用 < 10MB

### 文档指标
- ✅ API 文档完整
- ✅ 使用示例可运行
- ✅ 参数说明清晰

---

## 📖 参考资料

### 技术文档
- [v0.3.0 策略框架设计](../../v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md)
- [IStrategy 接口文档](../../features/strategy/api.md)
- [技术指标库文档](../../features/indicators/api.md)

### 外部资源
- [Moving Average Crossover Strategy - Investopedia](https://www.investopedia.com/articles/active-trading/052014/how-use-moving-average-buy-stocks.asp)
- [Freqtrade Strategy Examples](https://github.com/freqtrade/freqtrade-strategies)
- [TA-Lib SMA Documentation](https://ta-lib.org/function.html?name=SMA)

### 代码示例
- [Freqtrade SMA Strategy](https://www.freqtrade.io/en/stable/strategy-customization/)
- [Backtrader MA Cross Strategy](https://www.backtrader.com/docu/quickstart/quickstart/)

---

## 📝 实施笔记

### 开发环境
- Zig 版本: 0.13.0+
- 测试框架: Zig built-in test
- 性能分析: Zig built-in profiler

### 开发时间分配
- 结构设计: 0.5小时
- 接口实现: 2小时
- 信号逻辑: 2小时
- 单元测试: 2小时
- 集成测试: 1小时
- 文档编写: 1小时
- **总计**: 8.5小时（约1天）

### 潜在风险
1. **风险**: SMA/EMA 指标可能未完成
   - **缓解**: 提前检查 STORY-015 进度，必要时协调

2. **风险**: IStrategy 接口可能变更
   - **缓解**: 及时同步 STORY-013 的变更

3. **风险**: 回测数据不足
   - **缓解**: 准备多组测试数据（趋势/震荡）

---

## ✅ 完成检查清单

### 开发阶段
- [ ] 创建 `dual_ma.zig` 文件
- [ ] 实现策略结构体
- [ ] 实现 IStrategy 接口
- [ ] 实现 populateIndicators
- [ ] 实现 generateEntrySignal
- [ ] 实现 generateExitSignal
- [ ] 实现 calculatePositionSize
- [ ] 实现 getMetadata

### 测试阶段
- [ ] 编写参数验证测试
- [ ] 编写金叉信号测试
- [ ] 编写死叉信号测试
- [ ] 编写出场信号测试
- [ ] 编写内存泄漏测试
- [ ] 运行集成测试
- [ ] 性能基准测试

### 文档阶段
- [ ] 编写策略文档
- [ ] 更新 API 文档
- [ ] 编写使用示例
- [ ] 添加代码注释

### 验收阶段
- [ ] 所有测试通过
- [ ] 代码审查完成
- [ ] 文档审查完成
- [ ] 性能指标达标

---

**创建时间**: 2025-12-25
**预计开始**: Week 2 Day 1
**预计完成**: Week 2 Day 1
**实际开始**: _待填写_
**实际完成**: _待填写_
**开发者**: _待分配_

---

Generated with Claude Code
