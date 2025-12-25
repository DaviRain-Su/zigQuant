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
                return try std.fmt.allocPrint(allocator, "{{\"method\":\"subscribe\",\"subscription\":{{\"type\":\"{s}\",\"coin\":\"{s}\",\"user\":\"{s}\"}}}}", .{ self.channel.toString(), coin, user });
            } else {
                return try std.fmt.allocPrint(allocator, "{{\"method\":\"subscribe\",\"subscription\":{{\"type\":\"{s}\",\"coin\":\"{s}\"}}}}", .{ self.channel.toString(), coin });
            }
        } else if (self.user) |user| {
            return try std.fmt.allocPrint(allocator, "{{\"method\":\"subscribe\",\"subscription\":{{\"type\":\"{s}\",\"user\":\"{s}\"}}}}", .{ self.channel.toString(), user });
        } else {
            return try std.fmt.allocPrint(allocator, "{{\"method\":\"subscribe\",\"subscription\":{{\"type\":\"{s}\"}}}}", .{self.channel.toString()});
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
            .error_msg => |data| {
                allocator.free(data.msg);
            },
            .unknown => |data| allocator.free(data),
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

test "Message: deinit allMids" {
    const allocator = std.testing.allocator;

    // Create a message with allocated data
    var mids = try allocator.alloc(AllMidsData.MidPrice, 2);
    mids[0] = .{
        .coin = try allocator.dupe(u8, "BTC"),
        .mid = Decimal.ZERO,
    };
    mids[1] = .{
        .coin = try allocator.dupe(u8, "ETH"),
        .mid = Decimal.ZERO,
    };

    const msg = Message{
        .allMids = .{ .mids = mids },
    };

    // Should not leak when deinit is called
    msg.deinit(allocator);
}

test "Message: deinit l2Book" {
    const allocator = std.testing.allocator;

    var bids = try allocator.alloc(L2BookData.Level, 2);
    bids[0] = .{ .px = Decimal.ZERO, .sz = Decimal.ZERO, .n = 1 };
    bids[1] = .{ .px = Decimal.ZERO, .sz = Decimal.ZERO, .n = 1 };

    var asks = try allocator.alloc(L2BookData.Level, 2);
    asks[0] = .{ .px = Decimal.ZERO, .sz = Decimal.ZERO, .n = 1 };
    asks[1] = .{ .px = Decimal.ZERO, .sz = Decimal.ZERO, .n = 1 };

    const msg = Message{
        .l2Book = .{
            .coin = try allocator.dupe(u8, "ETH"),
            .levels = .{ .bids = bids, .asks = asks },
            .timestamp = 0,
        },
    };

    msg.deinit(allocator);
}

test "Message: deinit trades" {
    const allocator = std.testing.allocator;

    var trades_list = try allocator.alloc(TradesData.Trade, 2);
    trades_list[0] = .{
        .px = Decimal.ZERO,
        .sz = Decimal.ZERO,
        .side = try allocator.dupe(u8, "A"),
        .time = 0,
        .hash = try allocator.dupe(u8, "0xabc"),
    };
    trades_list[1] = .{
        .px = Decimal.ZERO,
        .sz = Decimal.ZERO,
        .side = try allocator.dupe(u8, "B"),
        .time = 0,
        .hash = try allocator.dupe(u8, "0xdef"),
    };

    const msg = Message{
        .trades = .{
            .coin = try allocator.dupe(u8, "ETH"),
            .trades = trades_list,
        },
    };

    msg.deinit(allocator);
}

test "Message: deinit subscriptionResponse" {
    const allocator = std.testing.allocator;

    const msg = Message{
        .subscriptionResponse = .{
            .method = try allocator.dupe(u8, "subscribe"),
            .subscription = .{
                .type = try allocator.dupe(u8, "allMids"),
                .coin = try allocator.dupe(u8, "ETH"),
                .user = try allocator.dupe(u8, "0xabc123"),
            },
        },
    };

    msg.deinit(allocator);
}

test "Message: deinit subscriptionResponse with null coin and user" {
    const allocator = std.testing.allocator;

    const msg = Message{
        .subscriptionResponse = .{
            .method = try allocator.dupe(u8, "subscribe"),
            .subscription = .{
                .type = try allocator.dupe(u8, "allMids"),
                .coin = null,
                .user = null,
            },
        },
    };

    msg.deinit(allocator);
}

test "Message: deinit orderUpdate" {
    const allocator = std.testing.allocator;

    const msg = Message{
        .orderUpdate = .{
            .order = .{
                .oid = 12345,
                .coin = try allocator.dupe(u8, "ETH"),
                .side = try allocator.dupe(u8, "B"),
                .limitPx = Decimal.ZERO,
                .sz = Decimal.ZERO,
                .timestamp = 0,
                .origSz = Decimal.ZERO,
                .status = try allocator.dupe(u8, "open"),
            },
        },
    };

    msg.deinit(allocator);
}

test "Message: deinit userFill" {
    const allocator = std.testing.allocator;

    const msg = Message{
        .userFill = .{
            .coin = try allocator.dupe(u8, "ETH"),
            .px = Decimal.ZERO,
            .sz = Decimal.ZERO,
            .side = try allocator.dupe(u8, "B"),
            .time = 0,
            .oid = 12345,
            .tid = 67890,
            .fee = Decimal.ZERO,
            .feeToken = try allocator.dupe(u8, "USDC"),
            .closedPnl = Decimal.ZERO,
        },
    };

    msg.deinit(allocator);
}

test "Message: deinit user" {
    const allocator = std.testing.allocator;

    var asset_positions = try allocator.alloc(UserData.AssetPosition, 2);
    asset_positions[0] = .{
        .coin = try allocator.dupe(u8, "USDC"),
        .total = Decimal.ZERO,
        .hold = Decimal.ZERO,
    };
    asset_positions[1] = .{
        .coin = try allocator.dupe(u8, "ETH"),
        .total = Decimal.ZERO,
        .hold = Decimal.ZERO,
    };

    const msg = Message{
        .user = .{
            .positions = &.{},
            .assetPositions = asset_positions,
            .marginSummary = .{
                .accountValue = Decimal.ZERO,
                .totalNtlPos = Decimal.ZERO,
                .totalRawUsd = Decimal.ZERO,
                .totalMarginUsed = Decimal.ZERO,
                .withdrawable = Decimal.ZERO,
            },
        },
    };

    msg.deinit(allocator);
}

test "Message: deinit unknown" {
    const allocator = std.testing.allocator;

    const msg = Message{
        .unknown = try allocator.dupe(u8, "unknown data"),
    };

    msg.deinit(allocator);
}

test "Message: deinit error_msg" {
    const allocator = std.testing.allocator;

    const msg = Message{
        .error_msg = .{
            .code = 400,
            .msg = try allocator.dupe(u8, "Error message"),
        },
    };

    msg.deinit(allocator);
}
