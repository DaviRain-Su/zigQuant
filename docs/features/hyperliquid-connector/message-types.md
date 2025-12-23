# WebSocket 消息类型参考

> 导航: [首页](../../../README.md) / [Features](../../README.md) / [Hyperliquid 连接器](./README.md) / 消息类型

## 消息枚举

```zig
pub const Message = union(enum) {
    l2_book: WsBook,
    trades: []WsTrade,
    user_fills: WsUserFills,
    user_events: WsUserEvent,
    order_updates: []WsOrder,
    all_mids: std.StringHashMap(Decimal),
    candle: []WsCandle,
    bbo: WsBbo,
    subscription_response: SubscriptionResponse,
    pong: void,
    unknown: []const u8,
};
```

## WsBook - 订单簿

```zig
pub const WsBook = struct {
    coin: []const u8,
    time: Timestamp,
    levels: [2][]Level,  // [0]=bids, [1]=asks

    pub const Level = struct {
        px: Decimal,   // 价格
        sz: Decimal,   // 数量
        n: u32,        // 订单数量
    };
};
```

**JSON 示例**:
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

---

## WsTrade - 交易数据

```zig
pub const WsTrade = struct {
    coin: []const u8,
    side: []const u8,      // "B" (买) 或 "A" (卖)
    px: Decimal,           // 成交价格
    sz: Decimal,           // 成交数量
    time: Timestamp,
    hash: []const u8,      // 交易哈希
    tid: ?u64 = null,      // 成交 ID (可选)
};
```

**JSON 示例**:
```json
{
  "coin": "BTC",
  "side": "B",
  "px": "97000.5",
  "sz": "0.1",
  "time": 1640000000000,
  "hash": "0x..."
}
```

---

## WsUserFills - 用户成交

```zig
pub const WsUserFills = struct {
    isSnapshot: bool,
    user: []const u8,
    fills: []UserFill,

    pub const UserFill = struct {
        coin: []const u8,
        px: Decimal,             // 成交价格
        sz: Decimal,             // 成交数量
        side: []const u8,        // "B" (买) 或 "A" (卖)
        time: Timestamp,
        startPosition: Decimal,  // 开始仓位
        dir: []const u8,         // 方向
        closedPnl: Decimal,      // 已实现盈亏
        hash: []const u8,
        oid: u64,                // 订单 ID
        crossed: bool,
        fee: Decimal,
        feeToken: []const u8,    // 手续费币种
        tid: u64,                // 成交 ID
    };
};
```

**dir 取值**:
- `"Open Long"` - 开多仓
- `"Close Long"` - 平多仓
- `"Open Short"` - 开空仓
- `"Close Short"` - 平空仓

**JSON 示例**:
```json
{
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
      "feeToken": "USDC",
      "tid": 987654
    }
  ]
}
```

---

## WsUserEvent - 用户事件

```zig
pub const WsUserEvent = union(enum) {
    fills: []UserFill,
    funding: Funding,
    liquidation: Liquidation,
    nonUserCancel: []NonUserCancel,

    pub const Funding = struct {
        coin: []const u8,
        usdc: Decimal,
        time: Timestamp,
    };

    pub const Liquidation = struct {
        // 清算详情
    };

    pub const NonUserCancel = struct {
        coin: []const u8,
        oid: u64,
    };
};
```

**JSON 示例 (fills)**:
```json
{
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
```

**JSON 示例 (funding)**:
```json
{
  "funding": {
    "coin": "ETH",
    "usdc": "0.123",
    "time": 1640000000000
  }
}
```

**JSON 示例 (nonUserCancel)**:
```json
{
  "nonUserCancel": [
    {
      "coin": "ETH",
      "oid": 123456
    }
  ]
}
```

---

## WsOrder - 订单更新

```zig
pub const WsOrder = struct {
    order: Order,
    status: []const u8,
    statusTimestamp: Timestamp,

    pub const Order = struct {
        coin: []const u8,
        side: []const u8,      // "B" (买) 或 "A" (卖)
        limitPx: Decimal,
        sz: Decimal,
        oid: u64,
        timestamp: Timestamp,
        origSz: Decimal,       // 原始数量
    };
};
```

**status 取值**:
- `"resting"` - 挂单中
- `"filled"` - 已成交
- `"canceled"` - 已撤销
- `"triggered"` - 已触发
- `"rejected"` - 已拒绝

**JSON 示例**:
```json
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
```

---

## WsCandle - K 线数据

```zig
pub const WsCandle = struct {
    t: Timestamp,      // 时间
    o: Decimal,        // 开盘价
    h: Decimal,        // 最高价
    l: Decimal,        // 最低价
    c: Decimal,        // 收盘价
    v: Decimal,        // 成交量
};
```

