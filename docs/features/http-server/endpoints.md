# REST API 端点详情

> 完整的 REST API 端点说明

**最后更新**: 2025-12-28

---

## 概览

- **Base URL**: `http://localhost:8080`
- **API Version**: `v1`
- **Content-Type**: `application/json`
- **认证方式**: JWT Bearer Token

---

## 健康检查

### GET /health

服务健康状态检查。

**认证**: 不需要

**响应**:

```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": 1735344000
}
```

### GET /ready

服务就绪检查，验证所有依赖服务。

**认证**: 不需要

**响应 (就绪)**:

```json
{
  "ready": true
}
```

**响应 (未就绪)** - 503:

```json
{
  "ready": false,
  "reason": "Database connection failed"
}
```

---

## 认证

### POST /api/v1/auth/login

用户登录，获取 JWT Token。

**请求**:

```json
{
  "username": "admin",
  "password": "password123"
}
```

**响应**:

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 86400,
  "token_type": "Bearer"
}
```

### POST /api/v1/auth/refresh

刷新 Token。

**请求头**:

```
Authorization: Bearer <current-token>
```

**响应**:

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 86400
}
```

### GET /api/v1/auth/me

获取当前用户信息。

**认证**: 需要

**响应**:

```json
{
  "id": "user_123",
  "username": "admin",
  "role": "admin",
  "created_at": "2024-01-01T00:00:00Z"
}
```

---

## 策略管理

### GET /api/v1/strategies

列出所有策略。

**认证**: 需要

**查询参数**:

| 参数 | 类型 | 描述 |
|------|------|------|
| status | string | 过滤状态 (running, stopped) |
| pair | string | 过滤交易对 |
| limit | number | 返回数量限制 |
| offset | number | 偏移量 |

**响应**:

```json
{
  "strategies": [
    {
      "id": "sma_cross_btc",
      "name": "SMA Cross Strategy",
      "pair": "BTC-USDT",
      "timeframe": "1h",
      "status": "running",
      "created_at": "2024-12-01T00:00:00Z",
      "pnl": 2500.50,
      "win_rate": 0.65
    }
  ],
  "total": 5,
  "limit": 10,
  "offset": 0
}
```

### GET /api/v1/strategies/:id

获取策略详情。

**认证**: 需要

**响应**:

```json
{
  "id": "sma_cross_btc",
  "name": "SMA Cross Strategy",
  "description": "Simple SMA crossover strategy",
  "pair": "BTC-USDT",
  "timeframe": "1h",
  "status": "running",
  "config": {
    "fast_period": 10,
    "slow_period": 20,
    "position_size": 0.1
  },
  "metrics": {
    "total_trades": 150,
    "win_rate": 0.65,
    "total_pnl": 2500.50,
    "sharpe_ratio": 1.85,
    "max_drawdown": 0.08
  },
  "created_at": "2024-12-01T00:00:00Z",
  "updated_at": "2024-12-28T10:00:00Z"
}
```

### POST /api/v1/strategies/:id/run

启动策略。

**认证**: 需要

**响应**:

```json
{
  "id": "sma_cross_btc",
  "status": "running",
  "message": "Strategy started successfully",
  "started_at": "2024-12-28T10:00:00Z"
}
```

### POST /api/v1/strategies/:id/stop

停止策略。

**认证**: 需要

**响应**:

```json
{
  "id": "sma_cross_btc",
  "status": "stopped",
  "message": "Strategy stopped successfully",
  "stopped_at": "2024-12-28T10:30:00Z"
}
```

---

## 回测

### POST /api/v1/backtest

创建回测任务。

**认证**: 需要

**请求**:

```json
{
  "strategy_id": "sma_cross",
  "start_date": "2024-01-01",
  "end_date": "2024-12-31",
  "initial_capital": 10000,
  "config": {
    "fast_period": 10,
    "slow_period": 20
  }
}
```

**响应** - 202 Accepted:

```json
{
  "id": "bt_abc123",
  "status": "pending",
  "message": "Backtest submitted",
  "submitted_at": "2024-12-28T10:00:00Z"
}
```

### GET /api/v1/backtest/:id

获取回测结果。

**认证**: 需要

**响应 (进行中)**:

```json
{
  "id": "bt_abc123",
  "status": "running",
  "progress": 0.65
}
```

**响应 (完成)**:

