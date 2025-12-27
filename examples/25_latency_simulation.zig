//! Example 25: Dual Latency Simulation (v0.7.0)
//!
//! This example demonstrates the Dual Latency Simulation module for
//! realistic modeling of feed latency and order latency in backtests.
//!
//! Features:
//! - Feed latency (market data delay)
//! - Order latency (submit + response)
//! - Multiple latency models (Constant, Normal, Interpolated)
//! - Order timeline tracking
//!
//! Run: zig build run-example-latency

const std = @import("std");
const zigQuant = @import("zigQuant");

const latency_model = zigQuant.latency_model;
const LatencyModel = latency_model.LatencyModel;
const LatencyModelType = latency_model.LatencyModelType;
const OrderLatencyModel = latency_model.OrderLatencyModel;
const FeedLatencyModel = latency_model.FeedLatencyModel;
const LatencySimulator = latency_model.LatencySimulator;
const LatencyStats = latency_model.LatencyStats;
const OrderTimeline = latency_model.OrderTimeline;

pub fn main() !void {
    // Using std.debug.print for output

    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("      Example 25: Dual Latency Simulation (v0.7.0)\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 1: Introduction
    // ========================================================================
    std.debug.print("--- 1. Introduction ---\n\n", .{});
    std.debug.print("Dual Latency Simulation models two critical paths:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Feed Latency (Market Data):\n", .{});
    std.debug.print("    Exchange -> Network -> Strategy\n", .{});
    std.debug.print("    Typical: 1-50ms\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Order Latency (Round Trip):\n", .{});
    std.debug.print("    Strategy -> Network -> Exchange -> Network -> Strategy\n", .{});
    std.debug.print("    Entry: Strategy -> Exchange\n", .{});
    std.debug.print("    Response: Exchange -> Strategy\n", .{});
    std.debug.print("    Typical: 5-100ms total\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 2: Latency Models
    // ========================================================================
    std.debug.print("--- 2. Latency Models ---\n\n", .{});

    std.debug.print("  LatencyModelType = enum {{\n", .{});
    std.debug.print("      Constant,      // Fixed latency\n", .{});
    std.debug.print("      Normal,        // Gaussian distribution\n", .{});
    std.debug.print("      Interpolated,  // From historical data\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // Constant model
    std.debug.print("  Constant Model:\n", .{});
    var const_model = LatencyModel.constantMs(10);
    const const_latency = const_model.getLatency(0);
    std.debug.print("    10ms constant -> {d:.2}ms\n", .{@as(f64, @floatFromInt(const_latency)) / 1_000_000.0});
    std.debug.print("\n", .{});

    // Normal model
    std.debug.print("  Normal Model:\n", .{});
    var normal_model = LatencyModel.normalMs(10, 2);
    normal_model.setSeed(12345);

    std.debug.print("    mean=10ms, std=2ms\n", .{});
    std.debug.print("    Samples: ", .{});
    for (0..5) |_| {
        const sample = normal_model.getLatency(0);
        std.debug.print("{d:.1}ms ", .{@as(f64, @floatFromInt(sample)) / 1_000_000.0});
    }
    std.debug.print("\n\n", .{});

    // Interpolated model
    std.debug.print("  Interpolated Model:\n", .{});
    std.debug.print("    Uses historical latency data points\n", .{});
    std.debug.print("    Linear interpolation between points\n", .{});
    std.debug.print("    Good for: Time-of-day patterns\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 3: Feed Latency
    // ========================================================================
    std.debug.print("--- 3. Feed Latency ---\n\n", .{});

    var feed = FeedLatencyModel.constant(10);
    std.debug.print("  Created FeedLatencyModel (10ms constant)\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("  Example:\n", .{});
    std.debug.print("    Exchange time: 1000000000 ns (t=1s)\n", .{});
    const local_time = feed.simulate(1000000000);
    std.debug.print("    Local time:    {d} ns (t={d:.3}s)\n", .{
        local_time,
        @as(f64, @floatFromInt(local_time)) / 1_000_000_000.0,
    });
    std.debug.print("    Delay: 10ms\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 4: Order Latency
    // ========================================================================
    std.debug.print("--- 4. Order Latency ---\n\n", .{});

    var order = OrderLatencyModel.constant(5, 5);
    std.debug.print("  Created OrderLatencyModel:\n", .{});
    std.debug.print("    - Entry latency: 5ms\n", .{});
    std.debug.print("    - Response latency: 5ms\n", .{});
    std.debug.print("    - Exchange processing: 0.1ms\n", .{});
    std.debug.print("\n", .{});

    // Simulate order flow
    const timeline = order.simulateOrderFlow(0);
    std.debug.print("  Order Timeline:\n", .{});
    std.debug.print("    - Strategy submit: {d}ns\n", .{timeline.strategy_submit});
    std.debug.print("    - Exchange arrive: {d}ns ({d:.1}ms)\n", .{
        timeline.exchange_arrive,
        timeline.entryLatencyMs(),
    });
    std.debug.print("    - Exchange process: {d}ns (+{d:.1}ms)\n", .{
        timeline.exchange_process,
        @as(f64, @floatFromInt(timeline.processingTime())) / 1_000_000.0,
    });
    std.debug.print("    - Strategy ack: {d}ns ({d:.1}ms)\n", .{
        timeline.strategy_ack,
        timeline.responseLatencyMs(),
    });
    std.debug.print("    - Total roundtrip: {d:.1}ms\n", .{timeline.roundtripMs()});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 5: Latency Simulator
    // ========================================================================
    std.debug.print("--- 5. Latency Simulator ---\n\n", .{});

    var sim = LatencySimulator.default();
    std.debug.print("  Created default LatencySimulator:\n", .{});
    std.debug.print("    - Feed latency: 10ms\n", .{});
    std.debug.print("    - Order roundtrip: 10.1ms\n", .{});
    std.debug.print("\n", .{});

    // Simulate feed event
    const feed_time = sim.simulateFeedEvent(0);
    std.debug.print("  Feed event simulation:\n", .{});
    std.debug.print("    Exchange time: 0\n", .{});
    std.debug.print("    Local receive: {d}ns ({d:.1}ms delay)\n", .{
        feed_time,
        @as(f64, @floatFromInt(feed_time)) / 1_000_000.0,
    });
    std.debug.print("\n", .{});

    // Simulate order submission
    const order_timeline = sim.simulateOrderSubmit(feed_time);
    std.debug.print("  Order simulation (submitted at local time):\n", .{});
    std.debug.print("    Submit: {d:.1}ms\n", .{@as(f64, @floatFromInt(order_timeline.strategy_submit)) / 1_000_000.0});
    std.debug.print("    Arrive at exchange: {d:.1}ms\n", .{@as(f64, @floatFromInt(order_timeline.exchange_arrive)) / 1_000_000.0});
    std.debug.print("    Ack received: {d:.1}ms\n", .{@as(f64, @floatFromInt(order_timeline.strategy_ack)) / 1_000_000.0});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 6: Zero Latency Mode
    // ========================================================================
    std.debug.print("--- 6. Zero Latency Mode ---\n\n", .{});

    var zero_sim = LatencySimulator.zeroLatency();
    std.debug.print("  Zero latency simulator for testing:\n", .{});

    const zero_feed = zero_sim.simulateFeedEvent(1000);
    const zero_order = zero_sim.simulateOrderSubmit(1000);

    std.debug.print("    Feed delay: {d}ns\n", .{zero_feed - 1000});
    std.debug.print("    Order roundtrip: {d}ns (only exchange processing)\n", .{zero_order.total_roundtrip});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 7: Latency Statistics
    // ========================================================================
    std.debug.print("--- 7. Latency Statistics ---\n\n", .{});

    var stats = LatencyStats.init();

    // Record some samples
    stats.record(10_000_000); // 10ms
    stats.record(12_000_000); // 12ms
    stats.record(8_000_000); // 8ms
    stats.record(15_000_000); // 15ms
    stats.record(9_000_000); // 9ms

    std.debug.print("  Recorded 5 samples:\n", .{});
    std.debug.print("    Count: {d}\n", .{stats.count});
    std.debug.print("    Mean: {d:.2}ms\n", .{stats.meanMs()});
    std.debug.print("    Std: {d:.2}ms\n", .{stats.stdMs()});
    std.debug.print("    Min: {d:.2}ms\n", .{stats.minMs()});
    std.debug.print("    Max: {d:.2}ms\n", .{stats.maxMs()});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 8: Backtest Integration
    // ========================================================================
    std.debug.print("--- 8. Backtest Integration ---\n\n", .{});

    std.debug.print("  // In backtest engine:\n", .{});
    std.debug.print("  fn processBar(bar: Bar) void {{\n", .{});
    std.debug.print("      // Apply feed latency\n", .{});
    std.debug.print("      const local_time = latency.simulateFeedEvent(bar.timestamp);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("      // Strategy sees delayed data\n", .{});
    std.debug.print("      strategy.onBar(bar, local_time);\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn submitOrder(order: Order, local_time: i64) void {{\n", .{});
    std.debug.print("      // Simulate order flow\n", .{});
    std.debug.print("      const timeline = latency.simulateOrderSubmit(local_time);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("      // Order arrives at exchange later\n", .{});
    std.debug.print("      scheduleEvent(timeline.exchange_arrive, executeOrder, order);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("      // Ack arrives even later\n", .{});
    std.debug.print("      scheduleEvent(timeline.strategy_ack, notifyFill, order);\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("================================================================\n", .{});
    std.debug.print("  Dual Latency Simulation Summary\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Key Features:\n", .{});
    std.debug.print("    - Separate feed and order latency\n", .{});
    std.debug.print("    - Multiple distribution models\n", .{});
    std.debug.print("    - Complete order timeline\n", .{});
    std.debug.print("    - Statistics tracking\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Impact on Backtest:\n", .{});
    std.debug.print("    - Strategy sees delayed prices\n", .{});
    std.debug.print("    - Orders execute at future prices\n", .{});
    std.debug.print("    - More realistic slippage\n", .{});
    std.debug.print("    - Better P&L estimation\n", .{});
    std.debug.print("\n", .{});
}
