//! Authentication Handlers
//!
//! Handles authentication-related API endpoints:
//! - POST /api/v1/auth/login - User login, returns JWT
//! - POST /api/v1/auth/refresh - Refresh JWT token
//! - GET /api/v1/auth/me - Get current user info

const std = @import("std");
const httpz = @import("httpz");

const jwt = @import("../jwt.zig");
const auth_middleware = @import("../middleware/auth.zig");

/// Login request body
pub const LoginRequest = struct {
    username: []const u8,
    password: []const u8,
};

/// Login response
pub const LoginResponse = struct {
    token: []const u8,
    expires_in: i64,
    token_type: []const u8 = "Bearer",
};

/// User info response
pub const UserInfoResponse = struct {
    user_id: []const u8,
    issued_at: i64,
    expires_at: i64,
    issuer: ?[]const u8,
};

/// Authentication handler context
pub const AuthHandlers = struct {
    jwt_manager: *jwt.JwtManager,
    // In a real app, this would be a user database or auth service
    // For now, we use a simple static check

    const Self = @This();

    /// Initialize auth handlers
    pub fn init(jwt_manager: *jwt.JwtManager) Self {
        return .{
            .jwt_manager = jwt_manager,
        };
    }

    /// POST /api/v1/auth/login
    /// Authenticate user and return JWT token
    pub fn login(self: *Self, request: *httpz.Request, response: *httpz.Response) !void {
        // Parse request body
        const body = request.body() orelse {
            response.setStatus(.bad_request);
            try response.json(.{
                .@"error" = "Missing request body",
            }, .{});
            return;
        };

        const parsed = std.json.parseFromSlice(LoginRequest, request.arena, body, .{}) catch {
            response.setStatus(.bad_request);
            try response.json(.{
                .@"error" = "Invalid JSON format",
                .expected = "{ \"username\": \"...\", \"password\": \"...\" }",
            }, .{});
            return;
        };
        defer parsed.deinit();

        const login_req = parsed.value;

        // Validate credentials (simple check for demo)
        // In production, this would check against a real user database
        if (!validateCredentials(login_req.username, login_req.password)) {
            response.setStatus(.unauthorized);
            try response.json(.{
                .@"error" = "Invalid credentials",
            }, .{});
            return;
        }

        // Generate JWT token
        const token = self.jwt_manager.generateToken(login_req.username) catch |err| {
            std.log.err("Failed to generate token: {}", .{err});
            response.setStatus(.internal_server_error);
            try response.json(.{
                .@"error" = "Failed to generate token",
            }, .{});
            return;
        };
        defer request.arena.free(token);

        // Return token
        try response.json(.{
            .token = token,
            .expires_in = self.jwt_manager.expiry_seconds,
            .token_type = "Bearer",
        }, .{});
    }

    /// POST /api/v1/auth/refresh
    /// Refresh JWT token
    pub fn refresh(self: *Self, request: *httpz.Request, response: *httpz.Response) !void {
        // Get current token from Authorization header
        const auth_header = request.header("authorization") orelse {
            response.setStatus(.unauthorized);
            try response.json(.{
                .@"error" = "Missing Authorization header",
            }, .{});
            return;
        };

        const token = auth_middleware.extractBearerToken(auth_header) orelse {
            response.setStatus(.unauthorized);
            try response.json(.{
                .@"error" = "Invalid Authorization format. Expected: Bearer <token>",
            }, .{});
            return;
        };

        // Refresh the token
        const new_token = self.jwt_manager.refreshToken(token) catch |err| {
            const err_msg = switch (err) {
                error.TokenExpired => "Token has expired. Please login again.",
                error.InvalidSignature => "Invalid token signature.",
                else => "Invalid token.",
            };
            response.setStatus(.unauthorized);
            try response.json(.{
                .@"error" = err_msg,
            }, .{});
            return;
        };
        defer request.arena.free(new_token);

        try response.json(.{
            .token = new_token,
            .expires_in = self.jwt_manager.expiry_seconds,
            .token_type = "Bearer",
        }, .{});
    }

    /// GET /api/v1/auth/me
    /// Get current user info from token
    pub fn me(self: *Self, request: *httpz.Request, response: *httpz.Response) !void {
        // Authenticate request
        const auth_ctx = auth_middleware.authenticate(self.jwt_manager, request) catch |err| {
            const err_msg = switch (err) {
                auth_middleware.AuthError.MissingAuthHeader => "Missing Authorization header",
                auth_middleware.AuthError.InvalidAuthFormat => "Invalid Authorization format",
                auth_middleware.AuthError.TokenExpired => "Token has expired",
                auth_middleware.AuthError.InvalidSignature => "Invalid token signature",
                else => "Invalid token",
            };
            response.setStatus(.unauthorized);
            try response.json(.{
                .@"error" = err_msg,
            }, .{});
            return;
        };

        // Return user info
        try response.json(.{
            .user_id = auth_ctx.payload.sub,
            .issued_at = auth_ctx.payload.iat,
            .expires_at = auth_ctx.payload.exp,
            .issuer = auth_ctx.payload.iss,
        }, .{});
    }
};

/// Simple credential validation
/// In production, this would check against a real user database with hashed passwords
fn validateCredentials(username: []const u8, password: []const u8) bool {
    // Demo credentials - in production use proper authentication
    // NEVER hardcode credentials like this in real applications!
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

// ============================================================================
// Tests
// ============================================================================

test "validateCredentials: valid credentials" {
    try std.testing.expect(validateCredentials("admin", "admin123"));
    try std.testing.expect(validateCredentials("trader", "trader123"));
}

test "validateCredentials: invalid credentials" {
    try std.testing.expect(!validateCredentials("admin", "wrong"));
    try std.testing.expect(!validateCredentials("unknown", "pass"));
    try std.testing.expect(!validateCredentials("", ""));
}
