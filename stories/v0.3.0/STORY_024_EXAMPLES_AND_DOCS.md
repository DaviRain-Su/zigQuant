# Story 024: 示例、文档和集成测试完善

**Story ID**: 024
**Version**: v0.3.0
**Week**: Week 3
**Priority**: P0
**Estimated Effort**: 2 天
**Status**: 待开始

---

## 📋 概述

### 标题
示例、文档和集成测试完善

### 描述
创建完整的使用示例，更新项目文档，完善集成测试。确保用户能够快速上手策略开发，开发者能够理解系统架构，测试能够验证系统整体功能。

### 业务价值
- **降低学习曲线**: 通过完整示例帮助用户快速入门
- **提高代码质量**: 完善的测试保证系统稳定性
- **促进协作**: 清晰的文档降低团队协作成本
- **增强信心**: 完善的测试和文档提升项目专业度

### 用户故事
作为新用户，我希望能看到完整的使用示例和清晰的文档，这样我就可以快速学习如何使用 zigQuant 开发和测试交易策略。

---

## 🎯 目标与范围

### 功能目标
1. ✅ 创建策略回测示例（`examples/05_strategy_backtest.zig`）
2. ✅ 创建参数优化示例（`examples/06_strategy_optimize.zig`）
3. ✅ 创建自定义策略示例（`examples/07_custom_strategy.zig`）
4. ✅ 完善集成测试（`tests/integration/strategy_full_test.zig`）
5. ✅ 更新功能文档
6. ✅ 更新 README.md 和快速开始指南

### 非功能目标
- **可读性**: 示例代码清晰易懂，注释充分
- **完整性**: 文档覆盖所有主要功能和 API
- **准确性**: 示例可运行，文档与代码一致
- **可维护性**: 测试覆盖关键路径，易于维护

### 范围界定

#### 包含内容
- 3 个完整的示例程序
- 集成测试套件
- 功能文档更新
- API 参考文档
- README 和快速开始指南
- 策略开发教程

#### 不包含内容
- 视频教程
- 图形化界面文档
- 多语言文档
- 性能调优指南（留待后续）

---

## 📝 详细任务分解

### Task 1: 创建策略回测示例 (3小时)

**文件**: `examples/05_strategy_backtest.zig`

**目标**: 展示如何使用内置策略进行回测

