//! CORS Middleware
//!
//! Cross-Origin Resource Sharing (CORS) support for the API server.
//! Allows browsers to make requests from different origins.

const std = @import("std");
const httpz = @import("httpz");

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

/// Add CORS headers to a response
pub fn addCorsHeaders(
    response: *httpz.Response,
    origin: ?[]const u8,
    config: CorsConfig,
) void {
    // Determine the origin to use
    const cors_origin = if (origin) |o|
        if (isOriginAllowed(o, config.allowed_origins)) o else null
    else
        null;

    // If wildcard is allowed and no specific origin, use "*"
    const wildcard: []const u8 = "*";
    const origin_value: ?[]const u8 = cors_origin orelse (if (isWildcardAllowed(config.allowed_origins)) wildcard else null);

    if (origin_value) |ov| {
        response.header("Access-Control-Allow-Origin", ov);
    }

    if (config.allow_credentials) {
        response.header("Access-Control-Allow-Credentials", "true");
    }

    response.header("Access-Control-Allow-Methods", config.allowed_methods);
    response.header("Access-Control-Allow-Headers", config.allowed_headers);
    response.header("Access-Control-Expose-Headers", config.exposed_headers);
}

/// Handle preflight OPTIONS request
pub fn handlePreflight(
    response: *httpz.Response,
    origin: ?[]const u8,
    config: CorsConfig,
) void {
    addCorsHeaders(response, origin, config);

    // Add max-age for preflight caching
    var max_age_buf: [16]u8 = undefined;
    const max_age_str = std.fmt.bufPrint(&max_age_buf, "{d}", .{config.max_age}) catch "86400";
    response.header("Access-Control-Max-Age", max_age_str);

    // Return 204 No Content for preflight
    response.status = 204;
}

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
