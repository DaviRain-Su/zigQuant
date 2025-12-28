//! LLM Client
//!
//! This module provides concrete LLM client implementations for different
//! AI providers (OpenAI, Anthropic, etc.).
//!
//! Note: The actual zig-ai-sdk integration is pending API stabilization.
//! Currently provides a functional stub implementation that can be replaced
//! with real API calls when zig-ai-sdk is updated.
//!
//! Design principles:
//! - Implement ILLMClient interface
//! - Support multiple AI providers
//! - Thread-safe and reusable

const std = @import("std");
const types = @import("types.zig");
const interfaces = @import("interfaces.zig");

const AIProvider = types.AIProvider;
const AIModel = types.AIModel;
const AIConfig = types.AIConfig;
const ILLMClient = interfaces.ILLMClient;

// ============================================================================
// LLM Client
// ============================================================================

/// Multi-provider LLM Client implementation
/// Note: Currently uses stub implementation. Real zig-ai-sdk integration
/// will be enabled once API compatibility with Zig 0.15 is verified.
pub const LLMClient = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,
    /// Client configuration
    config: AIConfig,
    /// Connection state
    connected: bool,

    /// Initialize LLM Client
    pub fn init(allocator: std.mem.Allocator, config: AIConfig) !*LLMClient {
        // Validate configuration
        try config.validate();

        // Check provider support
        switch (config.provider) {
            .openai, .anthropic, .custom => {},
            .google => return error.UnsupportedProvider,
        }

        const self = try allocator.create(LLMClient);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .connected = true,
        };

        return self;
    }

    /// Release resources
    pub fn deinit(self: *LLMClient) void {
        self.allocator.destroy(self);
    }

    /// Convert to ILLMClient interface
    pub fn toInterface(self: *LLMClient) ILLMClient {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Get model information
    pub fn getModel(self: *LLMClient) AIModel {
        return .{
            .provider = self.config.provider,
            .model_id = self.config.model_id,
        };
    }

    /// Check connection state
    pub fn isConnected(self: *LLMClient) bool {
        return self.connected;
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn generateTextImpl(ptr: *anyopaque, allocator: std.mem.Allocator, prompt: []const u8) anyerror![]const u8 {
        const self: *LLMClient = @ptrCast(@alignCast(ptr));
        return self.generateTextInternal(allocator, prompt);
    }

    fn generateObjectImpl(ptr: *anyopaque, allocator: std.mem.Allocator, prompt: []const u8, schema: []const u8) anyerror![]const u8 {
        const self: *LLMClient = @ptrCast(@alignCast(ptr));
        return self.generateObjectInternal(allocator, prompt, schema);
    }

    fn getModelImpl(ptr: *anyopaque) AIModel {
        const self: *LLMClient = @ptrCast(@alignCast(ptr));
        return self.getModel();
    }

    fn isConnectedImpl(ptr: *anyopaque) bool {
        const self: *LLMClient = @ptrCast(@alignCast(ptr));
        return self.isConnected();
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *LLMClient = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    const vtable = ILLMClient.VTable{
        .generateText = generateTextImpl,
        .generateObject = generateObjectImpl,
        .getModel = getModelImpl,
        .isConnected = isConnectedImpl,
        .deinit = deinitImpl,
    };

    // ========================================================================
    // Internal Implementation
    // ========================================================================

    /// Generate text response (internal implementation)
    /// TODO: Replace with zig-ai-sdk calls when API is stabilized
    fn generateTextInternal(self: *LLMClient, allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
        if (!self.connected) {
            return error.ConnectionFailed;
        }

        // Stub response - indicates ready for real integration
        _ = prompt;

        return switch (self.config.provider) {
            .openai => try allocator.dupe(u8, "[OpenAI] Response pending - zig-ai-sdk integration required"),
            .anthropic => try allocator.dupe(u8, "[Anthropic] Response pending - zig-ai-sdk integration required"),
            .custom => try allocator.dupe(u8, "[Custom] Response pending - zig-ai-sdk integration required"),
            .google => error.UnsupportedProvider,
        };
    }

    /// Generate structured JSON response (internal implementation)
    /// TODO: Replace with zig-ai-sdk calls when API is stabilized
    fn generateObjectInternal(self: *LLMClient, allocator: std.mem.Allocator, prompt: []const u8, schema: []const u8) ![]const u8 {
        if (!self.connected) {
            return error.ConnectionFailed;
        }

        // Stub response - returns valid JSON for AIAdvice
        _ = prompt;
        _ = schema;

        const stub_response =
            \\{"action": "hold", "confidence": 0.5, "reasoning": "Stub response - zig-ai-sdk integration pending. Please set up API credentials for actual AI responses."}
        ;

        return try allocator.dupe(u8, stub_response);
    }
};

// ============================================================================
// Provider-specific Helpers
// ============================================================================

/// Get API endpoint URL for provider
pub fn getApiEndpoint(ai_provider: AIProvider, base_url: ?[]const u8) []const u8 {
    if (base_url) |url| {
        return url;
    }

    return switch (ai_provider) {
        .openai => "https://api.openai.com/v1",
        .anthropic => "https://api.anthropic.com/v1",
        .google => "https://generativelanguage.googleapis.com/v1",
        .custom => "",
    };
}

/// Check if provider is supported
pub fn isProviderSupported(ai_provider: AIProvider) bool {
    return switch (ai_provider) {
        .openai, .anthropic, .custom => true,
        .google => false, // Not yet implemented
    };
}

// ============================================================================
// Tests
// ============================================================================

test "LLMClient: init and deinit" {
    const config = AIConfig{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = "test-api-key",
    };

    const client = try LLMClient.init(std.testing.allocator, config);
    defer client.deinit();

    try std.testing.expect(client.isConnected());
    try std.testing.expectEqual(AIProvider.anthropic, client.getModel().provider);
}

test "LLMClient: unsupported provider" {
    const config = AIConfig{
        .provider = .google,
        .model_id = "gemini-pro",
        .api_key = "test-api-key",
    };

    const result = LLMClient.init(std.testing.allocator, config);
    try std.testing.expectError(error.UnsupportedProvider, result);
}

test "LLMClient: invalid config" {
    const config = AIConfig{
        .provider = .openai,
        .model_id = "", // Invalid: empty model ID
        .api_key = "test-key",
    };

    const result = LLMClient.init(std.testing.allocator, config);
    try std.testing.expectError(error.EmptyModelId, result);
}

test "LLMClient: toInterface" {
    const config = AIConfig{
        .provider = .openai,
        .model_id = "gpt-4o",
        .api_key = "test-api-key",
    };

    const client = try LLMClient.init(std.testing.allocator, config);

    const iface = client.toInterface();
    defer iface.deinit();

    try std.testing.expect(iface.isConnected());

    const model = iface.getModel();
    try std.testing.expectEqual(AIProvider.openai, model.provider);
    try std.testing.expectEqualStrings("gpt-4o", model.model_id);
}

test "LLMClient: generateText stub" {
    const config = AIConfig{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = "test-api-key",
    };

    const client = try LLMClient.init(std.testing.allocator, config);
    const iface = client.toInterface();
    defer iface.deinit();

    const response = try iface.generateText(std.testing.allocator, "Test prompt");
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "Anthropic") != null);
}