**实现内容**:
```zig
//! Strategy Backtest Example
//!
//! 此示例展示如何使用 zigQuant 的回测引擎测试交易策略。
//!
//! 功能：
//! 1. 加载历史市场数据
//! 2. 配置回测引擎
//! 3. 运行双均线策略回测
//! 4. 分析和展示回测结果
//!
//! 运行：
//!   zig build run-example-05

const std = @import("std");
const zigquant = @import("zigquant");

const Logger = zigquant.Logger;
const BacktestEngine = zigquant.BacktestEngine;
const DualMAStrategy = zigquant.strategy.builtin.DualMAStrategy;
const TradingPair = zigquant.types.TradingPair;
const Timeframe = zigquant.types.Timeframe;
const Timestamp = zigquant.types.Timestamp;
const Decimal = zigquant.types.Decimal;

pub fn main() !void {
    // 1. 初始化内存分配器
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected!", .{});
        }
    }
    const allocator = gpa.allocator();

    // 2. 初始化日志系统
    var logger = try Logger.init(allocator, .info);
    defer logger.deinit();

    logger.info("=== Strategy Backtest Example ===", .{});

    // 3. 加载历史数据
    logger.info("Loading historical data...", .{});
    const data_feed = try loadHistoricalData(allocator, "data/BTC-USDT-15m.csv");
    defer data_feed.deinit();

    logger.info("Loaded {d} candles", .{data_feed.candle_count});

    // 4. 创建双均线策略
    logger.info("Creating DualMA strategy...", .{});
    var strategy = try DualMAStrategy.create(allocator, .{
        .fast_period = 10,
        .slow_period = 20,
    });
    defer strategy.deinit();

    // 5. 配置回测引擎
    logger.info("Configuring backtest engine...", .{});
    var engine = try BacktestEngine.init(allocator, logger, data_feed);
    defer engine.deinit();

    const backtest_config = BacktestEngine.Config{
        .pair = try TradingPair.parse("BTC-USDT"),
        .timeframe = Timeframe.m15,
        .start_time = try Timestamp.parse("2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.parse("2024-06-30T23:59:59Z"),
        .initial_capital = try Decimal.fromFloat(10000.0),
        .commission_rate = try Decimal.fromFloat(0.001),
    };

    // 6. 运行回测
    logger.info("Running backtest...", .{});
    const start_time = std.time.milliTimestamp();

    const result = try engine.run(strategy, backtest_config);
    defer result.deinit();

    const elapsed = std.time.milliTimestamp() - start_time;
    logger.info("Backtest completed in {d}ms", .{elapsed});

    // 7. 展示结果
    try printBacktestResults(result);

    // 8. 详细分析
    logger.info("\n=== Trade Analysis ===", .{});
    try analyzetrades(result.trades);

    // 9. 保存报告
    logger.info("\nSaving report to file...", .{});
    try saveReport(allocator, result, "backtest_report.json");
    logger.info("Report saved successfully", .{});

    logger.info("\n=== Example Complete ===", .{});
}

fn loadHistoricalData(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) !*DataFeed {
    // 从 CSV 文件加载历史数据
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var data_feed = try DataFeed.init(allocator);

    // 解析 CSV 并加载蜡烛数据
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var line_buf: [1024]u8 = undefined;
    var line_num: usize = 0;

    while (try in_stream.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
        line_num += 1;
        if (line_num == 1) continue; // 跳过标题行

        // 解析: timestamp,open,high,low,close,volume
        var iter = std.mem.split(u8, line, ",");

        const candle = Candle{
            .timestamp = try Timestamp.parse(iter.next().?),
            .open = try Decimal.parse(iter.next().?),
            .high = try Decimal.parse(iter.next().?),
            .low = try Decimal.parse(iter.next().?),
            .close = try Decimal.parse(iter.next().?),
            .volume = try Decimal.parse(iter.next().?),
        };

        try data_feed.addCandle(candle);
    }

    return data_feed;
}

fn printBacktestResults(result: BacktestEngine.Result) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n", .{});
    try stdout.print("═══════════════════════════════════════════════════\n", .{});
    try stdout.print("              Backtest Results\n", .{});
    try stdout.print("═══════════════════════════════════════════════════\n", .{});
    try stdout.print("\n", .{});

    try stdout.print("Performance Metrics:\n", .{});
    try stdout.print("───────────────────────────────────────────────────\n", .{});
    try stdout.print("  Total Trades:       {d}\n", .{result.total_trades});
    try stdout.print("  Winning Trades:     {d} ({d:.1}%)\n",
        .{result.winning_trades, result.win_rate * 100});
    try stdout.print("  Losing Trades:      {d}\n", .{result.losing_trades});
    try stdout.print("\n", .{});

    try stdout.print("Profit/Loss:\n", .{});
    try stdout.print("───────────────────────────────────────────────────\n", .{});
    try stdout.print("  Initial Capital:    ${s}\n", .{result.initial_capital.toString()});
    try stdout.print("  Final Capital:      ${s}\n", .{result.final_capital.toString()});
    try stdout.print("  Net Profit:         ${s}\n", .{result.net_profit.toString()});
    try stdout.print("  Total Profit:       ${s}\n", .{result.total_profit.toString()});
    try stdout.print("  Total Loss:         ${s}\n", .{result.total_loss.toString()});
    try stdout.print("  Profit Factor:      {d:.2}\n", .{result.profit_factor});
    try stdout.print("\n", .{});

    try stdout.print("Risk Metrics:\n", .{});
    try stdout.print("───────────────────────────────────────────────────\n", .{});
    try stdout.print("  Sharpe Ratio:       {d:.2}\n", .{result.sharpe_ratio});
    try stdout.print("  Max Drawdown:       {d:.2}%\n", .{result.max_drawdown * 100});
    try stdout.print("  Max Drawdown $:     ${s}\n", .{result.max_drawdown_amount.toString()});
    try stdout.print("\n", .{});

    try stdout.print("═══════════════════════════════════════════════════\n", .{});
}

fn analyzetrades(trades: []const Trade) !void {
    if (trades.len == 0) return;

    const stdout = std.io.getStdOut().writer();

    try stdout.print("\nFirst 5 Trades:\n", .{});
    try stdout.print("───────────────────────────────────────────────────\n", .{});
    try stdout.print("{s:<20} {s:<10} {s:<12} {s:<12} {s:<12}\n",
        .{"Entry Time", "Side", "Entry Price", "Exit Price", "PnL"});
    try stdout.print("───────────────────────────────────────────────────\n", .{});

    const count = @min(5, trades.len);
    for (trades[0..count]) |trade| {
        try stdout.print("{s:<20} {s:<10} ${s:<11} ${s:<11} ${s:<11}\n", .{
            trade.entry_time.toString(),
            @tagName(trade.side),
            trade.entry_price.toString(),
            trade.exit_price.toString(),
            trade.pnl.toString(),
        });
    }

    try stdout.print("\n", .{});
}

fn saveReport(
    allocator: std.mem.Allocator,
    result: BacktestEngine.Result,
    file_path: []const u8,
) !void {
    // 将结果序列化为 JSON 并保存
    var json_buf = std.ArrayList(u8).init(allocator);
    defer json_buf.deinit();

    try std.json.stringify(result, .{}, json_buf.writer());

    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try file.writeAll(json_buf.items);
}
```

**验收标准**:
- [ ] 示例代码可编译运行
- [ ] 注释清晰完整
- [ ] 展示核心功能
- [ ] 输出格式美观
- [ ] 无内存泄漏

---

### Task 2: 创建参数优化示例 (3小时)

**文件**: `examples/06_strategy_optimize.zig`

**目标**: 展示如何使用优化器寻找最佳参数

