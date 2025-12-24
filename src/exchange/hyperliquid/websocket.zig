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
        handler.ws.handleMessage(data) catch {
            handler.ws.logger.err("Error handling WebSocket message", .{}) catch {};
        };
    }

    pub fn close(handler: *@This()) void {
        handler.ws.logger.warn("Server closed connection", .{}) catch {};
        handler.ws.handleConnectionError();
    }

    pub fn serverPing(handler: *@This(), data: []u8) !void {
        _ = data;
        _ = handler;
        // Pong is automatically sent by the library
    }

    pub fn serverClose(handler: *@This(), data: []u8) !void {
        _ = data;
        handler.ws.logger.info("Received close frame", .{}) catch {};
        handler.ws.handleConnectionError();
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

    // Message callback
    on_message: ?*const fn (Message) void,

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
        };
    }

    pub fn deinit(self: *HyperliquidWS) void {
        self.should_reconnect.store(false, .release);
        self.disconnect();
        self.subscription_manager.deinit();
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
    pub fn disconnect(self: *HyperliquidWS) void {
        if (self.client) |*client| {
            self.connected.store(false, .release);

            // Give threads time to notice disconnect and exit
            std.Thread.sleep(500 * std.time.ns_per_ms);

            client.close(.{}) catch {};
            client.deinit();
            self.client = null;

            // Clean up thread arena (frees all thread-related allocations)
            if (self.thread_arena) |*arena| {
                arena.deinit();
                self.thread_arena = null;
            }

            self.logger.info("WebSocket disconnected", .{}) catch {};
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
                break :blk try std.fmt.allocPrint(self.allocator,
                    "{{\"method\":\"unsubscribe\",\"subscription\":{{\"type\":\"{s}\",\"coin\":\"{s}\",\"user\":\"{s}\"}}}}",
                    .{sub.channel.toString(), coin, user});
            } else {
                break :blk try std.fmt.allocPrint(self.allocator,
                    "{{\"method\":\"unsubscribe\",\"subscription\":{{\"type\":\"{s}\",\"coin\":\"{s}\"}}}}",
                    .{sub.channel.toString(), coin});
            }
        } else if (sub.user) |user| blk: {
            break :blk try std.fmt.allocPrint(self.allocator,
                "{{\"method\":\"unsubscribe\",\"subscription\":{{\"type\":\"{s}\",\"user\":\"{s}\"}}}}",
                .{sub.channel.toString(), user});
        } else blk: {
            break :blk try std.fmt.allocPrint(self.allocator,
                "{{\"method\":\"unsubscribe\",\"subscription\":{{\"type\":\"{s}\"}}}}",
                .{sub.channel.toString()});
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
        self.logger.debug("Received WebSocket message", .{}) catch {};

        // Parse message
        const msg = try self.message_handler.parse(data);
        defer msg.deinit(self.allocator);

        // Call user callback
        if (self.on_message) |callback| {
            callback(msg);
        }
    }

    /// Handle connection error and attempt reconnect
    fn handleConnectionError(self: *HyperliquidWS) void {
        if (!self.should_reconnect.load(.acquire)) return;

        self.logger.warn("Connection lost, attempting to reconnect...", .{}) catch {};

        var attempts: u32 = 0;
        while (attempts < self.config.max_reconnect_attempts) : (attempts += 1) {
            if (!self.should_reconnect.load(.acquire)) break;

            std.Thread.sleep(self.config.reconnect_interval_ms * std.time.ns_per_ms);

            self.connect() catch {
                self.logger.warn("Reconnect attempt failed", .{}) catch {};
                continue;
            };

            // Resubscribe to all channels
            self.resubscribeAll() catch {
                self.logger.err("Failed to resubscribe", .{}) catch {};
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
        const subs = self.subscription_manager.getAll();

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
        .ptr = @constCast(@ptrCast(&struct {}{})),
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
