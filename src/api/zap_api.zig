//! Zap API Module - Thin wrapper for Zap Server exports
//!
//! This module re-exports Zap server types for use within the zigQuant module.
//! It provides access to the Zap-based API server (v2) without importing jwt.zig
//! directly, which would cause module conflicts.

const zap_server = @import("zap_server.zig");

// Re-export Zap server types
pub const ZapServer = zap_server.ZapServer;
pub const Config = zap_server.Config;
pub const Dependencies = zap_server.Dependencies;
pub const ServerContext = zap_server.ServerContext;