```json
{
  "id": "bt_abc123",
  "status": "completed",
  "metrics": {
    "total_return": 0.25,
    "annual_return": 0.30,
    "sharpe_ratio": 1.85,
    "max_drawdown": 0.08,
    "win_rate": 0.65,
    "total_trades": 150,
    "profit_factor": 1.8
  },
  "equity_curve": [
    {"time": "2024-01-01", "equity": 10000},
    {"time": "2024-01-02", "equity": 10050}
  ],
  "trades": [
    {
      "id": 1,
      "side": "buy",
      "price": 42000,
      "size": 0.1,
      "pnl": 150,
      "timestamp": "2024-01-15T10:00:00Z"
    }
  ],
  "completed_at": "2024-12-28T10:05:00Z"
}
```

---

## 交易

### GET /api/v1/orders

获取订单列表。

**认证**: 需要

**查询参数**:

| 参数 | 类型 | 描述 |
|------|------|------|
| status | string | filled, open, cancelled |
| pair | string | 交易对 |
| limit | number | 返回数量 |

**响应**:

```json
{
  "orders": [
    {
      "id": "ord_123",
      "pair": "BTC-USDT",
      "side": "buy",
      "type": "limit",
      "price": 42000,
      "size": 0.1,
      "filled": 0.1,
      "status": "filled",
      "created_at": "2024-12-28T10:00:00Z"
    }
  ],
  "total": 100
}
```

### POST /api/v1/orders

创建订单。

**认证**: 需要

**请求**:

```json
{
  "pair": "BTC-USDT",
  "side": "buy",
  "type": "limit",
  "price": 42000,
  "size": 0.1
}
```

**响应** - 201 Created:

```json
{
  "id": "ord_456",
  "pair": "BTC-USDT",
  "side": "buy",
  "type": "limit",
  "price": 42000,
  "size": 0.1,
  "status": "open",
  "created_at": "2024-12-28T10:00:00Z"
}
```

### DELETE /api/v1/orders/:id

取消订单。

**认证**: 需要

**响应**:

```json
{
  "id": "ord_456",
  "status": "cancelled",
  "cancelled_at": "2024-12-28T10:01:00Z"
}
```

### GET /api/v1/positions

获取当前仓位。

**认证**: 需要

**响应**:

```json
{
  "positions": [
    {
      "pair": "BTC-USDT",
      "side": "long",
      "size": 0.5,
      "entry_price": 42000,
      "current_price": 43000,
      "unrealized_pnl": 500,
      "leverage": 1,
      "margin": 21000
    }
  ],
  "total_equity": 25500,
  "total_unrealized_pnl": 500
}
```

---

## 账户

### GET /api/v1/account

获取账户信息。

**认证**: 需要

**响应**:

```json
{
  "id": "acc_123",
  "exchange": "hyperliquid",
  "balance": 25000,
  "available": 20000,
  "margin_used": 5000,
  "unrealized_pnl": 500,
  "leverage": 1
}
```

### GET /api/v1/account/balance

获取账户余额。

**认证**: 需要

**响应**:

```json
{
  "total": 25500,
  "available": 20000,
  "margin_used": 5000,
  "unrealized_pnl": 500,
  "currency": "USDT"
}
```

---

## 监控

### GET /api/v1/metrics

获取 JSON 格式性能指标。

**认证**: 需要

**响应**:

```json
{
  "trading": {
    "total_trades": 1500,
    "win_rate": 0.62,
    "total_pnl": 15000,
    "sharpe_ratio": 1.75,
    "max_drawdown": 0.08
  },
  "system": {
    "uptime_seconds": 86400,
    "memory_bytes": 52428800,
    "api_requests_total": 50000
  },
  "exchange": {
    "connected": true,
    "latency_ms": 50
  }
}
```

### GET /metrics

获取 Prometheus 格式指标。

**认证**: 不需要

**响应** (text/plain):

```
# HELP zigquant_trades_total Total trades
# TYPE zigquant_trades_total counter
zigquant_trades_total{strategy="sma_cross",side="buy"} 750
zigquant_trades_total{strategy="sma_cross",side="sell"} 750

# HELP zigquant_win_rate Strategy win rate
# TYPE zigquant_win_rate gauge
zigquant_win_rate{strategy="sma_cross"} 0.62

# HELP zigquant_uptime_seconds Uptime in seconds
# TYPE zigquant_uptime_seconds counter
zigquant_uptime_seconds 86400
```

---

## 错误响应

### 错误格式

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

---

## 速率限制

| 端点类型 | 限制 |
|----------|------|
| 认证端点 | 10 次/分钟 |
| 其他端点 | 100 次/分钟 |

超出限制返回 429 状态码。

---

*最后更新: 2025-12-28*
