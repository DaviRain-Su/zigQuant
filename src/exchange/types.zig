//! Exchange Types - Unified data types for all exchanges
//!
//! This module defines the unified data types used across all exchange connectors.
//! All exchanges must convert their native formats to these types.
//!
//! Design principles:
//! - Exchange-agnostic: Works for CEX, DEX, futures, spot
//! - Type-safe: Compile-time validation
//! - Efficient: Minimal allocations, use Decimal for precision
//! - Extensible: Easy to add new fields without breaking compatibility

const std = @import("std");
const Decimal = @import("../root.zig").Decimal;
const Timestamp = @import("../root.zig").Timestamp;

// ============================================================================
// Trading Pair
// ============================================================================

/// Trading pair (unified representation across all exchanges)
pub const TradingPair = struct {
    base: []const u8, // e.g. "BTC", "ETH"
    quote: []const u8, // e.g. "USDT", "USDC"

    /// Create a standard symbol string (BASE-QUOTE format)
    pub fn symbol(self: TradingPair, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s}-{s}", .{ self.base, self.quote });
    }

    /// Parse from symbol string
    /// Supports formats: "BTC-USDT", "BTC/USDT", "BTCUSDT" (tries to detect)
    pub fn fromSymbol(sym: []const u8) !TradingPair {
        // Try dash separator
        if (std.mem.indexOf(u8, sym, "-")) |idx| {
            return .{
                .base = sym[0..idx],
                .quote = sym[idx + 1 ..],
            };
        }

        // Try slash separator
        if (std.mem.indexOf(u8, sym, "/")) |idx| {
            return .{
                .base = sym[0..idx],
                .quote = sym[idx + 1 ..],
            };
        }

        // No separator found - cannot parse
        return error.InvalidSymbolFormat;
    }

    /// Compare two trading pairs
    pub fn eql(self: TradingPair, other: TradingPair) bool {
        return std.mem.eql(u8, self.base, other.base) and
            std.mem.eql(u8, self.quote, other.quote);
    }
};

// ============================================================================
// Timeframe
// ============================================================================

/// Trading timeframe (candle interval)
/// Represents the duration of each candle in historical data and live trading
pub const Timeframe = enum {
    m1, // 1 minute
    m5, // 5 minutes
    m15, // 15 minutes
    m30, // 30 minutes
    h1, // 1 hour
    h4, // 4 hours
    d1, // 1 day
    w1, // 1 week

    /// Convert to string representation
    pub fn toString(self: Timeframe) []const u8 {
        return switch (self) {
            .m1 => "1m",
            .m5 => "5m",
            .m15 => "15m",
            .m30 => "30m",
            .h1 => "1h",
            .h4 => "4h",
            .d1 => "1d",
            .w1 => "1w",
        };
    }

    /// Parse from string representation
    pub fn fromString(s: []const u8) !Timeframe {
        if (std.mem.eql(u8, s, "1m")) return .m1;
        if (std.mem.eql(u8, s, "5m")) return .m5;
        if (std.mem.eql(u8, s, "15m")) return .m15;
        if (std.mem.eql(u8, s, "30m")) return .m30;
        if (std.mem.eql(u8, s, "1h")) return .h1;
        if (std.mem.eql(u8, s, "4h")) return .h4;
        if (std.mem.eql(u8, s, "1d")) return .d1;
        if (std.mem.eql(u8, s, "1w")) return .w1;
        return error.InvalidTimeframe;
    }

    /// Convert to minutes (for calculations and comparisons)
    pub fn toMinutes(self: Timeframe) u32 {
        return switch (self) {
            .m1 => 1,
            .m5 => 5,
            .m15 => 15,
            .m30 => 30,
            .h1 => 60,
            .h4 => 240,
            .d1 => 1440,
            .w1 => 10080,
        };
    }

    /// Convert to seconds (for timestamp calculations)
    pub fn toSeconds(self: Timeframe) u32 {
        return self.toMinutes() * 60;
    }

    /// Compare two timeframes
    /// Returns true if self is shorter than other
    pub fn isShorterThan(self: Timeframe, other: Timeframe) bool {
        return self.toMinutes() < other.toMinutes();
    }
};

// ============================================================================
// Order Side
// ============================================================================

