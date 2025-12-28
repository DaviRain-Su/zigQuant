# API 认证

zigQuant API 使用 JWT (JSON Web Token) 进行认证。

## 认证流程

```
1. 用户登录 → POST /api/v1/auth/login
2. 服务器验证凭据 → 返回 JWT Token
3. 客户端存储 Token
4. 后续请求携带 Token → Authorization: Bearer <token>
5. Token 过期前刷新 → POST /api/v1/auth/refresh
```

## 获取 Token

### 请求

```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "your-password"
  }'
```

### 响应

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhZG1pbiIsImlhdCI6MTczNTM0NDAwMCwiZXhwIjoxNzM1NDMwNDAwfQ.signature",
  "expires_in": 86400,
  "token_type": "Bearer"
}
```

## 使用 Token

在所有需要认证的请求中添加 `Authorization` 头:

```bash
curl http://localhost:8080/api/v1/strategies \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Token 结构

JWT Token 由三部分组成:

```
Header.Payload.Signature
```

### Header

```json
{
  "alg": "HS256",
  "typ": "JWT"
}
```

### Payload

```json
{
  "sub": "user_id",
  "iat": 1735344000,
  "exp": 1735430400
}
```

| 字段 | 描述 |
|------|------|
| sub | 用户 ID |
| iat | Token 签发时间 (Unix timestamp) |
| exp | Token 过期时间 (Unix timestamp) |

### Signature

使用 HMAC-SHA256 算法签名:

```
HMACSHA256(
  base64UrlEncode(header) + "." + base64UrlEncode(payload),
  secret
)
```

## 刷新 Token

在 Token 过期前刷新:

```bash
curl -X POST http://localhost:8080/api/v1/auth/refresh \
  -H "Authorization: Bearer <current-token>"
```

响应:

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 86400
}
```

## Token 过期

默认 Token 有效期为 24 小时，可通过配置修改:

```json
{
  "api": {
    "jwt_expiry_hours": 24
  }
}
```

## 错误处理

### 缺少 Token

```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Missing Authorization header"
  }
}
```

### 无效 Token

```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Invalid token"
  }
}
```

### Token 过期

```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Token expired"
  }
}
```

## 安全最佳实践

1. **使用 HTTPS**: 生产环境必须使用 HTTPS
2. **安全存储**: 不要在前端代码中硬编码 Token
3. **定期刷新**: 在 Token 过期前刷新
4. **最小权限**: 使用适当的用户角色
5. **密钥管理**:
   - 使用强随机密钥 (至少 32 字节)
   - 定期轮换密钥
   - 不要在代码中硬编码密钥

## 配置

### JWT 密钥

通过环境变量设置:

```bash
export ZIGQUANT_JWT_SECRET="your-secret-key-at-least-32-bytes"
```

或在配置文件中:

```json
{
  "api": {
    "jwt_secret": "your-secret-key-at-least-32-bytes"
  }
}
```

---

*最后更新: 2025-12-28*
