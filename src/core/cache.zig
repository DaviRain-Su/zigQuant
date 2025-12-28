//! Cache - 中央数据缓存组件
//!
//! 为 NautilusTrader 风格的事件驱动架构提供统一的数据缓存。
//!
//! ## 功能
//! - 订单簿缓存 (by symbol)
//! - 仓位缓存 (by symbol)
//! - 账户余额缓存
//! - K线数据缓存 (by symbol + timeframe)
//! - 最新报价缓存
//! - 与 MessageBus 集成，自动发布数据更新事件
//!
//! ## 设计原则
//! - 单线程设计，无锁
//! - 通过 MessageBus 发布变更通知
//! - 内存高效，使用 HashMap 快速查找
//! - 自动过期机制（可选）

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("decimal.zig").Decimal;
const Timestamp = @import("time.zig").Timestamp;
const OrderBook = @import("../market/orderbook.zig").OrderBook;
const Level = @import("../market/orderbook.zig").Level;
const Position = @import("../trading/position.zig").Position;
const message_bus = @import("message_bus.zig");
const MessageBus = message_bus.MessageBus;
const Event = message_bus.Event;
const Order = @import("../exchange/types.zig").Order;

// ============================================================================
// 类型定义
// ============================================================================

/// 账户余额
pub const AccountBalance = struct {
    currency: []const u8, // 货币 (e.g. "USDT")
    total: Decimal, // 总余额
    available: Decimal, // 可用余额
    locked: Decimal, // 锁定余额 (保证金/挂单)
    unrealized_pnl: Decimal, // 未实现盈亏
    updated_at: Timestamp,
};

/// 报价 (Tick)
pub const Quote = struct {
    symbol: []const u8,
    bid: Decimal, // 最高买价
    ask: Decimal, // 最低卖价
    bid_size: Decimal, // 买价深度
    ask_size: Decimal, // 卖价深度
    timestamp: Timestamp,

    /// 计算中间价
    pub fn midPrice(self: Quote) Decimal {
        return self.bid.add(self.ask).div(Decimal.fromInt(2)) catch Decimal.ZERO;
    }

    /// 计算价差
    pub fn spread(self: Quote) Decimal {
        return self.ask.sub(self.bid);
    }

    /// 计算价差百分比
    pub fn spreadPercent(self: Quote) Decimal {
        const mid = self.midPrice();
        if (mid.cmp(Decimal.ZERO) == .eq) return Decimal.ZERO;
        return self.spread().mul(Decimal.fromInt(100)).div(mid) catch Decimal.ZERO;
    }
};

/// K线 (OHLCV Bar)
pub const Bar = struct {
    symbol: []const u8,
    timeframe: Timeframe,
    open: Decimal,
    high: Decimal,
    low: Decimal,
    close: Decimal,
    volume: Decimal,
    timestamp: Timestamp, // K线开始时间
    is_closed: bool, // 是否已闭合

    /// 是否为阳线
    pub fn isBullish(self: Bar) bool {
        return self.close.cmp(self.open) == .gt;
    }

    /// 是否为阴线
    pub fn isBearish(self: Bar) bool {
        return self.close.cmp(self.open) == .lt;
    }

    /// 计算振幅
    pub fn range(self: Bar) Decimal {
        return self.high.sub(self.low);
    }
};

/// 时间周期 (支持 Binance 全部时间周期)
pub const Timeframe = enum {
    s1, // 1秒
    m1, // 1分钟
    m3, // 3分钟
    m5, // 5分钟
    m15, // 15分钟
    m30, // 30分钟
    h1, // 1小时
    h2, // 2小时
    h4, // 4小时
    h6, // 6小时
    h8, // 8小时
    h12, // 12小时
    d1, // 1天
    d3, // 3天
    w1, // 1周
    M1, // 1月

    pub fn toSeconds(self: Timeframe) u64 {
        return switch (self) {
            .s1 => 1,
            .m1 => 60,
            .m3 => 180,
            .m5 => 300,
            .m15 => 900,
            .m30 => 1800,
            .h1 => 3600,
            .h2 => 7200,
            .h4 => 14400,
            .h6 => 21600,
            .h8 => 28800,
            .h12 => 43200,
            .d1 => 86400,
            .d3 => 259200,
            .w1 => 604800,
            .M1 => 2592000,
        };
    }

    pub fn toString(self: Timeframe) []const u8 {
        return switch (self) {
            .s1 => "1s",
            .m1 => "1m",
            .m3 => "3m",
            .m5 => "5m",
            .m15 => "15m",
            .m30 => "30m",
            .h1 => "1h",
            .h2 => "2h",
            .h4 => "4h",
            .h6 => "6h",
            .h8 => "8h",
            .h12 => "12h",
            .d1 => "1d",
            .d3 => "3d",
            .w1 => "1w",
            .M1 => "1M",
        };
    }
};

