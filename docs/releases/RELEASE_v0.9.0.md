# zigQuant v0.9.0 Release Notes

**Release Date**: TBD
**Version**: 0.9.0
**Codename**: AI-Powered Trading

---

## Overview

v0.9.0 introduces AI-powered trading capabilities to zigQuant, enabling intelligent decision-making through LLM (Large Language Model) integration. This release provides a unified interface for multiple AI providers (OpenAI, Anthropic Claude), an AI Advisor for structured trading recommendations, and a Hybrid Strategy that combines traditional technical analysis with AI insights.

---

## Highlights

### AI Strategy Integration

Based on `zig-ai-sdk`, zigQuant now supports AI-assisted trading decisions:

- **ILLMClient** - VTable-based LLM client interface supporting 30+ AI providers
- **LLMClient** - Multi-provider implementation (OpenAI, Anthropic)
- **AIAdvisor** - Structured trading recommendation service with confidence scoring
- **PromptBuilder** - Professional market analysis prompt engineering
- **HybridAIStrategy** - Weighted combination of technical indicators and AI advice

### Key Features

- **Multi-Provider Support**: Seamlessly switch between OpenAI (GPT-4o, o1, o3) and Anthropic (Claude Sonnet 4.5, Opus 4.5, Haiku)
- **Structured Output**: JSON Schema-constrained responses for reliable parsing
- **Weighted Decision Making**: Configurable weights for technical (default 60%) and AI (default 40%) signals
- **Graceful Degradation**: Automatic fallback to pure technical analysis when AI fails
- **Request Statistics**: Track success rate, latency, and API usage

---

## New Components

### ILLMClient Interface

```zig
const ILLMClient = zigQuant.ILLMClient;

pub const ILLMClient = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        generateText: *const fn (ptr: *anyopaque, prompt: []const u8) anyerror![]const u8,
        generateObject: *const fn (ptr: *anyopaque, prompt: []const u8, schema: []const u8) anyerror![]const u8,
        getModel: *const fn (ptr: *anyopaque) AIModel,
        isConnected: *const fn (ptr: *anyopaque) bool,
        deinit: *const fn (ptr: *anyopaque) void,
    };
};
```

### LLMClient

```zig
const LLMClient = zigQuant.LLMClient;

// Create client with Anthropic Claude
var client = try LLMClient.init(allocator, .{
    .provider = .anthropic,
    .model_id = "claude-sonnet-4-5",
    .api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse return error.NoApiKey,
    .temperature = 0.3,
    .max_tokens = 1024,
});
defer client.deinit();

// Generate text response
const response = try client.toInterface().generateText("Analyze BTC market conditions");
```

### AIAdvisor

```zig
const AIAdvisor = zigQuant.AIAdvisor;

var advisor = AIAdvisor.init(allocator, client.toInterface(), .{
    .min_confidence_threshold = 0.6,
    .max_retries = 2,
});
defer advisor.deinit();

// Get AI trading advice
const advice = try advisor.getAdvice(.{
    .pair = .{ .base = "BTC", .quote = "USDT" },
    .current_price = Decimal.fromFloat(45000.0),
    .price_change_24h = 0.025,
    .indicators = &.{
        .{ .name = "RSI", .value = 35.5, .interpretation = "approaching oversold" },
        .{ .name = "MACD", .value = 120.3, .interpretation = "bullish momentum" },
    },
    .recent_candles = candles,
    .position = null,
});

// advice.action: .strong_buy, .buy, .hold, .sell, .strong_sell
// advice.confidence: 0.0 - 1.0
// advice.reasoning: AI explanation
```

### HybridAIStrategy

```zig
const HybridAIStrategy = zigQuant.HybridAIStrategy;

// Create hybrid strategy
var strategy = try HybridAIStrategy.create(allocator, .{
    .pair = .{ .base = "BTC", .quote = "USDT" },
    .timeframe = .h1,
    .ai_weight = 0.4,        // 40% AI
    .technical_weight = 0.6, // 60% technical
    .min_combined_score = 0.6,
    .ai_config = .{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = api_key,
    },
});
defer strategy.destroy();

// Use in backtest
const engine = try zigQuant.BacktestEngine.init(allocator, .{});
defer engine.deinit();

const result = try engine.run(strategy.toStrategy(), candles);
std.debug.print("AI Hybrid Return: {d:.2}%\n", .{result.total_return * 100});
```

### PromptBuilder

```zig
const PromptBuilder = zigQuant.PromptBuilder;

var builder = PromptBuilder.init(allocator);
defer builder.deinit();

// Build professional market analysis prompt
const prompt = try builder.buildMarketAnalysisPrompt(.{
    .pair = .{ .base = "BTC", .quote = "USDT" },
    .current_price = Decimal.fromFloat(45000.0),
    .price_change_24h = 0.025,
    .indicators = indicators,
    .recent_candles = candles,
    .position = current_position,
});

// Get JSON schema for structured output
const schema = PromptBuilder.getAdviceSchema();
```

---

## Type Definitions

### AIAdvice

```zig
pub const AIAdvice = struct {
    action: Action,
    confidence: f64,        // [0.0, 1.0]
    reasoning: []const u8,  // AI explanation
    timestamp: i64,

    pub const Action = enum {
        strong_buy,   // Score: 1.0
        buy,          // Score: 0.75
        hold,         // Score: 0.5
        sell,         // Score: 0.25
        strong_sell,  // Score: 0.0
    };

    pub fn toScore(self: AIAdvice) f64;
};
```

### AIConfig

