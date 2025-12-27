//! 批量订单模拟模块
//!
//! 根据交易信号批量模拟订单执行，计算交易结果。

const std = @import("std");
const Allocator = std.mem.Allocator;

const signal_generator = @import("signal_generator.zig");
const Signal = signal_generator.Signal;
const SignalDirection = signal_generator.SignalDirection;
const data_loader = @import("data_loader.zig");
const DataSet = data_loader.DataSet;

/// 交易方向
pub const TradeSide = enum {
    buy,
    sell,
};

/// 交易记录
pub const Trade = struct {
    entry_index: usize,
    exit_index: usize,
    entry_time: i64,
    exit_time: i64,
    entry_price: f64,
    exit_price: f64,
    side: TradeSide,
    size: f64,
    pnl: f64,
    pnl_pct: f64,
    commission: f64,

    pub fn format(
        self: Trade,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("Trade{{ entry={d}, exit={d}, pnl={d:.2}% }}", .{
            self.entry_index,
            self.exit_index,
            self.pnl_pct * 100,
        });
    }
};

/// 权益快照
pub const EquitySnapshot = struct {
    timestamp: i64,
    equity: f64,
    drawdown: f64,
    drawdown_pct: f64,
};

/// 模拟结果
pub const SimulationResult = struct {
    allocator: Allocator,

    /// 交易列表
    trades: []Trade,

    /// 权益曲线
    equity_curve: []EquitySnapshot,

    /// 最终资本
    final_capital: f64,

    /// 初始资本
    initial_capital: f64,

    /// 总收益
    total_return: f64,

    /// 总收益率
    total_return_pct: f64,

    /// 最大回撤
    max_drawdown: f64,

    /// 最大回撤百分比
    max_drawdown_pct: f64,

    /// 胜率
    win_rate: f64,

    /// 盈亏比
    profit_factor: f64,

    /// 交易次数
    trade_count: usize,

    /// 获胜次数
    win_count: usize,

    /// 失败次数
    loss_count: usize,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.trades);
        self.allocator.free(self.equity_curve);
    }
};

