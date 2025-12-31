//! Custom Strategy Example
//!
//! 此示例展示如何创建自定义交易策略并进行回测。
//!
//! 我们将实现一个简单的 MACD 交叉策略：
//! - 当 MACD 线上穿信号线时买入（多头信号）
//! - 当 MACD 线下穿信号线时卖出（空头信号）
//!
//! 功能：
//! 1. 定义自定义策略结构
//! 2. 实现 IStrategy 接口
//! 3. 使用 IndicatorManager 计算指标
//! 4. 生成交易信号
//! 5. 运行回测并展示结果
//!
//! 运行：
//!   zig build run-example-custom

const std = @import("std");
const zigQuant = @import("zigQuant");

const Logger = zigQuant.Logger;
const IStrategy = zigQuant.IStrategy;
const StrategyContext = zigQuant.strategy_interface.StrategyContext;
const StrategyMetadata = zigQuant.StrategyMetadata;
const StrategyParameter = zigQuant.StrategyParameter;
const ROITarget = zigQuant.strategy_types.ROITarget;
const ParameterType = zigQuant.ParameterType;
const ParameterValue = zigQuant.ParameterValue;
const Signal = zigQuant.Signal;
const SignalType = zigQuant.SignalType;
const SignalMetadata = zigQuant.SignalMetadata;
const IndicatorValue = zigQuant.SignalIndicatorValue;
const OrderSide = zigQuant.OrderSide;
const Candles = zigQuant.Candles;
const Position = zigQuant.backtest_position.Position;
const Account = zigQuant.backtest_account.Account;
const Decimal = zigQuant.Decimal;
const TradingPair = zigQuant.TradingPair;
const Timeframe = zigQuant.Timeframe;
const Timestamp = zigQuant.Timestamp;
const BacktestEngine = zigQuant.BacktestEngine;
const BacktestConfig = zigQuant.BacktestConfig;
const IndicatorManager = zigQuant.IndicatorManager;
const indicator_helpers = zigQuant.indicator_helpers;

// ============================================================================
// 自定义 MACD 交叉策略
// ============================================================================

/// 策略配置
pub const MACDCrossConfig = struct {
    /// 交易对
    pair: TradingPair,

    /// 快速 EMA 周期
    fast_period: u32 = 12,

    /// 慢速 EMA 周期
    slow_period: u32 = 26,

    /// 信号线周期
    signal_period: u32 = 9,

    /// 最小交叉强度（用于过滤弱信号）
    min_cross_strength: f64 = 0.0001,
};

