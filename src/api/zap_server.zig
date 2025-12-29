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
const BacktestRequest = engine_mod.BacktestRequest;
const BacktestStatus = engine_mod.BacktestStatus;
const StrategyRequest = engine_mod.StrategyRequest;
const TradingMode = engine_mod.TradingMode;
const LiveRequest = engine_mod.LiveRequest;
const LiveStatus = engine_mod.LiveStatus;
const LiveTradingMode = engine_mod.LiveTradingMode;
const AIRuntimeConfig = engine_mod.AIRuntimeConfig;
const AIStatus = engine_mod.AIStatus;

// Import Logger for colored output
const logger_mod = @import("../core/logger.zig");
const Logger = logger_mod.Logger;
const LogWriter = logger_mod.LogWriter;
const LogRecord = logger_mod.LogRecord;
const Level = logger_mod.Level;
const AnsiColors = logger_mod.AnsiColors;

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
    // Exchange configuration from config.json
    exchange_wallet: ?[]const u8 = null,
    exchange_secret: ?[]const u8 = null,
    exchange_testnet: bool = true,

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
// Colored Logging Helpers
// ============================================================================

/// Log an incoming request with color (using std.debug.print for simplicity)
fn logRequest(method: []const u8, path: []const u8) void {
    std.debug.print("{s}{s}>>> {s}{s} {s}{s} {s}{s}\n", .{
        AnsiColors.BOLD,
        AnsiColors.CYAN,
        AnsiColors.RESET,
        AnsiColors.BRIGHT_GREEN,
        method,
        AnsiColors.RESET,
        path,
        AnsiColors.RESET,
    });
}

/// Log request body with color
fn logRequestBody(body: []const u8) void {
    const max_len: usize = 1000;
    if (body.len > max_len) {
        std.debug.print("{s}>>> BODY ({d} bytes, truncated):{s} {s}...\n", .{
            AnsiColors.YELLOW,
            body.len,
            AnsiColors.RESET,
            body[0..max_len],
        });
    } else {
        std.debug.print("{s}>>> BODY ({d} bytes):{s} {s}\n", .{
            AnsiColors.YELLOW,
            body.len,
            AnsiColors.RESET,
            body,
        });
    }
}

/// Log response with color
fn logResponse(status: []const u8, bytes: usize, body: []const u8) void {
    const max_len: usize = 2000;

    // Choose color based on status
    const status_color = if (std.mem.startsWith(u8, status, "2"))
        AnsiColors.GREEN
    else if (std.mem.startsWith(u8, status, "4"))
        AnsiColors.YELLOW
    else if (std.mem.startsWith(u8, status, "5"))
        AnsiColors.RED
    else
        AnsiColors.WHITE;

    if (body.len > max_len) {
        std.debug.print("{s}{s}<<< {s}{s}({d} bytes):{s} {s}...\n", .{
            AnsiColors.BOLD,
            AnsiColors.MAGENTA,
            AnsiColors.RESET,
            status_color,
            bytes,
            AnsiColors.RESET,
            body[0..max_len],
        });
    } else {
        std.debug.print("{s}{s}<<< {s}{s}({d} bytes):{s} {s}\n", .{
            AnsiColors.BOLD,
            AnsiColors.MAGENTA,
            AnsiColors.RESET,
            status_color,
            bytes,
            AnsiColors.RESET,
            body,
        });
    }
}

/// Log handler entry with color
fn logHandler(handler_name: []const u8) void {
    std.debug.print("{s}    -> {s}{s}\n", .{
        AnsiColors.DIM,
        handler_name,
        AnsiColors.RESET,
    });
}

/// Log info message with color
fn logInfo(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}[INFO]{s} " ++ fmt ++ "\n", .{ AnsiColors.GREEN, AnsiColors.RESET } ++ args);
}

/// Log error message with color
fn logError(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}[ERROR]{s} " ++ fmt ++ "\n", .{ AnsiColors.RED, AnsiColors.RESET } ++ args);
}