/// Order side (buy or sell)
pub const Side = enum {
    buy,
    sell,

    pub fn toString(self: Side) []const u8 {
        return switch (self) {
            .buy => "buy",
            .sell => "sell",
        };
    }

    pub fn fromString(s: []const u8) !Side {
        if (std.mem.eql(u8, s, "buy")) return .buy;
        if (std.mem.eql(u8, s, "sell")) return .sell;
        return error.InvalidSide;
    }
};

// ============================================================================
// Order Type
// ============================================================================

/// Order type
pub const OrderType = enum {
    limit,
    market,

    pub fn toString(self: OrderType) []const u8 {
        return switch (self) {
            .limit => "limit",
            .market => "market",
        };
    }

    pub fn fromString(s: []const u8) !OrderType {
        if (std.mem.eql(u8, s, "limit")) return .limit;
        if (std.mem.eql(u8, s, "market")) return .market;
        return error.InvalidOrderType;
    }
};

// ============================================================================
// Time In Force
// ============================================================================

/// Time-in-force options
pub const TimeInForce = enum {
    gtc, // Good-til-Cancel (default for most exchanges)
    ioc, // Immediate-or-Cancel
    alo, // Add-Liquidity-Only (Post-only, Hyperliquid terminology)
    fok, // Fill-or-Kill (not supported by Hyperliquid in MVP)

    pub fn toString(self: TimeInForce) []const u8 {
        return switch (self) {
            .gtc => "Gtc",
            .ioc => "Ioc",
            .alo => "Alo",
            .fok => "Fok",
        };
    }

    pub fn fromString(s: []const u8) !TimeInForce {
        if (std.mem.eql(u8, s, "Gtc")) return .gtc;
        if (std.mem.eql(u8, s, "Ioc")) return .ioc;
        if (std.mem.eql(u8, s, "Alo")) return .alo;
        if (std.mem.eql(u8, s, "Fok")) return .fok;
        return error.InvalidTimeInForce;
    }
};

// ============================================================================
// Order Status
// ============================================================================

/// Order status (unified across exchanges)
pub const OrderStatus = enum {
    pending, // Order created but not yet submitted to exchange
    open, // Order is active on exchange
    filled, // Order completely filled
    partially_filled, // Order partially filled
    cancelled, // Order cancelled
    rejected, // Order rejected by exchange

    pub fn toString(self: OrderStatus) []const u8 {
        return switch (self) {
            .pending => "pending",
            .open => "open",
            .filled => "filled",
            .partially_filled => "partially_filled",
            .cancelled => "cancelled",
            .rejected => "rejected",
        };
    }

    pub fn fromString(s: []const u8) !OrderStatus {
        if (std.mem.eql(u8, s, "pending")) return .pending;
        if (std.mem.eql(u8, s, "open")) return .open;
        if (std.mem.eql(u8, s, "filled")) return .filled;
        if (std.mem.eql(u8, s, "partially_filled")) return .partially_filled;
        if (std.mem.eql(u8, s, "cancelled")) return .cancelled;
        if (std.mem.eql(u8, s, "rejected")) return .rejected;
        return error.InvalidOrderStatus;
    }
};

// ============================================================================
// Order Request
// ============================================================================

/// Unified order request (for creating orders)
pub const OrderRequest = struct {
    pair: TradingPair,
    side: Side,
    order_type: OrderType,
    amount: Decimal,
    price: ?Decimal = null, // null for market orders
    time_in_force: TimeInForce = .gtc,
    reduce_only: bool = false,
    client_order_id: ?[]const u8 = null,

    /// Validate order request
    pub fn validate(self: OrderRequest) !void {
        // Amount must be positive
        if (!self.amount.isPositive()) {
            return error.InvalidAmount;
        }

        // Limit orders must have a price
        if (self.order_type == .limit and self.price == null) {
            return error.LimitOrderRequiresPrice;
        }

        // Market orders should not have a price
        if (self.order_type == .market and self.price != null) {
            return error.MarketOrderShouldNotHavePrice;
        }

        // Price (if provided) must be positive
        if (self.price) |p| {
            if (!p.isPositive()) {
                return error.InvalidPrice;
            }
        }
    }
};

// ============================================================================
// Order Response
// ============================================================================

