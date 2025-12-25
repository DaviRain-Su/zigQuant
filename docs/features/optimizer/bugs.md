# Parameter Optimizer Known Issues

**Version**: v0.3.0
**Status**: Planned
**Last Updated**: 2025-12-25

---

## 📋 Bug Tracking

No known bugs at this time (module not yet implemented).

This file will track bugs discovered during the parameter optimizer implementation.

---

## Bug Report Template

```markdown
### BUG-OPT-XXX: [Short Description]

**Severity**: Critical / High / Medium / Low
**Status**: Open / In Progress / Fixed / Won't Fix
**Discovered**: YYYY-MM-DD
**Reporter**: [Name]

#### Description

[Detailed problem description]

#### Reproduction Steps

1. Step 1
2. Step 2
3. ...

#### Expected Behavior

[What should happen]

#### Actual Behavior

[What actually happens]

#### Environment

- Zig Version: 0.15.2
- OS: Linux/macOS/Windows
- Platform: x86_64

#### Related Code

```zig
// Code snippet
```

#### Workaround

[If a temporary workaround exists]

#### Root Cause

[Root cause analysis]

#### Fix Plan

[Proposed fix]

#### Fix Commit

Commit: `[commit hash]`
PR: `[PR number]`
Fixed in: `v0.x.x`

---
```

## Common Bug Categories

### Combination Generation Issues
- Cartesian product calculation errors
- Off-by-one errors in range iteration
- Incorrect handling of edge cases (empty ranges, single value ranges)
- Memory leaks in combination generation

### Optimization Logic Errors
- Incorrect scoring calculations
- Best result selection errors
- Handling of failed backtests
- Progress tracking inaccuracies

### Parameter Handling Issues
- Type validation failures
- Range validation errors
- Parameter cloning issues
- Parameter set memory management

### Performance Issues
- Slow combination generation for large search spaces
- Memory leaks during long optimizations
- Excessive memory allocation
- Inefficient result storage

### Export/Import Issues
- JSON formatting errors
- CSV column alignment issues
- Unicode handling in parameter names
- File I/O errors

---

## Example Bugs (Hypothetical)

### BUG-OPT-001: [Example] Decimal range count off by one

**Severity**: High
**Status**: Fixed
**Discovered**: 2025-12-25
**Reporter**: Example

#### Description

The `DecimalRange.count()` method returns incorrect count for certain step values, causing one fewer combination to be generated than expected.

#### Reproduction Steps

1. Create DecimalRange: min=0.1, max=0.9, step=0.2
2. Call `count()` method
3. Expected: 5 values (0.1, 0.3, 0.5, 0.7, 0.9)
4. Actual: 4 values returned

#### Expected Behavior

`count()` should return 5 for the range [0.1, 0.9] with step 0.2.

#### Actual Behavior

Returns 4, missing the last value.

#### Root Cause

Floating-point precision issue in calculation:

```zig
pub fn count(self: DecimalRange) !usize {
    const range = try self.max.sub(self.min);  // 0.8
    const count_decimal = try range.div(self.step);  // 0.8 / 0.2 = 4.0
    const count_float = try count_decimal.toFloat();
    return @intFromFloat(@floor(count_float) + 1);  // floor(4.0) + 1 = 5
}
```

The issue is that `0.8 / 0.2` may not equal exactly 4.0 due to Decimal representation, resulting in 3.9999..., which floors to 3, giving count of 4.

#### Fix Plan

Use ceiling instead of floor, or add small epsilon:

```zig
pub fn count(self: DecimalRange) !usize {
    const range = try self.max.sub(self.min);
    const count_decimal = try range.div(self.step);
    const count_float = try count_decimal.toFloat();
    // Use ceiling to handle floating-point precision
    return @intFromFloat(@ceil(count_float));
}
```

Or better, iterate and count:

```zig
pub fn count(self: DecimalRange) !usize {
    var cnt: usize = 0;
    var val = self.min;
    while (val.lte(self.max)) : (cnt += 1) {
        val = try val.add(self.step);
    }
    return cnt;
}
```

#### Fix Commit

Commit: `abc123def`
Fixed in: `v0.3.1`

---

### BUG-OPT-002: [Example] Cartesian product incorrect for 3+ parameters

**Severity**: Critical
**Status**: Fixed
**Discovered**: 2025-12-25
**Reporter**: Example

#### Description

When generating combinations for 3 or more parameters, the cartesian product algorithm produces duplicate combinations or skips valid ones.

#### Reproduction Steps

1. Define 3 integer parameters:
   - A: [1, 2]
   - B: [10, 20]
   - C: [100, 200]
2. Generate all combinations
3. Expected: 8 combinations (2×2×2)
4. Actual: 6 combinations with duplicates

#### Expected Behavior

Should generate all 8 unique combinations:
```
(1, 10, 100), (1, 10, 200), (1, 20, 100), (1, 20, 200),
(2, 10, 100), (2, 10, 200), (2, 20, 100), (2, 20, 200)
```

