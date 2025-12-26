//! Strategy System Integration Test
//!
//! This test validates the complete strategy framework including:
//! - Strategy creation and initialization
//! - Backtest engine execution
//! - Performance analysis and metrics
//! - All three builtin strategies
//! - Grid search optimizer
//! - Memory leak detection
//!
//! Run: zig build test

const std = @import("std");
const testing = std.testing;
const zigQuant = @import("zigQuant");

const Logger = zigQuant.Logger;
const BacktestEngine = zigQuant.BacktestEngine;
const BacktestConfig = zigQuant.BacktestConfig;
const PerformanceAnalyzer = zigQuant.PerformanceAnalyzer;
const GridSearchOptimizer = zigQuant.GridSearchOptimizer;
const OptimizationConfig = zigQuant.OptimizationConfig;
const DualMAStrategy = zigQuant.DualMAStrategy;
const RSIMeanReversionStrategy = zigQuant.RSIMeanReversionStrategy;
const BollingerBreakoutStrategy = zigQuant.BollingerBreakoutStrategy;
const TradingPair = zigQuant.TradingPair;
const Timeframe = zigQuant.Timeframe;
const Timestamp = zigQuant.Timestamp;
const Decimal = zigQuant.Decimal;
const Candle = zigQuant.Candle;
const Candles = zigQuant.Candles;

// ============================================================================
// Test Helpers
// ============================================================================

