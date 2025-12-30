//! AlertManager - Alert and Notification System (Story 044)
//!
//! Multi-channel alert system for important events:
//! - Risk alerts: Drawdown, position exceeded
//! - Trade alerts: Stop loss, take profit, liquidation
//! - System alerts: Connection, errors, performance
//! - Strategy alerts: Signals, state changes

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;

/// Alert Manager - Multi-channel notification system
pub const AlertManager = struct {
    allocator: Allocator,
    channels: std.ArrayListUnmanaged(IAlertChannel),
    config: AlertConfig,
    history: std.ArrayListUnmanaged(Alert),
    mutex: std.Thread.Mutex,

    // Statistics
    total_alerts: u64,
    alerts_by_level: [5]u64, // By level

    // Throttle control
    last_alert_time: std.StringHashMap(i64),

    const Self = @This();

    pub fn init(allocator: Allocator, config: AlertConfig) Self {
        return .{
            .allocator = allocator,
            .channels = .{},
            .config = config,
            .history = .{},
            .mutex = .{},
            .total_alerts = 0,
            .alerts_by_level = .{ 0, 0, 0, 0, 0 },
            .last_alert_time = std.StringHashMap(i64).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.channels.deinit(self.allocator);
        self.history.deinit(self.allocator);

        // Free throttle keys - only if map has entries
        if (self.last_alert_time.count() > 0) {
            var iter = self.last_alert_time.iterator();
            while (iter.next()) |entry| {
                // Free the duplicated key string
                const key = entry.key_ptr.*;
                if (key.len > 0) {
                    self.allocator.free(key);
                }
            }
        }
        self.last_alert_time.deinit();
    }

    /// Add alert channel
    pub fn addChannel(self: *Self, channel: IAlertChannel) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.channels.append(self.allocator, channel);
    }

    /// Send alert
    pub fn sendAlert(self: *Self, alert: Alert) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 1. Check alert level
        if (@intFromEnum(alert.level) < @intFromEnum(self.config.min_level)) {
            return;
        }

        // 2. Check throttle
        if (self.isThrottled(alert.id)) {
            return;
        }

        // 3. Check quiet hours
        if (self.isQuietHours() and @intFromEnum(alert.level) < @intFromEnum(self.config.quiet_hours_min_level)) {
            return;
        }

        // 4. Send to all channels
        for (self.channels.items) |channel| {
            if (channel.isAvailable()) {
                channel.send(alert) catch |err| {
                    std.log.err("[ALERT] Channel send failed: {}", .{err});
                };
            }
        }

        // 5. Update statistics
        self.total_alerts += 1;
        self.alerts_by_level[@intFromEnum(alert.level)] += 1;

        // 6. Record history
        if (self.history.items.len >= self.config.max_history_size) {
            _ = self.history.orderedRemove(0);
        }
        try self.history.append(self.allocator, alert);

        // 7. Update throttle time
        const key = try self.allocator.dupe(u8, alert.id);
        if (try self.last_alert_time.fetchPut(key, std.time.milliTimestamp())) |old| {
            self.allocator.free(old.key);
        }
    }

    /// Check if throttled
    /// NOTE: Throttle temporarily disabled due to HashMap memory issue
    fn isThrottled(self: *Self, alert_id: []const u8) bool {
        _ = self;
        _ = alert_id;
        // Temporarily disabled to avoid segfault
        // TODO: Fix HashMap memory management
        return false;
    }

    /// Check if in quiet hours
    fn isQuietHours(self: *Self) bool {
        if (self.config.quiet_hours_start == null or self.config.quiet_hours_end == null) {
            return false;
        }

        const now = std.time.timestamp();
        const hour: u8 = @intCast(@mod(@divFloor(now, 3600), 24));

        const start = self.config.quiet_hours_start.?;
        const end = self.config.quiet_hours_end.?;

        if (start < end) {
            return hour >= start and hour < end;
        } else {
            // Crosses midnight
            return hour >= start or hour < end;
        }
    }

    // Convenience methods

    /// Send info alert
    pub fn info(self: *Self, title: []const u8, message: []const u8, source: []const u8) !void {
        try self.sendAlert(Alert{
            .id = title,
            .level = .info,
            .category = .system_connected,
            .title = title,
            .message = message,
            .timestamp = std.time.timestamp(),
            .source = source,
        });
    }

    /// Send warning alert
    pub fn warning(self: *Self, title: []const u8, message: []const u8, source: []const u8) !void {
        try self.sendAlert(Alert{
            .id = title,
            .level = .warning,
            .category = .system_error,
            .title = title,
            .message = message,
            .timestamp = std.time.timestamp(),
            .source = source,
        });
    }

    /// Send critical alert
    pub fn critical(self: *Self, title: []const u8, message: []const u8, source: []const u8) !void {
        try self.sendAlert(Alert{
            .id = title,
            .level = .critical,
            .category = .system_error,
            .title = title,
            .message = message,
            .timestamp = std.time.timestamp(),
            .source = source,
        });
    }

    /// Send emergency alert
    pub fn emergency(self: *Self, title: []const u8, message: []const u8, source: []const u8) !void {
        try self.sendAlert(Alert{
            .id = title,
            .level = .emergency,
            .category = .system_error,
            .title = title,
            .message = message,
            .timestamp = std.time.timestamp(),
            .source = source,
        });
    }

    /// Send risk alert
    pub fn riskAlert(self: *Self, category: AlertCategory, details: AlertDetails) !void {
        const title = switch (category) {
            .risk_position_exceeded => "Position Limit Exceeded",
            .risk_leverage_exceeded => "Leverage Limit Exceeded",
            .risk_daily_loss => "Daily Loss Limit Reached",
            .risk_drawdown => "Drawdown Alert",
            .risk_kill_switch => "Kill Switch Triggered",
            else => "Risk Alert",
        };

        try self.sendAlert(Alert{
            .id = @tagName(category),
            .level = .critical,
            .category = category,
            .title = title,
            .message = "Risk threshold breached",
            .timestamp = std.time.timestamp(),
            .source = "RiskEngine",
            .details = details,
        });
    }

    /// Send trade alert
    pub fn tradeAlert(self: *Self, category: AlertCategory, details: AlertDetails) !void {
        const title = switch (category) {
            .trade_executed => "Trade Executed",
            .trade_failed => "Trade Failed",
            .trade_stop_loss => "Stop Loss Triggered",
            .trade_take_profit => "Take Profit Triggered",
            .trade_liquidation => "Position Liquidated",
            else => "Trade Alert",
        };

        const level: AlertLevel = switch (category) {
            .trade_liquidation => .emergency,
            .trade_failed, .trade_stop_loss => .warning,
            else => .info,
        };

        try self.sendAlert(Alert{
            .id = @tagName(category),
            .level = level,
            .category = category,
            .title = title,
            .message = "Trade event occurred",
            .timestamp = std.time.timestamp(),
            .source = "TradeEngine",
            .details = details,
        });
    }

    /// Get alert statistics
    pub fn getStats(self: *Self) AlertStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return AlertStats{
            .total_alerts = self.total_alerts,
            .by_debug = self.alerts_by_level[0],
            .by_info = self.alerts_by_level[1],
            .by_warning = self.alerts_by_level[2],
            .by_critical = self.alerts_by_level[3],
            .by_emergency = self.alerts_by_level[4],
            .history_size = self.history.items.len,
            .channel_count = self.channels.items.len,
        };
    }

    /// Get recent alerts
    pub fn getRecentAlerts(self: *Self, count: usize) []const Alert {
        self.mutex.lock();
        defer self.mutex.unlock();

        const len = self.history.items.len;
        if (len == 0) return &[_]Alert{};

        const start = if (len > count) len - count else 0;
        return self.history.items[start..];
    }

    /// Clear alert history
    pub fn clearHistory(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.history.clearRetainingCapacity();
    }
};

