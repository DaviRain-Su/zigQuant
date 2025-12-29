# WebSocket 协议设计

> 实时双向通信协议规范

**版本**: v2.0.0
**状态**: 📋 设计阶段
**创建日期**: 2025-12-29

---

## 📋 概述

WebSocket 连接用于：
1. **服务端推送**: 实时状态更新、交易事件、日志流
2. **客户端命令**: 控制指令的低延迟发送
3. **订阅管理**: 按需订阅感兴趣的事件频道

---

## 🔌 连接建立

### 握手

```
GET /ws?token=<jwt_token> HTTP/1.1
Host: localhost:8080
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Protocol: zigquant-v2
Sec-WebSocket-Version: 13
```

### 认证流程

```
Client                                          Server
   │                                               │
   │─── WebSocket Handshake (with token) ─────────▶│
   │                                               │
   │◀─── 101 Switching Protocols ──────────────────│
   │                                               │
   │─── { type: "auth", token: "..." } ───────────▶│
   │                                               │
   │◀─── { type: "auth_result", success: true } ───│
   │                                               │
   │─── { type: "subscribe", channels: [...] } ───▶│
   │                                               │
   │◀─── { type: "subscribed", channels: [...] } ──│
   │                                               │
   │◀─── Events / Status Updates ──────────────────│
   │                                               │
```

---

## 📨 消息格式

### 基础消息结构

```typescript
interface WSMessage {
  // 消息类型
  type: 'auth' | 'auth_result' | 'subscribe' | 'unsubscribe' | 
        'subscribed' | 'event' | 'command' | 'response' | 'error' | 
        'ping' | 'pong';
  
  // 请求 ID (command/response 配对)
  id?: string;
  
  // 时间戳 (毫秒)
  timestamp: number;
  
  // 消息内容
  data?: any;
}
```

### 事件消息

```typescript
interface EventMessage extends WSMessage {
  type: 'event';
  channel: string;    // 频道名
  event: string;      // 事件名
  data: any;          // 事件数据
}
```

### 命令消息

```typescript
interface CommandMessage extends WSMessage {
  type: 'command';
  id: string;         // 唯一请求 ID
  action: string;     // 动作名称
  params: any;        // 动作参数
}
```

### 响应消息

```typescript
interface ResponseMessage extends WSMessage {
  type: 'response';
  id: string;         // 对应的请求 ID
  success: boolean;
  data?: any;
  error?: {
    code: string;
    message: string;
  };
}
```

---

## 📡 频道系统

### 频道命名规范

```
<category>.<instance_id>.<event_type>
```

示例：
- `grid.grid_abc123.order` - 特定网格的订单事件
- `grid.*.status` - 所有网格的状态事件
- `system.health` - 系统健康状态

### 支持的频道

#### 网格交易 (`grid.*`)

| 频道 | 事件 | 说明 |
|------|------|------|
| `grid.<id>.status` | - | 状态更新 (每秒) |
| `grid.<id>.order` | `placed`, `filled`, `cancelled` | 订单事件 |
| `grid.<id>.trade` | `executed` | 成交事件 |
| `grid.<id>.pnl` | `updated` | PnL 更新 |
| `grid.<id>.risk` | `check`, `rejected`, `kill_switch` | 风险事件 |
| `grid.<id>.lifecycle` | `started`, `stopped`, `error` | 生命周期 |

#### 回测 (`backtest.*`)

| 频道 | 事件 | 说明 |
|------|------|------|
| `backtest.<id>.progress` | - | 进度更新 (每秒) |
| `backtest.<id>.lifecycle` | `started`, `completed`, `cancelled`, `error` | 生命周期 |

#### 策略 (`strategy.*`)

| 频道 | 事件 | 说明 |
|------|------|------|
| `strategy.<id>.status` | - | 状态更新 |
| `strategy.<id>.signal` | `generated` | 信号生成 |
| `strategy.<id>.lifecycle` | `started`, `stopped`, `error` | 生命周期 |

#### 系统 (`system.*`)

| 频道 | 事件 | 说明 |
|------|------|------|
| `system.health` | - | 健康状态 (每 5 秒) |
| `system.log` | `debug`, `info`, `warn`, `error` | 日志流 |
| `system.kill_switch` | `activated`, `deactivated` | Kill Switch 状态 |
| `system.exchange` | `connected`, `disconnected`, `error` | 交易所连接 |

---

## 🔄 订阅管理

### 订阅

```json
{
  "type": "subscribe",
  "channels": [
    "grid.grid_abc123.*",
    "system.health",
    "system.log"
  ]
}
```

