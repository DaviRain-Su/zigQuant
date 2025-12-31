//! 向量化回测引擎
//!
//! 集成数据加载、指标计算、信号生成和订单模拟的完整回测流程。
//! 目标性能: > 100,000 bars/s

const std = @import("std");
const Allocator = std.mem.Allocator;

const simd_indicators = @import("simd_indicators.zig");
const SimdIndicators = simd_indicators.SimdIndicators;
const data_loader = @import("data_loader.zig");
const DataSet = data_loader.DataSet;
const MmapDataLoader = data_loader.MmapDataLoader;
const signal_generator = @import("signal_generator.zig");
const Signal = signal_generator.Signal;
const SignalDirection = signal_generator.SignalDirection;
const BatchSignalGenerator = signal_generator.BatchSignalGenerator;
const order_simulator = @import("order_simulator.zig");
const BatchOrderSimulator = order_simulator.BatchOrderSimulator;
const SimulationResult = order_simulator.SimulationResult;
const PerformanceAnalyzer = order_simulator.PerformanceAnalyzer;

/// 策略类型
pub const StrategyType = enum {
    dual_ma, // 双均线策略
    rsi, // RSI 策略
    macd, // MACD 策略
    bollinger, // 布林带策略
    custom, // 自定义策略
};

/// 策略配置
pub const StrategyConfig = union(StrategyType) {
    dual_ma: DualMAConfig,
    rsi: RSIConfig,
    macd: MACDConfig,
    bollinger: BollingerConfig,
    custom: CustomConfig,

    pub const DualMAConfig = struct {
        fast_period: usize = 10,
        slow_period: usize = 30,
    };

    pub const RSIConfig = struct {
        period: usize = 14,
        oversold: f64 = 30.0,
        overbought: f64 = 70.0,
    };

    pub const MACDConfig = struct {
        fast_period: usize = 12,
        slow_period: usize = 26,
        signal_period: usize = 9,
    };

    pub const BollingerConfig = struct {
        period: usize = 20,
        num_std: f64 = 2.0,
    };

    pub const CustomConfig = struct {
        signal_fn: ?*const fn (*const DataSet, []Signal) void = null,
    };
};

