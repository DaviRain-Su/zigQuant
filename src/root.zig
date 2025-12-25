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

// Strategy modules
pub const strategy_signal = @import("strategy/signal.zig");
pub const strategy_types = @import("strategy/types.zig");
pub const strategy_interface = @import("strategy/interface.zig");
pub const strategy_position_manager = @import("strategy/position_manager.zig");
pub const strategy_market_data = @import("strategy/market_data.zig");
pub const strategy_risk = @import("strategy/risk.zig");
pub const strategy_executor = @import("strategy/executor.zig");
pub const strategy_context = @import("strategy/context.zig");

// Built-in strategies
pub const strategy_dual_ma = @import("strategy/builtin/dual_ma.zig");
pub const strategy_mean_reversion = @import("strategy/builtin/mean_reversion.zig");
pub const strategy_breakout = @import("strategy/builtin/breakout.zig");

// Indicator modules
pub const indicator_interface = @import("strategy/indicators/interface.zig");
pub const indicator_utils = @import("strategy/indicators/utils.zig");
pub const indicator_manager = @import("strategy/indicators/manager.zig");
pub const indicator_helpers = @import("strategy/indicators/helpers.zig");
pub const indicator_sma = @import("strategy/indicators/sma.zig");
pub const indicator_ema = @import("strategy/indicators/ema.zig");
pub const indicator_rsi = @import("strategy/indicators/rsi.zig");
pub const indicator_macd = @import("strategy/indicators/macd.zig");
pub const indicator_bollinger = @import("strategy/indicators/bollinger.zig");

// Trading modules
pub const order_store = @import("trading/order_store.zig");
pub const order_manager = @import("trading/order_manager.zig");
pub const position = @import("trading/position.zig");
pub const account = @import("trading/account.zig");
pub const position_tracker = @import("trading/position_tracker.zig");

// Backtest modules
pub const backtest_types = @import("backtest/types.zig");
pub const backtest_event = @import("backtest/event.zig");
pub const backtest_executor = @import("backtest/executor.zig");
pub const backtest_account = @import("backtest/account.zig");
pub const backtest_position = @import("backtest/position.zig");
pub const backtest_data_feed = @import("backtest/data_feed.zig");
pub const backtest_engine = @import("backtest/engine.zig");
pub const backtest_analyzer = @import("backtest/analyzer.zig");

// Re-export market data types
pub const OrderBook = orderbook.OrderBook;
pub const OrderBookManager = orderbook.OrderBookManager;
pub const BookLevel = orderbook.Level; // Renamed to avoid conflict with logger.Level
pub const SlippageResult = orderbook.SlippageResult;
pub const Candle = candles.Candle;
pub const Candles = candles.Candles;
pub const IndicatorSeries = candles.IndicatorSeries;
pub const IndicatorValue = candles.IndicatorValue;

// Re-export strategy types
pub const Signal = strategy_signal.Signal;
pub const SignalType = strategy_signal.SignalType;
pub const SignalMetadata = strategy_signal.SignalMetadata;
pub const SignalIndicatorValue = strategy_signal.IndicatorValue;
pub const StrategyMetadata = strategy_types.StrategyMetadata;
pub const StrategyParameter = strategy_types.StrategyParameter;
pub const ParameterType = strategy_types.ParameterType;
pub const ParameterValue = strategy_types.ParameterValue;
pub const StrategyConfig = strategy_types.StrategyConfig;
pub const MinimalROI = strategy_types.MinimalROI;
pub const TrailingStopConfig = strategy_types.TrailingStopConfig;
pub const IStrategy = strategy_interface.IStrategy;
pub const StrategyPosition = strategy_position_manager.StrategyPosition;
pub const PositionStatus = strategy_position_manager.PositionStatus;
pub const PositionManager = strategy_position_manager.PositionManager;
pub const MarketDataProvider = strategy_market_data.MarketDataProvider;
pub const RiskManager = strategy_risk.RiskManager;
pub const OrderExecutor = strategy_executor.OrderExecutor;
pub const StrategyContext = strategy_context.StrategyContext;

// Re-export built-in strategies
pub const DualMAStrategy = strategy_dual_ma.DualMAStrategy;
pub const RSIMeanReversionStrategy = strategy_mean_reversion.RSIMeanReversionStrategy;
pub const BollingerBreakoutStrategy = strategy_breakout.BollingerBreakoutStrategy;

// Re-export indicator types
pub const IIndicator = indicator_interface.IIndicator;
pub const IndicatorManager = indicator_manager.IndicatorManager;
pub const CacheStats = indicator_manager.CacheStats;
pub const SMA = indicator_sma.SMA;
pub const EMA = indicator_ema.EMA;
pub const RSI = indicator_rsi.RSI;
pub const MACD = indicator_macd.MACD;
pub const MACDResult = indicator_macd.MACDResult;
pub const BollingerBands = indicator_bollinger.BollingerBands;
pub const BollingerResult = indicator_bollinger.BollingerResult;

// Re-export trading types
pub const OrderStore = order_store.OrderStore;
pub const OrderManager = order_manager.OrderManager;
pub const TradingPosition = position.Position;
pub const Account = account.Account;
pub const PositionTracker = position_tracker.PositionTracker;

// Re-export backtest types
pub const BacktestEngine = backtest_engine.BacktestEngine;
pub const BacktestConfig = backtest_types.BacktestConfig;
pub const BacktestResult = backtest_types.BacktestResult;
pub const BacktestError = backtest_types.BacktestError;
pub const Trade = backtest_types.Trade;
pub const EquitySnapshot = backtest_types.EquitySnapshot;
pub const PositionSide = backtest_types.PositionSide;
pub const PerformanceAnalyzer = backtest_analyzer.PerformanceAnalyzer;
pub const PerformanceMetrics = backtest_analyzer.PerformanceMetrics;
pub const HistoricalDataFeed = backtest_data_feed.HistoricalDataFeed;
pub const BacktestAccount = backtest_account.Account;
pub const BacktestPosition = backtest_position.Position;
pub const BacktestPositionManager = backtest_position.PositionManager;
pub const BacktestOrderExecutor = backtest_executor.OrderExecutor;

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

    // Strategy modules
    _ = strategy_signal;
    _ = strategy_types;
    _ = strategy_interface;
    _ = strategy_position_manager;
    _ = strategy_market_data;
    _ = strategy_risk;
    _ = strategy_executor;
    _ = strategy_context;
    _ = strategy_dual_ma;
    _ = strategy_mean_reversion;
    _ = strategy_breakout;

    // Indicator modules
    _ = indicator_interface;
    _ = indicator_utils;
    _ = indicator_manager;
    _ = indicator_helpers;
    _ = indicator_sma;
    _ = indicator_ema;
    _ = indicator_rsi;
    _ = indicator_macd;
    _ = indicator_bollinger;

    // Trading modules
    _ = order_store;
    _ = order_manager;
    _ = position;
    _ = account;
    _ = position_tracker;

    // Backtest modules
    _ = backtest_types;
    _ = backtest_event;
    _ = backtest_executor;
    _ = backtest_account;
    _ = backtest_position;
    _ = backtest_data_feed;
    _ = backtest_engine;
    _ = backtest_analyzer;
}
