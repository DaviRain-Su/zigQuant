//! zigQuant WebSocket Server
//!
//! Real-time bidirectional communication for:
//! - Server push: status updates, trade events, log streams
//! - Client commands: low-latency control instructions
//! - Subscription management: channel-based event filtering
//!
//! Protocol: zigquant-v2 (see docs/architecture/web-control-platform/websocket.md)

const std = @import("std");
const zap = @import("zap");
const Allocator = std.mem.Allocator;

// Import zigQuant types
const engine_mod = @import("../engine/mod.zig");
const EngineManager = engine_mod.EngineManager;

// ============================================================================
// WebSocket Context
// ============================================================================

/// Context passed to each WebSocket connection
pub const WsContext = struct {
    allocator: Allocator,
    server: *WebSocketServer,
    handle: zap.WebSockets.WsHandle,
    user_id: ?[]const u8,
    subscriptions: std.StringHashMap(void),
    authenticated: bool,
    last_ping: i64,

    pub fn init(allocator: Allocator, server: *WebSocketServer) !*WsContext {
        const ctx = try allocator.create(WsContext);
        ctx.* = .{
            .allocator = allocator,
            .server = server,
            .handle = null,
            .user_id = null,
            .subscriptions = std.StringHashMap(void).init(allocator),
            .authenticated = false,
            .last_ping = std.time.timestamp(),
        };
        return ctx;
    }

    pub fn deinit(self: *WsContext) void {
        // Clean up subscriptions
        self.subscriptions.deinit();
        if (self.user_id) |uid| {
            self.allocator.free(uid);
        }
        self.allocator.destroy(self);
    }

    /// Subscribe to a channel pattern
    pub fn subscribe(self: *WsContext, channel: []const u8) !void {
        const channel_copy = try self.allocator.dupe(u8, channel);
        try self.subscriptions.put(channel_copy, {});
    }

    /// Unsubscribe from a channel pattern
    pub fn unsubscribe(self: *WsContext, channel: []const u8) void {
        if (self.subscriptions.fetchRemove(channel)) |entry| {
            self.allocator.free(entry.key);
        }
    }

    /// Check if subscribed to a channel (supports wildcards)
    pub fn isSubscribed(self: *WsContext, channel: []const u8) bool {
        // Exact match
        if (self.subscriptions.contains(channel)) return true;

        // Wildcard matching
        var it = self.subscriptions.keyIterator();
        while (it.next()) |pattern| {
            if (matchWildcard(pattern.*, channel)) return true;
        }
        return false;
    }
};

/// Match a channel against a pattern with wildcards
fn matchWildcard(pattern: []const u8, channel: []const u8) bool {
    // Simple wildcard matching: grid.* matches grid.abc, grid.def, etc.
    if (std.mem.eql(u8, pattern, "*")) return true;

    var pattern_parts = std.mem.splitScalar(u8, pattern, '.');
    var channel_parts = std.mem.splitScalar(u8, channel, '.');

    while (true) {
        const p = pattern_parts.next();
        const c = channel_parts.next();

        if (p == null and c == null) return true;
        if (p == null or c == null) return false;

        if (!std.mem.eql(u8, p.?, "*") and !std.mem.eql(u8, p.?, c.?)) {
            return false;
        }
    }
}

// ============================================================================
// WebSocket Handler using Zap's Handler pattern
// ============================================================================

const WsHandler = zap.WebSockets.Handler(WsContext);

// ============================================================================
// WebSocket Server
// ============================================================================

/// WebSocket Server configuration
pub const WsServerConfig = struct {
    allocator: Allocator,
    jwt_secret: []const u8,
    engine_manager: ?*EngineManager = null,
};

