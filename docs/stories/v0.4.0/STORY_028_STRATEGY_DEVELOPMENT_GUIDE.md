# Story: 策略开发文档和教程

**ID**: `STORY-028`
**版本**: `v0.4.0`
**创建日期**: 2024-12-26
**状态**: 📋 待开始
**优先级**: P2 (中优先级)
**预计工时**: 2 天
**依赖**: Story 025 (扩展指标), Story 026 (扩展策略)

---

## 📋 需求描述

### 用户故事
作为策略开发者，我希望有完整的开发文档和教程，以便我可以快速学习如何创建自定义策略，而不需要深入研究框架源码。

### 背景
v0.3.0 虽然实现了策略框架，但缺少完整的开发指南。新用户需要：
1. 理解 IStrategy 接口
2. 学习如何使用 StrategyContext
3. 掌握技术指标的使用
4. 了解最佳实践和常见陷阱
5. 参考完整的示例代码

参考平台：
- **Freqtrade**: 优秀的策略开发文档，包含多个教程
- **QuantConnect**: 详细的 API 文档和视频教程
- **Backtrader**: 丰富的示例代码库

### 范围
- **包含**:
  - 策略开发快速入门教程
  - IStrategy 接口完整文档
  - StrategyContext API 参考
  - 技术指标使用指南
  - 调试技巧和最佳实践
  - 5+ 个完整示例策略（含注释）
  - FAQ 常见问题解答

- **不包含**:
  - 视频教程（后续版本）
  - 交互式教程（v1.0）
  - 高级优化技巧（v0.5.0+）
  - 机器学习集成（v1.0+）

---

## 🎯 验收标准

### 文档完整性

- [ ] **AC1**: 快速入门教程完成
  - 15 分钟完成第一个策略
  - 包含从零到回测的完整流程
  - 代码可直接复制运行

- [ ] **AC2**: IStrategy 接口文档完成
  - 每个方法的详细说明
  - 参数和返回值文档
  - 使用示例和注意事项

- [ ] **AC3**: StrategyContext 文档完成
  - 所有可用属性的说明
  - 所有辅助方法的说明
  - 性能注意事项

- [ ] **AC4**: 技术指标使用指南完成
  - 所有 15+ 指标的使用示例
  - 参数推荐和优化建议
  - 组合使用技巧

- [ ] **AC5**: 调试和测试指南完成
  - 单元测试编写方法
  - 日志和调试技巧
  - 常见错误排查

- [ ] **AC6**: 最佳实践文档完成
  - 代码组织建议
  - 性能优化技巧
  - 安全注意事项
  - 常见陷阱避免

### 示例策略

- [ ] **AC7**: 5 个示例策略完成并注释
  1. 简单趋势跟随（入门级）
  2. 多指标组合（中级）
  3. 状态机策略（中级）
  4. 动态参数调整（高级）
  5. 复杂入场确认（高级）

- [ ] **AC8**: 每个示例包含：
  - 策略说明
  - 完整代码（详细注释）
  - JSON 配置
  - 回测示例
  - 优化建议

### FAQ

- [ ] **AC9**: FAQ 文档完成
  - 至少 20 个常见问题
  - 分类组织（入门、进阶、调试）
  - 清晰的问题和解答

### 质量标准

- [ ] **AC10**: 代码示例可运行
  - 所有示例通过编译
  - 所有示例可以回测
  - 无内存泄漏

- [ ] **AC11**: 文档清晰易懂
  - 技术术语有解释
  - 步骤清晰明确
  - 截图和示意图

---

## 🔧 文档结构

### 目录组织