/// MACD 交叉策略
pub const MACDCrossStrategy = struct {
    allocator: std.mem.Allocator,
    config: MACDCrossConfig,
    indicator_manager: IndicatorManager,
    logger: Logger,
    initialized: bool,

    /// 创建策略实例
    pub fn create(allocator: std.mem.Allocator, config: MACDCrossConfig) !*MACDCrossStrategy {
        const self = try allocator.create(MACDCrossStrategy);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .indicator_manager = IndicatorManager.init(allocator),
            .logger = undefined,
            .initialized = false,
        };

        return self;
    }

    /// 销毁策略
    pub fn destroy(self: *MACDCrossStrategy) void {
        self.indicator_manager.deinit();
        self.allocator.destroy(self);
    }

    /// 转换为 IStrategy 接口
    pub fn toStrategy(self: *MACDCrossStrategy) IStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn init(ptr: *anyopaque, ctx: StrategyContext) !void {
        const self: *MACDCrossStrategy = @ptrCast(@alignCast(ptr));
        self.logger = ctx.logger;
        self.initialized = true;
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *MACDCrossStrategy = @ptrCast(@alignCast(ptr));
        self.indicator_manager.deinit();
        self.initialized = false;
    }

    fn populateIndicators(ptr: *anyopaque, candles: *Candles) !void {
        const self: *MACDCrossStrategy = @ptrCast(@alignCast(ptr));

        // 计算快速 EMA
        const fast_ema = try indicator_helpers.getEMA(
            &self.indicator_manager,
            candles,
            self.config.fast_period,
        );
        _ = fast_ema;

        // 计算慢速 EMA
        const slow_ema = try indicator_helpers.getEMA(
            &self.indicator_manager,
            candles,
            self.config.slow_period,
        );
        _ = slow_ema;

        // MACD 线 = 快速 EMA - 慢速 EMA (在实际使用中会从指标中获取)
        // 信号线 = MACD 线的 EMA (在实际使用中会从指标中获取)

        // 注意：这里简化了 MACD 的计算，实际应该使用专门的 MACD 指标
        // 为了示例的简洁性，我们直接使用 EMA 交叉
    }

    fn generateEntrySignal(
        ptr: *anyopaque,
        candles: *Candles,
        index: usize,
    ) !?Signal {
        const self: *MACDCrossStrategy = @ptrCast(@alignCast(ptr));

        // 需要足够的历史数据
        if (index < self.config.slow_period + 1) return null;

        // 获取快速和慢速 EMA
        const fast_ema = try indicator_helpers.getEMA(
            &self.indicator_manager,
            candles,
            self.config.fast_period,
        );

        const slow_ema = try indicator_helpers.getEMA(
            &self.indicator_manager,
            candles,
            self.config.slow_period,
        );

        // 计算当前和前一个周期的差值
        const current_diff = fast_ema[index].sub(slow_ema[index]);
        const prev_diff = fast_ema[index - 1].sub(slow_ema[index - 1]);

        const current_diff_f = current_diff.toFloat();
        const prev_diff_f = prev_diff.toFloat();

        // 检测金叉（快线上穿慢线）
        if (prev_diff_f <= 0 and current_diff_f > 0 and current_diff_f > self.config.min_cross_strength) {
            const signal_strength = @abs(current_diff_f) / candles.candles[index].close.toFloat();

            const metadata = try SignalMetadata.init(
                self.allocator,
                "MACD golden cross: Fast EMA crossed above Slow EMA",
                @as([]const IndicatorValue, &.{}),
            );

            return try Signal.init(
                .entry_long,
                self.config.pair,
                .buy,
                candles.candles[index].close,
                signal_strength,
                candles.candles[index].timestamp,
                metadata,
            );
        }

        return null;
    }

    fn generateExitSignal(
        ptr: *anyopaque,
        candles: *Candles,
        position: Position,
    ) !?Signal {
        const self: *MACDCrossStrategy = @ptrCast(@alignCast(ptr));

        const index = candles.candles.len - 1;
        if (index < self.config.slow_period + 1) return null;

        // 获取快速和慢速 EMA
        const fast_ema = try indicator_helpers.getEMA(
            &self.indicator_manager,
            candles,
            self.config.fast_period,
        );

        const slow_ema = try indicator_helpers.getEMA(
            &self.indicator_manager,
            candles,
            self.config.slow_period,
        );

        // 计算当前和前一个周期的差值
        const current_diff = fast_ema[index].sub(slow_ema[index]);
        const prev_diff = fast_ema[index - 1].sub(slow_ema[index - 1]);

        const current_diff_f = current_diff.toFloat();
        const prev_diff_f = prev_diff.toFloat();

        // 如果持有多单，检测死叉（快线下穿慢线）
        if (position.side == .long) {
            if (prev_diff_f >= 0 and current_diff_f < 0) {
                const signal_strength = @abs(current_diff_f) / candles.candles[index].close.toFloat();

                const metadata = try SignalMetadata.init(
                    self.allocator,
                    "MACD death cross: Fast EMA crossed below Slow EMA",
                    @as([]const IndicatorValue, &.{}),
                );

                return try Signal.init(
                    .exit_long,
                    position.pair,
                    .sell,
                    candles.candles[index].close,
                    signal_strength,
                    candles.candles[index].timestamp,
                    metadata,
                );
            }
        }

        return null;
    }

    fn calculatePositionSize(
        ptr: *anyopaque,
        signal: Signal,
        account: Account,
    ) !Decimal {
        _ = ptr;
        _ = signal;

        // 简单的固定百分比仓位管理：使用账户余额的 95%
        const position_pct = try Decimal.fromString("0.95");
        return account.balance.mul(position_pct);
    }

    fn getParameters(ptr: *anyopaque) []const StrategyParameter {
        const self: *MACDCrossStrategy = @ptrCast(@alignCast(ptr));
        _ = self;

        // 返回空数组，因为这个示例不支持参数优化
        const params: []const StrategyParameter = &.{};
        return params;
    }

    fn getMetadata(ptr: *anyopaque) StrategyMetadata {
        const self: *MACDCrossStrategy = @ptrCast(@alignCast(ptr));

        const roi_targets = [_]ROITarget{
            .{ .time_minutes = 0, .profit_ratio = Decimal.fromFloat(0.03) },
            .{ .time_minutes = 30, .profit_ratio = Decimal.fromFloat(0.01) },
        };

        return .{
            .name = "MACD Cross Strategy",
            .version = "1.0.0",
            .author = "Custom Strategy Example",
            .description = "Simple MACD crossover strategy using EMA",
            .strategy_type = .trend_following,
            .timeframe = .h1,
            .startup_candle_count = self.config.slow_period + 10,
            .minimal_roi = .{ .targets = &roi_targets },
            .stoploss = Decimal.fromFloat(-0.05),
            .trailing_stop = null,
        };
    }

    const vtable = IStrategy.VTable{
        .init = init,
        .deinit = deinit,
        .populateIndicators = populateIndicators,
        .generateEntrySignal = generateEntrySignal,
        .generateExitSignal = generateExitSignal,
        .calculatePositionSize = calculatePositionSize,
        .getParameters = getParameters,
        .getMetadata = getMetadata,
    };
};

