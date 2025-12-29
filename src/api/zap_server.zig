//! zigQuant API Server (v2.0.0) - Based on Zap
//!
//! High-performance REST API server built on zap framework.
//! Provides HTTP/WebSocket endpoints for trading operations.
//!
//! Features:
//! - High-performance HTTP server (facil.io under the hood)
//! - JWT authentication
//! - Grid Trading API
//! - Health check endpoints
//!
//! Usage:
//!   const server = try ZapServer.init(allocator, config, deps);
//!   defer server.deinit();
//!   try server.start();

const std = @import("std");
const zap = @import("zap");
const Allocator = std.mem.Allocator;

// Import zigQuant types via relative imports (since this file is part of the zigQuant module)
const engine_mod = @import("../engine/mod.zig");
const EngineManager = engine_mod.EngineManager;
const GridConfig = engine_mod.GridConfig;
const TradingMode = engine_mod.TradingMode;
const GridStatus = engine_mod.GridStatus;
const GridStats = engine_mod.GridStats;
const BacktestRequest = engine_mod.BacktestRequest;
const BacktestStatus = engine_mod.BacktestStatus;

const exchange_types = @import("../exchange/types.zig");
const TradingPair = exchange_types.TradingPair;

const decimal_mod = @import("../core/decimal.zig");
const Decimal = decimal_mod.Decimal;

const logger_mod = @import("../core/logger.zig");
const Logger = logger_mod.Logger;

// ============================================================================
// Embedded JWT Implementation (to avoid cross-module import conflicts)
// ============================================================================

/// JWT payload structure
pub const JwtPayload = struct {
    sub: []const u8,
    iat: i64,
    exp: i64,
    iss: ?[]const u8 = null,
};

/// JWT Manager for generating and verifying tokens
pub const JwtManager = struct {
    allocator: Allocator,
    secret: []const u8,
    expiry_seconds: i64,
    issuer: ?[]const u8,

    pub fn init(
        allocator: Allocator,
        secret: []const u8,
        expiry_hours: u32,
        issuer: ?[]const u8,
    ) JwtManager {
        return .{
            .allocator = allocator,
            .secret = secret,
            .expiry_seconds = @as(i64, expiry_hours) * 3600,
            .issuer = issuer,
        };
    }

    pub fn generateToken(self: *const JwtManager, user_id: []const u8) ![]const u8 {
        const now = std.time.timestamp();
        const header = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";
        const header_b64 = try base64UrlEncode(self.allocator, header);
        defer self.allocator.free(header_b64);

        var payload_buf: [512]u8 = undefined;
        const payload = if (self.issuer) |iss|
            try std.fmt.bufPrint(&payload_buf, "{{\"sub\":\"{s}\",\"iat\":{d},\"exp\":{d},\"iss\":\"{s}\"}}", .{ user_id, now, now + self.expiry_seconds, iss })
        else
            try std.fmt.bufPrint(&payload_buf, "{{\"sub\":\"{s}\",\"iat\":{d},\"exp\":{d}}}", .{ user_id, now, now + self.expiry_seconds });

        const payload_b64 = try base64UrlEncode(self.allocator, payload);
        defer self.allocator.free(payload_b64);

        const message = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ header_b64, payload_b64 });
        defer self.allocator.free(message);

        const signature = try hmacSha256(self.allocator, message, self.secret);
        defer self.allocator.free(signature);

        const signature_b64 = try base64UrlEncode(self.allocator, signature);
        defer self.allocator.free(signature_b64);

        return try std.fmt.allocPrint(self.allocator, "{s}.{s}.{s}", .{ header_b64, payload_b64, signature_b64 });
    }

    pub fn verifyToken(self: *const JwtManager, token: []const u8) !JwtPayload {
        var parts_iter = std.mem.splitScalar(u8, token, '.');
        const header_b64 = parts_iter.next() orelse return error.InvalidToken;
        const payload_b64 = parts_iter.next() orelse return error.InvalidToken;
        const signature_b64 = parts_iter.next() orelse return error.InvalidToken;
        if (parts_iter.next() != null) return error.InvalidToken;

        const message = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ header_b64, payload_b64 });
        defer self.allocator.free(message);

        const expected_sig = try hmacSha256(self.allocator, message, self.secret);
        defer self.allocator.free(expected_sig);

        const expected_sig_b64 = try base64UrlEncode(self.allocator, expected_sig);
        defer self.allocator.free(expected_sig_b64);

        if (!std.mem.eql(u8, signature_b64, expected_sig_b64)) {
            return error.InvalidSignature;
        }

        const payload_json = try base64UrlDecode(self.allocator, payload_b64);
        defer self.allocator.free(payload_json);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, payload_json, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        const sub = obj.get("sub") orelse return error.MissingSubject;
        const iat = obj.get("iat") orelse return error.MissingIssuedAt;
        const exp = obj.get("exp") orelse return error.MissingExpiration;

        const exp_time = switch (exp) {
            .integer => |i| i,
            else => return error.InvalidExpiration,
        };

        if (std.time.timestamp() > exp_time) {
            return error.TokenExpired;
        }

        const sub_str = switch (sub) {
            .string => |s| s,
            else => return error.InvalidSubject,
        };

        const iat_time = switch (iat) {
            .integer => |i| i,
            else => return error.InvalidIssuedAt,
        };

        var iss_str: ?[]const u8 = null;
        if (obj.get("iss")) |iss| {
            iss_str = switch (iss) {
                .string => |s| s,
                else => null,
            };
        }

        // Copy strings to owned memory since parsed will be deinitialized
        const sub_copy = try self.allocator.dupe(u8, sub_str);
        errdefer self.allocator.free(sub_copy);

        var iss_copy: ?[]const u8 = null;
        if (iss_str) |iss| {
            iss_copy = try self.allocator.dupe(u8, iss);
        }

        return JwtPayload{
            .sub = sub_copy,
            .iat = iat_time,
            .exp = exp_time,
            .iss = iss_copy,
        };
    }

    /// Free memory allocated for a JWT payload
    pub fn freePayload(self: *const JwtManager, payload: *const JwtPayload) void {
        self.allocator.free(payload.sub);
        if (payload.iss) |iss| {
            self.allocator.free(iss);
        }
    }
};

