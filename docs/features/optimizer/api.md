# Parameter Optimizer API Reference

**Version**: v0.3.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-25

---

## Table of Contents

1. [Core Types](#core-types)
2. [GridSearchOptimizer](#gridsearchoptimizer)
3. [CombinationGenerator](#combinationgenerator)
4. [OptimizationResult](#optimizationresult)
5. [StrategyFactory](#strategyfactory)
6. [Usage Examples](#usage-examples)

---

## Core Types

### StrategyParameter

Defines a strategy parameter with its type, default value, and optimization range.

```zig
pub const StrategyParameter = struct {
    name: []const u8,
    type: ParameterType,
    default_value: ParameterValue,
    optimize: bool,
    range: ?ParameterRange,

    pub const ParameterType = enum {
        integer,
        decimal,
        boolean,
        discrete,
    };

    pub const ParameterValue = union(ParameterType) {
        integer: i64,
        decimal: Decimal,
        boolean: bool,
        discrete: []const u8,
    };

    pub const ParameterRange = union(ParameterType) {
        integer: IntegerRange,
        decimal: DecimalRange,
        boolean: void,  // No range for boolean
        discrete: []const []const u8,
    };

    pub const IntegerRange = struct {
        min: i64,
        max: i64,
        step: i64,
    };

    pub const DecimalRange = struct {
        min: Decimal,
        max: Decimal,
        step: Decimal,
    };
};
```

**Example**:
```zig
const fast_period = StrategyParameter{
    .name = "fast_period",
    .type = .integer,
    .default_value = .{ .integer = 10 },
    .optimize = true,
    .range = .{ .integer = .{ .min = 5, .max = 20, .step = 5 } },
};

const threshold = StrategyParameter{
    .name = "threshold",
    .type = .decimal,
    .default_value = .{ .decimal = try Decimal.fromString("0.5") },
    .optimize = true,
    .range = .{ .decimal = .{
        .min = try Decimal.fromString("0.1"),
        .max = try Decimal.fromString("0.9"),
        .step = try Decimal.fromString("0.2"),
    } },
};

const signal_type = StrategyParameter{
    .name = "signal_type",
    .type = .discrete,
    .default_value = .{ .discrete = "cross" },
    .optimize = true,
    .range = .{ .discrete = &[_][]const u8{ "cross", "threshold", "divergence" } },
};
```

---

### OptimizationConfig

Configuration for an optimization run.

```zig
pub const OptimizationConfig = struct {
    objective: OptimizationObjective,
    backtest_config: BacktestConfig,
    parameters: []const StrategyParameter,
    max_combinations: ?usize,
    enable_parallel: bool,
};

pub const OptimizationObjective = enum {
    maximize_sharpe_ratio,
    maximize_profit_factor,
    maximize_win_rate,
    minimize_max_drawdown,
    maximize_net_profit,
    custom,
};
```

**Field Descriptions**:
- `objective` - What metric to optimize for
- `backtest_config` - Backtest configuration to use for each test
- `parameters` - Array of parameters to optimize
- `max_combinations` - Optional limit on number of combinations to test
- `enable_parallel` - Whether to use parallel execution (v0.3.0: false)

**Example**:
```zig
const opt_config = OptimizationConfig{
    .objective = .maximize_sharpe_ratio,
    .backtest_config = backtest_config,
    .parameters = &params,
    .max_combinations = 1000,
    .enable_parallel = false,
};
```

---

### ParameterSet

A specific combination of parameter values.

```zig
pub const ParameterSet = struct {
    allocator: std.mem.Allocator,
    values: std.StringHashMap(ParameterValue),

    pub fn init(allocator: std.mem.Allocator) ParameterSet;
    pub fn deinit(self: *ParameterSet) void;

    pub fn set(self: *ParameterSet, name: []const u8, value: ParameterValue) !void;
    pub fn get(self: *const ParameterSet, name: []const u8) ?ParameterValue;

    pub fn clone(self: *const ParameterSet) !ParameterSet;
    pub fn format(
        self: ParameterSet,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void;
};
```

**Methods**:
- `init()` - Create new empty parameter set
- `deinit()` - Free all memory
- `set()` - Set a parameter value
- `get()` - Get a parameter value by name
- `clone()` - Create a deep copy
- `format()` - Format for printing

**Example**:
```zig
var param_set = ParameterSet.init(allocator);
defer param_set.deinit();

try param_set.set("fast_period", .{ .integer = 10 });
try param_set.set("slow_period", .{ .integer = 20 });

const fast = param_set.get("fast_period").?.integer;  // 10
std.debug.print("Parameters: {}\n", .{param_set});
```

---

## GridSearchOptimizer

Main optimizer that performs exhaustive grid search over parameter space.

### Structure

```zig
pub const GridSearchOptimizer = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    engine: *BacktestEngine,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        engine: *BacktestEngine,
    ) GridSearchOptimizer;

    pub fn deinit(self: *GridSearchOptimizer) void;

    pub fn optimize(
        self: *GridSearchOptimizer,
        strategy_factory: StrategyFactory,
        config: OptimizationConfig,
    ) !OptimizationResult;

    pub fn scoreResult(
        self: *GridSearchOptimizer,
        result: *const BacktestResult,
        objective: OptimizationObjective,
    ) !f64;

    pub fn findBestResult(
        self: *GridSearchOptimizer,
        all_results: []const BacktestResult,
        objective: OptimizationObjective,
    ) !struct { index: usize, score: f64 };
};
```

### Methods

#### `init()`

Creates a new optimizer instance.

**Signature**:
```zig
pub fn init(
    allocator: std.mem.Allocator,
    logger: Logger,
    engine: *BacktestEngine,
) GridSearchOptimizer
```

**Parameters**:
- `allocator` - Memory allocator for optimizer operations
- `logger` - Logger for progress updates
- `engine` - Backtest engine to use for testing

**Returns**: Initialized GridSearchOptimizer

**Example**:
```zig
var engine = try BacktestEngine.init(allocator);
defer engine.deinit();

var optimizer = GridSearchOptimizer.init(allocator, logger, &engine);
defer optimizer.deinit();
```

---

#### `optimize()`

Runs the optimization process.

**Signature**:
```zig
pub fn optimize(
    self: *GridSearchOptimizer,
    strategy_factory: StrategyFactory,
    config: OptimizationConfig,
) !OptimizationResult
```

**Parameters**:
- `strategy_factory` - Factory function to create strategy instances
- `config` - Optimization configuration

**Returns**: `OptimizationResult` containing best parameters and all results

**Errors**:
- `error.OutOfMemory` - Insufficient memory
- `error.NoValidCombinations` - No parameter combinations generated
- `error.AllBacktestsFailed` - All backtests failed

**Example**:
```zig
const result = try optimizer.optimize(createMACrossStrategy, opt_config);
defer result.deinit();

std.debug.print("Best Parameters:\n", .{});
std.debug.print("  fast_period: {}\n", .{result.best_params.get("fast_period").?.integer});
std.debug.print("Best Sharpe: {d:.4}\n", .{result.best_score});
```

**Process**:
1. Generate all parameter combinations
2. For each combination:
   - Create strategy instance with parameters
   - Run backtest
   - Calculate score based on objective
3. Find and return best result

---

#### `scoreResult()`

Calculates score for a backtest result based on objective.

**Signature**:
```zig
pub fn scoreResult(
    self: *GridSearchOptimizer,
    result: *const BacktestResult,
    objective: OptimizationObjective,
) !f64
```

**Parameters**:
- `result` - Backtest result to score
- `objective` - Optimization objective

**Returns**: Score value (higher is better, except for minimize_* objectives)

**Scoring Functions**:

| Objective | Score Calculation | Note |
|-----------|------------------|------|
| `maximize_sharpe_ratio` | `metrics.sharpe_ratio` | Risk-adjusted returns |
| `maximize_profit_factor` | `metrics.profit_factor` | Profit/loss ratio |
| `maximize_win_rate` | `metrics.win_rate` | Winning trade % |
| `minimize_max_drawdown` | `-metrics.max_drawdown` | Negated for maximization |
| `maximize_net_profit` | `metrics.net_profit.toFloat()` | Total profit |

**Example**:
```zig
const score = try optimizer.scoreResult(&backtest_result, .maximize_sharpe_ratio);
std.debug.print("Sharpe Ratio: {d:.4}\n", .{score});
```

---

#### `findBestResult()`

Finds the best result from an array of backtest results.

**Signature**:
```zig
pub fn findBestResult(
    self: *GridSearchOptimizer,
    all_results: []const BacktestResult,
    objective: OptimizationObjective,
) !struct { index: usize, score: f64 }
```

**Parameters**:
- `all_results` - Array of all backtest results
- `objective` - Optimization objective

**Returns**: Struct with index of best result and its score

**Example**:
```zig
const best = try optimizer.findBestResult(all_results, .maximize_sharpe_ratio);
const best_result = all_results[best.index];
std.debug.print("Best index: {}, Score: {d:.4}\n", .{ best.index, best.score });
```

---

## CombinationGenerator

Generates all parameter combinations from defined ranges.

### Structure

```zig
pub const CombinationGenerator = struct {
    allocator: std.mem.Allocator,
    parameters: []const StrategyParameter,

    pub fn init(
        allocator: std.mem.Allocator,
        parameters: []const StrategyParameter,
    ) CombinationGenerator;

    pub fn generateAll(self: *CombinationGenerator) ![]ParameterSet;
    pub fn countCombinations(self: *const CombinationGenerator) !usize;

    fn generateIntegerValues(range: IntegerRange) ![]i64;
    fn generateDecimalValues(allocator: std.mem.Allocator, range: DecimalRange) ![]Decimal;
    fn generateBooleanValues() [2]bool;
};
```

### Methods

#### `generateAll()`

Generates all parameter combinations.

**Signature**:
```zig
pub fn generateAll(self: *CombinationGenerator) ![]ParameterSet
```

**Returns**: Array of all parameter combinations

**Errors**:
- `error.OutOfMemory` - Insufficient memory
- `error.TooManyCombinations` - Combination count exceeds limits

**Algorithm**:
```
1. For each parameter, generate all possible values
2. Compute cartesian product of all value sets
3. Create ParameterSet for each combination
```

**Example**:
```zig
var generator = CombinationGenerator.init(allocator, &params);
const combinations = try generator.generateAll();
defer allocator.free(combinations);

std.debug.print("Total combinations: {}\n", .{combinations.len});
for (combinations) |combo| {
    std.debug.print("{}\n", .{combo});
}
```

---

#### `countCombinations()`

Calculates total number of combinations without generating them.

**Signature**:
```zig
pub fn countCombinations(self: *const CombinationGenerator) !usize
```

**Returns**: Total number of parameter combinations

**Formula**:
```
count = product(values_per_parameter[i] for all i)
```

**Example**:
```zig
const generator = CombinationGenerator.init(allocator, &params);
const count = try generator.countCombinations();

if (count > 10000) {
    std.debug.print("Warning: {} combinations may take a long time\n", .{count});
}
```

---

## OptimizationResult

Contains the results of an optimization run.

### Structure

```zig
pub const OptimizationResult = struct {
    allocator: std.mem.Allocator,
    best_params: ParameterSet,
    best_score: f64,
    all_results: []BacktestResult,
    all_params: []ParameterSet,
    total_combinations: usize,
    successful_combinations: usize,
    failed_combinations: usize,

    pub fn deinit(self: *OptimizationResult) void;

    pub fn getRankedResults(
        self: *const OptimizationResult,
        objective: OptimizationObjective,
        top_n: usize,
    ) ![]struct { params: ParameterSet, score: f64, result: *const BacktestResult };

    pub fn exportToJson(self: *const OptimizationResult, file_path: []const u8) !void;
    pub fn exportToCsv(self: *const OptimizationResult, file_path: []const u8) !void;
};
```

### Fields

- `best_params` - Optimal parameter combination
- `best_score` - Score of best combination
- `all_results` - All backtest results (successful only)
- `all_params` - All parameter combinations tested
- `total_combinations` - Total combinations attempted
- `successful_combinations` - Number of successful backtests
- `failed_combinations` - Number of failed backtests

### Methods

#### `getRankedResults()`

Returns top N results ranked by score.

**Signature**:
```zig
pub fn getRankedResults(
    self: *const OptimizationResult,
    objective: OptimizationObjective,
    top_n: usize,
) ![]struct { params: ParameterSet, score: f64, result: *const BacktestResult }
```

**Parameters**:
- `objective` - Optimization objective used
- `top_n` - Number of top results to return

**Returns**: Array of top N results with parameters, scores, and backtest results

**Example**:
```zig
const top_10 = try result.getRankedResults(.maximize_sharpe_ratio, 10);
defer allocator.free(top_10);

std.debug.print("Top 10 Combinations:\n", .{});
for (top_10, 0..) |entry, i| {
    std.debug.print("{}. Score: {d:.4}, Params: {}\n", .{ i + 1, entry.score, entry.params });
}
```

---

#### `exportToJson()`

Exports optimization results to JSON file.

**Signature**:
```zig
pub fn exportToJson(self: *const OptimizationResult, file_path: []const u8) !void
```

**Parameters**:
- `file_path` - Path to output JSON file

**JSON Format**:
```json
{
  "best_params": {
    "fast_period": 10,
    "slow_period": 25
  },
  "best_score": 1.85,
  "total_combinations": 24,
  "successful_combinations": 22,
  "failed_combinations": 2,
  "all_results": [
    {
      "params": { "fast_period": 5, "slow_period": 15 },
      "score": 1.23,
      "metrics": { ... }
    },
    ...
  ]
}
```

**Example**:
```zig
try result.exportToJson("optimization_results.json");
std.debug.print("Results exported to optimization_results.json\n", .{});
```

---

#### `exportToCsv()`

Exports optimization results to CSV file.

**Signature**:
```zig
pub fn exportToCsv(self: *const OptimizationResult, file_path: []const u8) !void
```

**Parameters**:
- `file_path` - Path to output CSV file

**CSV Format**:
```csv
fast_period,slow_period,score,sharpe_ratio,profit_factor,win_rate,max_drawdown
5,15,1.23,1.23,1.45,0.58,-0.15
10,20,1.85,1.85,1.89,0.62,-0.12
...
```

**Example**:
```zig
try result.exportToCsv("optimization_results.csv");
std.debug.print("Results exported to CSV\n", .{});
```

---

## StrategyFactory

Factory function type for creating strategy instances with parameters.

### Type Definition

```zig
pub const StrategyFactory = *const fn (
    allocator: std.mem.Allocator,
    params: ParameterSet,
) anyerror!IStrategy;
```

### Example Implementation

```zig
fn createMACrossStrategy(
    allocator: std.mem.Allocator,
    params: ParameterSet,
) !IStrategy {
    const fast_period = params.get("fast_period").?.integer;
    const slow_period = params.get("slow_period").?.integer;

    return try MACrossStrategy.init(allocator, .{
        .fast_period = @intCast(fast_period),
        .slow_period = @intCast(slow_period),
    });
}

// Usage
const result = try optimizer.optimize(createMACrossStrategy, opt_config);
```

---

## Usage Examples

### Basic Grid Search

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Define parameters
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

    // 2. Configure optimization
    const opt_config = zigQuant.OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = backtest_config,
        .parameters = &params,
        .max_combinations = null,
        .enable_parallel = false,
    };

    // 3. Run optimization
    var engine = try zigQuant.BacktestEngine.init(allocator);
    defer engine.deinit();

    var optimizer = zigQuant.GridSearchOptimizer.init(allocator, logger, &engine);
    defer optimizer.deinit();

    const result = try optimizer.optimize(createMACrossStrategy, opt_config);
    defer result.deinit();

    // 4. Print results
    std.debug.print("Best Parameters:\n", .{});
    std.debug.print("  fast_period: {}\n", .{result.best_params.get("fast_period").?.integer});
    std.debug.print("  slow_period: {}\n", .{result.best_params.get("slow_period").?.integer});
    std.debug.print("Best Sharpe Ratio: {d:.4}\n", .{result.best_score});
}
```

### Multi-Type Parameters

```zig
var params = [_]zigQuant.StrategyParameter{
    // Integer parameter
    .{
        .name = "period",
        .type = .integer,
        .default_value = .{ .integer = 14 },
        .optimize = true,
        .range = .{ .integer = .{ .min = 10, .max = 30, .step = 5 } },
    },
    // Decimal parameter
    .{
        .name = "threshold",
        .type = .decimal,
        .default_value = .{ .decimal = try Decimal.fromString("0.5") },
        .optimize = true,
        .range = .{ .decimal = .{
            .min = try Decimal.fromString("0.2"),
            .max = try Decimal.fromString("0.8"),
            .step = try Decimal.fromString("0.2"),
        } },
    },
    // Boolean parameter
    .{
        .name = "use_trailing_stop",
        .type = .boolean,
        .default_value = .{ .boolean = false },
        .optimize = true,
        .range = .{ .boolean = {} },
    },
    // Discrete parameter
    .{
        .name = "signal_type",
        .type = .discrete,
        .default_value = .{ .discrete = "cross" },
        .optimize = true,
        .range = .{ .discrete = &[_][]const u8{ "cross", "threshold", "divergence" } },
    },
};
```

### Exporting Results

```zig
const result = try optimizer.optimize(createStrategy, opt_config);
defer result.deinit();

// Export to JSON
try result.exportToJson("results.json");

// Export to CSV
try result.exportToCsv("results.csv");

// Get top 10 results
const top_10 = try result.getRankedResults(.maximize_sharpe_ratio, 10);
defer allocator.free(top_10);

for (top_10, 0..) |entry, i| {
    std.debug.print("\n#{} - Score: {d:.4}\n", .{ i + 1, entry.score });
    std.debug.print("Parameters: {}\n", .{entry.params});
    std.debug.print("Metrics:\n", .{});
    std.debug.print("  Net Profit: {}\n", .{entry.result.metrics.net_profit});
    std.debug.print("  Win Rate: {d:.2}%\n", .{entry.result.metrics.win_rate * 100});
    std.debug.print("  Max Drawdown: {d:.2}%\n", .{entry.result.metrics.max_drawdown * 100});
}
```

### Custom Optimization Objective

```zig
// Define custom scoring function
fn customScoreFunc(result: *const BacktestResult) f64 {
    // Custom formula: weighted combination of metrics
    const sharpe_weight = 0.4;
    const profit_weight = 0.3;
    const dd_weight = 0.3;

    const sharpe_score = result.metrics.sharpe_ratio;
    const profit_score = result.metrics.profit_factor;
    const dd_score = 1.0 - result.metrics.max_drawdown;  // Convert to positive

    return sharpe_weight * sharpe_score +
           profit_weight * profit_score +
           dd_weight * dd_score;
}

// Use in optimization (future v0.4.0+)
const opt_config = OptimizationConfig{
    .objective = .custom,
    .custom_scorer = customScoreFunc,
    // ...
};
```

---

## Error Handling

### Common Errors

```zig
// Handle optimization errors
const result = optimizer.optimize(createStrategy, opt_config) catch |err| {
    switch (err) {
        error.OutOfMemory => {
            std.debug.print("Not enough memory for optimization\n", .{});
            return err;
        },
        error.NoValidCombinations => {
            std.debug.print("No parameter combinations generated\n", .{});
            return err;
        },
        error.AllBacktestsFailed => {
            std.debug.print("All backtests failed - check strategy implementation\n", .{});
            return err;
        },
        else => return err,
    }
};
```

---

## Performance Considerations

### Memory Usage

```zig
// Estimate memory before optimization
const generator = CombinationGenerator.init(allocator, &params);
const count = try generator.countCombinations();

const estimated_memory = count * @sizeOf(BacktestResult);
std.debug.print("Estimated memory: {} MB\n", .{estimated_memory / 1024 / 1024});

if (estimated_memory > 1024 * 1024 * 1024) {  // > 1GB
    std.debug.print("Warning: Large memory usage expected\n", .{});
}
```

### Optimization Speed

```zig
const start_time = std.time.milliTimestamp();

const result = try optimizer.optimize(createStrategy, opt_config);
defer result.deinit();

const elapsed = std.time.milliTimestamp() - start_time;
const combinations_per_sec = @as(f64, @floatFromInt(result.total_combinations)) /
                             (@as(f64, @floatFromInt(elapsed)) / 1000.0);

std.debug.print("Optimization completed in {d:.2}s\n", .{@as(f64, @floatFromInt(elapsed)) / 1000.0});
std.debug.print("Speed: {d:.1} combinations/s\n", .{combinations_per_sec});
```

---

## Thread Safety

**v0.3.0 Limitations**:
- GridSearchOptimizer is NOT thread-safe
- Do not call `optimize()` concurrently
- Each optimizer instance should be used from a single thread

**Future (v0.4.0+)**:
- Parallel optimization with `enable_parallel = true`
- Thread-safe result aggregation

---

## Best Practices

### 1. Parameter Range Selection

```zig
// ✅ Good: Reasonable ranges
.range = .{ .integer = .{ .min = 5, .max = 50, .step = 5 } }  // 10 values

// ❌ Bad: Too fine-grained
.range = .{ .integer = .{ .min = 5, .max = 500, .step = 1 } }  // 496 values!
```

### 2. Combination Count Management

```zig
// Check combination count before optimization
const generator = CombinationGenerator.init(allocator, &params);
const count = try generator.countCombinations();

if (count > 1000) {
    std.debug.print("Warning: {} combinations - consider reducing ranges\n", .{count});
}
```

### 3. Memory Management

```zig
// Always defer deinit
const result = try optimizer.optimize(createStrategy, opt_config);
defer result.deinit();  // Critical!

// Use arena allocator for temporary data
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const temp_allocator = arena.allocator();
```

### 4. Result Validation

```zig
const result = try optimizer.optimize(createStrategy, opt_config);
defer result.deinit();

// Check success rate
const success_rate = @as(f64, @floatFromInt(result.successful_combinations)) /
                     @as(f64, @floatFromInt(result.total_combinations));

if (success_rate < 0.5) {
    std.debug.print("Warning: Low success rate ({d:.1}%)\n", .{success_rate * 100});
    std.debug.print("Check strategy implementation for errors\n", .{});
}
```

---

## Version History

- **v0.3.0** (Planned) - Initial implementation
  - Grid search optimizer
  - Multi-type parameter support
  - Result export (JSON, CSV)
  - Basic optimization objectives

- **v0.4.0** (Planned) - Advanced features
  - Parallel optimization
  - Custom objective functions
  - Walk-forward analysis
  - Genetic algorithm optimizer

---

**Version**: v0.3.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-25
