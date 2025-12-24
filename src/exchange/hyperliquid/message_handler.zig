//! WebSocket Message Handler
//!
//! Parses and dispatches WebSocket messages from Hyperliquid.

const std = @import("std");
const ws_types = @import("ws_types.zig");
const Message = ws_types.Message;
const Decimal = @import("../../core/decimal.zig").Decimal;

// ============================================================================
// Message Handler
// ============================================================================

pub const MessageHandler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MessageHandler {
        return .{
            .allocator = allocator,
        };
    }

    /// Parse a raw WebSocket message
    pub fn parse(self: *MessageHandler, raw: []const u8) !Message {
        // Parse JSON
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            raw,
            .{},
        ) catch {
            // Return raw message as unknown
            const copy = try self.allocator.dupe(u8, raw);
            return Message{ .unknown = copy };
        };
        defer parsed.deinit();

        const root = parsed.value;

        // Hyperliquid WS format: {"channel": "...", "data": {...}}
        if (root.object.get("channel")) |channel_value| {
            const channel = channel_value.string;

            // Get data field
            const data = root.object.get("data") orelse {
                const copy = try self.allocator.dupe(u8, raw);
                return Message{ .unknown = copy };
            };

            if (std.mem.eql(u8, channel, "subscriptionResponse")) {
                return try self.parseSubscriptionResponse(data);
            } else if (std.mem.eql(u8, channel, "allMids")) {
                return try self.parseAllMids(data);
            } else if (std.mem.eql(u8, channel, "l2Book")) {
                return try self.parseL2Book(data);
            } else if (std.mem.eql(u8, channel, "trades")) {
                return try self.parseTrades(data);
            } else if (std.mem.eql(u8, channel, "user")) {
                return try self.parseUser(data);
            } else if (std.mem.eql(u8, channel, "orderUpdates")) {
                return try self.parseOrderUpdate(data);
            } else if (std.mem.eql(u8, channel, "userFills")) {
                return try self.parseUserFill(data);
            }
        }

        // Check for error
        if (root.object.get("error")) |_| {
            return try self.parseError(root);
        }

        // Unknown message type
        const copy = try self.allocator.dupe(u8, raw);
        return Message{ .unknown = copy };
    }

    // ------------------------------------------------------------------------
    // Parser implementations (stubs for now)
    // ------------------------------------------------------------------------

    fn parseAllMids(self: *MessageHandler, data: std.json.Value) !Message {
        // data has structure: {"mids": {"BTC": "50000.0", "ETH": "3000.0", ...}}
        const data_obj = data.object;
        const mids_value = data_obj.get("mids") orelse return error.InvalidFormat;
        const mids_obj = mids_value.object;

        var mids_list = try self.allocator.alloc(ws_types.AllMidsData.MidPrice, mids_obj.count());

        var i: usize = 0;
        var iter = mids_obj.iterator();
        while (iter.next()) |entry| : (i += 1) {
            const coin = try self.allocator.dupe(u8, entry.key_ptr.*);
            const price_str = entry.value_ptr.*.string;

            mids_list[i] = .{
                .coin = coin,
                .mid = Decimal.fromString(price_str) catch Decimal.ZERO,
            };
        }

        return Message{
            .allMids = .{
                .mids = mids_list,
            },
        };
    }

    fn parseL2Book(self: *MessageHandler, data: std.json.Value) !Message {
        // Example: {"coin":"ETH","time":1234567890,"levels":[[{"px":"3000.0","sz":"1.5","n":2},...],[...]]}
        const obj = data.object;
        const coin_str = obj.get("coin").?.string;
        const coin = try self.allocator.dupe(u8, coin_str);
        const time = obj.get("time").?.integer;
        const levels = obj.get("levels").?.array;

        // levels[0] = bids, levels[1] = asks
        const bids_array = levels.items[0].array;
        const asks_array = levels.items[1].array;

        var bids = try self.allocator.alloc(ws_types.L2BookData.Level, bids_array.items.len);
        for (bids_array.items, 0..) |level, i| {
            const level_obj = level.object;
            bids[i] = .{
                .px = Decimal.fromString(level_obj.get("px").?.string) catch Decimal.ZERO,
                .sz = Decimal.fromString(level_obj.get("sz").?.string) catch Decimal.ZERO,
                .n = @intCast(level_obj.get("n").?.integer),
            };
        }

        var asks = try self.allocator.alloc(ws_types.L2BookData.Level, asks_array.items.len);
        for (asks_array.items, 0..) |level, i| {
            const level_obj = level.object;
            asks[i] = .{
                .px = Decimal.fromString(level_obj.get("px").?.string) catch Decimal.ZERO,
                .sz = Decimal.fromString(level_obj.get("sz").?.string) catch Decimal.ZERO,
                .n = @intCast(level_obj.get("n").?.integer),
            };
        }

        return Message{
            .l2Book = .{
                .coin = coin,
                .levels = .{
                    .bids = bids,
                    .asks = asks,
                },
                .timestamp = time,
            },
        };
    }

    fn parseTrades(self: *MessageHandler, data: std.json.Value) !Message {
        // Example: [{"coin":"ETH","side":"A","px":"3000.0","sz":"1.5","time":1234567890,"hash":"0x..."}]
        const trades_array = data.array;
        if (trades_array.items.len == 0) {
            return Message{
                .trades = .{
                    .coin = try self.allocator.dupe(u8, "UNKNOWN"),
                    .trades = &.{},
                },
            };
        }

        // Get coin from first trade
        const first_trade = trades_array.items[0].object;
        const coin_str = first_trade.get("coin").?.string;
        const coin = try self.allocator.dupe(u8, coin_str);

        var trades_list = try self.allocator.alloc(ws_types.TradesData.Trade, trades_array.items.len);

        for (trades_array.items, 0..) |trade_value, i| {
            const trade_obj = trade_value.object;
            const px_str = trade_obj.get("px").?.string;
            const sz_str = trade_obj.get("sz").?.string;
            const side_str = trade_obj.get("side").?.string;
            const hash_str = trade_obj.get("hash").?.string;

            trades_list[i] = .{
                .px = Decimal.fromString(px_str) catch Decimal.ZERO,
                .sz = Decimal.fromString(sz_str) catch Decimal.ZERO,
                .side = try self.allocator.dupe(u8, side_str),
                .time = trade_obj.get("time").?.integer,
                .hash = try self.allocator.dupe(u8, hash_str),
            };
        }

        return Message{
            .trades = .{
                .coin = coin,
                .trades = trades_list,
            },
        };
    }

    fn parseUser(self: *MessageHandler, data: std.json.Value) !Message {
        // Parse user clearinghouse state message
        const obj = data.object;

        // Parse assetPositions
        const asset_positions_array = obj.get("assetPositions").?.array;
        var asset_positions = try self.allocator.alloc(ws_types.UserData.AssetPosition, asset_positions_array.items.len);

        for (asset_positions_array.items, 0..) |ap_value, i| {
            const ap_obj = ap_value.object;
            const position = ap_obj.get("position").?.object;

            const coin_str = position.get("coin").?.string;
            const total_str = position.get("positionValue").?.string;
            const margin_str = position.get("marginUsed").?.string;

            asset_positions[i] = .{
                .coin = try self.allocator.dupe(u8, coin_str),
                .total = Decimal.fromString(total_str) catch Decimal.ZERO,
                .hold = Decimal.fromString(margin_str) catch Decimal.ZERO,
            };
        }

        // Parse marginSummary
        const margin_obj = obj.get("marginSummary").?.object;
        const account_value_str = margin_obj.get("accountValue").?.string;
        const total_ntl_str = margin_obj.get("totalNtlPos").?.string;
        const total_raw_str = margin_obj.get("totalRawUsd").?.string;
        const margin_used_str = margin_obj.get("totalMarginUsed").?.string;

        const withdrawable_str = obj.get("withdrawable").?.string;

        return Message{
            .user = .{
                .positions = &.{}, // Positions are in assetPositions
                .assetPositions = asset_positions,
                .marginSummary = .{
                    .accountValue = Decimal.fromString(account_value_str) catch Decimal.ZERO,
                    .totalNtlPos = Decimal.fromString(total_ntl_str) catch Decimal.ZERO,
                    .totalRawUsd = Decimal.fromString(total_raw_str) catch Decimal.ZERO,
                    .totalMarginUsed = Decimal.fromString(margin_used_str) catch Decimal.ZERO,
                    .withdrawable = Decimal.fromString(withdrawable_str) catch Decimal.ZERO,
                },
            },
        };
    }

    fn parseOrderUpdate(self: *MessageHandler, data: std.json.Value) !Message {
        // Parse order update message
        // Format: { order: {...}, status: string, statusTimestamp: number, user: string }
        const data_obj = data.object;
        const order_obj = data_obj.get("order").?.object;
        const status_str = data_obj.get("status").?.string; // Status is at data level, not order level

        const coin_str = order_obj.get("coin").?.string;
        const side_str = order_obj.get("side").?.string;
        const limit_px_str = order_obj.get("limitPx").?.string;
        const sz_str = order_obj.get("sz").?.string;
        const orig_sz_str = order_obj.get("origSz").?.string;

        return Message{
            .orderUpdate = .{
                .order = .{
                    .oid = @intCast(order_obj.get("oid").?.integer),
                    .coin = try self.allocator.dupe(u8, coin_str),
                    .side = try self.allocator.dupe(u8, side_str),
                    .limitPx = Decimal.fromString(limit_px_str) catch Decimal.ZERO,
                    .sz = Decimal.fromString(sz_str) catch Decimal.ZERO,
                    .timestamp = order_obj.get("timestamp").?.integer,
                    .origSz = Decimal.fromString(orig_sz_str) catch Decimal.ZERO,
                    .status = try self.allocator.dupe(u8, status_str),
                },
            },
        };
    }

    fn parseUserFill(self: *MessageHandler, data: std.json.Value) !Message {
        // Parse user fill message
        // Format: { coin, px, sz, side, time, startPosition, dir, closedPnl, hash, oid, crossed, fee, tid, feeToken? }
        const fill_obj = data.object;

        const coin_str = fill_obj.get("coin").?.string;
        const side_str = fill_obj.get("side").?.string;
        const px_str = fill_obj.get("px").?.string;
        const sz_str = fill_obj.get("sz").?.string;
        const fee_str = fill_obj.get("fee").?.string;
        const closed_pnl_str = fill_obj.get("closedPnl").?.string;

        // feeToken is optional (default to "USDC" if not present)
        const fee_token_str = if (fill_obj.get("feeToken")) |ft| ft.string else "USDC";

        return Message{
            .userFill = .{
                .coin = try self.allocator.dupe(u8, coin_str),
                .px = Decimal.fromString(px_str) catch Decimal.ZERO,
                .sz = Decimal.fromString(sz_str) catch Decimal.ZERO,
                .side = try self.allocator.dupe(u8, side_str),
                .time = fill_obj.get("time").?.integer,
                .oid = @intCast(fill_obj.get("oid").?.integer),
                .tid = @intCast(fill_obj.get("tid").?.integer),
                .fee = Decimal.fromString(fee_str) catch Decimal.ZERO,
                .feeToken = try self.allocator.dupe(u8, fee_token_str),
                .closedPnl = Decimal.fromString(closed_pnl_str) catch Decimal.ZERO,
            },
        };
    }

    fn parseSubscriptionResponse(self: *MessageHandler, data: std.json.Value) !Message {
        const obj = data.object;
        const method_str = obj.get("method").?.string;
        const method = try self.allocator.dupe(u8, method_str);

        const sub = obj.get("subscription").?.object;
        const sub_type_str = sub.get("type").?.string;
        const sub_type = try self.allocator.dupe(u8, sub_type_str);

        const coin = if (sub.get("coin")) |c| try self.allocator.dupe(u8, c.string) else null;
        const user = if (sub.get("user")) |u| try self.allocator.dupe(u8, u.string) else null;

        return Message{
            .subscriptionResponse = .{
                .method = method,
                .subscription = .{
                    .type = sub_type,
                    .coin = coin,
                    .user = user,
                },
            },
        };
    }

    fn parseError(self: *MessageHandler, root: std.json.Value) !Message {
        const error_obj = root.object.get("error").?.object;
        const code = if (error_obj.get("code")) |c| @as(i32, @intCast(c.integer)) else -1;
        const msg_str = if (error_obj.get("message")) |m| m.string else "Unknown error";

        return Message{
            .error_msg = .{
                .code = code,
                .msg = try self.allocator.dupe(u8, msg_str),
            },
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "MessageHandler: parse subscription response" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"channel":"subscriptionResponse","data":{"method":"subscribe","subscription":{"type":"allMids"}}}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .subscriptionResponse);
    try std.testing.expectEqualStrings("subscribe", msg.subscriptionResponse.method);
    try std.testing.expectEqualStrings("allMids", msg.subscriptionResponse.subscription.type);
}

