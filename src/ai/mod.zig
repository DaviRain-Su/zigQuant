//! AI Module
//!
//! This module provides AI/LLM integration for trading strategy assistance.
//! It includes client abstractions, prompt building, and structured advice generation.
//!
//! ## Components
//!
//! - **ILLMClient**: VTable interface for LLM providers (OpenAI, Anthropic, etc.)
//! - **LLMClient**: Concrete multi-provider LLM client implementation
//! - **AIAdvisor**: High-level advisor that returns structured trading advice
//! - **PromptBuilder**: Utility for building market analysis prompts
//!
//! ## Quick Start
//!
//! ```zig
//! const ai = @import("ai");
//!
//! // Create LLM client
//! const config = ai.AIConfig{
//!     .provider = .anthropic,
//!     .model_id = "claude-sonnet-4-5",
//!     .api_key = "your-api-key",
//! };
//! const client = try ai.LLMClient.init(allocator, config);
//! defer client.deinit();
//!
//! // Create advisor
//! var advisor = ai.AIAdvisor.init(allocator, client.toInterface(), .{});
//! defer advisor.deinit();
//!
//! // Get trading advice
//! const advice = try advisor.getAdvice(market_context);
//! defer advisor.freeAdvice(advice);
//! ```

const std = @import("std");

// ============================================================================
// Sub-modules
// ============================================================================

/// Type definitions for AI module
pub const types = @import("types.zig");

/// Interface definitions (ILLMClient)
pub const interfaces = @import("interfaces.zig");

/// LLM client implementations
pub const client = @import("client.zig");

/// AI Advisor for trading recommendations
pub const advisor = @import("advisor.zig");

/// Prompt building utilities
pub const prompt_builder = @import("prompt_builder.zig");

// ============================================================================
// Type Re-exports
// ============================================================================

// Core types
pub const AIProvider = types.AIProvider;
pub const AIModel = types.AIModel;
pub const AIConfig = types.AIConfig;
pub const AIAdvice = types.AIAdvice;
pub const Action = types.Action;
pub const MarketContext = types.MarketContext;
pub const IndicatorSnapshot = types.IndicatorSnapshot;
pub const AdvisorConfig = types.AdvisorConfig;
pub const AdvisorStats = types.AdvisorStats;

// Interfaces
pub const ILLMClient = interfaces.ILLMClient;
pub const MockLLMClient = interfaces.MockLLMClient;

// Implementations
pub const LLMClient = client.LLMClient;
pub const AIAdvisor = advisor.AIAdvisor;
pub const PromptBuilder = prompt_builder.PromptBuilder;

// Utility functions
pub const getApiEndpoint = client.getApiEndpoint;
pub const isProviderSupported = client.isProviderSupported;

// ============================================================================
// Module-level Utilities
// ============================================================================

/// Create a configured LLM client from environment variables
/// Expects ZIGQUANT_AI_PROVIDER, ZIGQUANT_AI_MODEL, and ZIGQUANT_AI_API_KEY
pub fn createClientFromEnv(allocator: std.mem.Allocator) !*LLMClient {
    const provider_str = std.posix.getenv("ZIGQUANT_AI_PROVIDER") orelse "anthropic";
    const model_id = std.posix.getenv("ZIGQUANT_AI_MODEL") orelse "claude-sonnet-4-5";
    const api_key = std.posix.getenv("ZIGQUANT_AI_API_KEY") orelse return error.MissingApiKey;

    const provider = std.meta.stringToEnum(AIProvider, provider_str) orelse .anthropic;

    const config = AIConfig{
        .provider = provider,
        .model_id = model_id,
        .api_key = api_key,
    };

    return try LLMClient.init(allocator, config);
}

/// Create a default advisor with environment-based configuration
pub fn createAdvisorFromEnv(allocator: std.mem.Allocator) !struct { advisor: AIAdvisor, client: *LLMClient } {
    const llm_client = try createClientFromEnv(allocator);
    errdefer llm_client.deinit();

    const ai_advisor = AIAdvisor.init(
        allocator,
        llm_client.toInterface(),
        .{},
    );

    return .{
        .advisor = ai_advisor,
        .client = llm_client,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "mod: all submodules import correctly" {
    // Verify all submodules can be imported
    _ = types;
    _ = interfaces;
    _ = client;
    _ = advisor;
    _ = prompt_builder;
}

test "mod: type re-exports are accessible" {
    // Verify type re-exports work
    const config = AIConfig{
        .provider = .openai,
        .model_id = "gpt-4o",
        .api_key = "test-key",
    };

    try std.testing.expectEqual(AIProvider.openai, config.provider);
    try std.testing.expectEqualStrings("gpt-4o", config.model_id);
}

test "mod: MockLLMClient from interfaces" {
    var mock = MockLLMClient.init("test response");
    const iface = mock.toInterface();

    try std.testing.expect(iface.isConnected());

    const model = iface.getModel();
    try std.testing.expectEqual(AIProvider.custom, model.provider);
}

test "mod: Action enum conversion" {
    try std.testing.expectEqual(Action.buy, Action.fromString("buy").?);
    try std.testing.expectEqual(Action.strong_sell, Action.fromString("strong_sell").?);
    try std.testing.expect(Action.fromString("invalid") == null);
}

test "mod: AIAdvice validation" {
    const valid_advice = AIAdvice{
        .action = .hold,
        .confidence = 0.75,
        .reasoning = "Test reasoning",
        .timestamp = std.time.milliTimestamp(),
    };

    try std.testing.expect(valid_advice.isValid());
    try std.testing.expect(valid_advice.meetsConfidenceThreshold(0.5));
    try std.testing.expect(!valid_advice.meetsConfidenceThreshold(0.9));
}

test "mod: PromptBuilder" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const schema = PromptBuilder.getAdviceSchema();
    try std.testing.expect(schema.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, schema, "action") != null);
}

test "mod: complete workflow with mock" {
    var mock = MockLLMClient.init(
        \\{"action": "buy", "confidence": 0.8, "reasoning": "Test buy signal"}
    );

    var ai_advisor = AIAdvisor.init(
        std.testing.allocator,
        mock.toInterface(),
        .{ .max_retries = 0 },
    );
    defer ai_advisor.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = @import("../root.zig").Decimal.fromFloat(50000.0),
        .price_change_24h = 0.05,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };

    const advice = try ai_advisor.getAdvice(ctx);
    defer ai_advisor.freeAdvice(advice);

    try std.testing.expectEqual(Action.buy, advice.action);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8), advice.confidence, 0.001);
}

test {
    // Run all submodule tests
    std.testing.refAllDecls(@This());
}