/// Log debug/detail message with color
fn logDetail(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}    " ++ fmt ++ "{s}\n", .{AnsiColors.DIM} ++ args ++ .{AnsiColors.RESET});
}

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
    const method_str = r.method orelse "UNKNOWN";

    // Log incoming request with color
    logRequest(method_str, path);

    // Log request body for POST/PUT/PATCH
    if (method == .POST or method == .PUT or method == .PATCH) {
        if (r.body) |body| {
            logRequestBody(body);
        }
    }

    // Log query parameters if present
    if (r.query) |query| {
        if (query.len > 0) {
            logDetail("QUERY: {s}", .{query});
        }
    }

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
    // V2 Strategy endpoints (unified - supports all strategy types including grid)
    else if (std.mem.eql(u8, path, "/api/v2/strategy") or std.mem.eql(u8, path, "/api/v2/strategies")) {
        try handleStrategyList(r, ctx, method);
    } else if (std.mem.startsWith(u8, path, "/api/v2/strategy/")) {
        try handleStrategyDetail(r, ctx, path, method);
    }
    // V2 Backtest endpoints
    else if (std.mem.eql(u8, path, "/api/v2/backtest")) {
        try handleBacktestList(r, ctx);
    } else if (std.mem.eql(u8, path, "/api/v2/backtest/run")) {
        try handleBacktestRun(r, ctx, method);
    } else if (std.mem.startsWith(u8, path, "/api/v2/backtest/")) {
        try handleBacktestDetail(r, ctx, path, method);
    }
    // V2 Live Trading endpoints
    else if (std.mem.eql(u8, path, "/api/v2/live") or std.mem.eql(u8, path, "/api/v2/live/sessions")) {
        try handleLiveList(r, ctx, method);
    } else if (std.mem.startsWith(u8, path, "/api/v2/live/")) {
        try handleLiveDetail(r, ctx, path, method);
    }
    // V2 System endpoints
    else if (std.mem.eql(u8, path, "/api/v2/system/kill-switch")) {
        try handleKillSwitch(r, ctx, method);
    } else if (std.mem.eql(u8, path, "/api/v2/system/health")) {
        try handleSystemHealth(r, ctx);
    } else if (std.mem.eql(u8, path, "/api/v2/system/logs")) {
        try handleSystemLogs(r, ctx);
    }
    // V2 AI Configuration endpoints
    else if (std.mem.eql(u8, path, "/api/v2/ai/config") or std.mem.eql(u8, path, "/api/v2/ai/status")) {
        try handleAIConfig(r, ctx, method);
    } else if (std.mem.eql(u8, path, "/api/v2/ai/enable")) {
        try handleAIEnable(r, ctx, method);
    } else if (std.mem.eql(u8, path, "/api/v2/ai/disable")) {
        try handleAIDisable(r, ctx, method);
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

// ============================================================================
// Strategy API Handlers (Unified - supports all strategy types including Grid)
// ============================================================================

fn handleStrategyList(r: zap.Request, ctx: *ServerContext, method: zap.http.Method) !void {
    if (ctx.deps.engine_manager == null) {
        r.setStatus(.service_unavailable);
        try r.sendJson(
            \\{"success":false,"error":{"code":"SERVICE_UNAVAILABLE","message":"Engine manager not configured"}}
        );
        return;
    }

    const manager = ctx.deps.engine_manager.?;

    switch (method) {
        .GET => {
            // List all strategies
            const strategies = manager.listStrategies(ctx.allocator) catch |err| {
                r.setStatus(.internal_server_error);
                var buf: [256]u8 = undefined;
                const json = std.fmt.bufPrint(&buf,
                    \\{{"success":false,"error":{{"code":"LIST_FAILED","message":"Failed to list strategies: {s}"}}}}
                , .{@errorName(err)}) catch
                    \\{"success":false,"error":{"code":"LIST_FAILED","message":"Failed to list strategies"}}
                ;
                try r.setContentType(.JSON);
                try r.sendBody(json);
                return;
            };
            defer ctx.allocator.free(strategies);

            // Build JSON response
            var response_buf = std.ArrayList(u8){};
            defer response_buf.deinit(ctx.allocator);

            const writer = response_buf.writer(ctx.allocator);
            try writer.writeAll("{\"success\":true,\"data\":{\"strategies\":[");

            for (strategies, 0..) |s, i| {
                if (i > 0) try writer.writeAll(",");
                try std.fmt.format(writer,
                    \\{{"id":"{s}","strategy":"{s}","symbol":"{s}","status":"{s}","mode":"{s}","realized_pnl":{d:.4},"current_position":{d:.4},"total_signals":{d},"total_trades":{d},"win_rate":{d:.2},"uptime_seconds":{d}}}
                , .{
                    s.id,
                    s.strategy,
                    s.symbol,
                    s.status,
                    s.mode,
                    s.realized_pnl,
                    s.current_position,
                    s.total_signals,
                    s.total_trades,
                    s.win_rate,
                    s.uptime_seconds,
                });
            }

            try writer.writeAll("],\"total\":");
            try std.fmt.format(writer, "{d}", .{strategies.len});
            try writer.writeAll("}}");

            try r.setContentType(.JSON);
            try r.sendBody(response_buf.items);
        },
        .POST => {
            // Start a new strategy
            const body = r.body orelse {
                r.setStatus(.bad_request);
                try r.sendJson(
                    \\{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Missing request body"}}
                );
                return;
            };

            // Parse strategy request
            const StrategyStartRequest = struct {
                id: ?[]const u8 = null,
                strategy: []const u8,
                symbol: []const u8,
                timeframe: []const u8 = "1h",
                mode: []const u8 = "paper",
                initial_capital: f64 = 10000,
                check_interval_ms: u64 = 5000,
                params: ?[]const u8 = null,
                risk_enabled: bool = true,
                max_daily_loss_pct: f64 = 0.02,
                max_position_size: f64 = 1.0,
                // Grid-specific parameters (used when strategy = "grid")
                upper_price: ?f64 = null,
                lower_price: ?f64 = null,
                grid_count: u32 = 10,
                order_size: f64 = 0.001,
                take_profit_pct: f64 = 0.5,
            };

            const parsed = std.json.parseFromSlice(StrategyStartRequest, ctx.allocator, body, .{}) catch {
                r.setStatus(.bad_request);
                try r.sendJson(
                    \\{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Invalid JSON format"}}
                );
                return;
            };
            defer parsed.deinit();

            const req = parsed.value;

            // Generate ID if not provided
            var id_buf: [32]u8 = undefined;
            const strategy_id = req.id orelse blk: {
                const now = std.time.milliTimestamp();
                break :blk std.fmt.bufPrint(&id_buf, "strat_{d}", .{now}) catch "strat_default";
            };

            // Parse mode
            const mode = TradingMode.fromString(req.mode);

            // Build strategy request
            const strategy_request = StrategyRequest{
                .strategy = req.strategy,
                .symbol = req.symbol,
                .timeframe = req.timeframe,
                .mode = mode,
                .initial_capital = req.initial_capital,
                .check_interval_ms = req.check_interval_ms,
                .params = req.params,
                .risk_enabled = req.risk_enabled,
                .max_daily_loss_pct = req.max_daily_loss_pct,
                .max_position_size = req.max_position_size,
                // Grid-specific parameters
                .upper_price = req.upper_price,
                .lower_price = req.lower_price,
                .grid_count = req.grid_count,
                .order_size = req.order_size,
                .take_profit_pct = req.take_profit_pct,
            };

            // Start strategy
            manager.startStrategy(strategy_id, strategy_request) catch |err| {
                r.setStatus(.internal_server_error);
                var buf: [256]u8 = undefined;
                const json = std.fmt.bufPrint(&buf,
                    \\{{"success":false,"error":{{"code":"START_FAILED","message":"Failed to start strategy: {s}"}}}}
                , .{@errorName(err)}) catch
                    \\{"success":false,"error":{"code":"START_FAILED","message":"Failed to start strategy"}}
                ;
                try r.setContentType(.JSON);
                try r.sendBody(json);
                return;
            };

            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":true,"data":{{"id":"{s}","status":"running","strategy":"{s}","symbol":"{s}","mode":"{s}"}}}}
            , .{ strategy_id, req.strategy, req.symbol, req.mode }) catch
                \\{"success":true,"data":{"status":"started"}}
            ;
            r.setStatus(.created);
            try r.setContentType(.JSON);
            try r.sendBody(json);
        },
        else => {
            r.setStatus(.method_not_allowed);
            try r.sendJson(
                \\{"success":false,"error":{"code":"METHOD_NOT_ALLOWED","message":"Use GET to list or POST to start"}}
            );
        },
    }
}

fn handleStrategyDetail(r: zap.Request, ctx: *ServerContext, path: []const u8, method: zap.http.Method) !void {
    if (ctx.deps.engine_manager == null) {
        r.setStatus(.service_unavailable);
        try r.sendJson(
            \\{"success":false,"error":{"code":"SERVICE_UNAVAILABLE","message":"Engine manager not configured"}}
        );
        return;
    }

    const manager = ctx.deps.engine_manager.?;

    // Extract strategy ID from path: /api/v2/strategy/:id[/action]
    const prefix = "/api/v2/strategy/";
    const remainder = path[prefix.len..];

    // Find strategy ID and optional action
    var strategy_id = remainder;
    var action: []const u8 = "";
    if (std.mem.indexOf(u8, remainder, "/")) |idx| {
        strategy_id = remainder[0..idx];
        action = remainder[idx + 1 ..];
    }

    if (std.mem.eql(u8, action, "stop") or (action.len == 0 and method == .DELETE)) {
        // Stop a strategy
        manager.stopStrategy(strategy_id) catch |err| {
            r.setStatus(.not_found);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"STOP_FAILED","message":"Failed to stop strategy: {s}"}}}}
            , .{@errorName(err)}) catch
                \\{"success":false,"error":{"code":"STOP_FAILED","message":"Strategy not found or failed to stop"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };

        var buf: [128]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"id":"{s}","status":"stopped"}}}}
        , .{strategy_id}) catch
            \\{"success":true,"data":{"status":"stopped"}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else if (std.mem.eql(u8, action, "pause")) {
        manager.pauseStrategy(strategy_id) catch |err| {
            r.setStatus(.internal_server_error);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"PAUSE_FAILED","message":"Failed to pause strategy: {s}"}}}}
            , .{@errorName(err)}) catch
                \\{"success":false,"error":{"code":"PAUSE_FAILED","message":"Strategy not found or failed to pause"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };

        var buf: [128]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"id":"{s}","status":"paused"}}}}
        , .{strategy_id}) catch
            \\{"success":true,"data":{"status":"paused"}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else if (std.mem.eql(u8, action, "resume")) {
        manager.resumeStrategy(strategy_id) catch |err| {
            r.setStatus(.internal_server_error);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"RESUME_FAILED","message":"Failed to resume strategy: {s}"}}}}
            , .{@errorName(err)}) catch
                \\{"success":false,"error":{"code":"RESUME_FAILED","message":"Strategy not found or failed to resume"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };

        var buf: [128]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"id":"{s}","status":"running"}}}}
        , .{strategy_id}) catch
            \\{"success":true,"data":{"status":"running"}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else if (action.len == 0 and method == .GET) {
        // Get strategy details
        const stats = manager.getStrategyStats(strategy_id) catch |err| {
            r.setStatus(.not_found);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"NOT_FOUND","message":"Strategy not found: {s}"}}}}
            , .{@errorName(err)}) catch
                \\{"success":false,"error":{"code":"NOT_FOUND","message":"Strategy not found"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };

        const status = manager.getStrategyStatus(strategy_id) catch .stopped;

        var buf: [512]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"id":"{s}","status":"{s}","stats":{{"total_signals":{d},"total_trades":{d},"winning_trades":{d},"losing_trades":{d},"realized_pnl":{d:.4},"unrealized_pnl":{d:.4},"current_position":{d:.4},"win_rate":{d:.2},"uptime_seconds":{d}}}}}}}
        , .{
            strategy_id,
            status.toString(),
            stats.total_signals,
            stats.total_trades,
            stats.winning_trades,
            stats.losing_trades,
            stats.realized_pnl,
            stats.unrealized_pnl,
            stats.current_position,
            stats.win_rate,
            stats.uptime_seconds,
        }) catch
            \\{"success":true,"data":{"status":"unknown"}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else {
        r.setStatus(.not_found);
        try r.sendJson(
            \\{"success":false,"error":{"code":"NOT_FOUND","message":"Unknown strategy endpoint"}}
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

fn handleBacktestList(r: zap.Request, ctx: *ServerContext) !void {
    logHandler("handleBacktestList");

    if (ctx.deps.engine_manager == null) {
        // No engine manager, return empty list
        const response = "{\"success\":true,\"data\":{\"backtests\":[],\"total\":0}}";
        logResponse("200", response.len, response);
        try r.setContentType(.JSON);
        try r.sendJson(response);
        return;
    }

    const manager = ctx.deps.engine_manager.?;

    // Get backtest list from manager
    const backtests = manager.listBacktests(ctx.allocator) catch |err| {
        r.setStatus(.internal_server_error);
        logError("Failed to list backtests: {}", .{err});
        const err_response = "{\"success\":false,\"error\":{\"code\":\"LIST_FAILED\",\"message\":\"Failed to list backtests\"}}";
        logResponse("500", err_response.len, err_response);
        try r.setContentType(.JSON);
        try r.sendJson(err_response);
        return;
    };
    defer ctx.allocator.free(backtests);

    logDetail("Found {d} backtests", .{backtests.len});

    // Build JSON response
    var response_buf = std.ArrayList(u8){};
    defer response_buf.deinit(ctx.allocator);

    const writer = response_buf.writer(ctx.allocator);
    try writer.writeAll("{\"success\":true,\"data\":{\"backtests\":[");

    for (backtests, 0..) |bt, i| {
        if (i > 0) try writer.writeAll(",");
        try std.fmt.format(writer,
            \\{{"id":"{s}","strategy":"{s}","symbol":"{s}","status":"{s}","progress":{d:.2},"trades_so_far":{d},"elapsed_seconds":{d}}}
        , .{
            bt.id,
            bt.strategy,
            bt.symbol,
            bt.status,
            bt.progress,
            bt.trades_so_far,
            bt.elapsed_seconds,
        });
    }

    try writer.writeAll("],\"total\":");
    try std.fmt.format(writer, "{d}", .{backtests.len});
    try writer.writeAll("}}");

    // Log the response with color
    logResponse("200", response_buf.items.len, response_buf.items);

    try r.setContentType(.JSON);
    try r.sendBody(response_buf.items);
}

fn handleBacktestRun(r: zap.Request, ctx: *ServerContext, method: zap.http.Method) !void {
    logHandler("handleBacktestRun");

    if (method != .POST) {
        const err_resp = "{\"success\":false,\"error\":{\"code\":\"METHOD_NOT_ALLOWED\",\"message\":\"Only POST allowed\"}}";
        logResponse("405", err_resp.len, err_resp);
        r.setStatus(.method_not_allowed);
        try r.sendJson(err_resp);
        return;
    }

    if (ctx.deps.engine_manager == null) {
        const err_resp = "{\"success\":false,\"error\":{\"code\":\"SERVICE_UNAVAILABLE\",\"message\":\"Engine manager not configured\"}}";
        logResponse("503", err_resp.len, err_resp);
        r.setStatus(.service_unavailable);
        try r.sendJson(err_resp);
        return;
    }

    const manager = ctx.deps.engine_manager.?;

    const body = r.body orelse {
        const err_resp = "{\"success\":false,\"error\":{\"code\":\"VALIDATION_ERROR\",\"message\":\"Missing request body\"}}";
        logResponse("400", err_resp.len, err_resp);
        r.setStatus(.bad_request);
        try r.sendJson(err_resp);
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
        const err_resp = "{\"success\":false,\"error\":{\"code\":\"VALIDATION_ERROR\",\"message\":\"Invalid JSON format\"}}";
        logResponse("400", err_resp.len, err_resp);
        r.setStatus(.bad_request);
        try r.sendJson(err_resp);
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;
    logDetail("Parsed: strategy={s}, symbol={s}, timeframe={s}", .{ req.strategy, req.symbol, req.timeframe });

    // Generate backtest ID
    var id_buf: [32]u8 = undefined;
    const ts = std.time.timestamp();
    const backtest_id = std.fmt.bufPrint(&id_buf, "bt_{d}", .{ts}) catch "bt_new";
    logDetail("Generated backtest ID: {s}", .{backtest_id});

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
        logResponse("500", json.len, json);
        try r.setContentType(.JSON);
        try r.sendBody(json);
        return;
    };

    logInfo("Backtest started: {s}", .{backtest_id});

    r.setStatus(.created);
    var buf: [256]u8 = undefined;
    const json = std.fmt.bufPrint(&buf,
        \\{{"success":true,"data":{{"id":"{s}","status":"queued","estimated_duration":30}}}}
    , .{backtest_id}) catch
        \\{"success":true,"data":{"status":"queued"}}
    ;
    logResponse("201", json.len, json);
    try r.setContentType(.JSON);
    try r.sendBody(json);
}

fn handleBacktestDetail(r: zap.Request, ctx: *ServerContext, path: []const u8, method: zap.http.Method) !void {
    logHandler("handleBacktestDetail");

    if (ctx.deps.engine_manager == null) {
        const err_resp = "{\"success\":false,\"error\":{\"code\":\"SERVICE_UNAVAILABLE\",\"message\":\"Engine manager not configured\"}}";
        logResponse("503", err_resp.len, err_resp);
        r.setStatus(.service_unavailable);
        try r.sendJson(err_resp);
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

    logDetail("backtest_id={s}, action={s}", .{ backtest_id, if (action.len > 0) action else "(status)" });

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
            // Build full response with trades array
            var response_buf = std.ArrayList(u8){};
            defer response_buf.deinit(ctx.allocator);

            const writer = response_buf.writer(ctx.allocator);

            // Start response
            try writer.writeAll("{\"success\":true,\"data\":{");

            // Basic info
            try std.fmt.format(writer, "\"id\":\"{s}\",\"status\":\"completed\",", .{backtest_id});

            // Metrics
            try writer.writeAll("\"metrics\":{");
            try std.fmt.format(writer, "\"total_return\":{d:.6},", .{res.total_return});
            try std.fmt.format(writer, "\"sharpe_ratio\":{d:.4},", .{res.sharpe_ratio});
            try std.fmt.format(writer, "\"max_drawdown\":{d:.6},", .{res.max_drawdown});
            try std.fmt.format(writer, "\"win_rate\":{d:.4},", .{res.win_rate});
            try std.fmt.format(writer, "\"profit_factor\":{d:.4},", .{res.profit_factor});
            try std.fmt.format(writer, "\"total_trades\":{d},", .{res.total_trades});
            try std.fmt.format(writer, "\"winning_trades\":{d},", .{res.winning_trades});
            try std.fmt.format(writer, "\"losing_trades\":{d},", .{res.losing_trades});
            try std.fmt.format(writer, "\"net_profit\":{d:.2},", .{res.net_profit});
            try std.fmt.format(writer, "\"total_commission\":{d:.4}", .{res.total_commission});
            try writer.writeAll("},");

            // Trades array (for chart visualization)
            try writer.writeAll("\"trades\":[");

            // Get detailed trades from the full result if available
            const detailed_result = manager.getBacktestDetailedResult(backtest_id) catch null;
            if (detailed_result) |detail| {
                for (detail.trades, 0..) |trade, i| {
                    if (i > 0) try writer.writeAll(",");
                    try writer.writeAll("{");
                    try std.fmt.format(writer, "\"id\":{d},", .{trade.id});
                    try std.fmt.format(writer, "\"side\":\"{s}\",", .{trade.side.toString()});
                    try std.fmt.format(writer, "\"entry_time\":{d},", .{trade.entry_time.millis});
                    try std.fmt.format(writer, "\"exit_time\":{d},", .{trade.exit_time.millis});
                    try std.fmt.format(writer, "\"entry_price\":{d:.8},", .{trade.entry_price.toFloat()});
                    try std.fmt.format(writer, "\"exit_price\":{d:.8},", .{trade.exit_price.toFloat()});
                    try std.fmt.format(writer, "\"size\":{d:.8},", .{trade.size.toFloat()});
                    try std.fmt.format(writer, "\"pnl\":{d:.8},", .{trade.pnl.toFloat()});
                    try std.fmt.format(writer, "\"pnl_percent\":{d:.6},", .{trade.pnl_percent.toFloat()});
                    try std.fmt.format(writer, "\"commission\":{d:.8}", .{trade.commission.toFloat()});
                    try writer.writeAll("}");
                }
            }
            try writer.writeAll("],");

            // Equity curve (for PnL chart)
            try writer.writeAll("\"equity_curve\":[");
            if (detailed_result) |detail| {
                // Sample equity curve if too many points (max 500)
                const max_points: usize = 500;
                const curve = detail.equity_curve;
                const step = if (curve.len > max_points) curve.len / max_points else 1;

                var count: usize = 0;
                var i: usize = 0;
                while (i < curve.len) : (i += step) {
                    if (count > 0) try writer.writeAll(",");
                    const snapshot = curve[i];
                    try writer.writeAll("{");
                    try std.fmt.format(writer, "\"timestamp\":{d},", .{snapshot.timestamp.millis});
                    try std.fmt.format(writer, "\"equity\":{d:.4},", .{snapshot.equity.toFloat()});
                    try std.fmt.format(writer, "\"balance\":{d:.4}", .{snapshot.balance.toFloat()});
                    try writer.writeAll("}");
                    count += 1;
                }
            }
            try writer.writeAll("]");

            // Close data and response
            try writer.writeAll("}}");

            // Log response with color
            logResponse("200", response_buf.items.len, response_buf.items);

            try r.setContentType(.JSON);
            try r.sendBody(response_buf.items);
        } else {
            const err_resp = "{\"success\":false,\"error\":{\"code\":\"NO_RESULT\",\"message\":\"No result available\"}}";
            logResponse("500", err_resp.len, err_resp);
            r.setStatus(.internal_server_error);
            try r.sendJson(err_resp);
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
    } else if (action.len == 0 and method == .GET) {
        // GET /api/v2/backtest/:id - Get backtest info/status
        const status = manager.getBacktestStatus(backtest_id) catch |err| {
            if (err == error.BacktestNotFound) {
                r.setStatus(.not_found);
                try r.sendJson(
                    \\{"success":false,"error":{"code":"NOT_FOUND","message":"Backtest not found"}}
                );
            } else {
                r.setStatus(.internal_server_error);
                try r.sendJson(
                    \\{"success":false,"error":{"code":"INTERNAL_ERROR","message":"Failed to get backtest status"}}
                );
            }
            return;
        };

        // Try to get progress info if available
        const progress = manager.getBacktestProgress(backtest_id) catch null;

        if (progress) |prog| {
            var buf: [512]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":true,"data":{{"id":"{s}","status":"{s}","progress":{d:.2},"trades_so_far":{d},"elapsed_seconds":{d}}}}}
            , .{ backtest_id, status.toString(), prog.progress, prog.trades_so_far, prog.elapsed_seconds }) catch
                \\{"success":true,"data":{}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
        } else {
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":true,"data":{{"id":"{s}","status":"{s}"}}}}
            , .{ backtest_id, status.toString() }) catch
                \\{"success":true,"data":{}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
        }
    } else {
        r.setStatus(.not_found);
        try r.sendJson(
            \\{"success":false,"error":{"code":"NOT_FOUND","message":"Unknown backtest endpoint"}}
        );
    }
}

// ============================================================================
// Live Trading API Handlers
// ============================================================================

fn handleLiveList(r: zap.Request, ctx: *ServerContext, method: zap.http.Method) !void {
    logHandler("handleLiveList");

    if (ctx.deps.engine_manager == null) {
        const err_resp = "{\"success\":false,\"error\":{\"code\":\"SERVICE_UNAVAILABLE\",\"message\":\"Engine manager not configured\"}}";
        logResponse("503", err_resp.len, err_resp);
        r.setStatus(.service_unavailable);
        try r.sendJson(err_resp);
        return;
    }

    const manager = ctx.deps.engine_manager.?;

    switch (method) {
        .GET => {
            // List all live trading sessions
            const sessions = manager.listLive(ctx.allocator) catch |err| {
                r.setStatus(.internal_server_error);
                var buf: [256]u8 = undefined;
                const json = std.fmt.bufPrint(&buf,
                    \\{{"success":false,"error":{{"code":"LIST_FAILED","message":"Failed to list live sessions: {s}"}}}}
                , .{@errorName(err)}) catch
                    \\{"success":false,"error":{"code":"LIST_FAILED","message":"Failed to list live sessions"}}
                ;
                logResponse("500", json.len, json);
                try r.setContentType(.JSON);
                try r.sendBody(json);
                return;
            };
            defer ctx.allocator.free(sessions);

            logDetail("Found {d} live sessions", .{sessions.len});

            // Build JSON response
            var response_buf = std.ArrayList(u8){};
            defer response_buf.deinit(ctx.allocator);

            const writer = response_buf.writer(ctx.allocator);
            try writer.writeAll("{\"success\":true,\"data\":{\"sessions\":[");

            for (sessions, 0..) |s, i| {
                if (i > 0) try writer.writeAll(",");

                // Build symbols array
                try writer.writeAll("{\"id\":\"");
                try writer.writeAll(s.id);
                try writer.writeAll("\",\"name\":\"");
                try writer.writeAll(s.name);
                try writer.writeAll("\",\"exchange\":\"");
                try writer.writeAll(s.exchange);
                try writer.writeAll("\",\"status\":\"");
                try writer.writeAll(s.status);
                try writer.writeAll("\",\"connection_status\":\"");
                try writer.writeAll(s.connection_status);
                try writer.writeAll("\",\"testnet\":");
                try writer.writeAll(if (s.testnet) "true" else "false");
                // Strategy info (NEW)
                try writer.writeAll(",\"strategy\":\"");
                try writer.writeAll(s.strategy);
                try writer.writeAll("\",\"timeframe\":\"");
                try writer.writeAll(s.timeframe);
                try std.fmt.format(writer, "\",\"leverage\":{d}", .{s.leverage});
                // Symbols array
                try writer.writeAll(",\"symbols\":[");
                for (s.symbols, 0..) |sym, j| {
                    if (j > 0) try writer.writeAll(",");
                    try writer.writeAll("\"");
                    try writer.writeAll(sym);
                    try writer.writeAll("\"");
                }
                try std.fmt.format(writer,
                    \\],"current_position":{d:.6},"entry_price":{d:.2},"account_balance":{d:.4},"available_balance":{d:.4},"initial_capital":{d:.4},"orders_submitted":{d},"orders_filled":{d},"orders_cancelled":{d},"orders_rejected":{d},"total_volume":{d:.4},"realized_pnl":{d:.4},"unrealized_pnl":{d:.4},"last_price":{d:.6},"uptime_ms":{d},"ticks":{d},"reconnects":{d}}}
                , .{
                    s.current_position,
                    s.entry_price,
                    s.account_balance,
                    s.available_balance,
                    s.initial_capital,
                    s.orders_submitted,
                    s.orders_filled,
                    s.orders_cancelled,
                    s.orders_rejected,
                    s.total_volume,
                    s.realized_pnl,
                    s.unrealized_pnl,
                    s.last_price,
                    s.uptime_ms,
                    s.ticks,
                    s.reconnects,
                });
            }

            try writer.writeAll("],\"total\":");
            try std.fmt.format(writer, "{d}", .{sessions.len});
            try writer.writeAll("}}");

            logResponse("200", response_buf.items.len, response_buf.items);
            try r.setContentType(.JSON);
            try r.sendBody(response_buf.items);
        },
        .POST => {
            // Start a new live trading session
            const body = r.body orelse {
                const err_resp = "{\"success\":false,\"error\":{\"code\":\"VALIDATION_ERROR\",\"message\":\"Missing request body\"}}";
                logResponse("400", err_resp.len, err_resp);
                r.setStatus(.bad_request);
                try r.sendJson(err_resp);
                return;
            };

            // Parse live trading request
            const LiveStartRequest = struct {
                id: ?[]const u8 = null,
                name: []const u8 = "default",
                mode: []const u8 = "event_driven",
                exchange: []const u8 = "hyperliquid",
                testnet: ?bool = null, // null means use config default
                symbols: ?[]const []const u8 = null,
                heartbeat_interval_ms: u64 = 30000,
                tick_interval_ms: u64 = 1000,
                auto_reconnect: bool = true,
                wallet: ?[]const u8 = null,
                private_key: ?[]const u8 = null,
                // Strategy configuration (NEW)
                strategy: ?[]const u8 = null,
                strategy_params: ?[]const u8 = null,
                timeframe: []const u8 = "1h",
                initial_capital: f64 = 0, // 0 = use real balance from exchange
                leverage: u32 = 1, // 1-100, default 1 (no leverage)
                // Grid trading specific parameters
                upper_price: ?f64 = null,
                lower_price: ?f64 = null,
                grid_count: u32 = 10,
                order_size: f64 = 0.001,
                take_profit_pct: f64 = 0.5,
            };

            const parsed = std.json.parseFromSlice(LiveStartRequest, ctx.allocator, body, .{}) catch {
                const err_resp = "{\"success\":false,\"error\":{\"code\":\"VALIDATION_ERROR\",\"message\":\"Invalid JSON format\"}}";
                logResponse("400", err_resp.len, err_resp);
                r.setStatus(.bad_request);
                try r.sendJson(err_resp);
                return;
            };
            defer parsed.deinit();

            const req = parsed.value;

            // Use credentials from config.json if not provided in request
            const wallet = req.wallet orelse ctx.deps.exchange_wallet;
            const private_key = req.private_key orelse ctx.deps.exchange_secret;
            const testnet = req.testnet orelse ctx.deps.exchange_testnet;

            logDetail("Starting live session: name={s}, exchange={s}, testnet={}", .{ req.name, req.exchange, testnet });
            if (wallet) |w| {
                logDetail("Using wallet: {s}...", .{if (w.len > 10) w[0..10] else w});
            } else {
                logError("No wallet configured! Check config.json or provide wallet in request", .{});
            }

            // Generate ID if not provided
            var id_buf: [32]u8 = undefined;
            const live_id = req.id orelse blk: {
                const now = std.time.milliTimestamp();
                break :blk std.fmt.bufPrint(&id_buf, "live_{d}", .{now}) catch "live_default";
            };

            // Parse trading mode
            const trading_mode: LiveTradingMode = if (std.mem.eql(u8, req.mode, "clock_driven"))
                .clock_driven
            else if (std.mem.eql(u8, req.mode, "hybrid"))
                .hybrid
            else
                .event_driven;

            // Validate leverage
            const leverage = if (req.leverage >= 1 and req.leverage <= 100) req.leverage else 1;

            // Build live request with merged credentials
            const live_request = LiveRequest{
                .name = req.name,
                .mode = trading_mode,
                .symbols = req.symbols orelse &[_][]const u8{},
                .heartbeat_interval_ms = req.heartbeat_interval_ms,
                .tick_interval_ms = req.tick_interval_ms,
                .auto_reconnect = req.auto_reconnect,
                .exchange = req.exchange,
                .wallet = wallet,
                .private_key = private_key,
                .testnet = testnet,
                // Strategy configuration (NEW)
                .strategy = req.strategy,
                .strategy_params = req.strategy_params,
                .timeframe = req.timeframe,
                .initial_capital = req.initial_capital,
                .leverage = leverage,
                // Grid trading parameters
                .upper_price = req.upper_price,
                .lower_price = req.lower_price,
                .grid_count = req.grid_count,
                .order_size = req.order_size,
                .take_profit_pct = req.take_profit_pct,
            };

            // Start live trading session
            manager.startLive(live_id, live_request) catch |err| {
                r.setStatus(.bad_request);
                var buf: [512]u8 = undefined;

                // Provide more helpful error messages
                const error_info: struct { code: []const u8, message: []const u8 } = switch (err) {
                    error.InvalidGridPrices => .{
                        .code = "INVALID_GRID_PRICES",
                        .message = "upper_price must be greater than lower_price",
                    },
                    error.MissingGridPrices => .{
                        .code = "MISSING_GRID_PRICES",
                        .message = "Grid strategy requires upper_price and lower_price",
                    },
                    error.InvalidStrategyConfig => .{
                        .code = "INVALID_STRATEGY_CONFIG",
                        .message = "Invalid strategy configuration",
                    },
                    error.MissingStrategyParam => .{
                        .code = "MISSING_STRATEGY_PARAM",
                        .message = "Missing required strategy parameter",
                    },
                    error.InvalidStrategyParam => .{
                        .code = "INVALID_STRATEGY_PARAM",
                        .message = "Invalid strategy parameter value",
                    },
                    error.StrategyNotFound => .{
                        .code = "STRATEGY_NOT_FOUND",
                        .message = "Unknown strategy name",
                    },
                    error.StrategyCreationFailed => .{
                        .code = "STRATEGY_CREATION_FAILED",
                        .message = "Failed to create strategy",
                    },
                    else => .{
                        .code = "START_FAILED",
                        .message = "Failed to start live session",
                    },
                };

                const json = std.fmt.bufPrint(&buf,
                    \\{{"success":false,"error":{{"code":"{s}","message":"{s}"}}}}
                , .{ error_info.code, error_info.message }) catch
                    \\{"success":false,"error":{"code":"START_FAILED","message":"Failed to start live session"}}
                ;
                logResponse("400", json.len, json);
                try r.setContentType(.JSON);
                try r.sendBody(json);
                return;
            };

            const strategy_name = req.strategy orelse "none";
            logInfo("Live session started: id={s}, name={s}, strategy={s}", .{ live_id, req.name, strategy_name });

            var buf: [512]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":true,"data":{{"id":"{s}","status":"running","name":"{s}","exchange":"{s}","testnet":{s},"strategy":"{s}"}}}}
            , .{ live_id, req.name, req.exchange, if (testnet) "true" else "false", strategy_name }) catch
                \\{"success":true,"data":{"status":"started"}}
            ;
            logResponse("201", json.len, json);
            r.setStatus(.created);
            try r.setContentType(.JSON);
            try r.sendBody(json);
        },
        else => {
            r.setStatus(.method_not_allowed);
            try r.sendJson(
                \\{"success":false,"error":{"code":"METHOD_NOT_ALLOWED","message":"Use GET to list or POST to start"}}
            );
        },
    }
}