fn base64UrlEncode(allocator: Allocator, data: []const u8) ![]const u8 {
    const codecs = std.base64.url_safe_no_pad;
    const size = codecs.Encoder.calcSize(data.len);
    const result = try allocator.alloc(u8, size);
    _ = codecs.Encoder.encode(result, data);
    return result;
}

fn base64UrlDecode(allocator: Allocator, encoded: []const u8) ![]const u8 {
    const codecs = std.base64.url_safe_no_pad;
    const size = try codecs.Decoder.calcSizeForSlice(encoded);
    const result = try allocator.alloc(u8, size);
    try codecs.Decoder.decode(result, encoded);
    return result;
}

fn hmacSha256(allocator: Allocator, message: []const u8, key: []const u8) ![]const u8 {
    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    var out: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&out, message, key);
    const result = try allocator.alloc(u8, HmacSha256.mac_length);
    @memcpy(result, &out);
    return result;
}

// ============================================================================
// Configuration Types
// ============================================================================

/// API Server Configuration
pub const Config = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 8080,
    /// Number of worker processes. Use 1 for single-process mode (required for shared state).
    /// Multi-worker mode spawns separate processes that don't share memory.
    workers: i16 = 1,
    threads: i16 = 2,
    jwt_secret: []const u8,
    jwt_expiry_hours: u32 = 24,
    log_requests: bool = true,
    public_folder: ?[]const u8 = null,
    max_body_size: usize = 1024 * 1024,

    pub fn validate(self: Config) !void {
        if (self.jwt_secret.len < 32) return error.JwtSecretTooShort;
        if (self.port == 0) return error.InvalidPort;
    }
};

/// API Dependencies
pub const Dependencies = struct {
    allocator: Allocator,
    engine_manager: ?*EngineManager = null,

    pub fn init(allocator: Allocator) Dependencies {
        return .{ .allocator = allocator };
    }

    pub fn setEngineManager(self: *Dependencies, manager: *EngineManager) void {
        self.engine_manager = manager;
    }
};

/// Server Context
pub const ServerContext = struct {
    allocator: Allocator,
    config: Config,
    deps: *Dependencies,
    start_time: i64,
    request_count: std.atomic.Value(u64),
    jwt_manager: JwtManager,

    pub fn uptime(self: *const ServerContext) i64 {
        return std.time.timestamp() - self.start_time;
    }

    pub fn incrementRequests(self: *ServerContext) u64 {
        return self.request_count.fetchAdd(1, .monotonic);
    }

    pub fn getRequestCount(self: *const ServerContext) u64 {
        return self.request_count.load(.monotonic);
    }
};

// Global context
var global_context: ?*ServerContext = null;

// ============================================================================
// Zap Server
// ============================================================================

pub const ZapServer = struct {
    allocator: Allocator,
    config: Config,
    deps: *Dependencies,
    context: *ServerContext,
    listener: zap.HttpListener,

    const Self = @This();

    pub fn init(allocator: Allocator, config: Config, deps: *Dependencies) !*Self {
        try config.validate();

        const context = try allocator.create(ServerContext);
        errdefer allocator.destroy(context);

        context.* = .{
            .allocator = allocator,
            .config = config,
            .deps = deps,
            .start_time = std.time.timestamp(),
            .request_count = std.atomic.Value(u64).init(0),
            .jwt_manager = JwtManager.init(allocator, config.jwt_secret, config.jwt_expiry_hours, "zigquant"),
        };

        global_context = context;

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Create simple HTTP listener with manual routing
        const listener = zap.HttpListener.init(.{
            .port = config.port,
            .log = config.log_requests,
            .public_folder = config.public_folder,
            .max_body_size = config.max_body_size,
            .on_request = handleRequest,
        });

        self.* = .{
            .allocator = allocator,
            .config = config,
            .deps = deps,
            .context = context,
            .listener = listener,
        };

        return self;
    }

    pub fn start(self: *Self) !void {
        std.log.info("zigQuant API Server v2.0.0 (zap)", .{});
        std.log.info("Listening on http://{s}:{d}", .{ self.config.host, self.config.port });
        std.log.info("Press Ctrl+C to stop", .{});

        try self.listener.listen();

        zap.start(.{
            .threads = self.config.threads,
            .workers = self.config.workers,
        });
    }

    pub fn stop(_: *Self) void {
        zap.stop();
    }

    pub fn deinit(self: *Self) void {
        // HttpListener doesn't have deinit in zap 0.10.6
        global_context = null;
        self.allocator.destroy(self.context);
        self.allocator.destroy(self);
    }
};

