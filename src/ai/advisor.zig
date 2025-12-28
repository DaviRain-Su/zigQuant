//! AI Advisor
//!
//! This module provides the AIAdvisor component that wraps LLM client calls
//! and returns structured trading advice. It handles prompt building, response
//! parsing, statistics tracking, and error handling.
//!
//! Design principles:
//! - Clean interface for getting trading advice
//! - Structured JSON response parsing
//! - Built-in statistics tracking
//! - Graceful error handling with retries

const std = @import("std");
const types = @import("types.zig");
const interfaces = @import("interfaces.zig");
const prompt_builder = @import("prompt_builder.zig");

const AIAdvice = types.AIAdvice;
const Action = types.Action;
const AdvisorConfig = types.AdvisorConfig;
const AdvisorStats = types.AdvisorStats;
const MarketContext = types.MarketContext;
const ILLMClient = interfaces.ILLMClient;
const PromptBuilder = prompt_builder.PromptBuilder;

// ============================================================================
// AI Advisor
// ============================================================================

/// AI Advisor - provides structured trading recommendations
pub const AIAdvisor = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,
    /// LLM client interface
    client: ILLMClient,
    /// Prompt builder
    builder: PromptBuilder,
    /// Advisor configuration
    config: AdvisorConfig,
    /// Statistics
    stats: AdvisorStats,

    /// Initialize AI Advisor
    pub fn init(
        allocator: std.mem.Allocator,
        client: ILLMClient,
        config: AdvisorConfig,
    ) AIAdvisor {
        return .{
            .allocator = allocator,
            .client = client,
            .builder = PromptBuilder.init(allocator),
            .config = config,
            .stats = AdvisorStats.init(),
        };
    }

    /// Release resources
    pub fn deinit(self: *AIAdvisor) void {
        self.builder.deinit();
    }

    /// Get AI trading advice for given market context
    pub fn getAdvice(self: *AIAdvisor, ctx: MarketContext) !AIAdvice {
        const start_time = std.time.milliTimestamp();

        // Build prompt
        const prompt = try self.builder.buildMarketAnalysisPrompt(ctx);
        const schema = PromptBuilder.getAdviceSchema();

        // Call LLM with retries
        var last_error: anyerror = error.Unknown;
        var attempt: u8 = 0;

        while (attempt <= self.config.max_retries) : (attempt += 1) {
            const response = self.client.generateObject(self.allocator, prompt, schema) catch |err| {
                last_error = err;

                // Wait before retry (except on last attempt)
                if (attempt < self.config.max_retries) {
                    std.Thread.sleep(self.config.retry_delay_ms * std.time.ns_per_ms);
                }
                continue;
            };
            defer self.allocator.free(response);

            // Parse response
            const advice = self.parseAdviceResponse(response) catch |err| {
                last_error = err;

                if (attempt < self.config.max_retries) {
                    std.Thread.sleep(self.config.retry_delay_ms * std.time.ns_per_ms);
                }
                continue;
            };

            // Update stats
            const latency = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
            self.stats.update(true, latency);

            return advice;
        }

        // All attempts failed
        const latency = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
        self.stats.update(false, latency);
        return last_error;
    }

    /// Get simple advice using simplified prompt
    pub fn getSimpleAdvice(self: *AIAdvisor, ctx: MarketContext) !AIAdvice {
        const start_time = std.time.milliTimestamp();

        // Build simple prompt
        const prompt = try self.builder.buildSimplePrompt(ctx);
        const schema = PromptBuilder.getAdviceSchema();

        // Call LLM (no retries for simple advice)
        const response = try self.client.generateObject(self.allocator, prompt, schema);
        defer self.allocator.free(response);

        // Parse response
        const advice = try self.parseAdviceResponse(response);

        // Update stats
        const latency = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
        self.stats.update(true, latency);

        return advice;
    }

    /// Parse AI response JSON into AIAdvice
    fn parseAdviceResponse(self: *AIAdvisor, response: []const u8) !AIAdvice {
        const parsed = std.json.parseFromSlice(
            AdviceJson,
            self.allocator,
            response,
            .{},
        ) catch {
            return error.ParseError;
        };
        defer parsed.deinit();

        // Parse action
        const action = Action.fromString(parsed.value.action) orelse {
            return error.ParseError;
        };

        // Validate confidence
        if (parsed.value.confidence < 0.0 or parsed.value.confidence > 1.0) {
            return error.InvalidConfidence;
        }

        // Copy reasoning string
        const reasoning = try self.allocator.dupe(u8, parsed.value.reasoning);

        return AIAdvice{
            .action = action,
            .confidence = parsed.value.confidence,
            .reasoning = reasoning,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    /// Get current statistics
    pub fn getStats(self: *AIAdvisor) AdvisorStats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *AIAdvisor) void {
        self.stats = AdvisorStats.init();
    }

    /// Check if client is connected
    pub fn isConnected(self: *AIAdvisor) bool {
        return self.client.isConnected();
    }

    /// Get underlying model info
    pub fn getModel(self: *AIAdvisor) types.AIModel {
        return self.client.getModel();
    }

    /// Free advice reasoning memory
    pub fn freeAdvice(self: *AIAdvisor, advice: AIAdvice) void {
        self.allocator.free(advice.reasoning);
    }
};

