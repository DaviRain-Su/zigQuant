# API V2 设计文档

> REST + WebSocket 双协议 API 设计

**版本**: v2.0.0
**状态**: 📋 设计阶段
**创建日期**: 2025-12-29

---

## 📋 概述

API V2 在 V1 基础上增加：
- WebSocket 实时通信
- 真实的策略控制能力
- 状态持久化和恢复
- 更细粒度的权限控制

---

## 🔌 连接方式

### REST API

```
Base URL: http://localhost:8080/api/v2
Content-Type: application/json
Authorization: Bearer <jwt_token>
```

### WebSocket

```
URL: ws://localhost:8080/ws
Protocol: zigquant-v2
Authorization: Query param ?token=<jwt_token>
```

---

## 📡 WebSocket 协议

### 连接建立

```typescript
// 客户端连接
const ws = new WebSocket('ws://localhost:8080/ws?token=xxx');

// 连接成功后发送认证
ws.onopen = () => {
  ws.send(JSON.stringify({
    type: 'auth',
    token: 'jwt_token_here'
  }));
};
```

### 消息格式

```typescript
interface WSMessage {
  type: 'event' | 'command' | 'response' | 'error';
  id?: string;        // 请求 ID (用于 command/response 匹配)
  channel?: string;   // 事件频道
  event?: string;     // 事件名称
  data: any;          // 消息内容
  timestamp: number;  // 时间戳
}
```

### 订阅管理

```typescript
// 订阅频道
ws.send(JSON.stringify({
  type: 'subscribe',
  channels: ['grid.*', 'system.health', 'backtest.progress.*']
}));

// 取消订阅
ws.send(JSON.stringify({
  type: 'unsubscribe',
  channels: ['grid.*']
}));
```

### 频道列表

| 频道模式 | 说明 |
|----------|------|
| `grid.*` | 所有网格事件 |
| `grid.<id>.*` | 特定网格的所有事件 |
| `grid.<id>.order` | 特定网格的订单事件 |
| `backtest.*` | 所有回测事件 |
| `backtest.<id>.progress` | 特定回测进度 |
| `strategy.*` | 所有策略事件 |
| `system.*` | 系统事件 |
| `system.health` | 健康状态 |
| `system.log` | 实时日志 |

---

## 🎮 网格交易 API

### 启动网格

**POST** `/api/v2/grid/start`

```json
// Request
{
  "pair": "BTC-USDC",
  "upper_price": 100000,
  "lower_price": 90000,
  "grid_count": 10,
  "order_size": 0.001,
  "take_profit_pct": 0.5,
  "mode": "testnet",      // paper | testnet | mainnet
  "config_file": "config.test.json",  // 可选
  "risk_enabled": true
}

// Response
{
  "success": true,
  "data": {
    "id": "grid_abc123",
    "status": "starting",
    "created_at": "2025-12-29T10:00:00Z"
  }
}
```

**WebSocket 事件**:
```json
{
  "type": "event",
  "channel": "grid.grid_abc123",
  "event": "started",
  "data": {
    "id": "grid_abc123",
    "config": { ... },
    "status": "running"
  }
}
```

### 停止网格

**POST** `/api/v2/grid/:id/stop`

```json
// Request
{
  "cancel_orders": true,  // 是否取消挂单
  "close_position": false // 是否平仓
}

// Response
{
  "success": true,
  "data": {
    "id": "grid_abc123",
    "status": "stopped",
    "final_pnl": 12.34,
    "total_trades": 15
  }
}
```

### 更新网格参数

**PUT** `/api/v2/grid/:id/params`

```json
// Request (只更新指定字段)
{
  "take_profit_pct": 0.8,
  "order_size": 0.002
}

// Response
{
  "success": true,
  "data": {
    "id": "grid_abc123",
    "updated_params": ["take_profit_pct", "order_size"],
    "effective_from": "next_cycle"
  }
}
```

### 获取网格状态

**GET** `/api/v2/grid/:id/status`