test "MessageHandler: parse unknown message" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw = "{\"unknown\":\"data\"}";
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .unknown);
}

test "MessageHandler: parse allMids" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"channel":"allMids","data":{"mids":{"BTC":"50000.5","ETH":"3000.25"}}}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .allMids);
    try std.testing.expectEqual(@as(usize, 2), msg.allMids.mids.len);

    // Check that coins are present (order may vary due to HashMap)
    var found_btc = false;
    var found_eth = false;
    for (msg.allMids.mids) |mid| {
        if (std.mem.eql(u8, mid.coin, "BTC")) {
            found_btc = true;
            try std.testing.expect(mid.mid.value == 50000_500000000000000000);
        } else if (std.mem.eql(u8, mid.coin, "ETH")) {
            found_eth = true;
            try std.testing.expect(mid.mid.value == 3000_250000000000000000);
        }
    }
    try std.testing.expect(found_btc);
    try std.testing.expect(found_eth);
}

test "MessageHandler: parse l2Book" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"channel":"l2Book","data":{"coin":"ETH","time":1234567890,"levels":[[{"px":"3000.0","sz":"1.5","n":2},{"px":"2999.0","sz":"2.0","n":1}],[{"px":"3001.0","sz":"1.0","n":1},{"px":"3002.0","sz":"0.5","n":1}]]}}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .l2Book);
    try std.testing.expectEqualStrings("ETH", msg.l2Book.coin);
    try std.testing.expectEqual(@as(i64, 1234567890), msg.l2Book.timestamp);

    // Check bids
    try std.testing.expectEqual(@as(usize, 2), msg.l2Book.levels.bids.len);
    try std.testing.expect(msg.l2Book.levels.bids[0].px.value == 3000_000000000000000000);
    try std.testing.expect(msg.l2Book.levels.bids[0].sz.value == 1_500000000000000000);
    try std.testing.expectEqual(@as(u32, 2), msg.l2Book.levels.bids[0].n);

    // Check asks
    try std.testing.expectEqual(@as(usize, 2), msg.l2Book.levels.asks.len);
    try std.testing.expect(msg.l2Book.levels.asks[0].px.value == 3001_000000000000000000);
    try std.testing.expect(msg.l2Book.levels.asks[0].sz.value == 1_000000000000000000);
}