/// 缓存错误
pub const CacheError = error{
    SymbolNotFound,
    OutOfMemory,
    InvalidData,
    TimeframeNotFound,
};

// ============================================================================
// Cache 主结构
// ============================================================================

pub const Cache = struct {
    allocator: Allocator,
    bus: ?*MessageBus,

    // 订单簿缓存: symbol -> OrderBook
    orderbooks: std.StringHashMap(*OrderBook),

    // 仓位缓存: symbol -> Position
    positions: std.StringHashMap(*Position),

    // 账户余额缓存: currency -> Balance
    balances: std.StringHashMap(AccountBalance),

    // 报价缓存: symbol -> Quote
    quotes: std.StringHashMap(Quote),

    // K线缓存: "symbol:timeframe" -> []Bar
    bars: std.StringHashMap(BarSeries),

    // 订单缓存: order_id -> Order
    orders: std.StringHashMap(*Order),

    // 配置
    config: Config,

    // 统计
    stats: Stats,

    pub const Config = struct {
        max_bars_per_series: usize = 1000, // 每个序列最多保留的K线数量
        quote_expiry_ms: u64 = 60_000, // 报价过期时间 (1分钟)
        enable_notifications: bool = false, // 是否启用 MessageBus 通知 (默认关闭，后续集成时启用)
    };

    pub const Stats = struct {
        orderbook_updates: u64 = 0,
        quote_updates: u64 = 0,
        position_updates: u64 = 0,
        bar_updates: u64 = 0,
        order_updates: u64 = 0,
    };

    const BarSeries = struct {
        bars: std.ArrayList(Bar),
        max_size: usize,

        pub fn init(_: Allocator, max_size: usize) BarSeries {
            return .{
                .bars = .{},
                .max_size = max_size,
            };
        }

        pub fn deinit(self: *BarSeries, allocator: Allocator) void {
            for (self.bars.items) |*bar| {
                allocator.free(bar.symbol);
            }
            self.bars.deinit(allocator);
        }

        pub fn append(self: *BarSeries, allocator: Allocator, bar: Bar) !void {
            // 如果超过最大大小，移除最旧的
            if (self.bars.items.len >= self.max_size) {
                const old_bar = self.bars.orderedRemove(0);
                allocator.free(old_bar.symbol);
            }
            try self.bars.append(allocator, bar);
        }

        pub fn last(self: *const BarSeries) ?Bar {
            if (self.bars.items.len == 0) return null;
            return self.bars.items[self.bars.items.len - 1];
        }

        pub fn updateLast(self: *BarSeries, bar: Bar, allocator: Allocator) void {
            if (self.bars.items.len > 0) {
                const last_bar = &self.bars.items[self.bars.items.len - 1];
                allocator.free(last_bar.symbol);
                last_bar.* = bar;
            }
        }
    };

    // ========================================================================
    // 初始化和清理
    // ========================================================================

    /// 初始化 Cache
    pub fn init(allocator: Allocator, bus: ?*MessageBus, config: Config) Cache {
        return .{
            .allocator = allocator,
            .bus = bus,
            .orderbooks = std.StringHashMap(*OrderBook).init(allocator),
            .positions = std.StringHashMap(*Position).init(allocator),
            .balances = std.StringHashMap(AccountBalance).init(allocator),
            .quotes = std.StringHashMap(Quote).init(allocator),
            .bars = std.StringHashMap(BarSeries).init(allocator),
            .orders = std.StringHashMap(*Order).init(allocator),
            .config = config,
            .stats = .{},
        };
    }

    /// 释放资源
    pub fn deinit(self: *Cache) void {
        // 释放订单簿
        var ob_iter = self.orderbooks.iterator();
        while (ob_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.orderbooks.deinit();

        // 释放仓位
        var pos_iter = self.positions.iterator();
        while (pos_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.positions.deinit();

        // 释放余额
        var bal_iter = self.balances.iterator();
        while (bal_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.currency);
        }
        self.balances.deinit();

        // 释放报价
        var quote_iter = self.quotes.iterator();
        while (quote_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.symbol);
        }
        self.quotes.deinit();

        // 释放K线
        var bar_iter = self.bars.iterator();
        while (bar_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.bars.deinit();

        // 释放订单 (只释放 key，不释放 Order 本身，因为 Order 可能被其他地方管理)
        var order_iter = self.orders.iterator();
        while (order_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.orders.deinit();
    }

    // ========================================================================
    // OrderBook 操作
    // ========================================================================

    /// 更新订单簿
    pub fn updateOrderBook(self: *Cache, symbol: []const u8, bids: []const Level, asks: []const Level) !void {
        const result = try self.orderbooks.getOrPut(symbol);

        if (!result.found_existing) {
            // 创建新订单簿
            result.key_ptr.* = try self.allocator.dupe(u8, symbol);
            const ob = try self.allocator.create(OrderBook);
            ob.* = try OrderBook.init(self.allocator, symbol);
            result.value_ptr.* = ob;
        }

        // 更新订单簿数据
        const ob = result.value_ptr.*;
        try ob.applySnapshot(bids, asks, Timestamp.now());

        self.stats.orderbook_updates += 1;

        // 发布更新事件
        if (self.config.enable_notifications) {
            if (self.bus) |bus| {
                bus.publish("orderbook.update", .{
                    .orderbook_update = .{
                        .instrument_id = symbol,
                        .timestamp = Timestamp.now().millis * 1_000_000, // millis to nanos
                        .is_snapshot = true,
                    },
                });
            }
        }
    }

    /// 获取订单簿
    pub fn getOrderBook(self: *const Cache, symbol: []const u8) ?*OrderBook {
        return self.orderbooks.get(symbol);
    }

    /// 获取最优买价
    pub fn getBestBid(self: *const Cache, symbol: []const u8) ?Decimal {
        if (self.orderbooks.get(symbol)) |ob| {
            if (ob.getBestBid()) |level| {
                return level.price;
            }
        }
        return null;
    }

    /// 获取最优卖价
    pub fn getBestAsk(self: *const Cache, symbol: []const u8) ?Decimal {
        if (self.orderbooks.get(symbol)) |ob| {
            if (ob.getBestAsk()) |level| {
                return level.price;
            }
        }
        return null;
    }

    // ========================================================================
    // Quote 操作
    // ========================================================================

    /// 更新报价
    pub fn updateQuote(self: *Cache, quote: Quote) !void {
        const result = try self.quotes.getOrPut(quote.symbol);

        if (!result.found_existing) {
            result.key_ptr.* = try self.allocator.dupe(u8, quote.symbol);
        } else {
            // 释放旧的 symbol
            self.allocator.free(result.value_ptr.symbol);
        }

        // 复制 symbol
        var new_quote = quote;
        new_quote.symbol = try self.allocator.dupe(u8, quote.symbol);
        result.value_ptr.* = new_quote;

        self.stats.quote_updates += 1;

        // 发布更新事件
        if (self.config.enable_notifications) {
            if (self.bus) |bus| {
                bus.publish("quote.update", .{
                    .market_data = .{
                        .instrument_id = quote.symbol,
                        .timestamp = quote.timestamp.millis * 1_000_000, // millis to nanos
                        .bid = quote.bid.toFloat(),
                        .ask = quote.ask.toFloat(),
                        .bid_size = quote.bid_size.toFloat(),
                        .ask_size = quote.ask_size.toFloat(),
                    },
                });
            }
        }
    }

    /// 获取报价
    pub fn getQuote(self: *const Cache, symbol: []const u8) ?Quote {
        return self.quotes.get(symbol);
    }

    /// 获取中间价
    pub fn getMidPrice(self: *const Cache, symbol: []const u8) ?Decimal {
        if (self.quotes.get(symbol)) |quote| {
            return quote.midPrice();
        }
        return null;
    }

    // ========================================================================
    // Position 操作
    // ========================================================================

    /// 更新仓位
    pub fn updatePosition(self: *Cache, position: *Position) !void {
        const result = try self.positions.getOrPut(position.coin);

        if (!result.found_existing) {
            result.key_ptr.* = try self.allocator.dupe(u8, position.coin);
            // 创建新的仓位副本
            const pos = try self.allocator.create(Position);
            pos.* = position.*;
            result.value_ptr.* = pos;
        } else {
            // 更新现有仓位
            result.value_ptr.*.* = position.*;
        }

        self.stats.position_updates += 1;

        // 发布更新事件
        if (self.config.enable_notifications) {
            if (self.bus) |bus| {
                const side: message_bus.PositionEvent.Side = if (position.szi.cmp(Decimal.ZERO) == .gt) .long else if (position.szi.cmp(Decimal.ZERO) == .lt) .short else .flat;
                bus.publish("position.update", .{
                    .position_updated = .{
                        .instrument_id = position.coin,
                        .side = side,
                        .quantity = position.szi.abs().toFloat(),
                        .entry_price = position.entry_px.toFloat(),
                        .unrealized_pnl = position.unrealized_pnl.toFloat(),
                        .timestamp = position.updated_at.millis * 1_000_000, // millis to nanos
                    },
                });
            }
        }
    }

    /// 获取仓位
    pub fn getPosition(self: *const Cache, symbol: []const u8) ?*Position {
        return self.positions.get(symbol);
    }

    /// 检查是否有仓位
    pub fn hasPosition(self: *const Cache, symbol: []const u8) bool {
        return self.positions.contains(symbol);
    }

    /// 获取所有仓位
    pub fn getAllPositions(self: *const Cache) []*Position {
        var result: []*Position = &[_]*Position{};
        var list = std.ArrayList(*Position).init(self.allocator);
        defer list.deinit(self.allocator);

        var iter = self.positions.iterator();
        while (iter.next()) |entry| {
            list.append(self.allocator, entry.value_ptr.*) catch {};
        }

        if (list.items.len > 0) {
            result = list.toOwnedSlice(self.allocator) catch &[_]*Position{};
        }
        return result;
    }

    // ========================================================================
    // Balance 操作
    // ========================================================================

    /// 更新余额
    pub fn updateBalance(self: *Cache, balance: AccountBalance) !void {
        const result = try self.balances.getOrPut(balance.currency);

        if (!result.found_existing) {
            result.key_ptr.* = try self.allocator.dupe(u8, balance.currency);
        } else {
            // 释放旧的 currency
            self.allocator.free(result.value_ptr.currency);
        }

        // 复制 currency
        var new_balance = balance;
        new_balance.currency = try self.allocator.dupe(u8, balance.currency);
        result.value_ptr.* = new_balance;

        // 发布更新事件
        if (self.config.enable_notifications) {
            if (self.bus) |bus| {
                bus.publish("account.update", .{
                    .account_updated = .{
                        .account_id = balance.currency,
                        .balance = balance.total.toFloat(),
                        .available = balance.available.toFloat(),
                        .margin_used = balance.locked.toFloat(),
                        .unrealized_pnl = balance.unrealized_pnl.toFloat(),
                        .timestamp = balance.updated_at.millis * 1_000_000, // millis to nanos
                    },
                });
            }
        }
    }

    /// 获取余额
    pub fn getBalance(self: *const Cache, currency: []const u8) ?AccountBalance {
        return self.balances.get(currency);
    }

    /// 获取可用余额
    pub fn getAvailableBalance(self: *const Cache, currency: []const u8) Decimal {
        if (self.balances.get(currency)) |balance| {
            return balance.available;
        }
        return Decimal.ZERO;
    }

    // ========================================================================
    // Bar 操作
    // ========================================================================

    /// 生成 bar key
    fn makeBarKey(self: *Cache, symbol: []const u8, timeframe: Timeframe) ![]const u8 {
        var buf: [256]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{s}:{s}", .{ symbol, timeframe.toString() }) catch return CacheError.InvalidData;
        return try self.allocator.dupe(u8, result);
    }

    /// 更新 K线
    pub fn updateBar(self: *Cache, bar: Bar) !void {
        const key = try self.makeBarKey(bar.symbol, bar.timeframe);
        defer self.allocator.free(key);

        const result = try self.bars.getOrPut(key);

        if (!result.found_existing) {
            result.key_ptr.* = try self.allocator.dupe(u8, key);
            result.value_ptr.* = BarSeries.init(self.allocator, self.config.max_bars_per_series);
        }

        // 复制 symbol
        var owned_bar = bar;
        owned_bar.symbol = try self.allocator.dupe(u8, bar.symbol);

        // 检查是否更新最后一个 bar
        if (result.value_ptr.last()) |last_bar| {
            if (last_bar.timestamp.eql(bar.timestamp) and !last_bar.is_closed) {
                // 更新未闭合的 bar
                result.value_ptr.updateLast(owned_bar, self.allocator);
            } else {
                // 添加新 bar
                try result.value_ptr.append(self.allocator, owned_bar);
            }
        } else {
            // 第一个 bar
            try result.value_ptr.append(self.allocator, owned_bar);
        }

        self.stats.bar_updates += 1;

        // 发布更新事件
        if (self.config.enable_notifications and bar.is_closed) {
            if (self.bus) |bus| {
                const tf: message_bus.CandleEvent.Timeframe = switch (bar.timeframe) {
                    .s1 => .s1,
                    .m1 => .m1,
                    .m3 => .m3,
                    .m5 => .m5,
                    .m15 => .m15,
                    .m30 => .m30,
                    .h1 => .h1,
                    .h2 => .h2,
                    .h4 => .h4,
                    .h6 => .h6,
                    .h8 => .h8,
                    .h12 => .h12,
                    .d1 => .d1,
                    .d3 => .d3,
                    .w1 => .w1,
                    .M1 => .M1,
                };
                bus.publish("bar.closed", .{
                    .candle = .{
                        .instrument_id = bar.symbol,
                        .timeframe = tf,
                        .open = bar.open.toFloat(),
                        .high = bar.high.toFloat(),
                        .low = bar.low.toFloat(),
                        .close = bar.close.toFloat(),
                        .volume = bar.volume.toFloat(),
                        .timestamp = bar.timestamp.millis * 1_000_000, // millis to nanos
                    },
                });
            }
        }
    }

    /// 获取最新 bar
    pub fn getLastBar(self: *const Cache, symbol: []const u8, timeframe: Timeframe) ?Bar {
        var buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{s}:{s}", .{ symbol, timeframe.toString() }) catch return null;

        if (self.bars.get(key[0..key.len])) |series| {
            return series.last();
        }
        return null;
    }

    /// 获取 bar 序列
    pub fn getBars(self: *const Cache, symbol: []const u8, timeframe: Timeframe) ?[]const Bar {
        var buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{s}:{s}", .{ symbol, timeframe.toString() }) catch return null;

        if (self.bars.get(key[0..key.len])) |series| {
            return series.bars.items;
        }
        return null;
    }

    // ========================================================================
    // Order 操作
    // ========================================================================

    /// 更新订单
    pub fn updateOrder(self: *Cache, order: *Order) !void {
        const result = try self.orders.getOrPut(order.order_id);

        if (!result.found_existing) {
            result.key_ptr.* = try self.allocator.dupe(u8, order.order_id);
        }

        result.value_ptr.* = order;
        self.stats.order_updates += 1;

        // 发布更新事件
        if (self.config.enable_notifications) {
            if (self.bus) |bus| {
                const side: message_bus.OrderEvent.Side = if (order.side == .buy) .buy else .sell;
                const order_type: message_bus.OrderEvent.OrderType = switch (order.order_type) {
                    .market => .market,
                    .limit => .limit,
                    else => .market,
                };
                const status: message_bus.OrderEvent.OrderStatus = switch (order.status) {
                    .pending => .pending,
                    .open => .submitted,
                    .partially_filled => .partially_filled,
                    .filled => .filled,
                    .cancelled => .cancelled,
                    .rejected => .rejected,
                };
                const order_id = order.client_order_id orelse "";
                bus.publish("order.update", .{
                    .order_submitted = .{
                        .order_id = order_id,
                        .instrument_id = order.pair.base,
                        .side = side,
                        .order_type = order_type,
                        .quantity = order.amount.toFloat(),
                        .status = status,
                        .price = if (order.price) |p| p.toFloat() else null,
                        .timestamp = order.updated_at.millis * 1_000_000, // millis to nanos
                    },
                });
            }
        }
    }

    /// 获取订单
    pub fn getOrder(self: *const Cache, order_id: []const u8) ?*Order {
        return self.orders.get(order_id);
    }

    /// 移除订单
    pub fn removeOrder(self: *Cache, order_id: []const u8) void {
        if (self.orders.fetchRemove(order_id)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    // ========================================================================
    // 工具方法
    // ========================================================================

    /// 获取统计信息
    pub fn getStats(self: *const Cache) Stats {
        return self.stats;
    }

    /// 清空所有缓存
    pub fn clear(self: *Cache) void {
        // 清空订单簿
        var ob_iter = self.orderbooks.iterator();
        while (ob_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.orderbooks.clearRetainingCapacity();

        // 清空仓位
        var pos_iter = self.positions.iterator();
        while (pos_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.positions.clearRetainingCapacity();

        // 清空余额
        var bal_iter = self.balances.iterator();
        while (bal_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.currency);
        }
        self.balances.clearRetainingCapacity();

        // 清空报价
        var quote_iter = self.quotes.iterator();
        while (quote_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.symbol);
        }
        self.quotes.clearRetainingCapacity();

        // 清空K线
        var bar_iter = self.bars.iterator();
        while (bar_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.bars.clearRetainingCapacity();

        // 清空订单
        var order_iter = self.orders.iterator();
        while (order_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.orders.clearRetainingCapacity();

        // 重置统计
        self.stats = .{};
    }

    /// 检查报价是否过期
    pub fn isQuoteExpired(self: *const Cache, symbol: []const u8) bool {
        if (self.quotes.get(symbol)) |quote| {
            const now = Timestamp.now();
            const age_ms = now.diffMs(quote.timestamp);
            return age_ms > @as(i64, @intCast(self.config.quote_expiry_ms));
        }
        return true; // 不存在视为过期
    }
};

// ============================================================================
// 测试
// ============================================================================

test "Cache: init and deinit" {
    const cache = Cache.init(std.testing.allocator, null, .{});
    var mutable_cache = cache;
    defer mutable_cache.deinit();

    try std.testing.expectEqual(@as(u64, 0), mutable_cache.stats.orderbook_updates);
}

test "Cache: quote operations" {
    var cache = Cache.init(std.testing.allocator, null, .{});
    defer cache.deinit();

    const quote = Quote{
        .symbol = "BTC-USDT",
        .bid = Decimal.fromInt(50000),
        .ask = Decimal.fromInt(50010),
        .bid_size = Decimal.fromInt(10),
        .ask_size = Decimal.fromInt(5),
        .timestamp = Timestamp.now(),
    };

    try cache.updateQuote(quote);

    const cached = cache.getQuote("BTC-USDT");
    try std.testing.expect(cached != null);
    try std.testing.expectEqual(Decimal.fromInt(50000), cached.?.bid);
    try std.testing.expectEqual(Decimal.fromInt(50010), cached.?.ask);
}

test "Cache: mid price calculation" {
    var cache = Cache.init(std.testing.allocator, null, .{});
    defer cache.deinit();

    const quote = Quote{
        .symbol = "ETH-USDT",
        .bid = Decimal.fromInt(3000),
        .ask = Decimal.fromInt(3010),
        .bid_size = Decimal.fromInt(10),
        .ask_size = Decimal.fromInt(5),
        .timestamp = Timestamp.now(),
    };

    try cache.updateQuote(quote);

    const mid = cache.getMidPrice("ETH-USDT");
    try std.testing.expect(mid != null);
    // Mid = (3000 + 3010) / 2 = 3005
    try std.testing.expectEqual(Decimal.fromInt(3005), mid.?);
}

test "Cache: balance operations" {
    var cache = Cache.init(std.testing.allocator, null, .{});
    defer cache.deinit();

    const balance = AccountBalance{
        .currency = "USDT",
        .total = Decimal.fromInt(10000),
        .available = Decimal.fromInt(8000),
        .locked = Decimal.fromInt(2000),
        .unrealized_pnl = Decimal.fromInt(100),
        .updated_at = Timestamp.now(),
    };

    try cache.updateBalance(balance);

    const cached = cache.getBalance("USDT");
    try std.testing.expect(cached != null);
    try std.testing.expectEqual(Decimal.fromInt(10000), cached.?.total);
    try std.testing.expectEqual(Decimal.fromInt(8000), cached.?.available);

    const available = cache.getAvailableBalance("USDT");
    try std.testing.expectEqual(Decimal.fromInt(8000), available);
}

test "Cache: stats tracking" {
    var cache = Cache.init(std.testing.allocator, null, .{});
    defer cache.deinit();

    const quote = Quote{
        .symbol = "BTC-USDT",
        .bid = Decimal.fromInt(50000),
        .ask = Decimal.fromInt(50010),
        .bid_size = Decimal.fromInt(10),
        .ask_size = Decimal.fromInt(5),
        .timestamp = Timestamp.now(),
    };

    try cache.updateQuote(quote);
    try cache.updateQuote(quote);
    try cache.updateQuote(quote);

    const stats = cache.getStats();
    try std.testing.expectEqual(@as(u64, 3), stats.quote_updates);
}

test "Cache: clear" {
    var cache = Cache.init(std.testing.allocator, null, .{});
    defer cache.deinit();

    const quote = Quote{
        .symbol = "BTC-USDT",
        .bid = Decimal.fromInt(50000),
        .ask = Decimal.fromInt(50010),
        .bid_size = Decimal.fromInt(10),
        .ask_size = Decimal.fromInt(5),
        .timestamp = Timestamp.now(),
    };

    try cache.updateQuote(quote);
    try std.testing.expect(cache.getQuote("BTC-USDT") != null);

    cache.clear();

    try std.testing.expect(cache.getQuote("BTC-USDT") == null);
    try std.testing.expectEqual(@as(u64, 0), cache.stats.quote_updates);
}

test "Quote: spread calculations" {
    const quote = Quote{
        .symbol = "BTC-USDT",
        .bid = Decimal.fromInt(50000),
        .ask = Decimal.fromInt(50100),
        .bid_size = Decimal.fromInt(10),
        .ask_size = Decimal.fromInt(5),
        .timestamp = Timestamp.now(),
    };

    // Spread = 50100 - 50000 = 100
    try std.testing.expectEqual(Decimal.fromInt(100), quote.spread());

    // Mid = (50000 + 50100) / 2 = 50050
    try std.testing.expectEqual(Decimal.fromInt(50050), quote.midPrice());
}

test "Bar: bullish and bearish" {
    const bullish = Bar{
        .symbol = "BTC",
        .timeframe = .h1,
        .open = Decimal.fromInt(50000),
        .high = Decimal.fromInt(51000),
        .low = Decimal.fromInt(49500),
        .close = Decimal.fromInt(50500),
        .volume = Decimal.fromInt(1000),
        .timestamp = Timestamp.now(),
        .is_closed = true,
    };

    try std.testing.expect(bullish.isBullish());
    try std.testing.expect(!bullish.isBearish());

    const bearish = Bar{
        .symbol = "BTC",
        .timeframe = .h1,
        .open = Decimal.fromInt(50000),
        .high = Decimal.fromInt(50500),
        .low = Decimal.fromInt(49000),
        .close = Decimal.fromInt(49500),
        .volume = Decimal.fromInt(1000),
        .timestamp = Timestamp.now(),
        .is_closed = true,
    };

    try std.testing.expect(!bearish.isBullish());
    try std.testing.expect(bearish.isBearish());
}

test "Timeframe: to seconds" {
    try std.testing.expectEqual(@as(u64, 60), Timeframe.m1.toSeconds());
    try std.testing.expectEqual(@as(u64, 300), Timeframe.m5.toSeconds());
    try std.testing.expectEqual(@as(u64, 3600), Timeframe.h1.toSeconds());
    try std.testing.expectEqual(@as(u64, 86400), Timeframe.d1.toSeconds());
}