**实现内容**:
```zig
//! Strategy Optimization Example
//!
//! 此示例展示如何使用网格搜索优化器寻找策略的最佳参数。
//!
//! 功能：
//! 1. 定义参数搜索空间
//! 2. 配置优化目标
//! 3. 运行参数优化
//! 4. 分析优化结果
//! 5. 验证最优参数
//!
//! 运行：
//!   zig build run-example-06

const std = @import("std");
const zigquant = @import("zigquant");

const Logger = zigquant.Logger;
const BacktestEngine = zigquant.BacktestEngine;
const GridSearchOptimizer = zigquant.optimizer.GridSearchOptimizer;
const DualMAStrategy = zigquant.strategy.builtin.DualMAStrategy;
const ParameterRange = zigquant.optimizer.types.ParameterRange;
const ParameterValue = zigquant.types.ParameterValue;
const OptimizationObjective = zigquant.optimizer.types.OptimizationObjective;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected!", .{});
        }
    }
    const allocator = gpa.allocator();

    var logger = try Logger.init(allocator, .info);
    defer logger.deinit();

    logger.info("=== Strategy Optimization Example ===", .{});

    // 1. 加载历史数据
    logger.info("Loading historical data...", .{});
    const data_feed = try loadHistoricalData(allocator, "data/BTC-USDT-15m.csv");
    defer data_feed.deinit();

    // 2. 定义参数搜索空间
    logger.info("Defining parameter space...", .{});
    const parameters = [_]StrategyParameter{
        .{
            .name = "fast_period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .range = .{
                .integer = .{
                    .min = 5,
                    .max = 20,
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
                    .max = 50,
                    .step = 10,
                },
            },
            .optimize = true,
        },
    };

    // 计算总组合数
    const total_combinations = (20 - 5) / 5 + 1 * (50 - 20) / 10 + 1;
    logger.info("Total parameter combinations: {d}", .{total_combinations});

    // 3. 配置优化器
    logger.info("Configuring optimizer...", .{});
    var backtest_engine = try BacktestEngine.init(allocator, logger, data_feed);
    defer backtest_engine.deinit();

    var optimizer = GridSearchOptimizer.init(
        allocator,
        logger,
        &backtest_engine,
    );
    defer optimizer.deinit();

    // 4. 配置优化参数
    const backtest_config = BacktestEngine.Config{
        .pair = try TradingPair.parse("BTC-USDT"),
        .timeframe = Timeframe.m15,
        .start_time = try Timestamp.parse("2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.parse("2024-06-30T23:59:59Z"),
        .initial_capital = try Decimal.fromFloat(10000.0),
        .commission_rate = try Decimal.fromFloat(0.001),
    };

    const opt_config = OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = backtest_config,
        .parameters = &parameters,
        .max_combinations = null,
        .enable_parallel = false,
    };

    // 5. 定义策略工厂函数
    const StrategyFactory = struct {
        fn create(params: ParameterSet) !IStrategy {
            const fast_period = params.get("fast_period").?.integer;
            const slow_period = params.get("slow_period").?.integer;

            return try DualMAStrategy.create(allocator, .{
                .fast_period = @intCast(fast_period),
                .slow_period = @intCast(slow_period),
            });
        }
    };

    // 6. 运行优化
    logger.info("\nStarting optimization...", .{});
    const start_time = std.time.milliTimestamp();

    const result = try optimizer.optimize(StrategyFactory.create, opt_config);
    defer result.deinit();

    const elapsed = std.time.milliTimestamp() - start_time;
    logger.info("Optimization completed in {d}ms", .{elapsed});

    // 7. 展示结果
    try printOptimizationResults(result);

    // 8. 显示 Top 10 参数组合
    logger.info("\n=== Top 10 Parameter Sets ===", .{});
    try printTopResults(result, 10);

    // 9. 参数敏感性分析
    logger.info("\n=== Parameter Sensitivity Analysis ===", .{});
    try analyzeSensitivity(result);

    // 10. 验证最优参数
    logger.info("\n=== Validating Best Parameters ===", .{});
    try validateBestParams(allocator, logger, result, data_feed);

    logger.info("\n=== Example Complete ===", .{});
}

fn printOptimizationResults(result: OptimizationResult) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n", .{});
    try stdout.print("═══════════════════════════════════════════════════\n", .{});
    try stdout.print("           Optimization Results\n", .{});
    try stdout.print("═══════════════════════════════════════════════════\n", .{});
    try stdout.print("\n", .{});

    try stdout.print("Summary:\n", .{});
    try stdout.print("───────────────────────────────────────────────────\n", .{});
    try stdout.print("  Total Combinations:  {d}\n", .{result.total_combinations});
    try stdout.print("  Elapsed Time:        {d}ms\n", .{result.elapsed_time_ms});
    try stdout.print("  Avg Time per Test:   {d:.2}ms\n",
        .{@as(f64, @floatFromInt(result.elapsed_time_ms)) / @as(f64, @floatFromInt(result.total_combinations))});
    try stdout.print("\n", .{});

    try stdout.print("Best Parameters:\n", .{});
    try stdout.print("───────────────────────────────────────────────────\n", .{});

    var iter = result.best_params.values.iterator();
    while (iter.next()) |entry| {
        try stdout.print("  {s:<20} {any}\n", .{entry.key_ptr.*, entry.value_ptr.*});
    }

    try stdout.print("\n", .{});
    try stdout.print("Best Performance:\n", .{});
    try stdout.print("───────────────────────────────────────────────────\n", .{});
    try stdout.print("  Optimization Score:  {d:.4}\n", .{result.best_score});
    try stdout.print("  Net Profit:          ${s}\n", .{result.best_result.net_profit.toString()});
    try stdout.print("  Sharpe Ratio:        {d:.2}\n", .{result.best_result.sharpe_ratio});
    try stdout.print("  Win Rate:            {d:.2}%\n", .{result.best_result.win_rate * 100});
    try stdout.print("  Max Drawdown:        {d:.2}%\n", .{result.best_result.max_drawdown * 100});
    try stdout.print("\n", .{});

    try stdout.print("═══════════════════════════════════════════════════\n", .{});
}

fn printTopResults(result: OptimizationResult, top_n: u32) !void {
    const stdout = std.io.getStdOut().writer();

    const sorted = try result.getRankedResults(top_n);
    defer allocator.free(sorted);

    try stdout.print("\n", .{});
    try stdout.print("{s:<5} {s:<15} {s:<15} {s:<12} {s:<12} {s:<12}\n",
        .{"Rank", "Fast Period", "Slow Period", "Sharpe", "Win Rate", "Profit"});
    try stdout.print("────────────────────────────────────────────────────────────────────\n", .{});

    for (sorted, 1..) |r, i| {
        try stdout.print("{d:<5} {d:<15} {d:<15} {d:<12.2} {d:<12.1}% ${s}\n", .{
            i,
            r.params.get("fast_period").?.integer,
            r.params.get("slow_period").?.integer,
            r.sharpe_ratio,
            r.win_rate * 100,
            r.net_profit.toString(),
        });
    }

    try stdout.print("\n", .{});
}

fn analyzeSensitivity(result: OptimizationResult) !void {
    // 分析各参数对结果的影响
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\nParameter Impact on Performance:\n", .{});
    try stdout.print("───────────────────────────────────────────────────\n", .{});

    // 分析 fast_period
    try stdout.print("\nFast Period Impact:\n", .{});
    // 按 fast_period 分组统计平均 Sharpe Ratio
    // ...

    // 分析 slow_period
    try stdout.print("\nSlow Period Impact:\n", .{});
    // 按 slow_period 分组统计平均 Sharpe Ratio
    // ...
}

fn validateBestParams(
    allocator: std.mem.Allocator,
    logger: Logger,
    result: OptimizationResult,
    data_feed: *DataFeed,
) !void {
    logger.info("Running validation with best parameters...", .{});

    // 使用最优参数在不同时间段验证
    // 检查是否存在过拟合
    // ...
}
```

