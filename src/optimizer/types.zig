/// Parameter Optimizer Types
///
/// Defines core types for strategy parameter optimization:
/// - Parameter definitions and ranges
/// - Parameter sets and combinations
/// - Optimization objectives and results
///
/// This module provides type-safe parameter handling for grid search
/// and other optimization algorithms.

const std = @import("std");
const root = @import("../root.zig");
const Decimal = root.Decimal;
const BacktestResult = root.BacktestResult;
const BacktestConfig = root.BacktestConfig;

/// Parameter type enumeration
pub const ParameterType = enum {
    integer,
    decimal,
    boolean,
    discrete,
};

/// Parameter value union - holds actual parameter values
pub const ParameterValue = union(ParameterType) {
    integer: i64,
    decimal: Decimal,
    boolean: bool,
    discrete: []const u8,

    /// Format parameter value for display
    pub fn format(
        self: ParameterValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .integer => |val| try writer.print("{d}", .{val}),
            .decimal => |val| try writer.print("{}", .{val}),
            .boolean => |val| try writer.print("{}", .{val}),
            .discrete => |val| try writer.print("{s}", .{val}),
        }
    }

    /// Clone parameter value
    pub fn clone(self: ParameterValue, allocator: std.mem.Allocator) !ParameterValue {
        return switch (self) {
            .integer => |val| ParameterValue{ .integer = val },
            .decimal => |val| ParameterValue{ .decimal = val },
            .boolean => |val| ParameterValue{ .boolean = val },
            .discrete => |val| ParameterValue{ .discrete = try allocator.dupe(u8, val) },
        };
    }

    /// Free allocated memory (for discrete values)
    pub fn deinit(self: ParameterValue, allocator: std.mem.Allocator) void {
        switch (self) {
            .discrete => |val| allocator.free(val),
            else => {},
        }
    }
};

/// Integer parameter range
pub const IntegerRange = struct {
    min: i64,
    max: i64,
    step: i64,

    /// Count number of values in this range
    pub fn count(self: IntegerRange) u32 {
        if (self.step == 0) return 0;
        const range = self.max - self.min;
        return @intCast(@divTrunc(range, self.step) + 1);
    }
};

/// Decimal parameter range
pub const DecimalRange = struct {
    min: Decimal,
    max: Decimal,
    step: Decimal,

    /// Count number of values in this range
    pub fn count(self: DecimalRange) !u32 {
        const range = self.max.sub(self.min);
        const steps = try range.div(self.step);
        const steps_float = steps.toFloat();
        return @intFromFloat(steps_float + 1.0);
    }
};

/// Parameter range union - defines search space for a parameter
pub const ParameterRange = union(ParameterType) {
    integer: IntegerRange,
    decimal: DecimalRange,
    boolean: void,
    discrete: []const ParameterValue,

    /// Count number of values in this range
    pub fn count(self: ParameterRange) !u32 {
        return switch (self) {
            .integer => |r| r.count(),
            .decimal => |r| try r.count(),
            .boolean => 2,
            .discrete => |vals| @intCast(vals.len),
        };
    }
};

/// Strategy parameter definition
pub const StrategyParameter = struct {
    name: []const u8,
    type: ParameterType,
    default_value: ParameterValue,
    optimize: bool,
    range: ?ParameterRange,

    /// Validate parameter definition
    pub fn validate(self: *const StrategyParameter) !void {
        // If optimize is true, range must be provided
        if (self.optimize and self.range == null) {
            return error.MissingParameterRange;
        }

        // Type of default_value must match parameter type
        if (@intFromEnum(self.default_value) != @intFromEnum(self.type)) {
            return error.ParameterTypeMismatch;
        }

        // If range is provided, type must match
        if (self.range) |range| {
            if (@intFromEnum(range) != @intFromEnum(self.type)) {
                return error.ParameterRangeMismatch;
            }
        }
    }
};

