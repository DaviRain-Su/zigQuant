//! Cross-Exchange Arbitrage 跨交易所套利
//!
//! 实现跨交易所套利策略，监测不同交易所之间的价格差异，
//! 在有利可图时执行同时买卖操作获取无风险利润。
//!
//! ## Story 037: Cross-Exchange Arbitrage
//!
//! 套利原理:
//! - 在价格较低的交易所买入
//! - 在价格较高的交易所卖出
//! - 利润 = 卖出价 - 买入价 - 手续费
//!
//! ## 使用示例
//!
//! ```zig
//! const arb = @import("market_making").arbitrage;
//!
//! var strategy = arb.CrossExchangeArbitrage.init(allocator, .{
//!     .symbol = "ETH/USDT",
//!     .min_profit_bps = 10,
//!     .trade_amount = Decimal.fromFloat(0.1),
//! });
//!
//! // 检测套利机会
//! const opp = strategy.detectOpportunity(quote_a, quote_b);
//! if (opp) |opportunity| {
//!     try strategy.executeArbitrage(opportunity);
//! }
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;
const IClockStrategy = @import("interfaces.zig").IClockStrategy;

// ============================================================================
// 套利方向
// ============================================================================

/// 套利方向
pub const Direction = enum {
    /// 在 A 买入，在 B 卖出
    a_to_b,
    /// 在 B 买入，在 A 卖出
    b_to_a,

    pub fn format(
        self: Direction,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .a_to_b => try writer.writeAll("A→B"),
            .b_to_a => try writer.writeAll("B→A"),
        }
    }
};

// ============================================================================
// 报价结构
// ============================================================================

/// 交易所报价
pub const Quote = struct {
    /// 买一价 (最高买价)
    bid: Decimal,
    /// 卖一价 (最低卖价)
    ask: Decimal,
    /// 买一量
    bid_size: Decimal,
    /// 卖一量
    ask_size: Decimal,
    /// 时间戳
    timestamp: i64,

    /// 计算中间价
    pub fn midPrice(self: Quote) !Decimal {
        return try self.bid.add(self.ask).div(Decimal.fromInt(2));
    }

    /// 计算价差 (bps)
    pub fn spreadBps(self: Quote) u32 {
        if (self.bid.isZero()) return 0;
        const spread = self.ask.sub(self.bid);
        const div_result = spread.div(self.bid) catch return 0;
        const bps_float = div_result.mul(Decimal.fromInt(10000)).toFloat();
        return @intFromFloat(@max(0, bps_float));
    }
};

// ============================================================================
// 套利配置
// ============================================================================

/// 套利配置
pub const ArbitrageConfig = struct {
    /// 交易对
    symbol: []const u8 = "ETH/USDT",

    /// 最小利润阈值 (basis points)
    /// 扣除费用后的净利润
    min_profit_bps: u32 = 10, // 0.1%

    /// 交易数量
    trade_amount: Decimal = Decimal.fromFloat(0.1),

    /// 最大滑点容忍度 (bps)
    max_slippage_bps: u32 = 5,

    /// 交易所 A 费率 (bps)
    fee_bps_a: u32 = 10, // 0.1%

    /// 交易所 B 费率 (bps)
    fee_bps_b: u32 = 10, // 0.1%

    /// 最大单边仓位
    max_position: Decimal = Decimal.fromFloat(1.0),

    /// 订单超时 (ms)
    order_timeout_ms: u32 = 5000,

    /// 冷却时间 (ms) - 执行套利后等待
    cooldown_ms: u32 = 1000,

    /// 交易所 A 名称
    exchange_a_name: []const u8 = "ExchangeA",

    /// 交易所 B 名称
    exchange_b_name: []const u8 = "ExchangeB",
};

// ============================================================================
// 套利机会
// ============================================================================

/// 利润计算结果
pub const ProfitCalc = struct {
    /// 毛利润 (bps)
    gross_profit_bps: u32,
    /// 总费用 (bps)
    fee_bps: u32,
    /// 净利润 (bps)
    net_profit_bps: i32,
};