**验收标准**:
- [ ] 示例代码可编译运行
- [ ] 完整展示优化流程
- [ ] 结果分析详细
- [ ] 包含参数敏感性分析
- [ ] 无内存泄漏

---

### Task 3: 创建自定义策略示例 (2小时)

**文件**: `examples/07_custom_strategy.zig`

**目标**: 展示如何开发自定义策略

**实现内容**:
```zig
//! Custom Strategy Example
//!
//! 此示例展示如何创建自定义交易策略并进行回测。
//!
//! 我们将实现一个简单的 RSI 超买超卖策略：
//! - 当 RSI < 30 时买入（超卖）
//! - 当 RSI > 70 时卖出（超买）
//!
//! 运行：
//!   zig build run-example-07

const std = @import("std");
const zigquant = @import("zigquant");

const IStrategy = zigquant.strategy.IStrategy;
const StrategyContext = zigquant.strategy.StrategyContext;
const StrategyMetadata = zigquant.strategy.StrategyMetadata;
const Signal = zigquant.strategy.Signal;
const Candles = zigquant.types.Candles;
const Position = zigquant.types.Position;
const RSI = zigquant.strategy.indicators.RSI;

/// 自定义 RSI 策略
pub const CustomRSIStrategy = struct {
    allocator: std.mem.Allocator,
    ctx: StrategyContext,

    // 策略参数
    rsi_period: u32,
    oversold_threshold: f64,
    overbought_threshold: f64,

    const Self = @This();

    /// 创建策略实例
    pub fn create(
        allocator: std.mem.Allocator,
        config: Config,
    ) !IStrategy {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .ctx = undefined,
            .rsi_period = config.rsi_period,
            .oversold_threshold = config.oversold_threshold,
            .overbought_threshold = config.overbought_threshold,
        };

        return IStrategy{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    pub const Config = struct {
        rsi_period: u32 = 14,
        oversold_threshold: f64 = 30.0,
        overbought_threshold: f64 = 70.0,
    };

    // ========== IStrategy 接口实现 ==========

    fn initImpl(ptr: *anyopaque, ctx: StrategyContext) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.ctx = ctx;
        self.ctx.logger.info("CustomRSIStrategy initialized", .{});
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.allocator.destroy(self);
    }

    fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // 计算 RSI 指标
        const rsi_indicator = RSI.init(self.allocator, self.rsi_period);
        const rsi_values = try rsi_indicator.calculate(candles.data);

        try candles.addIndicator("rsi", rsi_values);
    }

    fn generateEntrySignalImpl(
        ptr: *anyopaque,
        candles: *Candles,
        index: usize,
    ) !?Signal {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // 需要足够的历史数据
        if (index < self.rsi_period) return null;

        const rsi_values = candles.getIndicator("rsi") orelse return null;
        const current_rsi = rsi_values[index].toFloat();

        // 超卖信号 - 买入
        if (current_rsi < self.oversold_threshold) {
            return Signal{
                .type = .entry_long,
                .pair = self.ctx.config.pair,
                .side = .buy,
                .price = candles.data[index].close,
                .strength = (self.oversold_threshold - current_rsi) / self.oversold_threshold,
                .timestamp = candles.data[index].timestamp,
                .metadata = .{
                    .reason = "RSI oversold",
                    .indicators = &[_]IndicatorValue{
                        .{ .name = "rsi", .value = current_rsi },
                    },
                },
            };
        }

        return null;
    }

    fn generateExitSignalImpl(
        ptr: *anyopaque,
        candles: *Candles,
        pos: Position,
    ) !?Signal {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const index = candles.data.len - 1;
        const rsi_values = candles.getIndicator("rsi") orelse return null;
        const current_rsi = rsi_values[index].toFloat();

        // 如果持有多单，当 RSI 超买时平仓
        if (pos.side == .long and current_rsi > self.overbought_threshold) {
            return Signal{
                .type = .exit_long,
                .pair = pos.pair,
                .side = .sell,
                .price = candles.data[index].close,
                .strength = (current_rsi - self.overbought_threshold) / (100.0 - self.overbought_threshold),
                .timestamp = candles.data[index].timestamp,
                .metadata = .{
                    .reason = "RSI overbought",
                    .indicators = &[_]IndicatorValue{
                        .{ .name = "rsi", .value = current_rsi },
                    },
                },
            };
        }

        return null;
    }

    fn calculatePositionSizeImpl(
        ptr: *anyopaque,
        signal: Signal,
        account: Account,
    ) !Decimal {
        _ = ptr;
        _ = signal;

        // 简单的固定百分比仓位管理: 使用账户余额的 10%
        const position_size = try account.balance.mul(try Decimal.fromFloat(0.1));
        return position_size;
    }

    fn getParametersImpl(ptr: *anyopaque) []StrategyParameter {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return &[_]StrategyParameter{
            .{
                .name = "rsi_period",
                .type = .integer,
                .default_value = .{ .integer = @intCast(self.rsi_period) },
                .range = .{ .integer = .{ .min = 7, .max = 21, .step = 7 } },
                .optimize = true,
            },
            .{
                .name = "oversold_threshold",
                .type = .decimal,
                .default_value = .{ .decimal = try Decimal.fromFloat(self.oversold_threshold) },
                .range = .{ .decimal = .{
                    .min = try Decimal.fromFloat(20.0),
                    .max = try Decimal.fromFloat(40.0),
                    .step = try Decimal.fromFloat(5.0),
                } },
                .optimize = true,
            },
            .{
                .name = "overbought_threshold",
                .type = .decimal,
                .default_value = .{ .decimal = try Decimal.fromFloat(self.overbought_threshold) },
                .range = .{ .decimal = .{
                    .min = try Decimal.fromFloat(60.0),
                    .max = try Decimal.fromFloat(80.0),
                    .step = try Decimal.fromFloat(5.0),
                } },
                .optimize = true,
            },
        };
    }

    fn getMetadataImpl(ptr: *anyopaque) StrategyMetadata {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = self;

        return StrategyMetadata{
            .name = "Custom RSI Mean Reversion",
            .version = "1.0.0",
            .author = "zigQuant User",
            .description = "RSI-based mean reversion strategy with customizable thresholds",
            .strategy_type = .mean_reversion,
            .timeframe = .m15,
            .startup_candle_count = self.rsi_period,
            .minimal_roi = MinimalROI{
                .targets = &[_]MinimalROI.ROITarget{
                    .{ .time_minutes = 0, .profit_ratio = try Decimal.fromFloat(0.03) },
                    .{ .time_minutes = 60, .profit_ratio = try Decimal.fromFloat(0.01) },
                },
            },
            .stoploss = try Decimal.fromFloat(-0.05),
            .trailing_stop = null,
        };
    }

    const vtable = IStrategy.VTable{
        .init = initImpl,
        .deinit = deinitImpl,
        .populateIndicators = populateIndicatorsImpl,
        .generateEntrySignal = generateEntrySignalImpl,
        .generateExitSignal = generateExitSignalImpl,
        .calculatePositionSize = calculatePositionSizeImpl,
        .getParameters = getParametersImpl,
        .getMetadata = getMetadataImpl,
    };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected!", .{});
        }
    }
    const allocator = gpa.allocator();

    var logger = try Logger.init(allocator, .info);
    defer logger.deinit();

    logger.info("=== Custom Strategy Example ===", .{});

    // 1. 创建自定义策略
    logger.info("Creating custom RSI strategy...", .{});
    var strategy = try CustomRSIStrategy.create(allocator, .{
        .rsi_period = 14,
        .oversold_threshold = 30.0,
        .overbought_threshold = 70.0,
    });
    defer strategy.deinit();

    // 2. 显示策略信息
    const metadata = strategy.getMetadata();
    logger.info("Strategy: {s} v{s}", .{metadata.name, metadata.version});
    logger.info("Type: {s}", .{@tagName(metadata.strategy_type)});

    // 3. 加载数据并回测
    logger.info("\nLoading data and running backtest...", .{});
    const data_feed = try loadHistoricalData(allocator, "data/BTC-USDT-15m.csv");
    defer data_feed.deinit();

    var engine = try BacktestEngine.init(allocator, logger, data_feed);
    defer engine.deinit();

    const backtest_config = BacktestEngine.Config{
        .pair = try TradingPair.parse("BTC-USDT"),
        .timeframe = Timeframe.m15,
        .start_time = try Timestamp.parse("2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.parse("2024-06-30T23:59:59Z"),
        .initial_capital = try Decimal.fromFloat(10000.0),
        .commission_rate = try Decimal.fromFloat(0.001),
    };

    const result = try engine.run(strategy, backtest_config);
    defer result.deinit();

    // 4. 展示结果
    try printBacktestResults(result);

    logger.info("\n=== Example Complete ===", .{});
    logger.info("You have successfully created and tested a custom strategy!", .{});
}
```

