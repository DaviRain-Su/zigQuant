# Email 通知

通过邮件接收告警通知，支持 SendGrid、Mailgun、Resend 等主流邮件服务。

## 支持的服务商

| 服务商 | API Endpoint | 特点 |
|--------|--------------|------|
| SendGrid | api.sendgrid.com | 免费额度大，稳定 |
| Mailgun | api.mailgun.net | 开发者友好 |
| Resend | api.resend.com | 现代 API，简洁 |

## 配置步骤

### SendGrid

#### 1. 获取 API Key

1. 注册 [SendGrid](https://sendgrid.com)
2. 进入 Settings → API Keys
3. 创建新的 API Key (Full Access 或 Mail Send)
4. 保存 API Key (以 `SG.` 开头)

#### 2. 验证发件人

1. 进入 Settings → Sender Authentication
2. 选择 Single Sender Verification 或 Domain Authentication
3. 按提示完成验证

#### 3. 配置 zigQuant

```json
{
  "notifications": {
    "email": {
      "enabled": true,
      "provider": "sendgrid",
      "api_key": "SG.xxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "from": "alerts@yourdomain.com",
      "to": ["admin@yourdomain.com", "trader@yourdomain.com"],
      "min_level": "critical",
      "rate_limit_per_minute": 10
    }
  }
}
```

### Resend

#### 1. 获取 API Key

1. 注册 [Resend](https://resend.com)
2. 进入 API Keys
3. 创建新的 API Key
4. 保存 API Key (以 `re_` 开头)

#### 2. 配置

```json
{
  "notifications": {
    "email": {
      "enabled": true,
      "provider": "resend",
      "api_key": "re_xxxxxxxxxxxxxxxxxxxx",
      "from": "zigQuant <alerts@yourdomain.com>",
      "to": ["admin@yourdomain.com"],
      "min_level": "critical"
    }
  }
}
```

### Mailgun

#### 1. 获取 API Key

1. 注册 [Mailgun](https://mailgun.com)
2. 进入 Settings → API Keys
3. 复制 Private API Key

#### 2. 配置

```json
{
  "notifications": {
    "email": {
      "enabled": true,
      "provider": "mailgun",
      "api_key": "key-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "domain": "mail.yourdomain.com",
      "from": "alerts@yourdomain.com",
      "to": ["admin@yourdomain.com"]
    }
  }
}
```

## 配置选项

| 选项 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| `enabled` | boolean | false | 是否启用 |
| `provider` | string | "sendgrid" | 服务商 |
| `api_key` | string | - | API Key (必填) |
| `from` | string | - | 发件人地址 (必填) |
| `to` | string[] | - | 收件人列表 (必填) |
| `min_level` | string | "critical" | 最低告警级别 |
| `rate_limit_per_minute` | number | 10 | 每分钟最大邮件数 |

## 邮件格式

### 主题

```
[zigQuant CRITICAL] 交易所断连
```

格式: `[zigQuant <LEVEL>] <Title>`

### 正文 (HTML)

```html
<!DOCTYPE html>
<html>
<head>
  <style>
    .alert { padding: 20px; border-left: 4px solid #e74c3c; }
    .title { font-size: 18px; font-weight: bold; color: #e74c3c; }
    .message { margin-top: 10px; color: #333; }
  </style>
</head>
<body>
  <div class="alert">
    <div class="title">交易所断连</div>
    <div class="message">
      交易所 Hyperliquid 已断开连接超过 1 分钟。
    </div>
  </div>
  <div class="footer">
    This alert was sent by zigQuant Trading System.
  </div>
</body>
</html>
```

### 告警级别颜色

| 级别 | 颜色 |
|------|------|
| info | #3498db (蓝色) |
| warning | #f39c12 (橙色) |
| critical | #e74c3c (红色) |

## 测试

### API 测试

```bash
curl -X POST http://localhost:8080/api/v1/test/email \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test email from zigQuant"}'
```

### 手动测试 (SendGrid)

```bash
curl -X POST "https://api.sendgrid.com/v3/mail/send" \
  -H "Authorization: Bearer SG.xxxxx" \
  -H "Content-Type: application/json" \
  -d '{
    "personalizations": [{"to": [{"email": "test@example.com"}]}],
    "from": {"email": "alerts@example.com"},
    "subject": "Test",
    "content": [{"type": "text/html", "value": "<p>Test</p>"}]
  }'
```

## 常见问题

### 邮件未送达

**问题**: 收件箱没有邮件

**排查**:
1. 检查垃圾邮件文件夹
2. 验证发件人域名 (SPF, DKIM)
3. 检查 API Key 权限
4. 查看服务商后台的发送日志

### 进入垃圾邮件

**解决**:
1. 完成域名验证 (SPF, DKIM, DMARC)
2. 使用业务域名而非免费邮箱
3. 避免敏感词汇
4. 确保退订链接存在

### API 报错

**问题**: 返回 401 或 403

**解决**:
1. 检查 API Key 是否正确
2. 确认 API Key 有发送权限
3. 检查是否超出配额

## 最佳实践

1. **域名验证**: 完成 SPF/DKIM 配置提高送达率
2. **收件人分组**: 重要告警发给核心人员
3. **合理限制**: 设置适当的 min_level 和频率限制
4. **备用渠道**: 关键告警同时发送 Telegram
5. **定期测试**: 确保邮件服务正常工作

## 环境变量

```bash
# SendGrid
export SENDGRID_API_KEY="SG.xxxxx"

# Resend
export RESEND_API_KEY="re_xxxxx"

# Mailgun
export MAILGUN_API_KEY="key-xxxxx"
export MAILGUN_DOMAIN="mail.yourdomain.com"
```

---

*最后更新: 2025-12-28*
