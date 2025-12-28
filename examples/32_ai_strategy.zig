//! AI Strategy Example
//!
//! This example demonstrates how to use the Hybrid AI Strategy which
//! combines traditional technical analysis (RSI, SMA) with AI-powered
//! market insights.
//!
//! Features:
//! 1. Configure AI integration (optional - falls back to pure technical)
//! 2. Create HybridAIStrategy with configurable weights
//! 3. Run backtest with the hybrid strategy
//! 4. View AI-assisted signal statistics
//!
//! The hybrid strategy works in two modes:
//! - With AI: Combines technical signals (60%) with AI advice (40%)
//! - Without AI: Uses pure technical analysis (RSI + SMA signals)
//!
//! Run:
//!   zig build run-example-ai

const std = @import("std");
const zigQuant = @import("zigQuant");

const Logger = zigQuant.Logger;
const IStrategy = zigQuant.IStrategy;
const Signal = zigQuant.Signal;
const Candles = zigQuant.Candles;
const Decimal = zigQuant.Decimal;
const TradingPair = zigQuant.TradingPair;
const Timeframe = zigQuant.Timeframe;
const Timestamp = zigQuant.Timestamp;
const BacktestEngine = zigQuant.BacktestEngine;
const BacktestConfig = zigQuant.BacktestConfig;

// AI modules
const HybridAIStrategy = zigQuant.HybridAIStrategy;
const HybridAIConfig = zigQuant.HybridAIConfig;
const ai = zigQuant.ai;

// ============================================================================
// Main Function - Run Hybrid AI Strategy Backtest
// ============================================================================

pub fn main() !void {
    // 1. Initialize memory allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // 2. Initialize logging system
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
        .ptr = @constCast(@ptrCast(&dummy)),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    var logger = Logger.init(allocator, log_writer, .info);
    defer logger.deinit();

    try logger.info("============================================================", .{});
    try logger.info("    zigQuant - AI Strategy Example (v0.9.0)", .{});
    try logger.info("============================================================", .{});
    try logger.info("", .{});

    // 3. Create Hybrid AI Strategy (without LLM client for demo)
    try logger.info("Creating Hybrid AI Strategy...", .{});
    try logger.info("  Note: Running in technical-only mode (no LLM configured)", .{});
    try logger.info("", .{});

    const strategy_config = HybridAIConfig{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .timeframe = .h1,

        // Technical indicator parameters
        .rsi_period = 14,
        .rsi_oversold = 30.0,
        .rsi_overbought = 70.0,
        .sma_period = 20,

        // Signal weights (AI weight is 0 when no LLM)
        .ai_weight = 0.0, // Technical only mode
        .technical_weight = 1.0,

        // Signal thresholds
        .min_long_score = 0.65,
        .max_short_score = 0.35,
        .min_ai_confidence = 0.6,

        // Position sizing
        .risk_per_trade = 0.02,
        .max_position_pct = 0.1,
    };

    const strategy_ptr = try HybridAIStrategy.create(allocator, strategy_config);
    defer strategy_ptr.destroy();

    const strategy = strategy_ptr.toStrategy();
    const metadata = strategy.getMetadata();

    try logger.info("Strategy Configuration:", .{});
    try logger.info("  Name:           {s} v{s}", .{ metadata.name, metadata.version });
    try logger.info("  Description:    {s}", .{metadata.description});
    try logger.info("  RSI Period:     {}", .{strategy_config.rsi_period});
    try logger.info("  SMA Period:     {}", .{strategy_config.sma_period});
    try logger.info("  Technical Wt:   {d:.0}%", .{strategy_config.technical_weight * 100});
    try logger.info("  AI Weight:      {d:.0}%", .{strategy_config.ai_weight * 100});
    try logger.info("", .{});

    // 4. Configure backtest
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

    try logger.info("  Pair:           BTC/USDT", .{});
    try logger.info("  Timeframe:      1h", .{});
    try logger.info("  Period:         2024-01-01 to 2024-12-31", .{});
    try logger.info("  Initial Cap:    $10,000", .{});
    try logger.info("  Commission:     0.1%", .{});
    try logger.info("", .{});

    // 5. Run backtest
    var engine = BacktestEngine.init(allocator, logger);

    try logger.info("Running backtest...", .{});
    const start_time = std.time.milliTimestamp();

    var result = try engine.run(strategy, backtest_config);
    defer result.deinit();

    const elapsed = std.time.milliTimestamp() - start_time;
    try logger.info("Backtest completed in {}ms", .{elapsed});
    try logger.info("", .{});

    // 6. Display results
    try logger.info("============================================================", .{});
    try logger.info("                  Backtest Results", .{});
    try logger.info("============================================================", .{});
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

    // 7. Display strategy-specific statistics
    const stats = strategy_ptr.getStats();
    try logger.info("AI Strategy Statistics:", .{});
    try logger.info("  Total Signals:      {}", .{stats.total_signals});
    try logger.info("  AI-Assisted:        {}", .{stats.ai_assisted_signals});
    try logger.info("  Fallback Signals:   {}", .{stats.fallback_signals});
    try logger.info("  AI Usage Rate:      {d:.1}%", .{stats.ai_usage_rate * 100});
    try logger.info("", .{});

    // 8. Show first few trades
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

            try logger.info("  Trade #{}: {s} entry=${s} exit=${s} pnl=${s}", .{
                i,
                @tagName(trade.side),
                entry_str,
                exit_str,
                pnl_str,
            });
        }

        if (result.trades.len > 3) {
            try logger.info("  ... and {} more trades", .{result.trades.len - 3});
        }
    }

    try logger.info("", .{});
    try logger.info("============================================================", .{});
    try logger.info("Example Complete", .{});
    try logger.info("", .{});
    try logger.info("This example demonstrated:", .{});
    try logger.info("  1. Creating HybridAIStrategy with technical-only mode", .{});
    try logger.info("  2. Configuring RSI and SMA indicator parameters", .{});
    try logger.info("  3. Setting up signal weight distribution", .{});
    try logger.info("  4. Running backtest with hybrid strategy", .{});
    try logger.info("  5. Viewing AI-specific statistics", .{});
    try logger.info("", .{});
    try logger.info("To enable AI-assisted trading:", .{});
    try logger.info("  1. Set ANTHROPIC_API_KEY or OPENAI_API_KEY env variable", .{});
    try logger.info("  2. Use HybridAIStrategy.createWithAI() method", .{});
    try logger.info("  3. Adjust ai_weight/technical_weight (must sum to 1.0)", .{});
    try logger.info("============================================================", .{});
}
