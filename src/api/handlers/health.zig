//! Health Check Handlers
//!
//! Helper types and utilities for health check endpoints.
//!
//! Note: The actual route handlers are implemented in server.zig
//! because they require access to ServerContext.

const std = @import("std");

/// Health check response structure
pub const HealthResponse = struct {
    status: []const u8,
    version: []const u8,
    uptime_seconds: i64,
    timestamp: i64,
};

/// Readiness check response structure
pub const ReadyResponse = struct {
    ready: bool,
    checks: struct {
        jwt_configured: bool,
        server_running: bool,
    },
};

/// Version response structure
pub const VersionResponse = struct {
    name: []const u8,
    version: []const u8,
    api_version: []const u8,
    zig_version: []const u8,
};

test "health types compile" {
    const health = HealthResponse{
        .status = "healthy",
        .version = "1.0.0",
        .uptime_seconds = 100,
        .timestamp = 1234567890,
    };
    _ = health;
}
