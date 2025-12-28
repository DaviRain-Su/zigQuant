//! Prompt Builder
//!
//! This module provides utilities for constructing professional market analysis
//! prompts for AI-powered trading decisions. Includes prompt templates, JSON
//! schema definitions, and market context formatting.
//!
//! Design principles:
//! - Professional trading terminology
//! - Structured prompt format for consistent AI responses
//! - JSON Schema for structured output validation

const std = @import("std");
const types = @import("types.zig");
const MarketContext = types.MarketContext;
const IndicatorSnapshot = types.IndicatorSnapshot;
const PositionInfo = types.PositionInfo;
const Decimal = @import("../root.zig").Decimal;

// ============================================================================
// Prompt Builder
// ============================================================================

/// Professional market analysis prompt builder
pub const PromptBuilder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    /// Initialize prompt builder
    pub fn init(allocator: std.mem.Allocator) PromptBuilder {
        return .{
            .allocator = allocator,
            .buffer = .{},
        };
    }

    /// Release resources
    pub fn deinit(self: *PromptBuilder) void {
        self.buffer.deinit(self.allocator);
    }

    /// Clear buffer for reuse
    pub fn clear(self: *PromptBuilder) void {
        self.buffer.clearRetainingCapacity();
    }

    /// Build professional market analysis prompt
    pub fn buildMarketAnalysisPrompt(self: *PromptBuilder, ctx: MarketContext) ![]const u8 {
        self.clear();
        const writer = self.buffer.writer(self.allocator);

        // System context
        try writer.writeAll(
            \\You are a professional quantitative trading analyst with expertise in technical analysis and risk management. Analyze the following market data and provide a structured trading recommendation.
            \\
            \\
        );

        // Market data section
        try writer.writeAll("## Market Data\n\n");
        try writer.print("- **Trading Pair**: {s}/{s}\n", .{ ctx.pair.base, ctx.pair.quote });
        try writer.print("- **Current Price**: {d:.4}\n", .{ctx.current_price.toFloat()});
        try writer.print("- **24h Change**: {d:.2}%\n", .{ctx.price_change_24h * 100});

        // Technical indicators section
        if (ctx.indicators.len > 0) {
            try writer.writeAll("\n## Technical Indicators\n\n");
            for (ctx.indicators) |ind| {
                try writer.print("- **{s}**: {d:.4}", .{ ind.name, ind.value });
                if (ind.interpretation.len > 0) {
                    try writer.print(" ({s})", .{ind.interpretation});
                }
                try writer.writeAll("\n");
            }
        }

        // Recent price action
        if (ctx.recent_candles.len > 0) {
            try writer.writeAll("\n## Recent Price Action\n\n");
            const candle_count = @min(ctx.recent_candles.len, 5);
            try writer.print("Last {d} candles:\n", .{candle_count});

            const start_idx = ctx.recent_candles.len - candle_count;
            for (ctx.recent_candles[start_idx..], 0..) |candle, i| {
                const direction: []const u8 = if (candle.close.cmp(candle.open) == .gt) "+" else "-";
                try writer.print("  {d}. O:{d:.2} H:{d:.2} L:{d:.2} C:{d:.2} ({s})\n", .{
                    i + 1,
                    candle.open.toFloat(),
                    candle.high.toFloat(),
                    candle.low.toFloat(),
                    candle.close.toFloat(),
                    direction,
                });
            }
        }

        // Current position section
        if (ctx.position) |pos| {
            try writer.writeAll("\n## Current Position\n\n");
            try writer.print("- **Side**: {s}\n", .{pos.side.toString()});
            try writer.print("- **Entry Price**: {d:.4}\n", .{pos.entry_price.toFloat()});
            try writer.print("- **Size**: {d:.4}\n", .{pos.size.toFloat()});
            try writer.print("- **Unrealized PnL**: {d:.2}%\n", .{pos.unrealized_pnl_pct * 100});
            try writer.print("- **Duration**: {d} minutes\n", .{pos.duration_minutes});
        }

        // Additional notes
        if (ctx.notes) |notes| {
            try writer.writeAll("\n## Additional Context\n\n");
            try writer.print("{s}\n", .{notes});
        }

        // Task instruction
        try writer.writeAll(
            \\
            \\## Task
            \\
            \\Based on the above market data, provide your trading recommendation. Consider:
            \\
            \\1. **Trend Analysis**: Current market direction and momentum
            \\2. **Technical Signals**: Indicator readings and their implications
            \\3. **Risk Assessment**: Potential downside and risk factors
            \\4. **Entry/Exit Timing**: Optimal action given current conditions
            \\
            \\Provide a structured response with:
            \\- **Action**: One of (strong_buy, buy, hold, sell, strong_sell)
            \\- **Confidence**: Your confidence level (0.0 to 1.0)
            \\- **Reasoning**: Brief explanation of your recommendation
            \\
        );

        return self.buffer.items;
    }

    /// Build a simple prompt for quick analysis
    pub fn buildSimplePrompt(self: *PromptBuilder, ctx: MarketContext) ![]const u8 {
        self.clear();
        const writer = self.buffer.writer(self.allocator);

        try writer.print(
            \\Analyze {s}/{s} at price {d:.2} (24h: {d:.2}%).
            \\
        , .{
            ctx.pair.base,
            ctx.pair.quote,
            ctx.current_price.toFloat(),
            ctx.price_change_24h * 100,
        });

        if (ctx.indicators.len > 0) {
            try writer.writeAll("Indicators: ");
            for (ctx.indicators, 0..) |ind, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}={d:.2}", .{ ind.name, ind.value });
            }
            try writer.writeAll(".\n");
        }

        try writer.writeAll("Provide action (strong_buy/buy/hold/sell/strong_sell), confidence (0-1), and brief reasoning.\n");

        return self.buffer.items;
    }

    /// Get JSON schema for AIAdvice structured output
    pub fn getAdviceSchema() []const u8 {
        return advice_schema;
    }

    /// Get JSON schema for extended advice with additional fields
    pub fn getExtendedAdviceSchema() []const u8 {
        return extended_advice_schema;
    }
};

