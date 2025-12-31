//! Strategy Backtest Example
//!
//! 此示例展示如何使用 zigQuant 的回测引擎测试交易策略。
//!
//! 功能：
//! 1. 使用 StrategyFactory 加载策略配置
//! 2. 配置回测引擎参数
//! 3. 运行双均线策略回测
//! 4. 分析和展示回测结果
//!
//! 运行：
//!   zig build run-example-backtest

const std = @import("std");
const zigQuant = @import("zigQuant");

const Logger = zigQuant.Logger;
const BacktestEngine = zigQuant.BacktestEngine;
const BacktestConfig = zigQuant.BacktestConfig;
const StrategyFactory = zigQuant.StrategyFactory;
const TradingPair = zigQuant.TradingPair;
const Timeframe = zigQuant.Timeframe;
const Timestamp = zigQuant.Timestamp;
const Decimal = zigQuant.Decimal;

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
    try logger.info("    zigQuant - Strategy Backtest Example", .{});
    try logger.info("═══════════════════════════════════════════════════", .{});
    try logger.info("", .{});

    // 3. 使用 StrategyFactory 加载策略配置
    try logger.info("Loading strategy configuration...", .{});

    const config_path = "examples/strategies/dual_ma.json";
    const config_json = std.fs.cwd().readFileAlloc(
        allocator,
        config_path,
        1024 * 1024,
    ) catch |err| {
        try logger.err("Failed to read config file: {s}", .{config_path});
        try logger.err("Error: {}", .{err});
        return err;
    };
    defer allocator.free(config_json);

    var factory = StrategyFactory.init(allocator);
    var strategy_wrapper = try factory.create("dual_ma", config_json);
    defer strategy_wrapper.deinit();

    const strategy = strategy_wrapper.interface;
    const metadata = strategy.getMetadata();

    try logger.info("✓ Strategy loaded: {s} v{s}", .{ metadata.name, metadata.version });
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
        .data_file = "data/BTCUSDT_1h_2017_2025.csv",
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

    // Trading Statistics
    try logger.info("Trading Statistics:", .{});
    try logger.info("  Total Trades:       {}", .{result.total_trades});
    try logger.info("  Winning Trades:     {} ({d:.1}%)", .{
        result.winning_trades,
        result.win_rate * 100,
    });
    try logger.info("  Losing Trades:      {}", .{result.losing_trades});
    try logger.info("", .{});

    // P&L Statistics
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

    // Show first few trades if any
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
    try logger.info("═══════════════════════════════════════════════════", .{});
}
