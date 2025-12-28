# 通知系统

zigQuant 支持多渠道告警通知，帮助您及时响应市场变化和系统事件。

## 支持的渠道

| 渠道 | 描述 | 适用场景 |
|------|------|----------|
| [Telegram](./telegram.md) | 即时消息推送 | 实时告警 |
| [Email](./email.md) | 邮件通知 | 详细报告 |
| Webhook | 自定义 HTTP 回调 | 系统集成 |
| Console | 控制台输出 | 开发调试 |
| Log | 日志记录 | 审计追踪 |

## 快速开始

### 1. 配置通知渠道

在 `config.json` 中添加通知配置:

```json
{
  "notifications": {
    "telegram": {
      "enabled": true,
      "bot_token": "123456789:ABCdefGHIjklMNOpqrsTUVwxyz",
      "chat_id": "-1001234567890",
      "min_level": "warning"
    },
    "email": {
      "enabled": true,
      "provider": "sendgrid",
      "api_key": "SG.xxxx",
      "from": "alerts@example.com",
      "to": ["admin@example.com"]
    }
  }
}
```

### 2. 告警级别

| 级别 | 描述 | 默认渠道 |
|------|------|----------|
| `info` | 信息通知 | Console, Log |
| `warning` | 警告告警 | Telegram |
| `critical` | 严重告警 | Telegram, Email |

### 3. 路由规则

```
告警级别       渠道
─────────────────────────
info     →  Console, Log
warning  →  Telegram
critical →  Telegram + Email
```

## 告警类型

### 交易告警

- 订单执行成功/失败
- 仓位开/平
- 止损/止盈触发
- 连续亏损警告

### 风控告警

- 回撤超限
- 胜率下降
- 日亏损超限
- 仓位集中度过高

### 系统告警

- 交易所断连
- API 响应超时
- 服务重启
- 内存使用过高

## 消息模板

### Telegram 消息示例

```
🚨 [CRITICAL] 交易所断连

交易所 Hyperliquid 已断开连接超过 1 分钟

Time: 2024-12-28 10:00:00 UTC
```

### Email 消息示例

```
Subject: [zigQuant CRITICAL] 交易所断连

<html>
  <div class="alert">
    <div class="title">交易所断连</div>
    <div class="message">
      交易所 Hyperliquid 已断开连接超过 1 分钟。
      请检查网络连接和 API 密钥配置。
    </div>
  </div>
</html>
```

## 频率限制

为防止告警风暴，系统实现了频率限制:

| 渠道 | 默认限制 |
|------|----------|
| Telegram | 30 条/分钟 |
| Email | 10 封/分钟 |
| Webhook | 60 次/分钟 |

超出限制的告警会被记录到日志但不会发送。

## API 接口

### 发送测试通知

```bash
# 测试 Telegram
curl -X POST http://localhost:8080/api/v1/test/telegram \
  -H "Authorization: Bearer $TOKEN"

# 测试 Email
curl -X POST http://localhost:8080/api/v1/test/email \
  -H "Authorization: Bearer $TOKEN"
```

### 查看通知历史

```bash
curl http://localhost:8080/api/v1/notifications \
  -H "Authorization: Bearer $TOKEN"
```

## 代码示例

### 手动发送告警

```zig
const AlertManager = @import("zigQuant").AlertManager;

// 发送告警
alert_manager.alert(.critical, "交易所断连", "Hyperliquid 已断开连接");

// 带元数据的告警
alert_manager.alertWithMetadata(.warning, "高回撤警告", "当前回撤 8.5%", .{
    .drawdown = "0.085",
    .threshold = "0.10",
});
```

## 相关文档

- [Telegram 配置](./telegram.md)
- [Email 配置](./email.md)
- [Story 052: 通知系统](../../stories/v1.0.0/STORY_052_NOTIFICATIONS.md)

---

*最后更新: 2025-12-28*