**验收标准**:
- [ ] 示例代码可编译运行
- [ ] 完整展示自定义策略开发流程
- [ ] 包含详细注释说明
- [ ] 策略逻辑清晰易懂
- [ ] 无内存泄漏

---

### Task 4: 完善集成测试 (4小时)

**文件**: `tests/integration/strategy_full_test.zig`

**测试内容**:
```zig
//! Strategy Framework Integration Tests
//!
//! 完整的策略框架集成测试，覆盖从数据加载到回测分析的全流程。

const std = @import("std");
const testing = std.testing;
const zigquant = @import("zigquant");

test "集成测试: 完整回测流程" {
    const allocator = testing.allocator;

    // 1. 准备测试数据
    var data_feed = try createTestDataFeed(allocator);
    defer data_feed.deinit();

    // 2. 创建策略
    var strategy = try DualMAStrategy.create(allocator, .{
        .fast_period = 10,
        .slow_period = 20,
    });
    defer strategy.deinit();

    // 3. 创建回测引擎
    var logger = try Logger.init(allocator, .warn);
    defer logger.deinit();

    var engine = try BacktestEngine.init(allocator, logger, &data_feed);
    defer engine.deinit();

    // 4. 运行回测
    const config = BacktestEngine.Config{
        .pair = try TradingPair.parse("BTC-USDT"),
        .timeframe = Timeframe.m15,
        .start_time = try Timestamp.parse("2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.parse("2024-01-31T23:59:59Z"),
        .initial_capital = try Decimal.fromFloat(10000.0),
        .commission_rate = try Decimal.fromFloat(0.001),
    };

    const result = try engine.run(strategy, config);
    defer result.deinit();

    // 5. 验证结果
    try testing.expect(result.total_trades > 0);
    try testing.expect(result.winning_trades + result.losing_trades == result.total_trades);
    try testing.expect(result.win_rate >= 0.0 and result.win_rate <= 1.0);
}

test "集成测试: 参数优化流程" {
    const allocator = testing.allocator;

    // 准备数据
    var data_feed = try createTestDataFeed(allocator);
    defer data_feed.deinit();

    var logger = try Logger.init(allocator, .warn);
    defer logger.deinit();

    // 创建回测引擎和优化器
    var backtest_engine = try BacktestEngine.init(allocator, logger, &data_feed);
    defer backtest_engine.deinit();

    var optimizer = GridSearchOptimizer.init(allocator, logger, &backtest_engine);
    defer optimizer.deinit();

    // 定义参数空间
    const parameters = [_]StrategyParameter{
        .{
            .name = "fast_period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .range = .{ .integer = .{ .min = 5, .max = 15, .step = 5 } },
            .optimize = true,
        },
        .{
            .name = "slow_period",
            .type = .integer,
            .default_value = .{ .integer = 20 },
            .range = .{ .integer = .{ .min = 20, .max = 30, .step = 5 } },
            .optimize = true,
        },
    };

    // 运行优化
    const backtest_config = BacktestEngine.Config{
        .pair = try TradingPair.parse("BTC-USDT"),
        .timeframe = Timeframe.m15,
        .start_time = try Timestamp.parse("2024-01-01T00:00:00Z"),
        .end_time = try Timestamp.parse("2024-01-31T23:59:59Z"),
        .initial_capital = try Decimal.fromFloat(10000.0),
        .commission_rate = try Decimal.fromFloat(0.001),
    };

    const opt_config = OptimizationConfig{
        .objective = .maximize_sharpe_ratio,
        .backtest_config = backtest_config,
        .parameters = &parameters,
        .max_combinations = null,
        .enable_parallel = false,
    };

    const strategy_factory = struct {
        fn create(params: ParameterSet) !IStrategy {
            return try DualMAStrategy.create(allocator, .{
                .fast_period = @intCast(params.get("fast_period").?.integer),
                .slow_period = @intCast(params.get("slow_period").?.integer),
            });
        }
    }.create;

    const result = try optimizer.optimize(strategy_factory, opt_config);
    defer result.deinit();

    // 验证优化结果
    try testing.expect(result.total_combinations == 9);  // 3 * 3 = 9
    try testing.expect(result.best_score > 0.0);
}

test "集成测试: 多策略对比" {
    // 测试多个策略在相同数据上的表现对比
}

test "集成测试: 内存安全" {
    // 使用 GeneralPurposeAllocator 验证无内存泄漏
}

test "集成测试: 性能基准" {
    // 测试回测性能是否达标
}

// 辅助函数
fn createTestDataFeed(allocator: std.mem.Allocator) !DataFeed {
    // 生成模拟的历史数据
    var data_feed = try DataFeed.init(allocator);

    // 生成 30 天的 15 分钟K线数据
    const start_time = try Timestamp.parse("2024-01-01T00:00:00Z");
    var current_time = start_time;
    var price = try Decimal.fromFloat(45000.0);

    for (0..2880) |_| {  // 30 天 * 96 根K线/天
        // 随机价格波动
        const rand = std.crypto.random;
        const change_pct = @as(f64, @floatFromInt(rand.intRangeAtMost(i32, -100, 100))) / 10000.0;
        price = try price.mul(try Decimal.fromFloat(1.0 + change_pct));

        const candle = Candle{
            .timestamp = current_time,
            .open = price,
            .high = try price.mul(try Decimal.fromFloat(1.001)),
            .low = try price.mul(try Decimal.fromFloat(0.999)),
            .close = price,
            .volume = try Decimal.fromFloat(1000.0),
        };

        try data_feed.addCandle(candle);
        current_time = current_time.add(15 * 60);  // +15 分钟
    }

    return data_feed;
}
```

