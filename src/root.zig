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
pub const message_bus = @import("core/message_bus.zig");
pub const cache = @import("core/cache.zig");
pub const data_engine = @import("core/data_engine.zig");
pub const execution_engine = @import("core/execution_engine.zig");
pub const live_engine = @import("trading/live_engine.zig");

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

// New v0.4.0 strategies
pub const strategy_triple_ma = @import("strategy/builtin/triple_ma.zig");
pub const strategy_macd_divergence = @import("strategy/builtin/macd_divergence.zig");

// Strategy factory
pub const StrategyFactory = @import("strategy/factory.zig").StrategyFactory;
pub const StrategyWrapper = @import("strategy/factory.zig").StrategyWrapper;

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

// New v0.4.0 indicators
pub const indicator_williams_r = @import("strategy/indicators/williams_r.zig");
pub const indicator_cci = @import("strategy/indicators/cci.zig");
pub const indicator_roc = @import("strategy/indicators/roc.zig");
pub const indicator_adx = @import("strategy/indicators/adx.zig");
pub const indicator_obv = @import("strategy/indicators/obv.zig");
pub const indicator_vwap = @import("strategy/indicators/vwap.zig");
pub const indicator_parabolic_sar = @import("strategy/indicators/parabolic_sar.zig");
pub const indicator_ichimoku = @import("strategy/indicators/ichimoku.zig");

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

// v0.4.0 Backtest export modules
pub const backtest_export = @import("backtest/export.zig");
pub const backtest_json_exporter = @import("backtest/json_exporter.zig");
pub const backtest_csv_exporter = @import("backtest/csv_exporter.zig");
pub const backtest_result_loader = @import("backtest/result_loader.zig");

// v0.6.0 Vectorized backtest modules
pub const vectorized = @import("backtest/vectorized/mod.zig");

// v0.6.0 Exchange adapters
pub const adapters = @import("adapters/mod.zig");

// Optimizer modules
pub const optimizer_types = @import("optimizer/types.zig");
pub const optimizer_combination = @import("optimizer/combination.zig");
pub const optimizer_grid_search = @import("optimizer/grid_search.zig");
pub const optimizer_result = @import("optimizer/result.zig");

// v0.4.0 Walk-Forward optimizer modules
pub const optimizer_data_split = @import("optimizer/data_split.zig");
pub const optimizer_overfitting = @import("optimizer/overfitting_detector.zig");
pub const optimizer_walk_forward = @import("optimizer/walk_forward.zig");

// v0.4.0 Parallel backtest modules
pub const optimizer_thread_pool = @import("optimizer/thread_pool.zig");
pub const optimizer_parallel_executor = @import("optimizer/parallel_executor.zig");

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

// Re-export new v0.4.0 strategies
pub const TripleMAStrategy = strategy_triple_ma.TripleMAStrategy;
pub const MACDDivergenceStrategy = strategy_macd_divergence.MACDDivergenceStrategy;

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

// Re-export new v0.4.0 indicator types
pub const WilliamsR = indicator_williams_r.WilliamsR;
pub const CCI = indicator_cci.CCI;
pub const ROC = indicator_roc.ROC;
pub const ADX = indicator_adx.ADX;
pub const ADXResult = indicator_adx.ADXResult;
pub const OBV = indicator_obv.OBV;
pub const VWAP = indicator_vwap.VWAP;
pub const ParabolicSAR = indicator_parabolic_sar.ParabolicSAR;
pub const Ichimoku = indicator_ichimoku.Ichimoku;
pub const IchimokuResult = indicator_ichimoku.IchimokuResult;

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

// Re-export v0.4.0 backtest export types
pub const Exporter = backtest_export.Exporter;
pub const ExportFormat = backtest_export.ExportFormat;
pub const ExportOptions = backtest_export.ExportOptions;
pub const ExportResult = backtest_export.ExportResult;
pub const JSONExporter = backtest_json_exporter.JSONExporter;
pub const CSVExporter = backtest_csv_exporter.CSVExporter;
pub const ResultLoader = backtest_result_loader.ResultLoader;
pub const LoadedResult = backtest_result_loader.LoadedResult;
pub const ResultComparison = backtest_result_loader.ResultComparison;