/// 套利机会
pub const ArbitrageOpportunity = struct {
    /// 套利方向
    direction: Direction,
    /// 买入价格
    buy_price: Decimal,
    /// 卖出价格
    sell_price: Decimal,
    /// 可用数量 (取两边最小值)
    available_amount: Decimal,
    /// 交易数量
    trade_amount: Decimal,
    /// 毛利润 (bps)
    gross_profit_bps: u32,
    /// 费用 (bps)
    fee_bps: u32,
    /// 净利润 (bps)
    net_profit_bps: i32,
    /// 预期利润金额
    expected_profit: Decimal,
    /// 检测时间戳
    timestamp: i64,
};

// ============================================================================
// 成交结果
// ============================================================================

/// 订单成交结果
pub const FillResult = struct {
    /// 是否成交
    filled: bool,
    /// 成交价格
    fill_price: Decimal,
    /// 成交数量
    fill_amount: Decimal,
    /// 手续费
    fee: Decimal,
};

/// 套利执行结果
pub const ArbitrageResult = struct {
    /// 是否成功
    success: bool,
    /// 买入成交
    buy_fill: FillResult,
    /// 卖出成交
    sell_fill: FillResult,
    /// 实际利润
    actual_profit: Decimal,
    /// 执行时间 (ms)
    execution_time_ms: u64,
};

// ============================================================================
// 套利统计
// ============================================================================

/// 套利策略统计
pub const ArbStats = struct {
    /// 检测到的机会数
    opportunities_detected: u32,
    /// 已执行的机会数
    opportunities_executed: u32,
    /// 错过的机会数
    opportunities_missed: u32,
    /// 失败的执行数
    opportunities_failed: u32,
    /// 交易次数
    trade_count: u32,
    /// 总利润
    total_profit: Decimal,
    /// 总手续费
    total_fees: Decimal,
    /// 交易所 A 仓位
    position_a: Decimal,
    /// 交易所 B 仓位
    position_b: Decimal,
    /// 成功率
    success_rate: f64,
    /// 平均利润 (bps)
    avg_profit_bps: f64,

    pub fn init() ArbStats {
        return .{
            .opportunities_detected = 0,
            .opportunities_executed = 0,
            .opportunities_missed = 0,
            .opportunities_failed = 0,
            .trade_count = 0,
            .total_profit = Decimal.ZERO,
            .total_fees = Decimal.ZERO,
            .position_a = Decimal.ZERO,
            .position_b = Decimal.ZERO,
            .success_rate = 0,
            .avg_profit_bps = 0,
        };
    }
};

// ============================================================================
// 跨交易所套利策略
// ============================================================================