响应：

```json
{
  "type": "subscribed",
  "timestamp": 1703836800000,
  "data": {
    "channels": ["grid.grid_abc123.*", "system.health", "system.log"],
    "active_subscriptions": 3
  }
}
```

### 取消订阅

```json
{
  "type": "unsubscribe",
  "channels": ["system.log"]
}
```

### 通配符规则

| 模式 | 匹配 |
|------|------|
| `grid.*` | `grid.abc.status`, `grid.def.order`, ... |
| `grid.abc.*` | `grid.abc.status`, `grid.abc.order`, ... |
| `grid.*.status` | `grid.abc.status`, `grid.def.status`, ... |
| `*` | 所有频道 (不推荐) |

---

## 🎮 命令执行

### 通过 WebSocket 发送命令

```json
{
  "type": "command",
  "id": "cmd_001",
  "timestamp": 1703836800000,
  "action": "grid.start",
  "params": {
    "pair": "BTC-USDC",
    "upper_price": 100000,
    "lower_price": 90000,
    "grid_count": 10
  }
}
```

### 命令响应

成功：

```json
{
  "type": "response",
  "id": "cmd_001",
  "timestamp": 1703836800050,
  "success": true,
  "data": {
    "grid_id": "grid_abc123",
    "status": "starting"
  }
}
```

失败：

```json
{
  "type": "response",
  "id": "cmd_001",
  "timestamp": 1703836800050,
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "upper_price must be greater than lower_price"
  }
}
```

### 支持的命令

| 动作 | 参数 | 说明 |
|------|------|------|
| `grid.start` | GridConfig | 启动网格 |
| `grid.stop` | `{ id, cancel_orders }` | 停止网格 |
| `grid.update_params` | `{ id, params }` | 更新参数 |
| `backtest.run` | BacktestConfig | 启动回测 |
| `backtest.cancel` | `{ id }` | 取消回测 |
| `strategy.start` | StrategyConfig | 启动策略 |
| `strategy.stop` | `{ id }` | 停止策略 |
| `system.kill_switch` | `{ action, reason }` | Kill Switch |

---

## 💓 心跳机制

### 客户端 Ping

```json
{
  "type": "ping",
  "timestamp": 1703836800000
}
```

### 服务端 Pong

```json
{
  "type": "pong",
  "timestamp": 1703836800001
}
```

### 超时规则

- 客户端应每 30 秒发送 Ping
- 服务端 60 秒未收到 Ping 则断开连接
- 服务端每 30 秒也会主动发送 Ping

---

## 📊 事件示例

### 网格状态更新

```json
{
  "type": "event",
  "channel": "grid.grid_abc123.status",
  "event": "update",
  "timestamp": 1703836800000,
  "data": {
    "id": "grid_abc123",
    "current_price": 95000.50,
    "position": 0.003,
    "active_buy_orders": 3,
    "active_sell_orders": 2,
    "realized_pnl": 12.34,
    "unrealized_pnl": 5.67
  }
}
```

### 订单成交

```json
{
  "type": "event",
  "channel": "grid.grid_abc123.order",
  "event": "filled",
  "timestamp": 1703836800000,
  "data": {
    "grid_id": "grid_abc123",
    "level": 2,
    "side": "buy",
    "price": 94000,
    "amount": 0.001,
    "position_after": 0.003
  }
}
```

### 回测进度

```json
{
  "type": "event",
  "channel": "backtest.bt_xyz789.progress",
  "event": "update",
  "timestamp": 1703836800000,
  "data": {
    "id": "bt_xyz789",
    "progress": 0.45,
    "current_date": "2024-06-15",
    "trades_count": 127,
    "current_equity": 10523.45
  }
}
```

### 系统日志

```json
{
  "type": "event",
  "channel": "system.log",
  "event": "info",
  "timestamp": 1703836800000,
  "data": {
    "level": "info",
    "source": "grid.grid_abc123",
    "message": "[FILL] BUY @ 94000.00 | Position: 0.001000"
  }
}
```

### Kill Switch 激活

```json
{
  "type": "event",
  "channel": "system.kill_switch",
  "event": "activated",
  "timestamp": 1703836800000,
  "data": {
    "reason": "Daily loss limit exceeded",
    "affected": {
      "grids_stopped": 2,
      "strategies_stopped": 3,
      "orders_cancelled": 15
    }
  }
}
```

---

## 🔒 安全考虑

### 认证

1. WebSocket 连接必须携带有效 JWT Token
2. Token 过期后服务端主动断开连接
3. 支持通过 WebSocket 刷新 Token