// ============================================================================
// Request Handler with Manual Routing
// ============================================================================

fn handleRequest(r: zap.Request) !void {
    const ctx = global_context orelse {
        try r.sendJson(
            \\{"error":"Server not initialized"}
        );
        return;
    };

    _ = ctx.incrementRequests();

    const path = r.path orelse "/";
    const method = zap.http.methodToEnum(r.method);

    // Route the request - support both /api/v1 and /api/v2 prefixes
    if (std.mem.eql(u8, path, "/health")) {
        try handleHealth(r, ctx);
    } else if (std.mem.eql(u8, path, "/version")) {
        try handleVersion(r);
    } else if (std.mem.eql(u8, path, "/ready")) {
        try handleReady(r, ctx);
    } else if (std.mem.eql(u8, path, "/metrics")) {
        try handleMetrics(r, ctx);
    }
    // Auth endpoints (v1 and v2)
    else if (std.mem.startsWith(u8, path, "/api/v1/auth/") or std.mem.startsWith(u8, path, "/api/v2/auth/")) {
        try handleAuth(r, ctx, path, method);
    }
    // Grid endpoints (v1 and v2)
    else if (std.mem.eql(u8, path, "/api/v1/grid/summary") or std.mem.eql(u8, path, "/api/v2/grid/summary")) {
        try handleGridSummary(r, ctx);
    } else if (std.mem.eql(u8, path, "/api/v1/grid") or std.mem.eql(u8, path, "/api/v2/grid")) {
        try handleGrid(r, ctx, method);
    } else if (std.mem.startsWith(u8, path, "/api/v1/grid/") or std.mem.startsWith(u8, path, "/api/v2/grid/")) {
        try handleGridDetail(r, ctx, path, method);
    }
    // V2 Backtest endpoints
    else if (std.mem.eql(u8, path, "/api/v2/backtest/run")) {
        try handleBacktestRun(r, ctx, method);
    } else if (std.mem.startsWith(u8, path, "/api/v2/backtest/")) {
        try handleBacktestDetail(r, ctx, path, method);
    }
    // V2 System endpoints
    else if (std.mem.eql(u8, path, "/api/v2/system/kill-switch")) {
        try handleKillSwitch(r, ctx, method);
    } else if (std.mem.eql(u8, path, "/api/v2/system/health")) {
        try handleSystemHealth(r, ctx);
    } else if (std.mem.eql(u8, path, "/api/v2/system/logs")) {
        try handleSystemLogs(r, ctx);
    } else {
        r.setStatus(.not_found);
        try r.sendJson(
            \\{"error":"Not Found"}
        );
    }
}

fn handleHealth(r: zap.Request, ctx: *ServerContext) !void {
    var buf: [512]u8 = undefined;
    const json = try std.fmt.bufPrint(&buf,
        \\{{"status":"healthy","version":"2.0.0","uptime":{d},"requests":{d},"timestamp":{d}}}
    , .{ ctx.uptime(), ctx.getRequestCount(), std.time.timestamp() });
    try r.setContentType(.JSON);
    try r.sendBody(json);
}

fn handleVersion(r: zap.Request) !void {
    try r.setContentType(.JSON);
    try r.sendBody(
        \\{"name":"zigQuant","version":"2.0.0","api_version":"v1","framework":"zap"}
    );
}

fn handleReady(r: zap.Request, ctx: *ServerContext) !void {
    const jwt_configured = ctx.config.jwt_secret.len >= 32;
    if (jwt_configured) {
        try r.setContentType(.JSON);
        try r.sendBody(
            \\{"ready":true,"checks":{"jwt_configured":true,"server_running":true}}
        );
    } else {
        r.setStatus(.service_unavailable);
        try r.sendJson(
            \\{"ready":false,"checks":{"jwt_configured":false,"server_running":true}}
        );
    }
}

fn handleMetrics(r: zap.Request, ctx: *ServerContext) !void {
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
    , .{ ctx.uptime(), ctx.getRequestCount() }) catch "# Error generating metrics\n";

    try r.setHeader("content-type", "text/plain; version=0.0.4");
    try r.sendBody(metrics);
}