/// WebSocket Server - manages all WebSocket connections
pub const WebSocketServer = struct {
    allocator: Allocator,
    config: WsServerConfig,

    // Active connections
    connections: std.ArrayList(*WsContext),
    connections_mutex: std.Thread.Mutex,

    // Broadcast channels
    broadcast_thread: ?std.Thread,
    should_stop: std.atomic.Value(bool),

    const Self = @This();

    /// Initialize the WebSocket server
    pub fn init(config: WsServerConfig) !*Self {
        const self = try config.allocator.create(Self);
        self.* = .{
            .allocator = config.allocator,
            .config = config,
            .connections = std.ArrayList(*WsContext){},
            .connections_mutex = .{},
            .broadcast_thread = null,
            .should_stop = std.atomic.Value(bool).init(false),
        };
        return self;
    }

    /// Start the broadcast loop
    pub fn start(self: *Self) !void {
        self.should_stop.store(false, .release);
        self.broadcast_thread = try std.Thread.spawn(.{}, broadcastLoop, .{self});
    }

    /// Stop the server
    pub fn stop(self: *Self) void {
        self.should_stop.store(true, .release);
        if (self.broadcast_thread) |thread| {
            thread.join();
            self.broadcast_thread = null;
        }
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.stop();

        self.connections_mutex.lock();
        defer self.connections_mutex.unlock();

        for (self.connections.items) |ctx| {
            ctx.deinit();
        }
        self.connections.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Handle HTTP upgrade to WebSocket
    pub fn handleUpgrade(self: *Self, r: zap.Request) !void {
        // Create context for this connection
        const ctx = try WsContext.init(self.allocator, self);
        errdefer ctx.deinit();

        // Add to connections list
        {
            self.connections_mutex.lock();
            defer self.connections_mutex.unlock();
            try self.connections.append(self.allocator, ctx);
        }

        // Set up WebSocket settings
        var settings = WsHandler.WebSocketSettings{
            .on_open = onOpen,
            .on_message = onMessage,
            .on_close = onClose,
            .context = ctx,
        };

        // Upgrade the connection
        WsHandler.upgrade(r.h, &settings) catch |err| {
            std.log.err("WebSocket upgrade failed: {}", .{err});
            self.removeConnection(ctx);
            return err;
        };
    }

    /// Broadcast an event to all subscribed clients
    pub fn broadcast(self: *Self, channel: []const u8, event: []const u8, data: []const u8) void {
        self.connections_mutex.lock();
        defer self.connections_mutex.unlock();

        var msg_buf: [4096]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf,
            \\{{"type":"event","channel":"{s}","event":"{s}","timestamp":{d},"data":{s}}}
        , .{ channel, event, std.time.milliTimestamp(), data }) catch return;

        for (self.connections.items) |ctx| {
            if (ctx.authenticated and ctx.isSubscribed(channel)) {
                WsHandler.write(ctx.handle, msg, true) catch {};
            }
        }
    }

    /// Broadcast to a specific channel pattern using facil.io pub/sub
    pub fn publish(_: *Self, channel: []const u8, message: []const u8) void {
        WsHandler.publish(.{
            .channel = channel,
            .message = message,
            .is_json = true,
        });
    }

    /// Remove a connection from the list
    fn removeConnection(self: *Self, ctx: *WsContext) void {
        self.connections_mutex.lock();
        defer self.connections_mutex.unlock();

        for (self.connections.items, 0..) |c, i| {
            if (c == ctx) {
                _ = self.connections.orderedRemove(i);
                ctx.deinit();
                break;
            }
        }
    }

    /// Get connection count
    pub fn getConnectionCount(self: *Self) usize {
        self.connections_mutex.lock();
        defer self.connections_mutex.unlock();
        return self.connections.items.len;
    }

    /// Background broadcast loop for periodic updates
    fn broadcastLoop(self: *Self) void {
        var last_health_broadcast: i64 = 0;
        const health_interval: i64 = 5; // 5 seconds

        while (!self.should_stop.load(.acquire)) {
            const now = std.time.timestamp();

            // Broadcast health status every 5 seconds
            if (now - last_health_broadcast >= health_interval) {
                self.broadcastHealthStatus();
                last_health_broadcast = now;
            }

            // Broadcast strategy status updates
            self.broadcastStrategyStatuses();

            std.Thread.sleep(1 * std.time.ns_per_s);
        }
    }

    fn broadcastHealthStatus(self: *Self) void {
        if (self.config.engine_manager) |manager| {
            const health = manager.getSystemHealth();
            var buf: [512]u8 = undefined;
            const data = std.fmt.bufPrint(&buf,
                \\{{"status":"{s}","running_strategies":{d},"running_backtests":{d},"kill_switch":{s}}}
            , .{
                health.status,
                health.running_strategies,
                health.running_backtests,
                if (health.kill_switch_active) "true" else "false",
            }) catch return;

            self.broadcast("system.health", "update", data);
        }
    }

    fn broadcastStrategyStatuses(self: *Self) void {
        if (self.config.engine_manager) |manager| {
            const strategies = manager.listStrategies(self.allocator) catch return;
            defer self.allocator.free(strategies);

            for (strategies) |strat| {
                var buf: [512]u8 = undefined;
                const data = std.fmt.bufPrint(&buf,
                    \\{{"id":"{s}","strategy":"{s}","status":"{s}","realized_pnl":{d:.4},"position":{d:.6},"trades":{d}}}
                , .{
                    strat.id,
                    strat.strategy,
                    strat.status,
                    strat.realized_pnl,
                    strat.current_position,
                    strat.total_trades,
                }) catch continue;

                var channel_buf: [64]u8 = undefined;
                const channel = std.fmt.bufPrint(&channel_buf, "strategy.{s}.status", .{strat.id}) catch continue;
                self.broadcast(channel, "update", data);
            }
        }
    }
};

