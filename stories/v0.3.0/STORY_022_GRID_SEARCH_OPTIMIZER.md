# Story 022: GridSearchOptimizer 网格搜索优化器

**Story ID**: 022
**Version**: v0.3.0
**Week**: Week 3
**Priority**: P1
**Estimated Effort**: 2 天
**Status**: 待开始

---

## 📋 概述

### 标题
GridSearchOptimizer 网格搜索优化器

### 描述
实现参数优化器，自动搜索策略的最佳参数组合。通过遍历参数空间，使用回测引擎评估每个参数组合的表现，找出使目标指标（如夏普比率、盈亏比等）最优的参数配置。

### 业务价值
- **自动化优化**: 减少手动调参时间，提高策略开发效率
- **参数验证**: 通过系统化搜索验证参数稳健性
- **性能提升**: 找到最优参数组合，提高策略表现
- **避免过拟合**: 提供交叉验证能力，防止参数过度优化

### 用户故事
作为策略开发者，我希望能够自动搜索策略的最佳参数，这样我就可以快速找到最优配置而不需要手动尝试大量参数组合。

---

## 🎯 目标与范围

### 功能目标
1. ✅ 实现网格搜索算法，遍历所有参数组合
2. ✅ 支持多种参数类型（整数、小数、布尔值）
3. ✅ 集成回测引擎，评估每个参数组合
4. ✅ 支持多种优化目标（夏普比率、盈亏比、胜率等）
5. ✅ 提供优化进度追踪和结果报告
6. ✅ 支持并行优化（可选）

### 非功能目标
- **性能**: 单个回测完成时间 < 100ms
- **内存安全**: 零内存泄漏
- **可扩展**: 支持自定义优化算法
- **可测试**: 单元测试覆盖率 > 85%

### 范围界定

#### 包含内容
- 网格搜索优化器核心实现
- 参数组合生成器
- 优化结果分析和排序
- 优化器类型定义
- 完整的单元测试

#### 不包含内容
- 遗传算法优化器（留待后续版本）
- 贝叶斯优化（留待后续版本）
- 分布式优化（留待后续版本）
- GUI 可视化界面

---

## 📝 详细任务分解

### Task 1: 创建优化器类型定义 (2小时)

**文件**: `src/optimizer/types.zig`

**实现内容**:
```zig
/// 优化器公共类型定义

/// 参数范围定义
pub const ParameterRange = union(enum) {
    integer: struct {
        min: i64,
        max: i64,
        step: i64,
    },
    decimal: struct {
        min: Decimal,
        max: Decimal,
        step: Decimal,
    },
    boolean: void,
    discrete: []const ParameterValue,
};

/// 参数组合
pub const ParameterSet = struct {
    values: std.StringHashMap(ParameterValue),

    pub fn init(allocator: std.mem.Allocator) ParameterSet;
    pub fn deinit(self: *ParameterSet) void;
    pub fn set(self: *ParameterSet, name: []const u8, value: ParameterValue) !void;
    pub fn get(self: *const ParameterSet, name: []const u8) ?ParameterValue;
};

/// 优化目标
pub const OptimizationObjective = enum {
    maximize_sharpe_ratio,
    maximize_profit_factor,
    maximize_win_rate,
    minimize_max_drawdown,
    maximize_net_profit,
    custom,
};

/// 优化结果
pub const OptimizationResult = struct {
    best_params: ParameterSet,
    best_score: f64,
    all_results: []BacktestResult,
    total_combinations: u32,
    elapsed_time_ms: u64,

    pub fn deinit(self: *OptimizationResult) void;
    pub fn getRankedResults(self: *const OptimizationResult, top_n: u32) []BacktestResult;
};

/// 优化配置
pub const OptimizationConfig = struct {
    objective: OptimizationObjective,
    backtest_config: BacktestConfig,
    parameters: []StrategyParameter,
    max_combinations: ?u32,  // 限制最大组合数
    enable_parallel: bool,   // 是否启用并行
};
```

**验收标准**:
- [ ] 所有类型定义完整
- [ ] 类型有完整的文档注释
- [ ] ParameterSet 提供便捷的访问方法
- [ ] 编译通过，无警告

