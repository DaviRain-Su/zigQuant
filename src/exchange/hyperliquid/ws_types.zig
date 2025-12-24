//! Hyperliquid WebSocket Types
//!
//! Defines message types for Hyperliquid WebSocket API.
//! Reference: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket

const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Timestamp = @import("../../core/time.zig").Timestamp;

// ============================================================================
// Subscription Types
// ============================================================================

/// WebSocket subscription channel
pub const Channel = enum {
    /// All markets mid prices (ticker data)
    allMids,
    /// L2 order book for a specific coin
    l2Book,
    /// Recent trades for a specific coin
    trades,
    /// User-specific data (orders, positions, fills)
    user,
    /// Order updates for user
    orderUpdates,
    /// User fills (execution history)
    userFills,
    /// User funding payments
    userFundings,
    /// User non-funding ledger updates
    userNonFundingLedgerUpdates,

    pub fn toString(self: Channel) []const u8 {
        return switch (self) {
            .allMids => "allMids",
            .l2Book => "l2Book",
            .trades => "trades",
            .user => "user",
            .orderUpdates => "orderUpdates",
            .userFills => "userFills",
            .userFundings => "userFundings",
            .userNonFundingLedgerUpdates => "userNonFundingLedgerUpdates",
        };
    }
};

/// Subscription request
pub const Subscription = struct {
    channel: Channel,
    coin: ?[]const u8 = null, // Required for l2Book, trades
    user: ?[]const u8 = null, // Required for user-specific channels

    /// Convert subscription to JSON
    pub fn toJSON(self: Subscription, allocator: std.mem.Allocator) ![]u8 {
        // Build JSON string using allocPrint
        if (self.coin) |coin| {
            if (self.user) |user| {
                return try std.fmt.allocPrint(allocator,
                    "{{\"method\":\"subscribe\",\"subscription\":{{\"type\":\"{s}\",\"coin\":\"{s}\",\"user\":\"{s}\"}}}}",
                    .{self.channel.toString(), coin, user});
            } else {
                return try std.fmt.allocPrint(allocator,
                    "{{\"method\":\"subscribe\",\"subscription\":{{\"type\":\"{s}\",\"coin\":\"{s}\"}}}}",
                    .{self.channel.toString(), coin});
            }
        } else if (self.user) |user| {
            return try std.fmt.allocPrint(allocator,
                "{{\"method\":\"subscribe\",\"subscription\":{{\"type\":\"{s}\",\"user\":\"{s}\"}}}}",
                .{self.channel.toString(), user});
        } else {
            return try std.fmt.allocPrint(allocator,
                "{{\"method\":\"subscribe\",\"subscription\":{{\"type\":\"{s}\"}}}}",
                .{self.channel.toString()});
        }
    }
};

// ============================================================================
// Message Types
// ============================================================================

/// WebSocket message (inbound)
pub const Message = union(enum) {
    allMids: AllMidsData,
    l2Book: L2BookData,
    trades: TradesData,
    user: UserData,
    orderUpdate: OrderUpdateData,
    userFill: UserFillData,
    subscriptionResponse: SubscriptionResponse,
    error_msg: ErrorMessage,
    unknown: []const u8,

    pub fn deinit(self: Message, allocator: std.mem.Allocator) void {
        switch (self) {
            .allMids => |data| {
                for (data.mids) |mid| {
                    allocator.free(mid.coin);
                }
                allocator.free(data.mids);
            },
            .l2Book => |data| {
                allocator.free(data.coin);
                allocator.free(data.levels.bids);
                allocator.free(data.levels.asks);
            },
            .trades => |data| {
                allocator.free(data.coin);
                for (data.trades) |trade| {
                    allocator.free(trade.side);
                    allocator.free(trade.hash);
                }
                allocator.free(data.trades);
            },
            .subscriptionResponse => |data| {
                allocator.free(data.method);
                allocator.free(data.subscription.type);
                if (data.subscription.coin) |coin| allocator.free(coin);
                if (data.subscription.user) |user| allocator.free(user);
            },
            .orderUpdate => |data| {
                allocator.free(data.order.coin);
                allocator.free(data.order.side);
                allocator.free(data.order.status);
            },
            .userFill => |data| {
                allocator.free(data.coin);
                allocator.free(data.side);
                allocator.free(data.feeToken);
            },
            .user => |data| {
                for (data.assetPositions) |ap| {
                    allocator.free(ap.coin);
                }
                allocator.free(data.assetPositions);
            },
            .unknown => |data| allocator.free(data),
            else => {},
        }
    }
};