// ============================================================================
// WebSocket Callbacks
// ============================================================================

fn onOpen(ctx: ?*WsContext, handle: zap.WebSockets.WsHandle) !void {
    if (ctx) |c| {
        c.handle = handle;
        c.last_ping = std.time.timestamp();
        std.log.info("WebSocket connection opened", .{});

        // Send welcome message
        var buf: [256]u8 = undefined;
        const welcome = std.fmt.bufPrint(&buf,
            \\{{"type":"connected","timestamp":{d},"data":{{"protocol":"zigquant-v2","server":"zigQuant API v2.0.0"}}}}
        , .{std.time.milliTimestamp()}) catch return;
        WsHandler.write(handle, welcome, true) catch {};
    }
}

fn onMessage(ctx: ?*WsContext, handle: zap.WebSockets.WsHandle, message: []const u8, is_text: bool) !void {
    _ = is_text;

    if (ctx == null or handle == null) return;
    const c = ctx.?;
    c.last_ping = std.time.timestamp();

    // Parse JSON message
    const parsed = std.json.parseFromSlice(std.json.Value, c.allocator, message, .{}) catch {
        try sendError(handle, null, "PARSE_ERROR", "Invalid JSON");
        return;
    };
    defer parsed.deinit();

    const root = parsed.value.object;
    const msg_type = root.get("type") orelse {
        try sendError(handle, null, "INVALID_MESSAGE", "Missing 'type' field");
        return;
    };

    const type_str = switch (msg_type) {
        .string => |s| s,
        else => {
            try sendError(handle, null, "INVALID_MESSAGE", "'type' must be a string");
            return;
        },
    };

    // Handle different message types
    if (std.mem.eql(u8, type_str, "auth")) {
        try handleAuth(c, handle, root);
    } else if (std.mem.eql(u8, type_str, "subscribe")) {
        try handleSubscribe(c, handle, root);
    } else if (std.mem.eql(u8, type_str, "unsubscribe")) {
        try handleUnsubscribe(c, handle, root);
    } else if (std.mem.eql(u8, type_str, "ping")) {
        try handlePing(handle);
    } else if (std.mem.eql(u8, type_str, "command")) {
        try handleCommand(c, handle, root);
    } else {
        try sendError(handle, null, "UNKNOWN_TYPE", "Unknown message type");
    }
}