**JSON 示例**:
```json
{
  "t": 1640000000000,
  "o": "2000.0",
  "h": "2100.0",
  "l": "1950.0",
  "c": "2050.0",
  "v": "1000.0"
}
```

---

## WsBbo - 最优买卖价

```zig
pub const WsBbo = struct {
    coin: []const u8,
    bid: Decimal,
    ask: Decimal,
    time: Timestamp,
};
```

**JSON 示例**:
```json
{
  "coin": "ETH",
  "bid": "2000.5",
  "ask": "2001.0",
  "time": 1640000000000
}
```

---

## SubscriptionResponse - 订阅响应

```zig
pub const SubscriptionResponse = struct {
    method: []const u8,      // "subscribe" 或 "unsubscribe"
    subscription: Subscription,
};
```

**JSON 示例**:
```json
{
  "method": "subscribe",
  "subscription": {
    "type": "l2Book",
    "coin": "ETH"
  }
}
```

---

## 消息解析

### MessageHandler

```zig
pub const MessageHandler = struct {
    allocator: std.mem.Allocator,

    pub fn parse(self: *MessageHandler, raw: []const u8) !Message {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            raw,
            .{},
        );
        defer parsed.deinit();

        const channel = parsed.value.object.get("channel").?.string;

        if (std.mem.eql(u8, channel, "l2Book")) {
            return Message{ .l2_book = try self.parseL2Book(parsed.value) };
        } else if (std.mem.eql(u8, channel, "trades")) {
            return Message{ .trades = try self.parseTrades(parsed.value) };
        } else if (std.mem.eql(u8, channel, "userFills")) {
            return Message{ .user_fills = try self.parseUserFills(parsed.value) };
        }
        // ... 其他类型

        return Message{ .unknown = raw };
    }

    fn parseL2Book(self: *MessageHandler, value: std.json.Value) !WsBook {
        const data = value.object.get("data").?.object;

        const coin = data.get("coin").?.string;
        const time = @as(Timestamp, @intCast(data.get("time").?.integer));

        const levels_arr = data.get("levels").?.array.items;
        const bids = try self.parseLevels(levels_arr[0].array.items);
        const asks = try self.parseLevels(levels_arr[1].array.items);

        return WsBook{
            .coin = try self.allocator.dupe(u8, coin),
            .time = time,
            .levels = [2][]WsBook.Level{ bids, asks },
        };
    }
};
```

### 使用示例

```zig
var handler = MessageHandler.init(allocator);
defer handler.deinit();

ws.on_raw_message = struct {
    fn callback(raw: []const u8) void {
        const msg = handler.parse(raw) catch |err| {
            std.debug.print("Failed to parse message: {}\n", .{err});
            return;
        };

        switch (msg) {
            .l2_book => |book| {
                std.debug.print("Order Book: {s}\n", .{book.coin});
            },
            .trades => |trades| {
                for (trades) |trade| {
                    std.debug.print("Trade: {s} {}\n", .{trade.coin, trade.sz});
                }
            },
            else => {},
        }
    }
}.callback;
```

---

## 完整消息流程

```zig
pub fn handleWebSocketMessage(raw_msg: []const u8) void {
    var handler = MessageHandler.init(allocator);
    defer handler.deinit();

    const msg = handler.parse(raw_msg) catch |err| {
        logger.err("Failed to parse message: {}", .{err});
        return;
    };

    switch (msg) {
        .l2_book => |book| {
            // 更新本地订单簿
            orderbook_manager.updateBook(book);
        },
        .trades => |trades| {
            // 处理交易数据
            for (trades) |trade| {
                trade_recorder.record(trade);
            }
        },
        .user_fills => |fills| {
            // 更新仓位
            for (fills.fills) |fill| {
                position_tracker.handleFill(fill);
            }
        },
        .user_events => |event| {
            // 处理用户事件
            switch (event) {
                .fills => |fills| {
                    for (fills) |fill| {
                        order_manager.handleFill(fill);
                    }
                },
                .funding => |funding| {
                    logger.info("Funding: {s} {}", .{funding.coin, funding.usdc});
                },
                .nonUserCancel => |cancels| {
                    for (cancels) |cancel| {
                        order_manager.handleSystemCancel(cancel.oid);
                    }
                },
                else => {},
            }
        },
        .order_updates => |orders| {
            // 更新订单状态
            for (orders) |order| {
                order_manager.updateOrderStatus(order.order.oid, order.status);
            }
        },
        .subscription_response => |response| {
            logger.info("Subscription confirmed: {s}", .{response.method});
        },
        .pong => {
            // 心跳响应
        },
        .unknown => |raw| {
            logger.warn("Unknown message: {s}", .{raw});
        },
        else => {},
    }
}
```

## 参考资料

- [Hyperliquid WebSocket API](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket)
- [Subscriptions](./subscriptions.md)
- [WebSocket Guide](./websocket.md)
