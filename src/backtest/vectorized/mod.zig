//! 向量化回测模块
//!
//! 提供高性能的向量化回测功能，利用 SIMD 指令和内存映射技术
//! 实现 100,000+ bars/s 的回测速度。
//!
//! ## 模块组成
//!
//! - `VectorizedBacktester`: 主回测器，集成完整回测流程
//! - `SimdIndicators`: SIMD 加速的指标计算
//! - `MmapDataLoader`: 内存映射数据加载
//! - `BatchSignalGenerator`: 批量信号生成
//! - `BatchOrderSimulator`: 批量订单模拟
//!
//! ## 使用示例
//!
//! ```zig
//! const vectorized = @import("backtest/vectorized/mod.zig");
//!
//! var backtester = vectorized.VectorizedBacktester.init(allocator, .{
//!     .initial_capital = 100000.0,
//!     .use_simd = true,
//! });
//!
//! // 加载数据
//! var dataset = try backtester.loadData("data/btc_1m.csv");
//! defer dataset.deinit();
//!
//! // 运行双均线策略
//! var result = try backtester.run(&dataset, .{
//!     .dual_ma = .{ .fast_period = 10, .slow_period = 30 },
//! });
//! defer result.deinit();
//!
//! // 打印结果
//! try result.printSummary(std.io.getStdOut().writer());
//! ```

const std = @import("std");

// 导出子模块
pub const simd_indicators = @import("simd_indicators.zig");
pub const data_loader = @import("data_loader.zig");
pub const signal_generator = @import("signal_generator.zig");
pub const order_simulator = @import("order_simulator.zig");
pub const backtester = @import("backtester.zig");

// 主要类型导出
pub const VectorizedBacktester = backtester.VectorizedBacktester;
pub const BacktestResult = backtester.BacktestResult;
pub const StrategyType = backtester.StrategyType;
pub const StrategyConfig = backtester.StrategyConfig;

pub const SimdIndicators = simd_indicators.SimdIndicators;

pub const DataSet = data_loader.DataSet;
pub const VecCandle = data_loader.VecCandle;
pub const MmapDataLoader = data_loader.MmapDataLoader;
pub const generateTestData = data_loader.generateTestData;

pub const Signal = signal_generator.Signal;
pub const SignalDirection = signal_generator.SignalDirection;
pub const BatchSignalGenerator = signal_generator.BatchSignalGenerator;

pub const Trade = order_simulator.Trade;
pub const TradeSide = order_simulator.TradeSide;
pub const SimulationResult = order_simulator.SimulationResult;
pub const EquitySnapshot = order_simulator.EquitySnapshot;
pub const BatchOrderSimulator = order_simulator.BatchOrderSimulator;
pub const PerformanceAnalyzer = order_simulator.PerformanceAnalyzer;

/// 快速创建回测器的辅助函数
pub fn createBacktester(
    allocator: std.mem.Allocator,
    initial_capital: f64,
) VectorizedBacktester {
    return VectorizedBacktester.init(allocator, .{
        .initial_capital = initial_capital,
        .use_simd = true,
        .use_mmap = true,
    });
}

/// 快速运行双均线回测
pub fn runDualMABacktest(
    allocator: std.mem.Allocator,
    dataset: *const DataSet,
    fast_period: usize,
    slow_period: usize,
    initial_capital: f64,
) !BacktestResult {
    var bt = createBacktester(allocator, initial_capital);
    return bt.run(dataset, .{
        .dual_ma = .{
            .fast_period = fast_period,
            .slow_period = slow_period,
        },
    }, null);
}

/// 快速运行 RSI 回测
pub fn runRSIBacktest(
    allocator: std.mem.Allocator,
    dataset: *const DataSet,
    period: usize,
    oversold: f64,
    overbought: f64,
    initial_capital: f64,
) !BacktestResult {
    var bt = createBacktester(allocator, initial_capital);
    return bt.run(dataset, .{
        .rsi = .{
            .period = period,
            .oversold = oversold,
            .overbought = overbought,
        },
    }, null);
}

// ============================================================================
// 模块测试
// ============================================================================

test "module imports" {
    // 验证所有导出类型可用
    _ = VectorizedBacktester;
    _ = SimdIndicators;
    _ = DataSet;
    _ = Signal;
    _ = Trade;
}

test "quick backtest helper" {
    const allocator = std.testing.allocator;

    // 生成测试数据
    var dataset = try generateTestData(allocator, 500, 12345);
    defer dataset.deinit();

    // 使用辅助函数运行回测
    var result = try runDualMABacktest(
        allocator,
        &dataset,
        10,
        30,
        10000.0,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 500), result.bars_processed);
}

// 运行所有子模块测试
test {
    std.testing.refAllDecls(@This());
}