fn handleAuth(r: zap.Request, ctx: *ServerContext, path: []const u8, method: zap.http.Method) !void {
    if (std.mem.endsWith(u8, path, "/login") and method == .POST) {
        const body = r.body orelse {
            r.setStatus(.bad_request);
            try r.sendJson(
                \\{"error":"Missing request body"}
            );
            return;
        };

        const LoginRequest = struct { username: []const u8, password: []const u8 };
        const parsed = std.json.parseFromSlice(LoginRequest, ctx.allocator, body, .{}) catch {
            r.setStatus(.bad_request);
            try r.sendJson(
                \\{"error":"Invalid JSON format"}
            );
            return;
        };
        defer parsed.deinit();

        if (!validateCredentials(parsed.value.username, parsed.value.password)) {
            r.setStatus(.unauthorized);
            try r.sendJson(
                \\{"error":"Invalid credentials"}
            );
            return;
        }

        const token = ctx.jwt_manager.generateToken(parsed.value.username) catch {
            r.setStatus(.internal_server_error);
            try r.sendJson(
                \\{"error":"Failed to generate token"}
            );
            return;
        };

        var buf: [1024]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"token":"{s}","expires_in":{d},"token_type":"Bearer"}}
        , .{ token, ctx.jwt_manager.expiry_seconds }) catch
            \\{"error":"buffer overflow"}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else if (std.mem.endsWith(u8, path, "/me") and method == .GET) {
        if (r.getHeader("authorization")) |auth_header| {
            if (std.mem.startsWith(u8, auth_header, "Bearer ")) {
                const token = auth_header[7..];
                if (ctx.jwt_manager.verifyToken(token)) |payload| {
                    defer ctx.jwt_manager.freePayload(&payload);
                    var buf: [512]u8 = undefined;
                    const json = std.fmt.bufPrint(&buf,
                        \\{{"user_id":"{s}","issued_at":{d},"expires_at":{d}}}
                    , .{ payload.sub, payload.iat, payload.exp }) catch
                        \\{"error":"buffer overflow"}
                    ;
                    try r.setContentType(.JSON);
                    try r.sendBody(json);
                    return;
                } else |_| {}
            }
        }
        r.setStatus(.unauthorized);
        try r.sendJson(
            \\{"error":"Invalid or missing token"}
        );
    } else if (std.mem.endsWith(u8, path, "/refresh") and method == .POST) {
        // POST /api/v1/auth/refresh - Refresh JWT token
        const auth_header = r.getHeader("authorization") orelse {
            r.setStatus(.unauthorized);
            try r.sendJson(
                \\{"error":"Missing authorization header"}
            );
            return;
        };

        if (!std.mem.startsWith(u8, auth_header, "Bearer ")) {
            r.setStatus(.unauthorized);
            try r.sendJson(
                \\{"error":"Invalid authorization format. Expected: Bearer <token>"}
            );
            return;
        }

        const old_token = auth_header[7..];
        const payload = ctx.jwt_manager.verifyToken(old_token) catch |err| {
            r.setStatus(.unauthorized);
            var buf: [256]u8 = undefined;
            const json = if (err == error.TokenExpired)
                \\{"error":"Token expired. Please login again."}
            else
                std.fmt.bufPrint(&buf,
                    \\{{"error":"Invalid token: {s}"}}
                , .{@errorName(err)}) catch
                    \\{"error":"Invalid token"}
                ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };
        defer ctx.jwt_manager.freePayload(&payload);

        // Generate new token with same user ID
        const new_token = ctx.jwt_manager.generateToken(payload.sub) catch {
            r.setStatus(.internal_server_error);
            try r.sendJson(
                \\{"error":"Failed to generate new token"}
            );
            return;
        };

        var buf: [1024]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"token":"{s}","expires_in":{d},"token_type":"Bearer","refreshed":true}}
        , .{ new_token, ctx.jwt_manager.expiry_seconds }) catch
            \\{"error":"buffer overflow"}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else {
        r.setStatus(.not_found);
        try r.sendJson(
            \\{"error":"Not found"}
        );
    }
}