test "MessageHandler: parse trades" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"channel":"trades","data":[{"coin":"ETH","side":"A","px":"3000.0","sz":"1.5","time":1234567890,"hash":"0xabc123"},{"coin":"ETH","side":"B","px":"2999.5","sz":"2.0","time":1234567891,"hash":"0xdef456"}]}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .trades);
    try std.testing.expectEqualStrings("ETH", msg.trades.coin);
    try std.testing.expectEqual(@as(usize, 2), msg.trades.trades.len);

    // First trade
    try std.testing.expectEqualStrings("A", msg.trades.trades[0].side);
    try std.testing.expect(msg.trades.trades[0].px.value == 3000_000000000000000000);
    try std.testing.expect(msg.trades.trades[0].sz.value == 1_500000000000000000);
    try std.testing.expectEqual(@as(i64, 1234567890), msg.trades.trades[0].time);
    try std.testing.expectEqualStrings("0xabc123", msg.trades.trades[0].hash);

    // Second trade
    try std.testing.expectEqualStrings("B", msg.trades.trades[1].side);
    try std.testing.expect(msg.trades.trades[1].px.value == 2999_500000000000000000);
}

test "MessageHandler: parse user data" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"channel":"user","data":{"assetPositions":[{"position":{"coin":"USDC","positionValue":"10000.0","marginUsed":"0.0"}},{"position":{"coin":"ETH","positionValue":"5000.0","marginUsed":"500.0"}}],"marginSummary":{"accountValue":"15000.0","totalNtlPos":"5000.0","totalRawUsd":"10000.0","totalMarginUsed":"500.0"},"withdrawable":"9500.0"}}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .user);

    // Check asset positions
    try std.testing.expectEqual(@as(usize, 2), msg.user.assetPositions.len);
    try std.testing.expectEqualStrings("USDC", msg.user.assetPositions[0].coin);
    try std.testing.expect(msg.user.assetPositions[0].total.value == 10000_000000000000000000);

    try std.testing.expectEqualStrings("ETH", msg.user.assetPositions[1].coin);
    try std.testing.expect(msg.user.assetPositions[1].total.value == 5000_000000000000000000);
    try std.testing.expect(msg.user.assetPositions[1].hold.value == 500_000000000000000000);

    // Check margin summary
    try std.testing.expect(msg.user.marginSummary.accountValue.value == 15000_000000000000000000);
    try std.testing.expect(msg.user.marginSummary.totalNtlPos.value == 5000_000000000000000000);
    try std.testing.expect(msg.user.marginSummary.totalRawUsd.value == 10000_000000000000000000);
    try std.testing.expect(msg.user.marginSummary.totalMarginUsed.value == 500_000000000000000000);
    try std.testing.expect(msg.user.marginSummary.withdrawable.value == 9500_000000000000000000);
}

