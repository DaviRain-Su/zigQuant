//! API Configuration
//!
//! Configuration types for the REST API server.
//! Imports exchange types from zigQuant module to avoid module conflicts.

const std = @import("std");

// Import from zigQuant module (not direct file imports to avoid module conflicts)
const zigQuant = @import("zigQuant");
pub const IExchange = zigQuant.IExchange;
pub const ExchangeConfig = zigQuant.ExchangeConfig;
pub const Position = zigQuant.Position;
pub const Balance = zigQuant.Balance;
pub const Order = zigQuant.Order;
pub const Logger = zigQuant.Logger;

/// API Server Configuration
pub const ApiConfig = struct {
    /// Host to bind to
    host: []const u8 = "0.0.0.0",

    /// Port to listen on
    port: u16 = 8080,

    /// Number of worker threads (0 = auto-detect based on CPU cores)
    workers: u16 = 0,

    /// JWT secret key for signing tokens (must be at least 32 bytes)
    jwt_secret: []const u8,

    /// JWT token expiry in hours
    jwt_expiry_hours: u32 = 24,

    /// Allowed CORS origins
    cors_origins: []const []const u8 = &.{"*"},

    /// Read timeout in milliseconds
    read_timeout_ms: u32 = 30000,

    /// Write timeout in milliseconds
    write_timeout_ms: u32 = 30000,

    /// Maximum request body size in bytes
    max_body_size: usize = 1024 * 1024, // 1MB

    /// Enable request logging
    enable_logging: bool = true,

    /// Enable Prometheus metrics endpoint
    enable_metrics: bool = true,

    /// Validate configuration
    pub fn validate(self: ApiConfig) !void {
        if (self.jwt_secret.len < 32) {
            return error.JwtSecretTooShort;
        }

        if (self.port == 0) {
            return error.InvalidPort;
        }

        if (self.jwt_expiry_hours == 0) {
            return error.InvalidJwtExpiry;
        }
    }

    /// Load configuration from environment variables
    pub fn fromEnv() !ApiConfig {
        var config = ApiConfig{
            .jwt_secret = undefined,
        };

        // Required: JWT secret
        config.jwt_secret = std.posix.getenv("ZIGQUANT_JWT_SECRET") orelse {
            return error.MissingJwtSecret;
        };

        // Optional: Host
        if (std.posix.getenv("ZIGQUANT_API_HOST")) |host| {
            config.host = host;
        }

        // Optional: Port
        if (std.posix.getenv("ZIGQUANT_API_PORT")) |port_str| {
            config.port = std.fmt.parseInt(u16, port_str, 10) catch {
                return error.InvalidPort;
            };
        }

        // Optional: Workers
        if (std.posix.getenv("ZIGQUANT_API_WORKERS")) |workers_str| {
            config.workers = std.fmt.parseInt(u16, workers_str, 10) catch {
                return error.InvalidWorkers;
            };
        }

        // Optional: JWT expiry hours
        if (std.posix.getenv("ZIGQUANT_JWT_EXPIRY_HOURS")) |expiry_str| {
            config.jwt_expiry_hours = std.fmt.parseInt(u32, expiry_str, 10) catch {
                return error.InvalidJwtExpiry;
            };
        }

        try config.validate();
        return config;
    }
};

/// Dependencies for the API server
pub const ApiDependencies = struct {
    /// Exchange interface (polymorphic - can be any exchange implementation)
    exchange: ?IExchange = null,

    /// Exchange configuration
    exchange_config: ?ExchangeConfig = null,

    /// Backtest results directory
    backtest_results_dir: []const u8 = "backtest_results",

    /// Check if exchange is configured
    pub fn isExchangeConfigured(self: ApiDependencies) bool {
        return self.exchange != null;
    }
};

test "ApiConfig: validate - valid config" {
    const config = ApiConfig{
        .jwt_secret = "this-is-a-secret-key-with-32-bytes!!",
    };
    try config.validate();
}

test "ApiConfig: validate - jwt secret too short" {
    const config = ApiConfig{
        .jwt_secret = "short",
    };
    try std.testing.expectError(error.JwtSecretTooShort, config.validate());
}
