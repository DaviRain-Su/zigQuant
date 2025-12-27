//! SimulatedAccount - 模拟账户
//!
//! 用于 Paper Trading 的模拟账户，追踪余额、仓位和 PnL。
//! 提供完整的账户状态管理和统计分析功能。

const std = @import("std");
const Allocator = std.mem.Allocator;

const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const Side = @import("../exchange/types.zig").Side;

/// 仓位信息
pub const Position = struct {
    symbol: []const u8,
    quantity: Decimal,
    entry_price: Decimal,
    side: PositionSide,
    unrealized_pnl: Decimal,
    timestamp: Timestamp,

    pub const PositionSide = enum { long, short };

    /// 计算未实现盈亏
    pub fn updatePnl(self: *Position, current_price: Decimal) void {
        const price_diff = current_price.sub(self.entry_price);
        self.unrealized_pnl = switch (self.side) {
            .long => price_diff.mul(self.quantity),
            .short => price_diff.negate().mul(self.quantity),
        };
    }
};

/// 交易记录
pub const Trade = struct {
    symbol: []const u8,
    side: Side,
    entry_price: Decimal,
    exit_price: Decimal,
    quantity: Decimal,
    pnl: Decimal,
    commission: Decimal,
    timestamp: Timestamp,
};

/// 权益曲线点
pub const EquityPoint = struct {
    timestamp: Timestamp,
    equity: Decimal,
};

/// 订单成交信息
pub const OrderFill = struct {
    order_id: []const u8,
    symbol: []const u8,
    side: Side,
    fill_price: Decimal,
    fill_quantity: Decimal,
    commission: Decimal,
    timestamp: Timestamp,
};

/// 账户统计
pub const Stats = struct {
    current_balance: Decimal,
    total_pnl: Decimal,
    total_return_pct: f64,
    total_trades: usize,
    winning_trades: usize,
    losing_trades: usize,
    win_rate: f64,
    max_drawdown: f64,
    avg_win: Decimal,
    avg_loss: Decimal,
    profit_factor: f64,
    total_commission: Decimal,
};