// Re-export v0.6.0 vectorized backtest types
pub const VectorizedBacktester = vectorized.VectorizedBacktester;
pub const VecBacktestResult = vectorized.BacktestResult;
pub const VecStrategyConfig = vectorized.StrategyConfig;
pub const VecDataSet = vectorized.DataSet;
pub const VecCandle = vectorized.VecCandle;
pub const VecSignal = vectorized.Signal;
pub const VecSignalDirection = vectorized.SignalDirection;
pub const SimdIndicators = vectorized.SimdIndicators;
pub const MmapDataLoader = vectorized.MmapDataLoader;
pub const BatchSignalGenerator = vectorized.BatchSignalGenerator;
pub const BatchOrderSimulator = vectorized.BatchOrderSimulator;
pub const VecSimulationResult = vectorized.SimulationResult;
pub const VecTrade = vectorized.Trade;
pub const VecPerformanceAnalyzer = vectorized.PerformanceAnalyzer;

// Re-export v0.6.0 adapter types
pub const HyperliquidDataProvider = adapters.HyperliquidDataProvider;
pub const HyperliquidExecutionClient = adapters.HyperliquidExecutionClient;

// Re-export optimizer types
pub const OptimizerParameterType = optimizer_types.ParameterType;
pub const OptimizerParameterValue = optimizer_types.ParameterValue;
pub const OptimizerParameterRange = optimizer_types.ParameterRange;
pub const OptimizerIntegerRange = optimizer_types.IntegerRange;
pub const OptimizerDecimalRange = optimizer_types.DecimalRange;
pub const OptimizerStrategyParameter = optimizer_types.StrategyParameter;
pub const OptimizerParameterSet = optimizer_types.ParameterSet;
pub const OptimizationObjective = optimizer_types.OptimizationObjective;
pub const OptimizationResult = optimizer_types.OptimizationResult;
pub const OptimizationConfig = optimizer_types.OptimizationConfig;
pub const ParameterResult = optimizer_types.ParameterResult;
pub const CombinationGenerator = optimizer_combination.CombinationGenerator;
pub const GridSearchOptimizer = optimizer_grid_search.GridSearchOptimizer;
pub const StrategyFactoryFn = optimizer_grid_search.GridSearchOptimizer.StrategyFactoryFn;
pub const ResultAnalyzer = optimizer_result.ResultAnalyzer;
pub const ScoreStatistics = optimizer_result.ScoreStatistics;

// Re-export v0.4.0 Walk-Forward types
pub const DataSplitter = optimizer_data_split.DataSplitter;
pub const DataWindow = optimizer_data_split.DataWindow;
pub const SplitConfig = optimizer_data_split.SplitConfig;
pub const SplitStrategy = optimizer_data_split.SplitStrategy;
pub const OverfittingDetector = optimizer_overfitting.OverfittingDetector;
pub const OverfittingMetrics = optimizer_overfitting.OverfittingMetrics;
pub const WindowPerformance = optimizer_overfitting.WindowPerformance;
pub const WalkForwardAnalyzer = optimizer_walk_forward.WalkForwardAnalyzer;
pub const WalkForwardConfig = optimizer_walk_forward.WalkForwardConfig;
pub const WalkForwardResult = optimizer_walk_forward.WalkForwardResult;

// Re-export v0.4.0 Parallel backtest types
pub const ParallelExecutor = optimizer_parallel_executor.ParallelExecutor;
pub const ParallelTaskResult = optimizer_parallel_executor.TaskResult;
pub const ParallelConfig = optimizer_parallel_executor.ParallelConfig;

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

