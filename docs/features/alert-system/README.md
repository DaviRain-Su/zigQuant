# AlertSystem - 告警和通知系统

> 多渠道告警，及时通知重要事件

**状态**: 📋 待开始
**版本**: v0.8.0
**Story**: [STORY-044](../../stories/v0.8.0/STORY_044_ALERT_SYSTEM.md)
**最后更新**: 2025-12-27

---

## 📋 概述

AlertSystem 模块实现多渠道告警系统，在重要事件发生时及时通知用户，确保交易者能够快速响应市场变化和系统异常。

### 核心特性

- ✅ **多渠道支持**: Console, Telegram, Email, Webhook
- ✅ **告警级别**: Debug, Info, Warning, Critical, Emergency
- ✅ **节流控制**: 防止告警轰炸
- ✅ **静音时段**: 支持自定义静音时间
- ✅ **历史记录**: 告警历史查询

---

## 🚀 快速开始

```zig
const risk = @import("zigQuant").risk;

// 创建告警管理器
var alerts = risk.AlertManager.init(allocator, .{
    .min_level = .info,
    .throttle_window_ms = 30000,
});
defer alerts.deinit();

// 添加通道
var console = ConsoleChannel.init(.{ .colorize = true });
try alerts.addChannel(console.asChannel());

// 发送告警
try alerts.warning("High Volatility", "Market volatility is above normal", "MarketMonitor");

// 风险告警
try alerts.riskAlert(.risk_drawdown, .{ .actual = 0.08, .threshold = 0.10 });
```

---

## 📚 相关文档

- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [Bug 追踪](./bugs.md)
- [变更日志](./changelog.md)

---

## 🔧 核心 API

```zig
pub const AlertManager = struct {
    pub fn init(allocator: Allocator, config: AlertConfig) AlertManager;
    pub fn addChannel(self: *Self, channel: IAlertChannel) !void;
    pub fn sendAlert(self: *Self, alert: Alert) !void;
    pub fn info(self: *Self, title: []const u8, message: []const u8, source: []const u8) !void;
    pub fn warning(self: *Self, title: []const u8, message: []const u8, source: []const u8) !void;
    pub fn critical(self: *Self, title: []const u8, message: []const u8, source: []const u8) !void;
    pub fn riskAlert(self: *Self, category: AlertCategory, details: AlertDetails) !void;
    pub fn getStats(self: *Self) AlertStats;
};

pub const IAlertChannel = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        send: *const fn (ptr: *anyopaque, alert: Alert) anyerror!void,
        getType: *const fn (ptr: *anyopaque) ChannelType,
        isAvailable: *const fn (ptr: *anyopaque) bool,
    };
};
```

---

## 📊 告警级别

| 级别 | 用途 | 默认通道 |
|------|------|----------|
| Debug | 调试信息 | Console |
| Info | 一般信息 | Console |
| Warning | 警告 | Console, Telegram |
| Critical | 严重 | Console, Telegram, Email |
| Emergency | 紧急 | 所有通道 |

---

## 📝 支持的通道

### Console
本地终端输出，支持彩色显示

### Telegram
通过 Telegram Bot API 发送消息

### Email
通过 SMTP 发送邮件

### Webhook
发送 HTTP POST 到自定义 URL

---

*Last updated: 2025-12-27*
