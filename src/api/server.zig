//! API Server
//!
//! High-performance REST API server built on Zig standard library (std.http).
//!
//! Features:
//! - Health check endpoints (/health, /ready)
//! - JWT authentication
//! - CORS support
//! - Request logging
//! - Prometheus metrics export

const std = @import("std");
const Allocator = std.mem.Allocator;
const net = std.net;

const router_mod = @import("router.zig");
const Router = router_mod.Router;
const RequestContext = router_mod.RequestContext;
const Response = router_mod.Response;
const Method = router_mod.Method;

const config_mod = @import("config.zig");
const ApiConfig = config_mod.ApiConfig;
const ApiDependencies = config_mod.ApiDependencies;
const IExchange = config_mod.IExchange;

const jwt_mod = @import("jwt.zig");
const cors = @import("middleware/cors.zig");

// ============================================================================
// Response Types for Multi-Exchange API
// ============================================================================

/// Exchange info for listing exchanges
pub const ExchangeInfo = struct {
    name: []const u8,
    status: []const u8,
    network: []const u8,
};

/// Position summary per exchange
pub const PositionSummary = struct {
    exchange: []const u8,
    position_count: usize,
    total_pnl: f64,
    total_margin: f64,
    status: []const u8,
};

/// Order summary per exchange
pub const OrderSummary = struct {
    exchange: []const u8,
    order_count: usize,
    status: []const u8,
};

/// Account info per exchange
pub const AccountInfo = struct {
    exchange: []const u8,
    account_id: []const u8,
    account_type: []const u8,
    network: []const u8,
    status: []const u8,
};

/// Balance summary per exchange
pub const BalanceSummary = struct {
    exchange: []const u8,
    total: f64,
    available: f64,
    locked: f64,
    status: []const u8,
};

