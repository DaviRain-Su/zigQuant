//! Clock-Driven Scheduler
//!
//! This module implements a clock-driven scheduler that triggers strategies
//! at fixed time intervals. Suitable for market making and other strategies
//! that need periodic updates.
//!
//! Features:
//! - Fixed interval tick generation
//! - Multiple strategy support
//! - Thread-safe start/stop control
//! - Performance statistics tracking

const std = @import("std");
const Allocator = std.mem.Allocator;
const IClockStrategy = @import("interfaces.zig").IClockStrategy;

// ============================================================================
// Clock Statistics
// ============================================================================

/// Statistics for clock performance monitoring
pub const ClockStats = struct {
    /// Total number of ticks executed
    tick_count: u64,
    /// Average tick processing time in nanoseconds
    avg_tick_time_ns: u64,
    /// Maximum tick processing time in nanoseconds
    max_tick_time_ns: u64,
    /// Number of registered strategies
    strategy_count: usize,

    /// Create default stats
    pub fn init() ClockStats {
        return .{
            .tick_count = 0,
            .avg_tick_time_ns = 0,
            .max_tick_time_ns = 0,
            .strategy_count = 0,
        };
    }
};

// ============================================================================
// Clock Errors
// ============================================================================

/// Errors that can occur during clock operations
pub const ClockError = error{
    /// Clock is already running
    AlreadyRunning,
    /// Clock is not running
    NotRunning,
    /// Strategy already registered
    StrategyAlreadyRegistered,
    /// Strategy not found
    StrategyNotFound,
    /// Invalid tick interval
    InvalidInterval,
};

// ============================================================================
// Clock
// ============================================================================

/// Clock-driven scheduler for periodic strategy execution
pub const Clock = struct {
    /// Memory allocator
    allocator: Allocator,
    /// Tick interval in nanoseconds
    tick_interval_ns: u64,
    /// Registered strategies
    strategies: std.ArrayList(IClockStrategy),
    /// Running state (atomic for thread safety)
    running: std.atomic.Value(bool),
    /// Tick count
    tick_count: u64,
    /// Total tick processing time (for averaging)
    total_tick_time_ns: u64,
    /// Maximum tick processing time
    max_tick_time_ns: u64,

    const Self = @This();

    // ========================================================================
    // Initialization
    // ========================================================================

    /// Initialize clock with tick interval in milliseconds
    /// @param allocator: Memory allocator
    /// @param tick_interval_ms: Tick interval in milliseconds
    pub fn init(allocator: Allocator, tick_interval_ms: u64) !Self {
        if (tick_interval_ms == 0) {
            return ClockError.InvalidInterval;
        }

        return .{
            .allocator = allocator,
            .tick_interval_ns = tick_interval_ms * 1_000_000,
            .strategies = try std.ArrayList(IClockStrategy).initCapacity(allocator, 0),
            .running = std.atomic.Value(bool).init(false),
            .tick_count = 0,
            .total_tick_time_ns = 0,
            .max_tick_time_ns = 0,
        };
    }

    /// Initialize clock with tick interval in nanoseconds
    /// @param allocator: Memory allocator
    /// @param tick_interval_ns: Tick interval in nanoseconds
    pub fn initNs(allocator: Allocator, tick_interval_ns: u64) !Self {
        if (tick_interval_ns == 0) {
            return ClockError.InvalidInterval;
        }

        return .{
            .allocator = allocator,
            .tick_interval_ns = tick_interval_ns,
            .strategies = try std.ArrayList(IClockStrategy).initCapacity(allocator, 0),
            .running = std.atomic.Value(bool).init(false),
            .tick_count = 0,
            .total_tick_time_ns = 0,
            .max_tick_time_ns = 0,
        };
    }

    /// Deinitialize clock and free resources
    pub fn deinit(self: *Self) void {
        // Stop if running
        if (self.running.load(.seq_cst)) {
            self.stop();
        }
        self.strategies.deinit(self.allocator);
    }

    // ========================================================================
    // Strategy Management
    // ========================================================================

    /// Add a strategy to the clock
    /// @param strategy: Strategy implementing IClockStrategy
    pub fn addStrategy(self: *Self, strategy: IClockStrategy) !void {
        // Check if strategy already registered (compare by ptr)
        for (self.strategies.items) |s| {
            if (s.ptr == strategy.ptr) {
                return ClockError.StrategyAlreadyRegistered;
            }
        }
        try self.strategies.append(self.allocator, strategy);
    }

    /// Remove a strategy from the clock
    /// @param strategy: Strategy to remove
    pub fn removeStrategy(self: *Self, strategy: IClockStrategy) ClockError!void {
        for (self.strategies.items, 0..) |s, i| {
            if (s.ptr == strategy.ptr) {
                _ = self.strategies.orderedRemove(i);
                return;
            }
        }
        return ClockError.StrategyNotFound;
    }

    /// Get the number of registered strategies
    pub fn strategyCount(self: *const Self) usize {
        return self.strategies.items.len;
    }

    // ========================================================================
    // Clock Control
    // ========================================================================

    /// Start the clock (blocking)
    /// Runs the main loop until stop() is called
    pub fn start(self: *Self) !void {
        // Check if already running
        if (self.running.cmpxchgStrong(false, true, .seq_cst, .seq_cst)) |_| {
            return ClockError.AlreadyRunning;
        }

        // Reset statistics
        self.tick_count = 0;
        self.total_tick_time_ns = 0;
        self.max_tick_time_ns = 0;

        // Notify strategies of start
        for (self.strategies.items) |strategy| {
            try strategy.onStart();
        }

        // Main loop
        while (self.running.load(.seq_cst)) {
            const tick_start = std.time.nanoTimestamp();
            self.tick_count += 1;

            // Trigger all strategies
            for (self.strategies.items) |strategy| {
                strategy.onTick(self.tick_count, tick_start) catch |err| {
                    // Log error but continue (strategy should handle its own errors)
                    std.log.err("Strategy tick error: {}", .{err});
                };
            }

            // Calculate tick duration
            const tick_end = std.time.nanoTimestamp();
            const tick_duration: u64 = @intCast(@max(0, tick_end - tick_start));

            // Update statistics
            self.total_tick_time_ns += tick_duration;
            if (tick_duration > self.max_tick_time_ns) {
                self.max_tick_time_ns = tick_duration;
            }

            // Sleep until next tick
            if (tick_duration < self.tick_interval_ns) {
                const sleep_time = self.tick_interval_ns - tick_duration;
                std.Thread.sleep(sleep_time);
            }
        }

        // Notify strategies of stop
        for (self.strategies.items) |strategy| {
            strategy.onStop();
        }
    }

    /// Stop the clock
    pub fn stop(self: *Self) void {
        self.running.store(false, .seq_cst);
    }

    /// Check if clock is running
    pub fn isRunning(self: *const Self) bool {
        return self.running.load(.seq_cst);
    }

    // ========================================================================
    // Statistics
    // ========================================================================

    /// Get clock statistics
    pub fn getStats(self: *const Self) ClockStats {
        const avg_time = if (self.tick_count > 0)
            self.total_tick_time_ns / self.tick_count
        else
            0;

        return .{
            .tick_count = self.tick_count,
            .avg_tick_time_ns = avg_time,
            .max_tick_time_ns = self.max_tick_time_ns,
            .strategy_count = self.strategies.items.len,
        };
    }

    /// Get tick interval in milliseconds
    pub fn getTickIntervalMs(self: *const Self) u64 {
        return self.tick_interval_ns / 1_000_000;
    }

    /// Get tick interval in nanoseconds
    pub fn getTickIntervalNs(self: *const Self) u64 {
        return self.tick_interval_ns;
    }
};

