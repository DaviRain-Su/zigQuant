# Story: GridSearchOptimizer 增强和 Walk-Forward 分析

**ID**: `STORY-022-ENHANCED`
**版本**: `v0.4.0`
**创建日期**: 2024-12-26
**状态**: 📋 待开始
**优先级**: P1 (高优先级)
**预计工时**: 3-4 天
**依赖**: Story 022 (v0.3.0 GridSearchOptimizer 基础版本)

---

## 📋 需求描述

### 用户故事
作为策略开发者，我希望优化器能够防止过拟合并提供更准确的参数评估，以便我可以找到在实盘中真正有效的参数配置。

### 背景
v0.3.0 实现了基础的网格搜索优化器，但缺少防止过拟合的机制。v0.4.0 需要增强以下功能：

**v0.3.0 已实现**:
- ✅ 基础网格搜索
- ✅ 参数组合生成
- ✅ 并行回测执行
- ✅ 多种优化目标
- ✅ 结果排序和报告

**v0.4.0 新增功能**:
- 🆕 Walk-Forward 分析（滚动验证）
- 🆕 更多优化目标（Sortino、Calmar 等）
- 🆕 过拟合检测指标
- 🆕 参数稳定性分析
- 🆕 优化结果可视化（可选）
- 🆕 自适应网格搜索（可选）

参考平台：
- **Backtrader**: Walk-Forward 分析
- **QuantConnect**: 样本外验证
- **Optuna**: 自适应优化

### 范围
- **包含**:
  - Walk-Forward 分析核心功能
  - 训练集/测试集分割
  - 滚动窗口验证
  - 过拟合检测指标
  - 新增优化目标
  - 参数稳定性报告

- **不包含**:
  - 遗传算法优化（v0.5.0+）
  - 贝叶斯优化（v0.5.0+）
  - 机器学习参数优化（v1.0+）
  - Web 可视化界面（v1.0）

---

## 🎯 验收标准

### Walk-Forward 分析

- [ ] **AC1**: 训练/测试集分割实现
  - 支持固定比例分割（如 70%/30%）
  - 支持滚动窗口分割
  - 支持多折交叉验证

- [ ] **AC2**: Walk-Forward 核心算法实现
  - 在训练集上优化参数
  - 在测试集上验证参数
  - 记录训练和测试表现
  - 计算过拟合指标

- [ ] **AC3**: 滚动窗口验证实现
  - 支持固定窗口大小
  - 支持扩展窗口
  - 支持锚定窗口
  - 可配置窗口步长

### 新增优化目标

- [ ] **AC4**: Sortino Ratio 实现
  - 只考虑下行波动
  - 使用最小可接受收益率
  - 与 Sharpe 对比测试

- [ ] **AC5**: Calmar Ratio 实现
  - 年化收益 / 最大回撤
  - 适合长期策略
  - 计算公式正确

- [ ] **AC6**: 更多风险指标
  - Omega Ratio
  - Tail Ratio
  - 信息比率 (Information Ratio)

### 过拟合检测

- [ ] **AC7**: 过拟合指标计算
  - Training/Testing 表现差异
  - 参数敏感度分析
  - 稳定性得分
  - 过拟合概率估计

- [ ] **AC8**: 参数稳定性分析
  - 参数变化对结果的影响
  - 敏感参数识别
  - 参数鲁棒性报告

### 性能和质量

- [ ] **AC9**: 性能优化
  - Walk-Forward 并行化
  - 缓存中间结果
  - 内存使用优化

- [ ] **AC10**: 单元测试覆盖率 > 85%
  - Walk-Forward 算法测试
  - 分割策略测试
  - 过拟合检测测试

- [ ] **AC11**: 文档完整
  - Walk-Forward 使用指南
  - 过拟合防止最佳实践
  - 配置示例

---

## 🔧 技术设计

### 架构概览

```
src/optimizer/
    ├── types.zig               # 已存在
    ├── grid_search.zig         # 已存在，需增强
    ├── combination.zig         # 已存在
    ├── result.zig              # 已存在
    ├── walk_forward.zig        # 新增 ✨
    ├── data_split.zig          # 新增 ✨
    ├── overfitting_detector.zig # 新增 ✨
    └── objectives.zig          # 增强，新增指标 ✨

docs/features/optimizer/
    ├── README.md               # 更新
    ├── walk-forward.md         # 新增 ✨
    └── overfitting-prevention.md # 新增 ✨
```