/// Unified order response (from exchange)
pub const Order = struct {
    exchange_order_id: ?u64 = null, // Optional until exchange confirms
    client_order_id: ?[]const u8 = null,
    pair: TradingPair,
    side: Side,
    order_type: OrderType,
    status: OrderStatus,
    amount: Decimal,
    price: ?Decimal,
    filled_amount: Decimal,
    avg_fill_price: ?Decimal = null,
    created_at: Timestamp,
    updated_at: Timestamp,

    /// Calculate remaining amount
    pub fn remainingAmount(self: Order) Decimal {
        return self.amount.sub(self.filled_amount);
    }

    /// Check if order is complete
    pub fn isComplete(self: Order) bool {
        return self.status == .filled or self.status == .cancelled or self.status == .rejected;
    }

    /// Check if order is active
    pub fn isActive(self: Order) bool {
        return self.status == .open or self.status == .partially_filled;
    }
};

// ============================================================================
// Order Events (for WebSocket/real-time updates)
// ============================================================================

/// Order status update event (from WebSocket or polling)
pub const OrderUpdateEvent = struct {
    exchange_order_id: u64,
    status: OrderStatus,
    filled_amount: Decimal,
    avg_fill_price: ?Decimal = null,
    timestamp: Timestamp,
};

/// Order fill/execution event
pub const OrderFillEvent = struct {
    exchange_order_id: u64,
    fill_price: Decimal,
    fill_amount: Decimal,
    total_filled: Decimal, // Total filled amount after this fill
    timestamp: Timestamp,
};

// ============================================================================
// Ticker
// ============================================================================

/// Market ticker data
pub const Ticker = struct {
    pair: TradingPair,
    bid: Decimal,
    ask: Decimal,
    last: Decimal,
    volume_24h: Decimal,
    timestamp: Timestamp,

    /// Get mid price (average of bid and ask)
    pub fn midPrice(self: Ticker) Decimal {
        const sum = self.bid.add(self.ask);
        return sum.div(Decimal.fromInt(2)) catch Decimal.ZERO;
    }

    /// Get spread
    pub fn spread(self: Ticker) Decimal {
        return self.ask.sub(self.bid);
    }

    /// Get spread in basis points (0.01%)
    /// Formula: (spread / mid_price) * 10000
    pub fn spreadBps(self: Ticker) Decimal {
        const mid = self.midPrice();
        if (mid.isZero()) return Decimal.ZERO;

        const s = self.spread();
        const ratio = s.div(mid) catch return Decimal.ZERO;
        return ratio.mul(Decimal.fromInt(10000));
    }
};

// ============================================================================
// Orderbook Level
// ============================================================================

/// Single price level in orderbook
pub const OrderbookLevel = struct {
    price: Decimal,
    quantity: Decimal,
    num_orders: u32 = 1, // Some exchanges provide this

    /// Calculate notional value (price * quantity)
    pub fn notional(self: OrderbookLevel) Decimal {
        return self.price.mul(self.quantity);
    }
};

// ============================================================================
// Orderbook
// ============================================================================

/// L2 Orderbook (price level aggregated)
pub const Orderbook = struct {
    pair: TradingPair,
    bids: []OrderbookLevel, // Sorted highest to lowest
    asks: []OrderbookLevel, // Sorted lowest to highest
    timestamp: Timestamp,

    /// Free allocated memory
    pub fn deinit(self: Orderbook, allocator: std.mem.Allocator) void {
        allocator.free(self.bids);
        allocator.free(self.asks);
    }

    /// Get best bid
    pub fn getBestBid(self: Orderbook) ?OrderbookLevel {
        return if (self.bids.len > 0) self.bids[0] else null;
    }

    /// Get best ask
    pub fn getBestAsk(self: Orderbook) ?OrderbookLevel {
        return if (self.asks.len > 0) self.asks[0] else null;
    }

    /// Get mid price (average of best bid and best ask)
    pub fn getMidPrice(self: Orderbook) ?Decimal {
        const best_bid = self.getBestBid() orelse return null;
        const best_ask = self.getBestAsk() orelse return null;

        const sum = best_bid.price.add(best_ask.price);
        return sum.div(Decimal.fromInt(2)) catch null;
    }

    /// Get spread
    pub fn getSpread(self: Orderbook) ?Decimal {
        const best_bid = self.getBestBid() orelse return null;
        const best_ask = self.getBestAsk() orelse return null;

        return best_ask.price.sub(best_bid.price);
    }
};

// ============================================================================
// Balance
// ============================================================================

/// Account balance for a single asset
pub const Balance = struct {
    asset: []const u8, // e.g. "USDC", "BTC"
    total: Decimal, // Total balance
    available: Decimal, // Available for trading
    locked: Decimal, // Locked in orders/positions

    /// Validate balance consistency
    pub fn validate(self: Balance) !void {
        // total = available + locked
        const sum = self.available.add(self.locked);
        if (!sum.eql(self.total)) {
            return error.BalanceInconsistent;
        }
    }
};

