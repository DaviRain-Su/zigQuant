//! ILLMClient Interface
//!
//! This module defines the LLM client interface using Zig's VTable pattern.
//! All LLM client implementations must conform to this interface to be used
//! by the AI Advisor and Hybrid Strategy components.
//!
//! Design follows the project's existing interface patterns (IStrategy, IExchange).

const std = @import("std");
const types = @import("types.zig");
const AIModel = types.AIModel;
const AIConfig = types.AIConfig;

// ============================================================================
// ILLMClient Interface
// ============================================================================

/// LLM Client interface using VTable pattern
/// Provides unified API for different AI providers (OpenAI, Anthropic, etc.)
pub const ILLMClient = struct {
    /// Opaque pointer to the concrete implementation
    ptr: *anyopaque,
    /// Virtual function table
    vtable: *const VTable,

    /// Virtual function table definition
    pub const VTable = struct {
        /// Generate text response from prompt
        /// @param ptr: Implementation pointer
        /// @param allocator: Memory allocator for response
        /// @param prompt: Input prompt text
        /// @return Generated text response (caller owns memory)
        generateText: *const fn (
            ptr: *anyopaque,
            allocator: std.mem.Allocator,
            prompt: []const u8,
        ) anyerror![]const u8,

        /// Generate structured JSON response from prompt with schema constraint
        /// @param ptr: Implementation pointer
        /// @param allocator: Memory allocator for response
        /// @param prompt: Input prompt text
        /// @param schema: JSON schema for structured output
        /// @return JSON string conforming to schema (caller owns memory)
        generateObject: *const fn (
            ptr: *anyopaque,
            allocator: std.mem.Allocator,
            prompt: []const u8,
            schema: []const u8,
        ) anyerror![]const u8,

        /// Get model information
        /// @param ptr: Implementation pointer
        /// @return AIModel containing provider and model ID
        getModel: *const fn (ptr: *anyopaque) AIModel,

        /// Check if client is connected and ready
        /// @param ptr: Implementation pointer
        /// @return true if connected
        isConnected: *const fn (ptr: *anyopaque) bool,

        /// Release client resources
        /// @param ptr: Implementation pointer
        deinit: *const fn (ptr: *anyopaque) void,
    };

    // ========================================================================
    // Proxy Methods
    // ========================================================================

    /// Generate text response from prompt
    pub fn generateText(self: ILLMClient, allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
        return self.vtable.generateText(self.ptr, allocator, prompt);
    }

    /// Generate structured JSON response
    pub fn generateObject(self: ILLMClient, allocator: std.mem.Allocator, prompt: []const u8, schema: []const u8) ![]const u8 {
        return self.vtable.generateObject(self.ptr, allocator, prompt, schema);
    }

    /// Get model information
    pub fn getModel(self: ILLMClient) AIModel {
        return self.vtable.getModel(self.ptr);
    }

    /// Check connection status
    pub fn isConnected(self: ILLMClient) bool {
        return self.vtable.isConnected(self.ptr);
    }

    /// Release resources
    pub fn deinit(self: ILLMClient) void {
        self.vtable.deinit(self.ptr);
    }
};

// ============================================================================
// Mock Implementation for Testing
// ============================================================================

