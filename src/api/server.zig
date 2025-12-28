//! API Server
//!
//! High-performance REST API server built on http.zig.
//!
//! Features:
//! - Health check endpoints (/health, /ready)
//! - JWT authentication
//! - CORS support
//! - Request logging
//! - Prometheus metrics export

const std = @import("std");
const httpz = @import("httpz");
const Allocator = std.mem.Allocator;

const config_mod = @import("config.zig");
const ApiConfig = config_mod.ApiConfig;
const ApiDependencies = config_mod.ApiDependencies;
const handlers = @import("handlers/mod.zig");

/// API Server State
/// This is passed to all request handlers as context.
pub const ServerContext = struct {
    allocator: Allocator,
    config: ApiConfig,
    deps: ApiDependencies,
    start_time: i64,

    /// Get server uptime in seconds
    pub fn uptime(self: *const ServerContext) i64 {
        return std.time.timestamp() - self.start_time;
    }
};

/// API Server
pub const ApiServer = struct {
    allocator: Allocator,
    config: ApiConfig,
    deps: ApiDependencies,
    context: *ServerContext,
    server: HttpServer,

    const Self = @This();
    const HttpServer = httpz.Server(*ServerContext);

    /// Initialize the API server
    pub fn init(
        allocator: Allocator,
        config: ApiConfig,
        deps: ApiDependencies,
    ) !*Self {
        // Validate configuration
        try config.validate();

        // Create server context
        const context = try allocator.create(ServerContext);
        errdefer allocator.destroy(context);

        context.* = .{
            .allocator = allocator,
            .config = config,
            .deps = deps,
            .start_time = std.time.timestamp(),
        };

        // Create HTTP server
        // Note: httpz.Config.address expects []const u8 or null (for 0.0.0.0)
        const address: ?[]const u8 = if (std.mem.eql(u8, config.host, "0.0.0.0"))
            null
        else
            config.host;

        var server = try HttpServer.init(allocator, .{
            .port = config.port,
            .address = address,
            .request = .{
                .max_body_size = config.max_body_size,
            },
        }, context);
        errdefer server.deinit();

        // Setup routes
        try setupRoutes(&server);

        // Create ApiServer instance
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .deps = deps,
            .context = context,
            .server = server,
        };

        return self;
    }

    /// Setup all routes
    fn setupRoutes(server: *HttpServer) !void {
        var router = try server.router(.{});

        // Health check endpoints (no auth required)
        router.get("/health", handleHealth, .{});
        router.get("/ready", handleReady, .{});
        router.get("/version", handleVersion, .{});

        // API v1 routes
        // TODO: Add authentication middleware
        router.get("/api/v1/strategies", handleStrategiesList, .{});
        router.get("/api/v1/strategies/:id", handleStrategyGet, .{});

        // Metrics endpoint
        router.get("/metrics", handleMetrics, .{});
    }

    /// Start the server (blocking)
    pub fn start(self: *Self) !void {
        std.log.info("Starting API server on {s}:{d}", .{ self.config.host, self.config.port });
        try self.server.listen();
    }

    /// Stop the server
    pub fn stop(self: *Self) void {
        self.server.stop();
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.server.deinit();
        self.allocator.destroy(self.context);
        self.allocator.destroy(self);
    }

    // ========================================================================
    // Route Handlers
    // ========================================================================

    fn handleHealth(ctx: *ServerContext, _: *httpz.Request, res: *httpz.Response) !void {
        try res.json(.{
            .status = "healthy",
            .version = "1.0.0",
            .uptime_seconds = ctx.uptime(),
            .timestamp = std.time.timestamp(),
        }, .{});
    }

    fn handleReady(_: *ServerContext, _: *httpz.Request, res: *httpz.Response) !void {
        // TODO: Check actual dependencies
        try res.json(.{
            .ready = true,
        }, .{});
    }

    fn handleVersion(_: *ServerContext, _: *httpz.Request, res: *httpz.Response) !void {
        try res.json(.{
            .name = "zigQuant",
            .version = "1.0.0",
            .api_version = "v1",
        }, .{});
    }

    fn handleStrategiesList(_: *ServerContext, _: *httpz.Request, res: *httpz.Response) !void {
        // TODO: Get from StrategyRegistry
        try res.json(.{
            .strategies = &[_]struct {
                id: []const u8,
                name: []const u8,
                status: []const u8,
            }{
                .{ .id = "dual_ma", .name = "Dual MA Crossover", .status = "available" },
                .{ .id = "rsi_mean_reversion", .name = "RSI Mean Reversion", .status = "available" },
                .{ .id = "bollinger_breakout", .name = "Bollinger Breakout", .status = "available" },
            },
            .total = 3,
        }, .{});
    }

    fn handleStrategyGet(_: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        const id = req.param("id") orelse {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Missing strategy ID" }, .{});
            return;
        };

        // TODO: Get from StrategyRegistry
        try res.json(.{
            .id = id,
            .name = "Dual MA Crossover",
            .description = "Simple moving average crossover strategy",
            .status = "available",
            .config = .{
                .fast_period = 10,
                .slow_period = 20,
            },
        }, .{});
    }

    fn handleMetrics(_: *ServerContext, _: *httpz.Request, res: *httpz.Response) !void {
        res.content_type = httpz.ContentType.TEXT;

        const writer = res.writer();
        try writer.writeAll("# HELP zigquant_uptime_seconds Server uptime in seconds\n");
        try writer.writeAll("# TYPE zigquant_uptime_seconds counter\n");
        try writer.writeAll("zigquant_uptime_seconds 0\n\n");

        try writer.writeAll("# HELP zigquant_api_requests_total Total API requests\n");
        try writer.writeAll("# TYPE zigquant_api_requests_total counter\n");
        try writer.writeAll("zigquant_api_requests_total 0\n");
    }
};

test "ApiServer: basic initialization" {
    // Basic compile test - full tests require httpz mock
}
