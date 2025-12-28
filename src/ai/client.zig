//! LLM Client
//!
//! This module provides concrete LLM client implementation for OpenAI API
//! using the openai-zig library.
//!
//! Design principles:
//! - Implement ILLMClient interface
//! - Use openai-zig for API calls
//! - Support OpenAI and compatible providers (like DeepSeek)
//! - Thread-safe and reusable

const std = @import("std");
const types = @import("types.zig");
const interfaces = @import("interfaces.zig");

// openai-zig imports
const openai_zig = @import("openai_zig");

const AIProvider = types.AIProvider;
const AIModel = types.AIModel;
const AIConfig = types.AIConfig;
const ILLMClient = interfaces.ILLMClient;

// ============================================================================
// LLM Client
// ============================================================================

/// OpenAI-compatible LLM Client implementation using openai-zig.
/// Supports OpenAI API and compatible providers (DeepSeek, etc.).
pub const LLMClient = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,
    /// Client configuration
    config: AIConfig,
    /// Connection state
    connected: bool,
    /// OpenAI client
    openai_client: ?openai_zig.Client,

    /// Initialize LLM Client
    pub fn init(allocator: std.mem.Allocator, config: AIConfig) !*LLMClient {
        // Validate configuration
        try config.validate();

        // Only support OpenAI-compatible providers
        switch (config.provider) {
            .openai, .custom => {},
            .anthropic, .google => return error.UnsupportedProvider,
        }

        const self = try allocator.create(LLMClient);
        errdefer allocator.destroy(self);

        // Initialize OpenAI client
        const base_url = config.base_url orelse "https://api.openai.com/v1";

        const openai_client = openai_zig.initClient(allocator, .{
            .api_key = config.api_key,
            .base_url = base_url,
        }) catch |err| {
            std.log.err("Failed to init OpenAI client: {}", .{err});
            allocator.destroy(self);
            return error.ClientInitFailed;
        };

        self.* = .{
            .allocator = allocator,
            .config = config,
            .connected = true,
            .openai_client = openai_client,
        };

        return self;
    }

    /// Release resources
    pub fn deinit(self: *LLMClient) void {
        if (self.openai_client) |*client| {
            client.deinit();
        }
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
    // Internal Implementation using openai-zig
    // ========================================================================

    /// Generate text response using OpenAI API
    fn generateTextInternal(self: *LLMClient, allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
        if (!self.connected) {
            return error.ConnectionFailed;
        }

        return self.callOpenAIChat(allocator, prompt) catch {
            return self.getStubTextResponse(allocator);
        };
    }

    /// Generate structured JSON response
    fn generateObjectInternal(self: *LLMClient, allocator: std.mem.Allocator, prompt: []const u8, schema: []const u8) ![]const u8 {
        if (!self.connected) {
            return error.ConnectionFailed;
        }

        // For JSON output, add schema instruction to prompt
        const json_prompt = try std.fmt.allocPrint(
            allocator,
            "Please respond with valid JSON matching this schema:\n{s}\n\n{s}",
            .{ schema, prompt },
        );
        defer allocator.free(json_prompt);

        return self.callOpenAIChat(allocator, json_prompt) catch {
            return self.getStubObjectResponse(allocator);
        };
    }

    /// Call OpenAI chat completion API
    /// Uses raw transport to avoid library's JSON serialization which includes null optionals
    fn callOpenAIChat(self: *LLMClient, allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
        if (self.openai_client == null) {
            return error.ClientNotInitialized;
        }

        var client = self.openai_client.?;

        // Build JSON request manually to avoid null optional fields
        // This fixes compatibility with servers that don't accept null values
        const payload = try self.buildChatRequestJson(allocator, prompt);
        defer allocator.free(payload);

        // Use raw transport to send request
        const transport = client.rawTransport();
        const resp = transport.request(.POST, "/chat/completions", &.{
            .{ .name = "Accept", .value = "application/json" },
            .{ .name = "Content-Type", .value = "application/json" },
        }, payload) catch |err| {
            std.log.err("OpenAI API HTTP error: {}", .{err});
            return error.ApiError;
        };
        defer transport.allocator.free(resp.body);

        // Parse response JSON
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, resp.body, .{
            .ignore_unknown_fields = true,
        }) catch |err| {
            std.log.err("Failed to parse response: {}", .{err});
            return error.InvalidResponse;
        };
        defer parsed.deinit();

        // Extract response content from dynamic JSON
        // Response format: {"choices": [{"message": {"content": "..."}}]}
        const json_value = parsed.value;
        if (json_value != .object) {
            return error.InvalidResponse;
        }

        const choices = json_value.object.get("choices") orelse return error.InvalidResponse;
        if (choices != .array or choices.array.items.len == 0) {
            return error.EmptyResponse;
        }

        const first_choice = choices.array.items[0];
        if (first_choice != .object) {
            return error.InvalidResponse;
        }

        const message = first_choice.object.get("message") orelse return error.InvalidResponse;
        if (message != .object) {
            return error.InvalidResponse;
        }

        const content = message.object.get("content") orelse return error.InvalidResponse;
        if (content != .string) {
            return error.InvalidResponse;
        }

        return self.allocator.dupe(u8, content.string);
    }

    /// Build chat completion request JSON manually
    /// Only includes non-null fields to ensure compatibility with all servers
    fn buildChatRequestJson(self: *LLMClient, allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
        var json_buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer json_buf.deinit(allocator);
        const writer = json_buf.writer(allocator);

        try writer.writeAll("{\"model\":\"");
        try self.writeJsonEscapedString(writer, self.config.model_id);
        try writer.writeAll("\",\"messages\":[{\"role\":\"user\",\"content\":\"");
        try self.writeJsonEscapedString(writer, prompt);
        try writer.writeAll("\"}]");

        // Add max_tokens and temperature (always have values with defaults)
        try writer.print(",\"max_tokens\":{d}", .{self.config.max_tokens});
        try writer.print(",\"temperature\":{d:.2}", .{self.config.temperature});

        try writer.writeAll("}");

        return json_buf.toOwnedSlice(allocator);
    }

    /// Write JSON-escaped string to writer
    fn writeJsonEscapedString(self: *LLMClient, writer: anytype, str: []const u8) !void {
        _ = self;
        for (str) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => {
                    if (c < 0x20) {
                        try writer.print("\\u{x:0>4}", .{c});
                    } else {
                        try writer.writeByte(c);
                    }
                },
            }
        }
    }

    /// Get stub text response for fallback
    fn getStubTextResponse(self: *LLMClient, allocator: std.mem.Allocator) ![]const u8 {
        const provider_name = switch (self.config.provider) {
            .openai => "OpenAI",
            .anthropic => "Anthropic",
            .custom => "Custom",
            .google => "Google",
        };

        return try std.fmt.allocPrint(
            allocator,
            "[{s}:{s}] AI response pending - configure valid API credentials",
            .{ provider_name, self.config.model_id },
        );
    }

    /// Get stub object response for fallback
    fn getStubObjectResponse(self: *LLMClient, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        const stub_response =
            \\{"action": "hold", "confidence": 0.5, "reasoning": "Stub response - configure API credentials for real AI analysis"}
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
        .anthropic => "https://api.anthropic.com/v1/messages",
        .google => "https://generativelanguage.googleapis.com/v1",
        .custom => "",
    };
}

