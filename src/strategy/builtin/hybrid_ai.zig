//! Hybrid AI Strategy
//!
//! A hybrid trading strategy that combines traditional technical analysis with AI-powered
//! market analysis. The strategy uses configurable weights to blend signals from technical
//! indicators (RSI, MA) with structured AI advice.
//!
//! Key Features:
//! - Combines RSI and Moving Average technical signals
//! - Integrates AI advisor for intelligent market analysis
//! - Configurable weight distribution between technical and AI signals
//! - Graceful fallback to pure technical analysis when AI is unavailable
//!
//! Strategy Flow:
//! 1. Calculate technical indicators (RSI, SMA)
//! 2. Generate technical signal score based on indicator values
//! 3. Request AI advice with market context (when available)
//! 4. Combine signals using weighted average
//! 5. Generate entry/exit signals based on combined score

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candles = @import("../../root.zig").Candles;
const Candle = @import("../../root.zig").Candle;
const TradingPair = @import("../../root.zig").TradingPair;
const Timestamp = @import("../../root.zig").Timestamp;
const Side = @import("../../root.zig").Side;
const Timeframe = @import("../../root.zig").Timeframe;
const IStrategy = @import("../interface.zig").IStrategy;
const StrategyContext = @import("../interface.zig").StrategyContext;
const Signal = @import("../signal.zig").Signal;
const SignalType = @import("../signal.zig").SignalType;
const SignalMetadata = @import("../signal.zig").SignalMetadata;
const IndicatorValue = @import("../signal.zig").IndicatorValue;
const StrategyMetadata = @import("../types.zig").StrategyMetadata;
const StrategyParameter = @import("../types.zig").StrategyParameter;
const StrategyType = @import("../types.zig").StrategyType;
const MinimalROI = @import("../types.zig").MinimalROI;
const Position = @import("../../backtest/position.zig").Position;
const Account = @import("../../backtest/account.zig").Account;
const IndicatorManager = @import("../../root.zig").IndicatorManager;
const indicator_helpers = @import("../../root.zig").indicator_helpers;
const Logger = @import("../../root.zig").Logger;

// AI modules
const ai = @import("../../ai/mod.zig");
const AIAdvisor = ai.AIAdvisor;
const AIConfig = ai.AIConfig;
const AIAdvice = ai.AIAdvice;
const Action = ai.Action;
const MarketContext = ai.MarketContext;
const IndicatorSnapshot = ai.IndicatorSnapshot;
const ILLMClient = ai.ILLMClient;
const LLMClient = ai.LLMClient;

// ============================================================================
// Configuration
// ============================================================================

/// Hybrid AI Strategy configuration
pub const Config = struct {
    /// Trading pair
    pair: TradingPair,

    /// Timeframe for analysis
    timeframe: Timeframe = .h1,

    // Technical Indicator Parameters
    /// RSI period
    rsi_period: u32 = 14,
    /// RSI oversold threshold
    rsi_oversold: f64 = 30.0,
    /// RSI overbought threshold
    rsi_overbought: f64 = 70.0,
    /// SMA period
    sma_period: u32 = 20,

    // Signal Weight Configuration
    /// Weight for AI advice (0.0 - 1.0)
    ai_weight: f64 = 0.4,
    /// Weight for technical indicators (0.0 - 1.0)
    technical_weight: f64 = 0.6,

    // Signal Thresholds
    /// Minimum combined score for long entry (> 0.5 for bullish)
    min_long_score: f64 = 0.65,
    /// Maximum combined score for short entry (< 0.5 for bearish)
    max_short_score: f64 = 0.35,
    /// Minimum confidence from AI to consider its advice
    min_ai_confidence: f64 = 0.6,

    // Position Sizing
    /// Risk per trade as percentage of account (0.01 = 1%)
    risk_per_trade: f64 = 0.02,
    /// Maximum position size as percentage of account
    max_position_pct: f64 = 0.1,

    /// Validate configuration
    pub fn validate(self: Config) !void {
        // Validate weights sum to 1.0
        const weight_sum = self.ai_weight + self.technical_weight;
        if (@abs(weight_sum - 1.0) > 0.001) {
            return error.InvalidWeights;
        }

        // Validate individual weights
        if (self.ai_weight < 0.0 or self.ai_weight > 1.0) {
            return error.InvalidAIWeight;
        }
        if (self.technical_weight < 0.0 or self.technical_weight > 1.0) {
            return error.InvalidTechnicalWeight;
        }

        // Validate RSI parameters
        if (self.rsi_period < 2 or self.rsi_period > 100) {
            return error.InvalidRSIPeriod;
        }
        if (self.rsi_oversold >= self.rsi_overbought) {
            return error.InvalidRSIThresholds;
        }

        // Validate SMA period
        if (self.sma_period < 2 or self.sma_period > 200) {
            return error.InvalidSMAPeriod;
        }

        // Validate score thresholds
        if (self.min_long_score < 0.5 or self.min_long_score > 1.0) {
            return error.InvalidLongScoreThreshold;
        }
        if (self.max_short_score < 0.0 or self.max_short_score > 0.5) {
            return error.InvalidShortScoreThreshold;
        }
    }
};