// ============================================================================
// Test Strategy Implementation
// ============================================================================

/// Simple test strategy for unit testing
pub const SimpleTestStrategy = struct {
    tick_count: u64 = 0,
    started: bool = false,
    stopped: bool = false,
    last_tick: u64 = 0,
    last_timestamp: i128 = 0,

    const Self = @This();

    /// VTable for IClockStrategy
    const vtable = IClockStrategy.VTable{
        .onTick = onTickImpl,
        .onStart = onStartImpl,
        .onStop = onStopImpl,
    };

    fn onTickImpl(ptr: *anyopaque, tick: u64, timestamp_ns: i128) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.tick_count += 1;
        self.last_tick = tick;
        self.last_timestamp = timestamp_ns;
    }

    fn onStartImpl(ptr: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.started = true;
    }

    fn onStopImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.stopped = true;
    }

    /// Get IClockStrategy interface
    pub fn asClockStrategy(self: *Self) IClockStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Reset state for testing
    pub fn reset(self: *Self) void {
        self.tick_count = 0;
        self.started = false;
        self.stopped = false;
        self.last_tick = 0;
        self.last_timestamp = 0;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Clock: initialization" {
    const allocator = std.testing.allocator;

    var clock = try Clock.init(allocator, 100); // 100ms interval
    defer clock.deinit();

    try std.testing.expectEqual(@as(u64, 100_000_000), clock.tick_interval_ns);
    try std.testing.expectEqual(@as(usize, 0), clock.strategyCount());
    try std.testing.expect(!clock.isRunning());
}

test "Clock: initialization with nanoseconds" {
    const allocator = std.testing.allocator;

    var clock = try Clock.initNs(allocator, 50_000_000); // 50ms in ns
    defer clock.deinit();

    try std.testing.expectEqual(@as(u64, 50_000_000), clock.tick_interval_ns);
    try std.testing.expectEqual(@as(u64, 50), clock.getTickIntervalMs());
}