---

### Task 2: 实现参数组合生成器 (3小时)

**文件**: `src/optimizer/grid_search.zig` (Part 1)

**实现内容**:
```zig
/// 参数组合生成器
pub const CombinationGenerator = struct {
    allocator: std.mem.Allocator,
    parameters: []const StrategyParameter,

    pub fn init(
        allocator: std.mem.Allocator,
        parameters: []const StrategyParameter,
    ) CombinationGenerator;

    pub fn deinit(self: *CombinationGenerator) void;

    /// 生成所有参数组合
    pub fn generateAll(self: *CombinationGenerator) ![]ParameterSet {
        // 1. 计算总组合数
        const total = try self.countCombinations();

        // 2. 生成笛卡尔积
        var combinations = try self.allocator.alloc(ParameterSet, total);

        // 3. 递归生成组合
        try self.generateRecursive(combinations, 0, &.{});

        return combinations;
    }

    /// 计算总组合数
    fn countCombinations(self: *const CombinationGenerator) !u32 {
        var count: u32 = 1;
        for (self.parameters) |param| {
            if (!param.optimize) continue;

            const param_count = switch (param.range.?) {
                .integer => |r| @divTrunc(r.max - r.min, r.step) + 1,
                .decimal => |r| {
                    const steps = try r.max.sub(r.min).div(r.step);
                    return @intFromFloat(steps.toFloat() + 1.0);
                },
                .boolean => 2,
                .discrete => |d| d.len,
            };
            count *= param_count;
        }
        return count;
    }

    /// 递归生成组合
    fn generateRecursive(
        self: *CombinationGenerator,
        combinations: []ParameterSet,
        param_index: usize,
        current_values: []const ParameterValue,
    ) !void {
        // 实现递归笛卡尔积生成
    }
};
```

**验收标准**:
- [ ] 能正确生成所有参数组合
- [ ] 支持整数、小数、布尔、离散值类型
- [ ] 笛卡尔积计算正确
- [ ] 通过单元测试验证组合数量和内容

---

### Task 3: 实现网格搜索优化器核心 (4小时)

**文件**: `src/optimizer/grid_search.zig` (Part 2)

**实现内容**:
```zig
/// 网格搜索优化器
pub const GridSearchOptimizer = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    backtest_engine: *BacktestEngine,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        backtest_engine: *BacktestEngine,
    ) GridSearchOptimizer {
        return .{
            .allocator = allocator,
            .logger = logger,
            .backtest_engine = backtest_engine,
        };
    }

    pub fn deinit(self: *GridSearchOptimizer) void {
        _ = self;
    }

    /// 执行优化
    pub fn optimize(
        self: *GridSearchOptimizer,
        strategy_factory: *const fn (ParameterSet) anyerror!IStrategy,
        config: OptimizationConfig,
    ) !OptimizationResult {
        const start_time = std.time.milliTimestamp();

        // 1. 生成参数组合
        self.logger.info("Generating parameter combinations...", .{});
        var generator = CombinationGenerator.init(self.allocator, config.parameters);
        defer generator.deinit();

        const combinations = try generator.generateAll();
        defer {
            for (combinations) |*combo| combo.deinit();
            self.allocator.free(combinations);
        }

        self.logger.info("Total combinations: {d}", .{combinations.len});

        // 2. 遍历所有组合并回测
        var results = try self.allocator.alloc(BacktestResult, combinations.len);

        for (combinations, 0..) |params, i| {
            // 进度日志
            if (i % 10 == 0) {
                self.logger.info("Progress: {d}/{d} ({d:.1}%)",
                    .{i, combinations.len, @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(combinations.len)) * 100.0});
            }

            // 创建策略实例
            var strategy = try strategy_factory(params);
            defer strategy.deinit();

            // 运行回测
            results[i] = try self.backtest_engine.run(strategy, config.backtest_config);
            results[i].params = params;
        }

        // 3. 找出最优结果
        const best_index = try self.findBestResult(results, config.objective);

        const elapsed = std.time.milliTimestamp() - start_time;

        return OptimizationResult{
            .best_params = try combinations[best_index].clone(self.allocator),
            .best_score = try self.scoreResult(results[best_index], config.objective),
            .all_results = results,
            .total_combinations = @intCast(combinations.len),
            .elapsed_time_ms = @intCast(elapsed),
        };
    }

    /// 根据优化目标找出最优结果
    fn findBestResult(
        self: *GridSearchOptimizer,
        results: []const BacktestResult,
        objective: OptimizationObjective,
    ) !usize {
        var best_index: usize = 0;
        var best_score = try self.scoreResult(results[0], objective);

        for (results[1..], 1..) |result, i| {
            const score = try self.scoreResult(result, objective);
            if (score > best_score) {
                best_score = score;
                best_index = i;
            }
        }

        return best_index;
    }

    /// 计算结果得分
    fn scoreResult(
        self: *GridSearchOptimizer,
        result: BacktestResult,
        objective: OptimizationObjective,
    ) !f64 {
        _ = self;
        return switch (objective) {
            .maximize_sharpe_ratio => result.sharpe_ratio,
            .maximize_profit_factor => result.profit_factor,
            .maximize_win_rate => result.win_rate,
            .minimize_max_drawdown => 1.0 - result.max_drawdown,
            .maximize_net_profit => result.net_profit.toFloat(),
            .custom => unreachable,
        };
    }
};
```