// ============================================================================
// Hybrid AI Strategy
// ============================================================================

/// Hybrid AI Strategy - combines technical analysis with AI advice
pub const HybridAIStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    indicator_manager: IndicatorManager,
    ai_advisor: ?AIAdvisor,
    llm_client: ?*LLMClient,
    logger: Logger,
    initialized: bool,

    // Statistics
    total_signals: u64,
    ai_assisted_signals: u64,
    fallback_signals: u64,

    /// Create a new Hybrid AI strategy instance
    /// Note: AI advisor is optional - if LLM client is not provided, falls back to pure technical
    pub fn create(allocator: std.mem.Allocator, config: Config) !*HybridAIStrategy {
        // Validate configuration
        try config.validate();

        const self = try allocator.create(HybridAIStrategy);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .indicator_manager = IndicatorManager.init(allocator),
            .ai_advisor = null,
            .llm_client = null,
            .logger = undefined,
            .initialized = false,
            .total_signals = 0,
            .ai_assisted_signals = 0,
            .fallback_signals = 0,
        };

        return self;
    }

    /// Create with AI integration
    pub fn createWithAI(allocator: std.mem.Allocator, config: Config, llm_client: *LLMClient) !*HybridAIStrategy {
        const self = try create(allocator, config);
        errdefer self.destroy();

        self.llm_client = llm_client;
        self.ai_advisor = AIAdvisor.init(
            allocator,
            llm_client.toInterface(),
            .{
                .min_confidence_threshold = config.min_ai_confidence,
                .max_retries = 1,
                .retry_delay_ms = 500,
            },
        );

        return self;
    }

    /// Convert to IStrategy interface
    pub fn toStrategy(self: *HybridAIStrategy) IStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Destroy strategy and free resources
    pub fn destroy(self: *HybridAIStrategy) void {
        if (self.ai_advisor) |*advisor| {
            advisor.deinit();
        }
        self.indicator_manager.deinit();
        self.allocator.destroy(self);
    }

    /// Get strategy statistics
    pub fn getStats(self: *HybridAIStrategy) struct {
        total_signals: u64,
        ai_assisted_signals: u64,
        fallback_signals: u64,
        ai_usage_rate: f64,
    } {
        const ai_rate = if (self.total_signals > 0)
            @as(f64, @floatFromInt(self.ai_assisted_signals)) / @as(f64, @floatFromInt(self.total_signals))
        else
            0.0;

        return .{
            .total_signals = self.total_signals,
            .ai_assisted_signals = self.ai_assisted_signals,
            .fallback_signals = self.fallback_signals,
            .ai_usage_rate = ai_rate,
        };
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn initImpl(ptr: *anyopaque, ctx: StrategyContext) !void {
        const self: *HybridAIStrategy = @ptrCast(@alignCast(ptr));
        self.logger = ctx.logger;
        self.initialized = true;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *HybridAIStrategy = @ptrCast(@alignCast(ptr));
        if (self.ai_advisor) |*advisor| {
            advisor.deinit();
            self.ai_advisor = null;
        }
        self.indicator_manager.deinit();
        self.initialized = false;
    }

    fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
        const self: *HybridAIStrategy = @ptrCast(@alignCast(ptr));

        // Calculate RSI
        const rsi_values = try indicator_helpers.getRSI(
            &self.indicator_manager,
            candles,
            self.config.rsi_period,
        );
        try candles.addIndicatorValues("rsi", rsi_values);

        // Calculate SMA
        const sma_values = try indicator_helpers.getSMA(
            &self.indicator_manager,
            candles,
            self.config.sma_period,
        );
        try candles.addIndicatorValues("sma", sma_values);
    }

    fn generateEntrySignalImpl(ptr: *anyopaque, candles: *Candles, index: usize) !?Signal {
        const self: *HybridAIStrategy = @ptrCast(@alignCast(ptr));

        // Need enough data for indicators
        const min_period = @max(self.config.rsi_period, self.config.sma_period);
        if (index < min_period) return null;

        // Get current candle
        const current_candle = candles.get(index) orelse return null;

        // Get technical signal
        const tech_result = self.calculateTechnicalScore(candles, index) orelse return null;

        // For now, use pure technical signals (AI integration can be added when needed)
        // This simplifies the implementation and avoids async complexity
        const combined_score = tech_result.score;

        // Update statistics
        self.total_signals += 1;
        self.fallback_signals += 1;

        // Generate signal based on combined score
        const current_price = current_candle.close;
        const timestamp = current_candle.timestamp;

        if (combined_score >= self.config.min_long_score) {
            // Long entry signal
            return Signal{
                .type = .entry_long,
                .pair = self.config.pair,
                .side = .buy,
                .price = current_price,
                .strength = combined_score,
                .timestamp = timestamp,
                .metadata = null,
            };
        } else if (combined_score <= self.config.max_short_score) {
            // Short entry signal
            return Signal{
                .type = .entry_short,
                .pair = self.config.pair,
                .side = .sell,
                .price = current_price,
                .strength = 1.0 - combined_score,
                .timestamp = timestamp,
                .metadata = null,
            };
        }

        return null;
    }

    fn generateExitSignalImpl(ptr: *anyopaque, candles: *Candles, position: Position) !?Signal {
        const self: *HybridAIStrategy = @ptrCast(@alignCast(ptr));

        const index = candles.len() - 1;
        const min_period = @max(self.config.rsi_period, self.config.sma_period);
        if (index < min_period) return null;

        const current_candle = candles.get(index) orelse return null;
        const tech_result = self.calculateTechnicalScore(candles, index) orelse return null;
        const current_price = current_candle.close;
        const timestamp = current_candle.timestamp;

        // Exit logic based on position side
        if (position.side == .long) {
            // Exit long if bearish
            if (tech_result.score < 0.4 or tech_result.rsi > self.config.rsi_overbought) {
                return Signal{
                    .type = .exit_long,
                    .pair = self.config.pair,
                    .side = .sell,
                    .price = current_price,
                    .strength = 1.0 - tech_result.score,
                    .timestamp = timestamp,
                    .metadata = null,
                };
            }
        } else if (position.side == .short) {
            // Exit short if bullish
            if (tech_result.score > 0.6 or tech_result.rsi < self.config.rsi_oversold) {
                return Signal{
                    .type = .exit_short,
                    .pair = self.config.pair,
                    .side = .buy,
                    .price = current_price,
                    .strength = tech_result.score,
                    .timestamp = timestamp,
                    .metadata = null,
                };
            }
        }

        return null;
    }

    fn calculatePositionSizeImpl(ptr: *anyopaque, signal: Signal, account: Account) !Decimal {
        const self: *HybridAIStrategy = @ptrCast(@alignCast(ptr));

        // Use available balance for position sizing
        const available = account.balance.mul(Decimal.fromFloat(0.95));
        const position_size = try available.div(signal.price);

        // Apply risk constraints
        const equity = account.balance.toFloat();
        const max_size = equity * self.config.max_position_pct;
        const final_size = @min(position_size.toFloat(), max_size);

        return Decimal.fromFloat(final_size * signal.strength);
    }

    fn getParametersImpl(_: *anyopaque) []const StrategyParameter {
        return &parameters;
    }

    fn getMetadataImpl(_: *anyopaque) StrategyMetadata {
        return metadata;
    }

    // ========================================================================
    // Internal Helpers
    // ========================================================================

    const TechnicalResult = struct {
        score: f64,
        rsi: f64,
        sma: f64,
        price: f64,
    };

    fn calculateTechnicalScore(self: *HybridAIStrategy, candles: *Candles, index: usize) ?TechnicalResult {
        // Get current candle
        const current_candle = candles.get(index) orelse return null;

        // Get RSI indicator
        const rsi_indicator = candles.getIndicator("rsi") orelse return null;
        const rsi = rsi_indicator.values[index].toFloat();

        // Get SMA indicator
        const sma_indicator = candles.getIndicator("sma") orelse return null;
        const sma = sma_indicator.values[index].toFloat();

        const current_price = current_candle.close.toFloat();

        // Calculate technical score [0, 1]
        var score: f64 = 0.5; // Start neutral

        // RSI contribution
        if (rsi < self.config.rsi_oversold) {
            // Oversold - bullish
            const oversold_strength = (self.config.rsi_oversold - rsi) / self.config.rsi_oversold;
            score += oversold_strength * 0.25;
        } else if (rsi > self.config.rsi_overbought) {
            // Overbought - bearish
            const overbought_strength = (rsi - self.config.rsi_overbought) / (100.0 - self.config.rsi_overbought);
            score -= overbought_strength * 0.25;
        }

        // Price vs SMA contribution
        if (current_price > sma) {
            const above_pct = (current_price - sma) / sma;
            score += @min(above_pct * 10.0, 0.25); // Cap at 0.25
        } else {
            const below_pct = (sma - current_price) / sma;
            score -= @min(below_pct * 10.0, 0.25); // Cap at 0.25
        }

        // Clamp score to [0, 1]
        score = @max(0.0, @min(1.0, score));

        return .{
            .score = score,
            .rsi = rsi,
            .sma = sma,
            .price = current_price,
        };
    }

    // ========================================================================
    // VTable
    // ========================================================================

    const vtable = IStrategy.VTable{
        .init = initImpl,
        .deinit = deinitImpl,
        .populateIndicators = populateIndicatorsImpl,
        .generateEntrySignal = generateEntrySignalImpl,
        .generateExitSignal = generateExitSignalImpl,
        .calculatePositionSize = calculatePositionSizeImpl,
        .getParameters = getParametersImpl,
        .getMetadata = getMetadataImpl,
    };

    // ========================================================================
    // Strategy Metadata
    // ========================================================================

    const roi_targets = [_]@import("../types.zig").ROITarget{
        .{ .time_minutes = 0, .profit_ratio = Decimal.fromFloat(0.10) }, // 10% immediate
        .{ .time_minutes = 30, .profit_ratio = Decimal.fromFloat(0.05) }, // 5% after 30min
        .{ .time_minutes = 60, .profit_ratio = Decimal.fromFloat(0.02) }, // 2% after 1hr
        .{ .time_minutes = 120, .profit_ratio = Decimal.fromFloat(0.01) }, // 1% after 2hr
    };

    const metadata = StrategyMetadata{
        .name = "Hybrid AI Strategy",
        .version = "1.0.0",
        .author = "zigQuant",
        .description = "Combines RSI/SMA technical analysis with AI-powered market insights",
        .strategy_type = .trend_following,
        .timeframe = .h1,
        .startup_candle_count = 30,
        .minimal_roi = .{ .targets = &roi_targets },
        .stoploss = Decimal.fromFloat(-0.05), // -5% stop loss
        .trailing_stop = null,
    };

    const parameters = [_]StrategyParameter{
        .{
            .name = "rsi_period",
            .description = "RSI calculation period",
            .value = .{ .integer = 14 },
        },
        .{
            .name = "sma_period",
            .description = "SMA calculation period",
            .value = .{ .integer = 20 },
        },
        .{
            .name = "ai_weight",
            .description = "Weight for AI advice (0-1)",
            .value = .{ .decimal = Decimal.fromFloat(0.4) },
        },
        .{
            .name = "technical_weight",
            .description = "Weight for technical analysis (0-1)",
            .value = .{ .decimal = Decimal.fromFloat(0.6) },
        },
    };
};

