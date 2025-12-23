# Hyperliquid API 快速参考

**版本**: v1.0
**更新日期**: 2025-12-23
**完整文档**: [HYPERLIQUID_API_RESEARCH.md](../stories/v0.2-mvp/HYPERLIQUID_API_RESEARCH.md)

---

## 🔗 连接信息

| 环境 | HTTP API | WebSocket |
|------|----------|-----------|
| **主网** | `https://api.hyperliquid.xyz` | `wss://api.hyperliquid.xyz/ws` |
| **测试网** | `https://api.hyperliquid-testnet.xyz` | `wss://api.hyperliquid-testnet.xyz/ws` |

---

## 📡 Info API（无需认证）

所有请求: `POST /info`

| 端点类型 | 请求体 | 说明 |
|---------|--------|------|
| `allMids` | `{"type": "allMids"}` | 所有币种中间价 |
| `meta` | `{"type": "meta"}` | 资产元数据 |
| `metaAndAssetCtxs` | `{"type": "metaAndAssetCtxs"}` | 元数据+上下文 |
| `clearinghouseState` | `{"type": "clearinghouseState", "user": "0x..."}` | 账户状态 |
| `userState` | `{"type": "userState", "user": "0x..."}` | 用户状态（含仓位） |
| `spotUserState` | `{"type": "spotUserState", "user": "0x..."}` | 现货账户 |
| `openOrders` | `{"type": "openOrders", "user": "0x..."}` | 未完成订单 |
| `userFills` | `{"type": "userFills", "user": "0x..."}` | 成交历史 |
| `l2Book` | `{"type": "l2Book", "coin": "ETH"}` | L2 订单簿 |
| `candleSnapshot` | `{"type": "candleSnapshot", "req": {...}}` | K线快照 |
| `historicalOrders` | `{"type": "historicalOrders", "user": "0x..."}` | 历史订单 |

---

## 💱 Exchange API（需要 Ed25519 签名）

所有请求: `POST /exchange`

### 核心操作

| 操作 | Python SDK 方法 | 说明 |
|------|----------------|------|
| **下单** | `exchange.order(coin, is_buy, sz, limit_px, order_type, ...)` | 下限价单 |
| **批量下单** | `exchange.bulk_orders(order_requests)` | 批量下单 |
| **撤单** | `exchange.cancel(coin, oid)` | 撤销订单 |
| **批量撤单** | `exchange.bulk_cancel(cancel_requests)` | 批量撤单 |
| **修改订单** | `exchange.modify_order(oid, coin, ...)` | 修改现有订单 |
| **市价开仓** | `exchange.market_open(coin, is_buy, sz, slippage)` | 市价建仓 |
| **市价平仓** | `exchange.market_close(coin, sz, slippage)` | 市价平仓 |
| **定时撤单** | `exchange.schedule_cancel(time)` | 定时撤销所有订单 |

### 订单类型 (order_type)

```python
# 限价单 GTC (Good-Til-Cancelled)
order_type = {"limit": {"tif": "Gtc"}}

# 限价单 IOC (Immediate-Or-Cancel)
order_type = {"limit": {"tif": "Ioc"}}

# 限价单 ALO (Add-Liquidity-Only, 只做 Maker)
order_type = {"limit": {"tif": "Alo"}}

# 触发单 (Stop Loss / Take Profit)
order_type = {
    "trigger": {
        "triggerPx": "2000.0",
        "isMarket": False,
        "tpsl": "tp"  # "tp" 或 "sl"
    }
}
```

---

## 🔌 WebSocket 订阅

### 订阅消息格式

```json
{
  "method": "subscribe",
  "subscription": {
    "type": "订阅类型",
    "coin": "币种",  // 部分类型需要
    "user": "地址"   // 部分类型需要
  }
}
```

### 常用订阅类型

| 类型 | 参数 | 用途 | Story |
|------|------|------|-------|
| **l2Book** | `coin` | L2 订单簿实时更新 | Story 008 |
| **trades** | `coin` | 实时成交数据 | Story 006/007 |
| **allMids** | - | 所有币种中间价 | Story 006/008 |
| **userFills** | `user` | 用户成交事件 | Story 011 |
| **userEvents** | `user` | 用户订单事件 | Story 010 |
| **orderUpdates** | `user` | 订单状态更新 | Story 010 |
| **clearinghouseState** | `user` | 账户状态更新 | Story 011 |
| **candle** | `coin`, `interval` | K线数据 | 未来功能 |
| **bbo** | `coin` | 最优买卖价 | Story 008 |

---

## 🔐 认证与签名

### Ed25519 签名流程

```python
from eth_account import Account
import json

# 1. 准备请求体
action = {
    "type": "order",
    "orders": [...],
    "grouping": "na"
}

# 2. 构造签名消息
connection_id = bytes.fromhex(...)  # 连接 ID
nonce = int(time.time() * 1000)

# 3. 签名
signature = account.sign_message(...)

# 4. 发送请求
payload = {
    "action": action,
    "nonce": nonce,
    "signature": signature,
    "vaultAddress": None  # 或指定金库地址
}
```