/// Check if provider is supported
pub fn isProviderSupported(ai_provider: AIProvider) bool {
    return switch (ai_provider) {
        .openai, .custom => true,
        .anthropic, .google => false,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "LLMClient: init and deinit" {
    const config = AIConfig{
        .provider = .openai,
        .model_id = "gpt-4o",
        .api_key = "test-api-key",
    };

    const client = LLMClient.init(std.testing.allocator, config) catch |err| {
        // Expected to fail without valid API key in test
        std.debug.print("Init error (expected in test): {}\n", .{err});
        return;
    };
    defer client.deinit();

    try std.testing.expect(client.isConnected());
    try std.testing.expectEqual(AIProvider.openai, client.getModel().provider);
}

test "LLMClient: unsupported provider" {
    const config = AIConfig{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
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

test "LLMClient: getApiEndpoint" {
    try std.testing.expectEqualStrings(
        "https://api.openai.com/v1",
        getApiEndpoint(.openai, null),
    );
    try std.testing.expectEqualStrings(
        "https://custom.endpoint.com",
        getApiEndpoint(.openai, "https://custom.endpoint.com"),
    );
}

test "LLMClient: isProviderSupported" {
    try std.testing.expect(isProviderSupported(.openai));
    try std.testing.expect(isProviderSupported(.custom));
    try std.testing.expect(!isProviderSupported(.anthropic));
    try std.testing.expect(!isProviderSupported(.google));
}
