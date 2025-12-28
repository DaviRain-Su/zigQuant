# 通知系统 - 实现细节

> 深入了解内部实现

**最后更新**: 2025-12-28

---

## 架构概述

```
┌─────────────────────────────────────────────────────────────┐
│                  Notification System                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │               AlertSystem                            │    │
│  │  ┌─────────────────────────────────────────────┐    │    │
│  │  │            Alert Queue                       │    │    │
│  │  └─────────────────────────────────────────────┘    │    │
│  │                      │                               │    │
│  │                      ▼                               │    │
│  │  ┌─────────────────────────────────────────────┐    │    │
│  │  │           Channel Router                     │    │    │
│  │  │  (routes alerts to appropriate channels)     │    │    │
│  │  └─────────────────────────────────────────────┘    │    │
│  └──────────────────────│──────────────────────────────┘    │
│                         │                                    │
│         ┌───────────────┼───────────────┐                   │
│         │               │               │                   │
│         ▼               ▼               ▼                   │
│  ┌───────────┐  ┌───────────┐  ┌───────────────────┐       │
│  │ Telegram  │  │   Email   │  │     Webhook       │       │
│  │  Channel  │  │  Channel  │  │     Channel       │       │
│  └─────┬─────┘  └─────┬─────┘  └─────────┬─────────┘       │
│        │              │                   │                  │
│        ▼              ▼                   ▼                  │
│  ┌───────────┐  ┌───────────┐  ┌───────────────────┐       │
│  │ Telegram  │  │ SendGrid/ │  │  Custom Webhook   │       │
│  │  Bot API  │  │  Mailgun  │  │    Endpoint       │       │
│  └───────────┘  └───────────┘  └───────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

---

## IAlertChannel 接口

### 现有定义 (src/risk/alert.zig)

```zig
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

pub const ChannelType = enum {
    telegram,
    email,
    webhook,
    log,
};
```

---

## TelegramChannel 实现

### 数据结构

```zig
// src/risk/channels/telegram.zig
const std = @import("std");
const http = std.http;

pub const TelegramChannel = struct {
    allocator: std.mem.Allocator,
    bot_token: []const u8,
    chat_id: []const u8,
    http_client: http.Client,
    rate_limiter: RateLimiter,
    min_level: AlertLevel,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: TelegramConfig) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .bot_token = try allocator.dupe(u8, config.bot_token),
            .chat_id = try allocator.dupe(u8, config.chat_id),
            .http_client = http.Client{ .allocator = allocator },
            .rate_limiter = RateLimiter.init(config.rate_limit_per_minute),
            .min_level = config.min_level,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.bot_token);
        self.allocator.free(self.chat_id);
        self.http_client.deinit();
        self.allocator.destroy(self);
    }
};

pub const TelegramConfig = struct {
    bot_token: []const u8,
    chat_id: []const u8,
    min_level: AlertLevel = .warning,
    rate_limit_per_minute: u32 = 30,
};
```

### 发送实现

```zig
fn sendImpl(ptr: *anyopaque, alert: Alert) !void {
    const self: *TelegramChannel = @ptrCast(@alignCast(ptr));

    // 检查最低级别
    if (@intFromEnum(alert.level) < @intFromEnum(self.min_level)) {
        return;
    }

    // 检查速率限制
    if (!self.rate_limiter.tryAcquire()) {
        return error.RateLimited;
    }

    // 格式化消息
    const message = try self.formatMessage(alert);
    defer self.allocator.free(message);

    // 构建 API URL
    const url = try std.fmt.allocPrint(
        self.allocator,
        "https://api.telegram.org/bot{s}/sendMessage",
        .{self.bot_token},
    );
    defer self.allocator.free(url);

    // 构建请求体
    const body = try std.json.stringifyAlloc(self.allocator, .{
        .chat_id = self.chat_id,
        .text = message,
        .parse_mode = "HTML",
    }, .{});
    defer self.allocator.free(body);

    // 发送请求
    var request = try self.http_client.open(.POST, try std.Uri.parse(url), .{
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        },
    });
    defer request.deinit();

    request.transfer_encoding = .{ .content_length = body.len };
    try request.send();
    try request.writer().writeAll(body);
    try request.finish();
    try request.wait();

    if (request.status != .ok) {
        return error.TelegramApiError;
    }
}

