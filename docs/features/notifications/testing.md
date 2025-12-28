# 通知系统 - 测试文档

> 测试覆盖和验证

**最后更新**: 2025-12-28

---

## 测试概览

| 类别 | 测试数 | 覆盖率 |
|------|--------|--------|
| 单元测试 | TBD | TBD |
| 集成测试 | TBD | TBD |
| E2E 测试 | TBD | TBD |

---

## 单元测试

### RateLimiter 测试

```zig
const std = @import("std");
const testing = std.testing;
const RateLimiter = @import("channels").RateLimiter;

test "RateLimiter allows requests within limit" {
    var limiter = RateLimiter.init(10);  // 10 per minute

    // 前 10 个请求应该成功
    for (0..10) |_| {
        try testing.expect(limiter.tryAcquire());
    }

    // 第 11 个应该失败
    try testing.expect(!limiter.tryAcquire());
}

test "RateLimiter refills over time" {
    var limiter = RateLimiter.init(10);

    // 消耗所有 tokens
    for (0..10) |_| {
        _ = limiter.tryAcquire();
    }

    // 模拟时间流逝 (需要 mock 时间)
    // 60 秒后应该完全恢复
    limiter.last_refill = std.time.timestamp() - 60;
    limiter.refill();

    try testing.expectEqual(@as(u32, 10), limiter.tokens);
}

test "RateLimiter partial refill" {
    var limiter = RateLimiter.init(60);  // 60 per minute = 1 per second

    // 消耗所有
    for (0..60) |_| {
        _ = limiter.tryAcquire();
    }

    // 30 秒后应该恢复约 30 个
    limiter.last_refill = std.time.timestamp() - 30;
    limiter.refill();

    try testing.expect(limiter.tokens >= 29 and limiter.tokens <= 31);
}
```

### Alert 格式化测试

```zig
test "formatTelegramMessage includes all fields" {
    const alert = Alert{
        .level = .critical,
        .title = "Max Drawdown Exceeded",
        .message = "Drawdown reached 15%, exceeding 10% limit",
        .strategy = "sma_cross",
        .timestamp = 1703750400,
    };

    const message = try formatTelegramMessage(testing.allocator, alert);
    defer testing.allocator.free(message);

    try testing.expect(std.mem.indexOf(u8, message, "🚨") != null);
    try testing.expect(std.mem.indexOf(u8, message, "Max Drawdown Exceeded") != null);
    try testing.expect(std.mem.indexOf(u8, message, "15%") != null);
    try testing.expect(std.mem.indexOf(u8, message, "sma_cross") != null);
}

test "formatEmailSubject includes level and title" {
    const alert = Alert{
        .level = .warning,
        .title = "Position Size Alert",
        .message = "Large position detected",
        .strategy = null,
        .timestamp = 0,
    };

    const subject = try formatEmailSubject(testing.allocator, alert);
    defer testing.allocator.free(subject);

    try testing.expectEqualStrings("[zigQuant WARNING] Position Size Alert", subject);
}

test "formatEmailBody is valid HTML" {
    const alert = Alert{
        .level = .info,
        .title = "Test",
        .message = "Test message",
        .strategy = "test",
        .timestamp = 0,
    };

    const body = try formatEmailBody(testing.allocator, alert);
    defer testing.allocator.free(body);

    try testing.expect(std.mem.indexOf(u8, body, "<!DOCTYPE html>") != null);
    try testing.expect(std.mem.indexOf(u8, body, "</html>") != null);
}
```

### TelegramChannel 测试

```zig
test "TelegramChannel.init validates config" {
    const allocator = testing.allocator;

    // 有效配置
    const channel = try TelegramChannel.init(allocator, .{
        .bot_token = "123456:ABC-DEF",
        .chat_id = "-100123456789",
    });
    defer channel.deinit();

    try testing.expect(channel.isAvailable());
}

test "TelegramChannel respects min_level" {
    const allocator = testing.allocator;

    var channel = try TelegramChannel.init(allocator, .{
        .bot_token = "123456:ABC-DEF",
        .chat_id = "-100123456789",
        .min_level = .critical,
    });
    defer channel.deinit();

    // info 级别应该被过滤
    const info_alert = Alert{
        .level = .info,
        .title = "Info",
        .message = "Info message",
        .strategy = null,
        .timestamp = 0,
    };

    // 这个应该静默返回，不发送
    try channel.asChannel().send(info_alert);

    // 实际发送需要 mock HTTP client
}
```