```
docs/guides/
    ├── strategy/
    │   ├── README.md                      # 概览
    │   ├── quickstart.md                  # 快速入门 ✨
    │   ├── interface.md                   # IStrategy 接口文档 ✨
    │   ├── context.md                     # StrategyContext 文档 ✨
    │   ├── indicators.md                  # 指标使用指南 ✨
    │   ├── debugging.md                   # 调试指南 ✨
    │   ├── best-practices.md              # 最佳实践 ✨
    │   ├── examples/
    │   │   ├── 01_simple_trend.md         # 示例 1 ✨
    │   │   ├── 02_multi_indicator.md      # 示例 2 ✨
    │   │   ├── 03_state_machine.md        # 示例 3 ✨
    │   │   ├── 04_dynamic_params.md       # 示例 4 ✨
    │   │   └── 05_complex_entry.md        # 示例 5 ✨
    │   └── faq.md                         # FAQ ✨

examples/strategies/
    ├── tutorial/
    │   ├── 01_hello_strategy.zig          # 教程 1 ✨
    │   ├── 02_using_indicators.zig        # 教程 2 ✨
    │   ├── 03_risk_management.zig         # 教程 3 ✨
    │   ├── 04_state_tracking.zig          # 教程 4 ✨
    │   └── 05_advanced_signals.zig        # 教程 5 ✨
    └── tutorial_configs/
        ├── 01_hello_strategy.json
        ├── 02_using_indicators.json
        └── ...
```

---

## 📚 文档内容详细设计

### 1. 快速入门 (quickstart.md)

#### 内容大纲

```markdown
# 策略开发快速入门

## 目标
15 分钟内创建并回测你的第一个策略。

## 准备工作
- zigQuant 已安装
- 基本的 Zig 语言知识
- 历史数据文件（或使用示例数据）

## Step 1: 创建策略文件 (5 分钟)

创建 `src/strategy/custom/my_first_strategy.zig`:

\`\`\`zig
const std = @import("std");
const zigQuant = @import("../../root.zig");

// 导入需要的类型
const IStrategy = zigQuant.IStrategy;
const StrategyContext = zigQuant.strategy_interface.StrategyContext;
const Signal = zigQuant.strategy_interface.Signal;
const SignalType = zigQuant.strategy_interface.SignalType;
const Decimal = zigQuant.Decimal;

/// 我的第一个策略：简单的 RSI 超买超卖策略
pub const MyFirstStrategy = struct {
    allocator: std.mem.Allocator,

    // 参数
    rsi_period: u32,
    oversold_threshold: f64,
    overbought_threshold: f64,

    // 状态
    in_position: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        rsi_period: u32,
        oversold: f64,
        overbought: f64,
    ) !MyFirstStrategy {
        return .{
            .allocator = allocator,
            .rsi_period = rsi_period,
            .oversold_threshold = oversold,
            .overbought_threshold = overbought,
            .in_position = false,
        };
    }

    pub fn toInterface(self: *MyFirstStrategy) IStrategy {
        // VTable 实现...
    }

    fn onCandleFn(
        ptr: *anyopaque,
        ctx: *StrategyContext,
    ) anyerror!?Signal {
        const self: *MyFirstStrategy = @ptrCast(@alignCast(ptr));

        // 获取 RSI 指标值
        const rsi_values = try ctx.getRSI(self.rsi_period);

        // 检查是否有足够的历史数据
        if (rsi_values.len == 0) return null;

        const current_rsi = try rsi_values[rsi_values.len - 1].toFloat();

        // 买入信号：RSI < 超卖线 且没有持仓
        if (!self.in_position and current_rsi < self.oversold_threshold) {
            self.in_position = true;
            return Signal{
                .signal_type = .buy,
                .price = ctx.current_candle.close,
                .quantity = try Decimal.fromInt(1),
                .reason = "RSI oversold",
            };
        }

        // 卖出信号：RSI > 超买线 且有持仓
        if (self.in_position and current_rsi > self.overbought_threshold) {
            self.in_position = false;
            return Signal{
                .signal_type = .sell,
                .price = ctx.current_candle.close,
                .quantity = try Decimal.fromInt(1),
                .reason = "RSI overbought",
            };
        }

        return null;
    }
};
\`\`\`

## Step 2: 创建配置文件 (2 分钟)

创建 `examples/strategies/my_first_strategy.json`:

\`\`\`json
{
  "strategy": "my_first_strategy",
  "pair": {
    "base": "BTC",
    "quote": "USDT"
  },
  "timeframe": "1h",
  "parameters": {
    "rsi_period": 14,
    "oversold_threshold": 30,
    "overbought_threshold": 70
  }
}
\`\`\`

## Step 3: 注册策略 (3 分钟)

在 `src/strategy/factory.zig` 中添加你的策略...

## Step 4: 运行回测 (5 分钟)

\`\`\`bash
zig build run -- backtest \\
  --strategy my_first_strategy \\
  --config examples/strategies/my_first_strategy.json \\
  --data data/BTCUSDT_1h_2024.csv
\`\`\`

## 恭喜！

你已经完成了第一个策略！接下来：
- [学习使用更多指标](indicators.md)
- [了解最佳实践](best-practices.md)
- [查看更多示例](examples/)
```

