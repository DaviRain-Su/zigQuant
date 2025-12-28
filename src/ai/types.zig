//! AI Types
//!
//! This module defines the core types used for AI-powered trading decisions.
//! Includes AI provider definitions, model information, trading advice structures,
//! and market context for prompt building.
//!
//! Design principles:
//! - Type-safe configuration with compile-time validation
//! - Consistent with existing strategy types patterns
//! - Memory-efficient with minimal allocations

const std = @import("std");
const Decimal = @import("../root.zig").Decimal;
const TradingPair = @import("../root.zig").exchange_types.TradingPair;
const Candle = @import("../root.zig").Candle;

// ============================================================================
// AI Provider
// ============================================================================

/// AI service provider enumeration
pub const AIProvider = enum {
    /// OpenAI (GPT-4o, o1, o3 series)
    openai,
    /// Anthropic (Claude Sonnet, Opus, Haiku)
    anthropic,
    /// Google (Gemini series) - planned
    google,
    /// Custom provider implementation
    custom,

    /// Convert to string representation
    pub fn toString(self: AIProvider) []const u8 {
        return switch (self) {
            .openai => "openai",
            .anthropic => "anthropic",
            .google => "google",
            .custom => "custom",
        };
    }

    /// Parse from string
    pub fn fromString(s: []const u8) ?AIProvider {
        if (std.mem.eql(u8, s, "openai")) return .openai;
        if (std.mem.eql(u8, s, "anthropic")) return .anthropic;
        if (std.mem.eql(u8, s, "google")) return .google;
        if (std.mem.eql(u8, s, "custom")) return .custom;
        return null;
    }
};

// ============================================================================
// AI Model
// ============================================================================

/// AI model information
pub const AIModel = struct {
    /// AI provider
    provider: AIProvider,
    /// Model identifier (e.g., "gpt-4o", "claude-sonnet-4-5")
    model_id: []const u8,

    /// Check if model ID is valid
    pub fn isValid(self: AIModel) bool {
        return self.model_id.len > 0;
    }

    /// Get display name
    pub fn getDisplayName(self: AIModel) []const u8 {
        return self.model_id;
    }
};

// ============================================================================
// AI Config
// ============================================================================

/// AI configuration structure
pub const AIConfig = struct {
    /// AI provider
    provider: AIProvider,
    /// Model identifier
    model_id: []const u8,
    /// API key for authentication
    api_key: []const u8,
    /// Maximum tokens to generate
    max_tokens: u32 = 1024,
    /// Generation temperature (0-1, lower = more deterministic)
    temperature: f32 = 0.3,
    /// Request timeout in milliseconds
    timeout_ms: u32 = 30000,
    /// Base URL override (optional, for custom endpoints)
    base_url: ?[]const u8 = null,

    /// Validate configuration
    pub fn validate(self: AIConfig) !void {
        if (self.model_id.len == 0) {
            return error.EmptyModelId;
        }
        if (self.api_key.len == 0) {
            return error.EmptyApiKey;
        }
        if (self.temperature < 0.0 or self.temperature > 2.0) {
            return error.InvalidTemperature;
        }
        if (self.max_tokens == 0) {
            return error.InvalidMaxTokens;
        }
        if (self.timeout_ms == 0) {
            return error.InvalidTimeout;
        }
    }

    /// Check if configuration is valid
    pub fn isValid(self: AIConfig) bool {
        return self.model_id.len > 0 and
            self.api_key.len > 0 and
            self.temperature >= 0.0 and self.temperature <= 2.0 and
            self.max_tokens > 0 and
            self.timeout_ms > 0;
    }

    /// Get AIModel from config
    pub fn toModel(self: AIConfig) AIModel {
        return .{
            .provider = self.provider,
            .model_id = self.model_id,
        };
    }
};

// ============================================================================
// AI Advice
// ============================================================================

