# JWT 认证

> 完整的认证流程说明

**最后更新**: 2025-12-28

---

## 概述

zigQuant API 使用 JWT (JSON Web Token) 进行认证，采用 HS256 签名算法。

---

## 认证流程

```
1. 用户登录 → POST /api/v1/auth/login
2. 服务器验证凭据 → 返回 JWT Token
3. 客户端存储 Token
4. 后续请求携带 Token → Authorization: Bearer <token>
5. Token 过期前刷新 → POST /api/v1/auth/refresh
```

```
┌─────────┐                           ┌─────────┐
│  Client │                           │  Server │
└────┬────┘                           └────┬────┘
     │                                      │
     │  POST /api/v1/auth/login             │
     │  {username, password}                │
     │─────────────────────────────────────>│
     │                                      │
     │  {token, expires_in}                 │
     │<─────────────────────────────────────│
     │                                      │
     │  GET /api/v1/strategies              │
     │  Authorization: Bearer <token>       │
     │─────────────────────────────────────>│
     │                                      │
     │  {strategies: [...]}                 │
     │<─────────────────────────────────────│
     │                                      │
```

---

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

---

## 使用 Token

在所有需要认证的请求中添加 `Authorization` 头:

```bash
curl http://localhost:8080/api/v1/strategies \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### 编程语言示例

**Python**:

```python
import requests

token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
headers = {"Authorization": f"Bearer {token}"}

response = requests.get(
    "http://localhost:8080/api/v1/strategies",
    headers=headers
)
```

**JavaScript**:

```javascript
const token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...";

const response = await fetch("http://localhost:8080/api/v1/strategies", {
  headers: {
    Authorization: `Bearer ${token}`,
  },
});
```

**Go**:

```go
token := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

req, _ := http.NewRequest("GET", "http://localhost:8080/api/v1/strategies", nil)
req.Header.Set("Authorization", "Bearer "+token)

resp, _ := http.DefaultClient.Do(req)
```

---

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
| sub | 用户 ID (Subject) |
| iat | Token 签发时间 (Issued At, Unix timestamp) |
| exp | Token 过期时间 (Expiration, Unix timestamp) |

### Signature

使用 HMAC-SHA256 算法签名:

```
HMACSHA256(
  base64UrlEncode(header) + "." + base64UrlEncode(payload),
  secret
)
```

---

## 刷新 Token

在 Token 过期前刷新，获取新的 Token:

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

### 刷新策略

建议在 Token 过期前 10% 的时间内刷新:

```javascript
const expiresIn = 86400; // 24 hours
const refreshAt = expiresIn * 0.9; // 21.6 hours

setTimeout(refreshToken, refreshAt * 1000);
```

---

## Token 过期

默认 Token 有效期为 24 小时，可通过配置修改:

```json
{
  "api": {
    "jwt_expiry_hours": 24
  }
}
```

或环境变量:

```bash
export ZIGQUANT_JWT_EXPIRY_HOURS=48
```

---

## 错误处理

### 缺少 Token

HTTP 401:

```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Missing Authorization header"
  }
}
```

### 无效 Token

HTTP 401:

```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Invalid token"
  }
}
```

### Token 过期

HTTP 401:

```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Token expired"
  }
}
```

### 格式错误

HTTP 401:

```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Invalid Authorization format, expected 'Bearer <token>'"
  }
}
```

---

## 配置

### JWT 密钥

**环境变量** (推荐):

```bash
export ZIGQUANT_JWT_SECRET="your-secret-key-at-least-32-bytes-long"
```

**配置文件**:

```json
{
  "api": {
    "jwt_secret": "your-secret-key-at-least-32-bytes-long"
  }
}
```

### 生成安全密钥

```bash
# Linux/macOS
openssl rand -base64 32

# 输出示例: K7gNU3sdo+OL0wNhqoVWhr3g6s1xYv72ol/pe/Unols=
```

---

## 安全最佳实践

### 1. 使用 HTTPS

生产环境必须使用 HTTPS，防止 Token 被截获:

```bash
# 使用反向代理 (nginx)
server {
    listen 443 ssl;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:8080;
    }
}
```

### 2. 安全存储 Token

**浏览器**:
- 使用 `httpOnly` Cookie (防 XSS)
- 或 `localStorage` (需防范 XSS)
- 避免 `sessionStorage` (关闭标签页丢失)

**服务端**:
- 加密存储
- 不记录到日志

### 3. Token 刷新策略

```javascript
// 设置自动刷新
function setupAutoRefresh(expiresIn) {
  const refreshTime = expiresIn * 0.9 * 1000; // 90% of expiry

  setTimeout(async () => {
    try {
      const newToken = await refreshToken();
      saveToken(newToken);
      setupAutoRefresh(newToken.expires_in);
    } catch (error) {
      // 刷新失败，重新登录
      logout();
    }
  }, refreshTime);
}
```

### 4. 密钥管理

- 使用强随机密钥 (至少 32 字节)
- 定期轮换密钥
- 不要在代码中硬编码密钥
- 使用环境变量或密钥管理服务

### 5. 登出处理

由于 JWT 是无状态的，服务端无法"撤销" Token。可选方案:

- **短过期时间**: 减少 Token 有效期
- **Token 黑名单**: 服务端维护已登出 Token 列表
- **刷新 Token**: 登出时仅撤销刷新 Token

---

## Zig 实现参考

```zig
// 验证 Token
pub fn verifyToken(self: *JwtManager, token: []const u8) !JwtPayload {
    // 1. 分割 Token
    var parts = std.mem.splitScalar(u8, token, '.');
    const header_b64 = parts.next() orelse return error.InvalidToken;
    const payload_b64 = parts.next() orelse return error.InvalidToken;
    const signature_b64 = parts.next() orelse return error.InvalidToken;

    // 2. 验证签名
    const message = token[0 .. header_b64.len + 1 + payload_b64.len];
    const expected_sig = hmacSha256(message, self.secret);
    const actual_sig = base64Decode(signature_b64);

    if (!std.mem.eql(u8, expected_sig, actual_sig)) {
        return error.InvalidSignature;
    }

    // 3. 解析 Payload
    const payload_json = base64Decode(payload_b64);
    const payload = try std.json.parseFromSlice(JwtPayload, self.allocator, payload_json, .{});

    // 4. 验证过期时间
    if (std.time.timestamp() > payload.value.exp) {
        return error.TokenExpired;
    }

    return payload.value;
}
```

---

*最后更新: 2025-12-28*