fn handleGrid(r: zap.Request, ctx: *ServerContext, method: zap.http.Method) !void {
    if (method == .GET) {
        // GET /api/v1/grid - List all grids
        if (ctx.deps.engine_manager) |manager| {
            const grids = manager.getAllGridsSummary(ctx.allocator) catch |err| {
                r.setStatus(.internal_server_error);
                var buf: [256]u8 = undefined;
                const json = std.fmt.bufPrint(&buf,
                    \\{{"error":"Failed to get grids: {s}"}}
                , .{@errorName(err)}) catch
                    \\{"error":"Failed to get grids"}
                ;
                try r.setContentType(.JSON);
                try r.sendBody(json);
                return;
            };
            defer ctx.allocator.free(grids);

            // Build JSON response
            var response = std.ArrayList(u8){};
            defer response.deinit(ctx.allocator);

            try response.appendSlice(ctx.allocator, "{\"grids\":[");
            for (grids, 0..) |grid, i| {
                if (i > 0) try response.append(ctx.allocator, ',');
                var grid_buf: [512]u8 = undefined;
                const grid_json = std.fmt.bufPrint(&grid_buf,
                    \\{{"id":"{s}","pair":"{s}/{s}","status":"{s}","mode":"{s}","realized_pnl":{d:.4},"position":{d:.6},"trades":{d},"uptime":{d}}}
                , .{
                    grid.id,
                    grid.pair.base,
                    grid.pair.quote,
                    grid.status,
                    grid.mode,
                    grid.realized_pnl,
                    grid.current_position,
                    grid.total_trades,
                    grid.uptime_seconds,
                }) catch continue;
                try response.appendSlice(ctx.allocator, grid_json);
            }
            var total_buf: [64]u8 = undefined;
            const total_json = std.fmt.bufPrint(&total_buf, "],\"total\":{d}}}", .{grids.len}) catch "]}";
            try response.appendSlice(ctx.allocator, total_json);

            try r.setContentType(.JSON);
            try r.sendBody(response.items);
        } else {
            try r.setContentType(.JSON);
            try r.sendBody(
                \\{"grids":[],"total":0,"note":"Engine manager not configured"}
            );
        }
    } else if (method == .POST) {
        // POST /api/v1/grid - Create new grid
        if (ctx.deps.engine_manager) |manager| {
            const body = r.body orelse {
                r.setStatus(.bad_request);
                try r.sendJson(
                    \\{"error":"Missing request body"}
                );
                return;
            };

            // Parse grid creation request
            const CreateGridRequest = struct {
                id: ?[]const u8 = null,
                pair_base: []const u8,
                pair_quote: []const u8,
                upper_price: f64,
                lower_price: f64,
                grid_count: u32,
                order_size: f64,
                take_profit_pct: f64 = 0.5,
                mode: []const u8 = "paper",
            };

            const parsed = std.json.parseFromSlice(CreateGridRequest, ctx.allocator, body, .{}) catch {
                r.setStatus(.bad_request);
                try r.sendJson(
                    \\{"error":"Invalid JSON format. Required: pair_base, pair_quote, upper_price, lower_price, grid_count, order_size"}
                );
                return;
            };
            defer parsed.deinit();

            const req = parsed.value;

            // Generate ID if not provided
            var id_buf: [32]u8 = undefined;
            const grid_id = req.id orelse blk: {
                const ts = std.time.timestamp();
                const formatted = std.fmt.bufPrint(&id_buf, "grid_{d}", .{ts}) catch "grid_new";
                break :blk formatted;
            };

            // Parse trading mode
            const mode: engine_mod.TradingMode = if (std.mem.eql(u8, req.mode, "mainnet"))
                .mainnet
            else if (std.mem.eql(u8, req.mode, "testnet"))
                .testnet
            else
                .paper;

            // Create grid config
            const grid_config = engine_mod.GridConfig{
                .pair = .{ .base = req.pair_base, .quote = req.pair_quote },
                .upper_price = Decimal.fromFloat(req.upper_price),
                .lower_price = Decimal.fromFloat(req.lower_price),
                .grid_count = req.grid_count,
                .order_size = Decimal.fromFloat(req.order_size),
                .take_profit_pct = req.take_profit_pct,
                .mode = mode,
            };

            // Validate config
            grid_config.validate() catch |err| {
                r.setStatus(.bad_request);
                var buf: [256]u8 = undefined;
                const json = std.fmt.bufPrint(&buf,
                    \\{{"error":"Invalid grid config: {s}"}}
                , .{@errorName(err)}) catch
                    \\{"error":"Invalid grid configuration"}
                ;
                try r.setContentType(.JSON);
                try r.sendBody(json);
                return;
            };

            // Start the grid
            manager.startGrid(grid_id, grid_config) catch |err| {
                r.setStatus(.internal_server_error);
                var buf: [256]u8 = undefined;
                const json = std.fmt.bufPrint(&buf,
                    \\{{"error":"Failed to start grid: {s}"}}
                , .{@errorName(err)}) catch
                    \\{"error":"Failed to start grid"}
                ;
                try r.setContentType(.JSON);
                try r.sendBody(json);
                return;
            };

            r.setStatus(.created);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"id":"{s}","status":"started","message":"Grid trading bot created and started"}}
            , .{grid_id}) catch
                \\{"status":"started"}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
        } else {
            r.setStatus(.service_unavailable);
            try r.sendJson(
                \\{"error":"Engine manager not configured"}
            );
        }
    } else {
        r.setStatus(.method_not_allowed);
        try r.sendJson(
            \\{"error":"Method not allowed"}
        );
    }
}

fn handleGridSummary(r: zap.Request, ctx: *ServerContext) !void {
    if (ctx.deps.engine_manager) |manager| {
        const stats = manager.getManagerStats();
        var buf: [512]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"total_grids":{d},"running_grids":{d},"stopped_grids":{d},"total_started":{d},"total_stopped":{d},"total_realized_pnl":{d:.4},"total_trades":{d}}}
        , .{
            stats.total_grids,
            stats.running_grids,
            stats.stopped_grids,
            stats.total_grids_started,
            stats.total_grids_stopped,
            stats.total_realized_pnl,
            stats.total_trades,
        }) catch
            \\{"error":"buffer overflow"}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else {
        try r.setContentType(.JSON);
        try r.sendBody(
            \\{"total_grids":0,"running_grids":0,"stopped_grids":0,"note":"Engine manager not configured"}
        );
    }
}

