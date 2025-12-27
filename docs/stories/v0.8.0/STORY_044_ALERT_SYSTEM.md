# Story 044: 告警和通知系统

**版本**: v0.8.0
**状态**: 📋 规划中
**优先级**: P2 (重要)
**预计时间**: 2-3 天
**依赖**: Story 043 (风险指标监控)
**参考**: 企业告警系统最佳实践

---

## 目标

实现多渠道告警系统，在重要事件发生时及时通知用户，确保交易者能够快速响应市场变化和系统异常。

## 背景

在自动化交易中，及时的告警通知至关重要:
1. **风险告警**: 回撤超限、仓位异常
2. **交易告警**: 大额成交、止损触发
3. **系统告警**: 连接断开、性能异常
4. **策略告警**: 信号触发、状态变化

支持多渠道通知，用户可以根据告警级别选择不同的通知方式。

---

## 核心功能

### 1. 告警管理器

```zig
/// 告警管理器
pub const AlertManager = struct {
    allocator: Allocator,
    channels: std.ArrayList(IAlertChannel),
    config: AlertConfig,
    history: std.ArrayList(AlertRecord),
    mutex: std.Thread.Mutex,

    // 统计
    total_alerts: u64,
    alerts_by_level: [5]u64,  // 按级别统计

    // 节流控制
    last_alert_time: std.StringHashMap(i64),
    throttle_window_ms: u64,

    const Self = @This();

    pub fn init(allocator: Allocator, config: AlertConfig) Self {
        return .{
            .allocator = allocator,
            .channels = std.ArrayList(IAlertChannel).init(allocator),
            .config = config,
            .history = std.ArrayList(AlertRecord).init(allocator),
            .mutex = .{},
            .total_alerts = 0,
            .alerts_by_level = .{ 0, 0, 0, 0, 0 },
            .last_alert_time = std.StringHashMap(i64).init(allocator),
            .throttle_window_ms = config.throttle_window_ms,
        };
    }

    pub fn deinit(self: *Self) void {
        self.channels.deinit();
        self.history.deinit();
        self.last_alert_time.deinit();
    }
};
```

### 2. 告警配置

```zig
/// 告警配置
pub const AlertConfig = struct {
    // 启用的告警级别
    min_level: AlertLevel = .info,

    // 节流配置
    throttle_window_ms: u64 = 60000,  // 同类告警最小间隔 (1分钟)
    max_alerts_per_hour: u32 = 100,    // 每小时最大告警数

    // 通道选择
    channel_by_level: struct {
        debug: []const ChannelType = &.{.console},
        info: []const ChannelType = &.{.console},
        warning: []const ChannelType = &.{ .console, .telegram },
        critical: []const ChannelType = &.{ .console, .telegram, .email },
        emergency: []const ChannelType = &.{ .console, .telegram, .email, .webhook },
    } = .{},

    // 历史记录
    max_history_size: usize = 1000,

    // 静音时段 (可选)
    quiet_hours_start: ?u8 = null,  // 例如 22 (晚上10点)
    quiet_hours_end: ?u8 = null,    // 例如 8 (早上8点)
    quiet_hours_min_level: AlertLevel = .critical,  // 静音时段只发送此级别以上
};

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
            .debug => "🔍",
            .info => "ℹ️",
            .warning => "⚠️",
            .critical => "🚨",
            .emergency => "🆘",
        };
    }
};

pub const ChannelType = enum {
    console,
    telegram,
    email,
    webhook,
    slack,
    discord,
};
```

### 3. 告警消息

```zig
/// 告警消息
pub const Alert = struct {
    id: []const u8,             // 唯一标识
    level: AlertLevel,
    category: AlertCategory,
    title: []const u8,
    message: []const u8,
    timestamp: i64,
    source: []const u8,         // 来源模块
    details: ?AlertDetails = null,
    tags: ?[]const []const u8 = null,

    pub fn format(self: Alert) []const u8 {
        // 格式化为可读消息
        return std.fmt.allocPrint(self.allocator,
            "{s} [{s}] {s}\n{s}\n\nSource: {s}\nTime: {s}",
            .{
                self.level.emoji(),
                self.level.toString(),
                self.title,
                self.message,
                self.source,
                formatTimestamp(self.timestamp),
            },
        ) catch "";
    }
};

pub const AlertCategory = enum {
    // 风险类
    risk_position_exceeded,
    risk_leverage_exceeded,
    risk_daily_loss,
    risk_drawdown,
    risk_kill_switch,

    // 交易类
    trade_executed,
    trade_failed,
    trade_stop_loss,
    trade_take_profit,
    trade_liquidation,

    // 系统类
    system_connected,
    system_disconnected,
    system_error,
    system_performance,
    system_memory,

    // 策略类
    strategy_started,
    strategy_stopped,
    strategy_signal,
    strategy_error,
};

pub const AlertDetails = struct {
    symbol: ?[]const u8 = null,
    price: ?Decimal = null,
    quantity: ?Decimal = null,
    pnl: ?Decimal = null,
    threshold: ?f64 = null,
    actual: ?f64 = null,
    extra: ?std.json.ObjectMap = null,
};

pub const AlertRecord = struct {
    alert: Alert,
    sent_to: []const ChannelType,
    success: bool,
    error_message: ?[]const u8 = null,
};
```

