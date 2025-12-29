//! API Module - REST API Server
//!
//! Provides a high-performance REST API server for zigQuant based on Zap/facil.io.
//!
//! Features:
//! - High-performance HTTP server (facil.io under the hood)
//! - JWT authentication
//! - Grid Trading API
//! - Health check endpoints
//! - Prometheus metrics export
//!
//! Usage:
//!   const zigQuant = @import("zigQuant");
//!   const server = try zigQuant.ZapServer.init(allocator, config, deps);
//!   defer server.deinit();
//!   try server.start();

const std = @import("std");

// Re-export Zap server types
pub const zap_server = @import("zap_server.zig");
pub const Server = zap_server.ZapServer;
pub const Config = zap_server.Config;
pub const Dependencies = zap_server.Dependencies;
pub const ServerContext = zap_server.ServerContext;
pub const JwtManager = zap_server.JwtManager;
pub const JwtPayload = zap_server.JwtPayload;

// Version info
pub const version = "2.0.0";

test {
    std.testing.refAllDecls(@This());
}