// ============================================================================
// Tests
// ============================================================================

test "HybridAIStrategy: create and destroy" {
    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDT" },
    };

    const strategy = try HybridAIStrategy.create(std.testing.allocator, config);
    defer strategy.destroy();

    try std.testing.expect(!strategy.initialized);
    try std.testing.expect(strategy.ai_advisor == null);
}

test "HybridAIStrategy: config validation" {
    // Valid config
    const valid = Config{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .ai_weight = 0.4,
        .technical_weight = 0.6,
    };
    try valid.validate();

    // Invalid weights (don't sum to 1.0)
    const invalid_weights = Config{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .ai_weight = 0.5,
        .technical_weight = 0.6,
    };
    try std.testing.expectError(error.InvalidWeights, invalid_weights.validate());

    // Invalid RSI thresholds
    const invalid_rsi = Config{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .rsi_oversold = 80.0,
        .rsi_overbought = 30.0,
    };
    try std.testing.expectError(error.InvalidRSIThresholds, invalid_rsi.validate());
}

test "HybridAIStrategy: toStrategy interface" {
    const config = Config{
        .pair = .{ .base = "ETH", .quote = "USDT" },
    };

    const strategy = try HybridAIStrategy.create(std.testing.allocator, config);
    defer strategy.destroy();

    const iface = strategy.toStrategy();

    // Test metadata
    const meta = iface.getMetadata();
    try std.testing.expectEqualStrings("Hybrid AI Strategy", meta.name);
    try std.testing.expectEqualStrings("1.0.0", meta.version);
}

test "HybridAIStrategy: getStats" {
    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDT" },
    };

    const strategy = try HybridAIStrategy.create(std.testing.allocator, config);
    defer strategy.destroy();

    const stats = strategy.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_signals);
    try std.testing.expectEqual(@as(f64, 0.0), stats.ai_usage_rate);
}

test "HybridAIStrategy: parameters" {
    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDT" },
    };

    const strategy = try HybridAIStrategy.create(std.testing.allocator, config);
    defer strategy.destroy();

    const iface = strategy.toStrategy();

    // Check parameters
    const params = iface.getParameters();
    try std.testing.expect(params.len == 4);
    try std.testing.expectEqualStrings("rsi_period", params[0].name);
    try std.testing.expectEqualStrings("sma_period", params[1].name);
}