// ============================================================================
// JSON Schemas
// ============================================================================

/// Standard AIAdvice JSON Schema
const advice_schema =
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "action": {
    \\      "type": "string",
    \\      "enum": ["strong_buy", "buy", "hold", "sell", "strong_sell"],
    \\      "description": "Trading action recommendation"
    \\    },
    \\    "confidence": {
    \\      "type": "number",
    \\      "minimum": 0,
    \\      "maximum": 1,
    \\      "description": "Confidence level from 0.0 to 1.0"
    \\    },
    \\    "reasoning": {
    \\      "type": "string",
    \\      "description": "Brief explanation for the recommendation"
    \\    }
    \\  },
    \\  "required": ["action", "confidence", "reasoning"],
    \\  "additionalProperties": false
    \\}
;

/// Extended AIAdvice JSON Schema with additional analysis fields
const extended_advice_schema =
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "action": {
    \\      "type": "string",
    \\      "enum": ["strong_buy", "buy", "hold", "sell", "strong_sell"],
    \\      "description": "Trading action recommendation"
    \\    },
    \\    "confidence": {
    \\      "type": "number",
    \\      "minimum": 0,
    \\      "maximum": 1,
    \\      "description": "Confidence level from 0.0 to 1.0"
    \\    },
    \\    "reasoning": {
    \\      "type": "string",
    \\      "description": "Brief explanation for the recommendation"
    \\    },
    \\    "key_factors": {
    \\      "type": "array",
    \\      "items": {"type": "string"},
    \\      "description": "List of key factors influencing the decision"
    \\    },
    \\    "risk_level": {
    \\      "type": "string",
    \\      "enum": ["low", "medium", "high"],
    \\      "description": "Assessed risk level"
    \\    },
    \\    "target_price": {
    \\      "type": "number",
    \\      "description": "Suggested target price (optional)"
    \\    },
    \\    "stop_loss": {
    \\      "type": "number",
    \\      "description": "Suggested stop loss price (optional)"
    \\    }
    \\  },
    \\  "required": ["action", "confidence", "reasoning"],
    \\  "additionalProperties": false
    \\}
;

// ============================================================================
// Prompt Templates
// ============================================================================

/// Pre-defined prompt templates for common scenarios
pub const PromptTemplates = struct {
    /// Entry analysis prompt template
    pub const entry_analysis =
        \\Analyze the following market conditions for potential entry:
        \\{context}
        \\
        \\Focus on:
        \\1. Trend confirmation signals
        \\2. Support/resistance levels
        \\3. Volume confirmation
        \\4. Risk/reward ratio
        \\
        \\Recommend: enter long, enter short, or wait.
    ;

    /// Exit analysis prompt template
    pub const exit_analysis =
        \\Analyze the following position for potential exit:
        \\{context}
        \\
        \\Consider:
        \\1. Profit target achievement
        \\2. Trend exhaustion signals
        \\3. Risk of reversal
        \\4. Time-based factors
        \\
        \\Recommend: hold, take profit, or exit with loss.
    ;

    /// Risk assessment prompt template
    pub const risk_assessment =
        \\Assess the risk level for the following trade:
        \\{context}
        \\
        \\Evaluate:
        \\1. Market volatility
        \\2. Position size relative to account
        \\3. Stop loss distance
        \\4. Correlation with other positions
        \\
        \\Rate risk: low, medium, or high with explanation.
    ;
};