fn onClose(ctx: ?*WsContext, uuid: isize) !void {
    _ = uuid;
    if (ctx) |c| {
        std.log.info("WebSocket connection closed", .{});
        c.server.removeConnection(c);
    }
}

// ============================================================================
// Message Handlers
// ============================================================================

fn handleAuth(ctx: *WsContext, handle: zap.WebSockets.WsHandle, root: std.json.ObjectMap) !void {
    const token_val = root.get("token") orelse {
        try sendAuthResult(handle, false, "Missing token");
        return;
    };

    const token = switch (token_val) {
        .string => |s| s,
        else => {
            try sendAuthResult(handle, false, "Token must be a string");
            return;
        },
    };

    // TODO: Validate JWT token using the same logic as HTTP API
    // For now, accept any non-empty token
    if (token.len > 0) {
        ctx.authenticated = true;
        ctx.user_id = try ctx.allocator.dupe(u8, "authenticated_user");
        try sendAuthResult(handle, true, null);
    } else {
        try sendAuthResult(handle, false, "Invalid token");
    }
}

fn handleSubscribe(ctx: *WsContext, handle: zap.WebSockets.WsHandle, root: std.json.ObjectMap) !void {
    if (!ctx.authenticated) {
        try sendError(handle, null, "AUTH_REQUIRED", "Authentication required");
        return;
    }

    const channels_val = root.get("channels") orelse {
        try sendError(handle, null, "INVALID_MESSAGE", "Missing 'channels' field");
        return;
    };

    const channels = switch (channels_val) {
        .array => |arr| arr,
        else => {
            try sendError(handle, null, "INVALID_MESSAGE", "'channels' must be an array");
            return;
        },
    };

    var subscribed_count: usize = 0;
    for (channels.items) |ch| {
        const channel = switch (ch) {
            .string => |s| s,
            else => continue,
        };
        ctx.subscribe(channel) catch continue;
        subscribed_count += 1;
    }

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf,
        \\{{"type":"subscribed","timestamp":{d},"data":{{"count":{d},"active_subscriptions":{d}}}}}
    , .{ std.time.milliTimestamp(), subscribed_count, ctx.subscriptions.count() }) catch return;
    WsHandler.write(handle, msg, true) catch {};
}

fn handleUnsubscribe(ctx: *WsContext, handle: zap.WebSockets.WsHandle, root: std.json.ObjectMap) !void {
    const channels_val = root.get("channels") orelse return;

    const channels = switch (channels_val) {
        .array => |arr| arr,
        else => return,
    };

    for (channels.items) |ch| {
        const channel = switch (ch) {
            .string => |s| s,
            else => continue,
        };
        ctx.unsubscribe(channel);
    }

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf,
        \\{{"type":"unsubscribed","timestamp":{d},"data":{{"active_subscriptions":{d}}}}}
    , .{ std.time.milliTimestamp(), ctx.subscriptions.count() }) catch return;
    WsHandler.write(handle, msg, true) catch {};
}

fn handlePing(handle: zap.WebSockets.WsHandle) !void {
    var buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf,
        \\{{"type":"pong","timestamp":{d}}}
    , .{std.time.milliTimestamp()}) catch return;
    WsHandler.write(handle, msg, true) catch {};
}

