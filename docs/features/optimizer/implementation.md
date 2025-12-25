# Parameter Optimizer Implementation Guide

**Version**: v0.3.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-25

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core Components](#core-components)
3. [Grid Search Algorithm](#grid-search-algorithm)
4. [Parameter Management](#parameter-management)
5. [Result Handling](#result-handling)
6. [Memory Management](#memory-management)
7. [Error Handling](#error-handling)
8. [Performance Optimization](#performance-optimization)

---

## Architecture Overview

### Module Structure

```
optimizer/
├── types.zig              # Type definitions (StrategyParameter, ParameterSet, etc.)
├── grid_search.zig        # GridSearchOptimizer implementation
├── combination.zig        # CombinationGenerator implementation
├── result.zig             # OptimizationResult implementation
└── tests/
    ├── types_test.zig
    ├── grid_search_test.zig
    ├── combination_test.zig
    └── integration_test.zig
```

### Dependencies

```zig
const std = @import("std");
const core = @import("../core/root.zig");
const Decimal = core.Decimal;
const Logger = core.Logger;
const BacktestEngine = @import("../backtest/engine.zig").BacktestEngine;
const BacktestConfig = @import("../backtest/config.zig").BacktestConfig;
const BacktestResult = @import("../backtest/result.zig").BacktestResult;
const IStrategy = @import("../strategy/interface.zig").IStrategy;
```

### Data Flow

```
1. User defines parameters + optimization config
              ↓
2. CombinationGenerator creates all parameter sets
              ↓
3. GridSearchOptimizer iterates over combinations
              ↓
4. For each combination:
   - StrategyFactory creates strategy instance
   - BacktestEngine runs backtest
   - Optimizer scores result
              ↓
5. Optimizer finds best result
              ↓
6. Return OptimizationResult with best params + all results
```

---

## Core Components

### 1. types.zig

Contains all type definitions for the optimizer module.

#### StrategyParameter Implementation

```zig
// types.zig
const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;

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

    pub fn format(
        self: ParameterValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .integer => |v| try writer.print("{}", .{v}),
            .decimal => |v| try writer.print("{}", .{v}),
            .boolean => |v| try writer.print("{}", .{v}),
            .discrete => |v| try writer.print("{s}", .{v}),
        }
    }

    pub fn eql(self: ParameterValue, other: ParameterValue) bool {
        if (@as(ParameterType, self) != @as(ParameterType, other)) return false;

        return switch (self) {
            .integer => |v| v == other.integer,
            .decimal => |v| v.eql(other.decimal),
            .boolean => |v| v == other.boolean,
            .discrete => |v| std.mem.eql(u8, v, other.discrete),
        };
    }
};

pub const IntegerRange = struct {
    min: i64,
    max: i64,
    step: i64,

    pub fn validate(self: IntegerRange) !void {
        if (self.min >= self.max) return error.InvalidRange;
        if (self.step <= 0) return error.InvalidStep;
        if (self.step > (self.max - self.min)) return error.StepTooLarge;
    }

    pub fn count(self: IntegerRange) usize {
        return @intCast((self.max - self.min) / self.step + 1);
    }
};

pub const DecimalRange = struct {
    min: Decimal,
    max: Decimal,
    step: Decimal,

    pub fn validate(self: DecimalRange) !void {
        if (self.min.gte(self.max)) return error.InvalidRange;
        if (self.step.lte(Decimal.ZERO)) return error.InvalidStep;
        const range = try self.max.sub(self.min);
        if (self.step.gt(range)) return error.StepTooLarge;
    }

    pub fn count(self: DecimalRange) !usize {
        const range = try self.max.sub(self.min);
        const count_decimal = try range.div(self.step);
        const count_float = try count_decimal.toFloat();
        return @intFromFloat(@floor(count_float) + 1);
    }
};

pub const ParameterRange = union(ParameterType) {
    integer: IntegerRange,
    decimal: DecimalRange,
    boolean: void,
    discrete: []const []const u8,

    pub fn count(self: ParameterRange) !usize {
        return switch (self) {
            .integer => |r| r.count(),
            .decimal => |r| try r.count(),
            .boolean => 2,
            .discrete => |values| values.len,
        };
    }
};

pub const StrategyParameter = struct {
    name: []const u8,
    type: ParameterType,
    default_value: ParameterValue,
    optimize: bool,
    range: ?ParameterRange,

    pub fn validate(self: StrategyParameter) !void {
        // Check type consistency
        if (@as(ParameterType, self.default_value) != self.type) {
            return error.TypeMismatch;
        }

        // If optimize is true, range must be provided
        if (self.optimize and self.range == null) {
            return error.MissingRange;
        }

        // If range provided, validate it
        if (self.range) |r| {
            if (@as(ParameterType, r) != self.type) {
                return error.RangeTypeMismatch;
            }

            switch (r) {
                .integer => |int_range| try int_range.validate(),
                .decimal => |dec_range| try dec_range.validate(),
                .boolean => {},
                .discrete => |values| {
                    if (values.len == 0) return error.EmptyDiscreteValues;
                },
            }
        }
    }
};
```

#### ParameterSet Implementation

```zig
pub const ParameterSet = struct {
    allocator: std.mem.Allocator,
    values: std.StringHashMap(ParameterValue),

    pub fn init(allocator: std.mem.Allocator) ParameterSet {
        return .{
            .allocator = allocator,
            .values = std.StringHashMap(ParameterValue).init(allocator),
        };
    }

    pub fn deinit(self: *ParameterSet) void {
        self.values.deinit();
    }

    pub fn set(self: *ParameterSet, name: []const u8, value: ParameterValue) !void {
        try self.values.put(name, value);
    }

    pub fn get(self: *const ParameterSet, name: []const u8) ?ParameterValue {
        return self.values.get(name);
    }

    pub fn clone(self: *const ParameterSet) !ParameterSet {
        var new_set = ParameterSet.init(self.allocator);
        errdefer new_set.deinit();

        var iter = self.values.iterator();
        while (iter.next()) |entry| {
            try new_set.set(entry.key_ptr.*, entry.value_ptr.*);
        }

        return new_set;
    }

    pub fn format(
        self: ParameterSet,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("{ ");
        var iter = self.values.iterator();
        var first = true;
        while (iter.next()) |entry| {
            if (!first) try writer.writeAll(", ");
            first = false;
            try writer.print("{s}: {}", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        try writer.writeAll(" }");
    }
};
```

#### OptimizationConfig

```zig
pub const OptimizationObjective = enum {
    maximize_sharpe_ratio,
    maximize_profit_factor,
    maximize_win_rate,
    minimize_max_drawdown,
    maximize_net_profit,
    custom,

    pub fn isMaximize(self: OptimizationObjective) bool {
        return switch (self) {
            .minimize_max_drawdown => false,
            else => true,
        };
    }
};

pub const OptimizationConfig = struct {
    objective: OptimizationObjective,
    backtest_config: BacktestConfig,
    parameters: []const StrategyParameter,
    max_combinations: ?usize,
    enable_parallel: bool,

    pub fn validate(self: OptimizationConfig) !void {
        // Validate all parameters
        for (self.parameters) |param| {
            try param.validate();
        }

        // Check at least one parameter to optimize
        var has_optimize = false;
        for (self.parameters) |param| {
            if (param.optimize) {
                has_optimize = true;
                break;
            }
        }
        if (!has_optimize) {
            return error.NoParametersToOptimize;
        }
    }
};
```

---

### 2. combination.zig

Generates all parameter combinations using cartesian product.

```zig
// combination.zig
const std = @import("std");
const types = @import("types.zig");
const Decimal = @import("../core/decimal.zig").Decimal;

pub const CombinationGenerator = struct {
    allocator: std.mem.Allocator,
    parameters: []const types.StrategyParameter,

    pub fn init(
        allocator: std.mem.Allocator,
        parameters: []const types.StrategyParameter,
    ) CombinationGenerator {
        return .{
            .allocator = allocator,
            .parameters = parameters,
        };
    }

    pub fn countCombinations(self: *const CombinationGenerator) !usize {
        var total: usize = 1;

        for (self.parameters) |param| {
            if (!param.optimize) continue;

            const range = param.range orelse continue;
            const count = try range.count();
            total *= count;
        }

        return total;
    }

    pub fn generateAll(self: *CombinationGenerator) ![]types.ParameterSet {
        // Step 1: Generate value arrays for each parameter
        var value_arrays = std.ArrayList(ValueArray).init(self.allocator);
        defer {
            for (value_arrays.items) |*arr| arr.deinit();
            value_arrays.deinit();
        }

        for (self.parameters) |param| {
            if (!param.optimize) continue;

            const values = try self.generateValuesForParameter(param);
            try value_arrays.append(.{
                .name = param.name,
                .values = values,
            });
        }

        // Step 2: Calculate total combinations
        const total = try self.countCombinations();
        if (total == 0) return error.NoValidCombinations;

        // Step 3: Generate cartesian product
        var combinations = try self.allocator.alloc(types.ParameterSet, total);
        errdefer self.allocator.free(combinations);

        for (combinations) |*combo| {
            combo.* = types.ParameterSet.init(self.allocator);
        }

        // Step 4: Fill combinations
        try self.cartesianProduct(value_arrays.items, combinations);

        return combinations;
    }

    const ValueArray = struct {
        name: []const u8,
        values: std.ArrayList(types.ParameterValue),

        fn deinit(self: *ValueArray) void {
            self.values.deinit();
        }
    };

    fn generateValuesForParameter(
        self: *CombinationGenerator,
        param: types.StrategyParameter,
    ) !std.ArrayList(types.ParameterValue) {
        var values = std.ArrayList(types.ParameterValue).init(self.allocator);
        errdefer values.deinit();

        const range = param.range orelse return values;

        switch (range) {
            .integer => |int_range| {
                var val = int_range.min;
                while (val <= int_range.max) : (val += int_range.step) {
                    try values.append(.{ .integer = val });
                }
            },
            .decimal => |dec_range| {
                var val = dec_range.min;
                while (val.lte(dec_range.max)) {
                    try values.append(.{ .decimal = val });
                    val = try val.add(dec_range.step);
                }
            },
            .boolean => {
                try values.append(.{ .boolean = false });
                try values.append(.{ .boolean = true });
            },
            .discrete => |discrete_values| {
                for (discrete_values) |dv| {
                    try values.append(.{ .discrete = dv });
                }
            },
        }

        return values;
    }

    fn cartesianProduct(
        self: *CombinationGenerator,
        value_arrays: []const ValueArray,
        combinations: []types.ParameterSet,
    ) !void {
        if (value_arrays.len == 0) return;

        // Calculate repeat pattern for each parameter
        var repeat_counts = try self.allocator.alloc(usize, value_arrays.len);
        defer self.allocator.free(repeat_counts);

        var cycle_counts = try self.allocator.alloc(usize, value_arrays.len);
        defer self.allocator.free(cycle_counts);

        // Calculate repeat and cycle for each dimension
        var total_combinations: usize = 1;
        for (value_arrays) |arr| {
            total_combinations *= arr.values.items.len;
        }

        var repeat: usize = 1;
        var i: usize = value_arrays.len;
        while (i > 0) : (i -= 1) {
            const idx = i - 1;
            repeat_counts[idx] = repeat;
            cycle_counts[idx] = total_combinations / (repeat * value_arrays[idx].values.items.len);
            repeat *= value_arrays[idx].values.items.len;
        }

        // Fill each combination
        for (combinations, 0..) |*combo, combo_idx| {
            for (value_arrays, 0..) |arr, param_idx| {
                const value_idx = (combo_idx / repeat_counts[param_idx]) % arr.values.items.len;
                const value = arr.values.items[value_idx];
                try combo.set(arr.name, value);
            }
        }
    }
};
```

**Algorithm Explanation**:

The cartesian product algorithm works as follows:

For parameters `[A, B, C]` with values:
- A: [1, 2]
- B: [10, 20, 30]
- C: [100, 200]

Total combinations: 2 × 3 × 2 = 12

```
Repeat pattern:
- A repeats every 1 position, cycles 6 times
- B repeats every 2 positions, cycles 2 times
- C repeats every 6 positions, cycles 1 time

Index | A (cycle=6, rep=1) | B (cycle=2, rep=2) | C (cycle=1, rep=6)
------|--------------------|--------------------|-------------------
  0   | 1                  | 10                 | 100
  1   | 2                  | 10                 | 100
  2   | 1                  | 20                 | 100
  3   | 2                  | 20                 | 100
  4   | 1                  | 30                 | 100
  5   | 2                  | 30                 | 100
  6   | 1                  | 10                 | 200
  7   | 2                  | 10                 | 200
  8   | 1                  | 20                 | 200
  9   | 2                  | 20                 | 200
 10   | 1                  | 30                 | 200
 11   | 2                  | 30                 | 200
```

---

### 3. grid_search.zig

Main optimizer implementation.

```zig
// grid_search.zig
const std = @import("std");
const types = @import("types.zig");
const CombinationGenerator = @import("combination.zig").CombinationGenerator;
const OptimizationResult = @import("result.zig").OptimizationResult;
const Logger = @import("../core/logger.zig").Logger;
const BacktestEngine = @import("../backtest/engine.zig").BacktestEngine;
const BacktestResult = @import("../backtest/result.zig").BacktestResult;
const IStrategy = @import("../strategy/interface.zig").IStrategy;

pub const StrategyFactory = *const fn (
    allocator: std.mem.Allocator,
    params: types.ParameterSet,
) anyerror!IStrategy;

pub const GridSearchOptimizer = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    engine: *BacktestEngine,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        engine: *BacktestEngine,
    ) GridSearchOptimizer {
        return .{
            .allocator = allocator,
            .logger = logger,
            .engine = engine,
        };
    }

    pub fn deinit(self: *GridSearchOptimizer) void {
        _ = self;
    }

    pub fn optimize(
        self: *GridSearchOptimizer,
        strategy_factory: StrategyFactory,
        config: types.OptimizationConfig,
    ) !OptimizationResult {
        // Validate configuration
        try config.validate();

        // Generate all parameter combinations
        self.logger.info("Generating parameter combinations...", .{});
        var generator = CombinationGenerator.init(self.allocator, config.parameters);
        const all_params = try generator.generateAll();
        defer {
            for (all_params) |*params| params.deinit();
            self.allocator.free(all_params);
        }

        const total_count = all_params.len;
        self.logger.info("Total combinations: {}", .{total_count});

        // Limit combinations if configured
        const test_count = if (config.max_combinations) |max|
            @min(max, total_count)
        else
            total_count;

        // Allocate result arrays
        var all_results = std.ArrayList(BacktestResult).init(self.allocator);
        defer all_results.deinit();

        var successful_params = std.ArrayList(types.ParameterSet).init(self.allocator);
        defer successful_params.deinit();

        var failed_count: usize = 0;

        // Run backtest for each combination
        for (all_params[0..test_count], 0..) |param_set, i| {
            self.logger.debug("Testing combination {}/{}: {}", .{ i + 1, test_count, param_set });

            // Create strategy with parameters
            const strategy = strategy_factory(self.allocator, param_set) catch |err| {
                self.logger.err("Failed to create strategy: {}", .{err});
                failed_count += 1;
                continue;
            };
            defer {
                var mut_strategy = strategy;
                mut_strategy.deinit();
            }

            // Run backtest
            const result = self.engine.run(strategy, config.backtest_config) catch |err| {
                self.logger.err("Backtest failed: {}", .{err});
                failed_count += 1;
                continue;
            };

            // Score result
            const score = try self.scoreResult(&result, config.objective);
            self.logger.debug("Score: {d:.4}", .{score});

            // Store results
            try all_results.append(result);
            try successful_params.append(try param_set.clone());

            // Progress update
            if ((i + 1) % 10 == 0 or i + 1 == test_count) {
                const progress = @as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(test_count)) * 100.0;
                self.logger.info("Progress: {d:.1}% ({}/{})", .{ progress, i + 1, test_count });
            }
        }

        // Check if any backtests succeeded
        if (all_results.items.len == 0) {
            return error.AllBacktestsFailed;
        }

        // Find best result
        const best = try self.findBestResult(all_results.items, config.objective);
        self.logger.info("Best score: {d:.4} (combination {}/{})", .{
            best.score,
            best.index + 1,
            all_results.items.len,
        });

        // Create result
        return OptimizationResult{
            .allocator = self.allocator,
            .best_params = try successful_params.items[best.index].clone(),
            .best_score = best.score,
            .all_results = try all_results.toOwnedSlice(),
            .all_params = try successful_params.toOwnedSlice(),
            .total_combinations = test_count,
            .successful_combinations = all_results.items.len,
            .failed_combinations = failed_count,
        };
    }

    pub fn scoreResult(
        self: *GridSearchOptimizer,
        result: *const BacktestResult,
        objective: types.OptimizationObjective,
    ) !f64 {
        _ = self;

        return switch (objective) {
            .maximize_sharpe_ratio => result.metrics.sharpe_ratio,
            .maximize_profit_factor => result.metrics.profit_factor,
            .maximize_win_rate => result.metrics.win_rate,
            .minimize_max_drawdown => -result.metrics.max_drawdown,  // Negate for maximization
            .maximize_net_profit => try result.metrics.net_profit.toFloat(),
            .custom => error.CustomObjectiveNotSupported,  // v0.4.0+
        };
    }

    pub fn findBestResult(
        self: *GridSearchOptimizer,
        all_results: []const BacktestResult,
        objective: types.OptimizationObjective,
    ) !struct { index: usize, score: f64 } {
        if (all_results.len == 0) return error.NoResults;

        var best_index: usize = 0;
        var best_score = try self.scoreResult(&all_results[0], objective);

        for (all_results[1..], 1..) |*result, i| {
            const score = try self.scoreResult(result, objective);
            if (score > best_score) {
                best_score = score;
                best_index = i;
            }
        }

        return .{ .index = best_index, .score = best_score };
    }
};
```

---

### 4. result.zig

Optimization result container with export functionality.

```zig
// result.zig
const std = @import("std");
const types = @import("types.zig");
const BacktestResult = @import("../backtest/result.zig").BacktestResult;

pub const OptimizationResult = struct {
    allocator: std.mem.Allocator,
    best_params: types.ParameterSet,
    best_score: f64,
    all_results: []BacktestResult,
    all_params: []types.ParameterSet,
    total_combinations: usize,
    successful_combinations: usize,
    failed_combinations: usize,

    pub fn deinit(self: *OptimizationResult) void {
        self.best_params.deinit();

        for (self.all_results) |*result| {
            result.deinit(self.allocator);
        }
        self.allocator.free(self.all_results);

        for (self.all_params) |*params| {
            params.deinit();
        }
        self.allocator.free(self.all_params);
    }

    pub const RankedResult = struct {
        params: types.ParameterSet,
        score: f64,
        result: *const BacktestResult,
    };

    pub fn getRankedResults(
        self: *const OptimizationResult,
        objective: types.OptimizationObjective,
        top_n: usize,
    ) ![]RankedResult {
        const count = @min(top_n, self.all_results.len);

        // Create scored array
        var scored = try self.allocator.alloc(
            struct { index: usize, score: f64 },
            self.all_results.len,
        );
        defer self.allocator.free(scored);

        for (self.all_results, 0..) |*result, i| {
            const score = scoreBacktestResult(result, objective);
            scored[i] = .{ .index = i, .score = score };
        }

        // Sort by score (descending)
        std.mem.sort(@TypeOf(scored[0]), scored, {}, struct {
            fn lessThan(_: void, a: @TypeOf(scored[0]), b: @TypeOf(scored[0])) bool {
                return a.score > b.score;  // Descending
            }
        }.lessThan);

        // Build result array
        var ranked = try self.allocator.alloc(RankedResult, count);
        for (ranked, 0..) |*entry, i| {
            const idx = scored[i].index;
            entry.* = .{
                .params = try self.all_params[idx].clone(),
                .score = scored[i].score,
                .result = &self.all_results[idx],
            };
        }

        return ranked;
    }

    pub fn exportToJson(self: *const OptimizationResult, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        var buffered = std.io.bufferedWriter(file.writer());
        const writer = buffered.writer();

        try writer.writeAll("{\n");

        // Best params
        try writer.writeAll("  \"best_params\": ");
        try self.writeParameterSetJson(writer, self.best_params);
        try writer.writeAll(",\n");

        // Best score
        try writer.print("  \"best_score\": {d:.6},\n", .{self.best_score});

        // Statistics
        try writer.print("  \"total_combinations\": {},\n", .{self.total_combinations});
        try writer.print("  \"successful_combinations\": {},\n", .{self.successful_combinations});
        try writer.print("  \"failed_combinations\": {},\n", .{self.failed_combinations});

        // All results
        try writer.writeAll("  \"all_results\": [\n");
        for (self.all_results, 0..) |*result, i| {
            try writer.writeAll("    {\n");
            try writer.writeAll("      \"params\": ");
            try self.writeParameterSetJson(writer, self.all_params[i]);
            try writer.writeAll(",\n");
            try writer.print("      \"sharpe_ratio\": {d:.6},\n", .{result.metrics.sharpe_ratio});
            try writer.print("      \"profit_factor\": {d:.6},\n", .{result.metrics.profit_factor});
            try writer.print("      \"win_rate\": {d:.6}\n", .{result.metrics.win_rate});
            if (i < self.all_results.len - 1) {
                try writer.writeAll("    },\n");
            } else {
                try writer.writeAll("    }\n");
            }
        }
        try writer.writeAll("  ]\n");

        try writer.writeAll("}\n");
        try buffered.flush();
    }

    pub fn exportToCsv(self: *const OptimizationResult, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        var buffered = std.io.bufferedWriter(file.writer());
        const writer = buffered.writer();

        // Header row
        // Get parameter names from first param set
        var param_names = std.ArrayList([]const u8).init(self.allocator);
        defer param_names.deinit();

        var iter = self.all_params[0].values.iterator();
        while (iter.next()) |entry| {
            try param_names.append(entry.key_ptr.*);
        }

        // Write header
        for (param_names.items) |name| {
            try writer.print("{s},", .{name});
        }
        try writer.writeAll("sharpe_ratio,profit_factor,win_rate,max_drawdown\n");

        // Data rows
        for (self.all_results, 0..) |*result, i| {
            const params = self.all_params[i];

            // Write parameter values
            for (param_names.items) |name| {
                const value = params.get(name).?;
                switch (value) {
                    .integer => |v| try writer.print("{},", .{v}),
                    .decimal => |v| {
                        const f = try v.toFloat();
                        try writer.print("{d:.6},", .{f});
                    },
                    .boolean => |v| try writer.print("{},", .{v}),
                    .discrete => |v| try writer.print("{s},", .{v}),
                }
            }

            // Write metrics
            try writer.print("{d:.6},", .{result.metrics.sharpe_ratio});
            try writer.print("{d:.6},", .{result.metrics.profit_factor});
            try writer.print("{d:.6},", .{result.metrics.win_rate});
            try writer.print("{d:.6}\n", .{result.metrics.max_drawdown});
        }

        try buffered.flush();
    }

    fn writeParameterSetJson(
        self: *const OptimizationResult,
        writer: anytype,
        params: types.ParameterSet,
    ) !void {
        _ = self;
        try writer.writeAll("{ ");

        var iter = params.values.iterator();
        var first = true;
        while (iter.next()) |entry| {
            if (!first) try writer.writeAll(", ");
            first = false;

            try writer.print("\"{s}\": ", .{entry.key_ptr.*});
            const value = entry.value_ptr.*;
            switch (value) {
                .integer => |v| try writer.print("{}", .{v}),
                .decimal => |v| {
                    const f = try v.toFloat();
                    try writer.print("{d:.6}", .{f});
                },
                .boolean => |v| try writer.print("{}", .{v}),
                .discrete => |v| try writer.print("\"{s}\"", .{v}),
            }
        }

        try writer.writeAll(" }");
    }
};

fn scoreBacktestResult(result: *const BacktestResult, objective: types.OptimizationObjective) f64 {
    return switch (objective) {
        .maximize_sharpe_ratio => result.metrics.sharpe_ratio,
        .maximize_profit_factor => result.metrics.profit_factor,
        .maximize_win_rate => result.metrics.win_rate,
        .minimize_max_drawdown => -result.metrics.max_drawdown,
        .maximize_net_profit => result.metrics.net_profit.toFloat() catch 0.0,
        .custom => 0.0,
    };
}
```

---

## Memory Management

### Ownership Rules

1. **ParameterSet**: Caller owns, must call `deinit()`
2. **OptimizationResult**: Caller owns, must call `deinit()`
3. **BacktestResult**: Owned by OptimizationResult
4. **Strategy instances**: Created and destroyed per backtest

### Memory Lifecycle

```zig
pub fn optimize(...) !OptimizationResult {
    // 1. Generate combinations (temporary, freed before return)
    const all_params = try generator.generateAll();
    defer {
        for (all_params) |*params| params.deinit();
        self.allocator.free(all_params);
    }

    // 2. Accumulate results (transferred to OptimizationResult)
    var all_results = std.ArrayList(BacktestResult).init(self.allocator);
    var successful_params = std.ArrayList(types.ParameterSet).init(self.allocator);

    // 3. Run backtests
    for (all_params[0..test_count]) |param_set| {
        const strategy = strategy_factory(self.allocator, param_set) catch continue;
        defer {
            var mut_strategy = strategy;
            mut_strategy.deinit();  // Strategy freed immediately
        }

        const result = self.engine.run(strategy, config.backtest_config) catch continue;
        try all_results.append(result);  // Result moved to list
        try successful_params.append(try param_set.clone());  // Clone param set
    }

    // 4. Transfer ownership to OptimizationResult
    return OptimizationResult{
        .all_results = try all_results.toOwnedSlice(),  // ArrayList releases ownership
        .all_params = try successful_params.toOwnedSlice(),
        // ...
    };
}
```

### Arena Allocator for Temporary Data

```zig
pub fn optimize(...) !OptimizationResult {
    // Use arena for temporary allocations
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();

    // Generate combinations with arena
    var generator = CombinationGenerator.init(temp_allocator, config.parameters);
    const all_params = try generator.generateAll();
    // No need to manually free - arena.deinit() handles it

    // ... rest of implementation
}
```

---

## Error Handling

### Error Types

```zig
pub const OptimizerError = error{
    // Configuration errors
    InvalidRange,
    InvalidStep,
    StepTooLarge,
    TypeMismatch,
    MissingRange,
    RangeTypeMismatch,
    EmptyDiscreteValues,
    NoParametersToOptimize,

    // Runtime errors
    NoValidCombinations,
    AllBacktestsFailed,
    NoResults,
    TooManyCombinations,
    CustomObjectiveNotSupported,
} || std.mem.Allocator.Error;
```

### Error Handling Strategy

```zig
// Fail fast on configuration errors
pub fn optimize(...) !OptimizationResult {
    try config.validate();  // Fail immediately if invalid

    // Continue on individual backtest failures
    for (all_params) |param_set| {
        const strategy = strategy_factory(...) catch |err| {
            self.logger.err("Strategy creation failed: {}", .{err});
            failed_count += 1;
            continue;  // Try next combination
        };

        const result = self.engine.run(...) catch |err| {
            self.logger.err("Backtest failed: {}", .{err});
            failed_count += 1;
            continue;  // Try next combination
        };

        // Store successful result
    }

    // Fail if no backtests succeeded
    if (all_results.items.len == 0) {
        return error.AllBacktestsFailed;
    }
}
```

---

## Performance Optimization

### 1. Combination Count Estimation

```zig
// Check count before generating
const generator = CombinationGenerator.init(allocator, &params);
const count = try generator.countCombinations();

if (count > 100_000) {
    logger.warn("Very large search space: {} combinations", .{count});
    logger.warn("Consider reducing parameter ranges or using max_combinations", .{});
}
```

### 2. Early Termination

```zig
// Limit combinations if too many
const test_count = if (config.max_combinations) |max|
    @min(max, total_count)
else
    total_count;

for (all_params[0..test_count]) |param_set| {
    // Only test first N combinations
}
```

### 3. Progress Reporting

```zig
// Log progress every 10 combinations
if ((i + 1) % 10 == 0 or i + 1 == test_count) {
    const progress = @as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(test_count)) * 100.0;
    self.logger.info("Progress: {d:.1}% ({}/{})", .{ progress, i + 1, test_count });
}
```

### 4. Parallel Execution (v0.4.0+)

```zig
// Future: parallel backtest execution
if (config.enable_parallel) {
    const thread_pool = try std.Thread.Pool.init(allocator, .{});
    defer thread_pool.deinit();

    // Distribute combinations across threads
    // Synchronize result collection
}
```

---

## Testing Strategy

### Unit Tests

```zig
test "ParameterSet basic operations" {
    const allocator = std.testing.allocator;

    var params = ParameterSet.init(allocator);
    defer params.deinit();

    try params.set("period", .{ .integer = 14 });
    try std.testing.expectEqual(@as(i64, 14), params.get("period").?.integer);
}

test "IntegerRange validation" {
    const valid = IntegerRange{ .min = 5, .max = 20, .step = 5 };
    try valid.validate();

    const invalid_range = IntegerRange{ .min = 20, .max = 5, .step = 5 };
    try std.testing.expectError(error.InvalidRange, invalid_range.validate());

    const invalid_step = IntegerRange{ .min = 5, .max = 20, .step = 0 };
    try std.testing.expectError(error.InvalidStep, invalid_step.validate());
}

test "CombinationGenerator count" {
    const allocator = std.testing.allocator;

    var params = [_]StrategyParameter{
        .{
            .name = "a",
            .type = .integer,
            .default_value = .{ .integer = 1 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 1, .max = 3, .step = 1 } },  // 3 values
        },
        .{
            .name = "b",
            .type = .boolean,
            .default_value = .{ .boolean = false },
            .optimize = true,
            .range = .{ .boolean = {} },  // 2 values
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    const count = try generator.countCombinations();
    try std.testing.expectEqual(@as(usize, 6), count);  // 3 × 2 = 6
}
```

### Integration Tests

```zig
test "GridSearchOptimizer full flow" {
    const allocator = std.testing.allocator;

    // Setup logger, engine, config
    // ...

    var optimizer = GridSearchOptimizer.init(allocator, logger, &engine);
    defer optimizer.deinit();

    const result = try optimizer.optimize(mockStrategyFactory, opt_config);
    defer result.deinit();

    try std.testing.expect(result.successful_combinations > 0);
    try std.testing.expect(result.best_score > 0);
}
```

---

## Best Practices

1. **Always validate parameters** before optimization
2. **Use arena allocators** for temporary data
3. **Log progress** for long-running optimizations
4. **Handle backtest failures** gracefully
5. **Limit combination count** for exploratory runs
6. **Export results** for analysis
7. **Check memory usage** for large search spaces

---

**Version**: v0.3.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-25
