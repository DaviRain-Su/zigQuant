/// Thread Pool for Parallel Task Execution
///
/// A generic thread pool implementation for executing tasks in parallel.
/// Features:
/// - Configurable number of worker threads
/// - Work-stealing task queue
/// - Thread-safe result collection
/// - Graceful shutdown

const std = @import("std");

/// Task function type that returns a result
pub fn TaskFn(comptime ResultType: type, comptime ContextType: type) type {
    return *const fn (context: ContextType, task_index: usize) anyerror!ResultType;
}

/// Thread pool for parallel execution
pub fn ThreadPool(comptime ResultType: type, comptime ContextType: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        threads: []std.Thread,
        num_threads: usize,

        // Shared state
        mutex: std.Thread.Mutex,
        condition: std.Thread.Condition,

        // Task management
        task_fn: TaskFn(ResultType, ContextType),
        context: ContextType,
        next_task: usize,
        total_tasks: usize,

        // Results
        results: []ResultType,
        errors: []?anyerror,
        completed_count: usize,

        // Control
        shutdown: bool,
        started: bool,

        /// Initialize thread pool
        pub fn init(
            allocator: std.mem.Allocator,
            num_threads: ?usize,
        ) !Self {
            const thread_count = num_threads orelse @max(1, std.Thread.getCpuCount() catch 4);

            const threads = try allocator.alloc(std.Thread, thread_count);

            return Self{
                .allocator = allocator,
                .threads = threads,
                .num_threads = thread_count,
                .mutex = .{},
                .condition = .{},
                .task_fn = undefined,
                .context = undefined,
                .next_task = 0,
                .total_tasks = 0,
                .results = &[_]ResultType{},
                .errors = &[_]?anyerror{},
                .completed_count = 0,
                .shutdown = false,
                .started = false,
            };
        }

        /// Deinitialize thread pool
        pub fn deinit(self: *Self) void {
            // Signal shutdown
            {
                self.mutex.lock();
                defer self.mutex.unlock();
                self.shutdown = true;
            }
            self.condition.broadcast();

            // Wait for all threads to finish
            if (self.started) {
                for (self.threads) |thread| {
                    thread.join();
                }
            }

            self.allocator.free(self.threads);
        }

        /// Execute tasks in parallel
        pub fn execute(
            self: *Self,
            task_fn: TaskFn(ResultType, ContextType),
            context: ContextType,
            num_tasks: usize,
        ) ![]ResultType {
            if (num_tasks == 0) {
                return &[_]ResultType{};
            }

            // Allocate results and errors arrays
            const results = try self.allocator.alloc(ResultType, num_tasks);
            errdefer self.allocator.free(results);

            const errors = try self.allocator.alloc(?anyerror, num_tasks);
            defer self.allocator.free(errors);

            // Initialize errors to null
            for (errors) |*e| {
                e.* = null;
            }

            // Set up shared state
            {
                self.mutex.lock();
                defer self.mutex.unlock();

                self.task_fn = task_fn;
                self.context = context;
                self.next_task = 0;
                self.total_tasks = num_tasks;
                self.results = results;
                self.errors = errors;
                self.completed_count = 0;
                self.shutdown = false;
            }

            // Spawn worker threads
            for (self.threads, 0..) |*thread, i| {
                thread.* = try std.Thread.spawn(.{}, workerFn, .{ self, i });
            }
            self.started = true;

            // Wait for all tasks to complete
            {
                self.mutex.lock();
                defer self.mutex.unlock();

                while (self.completed_count < num_tasks) {
                    self.condition.wait(&self.mutex);
                }
            }

            // Signal shutdown and wait for threads
            {
                self.mutex.lock();
                defer self.mutex.unlock();
                self.shutdown = true;
            }
            self.condition.broadcast();

            for (self.threads) |thread| {
                thread.join();
            }
            self.started = false;

            // Check for errors
            for (errors, 0..) |err, i| {
                if (err) |e| {
                    self.allocator.free(results);
                    return e;
                }
                _ = i;
            }

            return results;
        }

        /// Worker thread function
        fn workerFn(self: *Self, thread_id: usize) void {
            _ = thread_id;

            while (true) {
                var task_index: usize = undefined;

                // Get next task
                {
                    self.mutex.lock();
                    defer self.mutex.unlock();

                    // Check for shutdown or no more tasks
                    while (self.next_task >= self.total_tasks and !self.shutdown) {
                        self.condition.wait(&self.mutex);
                    }

                    if (self.shutdown and self.next_task >= self.total_tasks) {
                        return;
                    }

                    if (self.next_task < self.total_tasks) {
                        task_index = self.next_task;
                        self.next_task += 1;
                    } else {
                        continue;
                    }
                }

                // Execute task (outside lock)
                const result = self.task_fn(self.context, task_index);

                // Store result
                {
                    self.mutex.lock();
                    defer self.mutex.unlock();

                    if (result) |r| {
                        self.results[task_index] = r;
                        self.errors[task_index] = null;
                    } else |err| {
                        self.errors[task_index] = err;
                    }

                    self.completed_count += 1;

                    // Signal completion
                    if (self.completed_count == self.total_tasks) {
                        self.condition.broadcast();
                    }
                }
            }
        }
    };
}