**验收标准**:
- [ ] 所有集成测试通过
- [ ] 覆盖核心业务流程
- [ ] 测试数据生成合理
- [ ] 性能测试达标
- [ ] 内存安全测试通过

---

### Task 5: 更新功能文档 (3小时)

**更新文档列表**:
1. `/home/davirain/dev/zigQuant/docs/features/strategy/README.md`
2. `/home/davirain/dev/zigQuant/docs/features/strategy/tutorial.md` (新建)
3. `/home/davirain/dev/zigQuant/docs/features/backtest/README.md`
4. `/home/davirain/dev/zigQuant/docs/features/indicators/api_reference.md` (新建)
5. `/home/davirain/dev/zigQuant/docs/API_REFERENCE.md` (更新)

**文档结构**: `tutorial.md`
```markdown
# 策略开发教程

## 目录
1. [快速开始](#快速开始)
2. [创建自定义策略](#创建自定义策略)
3. [使用技术指标](#使用技术指标)
4. [运行回测](#运行回测)
5. [参数优化](#参数优化)
6. [最佳实践](#最佳实践)

## 快速开始

### 使用内置策略

最简单的方式是使用 zigQuant 提供的内置策略...

### 运行第一个回测

```zig
const std = @import("std");
const zigquant = @import("zigquant");

