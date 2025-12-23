# WebSocket 订阅详解

> 导航: [首页](../../../README.md) / [Features](../../README.md) / [Hyperliquid 连接器](./README.md) / 订阅

## 订阅类型完整列表

| 订阅类型 | 参数 | 数据类型 | 说明 |
|---------|------|---------|------|
| `allMids` | `dex` (可选) | `AllMids` | 所有币种中间价 |
| `notification` | `user` | `Notification` | 用户通知 |
| `webData3` | `user` | `WebData3` | Web 数据 |
| `clearinghouseState` | `user` | `ClearinghouseState` | 账户状态 |
| `openOrders` | `user` | `OpenOrders` | 未完成订单 |
| `candle` | `coin`, `interval` | `Candle[]` | K 线数据 |
| `l2Book` | `coin`, `nSigFigs`, `mantissa` | `WsBook` | L2 订单簿 |
| `trades` | `coin` | `WsTrade[]` | 交易数据 |
| `orderUpdates` | `user` | `WsOrder[]` | 订单更新 |
| `userEvents` | `user` | `WsUserEvent` | 用户事件 |
| `userFills` | `user`, `aggregateByTime` | `WsUserFills` | 用户成交 |
| `userFundings` | `user` | `WsUserFundings` | 用户资金费用 |
| `userNonFundingLedgerUpdates` | `user` | `WsUserNonFundingLedgerUpdates` | 非资金费用账本 |
| `activeAssetCtx` | `coin` | `WsActiveAssetCtx` | 资产上下文 |
| `bbo` | `coin` | `WsBbo` | 最优买卖价 |

## 市场数据订阅

### allMids - 所有币种中间价

```zig
try ws.subscribe(.{
    .channel = .allMids,
});
```

**消息示例**:
```json
{
  "channel": "allMids",
  "data": {
    "BTC": "97000.5",
    "ETH": "3500.25",
    "SOL": "180.75"
  }
}
```

---

### l2Book - L2 订单簿

```zig
try ws.subscribe(.{
    .channel = .l2Book,
    .coin = "ETH",
    .nSigFigs = null,
    .mantissa = null,
});
```

**参数**:
- `nSigFigs`: (可选) 价格有效数字
- `mantissa`: (可选) 尾数

**消息示例**:
```json
{
  "channel": "l2Book",
  "data": {
    "coin": "ETH",
    "time": 1640000000000,
    "levels": [
      [{"px": "2000.5", "sz": "10.0", "n": 1}],
      [{"px": "2001.0", "sz": "8.0", "n": 1}]
    ]
  }
}
```

---

### trades - 交易数据

```zig
try ws.subscribe(.{
    .channel = .trades,
    .coin = "BTC",
});
```

**消息示例**:
```json
{
  "channel": "trades",
  "data": [
    {
      "coin": "BTC",
      "side": "B",
      "px": "97000.5",
      "sz": "0.1",
      "time": 1640000000000,
      "hash": "0x..."
    }
  ]
}
```

---

### bbo - 最优买卖价

```zig
try ws.subscribe(.{
    .channel = .bbo,
    .coin = "ETH",
});
```

**消息示例**:
```json
{
  "channel": "bbo",
  "data": {
    "coin": "ETH",
    "bid": "2000.5",
    "ask": "2001.0",
    "time": 1640000000000
  }
}
```

---

### candle - K 线数据

```zig
try ws.subscribe(.{
    .channel = .candle,
    .coin = "ETH",
    .interval = "1h",
});
```

**interval 选项**: `"1m"`, `"5m"`, `"15m"`, `"1h"`, `"4h"`, `"1d"`

**消息示例**:
```json
{
  "channel": "candle",
  "data": [
    {
      "t": 1640000000000,
      "o": "2000.0",
      "h": "2100.0",
      "l": "1950.0",
      "c": "2050.0",
      "v": "1000.0"
    }
  ]
}
```

---

## 用户数据订阅

### userFills - 用户成交

```zig
const user_address = try client.auth.getUserAddress();

try ws.subscribe(.{
    .channel = .userFills,
    .user = user_address,
    .aggregateByTime = false,  // 可选
});
```

**消息示例**:
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

**字段说明**:
- `isSnapshot`: 是否为快照（首次订阅时为 `true`）
- `dir`: 方向 (`"Open Long"`, `"Close Short"`, `"Open Short"`, `"Close Long"`)
- `closedPnl`: 已实现盈亏
- `startPosition`: 开始仓位

---

### userEvents - 用户事件

```zig
try ws.subscribe(.{
    .channel = .userEvents,
    .user = user_address,
});
```

**事件类型**:
1. `fills` - 成交事件
2. `funding` - 资金费用
3. `liquidation` - 清算事件
4. `nonUserCancel` - 非用户撤单

**消息示例 (fills)**:
```json
{
  "channel": "userEvents",
  "data": {
    "fills": [
      {
        "coin": "ETH",
        "px": "2000.5",
        "sz": "0.1",
        "dir": "Open Long",
        "closedPnl": "0.0"
      }
    ]
  }
}
```

**消息示例 (funding)**:
```json
{
  "channel": "userEvents",
  "data": {
    "funding": {
      "coin": "ETH",
      "usdc": "0.123",
      "time": 1640000000000
    }
  }
}
```

