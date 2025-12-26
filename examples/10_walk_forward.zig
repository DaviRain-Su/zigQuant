//! Walk-Forward Analysis Example (v0.4.0)
//!
//! 此示例展示如何使用 Walk-Forward 分析防止策略过拟合。
//!
//! Walk-Forward 分析是一种滚动优化方法：
//! 1. 将数据分为多个窗口 (训练期 + 测试期)
//! 2. 在每个训练期优化参数
//! 3. 在测试期验证参数
//! 4. 汇总所有测试期结果评估策略稳健性
//!
//! 运行：
//!   zig build run-example-walkforward

const std = @import("std");
const zigQuant = @import("zigQuant");

const Timestamp = zigQuant.Timestamp;
const Duration = zigQuant.Duration;

pub fn main() !void {
    

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║       zigQuant v0.4.0 - Walk-Forward Analysis              ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 1. Walk-Forward 分析概念
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("1. Walk-Forward 分析概念\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   目的: 防止策略过拟合，验证参数稳健性\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   传统回测的问题:\n", .{});
    std.debug.print("     - 使用全部历史数据优化参数\n", .{});
    std.debug.print("     - 参数可能过度拟合历史数据\n", .{});
    std.debug.print("     - 实盘表现可能大幅下降\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   Walk-Forward 解决方案:\n", .{});
    std.debug.print("     - 模拟真实交易场景\n", .{});
    std.debug.print("     - 只用过去数据优化，用未来数据验证\n", .{});
    std.debug.print("     - 多次验证确保参数稳健\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 2. 数据分割策略
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("2. 数据分割策略\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   支持的分割模式:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   (a) 固定窗口 (Fixed Window)\n", .{});
    std.debug.print("       |--Train--|--Test--|      |--Train--|--Test--|\n", .{});
    std.debug.print("       窗口大小固定，依次滑动\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   (b) 滚动窗口 (Rolling Window)\n", .{});
    std.debug.print("       |--Train--|--Test--|\n", .{});
    std.debug.print("         |--Train--|--Test--|\n", .{});
    std.debug.print("       窗口按步长滚动\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   (c) 扩展窗口 (Expanding Window)\n", .{});
    std.debug.print("       |--Train--|--Test--|\n", .{});
    std.debug.print("       |----Train----|--Test--|\n", .{});
    std.debug.print("       |------Train------|--Test--|\n", .{});
    std.debug.print("       训练期不断扩大\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   (d) 锚定窗口 (Anchored Window)\n", .{});
    std.debug.print("       |--Train--|--Test--|\n", .{});
    std.debug.print("       |--Train--|----|--Test--|\n", .{});
    std.debug.print("       起始点固定，测试期滑动\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 3. 示例配置
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("3. 示例配置\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   假设有 2 年历史数据 (2022-01-01 到 2023-12-31)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   Walk-Forward 配置:\n", .{});
    std.debug.print("     - 训练期: 6 个月\n", .{});
    std.debug.print("     - 测试期: 2 个月\n", .{});
    std.debug.print("     - 窗口数: 6 个\n", .{});
    std.debug.print("     - 分割模式: 滚动窗口\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   窗口划分:\n", .{});
    std.debug.print("     Window 1: Train [2022-01 ~ 2022-06] Test [2022-07 ~ 2022-08]\n", .{});
    std.debug.print("     Window 2: Train [2022-03 ~ 2022-08] Test [2022-09 ~ 2022-10]\n", .{});
    std.debug.print("     Window 3: Train [2022-05 ~ 2022-10] Test [2022-11 ~ 2022-12]\n", .{});
    std.debug.print("     Window 4: Train [2022-07 ~ 2022-12] Test [2023-01 ~ 2023-02]\n", .{});
    std.debug.print("     Window 5: Train [2022-09 ~ 2023-02] Test [2023-03 ~ 2023-04]\n", .{});
    std.debug.print("     Window 6: Train [2022-11 ~ 2023-04] Test [2023-05 ~ 2023-06]\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 4. 模拟 Walk-Forward 结果
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("4. 模拟 Walk-Forward 结果\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});

    // 模拟每个窗口的训练和测试结果
    const windows = [_]struct {
        id: u32,
        train_sharpe: f64,
        test_sharpe: f64,
        best_fast_ma: u32,
        best_slow_ma: u32,
    }{
        .{ .id = 1, .train_sharpe = 1.85, .test_sharpe = 1.42, .best_fast_ma = 10, .best_slow_ma = 30 },
        .{ .id = 2, .train_sharpe = 1.92, .test_sharpe = 1.55, .best_fast_ma = 12, .best_slow_ma = 28 },
        .{ .id = 3, .train_sharpe = 1.78, .test_sharpe = 1.38, .best_fast_ma = 10, .best_slow_ma = 32 },
        .{ .id = 4, .train_sharpe = 2.05, .test_sharpe = 1.25, .best_fast_ma = 8, .best_slow_ma = 25 },
        .{ .id = 5, .train_sharpe = 1.88, .test_sharpe = 1.62, .best_fast_ma = 11, .best_slow_ma = 30 },
        .{ .id = 6, .train_sharpe = 1.95, .test_sharpe = 1.48, .best_fast_ma = 10, .best_slow_ma = 28 },
    };

    std.debug.print("   ┌────────┬─────────────┬────────────┬───────────────────┐\n", .{});
    std.debug.print("   │ Window │ Train Sharpe│ Test Sharpe│ Best Params       │\n", .{});
    std.debug.print("   ├────────┼─────────────┼────────────┼───────────────────┤\n", .{});

    var train_sum: f64 = 0;
    var test_sum: f64 = 0;

    for (windows) |w| {
        train_sum += w.train_sharpe;
        test_sum += w.test_sharpe;
        std.debug.print("   │   {d}    │    {d:.2}     │    {d:.2}    │ fast={d}, slow={d} │\n", .{ w.id, w.train_sharpe, w.test_sharpe, w.best_fast_ma, w.best_slow_ma });
    }

    std.debug.print("   └────────┴─────────────┴────────────┴───────────────────┘\n", .{});
    std.debug.print("\n", .{});

    const avg_train = train_sum / @as(f64, @floatFromInt(windows.len));
    const avg_test = test_sum / @as(f64, @floatFromInt(windows.len));
    const efficiency = avg_test / avg_train * 100.0;

    std.debug.print("   汇总统计:\n", .{});
    std.debug.print("     - 平均训练期 Sharpe: {d:.2}\n", .{avg_train});
    std.debug.print("     - 平均测试期 Sharpe: {d:.2}\n", .{avg_test});
    std.debug.print("     - Walk-Forward 效率: {d:.1}%\n", .{efficiency});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 5. 过拟合检测
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("5. 过拟合检测\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});

    const performance_gap = avg_train - avg_test;
    const gap_ratio = performance_gap / avg_train * 100.0;

    std.debug.print("   过拟合指标:\n", .{});
    std.debug.print("     - 性能差距: {d:.2} (Train - Test)\n", .{performance_gap});
    std.debug.print("     - 差距比例: {d:.1}%\n", .{gap_ratio});
    std.debug.print("\n", .{});

    std.debug.print("   判断标准:\n", .{});
    if (gap_ratio < 20) {
        std.debug.print("     ✅ 差距 < 20%: 策略稳健，过拟合风险低\n", .{});
    } else if (gap_ratio < 40) {
        std.debug.print("     ⚠️ 差距 20-40%: 中等过拟合风险，建议调整\n", .{});
    } else {
        std.debug.print("     ❌ 差距 > 40%: 严重过拟合，需要重新设计策略\n", .{});
    }
    std.debug.print("\n", .{});

    std.debug.print("   参数稳定性分析:\n", .{});
    std.debug.print("     - fast_ma 范围: 8-12 (变异系数低)\n", .{});
    std.debug.print("     - slow_ma 范围: 25-32 (变异系数低)\n", .{});
    std.debug.print("     - 结论: 参数在不同时期保持稳定\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 6. 使用代码示例
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("6. 代码使用示例\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   // 创建 Walk-Forward 配置\n", .{});
    std.debug.print("   const wf_config = zigQuant.WalkForwardConfig{{\n", .{});
    std.debug.print("       .num_windows = 6,\n", .{});
    std.debug.print("       .train_ratio = 0.75,  // 75% 训练, 25% 测试\n", .{});
    std.debug.print("       .split_strategy = .rolling,\n", .{});
    std.debug.print("       .min_train_size = 1000,\n", .{});
    std.debug.print("       .min_test_size = 200,\n", .{});
    std.debug.print("   }};\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   // 创建分析器\n", .{});
    std.debug.print("   var analyzer = zigQuant.WalkForwardAnalyzer.init(\n", .{});
    std.debug.print("       allocator,\n", .{});
    std.debug.print("       wf_config,\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   // 运行分析\n", .{});
    std.debug.print("   const result = try analyzer.analyze(\n", .{});
    std.debug.print("       optimizer,\n", .{});
    std.debug.print("       strategy_factory,\n", .{});
    std.debug.print("       data,\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   // 检查过拟合\n", .{});
    std.debug.print("   var detector = zigQuant.OverfittingDetector.init(allocator);\n", .{});
    std.debug.print("   const metrics = try detector.analyze(result);\n", .{});
    std.debug.print("   if (metrics.is_overfitted) {{\n", .{});
    std.debug.print("       // 处理过拟合情况\n", .{});
    std.debug.print("   }}\n", .{});
    std.debug.print("\n", .{});

    // ═══════════════════════════════════════════════════════════
    // 总结
    // ═══════════════════════════════════════════════════════════
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("总结\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   Walk-Forward 分析的优势:\n", .{});
    std.debug.print("     1. 模拟真实交易环境\n", .{});
    std.debug.print("     2. 检测策略过拟合\n", .{});
    std.debug.print("     3. 验证参数稳定性\n", .{});
    std.debug.print("     4. 提供更可靠的性能预期\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("   最佳实践:\n", .{});
    std.debug.print("     1. 使用足够长的历史数据\n", .{});
    std.debug.print("     2. 训练期应包含多种市场状态\n", .{});
    std.debug.print("     3. 测试期应足够长以获得统计意义\n", .{});
    std.debug.print("     4. 关注 Walk-Forward 效率而非单一回测结果\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                    示例运行完成                             ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});
}