/// Alert Configuration
pub const AlertConfig = struct {
    // Minimum alert level
    min_level: AlertLevel = .info,

    // Throttle configuration
    throttle_window_ms: u64 = 60000, // Same alert minimum interval (1 minute)
    max_alerts_per_hour: u32 = 100, // Max alerts per hour

    // History configuration
    max_history_size: usize = 1000,

    // Quiet hours (optional)
    quiet_hours_start: ?u8 = null, // e.g., 22 (10 PM)
    quiet_hours_end: ?u8 = null, // e.g., 8 (8 AM)
    quiet_hours_min_level: AlertLevel = .critical, // Only send this level+ during quiet hours

    pub fn default() AlertConfig {
        return .{};
    }
};

/// Alert Level
pub const AlertLevel = enum(u8) {
    debug = 0,
    info = 1,
    warning = 2,
    critical = 3,
    emergency = 4,

    pub fn toString(self: AlertLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warning => "WARNING",
            .critical => "CRITICAL",
            .emergency => "EMERGENCY",
        };
    }

    pub fn emoji(self: AlertLevel) []const u8 {
        return switch (self) {
            .debug => "[D]",
            .info => "[I]",
            .warning => "[W]",
            .critical => "[!]",
            .emergency => "[!!!]",
        };
    }
};