pub fn main() !void {
    // ... 示例代码
}
```

## 创建自定义策略

### 步骤 1: 实现 IStrategy 接口

要创建自定义策略，你需要实现 `IStrategy` 接口...

### 步骤 2: 定义策略参数

...

### 步骤 3: 实现信号生成逻辑

...

## 使用技术指标

zigQuant 提供了丰富的技术指标库...

### 可用指标

- SMA (简单移动平均)
- EMA (指数移动平均)
- RSI (相对强弱指标)
- MACD
- Bollinger Bands

### 指标使用示例

```zig
const RSI = zigquant.strategy.indicators.RSI;

fn populateIndicators(self: *Self, candles: *Candles) !void {
    const rsi = RSI.init(self.allocator, 14);
    const rsi_values = try rsi.calculate(candles.data);
    try candles.addIndicator("rsi", rsi_values);
}
```

## 运行回测

### CLI 方式

```bash
zigquant strategy backtest --strategy DualMA --pair BTC-USDT
```

### 编程方式

```zig
// 示例代码
```

## 参数优化

### 定义参数空间

...

### 运行优化

```bash
zigquant strategy optimize --strategy DualMA -c config.toml
```

## 最佳实践

### 1. 参数设置

- 避免过度优化
- 使用合理的参数范围
- 进行交叉验证

### 2. 风险管理

- 设置止损
- 控制仓位大小
- 分散投资

### 3. 性能优化

- 缓存指标计算结果
- 避免重复计算
- 使用合适的数据结构

## 常见问题

### Q: 如何避免过拟合？

A: ...

### Q: 如何提高回测速度？

A: ...
```

