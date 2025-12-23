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

// Exchange modules
pub const exchange_types = @import("exchange/types.zig");
pub const exchange_interface = @import("exchange/interface.zig");
pub const exchange_registry = @import("exchange/registry.zig");
pub const exchange_symbol_mapper = @import("exchange/symbol_mapper.zig");

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

// Re-export exchange types
pub const IExchange = exchange_interface.IExchange;
pub const TradingPair = exchange_types.TradingPair;
pub const Side = exchange_types.Side;
pub const OrderType = exchange_types.OrderType;
pub const TimeInForce = exchange_types.TimeInForce;
pub const OrderStatus = exchange_types.OrderStatus;
pub const OrderRequest = exchange_types.OrderRequest;
pub const Order = exchange_types.Order;
pub const Ticker = exchange_types.Ticker;
pub const OrderbookLevel = exchange_types.OrderbookLevel;
pub const Orderbook = exchange_types.Orderbook;
pub const Balance = exchange_types.Balance;
pub const Position = exchange_types.Position;
pub const ExchangeRegistry = exchange_registry.ExchangeRegistry;
pub const SymbolMapper = exchange_symbol_mapper;
pub const ExchangeType = exchange_symbol_mapper.ExchangeType;

test {
    // Run tests from all modules
    std.testing.refAllDecls(@This());
    _ = time;
    _ = errors;
    _ = logger;
    _ = config;
    _ = decimal;
    _ = exchange_types;
    _ = exchange_interface;
    _ = exchange_registry;
    _ = exchange_symbol_mapper;
}