// ============================================================================
// Position
// ============================================================================

/// Trading position (for futures/perpetuals)
pub const Position = struct {
    pair: TradingPair,
    side: Side, // Long or Short
    size: Decimal, // Position size (always positive)
    entry_price: Decimal, // Average entry price
    mark_price: ?Decimal = null, // Current mark price
    liquidation_price: ?Decimal = null, // Liquidation price
    unrealized_pnl: Decimal, // Unrealized PnL
    leverage: u32, // Leverage multiplier
    margin_used: Decimal, // Margin used for position

    /// Calculate PnL percentage
    pub fn pnlPercent(self: Position) ?Decimal {
        const notional = self.entry_price.mul(self.size);
        if (notional.isZero()) return null;

        return self.unrealized_pnl.div(notional) catch null;
    }

    /// Check if position is long
    pub fn isLong(self: Position) bool {
        return self.side == .buy;
    }

    /// Check if position is short
    pub fn isShort(self: Position) bool {
        return self.side == .sell;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "TradingPair: symbol generation" {
    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };

    const sym = try pair.symbol(std.testing.allocator);
    defer std.testing.allocator.free(sym);

    try std.testing.expectEqualStrings("BTC-USDT", sym);
}

test "TradingPair: fromSymbol" {
    const pair1 = try TradingPair.fromSymbol("BTC-USDT");
    try std.testing.expectEqualStrings("BTC", pair1.base);
    try std.testing.expectEqualStrings("USDT", pair1.quote);

    const pair2 = try TradingPair.fromSymbol("ETH/USDC");
    try std.testing.expectEqualStrings("ETH", pair2.base);
    try std.testing.expectEqualStrings("USDC", pair2.quote);

    // Invalid format should error
    const result = TradingPair.fromSymbol("INVALID");
    try std.testing.expectError(error.InvalidSymbolFormat, result);
}

test "TradingPair: equality" {
    const pair1 = TradingPair{ .base = "BTC", .quote = "USDT" };
    const pair2 = TradingPair{ .base = "BTC", .quote = "USDT" };
    const pair3 = TradingPair{ .base = "ETH", .quote = "USDT" };

    try std.testing.expect(pair1.eql(pair2));
    try std.testing.expect(!pair1.eql(pair3));
}

test "Timeframe: string conversion" {
    try std.testing.expectEqualStrings("1m", Timeframe.m1.toString());
    try std.testing.expectEqualStrings("5m", Timeframe.m5.toString());
    try std.testing.expectEqualStrings("15m", Timeframe.m15.toString());
    try std.testing.expectEqualStrings("1h", Timeframe.h1.toString());
    try std.testing.expectEqualStrings("1d", Timeframe.d1.toString());

    try std.testing.expectEqual(Timeframe.m1, try Timeframe.fromString("1m"));
    try std.testing.expectEqual(Timeframe.m5, try Timeframe.fromString("5m"));
    try std.testing.expectEqual(Timeframe.h1, try Timeframe.fromString("1h"));
    try std.testing.expectEqual(Timeframe.d1, try Timeframe.fromString("1d"));

    // Invalid timeframe should error
    const result = Timeframe.fromString("invalid");
    try std.testing.expectError(error.InvalidTimeframe, result);
}

test "Timeframe: toMinutes conversion" {
    try std.testing.expectEqual(@as(u32, 1), Timeframe.m1.toMinutes());
    try std.testing.expectEqual(@as(u32, 5), Timeframe.m5.toMinutes());
    try std.testing.expectEqual(@as(u32, 15), Timeframe.m15.toMinutes());
    try std.testing.expectEqual(@as(u32, 30), Timeframe.m30.toMinutes());
    try std.testing.expectEqual(@as(u32, 60), Timeframe.h1.toMinutes());
    try std.testing.expectEqual(@as(u32, 240), Timeframe.h4.toMinutes());
    try std.testing.expectEqual(@as(u32, 1440), Timeframe.d1.toMinutes());
    try std.testing.expectEqual(@as(u32, 10080), Timeframe.w1.toMinutes());
}

test "Timeframe: toSeconds conversion" {
    try std.testing.expectEqual(@as(u32, 60), Timeframe.m1.toSeconds());
    try std.testing.expectEqual(@as(u32, 300), Timeframe.m5.toSeconds());
    try std.testing.expectEqual(@as(u32, 3600), Timeframe.h1.toSeconds());
}

test "Timeframe: comparison" {
    try std.testing.expect(Timeframe.m1.isShorterThan(.m5));
    try std.testing.expect(Timeframe.m15.isShorterThan(.h1));
    try std.testing.expect(!Timeframe.h1.isShorterThan(.m15));
    try std.testing.expect(!Timeframe.m5.isShorterThan(.m5));
}

test "Side: string conversion" {
    try std.testing.expectEqualStrings("buy", Side.buy.toString());
    try std.testing.expectEqualStrings("sell", Side.sell.toString());

    try std.testing.expectEqual(Side.buy, try Side.fromString("buy"));
    try std.testing.expectEqual(Side.sell, try Side.fromString("sell"));
}

test "OrderRequest: validation" {
    const valid_limit = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromInt(1),
        .price = Decimal.fromInt(50000),
    };
    try valid_limit.validate();

    const invalid_amount = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.ZERO,
        .price = Decimal.fromInt(50000),
    };
    try std.testing.expectError(error.InvalidAmount, invalid_amount.validate());

    const limit_no_price = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.fromInt(1),
        .price = null,
    };
    try std.testing.expectError(error.LimitOrderRequiresPrice, limit_no_price.validate());
}

