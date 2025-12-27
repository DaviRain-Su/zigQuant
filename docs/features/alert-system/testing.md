# AlertSystem - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-27

---

## 测试覆盖率

- **代码覆盖率**: 目标 > 85%
- **测试用例数**: 目标 15+

---

## 单元测试

```zig
test "AlertManager: send alert" {
    var alerts = AlertManager.init(allocator, .{});
    var console = MockChannel.init();
    try alerts.addChannel(console.asChannel());

    try alerts.warning("Test", "Test message", "test");

    try std.testing.expectEqual(@as(u64, 1), alerts.total_alerts);
    try std.testing.expect(console.received_alerts.len > 0);
}

test "AlertManager: throttling" {
    var alerts = AlertManager.init(allocator, .{ .throttle_window_ms = 1000 });

    try alerts.warning("Same ID", "Message 1", "test");
    try alerts.warning("Same ID", "Message 2", "test"); // 应被节流

    try std.testing.expectEqual(@as(u64, 1), alerts.total_alerts);
}

test "AlertManager: quiet hours" {
    var alerts = AlertManager.init(allocator, .{
        .quiet_hours_start = 22,
        .quiet_hours_end = 8,
        .quiet_hours_min_level = .critical,
    });

    // 在静音时段，Info 级别不应发送
    // 测试需要模拟时间
}
```

---

## 测试场景

### ✅ 已覆盖

- [x] 基本告警发送
- [x] 节流控制
- [x] 多通道发送
- [x] 级别过滤

### 📋 待补充

- [ ] 静音时段测试
- [ ] Telegram 集成测试
- [ ] Webhook 集成测试