/// Mock LLM Client for testing purposes
pub const MockLLMClient = struct {
    /// Preset response to return
    response: []const u8,
    /// Number of times generate was called
    call_count: u32 = 0,
    /// Whether to simulate failure
    should_fail: bool = false,
    /// Error to return on failure
    fail_error: anyerror = error.ApiError,
    /// Simulated connection state
    connected: bool = true,
    /// Model info
    model: AIModel,

    /// Create a new mock client with preset response
    pub fn init(response: []const u8) MockLLMClient {
        return .{
            .response = response,
            .model = .{
                .provider = .custom,
                .model_id = "mock-model",
            },
        };
    }

    /// Create a mock client that simulates failures
    pub fn initFailing(err: anyerror) MockLLMClient {
        return .{
            .response = "",
            .should_fail = true,
            .fail_error = err,
            .model = .{
                .provider = .custom,
                .model_id = "mock-model",
            },
        };
    }

    /// Create a mock client with custom model
    pub fn initWithModel(response: []const u8, model: AIModel) MockLLMClient {
        return .{
            .response = response,
            .model = model,
        };
    }

    /// Convert to ILLMClient interface
    pub fn toInterface(self: *MockLLMClient) ILLMClient {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Reset call count
    pub fn reset(self: *MockLLMClient) void {
        self.call_count = 0;
    }

    /// Set failure mode
    pub fn setFailure(self: *MockLLMClient, should_fail: bool, err: anyerror) void {
        self.should_fail = should_fail;
        self.fail_error = err;
    }

    // VTable implementation functions
    fn generateTextImpl(ptr: *anyopaque, allocator: std.mem.Allocator, _: []const u8) anyerror![]const u8 {
        const self: *MockLLMClient = @ptrCast(@alignCast(ptr));
        self.call_count += 1;

        if (self.should_fail) {
            return self.fail_error;
        }

        // Return a copy of the response
        return try allocator.dupe(u8, self.response);
    }

    fn generateObjectImpl(ptr: *anyopaque, allocator: std.mem.Allocator, _: []const u8, _: []const u8) anyerror![]const u8 {
        const self: *MockLLMClient = @ptrCast(@alignCast(ptr));
        self.call_count += 1;

        if (self.should_fail) {
            return self.fail_error;
        }

        // Return a copy of the response
        return try allocator.dupe(u8, self.response);
    }

    fn getModelImpl(ptr: *anyopaque) AIModel {
        const self: *MockLLMClient = @ptrCast(@alignCast(ptr));
        return self.model;
    }

    fn isConnectedImpl(ptr: *anyopaque) bool {
        const self: *MockLLMClient = @ptrCast(@alignCast(ptr));
        return self.connected;
    }

    fn deinitImpl(_: *anyopaque) void {
        // No-op for mock
    }

    /// VTable instance
    const vtable = ILLMClient.VTable{
        .generateText = generateTextImpl,
        .generateObject = generateObjectImpl,
        .getModel = getModelImpl,
        .isConnected = isConnectedImpl,
        .deinit = deinitImpl,
    };
};

// ============================================================================
// Tests
// ============================================================================

test "ILLMClient: VTable structure" {
    // Verify VTable has correct number of fields
    const vtable_info = @typeInfo(ILLMClient.VTable);
    try std.testing.expectEqual(@as(usize, 5), vtable_info.@"struct".fields.len);
}

test "MockLLMClient: basic usage" {
    var mock = MockLLMClient.init("Hello, World!");
    const client = mock.toInterface();

    const response = try client.generateText(std.testing.allocator, "test prompt");
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings("Hello, World!", response);
    try std.testing.expectEqual(@as(u32, 1), mock.call_count);
    try std.testing.expect(client.isConnected());
}

test "MockLLMClient: generateObject" {
    const json_response =
        \\{"action": "buy", "confidence": 0.85, "reasoning": "Bullish momentum"}
    ;

    var mock = MockLLMClient.init(json_response);
    const client = mock.toInterface();

    const schema = "{}"; // Simplified schema
    const response = try client.generateObject(std.testing.allocator, "test prompt", schema);
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings(json_response, response);
    try std.testing.expectEqual(@as(u32, 1), mock.call_count);
}

test "MockLLMClient: failure simulation" {
    var mock = MockLLMClient.initFailing(error.Timeout);
    const client = mock.toInterface();

    const result = client.generateText(std.testing.allocator, "test prompt");
    try std.testing.expectError(error.Timeout, result);
    try std.testing.expectEqual(@as(u32, 1), mock.call_count);
}

test "MockLLMClient: getModel" {
    var mock = MockLLMClient.initWithModel("test", .{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
    });
    const client = mock.toInterface();

    const model = client.getModel();
    try std.testing.expectEqual(types.AIProvider.anthropic, model.provider);
    try std.testing.expectEqualStrings("claude-sonnet-4-5", model.model_id);
}

test "MockLLMClient: reset and setFailure" {
    var mock = MockLLMClient.init("test");
    const client = mock.toInterface();

    const response1 = try client.generateText(std.testing.allocator, "test1");
    defer std.testing.allocator.free(response1);
    const response2 = try client.generateText(std.testing.allocator, "test2");
    defer std.testing.allocator.free(response2);
    try std.testing.expectEqual(@as(u32, 2), mock.call_count);

    mock.reset();
    try std.testing.expectEqual(@as(u32, 0), mock.call_count);

    mock.setFailure(true, error.RateLimited);
    const result = client.generateText(std.testing.allocator, "test3");
    try std.testing.expectError(error.RateLimited, result);
}

test "MockLLMClient: connection state" {
    var mock = MockLLMClient.init("test");

    try std.testing.expect(mock.connected);
    try std.testing.expect(mock.toInterface().isConnected());

    mock.connected = false;
    try std.testing.expect(!mock.toInterface().isConnected());
}

test "MockLLMClient: multiple calls" {
    var mock = MockLLMClient.init("response");
    const client = mock.toInterface();

    // Multiple calls should work and increment counter
    for (0..5) |_| {
        const response = try client.generateText(std.testing.allocator, "prompt");
        std.testing.allocator.free(response);
    }

    try std.testing.expectEqual(@as(u32, 5), mock.call_count);
}

test "ILLMClient: proxy methods compile" {
    // This test ensures all proxy methods compile correctly
    var mock = MockLLMClient.init("test");
    const client = mock.toInterface();

    // All these should compile
    _ = client.getModel();
    _ = client.isConnected();
    client.deinit();
}
