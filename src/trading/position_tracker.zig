//! Position Tracker - 仓位追踪器
//!
//! 提供实时仓位追踪和账户管理：
//! - 多币种仓位管理
//! - 账户状态同步
//! - 成交事件处理
//! - 盈亏计算和追踪
//!
//! 设计特点：
//! - 基于 IExchange 接口（交易所无关）
//! - 线程安全（使用 Mutex）
//! - 回调机制（仓位更新、账户更新）

const std = @import("std");
const Position = @import("position.zig").Position;
const Account = @import("account.zig").Account;
const IExchange = @import("../exchange/interface.zig").IExchange;
const Logger = @import("../core/logger.zig").Logger;
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;

// ============================================================================
// Position Tracker
// ============================================================================

pub const PositionTracker = struct {
    allocator: std.mem.Allocator,
    exchange: IExchange,
    logger: Logger,

    // 仓位映射：coin -> Position
    positions: std.StringHashMap(*Position),

    // 账户信息
    account: Account,

    // 回调
    on_position_update: ?*const fn (*Position) void,
    on_account_update: ?*const fn (*Account) void,

    mutex: std.Thread.Mutex,

    /// 初始化仓位追踪器
    pub fn init(
        allocator: std.mem.Allocator,
        exchange: IExchange,
        logger: Logger,
    ) PositionTracker {
        return .{
            .allocator = allocator,
            .exchange = exchange,
            .logger = logger,
            .positions = std.StringHashMap(*Position).init(allocator),
            .account = Account.init(),
            .on_position_update = null,
            .on_account_update = null,
            .mutex = .{},
        };
    }

    /// 清理资源
    pub fn deinit(self: *PositionTracker) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 释放所有仓位
        var iter = self.positions.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.positions.deinit();
    }

    /// 同步账户状态（从交易所）
    ///
    /// 查询交易所获取最新的仓位和账户信息
    pub fn syncAccountState(self: *PositionTracker) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.logger.info("Syncing account state...", .{}) catch {};

        // 从交易所获取仓位列表
        const exchange_positions = self.exchange.getPositions() catch |err| {
            self.logger.err("Failed to get positions: {}", .{err}) catch {};
            return err;
        };
        defer self.allocator.free(exchange_positions);

        // 从交易所获取账户余额
        const balances = self.exchange.getBalance() catch |err| {
            self.logger.err("Failed to get balance: {}", .{err}) catch {};
            return err;
        };
        defer self.allocator.free(balances);

        // 更新账户总价值（从余额计算）
        var total_value = Decimal.ZERO;
        for (balances) |balance| {
            total_value = total_value.add(balance.total);
        }
        self.account.cross_margin_summary.account_value = total_value;

        // 更新仓位
        for (exchange_positions) |ex_pos| {
            const coin = ex_pos.pair.base;

            // 计算 szi（有符号仓位大小）
            const szi = if (ex_pos.side == .buy) ex_pos.size else ex_pos.size.negate();

            // 获取或创建仓位
            var position = try self.getOrCreatePosition(coin, szi);

            // 更新仓位数据
            position.szi = szi;
            position.side = ex_pos.side;
            position.entry_px = ex_pos.entry_price;
            position.mark_price = ex_pos.mark_price;
            position.liquidation_px = ex_pos.liquidation_price;
            position.unrealized_pnl = ex_pos.unrealized_pnl;
            position.margin_used = ex_pos.margin_used;
            position.leverage.value = ex_pos.leverage;

            // 计算仓位价值
            if (ex_pos.mark_price) |mp| {
                position.position_value = ex_pos.size.mul(mp);
            }

            position.updated_at = Timestamp.now();

            // 触发回调
            if (self.on_position_update) |callback| {
                callback(position);
            }
        }

        self.logger.info("Account state synced: Positions={d}, Value={}", .{
            self.positions.count(),
            total_value.toFloat(),
        }) catch {};

        // 触发账户更新回调
        if (self.on_account_update) |callback| {
            callback(&self.account);
        }
    }

    /// 更新标记价格（用于计算未实现盈亏）
    pub fn updateMarkPrice(
        self: *PositionTracker,
        coin: []const u8,
        mark_price: Decimal,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.positions.get(coin)) |position| {
            try position.updateMarkPrice(mark_price);

            self.logger.info("Mark price updated: {s} @ {}", .{
                coin,
                mark_price.toFloat(),
            }) catch {};

            if (self.on_position_update) |callback| {
                callback(position);
            }
        }
    }

    /// 处理订单成交事件（更新仓位）
    ///
    /// 根据成交方向和数量更新仓位
    pub fn handleOrderFill(
        self: *PositionTracker,
        coin: []const u8,
        side: @import("../exchange/types.zig").Side,
        quantity: Decimal,
        price: Decimal,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 计算成交后的 szi 变化
        const current_pos = self.positions.get(coin);
        const current_szi = if (current_pos) |p| p.szi else Decimal.ZERO;

        // 计算新的 szi
        var new_szi: Decimal = undefined;
        const is_opening = blk: {
            if (current_szi.isZero()) {
                // 没有仓位，任何成交都是开仓
                break :blk true;
            }
            // 检查是否与当前方向相同
            const current_is_long = current_szi.cmp(Decimal.ZERO) == .gt;
            const fill_is_buy = side == .buy;
            break :blk current_is_long == fill_is_buy;
        };

        if (is_opening) {
            // 开仓或加仓
            if (side == .buy) {
                new_szi = current_szi.add(quantity);
            } else {
                new_szi = current_szi.sub(quantity);
            }

            // 获取或创建仓位
            var position = try self.getOrCreatePosition(coin, new_szi);
            try position.increase(quantity, price);

            self.logger.info("Position increased: {s} {s} {} @ {} (new szi: {})", .{
                coin,
                @tagName(side),
                quantity.toFloat(),
                price.toFloat(),
                new_szi.toFloat(),
            }) catch {};

            if (self.on_position_update) |callback| {
                callback(position);
            }
        } else {
            // 减仓或平仓
            if (current_pos) |position| {
                const close_pnl = try position.decrease(quantity, price);
                self.account.total_realized_pnl = self.account.total_realized_pnl.add(close_pnl);

                self.logger.info("Position decreased: {s} {s} {} @ {} (PnL: {}, remaining: {})", .{
                    coin,
                    @tagName(side),
                    quantity.toFloat(),
                    price.toFloat(),
                    close_pnl.toFloat(),
                    position.szi.toFloat(),
                }) catch {};

                // 如果完全平仓，移除仓位
                if (position.isEmpty()) {
                    const key = try self.allocator.dupe(u8, coin);
                    if (self.positions.fetchRemove(key)) |kv| {
                        self.allocator.free(kv.key);
                        kv.value.deinit();
                        self.allocator.destroy(kv.value);
                    }
                    self.allocator.free(key);

                    self.logger.info("Position closed: {s}", .{coin}) catch {};
                } else {
                    if (self.on_position_update) |callback| {
                        callback(position);
                    }
                }

                if (self.on_account_update) |callback| {
                    callback(&self.account);
                }
            }
        }
    }

    /// 获取所有仓位
    ///
    /// 返回的切片需要调用者释放
    pub fn getAllPositions(self: *PositionTracker) ![]const *Position {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list = try std.ArrayList(*Position).initCapacity(self.allocator, self.positions.count());
        errdefer list.deinit(self.allocator);

        var iter = self.positions.valueIterator();
        while (iter.next()) |pos| {
            try list.append(self.allocator, pos.*);
        }

        return try list.toOwnedSlice(self.allocator);
    }

    /// 获取单个仓位
    pub fn getPosition(self: *PositionTracker, coin: []const u8) ?*Position {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.positions.get(coin);
    }

    /// 获取账户信息
    pub fn getAccount(self: *PositionTracker) Account {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.account;
    }

    /// 获取统计信息
    pub fn getStats(self: *PositionTracker) Stats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var total_unrealized_pnl = Decimal.ZERO;
        var iter = self.positions.valueIterator();
        while (iter.next()) |pos| {
            total_unrealized_pnl = total_unrealized_pnl.add(pos.*.unrealized_pnl);
        }

        return .{
            .position_count = self.positions.count(),
            .account_value = self.account.cross_margin_summary.account_value,
            .total_realized_pnl = self.account.total_realized_pnl,
            .total_unrealized_pnl = total_unrealized_pnl,
        };
    }

    pub const Stats = struct {
        position_count: usize,
        account_value: Decimal,
        total_realized_pnl: Decimal,
        total_unrealized_pnl: Decimal,
    };

    // 内部辅助函数
    fn getOrCreatePosition(
        self: *PositionTracker,
        coin: []const u8,
        szi: Decimal,
    ) !*Position {
        if (self.positions.get(coin)) |pos| {
            return pos;
        }

        const pos = try self.allocator.create(Position);
        errdefer self.allocator.destroy(pos);

        pos.* = try Position.init(self.allocator, coin, szi);

        const key = try self.allocator.dupe(u8, coin);
        errdefer self.allocator.free(key);

        try self.positions.put(key, pos);

        return pos;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "PositionTracker: init and deinit" {
    const allocator = std.testing.allocator;

    // Create mock exchange
    const MockExchange = struct {
        fn getName(_: *anyopaque) []const u8 {
            return "mock";
        }
        fn connect(_: *anyopaque) anyerror!void {}
        fn disconnect(_: *anyopaque) void {}
        fn isConnected(_: *anyopaque) bool {
            return true;
        }
        fn getTicker(_: *anyopaque, _: @import("../exchange/types.zig").TradingPair) anyerror!@import("../exchange/types.zig").Ticker {
            return error.NotImplemented;
        }
        fn getOrderbook(_: *anyopaque, _: @import("../exchange/types.zig").TradingPair, _: u32) anyerror!@import("../exchange/types.zig").Orderbook {
            return error.NotImplemented;
        }
        fn createOrder(_: *anyopaque, _: @import("../exchange/types.zig").OrderRequest) anyerror!@import("../exchange/types.zig").Order {
            return error.NotImplemented;
        }
        fn cancelOrder(_: *anyopaque, _: u64) anyerror!void {}
        fn cancelAllOrders(_: *anyopaque, _: ?@import("../exchange/types.zig").TradingPair) anyerror!u32 {
            return 0;
        }
        fn getOrder(_: *anyopaque, _: u64) anyerror!@import("../exchange/types.zig").Order {
            return error.NotImplemented;
        }
        fn getBalance(_: *anyopaque) anyerror![]@import("../exchange/types.zig").Balance {
            return error.NotImplemented;
        }
        fn getOpenOrders(_: *anyopaque, _: ?@import("../exchange/types.zig").TradingPair) anyerror![]@import("../exchange/types.zig").Order {
            return error.NotImplemented;
        }
        fn getPositions(_: *anyopaque) anyerror![]@import("../exchange/types.zig").Position {
            return error.NotImplemented;
        }

        const vtable = IExchange.VTable{
            .getName = getName,
            .connect = connect,
            .disconnect = disconnect,
            .isConnected = isConnected,
            .getTicker = getTicker,
            .getOrderbook = getOrderbook,
            .createOrder = createOrder,
            .cancelOrder = cancelOrder,
            .cancelAllOrders = cancelAllOrders,
            .getOrder = getOrder,
            .getOpenOrders = getOpenOrders,
            .getBalance = getBalance,
            .getPositions = getPositions,
        };
    };

    const MockState = struct {};
    var mock = MockState{};
    const exchange = IExchange{
        .ptr = &mock,
        .vtable = &MockExchange.vtable,
    };

    // Create logger
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../core/logger.zig").LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const log_writer = @import("../core/logger.zig").LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    const logger = Logger.init(allocator, log_writer, .info);

    var tracker = PositionTracker.init(allocator, exchange, logger);
    defer tracker.deinit();

    const stats = tracker.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.position_count);
}
