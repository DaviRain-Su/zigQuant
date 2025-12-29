//! API Module - REST API Server
//!
//! Provides a high-performance REST API server for zigQuant.
//!
//! Two server implementations are available:
//! - Server (v1): Based on std.http - stable, feature-complete
//! - ZapServer (v2): Based on zap framework - available via zigQuant module
//!
//! Features:
//! - JWT authentication
//! - CORS support
//! - Request logging
//! - Health check endpoints
//! - Strategy management API
//! - Backtest API
//! - Trading API
//! - Grid Trading API
//! - Prometheus metrics export
//!
//! Note: ZapServer (v2) is accessed via the zigQuant module to avoid
//! module conflicts with zap dependency. Use:
//!   const zigQuant = @import("zigQuant");
//!   const server = try zigQuant.ZapServer.init(...);

const std = @import("std");

// Re-export public types for std.http server (v1)
pub const Server = @import("server.zig").ApiServer;
pub const config_mod = @import("config.zig");
pub const Config = config_mod.ApiConfig;
pub const Dependencies = config_mod.ApiDependencies;
pub const Jwt = @import("jwt.zig");
pub const JwtManager = Jwt.JwtManager;
pub const JwtPayload = Jwt.JwtPayload;
pub const handlers = @import("handlers/mod.zig");
pub const middleware = @import("middleware/mod.zig");

// Note: Zap-based server (v2) is NOT exported here to avoid module conflicts.
// Access via zigQuant module instead:
//   pub const ZapServer = zigQuant.ZapServer;
//   pub const ZapServerConfig = zigQuant.ZapServerConfig;
//   pub const ZapServerDependencies = zigQuant.ZapServerDependencies;

// Version info
pub const version = "1.0.0";

test {
    std.testing.refAllDecls(@This());
}