fn handleLiveDetail(r: zap.Request, ctx: *ServerContext, path: []const u8, method: zap.http.Method) !void {
    if (ctx.deps.engine_manager == null) {
        r.setStatus(.service_unavailable);
        try r.sendJson(
            \\{"success":false,"error":{"code":"SERVICE_UNAVAILABLE","message":"Engine manager not configured"}}
        );
        return;
    }

    const manager = ctx.deps.engine_manager.?;

    // Extract live session ID from path: /api/v2/live/:id[/action]
    const prefix = "/api/v2/live/";
    const remainder = path[prefix.len..];

    // Find session ID and optional action
    var session_id = remainder;
    var action: []const u8 = "";
    if (std.mem.indexOf(u8, remainder, "/")) |idx| {
        session_id = remainder[0..idx];
        action = remainder[idx + 1 ..];
    }

    if (std.mem.eql(u8, action, "stop") or (action.len == 0 and method == .DELETE)) {
        // Stop a live trading session
        manager.stopLive(session_id) catch |err| {
            r.setStatus(.not_found);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"STOP_FAILED","message":"Failed to stop live session: {s}"}}}}
            , .{@errorName(err)}) catch
                \\{"success":false,"error":{"code":"STOP_FAILED","message":"Live session not found or failed to stop"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };

        var buf: [128]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"id":"{s}","status":"stopped"}}}}
        , .{session_id}) catch
            \\{"success":true,"data":{"status":"stopped"}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else if (std.mem.eql(u8, action, "pause")) {
        manager.pauseLive(session_id) catch |err| {
            r.setStatus(.internal_server_error);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"PAUSE_FAILED","message":"Failed to pause live session: {s}"}}}}
            , .{@errorName(err)}) catch
                \\{"success":false,"error":{"code":"PAUSE_FAILED","message":"Live session not found or failed to pause"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };

        var buf: [128]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"id":"{s}","status":"paused"}}}}
        , .{session_id}) catch
            \\{"success":true,"data":{"status":"paused"}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else if (std.mem.eql(u8, action, "resume")) {
        manager.resumeLive(session_id) catch |err| {
            r.setStatus(.internal_server_error);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"RESUME_FAILED","message":"Failed to resume live session: {s}"}}}}
            , .{@errorName(err)}) catch
                \\{"success":false,"error":{"code":"RESUME_FAILED","message":"Live session not found or failed to resume"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };

        var buf: [128]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"id":"{s}","status":"running"}}}}
        , .{session_id}) catch
            \\{"success":true,"data":{"status":"running"}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else if (action.len == 0 and method == .GET) {
        // Get live session details
        const stats = manager.getLiveStats(session_id) catch |err| {
            r.setStatus(.not_found);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"NOT_FOUND","message":"Live session not found: {s}"}}}}
            , .{@errorName(err)}) catch
                \\{"success":false,"error":{"code":"NOT_FOUND","message":"Live session not found"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };

        const status = manager.getLiveStatus(session_id) catch .stopped;

        var buf: [512]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"id":"{s}","status":"{s}","stats":{{"uptime_ms":{d},"ticks":{d},"heartbeats_sent":{d},"reconnects":{d},"orders_submitted":{d},"orders_filled":{d},"orders_cancelled":{d},"total_volume":{d:.4},"realized_pnl":{d:.4}}}}}}}
        , .{
            session_id,
            status.toString(),
            stats.uptime_ms,
            stats.ticks,
            stats.heartbeats_sent,
            stats.reconnects,
            stats.orders_submitted,
            stats.orders_filled,
            stats.orders_cancelled,
            stats.total_volume,
            stats.realized_pnl,
        }) catch
            \\{"success":true,"data":{"status":"unknown"}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else if (std.mem.eql(u8, action, "subscribe") and method == .POST) {
        // Subscribe to a symbol
        const body = r.body orelse {
            r.setStatus(.bad_request);
            try r.sendJson(
                \\{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Missing request body"}}
            );
            return;
        };

        const SubscribeRequest = struct { symbol: []const u8 };
        const parsed = std.json.parseFromSlice(SubscribeRequest, ctx.allocator, body, .{}) catch {
            r.setStatus(.bad_request);
            try r.sendJson(
                \\{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Invalid JSON format"}}
            );
            return;
        };
        defer parsed.deinit();

        manager.subscribeLiveSymbol(session_id, parsed.value.symbol) catch |err| {
            r.setStatus(.internal_server_error);
            var buf: [256]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":false,"error":{{"code":"SUBSCRIBE_FAILED","message":"Failed to subscribe: {s}"}}}}
            , .{@errorName(err)}) catch
                \\{"success":false,"error":{"code":"SUBSCRIBE_FAILED","message":"Failed to subscribe"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
            return;
        };

        var buf: [128]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"symbol":"{s}","subscribed":true}}}}
        , .{parsed.value.symbol}) catch
            \\{"success":true,"data":{"subscribed":true}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
    } else {
        r.setStatus(.not_found);
        try r.sendJson(
            \\{"success":false,"error":{"code":"NOT_FOUND","message":"Unknown live endpoint"}}
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
            \\{{"success":true,"data":{{"kill_switch":true,"affected":{{"strategies_stopped":{d},"orders_cancelled":{d},"positions_closed":{d}}}}}}}
        , .{ result.strategies_stopped, result.orders_cancelled, result.positions_closed }) catch
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

        const json = std.fmt.bufPrint(&buf,
            \\{{"success":true,"data":{{"status":"{s}","components":{{"api_server":"up","engine_manager":"up"}},"metrics":{{"running_strategies":{d},"running_live":{d},"active_backtests":{d},"kill_switch_active":{s},"uptime_seconds":{d}}}}}}}
        , .{
            health.status,
            health.running_strategies,
            health.running_live,
            health.running_backtests,
            if (health.kill_switch_active) "true" else "false",
            ctx.uptime(),
        }) catch
            \\{"success":true,"data":{"status":"healthy"}}
        ;
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
    // Import log buffer module
    const log_buffer = @import("../core/log_buffer.zig");

    // Parse query parameters for filtering
    var limit: usize = 100;
    var min_level: ?@import("../core/logger.zig").Level = null;

    // Try to get limit from query params (using getParamSlice from zap)
    if (r.getParamSlice("limit")) |limit_str| {
        limit = std.fmt.parseInt(usize, limit_str, 10) catch 100;
        if (limit > 1000) limit = 1000; // Cap at 1000
    }

    // Try to get level filter
    if (r.getParamSlice("level")) |level_str| {
        if (std.mem.eql(u8, level_str, "trace")) {
            min_level = .trace;
        } else if (std.mem.eql(u8, level_str, "debug")) {
            min_level = .debug;
        } else if (std.mem.eql(u8, level_str, "info")) {
            min_level = .info;
        } else if (std.mem.eql(u8, level_str, "warn")) {
            min_level = .warn;
        } else if (std.mem.eql(u8, level_str, "error")) {
            min_level = .err;
        }
    }

    // Get global log buffer
    const buffer = log_buffer.getGlobalBuffer() orelse {
        // No log buffer configured - return empty with message
        try r.setContentType(.JSON);
        try r.sendBody(
            \\{"success":true,"data":{"logs":[],"total":0,"has_more":false,"message":"Log buffer not initialized"}}
        );
        return;
    };

    // Get recent logs
    const logs = buffer.getRecent(ctx.allocator, limit, min_level, null) catch {
        r.setStatus(.internal_server_error);
        try r.sendJson(
            \\{"success":false,"error":{"code":"LOG_FETCH_FAILED","message":"Failed to fetch logs"}}
        );
        return;
    };
    defer {
        for (logs) |entry| {
            ctx.allocator.free(entry.message);
            if (entry.source) |src| ctx.allocator.free(src);
            if (entry.context) |log_ctx| ctx.allocator.free(log_ctx);
        }
        ctx.allocator.free(logs);
    }

    // Build JSON response
    var response_buf = std.ArrayList(u8){};
    defer response_buf.deinit(ctx.allocator);

    const writer = response_buf.writer(ctx.allocator);
    try writer.writeAll("{\"success\":true,\"data\":{\"logs\":[");

    for (logs, 0..) |entry, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.writeAll("{");

        // Level
        try std.fmt.format(writer, "\"level\":\"{s}\",", .{entry.level.toString()});

        // Timestamp
        try std.fmt.format(writer, "\"timestamp\":{d},", .{entry.timestamp});

        // Message (escape JSON special chars)
        try writer.writeAll("\"message\":\"");
        for (entry.message) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
        try writer.writeAll("\"");

        // Source (optional)
        if (entry.source) |src| {
            try std.fmt.format(writer, ",\"source\":\"{s}\"", .{src});
        }

        try writer.writeAll("}");
    }

    try writer.writeAll("],\"total\":");
    try std.fmt.format(writer, "{d}", .{buffer.getCount()});
    try writer.writeAll(",\"has_more\":");
    try writer.writeAll(if (logs.len == limit) "true" else "false");
    try writer.writeAll("}}");

    try r.setContentType(.JSON);
    try r.sendBody(response_buf.items);
}