**验收标准**:
- [ ] 所有文档更新完成
- [ ] 文档内容准确无误
- [ ] 包含完整代码示例
- [ ] 格式统一美观
- [ ] 链接正确有效

---

### Task 6: 更新 README 和快速开始指南 (2小时)

**更新**: `/home/davirain/dev/zigQuant/README.md`

**添加内容**:
```markdown
## 策略开发和回测

### 使用内置策略

zigQuant 提供了多个内置策略供您使用：

```bash
# 查看可用策略
zigquant strategy list

# 运行双均线策略回测
zigquant strategy backtest --strategy DualMA --pair BTC-USDT \
  --start 2024-01-01T00:00:00Z --end 2024-06-30T23:59:59Z
```

### 创建自定义策略

```zig
const zigquant = @import("zigquant");
const IStrategy = zigquant.strategy.IStrategy;

pub const MyStrategy = struct {
    // 实现 IStrategy 接口
    // ...
};
```

查看完整教程: [策略开发教程](docs/features/strategy/tutorial.md)

### 参数优化

```bash
# 优化策略参数
zigquant strategy optimize --strategy DualMA \
  --objective maximize_sharpe_ratio \
  -c optimization_config.toml
```

### 示例代码

查看 `examples/` 目录获取更多示例：
- `05_strategy_backtest.zig` - 策略回测示例
- `06_strategy_optimize.zig` - 参数优化示例
- `07_custom_strategy.zig` - 自定义策略示例
```

**验收标准**:
- [ ] README 更新完整
- [ ] 快速开始指南清晰
- [ ] 代码示例正确
- [ ] 链接有效

---

## ✅ 验收标准

### 示例验收
- [ ] 所有示例代码可编译运行
- [ ] 示例注释清晰完整
- [ ] 示例展示核心功能
- [ ] 无内存泄漏

### 测试验收
- [ ] 集成测试覆盖核心流程
- [ ] 所有集成测试通过
- [ ] 性能测试达标
- [ ] 内存安全测试通过

### 文档验收
- [ ] 所有文档更新完成
- [ ] 文档内容准确完整
- [ ] 代码示例正确
- [ ] 格式统一美观
- [ ] 链接正确有效

### 整体验收
- [ ] v0.3.0 所有功能正常工作
- [ ] 新用户可通过文档快速上手
- [ ] 所有测试通过
- [ ] 无内存泄漏
- [ ] 性能指标达标

---

## 🔗 依赖关系

### 依赖项
- **Story 013-021**: 所有策略框架功能（必须完成）
- **Story 022**: 优化器（必须完成）
- **Story 023**: CLI 命令（必须完成）

### 被依赖项
- 无（这是最后一个 Story）

---

## 🧪 测试策略

### 示例测试
- 每个示例单独编译运行
- 验证输出正确性
- 内存泄漏检测
- 性能基准测试

### 集成测试
- 完整回测流程测试
- 参数优化流程测试
- 多策略对比测试
- 长时间运行稳定性测试

### 文档测试
- 文档代码示例可运行性
- 链接有效性检查
- 拼写和语法检查

---

## 📚 参考资料

### 示例参考
- [Freqtrade Examples](https://github.com/freqtrade/freqtrade/tree/develop/freqtrade/templates): 策略示例参考
- [Backtrader Samples](https://github.com/mementum/backtrader/tree/master/samples): 回测示例参考

### 文档参考
- [Freqtrade Documentation](https://www.freqtrade.io/): 文档结构参考
- [Rust Book](https://doc.rust-lang.org/book/): 教程写作风格参考

### 内部参考
- 所有 v0.3.0 设计文档和功能文档

---

## 📊 进度追踪

### 检查清单
- [ ] Task 1: 创建策略回测示例（3小时）
- [ ] Task 2: 创建参数优化示例（3小时）
- [ ] Task 3: 创建自定义策略示例（2小时）
- [ ] Task 4: 完善集成测试（4小时）
- [ ] Task 5: 更新功能文档（3小时）
- [ ] Task 6: 更新 README 和快速开始指南（2小时）

### 总计工作量
- **示例开发**: 8 小时
- **测试开发**: 4 小时
- **文档编写**: 5 小时
- **总计**: 17 小时（约 2 天）

---

## 🔄 后续改进

### v0.4.0 可能的增强
- [ ] 更多示例策略
- [ ] 视频教程
- [ ] 交互式教程
- [ ] 策略模板生成器
- [ ] 在线文档网站
- [ ] 社区策略分享平台

---

## 📝 备注

### 文档写作原则
- **清晰**: 用简单语言解释复杂概念
- **完整**: 覆盖所有关键功能和用例
- **准确**: 代码示例必须可运行
- **友好**: 对新手友好，提供渐进式学习路径

### 示例设计原则
- **独立性**: 每个示例可独立运行
- **渐进性**: 从简单到复杂
- **实用性**: 展示真实用例
- **注释**: 充分的代码注释

---

**创建时间**: 2025-12-25
**预计开始**: Week 3 Day 5
**预计完成**: Week 3 Day 6
**实际开始**:
**实际完成**:

---

Generated with [Claude Code](https://claude.com/claude-code)
