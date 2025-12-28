# 通知系统 - 变更日志

> 版本历史记录

**最后更新**: 2025-12-28

---

## [未发布]

### 计划中 (v1.0.0)

#### 新增
- IAlertChannel 接口
- TelegramChannel 实现
  - Bot API 集成
  - HTML 格式消息
  - 速率限制
  - 最低级别过滤
- EmailChannel 实现
  - SendGrid 支持
  - Mailgun 支持
  - Resend 支持
  - HTML 邮件模板
- WebhookChannel 实现
  - 自定义 HTTP 端点
  - JSON 负载
- RateLimiter 速率限制
- AlertManager 多渠道路由
- 异步发送队列
- 重试机制

#### 告警级别
- info - 信息通知
- warning - 警告通知
- critical - 严重告警

---

## 计划版本

### v1.1.0 (规划中)

#### 新增
- 消息队列持久化
- 自定义消息模板
- Discord 渠道支持
- Slack 渠道支持
- 告警聚合 (相同告警合并)

#### 优化
- 异步重试队列
- HTTP 连接池
- 批量发送

### v1.2.0 (规划中)

#### 新增
- 告警规则引擎
- 告警升级 (无响应自动升级)
- 值班表集成
- 告警确认 API

#### 安全
- 敏感信息脱敏
- 加密存储配置

---

## 版本规范

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 规范。

### 版本格式

```
MAJOR.MINOR.PATCH

- MAJOR: 不兼容的 API 变更
- MINOR: 向后兼容的新功能
- PATCH: 向后兼容的 bug 修复
```

### 变更类型

- **新增**: 新渠道、新功能
- **变更**: 现有功能的变更
- **弃用**: 即将移除的功能
- **移除**: 已移除的功能
- **修复**: bug 修复
- **安全**: 安全相关修复

---

*Last updated: 2025-12-28*