// Re-export v0.5.0 MessageBus types
pub const MessageBus = message_bus.MessageBus;
pub const MessageBusError = message_bus.MessageBusError;
pub const MessageBusEvent = message_bus.Event;
pub const MessageBusRequest = message_bus.Request;
pub const MessageBusResponse = message_bus.Response;
pub const MessageBusCommand = message_bus.Command;
// Event types with Bus prefix to avoid conflicts
pub const BusMarketDataEvent = message_bus.MarketDataEvent;
pub const BusOrderbookEvent = message_bus.OrderbookEvent;
pub const BusTradeEvent = message_bus.TradeEvent;
pub const BusCandleEvent = message_bus.CandleEvent;
pub const BusOrderEvent = message_bus.OrderEvent;
pub const BusOrderFillEvent = message_bus.OrderFillEvent;
pub const BusPositionEvent = message_bus.PositionEvent;
pub const BusAccountEvent = message_bus.AccountEvent;
pub const BusTickEvent = message_bus.TickEvent;
pub const BusShutdownEvent = message_bus.ShutdownEvent;

// Re-export v0.5.0 Cache types
pub const Cache = cache.Cache;
pub const CacheError = cache.CacheError;
pub const CacheQuote = cache.Quote;
pub const CacheBar = cache.Bar;
pub const CacheTimeframe = cache.Timeframe;
pub const AccountBalance = cache.AccountBalance;

// Re-export v0.5.0 DataEngine types
pub const DataEngine = data_engine.DataEngine;
pub const DataEngineError = data_engine.DataEngineError;
pub const IDataProvider = data_engine.IDataProvider;
pub const ProviderType = data_engine.ProviderType;
pub const SubscriptionType = data_engine.SubscriptionType;
pub const DataMessage = data_engine.DataMessage;
pub const MockDataProvider = data_engine.MockDataProvider;

// Re-export v0.5.0 ExecutionEngine types
pub const ExecutionEngine = execution_engine.ExecutionEngine;
pub const ExecutionError = execution_engine.ExecutionError;
pub const IExecutionClient = execution_engine.IExecutionClient;
pub const ExecOrderRequest = execution_engine.OrderRequest;
pub const ExecOrderResult = execution_engine.OrderResult;
pub const ExecPositionInfo = execution_engine.PositionInfo;
pub const ExecBalanceInfo = execution_engine.BalanceInfo;
pub const RiskConfig = execution_engine.RiskConfig;
pub const MockExecutionClient = execution_engine.MockExecutionClient;

// Re-export v0.5.0 LiveTradingEngine types
pub const LiveTradingEngine = live_engine.LiveTradingEngine;
pub const LiveConfig = live_engine.LiveConfig;
pub const TradingMode = live_engine.TradingMode;
pub const EngineState = live_engine.EngineState;
pub const ConnectionState = live_engine.ConnectionState;
pub const LiveError = live_engine.LiveError;
// v0.5.0 异步引擎 (libxev)
pub const AsyncLiveTradingEngine = live_engine.AsyncLiveTradingEngine;
pub const AsyncConfig = live_engine.AsyncLiveTradingEngine.AsyncConfig;

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
    _ = message_bus;
    _ = cache;
    _ = data_engine;
    _ = execution_engine;
    _ = live_engine;

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

    // New v0.4.0 strategy modules
    _ = strategy_triple_ma;
    _ = strategy_macd_divergence;

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

    // New v0.4.0 indicator modules
    _ = indicator_williams_r;
    _ = indicator_cci;
    _ = indicator_roc;
    _ = indicator_adx;
    _ = indicator_obv;
    _ = indicator_vwap;
    _ = indicator_parabolic_sar;
    _ = indicator_ichimoku;

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

    // v0.4.0 Backtest export modules
    _ = backtest_export;
    _ = backtest_json_exporter;
    _ = backtest_csv_exporter;
    _ = backtest_result_loader;

    // v0.6.0 Vectorized backtest modules
    _ = vectorized;

    // v0.6.0 Exchange adapters
    _ = adapters;

    // Optimizer modules
    _ = optimizer_types;
    _ = optimizer_combination;
    _ = optimizer_grid_search;
    _ = optimizer_result;

    // v0.4.0 Walk-Forward optimizer modules
    _ = optimizer_data_split;
    _ = optimizer_overfitting;
    _ = optimizer_walk_forward;

    // v0.4.0 Parallel backtest modules
    _ = optimizer_thread_pool;
    _ = optimizer_parallel_executor;
}