/// JSON structure for parsing AI response
const AdviceJson = struct {
    action: []const u8,
    confidence: f64,
    reasoning: []const u8,
};

// ============================================================================
// Tests
// ============================================================================

test "AIAdvisor: init and deinit" {
    var mock = interfaces.MockLLMClient.init("{}");
    var advisor = AIAdvisor.init(
        std.testing.allocator,
        mock.toInterface(),
        .{},
    );
    defer advisor.deinit();

    try std.testing.expect(advisor.isConnected());
}

test "AIAdvisor: getAdvice with valid response" {
    const response =
        \\{"action": "buy", "confidence": 0.85, "reasoning": "Strong bullish momentum detected based on RSI oversold conditions and MACD crossover."}
    ;

    var mock = interfaces.MockLLMClient.init(response);
    var advisor = AIAdvisor.init(
        std.testing.allocator,
        mock.toInterface(),
        .{ .max_retries = 0 },
    );
    defer advisor.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = @import("../root.zig").Decimal.fromFloat(45000.0),
        .price_change_24h = 0.025,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };

    const advice = try advisor.getAdvice(ctx);
    defer advisor.freeAdvice(advice);

    try std.testing.expectEqual(Action.buy, advice.action);
    try std.testing.expectApproxEqAbs(@as(f64, 0.85), advice.confidence, 0.001);
    try std.testing.expect(std.mem.indexOf(u8, advice.reasoning, "bullish") != null);
    try std.testing.expectEqual(@as(u32, 1), mock.call_count);
}

test "AIAdvisor: getAdvice with all action types" {
    const test_cases = [_]struct { response: []const u8, expected: Action }{
        .{ .response =
        \\{"action": "strong_buy", "confidence": 0.9, "reasoning": "test"}
        , .expected = .strong_buy },
        .{ .response =
        \\{"action": "buy", "confidence": 0.8, "reasoning": "test"}
        , .expected = .buy },
        .{ .response =
        \\{"action": "hold", "confidence": 0.5, "reasoning": "test"}
        , .expected = .hold },
        .{ .response =
        \\{"action": "sell", "confidence": 0.7, "reasoning": "test"}
        , .expected = .sell },
        .{ .response =
        \\{"action": "strong_sell", "confidence": 0.95, "reasoning": "test"}
        , .expected = .strong_sell },
    };

    for (test_cases) |tc| {
        var mock = interfaces.MockLLMClient.init(tc.response);
        var advisor = AIAdvisor.init(
            std.testing.allocator,
            mock.toInterface(),
            .{ .max_retries = 0 },
        );
        defer advisor.deinit();

        const ctx = MarketContext{
            .pair = .{ .base = "BTC", .quote = "USDT" },
            .current_price = @import("../root.zig").Decimal.fromFloat(45000.0),
            .price_change_24h = 0.0,
            .indicators = &.{},
            .recent_candles = &.{},
            .position = null,
        };

        const advice = try advisor.getAdvice(ctx);
        defer advisor.freeAdvice(advice);

        try std.testing.expectEqual(tc.expected, advice.action);
    }
}