/// 跨交易所套利策略
pub const CrossExchangeArbitrage = struct {
    allocator: Allocator,
    config: ArbitrageConfig,

    // 当前报价
    quote_a: ?Quote,
    quote_b: ?Quote,

    // 状态
    position_a: Decimal,
    position_b: Decimal,
    total_profit: Decimal,
    total_fees: Decimal,
    trade_count: u32,
    last_trade_time: i64,

    // 统计
    opportunities_detected: u32,
    opportunities_executed: u32,
    opportunities_missed: u32,
    opportunities_failed: u32,

    // 累计利润 (用于计算平均)
    cumulative_profit_bps: i64,

    const Self = @This();

    /// 初始化套利策略
    pub fn init(allocator: Allocator, config: ArbitrageConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .quote_a = null,
            .quote_b = null,
            .position_a = Decimal.ZERO,
            .position_b = Decimal.ZERO,
            .total_profit = Decimal.ZERO,
            .total_fees = Decimal.ZERO,
            .trade_count = 0,
            .last_trade_time = 0,
            .opportunities_detected = 0,
            .opportunities_executed = 0,
            .opportunities_missed = 0,
            .opportunities_failed = 0,
            .cumulative_profit_bps = 0,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        _ = self;
        // 无需清理
    }

    // ========================================================================
    // IClockStrategy 实现
    // ========================================================================

    const vtable = IClockStrategy.VTable{
        .onTick = onTickImpl,
        .onStart = onStartImpl,
        .onStop = onStopImpl,
    };

    /// 转换为 IClockStrategy 接口
    pub fn asClockStrategy(self: *Self) IClockStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn onTickImpl(ptr: *anyopaque, tick: u64, timestamp_ns: i128) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = tick;

        const now_ms: i64 = @intCast(@divFloor(timestamp_ns, 1_000_000));

        // 检查冷却时间
        if (now_ms - self.last_trade_time < self.config.cooldown_ms) {
            return;
        }

        // 需要两个交易所的报价
        const quote_a = self.quote_a orelse return;
        const quote_b = self.quote_b orelse return;

        // 检测套利机会
        const opportunity = self.detectOpportunity(quote_a, quote_b) orelse return;

        self.opportunities_detected += 1;

        // 验证净利润
        if (opportunity.net_profit_bps < @as(i32, @intCast(self.config.min_profit_bps))) {
            return;
        }

        // 检查仓位限制
        if (!self.canExecute(opportunity)) {
            self.opportunities_missed += 1;
            return;
        }

        // 执行套利 (模拟)
        const result = self.executeArbitrageSimulated(opportunity);

        if (result.success) {
            self.opportunities_executed += 1;
            self.last_trade_time = now_ms;
            self.trade_count += 1;
            self.total_profit = self.total_profit.add(result.actual_profit);
            self.total_fees = self.total_fees.add(result.buy_fill.fee).add(result.sell_fill.fee);
            self.cumulative_profit_bps += opportunity.net_profit_bps;

            // 更新仓位
            switch (opportunity.direction) {
                .a_to_b => {
                    self.position_a = self.position_a.add(opportunity.trade_amount);
                    self.position_b = self.position_b.sub(opportunity.trade_amount);
                },
                .b_to_a => {
                    self.position_b = self.position_b.add(opportunity.trade_amount);
                    self.position_a = self.position_a.sub(opportunity.trade_amount);
                },
            }
        } else {
            self.opportunities_failed += 1;
        }
    }

    fn onStartImpl(ptr: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        std.log.info("[Arb] Starting arbitrage for {s} between {s} and {s}", .{
            self.config.symbol,
            self.config.exchange_a_name,
            self.config.exchange_b_name,
        });
    }

    fn onStopImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const stats = self.getStats();
        std.log.info("[Arb] Stopped. Detected={}, Executed={}, Profit={d:.4}", .{
            stats.opportunities_detected,
            stats.opportunities_executed,
            stats.total_profit.toFloat(),
        });
    }

    // ========================================================================
    // 报价更新
    // ========================================================================

    /// 更新交易所 A 报价
    pub fn updateQuoteA(self: *Self, quote: Quote) void {
        self.quote_a = quote;
    }

    /// 更新交易所 B 报价
    pub fn updateQuoteB(self: *Self, quote: Quote) void {
        self.quote_b = quote;
    }

    // ========================================================================
    // 机会检测
    // ========================================================================

    /// 计算利润 (bps)
    pub fn calculateProfit(
        self: *Self,
        buy_price: Decimal,
        sell_price: Decimal,
        direction: Direction,
    ) ProfitCalc {
        // 毛利润 = (卖价 - 买价) / 买价 * 10000 bps
        if (buy_price.isZero()) {
            return .{ .gross_profit_bps = 0, .fee_bps = 0, .net_profit_bps = 0 };
        }

        const spread = sell_price.sub(buy_price);
        const div_result = spread.div(buy_price) catch return .{ .gross_profit_bps = 0, .fee_bps = 0, .net_profit_bps = 0 };
        const gross_bps_float = div_result.mul(Decimal.fromInt(10000)).toFloat();
        const gross_bps: u32 = if (gross_bps_float > 0) @intFromFloat(gross_bps_float) else 0;

        // 总费用 = 买入费用 + 卖出费用
        const fee_bps: u32 = switch (direction) {
            .a_to_b => self.config.fee_bps_a + self.config.fee_bps_b,
            .b_to_a => self.config.fee_bps_b + self.config.fee_bps_a,
        };

        // 净利润
        const net_bps: i32 = @as(i32, @intCast(gross_bps)) - @as(i32, @intCast(fee_bps));

        return .{
            .gross_profit_bps = gross_bps,
            .fee_bps = fee_bps,
            .net_profit_bps = net_bps,
        };
    }

    /// 检测套利机会
    pub fn detectOpportunity(self: *Self, quote_a: Quote, quote_b: Quote) ?ArbitrageOpportunity {
        // 机会 1: 在 A 买入 (A 的 ask), 在 B 卖出 (B 的 bid)
        // A.ask < B.bid 时有利可图
        const profit_a_to_b = self.calculateProfit(quote_a.ask, quote_b.bid, .a_to_b);

        // 机会 2: 在 B 买入 (B 的 ask), 在 A 卖出 (A 的 bid)
        // B.ask < A.bid 时有利可图
        const profit_b_to_a = self.calculateProfit(quote_b.ask, quote_a.bid, .b_to_a);

        const now = std.time.milliTimestamp();

        // 选择更优的机会
        if (profit_a_to_b.net_profit_bps > profit_b_to_a.net_profit_bps and
            profit_a_to_b.net_profit_bps >= @as(i32, @intCast(self.config.min_profit_bps)))
        {
            // 可用数量 = min(A 的卖量, B 的买量, 配置交易量)
            const available = if (quote_a.ask_size.cmp(quote_b.bid_size) == .lt) quote_a.ask_size else quote_b.bid_size;
            const trade_amount = if (available.cmp(self.config.trade_amount) == .lt) available else self.config.trade_amount;

            // 预期利润
            const spread = quote_b.bid.sub(quote_a.ask);
            const gross_profit = spread.mul(trade_amount);
            const fee_amount = quote_a.ask.mul(trade_amount).mul(Decimal.fromFloat(@as(f64, @floatFromInt(self.config.fee_bps_a)) / 10000.0))
                .add(quote_b.bid.mul(trade_amount).mul(Decimal.fromFloat(@as(f64, @floatFromInt(self.config.fee_bps_b)) / 10000.0)));
            const expected_profit = gross_profit.sub(fee_amount);

            return .{
                .direction = .a_to_b,
                .buy_price = quote_a.ask,
                .sell_price = quote_b.bid,
                .available_amount = available,
                .trade_amount = trade_amount,
                .gross_profit_bps = profit_a_to_b.gross_profit_bps,
                .fee_bps = profit_a_to_b.fee_bps,
                .net_profit_bps = profit_a_to_b.net_profit_bps,
                .expected_profit = expected_profit,
                .timestamp = now,
            };
        }

        if (profit_b_to_a.net_profit_bps >= @as(i32, @intCast(self.config.min_profit_bps))) {
            const available = if (quote_b.ask_size.cmp(quote_a.bid_size) == .lt) quote_b.ask_size else quote_a.bid_size;
            const trade_amount = if (available.cmp(self.config.trade_amount) == .lt) available else self.config.trade_amount;

            const spread = quote_a.bid.sub(quote_b.ask);
            const gross_profit = spread.mul(trade_amount);
            const fee_amount = quote_b.ask.mul(trade_amount).mul(Decimal.fromFloat(@as(f64, @floatFromInt(self.config.fee_bps_b)) / 10000.0))
                .add(quote_a.bid.mul(trade_amount).mul(Decimal.fromFloat(@as(f64, @floatFromInt(self.config.fee_bps_a)) / 10000.0)));
            const expected_profit = gross_profit.sub(fee_amount);

            return .{
                .direction = .b_to_a,
                .buy_price = quote_b.ask,
                .sell_price = quote_a.bid,
                .available_amount = available,
                .trade_amount = trade_amount,
                .gross_profit_bps = profit_b_to_a.gross_profit_bps,
                .fee_bps = profit_b_to_a.fee_bps,
                .net_profit_bps = profit_b_to_a.net_profit_bps,
                .expected_profit = expected_profit,
                .timestamp = now,
            };
        }

        return null;
    }

    // ========================================================================
    // 执行控制
    // ========================================================================

    /// 检查是否可以执行
    pub fn canExecute(self: *Self, opp: ArbitrageOpportunity) bool {
        // 检查仓位限制
        const new_position = switch (opp.direction) {
            .a_to_b => self.position_a.add(opp.trade_amount),
            .b_to_a => self.position_b.add(opp.trade_amount),
        };

        // 检查是否超过最大仓位
        if (new_position.abs().cmp(self.config.max_position) == .gt) {
            return false;
        }

        // 检查交易数量是否有效
        if (opp.trade_amount.isZero()) {
            return false;
        }

        return true;
    }

    /// 模拟执行套利
    fn executeArbitrageSimulated(self: *Self, opp: ArbitrageOpportunity) ArbitrageResult {
        _ = self;

        // 模拟成交 (假设完全成交)
        const buy_fee = opp.buy_price.mul(opp.trade_amount).mul(Decimal.fromFloat(0.001)); // 0.1%
        const sell_fee = opp.sell_price.mul(opp.trade_amount).mul(Decimal.fromFloat(0.001));

        const gross_profit = opp.sell_price.sub(opp.buy_price).mul(opp.trade_amount);
        const actual_profit = gross_profit.sub(buy_fee).sub(sell_fee);

        return .{
            .success = true,
            .buy_fill = .{
                .filled = true,
                .fill_price = opp.buy_price,
                .fill_amount = opp.trade_amount,
                .fee = buy_fee,
            },
            .sell_fill = .{
                .filled = true,
                .fill_price = opp.sell_price,
                .fill_amount = opp.trade_amount,
                .fee = sell_fee,
            },
            .actual_profit = actual_profit,
            .execution_time_ms = 5, // 模拟 5ms 执行时间
        };
    }

    // ========================================================================
    // 统计
    // ========================================================================

    /// 获取统计信息
    pub fn getStats(self: *Self) ArbStats {
        const success_rate: f64 = if (self.opportunities_detected > 0)
            @as(f64, @floatFromInt(self.opportunities_executed)) /
                @as(f64, @floatFromInt(self.opportunities_detected))
        else
            0;

        const avg_profit_bps: f64 = if (self.trade_count > 0)
            @as(f64, @floatFromInt(self.cumulative_profit_bps)) /
                @as(f64, @floatFromInt(self.trade_count))
        else
            0;

        return .{
            .opportunities_detected = self.opportunities_detected,
            .opportunities_executed = self.opportunities_executed,
            .opportunities_missed = self.opportunities_missed,
            .opportunities_failed = self.opportunities_failed,
            .trade_count = self.trade_count,
            .total_profit = self.total_profit,
            .total_fees = self.total_fees,
            .position_a = self.position_a,
            .position_b = self.position_b,
            .success_rate = success_rate,
            .avg_profit_bps = avg_profit_bps,
        };
    }

    /// 重置统计
    pub fn resetStats(self: *Self) void {
        self.opportunities_detected = 0;
        self.opportunities_executed = 0;
        self.opportunities_missed = 0;
        self.opportunities_failed = 0;
        self.trade_count = 0;
        self.total_profit = Decimal.ZERO;
        self.total_fees = Decimal.ZERO;
        self.cumulative_profit_bps = 0;
    }

    /// 获取净仓位
    pub fn getNetPosition(self: *Self) Decimal {
        return self.position_a.sub(self.position_b);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ArbitrageConfig: defaults" {
    const config = ArbitrageConfig{};
    try std.testing.expectEqual(@as(u32, 10), config.min_profit_bps);
    try std.testing.expectEqual(@as(u32, 10), config.fee_bps_a);
    try std.testing.expectEqual(@as(u32, 10), config.fee_bps_b);
}

