//! zigQuant - High-Performance Quantitative Trading Framework
//!
//! This is the root module for the zigQuant library.
const std = @import("std");

// Core modules
pub const time = @import("core/time.zig");
pub const errors = @import("core/errors.zig");
pub const logger = @import("core/logger.zig");
pub const config = @import("core/config.zig");
pub const decimal = @import("core/decimal.zig");

// Re-export commonly used types
pub const Timestamp = time.Timestamp;
pub const Duration = time.Duration;
pub const KlineInterval = time.KlineInterval;
pub const Decimal = decimal.Decimal;

// Re-export error types
pub const NetworkError = errors.NetworkError;
pub const APIError = errors.APIError;
pub const DataError = errors.DataError;
pub const BusinessError = errors.BusinessError;
pub const SystemError = errors.SystemError;
pub const TradingError = errors.TradingError;
pub const ErrorContext = errors.ErrorContext;
pub const WrappedError = errors.WrappedError;
pub const RetryConfig = errors.RetryConfig;

// Re-export logger types
pub const Logger = logger.Logger;
pub const Level = logger.Level;
pub const ConsoleWriter = logger.ConsoleWriter;
pub const FileWriter = logger.FileWriter;
pub const JSONWriter = logger.JSONWriter;
pub const StdLogWriter = logger.StdLogWriter;

// Re-export config types
pub const AppConfig = config.AppConfig;
pub const ServerConfig = config.ServerConfig;
pub const ExchangeConfig = config.ExchangeConfig;
pub const TradingConfig = config.TradingConfig;
pub const LoggingConfig = config.LoggingConfig;
pub const ConfigLoader = config.ConfigLoader;
pub const ConfigError = config.ConfigError;

test {
    // Run tests from all modules
    std.testing.refAllDecls(@This());
    _ = time;
    _ = errors;
    _ = logger;
    _ = config;
    _ = decimal;
}