```json
// Response
{
  "success": true,
  "data": {
    "id": "grid_abc123",
    "status": "running",
    "config": {
      "pair": "BTC-USDC",
      "upper_price": 100000,
      "lower_price": 90000,
      "grid_count": 10
    },
    "state": {
      "current_price": 95000,
      "position": 0.003,
      "active_buy_orders": 3,
      "active_sell_orders": 2,
      "total_trades": 15,
      "realized_pnl": 12.34,
      "unrealized_pnl": 5.67
    },
    "risk": {
      "risk_checks": 45,
      "orders_rejected": 2,
      "kill_switch": false
    },
    "started_at": "2025-12-29T10:00:00Z",
    "uptime_seconds": 3600
  }
}
```

### 获取网格订单

**GET** `/api/v2/grid/:id/orders`

```json
// Response
{
  "success": true,
  "data": {
    "buy_orders": [
      { "level": 0, "price": 90000, "status": "pending", "exchange_id": null },
      { "level": 1, "price": 92000, "status": "pending", "exchange_id": null }
    ],
    "sell_orders": [
      { "level": 2, "price": 94470, "status": "active", "exchange_id": "hl_123" }
    ],
    "filled_orders": [
      { "level": 2, "price": 94000, "side": "buy", "filled_at": "2025-12-29T10:05:00Z" }
    ]
  }
}
```

### 列出所有网格

**GET** `/api/v2/grid`

```json
// Response
{
  "success": true,
  "data": {
    "grids": [
      {
        "id": "grid_abc123",
        "pair": "BTC-USDC",
        "status": "running",
        "pnl": 12.34
      },
      {
        "id": "grid_def456",
        "pair": "ETH-USDC",
        "status": "stopped",
        "pnl": -5.67
      }
    ],
    "total": 2,
    "running": 1
  }
}
```

---

## 📊 回测 API

### 启动回测

**POST** `/api/v2/backtest/run`

```json
// Request
{
  "strategy": "dual_ma",
  "params": {
    "fast_period": 10,
    "slow_period": 30
  },
  "data": {
    "symbol": "BTCUSDT",
    "timeframe": "1h",
    "start_date": "2024-01-01",
    "end_date": "2024-12-31"
  },
  "config": {
    "initial_capital": 10000,
    "commission": 0.0005,
    "slippage": 0.0001
  }
}

// Response
{
  "success": true,
  "data": {
    "id": "bt_xyz789",
    "status": "queued",
    "estimated_duration": 30
  }
}
```

### 获取回测进度

**GET** `/api/v2/backtest/:id/progress`

```json
// Response
{
  "success": true,
  "data": {
    "id": "bt_xyz789",
    "status": "running",
    "progress": 0.45,
    "current_date": "2024-06-15",
    "trades_so_far": 127,
    "elapsed_seconds": 15
  }
}
```

**WebSocket 事件** (自动推送):
```json
{
  "type": "event",
  "channel": "backtest.bt_xyz789",
  "event": "progress",
  "data": {
    "progress": 0.46,
    "current_date": "2024-06-16"
  }
}
```

### 获取回测结果

**GET** `/api/v2/backtest/:id/result`

```json
// Response
{
  "success": true,
  "data": {
    "id": "bt_xyz789",
    "status": "completed",
    "metrics": {
      "total_return": 0.2534,
      "sharpe_ratio": 1.85,
      "max_drawdown": 0.12,
      "win_rate": 0.58,
      "total_trades": 342
    },
    "equity_curve": [
      { "date": "2024-01-01", "equity": 10000 },
      { "date": "2024-01-02", "equity": 10050 }
      // ...
    ],
    "trades": [
      // 最近 100 笔交易
    ]
  }
}
```

### 取消回测

**POST** `/api/v2/backtest/:id/cancel`

```json
// Response
{
  "success": true,
  "data": {
    "id": "bt_xyz789",
    "status": "cancelled",
    "progress_at_cancel": 0.45
  }
}
```

---

## 🎯 策略 API

### 启动策略

**POST** `/api/v2/strategy/:id/start`

```json
// Request
{
  "mode": "paper",  // paper | testnet | mainnet
  "params": {
    "fast_period": 10,
    "slow_period": 30
  },
  "symbols": ["BTC-USDC", "ETH-USDC"],
  "config_file": "config.test.json"
}

// Response
{
  "success": true,
  "data": {
    "instance_id": "strat_001",
    "strategy_id": "dual_ma",
    "status": "starting"
  }
}
```

### 停止策略

**POST** `/api/v2/strategy/:id/stop`

```json
// Request
{
  "instance_id": "strat_001",
  "close_positions": false
}

// Response
{
  "success": true,
  "data": {
    "instance_id": "strat_001",
    "status": "stopped",
    "final_pnl": 123.45
  }
}
```