/// Parameter set - a combination of parameter values
pub const ParameterSet = struct {
    allocator: std.mem.Allocator,
    values: std.StringHashMap(ParameterValue),

    /// Initialize parameter set
    pub fn init(allocator: std.mem.Allocator) ParameterSet {
        return .{
            .allocator = allocator,
            .values = std.StringHashMap(ParameterValue).init(allocator),
        };
    }

    /// Deinitialize parameter set
    pub fn deinit(self: *ParameterSet) void {
        // Free keys and values
        var iter = self.values.iterator();
        while (iter.next()) |entry| {
            // Free the key (owned name)
            self.allocator.free(entry.key_ptr.*);
            // Free the value
            entry.value_ptr.deinit(self.allocator);
        }
        self.values.deinit();
    }

    /// Set parameter value
    pub fn set(self: *ParameterSet, name: []const u8, value: ParameterValue) !void {
        // Clone the value to ensure ownership
        const cloned_value = try value.clone(self.allocator);
        errdefer cloned_value.deinit(self.allocator);

        // Check if key already exists
        const gop = try self.values.getOrPut(name);

        if (gop.found_existing) {
            // Free old value
            gop.value_ptr.deinit(self.allocator);
            // Update with new value
            gop.value_ptr.* = cloned_value;
        } else {
            // Duplicate the name for new entry
            const owned_name = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(owned_name);

            // Update key to owned name
            gop.key_ptr.* = owned_name;
            gop.value_ptr.* = cloned_value;
        }
    }

    /// Get parameter value
    pub fn get(self: *const ParameterSet, name: []const u8) ?ParameterValue {
        return self.values.get(name);
    }

    /// Clone parameter set
    pub fn clone(self: *const ParameterSet, allocator: std.mem.Allocator) !ParameterSet {
        var new_set = ParameterSet.init(allocator);
        errdefer new_set.deinit();

        var iter = self.values.iterator();
        while (iter.next()) |entry| {
            try new_set.set(entry.key_ptr.*, entry.value_ptr.*);
        }

        return new_set;
    }

    /// Get parameter count
    pub fn count(self: *const ParameterSet) usize {
        return self.values.count();
    }
};

/// Optimization objective
pub const OptimizationObjective = enum {
    // v0.3.0 objectives
    maximize_sharpe_ratio,
    maximize_profit_factor,
    maximize_win_rate,
    minimize_max_drawdown,
    maximize_net_profit,
    maximize_total_return,

    // v0.4.0 new objectives
    maximize_sortino_ratio, // Only considers downside volatility
    maximize_calmar_ratio, // Annual return / max drawdown
    maximize_omega_ratio, // Probability weighted ratio of gains vs losses
    maximize_tail_ratio, // Right tail / left tail distribution
    maximize_stability, // Consistency of returns
    maximize_risk_adjusted_return, // Custom risk-adjusted metric

    custom,

    /// Get objective name for display
    pub fn name(self: OptimizationObjective) []const u8 {
        return switch (self) {
            .maximize_sharpe_ratio => "Maximize Sharpe Ratio",
            .maximize_profit_factor => "Maximize Profit Factor",
            .maximize_win_rate => "Maximize Win Rate",
            .minimize_max_drawdown => "Minimize Max Drawdown",
            .maximize_net_profit => "Maximize Net Profit",
            .maximize_total_return => "Maximize Total Return",
            .maximize_sortino_ratio => "Maximize Sortino Ratio",
            .maximize_calmar_ratio => "Maximize Calmar Ratio",
            .maximize_omega_ratio => "Maximize Omega Ratio",
            .maximize_tail_ratio => "Maximize Tail Ratio",
            .maximize_stability => "Maximize Stability",
            .maximize_risk_adjusted_return => "Maximize Risk-Adjusted Return",
            .custom => "Custom Objective",
        };
    }

    /// Check if objective needs advanced metrics
    pub fn needsAdvancedMetrics(self: OptimizationObjective) bool {
        return switch (self) {
            .maximize_sortino_ratio,
            .maximize_calmar_ratio,
            .maximize_omega_ratio,
            .maximize_tail_ratio,
            .maximize_stability,
            .maximize_risk_adjusted_return,
            => true,
            else => false,
        };
    }
};

