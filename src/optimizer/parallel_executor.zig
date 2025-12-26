/// Parallel Backtest Executor
///
/// Executes multiple backtests in parallel using worker threads.
/// Designed for parameter optimization where many backtests need
/// to run with different parameter combinations.
///
/// Features:
/// - Parallel execution of backtests
/// - Thread-safe result collection
/// - Progress tracking
/// - Automatic thread count detection

const std = @import("std");
const root = @import("../root.zig");
const types = @import("types.zig");

const BacktestResult = root.BacktestResult;
const BacktestConfig = root.BacktestConfig;
const ParameterSet = types.ParameterSet;

/// Result from a single backtest task
pub const TaskResult = struct {
    index: usize,
    result: ?BacktestResult,
    score: f64,
    error_msg: ?[]const u8,
};

/// Parallel executor configuration
pub const ParallelConfig = struct {
    num_threads: ?usize = null, // null = auto-detect
    chunk_size: usize = 1, // Tasks per chunk (for better cache locality)
};

/// Parallel executor for running multiple backtests concurrently
pub const ParallelExecutor = struct {
    allocator: std.mem.Allocator,
    num_threads: usize,

    /// Initialize with automatic thread count detection
    pub fn init(allocator: std.mem.Allocator) ParallelExecutor {
        const cpu_count = std.Thread.getCpuCount() catch 4;
        return .{
            .allocator = allocator,
            .num_threads = @max(1, cpu_count),
        };
    }

    /// Initialize with specific thread count
    pub fn initWithThreads(allocator: std.mem.Allocator, num_threads: usize) ParallelExecutor {
        return .{
            .allocator = allocator,
            .num_threads = @max(1, num_threads),
        };
    }

    /// Execute tasks in parallel
    /// task_fn: function(allocator, task_index, user_context) -> TaskResult
    pub fn execute(
        self: *ParallelExecutor,
        comptime Context: type,
        context: Context,
        num_tasks: usize,
        task_fn: *const fn (std.mem.Allocator, usize, Context) TaskResult,
    ) ![]TaskResult {
        if (num_tasks == 0) {
            return &[_]TaskResult{};
        }

        // Allocate results array
        const results = try self.allocator.alloc(TaskResult, num_tasks);
        errdefer self.allocator.free(results);

        // For small task counts or single thread, run sequentially
        if (num_tasks <= self.num_threads or self.num_threads == 1) {
            for (0..num_tasks) |i| {
                results[i] = task_fn(self.allocator, i, context);
            }
            return results;
        }

        // Parallel execution
        var mutex = std.Thread.Mutex{};
        var next_task: usize = 0;

        // Worker context
        const WorkerData = struct {
            allocator: std.mem.Allocator,
            results: []TaskResult,
            mutex: *std.Thread.Mutex,
            next_task: *usize,
            num_tasks: usize,
            context: Context,
            task_fn: *const fn (std.mem.Allocator, usize, Context) TaskResult,
        };

        const worker_data = WorkerData{
            .allocator = self.allocator,
            .results = results,
            .mutex = &mutex,
            .next_task = &next_task,
            .num_tasks = num_tasks,
            .context = context,
            .task_fn = task_fn,
        };

        // Worker function
        const workerFn = struct {
            fn run(data: WorkerData) void {
                while (true) {
                    // Get next task index
                    const task_idx = blk: {
                        data.mutex.lock();
                        defer data.mutex.unlock();

                        if (data.next_task.* >= data.num_tasks) {
                            break :blk null;
                        }
                        const idx = data.next_task.*;
                        data.next_task.* += 1;
                        break :blk idx;
                    };

                    const idx = task_idx orelse break;

                    // Execute task
                    data.results[idx] = data.task_fn(data.allocator, idx, data.context);
                }
            }
        }.run;

        // Spawn worker threads
        const threads = try self.allocator.alloc(std.Thread, self.num_threads);
        defer self.allocator.free(threads);

        for (threads) |*thread| {
            thread.* = try std.Thread.spawn(.{}, workerFn, .{worker_data});
        }

        // Wait for all threads to complete
        for (threads) |thread| {
            thread.join();
        }

        return results;
    }

    /// Free results array
    pub fn freeResults(self: *ParallelExecutor, results: []TaskResult) void {
        self.allocator.free(results);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ParallelExecutor: initialization" {
    const allocator = std.testing.allocator;

    const executor = ParallelExecutor.init(allocator);
    try std.testing.expect(executor.num_threads >= 1);
}

test "ParallelExecutor: init with threads" {
    const allocator = std.testing.allocator;

    const executor = ParallelExecutor.initWithThreads(allocator, 4);
    try std.testing.expectEqual(@as(usize, 4), executor.num_threads);
}

test "ParallelExecutor: sequential execution" {
    const allocator = std.testing.allocator;

    var executor = ParallelExecutor.initWithThreads(allocator, 1);

    const Context = struct {
        multiplier: i32,
    };

    const task_fn = struct {
        fn run(_: std.mem.Allocator, index: usize, ctx: Context) TaskResult {
            return TaskResult{
                .index = index,
                .result = null,
                .score = @as(f64, @floatFromInt(index)) * @as(f64, @floatFromInt(ctx.multiplier)),
                .error_msg = null,
            };
        }
    }.run;

    const context = Context{ .multiplier = 2 };
    const results = try executor.execute(Context, context, 5, task_fn);
    defer executor.freeResults(results);

    try std.testing.expectEqual(@as(usize, 5), results.len);
    try std.testing.expectEqual(@as(f64, 0), results[0].score);
    try std.testing.expectEqual(@as(f64, 2), results[1].score);
    try std.testing.expectEqual(@as(f64, 4), results[2].score);
    try std.testing.expectEqual(@as(f64, 6), results[3].score);
    try std.testing.expectEqual(@as(f64, 8), results[4].score);
}

test "ParallelExecutor: parallel execution" {
    const allocator = std.testing.allocator;

    var executor = ParallelExecutor.initWithThreads(allocator, 4);

    const Context = struct {
        base: i32,
    };

    const task_fn = struct {
        fn run(_: std.mem.Allocator, index: usize, ctx: Context) TaskResult {
            return TaskResult{
                .index = index,
                .result = null,
                .score = @as(f64, @floatFromInt(index + @as(usize, @intCast(ctx.base)))),
                .error_msg = null,
            };
        }
    }.run;

    const context = Context{ .base = 10 };
    const results = try executor.execute(Context, context, 20, task_fn);
    defer executor.freeResults(results);

    try std.testing.expectEqual(@as(usize, 20), results.len);

    // Verify all results are present (order may vary in parallel execution)
    var sum: f64 = 0;
    for (results) |r| {
        sum += r.score;
    }
    // Sum should be: (10+11+12+...+29) = 20*10 + (0+1+2+...+19) = 200 + 190 = 390
    try std.testing.expectEqual(@as(f64, 390), sum);
}

test "ParallelExecutor: empty task list" {
    const allocator = std.testing.allocator;

    var executor = ParallelExecutor.init(allocator);

    const task_fn = struct {
        fn run(_: std.mem.Allocator, _: usize, _: void) TaskResult {
            return TaskResult{
                .index = 0,
                .result = null,
                .score = 0,
                .error_msg = null,
            };
        }
    }.run;

    const results = try executor.execute(void, {}, 0, task_fn);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}