/// Channel Type
pub const ChannelType = enum {
    console,
    telegram,
    email,
    webhook,
    slack,
    discord,
};

/// Alert Message
pub const Alert = struct {
    id: []const u8, // Unique identifier (for throttling)
    level: AlertLevel,
    category: AlertCategory,
    title: []const u8,
    message: []const u8,
    timestamp: i64,
    source: []const u8, // Source module
    details: ?AlertDetails = null,
};

/// Alert Category
pub const AlertCategory = enum {
    // Risk
    risk_position_exceeded,
    risk_leverage_exceeded,
    risk_daily_loss,
    risk_drawdown,
    risk_kill_switch,

    // Trade
    trade_executed,
    trade_failed,
    trade_stop_loss,
    trade_take_profit,
    trade_liquidation,

    // System
    system_connected,
    system_disconnected,
    system_error,
    system_performance,
    system_memory,

    // Strategy
    strategy_started,
    strategy_stopped,
    strategy_signal,
    strategy_error,
};

/// Alert Details
pub const AlertDetails = struct {
    symbol: ?[]const u8 = null,
    price: ?Decimal = null,
    quantity: ?Decimal = null,
    pnl: ?Decimal = null,
    threshold: ?f64 = null,
    actual: ?f64 = null,
};

/// Alert Statistics
pub const AlertStats = struct {
    total_alerts: u64,
    by_debug: u64,
    by_info: u64,
    by_warning: u64,
    by_critical: u64,
    by_emergency: u64,
    history_size: usize,
    channel_count: usize,
};

/// Alert Channel Interface (VTable pattern)
pub const IAlertChannel = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        send: *const fn (ptr: *anyopaque, alert: Alert) anyerror!void,
        getType: *const fn (ptr: *anyopaque) ChannelType,
        isAvailable: *const fn (ptr: *anyopaque) bool,
    };

    pub fn send(self: IAlertChannel, alert: Alert) !void {
        return self.vtable.send(self.ptr, alert);
    }

    pub fn getType(self: IAlertChannel) ChannelType {
        return self.vtable.getType(self.ptr);
    }

    pub fn isAvailable(self: IAlertChannel) bool {
        return self.vtable.isAvailable(self.ptr);
    }
};

/// Console Alert Channel
pub const ConsoleChannel = struct {
    config: ConsoleConfig,

    const Self = @This();

    pub const ConsoleConfig = struct {
        colorize: bool = true,
        show_details: bool = true,
        show_timestamp: bool = true,
    };

    pub fn init(config: ConsoleConfig) Self {
        return .{ .config = config };
    }

    fn sendImpl(ptr: *anyopaque, alert: Alert) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const color = if (self.config.colorize) getColor(alert.level) else "";
        const reset = if (self.config.colorize) "\x1b[0m" else "";

        std.debug.print("{s}{s} [{s}] {s}{s}\n", .{
            color,
            alert.level.emoji(),
            alert.level.toString(),
            alert.title,
            reset,
        });
        std.debug.print("  {s}\n", .{alert.message});

        if (self.config.show_details) {
            if (alert.details) |d| {
                if (d.symbol) |s| std.debug.print("  Symbol: {s}\n", .{s});
                if (d.price) |p| {
                    const pf = p.toFloat();
                    std.debug.print("  Price: {d:.2}\n", .{pf});
                }
                if (d.pnl) |pnl| {
                    const pnlf = pnl.toFloat();
                    std.debug.print("  PnL: {d:.2}\n", .{pnlf});
                }
                if (d.threshold) |t| std.debug.print("  Threshold: {d:.4}\n", .{t});
                if (d.actual) |a| std.debug.print("  Actual: {d:.4}\n", .{a});
            }
        }

        if (self.config.show_timestamp) {
            std.debug.print("  Source: {s} | Time: {d}\n", .{ alert.source, alert.timestamp });
        }

        std.debug.print("\n", .{});
    }

    fn getColor(level: AlertLevel) []const u8 {
        return switch (level) {
            .debug => "\x1b[37m", // Gray
            .info => "\x1b[36m", // Cyan
            .warning => "\x1b[33m", // Yellow
            .critical => "\x1b[31m", // Red
            .emergency => "\x1b[35m", // Magenta
        };
    }

    fn getTypeImpl(_: *anyopaque) ChannelType {
        return .console;
    }

    fn isAvailableImpl(_: *anyopaque) bool {
        return true;
    }

    const vtable = IAlertChannel.VTable{
        .send = sendImpl,
        .getType = getTypeImpl,
        .isAvailable = isAvailableImpl,
    };

    pub fn asChannel(self: *Self) IAlertChannel {
        return .{ .ptr = self, .vtable = &vtable };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "AlertManager: initialization" {
    const allocator = std.testing.allocator;

    var manager = AlertManager.init(allocator, AlertConfig.default());
    defer manager.deinit();

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_alerts);
    try std.testing.expectEqual(@as(usize, 0), stats.channel_count);
}

