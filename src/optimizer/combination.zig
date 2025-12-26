/// Parameter Combination Generator
///
/// This module provides functionality to generate all possible parameter
/// combinations for optimization using Cartesian product algorithm.
///
/// Supports:
/// - Integer ranges with step
/// - Decimal ranges with step
/// - Boolean values (true/false)
/// - Discrete value sets

const std = @import("std");
const root = @import("../root.zig");
const types = @import("types.zig");

const ParameterType = types.ParameterType;
const ParameterValue = types.ParameterValue;
const ParameterRange = types.ParameterRange;
const StrategyParameter = types.StrategyParameter;
const ParameterSet = types.ParameterSet;
const Decimal = root.Decimal;

/// Parameter combination generator
pub const CombinationGenerator = struct {
    allocator: std.mem.Allocator,
    parameters: []const StrategyParameter,

    /// Initialize combination generator
    pub fn init(
        allocator: std.mem.Allocator,
        parameters: []const StrategyParameter,
    ) CombinationGenerator {
        return .{
            .allocator = allocator,
            .parameters = parameters,
        };
    }

    /// Deinitialize (currently no-op as we don't own the parameters)
    pub fn deinit(self: *CombinationGenerator) void {
        _ = self;
    }

    /// Generate all parameter combinations
    pub fn generateAll(self: *CombinationGenerator) ![]ParameterSet {
        // 1. Count total combinations
        const total = try self.countCombinations();
        if (total == 0) {
            return &[_]ParameterSet{};
        }

        // 2. Allocate array for all combinations
        const combinations = try self.allocator.alloc(ParameterSet, total);
        errdefer self.allocator.free(combinations);

        // Initialize all parameter sets
        for (combinations) |*combo| {
            combo.* = ParameterSet.init(self.allocator);
        }

        // 3. Generate combinations recursively
        var index: usize = 0;
        try self.generateRecursive(combinations, &index, 0);

        return combinations;
    }

    /// Count total number of combinations
    pub fn countCombinations(self: *const CombinationGenerator) !u32 {
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

        return count;
    }

    /// Recursively generate parameter combinations
    fn generateRecursive(
        self: *CombinationGenerator,
        combinations: []ParameterSet,
        index: *usize,
        param_index: usize,
    ) anyerror!void {
        // Base case: reached end of parameters
        if (param_index >= self.parameters.len) {
            index.* += 1;
            return;
        }

        const param = self.parameters[param_index];

        // Skip non-optimizable parameters (use default values)
        if (!param.optimize) {
            // Set default value for all combinations
            const remaining_combos = try self.countRemainingCombinations(param_index + 1);
            const start_idx = index.*;
            const end_idx = start_idx + remaining_combos;

            var i = start_idx;
            while (i < end_idx) : (i += 1) {
                try combinations[i].set(param.name, param.default_value);
            }

            // Continue with next parameter
            try self.generateRecursive(combinations, index, param_index + 1);
            return;
        }

        // Generate values for this parameter
        const range = param.range orelse return error.MissingParameterRange;

        switch (range) {
            .integer => |int_range| {
                try self.generateIntegerCombinations(
                    combinations,
                    index,
                    param_index,
                    param.name,
                    int_range,
                );
            },
            .decimal => |dec_range| {
                try self.generateDecimalCombinations(
                    combinations,
                    index,
                    param_index,
                    param.name,
                    dec_range,
                );
            },
            .boolean => {
                try self.generateBooleanCombinations(
                    combinations,
                    index,
                    param_index,
                    param.name,
                );
            },
            .discrete => |values| {
                try self.generateDiscreteCombinations(
                    combinations,
                    index,
                    param_index,
                    param.name,
                    values,
                );
            },
        }
    }

    /// Generate combinations for integer parameter
    fn generateIntegerCombinations(
        self: *CombinationGenerator,
        combinations: []ParameterSet,
        index: *usize,
        param_index: usize,
        param_name: []const u8,
        range: types.IntegerRange,
    ) anyerror!void {
        var value = range.min;
        while (value <= range.max) : (value += range.step) {
            const start_idx = index.*;
            const param_value = ParameterValue{ .integer = value };

            // Calculate how many combinations this value will be in
            const remaining = try self.countRemainingCombinations(param_index + 1);

            // Set this parameter value for all combinations in this batch
            var i: usize = 0;
            while (i < remaining) : (i += 1) {
                const combo_idx = start_idx + i;
                try combinations[combo_idx].set(param_name, param_value);
            }

            // Recurse for next parameter
            try self.generateRecursive(combinations, index, param_index + 1);
        }
    }

    /// Generate combinations for decimal parameter
    fn generateDecimalCombinations(
        self: *CombinationGenerator,
        combinations: []ParameterSet,
        index: *usize,
        param_index: usize,
        param_name: []const u8,
        range: types.DecimalRange,
    ) anyerror!void {
        var value = range.min;
        const max = range.max;

        while (value.cmp(max) != .gt) {
            const start_idx = index.*;
            const param_value = ParameterValue{ .decimal = value };

            // Calculate how many combinations this value will be in
            const remaining = try self.countRemainingCombinations(param_index + 1);

            // Set this parameter value for all combinations in this batch
            var i: usize = 0;
            while (i < remaining) : (i += 1) {
                const combo_idx = start_idx + i;
                try combinations[combo_idx].set(param_name, param_value);
            }

            // Recurse for next parameter
            try self.generateRecursive(combinations, index, param_index + 1);

            // Advance to next value
            value = value.add(range.step);
        }
    }

    /// Generate combinations for boolean parameter
    fn generateBooleanCombinations(
        self: *CombinationGenerator,
        combinations: []ParameterSet,
        index: *usize,
        param_index: usize,
        param_name: []const u8,
    ) anyerror!void {
        const bool_values = [_]bool{ false, true };

        for (bool_values) |value| {
            const start_idx = index.*;
            const param_value = ParameterValue{ .boolean = value };

            // Calculate how many combinations this value will be in
            const remaining = try self.countRemainingCombinations(param_index + 1);

            // Set this parameter value for all combinations in this batch
            var i: usize = 0;
            while (i < remaining) : (i += 1) {
                const combo_idx = start_idx + i;
                try combinations[combo_idx].set(param_name, param_value);
            }

            // Recurse for next parameter
            try self.generateRecursive(combinations, index, param_index + 1);
        }
    }

    /// Generate combinations for discrete parameter
    fn generateDiscreteCombinations(
        self: *CombinationGenerator,
        combinations: []ParameterSet,
        index: *usize,
        param_index: usize,
        param_name: []const u8,
        values: []const ParameterValue,
    ) anyerror!void {
        for (values) |value| {
            const start_idx = index.*;

            // Calculate how many combinations this value will be in
            const remaining = try self.countRemainingCombinations(param_index + 1);

            // Set this parameter value for all combinations in this batch
            var i: usize = 0;
            while (i < remaining) : (i += 1) {
                const combo_idx = start_idx + i;
                try combinations[combo_idx].set(param_name, value);
            }

            // Recurse for next parameter
            try self.generateRecursive(combinations, index, param_index + 1);
        }
    }

    /// Count remaining combinations from a given parameter index
    fn countRemainingCombinations(self: *const CombinationGenerator, start_index: usize) anyerror!u32 {
        var count: u32 = 1;

        var i = start_index;
        while (i < self.parameters.len) : (i += 1) {
            const param = self.parameters[i];
            if (!param.optimize) continue;

            if (param.range) |range| {
                const param_count = try range.count();
                const new_count = @as(u64, count) * @as(u64, param_count);
                if (new_count > std.math.maxInt(u32)) {
                    return error.TooManyCombinations;
                }
                count = @intCast(new_count);
            }
        }

        return count;
    }
};