/// Trading action recommendation
pub const Action = enum {
    /// Strong buy signal (score: 1.0)
    strong_buy,
    /// Buy signal (score: 0.75)
    buy,
    /// Hold/neutral (score: 0.5)
    hold,
    /// Sell signal (score: 0.25)
    sell,
    /// Strong sell signal (score: 0.0)
    strong_sell,

    /// Convert to string representation
    pub fn toString(self: Action) []const u8 {
        return switch (self) {
            .strong_buy => "strong_buy",
            .buy => "buy",
            .hold => "hold",
            .sell => "sell",
            .strong_sell => "strong_sell",
        };
    }

    /// Parse from string
    pub fn fromString(s: []const u8) ?Action {
        if (std.mem.eql(u8, s, "strong_buy")) return .strong_buy;
        if (std.mem.eql(u8, s, "buy")) return .buy;
        if (std.mem.eql(u8, s, "hold")) return .hold;
        if (std.mem.eql(u8, s, "sell")) return .sell;
        if (std.mem.eql(u8, s, "strong_sell")) return .strong_sell;
        return null;
    }

    /// Convert action to numeric score [0, 1]
    pub fn toScore(self: Action) f64 {
        return switch (self) {
            .strong_buy => 1.0,
            .buy => 0.75,
            .hold => 0.5,
            .sell => 0.25,
            .strong_sell => 0.0,
        };
    }

    /// Check if action is bullish
    pub fn isBullish(self: Action) bool {
        return self == .strong_buy or self == .buy;
    }

    /// Check if action is bearish
    pub fn isBearish(self: Action) bool {
        return self == .strong_sell or self == .sell;
    }

    /// Check if action is neutral
    pub fn isNeutral(self: Action) bool {
        return self == .hold;
    }
};

/// AI trading advice structure
pub const AIAdvice = struct {
    /// Recommended action
    action: Action,
    /// Confidence level [0.0, 1.0]
    confidence: f64,
    /// AI reasoning/explanation
    reasoning: []const u8,
    /// Timestamp when advice was generated
    timestamp: i64,

    /// Convert action to numeric score [0, 1]
    pub fn toScore(self: AIAdvice) f64 {
        return self.action.toScore();
    }

    /// Get weighted score (action score * confidence)
    pub fn getWeightedScore(self: AIAdvice) f64 {
        return self.toScore() * self.confidence;
    }

    /// Check if advice meets minimum confidence threshold
    pub fn meetsConfidenceThreshold(self: AIAdvice, threshold: f64) bool {
        return self.confidence >= threshold;
    }

    /// Validate advice
    pub fn validate(self: AIAdvice) !void {
        if (self.confidence < 0.0 or self.confidence > 1.0) {
            return error.InvalidConfidence;
        }
        if (self.reasoning.len == 0) {
            return error.EmptyReasoning;
        }
    }

    /// Check if advice is valid
    pub fn isValid(self: AIAdvice) bool {
        return self.confidence >= 0.0 and self.confidence <= 1.0 and self.reasoning.len > 0;
    }
};

// ============================================================================
// Market Context
// ============================================================================

/// Indicator snapshot for prompt building
pub const IndicatorSnapshot = struct {
    /// Indicator name (e.g., "RSI", "MACD")
    name: []const u8,
    /// Indicator value
    value: f64,
    /// Human-readable interpretation (e.g., "oversold", "bullish")
    interpretation: []const u8,

    /// Check if snapshot is valid
    pub fn isValid(self: IndicatorSnapshot) bool {
        return self.name.len > 0;
    }
};

/// Position side for context
pub const PositionSide = enum {
    long,
    short,
    none,

    pub fn toString(self: PositionSide) []const u8 {
        return switch (self) {
            .long => "long",
            .short => "short",
            .none => "none",
        };
    }
};

/// Current position information for context
pub const PositionInfo = struct {
    /// Position side
    side: PositionSide,
    /// Entry price
    entry_price: Decimal,
    /// Current size
    size: Decimal,
    /// Unrealized PnL percentage
    unrealized_pnl_pct: f64,
    /// Duration in minutes
    duration_minutes: u32,
};