### Nonce 规则

- **格式**: 毫秒时间戳
- **要求**: 严格递增
- **建议**: 使用 `int(time.time() * 1000)`
- **错误**: 如果 nonce 太旧，会收到 "Nonce too small" 错误

---

## 📊 关键数据结构

### UserState (账户状态)

```json
{
  "assetPositions": [
    {
      "position": {
        "coin": "ETH",
        "szi": "1.5",              // 仓位大小（正=多，负=空）
        "entryPx": "2000.0",       // 入场均价
        "leverage": {
          "type": "cross",         // 或 "isolated"
          "value": 5
        },
        "liquidationPx": "1800.0", // 清算价
        "marginUsed": "600.0",     // 已用保证金
        "positionValue": "3000.0", // 仓位价值
        "unrealizedPnl": "150.0",  // 未实现盈亏
        "returnOnEquity": "0.25"   // ROE = 25%
      },
      "type": "oneWay"
    }
  ],
  "marginSummary": {
    "accountValue": "10000.0",     // 账户总价值
    "totalMarginUsed": "600.0",    // 总保证金
    "totalNtlPos": "3000.0",       // 总持仓价值
    "totalRawUsd": "9850.0"        // 原始 USD 价值
  }
}
```

### OrderBook (l2Book)

```json
{
  "coin": "ETH",
  "time": 1640000000000,
  "levels": [
    [  // Bids (买单)
      {"px": "2000.5", "sz": "10.0", "n": 1},
      {"px": "2000.0", "sz": "5.0", "n": 2}
    ],
    [  // Asks (卖单)
      {"px": "2001.0", "sz": "8.0", "n": 1},
      {"px": "2001.5", "sz": "12.0", "n": 1}
    ]
  ]
}
```

### UserFill (成交记录)

```json
{
  "coin": "ETH",
  "px": "2000.5",           // 成交价
  "sz": "0.1",              // 成交量
  "side": "B",              // B=买, A=卖
  "time": 1640000000000,
  "dir": "Open Long",       // 方向
  "closedPnl": "0.0",       // 平仓盈亏
  "hash": "0x...",
  "oid": 123456,            // 订单 ID
  "crossed": false,
  "fee": "0.01",            // 手续费
  "feeToken": "USDC",
  "startPosition": "0.0"    // 开始仓位
}
```

---

## ⚠️ 速率限制

### 请求限制

| 类型 | 限制 | 说明 |
|------|------|------|
| **Info API** | 20 req/s | 每个 IP |
| **Exchange API** | 20 req/s | 每个用户 |
| **WebSocket** | 1000 订阅 | 每个 IP |

### 建议

- 使用客户端限流器
- 批量操作使用 bulk API
- WebSocket 优先于轮询

---

## 🚨 常见错误

| 错误消息 | 原因 | 解决方案 |
|---------|------|---------|
| `Nonce too small` | nonce 不是递增 | 使用当前时间戳 |
| `Invalid signature` | 签名错误 | 检查私钥和消息格式 |
| `Insufficient margin` | 保证金不足 | 减少订单数量或杠杆 |
| `Price too far from oracle` | 价格偏离过大 | 调整限价 |
| `Order would be liquidated` | 会导致清算 | 降低杠杆或增加保证金 |

---

## 📝 快速示例

### 示例 1: 查询 ETH 价格

```bash
curl -X POST https://api.hyperliquid.xyz/info \
  -H "Content-Type: application/json" \
  -d '{"type": "allMids"}'
```

### 示例 2: 获取订单簿

```python
from hyperliquid.info import Info
from hyperliquid.utils import constants

info = Info(constants.TESTNET_API_URL, skip_ws=True)
l2_book = info.l2_snapshot("ETH")
print(l2_book)
```

### 示例 3: 下限价买单

```python
from hyperliquid.exchange import Exchange

exchange = Exchange(account, constants.TESTNET_API_URL)

order_result = exchange.order(
    coin="ETH",
    is_buy=True,
    sz=0.1,
    limit_px=2000.0,
    order_type={"limit": {"tif": "Gtc"}},
    reduce_only=False
)
print(order_result)
```

### 示例 4: WebSocket 订阅订单簿

```python
from hyperliquid.info import Info

def on_l2_book(msg):
    print(f"Order Book Update: {msg['data']['coin']}")

info = Info(constants.TESTNET_API_URL, skip_ws=False)
info.subscribe({"type": "l2Book", "coin": "ETH"}, on_l2_book)
```

---

## 🔗 相关资源

- **完整研究文档**: [HYPERLIQUID_API_RESEARCH.md](../stories/v0.2-mvp/HYPERLIQUID_API_RESEARCH.md)
- **官方文档**: https://hyperliquid.gitbook.io/hyperliquid-docs
- **Python SDK**: https://github.com/hyperliquid-dex/hyperliquid-python-sdk
- **Stories 映射**: 见研究文档第 12 章

---

*快速参考 | 开发时查阅 | 详见完整文档*