fn handleGridDetail(r: zap.Request, ctx: *ServerContext, path: []const u8, method: zap.http.Method) !void {
    const prefix = "/api/v1/grid/";
    const grid_id = path[prefix.len..];

    if (ctx.deps.engine_manager == null) {
        r.setStatus(.service_unavailable);
        try r.sendJson(
            \\{"error":"Engine manager not configured"}
        );
        return;
    }

    const manager = ctx.deps.engine_manager.?;

    if (method == .GET) {
        // GET /api/v1/grid/:id - Get grid details
        const status = manager.getGridStatus(grid_id) catch |err| {
            if (err == error.GridNotFound) {
                r.setStatus(.not_found);
                var buf: [256]u8 = undefined;
                const json = std.fmt.bufPrint(&buf,
                    \\{{"error":"Grid not found","id":"{s}"}}
                , .{grid_id}) catch
                    \\{"error":"Grid not found"}
                ;
                try r.setContentType(.JSON);
                try r.sendBody(json);
            } else {
                r.setStatus(.internal_server_error);
                try r.sendJson(
                    \\{"error":"Failed to get grid status"}
                );
            }
            return;
        };

        const stats = manager.getGridStats(grid_id) catch {
            r.setStatus(.internal_server_error);
            try r.sendJson(
                \\{"error":"Failed to get grid stats"}
            );
            return;
        };

        var buf: [1024]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"id":"{s}","status":"{s}","stats":{{"total_trades":{d},"realized_pnl":{d:.4},"unrealized_pnl":{d:.4},"current_position":{d:.6},"active_buy_orders":{d},"active_sell_orders":{d},"last_price":{d:.2},"uptime_seconds":{d}}}}}
        , .{
            grid_id,
            status.toString(),
            stats.total_trades,
            stats.realized_pnl,
            stats.unrealized_pnl,
            stats.current_position,
            stats.active_buy_orders,
            stats.active_sell_orders,
            stats.last_price,
            stats.uptime_seconds,
        }) catch
            \\{"error":"buffer overflow"}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else if (method == .DELETE) {
        // DELETE /api/v1/grid/:id - Stop and remove grid
        manager.stopGrid(grid_id) catch |err| {
            if (err == error.GridNotFound) {
                r.setStatus(.not_found);
                var buf: [256]u8 = undefined;
                const json = std.fmt.bufPrint(&buf,
                    \\{{"error":"Grid not found","id":"{s}"}}
                , .{grid_id}) catch
                    \\{"error":"Grid not found"}
                ;
                try r.setContentType(.JSON);
                try r.sendBody(json);
            } else {
                r.setStatus(.internal_server_error);
                var buf: [256]u8 = undefined;
                const json = std.fmt.bufPrint(&buf,
                    \\{{"error":"Failed to stop grid: {s}"}}
                , .{@errorName(err)}) catch
                    \\{"error":"Failed to stop grid"}
                ;
                try r.setContentType(.JSON);
                try r.sendBody(json);
            }
            return;
        };

        var buf: [256]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"id":"{s}","status":"stopped","message":"Grid trading bot stopped and removed"}}
        , .{grid_id}) catch
            \\{"status":"stopped"}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else {
        r.setStatus(.method_not_allowed);
        try r.sendJson(
            \\{"error":"Method not allowed"}
        );
    }
}

