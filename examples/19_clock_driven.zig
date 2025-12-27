//! Example 19: Clock-Driven Mode (v0.7.0)
//!
//! This example demonstrates the Clock-Driven execution mode for market making
//! and other strategies that require periodic updates at fixed intervals.
//!
//! Features:
//! - Fixed interval tick scheduling
//! - Multiple strategy registration
//! - Performance statistics tracking
//! - Thread-safe start/stop control
//!
//! Run: zig build run-example-clock-driven

const std = @import("std");
const zigQuant = @import("zigQuant");

const market_making = zigQuant.market_making;
const Clock = market_making.Clock;
const ClockStats = market_making.ClockStats;
const IClockStrategy = market_making.IClockStrategy;
const SimpleTestStrategy = market_making.SimpleTestStrategy;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    // Using std.debug.print for output

    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("       Example 19: Clock-Driven Mode (v0.7.0)\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 1: Introduction
    // ========================================================================
    std.debug.print("--- 1. Introduction ---\n\n", .{});
    std.debug.print("Clock-Driven mode provides:\n", .{});
    std.debug.print("  - Fixed interval strategy execution\n", .{});
    std.debug.print("  - Precise tick timing (target <10ms jitter)\n", .{});
    std.debug.print("  - Multiple strategy support\n", .{});
    std.debug.print("  - Performance tracking\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Use cases:\n", .{});
    std.debug.print("    - Market making (periodic quote updates)\n", .{});
    std.debug.print("    - TWAP/VWAP execution\n", .{});
    std.debug.print("    - Portfolio rebalancing\n", .{});
    std.debug.print("    - Periodic data collection\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 2: Clock Configuration
    // ========================================================================
    std.debug.print("--- 2. Clock Configuration ---\n\n", .{});

    std.debug.print("  Create clock with interval:\n", .{});
    std.debug.print("    var clock = try Clock.init(allocator, 100);  // 100ms\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Common intervals:\n", .{});
    std.debug.print("    - 10ms: High-frequency updates\n", .{});
    std.debug.print("    - 100ms: Standard market making\n", .{});
    std.debug.print("    - 1000ms: Low-frequency monitoring\n", .{});
    std.debug.print("\n", .{});

    // Create clock with 100ms interval
    var clock = try Clock.init(allocator, 100);
    defer clock.deinit();

    std.debug.print("  Clock created:\n", .{});
    std.debug.print("    - Interval: 100ms\n", .{});
    std.debug.print("    - Status: ready\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 3: IClockStrategy Interface
    // ========================================================================
    std.debug.print("--- 3. IClockStrategy Interface ---\n\n", .{});

    std.debug.print("  pub const IClockStrategy = struct {{\n", .{});
    std.debug.print("      ptr: *anyopaque,\n", .{});
    std.debug.print("      vtable: *const VTable,\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("      pub const VTable = struct {{\n", .{});
    std.debug.print("          onTick: fn(tick: u64, timestamp: i128) !void,\n", .{});
    std.debug.print("          onStart: fn() !void,\n", .{});
    std.debug.print("          onStop: fn() void,\n", .{});
    std.debug.print("      }};\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 4: Simple Test Strategy
    // ========================================================================
    std.debug.print("--- 4. Simple Test Strategy ---\n\n", .{});

    // Create test strategy
    var test_strategy = SimpleTestStrategy{};

    std.debug.print("  Created SimpleTestStrategy:\n", .{});
    std.debug.print("    - tick_count: {d}\n", .{test_strategy.tick_count});
    std.debug.print("    - started: {s}\n", .{if (test_strategy.started) "yes" else "no"});
    std.debug.print("    - stopped: {s}\n", .{if (test_strategy.stopped) "yes" else "no"});
    std.debug.print("\n", .{});

    // Register strategy
    try clock.addStrategy(test_strategy.asClockStrategy());
    std.debug.print("  Strategy registered with clock.\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 5: Running the Clock
    // ========================================================================
    std.debug.print("--- 5. Running the Clock ---\n\n", .{});

    std.debug.print("  // Start in separate thread (blocking call)\n", .{});
    std.debug.print("  const thread = try std.Thread.spawn(.{{}}, runClock, .{{&clock}});\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Stop from main thread\n", .{});
    std.debug.print("  std.time.sleep(5_000_000_000);  // 5 seconds\n", .{});
    std.debug.print("  clock.stop();\n", .{});
    std.debug.print("  thread.join();\n", .{});
    std.debug.print("\n", .{});

    // Simulate running for a few ticks
    std.debug.print("  Simulating 5 ticks manually:\n", .{});
    for (0..5) |i| {
        // Simulate tick
        test_strategy.tick_count += 1;
        std.debug.print("    Tick {d}: processed\n", .{i + 1});
    }
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 6: Clock Statistics
    // ========================================================================
    std.debug.print("--- 6. Clock Statistics ---\n\n", .{});

    std.debug.print("  ClockStats structure:\n", .{});
    std.debug.print("    tick_count: u64      - Total ticks processed\n", .{});
    std.debug.print("    avg_tick_time_ns: u64 - Average tick duration\n", .{});
    std.debug.print("    max_tick_time_ns: u64 - Maximum tick duration\n", .{});
    std.debug.print("    strategy_count: usize - Registered strategies\n", .{});
    std.debug.print("\n", .{});

    const stats = clock.getStats();
    std.debug.print("  Current stats:\n", .{});
    std.debug.print("    - Tick count: {d}\n", .{stats.tick_count});
    std.debug.print("    - Avg tick time: {d:.3} ms\n", .{@as(f64, @floatFromInt(stats.avg_tick_time_ns)) / 1_000_000.0});
    std.debug.print("    - Max tick time: {d:.3} ms\n", .{@as(f64, @floatFromInt(stats.max_tick_time_ns)) / 1_000_000.0});
    std.debug.print("    - Strategy count: {d}\n", .{stats.strategy_count});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 7: Multiple Strategies
    // ========================================================================
    std.debug.print("--- 7. Multiple Strategies ---\n\n", .{});

    std.debug.print("  Register multiple strategies:\n", .{});
    std.debug.print("    try clock.addStrategy(market_maker.asClockStrategy());\n", .{});
    std.debug.print("    try clock.addStrategy(inventory_mgr.asClockStrategy());\n", .{});
    std.debug.print("    try clock.addStrategy(reporter.asClockStrategy());\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  All strategies receive the same tick event.\n", .{});
    std.debug.print("  Processing order: FIFO (first registered, first called)\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 8: Error Handling
    // ========================================================================
    std.debug.print("--- 8. Error Handling ---\n\n", .{});

    std.debug.print("  Strategy errors don't stop the clock:\n", .{});
    std.debug.print("    - Error is logged\n", .{});
    std.debug.print("    - Other strategies continue\n", .{});
    std.debug.print("    - Next tick proceeds normally\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  ClockError types:\n", .{});
    std.debug.print("    - AlreadyRunning: Clock already started\n", .{});
    std.debug.print("    - NotRunning: Attempted stop when not running\n", .{});
    std.debug.print("    - StrategyFailed: Strategy threw error\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 9: Performance Targets
    // ========================================================================
    std.debug.print("--- 9. Performance Targets ---\n\n", .{});

    std.debug.print("  Tick jitter: <10ms (99th percentile)\n", .{});
    std.debug.print("  Tick processing: <1ms per strategy\n", .{});
    std.debug.print("  Memory: Stable (no leaks)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Optimization tips:\n", .{});
    std.debug.print("    - Keep onTick() lightweight\n", .{});
    std.debug.print("    - Avoid blocking I/O in tick handler\n", .{});
    std.debug.print("    - Pre-allocate resources in onStart()\n", .{});
    std.debug.print("    - Clean up in onStop()\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("================================================================\n", .{});
    std.debug.print("  Clock-Driven Mode Summary\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Key Features:\n", .{});
    std.debug.print("    - Fixed interval execution\n", .{});
    std.debug.print("    - Precise timing (<10ms jitter)\n", .{});
    std.debug.print("    - Multiple strategy support\n", .{});
    std.debug.print("    - Thread-safe control\n", .{});
    std.debug.print("    - Performance tracking\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Integration with v0.7.0:\n", .{});
    std.debug.print("    - PureMarketMaking (Story 034)\n", .{});
    std.debug.print("    - InventoryManager (Story 035)\n", .{});
    std.debug.print("    - CrossExchangeArbitrage (Story 037)\n", .{});
    std.debug.print("\n", .{});
}