### 4. 发送告警

```zig
/// 发送告警
pub fn sendAlert(self: *Self, alert: Alert) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    // 1. 检查告警级别
    if (@intFromEnum(alert.level) < @intFromEnum(self.config.min_level)) {
        return;
    }

    // 2. 检查节流
    if (self.isThrottled(alert)) {
        std.log.debug("[ALERT] Throttled: {s}", .{alert.id});
        return;
    }

    // 3. 检查静音时段
    if (self.isQuietHours() and @intFromEnum(alert.level) < @intFromEnum(self.config.quiet_hours_min_level)) {
        std.log.debug("[ALERT] Quiet hours: {s}", .{alert.id});
        return;
    }

    // 4. 确定发送通道
    const channels = self.getChannelsForLevel(alert.level);

    // 5. 发送到各通道
    var sent_to = std.ArrayList(ChannelType).init(self.allocator);
    defer sent_to.deinit();

    for (self.channels.items) |channel| {
        for (channels) |target| {
            if (channel.getType() == target) {
                channel.send(alert) catch |err| {
                    std.log.err("[ALERT] Failed to send via {s}: {}", .{ @tagName(target), err });
                    continue;
                };
                try sent_to.append(target);
            }
        }
    }

    // 6. 更新统计
    self.total_alerts += 1;
    self.alerts_by_level[@intFromEnum(alert.level)] += 1;

    // 7. 记录历史
    try self.recordAlert(alert, sent_to.items);

    // 8. 更新节流时间
    try self.last_alert_time.put(alert.id, std.time.milliTimestamp());

    std.log.info("[ALERT] Sent: {s} ({s})", .{ alert.title, alert.level.toString() });
}

/// 检查是否被节流
fn isThrottled(self: *Self, alert: Alert) bool {
    if (self.last_alert_time.get(alert.id)) |last_time| {
        const now = std.time.milliTimestamp();
        return (now - last_time) < @as(i64, @intCast(self.throttle_window_ms));
    }
    return false;
}

/// 检查是否在静音时段
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
        // 跨午夜
        return hour >= start or hour < end;
    }
}
```

### 5. 告警通道接口

```zig
/// 告警通道接口 (VTable 模式)
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
```

### 6. Console 通道

```zig
/// Console 告警通道
pub const ConsoleChannel = struct {
    config: ConsoleConfig,

    const Self = @This();

    pub const ConsoleConfig = struct {
        colorize: bool = true,
        show_details: bool = true,
    };

    pub fn init(config: ConsoleConfig) Self {
        return .{ .config = config };
    }

    pub fn send(self: *Self, alert: Alert) !void {
        const color = if (self.config.colorize) self.getColor(alert.level) else "";
        const reset = if (self.config.colorize) "\x1b[0m" else "";

        std.debug.print("{s}[{s}] {s}{s}\n", .{
            color,
            alert.level.toString(),
            alert.title,
            reset,
        });
        std.debug.print("  {s}\n", .{alert.message});

        if (self.config.show_details and alert.details != null) {
            const d = alert.details.?;
            if (d.symbol) |s| std.debug.print("  Symbol: {s}\n", .{s});
            if (d.price) |p| std.debug.print("  Price: {d}\n", .{p.toFloat()});
            if (d.pnl) |pnl| std.debug.print("  PnL: {d}\n", .{pnl.toFloat()});
        }
    }

    fn getColor(self: *Self, level: AlertLevel) []const u8 {
        _ = self;
        return switch (level) {
            .debug => "\x1b[37m",    // 灰色
            .info => "\x1b[36m",     // 青色
            .warning => "\x1b[33m",  // 黄色
            .critical => "\x1b[31m", // 红色
            .emergency => "\x1b[35m", // 紫色
        };
    }

    const vtable = IAlertChannel.VTable{
        .send = @ptrCast(&send),
        .getType = getType,
        .isAvailable = isAvailable,
    };

    fn getType(ptr: *anyopaque) ChannelType {
        _ = ptr;
        return .console;
    }

    fn isAvailable(ptr: *anyopaque) bool {
        _ = ptr;
        return true;
    }

    pub fn asChannel(self: *Self) IAlertChannel {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
```