/// 批量订单模拟器
pub const BatchOrderSimulator = struct {
    allocator: Allocator,
    config: Config,

    pub const Config = struct {
        initial_capital: f64 = 100000.0,
        commission_rate: f64 = 0.001, // 0.1%
        slippage: f64 = 0.0005, // 0.05%
        position_size_pct: f64 = 1.0, // 使用 100% 资金
        allow_short: bool = false, // 是否允许做空
    };

    const Self = @This();

    pub fn init(allocator: Allocator, config: Config) Self {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// 批量模拟订单执行
    pub fn simulate(
        self: *Self,
        dataset: *const DataSet,
        signals: []const Signal,
    ) !SimulationResult {
        std.debug.assert(dataset.len == signals.len);

        var trades = try std.ArrayList(Trade).initCapacity(self.allocator, 100);
        defer trades.deinit(self.allocator);

        var equity_snapshots = try std.ArrayList(EquitySnapshot).initCapacity(self.allocator, dataset.len / 10 + 1);
        defer equity_snapshots.deinit(self.allocator);

        var capital = self.config.initial_capital;
        var position: f64 = 0;
        var entry_price: f64 = 0;
        var entry_index: usize = 0;
        var entry_time: i64 = 0;
        var peak_equity = capital;
        var max_drawdown: f64 = 0;
        var max_drawdown_pct: f64 = 0;

        for (0..dataset.len) |i| {
            const sig = signals[i];
            const close = dataset.closes[i];
            const timestamp = dataset.timestamps[i];

            // 根据信号处理仓位
            if (sig.direction == .long and position == 0) {
                // 开多仓
                const exec_price = close * (1 + self.config.slippage);
                const commission = capital * self.config.commission_rate;
                const available = (capital - commission) * self.config.position_size_pct;
                position = available / exec_price;
                capital = capital - available - commission;
                entry_price = exec_price;
                entry_index = i;
                entry_time = timestamp;
            } else if (sig.direction == .short and position > 0) {
                // 平多仓
                const exec_price = close * (1 - self.config.slippage);
                const proceeds = position * exec_price;
                const commission = proceeds * self.config.commission_rate;
                capital = capital + proceeds - commission;

                const pnl = (exec_price - entry_price) * position - commission;
                const pnl_pct = (exec_price - entry_price) / entry_price;

                try trades.append(self.allocator, .{
                    .entry_index = entry_index,
                    .exit_index = i,
                    .entry_time = entry_time,
                    .exit_time = timestamp,
                    .entry_price = entry_price,
                    .exit_price = exec_price,
                    .side = .buy,
                    .size = position,
                    .pnl = pnl,
                    .pnl_pct = pnl_pct,
                    .commission = commission,
                });

                position = 0;
            }

            // 计算当前权益
            const current_equity = capital + position * close;

            // 更新峰值和回撤
            if (current_equity > peak_equity) {
                peak_equity = current_equity;
            }
            const drawdown = peak_equity - current_equity;
            const drawdown_pct = if (peak_equity > 0) drawdown / peak_equity else 0;

            if (drawdown_pct > max_drawdown_pct) {
                max_drawdown = drawdown;
                max_drawdown_pct = drawdown_pct;
            }

            // 记录权益快照 (每 N 个 bar 记录一次以节省内存)
            if (i % 10 == 0 or i == dataset.len - 1) {
                try equity_snapshots.append(self.allocator, .{
                    .timestamp = timestamp,
                    .equity = current_equity,
                    .drawdown = drawdown,
                    .drawdown_pct = drawdown_pct,
                });
            }
        }

        // 如果仍有持仓，按最后价格平仓
        if (position > 0) {
            const last_close = dataset.closes[dataset.len - 1];
            const exec_price = last_close * (1 - self.config.slippage);
            const proceeds = position * exec_price;
            const commission = proceeds * self.config.commission_rate;
            capital = capital + proceeds - commission;

            const pnl = (exec_price - entry_price) * position - commission;
            const pnl_pct = (exec_price - entry_price) / entry_price;

            try trades.append(self.allocator, .{
                .entry_index = entry_index,
                .exit_index = dataset.len - 1,
                .entry_time = entry_time,
                .exit_time = dataset.timestamps[dataset.len - 1],
                .entry_price = entry_price,
                .exit_price = exec_price,
                .side = .buy,
                .size = position,
                .pnl = pnl,
                .pnl_pct = pnl_pct,
                .commission = commission,
            });
        }

        // 计算统计指标
        const trade_count = trades.items.len;
        var win_count: usize = 0;
        var total_profit: f64 = 0;
        var total_loss: f64 = 0;

        for (trades.items) |trade| {
            if (trade.pnl > 0) {
                win_count += 1;
                total_profit += trade.pnl;
            } else {
                total_loss += @abs(trade.pnl);
            }
        }

        const win_rate = if (trade_count > 0)
            @as(f64, @floatFromInt(win_count)) / @as(f64, @floatFromInt(trade_count))
        else
            0;

        const profit_factor = if (total_loss > 0)
            total_profit / total_loss
        else if (total_profit > 0)
            std.math.inf(f64)
        else
            0;

        const total_return = capital - self.config.initial_capital;
        const total_return_pct = total_return / self.config.initial_capital;

        return .{
            .allocator = self.allocator,
            .trades = try trades.toOwnedSlice(self.allocator),
            .equity_curve = try equity_snapshots.toOwnedSlice(self.allocator),
            .final_capital = capital,
            .initial_capital = self.config.initial_capital,
            .total_return = total_return,
            .total_return_pct = total_return_pct,
            .max_drawdown = max_drawdown,
            .max_drawdown_pct = max_drawdown_pct,
            .win_rate = win_rate,
            .profit_factor = profit_factor,
            .trade_count = trade_count,
            .win_count = win_count,
            .loss_count = trade_count - win_count,
        };
    }

    /// 批量模拟多个信号组合 (用于参数优化)
    pub fn simulateBatch(
        self: *Self,
        dataset: *const DataSet,
        signal_sets: []const []const Signal,
        results: []SimulationResult,
    ) !void {
        std.debug.assert(signal_sets.len == results.len);

        for (signal_sets, 0..) |signals, i| {
            results[i] = try self.simulate(dataset, signals);
        }
    }
};

/// 性能分析器
pub const PerformanceAnalyzer = struct {
    /// 计算夏普比率
    pub fn calculateSharpeRatio(
        returns: []const f64,
        risk_free_rate: f64,
        periods_per_year: f64,
    ) f64 {
        if (returns.len == 0) return 0;

        // 计算平均收益
        var sum: f64 = 0;
        for (returns) |r| {
            sum += r;
        }
        const avg_return = sum / @as(f64, @floatFromInt(returns.len));

        // 计算标准差
        var sum_sq: f64 = 0;
        for (returns) |r| {
            const diff = r - avg_return;
            sum_sq += diff * diff;
        }
        const std_dev = @sqrt(sum_sq / @as(f64, @floatFromInt(returns.len)));

        if (std_dev == 0) return 0;

        // 年化
        const annualized_return = avg_return * periods_per_year;
        const annualized_std = std_dev * @sqrt(periods_per_year);

        return (annualized_return - risk_free_rate) / annualized_std;
    }

    /// 计算最大回撤
    pub fn calculateMaxDrawdown(equity: []const f64) struct { max_dd: f64, max_dd_pct: f64 } {
        if (equity.len == 0) return .{ .max_dd = 0, .max_dd_pct = 0 };

        var peak = equity[0];
        var max_dd: f64 = 0;
        var max_dd_pct: f64 = 0;

        for (equity) |e| {
            if (e > peak) {
                peak = e;
            }
            const dd = peak - e;
            const dd_pct = if (peak > 0) dd / peak else 0;

            if (dd_pct > max_dd_pct) {
                max_dd = dd;
                max_dd_pct = dd_pct;
            }
        }

        return .{ .max_dd = max_dd, .max_dd_pct = max_dd_pct };
    }

    /// 计算收益率序列 (从权益曲线)
    pub fn calculateReturns(allocator: Allocator, equity: []const f64) ![]f64 {
        if (equity.len < 2) {
            return try allocator.alloc(f64, 0);
        }

        const returns = try allocator.alloc(f64, equity.len - 1);

        for (0..equity.len - 1) |i| {
            returns[i] = if (equity[i] != 0)
                (equity[i + 1] - equity[i]) / equity[i]
            else
                0;
        }

        return returns;
    }

    /// 计算索提诺比率
    pub fn calculateSortinoRatio(
        returns: []const f64,
        risk_free_rate: f64,
        periods_per_year: f64,
    ) f64 {
        if (returns.len == 0) return 0;

        // 计算平均收益
        var sum: f64 = 0;
        for (returns) |r| {
            sum += r;
        }
        const avg_return = sum / @as(f64, @floatFromInt(returns.len));

        // 计算下行标准差 (只考虑负收益)
        var sum_sq: f64 = 0;
        var count: usize = 0;
        for (returns) |r| {
            if (r < 0) {
                sum_sq += r * r;
                count += 1;
            }
        }

        if (count == 0) {
            return if (avg_return > 0) std.math.inf(f64) else 0;
        }

        const downside_std = @sqrt(sum_sq / @as(f64, @floatFromInt(count)));

        if (downside_std == 0) return 0;

        // 年化
        const annualized_return = avg_return * periods_per_year;
        const annualized_downside = downside_std * @sqrt(periods_per_year);

        return (annualized_return - risk_free_rate) / annualized_downside;
    }
};

// ============================================================================
// 单元测试
// ============================================================================

test "BatchOrderSimulator basic simulation" {
    const allocator = std.testing.allocator;

    // 创建测试数据
    var loader = data_loader.MmapDataLoader.init(allocator, false);
    const timestamps = [_]i64{ 1000, 1060, 1120, 1180, 1240 };
    const opens = [_]f64{ 100.0, 101.0, 102.0, 103.0, 104.0 };
    const highs = [_]f64{ 105.0, 106.0, 107.0, 108.0, 109.0 };
    const lows = [_]f64{ 98.0, 99.0, 100.0, 101.0, 102.0 };
    const closes = [_]f64{ 102.0, 104.0, 106.0, 105.0, 108.0 };
    const volumes = [_]f64{ 1000.0, 1100.0, 1200.0, 1100.0, 1300.0 };

    var dataset = try loader.fromArrays(&timestamps, &opens, &highs, &lows, &closes, &volumes);
    defer dataset.deinit();

    // 创建信号: 买入 -> 持有 -> 持有 -> 卖出 -> 持有
    const signals = [_]Signal{
        .{ .direction = .long, .strength = 1.0, .timestamp = 1000 },
        .{ .direction = .neutral, .strength = 0.0, .timestamp = 1060 },
        .{ .direction = .neutral, .strength = 0.0, .timestamp = 1120 },
        .{ .direction = .short, .strength = 1.0, .timestamp = 1180 },
        .{ .direction = .neutral, .strength = 0.0, .timestamp = 1240 },
    };

    var simulator = BatchOrderSimulator.init(allocator, .{
        .initial_capital = 10000.0,
        .commission_rate = 0.001,
        .slippage = 0.0,
    });

    var result = try simulator.simulate(&dataset, &signals);
    defer result.deinit();

    // 验证结果
    try std.testing.expectEqual(@as(usize, 1), result.trade_count);
    try std.testing.expect(result.trades[0].pnl > 0); // 从 102 买入, 105 卖出应该盈利
}

test "PerformanceAnalyzer Sharpe ratio" {
    const returns = [_]f64{ 0.01, -0.005, 0.02, 0.015, -0.01, 0.025 };

    const sharpe = PerformanceAnalyzer.calculateSharpeRatio(&returns, 0.02, 252);

    // Sharpe 应该是正数 (正收益)
    try std.testing.expect(sharpe > 0);
}

test "PerformanceAnalyzer max drawdown" {
    const equity = [_]f64{ 100, 105, 110, 100, 95, 108, 115 };

    const result = PerformanceAnalyzer.calculateMaxDrawdown(&equity);

    // 最大回撤应该是从 110 到 95
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), result.max_dd, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 15.0 / 110.0), result.max_dd_pct, 0.001);
}