test "AIAdvisor: stats tracking" {
    const response =
        \\{"action": "hold", "confidence": 0.6, "reasoning": "Neutral"}
    ;

    var mock = interfaces.MockLLMClient.init(response);
    var advisor = AIAdvisor.init(
        std.testing.allocator,
        mock.toInterface(),
        .{ .max_retries = 0 },
    );
    defer advisor.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = @import("../root.zig").Decimal.fromFloat(45000.0),
        .price_change_24h = 0.0,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };

    // Initial stats
    var stats = advisor.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_requests);

    // Make requests
    for (0..3) |_| {
        const advice = try advisor.getAdvice(ctx);
        advisor.freeAdvice(advice);
    }

    stats = advisor.getStats();
    try std.testing.expectEqual(@as(u64, 3), stats.total_requests);
    try std.testing.expectEqual(@as(u64, 3), stats.successful_requests);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), stats.success_rate, 0.001);

    // Reset stats
    advisor.resetStats();
    stats = advisor.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_requests);
}

test "AIAdvisor: failure handling" {
    var mock = interfaces.MockLLMClient.initFailing(error.Timeout);
    var advisor = AIAdvisor.init(
        std.testing.allocator,
        mock.toInterface(),
        .{ .max_retries = 0 },
    );
    defer advisor.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = @import("../root.zig").Decimal.fromFloat(45000.0),
        .price_change_24h = 0.0,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };

    const result = advisor.getAdvice(ctx);
    try std.testing.expectError(error.Timeout, result);

    const stats = advisor.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.total_requests);
    try std.testing.expectEqual(@as(u64, 0), stats.successful_requests);
}

test "AIAdvisor: parse error handling" {
    const invalid_response = "not valid json";

    var mock = interfaces.MockLLMClient.init(invalid_response);
    var advisor = AIAdvisor.init(
        std.testing.allocator,
        mock.toInterface(),
        .{ .max_retries = 0 },
    );
    defer advisor.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = @import("../root.zig").Decimal.fromFloat(45000.0),
        .price_change_24h = 0.0,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };

    const result = advisor.getAdvice(ctx);
    try std.testing.expectError(error.ParseError, result);
}

test "AIAdvisor: invalid action in response" {
    const response =
        \\{"action": "invalid_action", "confidence": 0.5, "reasoning": "test"}
    ;

    var mock = interfaces.MockLLMClient.init(response);
    var advisor = AIAdvisor.init(
        std.testing.allocator,
        mock.toInterface(),
        .{ .max_retries = 0 },
    );
    defer advisor.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = @import("../root.zig").Decimal.fromFloat(45000.0),
        .price_change_24h = 0.0,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };

    const result = advisor.getAdvice(ctx);
    try std.testing.expectError(error.ParseError, result);
}

test "AIAdvisor: getModel" {
    var mock = interfaces.MockLLMClient.initWithModel("{}", .{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
    });
    var advisor = AIAdvisor.init(
        std.testing.allocator,
        mock.toInterface(),
        .{},
    );
    defer advisor.deinit();

    const model = advisor.getModel();
    try std.testing.expectEqual(types.AIProvider.anthropic, model.provider);
    try std.testing.expectEqualStrings("claude-sonnet-4-5", model.model_id);
}

test "AIAdvisor: no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected in AIAdvisor!");
        }
    }
    const allocator = gpa.allocator();

    const response =
        \\{"action": "buy", "confidence": 0.8, "reasoning": "Test reasoning text"}
    ;

    var mock = interfaces.MockLLMClient.init(response);
    var advisor = AIAdvisor.init(
        allocator,
        mock.toInterface(),
        .{ .max_retries = 0 },
    );

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = @import("../root.zig").Decimal.fromFloat(45000.0),
        .price_change_24h = 0.0,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };

    // Multiple advice requests
    for (0..5) |_| {
        const advice = try advisor.getAdvice(ctx);
        advisor.freeAdvice(advice);
    }

    advisor.deinit();
}