test "Quote: mid price and spread" {
    const quote = Quote{
        .bid = Decimal.fromInt(2000),
        .ask = Decimal.fromInt(2010),
        .bid_size = Decimal.fromFloat(1.0),
        .ask_size = Decimal.fromFloat(1.0),
        .timestamp = 0,
    };

    const mid = try quote.midPrice();
    try std.testing.expect(mid.toFloat() == 2005.0);

    const spread_bps = quote.spreadBps();
    try std.testing.expectEqual(@as(u32, 50), spread_bps); // 10/2000 * 10000 = 50 bps
}

test "CrossExchangeArbitrage: profit calculation" {
    const allocator = std.testing.allocator;

    var arb = CrossExchangeArbitrage.init(allocator, .{
        .symbol = "ETH/USDT",
        .min_profit_bps = 10,
        .fee_bps_a = 10, // 0.1%
        .fee_bps_b = 10, // 0.1%
    });
    defer arb.deinit();

    // 测试: 在 A 买 @ 2000, 在 B 卖 @ 2010
    // 毛利润 = (2010-2000)/2000 = 0.5% = 50 bps
    // 费用 = 10 + 10 = 20 bps
    // 净利润 = 50 - 20 = 30 bps
    const calc = arb.calculateProfit(
        Decimal.fromInt(2000),
        Decimal.fromInt(2010),
        .a_to_b,
    );

    try std.testing.expectEqual(@as(u32, 50), calc.gross_profit_bps);
    try std.testing.expectEqual(@as(u32, 20), calc.fee_bps);
    try std.testing.expectEqual(@as(i32, 30), calc.net_profit_bps);
}

