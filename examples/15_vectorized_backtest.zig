//! Example 15: Vectorized Backtest Engine (v0.6.0)
//!
//! This example demonstrates the high-performance vectorized backtesting engine
//! that leverages SIMD instructions and memory-mapped I/O for >100k bars/s throughput.
//!
//! Features:
//! - SIMD-accelerated indicator calculations
//! - Memory-mapped data loading
//! - Batch signal generation
//! - Multiple strategy types (Dual MA, RSI, MACD, Bollinger)
//!
//! Run: zig build run-example-vectorized

const std = @import("std");
const zigQuant = @import("zigQuant");

const vectorized = zigQuant.vectorized;
const VectorizedBacktester = vectorized.VectorizedBacktester;
const DataSet = vectorized.DataSet;
const generateTestData = vectorized.generateTestData;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    // Using std.debug.print for output

    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("     Example 15: Vectorized Backtest Engine (v0.6.0)\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 1: Introduction
    // ========================================================================
    std.debug.print("--- 1. Introduction ---\n\n", .{});
    std.debug.print("The Vectorized Backtest Engine provides:\n", .{});
    std.debug.print("  - SIMD-accelerated indicator calculations\n", .{});
    std.debug.print("  - Memory-mapped data loading for large datasets\n", .{});
    std.debug.print("  - Batch signal generation and order simulation\n", .{});
    std.debug.print("  - Target performance: >100,000 bars/second\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 2: Generate Test Data
    // ========================================================================
    std.debug.print("--- 2. Generating Test Data ---\n\n", .{});

    // Generate different dataset sizes for benchmarking
    const sizes = [_]usize{ 1_000, 10_000, 100_000 };

    for (sizes) |size| {
        std.debug.print("  Generating {d} bars of test data...\n", .{size});

        var dataset = try generateTestData(allocator, size, 12345);
        defer dataset.deinit();

        std.debug.print("    - Timestamps: {d} entries\n", .{dataset.len});
        std.debug.print("    - Price range: simulated OHLCV data\n", .{});
    }
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 3: Dual Moving Average Strategy
    // ========================================================================
    std.debug.print("--- 3. Dual Moving Average Strategy ---\n\n", .{});

    {
        var backtester = VectorizedBacktester.init(allocator, .{
            .initial_capital = 100_000.0,
            .commission_rate = 0.001,
            .slippage = 0.0005,
            .use_simd = true,
            .use_mmap = false, // Use memory for generated data
        });

        var dataset = try generateTestData(allocator, 10_000, 54321);
        defer dataset.deinit();

        std.debug.print("  Running Dual MA strategy (fast=10, slow=30)...\n", .{});

        var result = try backtester.run(&dataset, .{
            .dual_ma = .{ .fast_period = 10, .slow_period = 30 },
        });
        defer result.deinit();

        std.debug.print("  Results:\n", .{});
        std.debug.print("    - Bars processed: {d}\n", .{result.bars_processed});
        std.debug.print("    - Time elapsed: {d:.2} ms\n", .{@as(f64, @floatFromInt(result.elapsed_ns)) / 1_000_000.0});
        std.debug.print("    - Performance: {d:.0} bars/s\n", .{result.bars_per_second});
        std.debug.print("    - Initial capital: {d:.2}\n", .{result.simulation.initial_capital});
        std.debug.print("    - Final capital: {d:.2}\n", .{result.simulation.final_capital});
        std.debug.print("    - Total return: {d:.2}%\n", .{result.simulation.total_return_pct * 100});
        std.debug.print("    - Trade count: {d}\n", .{result.simulation.trade_count});
        std.debug.print("    - Win rate: {d:.2}%\n", .{result.simulation.win_rate * 100});
        std.debug.print("    - Max drawdown: {d:.2}%\n", .{result.simulation.max_drawdown_pct * 100});
        std.debug.print("\n", .{});
    }

    // ========================================================================
    // Section 4: RSI Strategy
    // ========================================================================
    std.debug.print("--- 4. RSI Mean Reversion Strategy ---\n\n", .{});

    {
        var backtester = VectorizedBacktester.init(allocator, .{
            .initial_capital = 100_000.0,
            .use_simd = true,
        });

        var dataset = try generateTestData(allocator, 10_000, 11111);
        defer dataset.deinit();

        std.debug.print("  Running RSI strategy (period=14, oversold=30, overbought=70)...\n", .{});

        var result = try backtester.run(&dataset, .{
            .rsi = .{ .period = 14, .oversold = 30.0, .overbought = 70.0 },
        });
        defer result.deinit();

        std.debug.print("  Results:\n", .{});
        std.debug.print("    - Performance: {d:.0} bars/s\n", .{result.bars_per_second});
        std.debug.print("    - Total return: {d:.2}%\n", .{result.simulation.total_return_pct * 100});
        std.debug.print("    - Trade count: {d}\n", .{result.simulation.trade_count});
        std.debug.print("    - Win rate: {d:.2}%\n", .{result.simulation.win_rate * 100});
        std.debug.print("\n", .{});
    }

    // ========================================================================
    // Section 5: MACD Strategy
    // ========================================================================
    std.debug.print("--- 5. MACD Strategy ---\n\n", .{});

    {
        var backtester = VectorizedBacktester.init(allocator, .{
            .initial_capital = 100_000.0,
            .use_simd = true,
        });

        var dataset = try generateTestData(allocator, 10_000, 22222);
        defer dataset.deinit();

        std.debug.print("  Running MACD strategy (fast=12, slow=26, signal=9)...\n", .{});

        var result = try backtester.run(&dataset, .{
            .macd = .{ .fast_period = 12, .slow_period = 26, .signal_period = 9 },
        });
        defer result.deinit();

        std.debug.print("  Results:\n", .{});
        std.debug.print("    - Performance: {d:.0} bars/s\n", .{result.bars_per_second});
        std.debug.print("    - Total return: {d:.2}%\n", .{result.simulation.total_return_pct * 100});
        std.debug.print("    - Trade count: {d}\n", .{result.simulation.trade_count});
        std.debug.print("\n", .{});
    }

    // ========================================================================
    // Section 6: Bollinger Bands Strategy
    // ========================================================================
    std.debug.print("--- 6. Bollinger Bands Strategy ---\n\n", .{});

    {
        var backtester = VectorizedBacktester.init(allocator, .{
            .initial_capital = 100_000.0,
            .use_simd = true,
        });

        var dataset = try generateTestData(allocator, 10_000, 33333);
        defer dataset.deinit();

        std.debug.print("  Running Bollinger strategy (period=20, std=2.0)...\n", .{});

        var result = try backtester.run(&dataset, .{
            .bollinger = .{ .period = 20, .num_std = 2.0 },
        });
        defer result.deinit();

        std.debug.print("  Results:\n", .{});
        std.debug.print("    - Performance: {d:.0} bars/s\n", .{result.bars_per_second});
        std.debug.print("    - Total return: {d:.2}%\n", .{result.simulation.total_return_pct * 100});
        std.debug.print("    - Trade count: {d}\n", .{result.simulation.trade_count});
        std.debug.print("\n", .{});
    }

    // ========================================================================
    // Section 7: Performance Benchmark
    // ========================================================================
    std.debug.print("--- 7. Performance Benchmark ---\n\n", .{});

    std.debug.print("  Testing with 100,000 bars...\n", .{});

    {
        var backtester = VectorizedBacktester.init(allocator, .{
            .initial_capital = 100_000.0,
            .use_simd = true,
        });

        var dataset = try generateTestData(allocator, 100_000, 99999);
        defer dataset.deinit();

        var result = try backtester.run(&dataset, .{
            .dual_ma = .{ .fast_period = 10, .slow_period = 30 },
        });
        defer result.deinit();

        const meets_target = result.meetsPerformanceTarget();
        std.debug.print("  Benchmark Results:\n", .{});
        std.debug.print("    - Bars processed: {d}\n", .{result.bars_processed});
        std.debug.print("    - Time elapsed: {d:.2} ms\n", .{@as(f64, @floatFromInt(result.elapsed_ns)) / 1_000_000.0});
        std.debug.print("    - Performance: {d:.0} bars/s\n", .{result.bars_per_second});
        std.debug.print("    - Meets 100k target: {s}\n", .{if (meets_target) "YES" else "NO"});
    }

    std.debug.print("\n", .{});

    // ========================================================================
    // Section 8: Quick Helper Functions
    // ========================================================================
    std.debug.print("--- 8. Quick Helper Functions ---\n\n", .{});

    std.debug.print("  The module provides convenience functions:\n\n", .{});
    std.debug.print("  // Quick Dual MA backtest\n", .{});
    std.debug.print("  var result = try vectorized.runDualMABacktest(\n", .{});
    std.debug.print("      allocator, &dataset, 10, 30, 100000.0\n", .{});
    std.debug.print("  );\n\n", .{});
    std.debug.print("  // Quick RSI backtest\n", .{});
    std.debug.print("  var result = try vectorized.runRSIBacktest(\n", .{});
    std.debug.print("      allocator, &dataset, 14, 30.0, 70.0, 100000.0\n", .{});
    std.debug.print("  );\n\n", .{});

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("================================================================\n", .{});
    std.debug.print("  Vectorized Backtest Engine Summary\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Key Features:\n", .{});
    std.debug.print("    - SIMD acceleration for indicator calculations\n", .{});
    std.debug.print("    - Memory-mapped file loading for large datasets\n", .{});
    std.debug.print("    - Multiple built-in strategies\n", .{});
    std.debug.print("    - Comprehensive performance metrics\n", .{});
    std.debug.print("    - Target: >100,000 bars/second throughput\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Supported Strategies:\n", .{});
    std.debug.print("    - Dual Moving Average (trend following)\n", .{});
    std.debug.print("    - RSI Mean Reversion (momentum)\n", .{});
    std.debug.print("    - MACD (trend + momentum)\n", .{});
    std.debug.print("    - Bollinger Bands (volatility breakout)\n", .{});
    std.debug.print("    - Custom (user-defined signal function)\n", .{});
    std.debug.print("\n", .{});
}