test "AlertManager: add channel" {
    const allocator = std.testing.allocator;

    var manager = AlertManager.init(allocator, AlertConfig.default());
    defer manager.deinit();

    var console = ConsoleChannel.init(.{ .colorize = false, .show_details = false, .show_timestamp = false });
    try manager.addChannel(console.asChannel());

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.channel_count);
}

test "AlertManager: send alert" {
    const allocator = std.testing.allocator;

    var manager = AlertManager.init(allocator, AlertConfig.default());
    defer manager.deinit();

    // Use a mock channel that doesn't print
    const MockChannel = struct {
        alert_count: u32 = 0,

        fn sendImpl(ptr: *anyopaque, _: Alert) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.alert_count += 1;
        }

        fn getTypeImpl(_: *anyopaque) ChannelType {
            return .console;
        }

        fn isAvailableImpl(_: *anyopaque) bool {
            return true;
        }

        const vtable = IAlertChannel.VTable{
            .send = sendImpl,
            .getType = getTypeImpl,
            .isAvailable = isAvailableImpl,
        };

        fn asChannel(self: *@This()) IAlertChannel {
            return .{ .ptr = self, .vtable = &vtable };
        }
    };

    var mock = MockChannel{};
    try manager.addChannel(mock.asChannel());

    try manager.sendAlert(.{
        .id = "test-alert",
        .level = .info,
        .category = .system_connected,
        .title = "Test Alert",
        .message = "This is a test",
        .timestamp = std.time.timestamp(),
        .source = "test",
    });

    try std.testing.expectEqual(@as(u32, 1), mock.alert_count);

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.total_alerts);
    try std.testing.expectEqual(@as(u64, 1), stats.by_info);
}

test "AlertManager: throttling" {
    const allocator = std.testing.allocator;

    const config = AlertConfig{
        .throttle_window_ms = 60000, // 1 minute
    };

    var manager = AlertManager.init(allocator, config);
    defer manager.deinit();

    const MockChannel = struct {
        alert_count: u32 = 0,

        fn sendImpl(ptr: *anyopaque, _: Alert) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.alert_count += 1;
        }

        fn getTypeImpl(_: *anyopaque) ChannelType {
            return .console;
        }

        fn isAvailableImpl(_: *anyopaque) bool {
            return true;
        }

        const vtable = IAlertChannel.VTable{
            .send = sendImpl,
            .getType = getTypeImpl,
            .isAvailable = isAvailableImpl,
        };

        fn asChannel(self: *@This()) IAlertChannel {
            return .{ .ptr = self, .vtable = &vtable };
        }
    };

    var mock = MockChannel{};
    try manager.addChannel(mock.asChannel());

    // First alert should go through
    try manager.sendAlert(.{
        .id = "throttle-test",
        .level = .warning,
        .category = .system_error,
        .title = "Test",
        .message = "Test",
        .timestamp = std.time.timestamp(),
        .source = "test",
    });

    // Second alert with same ID should be throttled
    try manager.sendAlert(.{
        .id = "throttle-test",
        .level = .warning,
        .category = .system_error,
        .title = "Test",
        .message = "Test",
        .timestamp = std.time.timestamp(),
        .source = "test",
    });

    // Only first one should have been sent
    try std.testing.expectEqual(@as(u32, 1), mock.alert_count);
}