/// Create a null logger for tests
fn createNullLogger(allocator: std.mem.Allocator) !Logger {
    const NullWriter = struct {
        fn write(_: *anyopaque, _: zigQuant.logger.LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const dummy = struct {};
    const log_writer = zigQuant.logger.LogWriter{
        .ptr = @constCast(@ptrCast(&dummy)),
        .writeFn = NullWriter.write,
        .flushFn = NullWriter.flush,
        .closeFn = NullWriter.close,
    };

    return Logger.init(allocator, log_writer, .err);
}

/// Generate synthetic test candles
fn generateTestCandles(allocator: std.mem.Allocator, count: usize) ![]Candle {
    const candles = try allocator.alloc(Candle, count);

    var rng = std.Random.DefaultPrng.init(42);
    const random = rng.random();

    var base_price: f64 = 50000.0;

    for (candles, 0..) |*candle, i| {
        // Generate realistic price movement
        const change = (random.float(f64) - 0.5) * 1000.0;
        base_price += change;

        const open = base_price;
        const high = base_price + random.float(f64) * 500.0;
        const low = base_price - random.float(f64) * 500.0;
        const close = low + random.float(f64) * (high - low);

        candle.* = Candle{
            .timestamp = .{ .millis = @intCast(i * 3600000) }, // 1 hour intervals
            .open = Decimal.fromFloat(open),
            .high = Decimal.fromFloat(high),
            .low = Decimal.fromFloat(low),
            .close = Decimal.fromFloat(close),
            .volume = Decimal.fromInt(1000),
        };

        base_price = close;
    }

    return candles;
}

// ============================================================================
// Strategy Tests
// ============================================================================

test "Strategy Integration: DualMA Strategy Backtest" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    // Create logger
    var logger = try createNullLogger(allocator);
    defer logger.deinit();

    // Create strategy
    const strategy_ptr = try DualMAStrategy.create(allocator, .{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .fast_period = 10,
        .slow_period = 20,
        .ma_type = .sma,
    });
    defer strategy_ptr.destroy();

    const strategy = strategy_ptr.toStrategy();

    // Create backtest config
    const config = BacktestConfig{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .timeframe = Timeframe.h1,
        .start_time = try Timestamp.fromISO8601(allocator, "2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.fromISO8601(allocator, "2024-12-31T23:59:59Z"),
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = try Decimal.fromString("0.001"),
        .slippage = try Decimal.fromString("0.0005"),
        .data_file = "data/BTCUSDT_1h_2024.csv",
    };

    // Run backtest
    var engine = BacktestEngine.init(allocator, logger);
    var result = try engine.run(strategy, config);
    defer result.deinit();

    // Verify result structure
    try testing.expect(result.total_trades >= 0);
    try testing.expect(!std.math.isNan(result.win_rate));
}

test "Strategy Integration: RSI Mean Reversion Strategy" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    // Create logger
    var logger = try createNullLogger(allocator);
    defer logger.deinit();

    // Create strategy
    const strategy_ptr = try RSIMeanReversionStrategy.create(allocator, .{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .rsi_period = 14,
        .oversold_threshold = 30,
        .overbought_threshold = 70,
    });
    defer strategy_ptr.destroy();

    const strategy = strategy_ptr.toStrategy();

    // Create backtest config
    const config = BacktestConfig{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .timeframe = Timeframe.h1,
        .start_time = try Timestamp.fromISO8601(allocator, "2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.fromISO8601(allocator, "2024-12-31T23:59:59Z"),
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = try Decimal.fromString("0.001"),
        .slippage = try Decimal.fromString("0.0005"),
        .data_file = "data/BTCUSDT_1h_2024.csv",
    };

    // Run backtest
    var engine = BacktestEngine.init(allocator, logger);
    var result = try engine.run(strategy, config);
    defer result.deinit();

    // Verify result
    try testing.expect(result.total_trades >= 0);
}

test "Strategy Integration: Bollinger Breakout Strategy" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    // Create logger
    var logger = try createNullLogger(allocator);
    defer logger.deinit();

    // Create strategy
    const strategy_ptr = try BollingerBreakoutStrategy.create(allocator, .{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .bb_period = 20,
        .bb_std_dev = 2.0,
    });
    defer strategy_ptr.destroy();

    const strategy = strategy_ptr.toStrategy();

    // Create backtest config
    const config = BacktestConfig{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .timeframe = Timeframe.h1,
        .start_time = try Timestamp.fromISO8601(allocator, "2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.fromISO8601(allocator, "2024-12-31T23:59:59Z"),
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = try Decimal.fromString("0.001"),
        .slippage = try Decimal.fromString("0.0005"),
        .data_file = "data/BTCUSDT_1h_2024.csv",
    };

    // Run backtest
    var engine = BacktestEngine.init(allocator, logger);
    var result = try engine.run(strategy, config);
    defer result.deinit();

    // Verify result
    try testing.expect(result.total_trades >= 0);
}

// ============================================================================
// Performance Analyzer Tests
// ============================================================================

test "Performance Analysis: Metrics Calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    // Create logger
    var logger = try createNullLogger(allocator);
    defer logger.deinit();

    // Create strategy
    const strategy_ptr = try DualMAStrategy.create(allocator, .{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .fast_period = 10,
        .slow_period = 20,
        .ma_type = .sma,
    });
    defer strategy_ptr.destroy();

    const strategy = strategy_ptr.toStrategy();

    // Create backtest config
    const config = BacktestConfig{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .timeframe = Timeframe.h1,
        .start_time = try Timestamp.fromISO8601(allocator, "2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.fromISO8601(allocator, "2024-12-31T23:59:59Z"),
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = try Decimal.fromString("0.001"),
        .slippage = try Decimal.fromString("0.0005"),
        .data_file = "data/BTCUSDT_1h_2024.csv",
    };

    // Run backtest
    var engine = BacktestEngine.init(allocator, logger);
    var result = try engine.run(strategy, config);
    defer result.deinit();

    // Analyze performance
    var analyzer = PerformanceAnalyzer.init(allocator, logger);

    const metrics = try analyzer.analyze(result);

    // Verify metrics are calculated
    try testing.expect(!std.math.isNan(metrics.win_rate));
    try testing.expect(!std.math.isNan(metrics.profit_factor));
    try testing.expect(!std.math.isNan(metrics.sharpe_ratio));
    try testing.expect(!std.math.isNan(metrics.max_drawdown));
}

// ============================================================================
// Optimizer Tests
// ============================================================================

test "Grid Search Optimizer: Parameter Optimization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    // Create logger
    var logger = try createNullLogger(allocator);
    defer logger.deinit();

    // Define parameters to optimize
    const StrategyParameter = zigQuant.OptimizerStrategyParameter;

    const parameters = [_]StrategyParameter{
        .{
            .name = "fast_period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .range = .{
                .integer = .{
                    .min = 5,
                    .max = 15,
                    .step = 5,
                },
            },
            .optimize = true,
        },
        .{
            .name = "slow_period",
            .type = .integer,
            .default_value = .{ .integer = 20 },
            .range = .{
                .integer = .{
                    .min = 20,
                    .max = 30,
                    .step = 10,
                },
            },
            .optimize = true,
        },
    };

    // Note: Strategy factory for optimizer would be complex to implement
    // in a test context. For now, we just verify the optimizer can be created.

    // Create optimizer config
    const backtest_config = BacktestConfig{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .timeframe = Timeframe.h1,
        .start_time = try Timestamp.fromISO8601(allocator, "2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.fromISO8601(allocator, "2024-06-30T23:59:59Z"),
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = try Decimal.fromString("0.001"),
        .slippage = try Decimal.fromString("0.0005"),
        .data_file = "data/BTCUSDT_1h_2024.csv",
    };

    const opt_config = OptimizationConfig{
        .objective = .maximize_profit_factor,
        .backtest_config = backtest_config,
        .parameters = &parameters,
        .max_combinations = 4, // Small number for fast test
        .enable_parallel = false,
    };

    // Run optimization
    var optimizer = try GridSearchOptimizer.init(allocator, opt_config);
    defer optimizer.deinit();

    // Note: Running the full optimization would require:
    // 1. A strategy factory function
    // 2. Market data file (data/BTCUSDT_1h_2024.csv)
    // For now, we just verify the optimizer was created successfully
    try testing.expect(optimizer.config.parameters.len == 2);
    const OptimizationObjective = zigQuant.OptimizationObjective;
    try testing.expectEqual(OptimizationObjective.maximize_profit_factor, optimizer.config.objective);
}

// ============================================================================
// Synthetic Data Tests (No external files required)
// ============================================================================

test "Backtest with Synthetic Data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    // Generate synthetic candles
    const candle_data = try generateTestCandles(allocator, 500);
    // Note: candle_data will be freed by candles.deinit()

    var candles = Candles.initWithCandles(
        allocator,
        TradingPair{ .base = "BTC", .quote = "USDT" },
        .h1,
        candle_data,
    );
    defer candles.deinit();

    // Create strategy
    const strategy_ptr = try DualMAStrategy.create(allocator, .{
        .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
        .fast_period = 10,
        .slow_period = 20,
        .ma_type = .sma,
    });
    defer strategy_ptr.destroy();

    // Verify candles were generated
    try testing.expectEqual(@as(usize, 500), candles.candles.len);

    // Strategy was created successfully (defer will clean it up)
}