fn handleCommand(ctx: *WsContext, handle: zap.WebSockets.WsHandle, root: std.json.ObjectMap) !void {
    if (!ctx.authenticated) {
        try sendError(handle, null, "AUTH_REQUIRED", "Authentication required");
        return;
    }

    const id_val = root.get("id");
    const id = if (id_val) |v| switch (v) {
        .string => |s| s,
        else => null,
    } else null;

    const action_val = root.get("action") orelse {
        try sendError(handle, id, "INVALID_COMMAND", "Missing 'action' field");
        return;
    };

    const action = switch (action_val) {
        .string => |s| s,
        else => {
            try sendError(handle, id, "INVALID_COMMAND", "'action' must be a string");
            return;
        },
    };

    // Route command to appropriate handler
    if (std.mem.startsWith(u8, action, "grid.")) {
        try handleGridCommand(ctx, handle, id, action, root);
    } else if (std.mem.startsWith(u8, action, "backtest.")) {
        try handleBacktestCommand(ctx, handle, id, action, root);
    } else if (std.mem.startsWith(u8, action, "strategy.")) {
        try handleStrategyCommand(ctx, handle, id, action, root);
    } else if (std.mem.startsWith(u8, action, "system.")) {
        try handleSystemCommand(ctx, handle, id, action, root);
    } else {
        try sendError(handle, id, "UNKNOWN_ACTION", "Unknown action");
    }
}

fn handleGridCommand(ctx: *WsContext, handle: zap.WebSockets.WsHandle, id: ?[]const u8, action: []const u8, root: std.json.ObjectMap) !void {
    // Grid commands are deprecated - use strategy.* commands with strategy="grid" instead
    _ = ctx;
    _ = action;
    _ = root;
    try sendError(handle, id, "DEPRECATED", "Grid commands are deprecated. Use strategy.start with strategy='grid' instead.");
}

fn handleBacktestCommand(ctx: *WsContext, handle: zap.WebSockets.WsHandle, id: ?[]const u8, action: []const u8, root: std.json.ObjectMap) !void {
    _ = root;
    if (ctx.server.config.engine_manager == null) {
        try sendError(handle, id, "SERVICE_UNAVAILABLE", "Engine manager not configured");
        return;
    }

    // TODO: Implement backtest commands
    if (std.mem.eql(u8, action, "backtest.run")) {
        try sendResponse(handle, id, true,
            \\{"message":"Backtest run command received - implement me"}
        );
    } else if (std.mem.eql(u8, action, "backtest.cancel")) {
        try sendResponse(handle, id, true,
            \\{"message":"Backtest cancel command received - implement me"}
        );
    } else {
        try sendError(handle, id, "UNKNOWN_ACTION", "Unknown backtest action");
    }
}

