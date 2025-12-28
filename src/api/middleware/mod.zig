//! API Middleware
//!
//! Middleware components for the API server.

const std = @import("std");

/// Authentication middleware
pub const auth = @import("auth.zig");
pub const AuthContext = auth.AuthContext;
pub const AuthError = auth.AuthError;

/// CORS middleware
pub const cors = @import("cors.zig");
pub const CorsConfig = cors.CorsConfig;

/// Logger middleware
pub const logger = @import("logger.zig");
pub const LogEntry = logger.LogEntry;
pub const LogLevel = logger.LogLevel;
pub const LoggerConfig = logger.LoggerConfig;

test {
    std.testing.refAllDecls(@This());
}