### 7. Telegram 通道

```zig
/// Telegram 告警通道
pub const TelegramChannel = struct {
    allocator: Allocator,
    bot_token: []const u8,
    chat_id: []const u8,
    http_client: *std.http.Client,

    const Self = @This();

    pub fn init(allocator: Allocator, bot_token: []const u8, chat_id: []const u8) !Self {
        const client = try allocator.create(std.http.Client);
        client.* = std.http.Client{ .allocator = allocator };
        return .{
            .allocator = allocator,
            .bot_token = bot_token,
            .chat_id = chat_id,
            .http_client = client,
        };
    }

    pub fn deinit(self: *Self) void {
        self.http_client.deinit();
        self.allocator.destroy(self.http_client);
    }

    pub fn send(self: *Self, alert: Alert) !void {
        // 构建消息
        const message = try std.fmt.allocPrint(self.allocator,
            \\{s} *{s}*
            \\
            \\{s}
            \\
            \\`{s}` | `{s}`
        , .{
            alert.level.emoji(),
            escapeMarkdown(alert.title),
            escapeMarkdown(alert.message),
            alert.source,
            formatTimestamp(alert.timestamp),
        });
        defer self.allocator.free(message);

        // 发送 HTTP 请求
        const url = try std.fmt.allocPrint(self.allocator,
            "https://api.telegram.org/bot{s}/sendMessage",
            .{self.bot_token},
        );
        defer self.allocator.free(url);

        const body = try std.json.stringifyAlloc(self.allocator, .{
            .chat_id = self.chat_id,
            .text = message,
            .parse_mode = "Markdown",
        });
        defer self.allocator.free(body);

        var request = try self.http_client.request(.POST, try std.Uri.parse(url), .{}, null);
        defer request.deinit();

        request.headers.content_type = .{ .value = "application/json" };
        try request.send(body);
        try request.finish();
        try request.wait();

        if (request.status != .ok) {
            return error.TelegramSendFailed;
        }
    }

    const vtable = IAlertChannel.VTable{
        .send = @ptrCast(&send),
        .getType = getType,
        .isAvailable = isAvailable,
    };

    fn getType(ptr: *anyopaque) ChannelType {
        _ = ptr;
        return .telegram;
    }

    fn isAvailable(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.bot_token.len > 0 and self.chat_id.len > 0;
    }

    pub fn asChannel(self: *Self) IAlertChannel {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
```

### 8. Webhook 通道

```zig
/// Webhook 告警通道
pub const WebhookChannel = struct {
    allocator: Allocator,
    url: []const u8,
    http_client: *std.http.Client,
    headers: ?std.StringHashMap([]const u8) = null,

    const Self = @This();

    pub fn init(allocator: Allocator, url: []const u8) !Self {
        const client = try allocator.create(std.http.Client);
        client.* = std.http.Client{ .allocator = allocator };
        return .{
            .allocator = allocator,
            .url = url,
            .http_client = client,
        };
    }

    pub fn deinit(self: *Self) void {
        self.http_client.deinit();
        self.allocator.destroy(self.http_client);
        if (self.headers) |*h| h.deinit();
    }

    pub fn send(self: *Self, alert: Alert) !void {
        // 构建 JSON payload
        const payload = try std.json.stringifyAlloc(self.allocator, .{
            .id = alert.id,
            .level = alert.level.toString(),
            .category = @tagName(alert.category),
            .title = alert.title,
            .message = alert.message,
            .timestamp = alert.timestamp,
            .source = alert.source,
        });
        defer self.allocator.free(payload);

        var request = try self.http_client.request(.POST, try std.Uri.parse(self.url), .{}, null);
        defer request.deinit();

        request.headers.content_type = .{ .value = "application/json" };

        // 添加自定义 headers
        if (self.headers) |h| {
            var it = h.iterator();
            while (it.next()) |entry| {
                try request.headers.append(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        try request.send(payload);
        try request.finish();
        try request.wait();

        if (request.status != .ok and request.status != .accepted) {
            return error.WebhookSendFailed;
        }
    }

    const vtable = IAlertChannel.VTable{
        .send = @ptrCast(&send),
        .getType = getType,
        .isAvailable = isAvailable,
    };

    fn getType(ptr: *anyopaque) ChannelType {
        _ = ptr;
        return .webhook;
    }

    fn isAvailable(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.url.len > 0;
    }

    pub fn asChannel(self: *Self) IAlertChannel {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
```

### 9. 便捷方法