**验收标准**:
- [ ] 能正确遍历所有参数组合
- [ ] 集成回测引擎正常工作
- [ ] 根据优化目标正确选择最优结果
- [ ] 提供进度日志输出
- [ ] 正确处理内存分配和释放

---

### Task 4: 添加优化结果分析功能 (2小时)

**文件**: `src/optimizer/grid_search.zig` (Part 3)

**实现内容**:
```zig
/// 优化结果分析器
pub const ResultAnalyzer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResultAnalyzer {
        return .{ .allocator = allocator };
    }

    /// 获取排名前 N 的结果
    pub fn getTopResults(
        self: *ResultAnalyzer,
        results: []BacktestResult,
        objective: OptimizationObjective,
        top_n: u32,
    ) ![]BacktestResult {
        // 1. 按得分排序
        const sorted = try self.sortByObjective(results, objective);

        // 2. 返回前 N 个
        const n = @min(top_n, sorted.len);
        return sorted[0..n];
    }

    /// 生成优化报告
    pub fn generateReport(
        self: *ResultAnalyzer,
        result: OptimizationResult,
    ) ![]const u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("=== Optimization Report ===\n", .{});
        try writer.print("Total Combinations: {d}\n", .{result.total_combinations});
        try writer.print("Elapsed Time: {d}ms\n", .{result.elapsed_time_ms});
        try writer.print("\n=== Best Parameters ===\n", .{});

        // 输出最优参数
        var iter = result.best_params.values.iterator();
        while (iter.next()) |entry| {
            try writer.print("{s}: {any}\n", .{entry.key_ptr.*, entry.value_ptr.*});
        }

        try writer.print("\n=== Best Result ===\n", .{});
        try writer.print("Score: {d:.4}\n", .{result.best_score});
        // ... 更多指标输出

        return buf.toOwnedSlice();
    }

    /// 参数敏感性分析
    pub fn analyzeSensitivity(
        self: *ResultAnalyzer,
        results: []BacktestResult,
        param_name: []const u8,
    ) !SensitivityAnalysis {
        // 分析某个参数对结果的影响
        // 返回参数值与得分的关系
    }

    fn sortByObjective(
        self: *ResultAnalyzer,
        results: []BacktestResult,
        objective: OptimizationObjective,
    ) ![]BacktestResult {
        const sorted = try self.allocator.dupe(BacktestResult, results);

        // 自定义排序函数
        std.sort.sort(BacktestResult, sorted, objective, comptime struct {
            fn lessThan(obj: OptimizationObjective, a: BacktestResult, b: BacktestResult) bool {
                const score_a = scoreForObjective(a, obj);
                const score_b = scoreForObjective(b, obj);
                return score_a > score_b;  // 降序
            }
        }.lessThan);

        return sorted;
    }
};

pub const SensitivityAnalysis = struct {
    param_name: []const u8,
    values: []f64,
    scores: []f64,
    correlation: f64,
};
```