### 数据结构

#### 1. Walk-Forward 分析器 (walk_forward.zig)

```zig
const std = @import("std");
const zigQuant = @import("../root.zig");

const BacktestEngine = zigQuant.BacktestEngine;
const BacktestResult = zigQuant.BacktestResult;
const GridSearchOptimizer = zigQuant.GridSearchOptimizer;
const OptimizationConfig = zigQuant.OptimizationConfig;

/// Walk-Forward 分割策略
pub const SplitStrategy = enum {
    /// 固定比例分割 (如 70/30)
    fixed_ratio,

    /// 滚动窗口
    rolling_window,

    /// 扩展窗口
    expanding_window,

    /// 锚定窗口
    anchored_window,
};

/// Walk-Forward 配置
pub const WalkForwardConfig = struct {
    /// 分割策略
    split_strategy: SplitStrategy,

    /// 训练集比例 (0.0-1.0)
    train_ratio: f64,

    /// 测试集比例 (0.0-1.0)
    test_ratio: f64,

    /// 滚动窗口步长（K线数）
    step_size: ?usize,

    /// 最小训练集大小
    min_train_size: usize,

    /// 最小测试集大小
    min_test_size: usize,

    /// 是否重新优化（每个窗口）
    reoptimize_each_window: bool,

    pub fn init(strategy: SplitStrategy, train_ratio: f64) WalkForwardConfig {
        return .{
            .split_strategy = strategy,
            .train_ratio = train_ratio,
            .test_ratio = 1.0 - train_ratio,
            .step_size = null,
            .min_train_size = 100,
            .min_test_size = 30,
            .reoptimize_each_window = true,
        };
    }

    pub fn validate(self: *const WalkForwardConfig) !void {
        if (self.train_ratio <= 0.0 or self.train_ratio >= 1.0) {
            return error.InvalidTrainRatio;
        }
        if (self.train_ratio + self.test_ratio > 1.0) {
            return error.InvalidRatioSum;
        }
    }
};

/// Walk-Forward 结果
pub const WalkForwardResult = struct {
    /// 窗口数量
    num_windows: usize,

    /// 每个窗口的结果
    window_results: []WindowResult,

    /// 总体统计
    overall_stats: OverallStats,

    /// 过拟合指标
    overfitting_metrics: OverfittingMetrics,

    pub fn deinit(self: *WalkForwardResult, allocator: std.mem.Allocator) void {
        for (self.window_results) |*result| {
            result.deinit(allocator);
        }
        allocator.free(self.window_results);
    }
};

/// 单个窗口结果
pub const WindowResult = struct {
    /// 窗口编号
    window_id: usize,

    /// 训练集时间范围
    train_start: Timestamp,
    train_end: Timestamp,

    /// 测试集时间范围
    test_start: Timestamp,
    test_end: Timestamp,

    /// 最优参数（在训练集上）
    best_params: ParameterSet,

    /// 训练集表现
    train_metrics: PerformanceMetrics,

    /// 测试集表现
    test_metrics: PerformanceMetrics,

    /// 过拟合程度
    overfitting_score: f64,

    pub fn deinit(self: *WindowResult, allocator: std.mem.Allocator) void {
        self.best_params.deinit();
    }
};

/// 总体统计
pub const OverallStats = struct {
    /// 平均训练表现
    avg_train_sharpe: f64,
    avg_train_return: f64,

    /// 平均测试表现
    avg_test_sharpe: f64,
    avg_test_return: f64,

    /// 表现一致性
    consistency_score: f64,

    /// 参数稳定性
    param_stability: f64,
};

/// Walk-Forward 分析器
pub const WalkForwardAnalyzer = struct {
    allocator: std.mem.Allocator,
    config: WalkForwardConfig,
    optimizer: *GridSearchOptimizer,

    pub fn init(
        allocator: std.mem.Allocator,
        config: WalkForwardConfig,
        optimizer: *GridSearchOptimizer,
    ) !WalkForwardAnalyzer {
        try config.validate();

        return .{
            .allocator = allocator,
            .config = config,
            .optimizer = optimizer,
        };
    }

    pub fn deinit(self: *WalkForwardAnalyzer) void {
        _ = self;
    }

    /// 运行 Walk-Forward 分析
    pub fn run(
        self: *WalkForwardAnalyzer,
        data: []const Candle,
        strategy_factory: anytype,
    ) !WalkForwardResult {
        // 1. 数据分割
        const windows = try self.splitData(data);
        defer self.allocator.free(windows);

        var window_results = try self.allocator.alloc(WindowResult, windows.len);
        errdefer self.allocator.free(window_results);

        // 2. 对每个窗口执行优化和验证
        for (windows, 0..) |window, i| {
            try self.logger.info("Processing window {}/{}", .{i + 1, windows.len});

            // 在训练集上优化
            const train_result = try self.optimizer.optimize(
                window.train_data,
                strategy_factory,
            );
            defer train_result.deinit();

            // 在测试集上验证
            const test_result = try self.validateOnTestSet(
                window.test_data,
                train_result.best_params,
                strategy_factory,
            );
            defer test_result.deinit();

            // 计算过拟合指标
            const overfitting_score = try self.calculateOverfitting(
                train_result,
                test_result,
            );

            // 保存窗口结果
            window_results[i] = WindowResult{
                .window_id = i,
                .train_start = window.train_start,
                .train_end = window.train_end,
                .test_start = window.test_start,
                .test_end = window.test_end,
                .best_params = try train_result.best_params.clone(),
                .train_metrics = train_result.metrics,
                .test_metrics = test_result.metrics,
                .overfitting_score = overfitting_score,
            };
        }

        // 3. 计算总体统计
        const overall_stats = try self.calculateOverallStats(window_results);

        // 4. 计算过拟合指标
        const overfitting_metrics = try self.detectOverfitting(window_results);

        return WalkForwardResult{
            .num_windows = windows.len,
            .window_results = window_results,
            .overall_stats = overall_stats,
            .overfitting_metrics = overfitting_metrics,
        };
    }

    fn splitData(self: *WalkForwardAnalyzer, data: []const Candle) ![]DataWindow {
        return switch (self.config.split_strategy) {
            .fixed_ratio => try self.splitFixedRatio(data),
            .rolling_window => try self.splitRollingWindow(data),
            .expanding_window => try self.splitExpandingWindow(data),
            .anchored_window => try self.splitAnchoredWindow(data),
        };
    }

    fn splitFixedRatio(self: *WalkForwardAnalyzer, data: []const Candle) ![]DataWindow {
        const train_size = @as(usize, @intFromFloat(
            @as(f64, @floatFromInt(data.len)) * self.config.train_ratio
        ));

        if (train_size < self.config.min_train_size) {
            return error.InsufficientTrainData;
        }

        if (data.len - train_size < self.config.min_test_size) {
            return error.InsufficientTestData;
        }

        var windows = try self.allocator.alloc(DataWindow, 1);
        windows[0] = .{
            .train_data = data[0..train_size],
            .test_data = data[train_size..],
            .train_start = data[0].timestamp,
            .train_end = data[train_size - 1].timestamp,
            .test_start = data[train_size].timestamp,
            .test_end = data[data.len - 1].timestamp,
        };

        return windows;
    }

    fn splitRollingWindow(self: *WalkForwardAnalyzer, data: []const Candle) ![]DataWindow {
        // 滚动窗口实现
        const window_size = @as(usize, @intFromFloat(
            @as(f64, @floatFromInt(data.len)) * self.config.train_ratio
        ));
        const step = self.config.step_size orelse window_size / 4;

        const num_windows = (data.len - window_size) / step + 1;
        var windows = try self.allocator.alloc(DataWindow, num_windows);

        for (windows, 0..) |*window, i| {
            const start = i * step;
            const train_end = start + window_size;
            const test_end = @min(train_end + step, data.len);

            window.* = .{
                .train_data = data[start..train_end],
                .test_data = data[train_end..test_end],
                .train_start = data[start].timestamp,
                .train_end = data[train_end - 1].timestamp,
                .test_start = data[train_end].timestamp,
                .test_end = data[test_end - 1].timestamp,
            };
        }

        return windows;
    }
};

const DataWindow = struct {
    train_data: []const Candle,
    test_data: []const Candle,
    train_start: Timestamp,
    train_end: Timestamp,
    test_start: Timestamp,
    test_end: Timestamp,
};
```

