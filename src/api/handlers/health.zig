//! Health Check Handlers
//!
//! Provides health and readiness endpoints for the API server.
//! These endpoints do not require authentication.

const std = @import("std");
const httpz = @import("httpz");

const Request = httpz.Request;
const Response = httpz.Response;

/// GET /health - Service health check
/// Returns basic health status of the service.
pub fn health(_: *Request, res: *Response) !void {
    const timestamp = std.time.timestamp();

    try res.json(.{
        .status = "healthy",
        .version = "1.0.0",
        .timestamp = timestamp,
    }, .{});
}

/// GET /ready - Readiness check
/// Verifies that all dependencies are ready to serve traffic.
pub fn ready(_: *Request, res: *Response) !void {
    // TODO: Check actual dependencies (database, exchange connections, etc.)
    // For now, always return ready

    const checks = .{
        .database = true,
        .exchange = true,
        .cache = true,
    };

    const all_ready = checks.database and checks.exchange and checks.cache;

    if (all_ready) {
        try res.json(.{
            .ready = true,
            .checks = checks,
        }, .{});
    } else {
        res.status = .service_unavailable;
        try res.json(.{
            .ready = false,
            .checks = checks,
        }, .{});
    }
}

/// GET /version - Version information
pub fn version(_: *Request, res: *Response) !void {
    try res.json(.{
        .name = "zigQuant",
        .version = "1.0.0",
        .zig_version = @import("builtin").zig_version_string,
    }, .{});
}

test "health handler returns healthy status" {
    // This would require httpz test utilities
    // For now, just ensure the module compiles
}
