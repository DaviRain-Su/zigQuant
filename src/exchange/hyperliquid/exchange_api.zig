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
const msgpack = @import("msgpack.zig");
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

        // Build msgpack order for signing
        const msgpack_order_type: msgpack.OrderType = if (order_request.order_type.limit != null)
            .{ .limit = .{ .tif = order_request.order_type.limit.?.tif } }
        else if (order_request.order_type.market != null)
            .{ .market = .{} }
        else
            return error.UnsupportedOrderType;

        const msgpack_order = msgpack.OrderRequest{
            .a = order_request.asset_index,
            .b = order_request.is_buy,
            .p = order_request.limit_px,
            .s = order_request.sz,
            .r = order_request.reduce_only,
            .t = msgpack_order_type,
        };

        const orders = [_]msgpack.OrderRequest{msgpack_order};
        const action_msgpack = try msgpack.packOrderAction(
            self.allocator,
            &orders,
            "na",
        );
        defer self.allocator.free(action_msgpack);

        self.logger.debug("Msgpack action size: {d} bytes", .{action_msgpack.len}) catch {};

        // Msgpack-encoded action ready for signing

        // Generate nonce (must be same for signing and request!)
        const nonce = @as(u64, @intCast(std.time.milliTimestamp()));

        // Sign the msgpack-encoded action (with phantom agent)
        const signature = try self.signer.?.signAction(action_msgpack, nonce);
        defer self.allocator.free(signature.r);
        defer self.allocator.free(signature.s);

        // Construct order action JSON for request body
        const order_type_json = if (order_request.order_type.limit != null) blk: {
            const tif = order_request.order_type.limit.?.tif;
            break :blk try std.fmt.allocPrint(
                self.allocator,
                \\{{"limit":{{"tif":"{s}"}}}}
            ,
                .{tif},
            );
        } else if (order_request.order_type.market != null) blk: {
            break :blk try self.allocator.dupe(u8, "{\"market\":{}}");
        } else {
            return error.UnsupportedOrderType;
        };
        defer self.allocator.free(order_type_json);

        const action_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"type":"order","orders":[{{"a":{d},"b":{s},"p":"{s}","s":"{s}","r":{s},"t":{s}}}],"grouping":"na"}}
        ,
            .{
                order_request.asset_index,
                if (order_request.is_buy) "true" else "false",
                order_request.limit_px,
                order_request.sz,
                if (order_request.reduce_only) "true" else "false",
                order_type_json,
            },
        );
        defer self.allocator.free(action_json);

        // Construct signed request (use the same nonce!)
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"action":{s},"nonce":{d},"signature":{{"r":"{s}","s":"{s}","v":{d}}},"vaultAddress":null}}
        ,
            .{
                action_json,
                nonce,
                signature.r,
                signature.s,
                signature.v,
            },
        );
        defer self.allocator.free(request_json);

        // Debug: Log the request being sent
        std.debug.print("[DEBUG] Sending placeOrder request:\n{s}\n", .{request_json});
        self.logger.debug("Sending placeOrder request: {s}", .{request_json}) catch {};

        // Send request
        const response_body = try self.http_client.postExchange(request_json);
        defer self.allocator.free(response_body);

        // Debug: Log the raw response
        std.debug.print("[DEBUG] Raw placeOrder response:\n{s}\n", .{response_body});
        self.logger.debug("Raw placeOrder response: {s}", .{response_body}) catch {};

        // Parse response as dynamic JSON first
        const parsed_raw = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response_body,
            .{ .allocate = .alloc_always },
        );
        defer parsed_raw.deinit();

        const root = parsed_raw.value.object;

        // Check status field
        const status = root.get("status") orelse return error.MissingStatus;
        const status_str = status.string;

        // Handle error response
        if (std.mem.eql(u8, status_str, "err")) {
            const response = root.get("response") orelse return error.MissingResponse;
            const error_msg = response.string;
            self.logger.err("Exchange API error: {s}", .{error_msg}) catch {};
            return error.ExchangeAPIError;
        }

        // Parse success response
        const parsed = try std.json.parseFromSlice(
            types.OrderResponse,
            self.allocator,
            response_body,
            .{ .allocate = .alloc_always },
        );
        defer parsed.deinit();

        // Check for order errors in statuses
        if (parsed.value.response.data) |data| {
            if (data.statuses.len > 0) {
                const first_status = data.statuses[0];
                if (first_status.@"error") |err_msg| {
                    self.logger.err("Order rejected: {s}", .{err_msg}) catch {};
                    return error.OrderRejected;
                }
            }
        }

        return parsed.value;
    }

    /// Cancel an order
    ///
    /// @param asset_index: Asset index from meta (e.g., 0 for ETH)
    /// @param order_id: Order ID to cancel
    pub fn cancelOrder(
        self: *ExchangeAPI,
        asset_index: u64,
        order_id: u64,
    ) !types.CancelResponse {
        if (self.signer == null) {
            return error.SignerRequired;
        }

        self.logger.debug("Canceling order {d} (asset index: {d})", .{ order_id, asset_index }) catch {};

        // Build msgpack cancel action for signing
        const msgpack_cancel = msgpack.CancelRequest{
            .a = asset_index,
            .o = order_id,
        };

        const cancels = [_]msgpack.CancelRequest{msgpack_cancel};
        const action_msgpack = try msgpack.packCancelAction(
            self.allocator,
            &cancels,
        );
        defer self.allocator.free(action_msgpack);

        self.logger.debug("Msgpack cancel action size: {d} bytes", .{action_msgpack.len}) catch {};

        // Generate nonce (must be same for signing and request!)
        const nonce = @as(u64, @intCast(std.time.milliTimestamp()));

        // Sign the msgpack-encoded action (with phantom agent)
        const signature = try self.signer.?.signAction(action_msgpack, nonce);
        defer self.allocator.free(signature.r);
        defer self.allocator.free(signature.s);

        // Construct cancel action JSON for request body
        const action_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"type":"cancel","cancels":[{{"a":{d},"o":{d}}}]}}
        ,
            .{
                asset_index,
                order_id,
            },
        );
        defer self.allocator.free(action_json);

        // Construct signed request (use the same nonce!)
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"action":{s},"nonce":{d},"signature":{{"r":"{s}","s":"{s}","v":{d}}},"vaultAddress":null}}
        ,
            .{
                action_json,
                nonce,
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
    /// @param asset_index: Asset index from meta (e.g., 0 for ETH), or null for all
    pub fn cancelAllOrders(
        self: *ExchangeAPI,
        asset_index: ?u64,
    ) !types.CancelResponse {
        if (self.signer == null) {
            return error.SignerRequired;
        }

        if (asset_index) |idx| {
            self.logger.debug("Canceling all orders for asset index {d}", .{idx}) catch {};
        } else {
            self.logger.debug("Canceling all orders", .{}) catch {};
        }

        // Build msgpack cancel all action for signing
        const msgpack_cancel = msgpack.CancelRequest{
            .a = asset_index,
            .o = null,
        };

        const cancels = [_]msgpack.CancelRequest{msgpack_cancel};
        const action_msgpack = try msgpack.packCancelAction(
            self.allocator,
            &cancels,
        );
        defer self.allocator.free(action_msgpack);

        self.logger.debug("Msgpack cancel all action size: {d} bytes", .{action_msgpack.len}) catch {};

        // Generate nonce (must be same for signing and request!)
        const nonce = @as(u64, @intCast(std.time.milliTimestamp()));

        // Sign the msgpack-encoded action (with phantom agent)
        const signature = try self.signer.?.signAction(action_msgpack, nonce);
        defer self.allocator.free(signature.r);
        defer self.allocator.free(signature.s);

        // Construct cancel action JSON for request body
        const action_json = if (asset_index) |idx| blk: {
            break :blk try std.fmt.allocPrint(
                self.allocator,
                \\{{"type":"cancel","cancels":[{{"a":{d},"o":null}}]}}
            ,
                .{idx},
            );
        } else blk: {
            break :blk try self.allocator.dupe(u8, "{\"type\":\"cancel\",\"cancels\":[{\"a\":null,\"o\":null}]}");
        };
        defer self.allocator.free(action_json);

        // Construct signed request (use the same nonce!)
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"action":{s},"nonce":{d},"signature":{{"r":"{s}","s":"{s}","v":{d}}},"vaultAddress":null}}
        ,
            .{
                action_json,
                nonce,
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

    /// Update leverage for a specific asset
    ///
    /// @param asset_index: Asset index from meta (e.g., 3 for BTC)
    /// @param leverage: Target leverage (1-100)
    /// @param is_cross: true for cross margin, false for isolated
    pub fn updateLeverage(
        self: *ExchangeAPI,
        asset_index: u64,
        leverage: u32,
        is_cross: bool,
    ) !void {
        if (self.signer == null) {
            return error.SignerRequired;
        }

        self.logger.info("Updating leverage for asset {d} to {d}x (cross={})", .{
            asset_index,
            leverage,
            is_cross,
        }) catch {};

        // Build the updateLeverage action
        // Format: {"type": "updateLeverage", "asset": 3, "isCross": true, "leverage": 5}
        const action_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"type":"updateLeverage","asset":{d},"isCross":{s},"leverage":{d}}}
        ,
            .{
                asset_index,
                if (is_cross) "true" else "false",
                leverage,
            },
        );
        defer self.allocator.free(action_json);

        // For updateLeverage, we need to sign the action as-is (not msgpack)
        // Generate nonce
        const nonce = @as(u64, @intCast(std.time.milliTimestamp()));

        // Sign the action (updateLeverage uses direct JSON signing, not msgpack)
        const signature = try self.signer.?.signActionJson(action_json, nonce);
        defer self.allocator.free(signature.r);
        defer self.allocator.free(signature.s);

        // Construct signed request
        const request_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"action":{s},"nonce":{d},"signature":{{"r":"{s}","s":"{s}","v":{d}}},"vaultAddress":null}}
        ,
            .{
                action_json,
                nonce,
                signature.r,
                signature.s,
                signature.v,
            },
        );
        defer self.allocator.free(request_json);

        // Send request
        const response_body = try self.http_client.postExchange(request_json);
        defer self.allocator.free(response_body);

        self.logger.debug("updateLeverage response: {s}", .{response_body}) catch {};

        // Parse response to check for errors
        const parsed_raw = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response_body,
            .{ .allocate = .alloc_always },
        );
        defer parsed_raw.deinit();

        const root = parsed_raw.value.object;
        const status = root.get("status") orelse return error.MissingStatus;
        const status_str = status.string;

        if (std.mem.eql(u8, status_str, "err")) {
            const response = root.get("response") orelse return error.MissingResponse;
            const error_msg = response.string;
            self.logger.err("updateLeverage failed: {s}", .{error_msg}) catch {};
            return error.UpdateLeverageFailed;
        }

        self.logger.info("Leverage updated successfully", .{}) catch {};
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
        .ptr = @ptrCast(@constCast(&struct {}{})),
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
