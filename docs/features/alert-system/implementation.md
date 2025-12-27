# AlertSystem - 实现细节

> 深入了解告警系统的内部实现

**最后更新**: 2025-12-27

---

## 数据结构

```zig
pub const AlertManager = struct {
    allocator: Allocator,
    channels: std.ArrayList(IAlertChannel),
    config: AlertConfig,
    history: std.ArrayList(AlertRecord),
    mutex: std.Thread.Mutex,

    // 统计
    total_alerts: u64,
    alerts_by_level: [5]u64,

    // 节流
    last_alert_time: std.StringHashMap(i64),
    throttle_window_ms: u64,
};

pub const Alert = struct {
    id: []const u8,
    level: AlertLevel,
    category: AlertCategory,
    title: []const u8,
    message: []const u8,
    timestamp: i64,
    source: []const u8,
    details: ?AlertDetails = null,
};
```

---

## 核心算法

### 发送告警

```zig
pub fn sendAlert(self: *Self, alert: Alert) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    // 1. 检查级别
    if (@intFromEnum(alert.level) < @intFromEnum(self.config.min_level)) {
        return;
    }

    // 2. 检查节流
    if (self.isThrottled(alert)) {
        return;
    }

    // 3. 检查静音时段
    if (self.isQuietHours() and @intFromEnum(alert.level) < @intFromEnum(self.config.quiet_hours_min_level)) {
        return;
    }

    // 4. 发送到各通道
    const channels = self.getChannelsForLevel(alert.level);
    for (self.channels.items) |channel| {
        for (channels) |target| {
            if (channel.getType() == target) {
                channel.send(alert) catch continue;
            }
        }
    }

    // 5. 更新统计
    self.total_alerts += 1;
    self.alerts_by_level[@intFromEnum(alert.level)] += 1;

    // 6. 记录历史
    try self.recordAlert(alert);

    // 7. 更新节流时间
    try self.last_alert_time.put(alert.id, std.time.milliTimestamp());
}
```

### 节流检查

```zig
fn isThrottled(self: *Self, alert: Alert) bool {
    if (self.last_alert_time.get(alert.id)) |last_time| {
        const now = std.time.milliTimestamp();
        return (now - last_time) < @as(i64, @intCast(self.throttle_window_ms));
    }
    return false;
}
```

### 静音时段

```zig
fn isQuietHours(self: *Self) bool {
    if (self.config.quiet_hours_start == null) return false;

    const now = std.time.timestamp();
    const hour: u8 = @intCast(@mod(@divFloor(now, 3600), 24));

    const start = self.config.quiet_hours_start.?;
    const end = self.config.quiet_hours_end.?;

    if (start < end) {
        return hour >= start and hour < end;
    } else {
        // 跨午夜
        return hour >= start or hour < end;
    }
}
```

---

## 通道实现

### Console

```zig
pub const ConsoleChannel = struct {
    config: ConsoleConfig,

    pub fn send(self: *Self, alert: Alert) !void {
        const color = self.getColor(alert.level);
        std.debug.print("{s}[{s}] {s}\x1b[0m\n", .{
            color, alert.level.toString(), alert.title,
        });
        std.debug.print("  {s}\n", .{alert.message});
    }

    fn getColor(level: AlertLevel) []const u8 {
        return switch (level) {
            .debug => "\x1b[37m",
            .info => "\x1b[36m",
            .warning => "\x1b[33m",
            .critical => "\x1b[31m",
            .emergency => "\x1b[35m",
        };
    }
};
```

### Telegram

```zig
pub const TelegramChannel = struct {
    bot_token: []const u8,
    chat_id: []const u8,

    pub fn send(self: *Self, alert: Alert) !void {
        const message = std.fmt.allocPrint(allocator,
            "{s} *{s}*\n\n{s}",
            .{ alert.level.emoji(), alert.title, alert.message },
        );
        defer allocator.free(message);

        // HTTP POST to Telegram API
        try self.httpPost("https://api.telegram.org/bot{s}/sendMessage", .{
            .chat_id = self.chat_id,
            .text = message,
            .parse_mode = "Markdown",
        });
    }
};
```

---

*完整实现请参考: `src/risk/alert.zig`*