fn validateCredentials(username: []const u8, password: []const u8) bool {
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
// Backtest API Handlers
// ============================================================================

fn handleBacktestRun(r: zap.Request, ctx: *ServerContext, method: zap.http.Method) !void {
    if (method != .POST) {
        r.setStatus(.method_not_allowed);
        try r.sendJson(
            \\{"success":false,"error":{"code":"METHOD_NOT_ALLOWED","message":"Only POST allowed"}}
        );
        return;
    }

    if (ctx.deps.engine_manager == null) {
        r.setStatus(.service_unavailable);
        try r.sendJson(
            \\{"success":false,"error":{"code":"SERVICE_UNAVAILABLE","message":"Engine manager not configured"}}
        );
        return;
    }

    const manager = ctx.deps.engine_manager.?;

    const body = r.body orelse {
        r.setStatus(.bad_request);
        try r.sendJson(
            \\{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Missing request body"}}
        );
        return;
    };

    // Parse backtest request
    const CreateBacktestRequest = struct {
        strategy: []const u8,
        params: ?[]const u8 = null,
        symbol: []const u8,
        timeframe: []const u8,
        start_date: []const u8,
        end_date: []const u8,
        initial_capital: f64 = 10000,
        commission: f64 = 0.0005,
        slippage: f64 = 0.0001,
        data_file: ?[]const u8 = null,
    };

    const parsed = std.json.parseFromSlice(CreateBacktestRequest, ctx.allocator, body, .{}) catch {
        r.setStatus(.bad_request);
        try r.sendJson(
            \\{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Invalid JSON format"}}
        );
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;

    // Generate backtest ID
    var id_buf: [32]u8 = undefined;
    const ts = std.time.timestamp();
    const backtest_id = std.fmt.bufPrint(&id_buf, "bt_{d}", .{ts}) catch "bt_new";

    // Create backtest request
    const backtest_request = BacktestRequest{
        .strategy = req.strategy,
        .params = req.params,
        .symbol = req.symbol,
        .timeframe = req.timeframe,
        .start_date = req.start_date,
        .end_date = req.end_date,
        .initial_capital = req.initial_capital,
        .commission = req.commission,
        .slippage = req.slippage,
        .data_file = req.data_file,
    };

    // Start backtest
    manager.startBacktest(backtest_id, backtest_request) catch |err| {
        r.setStatus(.internal_server_error);
        var buf: [256]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":false,"error":{{"code":"INTERNAL_ERROR","message":"Failed to start backtest: {s}"}}}}
        , .{@errorName(err)}) catch
            \\{"success":false,"error":{"code":"INTERNAL_ERROR","message":"Failed to start backtest"}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
        return;
    };

    r.setStatus(.created);
    var buf: [256]u8 = undefined;
    const json = std.fmt.bufPrint(&buf,
        \\{{"success":true,"data":{{"id":"{s}","status":"queued","estimated_duration":30}}}}
    , .{backtest_id}) catch
        \\{"success":true,"data":{"status":"queued"}}
    ;
    try r.setContentType(.JSON);
    try r.sendBody(json);
}

fn handleBacktestDetail(r: zap.Request, ctx: *ServerContext, path: []const u8, method: zap.http.Method) !void {
    if (ctx.deps.engine_manager == null) {
        r.setStatus(.service_unavailable);
        try r.sendJson(
            \\{"success":false,"error":{"code":"SERVICE_UNAVAILABLE","message":"Engine manager not configured"}}
        );
        return;
    }

    const manager = ctx.deps.engine_manager.?;

    // Parse path: /api/v2/backtest/:id/action
    const prefix = "/api/v2/backtest/";
    const rest = path[prefix.len..];

    // Find the backtest ID and action
    var backtest_id: []const u8 = rest;
    var action: []const u8 = "";

    if (std.mem.indexOf(u8, rest, "/")) |idx| {
        backtest_id = rest[0..idx];
        action = rest[idx + 1 ..];
    }

    if (std.mem.eql(u8, action, "progress") and method == .GET) {
        // GET /api/v2/backtest/:id/progress
        const progress = manager.getBacktestProgress(backtest_id) catch |err| {
            if (err == error.BacktestNotFound) {
                r.setStatus(.not_found);
                try r.sendJson(
                    \\{"success":false,"error":{"code":"NOT_FOUND","message":"Backtest not found"}}
                );
            } else {
                r.setStatus(.internal_server_error);
                try r.sendJson(
                    \\{"success":false,"error":{"code":"INTERNAL_ERROR","message":"Failed to get progress"}}
                );
            }
            return;
        };

        var buf: [512]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"id":"{s}","progress":{d:.2},"trades_so_far":{d},"elapsed_seconds":{d}}}}}
        , .{ backtest_id, progress.progress, progress.trades_so_far, progress.elapsed_seconds }) catch
            \\{"success":true,"data":{}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else if (std.mem.eql(u8, action, "result") and method == .GET) {
        // GET /api/v2/backtest/:id/result
        const status = manager.getBacktestStatus(backtest_id) catch |err| {
            if (err == error.BacktestNotFound) {
                r.setStatus(.not_found);
                try r.sendJson(
                    \\{"success":false,"error":{"code":"NOT_FOUND","message":"Backtest not found"}}
                );
            } else {
                r.setStatus(.internal_server_error);
                try r.sendJson(
                    \\{"success":false,"error":{"code":"INTERNAL_ERROR","message":"Failed to get status"}}
                );
            }
            return;
        };

        if (status != .completed) {
            r.setStatus(.bad_request);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"BACKTEST_NOT_COMPLETE","message":"Backtest status: {s}"}}}}
            , .{status.toString()}) catch
                \\{"success":false,"error":{"code":"BACKTEST_NOT_COMPLETE","message":"Backtest not completed"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        }

        const result = manager.getBacktestResult(backtest_id) catch {
            r.setStatus(.internal_server_error);
            try r.sendJson(
                \\{"success":false,"error":{"code":"INTERNAL_ERROR","message":"Failed to get result"}}
            );
            return;
        };

        if (result) |res| {
            var buf: [1024]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":true,"data":{{"id":"{s}","status":"completed","metrics":{{"total_return":{d:.4},"win_rate":{d:.4},"profit_factor":{d:.2},"total_trades":{d},"winning_trades":{d},"losing_trades":{d},"net_profit":{d:.2}}}}}}}
            , .{
                backtest_id,
                res.total_return,
                res.win_rate,
                res.profit_factor,
                res.total_trades,
                res.winning_trades,
                res.losing_trades,
                res.net_profit,
            }) catch
                \\{"success":true,"data":{}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
        } else {
            r.setStatus(.internal_server_error);
            try r.sendJson(
                \\{"success":false,"error":{"code":"NO_RESULT","message":"No result available"}}
            );
        }
    } else if (std.mem.eql(u8, action, "cancel") and method == .POST) {
        // POST /api/v2/backtest/:id/cancel
        const progress = manager.getBacktestProgress(backtest_id) catch {
            r.setStatus(.not_found);
            try r.sendJson(
                \\{"success":false,"error":{"code":"NOT_FOUND","message":"Backtest not found"}}
            );
            return;
        };

        manager.cancelBacktest(backtest_id) catch |err| {
            r.setStatus(.internal_server_error);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"CANCEL_FAILED","message":"Failed to cancel: {s}"}}}}
            , .{@errorName(err)}) catch
                \\{"success":false,"error":{"code":"CANCEL_FAILED","message":"Failed to cancel backtest"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };

        var buf: [256]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"id":"{s}","status":"cancelled","progress_at_cancel":{d:.2}}}}}
        , .{ backtest_id, progress.progress }) catch
            \\{"success":true,"data":{"status":"cancelled"}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else {
        r.setStatus(.not_found);
        try r.sendJson(
            \\{"success":false,"error":{"code":"NOT_FOUND","message":"Unknown backtest endpoint"}}
        );
    }
}