/// 向量化回测器
pub const VectorizedBacktester = struct {
    allocator: Allocator,
    config: Config,
    data_loader: MmapDataLoader,
    indicators: SimdIndicators,
    signal_gen: BatchSignalGenerator,
    simulator: BatchOrderSimulator,

    pub const Config = struct {
        /// 初始资金
        initial_capital: f64 = 100000.0,
        /// 手续费率
        commission_rate: f64 = 0.001,
        /// 滑点
        slippage: f64 = 0.0005,
        /// 仓位比例
        position_size_pct: f64 = 1.0,
        /// 是否使用 SIMD
        use_simd: bool = true,
        /// 是否使用 mmap
        use_mmap: bool = true,
        /// 是否允许做空
        allow_short: bool = false,
    };

    const Self = @This();

    pub fn init(allocator: Allocator, config: Config) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .data_loader = MmapDataLoader.init(allocator, config.use_mmap),
            .indicators = SimdIndicators.init(allocator, config.use_simd),
            .signal_gen = BatchSignalGenerator.init(allocator, config.use_simd),
            .simulator = BatchOrderSimulator.init(allocator, .{
                .initial_capital = config.initial_capital,
                .commission_rate = config.commission_rate,
                .slippage = config.slippage,
                .position_size_pct = config.position_size_pct,
                .allow_short = config.allow_short,
            }),
        };
    }

    /// 从 CSV 文件加载数据
    pub fn loadData(self: *Self, path: []const u8) !DataSet {
        return self.data_loader.loadCsv(path);
    }

    /// 运行回测
    pub fn run(
        self: *Self,
        dataset: *const DataSet,
        strategy: StrategyConfig,
        progress_callback: ?*const fn (progress: f64, current: usize, total: usize) void,
    ) !BacktestResult {
        const start_time = std.time.nanoTimestamp();

        // 分配信号数组
        const signals = try self.allocator.alloc(Signal, dataset.len);
        defer self.allocator.free(signals);

        // 根据策略类型生成信号
        switch (strategy) {
            .dual_ma => |cfg| {
                try self.runDualMA(dataset, cfg, signals);
                if (progress_callback) |callback| callback(0.25, dataset.len / 4, dataset.len);
            },
            .rsi => |cfg| {
                try self.runRSI(dataset, cfg, signals);
                if (progress_callback) |callback| callback(0.25, dataset.len / 4, dataset.len);
            },
            .macd => |cfg| {
                try self.runMACD(dataset, cfg, signals);
                if (progress_callback) |callback| callback(0.25, dataset.len / 4, dataset.len);
            },
            .bollinger => |cfg| {
                try self.runBollinger(dataset, cfg, signals);
                if (progress_callback) |callback| callback(0.25, dataset.len / 4, dataset.len);
            },
            .custom => |cfg| {
                if (cfg.signal_fn) |func| {
                    func(dataset, signals);
                }
                if (progress_callback) |callback| callback(0.25, dataset.len / 4, dataset.len);
            },
        }

        if (progress_callback) |callback| callback(0.5, dataset.len / 2, dataset.len);

        // 模拟执行
        if (progress_callback) |callback| callback(0.75, (3 * dataset.len) / 4, dataset.len);
        const sim_result = try self.simulator.simulate(dataset, signals);
        if (progress_callback) |callback| callback(1.0, dataset.len, dataset.len);

        const end_time = std.time.nanoTimestamp();
        const elapsed_ns = @as(u64, @intCast(end_time - start_time));

        // 计算性能指标
        const bars_per_second = if (elapsed_ns > 0)
            @as(f64, @floatFromInt(dataset.len)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0)
        else
            0;

        return BacktestResult{
            .allocator = self.allocator,
            .simulation = sim_result,
            .strategy = strategy,
            .bars_processed = dataset.len,
            .elapsed_ns = elapsed_ns,
            .bars_per_second = bars_per_second,
        };
    }

    /// 双均线策略
    fn runDualMA(
        self: *Self,
        dataset: *const DataSet,
        config: StrategyConfig.DualMAConfig,
        signals: []Signal,
    ) !void {
        const closes = dataset.getCloses();
        const timestamps = dataset.timestamps[0..dataset.len];

        // 分配指标数组
        const fast_ma = try self.allocator.alloc(f64, dataset.len);
        defer self.allocator.free(fast_ma);

        const slow_ma = try self.allocator.alloc(f64, dataset.len);
        defer self.allocator.free(slow_ma);

        // 计算均线
        self.indicators.computeSMA(closes, config.fast_period, fast_ma);
        self.indicators.computeSMA(closes, config.slow_period, slow_ma);

        // 生成交叉信号
        self.signal_gen.generateCrossSignals(fast_ma, slow_ma, timestamps, signals);

        // 过滤连续信号
        self.signal_gen.filterConsecutiveSignals(signals);
    }

    /// RSI 策略
    fn runRSI(
        self: *Self,
        dataset: *const DataSet,
        config: StrategyConfig.RSIConfig,
        signals: []Signal,
    ) !void {
        const closes = dataset.getCloses();
        const timestamps = dataset.timestamps[0..dataset.len];

        // 分配 RSI 数组
        const rsi = try self.allocator.alloc(f64, dataset.len);
        defer self.allocator.free(rsi);

        // 计算 RSI
        try self.indicators.computeRSI(closes, config.period, rsi);

        // 生成 RSI 信号
        self.signal_gen.generateRSISignals(rsi, timestamps, config.oversold, config.overbought, signals);

        // 过滤连续信号
        self.signal_gen.filterConsecutiveSignals(signals);
    }

    /// MACD 策略
    fn runMACD(
        self: *Self,
        dataset: *const DataSet,
        config: StrategyConfig.MACDConfig,
        signals: []Signal,
    ) !void {
        const closes = dataset.getCloses();
        const timestamps = dataset.timestamps[0..dataset.len];

        // 分配 MACD 数组
        const macd_line = try self.allocator.alloc(f64, dataset.len);
        defer self.allocator.free(macd_line);

        const signal_line = try self.allocator.alloc(f64, dataset.len);
        defer self.allocator.free(signal_line);

        const histogram = try self.allocator.alloc(f64, dataset.len);
        defer self.allocator.free(histogram);

        // 计算 MACD
        try self.indicators.computeMACD(
            closes,
            config.fast_period,
            config.slow_period,
            config.signal_period,
            macd_line,
            signal_line,
            histogram,
        );

        // 生成 MACD 信号
        self.signal_gen.generateMACDSignals(macd_line, signal_line, histogram, timestamps, signals);

        // 过滤连续信号
        self.signal_gen.filterConsecutiveSignals(signals);
    }

    /// 布林带策略
    fn runBollinger(
        self: *Self,
        dataset: *const DataSet,
        config: StrategyConfig.BollingerConfig,
        signals: []Signal,
    ) !void {
        const closes = dataset.getCloses();
        const timestamps = dataset.timestamps[0..dataset.len];

        // 分配布林带数组
        const upper = try self.allocator.alloc(f64, dataset.len);
        defer self.allocator.free(upper);

        const middle = try self.allocator.alloc(f64, dataset.len);
        defer self.allocator.free(middle);

        const lower = try self.allocator.alloc(f64, dataset.len);
        defer self.allocator.free(lower);

        // 计算布林带
        try self.indicators.computeBollingerBands(
            closes,
            config.period,
            config.num_std,
            upper,
            middle,
            lower,
        );

        // 生成布林带信号
        self.signal_gen.generateBollingerSignals(closes, upper, middle, lower, timestamps, signals);

        // 过滤连续信号
        self.signal_gen.filterConsecutiveSignals(signals);
    }

    /// 批量参数优化
    pub fn optimize(
        self: *Self,
        dataset: *const DataSet,
        param_sets: []const StrategyConfig,
        results: []BacktestResult,
    ) !void {
        std.debug.assert(param_sets.len == results.len);

        for (param_sets, 0..) |params, i| {
            results[i] = try self.run(dataset, params);
        }
    }
};

