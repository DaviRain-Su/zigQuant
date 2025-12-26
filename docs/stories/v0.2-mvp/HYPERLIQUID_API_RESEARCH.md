# Hyperliquid API 完整研究文档

**生成日期**: 2025-12-23
**版本**: v1.0
**目标**: 为 ZigQuant v0.2 MVP 提供 Hyperliquid 集成的完整技术参考

---

## 目录

1. [概述](#概述)
2. [API 端点](#api-端点)
3. [Info API 详细说明](#info-api-详细说明)
4. [Exchange API 详细说明](#exchange-api-详细说明)
5. [WebSocket API](#websocket-api)
6. [认证与签名](#认证与签名)
7. [订单类型与参数](#订单类型与参数)
8. [数据结构](#数据结构)
9. [错误处理](#错误处理)
10. [速率限制](#速率限制)
11. [Python SDK 参考](#python-sdk-参考)
12. [与 ZigQuant Stories 的对应关系](#与-zigquant-stories-的对应关系)

---

## 概述

### Hyperliquid 基本信息

- **类型**: 高性能 Layer 1 区块链 DEX
- **共识算法**: HyperBFT
- **架构**: HyperCore (订单簿) + HyperEVM (智能合约)
- **性能**: 200,000 订单/秒
- **特点**: 完全链上、低延迟 (<10ms)

### API 环境

| 环境 | HTTP API | WebSocket API |
|------|----------|---------------|
| 主网 | `https://api.hyperliquid.xyz` | `wss://api.hyperliquid.xyz/ws` |
| 测试网 | `https://api.hyperliquid-testnet.xyz` | `wss://api.hyperliquid-testnet.xyz/ws` |

### Python SDK

- **仓库**: [hyperliquid-dex/hyperliquid-python-sdk](https://github.com/hyperliquid-dex/hyperliquid-python-sdk)
- **安装**: `pip install hyperliquid-python-sdk`
- **Python 版本**: >=3.9, <4.0
- **许可证**: MIT

---

## API 端点

### 端点分类

Hyperliquid API 分为两大类：

1. **Info API** (`/info`): 只读数据查询，无需认证（公开市场数据）
2. **Exchange API** (`/exchange`): 交易操作，需要 Ed25519 签名认证

### 请求格式

所有 API 端点都使用 `POST` 方法，请求体为 JSON 格式：

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"type": "allMids"}' \
  https://api.hyperliquid.xyz/info
```

---

## Info API 详细说明

### 1. allMids - 获取所有币种中间价

获取所有交易对的中间价格（订单簿 mid price）。

**端点**: `/info`
**请求体**:
```json
{
  "type": "allMids",
  "dex": ""
}
```

**参数说明**:
- `dex`: (可选) DEX 标识，默认为 `""` 表示第一个 perp DEX

**响应示例**:
```json
{
  "BTC": "97000.5",
  "ETH": "3500.25",
  "SOL": "180.75"
}
```

**Python SDK 用法**:
```python
from hyperliquid.info import Info
from hyperliquid.utils import constants

info = Info(constants.TESTNET_API_URL, skip_ws=True)
all_mids = info.all_mids()
print(all_mids)  # {"BTC": "97000.5", ...}
```

**注意事项**:
- 如果订单簿为空，使用最近成交价作为 fallback
- 包含 spot 币种的 mid price

---

### 2. clearinghouseState (userState) - 获取账户状态

获取用户的永续合约账户摘要，包括余额、仓位、保证金等。

**端点**: `/info`
**请求体**:
```json
{
  "type": "clearinghouseState",
  "user": "0x31ca8395cf837de08b24da3f660e77761dfb974b"
}
```

**参数说明**:
- `user`: 用户地址（主账户或子账户地址，**不是** API wallet 地址）

**响应示例**:
```json
{
  "assetPositions": [
    {
      "position": {
        "coin": "ETH",
        "cumFunding": {
          "allTime": "514.085417",
          "sinceChange": "0.0",
          "sinceOpen": "0.0"
        },
        "entryPx": "2986.3",
        "leverage": {
          "rawUsd": "-95.059824",
          "type": "isolated",
          "value": 20
        },
        "liquidationPx": "2866.26936529",
        "marginUsed": "4.967826",
        "maxLeverage": 50,
        "positionValue": "100.02765",
        "returnOnEquity": "-0.0026789",
        "szi": "0.0335",
        "unrealizedPnl": "-0.0134"
      },
      "type": "oneWay"
    }
  ],
  "crossMaintenanceMarginUsed": "0.0",
  "crossMarginSummary": {
    "accountValue": "13104.514502",
    "totalMarginUsed": "0.0",
    "totalNtlPos": "0.0",
    "totalRawUsd": "13104.514502"
  },
  "marginSummary": {
    "accountValue": "13109.482328",
    "totalMarginUsed": "4.967826",
    "totalNtlPos": "100.02765",
    "totalRawUsd": "13009.454678"
  },
  "time": 1708622398623,
  "withdrawable": "13104.514502"
}
```

**字段说明**:
- `assetPositions`: 当前持仓数组
  - `position.coin`: 币种
  - `position.szi`: 仓位大小（有符号，正数=多头，负数=空头）
  - `position.entryPx`: 开仓均价
  - `position.leverage.type`: `"cross"` 或 `"isolated"`
  - `position.leverage.value`: 杠杆倍数
  - `position.liquidationPx`: 清算价格
  - `position.unrealizedPnl`: 未实现盈亏
  - `position.marginUsed`: 已用保证金
- `marginSummary.accountValue`: 账户总价值
- `marginSummary.totalMarginUsed`: 总已用保证金
- `withdrawable`: 可提现金额

**Python SDK 用法**:
```python
user_address = "0x31ca8395cf837de08b24da3f660e77761dfb974b"
user_state = info.user_state(user_address)

# 访问仓位信息
for asset_pos in user_state["assetPositions"]:
    position = asset_pos["position"]
    print(f"{position['coin']}: {position['szi']} @ {position['entryPx']}")
```

---

### 3. spotUserState - 获取现货账户状态

获取用户的现货账户余额。

**端点**: `/info`
**请求体**:
```json
{
  "type": "spotUserState",
  "user": "0x..."
}
```

**Python SDK 用法**:
```python
spot_state = info.spot_user_state(user_address)
```

---

### 4. openOrders - 获取未完成订单

获取用户当前所有未完成的订单。

**端点**: `/info`
**请求体**:
```json
{
  "type": "openOrders",
  "user": "0x..."
}
```

**Python SDK 用法**:
```python
open_orders = info.open_orders(user_address)
```

---

### 5. frontendOpenOrders - 获取前端展示的未完成订单

类似 `openOrders`，但包含额外的前端展示信息。

**Python SDK 用法**:
```python
frontend_orders = info.frontend_open_orders(user_address)
```

---

### 6. userFills - 获取用户成交历史

获取用户的成交记录。

**端点**: `/info`
**请求体**:
```json
{
  "type": "userFills",
  "user": "0x..."
}
```

**响应示例**:
```json
[
  {
    "closedPnl": "0.0",
    "coin": "AVAX",
    "crossed": false,
    "dir": "Open Long",
    "hash": "0xa166e3fa...",
    "oid": 90542681,
    "px": "18.435",
    "side": "B",
    "startPosition": "26.86",
    "sz": "93.53",
    "time": 1681222254710,
    "fee": "0.01",
    "feeToken": "USDC",
    "builderFee": "0.01",
    "tid": 118906512037719
  }
]
```

**字段说明**:
- `coin`: 币种
- `side`: `"B"` (买) 或 `"A"` (卖)
- `px`: 成交价格
- `sz`: 成交数量
- `dir`: 方向 (`"Open Long"`, `"Close Short"`, 等)
- `closedPnl`: 已实现盈亏
- `fee`: 手续费
- `oid`: 订单 ID
- `tid`: 成交 ID

**Python SDK 用法**:
```python
fills = info.user_fills(user_address)

# 按时间范围查询
fills_by_time = info.user_fills_by_time(
    user_address,
    start_time=1640000000000,
    end_time=1650000000000,
    aggregate_by_time=False
)
```

---

### 7. meta - 获取交易所元数据

获取所有可交易资产的元数据信息。

**端点**: `/info`
**请求体**:
```json
{
  "type": "meta"
}
```

**响应**:
包含 `universe` 数组，每个元素是一个资产信息：
```json
{
  "universe": [
    {
      "name": "BTC",
      "szDecimals": 5,
      "maxLeverage": 50,
      "onlyIsolated": false
    }
  ]
}
```

**字段说明**:
- `name`: 资产名称
- `szDecimals`: 数量精度（小数位数）
- `maxLeverage`: 最大杠杆倍数
- `onlyIsolated`: 是否仅支持逐仓模式

**Python SDK 用法**:
```python
meta = info.meta()
universe = meta["universe"]

# 获取资产索引
asset_index = info.name_to_asset("ETH")
```

---

### 8. metaAndAssetCtxs - 获取元数据和资产上下文

同时获取元数据和资产上下文信息。

**Python SDK 用法**:
```python
meta_and_ctx = info.meta_and_asset_ctxs()
```

---

### 9. spotMeta - 获取现货元数据

获取现货市场的元数据。

**Python SDK 用法**:
```python
spot_meta = info.spot_meta()
```

---

### 10. l2Snapshot (l2Book) - 获取订单簿快照

获取指定币种的 L2 订单簿快照。

**端点**: `/info`
**请求体**:
```json
{
  "type": "l2Book",
  "coin": "ETH"
}
```

**响应示例**:
```json
{
  "coin": "ETH",
  "time": 1640000000000,
  "levels": [
    [
      {"px": "2000.5", "sz": "10.0", "n": 1},
      {"px": "2000.0", "sz": "5.0", "n": 1}
    ],
    [
      {"px": "2001.0", "sz": "8.0", "n": 1},
      {"px": "2001.5", "sz": "12.0", "n": 1}
    ]
  ]
}
```

**字段说明**:
- `levels[0]`: Bids (买单)
- `levels[1]`: Asks (卖单)
- `px`: 价格
- `sz`: 数量
- `n`: 订单数量

**Python SDK 用法**:
```python
orderbook = info.l2_snapshot("ETH")
bids = orderbook["levels"][0]
asks = orderbook["levels"][1]
```

---

### 11. candlesSnapshot - 获取 K 线数据

获取 K 线（蜡烛图）历史数据。

**端点**: `/info`
**请求体**:
```json
{
  "type": "candleSnapshot",
  "req": {
    "coin": "ETH",
    "interval": "1h",
    "startTime": 1640000000000,
    "endTime": 1650000000000
  }
}
```

**参数说明**:
- `interval`: K 线周期 (`"1m"`, `"5m"`, `"15m"`, `"1h"`, `"4h"`, `"1d"`)
- `startTime`: 开始时间戳（毫秒）
- `endTime`: 结束时间戳（毫秒）

**Python SDK 用法**:
```python
candles = info.candles_snapshot(
    coin="ETH",
    interval="1h",
    startTime=1640000000000,
    endTime=1650000000000
)
```

---

### 12. fundingHistory - 获取资金费率历史

获取永续合约的资金费率历史数据。

**Python SDK 用法**:
```python
funding_history = info.funding_history(
    coin="ETH",
    startTime=1640000000000,
    endTime=1650000000000
)
```

---

### 13. userFees - 获取用户费率

获取用户的交易费率信息。

**Python SDK 用法**:
```python
user_fees = info.user_fees(user_address)
```

---

### 14. queryOrderByOid - 根据 OID 查询订单

根据订单 ID (OID) 查询订单详情。

**Python SDK 用法**:
```python
order_status = info.query_order_by_oid(user_address, oid=77738308)
```

---

### 15. queryOrderByCloid - 根据 CLOID 查询订单

根据客户端订单 ID (CLOID) 查询订单详情。

**Python SDK 用法**:
```python
order_status = info.query_order_by_cloid(user_address, cloid="my-order-123")
```

---

### 16. historicalOrders - 获取历史订单

获取用户的历史订单（最多 2000 条最近的订单）。

**端点**: `/info`
**请求体**:
```json
{
  "type": "historicalOrders",
  "user": "0x..."
}
```

**响应示例**:
```json
[
  {
    "order": {
      "coin": "ETH",
      "side": "A",
      "limitPx": "2412.7",
      "sz": "0.0",
      "oid": 1,
      "timestamp": 1724361546645,
      "origSz": "0.01"
    },
    "status": "filled",
    "statusTimestamp": 1724361546645
  }
]
```

**Python SDK 用法**:
```python
historical_orders = info.historical_orders(user_address)
```

---

### 17. userNonFundingLedgerUpdates - 获取非资金费用账本更新

获取除资金费用外的账本更新记录。

**Python SDK 用法**:
```python
ledger_updates = info.user_non_funding_ledger_updates(
    user_address,
    startTime=1640000000000,
    endTime=1650000000000
)
```

---

### Info API 完整方法列表

| 方法 | 说明 | 需要用户地址 |
|------|------|-------------|
| `all_mids()` | 所有币种中间价 | ✗ |
| `user_state(address)` | 用户账户状态 | ✓ |
| `spot_user_state(address)` | 现货账户状态 | ✓ |
| `open_orders(address)` | 未完成订单 | ✓ |
| `frontend_open_orders(address)` | 前端未完成订单 | ✓ |
| `user_fills(address)` | 用户成交历史 | ✓ |
| `user_fills_by_time(address, start, end)` | 按时间范围查询成交 | ✓ |
| `meta()` | 交易所元数据 | ✗ |
| `meta_and_asset_ctxs()` | 元数据和资产上下文 | ✗ |
| `spot_meta()` | 现货元数据 | ✗ |
| `spot_meta_and_asset_ctxs()` | 现货元数据和上下文 | ✗ |
| `l2_snapshot(coin)` | L2 订单簿快照 | ✗ |
| `candles_snapshot(coin, interval, start, end)` | K 线数据 | ✗ |
| `funding_history(coin, start, end)` | 资金费率历史 | ✗ |
| `user_funding_history(user, start, end)` | 用户资金费率历史 | ✓ |
| `user_fees(address)` | 用户费率 | ✓ |
| `query_order_by_oid(user, oid)` | 根据 OID 查询订单 | ✓ |
| `query_order_by_cloid(user, cloid)` | 根据 CLOID 查询订单 | ✓ |
| `historical_orders(user)` | 历史订单 | ✓ |
| `user_non_funding_ledger_updates(user, start, end)` | 非资金费用账本 | ✓ |
| `portfolio(user)` | 用户组合 | ✓ |
| `user_twap_slice_fills(user)` | TWAP 切片成交 | ✓ |

---

## Exchange API 详细说明

Exchange API 用于执行交易操作，所有请求都需要 **Ed25519 签名认证**。

### 1. order - 下单

下限价单或市价单。

**端点**: `/exchange`
**请求体**:
```json
{
  "action": {
    "type": "order",
    "orders": [
      {
        "a": 0,
        "b": true,
        "p": "2000.0",
        "s": "0.1",
        "r": false,
        "t": {
          "limit": {
            "tif": "Gtc"
          }
        }
      }
    ],
    "grouping": "na"
  },
  "nonce": 1640000000000,
  "signature": {
    "r": "0x...",
    "s": "0x...",
    "v": 27
  },
  "vaultAddress": null
}
```

**订单参数**:
- `a`: 资产索引（Asset Index）
  - 永续合约：从 `meta.universe` 获取索引
  - 现货：`10000 + spotMeta.universe 索引`
- `b`: 买/卖方向 (`true` = 买, `false` = 卖)
- `p`: 限价价格（字符串）
- `s`: 订单数量（字符串）
- `r`: 仅减仓标志 (`true` = reduce-only)
- `t`: 订单类型
  - `{"limit": {"tif": "Gtc"}}` - Good-til-Cancelled
  - `{"limit": {"tif": "Ioc"}}` - Immediate-or-Cancel
  - `{"limit": {"tif": "Alo"}}` - Add-Liquidity-Only (Post-only)
- `c`: (可选) 客户端订单 ID (CLOID)

**响应示例 - 成功（订单挂单）**:
```json
{
  "status": "ok",
  "response": {
    "type": "order",
    "data": {
      "statuses": [
        {
          "resting": {
            "oid": 77738308
          }
        }
      ]
    }
  }
}
```

**响应示例 - 成功（订单完全成交）**:
```json
{
  "status": "ok",
  "response": {
    "type": "order",
    "data": {
      "statuses": [
        {
          "filled": {
            "totalSz": "0.02",
            "avgPx": "1891.4",
            "oid": 77747314
          }
        }
      ]
    }
  }
}
```

**响应示例 - 错误**:
```json
{
  "status": "ok",
  "response": {
    "type": "order",
    "data": {
      "statuses": [
        {
          "error": "Order must have minimum value of $10."
        }
      ]
    }
  }
}
```

**Python SDK 用法**:
```python
from hyperliquid.exchange import Exchange
from hyperliquid.utils import constants

exchange = Exchange(
    wallet,  # ethers.Wallet 实例
    constants.TESTNET_API_URL
)

# 下限价单
order_result = exchange.order(
    coin="ETH",
    is_buy=True,
    sz=0.2,
    limit_px=1100,
    order_type={"limit": {"tif": "Gtc"}},
    reduce_only=False
)

# 检查订单状态
if order_result["status"] == "ok":
    status = order_result["response"]["data"]["statuses"][0]
    if "resting" in status:
        oid = status["resting"]["oid"]
        print(f"Order placed with OID: {oid}")
    elif "filled" in status:
        print(f"Order filled: {status['filled']}")
```

---

### 2. cancel - 撤单

撤销单个订单。

**端点**: `/exchange`
**请求体**:
```json
{
  "action": {
    "type": "cancel",
    "cancels": [
      {
        "a": 0,
        "o": 77738308
      }
    ]
  },
  "nonce": 1640000000000,
  "signature": {...}
}
```

**参数**:
- `a`: 资产索引
- `o`: 订单 ID (OID)

**响应示例**:
```json
{
  "status": "ok",
  "response": {
    "type": "cancel",
    "data": {
      "statuses": ["success"]
    }
  }
}
```

**错误响应**:
```json
{
  "status": "ok",
  "response": {
    "type": "cancel",
    "data": {
      "statuses": [
        {
          "error": "Order was never placed, already canceled, or filled."
        }
      ]
    }
  }
}
```

**Python SDK 用法**:
```python
# 撤销订单
cancel_result = exchange.cancel(coin="ETH", oid=77738308)
print(cancel_result)
```

---

### 3. cancelByCloid - 根据 CLOID 撤单

根据客户端订单 ID 撤销订单。

**Python SDK 用法**:
```python
cancel_result = exchange.cancel_by_cloid(coin="ETH", cloid="my-order-123")
```

---

### 4. bulkCancel - 批量撤单

批量撤销多个订单。

**Python SDK 用法**:
```python
from hyperliquid.exchange import CancelRequest

cancel_requests = [
    CancelRequest(coin="ETH", oid=123),
    CancelRequest(coin="BTC", oid=456),
]
bulk_result = exchange.bulk_cancel(cancel_requests)
```

---

### 5. modifyOrder - 修改订单

修改现有订单的参数。

**Python SDK 用法**:
```python
modify_result = exchange.modify_order(
    oid=77738308,
    coin="ETH",
    is_buy=True,
    sz=0.3,
    limit_px=2100,
    order_type={"limit": {"tif": "Gtc"}},
    reduce_only=False
)
```

---

### 6. bulkModifyOrders - 批量修改订单

批量修改多个订单。

**Python SDK 用法**:
```python
modify_requests = [...]
bulk_modify_result = exchange.bulk_modify_orders_new(modify_requests)
```

---

### 7. marketOpen - 市价开仓

以市价开仓（激进吃单）。

**Python SDK 用法**:
```python
# 市价买入 0.1 ETH
market_result = exchange.market_open(
    coin="ETH",
    is_buy=True,
    sz=0.1,
    px=None,  # 使用当前市价
    slippage=0.05  # 5% 滑点保护
)
```

---

### 8. marketClose - 市价平仓

以市价平仓。

**Python SDK 用法**:
```python
# 平仓全部 ETH 仓位
market_close_result = exchange.market_close(
    coin="ETH",
    sz=None,  # None 表示全部平仓
    px=None,
    slippage=0.05
)
```

---

### 9. scheduleCancel - 定时撤单

设置定时撤销所有订单。

**Python SDK 用法**:
```python
import time

# 10 秒后撤销所有订单
cancel_time = int(time.time() * 1000) + 10000
exchange.schedule_cancel(time=cancel_time)
```

---

### Exchange API 完整方法列表

| 方法 | 说明 | 需要签名 |
|------|------|---------|
| `order(coin, is_buy, sz, limit_px, order_type, ...)` | 下单 | ✓ |
| `bulk_orders(order_requests, ...)` | 批量下单 | ✓ |
| `cancel(coin, oid)` | 撤单 | ✓ |
| `cancel_by_cloid(coin, cloid)` | 根据 CLOID 撤单 | ✓ |
| `bulk_cancel(cancel_requests)` | 批量撤单 | ✓ |
| `bulk_cancel_by_cloid(cancel_requests)` | 批量根据 CLOID 撤单 | ✓ |
| `modify_order(oid, coin, ...)` | 修改订单 | ✓ |
| `bulk_modify_orders_new(modify_requests)` | 批量修改订单 | ✓ |
| `market_open(coin, is_buy, sz, px, slippage)` | 市价开仓 | ✓ |
| `market_close(coin, sz, px, slippage)` | 市价平仓 | ✓ |
| `schedule_cancel(time)` | 定时撤单 | ✓ |

---

## WebSocket API

### 连接信息

- **主网**: `wss://api.hyperliquid.xyz/ws`
- **测试网**: `wss://api.hyperliquid-testnet.xyz/ws`
- **订阅限制**: 每个 IP 最多 1000 个订阅

### 订阅消息格式

```json
{
  "method": "subscribe",
  "subscription": {
    "type": "trades",
    "coin": "SOL"
  }
}
```

### 订阅确认

```json
{
  "channel": "subscriptionResponse",
  "data": {
    "method": "subscribe",
    "subscription": {
      "type": "trades",
      "coin": "SOL"
    }
  }
}
```

### 订阅类型完整列表

| 订阅类型 | 参数 | 数据格式 | 说明 |
|---------|------|---------|------|
| `allMids` | `dex` (可选) | `AllMids` | 所有币种中间价 |
| `notification` | `user` | `Notification` | 用户通知 |
| `webData3` | `user` | `WebData3` | Web 数据 |
| `twapStates` | `user` | `TwapStates` | TWAP 状态 |
| `clearinghouseState` | `user` | `ClearinghouseState` | 账户状态 |
| `openOrders` | `user` | `OpenOrders` | 未完成订单 |
| `candle` | `coin`, `interval` | `Candle[]` | K 线数据 |
| `l2Book` | `coin`, `nSigFigs` (可选), `mantissa` (可选) | `WsBook` | L2 订单簿 |
| `trades` | `coin` | `WsTrade[]` | 交易数据 |
| `orderUpdates` | `user` | `WsOrder[]` | 订单更新 |
| `userEvents` | `user` | `WsUserEvent` | 用户事件 |
| `userFills` | `user`, `aggregateByTime` (可选) | `WsUserFills` | 用户成交 |
| `userFundings` | `user` | `WsUserFundings` | 用户资金费用 |
| `userNonFundingLedgerUpdates` | `user` | `WsUserNonFundingLedgerUpdates` | 非资金费用账本 |
| `activeAssetCtx` | `coin` | `WsActiveAssetCtx` 或 `WsActiveSpotAssetCtx` | 资产上下文 |
| `activeAssetData` | `user`, `coin` | `WsActiveAssetData` | 资产数据（仅 Perps） |
| `userTwapSliceFills` | `user` | `WsUserTwapSliceFills` | TWAP 切片成交 |
| `userTwapHistory` | `user` | `WsUserTwapHistory` | TWAP 历史 |
| `bbo` | `coin` | `WsBbo` | 最优买卖价 |

### 核心订阅示例

#### 1. 订阅订单簿 (l2Book)

```json
{
  "method": "subscribe",
  "subscription": {
    "type": "l2Book",
    "coin": "ETH"
  }
}
```

**数据推送示例**:
```json
{
  "channel": "l2Book",
  "data": {
    "coin": "ETH",
    "time": 1640000000000,
    "levels": [
      [
        {"px": "2000.5", "sz": "10.0", "n": 1}
      ],
      [
        {"px": "2001.0", "sz": "8.0", "n": 1}
      ]
    ]
  }
}
```

#### 2. 订阅交易数据 (trades)

```json
{
  "method": "subscribe",
  "subscription": {
    "type": "trades",
    "coin": "ETH"
  }
}
```

**数据推送示例**:
```json
{
  "channel": "trades",
  "data": [
    {
      "coin": "ETH",
      "side": "B",
      "px": "2000.5",
      "sz": "1.5",
      "time": 1640000000000,
      "hash": "0x..."
    }
  ]
}
```

#### 3. 订阅用户成交 (userFills)

```json
{
  "method": "subscribe",
  "subscription": {
    "type": "userFills",
    "user": "0x..."
  }
}
```

**数据推送示例**:
```json
{
  "channel": "userFills",
  "data": {
    "isSnapshot": false,
    "user": "0x...",
    "fills": [
      {
        "coin": "ETH",
        "px": "2000.5",
        "sz": "0.1",
        "side": "B",
        "time": 1640000000000,
        "startPosition": "0.0",
        "dir": "Open Long",
        "closedPnl": "0.0",
        "hash": "0x...",
        "oid": 123456,
        "crossed": false,
        "fee": "0.01",
        "feeToken": "USDC"
      }
    ]
  }
}
```

#### 4. 订阅用户事件 (userEvents)

```json
{
  "method": "subscribe",
  "subscription": {
    "type": "userEvents",
    "user": "0x..."
  }
}
```

**数据类型**:
- `{"fills": [...]}` - 成交事件
- `{"funding": {...}}` - 资金费用事件
- `{"liquidation": {...}}` - 清算事件
- `{"nonUserCancel": [...]}` - 非用户撤单事件

#### 5. 订阅订单更新 (orderUpdates)

```json
{
  "method": "subscribe",
  "subscription": {
    "type": "orderUpdates",
    "user": "0x..."
  }
}
```

### 快照机制

某些订阅（如 `userFills`）会在订阅确认时返回历史快照，标记为 `isSnapshot: true`：

```json
{
  "channel": "userFills",
  "data": {
    "isSnapshot": true,
    "user": "0x...",
    "fills": [...]
  }
}
```

### 心跳与超时

- WebSocket 可能因服务端维护而断开
- 建议实现自动重连机制
- 重连后需要重新订阅所有频道

### Python SDK WebSocket 示例

```python
from hyperliquid.info import Info

# 创建 Info 实例（启用 WebSocket）
info = Info(constants.TESTNET_API_URL, skip_ws=False)

# 订阅订单簿
def on_l2_book(data):
    print(f"Order Book Update: {data}")

info.subscribe(
    subscription={"type": "l2Book", "coin": "ETH"},
    callback=on_l2_book
)

# 订阅交易数据
def on_trades(data):
    print(f"Trade: {data}")

info.subscribe(
    subscription={"type": "trades", "coin": "ETH"},
    callback=on_trades
)

# 保持运行
import time
while True:
    time.sleep(1)
```

---

## 认证与签名

### Ed25519 签名机制

Hyperliquid Exchange API 使用 **Ed25519** 数字签名进行认证。

### 关键要点

1. **强烈建议使用官方 SDK**：手动实现签名容易出错，且错误信息不明确
2. **两种签名方案**：
   - `sign_l1_action`: 用于 L1 操作
   - `sign_user_signed_action`: 用于用户签名操作
3. **常见错误**：
   - 字段顺序错误（msgpack 序列化顺序敏感）
   - 数字格式错误（尾随零）
   - 地址大小写（应使用小写）
   - 签名验证细节（本地验证通过不代表服务端接受）

### 签名失败错误示例

```json
{
  "error": "L1 error: User or API Wallet 0x0123... does not exist"
}
```

或

```json
{
  "error": "Must deposit before performing actions"
}
```

### Nonce 系统

**Nonce 规则**:
- Hyperliquid 保存每个地址的 **100 个最高 nonce**
- 每个新交易的 nonce 必须：
  1. 大于当前保存的最小 nonce
  2. 从未被使用过
- Nonce 按 **签名者** 跟踪（用户地址或 API wallet 地址）

**最佳实践**:
- 使用当前时间戳（毫秒）作为 nonce
- 使用原子计数器确保唯一性
- 如需并行使用多个子账户，为每个子账户创建单独的 API wallet

**错误示例**:
```
"Nonce error: nonce value is lower than the next valid nonce"
```

### API Wallet

**什么是 API Wallet**:
- 用于程序化交易的代理钱包
- 从 [https://app.hyperliquid.xyz/API](https://app.hyperliquid.xyz/API) 创建
- 可以代表主账户或子账户签名

**重要提示**:
- **不要重复使用** API wallet 地址
- 一旦注销 (deregister)，已用 nonce 状态可能被清除
- 已签名的操作可能在 nonce 集合被清除后被重放

**配置示例 (Python SDK)**:
```python
from eth_account import Account
from hyperliquid.exchange import Exchange

# 创建 wallet
wallet = Account.from_key("your_private_key_hex")

# 初始化 Exchange（使用 API wallet）
exchange = Exchange(
    wallet=wallet,
    base_url=constants.TESTNET_API_URL,
    vault_address=None  # 如果是 vault，填入 vault 地址
)

# 如果使用 API wallet 代理主账户
# 在初始化时设置 walletAddress 字段
```

---

## 订单类型与参数

### TimeInForce (TIF) 选项

| TIF | 全称 | 说明 |
|-----|------|------|
| `Gtc` | Good-Til-Cancelled | 订单一直有效直到完全成交或手动撤销 |
| `Ioc` | Immediate-or-Cancel | 立即成交，未成交部分自动撤销 |
| `Alo` | Add-Liquidity-Only | 仅挂单（Post-only），不会立即成交，否则撤销 |

### 订单类型

#### 1. 限价单 (Limit Order)

**定义**: 指定价格和数量的订单，只在指定价格或更优价格成交。

**结构**:
```json
{
  "limit": {
    "tif": "Gtc" | "Ioc" | "Alo"
  }
}
```

**示例**:
```python
# GTC 限价单 - 挂单直到成交或撤销
exchange.order(
    coin="ETH",
    is_buy=True,
    sz=0.1,
    limit_px=2000.0,
    order_type={"limit": {"tif": "Gtc"}}
)

# IOC 限价单 - 立即成交或撤销
exchange.order(
    coin="ETH",
    is_buy=True,
    sz=0.1,
    limit_px=2050.0,
    order_type={"limit": {"tif": "Ioc"}}
)

# ALO 限价单 - 仅挂单（Post-only）
exchange.order(
    coin="ETH",
    is_buy=True,
    sz=0.1,
    limit_px=1995.0,
    order_type={"limit": {"tif": "Alo"}}
)
```

#### 2. 市价单 (Market Order)

**定义**: 以当前市场最优价格立即成交的订单。

**实现方式**: Hyperliquid 没有原生市价单类型，通过 SDK 的 `market_open` / `market_close` 方法模拟：
- 获取当前市场价格
- 加上滑点保护
- 下 IOC 限价单

**示例**:
```python
# 市价买入
exchange.market_open(
    coin="ETH",
    is_buy=True,
    sz=0.1,
    slippage=0.05  # 5% 滑点保护
)
```

#### 3. 止损单 (Stop Loss)

**说明**: 当价格达到触发价时，自动发送市价单平仓。

**注意**: 止损单自动为市价单，无法指定限价。

#### 4. 止盈单 (Take Profit)

**说明**: 当价格达到目标价时，自动发送市价单平仓。

**注意**: 止盈单自动为市价单。

#### 5. TWAP 订单

**说明**: 将大订单分割成多个子订单，在指定时间段内均匀执行（每 30 秒一个子订单）。

### 订单参数详解

#### 完整订单结构

```typescript
{
  a: number,              // 资产索引
  b: boolean,             // 买卖方向 (true=买, false=卖)
  p: string,              // 限价价格 (字符串，保留精度)
  s: string,              // 订单数量 (字符串)
  r: boolean,             // 仅减仓 (reduce-only)
  t: OrderType,           // 订单类型
  c?: string              // 客户端订单 ID (CLOID, 可选)
}
```

#### 字段说明

- **资产索引 (a)**:
  - 永续合约：从 `meta.universe` 获取索引（如 ETH = 0, BTC = 1）
  - 现货：`10000 + spotMeta.universe 中的索引`
    - 例如：PURR/USDC 在 spotMeta 中索引为 0，则 `a = 10000`

- **价格精度**:
  - 价格必须能被 tick size 整除
  - 错误示例：`"Price must be divisible by tick size"`

- **数量精度**:
  - 从 `meta.universe[].szDecimals` 获取
  - 例如：BTC 的 `szDecimals = 5`，数量为 `0.00001` BTC

- **最小订单价值**:
  - 所有订单必须满足最小价值 **$10 USD**
  - 错误示例：`"Order must have minimum value of $10."`

- **Reduce-Only (r)**:
  - `true`: 订单只能减少仓位，不能增加
  - 用于平仓或部分平仓

- **客户端订单 ID (c)**:
  - 可选字段，用于客户端跟踪订单
  - 可以使用 `cancel_by_cloid` / `query_order_by_cloid` 操作

### 订单状态

| 状态 | 说明 |
|------|------|
| `filled` | 完全成交 |
| `open` | 未完成（部分成交或未成交） |
| `canceled` | 已撤销 |
| `triggered` | 止损/止盈已触发 |
| `rejected` | 被拒绝 |
| `marginCanceled` | 因保证金不足被撤销 |

### 订单响应类型

#### 1. Resting (挂单成功)

```json
{
  "resting": {
    "oid": 77738308
  }
}
```

#### 2. Filled (完全成交)

```json
{
  "filled": {
    "totalSz": "0.02",
    "avgPx": "1891.4",
    "oid": 77747314
  }
}
```

#### 3. Error (错误)

```json
{
  "error": "Order must have minimum value of $10."
}
```

---

## 数据结构

### 1. Position (仓位)

```typescript
{
  coin: string,                    // 币种
  szi: string,                     // 仓位大小（有符号: +多头, -空头）
  entryPx: string,                 // 开仓均价
  leverage: {
    type: "cross" | "isolated",    // 杠杆类型
    value: number,                 // 杠杆倍数
    rawUsd: string                 // 原始 USD 价值
  },
  liquidationPx: string | null,    // 清算价格
  marginUsed: string,              // 已用保证金
  maxLeverage: number,             // 最大杠杆
  positionValue: string,           // 仓位价值
  returnOnEquity: string,          // 权益回报率
  unrealizedPnl: string,           // 未实现盈亏
  cumFunding: {
    allTime: string,               // 累计资金费用
    sinceChange: string,           // 自上次变动
    sinceOpen: string              // 自开仓
  }
}
```

### 2. MarginSummary (保证金摘要)

```typescript
{
  accountValue: string,            // 账户总价值
  totalMarginUsed: string,         // 总已用保证金
  totalNtlPos: string,             // 总名义仓位价值
  totalRawUsd: string              // 总原始 USD
}
```

### 3. AssetPosition (资产仓位)

```typescript
{
  position: Position,              // 仓位详情
  type: "oneWay" | "hedge"         // 仓位模式
}
```

### 4. UserState (用户状态)

```typescript
{
  assetPositions: AssetPosition[], // 仓位列表
  crossMaintenanceMarginUsed: string,
  crossMarginSummary: MarginSummary,
  marginSummary: MarginSummary,
  time: number,                    // 时间戳
  withdrawable: string             // 可提现金额
}
```

### 5. OrderBook (订单簿)

```typescript
{
  coin: string,                    // 币种
  time: number,                    // 时间戳
  levels: [
    Level[],                       // Bids (买单)
    Level[]                        // Asks (卖单)
  ]
}

type Level = {
  px: string,                      // 价格
  sz: string,                      // 数量
  n: number                        // 订单数量
}
```

### 6. Fill (成交记录)

```typescript
{
  coin: string,                    // 币种
  px: string,                      // 成交价格
  sz: string,                      // 成交数量
  side: "B" | "A",                 // 买/卖 (B=买, A=卖)
  time: number,                    // 时间戳
  startPosition: string,           // 开始仓位
  dir: string,                     // 方向 ("Open Long", "Close Short", etc.)
  closedPnl: string,               // 已实现盈亏
  hash: string,                    // 交易哈希
  oid: number,                     // 订单 ID
  crossed: boolean,                // 是否穿仓
  fee: string,                     // 手续费
  feeToken: string,                // 手续费币种
  tid: number                      // 成交 ID
}
```

### 7. Order (订单)

```typescript
{
  coin: string,                    // 币种
  side: "A" | "B",                 // 买/卖
  limitPx: string,                 // 限价
  sz: string,                      // 数量
  oid: number,                     // 订单 ID
  timestamp: number,               // 时间戳
  origSz: string                   // 原始数量
}
```

---

## 错误处理

### 常见错误代码

| 错误消息 | 原因 | 解决方案 |
|---------|------|---------|
| `Order must have minimum value of $10.` | 订单价值低于 $10 | 增加订单数量或价格 |
| `Price must be divisible by tick size` | 价格精度不符合 tick size | 调整价格使其符合 tick size |
| `Order was never placed, already canceled, or filled.` | 撤单时订单不存在 | 检查订单状态 |
| `L1 error: User or API Wallet does not exist` | 签名错误或账户不存在 | 检查签名实现、确保账户有余额 |
| `Must deposit before performing actions` | 账户无余额 | 向账户存入 USDC |
| `Nonce error: nonce value is lower than the next valid nonce` | Nonce 过小或重复 | 使用更大的 nonce（推荐时间戳） |
| `Too many cumulative requests sent` | 超过速率限制 | 等待或增加交易量 |
| `Order could not immediately match against any resting orders` | IOC 订单无法立即成交 | 调整价格或使用 GTC |
| `No liquidity available for market order` | 市价单无流动性 | 减少订单数量或等待流动性恢复 |
| `Only post-only orders allowed immediately after a network upgrade` | 网络升级后限制 | 等待限制解除 |

### HTTP 错误响应格式

**格式 1: 全局错误**
```json
{
  "status": "err",
  "response": "Error message here"
}
```

**格式 2: 批量操作错误（每个操作独立）**
```json
{
  "status": "ok",
  "response": {
    "type": "order",
    "data": {
      "statuses": [
        {"error": "Order must have minimum value of $10."},
        {"resting": {"oid": 123}}
      ]
    }
  }
}
```

### 错误处理最佳实践

1. **区分错误类型**:
   - 网络错误 (超时、连接失败) → 重试
   - 验证错误 (参数错误、余额不足) → 不重试，记录日志
   - 速率限制错误 → 等待后重试

2. **批量操作错误处理**:
   - 逐个检查 `statuses` 数组
   - 区分成功和失败的操作
   - 记录失败原因

3. **签名错误调试**:
   - 参考官方 Python SDK 实现
   - 使用测试网验证
   - 确保地址小写化
   - 检查 nonce 是否正确

---

## 速率限制

### 基本规则

- **默认限制**: 基于累计请求数和交易量
- **限制公式**: `limit` 取决于累计交易量（USDC）
- **撤单特殊限制**: `min(limit + 100000, limit * 2)`

### 速率限制错误

**错误消息**:
```
"Too many cumulative requests sent (x > y) for cumulative volume traded $z. Place taker orders to free up 1 request per USDC traded."
```

**解释**:
- `x`: 当前累计请求数
- `y`: 允许的最大请求数
- `z`: 累计交易量（USDC）

**缓解措施**:
1. 增加交易量（每交易 $1 USDC 可获得 1 次请求配额）
2. 减少请求频率
3. 使用批量操作减少请求次数

### 被限制后的行为

- 地址被限制时，允许每 **10 秒** 发送 1 次请求
- 需要通过增加交易量来解除限制

### WebSocket 订阅限制

- **每个 IP**: 最多 1000 个订阅
- 超过限制会抛出错误

### 客户端速率限制实现

**推荐策略**:
```python
import time

class RateLimiter:
    def __init__(self, min_interval_ms=50):
        self.min_interval_ms = min_interval_ms
        self.last_request_time = 0

    def wait(self):
        now = time.time() * 1000
        elapsed = now - self.last_request_time
        if elapsed < self.min_interval_ms:
            sleep_time = (self.min_interval_ms - elapsed) / 1000
            time.sleep(sleep_time)
        self.last_request_time = time.time() * 1000
```

**建议值**:
- 每秒最多 20 次请求 → `min_interval_ms = 50`

---

## Python SDK 参考

### 项目结构

```
hyperliquid-python-sdk/
├── hyperliquid/
│   ├── __init__.py
│   ├── api.py                  # 基础 API 类
│   ├── exchange.py             # Exchange API (36KB, 最大模块)
│   ├── info.py                 # Info API (27KB)
│   ├── websocket_manager.py   # WebSocket 管理 (7KB)
│   └── utils/                  # 工具模块
│       ├── constants.py
│       ├── signing.py          # Ed25519 签名
│       └── types.py
├── examples/
│   ├── basic_order.py
│   ├── basic_adding.py         # 做市示例
│   └── ...
└── tests/
```

### Info API 类

**初始化**:
```python
from hyperliquid.info import Info
from hyperliquid.utils import constants

info = Info(
    base_url=constants.TESTNET_API_URL,
    skip_ws=True  # 不启用 WebSocket
)
```

**常用方法**:
```python
# 获取所有中间价
all_mids = info.all_mids()

# 获取用户状态
user_state = info.user_state(user_address)

# 获取订单簿
orderbook = info.l2_snapshot("ETH")

# 获取用户成交
fills = info.user_fills(user_address)

# 查询订单状态
order_status = info.query_order_by_oid(user_address, oid=123456)
```

### Exchange API 类

**初始化**:
```python
from hyperliquid.exchange import Exchange
from eth_account import Account

# 创建钱包
wallet = Account.from_key("your_private_key")

# 初始化 Exchange
exchange = Exchange(
    wallet=wallet,
    base_url=constants.TESTNET_API_URL
)
```

**下单示例**:
```python
# 限价单
order_result = exchange.order(
    coin="ETH",
    is_buy=True,
    sz=0.2,
    limit_px=1100,
    order_type={"limit": {"tif": "Gtc"}},
    reduce_only=False
)

# 市价单
market_result = exchange.market_open(
    coin="ETH",
    is_buy=True,
    sz=0.1,
    slippage=0.05
)

# 撤单
cancel_result = exchange.cancel(coin="ETH", oid=123456)
```

### 完整示例：下单并撤单

```python
import json
from hyperliquid.info import Info
from hyperliquid.exchange import Exchange
from hyperliquid.utils import constants
from eth_account import Account

# 初始化
wallet = Account.from_key("your_private_key")
info = Info(constants.TESTNET_API_URL, skip_ws=True)
exchange = Exchange(wallet, constants.TESTNET_API_URL)

address = wallet.address

# 1. 查看当前仓位
user_state = info.user_state(address)
positions = [ap["position"] for ap in user_state["assetPositions"]]
if positions:
    print("Current positions:")
    for pos in positions:
        print(json.dumps(pos, indent=2))
else:
    print("No open positions")

# 2. 下限价单（价格设置很低，不会立即成交）
order_result = exchange.order("ETH", True, 0.2, 1100, {"limit": {"tif": "Gtc"}})
print("Order result:", order_result)

# 3. 查询订单状态
if order_result["status"] == "ok":
    status = order_result["response"]["data"]["statuses"][0]
    if "resting" in status:
        oid = status["resting"]["oid"]
        order_status = info.query_order_by_oid(address, oid)
        print("Order status by oid:", order_status)

# 4. 撤单
if order_result["status"] == "ok":
    status = order_result["response"]["data"]["statuses"][0]
    if "resting" in status:
        oid = status["resting"]["oid"]
        cancel_result = exchange.cancel("ETH", oid)
        print("Cancel result:", cancel_result)
```

### 做市示例 (basic_adding.py)

**核心逻辑**:
```python
class BasicAdder:
    def __init__(self, exchange, info, coin):
        self.exchange = exchange
        self.info = info
        self.coin = coin

        # 参数
        self.DEPTH = 0.003           # 挂单深度 (0.3%)
        self.MAX_POSITION = 1.0      # 最大仓位
        self.POLL_INTERVAL = 10      # 轮询间隔（秒）

    def run(self):
        while True:
            # 1. 获取当前市场价格
            all_mids = self.info.all_mids()
            mid_price = float(all_mids[self.coin])

            # 2. 计算挂单价格
            bid_price = mid_price * (1 - self.DEPTH)
            ask_price = mid_price * (1 + self.DEPTH)

            # 3. 检查当前仓位
            user_state = self.info.user_state(self.exchange.wallet.address)
            position = self.get_position(user_state, self.coin)

            # 4. 下单逻辑
            if position < self.MAX_POSITION:
                # 下买单
                self.exchange.order(
                    self.coin, True, 0.01, bid_price,
                    {"limit": {"tif": "Alo"}}
                )

            if position > -self.MAX_POSITION:
                # 下卖单
                self.exchange.order(
                    self.coin, False, 0.01, ask_price,
                    {"limit": {"tif": "Alo"}}
                )

            time.sleep(self.POLL_INTERVAL)
```

---

## 与 ZigQuant Stories 的对应关系

### Story 006: Hyperliquid HTTP 客户端实现

| ZigQuant 组件 | Hyperliquid API | Python SDK 对应 |
|--------------|----------------|----------------|
| `HyperliquidClient` | HTTP API 基础 | `hyperliquid.api.API` |
| `Auth` (Ed25519 签名) | 签名机制 | `hyperliquid.utils.signing` |
| `InfoAPI.getAllAssets()` | `meta` 端点 | `info.meta()` |
| `InfoAPI.getOrderBook()` | `l2Book` 端点 | `info.l2_snapshot(coin)` |
| `InfoAPI.getAccountState()` | `clearinghouseState` 端点 | `info.user_state(address)` |
| `InfoAPI.getRecentTrades()` | (无直接端点，需 WebSocket) | WebSocket `trades` |
| `ExchangeAPI.placeOrder()` | `order` 操作 | `exchange.order(...)` |
| `ExchangeAPI.cancelOrder()` | `cancel` 操作 | `exchange.cancel(coin, oid)` |
| `ExchangeAPI.getOrderStatus()` | `queryOrderByOid` | `info.query_order_by_oid(user, oid)` |
| `RateLimiter` | 客户端速率限制 | (需自己实现) |

**数据类型对应**:

| ZigQuant 类型 | Hyperliquid 数据 | Python SDK 类型 |
|--------------|-----------------|----------------|
| `OrderBook` | L2 Book 快照 | `dict` |
| `AccountState` | `clearinghouseState` | `dict` |
| `Position` | `assetPositions[].position` | `dict` |
| `Trade` | WebSocket `trades` | `dict` |
| `OrderRequest` | `order` 请求体 | `OrderRequest` |
| `OrderResponse` | `order` 响应 | `dict` |
| `OrderStatus` | 订单状态 | `dict` |

**核心方法对应**:

| ZigQuant 方法 | Hyperliquid 端点 | Python SDK |
|--------------|-----------------|-----------|
| `placeOrder()` | `POST /exchange` (type: order) | `exchange.order()` |
| `cancelOrder()` | `POST /exchange` (type: cancel) | `exchange.cancel()` |
| `getOrderBook()` | `POST /info` (type: l2Book) | `info.l2_snapshot()` |
| `getUserState()` | `POST /info` (type: clearinghouseState) | `info.user_state()` |

---

### Story 007: Hyperliquid WebSocket 实时数据流

| ZigQuant 组件 | Hyperliquid WebSocket | Python SDK 对应 |
|--------------|----------------------|----------------|
| `HyperliquidWS` | WebSocket 连接 | `websocket_manager.WebsocketManager` |
| `SubscriptionManager` | 订阅管理 | 内置在 `Info` 类 |
| `MessageHandler` | 消息解析 | 自动处理 |
| `Subscription.l2_book` | `{"type": "l2Book", "coin": "..."}` | `info.subscribe(...)` |
| `Subscription.trades` | `{"type": "trades", "coin": "..."}` | `info.subscribe(...)` |
| `Subscription.user_events` | `{"type": "userEvents", "user": "..."}` | `info.subscribe(...)` |
| `Subscription.user_fills` | `{"type": "userFills", "user": "..."}` | `info.subscribe(...)` |

**订阅示例对应**:

```zig
// ZigQuant
try ws.subscribe(.{
    .channel = .l2_book,
    .coin = "ETH",
    .user = null,
});
```

```python
# Python SDK
info.subscribe(
    subscription={"type": "l2Book", "coin": "ETH"},
    callback=on_l2_book
)
```

**消息类型对应**:

| ZigQuant 消息类型 | Hyperliquid 频道 | Python SDK 回调数据 |
|------------------|-----------------|-------------------|
| `Message.l2_book` | `l2Book` | `dict` (levels, coin, time) |
| `Message.trade` | `trades` | `list[dict]` (px, sz, side, ...) |
| `Message.user_event` | `userEvents` | `dict` (fills, funding, liquidation, ...) |
| `Message.user_fill` | `userFills` | `dict` (fills array) |
| `Message.all_mids` | `allMids` | `dict` (coin: price) |

---

### Story 008: 订单簿维护

| ZigQuant 组件 | Hyperliquid 数据源 | 实现建议 |
|--------------|-------------------|---------|
| `OrderBook.update()` | WebSocket `l2Book` | 订阅 `l2Book` 并更新本地数据结构 |
| `OrderBook.getBestBid()` | `levels[0][0]` | 从订阅数据中提取 |
| `OrderBook.getBestAsk()` | `levels[1][0]` | 从订阅数据中提取 |
| `OrderBook.getSnapshot()` | HTTP `l2Book` 或 WebSocket snapshot | 使用 `info.l2_snapshot()` 或订阅快照 |

---

### Story 009: 订单类型

| ZigQuant 订单类型 | Hyperliquid 实现 |
|------------------|-----------------|
| `Limit` | `{"limit": {"tif": "Gtc"}}` |
| `Market` | `market_open()` / `market_close()` (IOC 限价单模拟) |
| `PostOnly` | `{"limit": {"tif": "Alo"}}` |
| `IOC` | `{"limit": {"tif": "Ioc"}}` |
| `StopLoss` | (未在 MVP 中实现，需 Trigger 订单) |
| `TakeProfit` | (未在 MVP 中实现，需 Trigger 订单) |

---

### Story 010: 订单管理器

| ZigQuant 组件 | Hyperliquid API |
|--------------|----------------|
| `OrderManager.placeOrder()` | `exchange.order()` |
| `OrderManager.cancelOrder()` | `exchange.cancel()` |
| `OrderManager.modifyOrder()` | `exchange.modify_order()` |
| `OrderManager.getOrderStatus()` | `info.query_order_by_oid()` |
| `OrderManager.getOpenOrders()` | `info.open_orders()` |
| `OrderManager.trackOrder()` | WebSocket `orderUpdates` |

---

### Story 011: 仓位追踪器

| ZigQuant 组件 | Hyperliquid 数据 |
|--------------|-----------------|
| `PositionTracker.getPosition()` | `user_state.assetPositions` |
| `PositionTracker.updateFromFill()` | WebSocket `userFills` |
| `PositionTracker.unrealizedPnl` | `position.unrealizedPnl` |
| `PositionTracker.marginUsed` | `position.marginUsed` |
| `PositionTracker.liquidationPrice` | `position.liquidationPx` |

---

### 完整流程示例（对应多个 Story）

```python
# Story 006: HTTP 客户端
from hyperliquid.info import Info
from hyperliquid.exchange import Exchange

info = Info(constants.TESTNET_API_URL, skip_ws=True)
exchange = Exchange(wallet, constants.TESTNET_API_URL)

# Story 007: WebSocket 订阅
info_ws = Info(constants.TESTNET_API_URL, skip_ws=False)

def on_orderbook_update(data):
    # Story 008: 订单簿维护
    orderbook.update(data)

def on_user_fill(data):
    # Story 011: 仓位追踪
    position_tracker.update_from_fill(data)

info_ws.subscribe({"type": "l2Book", "coin": "ETH"}, on_orderbook_update)
info_ws.subscribe({"type": "userFills", "user": address}, on_user_fill)

# Story 009: 订单类型
# Story 010: 订单管理
order_result = exchange.order(
    coin="ETH",
    is_buy=True,
    sz=0.1,
    limit_px=2000.0,
    order_type={"limit": {"tif": "Gtc"}}  # Story 009: Limit order
)

# 获取订单状态
if order_result["status"] == "ok":
    oid = order_result["response"]["data"]["statuses"][0]["resting"]["oid"]
    order_status = info.query_order_by_oid(address, oid)

    # 撤单
    exchange.cancel("ETH", oid)

# Story 011: 仓位追踪
user_state = info.user_state(address)
for asset_pos in user_state["assetPositions"]:
    position = asset_pos["position"]
    print(f"Position: {position['coin']} {position['szi']}")
    print(f"Unrealized PnL: {position['unrealizedPnl']}")
    print(f"Liquidation Price: {position['liquidationPx']}")
```

---

## 参考资料

### 官方文档

- [Hyperliquid API 文档](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api)
- [Info API 端点](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint)
- [Exchange API 端点](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint)
- [WebSocket API](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket)
- [WebSocket 订阅](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions)
- [签名机制](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/signing)
- [Nonces 和 API Wallets](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/nonces-and-api-wallets)
- [速率限制](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/rate-limits-and-user-limits)
- [错误响应](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/error-responses)
- [订单类型](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/order-types)
- [保证金计算](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/margining)
- [清算机制](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/liquidations)

### Python SDK

- [GitHub 仓库](https://github.com/hyperliquid-dex/hyperliquid-python-sdk)
- [exchange.py 源码](https://github.com/hyperliquid-dex/hyperliquid-python-sdk/blob/master/hyperliquid/exchange.py)
- [info.py 源码](https://github.com/hyperliquid-dex/hyperliquid-python-sdk/blob/master/hyperliquid/info.py)
- [示例代码](https://github.com/hyperliquid-dex/hyperliquid-python-sdk/tree/master/examples)

### 社区资源

- [Chainstack Hyperliquid API 参考](https://docs.chainstack.com/reference/hyperliquid-info-allmids)
- [Quicknode Hyperliquid 错误参考](https://www.quicknode.com/docs/hyperliquid/error-references)
- [Apidog Hyperliquid API 指南](https://apidog.com/blog/hyperliquid-api/)
- [开发者指南：下单操作](https://blockchain.oodles.io/dev-blog/hyperliquid-api-a-dev-guide-to-placing-orders/)

---

## 附录

### A. 资产索引计算

**永续合约**:
```python
meta = info.meta()
for idx, asset in enumerate(meta["universe"]):
    print(f"{asset['name']}: index={idx}")
# 输出: BTC: index=0, ETH: index=1, ...
```

**现货**:
```python
spot_meta = info.spot_meta()
for idx, asset in enumerate(spot_meta["universe"]):
    spot_index = 10000 + idx
    print(f"{asset['name']}: index={spot_index}")
# 输出: PURR/USDC: index=10000, ...
```

### B. Tick Size 和 Lot Size

从 `meta` 响应中获取：
- `szDecimals`: 数量精度
- 价格精度通常为 1 或更小（如 0.1, 0.01）

### C. 保证金和杠杆计算

**开仓所需保证金**:
```
margin_required = position_size * mark_price / leverage
```

**清算价格公式**:
```
liq_price = entry_price - side * margin_available / position_size / (1 - l * side)
其中: l = 1 / MAINTENANCE_LEVERAGE
```

**维持保证金**:
```
maintenance_margin = initial_margin / 2
```

对于不同最大杠杆:
- 50x: 维持保证金率 = 1%
- 40x: 维持保证金率 = 1.25%
- 20x: 维持保证金率 = 2.5%
- 10x: 维持保证金率 = 5%

### D. 时间戳格式

所有时间戳为 **Unix 毫秒时间戳**：
```python
import time
timestamp_ms = int(time.time() * 1000)
```

### E. 地址格式

- **格式**: 以太坊地址格式 (0x...)
- **大小写**: 建议使用小写
- **长度**: 42 字符 (包括 `0x`)

---

**文档完成时间**: 2025-12-23
**作者**: Claude (基于官方文档和 Python SDK)
**适用版本**: Hyperliquid API v1 (2025-12)
**ZigQuant 版本**: v0.2 MVP