// ============================================================================
// System API Handlers
// ============================================================================

fn handleKillSwitch(r: zap.Request, ctx: *ServerContext, method: zap.http.Method) !void {
    if (method != .POST) {
        r.setStatus(.method_not_allowed);
        try r.sendJson(
            \\{"success":false,"error":{"code":"METHOD_NOT_ALLOWED","message":"Only POST allowed"}}
        );
        return;
    }

    if (ctx.deps.engine_manager == null) {
        r.setStatus(.service_unavailable);
        try r.sendJson(
            \\{"success":false,"error":{"code":"SERVICE_UNAVAILABLE","message":"Engine manager not configured"}}
        );
        return;
    }

    const manager = ctx.deps.engine_manager.?;

    const body = r.body orelse {
        r.setStatus(.bad_request);
        try r.sendJson(
            \\{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Missing request body"}}
        );
        return;
    };

    // Parse kill switch request
    const KillSwitchRequest = struct {
        action: []const u8, // "activate" or "deactivate"
        close_all_positions: bool = true,
        cancel_all_orders: bool = true,
        reason: []const u8 = "Manual emergency stop",
    };

    const parsed = std.json.parseFromSlice(KillSwitchRequest, ctx.allocator, body, .{}) catch {
        r.setStatus(.bad_request);
        try r.sendJson(
            \\{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Invalid JSON format"}}
        );
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;

    if (std.mem.eql(u8, req.action, "activate")) {
        const result = manager.activateKillSwitch(req.reason, req.cancel_all_orders, req.close_all_positions) catch |err| {
            r.setStatus(.internal_server_error);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"KILL_SWITCH_FAILED","message":"Failed to activate: {s}"}}}}
            , .{@errorName(err)}) catch
                \\{"success":false,"error":{"code":"KILL_SWITCH_FAILED","message":"Failed to activate kill switch"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };

        var buf: [512]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"kill_switch":true,"affected":{{"grids_stopped":{d},"strategies_stopped":{d},"orders_cancelled":{d},"positions_closed":{d}}}}}}}
        , .{ result.grids_stopped, result.strategies_stopped, result.orders_cancelled, result.positions_closed }) catch
            \\{"success":true,"data":{"kill_switch":true}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else if (std.mem.eql(u8, req.action, "deactivate")) {
        manager.deactivateKillSwitch();
        try r.setContentType(.JSON);
        try r.sendBody(
            \\{"success":true,"data":{"kill_switch":false}}
        );
    } else {
        r.setStatus(.bad_request);
        try r.sendJson(
            \\{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Invalid action. Use 'activate' or 'deactivate'"}}
        );
    }
}

fn handleSystemHealth(r: zap.Request, ctx: *ServerContext) !void {
    if (ctx.deps.engine_manager) |manager| {
        const health = manager.getSystemHealth();
        var buf: [512]u8 = undefined;

        const kill_reason = health.kill_switch_reason orelse "null";
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"status":"{s}","components":{{"api_server":"up","engine_manager":"up"}},"metrics":{{"running_grids":{d},"active_backtests":{d},"kill_switch_active":{s},"uptime_seconds":{d}}}}}}}
        , .{
            health.status,
            health.running_grids,
            health.running_backtests,
            if (health.kill_switch_active) "true" else "false",
            ctx.uptime(),
        }) catch
            \\{"success":true,"data":{"status":"healthy"}}
        ;
        _ = kill_reason;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else {
        try r.setContentType(.JSON);
        try r.sendBody(
            \\{"success":true,"data":{"status":"healthy","components":{"api_server":"up","engine_manager":"not_configured"}}}
        );
    }
}

fn handleSystemLogs(r: zap.Request, ctx: *ServerContext) !void {
    _ = ctx;
    // Return empty logs for now - in production, this would read from a log buffer
    try r.setContentType(.JSON);
    try r.sendBody(
        \\{"success":true,"data":{"logs":[],"total":0,"has_more":false}}
    );
}

// ============================================================================
// Tests
// ============================================================================

test "Config validation" {
    const config = Config{ .jwt_secret = "this-is-a-very-long-secret-key-for-jwt-signing!" };
    try config.validate();
}

test "Config validation - jwt too short" {
    const config = Config{ .jwt_secret = "short" };
    try std.testing.expectError(error.JwtSecretTooShort, config.validate());
}
