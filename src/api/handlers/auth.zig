//! Authentication Types and Helpers
//!
//! Provides types and helper functions for authentication.

const std = @import("std");

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

/// Simple credential validation
/// In production, this would check against a real user database with hashed passwords
pub fn validateCredentials(username: []const u8, password: []const u8) bool {
    // Demo credentials - in production use proper authentication
    // NEVER hardcode credentials like this in real applications!
    const demo_users = [_]struct { user: []const u8, pass: []const u8 }{
        .{ .user = "admin", .pass = "admin123" },
        .{ .user = "trader", .pass = "trader123" },
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

test "validateCredentials: valid credentials" {
    try std.testing.expect(validateCredentials("admin", "admin123"));
    try std.testing.expect(validateCredentials("trader", "trader123"));
}

test "validateCredentials: invalid credentials" {
    try std.testing.expect(!validateCredentials("admin", "wrong"));
    try std.testing.expect(!validateCredentials("unknown", "pass"));
    try std.testing.expect(!validateCredentials("", ""));
}