test "CrossExchangeArbitrage: opportunity detection - profitable" {
    const allocator = std.testing.allocator;

    var arb = CrossExchangeArbitrage.init(allocator, .{
        .symbol = "ETH/USDT",
        .min_profit_bps = 10,
        .trade_amount = Decimal.fromFloat(0.1),
        .fee_bps_a = 10,
        .fee_bps_b = 10,
    });
    defer arb.deinit();

    // 设置报价: A ask=2000, B bid=2015 (存在套利机会)
    const quote_a = Quote{
        .bid = Decimal.fromInt(1995),
        .ask = Decimal.fromInt(2000),
        .bid_size = Decimal.fromFloat(1.0),
        .ask_size = Decimal.fromFloat(1.0),
        .timestamp = 0,
    };

    const quote_b = Quote{
        .bid = Decimal.fromInt(2015),
        .ask = Decimal.fromInt(2020),
        .bid_size = Decimal.fromFloat(1.0),
        .ask_size = Decimal.fromFloat(1.0),
        .timestamp = 0,
    };

    const opp = arb.detectOpportunity(quote_a, quote_b);
    try std.testing.expect(opp != null);
    try std.testing.expect(opp.?.direction == .a_to_b);
    try std.testing.expect(opp.?.net_profit_bps > 0);

    // 毛利润 = (2015-2000)/2000 * 10000 = 75 bps
    // 净利润 = 75 - 20 = 55 bps
    try std.testing.expectEqual(@as(u32, 75), opp.?.gross_profit_bps);
    try std.testing.expectEqual(@as(i32, 55), opp.?.net_profit_bps);
}