### EmailChannel 测试

```zig
test "EmailChannel.init with SendGrid" {
    const allocator = testing.allocator;

    const channel = try EmailChannel.init(allocator, .{
        .provider = .sendgrid,
        .api_key = "SG.test_key",
        .from_address = "alerts@test.com",
        .to_addresses = &.{"admin@test.com"},
    });
    defer channel.deinit();

    try testing.expect(channel.provider == .sendgrid);
    try testing.expect(channel.isAvailable());
}

test "EmailChannel handles multiple recipients" {
    const allocator = testing.allocator;

    const channel = try EmailChannel.init(allocator, .{
        .provider = .sendgrid,
        .api_key = "SG.test_key",
        .from_address = "alerts@test.com",
        .to_addresses = &.{ "admin1@test.com", "admin2@test.com", "admin3@test.com" },
    });
    defer channel.deinit();

    try testing.expectEqual(@as(usize, 3), channel.to_addresses.items.len);
}
```

### AlertManager 测试

```zig
test "AlertManager routes to all channels" {
    const allocator = testing.allocator;

    var manager = AlertManager.init(allocator);
    defer manager.deinit();

    // 添加 mock channels
    var mock1 = MockChannel.init();
    var mock2 = MockChannel.init();

    try manager.addChannel(mock1.asChannel());
    try manager.addChannel(mock2.asChannel());

    const alert = Alert{
        .level = .warning,
        .title = "Test",
        .message = "Test",
        .strategy = null,
        .timestamp = 0,
    };

    try manager.sendAlert(alert);

    // 等待异步处理
    std.time.sleep(100 * std.time.ns_per_ms);

    try testing.expectEqual(@as(u32, 1), mock1.send_count);
    try testing.expectEqual(@as(u32, 1), mock2.send_count);
}

const MockChannel = struct {
    send_count: u32 = 0,

    fn sendImpl(ptr: *anyopaque, alert: Alert) !void {
        _ = alert;
        const self: *MockChannel = @ptrCast(@alignCast(ptr));
        self.send_count += 1;
    }

    fn asChannel(self: *MockChannel) IAlertChannel {
        return .{
            .ptr = self,
            .vtable = &.{
                .send = sendImpl,
                .getType = getTypeImpl,
                .isAvailable = isAvailableImpl,
            },
        };
    }
};
```

---

## 集成测试

### Telegram API 测试

```bash
#!/bin/bash
# test_telegram.sh

BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID}"

echo "Testing Telegram notification..."

# 发送测试消息
response=$(curl -s -X POST \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"${CHAT_ID}\",
    \"text\": \"<b>Test Alert</b>\n\nThis is a test message from zigQuant.\",
    \"parse_mode\": \"HTML\"
  }")

# 检查响应
ok=$(echo "$response" | jq -r '.ok')

if [ "$ok" = "true" ]; then
    echo "PASS: Telegram message sent successfully"
else
    echo "FAIL: Telegram API error"
    echo "$response" | jq
    exit 1
fi
```

### SendGrid API 测试

```bash
#!/bin/bash
# test_sendgrid.sh

API_KEY="${SENDGRID_API_KEY}"
FROM_EMAIL="${FROM_EMAIL}"
TO_EMAIL="${TO_EMAIL}"

echo "Testing SendGrid notification..."

response=$(curl -s -w "%{http_code}" -X POST \
  "https://api.sendgrid.com/v3/mail/send" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"personalizations\": [{\"to\": [{\"email\": \"${TO_EMAIL}\"}]}],
    \"from\": {\"email\": \"${FROM_EMAIL}\"},
    \"subject\": \"[zigQuant TEST] Integration Test\",
    \"content\": [{\"type\": \"text/plain\", \"value\": \"This is a test email.\"}]
  }")

status_code="${response: -3}"

if [ "$status_code" = "202" ]; then
    echo "PASS: SendGrid email sent successfully"
else
    echo "FAIL: SendGrid API error (status: $status_code)"
    echo "$response"
    exit 1
fi
```

### 端到端测试

