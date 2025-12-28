# Story 052: Telegram/Email 通知

**Story ID**: STORY-052
**版本**: v1.0.0
**优先级**: P1
**状态**: 📋 待开始
**依赖**: 无 (可与 Story 047 并行开发)

---

## 概述

扩展现有 AlertSystem，实现 Telegram Bot 和 Email (Webhook) 通知渠道，支持多级别告警路由和消息模板。

### 目标

1. Telegram Bot 消息推送
2. Email 通知 (SendGrid/Mailgun/Resend Webhook)
3. 告警级别路由
4. 消息模板支持
5. 发送频率限制 (防止告警风暴)
6. 通知延迟 < 5s

---

## 现有架构

### IAlertChannel 接口 (src/risk/alert.zig)

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
};

pub const ChannelType = enum {
    console,
    log,
    telegram,
    email,
    webhook,
};

pub const Alert = struct {
    level: AlertLevel,
    title: []const u8,
    message: []const u8,
    timestamp: i64,
    metadata: ?std.StringHashMap([]const u8),
};

pub const AlertLevel = enum {
    info,
    warning,
    critical,
};
```

---

## 文件结构

```
src/risk/channels/
├── mod.zig              # 模块导出
├── telegram.zig         # Telegram 通知
├── email.zig            # Email 通知 (Webhook)
└── rate_limiter.zig     # 频率限制器
```

---

## TelegramChannel 实现

### telegram.zig

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const alert = @import("../alert.zig");
const IAlertChannel = alert.IAlertChannel;
const Alert = alert.Alert;
const AlertLevel = alert.AlertLevel;
const ChannelType = alert.ChannelType;

pub const TelegramChannel = struct {
    allocator: Allocator,
    bot_token: []const u8,
    chat_id: []const u8,
    min_level: AlertLevel,
    rate_limiter: RateLimiter,

    const Self = @This();

    pub fn init(allocator: Allocator, config: TelegramConfig) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .bot_token = try allocator.dupe(u8, config.bot_token),
            .chat_id = try allocator.dupe(u8, config.chat_id),
            .min_level = config.min_level,
            .rate_limiter = RateLimiter.init(config.rate_limit_per_minute),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.bot_token);
        self.allocator.free(self.chat_id);
        self.allocator.destroy(self);
    }

    fn sendImpl(ptr: *anyopaque, alert_msg: Alert) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // 检查告警级别
        if (@intFromEnum(alert_msg.level) < @intFromEnum(self.min_level)) {
            return;
        }

        // 检查频率限制
        if (!self.rate_limiter.allow()) {
            std.log.warn("Telegram rate limit exceeded, skipping alert", .{});
            return;
        }

        // 格式化消息
        const message = try self.formatMessage(alert_msg);
        defer self.allocator.free(message);

        // 发送到 Telegram
        try self.sendToTelegram(message);
    }

    fn formatMessage(self: *Self, alert_msg: Alert) ![]const u8 {
        const level_emoji = switch (alert_msg.level) {
            .info => "ℹ️",
            .warning => "⚠️",
            .critical => "🚨",
        };

        const level_name = switch (alert_msg.level) {
            .info => "INFO",
            .warning => "WARNING",
            .critical => "CRITICAL",
        };

        return try std.fmt.allocPrint(self.allocator,
            \\{s} <b>[{s}] {s}</b>
            \\
            \\{s}
            \\
            \\<i>Time: {s}</i>
        , .{
            level_emoji,
            level_name,
            alert_msg.title,
            alert_msg.message,
            formatTimestamp(alert_msg.timestamp),
        });
    }

    fn sendToTelegram(self: *Self, message: []const u8) !void {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const url = try std.fmt.allocPrint(self.allocator,
            "https://api.telegram.org/bot{s}/sendMessage",
            .{self.bot_token}
        );
        defer self.allocator.free(url);

        // 构建请求体
        var body_buf: [4096]u8 = undefined;
        const body = try std.json.stringifyAlloc(self.allocator, .{
            .chat_id = self.chat_id,
            .text = message,
            .parse_mode = "HTML",
            .disable_web_page_preview = true,
        }, .{});
        defer self.allocator.free(body);

        // 发送 POST 请求
        var request = try client.request(.POST, try std.Uri.parse(url), .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
            },
        }, .{});
        defer request.deinit();

        request.transfer_encoding = .{ .content_length = body.len };
        try request.send();
        try request.writer().writeAll(body);
        try request.finish();
        try request.wait();

        if (request.status != .ok) {
            std.log.err("Telegram API error: {d}", .{@intFromEnum(request.status)});
            return error.TelegramApiError;
        }

        std.log.info("Telegram notification sent successfully", .{});
    }

    fn getTypeImpl(ptr: *anyopaque) ChannelType {
        _ = ptr;
        return .telegram;
    }

    fn isAvailableImpl(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.bot_token.len > 0 and self.chat_id.len > 0;
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

pub const TelegramConfig = struct {
    bot_token: []const u8,
    chat_id: []const u8,
    min_level: AlertLevel = .warning,
    rate_limit_per_minute: u32 = 30,
};

fn formatTimestamp(timestamp: i64) []const u8 {
    // 简化实现
    return "2024-12-28 10:00:00 UTC";
}
```