// ============================================================================
// Main Function - 运行自定义策略回测
// ============================================================================

pub fn main() !void {
    // 1. 初始化内存分配器
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // 2. 初始化日志系统
    const DummyWriter = struct {
        fn write(_: *anyopaque, record: zigQuant.logger.LogRecord) anyerror!void {
            const level_str = switch (record.level) {
                .trace => "TRACE",
                .debug => "DEBUG",
                .info => "INFO ",
                .warn => "WARN ",
                .err => "ERROR",
                .fatal => "FATAL",
            };
            std.debug.print("[{s}] {s}\n", .{ level_str, record.message });
        }
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const dummy = struct {};
    const log_writer = zigQuant.logger.LogWriter{
        .ptr = @ptrCast(@constCast(&dummy)),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    var logger = Logger.init(allocator, log_writer, .info);
    defer logger.deinit();

    try logger.info("═══════════════════════════════════════════════════", .{});
    try logger.info("    zigQuant - Custom Strategy Example", .{});
    try logger.info("═══════════════════════════════════════════════════", .{});
    try logger.info("", .{});

    // 3. 创建自定义策略
    try logger.info("Creating custom MACD Cross strategy...", .{});

    const strategy_ptr = try MACDCrossStrategy.create(allocator, .{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .fast_period = 12,
        .slow_period = 26,
        .signal_period = 9,
        .min_cross_strength = 0.0001,
    });
    defer strategy_ptr.destroy();

    const strategy = strategy_ptr.toStrategy();
    const metadata = strategy.getMetadata();

    try logger.info("✓ Strategy: {s} v{s}", .{ metadata.name, metadata.version });
    try logger.info("  Description: {s}", .{metadata.description});
    try logger.info("", .{});

    // 4. 配置回测引擎
    try logger.info("Configuring backtest...", .{});

    const backtest_config = BacktestConfig{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .timeframe = Timeframe.h1,
        .start_time = try Timestamp.fromISO8601(allocator, "2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.fromISO8601(allocator, "2024-12-31T23:59:59Z"),
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = try Decimal.fromString("0.001"),
        .slippage = try Decimal.fromString("0.0005"),
        .data_file = "data/BTCUSDT_1h_2024.csv",
    };

    try logger.info("✓ Pair: BTC/USDT | Timeframe: 1h | Capital: $10,000", .{});
    try logger.info("", .{});

    // 5. 运行回测
    var engine = BacktestEngine.init(allocator, logger);

    try logger.info("Running backtest...", .{});
    const start_time = std.time.milliTimestamp();

    var result = try engine.run(strategy, backtest_config, null);
    defer result.deinit();

    const elapsed = std.time.milliTimestamp() - start_time;
    try logger.info("✓ Backtest completed in {}ms", .{elapsed});
    try logger.info("", .{});

    // 6. 展示结果
    try logger.info("═══════════════════════════════════════════════════", .{});
    try logger.info("              Backtest Results", .{});
    try logger.info("═══════════════════════════════════════════════════", .{});
    try logger.info("", .{});

    try logger.info("Trading Statistics:", .{});
    try logger.info("  Total Trades:       {}", .{result.total_trades});
    try logger.info("  Winning Trades:     {} ({d:.1}%)", .{
        result.winning_trades,
        result.win_rate * 100,
    });
    try logger.info("  Losing Trades:      {}", .{result.losing_trades});
    try logger.info("", .{});

    try logger.info("Profit/Loss:", .{});

    const net_profit_str = try result.net_profit.toString(allocator);
    defer allocator.free(net_profit_str);
    const total_profit_str = try result.total_profit.toString(allocator);
    defer allocator.free(total_profit_str);
    const total_loss_str = try result.total_loss.toString(allocator);
    defer allocator.free(total_loss_str);

    try logger.info("  Net Profit:         ${s}", .{net_profit_str});
    try logger.info("  Total Profit:       ${s}", .{total_profit_str});
    try logger.info("  Total Loss:         ${s}", .{total_loss_str});
    try logger.info("  Profit Factor:      {d:.2}", .{result.profit_factor});
    try logger.info("", .{});

    try logger.info("Performance:", .{});
    try logger.info("  Total Candles:      {}", .{result.equity_curve.len});
    try logger.info("", .{});

    // 显示前几笔交易
    if (result.trades.len > 0) {
        const count = @min(3, result.trades.len);
        try logger.info("First {} Trade(s):", .{count});
        for (result.trades[0..count], 1..) |trade, i| {
            const entry_str = try trade.entry_price.toString(allocator);
            defer allocator.free(entry_str);
            const exit_str = try trade.exit_price.toString(allocator);
            defer allocator.free(exit_str);
            const pnl_str = try trade.pnl.toString(allocator);
            defer allocator.free(pnl_str);
            const pct_str = try trade.pnl_percent.toString(allocator);
            defer allocator.free(pct_str);

            try logger.info("  Trade #{}: {s} entry=${s} exit=${s} pnl=${s} ({s}%)", .{
                i,
                @tagName(trade.side),
                entry_str,
                exit_str,
                pnl_str,
                pct_str,
            });
        }

        if (result.trades.len > 3) {
            try logger.info("  ... and {} more trades", .{result.trades.len - 3});
        }
    }

    try logger.info("", .{});
    try logger.info("═══════════════════════════════════════════════════", .{});
    try logger.info("✓ Example Complete", .{});
    try logger.info("", .{});
    try logger.info("This example demonstrated:", .{});
    try logger.info("  1. Creating a custom strategy from scratch", .{});
    try logger.info("  2. Implementing IStrategy interface methods", .{});
    try logger.info("  3. Using IndicatorManager for calculations", .{});
    try logger.info("  4. Generating entry/exit signals", .{});
    try logger.info("  5. Running backtest with custom strategy", .{});
    try logger.info("═══════════════════════════════════════════════════", .{});
}