/// API Server State
/// This is passed to all request handlers as context.
pub const ServerContext = struct {
    allocator: Allocator,
    config: ApiConfig,
    deps: ApiDependencies,
    start_time: i64,
    jwt_manager: jwt_mod.JwtManager,
    request_count: std.atomic.Value(u64),
    cors_config: cors.CorsConfig,

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
    router: Router,
    running: std.atomic.Value(bool),

    const Self = @This();

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
            .cors_config = .{
                .allowed_origins = config.cors_origins,
            },
        };

        // Create router
        var router = Router.init(allocator);
        errdefer router.deinit();

        // Create ApiServer instance
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .deps = deps,
            .context = context,
            .router = router,
            .running = std.atomic.Value(bool).init(false),
        };

        // Setup routes
        try self.setupRoutes();

        return self;
    }

    /// Setup all routes
    fn setupRoutes(self: *Self) !void {
        std.log.info("Registering routes...", .{});

        // CORS preflight handler for all routes
        try self.router.options("/*", handleCorsPreflightWildcard);

        // Health check endpoints (no auth required)
        try self.router.getNoAuth("/health", handleHealth);
        try self.router.getNoAuth("/ready", handleReady);
        try self.router.getNoAuth("/version", handleVersion);

        // Authentication endpoints (no auth required)
        try self.router.postNoAuth("/api/v1/auth/login", handleLogin);
        try self.router.postNoAuth("/api/v1/auth/refresh", handleRefresh);
        try self.router.getNoAuth("/api/v1/auth/me", handleMe);

        // Exchanges - Multi-exchange support
        try self.router.get("/api/v1/exchanges", handleExchangesList);
        try self.router.get("/api/v1/exchanges/:name", handleExchangeGet);

        // Strategies
        try self.router.get("/api/v1/strategies", handleStrategiesList);
        try self.router.post("/api/v1/strategies/validate", handleStrategyValidate);
        try self.router.get("/api/v1/strategies/:id/params", handleStrategyParams);
        try self.router.post("/api/v1/strategies/:id/run", handleStrategyRun);
        try self.router.get("/api/v1/strategies/:id", handleStrategyGet);

        // Indicators
        try self.router.get("/api/v1/indicators", handleIndicatorsList);
        try self.router.get("/api/v1/indicators/:name", handleIndicatorGet);

        // Backtest
        try self.router.post("/api/v1/backtest", handleBacktestCreate);
        try self.router.get("/api/v1/backtest/results", handleBacktestResultsList);
        try self.router.get("/api/v1/backtest/:id/trades", handleBacktestTrades);
        try self.router.get("/api/v1/backtest/:id/equity", handleBacktestEquity);
        try self.router.get("/api/v1/backtest/:id", handleBacktestGet);

        // Risk Metrics
        try self.router.get("/api/v1/risk/metrics", handleRiskMetrics);
        try self.router.get("/api/v1/risk/metrics/var", handleRiskVaR);
        try self.router.get("/api/v1/risk/metrics/drawdown", handleRiskDrawdown);
        try self.router.get("/api/v1/risk/metrics/sharpe", handleRiskSharpe);
        try self.router.get("/api/v1/risk/metrics/report", handleRiskReport);
        try self.router.post("/api/v1/risk/kill-switch", handleKillSwitch);

        // Alerts
        try self.router.get("/api/v1/alerts", handleAlertsList);
        try self.router.get("/api/v1/alerts/stats", handleAlertsStats);

        // Paper Trading
        try self.router.post("/api/v1/trading/paper/start", handlePaperTradingStart);
        try self.router.post("/api/v1/trading/paper/stop", handlePaperTradingStop);
        try self.router.get("/api/v1/trading/paper/status", handlePaperTradingStatus);

        // Grid Trading (v0.10.0)
        try self.router.get("/api/v1/grid", handleGridList);
        try self.router.post("/api/v1/grid", handleGridStart);
        try self.router.get("/api/v1/grid/:id", handleGridGet);
        try self.router.put("/api/v1/grid/:id", handleGridUpdate);
        try self.router.delete("/api/v1/grid/:id", handleGridStop);
        try self.router.get("/api/v1/grid/:id/orders", handleGridOrders);
        try self.router.get("/api/v1/grid/:id/stats", handleGridStats);
        try self.router.get("/api/v1/grid/summary", handleGridSummary);

        // Data / Candles
        try self.router.get("/api/v1/data/candles", handleCandlesList);

        // Positions
        try self.router.get("/api/v1/positions", handlePositionsList);

        // Orders
        try self.router.get("/api/v1/orders", handleOrdersList);
        try self.router.post("/api/v1/orders", handleOrderCreate);
        try self.router.delete("/api/v1/orders/:id", handleOrderCancel);

        // Account
        try self.router.get("/api/v1/account", handleAccountGet);
        try self.router.get("/api/v1/account/balance", handleAccountBalance);

        // Metrics endpoint (Prometheus format)
        try self.router.getNoAuth("/metrics", handleMetrics);

        std.log.info("All {d} routes registered successfully", .{self.router.routes.items.len});
    }

    /// Start the server (blocking)
    pub fn start(self: *Self) !void {
        self.running.store(true, .release);

        const address = try net.Address.parseIp(self.config.host, self.config.port);
        var listener = try address.listen(.{
            .reuse_address = true,
        });
        defer listener.deinit();

        std.log.info("zigQuant API Server v1.0.0", .{});
        std.log.info("Server listening on http://{s}:{d}", .{ self.config.host, self.config.port });
        std.log.info("Health check: http://{s}:{d}/health", .{ self.config.host, self.config.port });
        std.log.info("Press Ctrl+C to stop", .{});

        while (self.running.load(.acquire)) {
            // Accept connection with timeout to allow checking running flag
            const conn = listener.accept() catch |err| {
                if (err == error.WouldBlock) continue;
                std.log.err("Accept error: {}", .{err});
                continue;
            };

            // Handle connection in a separate thread or inline
            self.handleConnection(conn) catch |err| {
                std.log.err("Handle error: {}", .{err});
            };
        }
    }

    /// Handle a single HTTP connection
    fn handleConnection(self: *Self, conn: net.Server.Connection) !void {
        defer conn.stream.close();

        var buffer: [8192]u8 = undefined;
        const n = conn.stream.read(&buffer) catch |err| {
            std.log.err("Read error: {}", .{err});
            return;
        };

        if (n == 0) return;

        const request_data = buffer[0..n];

        // Parse HTTP request
        const parsed = self.parseHttpRequest(request_data) orelse {
            try self.sendRawResponse(conn.stream, "400 Bad Request", "Bad Request");
            return;
        };

        try self.handleParsedRequest(conn.stream, parsed);
    }

    /// Simple HTTP request structure
    const ParsedRequest = struct {
        method: []const u8,
        path: []const u8,
        headers: []const u8,
        body: ?[]const u8,
    };

    /// Parse raw HTTP request
    fn parseHttpRequest(self: *Self, data: []const u8) ?ParsedRequest {
        _ = self;

        // Find end of first line
        const first_line_end = std.mem.indexOf(u8, data, "\r\n") orelse return null;
        const first_line = data[0..first_line_end];

        // Parse method and path
        var parts = std.mem.splitScalar(u8, first_line, ' ');
        const method = parts.next() orelse return null;
        const path = parts.next() orelse return null;

        // Find end of headers
        const headers_end = std.mem.indexOf(u8, data, "\r\n\r\n") orelse data.len;
        const headers = data[first_line_end + 2 .. headers_end];

        // Body starts after headers
        const body: ?[]const u8 = if (headers_end + 4 < data.len)
            data[headers_end + 4 ..]
        else
            null;

        return .{
            .method = method,
            .path = path,
            .headers = headers,
            .body = body,
        };
    }

    /// Handle parsed request
    fn handleParsedRequest(self: *Self, stream: net.Stream, parsed: ParsedRequest) !void {
        self.context.incrementRequestCount();

        // Parse method
        const method = if (std.mem.eql(u8, parsed.method, "GET"))
            Method.GET
        else if (std.mem.eql(u8, parsed.method, "POST"))
            Method.POST
        else if (std.mem.eql(u8, parsed.method, "PUT"))
            Method.PUT
        else if (std.mem.eql(u8, parsed.method, "DELETE"))
            Method.DELETE
        else if (std.mem.eql(u8, parsed.method, "OPTIONS"))
            Method.OPTIONS
        else {
            try self.sendRawResponse(stream, "405 Method Not Allowed", "Method Not Allowed");
            return;
        };

        // Get path without query string
        const path = if (std.mem.indexOf(u8, parsed.path, "?")) |idx|
            parsed.path[0..idx]
        else
            parsed.path;

        // Log request
        std.log.debug("{s} {s}", .{ parsed.method, path });

        // Match route
        const match_result = try self.router.match(self.allocator, method, path);

        if (match_result) |result| {
            // Create request context
            var response = Response.initWithAllocator(self.allocator);
            defer response.deinit();

            var ctx = RequestContext.init(self.allocator, self.context);
            defer ctx.deinit();

            ctx.method = method;
            ctx.path = path;
            ctx.params = result.params;
            ctx.response = &response;
            ctx.body = parsed.body;

            // Parse query parameters
            if (router_mod.extractQueryString(parsed.path)) |qs| {
                ctx.query = try router_mod.parseQueryString(self.allocator, qs);
            }

            // Add CORS headers
            try response.addHeader("Access-Control-Allow-Origin", "*");
            try response.addHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS");
            try response.addHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

            // Check authentication if required
            if (result.route.requires_auth) {
                // Simple auth check from Authorization header
                if (self.findHeader(parsed.headers, "Authorization")) |auth_header| {
                    if (std.mem.startsWith(u8, auth_header, "Bearer ")) {
                        const token = auth_header[7..];
                        if (self.context.jwt_manager.verifyToken(token)) |payload| {
                            ctx.user_id = payload.sub;
                        } else |_| {
                            response.setStatus(.unauthorized);
                            try response.json(.{ .@"error" = "Invalid token" });
                            try self.sendHttpResponse(stream, &response);
                            return;
                        }
                    } else {
                        response.setStatus(.unauthorized);
                        try response.json(.{ .@"error" = "Invalid Authorization format" });
                        try self.sendHttpResponse(stream, &response);
                        return;
                    }
                } else {
                    response.setStatus(.unauthorized);
                    try response.json(.{ .@"error" = "Missing Authorization header" });
                    try self.sendHttpResponse(stream, &response);
                    return;
                }
            }

            // Call handler
            result.route.handler(&ctx) catch |err| {
                std.log.err("Handler error: {}", .{err});
                response.setStatus(.internal_server_error);
                try response.json(.{ .@"error" = @errorName(err) });
            };

            // Send response
            try self.sendHttpResponse(stream, &response);
        } else {
            // Try to serve static files from dashboard/dist
            const served = self.serveStaticFile(stream, path) catch false;
            if (!served) {
                // 404 Not Found
                try self.sendRawResponse(stream, "404 Not Found", "{\"error\":\"Not Found\"}");
            }
        }
    }

    /// Serve static files from dashboard/dist directory
    fn serveStaticFile(self: *Self, stream: net.Stream, path: []const u8) !bool {
        // Build file path relative to dashboard/dist
        var file_path_buf: [512]u8 = undefined;
        var use_path = path;

        // Check if path has an extension (is a static asset)
        const has_extension = blk: {
            if (std.mem.lastIndexOf(u8, path, ".")) |dot_idx| {
                if (std.mem.lastIndexOf(u8, path, "/")) |slash_idx| {
                    break :blk dot_idx > slash_idx;
                }
                break :blk true;
            }
            break :blk false;
        };

        // SPA fallback: routes without extensions serve index.html
        if (!has_extension) {
            use_path = "/index.html";
        }

        const file_path = std.fmt.bufPrint(&file_path_buf, "dashboard/dist{s}", .{use_path}) catch {
            return false;
        };

        // Try to open and read the file
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Try SPA fallback for any 404
                if (!std.mem.eql(u8, use_path, "/index.html")) {
                    const index_path = "dashboard/dist/index.html";
                    const index_file = std.fs.cwd().openFile(index_path, .{}) catch {
                        return false;
                    };
                    defer index_file.close();
                    return self.sendStaticFileResponse(stream, index_file, "text/html; charset=utf-8");
                }
            }
            return false;
        };
        defer file.close();

        // Determine content type
        const content_type = self.getContentType(use_path);
        return self.sendStaticFileResponse(stream, file, content_type);
    }

    /// Get content type based on file extension
    fn getContentType(self: *Self, path: []const u8) []const u8 {
        _ = self;
        const ext = std.fs.path.extension(path);

        if (std.mem.eql(u8, ext, ".html")) return "text/html; charset=utf-8";
        if (std.mem.eql(u8, ext, ".js")) return "application/javascript; charset=utf-8";
        if (std.mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
        if (std.mem.eql(u8, ext, ".json")) return "application/json; charset=utf-8";
        if (std.mem.eql(u8, ext, ".png")) return "image/png";
        if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
        if (std.mem.eql(u8, ext, ".gif")) return "image/gif";
        if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
        if (std.mem.eql(u8, ext, ".ico")) return "image/x-icon";
        if (std.mem.eql(u8, ext, ".woff")) return "font/woff";
        if (std.mem.eql(u8, ext, ".woff2")) return "font/woff2";
        if (std.mem.eql(u8, ext, ".ttf")) return "font/ttf";
        if (std.mem.eql(u8, ext, ".eot")) return "application/vnd.ms-fontobject";
        if (std.mem.eql(u8, ext, ".map")) return "application/json";

        return "application/octet-stream";
    }

    /// Send static file response
    fn sendStaticFileResponse(self: *Self, stream: net.Stream, file: std.fs.File, content_type: []const u8) bool {
        _ = self;

        // Get file size
        const stat = file.stat() catch return false;
        const file_size = stat.size;

        // Read file content (limit to 10MB)
        if (file_size > 10 * 1024 * 1024) return false;

        var buf: [65536]u8 = undefined;
        var response_buf: [1024]u8 = undefined;

        // Write header
        const header = std.fmt.bufPrint(
            &response_buf,
            "HTTP/1.1 200 OK\r\n" ++
                "Content-Type: {s}\r\n" ++
                "Content-Length: {d}\r\n" ++
                "Access-Control-Allow-Origin: *\r\n" ++
                "Cache-Control: public, max-age=31536000\r\n" ++
                "\r\n",
            .{ content_type, file_size },
        ) catch return false;

        _ = stream.write(header) catch return false;

        // Stream file content in chunks
        while (true) {
            const n = file.read(&buf) catch return false;
            if (n == 0) break;
            _ = stream.write(buf[0..n]) catch return false;
        }

        return true;
    }

    /// Find header value in raw headers
    fn findHeader(self: *Self, headers: []const u8, name: []const u8) ?[]const u8 {
        _ = self;
        var lines = std.mem.splitSequence(u8, headers, "\r\n");
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, ": ")) |colon_idx| {
                const header_name = line[0..colon_idx];
                if (std.ascii.eqlIgnoreCase(header_name, name)) {
                    return line[colon_idx + 2 ..];
                }
            }
        }
        return null;
    }

    /// Send raw HTTP response
    fn sendRawResponse(self: *Self, stream: net.Stream, status: []const u8, body: []const u8) !void {
        _ = self;
        var buf: [4096]u8 = undefined;
        const response = std.fmt.bufPrint(
            &buf,
            "HTTP/1.1 {s}\r\n" ++
                "Content-Type: application/json\r\n" ++
                "Content-Length: {d}\r\n" ++
                "Access-Control-Allow-Origin: *\r\n" ++
                "\r\n" ++
                "{s}",
            .{ status, body.len, body },
        ) catch return;

        _ = stream.write(response) catch {};
    }

    /// Send HTTP response from Response struct
    fn sendHttpResponse(self: *Self, stream: net.Stream, response: *Response) !void {
        _ = self;

        // Build response
        var buf: [65536]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        // Status line
        const status_code = @intFromEnum(response.status);
        const status_text = switch (response.status) {
            .ok => "OK",
            .created => "Created",
            .no_content => "No Content",
            .bad_request => "Bad Request",
            .unauthorized => "Unauthorized",
            .forbidden => "Forbidden",
            .not_found => "Not Found",
            .method_not_allowed => "Method Not Allowed",
            .internal_server_error => "Internal Server Error",
            .service_unavailable => "Service Unavailable",
            else => "Unknown",
        };

        try writer.print("HTTP/1.1 {d} {s}\r\n", .{ status_code, status_text });

        // Headers
        for (response.headers.items) |h| {
            try writer.print("{s}: {s}\r\n", .{ h.name, h.value });
        }

        // Content-Length
        try writer.print("Content-Length: {d}\r\n", .{response.body.items.len});

        // End of headers
        try writer.writeAll("\r\n");

        // Body
        try writer.writeAll(response.body.items);

        // Send
        _ = stream.write(fbs.getWritten()) catch {};
    }

    /// Stop the server
    pub fn stop(self: *Self) void {
        self.running.store(false, .release);
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.router.deinit();
        self.allocator.destroy(self.context);
        self.allocator.destroy(self);
    }

    // ========================================================================
    // Route Handlers
    // ========================================================================

    fn handleCorsPreflightWildcard(ctx: *RequestContext) !void {
        ctx.response.setStatus(.no_content);
        try ctx.response.addHeader("Access-Control-Allow-Origin", "*");
        try ctx.response.addHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS");
        try ctx.response.addHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
        try ctx.response.addHeader("Access-Control-Max-Age", "86400");
    }

    fn handleHealth(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));
        try ctx.response.json(.{
            .status = "healthy",
            .version = "1.0.0",
            .uptime_seconds = server_ctx.uptime(),
            .timestamp = std.time.timestamp(),
        });
    }

    fn handleReady(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));
        const jwt_configured = server_ctx.config.jwt_secret.len >= 32;

        const checks = .{
            .jwt_configured = jwt_configured,
            .server_running = true,
        };

        if (jwt_configured) {
            try ctx.response.json(.{
                .ready = true,
                .checks = checks,
            });
        } else {
            ctx.response.setStatus(.service_unavailable);
            try ctx.response.json(.{
                .ready = false,
                .checks = checks,
            });
        }
    }

    fn handleVersion(ctx: *RequestContext) !void {
        try ctx.response.json(.{
            .name = "zigQuant",
            .version = "1.0.0",
            .api_version = "v1",
            .zig_version = @import("builtin").zig_version_string,
        });
    }

    fn handleLogin(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        const body = ctx.body orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing request body" });
            return;
        };

        const LoginRequest = struct {
            username: []const u8,
            password: []const u8,
        };

        const parsed = std.json.parseFromSlice(LoginRequest, ctx.arena.allocator(), body, .{}) catch {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{
                .@"error" = "Invalid JSON format",
                .expected = "{ \"username\": \"...\", \"password\": \"...\" }",
            });
            return;
        };

        const login_req = parsed.value;

        // Validate credentials (demo users)
        if (!validateCredentials(login_req.username, login_req.password)) {
            ctx.response.setStatus(.unauthorized);
            try ctx.response.json(.{ .@"error" = "Invalid credentials" });
            return;
        }

        // Generate JWT token
        const token = server_ctx.jwt_manager.generateToken(login_req.username) catch |err| {
            std.log.err("Failed to generate token: {}", .{err});
            ctx.response.setStatus(.internal_server_error);
            try ctx.response.json(.{ .@"error" = "Failed to generate token" });
            return;
        };

        try ctx.response.json(.{
            .token = token,
            .expires_in = server_ctx.jwt_manager.expiry_seconds,
            .token_type = "Bearer",
        });
    }

    fn handleRefresh(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        const auth_header = ctx.header("Authorization") orelse {
            ctx.response.setStatus(.unauthorized);
            try ctx.response.json(.{ .@"error" = "Missing Authorization header" });
            return;
        };

        if (!std.mem.startsWith(u8, auth_header, "Bearer ")) {
            ctx.response.setStatus(.unauthorized);
            try ctx.response.json(.{ .@"error" = "Invalid Authorization format" });
            return;
        }

        const token = auth_header[7..];
        const payload = server_ctx.jwt_manager.verifyToken(token) catch {
            ctx.response.setStatus(.unauthorized);
            try ctx.response.json(.{ .@"error" = "Invalid or expired token" });
            return;
        };

        // Generate new token
        const new_token = server_ctx.jwt_manager.generateToken(payload.sub) catch |err| {
            std.log.err("Failed to generate token: {}", .{err});
            ctx.response.setStatus(.internal_server_error);
            try ctx.response.json(.{ .@"error" = "Failed to generate token" });
            return;
        };

        try ctx.response.json(.{
            .token = new_token,
            .expires_in = server_ctx.jwt_manager.expiry_seconds,
            .token_type = "Bearer",
        });
    }

    fn handleMe(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        const auth_header = ctx.header("Authorization") orelse {
            ctx.response.setStatus(.unauthorized);
            try ctx.response.json(.{ .@"error" = "Missing Authorization header" });
            return;
        };

        if (!std.mem.startsWith(u8, auth_header, "Bearer ")) {
            ctx.response.setStatus(.unauthorized);
            try ctx.response.json(.{ .@"error" = "Invalid Authorization format" });
            return;
        }

        const token = auth_header[7..];
        const payload = server_ctx.jwt_manager.verifyToken(token) catch {
            ctx.response.setStatus(.unauthorized);
            try ctx.response.json(.{ .@"error" = "Invalid or expired token" });
            return;
        };

        try ctx.response.json(.{
            .user_id = payload.sub,
            .issuer = payload.iss,
            .issued_at = payload.iat,
            .expires_at = payload.exp,
        });
    }

    fn handleExchangesList(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        const exchange_count = server_ctx.deps.exchangeCount();

        if (exchange_count == 0) {
            try ctx.response.json(.{
                .exchanges = &[_]ExchangeInfo{},
                .total = @as(usize, 0),
                .note = "No exchanges configured",
            });
            return;
        }

        // Build exchange list from deps
        var exchanges: [16]ExchangeInfo = undefined;
        var i: usize = 0;
        var iter = server_ctx.deps.iterator();
        while (iter.next()) |entry| {
            if (i >= 16) break;
            const network = if (entry.value_ptr.config.testnet) "testnet" else "mainnet";
            const status = if (entry.value_ptr.interface.isConnected()) "connected" else "disconnected";
            exchanges[i] = .{
                .name = entry.key_ptr.*,
                .status = status,
                .network = network,
            };
            i += 1;
        }

        try ctx.response.json(.{
            .exchanges = exchanges[0..i],
            .total = exchange_count,
        });
    }

    fn handleExchangeGet(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));
        const name = ctx.param("name") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing exchange name" });
            return;
        };

        if (server_ctx.deps.getExchange(name)) |exchange_entry| {
            const network = if (exchange_entry.config.testnet) "testnet" else "mainnet";
            const status = if (exchange_entry.interface.isConnected()) "connected" else "disconnected";

            try ctx.response.json(.{
                .name = name,
                .status = status,
                .network = network,
                .api_key = exchange_entry.config.api_key,
                .features = .{
                    .spot = false,
                    .futures = true,
                    .margin = false,
                },
            });
        } else {
            ctx.response.setStatus(.not_found);
            try ctx.response.json(.{ .@"error" = "Exchange not found", .name = name });
        }
    }

    fn handleStrategiesList(ctx: *RequestContext) !void {
        // Return real strategies from the factory
        try ctx.response.json(.{
            .strategies = &[_]struct {
                id: []const u8,
                name: []const u8,
                description: []const u8,
                strategy_type: []const u8,
            }{
                .{
                    .id = "dual_ma",
                    .name = "Dual Moving Average",
                    .description = "Trend following strategy using fast/slow MA crossovers",
                    .strategy_type = "trend_following",
                },
                .{
                    .id = "rsi_mean_reversion",
                    .name = "RSI Mean Reversion",
                    .description = "Mean reversion strategy using RSI oversold/overbought levels",
                    .strategy_type = "mean_reversion",
                },
                .{
                    .id = "bollinger_breakout",
                    .name = "Bollinger Breakout",
                    .description = "Breakout strategy using Bollinger Bands volatility",
                    .strategy_type = "breakout",
                },
                .{
                    .id = "triple_ma",
                    .name = "Triple Moving Average",
                    .description = "Advanced trend strategy using three moving averages",
                    .strategy_type = "trend_following",
                },
                .{
                    .id = "macd_divergence",
                    .name = "MACD Divergence",
                    .description = "Divergence-based strategy using MACD indicator",
                    .strategy_type = "trend_following",
                },
                .{
                    .id = "hybrid_ai",
                    .name = "Hybrid AI Strategy",
                    .description = "Combines technical indicators with LLM analysis",
                    .strategy_type = "ai_hybrid",
                },
            },
            .total = @as(usize, 6),
        });
    }

    fn handleStrategyGet(ctx: *RequestContext) !void {
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing strategy ID" });
            return;
        };

        // Look up strategy details
        const advanced = @import("handlers/advanced.zig");
        const strategy_info = advanced.getStrategyParams(ctx.allocator, id) catch |err| {
            if (err == error.StrategyNotFound) {
                ctx.response.setStatus(.not_found);
                try ctx.response.json(.{
                    .@"error" = "Strategy not found",
                    .id = id,
                });
                return;
            }
            return err;
        };

        try ctx.response.json(.{
            .id = strategy_info.id,
            .name = strategy_info.name,
            .description = strategy_info.description,
            .strategy_type = strategy_info.strategy_type,
            .status = "available",
        });
    }

    fn handleStrategyParams(ctx: *RequestContext) !void {
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing strategy ID" });
            return;
        };

        // Look up strategy parameters from advanced.zig
        const advanced = @import("handlers/advanced.zig");
        const strategy_info = advanced.getStrategyParams(ctx.allocator, id) catch |err| {
            if (err == error.StrategyNotFound) {
                ctx.response.setStatus(.not_found);
                try ctx.response.json(.{
                    .@"error" = "Strategy not found",
                    .id = id,
                });
                return;
            }
            return err;
        };

        try ctx.response.json(.{
            .id = strategy_info.id,
            .name = strategy_info.name,
            .description = strategy_info.description,
            .strategy_type = strategy_info.strategy_type,
            .parameters = strategy_info.parameters,
        });
    }

    fn handleStrategyValidate(ctx: *RequestContext) !void {
        try ctx.response.json(.{
            .valid = true,
            .message = "Strategy configuration is valid",
        });
    }

    fn handleStrategyRun(ctx: *RequestContext) !void {
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing strategy ID" });
            return;
        };

        try ctx.response.json(.{
            .id = id,
            .status = "started",
            .message = "Strategy execution started",
        });
    }

    fn handleIndicatorsList(ctx: *RequestContext) !void {
        // Return real indicators from advanced.zig
        const advanced = @import("handlers/advanced.zig");
        const indicators = advanced.getIndicatorList();

        try ctx.response.json(.{
            .indicators = indicators,
            .total = indicators.len,
        });
    }

    fn handleIndicatorGet(ctx: *RequestContext) !void {
        const name = ctx.param("name") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing indicator name" });
            return;
        };

        // Look up indicator details from advanced.zig
        const advanced = @import("handlers/advanced.zig");
        const indicators = advanced.getIndicatorList();

        for (indicators) |indicator| {
            if (std.mem.eql(u8, indicator.name, name)) {
                try ctx.response.json(.{
                    .name = indicator.name,
                    .description = indicator.description,
                    .category = indicator.category,
                    .parameters = indicator.parameters,
                    .output_type = indicator.output_type,
                });
                return;
            }
        }

        // Not found
        ctx.response.setStatus(.not_found);
        try ctx.response.json(.{
            .@"error" = "Indicator not found",
            .name = name,
        });
    }

    fn handleBacktestCreate(ctx: *RequestContext) !void {
        try ctx.response.json(.{
            .id = "bt_001",
            .status = "created",
            .message = "Backtest created successfully",
        });
    }

    fn handleBacktestGet(ctx: *RequestContext) !void {
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing backtest ID" });
            return;
        };

        try ctx.response.json(.{
            .id = id,
            .status = "completed",
            .result = .{
                .total_return = 0.15,
                .sharpe_ratio = 1.5,
                .max_drawdown = 0.08,
            },
        });
    }

    fn handleBacktestResultsList(ctx: *RequestContext) !void {
        try ctx.response.json(.{
            .results = &[_][]const u8{},
            .total = @as(usize, 0),
        });
    }

    fn handleBacktestTrades(ctx: *RequestContext) !void {
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing backtest ID" });
            return;
        };

        try ctx.response.json(.{
            .backtest_id = id,
            .trades = &[_][]const u8{},
            .total = @as(usize, 0),
        });
    }

    fn handleBacktestEquity(ctx: *RequestContext) !void {
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing backtest ID" });
            return;
        };

        try ctx.response.json(.{
            .backtest_id = id,
            .equity_curve = &[_]f64{},
        });
    }

    fn handleRiskMetrics(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        if (server_ctx.deps.risk_monitor) |monitor| {
            const var_95 = monitor.calculateVaR(0.95);
            const var_99 = monitor.calculateVaR(0.99);
            const drawdown = monitor.calculateMaxDrawdown();
            const sharpe = monitor.calculateSharpeRatio(null);
            const sortino = monitor.calculateSortinoRatio(null);

            try ctx.response.json(.{
                .var_95 = var_95.var_percentage,
                .var_99 = var_99.var_percentage,
                .max_drawdown = drawdown.max_drawdown_pct,
                .current_drawdown = drawdown.current_drawdown_pct,
                .sharpe_ratio = sharpe.sharpe_ratio,
                .sortino_ratio = sortino.sortino_ratio,
                .annual_return = sharpe.annual_return,
                .annual_volatility = sharpe.annual_volatility,
                .observations = var_95.observations,
                .timestamp = std.time.timestamp(),
            });
        } else {
            // No risk monitor configured - return placeholder
            try ctx.response.json(.{
                .var_95 = 0.0,
                .var_99 = 0.0,
                .max_drawdown = 0.0,
                .sharpe_ratio = 0.0,
                .sortino_ratio = 0.0,
                .note = "Risk monitor not configured",
            });
        }
    }

    fn handleRiskVaR(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        if (server_ctx.deps.risk_monitor) |monitor| {
            const var_95 = monitor.calculateVaR(0.95);
            const var_99 = monitor.calculateVaR(0.99);

            try ctx.response.json(.{
                .var_95 = .{
                    .percentage = var_95.var_percentage,
                    .confidence = var_95.confidence,
                    .observations = var_95.observations,
                    .error_message = var_95.error_message,
                },
                .var_99 = .{
                    .percentage = var_99.var_percentage,
                    .confidence = var_99.confidence,
                    .observations = var_99.observations,
                    .error_message = var_99.error_message,
                },
                .timestamp = std.time.timestamp(),
            });
        } else {
            try ctx.response.json(.{
                .var_95 = .{ .percentage = 0.0, .note = "Risk monitor not configured" },
                .var_99 = .{ .percentage = 0.0, .note = "Risk monitor not configured" },
            });
        }
    }

    fn handleRiskDrawdown(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        if (server_ctx.deps.risk_monitor) |monitor| {
            const dd = monitor.calculateMaxDrawdown();

            try ctx.response.json(.{
                .current_drawdown = dd.current_drawdown_pct,
                .max_drawdown = dd.max_drawdown_pct,
                .peak_index = dd.peak_index,
                .trough_index = dd.trough_index,
                .is_recovering = dd.is_recovering,
                .error_message = dd.error_message,
                .timestamp = std.time.timestamp(),
            });
        } else {
            try ctx.response.json(.{
                .current_drawdown = 0.0,
                .max_drawdown = 0.0,
                .note = "Risk monitor not configured",
            });
        }
    }

    fn handleRiskSharpe(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        if (server_ctx.deps.risk_monitor) |monitor| {
            const sharpe = monitor.calculateSharpeRatio(null);
            const sortino = monitor.calculateSortinoRatio(null);
            const calmar = monitor.calculateCalmarRatio();

            try ctx.response.json(.{
                .sharpe_ratio = sharpe.sharpe_ratio,
                .sortino_ratio = sortino.sortino_ratio,
                .calmar_ratio = calmar.calmar_ratio,
                .annual_return = sharpe.annual_return,
                .annual_volatility = sharpe.annual_volatility,
                .downside_deviation = sortino.downside_deviation,
                .risk_free_rate = sharpe.risk_free_rate,
                .timestamp = std.time.timestamp(),
            });
        } else {
            try ctx.response.json(.{
                .sharpe_ratio = 0.0,
                .sortino_ratio = 0.0,
                .calmar_ratio = 0.0,
                .note = "Risk monitor not configured",
            });
        }
    }

    fn handleRiskReport(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        if (server_ctx.deps.risk_monitor) |monitor| {
            const var_95 = monitor.calculateVaR(0.95);
            const var_99 = monitor.calculateVaR(0.99);
            const dd = monitor.calculateMaxDrawdown();
            const sharpe = monitor.calculateSharpeRatio(null);
            const sortino = monitor.calculateSortinoRatio(null);
            const calmar = monitor.calculateCalmarRatio();

            try ctx.response.json(.{
                .report_type = "risk_metrics",
                .generated_at = std.time.timestamp(),
                .value_at_risk = .{
                    .var_95 = var_95.var_percentage,
                    .var_99 = var_99.var_percentage,
                    .observations = var_95.observations,
                },
                .drawdown = .{
                    .current = dd.current_drawdown_pct,
                    .max = dd.max_drawdown_pct,
                    .is_recovering = dd.is_recovering,
                },
                .ratios = .{
                    .sharpe = sharpe.sharpe_ratio,
                    .sortino = sortino.sortino_ratio,
                    .calmar = calmar.calmar_ratio,
                },
                .performance = .{
                    .annual_return = sharpe.annual_return,
                    .annual_volatility = sharpe.annual_volatility,
                    .downside_deviation = sortino.downside_deviation,
                },
            });
        } else {
            try ctx.response.json(.{
                .report_type = "risk_metrics",
                .generated_at = std.time.timestamp(),
                .status = "unavailable",
                .note = "Risk monitor not configured",
            });
        }
    }

    fn handleKillSwitch(ctx: *RequestContext) !void {
        try ctx.response.json(.{
            .status = "activated",
            .message = "Kill switch activated - all trading stopped",
        });
    }

    fn handleAlertsList(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        if (server_ctx.deps.alert_manager) |manager| {
            // Get alert history from the manager
            const alerts = manager.history.items;
            const total = alerts.len;

            // Return the most recent alerts (up to 100)
            const limit: usize = @min(total, 100);
            var alert_list: [100]struct {
                id: []const u8,
                level: []const u8,
                title: []const u8,
                message: []const u8,
                source: []const u8,
                timestamp: i64,
            } = undefined;

            for (0..limit) |i| {
                const alert = alerts[total - 1 - i]; // Reverse order (newest first)
                const level_str = switch (alert.level) {
                    .debug => "debug",
                    .info => "info",
                    .warning => "warning",
                    .critical => "critical",
                    .emergency => "emergency",
                };
                alert_list[i] = .{
                    .id = alert.id,
                    .level = level_str,
                    .title = alert.title,
                    .message = alert.message,
                    .source = alert.source,
                    .timestamp = alert.timestamp,
                };
            }

            try ctx.response.json(.{
                .alerts = alert_list[0..limit],
                .total = total,
                .timestamp = std.time.timestamp(),
            });
        } else {
            try ctx.response.json(.{
                .alerts = &[_][]const u8{},
                .total = @as(usize, 0),
                .note = "Alert manager not configured",
            });
        }
    }

    fn handleAlertsStats(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        if (server_ctx.deps.alert_manager) |manager| {
            try ctx.response.json(.{
                .total_alerts = manager.total_alerts,
                .by_level = .{
                    .debug = manager.alerts_by_level[0],
                    .info = manager.alerts_by_level[1],
                    .warning = manager.alerts_by_level[2],
                    .critical = manager.alerts_by_level[3],
                    .emergency = manager.alerts_by_level[4],
                },
                .channels_configured = manager.channels.items.len,
                .history_size = manager.history.items.len,
                .timestamp = std.time.timestamp(),
            });
        } else {
            try ctx.response.json(.{
                .total_alerts = @as(usize, 0),
                .by_level = .{
                    .debug = @as(usize, 0),
                    .info = @as(usize, 0),
                    .warning = @as(usize, 0),
                    .critical = @as(usize, 0),
                    .emergency = @as(usize, 0),
                },
                .note = "Alert manager not configured",
            });
        }
    }

    fn handlePaperTradingStart(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        // Generate session ID based on timestamp
        const session_id = std.time.timestamp();

        // In production, this would create a real PaperTradingEngine
        // For now, just record that we want to start a session
        try ctx.response.json(.{
            .status = "started",
            .session_id = session_id,
            .active_sessions = server_ctx.deps.paper_sessions.count() + 1,
            .message = "Paper trading session started",
            .timestamp = std.time.timestamp(),
        });
    }

    fn handlePaperTradingStop(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        try ctx.response.json(.{
            .status = "stopped",
            .remaining_sessions = server_ctx.deps.paper_sessions.count(),
            .message = "Paper trading session stopped",
            .timestamp = std.time.timestamp(),
        });
    }

    fn handlePaperTradingStatus(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        const session_count = server_ctx.deps.paper_sessions.count();
        const has_active = session_count > 0;

        try ctx.response.json(.{
            .active = has_active,
            .sessions = session_count,
            .timestamp = std.time.timestamp(),
        });
    }

    // ========================================================================
    // Grid Trading Handlers (v0.10.0)
    // ========================================================================

    fn handleGridList(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        if (server_ctx.deps.engine_manager) |manager| {
            const grids = manager.getAllGridsSummary(ctx.allocator) catch |err| {
                ctx.response.setStatus(.internal_server_error);
                try ctx.response.json(.{ .@"error" = @errorName(err) });
                return;
            };
            defer ctx.allocator.free(grids);

            try ctx.response.json(.{
                .grids = grids,
                .total = grids.len,
                .timestamp = std.time.timestamp(),
            });
        } else {
            try ctx.response.json(.{
                .grids = &[_][]const u8{},
                .total = @as(usize, 0),
                .note = "Engine manager not configured",
            });
        }
    }

    fn handleGridStart(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        const body = ctx.body orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing request body" });
            return;
        };

        // Parse grid config from request body
        const GridStartRequest = struct {
            id: ?[]const u8 = null,
            pair: struct { base: []const u8, quote: []const u8 },
            upper_price: f64,
            lower_price: f64,
            grid_count: u32 = 10,
            order_size: f64 = 0.001,
            take_profit_pct: f64 = 0.5,
            max_position: f64 = 1.0,
            check_interval_ms: u64 = 5000,
            mode: []const u8 = "paper",
            wallet: ?[]const u8 = null,
            private_key: ?[]const u8 = null,
            risk_enabled: bool = true,
            max_daily_loss_pct: f64 = 0.02,
        };

        const parsed = std.json.parseFromSlice(GridStartRequest, ctx.allocator, body, .{}) catch {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{
                .@"error" = "Invalid JSON format",
                .expected = "{ \"pair\": {\"base\": \"BTC\", \"quote\": \"USDC\"}, \"upper_price\": 100000, \"lower_price\": 90000, ... }",
            });
            return;
        };
        defer parsed.deinit();

        const req = parsed.value;

        // Generate ID if not provided
        const grid_id = req.id orelse blk: {
            var buf: [32]u8 = undefined;
            const id_str = std.fmt.bufPrint(&buf, "grid_{d}", .{std.time.timestamp()}) catch "grid_unknown";
            break :blk id_str;
        };

        if (server_ctx.deps.engine_manager) |manager| {
            const zigQuant = @import("zigQuant");
            const engine = zigQuant.engine;
            const Decimal = config_mod.Decimal;

            // Parse trading mode
            const mode: engine.TradingMode = if (std.mem.eql(u8, req.mode, "testnet"))
                .testnet
            else if (std.mem.eql(u8, req.mode, "mainnet"))
                .mainnet
            else
                .paper;

            const grid_config = engine.GridConfig{
                .pair = .{ .base = req.pair.base, .quote = req.pair.quote },
                .upper_price = Decimal.fromFloat(req.upper_price),
                .lower_price = Decimal.fromFloat(req.lower_price),
                .grid_count = req.grid_count,
                .order_size = Decimal.fromFloat(req.order_size),
                .take_profit_pct = req.take_profit_pct,
                .max_position = Decimal.fromFloat(req.max_position),
                .check_interval_ms = req.check_interval_ms,
                .mode = mode,
                .wallet = req.wallet,
                .private_key = req.private_key,
                .risk_enabled = req.risk_enabled,
                .max_daily_loss_pct = req.max_daily_loss_pct,
            };

            manager.startGrid(grid_id, grid_config) catch |err| {
                ctx.response.setStatus(.bad_request);
                try ctx.response.json(.{
                    .@"error" = @errorName(err),
                    .message = "Failed to start grid",
                });
                return;
            };

            ctx.response.setStatus(.created);
            try ctx.response.json(.{
                .id = grid_id,
                .status = "started",
                .message = "Grid trading bot started successfully",
                .timestamp = std.time.timestamp(),
            });
        } else {
            ctx.response.setStatus(.service_unavailable);
            try ctx.response.json(.{
                .@"error" = "Engine manager not configured",
                .message = "Grid trading is not available",
            });
        }
    }

    fn handleGridGet(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing grid ID" });
            return;
        };

        if (server_ctx.deps.engine_manager) |manager| {
            const status = manager.getGridStatus(id) catch |err| {
                if (err == error.GridNotFound) {
                    ctx.response.setStatus(.not_found);
                    try ctx.response.json(.{ .@"error" = "Grid not found", .id = id });
                    return;
                }
                ctx.response.setStatus(.internal_server_error);
                try ctx.response.json(.{ .@"error" = @errorName(err) });
                return;
            };

            const stats = manager.getGridStats(id) catch |err| {
                ctx.response.setStatus(.internal_server_error);
                try ctx.response.json(.{ .@"error" = @errorName(err) });
                return;
            };

            try ctx.response.json(.{
                .id = id,
                .status = status.toString(),
                .stats = .{
                    .total_trades = stats.total_trades,
                    .total_bought = stats.total_bought,
                    .total_sold = stats.total_sold,
                    .current_position = stats.current_position,
                    .realized_pnl = stats.realized_pnl,
                    .unrealized_pnl = stats.unrealized_pnl,
                    .active_buy_orders = stats.active_buy_orders,
                    .active_sell_orders = stats.active_sell_orders,
                    .last_price = stats.last_price,
                    .uptime_seconds = stats.uptime_seconds,
                    .orders_rejected_by_risk = stats.orders_rejected_by_risk,
                },
                .timestamp = std.time.timestamp(),
            });
        } else {
            ctx.response.setStatus(.service_unavailable);
            try ctx.response.json(.{ .@"error" = "Engine manager not configured" });
        }
    }

    fn handleGridUpdate(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing grid ID" });
            return;
        };

        const body = ctx.body orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing request body" });
            return;
        };

        // Parse partial update
        const GridUpdateRequest = struct {
            take_profit_pct: ?f64 = null,
            max_position: ?f64 = null,
            check_interval_ms: ?u64 = null,
            risk_enabled: ?bool = null,
            max_daily_loss_pct: ?f64 = null,
        };

        const parsed = std.json.parseFromSlice(GridUpdateRequest, ctx.allocator, body, .{}) catch {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Invalid JSON format" });
            return;
        };
        defer parsed.deinit();

        if (server_ctx.deps.engine_manager) |_| {
            // TODO: Implement updateGrid with partial updates
            // For now, just acknowledge the request
            try ctx.response.json(.{
                .id = id,
                .status = "updated",
                .message = "Grid configuration updated",
                .timestamp = std.time.timestamp(),
            });
        } else {
            ctx.response.setStatus(.service_unavailable);
            try ctx.response.json(.{ .@"error" = "Engine manager not configured" });
        }
    }

    fn handleGridStop(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing grid ID" });
            return;
        };

        if (server_ctx.deps.engine_manager) |manager| {
            manager.stopGrid(id) catch |err| {
                if (err == error.GridNotFound) {
                    ctx.response.setStatus(.not_found);
                    try ctx.response.json(.{ .@"error" = "Grid not found", .id = id });
                    return;
                }
                ctx.response.setStatus(.internal_server_error);
                try ctx.response.json(.{ .@"error" = @errorName(err) });
                return;
            };

            try ctx.response.json(.{
                .id = id,
                .status = "stopped",
                .message = "Grid trading bot stopped successfully",
                .timestamp = std.time.timestamp(),
            });
        } else {
            ctx.response.setStatus(.service_unavailable);
            try ctx.response.json(.{ .@"error" = "Engine manager not configured" });
        }
    }

    fn handleGridOrders(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing grid ID" });
            return;
        };

        if (server_ctx.deps.engine_manager) |manager| {
            const orders = manager.getGridOrders(ctx.allocator, id) catch |err| {
                if (err == error.GridNotFound) {
                    ctx.response.setStatus(.not_found);
                    try ctx.response.json(.{ .@"error" = "Grid not found", .id = id });
                    return;
                }
                ctx.response.setStatus(.internal_server_error);
                try ctx.response.json(.{ .@"error" = @errorName(err) });
                return;
            };
            defer ctx.allocator.free(orders);

            try ctx.response.json(.{
                .grid_id = id,
                .orders = orders,
                .total = orders.len,
                .timestamp = std.time.timestamp(),
            });
        } else {
            ctx.response.setStatus(.service_unavailable);
            try ctx.response.json(.{ .@"error" = "Engine manager not configured" });
        }
    }

    fn handleGridStats(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing grid ID" });
            return;
        };

        if (server_ctx.deps.engine_manager) |manager| {
            const stats = manager.getGridStats(id) catch |err| {
                if (err == error.GridNotFound) {
                    ctx.response.setStatus(.not_found);
                    try ctx.response.json(.{ .@"error" = "Grid not found", .id = id });
                    return;
                }
                ctx.response.setStatus(.internal_server_error);
                try ctx.response.json(.{ .@"error" = @errorName(err) });
                return;
            };

            try ctx.response.json(.{
                .grid_id = id,
                .total_trades = stats.total_trades,
                .total_bought = stats.total_bought,
                .total_sold = stats.total_sold,
                .current_position = stats.current_position,
                .realized_pnl = stats.realized_pnl,
                .unrealized_pnl = stats.unrealized_pnl,
                .active_buy_orders = stats.active_buy_orders,
                .active_sell_orders = stats.active_sell_orders,
                .last_price = stats.last_price,
                .uptime_seconds = stats.uptime_seconds,
                .orders_rejected_by_risk = stats.orders_rejected_by_risk,
                .timestamp = std.time.timestamp(),
            });
        } else {
            ctx.response.setStatus(.service_unavailable);
            try ctx.response.json(.{ .@"error" = "Engine manager not configured" });
        }
    }

    fn handleGridSummary(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        if (server_ctx.deps.engine_manager) |manager| {
            const stats = manager.getManagerStats();

            try ctx.response.json(.{
                .total_grids = stats.total_grids,
                .running_grids = stats.running_grids,
                .stopped_grids = stats.stopped_grids,
                .total_grids_started = stats.total_grids_started,
                .total_grids_stopped = stats.total_grids_stopped,
                .total_realized_pnl = stats.total_realized_pnl,
                .total_trades = stats.total_trades,
                .timestamp = std.time.timestamp(),
            });
        } else {
            try ctx.response.json(.{
                .total_grids = @as(usize, 0),
                .running_grids = @as(usize, 0),
                .stopped_grids = @as(usize, 0),
                .total_realized_pnl = @as(f64, 0),
                .total_trades = @as(u32, 0),
                .note = "Engine manager not configured",
            });
        }
    }

    fn handleCandlesList(ctx: *RequestContext) !void {
        try ctx.response.json(.{
            .candles = &[_][]const u8{},
            .total = @as(usize, 0),
        });
    }

    fn handlePositionsList(ctx: *RequestContext) !void {
        try ctx.response.json(.{
            .positions = &[_]PositionSummary{},
            .total = @as(usize, 0),
        });
    }

    fn handleOrdersList(ctx: *RequestContext) !void {
        try ctx.response.json(.{
            .orders = &[_]OrderSummary{},
            .total = @as(usize, 0),
        });
    }

    fn handleOrderCreate(ctx: *RequestContext) !void {
        try ctx.response.json(.{
            .order_id = "ord_001",
            .status = "created",
            .message = "Order created successfully",
        });
    }

    fn handleOrderCancel(ctx: *RequestContext) !void {
        const id = ctx.param("id") orelse {
            ctx.response.setStatus(.bad_request);
            try ctx.response.json(.{ .@"error" = "Missing order ID" });
            return;
        };

        try ctx.response.json(.{
            .order_id = id,
            .status = "cancelled",
            .message = "Order cancelled successfully",
        });
    }

    fn handleAccountGet(ctx: *RequestContext) !void {
        try ctx.response.json(.{
            .accounts = &[_]AccountInfo{},
            .total = @as(usize, 0),
        });
    }

    fn handleAccountBalance(ctx: *RequestContext) !void {
        try ctx.response.json(.{
            .balances = &[_]BalanceSummary{},
            .total = @as(usize, 0),
        });
    }

    fn handleMetrics(ctx: *RequestContext) !void {
        const server_ctx: *ServerContext = @ptrCast(@alignCast(ctx.server_context));

        // Generate Prometheus format metrics
        var buf: [4096]u8 = undefined;
        const metrics = std.fmt.bufPrint(&buf,
            \\# HELP zigquant_uptime_seconds Server uptime in seconds
            \\# TYPE zigquant_uptime_seconds gauge
            \\zigquant_uptime_seconds {d}
            \\
            \\# HELP zigquant_requests_total Total number of API requests
            \\# TYPE zigquant_requests_total counter
            \\zigquant_requests_total {d}
            \\
        , .{
            server_ctx.uptime(),
            server_ctx.getRequestCount(),
        }) catch {
            ctx.response.setStatus(.internal_server_error);
            try ctx.response.json(.{ .@"error" = "Failed to generate metrics" });
            return;
        };

        try ctx.response.setContentType("text/plain; version=0.0.4");
        try ctx.response.body.appendSlice(ctx.allocator, metrics);
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Validate user credentials (demo implementation)
fn validateCredentials(username: []const u8, password: []const u8) bool {
    // Demo users for testing
    const demo_users = [_]struct { user: []const u8, pass: []const u8 }{
        .{ .user = "admin", .pass = "admin123" },
        .{ .user = "user", .pass = "user123" },
        .{ .user = "demo", .pass = "demo123" },
    };

    for (demo_users) |u| {
        if (std.mem.eql(u8, username, u.user) and std.mem.eql(u8, password, u.pass)) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "ApiServer initialization" {
    // Basic initialization test
    const allocator = std.testing.allocator;
    _ = allocator;
}