```zig
// tests/integration/notifications_e2e.zig
test "e2e: send alert to all configured channels" {
    // 需要真实的配置和网络
    if (!isIntegrationTestEnabled()) {
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    // 加载配置
    const config = try loadTestConfig(allocator);
    defer config.deinit();

    // 初始化 AlertManager
    var manager = AlertManager.init(allocator);
    defer manager.deinit();

    // 添加 Telegram channel
    if (config.telegram) |tg_config| {
        const tg = try TelegramChannel.init(allocator, tg_config);
        try manager.addChannel(tg.asChannel());
    }

    // 添加 Email channel
    if (config.email) |email_config| {
        const email = try EmailChannel.init(allocator, email_config);
        try manager.addChannel(email.asChannel());
    }

    // 发送测试 alert
    const alert = Alert{
        .level = .info,
        .title = "E2E Test",
        .message = "This is an automated integration test.",
        .strategy = "test",
        .timestamp = std.time.timestamp(),
    };

    try manager.sendAlert(alert);

    // 等待发送完成
    std.time.sleep(5 * std.time.ns_per_s);

    // 验证 (可以通过检查日志或返回值)
    std.log.info("E2E test completed, check your notification channels", .{});
}
```

---

## 性能测试

### 吞吐量测试

```zig
pub fn benchmarkAlertThroughput() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = AlertManager.init(allocator);
    defer manager.deinit();

    // 添加 mock channel
    var mock = MockChannel.init();
    manager.addChannel(mock.asChannel()) catch unreachable;

    const iterations = 10000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        manager.sendAlert(.{
            .level = .info,
            .title = "Bench",
            .message = "Benchmark message",
            .strategy = null,
            .timestamp = 0,
        }) catch {};
    }

    // 等待队列清空
    while (manager.alert_queue.items.len > 0) {
        std.time.sleep(10 * std.time.ns_per_ms);
    }

    const elapsed = std.time.nanoTimestamp() - start;
    const ms_total = @as(f64, @floatFromInt(elapsed)) / 1_000_000.0;
    const alerts_per_sec = @as(f64, @floatFromInt(iterations)) / (ms_total / 1000.0);

    std.debug.print("Throughput: {d:.0} alerts/sec\n", .{alerts_per_sec});
}
```

### 延迟测试

```zig
pub fn benchmarkAlertLatency() void {
    // 测试从发送到实际发送的延迟
    var latencies = std.ArrayList(i64).init(allocator);
    defer latencies.deinit();

    for (0..100) |_| {
        const start = std.time.nanoTimestamp();

        // 同步发送
        channel.send(alert) catch {};

        const elapsed = std.time.nanoTimestamp() - start;
        latencies.append(elapsed) catch {};
    }

    // 计算 p50, p95, p99
    std.sort.sort(i64, latencies.items, {}, std.sort.asc(i64));

    const p50 = latencies.items[49];
    const p95 = latencies.items[94];
    const p99 = latencies.items[98];

    std.debug.print("Latency p50: {d:.2}ms, p95: {d:.2}ms, p99: {d:.2}ms\n", .{
        @as(f64, @floatFromInt(p50)) / 1_000_000.0,
        @as(f64, @floatFromInt(p95)) / 1_000_000.0,
        @as(f64, @floatFromInt(p99)) / 1_000_000.0,
    });
}
```

---

## 测试用例

### 正常情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| Telegram 发送 | 成功发送 Telegram 消息 | 📋 待实现 |
| Email 发送 | 成功发送邮件 | 📋 待实现 |
| 多渠道路由 | Alert 发送到所有渠道 | 📋 待实现 |
| 级别过滤 | 低于 min_level 被过滤 | 📋 待实现 |
| 格式化正确 | 消息格式正确 | 📋 待实现 |

### 边界情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 速率限制 | 超限时正确处理 | 📋 待实现 |
| 长消息 | 处理超长消息 | 📋 待实现 |
| 特殊字符 | HTML 转义正确 | 📋 待实现 |
| 空策略 | strategy 为 null | 📋 待实现 |

### 错误情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 网络错误 | 处理连接失败 | 📋 待实现 |
| API 错误 | 处理 API 返回错误 | 📋 待实现 |
| 无效配置 | 配置验证 | 📋 待实现 |
| 重试机制 | 失败后重试 | 📋 待实现 |

---

## 运行测试

```bash
# 运行所有测试
zig build test

# 运行通知模块测试
zig build test -- --filter "notification"

# 运行集成测试 (需要配置环境变量)
TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=xxx ./scripts/test_telegram.sh
SENDGRID_API_KEY=xxx ./scripts/test_sendgrid.sh
```

---

*Last updated: 2025-12-28*
