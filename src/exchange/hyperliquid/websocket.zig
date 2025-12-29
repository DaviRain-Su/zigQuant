//! Hyperliquid WebSocket Client
//!
//! Real-time market data and user updates via WebSocket.
//! Reference: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket

const std = @import("std");
const websocket = @import("websocket");
const ws_types = @import("ws_types.zig");
const subscription_mod = @import("subscription.zig");
const message_handler_mod = @import("message_handler.zig");
const Logger = @import("../../core/logger.zig").Logger;

const Subscription = ws_types.Subscription;
const Message = ws_types.Message;
const SubscriptionManager = subscription_mod.SubscriptionManager;
const MessageHandler = message_handler_mod.MessageHandler;

// ============================================================================
// WebSocket Handler Types
// ============================================================================

const ReadHandler = struct {
    ws: *HyperliquidWS,

    pub fn serverMessage(handler: *@This(), data: []u8) !void {
        // Skip if disconnecting
        if (!handler.ws.connected.load(.acquire)) return;

        handler.ws.handleMessage(data) catch {
            // Only log errors if still connected
            if (handler.ws.connected.load(.acquire)) {
                handler.ws.logger.err("Error handling WebSocket message", .{}) catch {};
            }
        };
    }

    pub fn close(handler: *@This()) void {
        // Only log and reconnect if we should reconnect
        if (handler.ws.should_reconnect.load(.acquire) and handler.ws.connected.load(.acquire)) {
            handler.ws.logger.warn("Server closed connection", .{}) catch {};
            handler.ws.handleConnectionError();
        }
        // Silent during shutdown
    }

    pub fn serverPing(handler: *@This(), data: []u8) !void {
        _ = data;
        _ = handler;
        // Pong is automatically sent by the library
    }

    pub fn serverClose(handler: *@This(), data: []u8) !void {
        _ = data;
        // Only log and reconnect if we should reconnect
        if (handler.ws.should_reconnect.load(.acquire) and handler.ws.connected.load(.acquire)) {
            handler.ws.logger.info("Received close frame", .{}) catch {};
            handler.ws.handleConnectionError();
        }
        // Silent during shutdown
    }
};

const PingThread = struct {
    ws: *HyperliquidWS,

    fn run(ctx: *@This()) void {
        while (ctx.ws.connected.load(.acquire)) {
            std.Thread.sleep(ctx.ws.config.ping_interval_ms * std.time.ns_per_ms);

            if (!ctx.ws.connected.load(.acquire)) break;

            // Send ping
            var ping_data = [_]u8{};
            ctx.ws.client.?.writePing(&ping_data) catch {
                ctx.ws.logger.warn("Failed to send ping", .{}) catch {};
            };
        }
    }
};

// ============================================================================
// WebSocket Client
// ============================================================================

