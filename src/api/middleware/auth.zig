//! Authentication Middleware
//!
//! JWT-based authentication middleware for the API server.
//! Validates Bearer tokens and attaches user context to requests.

const std = @import("std");
const httpz = @import("httpz");
const jwt = @import("../jwt.zig");

/// Authentication context attached to requests
pub const AuthContext = struct {
    user_id: []const u8,
    payload: jwt.JwtPayload,
};

/// Authentication error types
pub const AuthError = error{
    MissingAuthHeader,
    InvalidAuthFormat,
    InvalidToken,
    TokenExpired,
    InvalidSignature,
    MissingSubject,
    MissingIssuedAt,
    MissingExpiration,
    InvalidExpiration,
    InvalidSubject,
    InvalidIssuedAt,
};

/// Extract Bearer token from Authorization header
pub fn extractBearerToken(auth_header: []const u8) ?[]const u8 {
    const prefix = "Bearer ";
    if (auth_header.len <= prefix.len) return null;
    if (!std.mem.startsWith(u8, auth_header, prefix)) return null;
    return auth_header[prefix.len..];
}

/// Authenticate a request using JWT
pub fn authenticate(
    jwt_manager: *const jwt.JwtManager,
    request: anytype,
) AuthError!AuthContext {
    // Get Authorization header
    const auth_header = request.header("authorization") orelse {
        return AuthError.MissingAuthHeader;
    };

    // Extract Bearer token
    const token = extractBearerToken(auth_header) orelse {
        return AuthError.InvalidAuthFormat;
    };

    // Verify token
    const payload = jwt_manager.verifyToken(token) catch |err| {
        return switch (err) {
            error.InvalidToken => AuthError.InvalidToken,
            error.InvalidSignature => AuthError.InvalidSignature,
            error.TokenExpired => AuthError.TokenExpired,
            error.MissingSubject => AuthError.MissingSubject,
            error.MissingIssuedAt => AuthError.MissingIssuedAt,
            error.MissingExpiration => AuthError.MissingExpiration,
            error.InvalidExpiration => AuthError.InvalidExpiration,
            error.InvalidSubject => AuthError.InvalidSubject,
            error.InvalidIssuedAt => AuthError.InvalidIssuedAt,
            else => AuthError.InvalidToken,
        };
    };

    return AuthContext{
        .user_id = payload.sub,
        .payload = payload,
    };
}

/// Send unauthorized response
pub fn sendUnauthorized(response: anytype, message: []const u8) !void {
    response.setStatus(.unauthorized);
    try response.json(.{
        .@"error" = "Unauthorized",
        .message = message,
    }, .{});
}

/// Send forbidden response
pub fn sendForbidden(response: anytype, message: []const u8) !void {
    response.setStatus(.forbidden);
    try response.json(.{
        .@"error" = "Forbidden",
        .message = message,
    }, .{});
}

// ============================================================================
// Tests
// ============================================================================

test "extractBearerToken: valid token" {
    const result = extractBearerToken("Bearer abc123xyz");
    try std.testing.expectEqualStrings("abc123xyz", result.?);
}

test "extractBearerToken: missing Bearer prefix" {
    const result = extractBearerToken("Basic abc123xyz");
    try std.testing.expect(result == null);
}

test "extractBearerToken: empty header" {
    const result = extractBearerToken("");
    try std.testing.expect(result == null);
}

test "extractBearerToken: just Bearer" {
    const result = extractBearerToken("Bearer ");
    try std.testing.expectEqualStrings("", result.?);
}