/// Single parameter combination result
pub const ParameterResult = struct {
    params: ParameterSet,
    backtest_result: BacktestResult,
    score: f64,

    pub fn deinit(self: *ParameterResult) void {
        self.params.deinit();
        self.backtest_result.deinit();
    }
};

/// Optimization result
pub const OptimizationResult = struct {
    allocator: std.mem.Allocator,
    objective: OptimizationObjective,
    best_params: ParameterSet,
    best_score: f64,
    all_results: []ParameterResult,
    total_combinations: u32,
    elapsed_time_ms: u64,

    /// Deinitialize optimization result
    pub fn deinit(self: *OptimizationResult) void {
        self.best_params.deinit();

        for (self.all_results) |*result| {
            result.deinit();
        }
        self.allocator.free(self.all_results);
    }

    /// Get top N results sorted by score
    pub fn getTopResults(self: *const OptimizationResult, allocator: std.mem.Allocator, n: usize) ![]ParameterResult {
        const top_n = @min(n, self.all_results.len);

        // Sort results by score (descending)
        var sorted = try allocator.dupe(ParameterResult, self.all_results);

        std.sort.pdq(ParameterResult, sorted, {}, struct {
            fn lessThan(_: void, a: ParameterResult, b: ParameterResult) bool {
                return a.score > b.score; // Descending order
            }
        }.lessThan);

        // Return only top N
        const result = try allocator.alloc(ParameterResult, top_n);
        @memcpy(result, sorted[0..top_n]);
        allocator.free(sorted);

        return result;
    }
};

/// Optimization configuration
pub const OptimizationConfig = struct {
    objective: OptimizationObjective,
    backtest_config: BacktestConfig,
    parameters: []const StrategyParameter,
    max_combinations: ?u32,
    enable_parallel: bool,

    /// Validate optimization configuration
    pub fn validate(self: *const OptimizationConfig) !void {
        // At least one parameter must be optimizable
        var has_optimizable = false;
        for (self.parameters) |param| {
            if (param.optimize) {
                has_optimizable = true;

                // Validate each parameter
                try param.validate();
            }
        }

        if (!has_optimizable) {
            return error.NoOptimizableParameters;
        }

        // Validate backtest config
        try self.backtest_config.validate();
    }

    /// Calculate total number of combinations
    pub fn countCombinations(self: *const OptimizationConfig) !u32 {
        var count: u32 = 1;

        for (self.parameters) |param| {
            if (!param.optimize) continue;

            if (param.range) |range| {
                const param_count = try range.count();

                // Check for overflow
                const new_count = @as(u64, count) * @as(u64, param_count);
                if (new_count > std.math.maxInt(u32)) {
                    return error.TooManyCombinations;
                }

                count = @intCast(new_count);
            }
        }

        // Apply max_combinations limit if set
        if (self.max_combinations) |max| {
            count = @min(count, max);
        }

        return count;
    }
};

// Tests
test "ParameterValue: clone and deinit" {
    const allocator = std.testing.allocator;

    // Integer
    const int_val = ParameterValue{ .integer = 42 };
    const int_clone = try int_val.clone(allocator);
    defer int_clone.deinit(allocator);
    try std.testing.expectEqual(@as(i64, 42), int_clone.integer);

    // Decimal
    const dec_val = ParameterValue{ .decimal = Decimal.fromInt(100) };
    const dec_clone = try dec_val.clone(allocator);
    defer dec_clone.deinit(allocator);
    try std.testing.expect(dec_clone.decimal.eql(Decimal.fromInt(100)));

    // Boolean
    const bool_val = ParameterValue{ .boolean = true };
    const bool_clone = try bool_val.clone(allocator);
    defer bool_clone.deinit(allocator);
    try std.testing.expectEqual(true, bool_clone.boolean);

    // Discrete
    const disc_val = ParameterValue{ .discrete = "sma" };
    const disc_clone = try disc_val.clone(allocator);
    defer disc_clone.deinit(allocator);
    try std.testing.expectEqualStrings("sma", disc_clone.discrete);
}