### 2. IStrategy 接口文档 (interface.md)

```markdown
# IStrategy 接口文档

## 概述

IStrategy 是所有策略必须实现的核心接口。它定义了策略的生命周期和交互方法。

## 接口定义

\`\`\`zig
pub const IStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// 初始化策略
        init: *const fn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!void,

        /// 处理新蜡烛
        onCandle: *const fn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!?Signal,

        /// 获取策略名称
        getName: *const fn(ptr: *anyopaque) []const u8,

        /// 获取策略描述
        getDescription: *const fn(ptr: *anyopaque) []const u8,

        /// 清理资源
        deinit: *const fn(ptr: *anyopaque) void,
    };
};
\`\`\`

## 方法详解

### init()

**签名**: `fn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!void`

**用途**: 策略初始化，在回测开始前调用一次。

**参数**:
- `ptr`: 策略实例指针
- `ctx`: 策略上下文（提供历史数据和辅助方法）

**使用场景**:
- 初始化策略状态
- 预计算需要的指标
- 验证参数有效性

**示例**:
\`\`\`zig
fn initFn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!void {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));

    // 重置状态
    self.in_position = false;
    self.trade_count = 0;

    // 预计算指标（可选）
    const sma = try ctx.getSMA(20);
    // 缓存或预处理...
}
\`\`\`

### onCandle()

**签名**: `fn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!?Signal`

**用途**: 处理每根新蜡烛，决定是否产生交易信号。

**参数**:
- `ptr`: 策略实例指针
- `ctx`: 策略上下文（包含当前蜡烛和历史数据）

**返回值**:
- `null`: 无交易信号
- `Signal`: 买入或卖出信号

**调用频率**: 每根蜡烛一次（回测模式）

**性能要求**: < 10ms

**示例**:
\`\`\`zig
fn onCandleFn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!?Signal {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));

    // 1. 获取指标
    const rsi = try ctx.getRSI(14);
    if (rsi.len == 0) return null;

    // 2. 计算交易逻辑
    const current_rsi = try rsi[rsi.len - 1].toFloat();

    // 3. 生成信号
    if (current_rsi < 30 and !self.in_position) {
        self.in_position = true;
        return Signal{
            .signal_type = .buy,
            .price = ctx.current_candle.close,
            .quantity = try Decimal.fromInt(1),
            .reason = "RSI oversold",
        };
    }

    return null;
}
\`\`\`

### getName() 和 getDescription()

**用途**: 提供策略的人类可读信息。

**示例**:
\`\`\`zig
fn getNameFn(ptr: *anyopaque) []const u8 {
    _ = ptr;
    return "My RSI Strategy";
}

fn getDescriptionFn(ptr: *anyopaque) []const u8 {
    _ = ptr;
    return "Simple RSI oversold/overbought mean reversion strategy";
}
\`\`\`

### deinit()

**用途**: 清理策略资源。

**重要**: 必须释放所有分配的内存，避免泄漏。

**示例**:
\`\`\`zig
fn deinitFn(ptr: *anyopaque) void {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));
    // 释放分配的内存
    if (self.cached_data) |data| {
        self.allocator.free(data);
    }
}
\`\`\`

## 完整实现模板

见 [examples/strategy_template.zig](../../examples/strategy_template.zig)
```

### 3. 最佳实践 (best-practices.md)

