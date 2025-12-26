# Parameter Optimizer

**Version**: v0.3.0
**Status**: ✅ Completed
**Last Updated**: 2025-12-26

---

## Overview

The Parameter Optimizer module provides automated parameter search and optimization capabilities for trading strategies. It uses systematic search algorithms to find optimal parameter combinations that maximize specified performance objectives.

## Key Features

### Grid Search Optimizer
- **Exhaustive Search**: Tests all parameter combinations in defined ranges
- **Multi-Type Parameters**: Supports integer, decimal, boolean, and discrete values
- **Flexible Objectives**: Optimize for Sharpe ratio, profit factor, win rate, max drawdown, or custom metrics
- **Progress Tracking**: Real-time progress updates and result reporting
- **Result Ranking**: Automatically ranks and sorts all tested combinations

### Parameter Management
- **Parameter Ranges**: Define search spaces with min, max, and step values
- **Parameter Sets**: Manage parameter combinations efficiently
- **Optimization Config**: Flexible configuration for optimization runs

### Performance
- **Fast Execution**: Optimized for speed with optional parallel processing
- **Memory Efficient**: Careful memory management for large search spaces
- **Result Caching**: Stores all backtest results for later analysis

## Architecture

```
optimizer/
├── types.zig              # Type definitions
├── grid_search.zig        # Grid search implementation
├── combination.zig        # Parameter combination generator
└── result.zig             # Result analysis and ranking
```

## Quick Start

### Basic Grid Search

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Define parameters to optimize
    var params = [_]zigQuant.StrategyParameter{
        .{
            .name = "fast_period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 5, .max = 20, .step = 5 } },
        },
        .{
            .name = "slow_period",
            .type = .integer,
            .default_value = .{ .integer = 20 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 15, .max = 50, .step = 5 } },
        },
    };

    // Configure optimization
    const opt_config = zigQuant.OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = backtest_config,
        .parameters = &params,
        .max_combinations = null,
        .enable_parallel = false,
    };

    // Run optimization
    var engine = try zigQuant.BacktestEngine.init(allocator);
    defer engine.deinit();

    var optimizer = zigQuant.GridSearchOptimizer.init(
        allocator,
        logger,
        &engine,
    );
    defer optimizer.deinit();

    const result = try optimizer.optimize(strategyFactory, opt_config);
    defer result.deinit();

    // Print results
    std.debug.print("Best Parameters:\n", .{});
    std.debug.print("  fast_period: {}\n", .{result.best_params.get("fast_period").?.integer});
    std.debug.print("  slow_period: {}\n", .{result.best_params.get("slow_period").?.integer});
    std.debug.print("Best Score: {d:.4}\n", .{result.best_score});
    std.debug.print("Total Combinations Tested: {}\n", .{result.total_combinations});
}
```

## Core Components

### GridSearchOptimizer
Main optimizer that coordinates the optimization process.

**Key Methods**:
- `optimize()` - Run optimization for given strategy and config
- `findBestResult()` - Find best result based on objective
- `scoreResult()` - Calculate score for a backtest result

### CombinationGenerator
Generates all parameter combinations from defined ranges.

**Key Methods**:
- `generateAll()` - Generate all parameter combinations
- `countCombinations()` - Calculate total number of combinations

### OptimizationResult
Contains optimization results with best parameters and all tested combinations.

**Key Fields**:
- `best_params` - Optimal parameter set
- `best_score` - Score of best combination
- `all_results` - All backtest results
- `total_combinations` - Number of combinations tested

## Optimization Objectives

| Objective | Description | Formula |
|-----------|-------------|---------|
| `maximize_sharpe_ratio` | Risk-adjusted returns | `(return - rf_rate) / volatility` |
| `maximize_profit_factor` | Profit vs loss ratio | `total_profit / total_loss` |
| `maximize_win_rate` | Winning trade percentage | `winning_trades / total_trades` |
| `minimize_max_drawdown` | Smallest drawdown | `min(max_drawdown)` |
| `maximize_net_profit` | Total profit | `total_profit - total_loss` |
| `custom` | User-defined metric | Custom function |

## Performance Characteristics

- **Speed**: Single backtest < 100ms
- **Memory**: Linear with number of combinations
- **Scalability**: Supports 1000+ combinations efficiently
- **Parallel**: Optional parallel execution (future)

## Validation & Testing

### Overfitting Prevention
- **Walk-Forward Analysis**: Test on out-of-sample data
- **Cross-Validation**: Validate robustness across periods
- **Parameter Stability**: Check parameter sensitivity

### Testing Strategy
- Unit tests for combination generation
- Integration tests with backtest engine
- Performance benchmarks
- Overfitting detection tests

## Limitations (v0.3.0)

- **Grid Search Only**: Advanced algorithms (genetic, Bayesian) in future versions
- **Sequential Execution**: Parallel processing optional
- **Single Objective**: Multi-objective optimization in future
- **Memory Bound**: Large search spaces may require chunking

## Future Enhancements (v0.4.0+)

- Genetic algorithm optimizer
- Bayesian optimization
- Distributed/parallel optimization
- Walk-forward analysis built-in
- Multi-objective optimization
- Adaptive parameter ranges

## Related Documentation

- [API Reference](api.md) - Complete API documentation
- [Implementation Details](implementation.md) - Internal architecture
- [Testing Guide](testing.md) - Test strategy and examples
- [Story 022](../../stories/v0.3.0/STORY_022_GRID_SEARCH_OPTIMIZER.md) - Original user story

---

## ✅ v0.3.0 完成情况

### 已实现功能

- ✅ GridSearchOptimizer - 网格搜索优化器
- ✅ CombinationGenerator - 参数组合生成器
- ✅ OptimizationResult - 优化结果类型
- ✅ OptimizationConfig - 优化配置
- ✅ StrategyParameter - 参数定义和范围
- ✅ 6种优化目标 (Sharpe, Profit Factor, Win Rate, Max Drawdown, Net Profit, Custom)
- ✅ 参数类型支持 (integer, decimal, boolean, discrete)

### 核心组件

**文件结构**:
```
src/optimizer/
├── grid_search.zig        # GridSearchOptimizer 实现
├── types.zig              # OptimizationConfig, OptimizationResult
├── combination.zig        # CombinationGenerator
└── result.zig             # 结果分析和排序
```

### 示例和测试

**示例代码**:
- `examples/06_strategy_optimize.zig` - 完整优化示例 ✅

**测试代码**:
- `tests/integration/strategy_full_test.zig` - 集成测试 ✅
  - 测试 GridSearchOptimizer 创建
  - 测试参数组合生成
  - 内存泄漏检测

### 使用方法

```bash
# 运行优化示例
zig build run-example-optimize

# 运行集成测试
zig build test-strategy-full
```

---

**Version**: v0.3.0
**Status**: ✅ 已完成
**Last Updated**: 2025-12-26
