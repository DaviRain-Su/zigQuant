# Telegram 通知

通过 Telegram Bot 接收即时告警通知。

## 配置步骤

### 1. 创建 Telegram Bot

1. 在 Telegram 中搜索 `@BotFather`
2. 发送 `/newbot` 命令
3. 按提示设置 Bot 名称和用户名
4. 保存返回的 Bot Token (格式: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

### 2. 获取 Chat ID

#### 个人聊天

1. 向 Bot 发送任意消息
2. 访问: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
3. 找到 `chat.id` 字段

#### 群组聊天

1. 将 Bot 添加到群组
2. 在群组中 @Bot
3. 访问 getUpdates API 获取群组 ID (负数)

### 3. 配置 zigQuant

```json
{
  "notifications": {
    "telegram": {
      "enabled": true,
      "bot_token": "123456789:ABCdefGHIjklMNOpqrsTUVwxyz",
      "chat_id": "-1001234567890",
      "min_level": "warning",
      "rate_limit_per_minute": 30
    }
  }
}
```

或使用环境变量:

```bash
export TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
export TELEGRAM_CHAT_ID="-1001234567890"
```

## 配置选项

| 选项 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `enabled` | boolean | false | 是否启用 |
| `bot_token` | string | - | Bot Token (必填) |
| `chat_id` | string | - | Chat ID (必填) |
| `min_level` | string | "warning" | 最低告警级别 |
| `rate_limit_per_minute` | number | 30 | 每分钟最大消息数 |

## 消息格式

### 标准格式

```
🚨 [CRITICAL] 告警标题

告警详细信息

Time: 2024-12-28 10:00:00 UTC
```

### 告警级别图标

| 级别 | 图标 |
|------|------|
| info | ℹ️ |
| warning | ⚠️ |
| critical | 🚨 |

### HTML 格式支持

消息支持 HTML 标签:
- `<b>粗体</b>`
- `<i>斜体</i>`
- `<code>代码</code>`
- `<pre>代码块</pre>`
- `<a href="url">链接</a>`

## 测试

### API 测试

```bash
curl -X POST http://localhost:8080/api/v1/test/telegram \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test notification from zigQuant"}'
```

### 手动测试

```bash
curl -X POST "https://api.telegram.org/bot<BOT_TOKEN>/sendMessage" \
  -H "Content-Type: application/json" \
  -d '{
    "chat_id": "<CHAT_ID>",
    "text": "Test message",
    "parse_mode": "HTML"
  }'
```

## 常见问题

### Bot 无法发送消息

**问题**: 收不到消息

**排查**:
1. 检查 Bot Token 是否正确
2. 确认已向 Bot 发送过消息 (激活对话)
3. 群组需要先添加 Bot 为成员
4. 检查 Chat ID 格式 (群组 ID 为负数)

### 频率限制

**问题**: 消息被限制

**解决**:
1. 调整 `rate_limit_per_minute` 配置
2. 提高 `min_level` 减少告警数量
3. 使用告警聚合

### 格式错误

**问题**: 消息显示异常

**解决**:
1. 检查特殊字符转义
2. 确保 HTML 标签闭合
3. 避免使用不支持的标签

## 最佳实践

1. **使用群组**: 方便多人接收告警
2. **设置合理的 min_level**: 避免过多通知打扰
3. **启用静音**: 非紧急时段可静音群组
4. **定期检查**: 确保 Bot 正常工作

---

*最后更新: 2025-12-28*