fn formatMessage(self: *TelegramChannel, alert: Alert) ![]const u8 {
    const level_emoji = switch (alert.level) {
        .info => "ℹ️",
        .warning => "⚠️",
        .critical => "🚨",
    };

    return std.fmt.allocPrint(self.allocator,
        \\<b>{s} {s}</b>
        \\
        \\{s}
        \\
        \\<i>Strategy: {s}</i>
        \\<i>Time: {s}</i>
    , .{
        level_emoji,
        alert.title,
        alert.message,
        alert.strategy orelse "N/A",
        formatTimestamp(alert.timestamp),
    });
}

const vtable = IAlertChannel.VTable{
    .send = sendImpl,
    .getType = getTypeImpl,
    .isAvailable = isAvailableImpl,
};

pub fn asChannel(self: *TelegramChannel) IAlertChannel {
    return .{ .ptr = self, .vtable = &vtable };
}

fn getTypeImpl(ptr: *anyopaque) ChannelType {
    _ = ptr;
    return .telegram;
}

fn isAvailableImpl(ptr: *anyopaque) bool {
    const self: *TelegramChannel = @ptrCast(@alignCast(ptr));
    return self.bot_token.len > 0 and self.chat_id.len > 0;
}
```

---

## EmailChannel 实现

### 数据结构

```zig
// src/risk/channels/email.zig
const std = @import("std");
const http = std.http;

pub const EmailChannel = struct {
    allocator: std.mem.Allocator,
    provider: EmailProvider,
    api_key: []const u8,
    from_address: []const u8,
    to_addresses: std.ArrayList([]const u8),
    http_client: http.Client,
    rate_limiter: RateLimiter,
    min_level: AlertLevel,

    const Self = @This();

    pub const EmailProvider = enum {
        sendgrid,
        mailgun,
        resend,
    };

    pub fn init(allocator: std.mem.Allocator, config: EmailConfig) !*Self {
        const self = try allocator.create(Self);

        var to_list = std.ArrayList([]const u8).init(allocator);
        for (config.to_addresses) |addr| {
            try to_list.append(try allocator.dupe(u8, addr));
        }

        self.* = .{
            .allocator = allocator,
            .provider = config.provider,
            .api_key = try allocator.dupe(u8, config.api_key),
            .from_address = try allocator.dupe(u8, config.from_address),
            .to_addresses = to_list,
            .http_client = http.Client{ .allocator = allocator },
            .rate_limiter = RateLimiter.init(config.rate_limit_per_minute),
            .min_level = config.min_level,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.api_key);
        self.allocator.free(self.from_address);
        for (self.to_addresses.items) |addr| {
            self.allocator.free(addr);
        }
        self.to_addresses.deinit();
        self.http_client.deinit();
        self.allocator.destroy(self);
    }
};

pub const EmailConfig = struct {
    provider: EmailChannel.EmailProvider = .sendgrid,
    api_key: []const u8,
    from_address: []const u8,
    to_addresses: []const []const u8,
    min_level: AlertLevel = .critical,
    rate_limit_per_minute: u32 = 10,
};
```

### 发送实现

```zig
fn sendImpl(ptr: *anyopaque, alert: Alert) !void {
    const self: *EmailChannel = @ptrCast(@alignCast(ptr));

    // 检查最低级别
    if (@intFromEnum(alert.level) < @intFromEnum(self.min_level)) {
        return;
    }

    // 检查速率限制
    if (!self.rate_limiter.tryAcquire()) {
        return error.RateLimited;
    }

    // 格式化主题和正文
    const subject = try self.formatSubject(alert);
    defer self.allocator.free(subject);

    const body = try self.formatBody(alert);
    defer self.allocator.free(body);

    // 根据 provider 发送
    switch (self.provider) {
        .sendgrid => try self.sendViaSendGrid(subject, body),
        .mailgun => try self.sendViaMailgun(subject, body),
        .resend => try self.sendViaResend(subject, body),
    }
}