pub const HyperliquidWS = struct {
    allocator: std.mem.Allocator,
    config: Config,
    client: ?websocket.Client,
    subscription_manager: SubscriptionManager,
    message_handler: MessageHandler,
    logger: Logger,

    // Connection state
    connected: std.atomic.Value(bool),
    should_reconnect: std.atomic.Value(bool),

    // Arena allocator for thread-related allocations (cleaned up on disconnect)
    thread_arena: ?std.heap.ArenaAllocator,

    // Message callback with context
    on_message: ?*const fn (ctx: ?*anyopaque, msg: Message) void,
    on_message_ctx: ?*anyopaque,

    pub const Config = struct {
        ws_url: []const u8,
        host: []const u8,
        port: u16,
        path: []const u8 = "/ws",
        use_tls: bool = true,
        max_message_size: usize = 1024 * 1024, // 1MB
        buffer_size: usize = 8192,
        handshake_timeout_ms: u32 = 10000,
        reconnect_interval_ms: u64 = 5000,
        max_reconnect_attempts: u32 = 10,
        ping_interval_ms: u64 = 30000,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        config: Config,
        logger: Logger,
    ) HyperliquidWS {
        return .{
            .allocator = allocator,
            .config = config,
            .client = null,
            .subscription_manager = SubscriptionManager.init(allocator),
            .message_handler = MessageHandler.init(allocator),
            .logger = logger,
            .connected = std.atomic.Value(bool).init(false),
            .should_reconnect = std.atomic.Value(bool).init(true),
            .thread_arena = null,
            .on_message = null,
            .on_message_ctx = null,
        };
    }

    pub fn deinit(self: *HyperliquidWS) void {
        self.disconnectNoReconnect();
        self.subscription_manager.deinit();
    }

    /// Set message callback with context
    pub fn setMessageCallback(
        self: *HyperliquidWS,
        callback: *const fn (ctx: ?*anyopaque, msg: Message) void,
        ctx: ?*anyopaque,
    ) void {
        self.on_message = callback;
        self.on_message_ctx = ctx;
    }

    /// Connect to WebSocket
    pub fn connect(self: *HyperliquidWS) !void {
        // Create arena allocator for thread allocations
        self.thread_arena = std.heap.ArenaAllocator.init(self.allocator);

        self.logger.info("Connecting to WebSocket", .{
            .host = self.config.host,
            .port = self.config.port,
            .path = self.config.path,
        }) catch {};

        // Create client
        var client = try websocket.Client.init(self.allocator, .{
            .host = self.config.host,
            .port = self.config.port,
            .tls = self.config.use_tls,
            .max_size = self.config.max_message_size,
            .buffer_size = self.config.buffer_size,
        });
        errdefer client.deinit();

        // Perform handshake
        const headers = try std.fmt.allocPrint(
            self.allocator,
            "Host: {s}:{d}",
            .{ self.config.host, self.config.port },
        );
        defer self.allocator.free(headers);

        try client.handshake(self.config.path, .{
            .timeout_ms = self.config.handshake_timeout_ms,
            .headers = headers,
        });

        self.client = client;
        self.connected.store(true, .release);

        self.logger.info("WebSocket connected successfully", .{}) catch {};

        // Start background read loop
        try self.startReadLoop();

        // Start ping loop
        try self.startPingLoop();
    }

    /// Disconnect from WebSocket
    /// Note: This may trigger reconnection if should_reconnect is true.
    /// Use disconnectNoReconnect() to disconnect without triggering reconnection.
    pub fn disconnect(self: *HyperliquidWS) void {
        self.disconnectInternal();
    }

    /// Disconnect from WebSocket and prevent reconnection
    pub fn disconnectNoReconnect(self: *HyperliquidWS) void {
        self.should_reconnect.store(false, .release);
        self.disconnectInternal();
    }

    /// Internal disconnect implementation
    fn disconnectInternal(self: *HyperliquidWS) void {
        if (self.client) |*client| {
            // Signal threads to stop
            self.connected.store(false, .release);

            // Give threads time to notice disconnect and exit
            // Ping thread checks every ping_interval_ms, read thread should exit when connection closes
            std.Thread.sleep(100 * std.time.ns_per_ms);

            // Close the connection (this should cause read thread to exit)
            client.close(.{}) catch {};

            // Wait a bit more for threads to clean up
            std.Thread.sleep(200 * std.time.ns_per_ms);

            client.deinit();
            self.client = null;

            // Clean up thread arena (frees all thread-related allocations)
            if (self.thread_arena) |*arena| {
                arena.deinit();
                self.thread_arena = null;
            }

            // Only log if we're still supposed to (not during shutdown)
            if (self.should_reconnect.load(.acquire)) {
                self.logger.info("WebSocket disconnected", .{}) catch {};
            }
        }
    }

    /// Subscribe to a channel
    pub fn subscribe(self: *HyperliquidWS, sub: Subscription) !void {
        // Add to manager
        try self.subscription_manager.add(sub);

        // Send subscription message
        const json = try sub.toJSON(self.allocator);
        defer self.allocator.free(json);

        try self.send(json);

        self.logger.debug("Subscribed to channel", .{
            .channel = sub.channel.toString(),
        }) catch {};
    }

    /// Unsubscribe from a channel
    pub fn unsubscribe(self: *HyperliquidWS, sub: Subscription) !void {
        // Remove from manager
        self.subscription_manager.remove(sub);

        // Build unsubscription JSON
        const json = if (sub.coin) |coin| blk: {
            if (sub.user) |user| {
                break :blk try std.fmt.allocPrint(self.allocator, "{{\"method\":\"unsubscribe\",\"subscription\":{{\"type\":\"{s}\",\"coin\":\"{s}\",\"user\":\"{s}\"}}}}", .{ sub.channel.toString(), coin, user });
            } else {
                break :blk try std.fmt.allocPrint(self.allocator, "{{\"method\":\"unsubscribe\",\"subscription\":{{\"type\":\"{s}\",\"coin\":\"{s}\"}}}}", .{ sub.channel.toString(), coin });
            }
        } else if (sub.user) |user| blk: {
            break :blk try std.fmt.allocPrint(self.allocator, "{{\"method\":\"unsubscribe\",\"subscription\":{{\"type\":\"{s}\",\"user\":\"{s}\"}}}}", .{ sub.channel.toString(), user });
        } else blk: {
            break :blk try std.fmt.allocPrint(self.allocator, "{{\"method\":\"unsubscribe\",\"subscription\":{{\"type\":\"{s}\"}}}}", .{sub.channel.toString()});
        };
        defer self.allocator.free(json);

        try self.send(json);

        self.logger.debug("Unsubscribed from channel", .{
            .channel = sub.channel.toString(),
        }) catch {};
    }

    /// Send a message (thread-safe)
    fn send(self: *HyperliquidWS, data: []const u8) !void {
        if (self.client) |*client| {
            // websocket.Client.write requires []u8 (mutable) for masking
            const mutable_data = try self.allocator.dupe(u8, data);
            defer self.allocator.free(mutable_data);

            try client.write(mutable_data);
        } else {
            return error.NotConnected;
        }
    }

    /// Start background read loop
    fn startReadLoop(self: *HyperliquidWS) !void {
        if (self.client == null) return error.NotConnected;
        if (self.thread_arena == null) return error.ArenaNotInitialized;

        const arena_alloc = self.thread_arena.?.allocator();
        const handler = try arena_alloc.create(ReadHandler);
        handler.* = .{ .ws = self };

        // Start read loop in background thread
        const thread = try self.client.?.readLoopInNewThread(handler);
        thread.detach();

        self.logger.debug("WebSocket read loop started", .{}) catch {};
    }

    /// Start ping loop
    fn startPingLoop(self: *HyperliquidWS) !void {
        if (self.thread_arena == null) return error.ArenaNotInitialized;

        const arena_alloc = self.thread_arena.?.allocator();
        const ping_ctx = try arena_alloc.create(PingThread);
        ping_ctx.* = .{ .ws = self };

        const thread = try std.Thread.spawn(.{}, PingThread.run, .{ping_ctx});
        thread.detach();

        self.logger.debug("WebSocket ping loop started", .{}) catch {};
    }

    /// Handle incoming message
    fn handleMessage(self: *HyperliquidWS, data: []u8) !void {
        // Skip processing if we're disconnecting
        if (!self.connected.load(.acquire)) return;

        // Parse message
        const msg = try self.message_handler.parse(data);
        defer msg.deinit(self.allocator);

        // Call user callback with context
        if (self.on_message) |callback| {
            callback(self.on_message_ctx, msg);
        }
    }

    /// Handle connection error and attempt reconnect
    fn handleConnectionError(self: *HyperliquidWS) void {
        // Double-check we should reconnect (may have been set to false during shutdown)
        if (!self.should_reconnect.load(.acquire)) {
            self.logger.debug("Skipping reconnect - should_reconnect is false", .{}) catch {};
            return;
        }

        // Mark as disconnected first
        self.connected.store(false, .release);

        self.logger.warn("Connection lost, attempting to reconnect...", .{}) catch {};

        var attempts: u32 = 0;
        while (attempts < self.config.max_reconnect_attempts) : (attempts += 1) {
            // Check again before each attempt
            if (!self.should_reconnect.load(.acquire)) {
                self.logger.debug("Reconnect cancelled - should_reconnect is false", .{}) catch {};
                break;
            }

            std.Thread.sleep(self.config.reconnect_interval_ms * std.time.ns_per_ms);

            // Check again after sleep
            if (!self.should_reconnect.load(.acquire)) {
                self.logger.debug("Reconnect cancelled after sleep - should_reconnect is false", .{}) catch {};
                break;
            }

            self.connect() catch {
                self.logger.warn("Reconnect attempt {} failed", .{attempts + 1}) catch {};
                continue;
            };

            // Resubscribe to all channels
            self.resubscribeAll() catch |err| {
                self.logger.err("Failed to resubscribe: {}", .{err}) catch {};
                self.disconnect();
                continue;
            };

            self.logger.info("Reconnected successfully", .{}) catch {};
            return;
        }

        self.logger.err("Max reconnect attempts reached, giving up", .{}) catch {};
    }

    /// Resubscribe to all channels
    fn resubscribeAll(self: *HyperliquidWS) !void {
        // Get a copy of subscriptions to avoid holding mutex during send
        const subs = self.subscription_manager.getAllCopy(self.allocator) catch |err| {
            self.logger.err("Failed to get subscriptions copy: {}", .{err}) catch {};
            return err;
        };
        defer if (subs.len > 0) self.allocator.free(subs);

        for (subs) |sub| {
            const json = try sub.toJSON(self.allocator);
            defer self.allocator.free(json);
            try self.send(json);
        }

        self.logger.debug("Resubscribed to all channels", .{
            .count = subs.len,
        }) catch {};
    }

    /// Check if connected
    pub fn isConnected(self: *HyperliquidWS) bool {
        return self.connected.load(.acquire);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "HyperliquidWS: initialization" {
    const allocator = std.testing.allocator;

    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../core/logger.zig").LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../core/logger.zig").LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    const logger = @import("../../core/logger.zig").Logger.init(allocator, writer, .debug);

    const config = HyperliquidWS.Config{
        .ws_url = "wss://api.hyperliquid.xyz/ws",
        .host = "api.hyperliquid.xyz",
        .port = 443,
    };

    var ws = HyperliquidWS.init(allocator, config, logger);
    defer ws.deinit();

    try std.testing.expect(!ws.isConnected());
}
