# HTTP Server - 变更日志

> 版本历史记录

**最后更新**: 2025-12-28

---

## [未发布]

### 计划中 (v1.0.0)

#### 新增
- 基于 http.zig 的 HTTP 服务器
- JWT Token 认证 (HS256)
- CORS 中间件
- 请求日志中间件
- 健康检查端点 (`/health`, `/ready`)
- 认证端点 (`/api/v1/auth/*`)
- 策略管理端点 (`/api/v1/strategies/*`)
- 回测端点 (`/api/v1/backtest/*`)
- 订单端点 (`/api/v1/orders/*`)
- 仓位端点 (`/api/v1/positions/*`)
- 账户端点 (`/api/v1/account/*`)
- Prometheus 指标端点 (`/metrics`)

#### 依赖
- http.zig

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

- **新增**: 新功能
- **变更**: 现有功能的变更
- **弃用**: 即将移除的功能
- **移除**: 已移除的功能
- **修复**: bug 修复
- **安全**: 安全相关修复

---

*Last updated: 2025-12-28*