// Tests
test "CombinationGenerator: count combinations - single integer parameter" {
    const allocator = std.testing.allocator;

    const params = [_]StrategyParameter{
        .{
            .name = "period",
            .type = .integer,
            .default_value = ParameterValue{ .integer = 10 },
            .optimize = true,
            .range = ParameterRange{ .integer = .{ .min = 5, .max = 15, .step = 5 } },
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    defer generator.deinit();

    const count = try generator.countCombinations();
    // 5, 10, 15 = 3 values
    try std.testing.expectEqual(@as(u32, 3), count);
}

test "CombinationGenerator: count combinations - multiple parameters" {
    const allocator = std.testing.allocator;

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

    var generator = CombinationGenerator.init(allocator, &params);
    defer generator.deinit();

    const count = try generator.countCombinations();
    // fast_period: 3 values (5, 10, 15)
    // slow_period: 3 values (20, 25, 30)
    // Total: 3 * 3 = 9
    try std.testing.expectEqual(@as(u32, 9), count);
}

test "CombinationGenerator: generate integer combinations" {
    const allocator = std.testing.allocator;

    const params = [_]StrategyParameter{
        .{
            .name = "fast_period",
            .type = .integer,
            .default_value = ParameterValue{ .integer = 10 },
            .optimize = true,
            .range = ParameterRange{ .integer = .{ .min = 5, .max = 10, .step = 5 } },
        },
        .{
            .name = "slow_period",
            .type = .integer,
            .default_value = ParameterValue{ .integer = 20 },
            .optimize = true,
            .range = ParameterRange{ .integer = .{ .min = 20, .max = 25, .step = 5 } },
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    defer generator.deinit();

    const combinations = try generator.generateAll();
    defer {
        for (combinations) |*combo| {
            combo.deinit();
        }
        allocator.free(combinations);
    }

    // Should generate 2 * 2 = 4 combinations
    try std.testing.expectEqual(@as(usize, 4), combinations.len);

    // Verify each combination has both parameters
    for (combinations) |combo| {
        try std.testing.expect(combo.get("fast_period") != null);
        try std.testing.expect(combo.get("slow_period") != null);
    }

    // Verify specific combinations exist
    // (5, 20), (5, 25), (10, 20), (10, 25)
    const combo0 = combinations[0];
    try std.testing.expectEqual(@as(i64, 5), combo0.get("fast_period").?.integer);
    try std.testing.expectEqual(@as(i64, 20), combo0.get("slow_period").?.integer);

    const combo3 = combinations[3];
    try std.testing.expectEqual(@as(i64, 10), combo3.get("fast_period").?.integer);
    try std.testing.expectEqual(@as(i64, 25), combo3.get("slow_period").?.integer);
}

test "CombinationGenerator: boolean parameter" {
    const allocator = std.testing.allocator;

    const params = [_]StrategyParameter{
        .{
            .name = "use_stop_loss",
            .type = .boolean,
            .default_value = ParameterValue{ .boolean = true },
            .optimize = true,
            .range = ParameterRange{ .boolean = {} },
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    defer generator.deinit();

    const combinations = try generator.generateAll();
    defer {
        for (combinations) |*combo| {
            combo.deinit();
        }
        allocator.free(combinations);
    }

    // Should generate 2 combinations (true, false)
    try std.testing.expectEqual(@as(usize, 2), combinations.len);

    const val0 = combinations[0].get("use_stop_loss");
    const val1 = combinations[1].get("use_stop_loss");
    try std.testing.expect(val0 != null);
    try std.testing.expect(val1 != null);

    // One should be false, one should be true
    try std.testing.expect(val0.?.boolean != val1.?.boolean);
}

test "CombinationGenerator: mixed parameter types" {
    const allocator = std.testing.allocator;

    const params = [_]StrategyParameter{
        .{
            .name = "period",
            .type = .integer,
            .default_value = ParameterValue{ .integer = 10 },
            .optimize = true,
            .range = ParameterRange{ .integer = .{ .min = 10, .max = 15, .step = 5 } },
        },
        .{
            .name = "use_trailing",
            .type = .boolean,
            .default_value = ParameterValue{ .boolean = false },
            .optimize = true,
            .range = ParameterRange{ .boolean = {} },
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    defer generator.deinit();

    const combinations = try generator.generateAll();
    defer {
        for (combinations) |*combo| {
            combo.deinit();
        }
        allocator.free(combinations);
    }

    // period: 2 values (10, 15)
    // use_trailing: 2 values (false, true)
    // Total: 2 * 2 = 4
    try std.testing.expectEqual(@as(usize, 4), combinations.len);

    // All combinations should have both parameters
    for (combinations) |combo| {
        try std.testing.expect(combo.get("period") != null);
        try std.testing.expect(combo.get("use_trailing") != null);
    }
}

test "CombinationGenerator: non-optimizable parameters" {
    const allocator = std.testing.allocator;

    const params = [_]StrategyParameter{
        .{
            .name = "fast_period",
            .type = .integer,
            .default_value = ParameterValue{ .integer = 10 },
            .optimize = true,
            .range = ParameterRange{ .integer = .{ .min = 5, .max = 10, .step = 5 } },
        },
        .{
            .name = "commission",
            .type = .decimal,
            .default_value = ParameterValue{ .decimal = Decimal.fromFloat(0.001) },
            .optimize = false, // Not optimized
            .range = null,
        },
    };

    var generator = CombinationGenerator.init(allocator, &params);
    defer generator.deinit();

    const combinations = try generator.generateAll();
    defer {
        for (combinations) |*combo| {
            combo.deinit();
        }
        allocator.free(combinations);
    }

    // Only fast_period is optimized: 2 values (5, 10)
    try std.testing.expectEqual(@as(usize, 2), combinations.len);

    // All combinations should have commission set to default value
    for (combinations) |combo| {
        const commission = combo.get("commission");
        try std.testing.expect(commission != null);
        try std.testing.expect(commission.?.decimal.eql(Decimal.fromFloat(0.001)));
    }
}
