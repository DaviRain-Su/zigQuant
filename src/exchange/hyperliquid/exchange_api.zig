//! Hyperliquid Exchange API
//!
//! Provides trading operations:
//! - Place orders
//! - Cancel orders
//! - Modify orders (future)

const std = @import("std");
const HttpClient = @import("http.zig").HttpClient;
const types = @import("types.zig");
const auth = @import("auth.zig");
const Logger = @import("../../core/logger.zig").Logger;

// ============================================================================
// Exchange API
// ============================================================================

pub const ExchangeAPI = struct {
    http_client: *HttpClient,
    signer: ?*auth.Signer, // Optional: only needed for authenticated requests
    allocator: std.mem.Allocator,
    logger: Logger,

    pub fn init(
        allocator: std.mem.Allocator,
        http_client: *HttpClient,
        signer: ?*auth.Signer,
        logger: Logger,
    ) ExchangeAPI {
        return .{
            .allocator = allocator,
            .http_client = http_client,
            .signer = signer,
            .logger = logger,
        };
    }

    /// Place an order
    ///
    /// @param order_request: Order parameters
    /// @return Order response with order ID
    pub fn placeOrder(
        self: *ExchangeAPI,
        order_request: types.OrderRequest,
    ) !types.OrderResponse {
        if (self.signer == null) {
            return error.SignerRequired;
        }

        const order_type_str = if (order_request.order_type.limit != null) "limit" else "market";
        self.logger.debug("Placing order: {s} {s} @ {s}", .{
            if (order_request.is_buy) "buy" else "sell",
            order_type_str,
            order_request.coin,
        }) catch {};

        // Construct order action
        const action_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"type":"order","orders":[{{"a":{d},"b":true,"p":"{s}","s":"{s}","r":false,"t":{{"limit":{{"tif":"Gtc"}}}}}}],"grouping":"na"}}
            ,
            .{
                0, // asset index (TODO: lookup from coin)
                order_request.limit_px,
                order_request.sz,
            },
        );
        defer self.allocator.free(action_json);

        // Sign the action
        const signature = try self.signer.?.signAction(action_json);
        defer self.allocator.free(signature.r);
        defer self.allocator.free(signature.s);

        // Construct signed request
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"action":{s},"nonce":{d},"signature":{{"r":"{s}","s":"{s}","v":{d}}},"vaultAddress":null}}
            ,
            .{
                action_json,
                std.time.milliTimestamp(),
                signature.r,
                signature.s,
                signature.v,
            },
        );
        defer self.allocator.free(request_json);

        // Send request
        const response_body = try self.http_client.postExchange(request_json);
        defer self.allocator.free(response_body);

        // Parse response
        const parsed = try std.json.parseFromSlice(
            types.OrderResponse,
            self.allocator,
            response_body,
            .{ .allocate = .alloc_always },
        );
        defer parsed.deinit();

        return parsed.value;
    }

    /// Cancel an order
    ///
    /// @param coin: Symbol (e.g., "ETH")
    /// @param order_id: Order ID to cancel
    pub fn cancelOrder(
        self: *ExchangeAPI,
        coin: []const u8,
        order_id: u64,
    ) !types.CancelResponse {
        if (self.signer == null) {
            return error.SignerRequired;
        }

        self.logger.debug("Canceling order {d} for {s}", .{ order_id, coin }) catch {};

        // Construct cancel action
        const action_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"type":"cancel","cancels":[{{"a":{d},"o":{d}}}]}}
            ,
            .{
                0, // asset index (TODO: lookup from coin)
                order_id,
            },
        );
        defer self.allocator.free(action_json);

        // Sign the action
        const signature = try self.signer.?.signAction(action_json);
        defer self.allocator.free(signature.r);
        defer self.allocator.free(signature.s);

        // Construct signed request
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"action":{s},"nonce":{d},"signature":{{"r":"{s}","s":"{s}","v":{d}}},"vaultAddress":null}}
            ,
            .{
                action_json,
                std.time.milliTimestamp(),
                signature.r,
                signature.s,
                signature.v,
            },
        );
        defer self.allocator.free(request_json);

        // Send request
        const response_body = try self.http_client.postExchange(request_json);
        defer self.allocator.free(response_body);

        // Parse response
        const parsed = try std.json.parseFromSlice(
            types.CancelResponse,
            self.allocator,
            response_body,
            .{ .allocate = .alloc_always },
        );
        defer parsed.deinit();

        return parsed.value;
    }

    /// Cancel all orders for a coin
    ///
    /// @param coin: Symbol (e.g., "ETH") or null for all
    pub fn cancelAllOrders(
        self: *ExchangeAPI,
        coin: ?[]const u8,
    ) !types.CancelResponse {
        _ = coin;

        if (self.signer == null) {
            return error.SignerRequired;
        }

        self.logger.debug("Canceling all orders", .{}) catch {};

        // TODO: Implement cancel all
        return error.NotImplemented;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ExchangeAPI: initialization without signer" {
    const allocator = std.testing.allocator;

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

    const logger = @import("../../core/logger.zig").Logger.init(allocator, writer, .debug);

    var http_client = HttpClient.init(allocator, true, logger);
    defer http_client.deinit();

    const api = ExchangeAPI.init(allocator, &http_client, null, logger);

    try std.testing.expect(api.signer == null);
}