#### Actual Behavior

Generates 6 combinations with some duplicates and missing entries.

#### Root Cause

Incorrect calculation of repeat and cycle counts in `cartesianProduct`:

```zig
// Wrong calculation
var repeat: usize = 1;
var i: usize = value_arrays.len;
while (i > 0) : (i -= 1) {
    const idx = i - 1;
    repeat_counts[idx] = repeat;
    cycle_counts[idx] = total_combinations / (repeat * value_arrays[idx].values.items.len);
    repeat *= value_arrays[idx].values.items.len;
}
```

The cycle count calculation is incorrect.

#### Fix Plan

Fix the repeat/cycle calculation:

```zig
// Calculate repeat pattern correctly
var repeat: usize = 1;
for (0..value_arrays.len) |i| {
    const idx = value_arrays.len - 1 - i;
    repeat_counts[idx] = repeat;
    repeat *= value_arrays[idx].values.items.len;
}

// Calculate cycle counts
for (value_arrays, 0..) |arr, idx| {
    cycle_counts[idx] = total_combinations / (repeat_counts[idx] * arr.values.items.len);
}
```

#### Fix Commit

Commit: `def456abc`
Fixed in: `v0.3.0`

---

### BUG-OPT-003: [Example] Memory leak in OptimizationResult.deinit()

**Severity**: Critical
**Status**: Fixed
**Discovered**: 2025-12-25
**Reporter**: Example

#### Description

`OptimizationResult.deinit()` doesn't free all allocated memory, causing memory leaks when running multiple optimizations.

#### Reproduction Steps

1. Run optimization with GeneralPurposeAllocator
2. Call `result.deinit()`
3. Check allocator for leaks
4. Memory leak detected

#### Expected Behavior

All allocated memory should be freed.

#### Actual Behavior

`all_params` array elements are not freed before freeing the array itself.

#### Root Cause

Missing loop to deinit parameter sets:

```zig
pub fn deinit(self: *OptimizationResult) void {
    self.best_params.deinit();

    for (self.all_results) |*result| {
        result.deinit(self.allocator);
    }
    self.allocator.free(self.all_results);

    // Missing: deinit each ParameterSet!
    self.allocator.free(self.all_params);
}
```

#### Fix

```zig
pub fn deinit(self: *OptimizationResult) void {
    self.best_params.deinit();

    for (self.all_results) |*result| {
        result.deinit(self.allocator);
    }
    self.allocator.free(self.all_results);

    // Fix: deinit each parameter set
    for (self.all_params) |*params| {
        params.deinit();
    }
    self.allocator.free(self.all_params);
}
```

#### Fix Commit

Commit: `789ghi123`
Fixed in: `v0.3.0`

---

### BUG-OPT-004: [Example] Discrete parameter values not cloned properly

**Severity**: Medium
**Status**: Fixed
**Discovered**: 2025-12-25
**Reporter**: Example

#### Description

When cloning a `ParameterSet` containing discrete parameters, the string values are not deeply copied, leading to use-after-free errors.

#### Reproduction Steps

1. Create ParameterSet with discrete value: `mode = "fast"`
2. Clone the parameter set
3. Free original parameter set
4. Access discrete value in clone
5. Segmentation fault or garbage data

#### Expected Behavior

Clone should have independent copy of discrete string.

#### Actual Behavior

Clone shares the same string pointer, causing use-after-free.

#### Root Cause

ParameterSet.clone() doesn't deep-copy discrete strings:

```zig
pub fn clone(self: *const ParameterSet) !ParameterSet {
    var new_set = ParameterSet.init(self.allocator);
    errdefer new_set.deinit();

    var iter = self.values.iterator();
    while (iter.next()) |entry| {
        // This just copies the pointer for discrete values!
        try new_set.set(entry.key_ptr.*, entry.value_ptr.*);
    }

    return new_set;
}
```

#### Fix Plan

Deep copy discrete strings and parameter names:

```zig
pub fn clone(self: *const ParameterSet) !ParameterSet {
    var new_set = ParameterSet.init(self.allocator);
    errdefer new_set.deinit();

    var iter = self.values.iterator();
    while (iter.next()) |entry| {
        const name = try self.allocator.dupe(u8, entry.key_ptr.*);
        errdefer self.allocator.free(name);

        const value = switch (entry.value_ptr.*) {
            .discrete => |str| blk: {
                const cloned_str = try self.allocator.dupe(u8, str);
                break :blk ParameterValue{ .discrete = cloned_str };
            },
            else => entry.value_ptr.*,  // Other types are value types
        };

        try new_set.values.put(name, value);
    }

    return new_set;
}
```

Also need to update `deinit()` to free discrete strings.

#### Fix Commit

Commit: `111aaa222`
Fixed in: `v0.3.1`

---

### BUG-OPT-005: [Example] Scoring function doesn't handle NaN/Inf

**Severity**: High
**Status**: Open
**Discovered**: 2025-12-25
**Reporter**: Example