/// Market context for AI prompt building
pub const MarketContext = struct {
    /// Trading pair
    pair: TradingPair,
    /// Current market price
    current_price: Decimal,
    /// 24-hour price change percentage
    price_change_24h: f64,
    /// Technical indicators snapshot
    indicators: []const IndicatorSnapshot,
    /// Recent candle data
    recent_candles: []const Candle,
    /// Current position (optional)
    position: ?PositionInfo,
    /// Additional context notes
    notes: ?[]const u8 = null,

    /// Check if context has position
    pub fn hasPosition(self: MarketContext) bool {
        return self.position != null;
    }

    /// Get number of indicators
    pub fn getIndicatorCount(self: MarketContext) usize {
        return self.indicators.len;
    }

    /// Get number of candles
    pub fn getCandleCount(self: MarketContext) usize {
        return self.recent_candles.len;
    }

    /// Validate context
    pub fn validate(self: MarketContext) !void {
        if (self.pair.base.len == 0 or self.pair.quote.len == 0) {
            return error.InvalidTradingPair;
        }
    }

    /// Check if context is valid
    pub fn isValid(self: MarketContext) bool {
        return self.pair.base.len > 0 and self.pair.quote.len > 0;
    }
};

// ============================================================================
// Advisor Config
// ============================================================================

/// AI Advisor configuration
pub const AdvisorConfig = struct {
    /// Minimum confidence threshold for advice
    min_confidence_threshold: f64 = 0.6,
    /// Cache TTL in seconds (0 = no cache)
    cache_ttl_seconds: u32 = 60,
    /// Maximum retry attempts
    max_retries: u8 = 2,
    /// Retry delay in milliseconds
    retry_delay_ms: u32 = 1000,

    /// Validate configuration
    pub fn validate(self: AdvisorConfig) !void {
        if (self.min_confidence_threshold < 0.0 or self.min_confidence_threshold > 1.0) {
            return error.InvalidConfidenceThreshold;
        }
    }

    /// Check if configuration is valid
    pub fn isValid(self: AdvisorConfig) bool {
        return self.min_confidence_threshold >= 0.0 and self.min_confidence_threshold <= 1.0;
    }
};

/// Advisor statistics
pub const AdvisorStats = struct {
    /// Total number of requests
    total_requests: u64,
    /// Number of successful requests
    successful_requests: u64,
    /// Success rate (0-1)
    success_rate: f64,
    /// Average latency in milliseconds
    avg_latency_ms: f64,
    /// Total tokens used
    total_tokens: u64,

    /// Create empty stats
    pub fn init() AdvisorStats {
        return .{
            .total_requests = 0,
            .successful_requests = 0,
            .success_rate = 0.0,
            .avg_latency_ms = 0.0,
            .total_tokens = 0,
        };
    }

    /// Update stats with new request result
    pub fn update(self: *AdvisorStats, success: bool, latency_ms: u64) void {
        self.total_requests += 1;
        if (success) {
            self.successful_requests += 1;
        }
        self.success_rate = if (self.total_requests > 0)
            @as(f64, @floatFromInt(self.successful_requests)) / @as(f64, @floatFromInt(self.total_requests))
        else
            0.0;

        // Update rolling average latency
        const n = @as(f64, @floatFromInt(self.successful_requests));
        if (n > 0) {
            self.avg_latency_ms = self.avg_latency_ms + (@as(f64, @floatFromInt(latency_ms)) - self.avg_latency_ms) / n;
        }
    }
};

// ============================================================================
// AI Errors
// ============================================================================

/// AI-related errors
pub const AIError = error{
    /// Provider not supported
    UnsupportedProvider,
    /// Invalid configuration
    InvalidConfig,
    /// Empty model ID
    EmptyModelId,
    /// Empty API key
    EmptyApiKey,
    /// Invalid temperature value
    InvalidTemperature,
    /// Invalid max tokens
    InvalidMaxTokens,
    /// Invalid timeout
    InvalidTimeout,
    /// Invalid confidence value
    InvalidConfidence,
    /// Empty reasoning
    EmptyReasoning,
    /// Invalid trading pair
    InvalidTradingPair,
    /// Invalid confidence threshold
    InvalidConfidenceThreshold,
    /// Invalid weights configuration
    InvalidWeights,
    /// API request timeout
    Timeout,
    /// API error response
    ApiError,
    /// JSON parse error
    ParseError,
    /// Rate limit exceeded
    RateLimited,
    /// Connection failed
    ConnectionFailed,
    /// Model not available
    ModelNotAvailable,
};

