//! Pure Market Making 策略
//!
//! 在 mid price 两侧放置买卖订单，通过买卖价差获取利润的基础做市策略。
//!
//! ## 特性
//! - 双边报价 (同时在买卖两侧挂单)
//! - 多层级订单支持
//! - 自动刷新报价
//! - 仓位限制控制
//! - 实现 IClockStrategy 接口
//!
//! ## 使用示例
//!
//! ```zig
//! var mm = try PureMarketMaking.init(allocator, config, cache);
//! defer mm.deinit();
//!
//! // 注册到 Clock
//! try clock.addStrategy(mm.asClockStrategy());
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;
const Cache = @import("../core/cache.zig").Cache;
const Quote = @import("../core/cache.zig").Quote;
const IClockStrategy = @import("interfaces.zig").IClockStrategy;
const types = @import("types.zig");
const OrderInfo = types.OrderInfo;
const OrderFill = types.OrderFill;
const MMStats = types.MMStats;
const Side = @import("../exchange/types.zig").Side;

// ============================================================================
// 配置
// ============================================================================

/// Pure Market Making 配置
pub const PureMMConfig = struct {
    /// 交易对 (e.g. "ETH-USD")
    symbol: []const u8,

    /// 价差 (basis points, 1 bp = 0.01%)
    /// 例: 10 bps = 0.1% 总价差 (每边 0.05%)
    spread_bps: u32 = 10,

    /// 单边订单数量 (base currency)
    order_amount: Decimal,

    /// 价格层级数 (每边)
    order_levels: u32 = 1,

    /// 层级间价差 (basis points)
    level_spread_bps: u32 = 5,

    /// 最小报价更新阈值 (mid price 变化的 bps)
    min_refresh_bps: u32 = 2,

    /// 订单有效时间 (ticks)
    order_ttl_ticks: u32 = 60,

    /// 最大仓位 (base currency)
    max_position: Decimal,

    /// 是否启用两侧报价 (false = 只在单侧报价)
    dual_side: bool = true,

    /// 验证配置
    pub fn validate(self: PureMMConfig) !void {
        if (self.symbol.len == 0) {
            return error.InvalidSymbol;
        }
        if (self.spread_bps == 0) {
            return error.InvalidSpread;
        }
        if (self.order_levels == 0) {
            return error.InvalidLevels;
        }
        if (self.order_amount.cmp(Decimal.ZERO) != .gt) {
            return error.InvalidAmount;
        }
        if (self.max_position.cmp(Decimal.ZERO) != .gt) {
            return error.InvalidMaxPosition;
        }
    }
};

/// 配置错误
pub const ConfigError = error{
    InvalidSymbol,
    InvalidSpread,
    InvalidLevels,
    InvalidAmount,
    InvalidMaxPosition,
};

// ============================================================================
// Pure Market Making 策略
// ============================================================================