fn sendViaSendGrid(self: *EmailChannel, subject: []const u8, body: []const u8) !void {
    // 构建收件人列表
    var personalizations = std.ArrayList(struct { to: []const struct { email: []const u8 } }).init(self.allocator);
    defer personalizations.deinit();

    for (self.to_addresses.items) |addr| {
        try personalizations.append(.{
            .to = &[_]struct { email: []const u8 }{.{ .email = addr }},
        });
    }

    const payload = try std.json.stringifyAlloc(self.allocator, .{
        .personalizations = personalizations.items,
        .from = .{ .email = self.from_address },
        .subject = subject,
        .content = &[_]struct { type: []const u8, value: []const u8 }{
            .{ .type = "text/html", .value = body },
        },
    }, .{});
    defer self.allocator.free(payload);

    var request = try self.http_client.open(
        .POST,
        try std.Uri.parse("https://api.sendgrid.com/v3/mail/send"),
        .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
                .{ .name = "Authorization", .value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key}) },
            },
        },
    );
    defer request.deinit();

    request.transfer_encoding = .{ .content_length = payload.len };
    try request.send();
    try request.writer().writeAll(payload);
    try request.finish();
    try request.wait();

    if (request.status != .accepted and request.status != .ok) {
        return error.SendGridApiError;
    }
}

fn formatSubject(self: *EmailChannel, alert: Alert) ![]const u8 {
    const level_str = switch (alert.level) {
        .info => "INFO",
        .warning => "WARNING",
        .critical => "CRITICAL",
    };

    return std.fmt.allocPrint(self.allocator, "[zigQuant {s}] {s}", .{
        level_str,
        alert.title,
    });
}