test "MessageHandler: parse orderUpdate" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"channel":"orderUpdates","data":{"order":{"oid":12345,"coin":"ETH","side":"B","limitPx":"3000.0","sz":"1.0","timestamp":1234567890,"origSz":"1.5"},"status":"open","statusTimestamp":1234567890,"user":"0xabc123"}}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .orderUpdate);
    try std.testing.expectEqual(@as(u64, 12345), msg.orderUpdate.order.oid);
    try std.testing.expectEqualStrings("ETH", msg.orderUpdate.order.coin);
    try std.testing.expectEqualStrings("B", msg.orderUpdate.order.side);
    try std.testing.expect(msg.orderUpdate.order.limitPx.value == 3000_000000000000000000);
    try std.testing.expect(msg.orderUpdate.order.sz.value == 1_000000000000000000);
    try std.testing.expectEqual(@as(i64, 1234567890), msg.orderUpdate.order.timestamp);
    try std.testing.expect(msg.orderUpdate.order.origSz.value == 1_500000000000000000);
    try std.testing.expectEqualStrings("open", msg.orderUpdate.order.status);
}

test "MessageHandler: parse userFill" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"channel":"userFills","data":{"coin":"ETH","px":"3000.0","sz":"1.0","side":"B","time":1234567890,"oid":12345,"tid":67890,"fee":"3.0","feeToken":"USDC","closedPnl":"100.5"}}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .userFill);
    try std.testing.expectEqualStrings("ETH", msg.userFill.coin);
    try std.testing.expect(msg.userFill.px.value == 3000_000000000000000000);
    try std.testing.expect(msg.userFill.sz.value == 1_000000000000000000);
    try std.testing.expectEqualStrings("B", msg.userFill.side);
    try std.testing.expectEqual(@as(i64, 1234567890), msg.userFill.time);
    try std.testing.expectEqual(@as(u64, 12345), msg.userFill.oid);
    try std.testing.expectEqual(@as(u64, 67890), msg.userFill.tid);
    try std.testing.expect(msg.userFill.fee.value == 3_000000000000000000);
    try std.testing.expectEqualStrings("USDC", msg.userFill.feeToken);
    try std.testing.expect(msg.userFill.closedPnl.value == 100_500000000000000000);
}