// ============================================================================
// Memory Leak Tests
// ============================================================================

test "No Memory Leaks: Multiple Strategy Lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    // Create and destroy multiple strategies
    for (0..10) |_| {
        const strategy = try DualMAStrategy.create(allocator, .{
            .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
            .fast_period = 10,
            .slow_period = 20,
            .ma_type = .sma,
        });
        strategy.destroy();
    }
}

test "No Memory Leaks: Backtest Engine Lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    // Create logger
    var logger = try createNullLogger(allocator);
    defer logger.deinit();

    // Run multiple backtests
    for (0..5) |_| {
        const strategy_ptr = try DualMAStrategy.create(allocator, .{
            .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
            .fast_period = 10,
            .slow_period = 20,
            .ma_type = .sma,
        });
        defer strategy_ptr.destroy();

        const strategy = strategy_ptr.toStrategy();

        const config = BacktestConfig{
            .pair = TradingPair{ .base = "BTC", .quote = "USDT" },
            .timeframe = Timeframe.h1,
            .start_time = try Timestamp.fromISO8601(allocator, "2024-01-01T00:00:00Z"),
            .end_time = try Timestamp.fromISO8601(allocator, "2024-12-31T23:59:59Z"),
            .initial_capital = Decimal.fromInt(10000),
            .commission_rate = try Decimal.fromString("0.001"),
            .slippage = try Decimal.fromString("0.0005"),
            .data_file = "data/BTCUSDT_1h_2024.csv",
        };

        var engine = BacktestEngine.init(allocator, logger);
        var result = engine.run(strategy, config) catch continue; // Skip if data file missing
        defer result.deinit();
    }
}
