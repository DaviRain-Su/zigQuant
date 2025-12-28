//! OpenAI Chat Example
//!
//! This example demonstrates how to use the LLM Client to chat with
//! an OpenAI-compatible API server (like LM Studio, Ollama, or DeepSeek).
//!
//! Default Configuration (for local LM Studio server):
//! - Model: openai/gpt-oss-20b
//! - Base URL: http://127.0.0.1:1234/v1
//! - API Key: openai/gpt-oss-20b
//!
//! The library appends /chat/completions to base_url automatically.
//!
//! Run:
//!   zig build run-example-openai-chat
//!
//! To use with other providers, modify the config in main().

const std = @import("std");
const zigQuant = @import("zigQuant");

const ai = zigQuant.ai;
const AIConfig = ai.AIConfig;
const LLMClient = ai.LLMClient;

pub fn main() !void {
    // 1. Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("============================================================\n", .{});
    std.debug.print("    zigQuant - OpenAI Chat Example\n", .{});
    std.debug.print("============================================================\n\n", .{});

    // 2. Configure AI client for local OpenAI-compatible server
    // Note: The library appends /chat/completions to base_url
    // So for LM Studio: base_url = "http://127.0.0.1:1234/v1"
    // Full request URL will be: http://127.0.0.1:1234/v1/chat/completions
    const config = AIConfig{
        .provider = .custom, // Use custom for local/third-party OpenAI-compatible APIs
        .model_id = "openai/gpt-oss-20b",
        .api_key = "openai/gpt-oss-20b",
        .base_url = "http://127.0.0.1:1234/v1", // Local server endpoint (without /chat/completions)
        .max_tokens = 1024,
        .temperature = 0.7,
    };

    std.debug.print("Configuration:\n", .{});
    std.debug.print("  Provider:  Custom (OpenAI-compatible)\n", .{});
    std.debug.print("  Model:     {s}\n", .{config.model_id});
    std.debug.print("  Base URL:  {s}\n", .{config.base_url.?});
    std.debug.print("\n", .{});

    // 3. Initialize LLM Client
    std.debug.print("Initializing LLM client...\n", .{});
    const client = LLMClient.init(allocator, config) catch |err| {
        std.debug.print("Failed to initialize client: {}\n", .{err});
        return;
    };
    defer client.deinit();

    std.debug.print("Client initialized successfully!\n\n", .{});

    // 4. Get interface for making calls
    const iface = client.toInterface();

    // 5. Test simple text generation
    std.debug.print("============================================================\n", .{});
    std.debug.print("Test 1: Simple Text Generation\n", .{});
    std.debug.print("============================================================\n", .{});

    const prompt1 = "Hello! Please introduce yourself briefly.";
    std.debug.print("Prompt: {s}\n\n", .{prompt1});

    const response1 = iface.generateText(allocator, prompt1) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
    defer allocator.free(response1);

    std.debug.print("Response:\n{s}\n\n", .{response1});

    // 6. Test structured JSON generation (trading advice)
    std.debug.print("============================================================\n", .{});
    std.debug.print("Test 2: Trading Advice (JSON Output)\n", .{});
    std.debug.print("============================================================\n", .{});

    const trading_prompt =
        \\Analyze the following market conditions and provide trading advice:
        \\- BTC/USDT current price: $42,500
        \\- RSI (14): 35 (approaching oversold)
        \\- 20-day SMA: $43,200 (price below SMA)
        \\- 24h volume: +15% above average
        \\- Market sentiment: Neutral to slightly bearish
    ;

    const json_schema =
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "action": {"type": "string", "enum": ["strong_buy", "buy", "hold", "sell", "strong_sell"]},
        \\    "confidence": {"type": "number", "minimum": 0, "maximum": 1},
        \\    "reasoning": {"type": "string"}
        \\  },
        \\  "required": ["action", "confidence", "reasoning"]
        \\}
    ;

    std.debug.print("Prompt:\n{s}\n\n", .{trading_prompt});

    const response2 = iface.generateObject(allocator, trading_prompt, json_schema) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
    defer allocator.free(response2);

    std.debug.print("Response (JSON):\n{s}\n\n", .{response2});

    // 7. Parse and display the trading advice
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        response2,
        .{},
    ) catch |err| {
        std.debug.print("JSON parse error: {}\n", .{err});
        return;
    };
    defer parsed.deinit();

    if (parsed.value == .object) {
        std.debug.print("Parsed Trading Advice:\n", .{});
        if (parsed.value.object.get("action")) |action| {
            if (action == .string) {
                std.debug.print("  Action:     {s}\n", .{action.string});
            }
        }
        if (parsed.value.object.get("confidence")) |conf| {
            if (conf == .float) {
                std.debug.print("  Confidence: {d:.1}%\n", .{conf.float * 100});
            } else if (conf == .integer) {
                std.debug.print("  Confidence: {}%\n", .{conf.integer * 100});
            }
        }
        if (parsed.value.object.get("reasoning")) |reason| {
            if (reason == .string) {
                std.debug.print("  Reasoning:  {s}\n", .{reason.string});
            }
        }
    }

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("Example Complete!\n", .{});
    std.debug.print("============================================================\n", .{});
}