test "MessageHandler: parse userFill without feeToken" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"channel":"userFills","data":{"coin":"ETH","px":"3000.0","sz":"1.0","side":"B","time":1234567890,"oid":12345,"tid":67890,"fee":"3.0","closedPnl":"0.0"}}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .userFill);
    try std.testing.expectEqualStrings("USDC", msg.userFill.feeToken); // Default value
}

test "MessageHandler: parse error" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"error":{"code":400,"message":"Invalid request"}}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .error_msg);
    try std.testing.expectEqual(@as(i32, 400), msg.error_msg.code);
    try std.testing.expectEqualStrings("Invalid request", msg.error_msg.msg);
}

test "MessageHandler: parse subscription response with coin" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"channel":"subscriptionResponse","data":{"method":"subscribe","subscription":{"type":"l2Book","coin":"ETH"}}}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .subscriptionResponse);
    try std.testing.expectEqualStrings("subscribe", msg.subscriptionResponse.method);
    try std.testing.expectEqualStrings("l2Book", msg.subscriptionResponse.subscription.type);
    try std.testing.expect(msg.subscriptionResponse.subscription.coin != null);
    try std.testing.expectEqualStrings("ETH", msg.subscriptionResponse.subscription.coin.?);
}

test "MessageHandler: parse subscription response with user" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"channel":"subscriptionResponse","data":{"method":"subscribe","subscription":{"type":"user","user":"0xabc123"}}}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .subscriptionResponse);
    try std.testing.expect(msg.subscriptionResponse.subscription.user != null);
    try std.testing.expectEqualStrings("0xabc123", msg.subscriptionResponse.subscription.user.?);
}

test "MessageHandler: parse invalid JSON" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw = "not valid json {{{";
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .unknown);
    try std.testing.expectEqualStrings(raw, msg.unknown);
}

test "MessageHandler: parse empty trades array" {
    const allocator = std.testing.allocator;

    var handler = MessageHandler.init(allocator);

    const raw =
        \\{"channel":"trades","data":[]}
    ;
    const msg = try handler.parse(raw);
    defer msg.deinit(allocator);

    try std.testing.expect(msg == .trades);
    try std.testing.expectEqualStrings("UNKNOWN", msg.trades.coin);
    try std.testing.expectEqual(@as(usize, 0), msg.trades.trades.len);
}