```zig
/// 添加通道
pub fn addChannel(self: *Self, channel: IAlertChannel) !void {
    try self.channels.append(channel);
}

/// 快捷告警方法
pub fn info(self: *Self, title: []const u8, message: []const u8, source: []const u8) !void {
    try self.sendAlert(Alert{
        .id = generateId(),
        .level = .info,
        .category = .system_info,
        .title = title,
        .message = message,
        .timestamp = std.time.timestamp(),
        .source = source,
    });
}

pub fn warning(self: *Self, title: []const u8, message: []const u8, source: []const u8) !void {
    try self.sendAlert(Alert{
        .id = generateId(),
        .level = .warning,
        .category = .system_warning,
        .title = title,
        .message = message,
        .timestamp = std.time.timestamp(),
        .source = source,
    });
}

pub fn critical(self: *Self, title: []const u8, message: []const u8, source: []const u8) !void {
    try self.sendAlert(Alert{
        .id = generateId(),
        .level = .critical,
        .category = .system_error,
        .title = title,
        .message = message,
        .timestamp = std.time.timestamp(),
        .source = source,
    });
}

/// 风险告警
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
        .id = generateId(),
        .level = .critical,
        .category = category,
        .title = title,
        .message = "Risk threshold breached",
        .timestamp = std.time.timestamp(),
        .source = "RiskEngine",
        .details = details,
    });
}

/// 获取告警统计
pub fn getStats(self: *Self) AlertStats {
    return AlertStats{
        .total_alerts = self.total_alerts,
        .by_debug = self.alerts_by_level[0],
        .by_info = self.alerts_by_level[1],
        .by_warning = self.alerts_by_level[2],
        .by_critical = self.alerts_by_level[3],
        .by_emergency = self.alerts_by_level[4],
        .history_size = self.history.items.len,
    };
}

pub const AlertStats = struct {
    total_alerts: u64,
    by_debug: u64,
    by_info: u64,
    by_warning: u64,
    by_critical: u64,
    by_emergency: u64,
    history_size: usize,
};
```

---

## 实现任务

### Task 1: 实现 AlertManager 核心
- [ ] 告警配置
- [ ] 通道管理
- [ ] 发送逻辑
- [ ] 节流控制

### Task 2: 实现 Console 通道
- [ ] 格式化输出
- [ ] 颜色支持

### Task 3: 实现 Telegram 通道
- [ ] HTTP 请求
- [ ] 消息格式化
- [ ] 错误处理

### Task 4: 实现 Webhook 通道
- [ ] JSON 序列化
- [ ] 自定义 Headers
- [ ] 重试逻辑

### Task 5: 实现便捷方法
- [ ] 快捷告警方法
- [ ] 风险告警
- [ ] 统计功能

### Task 6: 单元测试
- [ ] 发送逻辑测试
- [ ] 节流测试
- [ ] 静音时段测试
- [ ] 通道测试

---

## 验收标准

### 功能
- [ ] 多通道告警正常工作
- [ ] 节流控制生效
- [ ] 静音时段正确处理
- [ ] 历史记录完整

### 性能
- [ ] 告警发送 < 100ms (本地)
- [ ] 不阻塞主线程

### 测试
- [ ] 各通道独立测试
- [ ] 集成测试

---

## 示例代码

```zig
const std = @import("std");
const AlertManager = @import("risk").AlertManager;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建告警管理器
    var alerts = AlertManager.init(allocator, .{
        .min_level = .info,
        .throttle_window_ms = 30000,
    });
    defer alerts.deinit();

    // 添加通道
    var console = ConsoleChannel.init(.{ .colorize = true });
    try alerts.addChannel(console.asChannel());

    // 如果配置了 Telegram
    if (std.os.getenv("TELEGRAM_BOT_TOKEN")) |token| {
        if (std.os.getenv("TELEGRAM_CHAT_ID")) |chat_id| {
            var telegram = try TelegramChannel.init(allocator, token, chat_id);
            try alerts.addChannel(telegram.asChannel());
        }
    }

    // 发送告警
    try alerts.info("System Started", "Trading system initialized", "main");
    try alerts.warning("High Volatility", "Market volatility is above normal", "MarketMonitor");

    // 风险告警
    try alerts.riskAlert(.risk_drawdown, .{
        .actual = 0.08,
        .threshold = 0.10,
    });
}
```

---

## 相关文档

- [v0.8.0 Overview](./OVERVIEW.md)
- [Story 043: 风险指标监控](./STORY_043_RISK_METRICS.md)
- [Story 045: Crash Recovery](./STORY_045_CRASH_RECOVERY.md)

---

**Story ID**: STORY-044
**状态**: 📋 规划中
**创建时间**: 2025-12-27