fn handleStrategyCommand(ctx: *WsContext, handle: zap.WebSockets.WsHandle, id: ?[]const u8, action: []const u8, root: std.json.ObjectMap) !void {
    if (ctx.server.config.engine_manager == null) {
        try sendError(handle, id, "SERVICE_UNAVAILABLE", "Engine manager not configured");
        return;
    }

    const manager = ctx.server.config.engine_manager.?;

    if (std.mem.eql(u8, action, "strategy.start")) {
        // Start a new strategy
        const params_val = root.get("params") orelse {
            try sendError(handle, id, "INVALID_PARAMS", "Missing 'params' field");
            return;
        };

        const params = switch (params_val) {
            .object => |obj| obj,
            else => {
                try sendError(handle, id, "INVALID_PARAMS", "'params' must be an object");
                return;
            },
        };

        // Extract required fields
        const strategy_id = blk: {
            if (params.get("id")) |v| {
                if (v == .string) break :blk v.string;
            }
            // Generate ID if not provided
            break :blk "strat_ws";
        };

        const strategy_name = blk: {
            if (params.get("strategy")) |v| {
                if (v == .string) break :blk v.string;
            }
            try sendError(handle, id, "INVALID_PARAMS", "Missing 'strategy' field");
            return;
        };

        const symbol = blk: {
            if (params.get("symbol")) |v| {
                if (v == .string) break :blk v.string;
            }
            try sendError(handle, id, "INVALID_PARAMS", "Missing 'symbol' field");
            return;
        };

        const timeframe = blk: {
            if (params.get("timeframe")) |v| {
                if (v == .string) break :blk v.string;
            }
            break :blk "1h"; // Default
        };

        const mode_str = blk: {
            if (params.get("mode")) |v| {
                if (v == .string) break :blk v.string;
            }
            break :blk "paper"; // Default
        };

        const StrategyRequest = engine_mod.StrategyRequest;
        const StrategyTradingMode = engine_mod.StrategyTradingMode;

        // Extract grid-specific parameters if this is a grid strategy
        const upper_price: ?f64 = blk: {
            if (params.get("upper_price")) |v| {
                if (v == .float) break :blk v.float;
                if (v == .integer) break :blk @floatFromInt(v.integer);
            }
            break :blk null;
        };

        const lower_price: ?f64 = blk: {
            if (params.get("lower_price")) |v| {
                if (v == .float) break :blk v.float;
                if (v == .integer) break :blk @floatFromInt(v.integer);
            }
            break :blk null;
        };

        const grid_count: u32 = blk: {
            if (params.get("grid_count")) |v| {
                if (v == .integer and v.integer >= 0 and v.integer <= 100) {
                    break :blk @intCast(v.integer);
                }
            }
            break :blk 10; // Default
        };

        const order_size: f64 = blk: {
            if (params.get("order_size")) |v| {
                if (v == .float) break :blk v.float;
                if (v == .integer) break :blk @floatFromInt(v.integer);
            }
            break :blk 0.001; // Default
        };

        const take_profit_pct: f64 = blk: {
            if (params.get("take_profit_pct")) |v| {
                if (v == .float) break :blk v.float;
                if (v == .integer) break :blk @floatFromInt(v.integer);
            }
            break :blk 0.5; // Default
        };

        const request = StrategyRequest{
            .strategy = strategy_name,
            .symbol = symbol,
            .timeframe = timeframe,
            .mode = StrategyTradingMode.fromString(mode_str),
            // Grid-specific parameters
            .upper_price = upper_price,
            .lower_price = lower_price,
            .grid_count = grid_count,
            .order_size = order_size,
            .take_profit_pct = take_profit_pct,
        };

        manager.startStrategy(strategy_id, request) catch |err| {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Failed to start strategy: {s}", .{@errorName(err)}) catch "Start failed";
            try sendError(handle, id, "START_FAILED", msg);
            return;
        };

        var buf: [256]u8 = undefined;
        const data = std.fmt.bufPrint(&buf,
            \\{{"id":"{s}","status":"running"}}
        , .{strategy_id}) catch return;
        try sendResponse(handle, id, true, data);
    } else if (std.mem.eql(u8, action, "strategy.stop")) {
        // Stop a strategy
        const params_val = root.get("params") orelse {
            try sendError(handle, id, "INVALID_PARAMS", "Missing 'params' field");
            return;
        };

        const params = switch (params_val) {
            .object => |obj| obj,
            else => {
                try sendError(handle, id, "INVALID_PARAMS", "'params' must be an object");
                return;
            },
        };

        const strategy_id = blk: {
            if (params.get("id")) |v| {
                if (v == .string) break :blk v.string;
            }
            try sendError(handle, id, "INVALID_PARAMS", "Missing 'id' field");
            return;
        };

        manager.stopStrategy(strategy_id) catch |err| {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Failed to stop strategy: {s}", .{@errorName(err)}) catch "Stop failed";
            try sendError(handle, id, "STOP_FAILED", msg);
            return;
        };

        var buf: [128]u8 = undefined;
        const data = std.fmt.bufPrint(&buf,
            \\{{"id":"{s}","status":"stopped"}}
        , .{strategy_id}) catch return;
        try sendResponse(handle, id, true, data);
    } else if (std.mem.eql(u8, action, "strategy.pause")) {
        // Pause a strategy
        const params_val = root.get("params") orelse {
            try sendError(handle, id, "INVALID_PARAMS", "Missing 'params' field");
            return;
        };

        const params = switch (params_val) {
            .object => |obj| obj,
            else => {
                try sendError(handle, id, "INVALID_PARAMS", "'params' must be an object");
                return;
            },
        };

        const strategy_id = blk: {
            if (params.get("id")) |v| {
                if (v == .string) break :blk v.string;
            }
            try sendError(handle, id, "INVALID_PARAMS", "Missing 'id' field");
            return;
        };

        manager.pauseStrategy(strategy_id) catch |err| {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Failed to pause strategy: {s}", .{@errorName(err)}) catch "Pause failed";
            try sendError(handle, id, "PAUSE_FAILED", msg);
            return;
        };

        var buf: [128]u8 = undefined;
        const data = std.fmt.bufPrint(&buf,
            \\{{"id":"{s}","status":"paused"}}
        , .{strategy_id}) catch return;
        try sendResponse(handle, id, true, data);
    } else if (std.mem.eql(u8, action, "strategy.resume")) {
        // Resume a paused strategy
        const params_val = root.get("params") orelse {
            try sendError(handle, id, "INVALID_PARAMS", "Missing 'params' field");
            return;
        };

        const params = switch (params_val) {
            .object => |obj| obj,
            else => {
                try sendError(handle, id, "INVALID_PARAMS", "'params' must be an object");
                return;
            },
        };

        const strategy_id = blk: {
            if (params.get("id")) |v| {
                if (v == .string) break :blk v.string;
            }
            try sendError(handle, id, "INVALID_PARAMS", "Missing 'id' field");
            return;
        };

        manager.resumeStrategy(strategy_id) catch |err| {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Failed to resume strategy: {s}", .{@errorName(err)}) catch "Resume failed";
            try sendError(handle, id, "RESUME_FAILED", msg);
            return;
        };

        var buf: [128]u8 = undefined;
        const data = std.fmt.bufPrint(&buf,
            \\{{"id":"{s}","status":"running"}}
        , .{strategy_id}) catch return;
        try sendResponse(handle, id, true, data);
    } else if (std.mem.eql(u8, action, "strategy.status")) {
        // Get strategy status
        const params_val = root.get("params") orelse {
            try sendError(handle, id, "INVALID_PARAMS", "Missing 'params' field");
            return;
        };

        const params = switch (params_val) {
            .object => |obj| obj,
            else => {
                try sendError(handle, id, "INVALID_PARAMS", "'params' must be an object");
                return;
            },
        };

        const strategy_id = blk: {
            if (params.get("id")) |v| {
                if (v == .string) break :blk v.string;
            }
            try sendError(handle, id, "INVALID_PARAMS", "Missing 'id' field");
            return;
        };

        const stats = manager.getStrategyStats(strategy_id) catch |err| {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Failed to get strategy status: {s}", .{@errorName(err)}) catch "Status failed";
            try sendError(handle, id, "STATUS_FAILED", msg);
            return;
        };

        const status = manager.getStrategyStatus(strategy_id) catch .stopped;

        var buf: [512]u8 = undefined;
        const data = std.fmt.bufPrint(&buf,
            \\{{"id":"{s}","status":"{s}","stats":{{"total_signals":{d},"total_trades":{d},"realized_pnl":{d:.4},"current_position":{d:.4},"win_rate":{d:.2}}}}}
        , .{
            strategy_id,
            status.toString(),
            stats.total_signals,
            stats.total_trades,
            stats.realized_pnl,
            stats.current_position,
            stats.win_rate,
        }) catch return;
        try sendResponse(handle, id, true, data);
    } else {
        try sendError(handle, id, "UNKNOWN_ACTION", "Unknown strategy action");
    }
}

