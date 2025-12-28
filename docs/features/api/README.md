# zigQuant REST API

zigQuant 提供完整的 REST API 接口，支持策略管理、回测执行、交易操作和监控集成。

## 快速开始

### 基础信息

- **Base URL**: `http://localhost:8080`
- **API Version**: `v1`
- **Content-Type**: `application/json`
- **认证方式**: JWT Bearer Token

### 获取 Token

```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin"}'
```

响应:

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 86400
}
```

### 使用 Token

```bash
curl http://localhost:8080/api/v1/strategies \
  -H "Authorization: Bearer <your-token>"
```

## API 端点

| 分类 | 端点 | 描述 |
|------|------|------|
| [健康检查](#健康检查) | `/health`, `/ready` | 服务状态 |
| [认证](#认证) | `/api/v1/auth/*` | 登录、Token 管理 |
| [策略](#策略管理) | `/api/v1/strategies/*` | 策略 CRUD |
| [回测](#回测) | `/api/v1/backtest/*` | 回测执行和查询 |
| [交易](#交易) | `/api/v1/orders/*`, `/api/v1/positions/*` | 订单和仓位 |
| [账户](#账户) | `/api/v1/account/*` | 账户信息 |
| [监控](#监控) | `/api/v1/metrics`, `/metrics` | 性能指标 |

## 详细文档

- [端点详情](./endpoints.md) - 所有 API 端点的详细说明
- [认证](./authentication.md) - JWT 认证流程

## 错误处理

### 错误响应格式

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid request body",
    "details": {
      "field": "strategy_id",
      "reason": "required"
    }
  }
}
```

### 错误码

| HTTP 状态码 | 错误码 | 描述 |
|-------------|--------|------|
| 400 | `VALIDATION_ERROR` | 请求参数错误 |
| 401 | `UNAUTHORIZED` | 未认证或 Token 过期 |
| 403 | `FORBIDDEN` | 权限不足 |
| 404 | `NOT_FOUND` | 资源不存在 |
| 429 | `RATE_LIMITED` | 请求过于频繁 |
| 500 | `INTERNAL_ERROR` | 服务器内部错误 |

## 速率限制

- 认证端点: 10 次/分钟
- 其他端点: 100 次/分钟
- 超出限制返回 429 状态码

## SDK

暂无官方 SDK，推荐使用标准 HTTP 客户端:

- **Python**: `requests`, `httpx`
- **JavaScript**: `fetch`, `axios`
- **Go**: `net/http`
- **Rust**: `reqwest`

---

*最后更新: 2025-12-28*