---

### orderUpdates - 订单更新

```zig
try ws.subscribe(.{
    .channel = .orderUpdates,
    .user = user_address,
});
```

**消息示例**:
```json
{
  "channel": "orderUpdates",
  "data": [
    {
      "order": {
        "coin": "ETH",
        "side": "B",
        "limitPx": "2000.0",
        "sz": "0.1",
        "oid": 123456,
        "timestamp": 1640000000000,
        "origSz": "0.1"
      },
      "status": "resting",
      "statusTimestamp": 1640000000000
    }
  ]
}
```

**status 选项**: `"resting"`, `"filled"`, `"canceled"`, `"triggered"`, `"rejected"`

---

### clearinghouseState - 账户状态

```zig
try ws.subscribe(.{
    .channel = .clearinghouseState,
    .user = user_address,
});
```

**消息示例**:
```json
{
  "channel": "clearinghouseState",
  "data": {
    "assetPositions": [...],
    "marginSummary": {
      "accountValue": "10000.0",
      "totalMarginUsed": "500.0"
    },
    "withdrawable": "9500.0"
  }
}
```

---

### openOrders - 未完成订单

```zig
try ws.subscribe(.{
    .channel = .openOrders,
    .user = user_address,
});
```

---

## 订阅管理

### 订阅格式

```zig
pub const Subscription = struct {
    channel: SubscriptionChannel,
    coin: ?[]const u8 = null,
    user: ?[]const u8 = null,
    interval: ?[]const u8 = null,
    nSigFigs: ?u8 = null,
    mantissa: ?u8 = null,
    aggregateByTime: ?bool = null,

    pub fn toJSON(self: Subscription, allocator: std.mem.Allocator) ![]u8 {
        var json_obj = std.json.ObjectMap.init(allocator);
        defer json_obj.deinit();

        try json_obj.put("method", .{ .string = "subscribe" });

        var sub_obj = std.json.ObjectMap.init(allocator);
        try sub_obj.put("type", .{ .string = @tagName(self.channel) });

        if (self.coin) |coin| {
            try sub_obj.put("coin", .{ .string = coin });
        }
        if (self.user) |user| {
            try sub_obj.put("user", .{ .string = user });
        }
        // ... 其他字段

        try json_obj.put("subscription", .{ .object = sub_obj });

        return try std.json.stringifyAlloc(allocator, json_obj, .{});
    }
};
```

### 订阅确认

服务器会返回订阅确认消息：

```json
{
  "channel": "subscriptionResponse",
  "data": {
    "method": "subscribe",
    "subscription": {
      "type": "l2Book",
      "coin": "ETH"
    }
  }
}
```

### 取消订阅

```zig
try ws.unsubscribe(.{
    .channel = .l2Book,
    .coin = "ETH",
});
```

**取消订阅消息**:
```json
{
  "method": "unsubscribe",
  "subscription": {
    "type": "l2Book",
    "coin": "ETH"
  }
}
```

---

## 使用示例

### 示例 1: 监控多个币种价格

```zig
// 订阅所有中间价
try ws.subscribe(.{ .channel = .allMids });

ws.on_message = struct {
    fn callback(msg: Message) void {
        if (msg == .all_mids) {
            for (msg.all_mids.keys()) |coin| {
                const price = msg.all_mids.get(coin).?;
                std.debug.print("{s}: ${}\n", .{coin, price.toFloat()});
            }
        }
    }
}.callback;
```

### 示例 2: 追踪用户订单和成交

```zig
const user_address = try client.auth.getUserAddress();

// 订阅订单更新
try ws.subscribe(.{
    .channel = .orderUpdates,
    .user = user_address,
});

// 订阅成交
try ws.subscribe(.{
    .channel = .userFills,
    .user = user_address,
});

ws.on_message = struct {
    fn callback(msg: Message) void {
        switch (msg) {
            .order_updates => |orders| {
                for (orders) |order| {
                    std.debug.print("Order {}: {s}\n", .{
                        order.order.oid, order.status,
                    });
                }
            },
            .user_fills => |fills| {
                for (fills.fills) |fill| {
                    std.debug.print("Fill: {s} {} @ {}\n", .{
                        fill.coin, fill.sz, fill.px,
                    });
                }
            },
            else => {},
        }
    }
}.callback;
```

### 示例 3: 维护本地订单簿

```zig
var eth_orderbook = try OrderBook.init(allocator, "ETH");
defer eth_orderbook.deinit();

try ws.subscribe(.{
    .channel = .l2Book,
    .coin = "ETH",
});

ws.on_message = struct {
    fn callback(msg: Message) void {
        if (msg == .l2_book) {
            if (std.mem.eql(u8, msg.l2_book.coin, "ETH")) {
                eth_orderbook.applySnapshot(
                    msg.l2_book.levels[0],
                    msg.l2_book.levels[1],
                    msg.l2_book.time,
                ) catch |err| {
                    std.debug.print("Error updating orderbook: {}\n", .{err});
                };
            }
        }
    }
}.callback;
```

## 参考资料

- [Hyperliquid WebSocket Subscriptions](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions)
- [Message Types](./message-types.md)
- [WebSocket Guide](./websocket.md)