// ============================================================================
// AI Configuration Handlers
// ============================================================================

fn handleAIConfig(r: zap.Request, ctx: *ServerContext, method: zap.http.Method) !void {
    const manager = ctx.deps.engine_manager orelse {
        r.setStatus(.service_unavailable);
        try r.sendJson(
            \\{"success":false,"error":{"code":"NO_ENGINE","message":"Engine manager not configured"}}
        );
        return;
    };

    switch (method) {
        .GET => {
            // Get current AI status
            const status = manager.getAIStatus();
            var buf: [1024]u8 = undefined;

            const endpoint_str = if (status.api_endpoint) |ep| ep else "null";
            const has_endpoint = status.api_endpoint != null;

            const json = std.fmt.bufPrint(&buf,
                \\{{"success":true,"data":{{"enabled":{s},"provider":"{s}","model_id":"{s}","api_endpoint":{s}"{s}"{s},"has_api_key":{s},"connected":{s}}}}}
            , .{
                if (status.enabled) "true" else "false",
                status.provider,
                status.model_id,
                if (has_endpoint) "\"" else "",
                endpoint_str,
                if (has_endpoint) "\"" else "",
                if (status.has_api_key) "true" else "false",
                if (status.connected) "true" else "false",
            }) catch
                \\{"success":true,"data":{"enabled":false,"provider":"openai","model_id":"gpt-4o"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
        },
        .POST, .PUT, .PATCH => {
            // Update AI configuration
            const body = r.body orelse {
                r.setStatus(.bad_request);
                try r.sendJson(
                    \\{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Request body required"}}
                );
                return;
            };

            const AIConfigRequest = struct {
                provider: ?[]const u8 = null,
                model_id: ?[]const u8 = null,
                api_endpoint: ?[]const u8 = null,
                api_key: ?[]const u8 = null,
            };

            const parsed = std.json.parseFromSlice(AIConfigRequest, ctx.allocator, body, .{}) catch {
                r.setStatus(.bad_request);
                try r.sendJson(
                    \\{"success":false,"error":{"code":"PARSE_ERROR","message":"Invalid JSON body"}}
                );
                return;
            };
            defer parsed.deinit();

            const req = parsed.value;

            // Update configuration
            manager.updateAIConfig(
                req.provider,
                req.model_id,
                req.api_endpoint,
                req.api_key,
                null, // don't auto-enable on config update
            );

            const status = manager.getAIStatus();
            var buf: [512]u8 = undefined;
            const json = std.fmt.bufPrint(&buf,
                \\{{"success":true,"data":{{"message":"AI configuration updated","provider":"{s}","model_id":"{s}","has_api_key":{s}}}}}
            , .{
                status.provider,
                status.model_id,
                if (status.has_api_key) "true" else "false",
            }) catch
                \\{"success":true,"data":{"message":"AI configuration updated"}}
            ;
            try r.setContentType(.JSON);
            try r.sendBody(json);
        },
        else => {
            r.setStatus(.method_not_allowed);
            try r.sendJson(
                \\{"success":false,"error":{"code":"METHOD_NOT_ALLOWED","message":"Use GET to read config, POST/PUT/PATCH to update"}}
            );
        },
    }
}

fn handleAIEnable(r: zap.Request, ctx: *ServerContext, method: zap.http.Method) !void {
    if (method != .POST) {
        r.setStatus(.method_not_allowed);
        try r.sendJson(
            \\{"success":false,"error":{"code":"METHOD_NOT_ALLOWED","message":"Use POST to enable AI"}}
        );
        return;
    }

    const manager = ctx.deps.engine_manager orelse {
        r.setStatus(.service_unavailable);
        try r.sendJson(
            \\{"success":false,"error":{"code":"NO_ENGINE","message":"Engine manager not configured"}}
        );
        return;
    };

    // Try to initialize the AI client
    manager.initAIClient() catch |err| {
        r.setStatus(.bad_request);
        var buf: [256]u8 = undefined;
        const json = std.fmt.bufPrint(&buf,
            \\{{"success":false,"error":{{"code":"AI_INIT_FAILED","message":"Failed to initialize AI: {s}"}}}}
        , .{@errorName(err)}) catch
            \\{"success":false,"error":{"code":"AI_INIT_FAILED","message":"Failed to initialize AI client"}}
        ;
        try r.setContentType(.JSON);
        try r.sendBody(json);
        return;
    };

    const status = manager.getAIStatus();
    var buf: [512]u8 = undefined;
    const json = std.fmt.bufPrint(&buf,
        \\{{"success":true,"data":{{"enabled":true,"provider":"{s}","model_id":"{s}","message":"AI enabled successfully"}}}}
    , .{ status.provider, status.model_id }) catch
        \\{"success":true,"data":{"enabled":true,"message":"AI enabled successfully"}}
    ;
    try r.setContentType(.JSON);
    try r.sendBody(json);
}

fn handleAIDisable(r: zap.Request, ctx: *ServerContext, method: zap.http.Method) !void {
    if (method != .POST) {
        r.setStatus(.method_not_allowed);
        try r.sendJson(
            \\{"success":false,"error":{"code":"METHOD_NOT_ALLOWED","message":"Use POST to disable AI"}}
        );
        return;
    }

    const manager = ctx.deps.engine_manager orelse {
        r.setStatus(.service_unavailable);
        try r.sendJson(
            \\{"success":false,"error":{"code":"NO_ENGINE","message":"Engine manager not configured"}}
        );
        return;
    };

    manager.disableAI();

    try r.setContentType(.JSON);
    try r.sendBody(
        \\{"success":true,"data":{"enabled":false,"message":"AI disabled successfully"}}
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