fn handleSystemCommand(ctx: *WsContext, handle: zap.WebSockets.WsHandle, id: ?[]const u8, action: []const u8, root: std.json.ObjectMap) !void {
    _ = root;
    if (ctx.server.config.engine_manager == null) {
        try sendError(handle, id, "SERVICE_UNAVAILABLE", "Engine manager not configured");
        return;
    }

    const manager = ctx.server.config.engine_manager.?;

    if (std.mem.eql(u8, action, "system.kill_switch")) {
        // Activate kill switch
        const result = manager.activateKillSwitch("WebSocket command", true, true) catch |err| {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Failed to activate kill switch: {s}", .{@errorName(err)}) catch "Kill switch failed";
            try sendError(handle, id, "KILL_SWITCH_FAILED", msg);
            return;
        };

        var buf: [256]u8 = undefined;
        const data = std.fmt.bufPrint(&buf,
            \\{{"kill_switch":true,"strategies_stopped":{d}}}
        , .{result.strategies_stopped}) catch return;
        try sendResponse(handle, id, true, data);
    } else {
        try sendError(handle, id, "UNKNOWN_ACTION", "Unknown system action");
    }
}

// ============================================================================
// Response Helpers
// ============================================================================

fn sendError(handle: zap.WebSockets.WsHandle, id: ?[]const u8, code: []const u8, message: []const u8) !void {
    var buf: [512]u8 = undefined;
    const msg = if (id) |req_id|
        std.fmt.bufPrint(&buf,
            \\{{"type":"response","id":"{s}","timestamp":{d},"success":false,"error":{{"code":"{s}","message":"{s}"}}}}
        , .{ req_id, std.time.milliTimestamp(), code, message })
    else
        std.fmt.bufPrint(&buf,
            \\{{"type":"error","timestamp":{d},"error":{{"code":"{s}","message":"{s}"}}}}
        , .{ std.time.milliTimestamp(), code, message });

    WsHandler.write(handle, msg catch return, true) catch {};
}