/// 回测结果
pub const BacktestResult = struct {
    allocator: Allocator,

    /// 模拟结果
    simulation: SimulationResult,

    /// 策略配置
    strategy: StrategyConfig,

    /// 处理的 K 线数量
    bars_processed: usize,

    /// 耗时 (纳秒)
    elapsed_ns: u64,

    /// 每秒处理的 K 线数
    bars_per_second: f64,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.simulation.deinit();
    }

    /// 打印结果摘要
    pub fn printSummary(self: *const Self, writer: anytype) !void {
        try writer.print("\n=== 回测结果 ===\n", .{});
        try writer.print("处理 K 线: {d}\n", .{self.bars_processed});
        try writer.print("耗时: {d:.2}ms\n", .{@as(f64, @floatFromInt(self.elapsed_ns)) / 1_000_000.0});
        try writer.print("性能: {d:.0} bars/s\n", .{self.bars_per_second});
        try writer.print("\n--- 交易统计 ---\n", .{});
        try writer.print("初始资金: {d:.2}\n", .{self.simulation.initial_capital});
        try writer.print("最终资金: {d:.2}\n", .{self.simulation.final_capital});
        try writer.print("总收益: {d:.2} ({d:.2}%)\n", .{
            self.simulation.total_return,
            self.simulation.total_return_pct * 100,
        });
        try writer.print("交易次数: {d}\n", .{self.simulation.trade_count});
        try writer.print("胜率: {d:.2}%\n", .{self.simulation.win_rate * 100});
        try writer.print("盈亏比: {d:.2}\n", .{self.simulation.profit_factor});
        try writer.print("最大回撤: {d:.2}%\n", .{self.simulation.max_drawdown_pct * 100});
    }

    /// 是否达到性能目标 (100k bars/s)
    pub fn meetsPerformanceTarget(self: *const Self) bool {
        return self.bars_per_second >= 100_000;
    }
};

// ============================================================================
// 单元测试
// ============================================================================

test "VectorizedBacktester dual MA strategy" {
    const allocator = std.testing.allocator;

    var backtester = VectorizedBacktester.init(allocator, .{
        .initial_capital = 10000.0,
        .use_simd = true,
        .use_mmap = false,
    });

    // 生成测试数据
    var dataset = try data_loader.generateTestData(allocator, 1000, 12345);
    defer dataset.deinit();

    // 运行双均线策略
    var result = try backtester.run(&dataset, .{
        .dual_ma = .{ .fast_period = 10, .slow_period = 30 },
    }, null);
    defer result.deinit();

    // 验证结果
    try std.testing.expectEqual(@as(usize, 1000), result.bars_processed);
    try std.testing.expect(result.elapsed_ns > 0);
    try std.testing.expect(result.bars_per_second > 0);
}

test "VectorizedBacktester RSI strategy" {
    const allocator = std.testing.allocator;

    var backtester = VectorizedBacktester.init(allocator, .{
        .initial_capital = 10000.0,
        .use_simd = true,
        .use_mmap = false,
    });

    // 生成测试数据
    var dataset = try data_loader.generateTestData(allocator, 500, 54321);
    defer dataset.deinit();

    // 运行 RSI 策略
    var result = try backtester.run(&dataset, .{
        .rsi = .{ .period = 14, .oversold = 30.0, .overbought = 70.0 },
    }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 500), result.bars_processed);
}

test "VectorizedBacktester performance benchmark" {
    const allocator = std.testing.allocator;

    var backtester = VectorizedBacktester.init(allocator, .{
        .initial_capital = 100000.0,
        .use_simd = true,
        .use_mmap = false,
    });

    // 生成大量测试数据
    var dataset = try data_loader.generateTestData(allocator, 100_000, 99999);
    defer dataset.deinit();

    // 运行基准测试
    var result = try backtester.run(&dataset, .{
        .dual_ma = .{ .fast_period = 10, .slow_period = 30 },
    }, null);
    defer result.deinit();

    // 输出性能信息
    // std.debug.print("\nBenchmark: {d:.0} bars/s (target: 100,000)\n", .{result.bars_per_second});

    // 性能应该合理 (在测试环境中可能不达标)
    try std.testing.expect(result.bars_per_second > 10_000);
}