**验收标准**:
- [ ] 能正确排序和筛选结果
- [ ] 报告格式清晰易读
- [ ] 敏感性分析计算正确
- [ ] 通过单元测试验证

---

### Task 5: 编写完整单元测试 (3小时)

**文件**: `src/optimizer/grid_search_test.zig`

**测试内容**:
```zig
const std = @import("std");
const testing = std.testing;
const GridSearchOptimizer = @import("grid_search.zig").GridSearchOptimizer;
const CombinationGenerator = @import("grid_search.zig").CombinationGenerator;

test "CombinationGenerator: 生成整数参数组合" {
    const allocator = testing.allocator;

    const params = [_]StrategyParameter{
        .{
            .name = "fast_period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .range = .{ .integer = .{ .min = 5, .max = 15, .step = 5 } },
            .optimize = true,
        },
        .{
            .name = "slow_period",
            .type = .integer,
            .default_value = .{ .integer = 20 },
            .range = .{ .integer = .{ .min = 20, .max = 30, .step = 5 } },
            .optimize = true,
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    defer generator.deinit();

    const combinations = try generator.generateAll();
    defer {
        for (combinations) |*combo| combo.deinit();
        allocator.free(combinations);
    }

    // 应该有 3 * 3 = 9 种组合
    try testing.expectEqual(@as(usize, 9), combinations.len);
}

test "CombinationGenerator: 混合参数类型" {
    // 测试整数、小数、布尔值混合
}

test "GridSearchOptimizer: 完整优化流程" {
    const allocator = testing.allocator;

    // 创建模拟策略工厂
    const strategy_factory = struct {
        fn create(params: ParameterSet) !IStrategy {
            // 返回测试策略
        }
    }.create;

    var engine = try BacktestEngine.init(allocator, /* ... */);
    defer engine.deinit();

    var optimizer = GridSearchOptimizer.init(allocator, logger, &engine);
    defer optimizer.deinit();

    const config = OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = /* ... */,
        .parameters = /* ... */,
        .max_combinations = null,
        .enable_parallel = false,
    };

    var result = try optimizer.optimize(strategy_factory, config);
    defer result.deinit();

    try testing.expect(result.best_score > 0.0);
    try testing.expect(result.total_combinations > 0);
}

test "GridSearchOptimizer: 不同优化目标" {
    // 测试不同优化目标得到不同结果
}

test "ResultAnalyzer: 排序功能" {
    // 测试结果排序
}

test "ResultAnalyzer: 报告生成" {
    // 测试报告生成
}

test "优化器内存安全" {
    // 使用 GeneralPurposeAllocator 检测内存泄漏
}
```

**验收标准**:
- [ ] 所有测试用例通过
- [ ] 测试覆盖率 > 85%
- [ ] 无内存泄漏
- [ ] 边界条件测试完整

---

### Task 6: 集成测试和文档 (2小时)

**集成测试**: `tests/integration/optimizer_integration_test.zig`

**测试场景**:
```zig
test "集成测试: 双均线策略参数优化" {
    // 1. 准备历史数据
    // 2. 定义参数空间
    // 3. 运行优化
    // 4. 验证找到有效的最优参数
}

test "集成测试: 多策略对比优化" {
    // 优化并对比多个策略的表现
}
```

**文档更新**:
- 更新 `/home/davirain/dev/zigQuant/docs/features/backtest/optimizer.md`
- 添加使用示例
- 添加参数优化最佳实践
- 添加 API 参考

**验收标准**:
- [ ] 集成测试通过
- [ ] 文档完整准确
- [ ] 提供完整使用示例
- [ ] API 参考完整

---

## ✅ 验收标准

### 功能验收
- [ ] 优化器能正确生成所有参数组合
- [ ] 集成回测引擎正常工作
- [ ] 支持多种优化目标
- [ ] 能找到最优参数组合
- [ ] 提供优化进度和结果报告

