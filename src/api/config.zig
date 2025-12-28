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
// Additional types for order creation
pub const Side = zigQuant.Side;
pub const OrderType = zigQuant.OrderType;
pub const TradingPair = zigQuant.TradingPair;
pub const Decimal = zigQuant.Decimal;
pub const OrderRequest = zigQuant.OrderRequest;

// Risk and Alert types
pub const RiskMetricsMonitor = zigQuant.RiskMetricsMonitor;
pub const RiskMetricsConfig = zigQuant.RiskMetricsConfig;
pub const AlertManager = zigQuant.AlertManager;
pub const AlertConfig = zigQuant.AlertConfig;
pub const Alert = zigQuant.Alert;

// Paper Trading
pub const PaperTradingEngine = zigQuant.PaperTradingEngine;
pub const PaperTradingConfig = zigQuant.PaperTradingConfig;

// Backtest
pub const ResultLoader = zigQuant.ResultLoader;
pub const Candle = zigQuant.Candle;
pub const CandleCache = zigQuant.CandleCache;

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

/// Exchange entry with interface and configuration
pub const ExchangeEntry = struct {
    interface: IExchange,
    config: ExchangeConfig,
};

/// Dependencies for the API server - supports multiple exchanges
pub const ApiDependencies = struct {
    /// Multiple exchanges indexed by name (e.g., "hyperliquid", "binance")
    exchanges: std.StringHashMap(ExchangeEntry),

    /// Allocator for managing exchange map
    allocator: std.mem.Allocator,

    /// Backtest results directory
    backtest_results_dir: []const u8 = "backtest_results",

    /// Risk metrics monitor (optional)
    risk_monitor: ?*RiskMetricsMonitor = null,

    /// Alert manager (optional)
    alert_manager: ?*AlertManager = null,

    /// Paper trading sessions (by session ID)
    paper_sessions: std.AutoHashMap(i64, *PaperTradingEngine),

    /// Backtest result loader (optional)
    backtest_loader: ?*ResultLoader = null,

    /// Candle cache for market data (optional)
    candle_cache: ?*CandleCache = null,

    /// Initialize dependencies
    pub fn init(allocator: std.mem.Allocator) ApiDependencies {
        return .{
            .exchanges = std.StringHashMap(ExchangeEntry).init(allocator),
            .allocator = allocator,
            .backtest_results_dir = "backtest_results",
            .risk_monitor = null,
            .alert_manager = null,
            .paper_sessions = std.AutoHashMap(i64, *PaperTradingEngine).init(allocator),
            .backtest_loader = null,
            .candle_cache = null,
        };
    }

    /// Deinitialize dependencies
    pub fn deinit(self: *ApiDependencies) void {
        self.exchanges.deinit();
        self.paper_sessions.deinit();
    }

    /// Set risk metrics monitor
    pub fn setRiskMonitor(self: *ApiDependencies, monitor: *RiskMetricsMonitor) void {
        self.risk_monitor = monitor;
    }

    /// Set alert manager
    pub fn setAlertManager(self: *ApiDependencies, manager: *AlertManager) void {
        self.alert_manager = manager;
    }

    /// Set backtest result loader
    pub fn setBacktestLoader(self: *ApiDependencies, loader: *ResultLoader) void {
        self.backtest_loader = loader;
    }

    /// Set candle cache
    pub fn setCandleCache(self: *ApiDependencies, cache: *CandleCache) void {
        self.candle_cache = cache;
    }

    /// Add paper trading session
    pub fn addPaperSession(self: *ApiDependencies, session_id: i64, engine: *PaperTradingEngine) !void {
        try self.paper_sessions.put(session_id, engine);
    }

    /// Get paper trading session
    pub fn getPaperSession(self: *const ApiDependencies, session_id: i64) ?*PaperTradingEngine {
        return self.paper_sessions.get(session_id);
    }

    /// Remove paper trading session
    pub fn removePaperSession(self: *ApiDependencies, session_id: i64) void {
        _ = self.paper_sessions.remove(session_id);
    }

    /// Add an exchange
    pub fn addExchange(self: *ApiDependencies, name: []const u8, interface: IExchange, config: ExchangeConfig) !void {
        try self.exchanges.put(name, .{
            .interface = interface,
            .config = config,
        });
    }

    /// Get an exchange by name
    pub fn getExchange(self: *const ApiDependencies, name: []const u8) ?ExchangeEntry {
        return self.exchanges.get(name);
    }

    /// Check if any exchange is configured
    pub fn hasExchanges(self: *const ApiDependencies) bool {
        return self.exchanges.count() > 0;
    }

    /// Get number of configured exchanges
    pub fn exchangeCount(self: *const ApiDependencies) usize {
        return self.exchanges.count();
    }

    /// Get all exchange names
    pub fn getExchangeNames(self: *const ApiDependencies, allocator: std.mem.Allocator) ![]const []const u8 {
        var names = std.ArrayList([]const u8).init(allocator);
        errdefer names.deinit();

        var iter = self.exchanges.keyIterator();
        while (iter.next()) |key| {
            try names.append(key.*);
        }

        return names.toOwnedSlice();
    }

    /// Iterate over all exchanges
    pub fn iterator(self: *const ApiDependencies) std.StringHashMap(ExchangeEntry).Iterator {
        return self.exchanges.iterator();
    }

    // Legacy compatibility - get first exchange (deprecated)
    pub fn isExchangeConfigured(self: *const ApiDependencies) bool {
        return self.hasExchanges();
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