```zig
pub const AIConfig = struct {
    provider: AIProvider,      // .openai, .anthropic, .google, .custom
    model_id: []const u8,      // "gpt-4o", "claude-sonnet-4-5", etc.
    api_key: []const u8,
    max_tokens: u32 = 1024,
    temperature: f32 = 0.3,    // Low for deterministic output
    timeout_ms: u32 = 30000,
};
```

---

## Supported AI Models

| Provider | Model ID | Best For |
|----------|----------|----------|
| OpenAI | `gpt-4o` | General analysis |
| OpenAI | `o1`, `o3` | Complex reasoning |
| Anthropic | `claude-sonnet-4-5` | Balanced performance |
| Anthropic | `claude-opus-4-5` | Best reasoning |
| Anthropic | `claude-haiku` | Low latency, low cost |

---

## Configuration

### Environment Variables

```bash
# OpenAI
export OPENAI_API_KEY="sk-..."

# Anthropic Claude
export ANTHROPIC_API_KEY="sk-ant-..."
```

### Hybrid Strategy Weights

| Configuration | AI Weight | Technical Weight | Use Case |
|---------------|-----------|------------------|----------|
| Conservative | 0.3 | 0.7 | Trust technical signals more |
| Balanced | 0.4 | 0.6 | Default configuration |
| AI-Forward | 0.5 | 0.5 | Equal weighting |

---

## Performance Considerations

### Latency

| Operation | Expected Latency |
|-----------|------------------|
| AI API Call | 500ms - 5s |
| Technical Analysis | < 1ms |
| Prompt Building | < 1ms |

### Cost Optimization

- Set reasonable `max_tokens` (default: 1024)
- Use lower-cost models (claude-haiku) for high-frequency scenarios
- Implement response caching (`cache_ttl_seconds`)
- Reduce AI call frequency in high-frequency strategies

### Model Pricing (Approximate)

| Model | Input Cost | Output Cost |
|-------|------------|-------------|
| GPT-4o | ~$5/1M tokens | ~$15/1M tokens |
| Claude Sonnet | ~$3/1M tokens | ~$15/1M tokens |
| Claude Haiku | ~$0.25/1M tokens | ~$1.25/1M tokens |

---

## Error Handling

### Fallback Mechanism

HybridAIStrategy automatically falls back to pure technical analysis when AI fails:

```zig
const ai_advice = self.ai_advisor.getAdvice(ctx) catch |err| {
    self.logger.warn("AI failed: {}, using technical only", .{err});
    return generateSignalFromTechnical(...);
};
```

### Common Errors

| Error | Description | Solution |
|-------|-------------|----------|
| `UnsupportedProvider` | Provider not supported | Check AIProvider enum |
| `InvalidWeights` | Weights don't sum to 1.0 | Adjust ai_weight + technical_weight |
| `Timeout` | API request timeout | Increase timeout_ms |
| `ApiError` | API returned error | Check API key and quota |

---

## File Structure

```
src/ai/
├── mod.zig              # Module exports
├── types.zig            # Type definitions
├── interfaces.zig       # ILLMClient interface
├── client.zig           # LLMClient implementation
├── advisor.zig          # AIAdvisor
└── prompt_builder.zig   # PromptBuilder

src/strategy/builtin/
└── hybrid_ai.zig        # HybridAIStrategy

examples/
└── 32_ai_strategy.zig   # AI strategy example
```

---

## Breaking Changes

None. v0.9.0 is fully backward compatible with v0.8.0.

---

## Migration Guide

No migration required. The new AI components are additive and do not affect existing functionality.

To use the new components:

```zig
const zigQuant = @import("zigQuant");

// New v0.9.0 imports
const ILLMClient = zigQuant.ILLMClient;
const LLMClient = zigQuant.LLMClient;
const AIAdvisor = zigQuant.AIAdvisor;
const AIAdvice = zigQuant.AIAdvice;
const AIConfig = zigQuant.AIConfig;
const HybridAIStrategy = zigQuant.HybridAIStrategy;
const PromptBuilder = zigQuant.PromptBuilder;
```

---

## Dependencies

### zig-ai-sdk

```zig
// build.zig.zon
.@"zig-ai-sdk" = .{
    .url = "https://github.com/evmts/ai-zig/archive/refs/heads/master.tar.gz",
    .hash = "zig_ai_sdk-0.1.0-ULWwFOjsNQDpPPJBPUBUJKikJkiIAASwHYLwqyzEmcim",
},
```

---

## Documentation

- [v0.9.0 Overview](../stories/v0.9.0/OVERVIEW.md)
- [Story 046: AI Strategy Integration](../stories/v0.9.0/STORY_046_AI_STRATEGY.md)
- [AI Module API](../features/ai/README.md)
- [Implementation Details](../features/ai/implementation.md)

---

## What's Next (v1.0.0)

v1.0.0 focuses on production readiness:

- REST API service for external integrations
- Web Dashboard for real-time monitoring
- Multi-strategy portfolio management
- Distributed backtesting
- Binance exchange adapter

See [NEXT_STEPS.md](../NEXT_STEPS.md) for the full roadmap.

---

## Contributors

- Claude (Implementation)
- zigQuant Community

---

## Installation

```bash
# Clone repository
git clone https://github.com/DaviRain-Su/zigQuant.git
cd zigQuant

# Set API keys
export ANTHROPIC_API_KEY="sk-ant-..."
# or
export OPENAI_API_KEY="sk-..."

# Build
zig build

# Run tests
zig build test

# Check AI module
zig test src/ai/mod.zig
```

---

**Full Changelog**: v0.8.0...v0.9.0