---

## EmailChannel 实现 (Webhook)

### email.zig

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const alert = @import("../alert.zig");
const IAlertChannel = alert.IAlertChannel;
const Alert = alert.Alert;
const AlertLevel = alert.AlertLevel;
const ChannelType = alert.ChannelType;

pub const EmailChannel = struct {
    allocator: Allocator,
    provider: EmailProvider,
    api_key: []const u8,
    from_address: []const u8,
    to_addresses: []const []const u8,
    min_level: AlertLevel,
    rate_limiter: RateLimiter,

    pub const EmailProvider = enum {
        sendgrid,
        mailgun,
        resend,
    };

    const Self = @This();

    pub fn init(allocator: Allocator, config: EmailConfig) !*Self {
        const self = try allocator.create(Self);

        // 复制 to_addresses
        var to_list = try allocator.alloc([]const u8, config.to_addresses.len);
        for (config.to_addresses, 0..) |addr, i| {
            to_list[i] = try allocator.dupe(u8, addr);
        }

        self.* = .{
            .allocator = allocator,
            .provider = config.provider,
            .api_key = try allocator.dupe(u8, config.api_key),
            .from_address = try allocator.dupe(u8, config.from_address),
            .to_addresses = to_list,
            .min_level = config.min_level,
            .rate_limiter = RateLimiter.init(config.rate_limit_per_minute),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.api_key);
        self.allocator.free(self.from_address);
        for (self.to_addresses) |addr| {
            self.allocator.free(addr);
        }
        self.allocator.free(self.to_addresses);
        self.allocator.destroy(self);
    }

    fn sendImpl(ptr: *anyopaque, alert_msg: Alert) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // 检查告警级别
        if (@intFromEnum(alert_msg.level) < @intFromEnum(self.min_level)) {
            return;
        }

        // 检查频率限制
        if (!self.rate_limiter.allow()) {
            std.log.warn("Email rate limit exceeded, skipping alert", .{});
            return;
        }

        // 构建邮件
        const subject = try self.formatSubject(alert_msg);
        defer self.allocator.free(subject);

        const body = try self.formatBody(alert_msg);
        defer self.allocator.free(body);

        // 根据 provider 发送
        switch (self.provider) {
            .sendgrid => try self.sendViaSendGrid(subject, body),
            .mailgun => try self.sendViaMailgun(subject, body),
            .resend => try self.sendViaResend(subject, body),
        }
    }

    fn formatSubject(self: *Self, alert_msg: Alert) ![]const u8 {
        const level_str = switch (alert_msg.level) {
            .info => "INFO",
            .warning => "WARNING",
            .critical => "CRITICAL",
        };

        return try std.fmt.allocPrint(self.allocator,
            "[zigQuant {s}] {s}",
            .{level_str, alert_msg.title}
        );
    }

    fn formatBody(self: *Self, alert_msg: Alert) ![]const u8 {
        const level_color = switch (alert_msg.level) {
            .info => "#3498db",
            .warning => "#f39c12",
            .critical => "#e74c3c",
        };

        return try std.fmt.allocPrint(self.allocator,
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\  <style>
            \\    body {{ font-family: Arial, sans-serif; }}
            \\    .alert {{ padding: 20px; border-left: 4px solid {s}; background: #f9f9f9; }}
            \\    .title {{ font-size: 18px; font-weight: bold; color: {s}; }}
            \\    .message {{ margin-top: 10px; color: #333; }}
            \\    .footer {{ margin-top: 20px; font-size: 12px; color: #999; }}
            \\  </style>
            \\</head>
            \\<body>
            \\  <div class="alert">
            \\    <div class="title">{s}</div>
            \\    <div class="message">{s}</div>
            \\  </div>
            \\  <div class="footer">
            \\    This alert was sent by zigQuant Trading System.
            \\  </div>
            \\</body>
            \\</html>
        , .{
            level_color,
            level_color,
            alert_msg.title,
            alert_msg.message,
        });
    }

    fn sendViaSendGrid(self: *Self, subject: []const u8, body: []const u8) !void {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // 构建 SendGrid 请求
        var personalizations = std.ArrayList(struct { to: []const struct { email: []const u8 } }).init(self.allocator);
        defer personalizations.deinit();

        var to_list = std.ArrayList(struct { email: []const u8 }).init(self.allocator);
        defer to_list.deinit();

        for (self.to_addresses) |addr| {
            try to_list.append(.{ .email = addr });
        }

        const payload = .{
            .personalizations = &[_]struct { to: []const struct { email: []const u8 } }{
                .{ .to = to_list.items },
            },
            .from = .{ .email = self.from_address },
            .subject = subject,
            .content = &[_]struct { @"type": []const u8, value: []const u8 }{
                .{ .@"type" = "text/html", .value = body },
            },
        };

        const payload_json = try std.json.stringifyAlloc(self.allocator, payload, .{});
        defer self.allocator.free(payload_json);

        // 发送请求
        const uri = try std.Uri.parse("https://api.sendgrid.com/v3/mail/send");
        var request = try client.request(.POST, uri, .{
            .extra_headers = &.{
                .{ .name = "Authorization", .value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key}) },
                .{ .name = "Content-Type", .value = "application/json" },
            },
        }, .{});
        defer request.deinit();

        request.transfer_encoding = .{ .content_length = payload_json.len };
        try request.send();
        try request.writer().writeAll(payload_json);
        try request.finish();
        try request.wait();

        if (request.status != .accepted and request.status != .ok) {
            std.log.err("SendGrid API error: {d}", .{@intFromEnum(request.status)});
            return error.EmailApiError;
        }

        std.log.info("Email notification sent via SendGrid", .{});
    }

    fn sendViaMailgun(self: *Self, subject: []const u8, body: []const u8) !void {
        // Mailgun 实现类似
        _ = self;
        _ = subject;
        _ = body;
        return error.NotImplemented;
    }

    fn sendViaResend(self: *Self, subject: []const u8, body: []const u8) !void {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var to_list = std.ArrayList([]const u8).init(self.allocator);
        defer to_list.deinit();
        for (self.to_addresses) |addr| {
            try to_list.append(addr);
        }

        const payload = .{
            .from = self.from_address,
            .to = to_list.items,
            .subject = subject,
            .html = body,
        };

        const payload_json = try std.json.stringifyAlloc(self.allocator, payload, .{});
        defer self.allocator.free(payload_json);

        const uri = try std.Uri.parse("https://api.resend.com/emails");
        var request = try client.request(.POST, uri, .{
            .extra_headers = &.{
                .{ .name = "Authorization", .value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key}) },
                .{ .name = "Content-Type", .value = "application/json" },
            },
        }, .{});
        defer request.deinit();

        request.transfer_encoding = .{ .content_length = payload_json.len };
        try request.send();
        try request.writer().writeAll(payload_json);
        try request.finish();
        try request.wait();

        if (request.status != .ok) {
            std.log.err("Resend API error: {d}", .{@intFromEnum(request.status)});
            return error.EmailApiError;
        }

        std.log.info("Email notification sent via Resend", .{});
    }

    fn getTypeImpl(ptr: *anyopaque) ChannelType {
        _ = ptr;
        return .email;
    }

    fn isAvailableImpl(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.api_key.len > 0 and self.to_addresses.len > 0;
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

pub const EmailConfig = struct {
    provider: EmailChannel.EmailProvider = .sendgrid,
    api_key: []const u8,
    from_address: []const u8,
    to_addresses: []const []const u8,
    min_level: AlertLevel = .critical,
    rate_limit_per_minute: u32 = 10,
};
```

---

## RateLimiter 实现

### rate_limiter.zig

```zig
const std = @import("std");

pub const RateLimiter = struct {
    max_per_minute: u32,
    tokens: u32,
    last_refill: i64,

    const Self = @This();

    pub fn init(max_per_minute: u32) Self {
        return .{
            .max_per_minute = max_per_minute,
            .tokens = max_per_minute,
            .last_refill = std.time.timestamp(),
        };
    }

    pub fn allow(self: *Self) bool {
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
            self.tokens = self.max_per_minute;
            self.last_refill = now;
        } else if (elapsed > 0) {
            // 按比例补充
            const to_add = @as(u32, @intCast(@divFloor(elapsed * self.max_per_minute, 60)));
            self.tokens = @min(self.tokens + to_add, self.max_per_minute);
            self.last_refill = now;
        }
    }
};
```

---

## 集成到 AlertManager

### src/risk/alert.zig 修改

```zig
const TelegramChannel = @import("channels/telegram.zig").TelegramChannel;
const EmailChannel = @import("channels/email.zig").EmailChannel;

pub const AlertManager = struct {
    allocator: Allocator,
    channels: std.ArrayList(IAlertChannel),

    pub fn init(allocator: Allocator) !*AlertManager {
        const self = try allocator.create(AlertManager);
        self.* = .{
            .allocator = allocator,
            .channels = std.ArrayList(IAlertChannel).init(allocator),
        };
        return self;
    }

    pub fn addTelegram(self: *AlertManager, config: TelegramChannel.TelegramConfig) !void {
        const channel = try TelegramChannel.init(self.allocator, config);
        try self.channels.append(channel.asChannel());
    }

    pub fn addEmail(self: *AlertManager, config: EmailChannel.EmailConfig) !void {
        const channel = try EmailChannel.init(self.allocator, config);
        try self.channels.append(channel.asChannel());
    }

    pub fn alert(self: *AlertManager, level: AlertLevel, title: []const u8, message: []const u8) void {
        const alert_msg = Alert{
            .level = level,
            .title = title,
            .message = message,
            .timestamp = std.time.timestamp(),
            .metadata = null,
        };

        for (self.channels.items) |channel| {
            channel.send(alert_msg) catch |err| {
                std.log.err("Failed to send alert via {s}: {}", .{
                    @tagName(channel.vtable.getType(channel.ptr)),
                    err,
                });
            };
        }
    }
};
```

---

## 配置示例

### config.json

```json
{
  "notifications": {
    "telegram": {
      "enabled": true,
      "bot_token": "123456789:ABCdefGHIjklMNOpqrsTUVwxyz",
      "chat_id": "-1001234567890",
      "min_level": "warning",
      "rate_limit_per_minute": 30
    },
    "email": {
      "enabled": true,
      "provider": "sendgrid",
      "api_key": "SG.xxxx",
      "from": "alerts@example.com",
      "to": ["admin@example.com", "trader@example.com"],
      "min_level": "critical",
      "rate_limit_per_minute": 10
    }
  }
}
```

---

## 测试

### 单元测试

```zig
test "TelegramChannel formats message correctly" {
    const allocator = std.testing.allocator;

    const config = TelegramConfig{
        .bot_token = "test-token",
        .chat_id = "test-chat",
        .min_level = .info,
    };

    var channel = try TelegramChannel.init(allocator, config);
    defer channel.deinit();

    const alert_msg = Alert{
        .level = .warning,
        .title = "Test Alert",
        .message = "This is a test",
        .timestamp = 1735344000,
        .metadata = null,
    };

    const message = try channel.formatMessage(alert_msg);
    defer allocator.free(message);

    try std.testing.expect(std.mem.indexOf(u8, message, "WARNING") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "Test Alert") != null);
}

test "RateLimiter limits correctly" {
    var limiter = RateLimiter.init(5);

    // 前 5 次应该允许
    for (0..5) |_| {
        try std.testing.expect(limiter.allow());
    }

    // 第 6 次应该被限制
    try std.testing.expect(!limiter.allow());
}
```

### 集成测试

```bash
# 测试 Telegram 通知
curl -X POST http://localhost:8080/api/v1/test/telegram \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test notification"}'

# 测试 Email 通知
curl -X POST http://localhost:8080/api/v1/test/email \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test email"}'
```

---

## 验收标准

### 功能要求

- [ ] Telegram Bot 消息发送成功
- [ ] Email 通知发送成功 (SendGrid)
- [ ] Email 通知发送成功 (Resend)
- [ ] 告警级别路由正确
- [ ] 消息格式化正确 (HTML)
- [ ] 频率限制生效

### 性能要求

- [ ] 通知延迟 < 5s
- [ ] 频率限制正确 (30/min Telegram, 10/min Email)
- [ ] 无内存泄漏

### 质量要求

- [ ] 单元测试覆盖
- [ ] 错误处理完善
- [ ] 日志记录完整

---

## 相关文档

- [v1.0.0 Overview](./OVERVIEW.md)
- [通知系统文档](../../features/notifications/README.md)

---

*最后更新: 2025-12-28*
