//! API Module - REST API + WebSocket Server
//!
//! Provides a high-performance API server for zigQuant based on Zap/facil.io.
//!
//! Features:
//! - High-performance HTTP server (facil.io under the hood)
//! - WebSocket real-time communication
//! - JWT authentication
//! - Grid Trading API
//! - Backtest API
//! - System API (kill-switch, health, logs)
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

// Re-export WebSocket types
pub const websocket = @import("websocket.zig");
pub const WebSocketServer = websocket.WebSocketServer;
pub const WsServerConfig = websocket.WsServerConfig;
pub const WsContext = websocket.WsContext;

// Version info
pub const version = "2.0.0";

test {
    std.testing.refAllDecls(@This());
}