fn formatBody(self: *EmailChannel, alert: Alert) ![]const u8 {
    const level_color = switch (alert.level) {
        .info => "#17a2b8",
        .warning => "#ffc107",
        .critical => "#dc3545",
    };

    return std.fmt.allocPrint(self.allocator,
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <style>
        \\    .alert {{ border-left: 4px solid {s}; padding: 16px; background: #f8f9fa; }}
        \\    .title {{ font-size: 18px; font-weight: bold; color: {s}; }}
        \\    .message {{ margin: 16px 0; color: #333; }}
        \\    .meta {{ font-size: 12px; color: #666; }}
        \\  </style>
        \\</head>
        \\<body>
        \\  <div class="alert">
        \\    <div class="title">{s}</div>
        \\    <div class="message">{s}</div>
        \\    <div class="meta">
        \\      Strategy: {s}<br>
        \\      Time: {s}
        \\    </div>
        \\  </div>
        \\</body>
        \\</html>
    , .{
        level_color,
        level_color,
        alert.title,
        alert.message,
        alert.strategy orelse "N/A",
        formatTimestamp(alert.timestamp),
    });
}
```

---

## RateLimiter 实现

```zig
// src/risk/channels/rate_limiter.zig
const std = @import("std");

pub const RateLimiter = struct {
    tokens: u32,
    max_tokens: u32,
    last_refill: i64,
    refill_rate: u32,  // tokens per minute

    const Self = @This();

    pub fn init(max_per_minute: u32) Self {
        return .{
            .tokens = max_per_minute,
            .max_tokens = max_per_minute,
            .last_refill = std.time.timestamp(),
            .refill_rate = max_per_minute,
        };
    }

    pub fn tryAcquire(self: *Self) bool {
        self.refill();

        if (self.tokens > 0) {
            self.tokens -= 1;
            return true;
        }
        return false;
    }

    fn refill(self: *Self) void {
        const now = std.time.timestamp();
        const elapsed = now - self.last_refill;

        if (elapsed >= 60) {
            // 每分钟完全补充
            self.tokens = self.max_tokens;
            self.last_refill = now;
        } else if (elapsed > 0) {
            // 线性补充
            const new_tokens = @as(u32, @intCast(elapsed)) * self.refill_rate / 60;
            self.tokens = @min(self.tokens + new_tokens, self.max_tokens);
            if (new_tokens > 0) {
                self.last_refill = now;
            }
        }
    }
};
```

---

## AlertManager 集成

```zig
// src/risk/alert.zig
pub const AlertManager = struct {
    allocator: std.mem.Allocator,
    channels: std.ArrayList(IAlertChannel),
    alert_queue: std.ArrayList(Alert),
    thread: ?std.Thread,
    running: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator) AlertManager {
        return .{
            .allocator = allocator,
            .channels = std.ArrayList(IAlertChannel).init(allocator),
            .alert_queue = std.ArrayList(Alert).init(allocator),
            .thread = null,
            .running = std.atomic.Value(bool).init(false),
        };
    }

    pub fn addChannel(self: *AlertManager, channel: IAlertChannel) !void {
        try self.channels.append(channel);
    }

    pub fn sendAlert(self: *AlertManager, alert: Alert) !void {
        // 异步发送到所有渠道
        try self.alert_queue.append(alert);

        // 通知工作线程
        if (self.thread == null) {
            self.startWorker();
        }
    }

    fn startWorker(self: *AlertManager) void {
        self.running.store(true, .release);
        self.thread = std.Thread.spawn(.{}, workerLoop, .{self}) catch null;
    }

    fn workerLoop(self: *AlertManager) void {
        while (self.running.load(.acquire)) {
            if (self.alert_queue.popOrNull()) |alert| {
                for (self.channels.items) |channel| {
                    if (channel.isAvailable()) {
                        channel.send(alert) catch |err| {
                            std.log.err("Failed to send alert via {}: {}", .{
                                channel.getType(),
                                err,
                            });
                        };
                    }
                }
            } else {
                std.time.sleep(100 * std.time.ns_per_ms);
            }
        }
    }
};
```

---

## 配置加载

```zig
// src/config/notifications.zig
pub const NotificationsConfig = struct {
    telegram: ?TelegramConfig = null,
    email: ?EmailConfig = null,
    webhooks: []const WebhookConfig = &.{},

    pub fn parse(json: std.json.Value) !NotificationsConfig {
        // JSON 解析逻辑
    }
};

// config.json 示例
// {
//   "notifications": {
//     "telegram": {
//       "bot_token": "123456:ABC-DEF...",
//       "chat_id": "-100123456789",
//       "min_level": "warning"
//     },
//     "email": {
//       "provider": "sendgrid",
//       "api_key": "SG.xxx",
//       "from_address": "alerts@example.com",
//       "to_addresses": ["admin@example.com"],
//       "min_level": "critical"
//     }
//   }
// }
```

---

## 错误处理

```zig
pub const NotificationError = error{
    RateLimited,
    TelegramApiError,
    SendGridApiError,
    MailgunApiError,
    ResendApiError,
    NetworkError,
    InvalidConfiguration,
};

fn handleError(err: NotificationError, channel_type: ChannelType) void {
    switch (err) {
        .RateLimited => {
            std.log.warn("Rate limited on {} channel", .{channel_type});
        },
        .TelegramApiError, .SendGridApiError => {
            std.log.err("API error on {} channel", .{channel_type});
            // 可以实现指数退避重试
        },
        .NetworkError => {
            std.log.err("Network error, will retry", .{});
        },
        else => {},
    }
}
```

---

## 重试机制

```zig
const RetryConfig = struct {
    max_retries: u32 = 3,
    initial_delay_ms: u64 = 1000,
    max_delay_ms: u64 = 30000,
    backoff_multiplier: f64 = 2.0,
};

fn sendWithRetry(
    channel: IAlertChannel,
    alert: Alert,
    config: RetryConfig,
) !void {
    var delay = config.initial_delay_ms;

    for (0..config.max_retries) |attempt| {
        channel.send(alert) catch |err| {
            if (attempt == config.max_retries - 1) {
                return err;
            }

            std.log.warn("Retry {}/{} after {}ms", .{
                attempt + 1,
                config.max_retries,
                delay,
            });

            std.time.sleep(delay * std.time.ns_per_ms);
            delay = @min(
                @as(u64, @intFromFloat(@as(f64, @floatFromInt(delay)) * config.backoff_multiplier)),
                config.max_delay_ms,
            );
            continue;
        };
        return;
    }
}
```

---

*Last updated: 2025-12-28*