test "CrossExchangeArbitrage: opportunity detection - not profitable" {
    const allocator = std.testing.allocator;

    var arb = CrossExchangeArbitrage.init(allocator, .{
        .symbol = "ETH/USDT",
        .min_profit_bps = 30, // 需要 30 bps 才执行
        .trade_amount = Decimal.fromFloat(0.1),
        .fee_bps_a = 10,
        .fee_bps_b = 10,
    });
    defer arb.deinit();

    // 设置报价: 价差太小，扣费后无利润
    const quote_a = Quote{
        .bid = Decimal.fromInt(1995),
        .ask = Decimal.fromInt(2000),
        .bid_size = Decimal.fromFloat(1.0),
        .ask_size = Decimal.fromFloat(1.0),
        .timestamp = 0,
    };

    const quote_b = Quote{
        .bid = Decimal.fromInt(2003), // 只有 3 点价差
        .ask = Decimal.fromInt(2008),
        .bid_size = Decimal.fromFloat(1.0),
        .ask_size = Decimal.fromFloat(1.0),
        .timestamp = 0,
    };

    // (2003-2000)/2000 * 10000 = 15 bps 毛利润
    // 净利润 = 15 - 20 = -5 bps (亏损)
    const opp = arb.detectOpportunity(quote_a, quote_b);
    try std.testing.expect(opp == null);
}