test "IntegerRange: count" {
    const range1 = IntegerRange{ .min = 5, .max = 20, .step = 5 };
    try std.testing.expectEqual(@as(u32, 4), range1.count()); // 5, 10, 15, 20

    const range2 = IntegerRange{ .min = 10, .max = 30, .step = 10 };
    try std.testing.expectEqual(@as(u32, 3), range2.count()); // 10, 20, 30
}

test "ParameterSet: basic operations" {
    const allocator = std.testing.allocator;

    var param_set = ParameterSet.init(allocator);
    defer param_set.deinit();

    // Set integer parameter
    try param_set.set("fast_period", ParameterValue{ .integer = 10 });

    // Get parameter
    const val = param_set.get("fast_period");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 10), val.?.integer);

    // Count
    try std.testing.expectEqual(@as(usize, 1), param_set.count());

    // Set another parameter
    try param_set.set("slow_period", ParameterValue{ .integer = 20 });
    try std.testing.expectEqual(@as(usize, 2), param_set.count());
}

test "ParameterSet: clone" {
    const allocator = std.testing.allocator;

    var original = ParameterSet.init(allocator);
    defer original.deinit();

    try original.set("period", ParameterValue{ .integer = 10 });
    try original.set("type", ParameterValue{ .discrete = "sma" });

    var cloned = try original.clone(allocator);
    defer cloned.deinit();

    try std.testing.expectEqual(@as(usize, 2), cloned.count());

    const period = cloned.get("period");
    try std.testing.expect(period != null);
    try std.testing.expectEqual(@as(i64, 10), period.?.integer);

    const type_val = cloned.get("type");
    try std.testing.expect(type_val != null);
    try std.testing.expectEqualStrings("sma", type_val.?.discrete);
}

test "StrategyParameter: validate" {
    // Valid parameter with optimization
    const param1 = StrategyParameter{
        .name = "period",
        .type = .integer,
        .default_value = ParameterValue{ .integer = 10 },
        .optimize = true,
        .range = ParameterRange{ .integer = .{ .min = 5, .max = 20, .step = 5 } },
    };
    try param1.validate();

    // Invalid: optimize without range
    const param2 = StrategyParameter{
        .name = "period",
        .type = .integer,
        .default_value = ParameterValue{ .integer = 10 },
        .optimize = true,
        .range = null,
    };
    try std.testing.expectError(error.MissingParameterRange, param2.validate());
}

test "OptimizationConfig: countCombinations" {
    const params = [_]StrategyParameter{
        .{
            .name = "fast_period",
            .type = .integer,
            .default_value = ParameterValue{ .integer = 10 },
            .optimize = true,
            .range = ParameterRange{ .integer = .{ .min = 5, .max = 15, .step = 5 } },
        },
        .{
            .name = "slow_period",
            .type = .integer,
            .default_value = ParameterValue{ .integer = 20 },
            .optimize = true,
            .range = ParameterRange{ .integer = .{ .min = 20, .max = 30, .step = 5 } },
        },
    };

    const config = OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = undefined, // Not used in this test
        .parameters = &params,
        .max_combinations = null,
        .enable_parallel = false,
    };

    // fast_period: 3 values (5, 10, 15)
    // slow_period: 3 values (20, 25, 30)
    // Total: 3 * 3 = 9
    const count = try config.countCombinations();
    try std.testing.expectEqual(@as(u32, 9), count);
}