#### 2. 过拟合检测器 (overfitting_detector.zig)

```zig
/// 过拟合指标
pub const OverfittingMetrics = struct {
    /// 训练/测试表现差异
    train_test_gap: f64,

    /// 参数敏感度
    param_sensitivity: f64,

    /// 稳定性得分 (0-1, 越高越稳定)
    stability_score: f64,

    /// 过拟合概率 (0-1)
    overfitting_probability: f64,

    /// 是否可能过拟合
    is_likely_overfitting: bool,
};

pub const OverfittingDetector = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) OverfittingDetector {
        return .{ .allocator = allocator };
    }

    /// 检测过拟合
    pub fn detect(
        self: *OverfittingDetector,
        window_results: []const WindowResult,
    ) !OverfittingMetrics {
        // 1. 计算训练/测试表现差异
        const train_test_gap = try self.calculateTrainTestGap(window_results);

        // 2. 计算参数敏感度
        const param_sensitivity = try self.calculateParamSensitivity(window_results);

        // 3. 计算稳定性得分
        const stability_score = try self.calculateStability(window_results);

        // 4. 估计过拟合概率
        const overfitting_prob = try self.estimateOverfittingProbability(
            train_test_gap,
            param_sensitivity,
            stability_score,
        );

        return OverfittingMetrics{
            .train_test_gap = train_test_gap,
            .param_sensitivity = param_sensitivity,
            .stability_score = stability_score,
            .overfitting_probability = overfitting_prob,
            .is_likely_overfitting = overfitting_prob > 0.7,
        };
    }

    fn calculateTrainTestGap(
        self: *OverfittingDetector,
        window_results: []const WindowResult,
    ) !f64 {
        var total_gap: f64 = 0.0;

        for (window_results) |result| {
            const gap = result.train_metrics.sharpe_ratio - result.test_metrics.sharpe_ratio;
            total_gap += @abs(gap);
        }

        return total_gap / @as(f64, @floatFromInt(window_results.len));
    }

    fn calculateStability(
        self: *OverfittingDetector,
        window_results: []const WindowResult,
    ) !f64 {
        // 计算测试集表现的标准差
        var test_sharpes = try self.allocator.alloc(f64, window_results.len);
        defer self.allocator.free(test_sharpes);

        for (window_results, 0..) |result, i| {
            test_sharpes[i] = result.test_metrics.sharpe_ratio;
        }

        const mean = blk: {
            var sum: f64 = 0.0;
            for (test_sharpes) |s| sum += s;
            break :blk sum / @as(f64, @floatFromInt(test_sharpes.len));
        };

        const variance = blk: {
            var sum: f64 = 0.0;
            for (test_sharpes) |s| {
                const diff = s - mean;
                sum += diff * diff;
            }
            break :blk sum / @as(f64, @floatFromInt(test_sharpes.len));
        };

        const std_dev = @sqrt(variance);

        // 稳定性得分: 1 - (std_dev / mean)，归一化到 [0, 1]
        const stability = 1.0 - @min(1.0, std_dev / @max(0.1, @abs(mean)));
        return @max(0.0, stability);
    }
};
```