test "Clock: invalid interval" {
    const allocator = std.testing.allocator;

    const result = Clock.init(allocator, 0);
    try std.testing.expectError(ClockError.InvalidInterval, result);
}

test "Clock: add and remove strategy" {
    const allocator = std.testing.allocator;

    var clock = try Clock.init(allocator, 100);
    defer clock.deinit();

    var strategy = SimpleTestStrategy{};
    const iface = strategy.asClockStrategy();

    // Add strategy
    try clock.addStrategy(iface);
    try std.testing.expectEqual(@as(usize, 1), clock.strategyCount());

    // Try to add same strategy again
    try std.testing.expectError(ClockError.StrategyAlreadyRegistered, clock.addStrategy(iface));

    // Remove strategy
    try clock.removeStrategy(iface);
    try std.testing.expectEqual(@as(usize, 0), clock.strategyCount());

    // Try to remove non-existent strategy
    try std.testing.expectError(ClockError.StrategyNotFound, clock.removeStrategy(iface));
}

test "Clock: multiple strategies" {
    const allocator = std.testing.allocator;

    var clock = try Clock.init(allocator, 100);
    defer clock.deinit();

    var strategy1 = SimpleTestStrategy{};
    var strategy2 = SimpleTestStrategy{};
    var strategy3 = SimpleTestStrategy{};

    try clock.addStrategy(strategy1.asClockStrategy());
    try clock.addStrategy(strategy2.asClockStrategy());
    try clock.addStrategy(strategy3.asClockStrategy());

    try std.testing.expectEqual(@as(usize, 3), clock.strategyCount());

    // Remove middle strategy
    try clock.removeStrategy(strategy2.asClockStrategy());
    try std.testing.expectEqual(@as(usize, 2), clock.strategyCount());
}

test "Clock: statistics initial state" {
    const allocator = std.testing.allocator;

    var clock = try Clock.init(allocator, 100);
    defer clock.deinit();

    const stats = clock.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.tick_count);
    try std.testing.expectEqual(@as(u64, 0), stats.avg_tick_time_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.max_tick_time_ns);
    try std.testing.expectEqual(@as(usize, 0), stats.strategy_count);
}

test "Clock: start and stop with thread" {
    const allocator = std.testing.allocator;

    var clock = try Clock.init(allocator, 10); // 10ms interval
    defer clock.deinit();

    var strategy = SimpleTestStrategy{};
    try clock.addStrategy(strategy.asClockStrategy());

    // Start clock in separate thread
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(c: *Clock) void {
            c.start() catch {};
        }
    }.run, .{&clock});

    // Let it run for a few ticks
    std.Thread.sleep(55_000_000); // 55ms = ~5 ticks

    // Stop the clock
    clock.stop();
    thread.join();

    // Verify strategy was called
    try std.testing.expect(strategy.started);
    try std.testing.expect(strategy.stopped);
    try std.testing.expect(strategy.tick_count >= 3); // At least 3 ticks

    // Verify statistics
    const stats = clock.getStats();
    try std.testing.expect(stats.tick_count >= 3);
    try std.testing.expectEqual(@as(usize, 1), stats.strategy_count);
}

test "Clock: tick jitter check" {
    const allocator = std.testing.allocator;

    var clock = try Clock.init(allocator, 10); // 10ms interval
    defer clock.deinit();

    var strategy = SimpleTestStrategy{};
    try clock.addStrategy(strategy.asClockStrategy());

    // Start clock in separate thread
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(c: *Clock) void {
            c.start() catch {};
        }
    }.run, .{&clock});

    // Let it run for several ticks
    std.Thread.sleep(105_000_000); // 105ms = ~10 ticks

    // Stop the clock
    clock.stop();
    thread.join();

    // Check that max tick time is reasonable (< 10ms for processing)
    const stats = clock.getStats();
    try std.testing.expect(stats.max_tick_time_ns < 10_000_000); // Processing < 10ms
}

test "SimpleTestStrategy: interface" {
    var strategy = SimpleTestStrategy{};
    const iface = strategy.asClockStrategy();

    // Test onStart
    try iface.onStart();
    try std.testing.expect(strategy.started);

    // Test onTick
    try iface.onTick(1, 1000);
    try std.testing.expectEqual(@as(u64, 1), strategy.tick_count);
    try std.testing.expectEqual(@as(u64, 1), strategy.last_tick);
    try std.testing.expectEqual(@as(i128, 1000), strategy.last_timestamp);

    // Test multiple ticks
    try iface.onTick(2, 2000);
    try std.testing.expectEqual(@as(u64, 2), strategy.tick_count);

    // Test onStop
    iface.onStop();
    try std.testing.expect(strategy.stopped);

    // Test reset
    strategy.reset();
    try std.testing.expectEqual(@as(u64, 0), strategy.tick_count);
    try std.testing.expect(!strategy.started);
    try std.testing.expect(!strategy.stopped);
}
