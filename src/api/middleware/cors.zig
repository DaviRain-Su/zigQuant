//! CORS Middleware
//!
//! Cross-Origin Resource Sharing (CORS) support for the API server.
//! Allows browsers to make requests from different origins.
//!
//! Note: CORS headers are now added directly in server.zig handleParsedRequest.
//! This module provides configuration types and helper functions only.

const std = @import("std");

/// CORS configuration
pub const CorsConfig = struct {
    /// Allowed origins ("*" for any)
    allowed_origins: []const []const u8 = &.{"*"},
    /// Allowed HTTP methods
    allowed_methods: []const u8 = "GET, POST, PUT, DELETE, PATCH, OPTIONS",
    /// Allowed headers
    allowed_headers: []const u8 = "Content-Type, Authorization, X-Requested-With",
    /// Exposed headers (headers the browser can access)
    exposed_headers: []const u8 = "X-Request-Id",
    /// Allow credentials (cookies, authorization headers)
    allow_credentials: bool = true,
    /// Max age for preflight cache (in seconds)
    max_age: u32 = 86400, // 24 hours
};

/// Check if origin is allowed
fn isOriginAllowed(origin: []const u8, allowed: []const []const u8) bool {
    for (allowed) |allowed_origin| {
        if (std.mem.eql(u8, allowed_origin, "*")) {
            return true;
        }
        if (std.mem.eql(u8, allowed_origin, origin)) {
            return true;
        }
    }
    return false;
}

/// Check if wildcard is in allowed origins
fn isWildcardAllowed(allowed: []const []const u8) bool {
    for (allowed) |allowed_origin| {
        if (std.mem.eql(u8, allowed_origin, "*")) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "isOriginAllowed: wildcard" {
    const allowed = &[_][]const u8{"*"};
    try std.testing.expect(isOriginAllowed("https://example.com", allowed));
    try std.testing.expect(isOriginAllowed("http://localhost:3000", allowed));
}

test "isOriginAllowed: specific origin" {
    const allowed = &[_][]const u8{ "https://example.com", "http://localhost:3000" };
    try std.testing.expect(isOriginAllowed("https://example.com", allowed));
    try std.testing.expect(isOriginAllowed("http://localhost:3000", allowed));
    try std.testing.expect(!isOriginAllowed("https://other.com", allowed));
}

test "isWildcardAllowed" {
    try std.testing.expect(isWildcardAllowed(&[_][]const u8{"*"}));
    try std.testing.expect(isWildcardAllowed(&[_][]const u8{ "https://example.com", "*" }));
    try std.testing.expect(!isWildcardAllowed(&[_][]const u8{"https://example.com"}));
}