/// 模拟账户
pub const SimulatedAccount = struct {
    allocator: Allocator,

    // 余额
    initial_balance: Decimal,
    current_balance: Decimal,
    available_balance: Decimal,

    // 仓位
    positions: std.StringHashMap(Position),

    // 交易历史
    trade_history: std.ArrayList(Trade),

    // 权益曲线
    equity_curve: std.ArrayList(EquityPoint),

    // 统计
    peak_equity: Decimal,
    max_drawdown: Decimal,
    total_commission: Decimal,

    const Self = @This();

    /// 初始化
    pub fn init(allocator: Allocator, initial_balance: Decimal) Self {
        return .{
            .allocator = allocator,
            .initial_balance = initial_balance,
            .current_balance = initial_balance,
            .available_balance = initial_balance,
            .positions = std.StringHashMap(Position).init(allocator),
            .trade_history = .{},
            .equity_curve = .{},
            .peak_equity = initial_balance,
            .max_drawdown = Decimal.ZERO,
            .total_commission = Decimal.ZERO,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        // 释放仓位 symbol 字符串
        var pos_iter = self.positions.iterator();
        while (pos_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.positions.deinit();

        // 释放交易历史 symbol 字符串
        for (self.trade_history.items) |trade| {
            self.allocator.free(trade.symbol);
        }
        self.trade_history.deinit(self.allocator);

        self.equity_curve.deinit(self.allocator);
    }

    /// 应用成交
    pub fn applyFill(self: *Self, fill: OrderFill) !void {
        const notional = fill.fill_price.mul(fill.fill_quantity);

        // 累计手续费
        self.total_commission = self.total_commission.add(fill.commission);

        if (fill.side == .buy) {
            // 买入: 扣除成本
            const total_cost = notional.add(fill.commission);
            self.available_balance = self.available_balance.sub(total_cost);

            // 更新或创建仓位
            if (self.positions.getPtr(fill.symbol)) |pos| {
                // 加仓: 计算新的平均入场价
                const old_cost = pos.entry_price.mul(pos.quantity);
                const new_qty = pos.quantity.add(fill.fill_quantity);
                const new_cost = old_cost.add(notional);
                pos.entry_price = new_cost.div(new_qty) catch pos.entry_price;
                pos.quantity = new_qty;
                pos.timestamp = fill.timestamp;
            } else {
                // 新仓位
                const symbol_copy = try self.allocator.dupe(u8, fill.symbol);
                try self.positions.put(symbol_copy, .{
                    .symbol = symbol_copy,
                    .quantity = fill.fill_quantity,
                    .entry_price = fill.fill_price,
                    .side = .long,
                    .unrealized_pnl = Decimal.ZERO,
                    .timestamp = fill.timestamp,
                });
            }
        } else {
            // 卖出
            if (self.positions.getPtr(fill.symbol)) |pos| {
                // 计算已实现盈亏
                const pnl = fill.fill_price.sub(pos.entry_price).mul(fill.fill_quantity);

                // 更新余额
                self.available_balance = self.available_balance.add(notional).sub(fill.commission);
                self.current_balance = self.current_balance.add(pnl).sub(fill.commission);

                // 记录交易
                const trade_symbol = try self.allocator.dupe(u8, fill.symbol);
                try self.trade_history.append(self.allocator, .{
                    .symbol = trade_symbol,
                    .side = fill.side,
                    .entry_price = pos.entry_price,
                    .exit_price = fill.fill_price,
                    .quantity = fill.fill_quantity,
                    .pnl = pnl,
                    .commission = fill.commission,
                    .timestamp = fill.timestamp,
                });

                // 更新仓位
                pos.quantity = pos.quantity.sub(fill.fill_quantity);
                if (pos.quantity.cmp(Decimal.ZERO) == .eq or pos.quantity.toFloat() < 0.00001) {
                    // 仓位已清空
                    if (self.positions.fetchRemove(fill.symbol)) |kv| {
                        self.allocator.free(kv.key);
                    }
                }
            } else {
                // 做空 (开空仓)
                const symbol_copy = try self.allocator.dupe(u8, fill.symbol);
                try self.positions.put(symbol_copy, .{
                    .symbol = symbol_copy,
                    .quantity = fill.fill_quantity,
                    .entry_price = fill.fill_price,
                    .side = .short,
                    .unrealized_pnl = Decimal.ZERO,
                    .timestamp = fill.timestamp,
                });

                // 卖空时只扣手续费
                self.available_balance = self.available_balance.sub(fill.commission);
            }
        }

        // 更新权益曲线
        try self.updateEquityCurve();
    }

    /// 更新权益曲线和回撤
    fn updateEquityCurve(self: *Self) !void {
        const equity = self.calculateTotalEquity();

        try self.equity_curve.append(self.allocator, .{
            .timestamp = Timestamp.now(),
            .equity = equity,
        });

        // 更新峰值和回撤
        if (equity.cmp(self.peak_equity) == .gt) {
            self.peak_equity = equity;
        } else if (self.peak_equity.toFloat() > 0) {
            const drawdown = self.peak_equity.sub(equity).div(self.peak_equity) catch Decimal.ZERO;
            if (drawdown.cmp(self.max_drawdown) == .gt) {
                self.max_drawdown = drawdown;
            }
        }
    }

    /// 计算总权益 (余额 + 未实现盈亏)
    pub fn calculateTotalEquity(self: *const Self) Decimal {
        var total_unrealized = Decimal.ZERO;
        var iter = self.positions.iterator();
        while (iter.next()) |entry| {
            total_unrealized = total_unrealized.add(entry.value_ptr.unrealized_pnl);
        }
        return self.current_balance.add(total_unrealized);
    }

    /// 更新仓位未实现盈亏
    pub fn updatePositionPnl(self: *Self, symbol: []const u8, current_price: Decimal) void {
        if (self.positions.getPtr(symbol)) |pos| {
            pos.updatePnl(current_price);
        }
    }

    /// 获取仓位
    pub fn getPosition(self: *const Self, symbol: []const u8) ?Position {
        return self.positions.get(symbol);
    }

    /// 检查是否有足够余额
    pub fn hasAvailableBalance(self: *const Self, amount: Decimal) bool {
        return self.available_balance.cmp(amount) != .lt;
    }

    /// 获取统计信息
    pub fn getStats(self: *const Self) Stats {
        const total_pnl = self.current_balance.sub(self.initial_balance);
        const total_trades = self.trade_history.items.len;

        // 统计盈亏交易
        var winning_trades: usize = 0;
        var losing_trades: usize = 0;
        var total_win = Decimal.ZERO;
        var total_loss = Decimal.ZERO;

        for (self.trade_history.items) |trade| {
            if (trade.pnl.toFloat() > 0) {
                winning_trades += 1;
                total_win = total_win.add(trade.pnl);
            } else if (trade.pnl.toFloat() < 0) {
                losing_trades += 1;
                total_loss = total_loss.add(trade.pnl.negate());
            }
        }

        const win_rate = if (total_trades > 0)
            @as(f64, @floatFromInt(winning_trades)) / @as(f64, @floatFromInt(total_trades))
        else
            0;

        const avg_win = if (winning_trades > 0)
            total_win.div(Decimal.fromInt(@intCast(winning_trades))) catch Decimal.ZERO
        else
            Decimal.ZERO;

        const avg_loss = if (losing_trades > 0)
            total_loss.div(Decimal.fromInt(@intCast(losing_trades))) catch Decimal.ZERO
        else
            Decimal.ZERO;

        const profit_factor = if (total_loss.toFloat() > 0)
            total_win.toFloat() / total_loss.toFloat()
        else if (total_win.toFloat() > 0)
            std.math.inf(f64)
        else
            0;

        const total_return_pct = if (self.initial_balance.toFloat() > 0)
            total_pnl.toFloat() / self.initial_balance.toFloat() * 100
        else
            0;

        return .{
            .current_balance = self.current_balance,
            .total_pnl = total_pnl,
            .total_return_pct = total_return_pct,
            .total_trades = total_trades,
            .winning_trades = winning_trades,
            .losing_trades = losing_trades,
            .win_rate = win_rate,
            .max_drawdown = self.max_drawdown.toFloat(),
            .avg_win = avg_win,
            .avg_loss = avg_loss,
            .profit_factor = profit_factor,
            .total_commission = self.total_commission,
        };
    }

    /// 重置账户
    pub fn reset(self: *Self) void {
        // 清空仓位
        var pos_iter = self.positions.iterator();
        while (pos_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.positions.clearRetainingCapacity();

        // 清空交易历史
        for (self.trade_history.items) |trade| {
            self.allocator.free(trade.symbol);
        }
        self.trade_history.clearRetainingCapacity();

        // 清空权益曲线
        self.equity_curve.clearRetainingCapacity();

        // 重置余额
        self.current_balance = self.initial_balance;
        self.available_balance = self.initial_balance;
        self.peak_equity = self.initial_balance;
        self.max_drawdown = Decimal.ZERO;
        self.total_commission = Decimal.ZERO;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "SimulatedAccount: init and deinit" {
    const allocator = std.testing.allocator;

    var account = SimulatedAccount.init(allocator, Decimal.fromInt(10000));
    defer account.deinit();

    try std.testing.expect(account.current_balance.eql(Decimal.fromInt(10000)));
    try std.testing.expect(account.available_balance.eql(Decimal.fromInt(10000)));
}

test "SimulatedAccount: apply buy fill" {
    const allocator = std.testing.allocator;

    var account = SimulatedAccount.init(allocator, Decimal.fromInt(10000));
    defer account.deinit();

    // 买入 1 ETH @ 2000, 手续费 1
    try account.applyFill(.{
        .order_id = "order-001",
        .symbol = "ETH",
        .side = .buy,
        .fill_price = Decimal.fromInt(2000),
        .fill_quantity = Decimal.fromInt(1),
        .commission = Decimal.fromInt(1),
        .timestamp = Timestamp.now(),
    });

    // 验证余额: 10000 - 2000 - 1 = 7999
    try std.testing.expectApproxEqAbs(@as(f64, 7999), account.available_balance.toFloat(), 0.01);

    // 验证仓位
    const pos = account.getPosition("ETH").?;
    try std.testing.expect(pos.quantity.eql(Decimal.fromInt(1)));
    try std.testing.expect(pos.entry_price.eql(Decimal.fromInt(2000)));
}

test "SimulatedAccount: apply sell fill with profit" {
    const allocator = std.testing.allocator;

    var account = SimulatedAccount.init(allocator, Decimal.fromInt(10000));
    defer account.deinit();

    // 买入 1 ETH @ 2000
    try account.applyFill(.{
        .order_id = "order-001",
        .symbol = "ETH",
        .side = .buy,
        .fill_price = Decimal.fromInt(2000),
        .fill_quantity = Decimal.fromInt(1),
        .commission = Decimal.fromInt(1),
        .timestamp = Timestamp.now(),
    });

    // 卖出 1 ETH @ 2100 (盈利 100)
    try account.applyFill(.{
        .order_id = "order-002",
        .symbol = "ETH",
        .side = .sell,
        .fill_price = Decimal.fromInt(2100),
        .fill_quantity = Decimal.fromInt(1),
        .commission = Decimal.fromInt(1),
        .timestamp = Timestamp.now(),
    });

    // 验证: 仓位已清空
    try std.testing.expect(account.getPosition("ETH") == null);

    // 验证: 交易历史
    try std.testing.expectEqual(@as(usize, 1), account.trade_history.items.len);

    const trade = account.trade_history.items[0];
    try std.testing.expectApproxEqAbs(@as(f64, 100), trade.pnl.toFloat(), 0.01);

    // 验证: 统计
    const stats = account.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.total_trades);
    try std.testing.expectEqual(@as(usize, 1), stats.winning_trades);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), stats.win_rate, 0.01);
}

test "SimulatedAccount: getStats" {
    const allocator = std.testing.allocator;

    var account = SimulatedAccount.init(allocator, Decimal.fromInt(10000));
    defer account.deinit();

    const stats = account.getStats();

    try std.testing.expect(stats.current_balance.eql(Decimal.fromInt(10000)));
    try std.testing.expectEqual(@as(usize, 0), stats.total_trades);
    try std.testing.expectApproxEqAbs(@as(f64, 0), stats.win_rate, 0.01);
}

test "SimulatedAccount: reset" {
    const allocator = std.testing.allocator;

    var account = SimulatedAccount.init(allocator, Decimal.fromInt(10000));
    defer account.deinit();

    // 买入
    try account.applyFill(.{
        .order_id = "order-001",
        .symbol = "ETH",
        .side = .buy,
        .fill_price = Decimal.fromInt(2000),
        .fill_quantity = Decimal.fromInt(1),
        .commission = Decimal.fromInt(1),
        .timestamp = Timestamp.now(),
    });

    // 重置
    account.reset();

    // 验证已重置
    try std.testing.expect(account.current_balance.eql(Decimal.fromInt(10000)));
    try std.testing.expect(account.getPosition("ETH") == null);
    try std.testing.expectEqual(@as(usize, 0), account.trade_history.items.len);
}
