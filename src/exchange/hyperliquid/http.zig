//! Hyperliquid HTTP Client
//!
//! Provides HTTP communication with Hyperliquid API:
//! - GET/POST request handling
//! - JSON serialization/deserialization
//! - Error handling and retries
//! - Connection management

const std = @import("std");
const types = @import("types.zig");
const Logger = @import("../../core/logger.zig").Logger;
const NetworkError = @import("../../core/errors.zig").NetworkError;

// ============================================================================
// HTTP Client
// ============================================================================

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    http_client: std.http.Client,
    logger: Logger,

    /// Initialize HTTP client
    pub fn init(
        allocator: std.mem.Allocator,
        testnet: bool,
        logger: Logger,
    ) HttpClient {
        const base_url = if (testnet)
            types.API_BASE_URL_TESTNET
        else
            types.API_BASE_URL_MAINNET;

        return .{
            .allocator = allocator,
            .base_url = base_url,
            .http_client = std.http.Client{ .allocator = allocator },
            .logger = logger,
        };
    }

    /// Deinitialize HTTP client
    pub fn deinit(self: *HttpClient) void {
        self.http_client.deinit();
    }

    /// Make POST request to Info endpoint
    pub fn postInfo(
        self: *HttpClient,
        request_body: []const u8,
    ) ![]const u8 {
        return self.post(types.INFO_ENDPOINT, request_body);
    }

    /// Make POST request to Exchange endpoint
    pub fn postExchange(
        self: *HttpClient,
        request_body: []const u8,
    ) ![]const u8 {
        return self.post(types.EXCHANGE_ENDPOINT, request_body);
    }

    /// Generic POST request
    pub fn post(
        self: *HttpClient,
        endpoint: []const u8,
        request_body: []const u8,
    ) ![]const u8 {
        // Create arena allocator for temporary data
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        // Build full URL
        const url = try std.fmt.allocPrint(
            arena_alloc,
            "{s}{s}",
            .{ self.base_url, endpoint },
        );

        self.logger.debug("POST {s}", .{url}) catch {};
        self.logger.debug("Request body: {s}", .{request_body}) catch {};

        // Prepare headers
        var header_list = try std.ArrayList(std.http.Header).initCapacity(arena_alloc, 2);
        try header_list.append(arena_alloc, .{ .name = "Content-Type", .value = "application/json" });

        // Create response writer
        var body_writer = std.io.Writer.Allocating.init(arena_alloc);
        defer body_writer.deinit();

        // Make HTTP request
        const result = self.http_client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = request_body,
            .extra_headers = header_list.items,
            .response_writer = &body_writer.writer,
            .keep_alive = true,
        }) catch return NetworkError.ConnectionFailed;

        // Check status code
        const status = @intFromEnum(result.status);
        if (status < 200 or status >= 300) {
            self.logger.err("HTTP error: {d}", .{status}) catch {};
            return NetworkError.HttpError;
        }

        // Copy response to persistent memory
        const written = body_writer.written();
        const response_body = try self.allocator.alloc(u8, written.len);
        @memcpy(response_body, written);

        self.logger.debug("Response: {s}", .{response_body}) catch {};

        return response_body;
    }

    /// Make GET request (for future use)
    pub fn get(
        self: *HttpClient,
        endpoint: []const u8,
    ) ![]const u8 {
        // Create arena allocator for temporary data
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        // Build full URL
        const url = try std.fmt.allocPrint(
            arena_alloc,
            "{s}{s}",
            .{ self.base_url, endpoint },
        );

        self.logger.debug("GET {s}", .{url}) catch {};

        // Create response writer
        var body_writer = std.io.Writer.Allocating.init(arena_alloc);
        defer body_writer.deinit();

        // Make HTTP request
        const result = self.http_client.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_writer = &body_writer.writer,
            .keep_alive = true,
        }) catch return NetworkError.ConnectionFailed;

        // Check status code
        const status = @intFromEnum(result.status);
        if (status < 200 or status >= 300) {
            self.logger.err("HTTP error: {d}", .{status}) catch {};
            return NetworkError.HttpError;
        }

        // Copy response to persistent memory
        const written = body_writer.written();
        const response_body = try self.allocator.alloc(u8, written.len);
        @memcpy(response_body, written);

        return response_body;
    }
};

// ============================================================================
// Tests
// ============================================================================

// Test helper: Create a dummy Logger for testing
fn createTestLogger(allocator: std.mem.Allocator) Logger {
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

    return Logger.init(allocator, writer, .debug);
}

test "HttpClient: initialization" {
    var logger = createTestLogger(std.testing.allocator);
    defer logger.deinit();

    var client = HttpClient.init(std.testing.allocator, true, logger);
    defer client.deinit();

    try std.testing.expectEqualStrings(types.API_BASE_URL_TESTNET, client.base_url);
}

test "HttpClient: mainnet URL" {
    var logger = createTestLogger(std.testing.allocator);
    defer logger.deinit();

    var client = HttpClient.init(std.testing.allocator, false, logger);
    defer client.deinit();

    try std.testing.expectEqualStrings(types.API_BASE_URL_MAINNET, client.base_url);
}
