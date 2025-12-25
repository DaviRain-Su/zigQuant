//! Simple MessagePack encoder for Hyperliquid action serialization
//!
//! This is a minimal implementation that only supports the subset of MessagePack
//! needed for encoding Hyperliquid API actions. It is NOT a full MessagePack implementation.
//!
//! Reference: https://msgpack.org/index.html

const std = @import("std");
const Allocator = std.mem.Allocator;

/// MessagePack encoder
pub const Encoder = struct {
    allocator: Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator) Encoder {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *Encoder) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn toOwnedSlice(self: *Encoder) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    /// Encode a map with N elements
    pub fn writeMapHeader(self: *Encoder, size: u32) !void {
        if (size <= 15) {
            // fixmap: 1000xxxx (0x80 - 0x8f)
            try self.buffer.append(self.allocator, @as(u8, 0x80) | @as(u8, @intCast(size)));
        } else if (size <= 0xffff) {
            // map16
            try self.buffer.append(self.allocator, 0xde);
            try self.buffer.append(self.allocator, @as(u8, @intCast(size >> 8)));
            try self.buffer.append(self.allocator, @as(u8, @intCast(size & 0xff)));
        } else {
            return error.MapTooLarge;
        }
    }

    /// Encode an array with N elements
    pub fn writeArrayHeader(self: *Encoder, size: u32) !void {
        if (size <= 15) {
            // fixarray: 1001xxxx (0x90 - 0x9f)
            try self.buffer.append(self.allocator, @as(u8, 0x90) | @as(u8, @intCast(size)));
        } else if (size <= 0xffff) {
            // array16
            try self.buffer.append(self.allocator, 0xdc);
            try self.buffer.append(self.allocator, @as(u8, @intCast(size >> 8)));
            try self.buffer.append(self.allocator, @as(u8, @intCast(size & 0xff)));
        } else {
            return error.ArrayTooLarge;
        }
    }

    /// Encode a string
    pub fn writeString(self: *Encoder, str: []const u8) !void {
        const len = str.len;
        if (len <= 31) {
            // fixstr: 101xxxxx (0xa0 - 0xbf)
            try self.buffer.append(self.allocator, @as(u8, 0xa0) | @as(u8, @intCast(len)));
        } else if (len <= 0xff) {
            // str8
            try self.buffer.append(self.allocator, 0xd9);
            try self.buffer.append(self.allocator, @as(u8, @intCast(len)));
        } else if (len <= 0xffff) {
            // str16
            try self.buffer.append(self.allocator, 0xda);
            try self.buffer.append(self.allocator, @as(u8, @intCast(len >> 8)));
            try self.buffer.append(self.allocator, @as(u8, @intCast(len & 0xff)));
        } else {
            return error.StringTooLong;
        }
        try self.buffer.appendSlice(self.allocator, str);
    }

    /// Encode a boolean
    pub fn writeBool(self: *Encoder, value: bool) !void {
        try self.buffer.append(self.allocator, if (value) @as(u8, 0xc3) else @as(u8, 0xc2));
    }

    /// Encode a uint
    pub fn writeUint(self: *Encoder, value: u64) !void {
        if (value <= 127) {
            // positive fixint: 0xxxxxxx (0x00 - 0x7f)
            try self.buffer.append(self.allocator, @as(u8, @intCast(value)));
        } else if (value <= 0xff) {
            // uint8
            try self.buffer.append(self.allocator, 0xcc);
            try self.buffer.append(self.allocator, @as(u8, @intCast(value)));
        } else if (value <= 0xffff) {
            // uint16
            try self.buffer.append(self.allocator, 0xcd);
            try self.buffer.append(self.allocator, @as(u8, @intCast(value >> 8)));
            try self.buffer.append(self.allocator, @as(u8, @intCast(value & 0xff)));
        } else if (value <= 0xffffffff) {
            // uint32
            try self.buffer.append(self.allocator, 0xce);
            try self.buffer.append(self.allocator, @as(u8, @intCast((value >> 24) & 0xff)));
            try self.buffer.append(self.allocator, @as(u8, @intCast((value >> 16) & 0xff)));
            try self.buffer.append(self.allocator, @as(u8, @intCast((value >> 8) & 0xff)));
            try self.buffer.append(self.allocator, @as(u8, @intCast(value & 0xff)));
        } else {
            // uint64
            try self.buffer.append(self.allocator, 0xcf);
            var i: u8 = 0;
            while (i < 8) : (i += 1) {
                const shift = @as(u6, @intCast(56 - i * 8));
                try self.buffer.append(self.allocator, @as(u8, @intCast((value >> shift) & 0xff)));
            }
        }
    }
};

/// Pack a Hyperliquid order action
///
/// Format:
/// {
///   "type": "order",
///   "orders": [...],
///   "grouping": "na"
/// }
pub fn packOrderAction(
    allocator: Allocator,
    orders: []const OrderRequest,
    grouping: []const u8,
) ![]u8 {
    var encoder = Encoder.init(allocator);
    errdefer encoder.deinit();

    // Root map with 3 keys: type, orders, grouping
    // IMPORTANT: Order must match JSON request body!
    try encoder.writeMapHeader(3);

    // Key: "type" (first, matching JSON order)
    try encoder.writeString("type");
    try encoder.writeString("order");

    // Key: "orders" (second)
    try encoder.writeString("orders");
    try encoder.writeArrayHeader(@intCast(orders.len));

    for (orders) |order| {
        try packOrder(&encoder, order);
    }

    // Key: "grouping" (third)
    try encoder.writeString("grouping");
    try encoder.writeString(grouping);

    return encoder.toOwnedSlice();
}

