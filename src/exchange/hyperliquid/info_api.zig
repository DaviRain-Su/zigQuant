//! Hyperliquid Info API
//!
//! Provides market data query functions:
//! - getAllMids: Get all ticker prices
//! - getL2Book: Get L2 orderbook
//! - getMeta: Get asset metadata
//! - getUserState: Get user balances and positions

const std = @import("std");
const HttpClient = @import("http.zig").HttpClient;
const types = @import("types.zig");
const Logger = @import("../../core/logger.zig").Logger;

// ============================================================================
// Info API
// ============================================================================

pub const InfoAPI = struct {
    http_client: *HttpClient,
    allocator: std.mem.Allocator,
    logger: Logger,

    pub fn init(
        allocator: std.mem.Allocator,
        http_client: *HttpClient,
        logger: Logger,
    ) InfoAPI {
        return .{
            .allocator = allocator,
            .http_client = http_client,
            .logger = logger,
        };
    }

    /// Get all mid prices
    ///
    /// Returns a map of symbol -> price string
    pub fn getAllMids(self: *InfoAPI) !std.StringHashMap([]const u8) {
        self.logger.debug("Fetching all mids", .{}) catch {};

        // Prepare request (simple JSON, no need for stringify)
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            "{{\"type\":\"allMids\"}}",
            .{},
        );
        defer self.allocator.free(request_json);

        // Send request
        const response_body = try self.http_client.postInfo(request_json);
        defer self.allocator.free(response_body);

        // Parse response
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response_body,
            .{},
        );
        defer parsed.deinit();

        // Create result map
        var result = std.StringHashMap([]const u8).init(self.allocator);
        errdefer result.deinit();

        // Extract prices from JSON object
        if (parsed.value != .object) {
            return error.InvalidResponse;
        }

        const obj = parsed.value.object;
        var iter = obj.iterator();
        while (iter.next()) |entry| {
            const symbol = try self.allocator.dupe(u8, entry.key_ptr.*);
            errdefer self.allocator.free(symbol);

            const price_str = if (entry.value_ptr.* == .string)
                try self.allocator.dupe(u8, entry.value_ptr.string)
            else
                return error.InvalidResponse;

            try result.put(symbol, price_str);
        }

        return result;
    }

    /// Get L2 orderbook for a coin
    ///
    /// @param coin: Symbol (e.g., "ETH")
    /// @return Parsed L2BookResponse (caller must call deinit())
    pub fn getL2Book(self: *InfoAPI, coin: []const u8) !std.json.Parsed(types.L2BookResponse) {
        self.logger.debug("Fetching L2 book for {s}", .{coin}) catch {};

        // Prepare request
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            "{{\"type\":\"l2Book\",\"coin\":\"{s}\"}}",
            .{coin},
        );
        defer self.allocator.free(request_json);

        // Send request
        const response_body = try self.http_client.postInfo(request_json);
        defer self.allocator.free(response_body);

        // Parse response (caller must call deinit() on returned Parsed object)
        const parsed = try std.json.parseFromSlice(
            types.L2BookResponse,
            self.allocator,
            response_body,
            .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
        );

        return parsed;
    }

    /// Get asset metadata
    ///
    /// @return Parsed MetaResponse (caller must call deinit())
    pub fn getMeta(self: *InfoAPI) !std.json.Parsed(types.MetaResponse) {
        self.logger.debug("Fetching meta", .{}) catch {};

        // Prepare request
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            "{{\"type\":\"meta\"}}",
            .{},
        );
        defer self.allocator.free(request_json);

        // Send request
        const response_body = try self.http_client.postInfo(request_json);
        defer self.allocator.free(response_body);

        // Parse response (caller must call deinit() on returned Parsed object)
        const parsed = try std.json.parseFromSlice(
            types.MetaResponse,
            self.allocator,
            response_body,
            .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
        );

        return parsed;
    }

    /// Get asset metadata and contexts (includes mark price, oracle price)
    ///
    /// Returns a JSON Value with array format: [{universe: [...]}, [{...}, ...]]
    /// @return Parsed JSON Value (caller must call deinit())
    pub fn getMetaAndAssetCtxs(self: *InfoAPI) !std.json.Parsed(std.json.Value) {
        self.logger.debug("Fetching meta and asset contexts", .{}) catch {};

        // Prepare request
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            "{{\"type\":\"metaAndAssetCtxs\"}}",
            .{},
        );
        defer self.allocator.free(request_json);

        // Send request
        const response_body = try self.http_client.postInfo(request_json);
        defer self.allocator.free(response_body);

        // Parse response as dynamic JSON (array of [meta, contexts])
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response_body,
            .{ .allocate = .alloc_always },
        );

        return parsed;
    }

    /// Get user state (balances and positions)
    ///
    /// @param user: User address
    /// @return Parsed UserStateResponse (caller must call deinit())
    pub fn getUserState(self: *InfoAPI, user: []const u8) !std.json.Parsed(types.UserStateResponse) {
        self.logger.debug("Fetching user state for {s}", .{user}) catch {};

        // Prepare request
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            "{{\"type\":\"clearinghouseState\",\"user\":\"{s}\"}}",
            .{user},
        );
        defer self.allocator.free(request_json);

        // Send request
        const response_body = try self.http_client.postInfo(request_json);
        defer self.allocator.free(response_body);

        // Parse response
        const parsed = try std.json.parseFromSlice(
            types.UserStateResponse,
            self.allocator,
            response_body,
            .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
        );

        // Note: Caller must call parsed.deinit()
        return parsed;
    }

    /// Get user's open orders
    ///
    /// @param user: User address (e.g., "0x...")
    /// @return OpenOrdersResponse (array of OpenOrder)
    pub fn getOpenOrders(self: *InfoAPI, user: []const u8) !std.json.Parsed(types.OpenOrdersResponse) {
        self.logger.debug("Fetching open orders for {s}", .{user}) catch {};

        // Prepare request
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            "{{\"type\":\"openOrders\",\"user\":\"{s}\"}}",
            .{user},
        );
        defer self.allocator.free(request_json);

        // Send request
        const response_body = try self.http_client.postInfo(request_json);
        defer self.allocator.free(response_body);

        // Parse response
        const parsed = try std.json.parseFromSlice(
            types.OpenOrdersResponse,
            self.allocator,
            response_body,
            .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
        );

        self.logger.debug("Retrieved {} open orders", .{parsed.value.len}) catch {};

        return parsed;
    }

    /// Free AllMids result
    pub fn freeAllMids(self: *InfoAPI, mids: *std.StringHashMap([]const u8)) void {
        var iter = mids.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        mids.deinit();
    }
};

// ============================================================================
// Tests
// ============================================================================

// Note: Real API tests require network access and will be in integration tests
// Unit tests here are minimal

test "InfoAPI: initialization" {
    const allocator = std.testing.allocator;

    // Create dummy logger
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../core/logger.zig").LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../core/logger.zig").LogWriter{
        .ptr = @constCast(@ptrCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    var logger = Logger.init(allocator, writer, .debug);
    defer logger.deinit();

    var http_client = HttpClient.init(allocator, true, logger);
    defer http_client.deinit();

    const api = InfoAPI.init(allocator, &http_client, logger);
    try std.testing.expect(api.allocator.ptr == allocator.ptr);
}
