//! Parallel Optimization Example (v0.4.0)
//!
//! 此示例展示如何使用并行优化加速策略参数搜索。
//!
//! 功能：
//! 1. 多线程并行回测
//! 2. 进度跟踪
//! 3. 性能对比 (并行 vs 顺序)
//!
//! 运行：
//!   zig build run-example-parallel

const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║       zigQuant v0.4.0 - Parallel Optimization              ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // 获取 CPU 核心数
    const cpu_count = std.Thread.getCpuCount() catch 4;

    // ═══════════════════════════════════════════════════════════
    // 1. 并行优化概念
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("1. 并行优化概念\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   系统信息:\n", .{});
    std.debug.print("     - 检测到 CPU 核心数: {d}\n", .{cpu_count});
    std.debug.print("     - 推荐并行线程数: {d}\n", .{cpu_count});
    std.debug.print("\n", .{});
    std.debug.print("   并行优化原理:\n", .{});
    std.debug.print("     - 网格搜索需要测试大量参数组合\n", .{});
    std.debug.print("     - 每个回测相互独立，可并行执行\n", .{});
    std.debug.print("     - 利用多核 CPU 加速计算\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   加速效果 (理论):\n", .{});
    std.debug.print("     - 顺序执行: N 个回测需要 N*T 时间\n", .{});
    std.debug.print("     - 并行执行: N 个回测需要 N*T/P 时间 (P=线程数)\n", .{});
    std.debug.print("     - 加速比: 最高可达 {d}x\n", .{cpu_count});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 2. 使用方法
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("2. 使用方法\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   方法 1: 使用 optimizeParallelTyped (推荐)\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   // 定义类型化的策略工厂函数\n", .{});
    std.debug.print("   fn createStrategy(\n", .{});
    std.debug.print("       params: zigQuant.OptimizerParameterSet\n", .{});
    std.debug.print("   ) anyerror!zigQuant.IStrategy {{\n", .{});
    std.debug.print("       // 从参数创建策略\n", .{});
    std.debug.print("       const fast = params.get(\"fast_period\").?.integer;\n", .{});
    std.debug.print("       const slow = params.get(\"slow_period\").?.integer;\n", .{});
    std.debug.print("       \n", .{});
    std.debug.print("       var strategy = try DualMAStrategy.init(\n", .{});
    std.debug.print("           allocator, fast, slow\n", .{});
    std.debug.print("       );\n", .{});
    std.debug.print("       return strategy.interface();\n", .{});
    std.debug.print("   }}\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 创建优化器 (指定线程数)\n", .{});
    std.debug.print("   var optimizer = try GridSearchOptimizer.initWithThreads(\n", .{});
    std.debug.print("       allocator,\n", .{});
    std.debug.print("       config,\n", .{});
    std.debug.print("       8,  // 使用 8 个线程\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 运行并行优化\n", .{});
    std.debug.print("   const result = try optimizer.optimizeParallelTyped(\n", .{});
    std.debug.print("       createStrategy,\n", .{});
    std.debug.print("       progressCallback,  // 可选的进度回调\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   方法 2: 配置启用并行\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   const config = OptimizationConfig{{\n", .{});
    std.debug.print("       .objective = .maximize_sharpe_ratio,\n", .{});
    std.debug.print("       .backtest_config = bt_config,\n", .{});
    std.debug.print("       .parameters = &params,\n", .{});
    std.debug.print("       .enable_parallel = true,  // 启用并行\n", .{});
    std.debug.print("   }};\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 3. 进度回调
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("3. 进度回调\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   定义进度回调函数:\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   fn progressCallback(completed: usize, total: usize) void {{\n", .{});
    std.debug.print("       const pct = @as(f64, @floatFromInt(completed)) /\n", .{});
    std.debug.print("                   @as(f64, @floatFromInt(total)) * 100.0;\n", .{});
    std.debug.print("       std.debug.print(\n", .{});
    std.debug.print("           \"\\rProgress: {{d}}/{{d}} ({{d:.1}}%%)\",\n", .{});
    std.debug.print("           .{{completed, total, pct}}\n", .{});
    std.debug.print("       );\n", .{});
    std.debug.print("   }}\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});

    // 模拟进度条
    std.debug.print("   模拟进度显示:\n", .{});
    std.debug.print("   ", .{});

    const total_steps: usize = 50;
    for (0..total_steps) |i| {
        const pct = @as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(total_steps)) * 100.0;
        const filled = (i + 1) * 30 / total_steps;
        const empty = 30 - filled;

        std.debug.print("\r   [", .{});
        for (0..filled) |_| std.debug.print("=", .{});
        for (0..empty) |_| std.debug.print(" ", .{});
        std.debug.print("] {d:.0}%", .{pct});

        std.Thread.sleep(20 * std.time.ns_per_ms);
    }
    std.debug.print(" Done!\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 4. 性能对比
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("4. 性能对比示例\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});

    // 模拟不同参数组合数的性能
    std.debug.print("   假设: 每个回测耗时 100ms\n", .{});
    std.debug.print("\n", .{});

    const combinations = [_]usize{ 100, 500, 1000, 5000, 10000 };
    const backtest_time_ms: f64 = 100.0;

    std.debug.print("   ┌────────────┬─────────────┬─────────────┬──────────┐\n", .{});
    std.debug.print("   │ 参数组合数 │ 顺序执行    │ 并行执行    │ 加速比   │\n", .{});
    std.debug.print("   │            │ (1 thread)  │ ({d} threads) │          │\n", .{cpu_count});
    std.debug.print("   ├────────────┼─────────────┼─────────────┼──────────┤\n", .{});

    for (combinations) |n| {
        const sequential_time = @as(f64, @floatFromInt(n)) * backtest_time_ms;
        const parallel_time = sequential_time / @as(f64, @floatFromInt(cpu_count));
        const speedup = sequential_time / parallel_time;

        const seq_str = formatTime(sequential_time);
        const par_str = formatTime(parallel_time);

        std.debug.print("   │ {d: >10} │ {s: <11} │ {s: <11} │ {d: >6.1}x  │\n", .{ n, seq_str, par_str, speedup });
    }

    std.debug.print("   └────────────┴─────────────┴─────────────┴──────────┘\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 5. 线程安全注意事项
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("5. 线程安全注意事项\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   策略工厂函数要求:\n", .{});
    std.debug.print("     1. 无状态或线程安全\n", .{});
    std.debug.print("     2. 每次调用创建独立的策略实例\n", .{});
    std.debug.print("     3. 不共享可变全局状态\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   安全示例:\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   // 每次创建新实例 - 线程安全\n", .{});
    std.debug.print("   fn createStrategy(params: ParameterSet) !IStrategy {{\n", .{});
    std.debug.print("       return try MyStrategy.init(allocator, params);\n", .{});
    std.debug.print("   }}\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   不安全示例:\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   var global_counter: usize = 0;  // 共享状态!\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   fn createStrategy(params: ParameterSet) !IStrategy {{\n", .{});
    std.debug.print("       global_counter += 1;  // 数据竞争!\n", .{});
    std.debug.print("       return try MyStrategy.init(allocator, params);\n", .{});
    std.debug.print("   }}\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 6. 最佳实践
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("6. 最佳实践\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   线程数选择:\n", .{});
    std.debug.print("     - CPU 密集型: 使用 CPU 核心数\n", .{});
    std.debug.print("     - I/O 密集型: 可使用 2x 核心数\n", .{});
    std.debug.print("     - 建议: 从 CPU 核心数开始，根据实际调整\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   内存考虑:\n", .{});
    std.debug.print("     - 每个线程需要独立的策略实例\n", .{});
    std.debug.print("     - 内存使用 ≈ 线程数 × 单个策略内存\n", .{});
    std.debug.print("     - 大数据集时注意内存限制\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   何时使用并行:\n", .{});
    std.debug.print("     ✅ 参数组合数 > 100\n", .{});
    std.debug.print("     ✅ 单次回测耗时 > 10ms\n", .{});
    std.debug.print("     ✅ 策略无共享状态\n", .{});
    std.debug.print("     ❌ 参数组合数很少 (< 10)\n", .{});
    std.debug.print("     ❌ 策略有复杂的共享依赖\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 总结
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("总结\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   并行优化优势:\n", .{});
    std.debug.print("     1. 大幅缩短优化时间\n", .{});
    std.debug.print("     2. 充分利用多核 CPU\n", .{});
    std.debug.print("     3. 支持更大的参数搜索空间\n", .{});
    std.debug.print("     4. 进度跟踪便于监控\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   适用场景:\n", .{});
    std.debug.print("     - 网格搜索优化\n", .{});
    std.debug.print("     - Walk-Forward 分析\n", .{});
    std.debug.print("     - 多策略批量回测\n", .{});
    std.debug.print("     - Monte Carlo 模拟\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                    示例运行完成                             ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});
}

/// 格式化时间显示
fn formatTime(ms: f64) [11]u8 {
    var buf: [11]u8 = undefined;

    if (ms < 1000) {
        _ = std.fmt.bufPrint(&buf, "{d:.0}ms      ", .{ms}) catch {};
    } else if (ms < 60000) {
        _ = std.fmt.bufPrint(&buf, "{d:.1}s       ", .{ms / 1000.0}) catch {};
    } else if (ms < 3600000) {
        _ = std.fmt.bufPrint(&buf, "{d:.1}min     ", .{ms / 60000.0}) catch {};
    } else {
        _ = std.fmt.bufPrint(&buf, "{d:.1}hr      ", .{ms / 3600000.0}) catch {};
    }

    return buf;
}