// ============================================================================
// Tests
// ============================================================================

test "AIProvider: toString and fromString" {
    try std.testing.expectEqualStrings("openai", AIProvider.openai.toString());
    try std.testing.expectEqualStrings("anthropic", AIProvider.anthropic.toString());
    try std.testing.expectEqualStrings("google", AIProvider.google.toString());
    try std.testing.expectEqualStrings("custom", AIProvider.custom.toString());

    try std.testing.expectEqual(AIProvider.openai, AIProvider.fromString("openai").?);
    try std.testing.expectEqual(AIProvider.anthropic, AIProvider.fromString("anthropic").?);
    try std.testing.expect(AIProvider.fromString("invalid") == null);
}

test "AIModel: validation" {
    const valid = AIModel{
        .provider = .openai,
        .model_id = "gpt-4o",
    };
    try std.testing.expect(valid.isValid());

    const invalid = AIModel{
        .provider = .openai,
        .model_id = "",
    };
    try std.testing.expect(!invalid.isValid());
}

test "AIConfig: validation" {
    const valid = AIConfig{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = "sk-test-key",
        .temperature = 0.3,
        .max_tokens = 1024,
    };
    try valid.validate();
    try std.testing.expect(valid.isValid());

    // Empty model ID
    const invalid1 = AIConfig{
        .provider = .anthropic,
        .model_id = "",
        .api_key = "sk-test-key",
    };
    try std.testing.expectError(error.EmptyModelId, invalid1.validate());

    // Empty API key
    const invalid2 = AIConfig{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = "",
    };
    try std.testing.expectError(error.EmptyApiKey, invalid2.validate());

    // Invalid temperature
    const invalid3 = AIConfig{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = "sk-test-key",
        .temperature = 3.0,
    };
    try std.testing.expectError(error.InvalidTemperature, invalid3.validate());
}

test "AIConfig: default values" {
    const config = AIConfig{
        .provider = .openai,
        .model_id = "gpt-4o",
        .api_key = "test-key",
    };

    try std.testing.expectEqual(@as(u32, 1024), config.max_tokens);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), config.temperature, 0.001);
    try std.testing.expectEqual(@as(u32, 30000), config.timeout_ms);
}

test "Action: toScore" {
    try std.testing.expectEqual(@as(f64, 1.0), Action.strong_buy.toScore());
    try std.testing.expectEqual(@as(f64, 0.75), Action.buy.toScore());
    try std.testing.expectEqual(@as(f64, 0.5), Action.hold.toScore());
    try std.testing.expectEqual(@as(f64, 0.25), Action.sell.toScore());
    try std.testing.expectEqual(@as(f64, 0.0), Action.strong_sell.toScore());
}

test "Action: bullish/bearish/neutral" {
    try std.testing.expect(Action.strong_buy.isBullish());
    try std.testing.expect(Action.buy.isBullish());
    try std.testing.expect(!Action.hold.isBullish());

    try std.testing.expect(Action.strong_sell.isBearish());
    try std.testing.expect(Action.sell.isBearish());
    try std.testing.expect(!Action.hold.isBearish());

    try std.testing.expect(Action.hold.isNeutral());
    try std.testing.expect(!Action.buy.isNeutral());
}

test "Action: toString and fromString" {
    try std.testing.expectEqualStrings("strong_buy", Action.strong_buy.toString());
    try std.testing.expectEqualStrings("buy", Action.buy.toString());
    try std.testing.expectEqualStrings("hold", Action.hold.toString());
    try std.testing.expectEqualStrings("sell", Action.sell.toString());
    try std.testing.expectEqualStrings("strong_sell", Action.strong_sell.toString());

    try std.testing.expectEqual(Action.buy, Action.fromString("buy").?);
    try std.testing.expectEqual(Action.strong_sell, Action.fromString("strong_sell").?);
    try std.testing.expect(Action.fromString("invalid") == null);
}