### 授权

1. 订阅频道需要相应权限
2. 命令执行需要相应权限
3. 管理员可订阅所有频道

### 限流

| 操作 | 限制 |
|------|------|
| 消息发送 | 100 条/秒 |
| 订阅频道 | 50 个/连接 |
| 命令执行 | 10 条/秒 |

---

## 💻 客户端实现示例

### TypeScript 封装

```typescript
class ZigQuantWebSocket {
  private ws: WebSocket | null = null;
  private subscriptions = new Set<string>();
  private commandCallbacks = new Map<string, (res: any) => void>();
  private eventHandlers = new Map<string, ((data: any) => void)[]>();

  connect(url: string, token: string): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(`${url}?token=${token}`);
      
      this.ws.onopen = () => {
        this.startHeartbeat();
        resolve();
      };
      
      this.ws.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        this.handleMessage(msg);
      };
      
      this.ws.onerror = reject;
    });
  }

  subscribe(channels: string[]): void {
    channels.forEach(ch => this.subscriptions.add(ch));
    this.send({ type: 'subscribe', channels });
  }

  unsubscribe(channels: string[]): void {
    channels.forEach(ch => this.subscriptions.delete(ch));
    this.send({ type: 'unsubscribe', channels });
  }

  on(channel: string, handler: (data: any) => void): void {
    if (!this.eventHandlers.has(channel)) {
      this.eventHandlers.set(channel, []);
    }
    this.eventHandlers.get(channel)!.push(handler);
  }

  command(action: string, params: any): Promise<any> {
    return new Promise((resolve, reject) => {
      const id = `cmd_${Date.now()}_${Math.random().toString(36).slice(2)}`;
      
      this.commandCallbacks.set(id, (res) => {
        this.commandCallbacks.delete(id);
        if (res.success) {
          resolve(res.data);
        } else {
          reject(res.error);
        }
      });
      
      this.send({ type: 'command', id, action, params });
      
      // Timeout
      setTimeout(() => {
        if (this.commandCallbacks.has(id)) {
          this.commandCallbacks.delete(id);
          reject({ code: 'TIMEOUT', message: 'Command timeout' });
        }
      }, 30000);
    });
  }

  private handleMessage(msg: WSMessage): void {
    switch (msg.type) {
      case 'event':
        this.handleEvent(msg as EventMessage);
        break;
      case 'response':
        const callback = this.commandCallbacks.get(msg.id!);
        if (callback) callback(msg);
        break;
      case 'ping':
        this.send({ type: 'pong', timestamp: Date.now() });
        break;
    }
  }

  private handleEvent(msg: EventMessage): void {
    // 精确匹配
    const handlers = this.eventHandlers.get(msg.channel) || [];
    handlers.forEach(h => h(msg.data));
    
    // 通配符匹配
    this.eventHandlers.forEach((handlers, pattern) => {
      if (this.matchPattern(pattern, msg.channel)) {
        handlers.forEach(h => h(msg.data));
      }
    });
  }

  private matchPattern(pattern: string, channel: string): boolean {
    const regex = pattern.replace(/\*/g, '[^.]+');
    return new RegExp(`^${regex}$`).test(channel);
  }

  private send(msg: any): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({ ...msg, timestamp: Date.now() }));
    }
  }

  private startHeartbeat(): void {
    setInterval(() => {
      this.send({ type: 'ping' });
    }, 30000);
  }
}

// 使用示例
const ws = new ZigQuantWebSocket();
await ws.connect('ws://localhost:8080/ws', 'jwt_token');

ws.subscribe(['grid.*', 'system.health']);

ws.on('grid.*.status', (data) => {
  console.log('Grid status:', data);
});

const result = await ws.command('grid.start', {
  pair: 'BTC-USDC',
  upper_price: 100000,
  lower_price: 90000,
  grid_count: 10
});
console.log('Grid started:', result.grid_id);
```

---

## 🔄 重连策略

### 客户端重连

```typescript
class ReconnectingWebSocket {
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private reconnectDelay = 1000;
  
  private reconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('Max reconnect attempts reached');
      return;
    }
    
    const delay = Math.min(
      this.reconnectDelay * Math.pow(2, this.reconnectAttempts),
      30000  // Max 30 seconds
    );
    
    setTimeout(() => {
      this.reconnectAttempts++;
      this.connect();
    }, delay);
  }
  
  private onConnect(): void {
    this.reconnectAttempts = 0;
    // 重新订阅之前的频道
    this.resubscribe();
  }
}
```

---

*创建时间: 2025-12-29*