test "Order: remainingAmount" {
    const order = Order{
        .exchange_order_id = 12345,
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .status = .partially_filled,
        .amount = Decimal.fromInt(10),
        .price = Decimal.fromInt(50000),
        .filled_amount = Decimal.fromInt(3),
        .created_at = Timestamp.now(),
        .updated_at = Timestamp.now(),
    };

    const remaining = order.remainingAmount();
    try std.testing.expect((Decimal.fromInt(7)).eql(remaining));
}

test "Ticker: calculations" {
    const ticker = Ticker{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .bid = Decimal.fromInt(50000),
        .ask = Decimal.fromInt(50100),
        .last = Decimal.fromInt(50050),
        .volume_24h = Decimal.fromInt(1000),
        .timestamp = Timestamp.now(),
    };

    // Mid price should be (50000 + 50100) / 2 = 50050
    const mid = ticker.midPrice();
    try std.testing.expect((Decimal.fromInt(50050)).eql(mid));

    // Spread should be 50100 - 50000 = 100
    const s = ticker.spread();
    try std.testing.expect((Decimal.fromInt(100)).eql(s));
}

test "Orderbook: best prices" {
    var bids = [_]OrderbookLevel{
        .{ .price = Decimal.fromInt(50000), .quantity = Decimal.fromInt(10) },
        .{ .price = Decimal.fromInt(49900), .quantity = Decimal.fromInt(5) },
    };

    var asks = [_]OrderbookLevel{
        .{ .price = Decimal.fromInt(50100), .quantity = Decimal.fromInt(8) },
        .{ .price = Decimal.fromInt(50200), .quantity = Decimal.fromInt(3) },
    };

    const ob = Orderbook{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .bids = &bids,
        .asks = &asks,
        .timestamp = Timestamp.now(),
    };

    const best_bid = ob.getBestBid().?;
    try std.testing.expect((Decimal.fromInt(50000)).eql(best_bid.price));

    const best_ask = ob.getBestAsk().?;
    try std.testing.expect((Decimal.fromInt(50100)).eql(best_ask.price));
}

test "Balance: validation" {
    const valid = Balance{
        .asset = "USDC",
        .total = Decimal.fromInt(1000),
        .available = Decimal.fromInt(700),
        .locked = Decimal.fromInt(300),
    };
    try valid.validate();

    const invalid = Balance{
        .asset = "USDC",
        .total = Decimal.fromInt(1000),
        .available = Decimal.fromInt(700),
        .locked = Decimal.fromInt(200), // 700 + 200 != 1000
    };
    try std.testing.expectError(error.BalanceInconsistent, invalid.validate());
}

test "Position: calculations" {
    const pos = Position{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .size = Decimal.fromInt(1),
        .entry_price = Decimal.fromInt(50000),
        .unrealized_pnl = Decimal.fromInt(1000),
        .leverage = 10,
        .margin_used = Decimal.fromInt(5000),
    };

    try std.testing.expect(pos.isLong());
    try std.testing.expect(!pos.isShort());
}
