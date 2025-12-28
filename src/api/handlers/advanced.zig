//! Advanced API Handlers
//!
//! Handlers for advanced features:
//! - Backtest execution and results
//! - Technical indicators
//! - Risk metrics (VaR, Drawdown, Sharpe)
//! - Alert management
//! - Strategy configuration

const std = @import("std");
const zigQuant = @import("zigQuant");

// Types
const Decimal = zigQuant.Decimal;
const TradingPair = zigQuant.TradingPair;
const Timeframe = zigQuant.Timeframe;
const Timestamp = zigQuant.Timestamp;

// Strategy
const StrategyFactory = zigQuant.StrategyFactory;

// Backtest
const BacktestEngine = zigQuant.BacktestEngine;
const BacktestConfig = zigQuant.BacktestConfig;
const PerformanceAnalyzer = zigQuant.PerformanceAnalyzer;

// Risk
const RiskMetricsMonitor = zigQuant.RiskMetricsMonitor;
const AlertManager = zigQuant.AlertManager;

// Indicators
const IndicatorManager = zigQuant.IndicatorManager;

// ============================================================================
// Strategy Handlers
// ============================================================================

/// Strategy info with parameters
pub const StrategyDetailInfo = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    strategy_type: []const u8,
    parameters: []const ParameterInfo,
};

pub const ParameterInfo = struct {
    name: []const u8,
    param_type: []const u8,
    default_value: []const u8,
    min_value: ?[]const u8 = null,
    max_value: ?[]const u8 = null,
    description: []const u8,
};

/// Get detailed strategy parameters
pub fn getStrategyParams(
    allocator: std.mem.Allocator,
    strategy_id: []const u8,
) !StrategyDetailInfo {
    // Built-in strategy definitions
    if (std.mem.eql(u8, strategy_id, "dual_ma")) {
        return StrategyDetailInfo{
            .id = "dual_ma",
            .name = "Dual Moving Average",
            .description = "Trend following strategy using fast/slow MA crossovers",
            .strategy_type = "trend_following",
            .parameters = &[_]ParameterInfo{
                .{
                    .name = "fast_period",
                    .param_type = "integer",
                    .default_value = "10",
                    .min_value = "2",
                    .max_value = "50",
                    .description = "Fast moving average period",
                },
                .{
                    .name = "slow_period",
                    .param_type = "integer",
                    .default_value = "20",
                    .min_value = "5",
                    .max_value = "200",
                    .description = "Slow moving average period",
                },
                .{
                    .name = "ma_type",
                    .param_type = "string",
                    .default_value = "sma",
                    .description = "Moving average type: sma or ema",
                },
            },
        };
    } else if (std.mem.eql(u8, strategy_id, "rsi_mean_reversion")) {
        return StrategyDetailInfo{
            .id = "rsi_mean_reversion",
            .name = "RSI Mean Reversion",
            .description = "Mean reversion strategy using RSI oversold/overbought levels",
            .strategy_type = "mean_reversion",
            .parameters = &[_]ParameterInfo{
                .{
                    .name = "rsi_period",
                    .param_type = "integer",
                    .default_value = "14",
                    .min_value = "2",
                    .max_value = "50",
                    .description = "RSI calculation period",
                },
                .{
                    .name = "oversold_threshold",
                    .param_type = "integer",
                    .default_value = "30",
                    .min_value = "10",
                    .max_value = "40",
                    .description = "Oversold level for buy signals",
                },
                .{
                    .name = "overbought_threshold",
                    .param_type = "integer",
                    .default_value = "70",
                    .min_value = "60",
                    .max_value = "90",
                    .description = "Overbought level for sell signals",
                },
            },
        };
    } else if (std.mem.eql(u8, strategy_id, "bollinger_breakout")) {
        return StrategyDetailInfo{
            .id = "bollinger_breakout",
            .name = "Bollinger Breakout",
            .description = "Breakout strategy using Bollinger Bands volatility",
            .strategy_type = "breakout",
            .parameters = &[_]ParameterInfo{
                .{
                    .name = "bb_period",
                    .param_type = "integer",
                    .default_value = "20",
                    .min_value = "5",
                    .max_value = "100",
                    .description = "Bollinger Bands period",
                },
                .{
                    .name = "bb_std_dev",
                    .param_type = "decimal",
                    .default_value = "2.0",
                    .min_value = "0.5",
                    .max_value = "4.0",
                    .description = "Standard deviation multiplier",
                },
            },
        };
    } else if (std.mem.eql(u8, strategy_id, "triple_ma")) {
        return StrategyDetailInfo{
            .id = "triple_ma",
            .name = "Triple Moving Average",
            .description = "Advanced trend strategy using three moving averages",
            .strategy_type = "trend_following",
            .parameters = &[_]ParameterInfo{
                .{
                    .name = "fast_period",
                    .param_type = "integer",
                    .default_value = "5",
                    .description = "Fast MA period",
                },
                .{
                    .name = "medium_period",
                    .param_type = "integer",
                    .default_value = "10",
                    .description = "Medium MA period",
                },
                .{
                    .name = "slow_period",
                    .param_type = "integer",
                    .default_value = "20",
                    .description = "Slow MA period",
                },
            },
        };
    } else if (std.mem.eql(u8, strategy_id, "macd_divergence")) {
        return StrategyDetailInfo{
            .id = "macd_divergence",
            .name = "MACD Divergence",
            .description = "Divergence-based strategy using MACD indicator",
            .strategy_type = "trend_following",
            .parameters = &[_]ParameterInfo{
                .{
                    .name = "fast_period",
                    .param_type = "integer",
                    .default_value = "12",
                    .description = "MACD fast period",
                },
                .{
                    .name = "slow_period",
                    .param_type = "integer",
                    .default_value = "26",
                    .description = "MACD slow period",
                },
                .{
                    .name = "signal_period",
                    .param_type = "integer",
                    .default_value = "9",
                    .description = "Signal line period",
                },
            },
        };
    } else if (std.mem.eql(u8, strategy_id, "hybrid_ai")) {
        return StrategyDetailInfo{
            .id = "hybrid_ai",
            .name = "Hybrid AI Strategy",
            .description = "Combines technical indicators with LLM analysis",
            .strategy_type = "ai_hybrid",
            .parameters = &[_]ParameterInfo{
                .{
                    .name = "ai_provider",
                    .param_type = "string",
                    .default_value = "openai",
                    .description = "AI provider: openai or anthropic",
                },
                .{
                    .name = "confidence_threshold",
                    .param_type = "decimal",
                    .default_value = "0.7",
                    .min_value = "0.5",
                    .max_value = "0.95",
                    .description = "Minimum confidence for signals",
                },
            },
        };
    }

    _ = allocator;
    return error.StrategyNotFound;
}