### 代码质量
- [ ] 代码符合项目编码规范
- [ ] 所有公共 API 有文档注释
- [ ] 无编译警告
- [ ] 通过 `zig fmt` 格式检查

### 测试验收
- [ ] 单元测试覆盖率 > 85%
- [ ] 所有单元测试通过
- [ ] 集成测试通过
- [ ] 无内存泄漏（GeneralPurposeAllocator 验证）

### 性能验收
- [ ] 单个回测完成时间 < 100ms
- [ ] 100 个组合优化时间 < 10秒
- [ ] 内存使用合理

### 文档验收
- [ ] API 文档完整
- [ ] 使用示例清晰
- [ ] 最佳实践说明完整

---

## 🔗 依赖关系

### 依赖项
- **Story 020**: BacktestEngine 回测引擎核心（必须完成）
- **Story 021**: PerformanceAnalyzer 性能分析（必须完成）
- **Story 013**: IStrategy 接口定义（必须完成）
- `src/types/decimal.zig`: Decimal 类型
- `src/logger/`: 日志系统

### 被依赖项
- **Story 023**: CLI 策略命令集成（依赖本 Story）
- **Story 024**: 示例和文档（依赖本 Story）

---

## 🧪 测试策略

### 单元测试
- **组合生成器测试**
  - 整数参数组合生成
  - 小数参数组合生成
  - 布尔参数组合生成
  - 离散值参数组合生成
  - 混合参数类型组合
  - 边界条件测试

- **优化器核心测试**
  - 完整优化流程
  - 不同优化目标
  - 策略工厂集成
  - 进度追踪

- **结果分析器测试**
  - 结果排序
  - 报告生成
  - 敏感性分析

### 集成测试
- 双均线策略参数优化
- RSI 策略参数优化
- 多策略对比优化
- 大规模组合优化（性能测试）

### 性能测试
- 100 组合优化时间
- 1000 组合优化时间
- 内存使用分析
- 并发优化测试（可选）

### 内存测试
- 使用 GeneralPurposeAllocator 检测泄漏
- 长时间运行稳定性测试

---

## 📚 参考资料

### 外部参考
- [Freqtrade Hyperopt](https://www.freqtrade.io/en/stable/hyperopt/): 参数优化参考
- [Backtrader Optimization](https://www.backtrader.com/docu/optimization/): 回测优化
- [Grid Search Algorithm](https://en.wikipedia.org/wiki/Hyperparameter_optimization#Grid_search): 网格搜索算法

### 内部参考
- `docs/v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md`: 设计文档
- `docs/features/backtest/engine.md`: 回测引擎文档
- `docs/features/strategy/interface.md`: 策略接口文档

---

## 📊 进度追踪

### 检查清单
- [ ] Task 1: 创建优化器类型定义（2小时）
- [ ] Task 2: 实现参数组合生成器（3小时）
- [ ] Task 3: 实现网格搜索优化器核心（4小时）
- [ ] Task 4: 添加优化结果分析功能（2小时）
- [ ] Task 5: 编写完整单元测试（3小时）
- [ ] Task 6: 集成测试和文档（2小时）

### 总计工作量
- **开发时间**: 11 小时
- **测试时间**: 5 小时
- **总计**: 16 小时（约 2 天）

---

## 🔄 后续改进

### v0.4.0 可能的增强
- [ ] 遗传算法优化器
- [ ] 贝叶斯优化器
- [ ] 并行优化支持
- [ ] Walk-forward 优化
- [ ] 交叉验证支持
- [ ] 过拟合检测

---

## 📝 备注

### 技术债务
- 当前版本不支持并行优化，大量组合可能耗时较长
- 未实现参数重要性分析
- 缺少可视化支持

### 风险与缓解
- **风险**: 参数空间过大导致优化时间过长
  - **缓解**: 添加 `max_combinations` 限制，提供采样优化选项

- **风险**: 过拟合问题
  - **缓解**: 文档中提供交叉验证建议，计划后续版本支持

---

**创建时间**: 2025-12-25
**预计开始**: Week 3 Day 1
**预计完成**: Week 3 Day 2
**实际开始**:
**实际完成**:

---

Generated with [Claude Code](https://claude.com/claude-code)