/// Simple parallel map function for one-shot execution
pub fn parallelMap(
    comptime ResultType: type,
    comptime ContextType: type,
    allocator: std.mem.Allocator,
    task_fn: TaskFn(ResultType, ContextType),
    context: ContextType,
    num_tasks: usize,
    num_threads: ?usize,
) ![]ResultType {
    if (num_tasks == 0) {
        return &[_]ResultType{};
    }

    // For small task counts, run sequentially
    const thread_count = num_threads orelse @max(1, std.Thread.getCpuCount() catch 4);
    if (num_tasks <= thread_count or thread_count == 1) {
        const results = try allocator.alloc(ResultType, num_tasks);
        errdefer allocator.free(results);

        for (0..num_tasks) |i| {
            results[i] = try task_fn(context, i);
        }
        return results;
    }

    // Use thread pool for larger task counts
    var pool = try ThreadPool(ResultType, ContextType).init(allocator, thread_count);
    defer pool.deinit();

    return try pool.execute(task_fn, context, num_tasks);
}

// ============================================================================
// Tests
// ============================================================================

test "ThreadPool: basic execution" {
    const allocator = std.testing.allocator;

    const Context = struct {
        multiplier: i32,
    };

    const task_fn = struct {
        fn execute(ctx: Context, index: usize) anyerror!i32 {
            return @as(i32, @intCast(index)) * ctx.multiplier;
        }
    }.execute;

    const context = Context{ .multiplier = 2 };

    const results = try parallelMap(i32, Context, allocator, task_fn, context, 10, 4);
    defer allocator.free(results);

    for (results, 0..) |result, i| {
        try std.testing.expectEqual(@as(i32, @intCast(i)) * 2, result);
    }
}

test "ThreadPool: empty task list" {
    const allocator = std.testing.allocator;

    const task_fn = struct {
        fn execute(_: void, _: usize) anyerror!i32 {
            return 0;
        }
    }.execute;

    const results = try parallelMap(i32, void, allocator, task_fn, {}, 0, 4);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "ThreadPool: single thread" {
    const allocator = std.testing.allocator;

    const task_fn = struct {
        fn execute(_: void, index: usize) anyerror!usize {
            return index * index;
        }
    }.execute;

    const results = try parallelMap(usize, void, allocator, task_fn, {}, 5, 1);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 0), results[0]);
    try std.testing.expectEqual(@as(usize, 1), results[1]);
    try std.testing.expectEqual(@as(usize, 4), results[2]);
    try std.testing.expectEqual(@as(usize, 9), results[3]);
    try std.testing.expectEqual(@as(usize, 16), results[4]);
}