// ============================================================================
// Tests
// ============================================================================

test "PromptBuilder: init and deinit" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try std.testing.expect(builder.buffer.items.len == 0);
}

test "PromptBuilder: buildMarketAnalysisPrompt basic" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = Decimal.fromFloat(45000.0),
        .price_change_24h = 0.025,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };

    const prompt = try builder.buildMarketAnalysisPrompt(ctx);

    // Verify prompt contains expected content
    try std.testing.expect(std.mem.indexOf(u8, prompt, "BTC/USDT") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "45000") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "2.50%") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "quantitative trading analyst") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "Task") != null);
}

test "PromptBuilder: buildMarketAnalysisPrompt with indicators" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const indicators = [_]IndicatorSnapshot{
        .{ .name = "RSI", .value = 35.5, .interpretation = "approaching oversold" },
        .{ .name = "MACD", .value = 120.3, .interpretation = "bullish momentum" },
    };

    const ctx = MarketContext{
        .pair = .{ .base = "ETH", .quote = "USDT" },
        .current_price = Decimal.fromFloat(2500.0),
        .price_change_24h = -0.015,
        .indicators = &indicators,
        .recent_candles = &.{},
        .position = null,
    };

    const prompt = try builder.buildMarketAnalysisPrompt(ctx);

    // Verify indicators section
    try std.testing.expect(std.mem.indexOf(u8, prompt, "Technical Indicators") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "RSI") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "35.5") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "approaching oversold") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "MACD") != null);
}

test "PromptBuilder: buildMarketAnalysisPrompt with position" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = Decimal.fromFloat(46000.0),
        .price_change_24h = 0.02,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = .{
            .side = .long,
            .entry_price = Decimal.fromFloat(45000.0),
            .size = Decimal.fromFloat(0.1),
            .unrealized_pnl_pct = 0.0222,
            .duration_minutes = 120,
        },
    };

    const prompt = try builder.buildMarketAnalysisPrompt(ctx);

    // Verify position section
    try std.testing.expect(std.mem.indexOf(u8, prompt, "Current Position") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "long") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "45000") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "120 minutes") != null);
}

test "PromptBuilder: buildSimplePrompt" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const indicators = [_]IndicatorSnapshot{
        .{ .name = "RSI", .value = 30.0, .interpretation = "" },
    };

    const ctx = MarketContext{
        .pair = .{ .base = "SOL", .quote = "USDT" },
        .current_price = Decimal.fromFloat(100.0),
        .price_change_24h = 0.05,
        .indicators = &indicators,
        .recent_candles = &.{},
        .position = null,
    };

    const prompt = try builder.buildSimplePrompt(ctx);

    try std.testing.expect(std.mem.indexOf(u8, prompt, "SOL/USDT") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "RSI=30") != null);
    try std.testing.expect(prompt.len < 500); // Simple prompt should be concise
}

test "PromptBuilder: clear and reuse" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = Decimal.fromFloat(45000.0),
        .price_change_24h = 0.01,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };

    // First build
    _ = try builder.buildMarketAnalysisPrompt(ctx);
    const first_len = builder.buffer.items.len;
    try std.testing.expect(first_len > 0);

    // Clear and rebuild
    builder.clear();
    try std.testing.expect(builder.buffer.items.len == 0);

    _ = try builder.buildSimplePrompt(ctx);
    try std.testing.expect(builder.buffer.items.len > 0);
}

test "PromptBuilder: getAdviceSchema returns valid JSON" {
    const schema = PromptBuilder.getAdviceSchema();

    // Verify it's valid JSON by parsing
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        schema,
        .{},
    );
    defer parsed.deinit();

    // Verify required fields exist
    try std.testing.expect(parsed.value.object.get("type") != null);
    try std.testing.expect(parsed.value.object.get("properties") != null);
    try std.testing.expect(parsed.value.object.get("required") != null);
}

test "PromptBuilder: getExtendedAdviceSchema returns valid JSON" {
    const schema = PromptBuilder.getExtendedAdviceSchema();

    // Verify it's valid JSON by parsing
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        schema,
        .{},
    );
    defer parsed.deinit();

    // Verify extended fields exist
    const props = parsed.value.object.get("properties").?.object;
    try std.testing.expect(props.get("key_factors") != null);
    try std.testing.expect(props.get("risk_level") != null);
}

test "PromptBuilder: no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected in PromptBuilder!");
        }
    }
    const allocator = gpa.allocator();

    var builder = PromptBuilder.init(allocator);

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = Decimal.fromFloat(45000.0),
        .price_change_24h = 0.01,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };

    // Multiple builds
    for (0..10) |_| {
        _ = try builder.buildMarketAnalysisPrompt(ctx);
        _ = try builder.buildSimplePrompt(ctx);
    }

    builder.deinit();
}