test "CrossExchangeArbitrage: reverse opportunity" {
    const allocator = std.testing.allocator;

    var arb = CrossExchangeArbitrage.init(allocator, .{
        .symbol = "ETH/USDT",
        .min_profit_bps = 10,
        .trade_amount = Decimal.fromFloat(0.1),
        .fee_bps_a = 10,
        .fee_bps_b = 10,
    });
    defer arb.deinit();

    // 设置报价: B ask < A bid (反向套利机会)
    const quote_a = Quote{
        .bid = Decimal.fromInt(2015),
        .ask = Decimal.fromInt(2020),
        .bid_size = Decimal.fromFloat(1.0),
        .ask_size = Decimal.fromFloat(1.0),
        .timestamp = 0,
    };

    const quote_b = Quote{
        .bid = Decimal.fromInt(1995),
        .ask = Decimal.fromInt(2000),
        .bid_size = Decimal.fromFloat(1.0),
        .ask_size = Decimal.fromFloat(1.0),
        .timestamp = 0,
    };

    const opp = arb.detectOpportunity(quote_a, quote_b);
    try std.testing.expect(opp != null);
    try std.testing.expect(opp.?.direction == .b_to_a);
}

test "CrossExchangeArbitrage: position limits" {
    const allocator = std.testing.allocator;

    var arb = CrossExchangeArbitrage.init(allocator, .{
        .symbol = "ETH/USDT",
        .min_profit_bps = 10,
        .trade_amount = Decimal.fromFloat(0.5),
        .max_position = Decimal.fromFloat(1.0),
    });
    defer arb.deinit();

    // 设置已有仓位接近限制
    arb.position_a = Decimal.fromFloat(0.8);

    const opp = ArbitrageOpportunity{
        .direction = .a_to_b,
        .buy_price = Decimal.fromInt(2000),
        .sell_price = Decimal.fromInt(2010),
        .available_amount = Decimal.fromFloat(1.0),
        .trade_amount = Decimal.fromFloat(0.5),
        .gross_profit_bps = 50,
        .fee_bps = 20,
        .net_profit_bps = 30,
        .expected_profit = Decimal.fromFloat(0.5),
        .timestamp = 0,
    };

    // 0.8 + 0.5 = 1.3 > 1.0 (超过限制)
    try std.testing.expect(!arb.canExecute(opp));

    // 减少仓位
    arb.position_a = Decimal.fromFloat(0.3);
    // 0.3 + 0.5 = 0.8 < 1.0
    try std.testing.expect(arb.canExecute(opp));
}

test "CrossExchangeArbitrage: stats" {
    const allocator = std.testing.allocator;

    var arb = CrossExchangeArbitrage.init(allocator, .{});
    defer arb.deinit();

    // 初始状态
    var stats = arb.getStats();
    try std.testing.expectEqual(@as(u32, 0), stats.opportunities_detected);
    try std.testing.expectEqual(@as(u32, 0), stats.trade_count);

    // 模拟一些活动
    arb.opportunities_detected = 100;
    arb.opportunities_executed = 80;
    arb.opportunities_missed = 10;
    arb.opportunities_failed = 10;
    arb.trade_count = 80;
    arb.cumulative_profit_bps = 2400; // 80 trades * 30 bps avg

    stats = arb.getStats();
    try std.testing.expectEqual(@as(u32, 100), stats.opportunities_detected);
    try std.testing.expectEqual(@as(u32, 80), stats.opportunities_executed);
    try std.testing.expect(stats.success_rate == 0.8);
    try std.testing.expect(stats.avg_profit_bps == 30.0);
}

test "CrossExchangeArbitrage: IClockStrategy interface" {
    const allocator = std.testing.allocator;

    var arb = CrossExchangeArbitrage.init(allocator, .{});
    defer arb.deinit();

    const strategy = arb.asClockStrategy();

    // 验证接口方法可调用
    try strategy.onStart();
    try strategy.onTick(1, std.time.nanoTimestamp());
    strategy.onStop();
}