/// Order request structure for msgpack
pub const OrderRequest = struct {
    a: u64, // asset index
    b: bool, // is_buy
    p: []const u8, // limit price
    s: []const u8, // size
    r: bool, // reduce_only
    t: OrderType, // order type
};

pub const OrderType = struct {
    limit: ?LimitType = null,
    market: ?MarketType = null,
};

pub const LimitType = struct {
    tif: []const u8, // time in force
};

pub const MarketType = struct {
    slippage: []const u8 = "0.05", // 5% default slippage tolerance
};

/// Pack a single order
fn packOrder(encoder: *Encoder, order: OrderRequest) !void {
    // Order map with 6 keys: a, b, p, s, r, t (order matters for msgpack!)
    try encoder.writeMapHeader(6);

    // Key: "a" (asset index)
    try encoder.writeString("a");
    try encoder.writeUint(order.a);

    // Key: "b" (is_buy)
    try encoder.writeString("b");
    try encoder.writeBool(order.b);

    // Key: "p" (price)
    try encoder.writeString("p");
    try encoder.writeString(order.p);

    // Key: "s" (size) - MUST come before "r" to match Python SDK order!
    try encoder.writeString("s");
    try encoder.writeString(order.s);

    // Key: "r" (reduce_only)
    try encoder.writeString("r");
    try encoder.writeBool(order.r);

    // Key: "t" (order type)
    try encoder.writeString("t");
    if (order.t.limit) |limit| {
        // Limit order: {"limit": {"tif": "..."}}
        try encoder.writeMapHeader(1);
        try encoder.writeString("limit");
        try encoder.writeMapHeader(1);
        try encoder.writeString("tif");
        try encoder.writeString(limit.tif);
    } else if (order.t.market) |_| {
        // Market order: {"market": {}} (empty map)
        try encoder.writeMapHeader(1);
        try encoder.writeString("market");
        try encoder.writeMapHeader(0); // Empty map for market orders
    } else {
        return error.UnsupportedOrderType;
    }
}

/// Cancel request structure for msgpack
pub const CancelRequest = struct {
    a: u64, // asset index
    o: u64, // order id
};

/// Pack a Hyperliquid cancel action
///
/// Format:
/// {
///   "type": "cancel",
///   "cancels": [...]
/// }
pub fn packCancelAction(
    allocator: Allocator,
    cancels: []const CancelRequest,
) ![]u8 {
    var encoder = Encoder.init(allocator);
    errdefer encoder.deinit();

    // Root map with 2 keys: type, cancels
    try encoder.writeMapHeader(2);

    // Key: "type" (first)
    try encoder.writeString("type");
    try encoder.writeString("cancel");

    // Key: "cancels" (second)
    try encoder.writeString("cancels");
    try encoder.writeArrayHeader(@intCast(cancels.len));

    for (cancels) |cancel| {
        try packCancel(&encoder, cancel);
    }

    return encoder.toOwnedSlice();
}

/// Pack a single cancel request
fn packCancel(encoder: *Encoder, cancel: CancelRequest) !void {
    // Cancel map with 2 keys: a, o
    try encoder.writeMapHeader(2);

    // Key: "a" (asset index)
    try encoder.writeString("a");
    try encoder.writeUint(cancel.a);

    // Key: "o" (order id)
    try encoder.writeString("o");
    try encoder.writeUint(cancel.o);
}

// ============================================================================
// Tests
// ============================================================================

test "encode fixmap" {
    var encoder = Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    try encoder.writeMapHeader(3);
    const result = try encoder.toOwnedSlice();
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(u8, 0x83), result[0]); // fixmap with 3 elements
}

test "encode fixstr" {
    var encoder = Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    try encoder.writeString("hello");
    const result = try encoder.toOwnedSlice();
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(u8, 0xa5), result[0]); // fixstr with 5 bytes
    try std.testing.expectEqualStrings("hello", result[1..]);
}

test "encode bool" {
    var encoder = Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    try encoder.writeBool(true);
    try encoder.writeBool(false);
    const result = try encoder.toOwnedSlice();
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(u8, 0xc3), result[0]); // true
    try std.testing.expectEqual(@as(u8, 0xc2), result[1]); // false
}

test "encode uint" {
    var encoder = Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    try encoder.writeUint(0);
    try encoder.writeUint(127);
    try encoder.writeUint(255);
    const result = try encoder.toOwnedSlice();
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(u8, 0), result[0]); // fixint 0
    try std.testing.expectEqual(@as(u8, 127), result[1]); // fixint 127
    try std.testing.expectEqual(@as(u8, 0xcc), result[2]); // uint8
    try std.testing.expectEqual(@as(u8, 255), result[3]);
}

test "pack order action" {
    const orders = [_]OrderRequest{
        .{
            .a = 0,
            .b = true,
            .p = "1000",
            .s = "0.01",
            .r = false,
            .t = .{ .limit = .{ .tif = "Gtc" } },
        },
    };

    const packed_data = try packOrderAction(std.testing.allocator, &orders, "na");
    defer std.testing.allocator.free(packed_data);

    // Should start with fixmap (3 keys)
    try std.testing.expectEqual(@as(u8, 0x83), packed_data[0]);

    // Should contain the strings "type", "orders", "grouping"
    const packed_str = std.mem.sliceAsBytes(packed_data);
    try std.testing.expect(std.mem.indexOf(u8, packed_str, "type") != null);
    try std.testing.expect(std.mem.indexOf(u8, packed_str, "orders") != null);
    try std.testing.expect(std.mem.indexOf(u8, packed_str, "grouping") != null);
}