// ============================================================================
// Indicator Handlers
// ============================================================================

/// Available indicator info
pub const IndicatorInfo = struct {
    name: []const u8,
    description: []const u8,
    category: []const u8,
    parameters: []const IndicatorParamInfo,
    output_type: []const u8,
};

pub const IndicatorParamInfo = struct {
    name: []const u8,
    param_type: []const u8,
    default_value: []const u8,
    description: []const u8,
};

/// Get list of all available indicators
pub fn getIndicatorList() []const IndicatorInfo {
    return &[_]IndicatorInfo{
        .{
            .name = "sma",
            .description = "Simple Moving Average",
            .category = "trend",
            .parameters = &[_]IndicatorParamInfo{
                .{ .name = "period", .param_type = "integer", .default_value = "20", .description = "Number of periods" },
            },
            .output_type = "single",
        },
        .{
            .name = "ema",
            .description = "Exponential Moving Average",
            .category = "trend",
            .parameters = &[_]IndicatorParamInfo{
                .{ .name = "period", .param_type = "integer", .default_value = "20", .description = "Number of periods" },
            },
            .output_type = "single",
        },
        .{
            .name = "rsi",
            .description = "Relative Strength Index",
            .category = "momentum",
            .parameters = &[_]IndicatorParamInfo{
                .{ .name = "period", .param_type = "integer", .default_value = "14", .description = "RSI period" },
            },
            .output_type = "single",
        },
        .{
            .name = "macd",
            .description = "Moving Average Convergence Divergence",
            .category = "momentum",
            .parameters = &[_]IndicatorParamInfo{
                .{ .name = "fast_period", .param_type = "integer", .default_value = "12", .description = "Fast EMA period" },
                .{ .name = "slow_period", .param_type = "integer", .default_value = "26", .description = "Slow EMA period" },
                .{ .name = "signal_period", .param_type = "integer", .default_value = "9", .description = "Signal line period" },
            },
            .output_type = "macd",
        },
        .{
            .name = "bollinger",
            .description = "Bollinger Bands",
            .category = "volatility",
            .parameters = &[_]IndicatorParamInfo{
                .{ .name = "period", .param_type = "integer", .default_value = "20", .description = "MA period" },
                .{ .name = "std_dev", .param_type = "decimal", .default_value = "2.0", .description = "Standard deviation multiplier" },
            },
            .output_type = "bollinger",
        },
        .{
            .name = "atr",
            .description = "Average True Range",
            .category = "volatility",
            .parameters = &[_]IndicatorParamInfo{
                .{ .name = "period", .param_type = "integer", .default_value = "14", .description = "ATR period" },
            },
            .output_type = "single",
        },
        .{
            .name = "adx",
            .description = "Average Directional Index",
            .category = "trend",
            .parameters = &[_]IndicatorParamInfo{
                .{ .name = "period", .param_type = "integer", .default_value = "14", .description = "ADX period" },
            },
            .output_type = "single",
        },
        .{
            .name = "cci",
            .description = "Commodity Channel Index",
            .category = "momentum",
            .parameters = &[_]IndicatorParamInfo{
                .{ .name = "period", .param_type = "integer", .default_value = "20", .description = "CCI period" },
            },
            .output_type = "single",
        },
        .{
            .name = "williams_r",
            .description = "Williams %R",
            .category = "momentum",
            .parameters = &[_]IndicatorParamInfo{
                .{ .name = "period", .param_type = "integer", .default_value = "14", .description = "Lookback period" },
            },
            .output_type = "single",
        },
        .{
            .name = "obv",
            .description = "On-Balance Volume",
            .category = "volume",
            .parameters = &[_]IndicatorParamInfo{},
            .output_type = "single",
        },
        .{
            .name = "vwap",
            .description = "Volume Weighted Average Price",
            .category = "volume",
            .parameters = &[_]IndicatorParamInfo{},
            .output_type = "single",
        },
        .{
            .name = "parabolic_sar",
            .description = "Parabolic Stop and Reverse",
            .category = "trend",
            .parameters = &[_]IndicatorParamInfo{
                .{ .name = "af_start", .param_type = "decimal", .default_value = "0.02", .description = "Initial acceleration factor" },
                .{ .name = "af_max", .param_type = "decimal", .default_value = "0.2", .description = "Maximum acceleration factor" },
            },
            .output_type = "single",
        },
    };
}