#### 3. 新增优化目标 (objectives.zig)

```zig
/// 扩展优化目标
pub const OptimizationObjective = enum {
    // v0.3.0 已有
    sharpe_ratio,
    total_return,
    profit_factor,
    win_rate,
    max_drawdown,
    net_profit,

    // v0.4.0 新增 ✨
    sortino_ratio,      // Sortino 比率
    calmar_ratio,       // Calmar 比率
    omega_ratio,        // Omega 比率
    tail_ratio,         // 尾部比率
    information_ratio,  // 信息比率
    stability,          // 稳定性得分

    pub fn calculate(
        self: OptimizationObjective,
        metrics: *const PerformanceMetrics,
    ) f64 {
        return switch (self) {
            .sharpe_ratio => metrics.sharpe_ratio,
            .total_return => metrics.total_return,
            .profit_factor => metrics.profit_factor,
            .win_rate => metrics.win_rate,
            .max_drawdown => -metrics.max_drawdown, // 负值，因为要最小化
            .net_profit => try metrics.net_profit.toFloat(),

            // 新增指标
            .sortino_ratio => metrics.sortino_ratio,
            .calmar_ratio => metrics.calmar_ratio,
            .omega_ratio => metrics.omega_ratio,
            .tail_ratio => metrics.tail_ratio,
            .information_ratio => metrics.information_ratio,
            .stability => metrics.stability_score,
        };
    }
};
```

