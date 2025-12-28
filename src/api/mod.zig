//! API Module - REST API Server
//!
//! Provides a high-performance REST API server for zigQuant using http.zig.
//!
//! Features:
//! - JWT authentication
//! - CORS support
//! - Request logging
//! - Health check endpoints
//! - Strategy management API
//! - Backtest API
//! - Trading API
//! - Prometheus metrics export

const std = @import("std");

// Re-export public types
pub const Server = @import("server.zig").ApiServer;
pub const Config = @import("config.zig").ApiConfig;
pub const handlers = @import("handlers/mod.zig");
pub const middleware = @import("middleware/mod.zig");

// Version info
pub const version = "1.0.0";

test {
    std.testing.refAllDecls(@This());
}