test "AIAdvice: toScore and getWeightedScore" {
    const advice = AIAdvice{
        .action = .buy,
        .confidence = 0.8,
        .reasoning = "Strong bullish momentum",
        .timestamp = 0,
    };

    try std.testing.expectEqual(@as(f64, 0.75), advice.toScore());
    try std.testing.expectApproxEqAbs(@as(f64, 0.6), advice.getWeightedScore(), 0.001);
}

test "AIAdvice: validation" {
    const valid = AIAdvice{
        .action = .hold,
        .confidence = 0.6,
        .reasoning = "Neutral market conditions",
        .timestamp = 0,
    };
    try valid.validate();
    try std.testing.expect(valid.isValid());

    // Invalid confidence
    const invalid1 = AIAdvice{
        .action = .buy,
        .confidence = 1.5,
        .reasoning = "Test",
        .timestamp = 0,
    };
    try std.testing.expectError(error.InvalidConfidence, invalid1.validate());
    try std.testing.expect(!invalid1.isValid());

    // Empty reasoning
    const invalid2 = AIAdvice{
        .action = .buy,
        .confidence = 0.8,
        .reasoning = "",
        .timestamp = 0,
    };
    try std.testing.expectError(error.EmptyReasoning, invalid2.validate());
    try std.testing.expect(!invalid2.isValid());
}

test "AIAdvice: meetsConfidenceThreshold" {
    const advice = AIAdvice{
        .action = .buy,
        .confidence = 0.7,
        .reasoning = "Test",
        .timestamp = 0,
    };

    try std.testing.expect(advice.meetsConfidenceThreshold(0.6));
    try std.testing.expect(advice.meetsConfidenceThreshold(0.7));
    try std.testing.expect(!advice.meetsConfidenceThreshold(0.8));
}

test "IndicatorSnapshot: validation" {
    const valid = IndicatorSnapshot{
        .name = "RSI",
        .value = 35.5,
        .interpretation = "approaching oversold",
    };
    try std.testing.expect(valid.isValid());

    const invalid = IndicatorSnapshot{
        .name = "",
        .value = 0,
        .interpretation = "",
    };
    try std.testing.expect(!invalid.isValid());
}

test "MarketContext: validation" {
    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = Decimal.fromFloat(45000.0),
        .price_change_24h = 0.025,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };
    try ctx.validate();
    try std.testing.expect(ctx.isValid());
    try std.testing.expect(!ctx.hasPosition());

    const invalid = MarketContext{
        .pair = .{ .base = "", .quote = "" },
        .current_price = Decimal.fromFloat(0),
        .price_change_24h = 0,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };
    try std.testing.expectError(error.InvalidTradingPair, invalid.validate());
    try std.testing.expect(!invalid.isValid());
}

test "AdvisorConfig: validation" {
    const valid = AdvisorConfig{
        .min_confidence_threshold = 0.6,
        .cache_ttl_seconds = 60,
        .max_retries = 2,
    };
    try valid.validate();
    try std.testing.expect(valid.isValid());

    const invalid = AdvisorConfig{
        .min_confidence_threshold = 1.5,
    };
    try std.testing.expectError(error.InvalidConfidenceThreshold, invalid.validate());
    try std.testing.expect(!invalid.isValid());
}

test "AdvisorStats: update" {
    var stats = AdvisorStats.init();
    try std.testing.expectEqual(@as(u64, 0), stats.total_requests);
    try std.testing.expectEqual(@as(f64, 0.0), stats.success_rate);

    stats.update(true, 100);
    try std.testing.expectEqual(@as(u64, 1), stats.total_requests);
    try std.testing.expectEqual(@as(u64, 1), stats.successful_requests);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), stats.success_rate, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), stats.avg_latency_ms, 0.001);

    stats.update(false, 50);
    try std.testing.expectEqual(@as(u64, 2), stats.total_requests);
    try std.testing.expectEqual(@as(u64, 1), stats.successful_requests);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), stats.success_rate, 0.001);
}
