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
        _ = self;
        const error_obj = root.object.get("error").?.object;
        const code = if (error_obj.get("code")) |c| @as(i32, @intCast(c.integer)) else -1;
        const msg = if (error_obj.get("message")) |m| m.string else "Unknown error";

        return Message{
            .error_msg = .{
                .code = code,
                .msg = msg,
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

    const raw = "{\"method\":\"subscribe\",\"subscription\":{\"type\":\"allMids\"}}";
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
