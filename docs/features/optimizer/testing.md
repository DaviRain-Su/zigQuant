# Parameter Optimizer Testing Guide

**Version**: v0.3.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-25

---

## Table of Contents

1. [Testing Strategy](#testing-strategy)
2. [Unit Tests](#unit-tests)
3. [Integration Tests](#integration-tests)
4. [End-to-End Tests](#end-to-end-tests)
5. [Performance Tests](#performance-tests)
6. [Validation Tests](#validation-tests)
7. [Test Utilities](#test-utilities)

---

## Testing Strategy

### Test Pyramid

```
           /\
          /  \    E2E Tests (5%)
         /____\   - Full optimization flow with real data
        /      \
       / Integ. \ Integration Tests (25%)
      /  Tests   \  - Component interactions
     /____________\
    /              \
   /  Unit Tests    \ Unit Tests (70%)
  /                  \  - Individual functions and types
 /____________________\
```

### Coverage Requirements

- **Overall Coverage**: > 85%
- **Critical Paths**: 100% (combination generation, scoring, result handling)
- **Error Paths**: > 90%

### Test Organization

```
optimizer/tests/
├── types_test.zig           # Type-related tests
├── combination_test.zig     # Combination generation tests
├── grid_search_test.zig     # Grid search optimizer tests
├── result_test.zig          # Result handling tests
├── integration_test.zig     # Integration tests
├── e2e_test.zig            # End-to-end tests
├── performance_test.zig     # Performance benchmarks
└── test_utils.zig          # Shared test utilities
```

---

## Unit Tests

### 1. Type Tests (types_test.zig)

#### ParameterValue Tests

```zig
const std = @import("std");
const testing = std.testing;
const types = @import("../types.zig");
const Decimal = @import("../../core/decimal.zig").Decimal;

test "ParameterValue: integer equality" {
    const v1 = types.ParameterValue{ .integer = 42 };
    const v2 = types.ParameterValue{ .integer = 42 };
    const v3 = types.ParameterValue{ .integer = 43 };

    try testing.expect(v1.eql(v2));
    try testing.expect(!v1.eql(v3));
}

test "ParameterValue: decimal equality" {
    const v1 = types.ParameterValue{ .decimal = try Decimal.fromString("3.14") };
    const v2 = types.ParameterValue{ .decimal = try Decimal.fromString("3.14") };
    const v3 = types.ParameterValue{ .decimal = try Decimal.fromString("3.15") };

    try testing.expect(v1.eql(v2));
    try testing.expect(!v1.eql(v3));
}

test "ParameterValue: boolean equality" {
    const v1 = types.ParameterValue{ .boolean = true };
    const v2 = types.ParameterValue{ .boolean = true };
    const v3 = types.ParameterValue{ .boolean = false };

    try testing.expect(v1.eql(v2));
    try testing.expect(!v1.eql(v3));
}

test "ParameterValue: discrete equality" {
    const v1 = types.ParameterValue{ .discrete = "option_a" };
    const v2 = types.ParameterValue{ .discrete = "option_a" };
    const v3 = types.ParameterValue{ .discrete = "option_b" };

    try testing.expect(v1.eql(v2));
    try testing.expect(!v1.eql(v3));
}

test "ParameterValue: type mismatch" {
    const v1 = types.ParameterValue{ .integer = 42 };
    const v2 = types.ParameterValue{ .decimal = try Decimal.fromString("42.0") };

    try testing.expect(!v1.eql(v2));
}
```

#### Range Tests

```zig
test "IntegerRange: validation - valid range" {
    const range = types.IntegerRange{ .min = 5, .max = 20, .step = 5 };
    try range.validate();
}

test "IntegerRange: validation - min >= max" {
    const range = types.IntegerRange{ .min = 20, .max = 5, .step = 5 };
    try testing.expectError(error.InvalidRange, range.validate());
}

test "IntegerRange: validation - zero step" {
    const range = types.IntegerRange{ .min = 5, .max = 20, .step = 0 };
    try testing.expectError(error.InvalidStep, range.validate());
}

test "IntegerRange: validation - negative step" {
    const range = types.IntegerRange{ .min = 5, .max = 20, .step = -5 };
    try testing.expectError(error.InvalidStep, range.validate());
}

test "IntegerRange: validation - step too large" {
    const range = types.IntegerRange{ .min = 5, .max = 20, .step = 100 };
    try testing.expectError(error.StepTooLarge, range.validate());
}

test "IntegerRange: count calculation" {
    const range = types.IntegerRange{ .min = 5, .max = 20, .step = 5 };
    try testing.expectEqual(@as(usize, 4), range.count());  // 5, 10, 15, 20
}

test "DecimalRange: validation and count" {
    const range = types.DecimalRange{
        .min = try Decimal.fromString("0.1"),
        .max = try Decimal.fromString("0.9"),
        .step = try Decimal.fromString("0.2"),
    };
    try range.validate();

    const count = try range.count();
    try testing.expectEqual(@as(usize, 5), count);  // 0.1, 0.3, 0.5, 0.7, 0.9
}
```

#### ParameterSet Tests

```zig
test "ParameterSet: basic operations" {
    const allocator = testing.allocator;

    var params = types.ParameterSet.init(allocator);
    defer params.deinit();

    // Set and get
    try params.set("period", .{ .integer = 14 });
    const value = params.get("period");
    try testing.expect(value != null);
    try testing.expectEqual(@as(i64, 14), value.?.integer);

    // Non-existent key
    const missing = params.get("nonexistent");
    try testing.expect(missing == null);
}

test "ParameterSet: clone" {
    const allocator = testing.allocator;

    var original = types.ParameterSet.init(allocator);
    defer original.deinit();

    try original.set("a", .{ .integer = 1 });
    try original.set("b", .{ .boolean = true });

    var cloned = try original.clone();
    defer cloned.deinit();

    try testing.expectEqual(@as(i64, 1), cloned.get("a").?.integer);
    try testing.expect(cloned.get("b").?.boolean);

    // Modify clone, original unchanged
    try cloned.set("a", .{ .integer = 2 });
    try testing.expectEqual(@as(i64, 1), original.get("a").?.integer);
    try testing.expectEqual(@as(i64, 2), cloned.get("a").?.integer);
}

test "ParameterSet: format" {
    const allocator = testing.allocator;

    var params = types.ParameterSet.init(allocator);
    defer params.deinit();

    try params.set("period", .{ .integer = 14 });
    try params.set("enabled", .{ .boolean = true });

    var buf: [256]u8 = undefined;
    const result = try std.fmt.bufPrint(&buf, "{}", .{params});

    try testing.expect(std.mem.indexOf(u8, result, "period: 14") != null);
    try testing.expect(std.mem.indexOf(u8, result, "enabled: true") != null);
}
```

#### StrategyParameter Tests

```zig
test "StrategyParameter: validation - valid config" {
    const param = types.StrategyParameter{
        .name = "period",
        .type = .integer,
        .default_value = .{ .integer = 10 },
        .optimize = true,
        .range = .{ .integer = .{ .min = 5, .max = 20, .step = 5 } },
    };
    try param.validate();
}

test "StrategyParameter: validation - type mismatch" {
    const param = types.StrategyParameter{
        .name = "period",
        .type = .integer,
        .default_value = .{ .decimal = try Decimal.fromString("10.0") },  // Wrong!
        .optimize = true,
        .range = .{ .integer = .{ .min = 5, .max = 20, .step = 5 } },
    };
    try testing.expectError(error.TypeMismatch, param.validate());
}

test "StrategyParameter: validation - optimize without range" {
    const param = types.StrategyParameter{
        .name = "period",
        .type = .integer,
        .default_value = .{ .integer = 10 },
        .optimize = true,
        .range = null,  // Missing range!
    };
    try testing.expectError(error.MissingRange, param.validate());
}

test "StrategyParameter: validation - range type mismatch" {
    const param = types.StrategyParameter{
        .name = "period",
        .type = .integer,
        .default_value = .{ .integer = 10 },
        .optimize = true,
        .range = .{ .decimal = .{  // Wrong range type!
            .min = try Decimal.fromString("5.0"),
            .max = try Decimal.fromString("20.0"),
            .step = try Decimal.fromString("5.0"),
        } },
    };
    try testing.expectError(error.RangeTypeMismatch, param.validate());
}
```

---

### 2. Combination Generator Tests (combination_test.zig)

```zig
const std = @import("std");
const testing = std.testing;
const types = @import("../types.zig");
const CombinationGenerator = @import("../combination.zig").CombinationGenerator;
const Decimal = @import("../../core/decimal.zig").Decimal;

test "CombinationGenerator: count - single integer parameter" {
    const allocator = testing.allocator;

    var params = [_]types.StrategyParameter{
        .{
            .name = "period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 5, .max = 20, .step = 5 } },
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    const count = try generator.countCombinations();
    try testing.expectEqual(@as(usize, 4), count);  // 5, 10, 15, 20
}

test "CombinationGenerator: count - multiple parameters" {
    const allocator = testing.allocator;

    var params = [_]types.StrategyParameter{
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
        .{
            .name = "c",
            .type = .discrete,
            .default_value = .{ .discrete = "x" },
            .optimize = true,
            .range = .{ .discrete = &[_][]const u8{ "x", "y" } },  // 2 values
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    const count = try generator.countCombinations();
    try testing.expectEqual(@as(usize, 12), count);  // 3 × 2 × 2 = 12
}

test "CombinationGenerator: generate - integer values" {
    const allocator = testing.allocator;

    var params = [_]types.StrategyParameter{
        .{
            .name = "period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 5, .max = 15, .step = 5 } },
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    const combinations = try generator.generateAll();
    defer {
        for (combinations) |*combo| combo.deinit();
        allocator.free(combinations);
    }

    try testing.expectEqual(@as(usize, 3), combinations.len);

    try testing.expectEqual(@as(i64, 5), combinations[0].get("period").?.integer);
    try testing.expectEqual(@as(i64, 10), combinations[1].get("period").?.integer);
    try testing.expectEqual(@as(i64, 15), combinations[2].get("period").?.integer);
}

test "CombinationGenerator: generate - boolean values" {
    const allocator = testing.allocator;

    var params = [_]types.StrategyParameter{
        .{
            .name = "use_stop",
            .type = .boolean,
            .default_value = .{ .boolean = false },
            .optimize = true,
            .range = .{ .boolean = {} },
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    const combinations = try generator.generateAll();
    defer {
        for (combinations) |*combo| combo.deinit();
        allocator.free(combinations);
    }

    try testing.expectEqual(@as(usize, 2), combinations.len);
    try testing.expect(!combinations[0].get("use_stop").?.boolean);
    try testing.expect(combinations[1].get("use_stop").?.boolean);
}

test "CombinationGenerator: generate - discrete values" {
    const allocator = testing.allocator;

    var params = [_]types.StrategyParameter{
        .{
            .name = "mode",
            .type = .discrete,
            .default_value = .{ .discrete = "fast" },
            .optimize = true,
            .range = .{ .discrete = &[_][]const u8{ "fast", "slow", "adaptive" } },
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    const combinations = try generator.generateAll();
    defer {
        for (combinations) |*combo| combo.deinit();
        allocator.free(combinations);
    }

    try testing.expectEqual(@as(usize, 3), combinations.len);
    try testing.expectEqualStrings("fast", combinations[0].get("mode").?.discrete);
    try testing.expectEqualStrings("slow", combinations[1].get("mode").?.discrete);
    try testing.expectEqualStrings("adaptive", combinations[2].get("mode").?.discrete);
}

test "CombinationGenerator: generate - cartesian product" {
    const allocator = testing.allocator;

    var params = [_]types.StrategyParameter{
        .{
            .name = "a",
            .type = .integer,
            .default_value = .{ .integer = 1 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 1, .max = 2, .step = 1 } },  // [1, 2]
        },
        .{
            .name = "b",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 10, .max = 20, .step = 10 } },  // [10, 20]
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    const combinations = try generator.generateAll();
    defer {
        for (combinations) |*combo| combo.deinit();
        allocator.free(combinations);
    }

    try testing.expectEqual(@as(usize, 4), combinations.len);  // 2 × 2 = 4

    // Expected: (1,10), (2,10), (1,20), (2,20)
    try testing.expectEqual(@as(i64, 1), combinations[0].get("a").?.integer);
    try testing.expectEqual(@as(i64, 10), combinations[0].get("b").?.integer);

    try testing.expectEqual(@as(i64, 2), combinations[1].get("a").?.integer);
    try testing.expectEqual(@as(i64, 10), combinations[1].get("b").?.integer);

    try testing.expectEqual(@as(i64, 1), combinations[2].get("a").?.integer);
    try testing.expectEqual(@as(i64, 20), combinations[2].get("b").?.integer);

    try testing.expectEqual(@as(i64, 2), combinations[3].get("a").?.integer);
    try testing.expectEqual(@as(i64, 20), combinations[3].get("b").?.integer);
}

test "CombinationGenerator: skip non-optimize parameters" {
    const allocator = testing.allocator;

    var params = [_]types.StrategyParameter{
        .{
            .name = "a",
            .type = .integer,
            .default_value = .{ .integer = 1 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 1, .max = 2, .step = 1 } },
        },
        .{
            .name = "b",
            .type = .integer,
            .default_value = .{ .integer = 100 },
            .optimize = false,  // Not optimized
            .range = null,
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    const count = try generator.countCombinations();
    try testing.expectEqual(@as(usize, 2), count);  // Only 'a' varies
}
```

---

### 3. Grid Search Tests (grid_search_test.zig)

```zig
const std = @import("std");
const testing = std.testing;
const types = @import("../types.zig");
const GridSearchOptimizer = @import("../grid_search.zig").GridSearchOptimizer;
const test_utils = @import("test_utils.zig");

test "GridSearchOptimizer: scoreResult - maximize sharpe" {
    const allocator = testing.allocator;

    var logger = try test_utils.createTestLogger(allocator);
    defer logger.deinit();

    var engine = try test_utils.createMockBacktestEngine(allocator);
    defer engine.deinit();

    var optimizer = GridSearchOptimizer.init(allocator, logger, &engine);
    defer optimizer.deinit();

    const result = test_utils.createMockBacktestResult(.{
        .sharpe_ratio = 1.5,
        .profit_factor = 2.0,
        .win_rate = 0.6,
        .max_drawdown = -0.15,
    });

    const score = try optimizer.scoreResult(&result, .maximize_sharpe_ratio);
    try testing.expectApproxEqAbs(1.5, score, 0.001);
}

test "GridSearchOptimizer: scoreResult - minimize drawdown" {
    const allocator = testing.allocator;

    var logger = try test_utils.createTestLogger(allocator);
    defer logger.deinit();

    var engine = try test_utils.createMockBacktestEngine(allocator);
    defer engine.deinit();

    var optimizer = GridSearchOptimizer.init(allocator, logger, &engine);
    defer optimizer.deinit();

    const result = test_utils.createMockBacktestResult(.{
        .sharpe_ratio = 1.5,
        .max_drawdown = -0.15,
    });

    const score = try optimizer.scoreResult(&result, .minimize_max_drawdown);
    try testing.expectApproxEqAbs(0.15, score, 0.001);  // Negated
}

test "GridSearchOptimizer: findBestResult" {
    const allocator = testing.allocator;

    var logger = try test_utils.createTestLogger(allocator);
    defer logger.deinit();

    var engine = try test_utils.createMockBacktestEngine(allocator);
    defer engine.deinit();

    var optimizer = GridSearchOptimizer.init(allocator, logger, &engine);
    defer optimizer.deinit();

    const results = [_]test_utils.MockBacktestResult{
        test_utils.createMockBacktestResult(.{ .sharpe_ratio = 1.0 }),
        test_utils.createMockBacktestResult(.{ .sharpe_ratio = 2.5 }),  // Best
        test_utils.createMockBacktestResult(.{ .sharpe_ratio = 1.8 }),
    };

    const best = try optimizer.findBestResult(&results, .maximize_sharpe_ratio);

    try testing.expectEqual(@as(usize, 1), best.index);
    try testing.expectApproxEqAbs(2.5, best.score, 0.001);
}
```

---

### 4. Result Tests (result_test.zig)

```zig
const std = @import("std");
const testing = std.testing;
const types = @import("../types.zig");
const OptimizationResult = @import("../result.zig").OptimizationResult;
const test_utils = @import("test_utils.zig");

test "OptimizationResult: getRankedResults" {
    const allocator = testing.allocator;

    var best_params = types.ParameterSet.init(allocator);
    try best_params.set("period", .{ .integer = 10 });

    var all_params = try allocator.alloc(types.ParameterSet, 3);
    for (all_params, 0..) |*p, i| {
        p.* = types.ParameterSet.init(allocator);
        try p.set("period", .{ .integer = @as(i64, @intCast(i * 10)) });
    }

    const all_results = try allocator.alloc(test_utils.MockBacktestResult, 3);
    all_results[0] = test_utils.createMockBacktestResult(.{ .sharpe_ratio = 1.0 });
    all_results[1] = test_utils.createMockBacktestResult(.{ .sharpe_ratio = 2.5 });
    all_results[2] = test_utils.createMockBacktestResult(.{ .sharpe_ratio = 1.8 });

    var result = OptimizationResult{
        .allocator = allocator,
        .best_params = best_params,
        .best_score = 2.5,
        .all_results = all_results,
        .all_params = all_params,
        .total_combinations = 3,
        .successful_combinations = 3,
        .failed_combinations = 0,
    };
    defer result.deinit();

    const ranked = try result.getRankedResults(.maximize_sharpe_ratio, 2);
    defer {
        for (ranked) |*r| r.params.deinit();
        allocator.free(ranked);
    }

    try testing.expectEqual(@as(usize, 2), ranked.len);
    try testing.expectApproxEqAbs(2.5, ranked[0].score, 0.001);  // Best first
    try testing.expectApproxEqAbs(1.8, ranked[1].score, 0.001);
}

test "OptimizationResult: exportToJson" {
    const allocator = testing.allocator;

    // Create minimal result
    var best_params = types.ParameterSet.init(allocator);
    try best_params.set("period", .{ .integer = 10 });

    var all_params = try allocator.alloc(types.ParameterSet, 1);
    all_params[0] = try best_params.clone();

    const all_results = try allocator.alloc(test_utils.MockBacktestResult, 1);
    all_results[0] = test_utils.createMockBacktestResult(.{ .sharpe_ratio = 1.5 });

    var result = OptimizationResult{
        .allocator = allocator,
        .best_params = best_params,
        .best_score = 1.5,
        .all_results = all_results,
        .all_params = all_params,
        .total_combinations = 1,
        .successful_combinations = 1,
        .failed_combinations = 0,
    };
    defer result.deinit();

    // Export to temp file
    const temp_path = "test_export.json";
    defer std.fs.cwd().deleteFile(temp_path) catch {};

    try result.exportToJson(temp_path);

    // Verify file exists
    const file = try std.fs.cwd().openFile(temp_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "best_params") != null);
    try testing.expect(std.mem.indexOf(u8, content, "best_score") != null);
    try testing.expect(std.mem.indexOf(u8, content, "1.5") != null);
}
```

---

## Integration Tests

### Full Optimization Flow

```zig
// integration_test.zig
const std = @import("std");
const testing = std.testing;
const test_utils = @import("test_utils.zig");
const GridSearchOptimizer = @import("../grid_search.zig").GridSearchOptimizer;
const types = @import("../types.zig");

test "Integration: full optimization flow" {
    const allocator = testing.allocator;

    var logger = try test_utils.createTestLogger(allocator);
    defer logger.deinit();

    var engine = try test_utils.createMockBacktestEngine(allocator);
    defer engine.deinit();

    var optimizer = GridSearchOptimizer.init(allocator, logger, &engine);
    defer optimizer.deinit();

    // Define parameters
    var params = [_]types.StrategyParameter{
        .{
            .name = "fast_period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 5, .max = 15, .step = 5 } },
        },
        .{
            .name = "slow_period",
            .type = .integer,
            .default_value = .{ .integer = 20 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 20, .max = 30, .step = 10 } },
        },
    };

    const backtest_config = test_utils.createMockBacktestConfig();

    const opt_config = types.OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = backtest_config,
        .parameters = &params,
        .max_combinations = null,
        .enable_parallel = false,
    };

    const result = try optimizer.optimize(test_utils.mockStrategyFactory, opt_config);
    defer result.deinit();

    // Verify results
    try testing.expect(result.total_combinations == 6);  // 3 × 2 = 6
    try testing.expect(result.successful_combinations > 0);
    try testing.expect(result.best_score > 0);
    try testing.expect(result.best_params.get("fast_period") != null);
    try testing.expect(result.best_params.get("slow_period") != null);
}

test "Integration: optimization with failures" {
    const allocator = testing.allocator;

    var logger = try test_utils.createTestLogger(allocator);
    defer logger.deinit();

    var engine = try test_utils.createMockBacktestEngine(allocator);
    defer engine.deinit();

    var optimizer = GridSearchOptimizer.init(allocator, logger, &engine);
    defer optimizer.deinit();

    // Use factory that sometimes fails
    const factory = test_utils.mockStrategyFactoryWithFailures;

    var params = [_]types.StrategyParameter{
        .{
            .name = "period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 5, .max = 15, .step = 5 } },
        },
    };

    const opt_config = types.OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = test_utils.createMockBacktestConfig(),
        .parameters = &params,
        .max_combinations = null,
        .enable_parallel = false,
    };

    const result = try optimizer.optimize(factory, opt_config);
    defer result.deinit();

    // Some should succeed, some fail
    try testing.expect(result.successful_combinations > 0);
    try testing.expect(result.failed_combinations > 0);
    try testing.expectEqual(
        result.total_combinations,
        result.successful_combinations + result.failed_combinations,
    );
}
```

---

## End-to-End Tests

### Real Data Optimization

```zig
// e2e_test.zig
test "E2E: optimize with real strategy and data" {
    const allocator = testing.allocator;

    // Load real historical data
    var data_feed = try test_utils.loadRealTestData(allocator, "test_data.csv");
    defer data_feed.deinit();

    var logger = try Logger.init(allocator, test_utils.createTestLogConfig());
    defer logger.deinit();

    var engine = try BacktestEngine.init(allocator);
    defer engine.deinit();

    var optimizer = GridSearchOptimizer.init(allocator, logger, &engine);
    defer optimizer.deinit();

    // Real strategy parameters
    var params = [_]types.StrategyParameter{
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
            .default_value = .{ .integer = 30 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 20, .max = 50, .step = 10 } },
        },
    };

    const backtest_config = BacktestConfig{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .timeframe = .m15,
        .start_date = try Timestamp.fromString("2024-01-01T00:00:00Z"),
        .end_date = try Timestamp.fromString("2024-03-01T00:00:00Z"),
        .initial_capital = try Decimal.fromString("10000"),
        .commission_rate = try Decimal.fromString("0.001"),
        .slippage = try Decimal.fromString("0.0005"),
        .position_limit = .one_at_a_time,
    };

    const opt_config = types.OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = backtest_config,
        .parameters = &params,
        .max_combinations = 100,
        .enable_parallel = false,
    };

    const result = try optimizer.optimize(createRealMACrossStrategy, opt_config);
    defer result.deinit();

    // Verify realistic results
    try testing.expect(result.successful_combinations > 0);
    try testing.expect(result.best_score > -3.0 and result.best_score < 10.0);  // Realistic Sharpe
    try testing.expect(result.all_results.len > 0);

    // Export results
    try result.exportToJson("e2e_results.json");
    try result.exportToCsv("e2e_results.csv");
}
```

---

## Performance Tests

### Benchmarks

```zig
// performance_test.zig
test "Performance: combination generation speed" {
    const allocator = testing.allocator;

    var params = [_]types.StrategyParameter{
        .{
            .name = "a",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 1, .max = 100, .step = 1 } },  // 100 values
        },
        .{
            .name = "b",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 1, .max = 10, .step = 1 } },  // 10 values
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);

    const start = std.time.milliTimestamp();
    const combinations = try generator.generateAll();  // 1000 combinations
    const elapsed = std.time.milliTimestamp() - start;

    defer {
        for (combinations) |*combo| combo.deinit();
        allocator.free(combinations);
    }

    std.debug.print("Generated 1000 combinations in {}ms\n", .{elapsed});
    try testing.expect(elapsed < 100);  // Should be < 100ms
}

test "Performance: optimization speed" {
    const allocator = testing.allocator;

    var logger = try test_utils.createTestLogger(allocator);
    defer logger.deinit();

    var engine = try test_utils.createFastMockBacktestEngine(allocator);
    defer engine.deinit();

    var optimizer = GridSearchOptimizer.init(allocator, logger, &engine);
    defer optimizer.deinit();

    var params = [_]types.StrategyParameter{
        .{
            .name = "period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .optimize = true,
            .range = .{ .integer = .{ .min = 5, .max = 50, .step = 5 } },  // 10 values
        },
    };

    const opt_config = types.OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = test_utils.createMockBacktestConfig(),
        .parameters = &params,
        .max_combinations = null,
        .enable_parallel = false,
    };

    const start = std.time.milliTimestamp();
    const result = try optimizer.optimize(test_utils.mockStrategyFactory, opt_config);
    const elapsed = std.time.milliTimestamp() - start;
    defer result.deinit();

    std.debug.print("Optimized 10 combinations in {}ms\n", .{elapsed});
    try testing.expect(elapsed < 5000);  // Should be < 5s with mock engine
}
```

---

## Validation Tests

### Overfitting Detection

```zig
test "Validation: parameter stability check" {
    // Run optimization multiple times with different data splits
    // Verify that optimal parameters are consistent
    // Flag if best parameters change drastically between runs
}

test "Validation: out-of-sample performance" {
    // Optimize on training data
    // Validate on test data
    // Check that performance doesn't degrade significantly
}
```

---

## Test Utilities

### test_utils.zig

```zig
const std = @import("std");
const types = @import("../types.zig");
const IStrategy = @import("../../strategy/interface.zig").IStrategy;
const BacktestEngine = @import("../../backtest/engine.zig").BacktestEngine;
const BacktestConfig = @import("../../backtest/config.zig").BacktestConfig;
const BacktestResult = @import("../../backtest/result.zig").BacktestResult;
const Logger = @import("../../core/logger.zig").Logger;
const Decimal = @import("../../core/decimal.zig").Decimal;

pub fn createTestLogger(allocator: std.mem.Allocator) !Logger {
    return Logger.init(allocator, .{
        .level = .debug,
        .output = .stdout,
    });
}

pub fn createMockBacktestEngine(allocator: std.mem.Allocator) !BacktestEngine {
    // Return a mock engine that returns predictable results
    _ = allocator;
    return error.NotImplemented;
}

pub const MockBacktestResult = struct {
    metrics: struct {
        sharpe_ratio: f64,
        profit_factor: f64,
        win_rate: f64,
        max_drawdown: f64,
        net_profit: Decimal,
    },

    pub fn deinit(self: *MockBacktestResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub fn createMockBacktestResult(metrics: anytype) MockBacktestResult {
    return .{
        .metrics = .{
            .sharpe_ratio = metrics.sharpe_ratio orelse 0.0,
            .profit_factor = metrics.profit_factor orelse 1.0,
            .win_rate = metrics.win_rate orelse 0.5,
            .max_drawdown = metrics.max_drawdown orelse 0.0,
            .net_profit = Decimal.ZERO,
        },
    };
}

pub fn mockStrategyFactory(
    allocator: std.mem.Allocator,
    params: types.ParameterSet,
) !IStrategy {
    _ = allocator;
    _ = params;
    return error.NotImplemented;
}

pub fn mockStrategyFactoryWithFailures(
    allocator: std.mem.Allocator,
    params: types.ParameterSet,
) !IStrategy {
    // Fail for some parameter combinations
    if (params.get("period")) |p| {
        if (p.integer == 10) {
            return error.InvalidConfiguration;
        }
    }
    return mockStrategyFactory(allocator, params);
}
```

---

## CI/CD Integration

### GitHub Actions Test Workflow

```yaml
name: Optimizer Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.2

      - name: Run unit tests
        run: zig build test-optimizer-unit

      - name: Run integration tests
        run: zig build test-optimizer-integration

      - name: Run E2E tests
        run: zig build test-optimizer-e2e

      - name: Check coverage
        run: zig build test-optimizer-coverage
```

---

## Testing Checklist

Before merging:

- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] E2E tests with real data pass
- [ ] Performance benchmarks meet targets
- [ ] Code coverage > 85%
- [ ] No memory leaks (valgrind/GPA)
- [ ] Documentation tests pass

---

**Version**: v0.3.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-25