/// AllMids message data
pub const AllMidsData = struct {
    mids: []MidPrice,

    pub const MidPrice = struct {
        coin: []const u8,
        mid: Decimal,
    };
};

/// L2 Book message data
pub const L2BookData = struct {
    coin: []const u8,
    levels: OrderbookLevels,
    timestamp: i64,

    pub const OrderbookLevels = struct {
        bids: []Level,
        asks: []Level,
    };

    pub const Level = struct {
        px: Decimal, // Price
        sz: Decimal, // Size
        n: u32, // Number of orders
    };
};

/// Trades message data
pub const TradesData = struct {
    coin: []const u8,
    trades: []Trade,

    pub const Trade = struct {
        px: Decimal, // Price
        sz: Decimal, // Size
        side: []const u8, // "A" (ask/sell) or "B" (bid/buy)
        time: i64, // Millisecond timestamp
        hash: []const u8, // Transaction hash
    };
};

/// User data message
pub const UserData = struct {
    positions: []Position,
    assetPositions: []AssetPosition,
    marginSummary: MarginSummary,

    pub const Position = struct {
        coin: []const u8,
        szi: Decimal, // Signed size (positive = long, negative = short)
        entryPx: Decimal,
        positionValue: Decimal,
        unrealizedPnl: Decimal,
        returnOnEquity: Decimal,
        leverage: Decimal,
        liquidationPx: ?Decimal,
    };

    pub const AssetPosition = struct {
        coin: []const u8,
        total: Decimal,
        hold: Decimal, // Locked in orders
    };

    pub const MarginSummary = struct {
        accountValue: Decimal,
        totalNtlPos: Decimal, // Total notional position
        totalRawUsd: Decimal,
        totalMarginUsed: Decimal,
        withdrawable: Decimal,
    };
};

/// Order update message
pub const OrderUpdateData = struct {
    order: Order,

    pub const Order = struct {
        oid: u64, // Order ID
        coin: []const u8,
        side: []const u8, // "A" or "B"
        limitPx: Decimal,
        sz: Decimal,
        timestamp: i64,
        origSz: Decimal, // Original size
        status: []const u8, // "open", "filled", "canceled", etc.
    };
};

/// User fill message
pub const UserFillData = struct {
    coin: []const u8,
    px: Decimal,
    sz: Decimal,
    side: []const u8,
    time: i64,
    oid: u64,
    tid: u64, // Trade ID
    fee: Decimal,
    feeToken: []const u8,
    closedPnl: Decimal,
};

/// Subscription response
pub const SubscriptionResponse = struct {
    method: []const u8,
    subscription: struct {
        type: []const u8,
        coin: ?[]const u8 = null,
        user: ?[]const u8 = null,
    },
};

/// Error message
pub const ErrorMessage = struct {
    code: i32,
    msg: []const u8,
};

// ============================================================================
// Tests
// ============================================================================

test "Subscription: allMids JSON" {
    const allocator = std.testing.allocator;

    const sub = Subscription{
        .channel = .allMids,
    };

    const json = try sub.toJSON(allocator);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"method\":\"subscribe\",\"subscription\":{\"type\":\"allMids\"}}",
        json,
    );
}

test "Subscription: l2Book with coin JSON" {
    const allocator = std.testing.allocator;

    const sub = Subscription{
        .channel = .l2Book,
        .coin = "ETH",
    };

    const json = try sub.toJSON(allocator);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"method\":\"subscribe\",\"subscription\":{\"type\":\"l2Book\",\"coin\":\"ETH\"}}",
        json,
    );
}

test "Subscription: user with address JSON" {
    const allocator = std.testing.allocator;

    const sub = Subscription{
        .channel = .user,
        .user = "0x1234567890abcdef",
    };

    const json = try sub.toJSON(allocator);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"method\":\"subscribe\",\"subscription\":{\"type\":\"user\",\"user\":\"0x1234567890abcdef\"}}",
        json,
    );
}