### 热更新参数

**PUT** `/api/v2/strategy/:id/params`

```json
// Request
{
  "instance_id": "strat_001",
  "params": {
    "fast_period": 12
  }
}

// Response
{
  "success": true,
  "data": {
    "instance_id": "strat_001",
    "updated_params": ["fast_period"],
    "status": "updated"
  }
}
```

---

## ⚙️ 系统 API

### Kill Switch

**POST** `/api/v2/system/kill-switch`

```json
// Request
{
  "action": "activate",  // activate | deactivate
  "close_all_positions": true,
  "cancel_all_orders": true,
  "reason": "Manual emergency stop"
}

// Response
{
  "success": true,
  "data": {
    "kill_switch": true,
    "affected": {
      "grids_stopped": 2,
      "strategies_stopped": 3,
      "orders_cancelled": 15,
      "positions_closed": 5
    }
  }
}
```

### 系统健康

**GET** `/api/v2/system/health`

```json
// Response
{
  "success": true,
  "data": {
    "status": "healthy",
    "components": {
      "api_server": "up",
      "engine_manager": "up",
      "database": "up",
      "exchange_hyperliquid": "up"
    },
    "metrics": {
      "running_grids": 2,
      "running_strategies": 3,
      "active_backtests": 1,
      "memory_mb": 128,
      "uptime_seconds": 86400
    }
  }
}
```

### 获取日志

**GET** `/api/v2/system/logs`

Query params:
- `level`: debug | info | warn | error
- `source`: grid | backtest | strategy | system
- `limit`: number (default 100)
- `since`: ISO timestamp

```json
// Response
{
  "success": true,
  "data": {
    "logs": [
      {
        "timestamp": "2025-12-29T10:05:00Z",
        "level": "info",
        "source": "grid.grid_abc123",
        "message": "[FILL] BUY @ 94000.00 | Position: 0.001000"
      }
    ],
    "total": 1523,
    "has_more": true
  }
}
```

---

## 🔐 认证

### 登录

**POST** `/api/v2/auth/login`

```json
// Request
{
  "username": "admin",
  "password": "password"
}

// Response
{
  "success": true,
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIs...",
    "expires_at": "2025-12-30T10:00:00Z",
    "user": {
      "id": "user_001",
      "username": "admin",
      "role": "admin"
    }
  }
}
```

### Token 刷新

**POST** `/api/v2/auth/refresh`

```json
// Request
{
  "token": "current_token"
}

// Response
{
  "success": true,
  "data": {
    "token": "new_token",
    "expires_at": "2025-12-30T10:00:00Z"
  }
}
```

---

## ❌ 错误响应

所有错误遵循统一格式：

```json
{
  "success": false,
  "error": {
    "code": "GRID_NOT_FOUND",
    "message": "Grid with ID 'grid_abc123' not found",
    "details": {
      "id": "grid_abc123"
    }
  }
}
```

### 错误码

| 错误码 | HTTP 状态 | 说明 |
|--------|----------|------|
| `AUTH_REQUIRED` | 401 | 需要认证 |
| `AUTH_INVALID` | 401 | Token 无效 |
| `AUTH_EXPIRED` | 401 | Token 过期 |
| `FORBIDDEN` | 403 | 权限不足 |
| `NOT_FOUND` | 404 | 资源不存在 |
| `VALIDATION_ERROR` | 400 | 参数验证失败 |
| `GRID_ALREADY_RUNNING` | 409 | 网格已在运行 |
| `GRID_NOT_RUNNING` | 400 | 网格未运行 |
| `KILL_SWITCH_ACTIVE` | 503 | Kill Switch 激活中 |
| `INTERNAL_ERROR` | 500 | 服务器内部错误 |

---

## 📊 Rate Limiting

| 端点类型 | 限制 |
|----------|------|
| 认证端点 | 10 次/分钟 |
| 读取端点 | 100 次/分钟 |
| 写入端点 | 30 次/分钟 |
| WebSocket 消息 | 100 条/秒 |

超限响应：

```json
{
  "success": false,
  "error": {
    "code": "RATE_LIMITED",
    "message": "Too many requests",
    "retry_after": 30
  }
}
```

---

*创建时间: 2025-12-29*
