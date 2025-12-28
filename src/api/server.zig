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
const jwt_mod = @import("jwt.zig");

/// API Server State
/// This is passed to all request handlers as context.
pub const ServerContext = struct {
    allocator: Allocator,
    config: ApiConfig,
    deps: ApiDependencies,
    start_time: i64,
    jwt_manager: jwt_mod.JwtManager,
    request_count: std.atomic.Value(u64),

    /// Get server uptime in seconds
    pub fn uptime(self: *const ServerContext) i64 {
        return std.time.timestamp() - self.start_time;
    }

    /// Increment request counter
    pub fn incrementRequestCount(self: *ServerContext) void {
        _ = self.request_count.fetchAdd(1, .monotonic);
    }

    /// Get total request count
    pub fn getRequestCount(self: *const ServerContext) u64 {
        return self.request_count.load(.monotonic);
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
            .jwt_manager = jwt_mod.JwtManager.init(
                allocator,
                config.jwt_secret,
                config.jwt_expiry_hours,
                "zigquant",
            ),
            .request_count = std.atomic.Value(u64).init(0),
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

        // Authentication endpoints (no auth required)
        router.post("/api/v1/auth/login", handleLogin, .{});
        router.post("/api/v1/auth/refresh", handleRefresh, .{});
        router.get("/api/v1/auth/me", handleMe, .{});

        // API v1 routes (public for now, auth can be added per-handler)
        router.get("/api/v1/strategies", handleStrategiesList, .{});
        router.get("/api/v1/strategies/:id", handleStrategyGet, .{});

        // Metrics endpoint (Prometheus format)
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
    // Route Handlers - Health & Info
    // ========================================================================

    fn handleHealth(ctx: *ServerContext, _: *httpz.Request, res: *httpz.Response) !void {
        ctx.incrementRequestCount();
        try res.json(.{
            .status = "healthy",
            .version = "1.0.0",
            .uptime_seconds = ctx.uptime(),
            .timestamp = std.time.timestamp(),
        }, .{});
    }

    fn handleReady(ctx: *ServerContext, _: *httpz.Request, res: *httpz.Response) !void {
        ctx.incrementRequestCount();
        // Check dependencies - for now we check if JWT is configured
        const jwt_configured = ctx.config.jwt_secret.len >= 32;

        // In a full implementation, we would check:
        // - Database connection (if using one)
        // - Exchange API connectivity
        // - Required services availability

        const checks = .{
            .jwt_configured = jwt_configured,
            .server_running = true,
        };

        const all_ready = jwt_configured;

        if (all_ready) {
            try res.json(.{
                .ready = true,
                .checks = checks,
            }, .{});
        } else {
            res.setStatus(.service_unavailable);
            try res.json(.{
                .ready = false,
                .checks = checks,
            }, .{});
        }
    }

    fn handleVersion(ctx: *ServerContext, _: *httpz.Request, res: *httpz.Response) !void {
        ctx.incrementRequestCount();
        try res.json(.{
            .name = "zigQuant",
            .version = "1.0.0",
            .api_version = "v1",
            .zig_version = @import("builtin").zig_version_string,
        }, .{});
    }

    // ========================================================================
    // Route Handlers - Authentication
    // ========================================================================

    fn handleLogin(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.incrementRequestCount();

        // Parse request body
        const body = req.body() orelse {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Missing request body" }, .{});
            return;
        };

        const LoginRequest = struct {
            username: []const u8,
            password: []const u8,
        };

        const parsed = std.json.parseFromSlice(LoginRequest, req.arena, body, .{}) catch {
            res.setStatus(.bad_request);
            try res.json(.{
                .@"error" = "Invalid JSON format",
                .expected = "{ \"username\": \"...\", \"password\": \"...\" }",
            }, .{});
            return;
        };

        const login_req = parsed.value;

        // Validate credentials (demo users - in production use proper auth)
        if (!validateCredentials(login_req.username, login_req.password)) {
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = "Invalid credentials" }, .{});
            return;
        }

        // Generate JWT token
        const token = ctx.jwt_manager.generateToken(login_req.username) catch |err| {
            std.log.err("Failed to generate token: {}", .{err});
            res.setStatus(.internal_server_error);
            try res.json(.{ .@"error" = "Failed to generate token" }, .{});
            return;
        };

        try res.json(.{
            .token = token,
            .expires_in = ctx.jwt_manager.expiry_seconds,
            .token_type = "Bearer",
        }, .{});
    }

    fn handleRefresh(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.incrementRequestCount();

        const auth_header = req.header("authorization") orelse {
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = "Missing Authorization header" }, .{});
            return;
        };

        const prefix = "Bearer ";
        if (!std.mem.startsWith(u8, auth_header, prefix)) {
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = "Invalid Authorization format" }, .{});
            return;
        }

        const token = auth_header[prefix.len..];
        const new_token = ctx.jwt_manager.refreshToken(token) catch |err| {
            const err_msg = switch (err) {
                error.TokenExpired => "Token has expired. Please login again.",
                error.InvalidSignature => "Invalid token signature.",
                else => "Invalid token.",
            };
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = err_msg }, .{});
            return;
        };

        try res.json(.{
            .token = new_token,
            .expires_in = ctx.jwt_manager.expiry_seconds,
            .token_type = "Bearer",
        }, .{});
    }

    fn handleMe(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.incrementRequestCount();

        const auth_header = req.header("authorization") orelse {
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = "Missing Authorization header" }, .{});
            return;
        };

        const prefix = "Bearer ";
        if (!std.mem.startsWith(u8, auth_header, prefix)) {
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = "Invalid Authorization format" }, .{});
            return;
        }

        const token = auth_header[prefix.len..];
        const payload = ctx.jwt_manager.verifyToken(token) catch |err| {
            const err_msg = switch (err) {
                error.TokenExpired => "Token has expired",
                error.InvalidSignature => "Invalid token signature",
                else => "Invalid token",
            };
            res.setStatus(.unauthorized);
            try res.json(.{ .@"error" = err_msg }, .{});
            return;
        };

        try res.json(.{
            .user_id = payload.sub,
            .issued_at = payload.iat,
            .expires_at = payload.exp,
            .issuer = payload.iss,
        }, .{});
    }

    // ========================================================================
    // Route Handlers - Strategies
    // ========================================================================

    fn handleStrategiesList(ctx: *ServerContext, _: *httpz.Request, res: *httpz.Response) !void {
        ctx.incrementRequestCount();

        // Built-in strategies available in zigQuant
        // These are the actual strategies implemented in src/strategy/
        try res.json(.{
            .strategies = &[_]struct {
                id: []const u8,
                name: []const u8,
                description: []const u8,
                status: []const u8,
            }{
                .{
                    .id = "dual_ma",
                    .name = "Dual MA Crossover",
                    .description = "Trend following strategy using fast/slow moving average crossovers",
                    .status = "available",
                },
                .{
                    .id = "rsi_mean_reversion",
                    .name = "RSI Mean Reversion",
                    .description = "Mean reversion strategy based on RSI oversold/overbought levels",
                    .status = "available",
                },
                .{
                    .id = "bollinger_breakout",
                    .name = "Bollinger Breakout",
                    .description = "Breakout strategy using Bollinger Bands volatility signals",
                    .status = "available",
                },
            },
            .total = 3,
        }, .{});
    }

    fn handleStrategyGet(ctx: *ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
        ctx.incrementRequestCount();

        const id = req.param("id") orelse {
            res.setStatus(.bad_request);
            try res.json(.{ .@"error" = "Missing strategy ID" }, .{});
            return;
        };

        // Strategy details based on ID
        if (std.mem.eql(u8, id, "dual_ma")) {
            try res.json(.{
                .id = "dual_ma",
                .name = "Dual MA Crossover",
                .description = "Trend following strategy using fast/slow moving average crossovers",
                .status = "available",
                .parameters = .{
                    .fast_period = .{ .type = "integer", .default = 10, .min = 2, .max = 50 },
                    .slow_period = .{ .type = "integer", .default = 20, .min = 5, .max = 200 },
                },
            }, .{});
        } else if (std.mem.eql(u8, id, "rsi_mean_reversion")) {
            try res.json(.{
                .id = "rsi_mean_reversion",
                .name = "RSI Mean Reversion",
                .description = "Mean reversion strategy based on RSI oversold/overbought levels",
                .status = "available",
                .parameters = .{
                    .rsi_period = .{ .type = "integer", .default = 14, .min = 2, .max = 50 },
                    .oversold = .{ .type = "float", .default = 30.0, .min = 0.0, .max = 50.0 },
                    .overbought = .{ .type = "float", .default = 70.0, .min = 50.0, .max = 100.0 },
                },
            }, .{});
        } else if (std.mem.eql(u8, id, "bollinger_breakout")) {
            try res.json(.{
                .id = "bollinger_breakout",
                .name = "Bollinger Breakout",
                .description = "Breakout strategy using Bollinger Bands volatility signals",
                .status = "available",
                .parameters = .{
                    .period = .{ .type = "integer", .default = 20, .min = 5, .max = 100 },
                    .std_dev = .{ .type = "float", .default = 2.0, .min = 0.5, .max = 4.0 },
                },
            }, .{});
        } else {
            res.setStatus(.not_found);
            try res.json(.{ .@"error" = "Strategy not found", .id = id }, .{});
        }
    }

    // ========================================================================
    // Route Handlers - Metrics
    // ========================================================================

    fn handleMetrics(ctx: *ServerContext, _: *httpz.Request, res: *httpz.Response) !void {
        res.content_type = httpz.ContentType.TEXT;

        const writer = res.writer();

        // Uptime metric
        try writer.writeAll("# HELP zigquant_uptime_seconds Server uptime in seconds\n");
        try writer.writeAll("# TYPE zigquant_uptime_seconds gauge\n");
        try writer.print("zigquant_uptime_seconds {d}\n\n", .{ctx.uptime()});

        // Request count metric
        try writer.writeAll("# HELP zigquant_api_requests_total Total API requests\n");
        try writer.writeAll("# TYPE zigquant_api_requests_total counter\n");
        try writer.print("zigquant_api_requests_total {d}\n\n", .{ctx.getRequestCount()});

        // Server info
        try writer.writeAll("# HELP zigquant_info Server information\n");
        try writer.writeAll("# TYPE zigquant_info gauge\n");
        try writer.writeAll("zigquant_info{version=\"1.0.0\",api_version=\"v1\"} 1\n");
    }

    // ========================================================================
    // Helper Functions
    // ========================================================================

    /// Validate user credentials (demo implementation)
    /// In production, use proper password hashing and database lookup
    fn validateCredentials(username: []const u8, password: []const u8) bool {
        const demo_users = [_]struct { user: []const u8, pass: []const u8 }{
            .{ .user = "admin", .pass = "admin123" },
            .{ .user = "trader", .pass = "trader123" },
        };

        for (demo_users) |u| {
            if (std.mem.eql(u8, username, u.user) and std.mem.eql(u8, password, u.pass)) {
                return true;
            }
        }
        return false;
    }
};

test "ApiServer: basic initialization" {
    // Basic compile test - full tests require httpz mock
}