#### Description

When a backtest results in NaN or Infinity for a metric (e.g., Sharpe ratio), the scoring function doesn't handle it gracefully, causing the optimizer to select invalid results as "best".

#### Reproduction Steps

1. Run optimization where one backtest has zero trades
2. Sharpe ratio becomes NaN (division by zero)
3. Score becomes NaN
4. findBestResult() selects the NaN result as best

#### Expected Behavior

NaN and Inf scores should be treated as invalid and skipped.

#### Actual Behavior

NaN propagates through comparisons, causing incorrect best selection.

#### Root Cause

No validation in scoreResult():

```zig
pub fn scoreResult(
    self: *GridSearchOptimizer,
    result: *const BacktestResult,
    objective: OptimizationObjective,
) !f64 {
    return switch (objective) {
        .maximize_sharpe_ratio => result.metrics.sharpe_ratio,  // May be NaN!
        // ...
    };
}
```

#### Fix Plan

Add validation:

```zig
pub fn scoreResult(
    self: *GridSearchOptimizer,
    result: *const BacktestResult,
    objective: OptimizationObjective,
) !f64 {
    const score = switch (objective) {
        .maximize_sharpe_ratio => result.metrics.sharpe_ratio,
        .maximize_profit_factor => result.metrics.profit_factor,
        .maximize_win_rate => result.metrics.win_rate,
        .minimize_max_drawdown => -result.metrics.max_drawdown,
        .maximize_net_profit => try result.metrics.net_profit.toFloat(),
        .custom => return error.CustomObjectiveNotSupported,
    };

    // Validate score
    if (std.math.isNan(score) or std.math.isInf(score)) {
        self.logger.warn("Invalid score (NaN/Inf) for objective {}", .{objective});
        return error.InvalidScore;
    }

    return score;
}
```

Also handle in findBestResult():

```zig
for (all_results[1..], 1..) |*result, i| {
    const score = self.scoreResult(result, objective) catch |err| {
        if (err == error.InvalidScore) continue;  // Skip invalid scores
        return err;
    };
    if (score > best_score) {
        best_score = score;
        best_index = i;
    }
}
```

#### Workaround

Manually filter results before analysis.

#### Fix Commit

TBD

---

### BUG-OPT-006: [Example] CSV export fails with special characters in parameter names

**Severity**: Low
**Status**: Open
**Discovered**: 2025-12-25
**Reporter**: Example

#### Description

When parameter names contain commas or quotes, CSV export produces malformed output.

#### Reproduction Steps

1. Create parameter with name: `threshold,high`
2. Run optimization
3. Export to CSV
4. CSV is malformed (extra columns)

#### Expected Behavior

Special characters should be escaped in CSV output.

#### Actual Behavior

Commas in parameter names break CSV structure.

#### Fix Plan

Escape CSV values:

```zig
fn writeCSVValue(writer: anytype, value: []const u8) !void {
    if (std.mem.indexOf(u8, value, ",") != null or
        std.mem.indexOf(u8, value, "\"") != null)
    {
        try writer.writeAll("\"");
        for (value) |c| {
            if (c == '"') try writer.writeAll("\"\"");  // Escape quotes
            try writer.writeByte(c);
        }
        try writer.writeAll("\"");
    } else {
        try writer.writeAll(value);
    }
}
```

---

## Bug Prevention Guidelines

### Code Review Checklist

- [ ] All memory allocations have corresponding frees
- [ ] Parameter ranges properly validated
- [ ] Cartesian product algorithm tested with 1-5 parameters
- [ ] Edge cases handled (zero combinations, all failures, etc.)
- [ ] NaN/Inf handling in scoring functions
- [ ] String values properly cloned in ParameterSet
- [ ] CSV/JSON export handles special characters
- [ ] Performance acceptable for large search spaces

### Testing Requirements

- Unit tests for all parameter types
- Combination generation tests with various parameter counts
- Integration tests with failing backtests
- Memory leak detection on all tests
- Performance regression tests
- CSV/JSON export validation

---

## Debugging Tips

### Memory Leak Detection

```zig
test "Debug: check for memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Run optimization
    // ...
}
```

### Combination Inspection

```zig
// Debug: print all combinations
const combinations = try generator.generateAll();
defer {
    for (combinations) |*combo| combo.deinit();
    allocator.free(combinations);
}

for (combinations, 0..) |combo, i| {
    std.debug.print("Combination {}: {}\n", .{ i, combo });
}
```

### Score Validation

```zig
// Check for invalid scores
for (all_results, 0..) |*result, i| {
    const score = try optimizer.scoreResult(result, objective);
    if (std.math.isNan(score) or std.math.isInf(score)) {
        std.debug.print("Invalid score at index {}: {d}\n", .{ i, score });
    }
}
```

---

**Note**: The bugs listed above are hypothetical examples for documentation purposes. Actual bugs will be tracked here during implementation.

---

**Version**: v0.3.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-25