test "AlertManager: level filtering" {
    const allocator = std.testing.allocator;

    const config = AlertConfig{
        .min_level = .warning, // Only warning and above
    };

    var manager = AlertManager.init(allocator, config);
    defer manager.deinit();

    const MockChannel = struct {
        alert_count: u32 = 0,

        fn sendImpl(ptr: *anyopaque, _: Alert) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.alert_count += 1;
        }

        fn getTypeImpl(_: *anyopaque) ChannelType {
            return .console;
        }

        fn isAvailableImpl(_: *anyopaque) bool {
            return true;
        }

        const vtable = IAlertChannel.VTable{
            .send = sendImpl,
            .getType = getTypeImpl,
            .isAvailable = isAvailableImpl,
        };

        fn asChannel(self: *@This()) IAlertChannel {
            return .{ .ptr = self, .vtable = &vtable };
        }
    };

    var mock = MockChannel{};
    try manager.addChannel(mock.asChannel());

    // Info should be filtered
    try manager.sendAlert(.{
        .id = "info-test",
        .level = .info,
        .category = .system_connected,
        .title = "Info",
        .message = "Test",
        .timestamp = std.time.timestamp(),
        .source = "test",
    });

    // Warning should go through
    try manager.sendAlert(.{
        .id = "warning-test",
        .level = .warning,
        .category = .system_error,
        .title = "Warning",
        .message = "Test",
        .timestamp = std.time.timestamp(),
        .source = "test",
    });

    try std.testing.expectEqual(@as(u32, 1), mock.alert_count);
}

test "AlertManager: convenience methods" {
    const allocator = std.testing.allocator;

    var manager = AlertManager.init(allocator, AlertConfig.default());
    defer manager.deinit();

    const MockChannel = struct {
        alert_count: u32 = 0,

        fn sendImpl(ptr: *anyopaque, _: Alert) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.alert_count += 1;
        }

        fn getTypeImpl(_: *anyopaque) ChannelType {
            return .console;
        }

        fn isAvailableImpl(_: *anyopaque) bool {
            return true;
        }

        const vtable = IAlertChannel.VTable{
            .send = sendImpl,
            .getType = getTypeImpl,
            .isAvailable = isAvailableImpl,
        };

        fn asChannel(self: *@This()) IAlertChannel {
            return .{ .ptr = self, .vtable = &vtable };
        }
    };

    var mock = MockChannel{};
    try manager.addChannel(mock.asChannel());

    try manager.info("Info", "Test info", "test");
    try manager.warning("Warning", "Test warning", "test");
    try manager.critical("Critical", "Test critical", "test");

    // Each has unique title, so not throttled
    try std.testing.expectEqual(@as(u32, 3), mock.alert_count);

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.by_info);
    try std.testing.expectEqual(@as(u64, 1), stats.by_warning);
    try std.testing.expectEqual(@as(u64, 1), stats.by_critical);
}

test "AlertManager: history" {
    const allocator = std.testing.allocator;

    const config = AlertConfig{
        .max_history_size = 3,
    };

    var manager = AlertManager.init(allocator, config);
    defer manager.deinit();

    // Add 5 alerts (exceeds max history)
    for (0..5) |i| {
        var buf: [20]u8 = undefined;
        const id = std.fmt.bufPrint(&buf, "alert-{d}", .{i}) catch "alert";

        try manager.sendAlert(.{
            .id = id,
            .level = .info,
            .category = .system_connected,
            .title = id,
            .message = "Test",
            .timestamp = std.time.timestamp(),
            .source = "test",
        });
    }

    // Should only have 3 in history
    const stats = manager.getStats();
    try std.testing.expectEqual(@as(usize, 3), stats.history_size);

    // Clear history
    manager.clearHistory();
    try std.testing.expectEqual(@as(usize, 0), manager.getStats().history_size);
}

test "ConsoleChannel: basic" {
    var console = ConsoleChannel.init(.{
        .colorize = false,
        .show_details = false,
        .show_timestamp = false,
    });

    const channel = console.asChannel();
    try std.testing.expect(channel.isAvailable());
    try std.testing.expectEqual(ChannelType.console, channel.getType());
}

test "AlertLevel: toString" {
    try std.testing.expectEqualStrings("DEBUG", AlertLevel.debug.toString());
    try std.testing.expectEqualStrings("INFO", AlertLevel.info.toString());
    try std.testing.expectEqualStrings("WARNING", AlertLevel.warning.toString());
    try std.testing.expectEqualStrings("CRITICAL", AlertLevel.critical.toString());
    try std.testing.expectEqualStrings("EMERGENCY", AlertLevel.emergency.toString());
}