test "LLMClient: generateObject stub" {
    const config = AIConfig{
        .provider = .openai,
        .model_id = "gpt-4o",
        .api_key = "test-api-key",
    };

    const client = try LLMClient.init(std.testing.allocator, config);
    const iface = client.toInterface();
    defer iface.deinit();

    const response = try iface.generateObject(std.testing.allocator, "Test prompt", "{}");
    defer std.testing.allocator.free(response);

    // Verify it's valid JSON
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        response,
        .{},
    );
    defer parsed.deinit();

    try std.testing.expect(parsed.value.object.get("action") != null);
}

test "LLMClient: getApiEndpoint" {
    try std.testing.expectEqualStrings(
        "https://api.openai.com/v1",
        getApiEndpoint(.openai, null),
    );
    try std.testing.expectEqualStrings(
        "https://api.anthropic.com/v1",
        getApiEndpoint(.anthropic, null),
    );
    try std.testing.expectEqualStrings(
        "https://custom.endpoint.com",
        getApiEndpoint(.openai, "https://custom.endpoint.com"),
    );
}

test "LLMClient: isProviderSupported" {
    try std.testing.expect(isProviderSupported(.openai));
    try std.testing.expect(isProviderSupported(.anthropic));
    try std.testing.expect(isProviderSupported(.custom));
    try std.testing.expect(!isProviderSupported(.google));
}

test "LLMClient: no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected in LLMClient!");
        }
    }
    const allocator = gpa.allocator();

    const config = AIConfig{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = "test-api-key",
    };

    // Create and destroy multiple times
    for (0..5) |_| {
        const client = try LLMClient.init(allocator, config);
        const iface = client.toInterface();

        const text = try iface.generateText(allocator, "test");
        allocator.free(text);

        const obj = try iface.generateObject(allocator, "test", "{}");
        allocator.free(obj);

        iface.deinit();
    }
}