---

## 📊 使用示例

### Walk-Forward 分析

```bash
# 使用 Walk-Forward 分析优化策略
zigquant optimize \
  --strategy dual_ma \
  --config examples/strategies/dual_ma_wf.json \
  --walk-forward \
  --train-ratio 0.7 \
  --window-type rolling \
  --output results/dual_ma_walk_forward.json
```

配置文件 `dual_ma_wf.json`:
```json
{
  "strategy": "dual_ma",
  "pair": {"base": "BTC", "quote": "USDT"},
  "timeframe": "1h",
  "parameters": {
    "ma_type": "sma"
  },
  "optimization": {
    "parameters": {
      "fast_period": {"min": 5, "max": 20, "step": 5},
      "slow_period": {"min": 20, "max": 50, "step": 10}
    },
    "objective": "sharpe_ratio",
    "walk_forward": {
      "enabled": true,
      "split_strategy": "rolling_window",
      "train_ratio": 0.7,
      "step_size": 1000,
      "min_train_size": 500,
      "min_test_size": 200
    }
  }
}
```

### 程序化使用

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 配置 Walk-Forward
    const wf_config = zigQuant.WalkForwardConfig{
        .split_strategy = .rolling_window,
        .train_ratio = 0.7,
        .test_ratio = 0.3,
        .step_size = 1000,
        .min_train_size = 500,
        .min_test_size = 200,
        .reoptimize_each_window = true,
    };

    // 2. 创建优化器
    var optimizer = try zigQuant.GridSearchOptimizer.init(
        allocator,
        opt_config,
    );
    defer optimizer.deinit();

    // 3. 创建 Walk-Forward 分析器
    var wf_analyzer = try zigQuant.WalkForwardAnalyzer.init(
        allocator,
        wf_config,
        &optimizer,
    );
    defer wf_analyzer.deinit();

    // 4. 运行分析
    const result = try wf_analyzer.run(candles, strategy_factory);
    defer result.deinit(allocator);

    // 5. 查看结果
    try logger.info("Windows: {}", .{result.num_windows});
    try logger.info("Avg Train Sharpe: {d:.2}", .{result.overall_stats.avg_train_sharpe});
    try logger.info("Avg Test Sharpe: {d:.2}", .{result.overall_stats.avg_test_sharpe});
    try logger.info("Overfitting Probability: {d:.2}%", .{
        result.overfitting_metrics.overfitting_probability * 100
    });

    if (result.overfitting_metrics.is_likely_overfitting) {
        try logger.warn("Warning: Strategy may be overfitted!", .{});
    }
}
```

---

## 📚 文档要求

### 新增文档

1. **Walk-Forward 使用指南** (`docs/features/optimizer/walk-forward.md`)
   - 什么是 Walk-Forward 分析
   - 如何配置
   - 分割策略对比
   - 结果解读

2. **过拟合防止指南** (`docs/features/optimizer/overfitting-prevention.md`)
   - 过拟合的识别
   - 防止方法
   - 最佳实践
   - 案例研究

3. **优化目标详解** (`docs/features/optimizer/objectives.md`)
   - 所有优化目标说明
   - 计算公式
   - 使用场景
   - 对比分析

---

## 🔗 相关文档

- [Story 022 (v0.3.0): GridSearchOptimizer 基础](../v0.3.0/STORY_022_GRID_SEARCH_OPTIMIZER.md)
- [Optimizer Feature 文档](../../features/optimizer/README.md)
- [BacktestEngine 文档](../../features/backtest/README.md)

---

## ✅ 完成标准

- [ ] Walk-Forward 分析器实现完成
- [ ] 所有分割策略实现
- [ ] 过拟合检测器实现
- [ ] 新增 6 个优化目标
- [ ] 所有单元测试通过（覆盖率 > 85%）
- [ ] 性能测试通过
- [ ] 3 个新文档完成
- [ ] CLI 参数集成
- [ ] 示例配置文件完成

---

**创建时间**: 2024-12-26
**最后更新**: 2024-12-26
**作者**: Claude (Sonnet 4.5)