```markdown
# 策略开发最佳实践

## 1. 代码组织

### ✅ 推荐
\`\`\`zig
pub const MyStrategy = struct {
    // 1. Allocator (必需)
    allocator: std.mem.Allocator,

    // 2. 参数 (可配置)
    period: u32,
    threshold: f64,

    // 3. 状态 (运行时)
    in_position: bool,
    trade_count: u32,

    // 4. 缓存 (性能优化，可选)
    cached_indicators: ?[]Decimal,
};
\`\`\`

### ❌ 避免
\`\`\`zig
pub const MyStrategy = struct {
    // 混乱的顺序，难以维护
    in_position: bool,
    allocator: std.mem.Allocator,
    some_data: []u8,
    period: u32,
};
\`\`\`

## 2. 性能优化

### 缓存指标计算

**问题**: 每次调用 `ctx.getSMA(20)` 都会重新计算。

**解决方案**: 在 `init()` 中预计算，在 `onCandle()` 中增量更新。

\`\`\`zig
fn initFn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!void {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));
    // 预计算
    self.cached_sma = try ctx.getSMA(20);
}

fn onCandleFn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!?Signal {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));
    // 使用缓存
    const sma = self.cached_sma.?;
    // ...
}
\`\`\`

## 3. 常见陷阱

### 陷阱 1: 前瞻偏差 (Look-Ahead Bias)

**错误示例**:
\`\`\`zig
// ❌ 使用了未来数据！
const future_price = ctx.candles[ctx.candles.len - 1].high;
if (ctx.current_candle.close < future_price) {
    // 这个信号在实盘中无法执行
}
\`\`\`

**正确做法**:
\`\`\`zig
// ✅ 只使用当前和过去的数据
const prev_high = ctx.candles[ctx.candles.len - 2].high;
if (ctx.current_candle.close > prev_high) {
    // 可以安全使用
}
\`\`\`

### 陷阱 2: 数组越界

**错误示例**:
\`\`\`zig
// ❌ 未检查数组长度
const prev_close = ctx.candles[ctx.candles.len - 2].close;
\`\`\`

**正确做法**:
\`\`\`zig
// ✅ 始终检查长度
if (ctx.candles.len < 2) return null;
const prev_close = ctx.candles[ctx.candles.len - 2].close;
\`\`\`

### 陷阱 3: 内存泄漏

**错误示例**:
\`\`\`zig
// ❌ 分配的内存未释放
fn onCandleFn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!?Signal {
    const data = try allocator.alloc(u8, 100);
    // 忘记 defer allocator.free(data);
    return null;
}
\`\`\`

**正确做法**:
\`\`\`zig
// ✅ 使用 defer 立即释放
fn onCandleFn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!?Signal {
    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);
    // 使用 data...
    return null;
}
\`\`\`

## 4. 测试

### 单元测试模板

\`\`\`zig
test "MyStrategy - basic buy signal" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建策略
    var strategy = try MyStrategy.init(allocator, 14, 30, 70);
    defer strategy.deinit();

    // 创建测试数据
    var candles = try createTestCandles(allocator);
    defer allocator.free(candles);

    // 创建上下文
    var ctx = StrategyContext.init(allocator, candles);
    defer ctx.deinit();

    // 测试初始化
    try strategy.initFn(&strategy, &ctx);

    // 测试信号生成
    const signal = try strategy.onCandleFn(&strategy, &ctx);

    try testing.expect(signal != null);
    try testing.expect(signal.?.signal_type == .buy);
}
\`\`\`

## 5. 调试技巧

### 使用日志

\`\`\`zig
fn onCandleFn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!?Signal {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));

    const rsi = try ctx.getRSI(14);
    const current_rsi = try rsi[rsi.len - 1].toFloat();

    // 调试日志
    try self.logger.debug("RSI: {d:.2}, Threshold: {d:.2}", .{
        current_rsi,
        self.threshold,
    });

    // ...
}
\`\`\`

## 6. 参数选择

### 参数范围建议

| 指标 | 参数 | 最小值 | 默认值 | 最大值 | 说明 |
|------|------|-------|--------|-------|------|
| SMA  | period | 5 | 20 | 200 | 短期: 5-20, 长期: 50-200 |
| RSI  | period | 7 | 14 | 28 | 标准 14，激进 7，保守 28 |
| RSI  | oversold | 20 | 30 | 40 | 标准 30，激进 20 |
| RSI  | overbought | 60 | 70 | 80 | 标准 70，激进 80 |
| MACD | fast | 8 | 12 | 16 | 标准 12 |
| MACD | slow | 21 | 26 | 34 | 标准 26 |

### 参数优化提示

1. **先测试默认值**: 确保策略逻辑正确
2. **网格搜索**: 使用 `optimize` 命令
3. **Walk-Forward**: 避免过拟合
4. **多市场验证**: 测试不同币种和时间段
```

### 4. FAQ (faq.md)

