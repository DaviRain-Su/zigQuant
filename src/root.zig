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
pub const hyperliquid_connector = @import("exchange/hyperliquid/connector.zig");

// Hyperliquid modules
pub const hyperliquid = struct {
    pub const HyperliquidClient = @import("exchange/hyperliquid/http.zig").HttpClient;
    pub const HyperliquidWS = @import("exchange/hyperliquid/websocket.zig").HyperliquidWS;
    pub const InfoAPI = @import("exchange/hyperliquid/info_api.zig").InfoAPI;
    pub const ExchangeAPI = @import("exchange/hyperliquid/exchange_api.zig").ExchangeAPI;
    pub const Signer = @import("exchange/hyperliquid/auth.zig").Signer;
    pub const Subscription = @import("exchange/hyperliquid/ws_types.zig").Subscription;
    pub const Channel = @import("exchange/hyperliquid/ws_types.zig").Channel;
    pub const Message = @import("exchange/hyperliquid/ws_types.zig").Message;
};

// Market data modules
pub const orderbook = @import("market/orderbook.zig");
pub const candles = @import("market/candles.zig");

// Trading modules
pub const order_store = @import("trading/order_store.zig");
pub const order_manager = @import("trading/order_manager.zig");
pub const position = @import("trading/position.zig");
pub const account = @import("trading/account.zig");
pub const position_tracker = @import("trading/position_tracker.zig");

// Re-export market data types
pub const OrderBook = orderbook.OrderBook;
pub const OrderBookManager = orderbook.OrderBookManager;
pub const BookLevel = orderbook.Level; // Renamed to avoid conflict with logger.Level
pub const SlippageResult = orderbook.SlippageResult;
pub const Candle = candles.Candle;
pub const Candles = candles.Candles;
pub const IndicatorSeries = candles.IndicatorSeries;
pub const IndicatorValue = candles.IndicatorValue;

// Re-export trading types
pub const OrderStore = order_store.OrderStore;
pub const OrderManager = order_manager.OrderManager;
pub const TradingPosition = position.Position;
pub const Account = account.Account;
pub const PositionTracker = position_tracker.PositionTracker;

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
pub const Config = config;
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
pub const Timeframe = exchange_types.Timeframe;
pub const Side = exchange_types.Side;
pub const OrderType = exchange_types.OrderType;
pub const TimeInForce = exchange_types.TimeInForce;
pub const OrderStatus = exchange_types.OrderStatus;
pub const OrderRequest = exchange_types.OrderRequest;
pub const Order = exchange_types.Order;
pub const OrderUpdateEvent = exchange_types.OrderUpdateEvent;
pub const OrderFillEvent = exchange_types.OrderFillEvent;
pub const Ticker = exchange_types.Ticker;
pub const OrderbookLevel = exchange_types.OrderbookLevel;
pub const Orderbook = exchange_types.Orderbook;
pub const Balance = exchange_types.Balance;
pub const Position = exchange_types.Position;
pub const ExchangeRegistry = exchange_registry.ExchangeRegistry;
pub const SymbolMapper = exchange_symbol_mapper;
pub const ExchangeType = exchange_symbol_mapper.ExchangeType;
pub const HyperliquidConnector = hyperliquid_connector.HyperliquidConnector;

test {
    // Run tests from all modules
    std.testing.refAllDecls(@This());

    // Core modules
    _ = time;
    _ = errors;
    _ = logger;
    _ = config;
    _ = decimal;

    // Exchange abstraction modules
    _ = exchange_types;
    _ = exchange_interface;
    _ = exchange_registry;
    _ = exchange_symbol_mapper;
    _ = hyperliquid_connector;

    // Hyperliquid implementation modules
    _ = @import("exchange/hyperliquid/http.zig");
    _ = @import("exchange/hyperliquid/websocket.zig");
    _ = @import("exchange/hyperliquid/info_api.zig");
    _ = @import("exchange/hyperliquid/exchange_api.zig");
    _ = @import("exchange/hyperliquid/auth.zig");
    _ = @import("exchange/hyperliquid/ws_types.zig");
    _ = @import("exchange/hyperliquid/subscription.zig");
    _ = @import("exchange/hyperliquid/message_handler.zig");
    _ = @import("exchange/hyperliquid/rate_limiter.zig");
    _ = @import("exchange/hyperliquid/types.zig");

    // Market data modules
    _ = orderbook;
    _ = candles;

    // Trading modules
    _ = order_store;
    _ = order_manager;
    _ = position;
    _ = account;
    _ = position_tracker;
}