fn sendResponse(handle: zap.WebSockets.WsHandle, id: ?[]const u8, success: bool, data: []const u8) !void {
    var buf: [1024]u8 = undefined;
    const msg = if (id) |req_id|
        std.fmt.bufPrint(&buf,
            \\{{"type":"response","id":"{s}","timestamp":{d},"success":{s},"data":{s}}}
        , .{ req_id, std.time.milliTimestamp(), if (success) "true" else "false", data })
    else
        std.fmt.bufPrint(&buf,
            \\{{"type":"response","timestamp":{d},"success":{s},"data":{s}}}
        , .{ std.time.milliTimestamp(), if (success) "true" else "false", data });

    WsHandler.write(handle, msg catch return, true) catch {};
}

fn sendAuthResult(handle: zap.WebSockets.WsHandle, success: bool, err_message: ?[]const u8) !void {
    var buf: [256]u8 = undefined;
    const msg = if (success)
        std.fmt.bufPrint(&buf,
            \\{{"type":"auth_result","timestamp":{d},"success":true}}
        , .{std.time.milliTimestamp()})
    else
        std.fmt.bufPrint(&buf,
            \\{{"type":"auth_result","timestamp":{d},"success":false,"error":"{s}"}}
        , .{ std.time.milliTimestamp(), err_message orelse "Authentication failed" });

    WsHandler.write(handle, msg catch return, true) catch {};
}

// ============================================================================
// Tests
// ============================================================================

test "matchWildcard" {
    try std.testing.expect(matchWildcard("*", "anything"));
    try std.testing.expect(matchWildcard("grid.*", "grid.abc"));
    try std.testing.expect(matchWildcard("grid.*", "grid.xyz"));
    try std.testing.expect(!matchWildcard("grid.*", "backtest.abc"));
    try std.testing.expect(matchWildcard("grid.*.status", "grid.abc.status"));
    try std.testing.expect(!matchWildcard("grid.*.status", "grid.abc.order"));
    try std.testing.expect(matchWildcard("system.health", "system.health"));
    try std.testing.expect(!matchWildcard("system.health", "system.log"));
}