/// Pure Market Making 策略
pub const PureMarketMaking = struct {
    /// 内存分配器
    allocator: Allocator,
    /// 策略配置
    config: PureMMConfig,
    /// 缓存引用 (获取 quote)
    cache: *Cache,

    // 状态
    /// 当前持仓
    current_position: Decimal,
    /// 活跃买单
    active_bids: std.ArrayList(OrderInfo),
    /// 活跃卖单
    active_asks: std.ArrayList(OrderInfo),
    /// 上次中间价
    last_mid_price: ?Decimal,
    /// 上次更新 tick
    last_update_tick: u64,
    /// 下一个订单 ID
    next_order_id: u64,

    // 统计
    /// 总成交笔数
    total_trades: u64,
    /// 总成交量
    total_volume: Decimal,
    /// 总成交额
    total_notional: Decimal,
    /// 已实现盈亏
    realized_pnl: Decimal,
    /// 总手续费
    total_fees: Decimal,
    /// 平均买入价 (用于计算 PnL)
    avg_entry_price: Decimal,

    const Self = @This();

    // ========================================================================
    // 初始化
    // ========================================================================

    /// 初始化策略
    pub fn init(allocator: Allocator, config: PureMMConfig, cache: *Cache) !Self {
        try config.validate();

        return .{
            .allocator = allocator,
            .config = config,
            .cache = cache,
            .current_position = Decimal.ZERO,
            .active_bids = try std.ArrayList(OrderInfo).initCapacity(allocator, config.order_levels),
            .active_asks = try std.ArrayList(OrderInfo).initCapacity(allocator, config.order_levels),
            .last_mid_price = null,
            .last_update_tick = 0,
            .next_order_id = 1,
            .total_trades = 0,
            .total_volume = Decimal.ZERO,
            .total_notional = Decimal.ZERO,
            .realized_pnl = Decimal.ZERO,
            .total_fees = Decimal.ZERO,
            .avg_entry_price = Decimal.ZERO,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        self.active_bids.deinit(self.allocator);
        self.active_asks.deinit(self.allocator);
    }

    // ========================================================================
    // IClockStrategy 实现
    // ========================================================================

    /// VTable for IClockStrategy
    const vtable = IClockStrategy.VTable{
        .onTick = onTickImpl,
        .onStart = onStartImpl,
        .onStop = onStopImpl,
    };

    /// 获取 IClockStrategy 接口
    pub fn asClockStrategy(self: *Self) IClockStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn onTickImpl(ptr: *anyopaque, tick: u64, timestamp: i128) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = timestamp;

        // 1. 获取当前 mid price
        const mid = self.getMidPrice() orelse return;

        // 2. 检查过期订单
        self.expireOldOrders(tick);

        // 3. 检查是否需要更新报价
        if (self.shouldRefreshQuotes(mid, tick)) {
            // 4. 取消所有现有订单
            self.cancelAllOrders();

            // 5. 下新订单
            try self.placeQuotes(mid, tick);

            self.last_mid_price = mid;
            self.last_update_tick = tick;
        }
    }

    fn onStartImpl(ptr: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        std.log.info("[PureMM] Starting for {s}, spread={d}bps, levels={d}", .{
            self.config.symbol,
            self.config.spread_bps,
            self.config.order_levels,
        });
    }

    fn onStopImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        std.log.info("[PureMM] Stopping, canceling all orders", .{});
        self.cancelAllOrders();
    }

    // ========================================================================
    // 核心逻辑
    // ========================================================================

    /// 获取中间价
    fn getMidPrice(self: *Self) ?Decimal {
        const quote = self.cache.getQuote(self.config.symbol) orelse return null;
        return quote.midPrice();
    }

    /// 检查是否需要刷新报价
    fn shouldRefreshQuotes(self: *Self, current_mid: Decimal, current_tick: u64) bool {
        // 首次运行
        if (self.last_mid_price == null) return true;

        // 检查订单是否为空
        if (self.active_bids.items.len == 0 and self.active_asks.items.len == 0) {
            return true;
        }

        const last_mid = self.last_mid_price.?;

        // 计算变化幅度 (basis points)
        const diff = current_mid.sub(last_mid);
        const abs_diff = if (diff.value < 0)
            Decimal{ .value = -diff.value, .scale = diff.scale }
        else
            diff;

        // change_bps = |diff| / last_mid * 10000
        const bps_multiplier = Decimal.fromInt(10000);
        const change_bps = abs_diff.mul(bps_multiplier).div(last_mid) catch Decimal.ZERO;

        // 如果变化超过阈值，刷新
        const threshold = Decimal.fromInt(@as(i64, @intCast(self.config.min_refresh_bps)));
        if (change_bps.cmp(threshold) == .gt) {
            return true;
        }

        // 检查订单 TTL
        const ticks_since_update = current_tick - self.last_update_tick;
        if (ticks_since_update >= self.config.order_ttl_ticks) {
            return true;
        }

        return false;
    }

    /// 下报价单
    fn placeQuotes(self: *Self, mid: Decimal, tick: u64) !void {
        // 检查仓位限制
        const abs_position = if (self.current_position.value < 0)
            Decimal{ .value = -self.current_position.value, .scale = self.current_position.scale }
        else
            self.current_position;

        if (abs_position.cmp(self.config.max_position) == .gt) {
            std.log.warn("[PureMM] Max position reached: {d}, skipping new quotes", .{
                self.current_position.toFloat(),
            });
            return;
        }

        // 计算半价差
        // half_spread = mid * spread_bps / 20000
        const spread_decimal = Decimal.fromInt(@as(i64, @intCast(self.config.spread_bps)));
        const divisor = Decimal.fromInt(20000);
        const half_spread = mid.mul(spread_decimal).div(divisor) catch Decimal.ZERO;

        // 多层级报价
        for (0..self.config.order_levels) |i| {
            // 计算层级偏移
            // level_offset = mid * (i * level_spread_bps) / 10000
            const level_offset = if (i == 0)
                Decimal.ZERO
            else blk: {
                const level_bps = @as(i64, @intCast(i * self.config.level_spread_bps));
                const offset_decimal = Decimal.fromInt(level_bps);
                const divisor2 = Decimal.fromInt(10000);
                break :blk mid.mul(offset_decimal).div(divisor2) catch Decimal.ZERO;
            };

            // 买单
            const should_bid = self.config.dual_side or self.current_position.toFloat() < 0;
            if (should_bid) {
                const bid_price = mid.sub(half_spread).sub(level_offset);
                try self.placeBid(bid_price, self.config.order_amount, tick);
            }

            // 卖单
            const should_ask = self.config.dual_side or self.current_position.toFloat() > 0;
            if (should_ask) {
                const ask_price = mid.add(half_spread).add(level_offset);
                try self.placeAsk(ask_price, self.config.order_amount, tick);
            }
        }
    }

    /// 下买单
    fn placeBid(self: *Self, price: Decimal, amount: Decimal, tick: u64) !void {
        const order_id = try self.generateOrderId();

        try self.active_bids.append(self.allocator, .{
            .order_id = order_id,
            .price = price,
            .amount = amount,
            .side = .buy,
            .created_tick = tick,
        });

        std.log.debug("[PureMM] Placed BID: {d} @ {d}", .{
            amount.toFloat(),
            price.toFloat(),
        });
    }

    /// 下卖单
    fn placeAsk(self: *Self, price: Decimal, amount: Decimal, tick: u64) !void {
        const order_id = try self.generateOrderId();

        try self.active_asks.append(self.allocator, .{
            .order_id = order_id,
            .price = price,
            .amount = amount,
            .side = .sell,
            .created_tick = tick,
        });

        std.log.debug("[PureMM] Placed ASK: {d} @ {d}", .{
            amount.toFloat(),
            price.toFloat(),
        });
    }

    /// 生成订单 ID
    fn generateOrderId(self: *Self) ![]const u8 {
        const id = self.next_order_id;
        self.next_order_id += 1;

        var buf: [32]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, "{d}", .{id}) catch return error.OutOfMemory;
        const result = try self.allocator.alloc(u8, slice.len);
        @memcpy(result, slice);
        return result;
    }

    /// 取消所有订单
    fn cancelAllOrders(self: *Self) void {
        // 释放订单 ID 内存
        for (self.active_bids.items) |order| {
            self.allocator.free(order.order_id);
        }
        self.active_bids.clearRetainingCapacity();

        for (self.active_asks.items) |order| {
            self.allocator.free(order.order_id);
        }
        self.active_asks.clearRetainingCapacity();
    }

    /// 过期旧订单
    fn expireOldOrders(self: *Self, current_tick: u64) void {
        // 过期买单
        var i: usize = 0;
        while (i < self.active_bids.items.len) {
            const order = self.active_bids.items[i];
            if (current_tick - order.created_tick >= self.config.order_ttl_ticks) {
                self.allocator.free(order.order_id);
                _ = self.active_bids.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        // 过期卖单
        i = 0;
        while (i < self.active_asks.items.len) {
            const order = self.active_asks.items[i];
            if (current_tick - order.created_tick >= self.config.order_ttl_ticks) {
                self.allocator.free(order.order_id);
                _ = self.active_asks.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    // ========================================================================
    // 成交处理
    // ========================================================================

    /// 处理成交回报
    pub fn onFill(self: *Self, fill: OrderFill) void {
        const fill_value = fill.quantity.mul(fill.price);

        if (fill.side == .buy) {
            // 更新平均买入价
            const old_value = self.current_position.mul(self.avg_entry_price);
            const new_total = self.current_position.add(fill.quantity);
            if (new_total.cmp(Decimal.ZERO) != .eq) {
                self.avg_entry_price = old_value.add(fill_value).div(new_total) catch Decimal.ZERO;
            }
            self.current_position = new_total;
        } else {
            // 计算已实现盈亏
            const pnl = fill.price.sub(self.avg_entry_price).mul(fill.quantity);
            self.realized_pnl = self.realized_pnl.add(pnl);
            self.current_position = self.current_position.sub(fill.quantity);
        }

        self.total_trades += 1;
        self.total_volume = self.total_volume.add(fill.quantity);
        self.total_notional = self.total_notional.add(fill_value);
        self.total_fees = self.total_fees.add(fill.fee);

        std.log.info("[PureMM] Fill: {d} {s} @ {d}, position: {d}, pnl: {d}", .{
            fill.quantity.toFloat(),
            if (fill.side == .buy) "BUY" else "SELL",
            fill.price.toFloat(),
            self.current_position.toFloat(),
            self.realized_pnl.toFloat(),
        });

        // 移除已成交订单
        self.removeFilledOrder(fill.order_id, fill.side);
    }

    /// 移除已成交订单
    fn removeFilledOrder(self: *Self, order_id: []const u8, side: Side) void {
        const list = if (side == .buy) &self.active_bids else &self.active_asks;

        for (list.items, 0..) |order, i| {
            if (std.mem.eql(u8, order.order_id, order_id)) {
                self.allocator.free(order.order_id);
                _ = list.orderedRemove(i);
                return;
            }
        }
    }

    // ========================================================================
    // 统计
    // ========================================================================

    /// 获取统计信息
    pub fn getStats(self: *const Self) MMStats {
        return .{
            .total_trades = self.total_trades,
            .total_volume = self.total_volume,
            .total_notional = self.total_notional,
            .current_position = self.current_position,
            .realized_pnl = self.realized_pnl,
            .active_bids = self.active_bids.items.len,
            .active_asks = self.active_asks.items.len,
            .total_fees = self.total_fees,
        };
    }

    /// 获取当前报价
    pub fn getCurrentQuotes(self: *const Self) struct { bids: []const OrderInfo, asks: []const OrderInfo } {
        return .{
            .bids = self.active_bids.items,
            .asks = self.active_asks.items,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "PureMMConfig: validation" {
    const valid_config = PureMMConfig{
        .symbol = "ETH-USD",
        .spread_bps = 10,
        .order_amount = Decimal.fromFloat(0.1),
        .order_levels = 2,
        .max_position = Decimal.fromFloat(1.0),
    };

    try valid_config.validate();
}

test "PureMMConfig: invalid symbol" {
    const config = PureMMConfig{
        .symbol = "",
        .order_amount = Decimal.fromFloat(0.1),
        .max_position = Decimal.fromFloat(1.0),
    };

    try std.testing.expectError(error.InvalidSymbol, config.validate());
}

test "PureMMConfig: invalid spread" {
    const config = PureMMConfig{
        .symbol = "ETH-USD",
        .spread_bps = 0,
        .order_amount = Decimal.fromFloat(0.1),
        .max_position = Decimal.fromFloat(1.0),
    };

    try std.testing.expectError(error.InvalidSpread, config.validate());
}

test "PureMarketMaking: initialization" {
    const allocator = std.testing.allocator;

    // 创建 mock cache
    var cache = Cache.init(allocator, null, .{});
    defer cache.deinit();

    const config = PureMMConfig{
        .symbol = "ETH-USD",
        .spread_bps = 10,
        .order_amount = Decimal.fromFloat(0.1),
        .order_levels = 2,
        .max_position = Decimal.fromFloat(1.0),
    };

    var mm = try PureMarketMaking.init(allocator, config, &cache);
    defer mm.deinit();

    try std.testing.expectEqual(Decimal.ZERO, mm.current_position);
    try std.testing.expectEqual(@as(u64, 0), mm.total_trades);
}

test "PureMarketMaking: getStats" {
    const allocator = std.testing.allocator;

    var cache = Cache.init(allocator, null, .{});
    defer cache.deinit();

    const config = PureMMConfig{
        .symbol = "ETH-USD",
        .spread_bps = 10,
        .order_amount = Decimal.fromFloat(0.1),
        .order_levels = 1,
        .max_position = Decimal.fromFloat(1.0),
    };

    var mm = try PureMarketMaking.init(allocator, config, &cache);
    defer mm.deinit();

    const stats = mm.getStats();

    try std.testing.expectEqual(@as(u64, 0), stats.total_trades);
    try std.testing.expectEqual(@as(usize, 0), stats.active_bids);
    try std.testing.expectEqual(@as(usize, 0), stats.active_asks);
}

test "PureMarketMaking: onFill updates position" {
    const allocator = std.testing.allocator;

    var cache = Cache.init(allocator, null, .{});
    defer cache.deinit();

    const config = PureMMConfig{
        .symbol = "ETH-USD",
        .spread_bps = 10,
        .order_amount = Decimal.fromFloat(0.1),
        .order_levels = 1,
        .max_position = Decimal.fromFloat(1.0),
    };

    var mm = try PureMarketMaking.init(allocator, config, &cache);
    defer mm.deinit();

    // 模拟买入成交
    mm.onFill(.{
        .order_id = "test1",
        .symbol = "ETH-USD",
        .side = .buy,
        .quantity = Decimal.fromFloat(0.1),
        .price = Decimal.fromInt(2000),
        .fee = Decimal.fromFloat(0.1),
        .timestamp = 0,
    });

    try std.testing.expect(mm.current_position.toFloat() > 0.09);
    try std.testing.expectEqual(@as(u64, 1), mm.total_trades);

    // 模拟卖出成交
    mm.onFill(.{
        .order_id = "test2",
        .symbol = "ETH-USD",
        .side = .sell,
        .quantity = Decimal.fromFloat(0.1),
        .price = Decimal.fromInt(2010),
        .fee = Decimal.fromFloat(0.1),
        .timestamp = 0,
    });

    try std.testing.expect(mm.current_position.toFloat() < 0.01);
    try std.testing.expectEqual(@as(u64, 2), mm.total_trades);
    // PnL = (2010 - 2000) * 0.1 = 1
    try std.testing.expect(mm.realized_pnl.toFloat() > 0);
}

test "PureMarketMaking: asClockStrategy" {
    const allocator = std.testing.allocator;

    var cache = Cache.init(allocator, null, .{});
    defer cache.deinit();

    const config = PureMMConfig{
        .symbol = "ETH-USD",
        .spread_bps = 10,
        .order_amount = Decimal.fromFloat(0.1),
        .order_levels = 1,
        .max_position = Decimal.fromFloat(1.0),
    };

    var mm = try PureMarketMaking.init(allocator, config, &cache);
    defer mm.deinit();

    const iface = mm.asClockStrategy();

    // Test interface methods
    try iface.onStart();
    try iface.onTick(1, 1000);
    iface.onStop();
}