```markdown
# 策略开发常见问题

## 入门问题

### Q1: 我需要多少 Zig 知识才能开发策略？

**A**: 基础即可。需要理解：
- 结构体和方法
- 错误处理 (`try`, `catch`)
- 内存管理 (`allocator`, `defer`)
- 可选类型 (`?T`)

参考 [Zig 快速入门](https://ziglang.org/learn/)。

### Q2: 如何选择第一个策略？

**A**: 推荐从简单的均值回归策略开始：
1. RSI 超买超卖
2. 布林带回归
3. 双均线交叉

这些策略逻辑简单，易于理解和调试。

### Q3: 回测结果很差怎么办？

**A**: 检查清单：
1. [ ] 策略逻辑是否正确？
2. [ ] 参数是否合理？
3. [ ] 是否有足够的交易次数（> 30）？
4. [ ] 手续费和滑点是否设置？
5. [ ] 时间周期是否匹配策略类型？

**不要过早优化**！先确保逻辑正确。

## 技术问题

### Q4: 如何访问前一根蜡烛的数据？

\`\`\`zig
// 当前蜡烛
const current = ctx.current_candle;

// 前一根蜡烛（注意检查长度）
if (ctx.candles.len < 2) return null;
const previous = ctx.candles[ctx.candles.len - 2];
\`\`\`

### Q5: 如何使用多个指标？

\`\`\`zig
fn onCandleFn(ptr: *anyopaque, ctx: *StrategyContext) anyerror!?Signal {
    // 获取多个指标
    const sma_20 = try ctx.getSMA(20);
    const rsi_14 = try ctx.getRSI(14);
    const macd = try ctx.getMACD(12, 26, 9);

    // 检查长度
    if (sma_20.len == 0 or rsi_14.len == 0) return null;

    // 组合使用
    const current_sma = sma_20[sma_20.len - 1];
    const current_rsi = try rsi_14[rsi_14.len - 1].toFloat();

    // 多重确认
    if (ctx.current_candle.close.gt(current_sma) and current_rsi < 30) {
        // 买入信号
    }
}
\`\`\`

### Q6: 如何实现止损止盈？

**方法 1**: 在策略中跟踪入场价格

\`\`\`zig
pub const MyStrategy = struct {
    // ...
    entry_price: ?Decimal,
    stop_loss_pct: f64,    // 2% = 0.02
    take_profit_pct: f64,  // 5% = 0.05

    fn onCandleFn(...) !?Signal {
        if (self.in_position) {
            const entry = self.entry_price.?;
            const current = ctx.current_candle.close;

            // 止损
            const stop_price = entry.mul(try Decimal.fromFloat(1 - self.stop_loss_pct));
            if (current.lte(stop_price)) {
                self.in_position = false;
                return Signal{ .signal_type = .sell, ... };
            }

            // 止盈
            const profit_price = entry.mul(try Decimal.fromFloat(1 + self.take_profit_pct));
            if (current.gte(profit_price)) {
                self.in_position = false;
                return Signal{ .signal_type = .sell, ... };
            }
        }
    }
};
\`\`\`

### Q7: 策略运行很慢怎么办？

**性能优化清单**:
1. [ ] 使用缓存避免重复计算指标
2. [ ] 减少内存分配（复用 buffer）
3. [ ] 使用性能分析器找到瓶颈
4. [ ] 考虑使用更简单的指标

\`\`\`bash
# 性能分析
zig build run -- backtest ... --profile
\`\`\`

## 调试问题

### Q8: 如何打印调试信息？

\`\`\`zig
// 使用 logger（推荐）
try self.logger.debug("RSI: {d:.2}", .{current_rsi});

// 使用 std.debug.print（仅开发）
std.debug.print("RSI: {d:.2}\n", .{current_rsi});
\`\`\`

### Q9: 如何检测内存泄漏？

\`\`\`bash
# 使用 GPA（General Purpose Allocator）
zig build test --summary all

# 查看输出中的内存泄漏报告
\`\`\`

在策略测试中：
\`\`\`zig
test "MyStrategy - no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) return error.MemoryLeak;
    }
    const allocator = gpa.allocator();

    // 测试策略...
}
\`\`\`

### Q10: 编译错误 "expected type '*MyStrategy', found '*anyopaque'" 怎么办？

**原因**: 类型转换错误。

**解决方案**: 使用 `@ptrCast` 和 `@alignCast`：

\`\`\`zig
// ❌ 错误
const self: *MyStrategy = ptr;

// ✅ 正确
const self: *MyStrategy = @ptrCast(@alignCast(ptr));
\`\`\`

## 回测问题

### Q11: 为什么回测没有产生任何交易？

**可能原因**:
1. 历史数据不足（检查 candles.len）
2. 指标需要的最小周期未满足
3. 信号条件太严格
4. 策略逻辑错误

**调试方法**:
\`\`\`zig
fn onCandleFn(...) !?Signal {
    try self.logger.debug("Candles: {}, RSI: {d:.2}", .{
        ctx.candles.len,
        current_rsi,
    });

    // 添加更多日志...
}
\`\`\`

### Q12: 回测结果与预期差异很大？

**检查项**:
1. 手续费设置（默认 0.1%）
2. 滑点设置（默认 0.05%）
3. 数据质量（是否有缺失或错误）
4. 时间范围（牛市vs熊市vs震荡）

### Q13: 如何比较多个策略？

\`\`\`bash
# 运行多个回测并导出结果
zigquant backtest --strategy dual_ma --config dual_ma.json --output results/dual_ma.json
zigquant backtest --strategy rsi --config rsi.json --output results/rsi.json

# 比较结果（使用外部工具或 v0.4.0 的对比功能）
\`\`\`

## 优化问题

### Q14: 参数优化需要多久？

取决于：
- 参数网格大小（组合数）
- 数据量（蜡烛数）
- CPU 核心数

**示例**:
- 2 个参数，各 10 个值 = 100 组合
- 8784 根蜡烛，8 核 CPU
- 预计: 2-5 分钟

### Q15: 如何避免过拟合？

**最佳实践**:
1. **Walk-Forward 验证**: 训练集 70%，测试集 30%
2. **多市场测试**: 测试不同币种
3. **样本外测试**: 用最新数据验证
4. **参数范围合理**: 避免极端值
5. **最小交易次数**: 至少 30 笔

### Q16: 优化后策略表现变差？

**原因**: 过拟合（overfitting）

**解决方案**:
1. 增加训练数据
2. 减少参数数量
3. 使用更保守的参数范围
4. 在不同市场阶段测试

## 实盘问题

### Q17: v0.4.0 支持实盘交易吗？

**A**: 不支持。实盘交易计划在 v0.5.0+。

当前可以：
- 回测历史数据
- 参数优化
- 模拟测试（Paper trading 在 v0.5.0）

### Q18: 如何准备实盘交易？

**准备清单**（v0.5.0 前）:
1. [ ] 充分回测（多市场，多时间段）
2. [ ] 参数优化和验证
3. [ ] 风险管理设置（止损止盈）
4. [ ] 资金管理策略
5. [ ] 监控和告警机制

### Q19: 回测盈利就能实盘赚钱吗？

**A**: 不一定！注意：
- 回测是历史数据，无法保证未来
- 实盘有延迟、滑点、执行风险
- 心理因素影响实盘表现
- 市场环境可能改变

**建议**: 先小资金测试，逐步增加。

## 其他问题

### Q20: 在哪里提问？

- GitHub Issues: https://github.com/davirain/zigQuant/issues
- 文档: `docs/guides/strategy/`
- 示例代码: `examples/strategies/`

### Q21: 如何贡献策略？

欢迎提交 PR！要求：
1. 完整的策略代码
2. JSON 配置文件
3. 回测结果文档
4. 单元测试
5. 策略说明文档

### Q22: 有策略模板吗？

是的！查看：
- `examples/strategy_template.zig`
- `docs/guides/strategy/quickstart.md`
```

---

## ✅ 完成标准

- [ ] 所有 9 个文档文件创建完成
- [ ] 5 个示例策略代码完成
- [ ] 所有代码示例可运行
- [ ] FAQ 至少 20 个问题
- [ ] 文档经过审查（清晰、准确）
- [ ] 所有链接有效
- [ ] 代码注释详细
- [ ] 无拼写和语法错误

---

**创建时间**: 2024-12-26
**最后更新**: 2024-12-26
**作者**: Claude (Sonnet 4.5)