// ============================================================================
// Risk Metrics Response Types
// ============================================================================

pub const VaRResponse = struct {
    var_amount: f64,
    var_percentage: f64,
    confidence: f64,
    observations: usize,
    method: []const u8 = "historical_simulation",
};

pub const DrawdownResponse = struct {
    current_drawdown: f64,
    max_drawdown: f64,
    max_drawdown_duration_days: u32,
    peak_equity: f64,
    trough_equity: f64,
};

pub const SharpeResponse = struct {
    sharpe_ratio: f64,
    annualized_return: f64,
    volatility: f64,
    risk_free_rate: f64,
};

pub const SortinoResponse = struct {
    sortino_ratio: f64,
    downside_deviation: f64,
    annualized_return: f64,
};

pub const RiskReportResponse = struct {
    timestamp: i64,
    var_95: VaRResponse,
    var_99: VaRResponse,
    drawdown: DrawdownResponse,
    sharpe: SharpeResponse,
    sortino: SortinoResponse,
    calmar_ratio: f64,
    risk_score: f64, // 0-100
};

// ============================================================================
// Alert Response Types
// ============================================================================

pub const AlertResponse = struct {
    id: []const u8,
    level: []const u8,
    category: []const u8,
    message: []const u8,
    timestamp: i64,
    acknowledged: bool,
};

pub const AlertStatsResponse = struct {
    total_alerts: u64,
    critical_count: u64,
    warning_count: u64,
    info_count: u64,
    last_alert_time: ?i64,
};

// ============================================================================
// Backtest Response Types
// ============================================================================

pub const BacktestStatusResponse = struct {
    id: []const u8,
    status: []const u8, // pending, running, completed, failed
    progress: f64, // 0-100
    started_at: ?i64,
    completed_at: ?i64,
    error_message: ?[]const u8,
};

pub const BacktestResultResponse = struct {
    id: []const u8,
    strategy_id: []const u8,
    pair: []const u8,
    timeframe: []const u8,
    start_date: []const u8,
    end_date: []const u8,
    initial_capital: f64,
    final_capital: f64,
    metrics: BacktestMetricsResponse,
    trade_count: u32,
};

pub const BacktestMetricsResponse = struct {
    // Returns
    total_return: f64,
    total_return_pct: f64,
    annualized_return: f64,

    // Risk
    max_drawdown: f64,
    max_drawdown_pct: f64,
    sharpe_ratio: f64,
    sortino_ratio: f64,

    // Trading
    total_trades: u32,
    winning_trades: u32,
    losing_trades: u32,
    win_rate: f64,
    profit_factor: f64,

    // Additional
    avg_trade_return: f64,
    max_consecutive_wins: u32,
    max_consecutive_losses: u32,
    avg_hold_time_hours: f64,
};

pub const TradeResponse = struct {
    id: u64,
    pair: []const u8,
    side: []const u8,
    entry_time: i64,
    exit_time: i64,
    entry_price: f64,
    exit_price: f64,
    size: f64,
    pnl: f64,
    pnl_percent: f64,
    commission: f64,
};

pub const EquityPointResponse = struct {
    timestamp: i64,
    equity: f64,
    drawdown: f64,
};
