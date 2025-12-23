# Hyperliquid WebSocket 使用指南

> 导航: [首页](../../../README.md) / [Features](../../README.md) / [Hyperliquid 连接器](./README.md) / WebSocket

## 概述

Hyperliquid WebSocket API 提供实时数据流，包括订单簿更新、交易数据、用户事件等。相比 REST API，WebSocket 具有更低的延迟（<10ms）和更高的效率。

## 连接信息

| 环境 | WebSocket URL |
|------|--------------|
| 主网 | `wss://api.hyperliquid.xyz/ws` |
| 测试网 | `wss://api.hyperliquid-testnet.xyz/ws` |

## 快速开始

### 初始化 WebSocket 客户端

```zig
const std = @import("std");
const HyperliquidWS = @import("exchange/hyperliquid/websocket.zig").HyperliquidWS;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 配置
    const config = HyperliquidWS.HyperliquidWSConfig{
        .ws_url = HyperliquidWS.HyperliquidWSConfig.DEFAULT_TESTNET_WS_URL,
        .reconnect_interval_ms = 1000,
        .max_reconnect_attempts = 5,
        .ping_interval_ms = 30000,
    };

    var ws = try HyperliquidWS.init(allocator, config, logger);
    defer ws.deinit();

    // 设置回调
    ws.on_message = handleMessage;
    ws.on_connect = handleConnect;
    ws.on_disconnect = handleDisconnect;

    // 连接
    try ws.connect();

    // 订阅
    try ws.subscribe(.{
        .channel = .l2Book,
        .coin = "ETH",
    });

    // 保持运行
    while (true) {
        std.time.sleep(std.time.ns_per_s);
    }
}
```

## 订阅管理

### 订阅订单簿

```zig
try ws.subscribe(.{
    .channel = .l2Book,
    .coin = "ETH",
    .nSigFigs = null,    // 可选：价格精度
    .mantissa = null,    // 可选：尾数
});
```

### 订阅交易数据

```zig
try ws.subscribe(.{
    .channel = .trades,
    .coin = "BTC",
});
```

### 订阅用户事件

```zig
const user_address = try client.auth.getUserAddress();

try ws.subscribe(.{
    .channel = .userEvents,
    .user = user_address,
});
```

### 订阅用户成交

```zig
try ws.subscribe(.{
    .channel = .userFills,
    .user = user_address,
    .aggregateByTime = false,  // 可选：是否按时间聚合
});
```

### 取消订阅

```zig
try ws.unsubscribe(.{
    .channel = .l2Book,
    .coin = "ETH",
});
```

## 消息处理

### 设置消息回调

```zig
fn handleMessage(msg: Message) void {
    switch (msg) {
        .l2_book => |book| {
            handleOrderBookUpdate(book);
        },
        .trades => |trades| {
            for (trades) |trade| {
                handleTrade(trade);
            }
        },
        .user_fills => |fills| {
            handleUserFills(fills);
        },
        .user_events => |event| {
            handleUserEvent(event);
        },
        .all_mids => |mids| {
            handleAllMids(mids);
        },
        .subscription_response => |response| {
            std.debug.print("Subscription confirmed: {s}\n", .{response.data.method});
        },
        .pong => {
            std.debug.print("Pong received\n", .{});
        },
        .unknown => |raw| {
            std.debug.print("Unknown message: {s}\n", .{raw});
        },
    }
}
```

### 订单簿更新

```zig
fn handleOrderBookUpdate(book: WsBook) void {
    std.debug.print("Order Book Update: {s}\n", .{book.coin});

    // 处理买单
    if (book.levels[0].len > 0) {
        const best_bid = book.levels[0][0];
        std.debug.print("  Best Bid: {} @ {}\n", .{
            best_bid.sz, best_bid.px,
        });
    }

    // 处理卖单
    if (book.levels[1].len > 0) {
        const best_ask = book.levels[1][0];
        std.debug.print("  Best Ask: {} @ {}\n", .{
            best_ask.sz, best_ask.px,
        });
    }
}
```

### 交易数据

```zig
fn handleTrade(trade: WsTrade) void {
    const side_str = if (std.mem.eql(u8, trade.side, "B")) "BUY" else "SELL";
    std.debug.print("Trade: {s} {s} {} @ {}\n", .{
        trade.coin, side_str, trade.sz, trade.px,
    });
}
```

### 用户成交

```zig
fn handleUserFills(fills: WsUserFills) void {
    if (fills.isSnapshot) {
        std.debug.print("Received fills snapshot ({} fills)\n", .{fills.fills.len});
    }

    for (fills.fills) |fill| {
        std.debug.print("Fill: {s} {s} {} @ {} (PnL: {})\n", .{
            fill.coin,
            fill.dir,
            fill.sz,
            fill.px,
            fill.closedPnl,
        });
    }
}
```

### 用户事件

```zig
fn handleUserEvent(event: WsUserEvent) void {
    switch (event) {
        .fills => |fills| {
            for (fills) |fill| {
                std.debug.print("Fill event: {s} {}\n", .{fill.coin, fill.sz});
            }
        },
        .funding => |funding| {
            std.debug.print("Funding: {s} {} USDC\n", .{
                funding.coin, funding.usdc,
            });
        },
        .liquidation => |liquidation| {
            std.debug.print("Liquidation event: {}\n", .{liquidation});
        },
        .nonUserCancel => |cancels| {
            for (cancels) |cancel| {
                std.debug.print("System cancelled order: OID={}\n", .{cancel.oid});
            }
        },
    }
}
```

## 连接管理

### 连接状态

```zig
if (ws.connected.load(.acquire)) {
    std.debug.print("WebSocket is connected\n", .{});
} else {
    std.debug.print("WebSocket is disconnected\n", .{});
}
```

### 手动断开

```zig
ws.disconnect();
```

### 连接回调

```zig
ws.on_connect = handleConnect;
ws.on_disconnect = handleDisconnect;

fn handleConnect() void {
    std.debug.print("WebSocket connected\n", .{});
}

fn handleDisconnect() void {
    std.debug.print("WebSocket disconnected\n", .{});
}
```

## 断线重连

HyperliquidWS 内置自动重连机制：

### 配置重连参数

```zig
const config = HyperliquidWS.HyperliquidWSConfig{
    .ws_url = "wss://api.hyperliquid-testnet.xyz/ws",
    .reconnect_interval_ms = 1000,  // 重连间隔
    .max_reconnect_attempts = 5,    // 最大重连次数
    .ping_interval_ms = 30000,      // 心跳间隔
};
```

### 重连流程

1. 检测到连接断开
2. 等待 `reconnect_interval_ms`
3. 尝试重新连接
4. 重连成功后，自动重新订阅所有频道
5. 如果重连失败，继续尝试直到达到 `max_reconnect_attempts`

### 重连错误处理

```zig
ws.on_error = handleError;

fn handleError(err: Error) void {
    switch (err) {
        Error.ConnectionFailed => {
            std.debug.print("Connection failed after max retries\n", .{});
        },
        else => {
            std.debug.print("Error: {}\n", .{err});
        },
    }
}
```

## 心跳机制

WebSocket 客户端自动发送心跳（ping）保持连接活跃：

```zig
const config = HyperliquidWS.HyperliquidWSConfig{
    .ping_interval_ms = 30000,  // 每 30 秒发送一次 ping
    // ...
};
```

## 最佳实践

### 1. 订阅快照

某些订阅（如 `userFills`）会在订阅确认时返回历史快照：

```zig
fn handleUserFills(fills: WsUserFills) void {
    if (fills.isSnapshot) {
        // 这是历史快照，初始化本地状态
        initializeFromSnapshot(fills.fills);
    } else {
        // 这是增量更新
        updateFromFill(fills.fills);
    }
}
```

### 2. 订阅限制

每个 IP 最多 1000 个订阅，避免过度订阅：

```zig
// 只订阅必要的频道
try ws.subscribe(.{ .channel = .l2Book, .coin = "ETH" });
try ws.subscribe(.{ .channel = .trades, .coin = "ETH" });

// 如果需要多个币种，考虑使用 allMids 而非逐个订阅
try ws.subscribe(.{ .channel = .allMids });
```

### 3. 消息顺序

WebSocket 消息按时间顺序推送，使用时间戳排序：

```zig
fn processMessages(messages: []Message) void {
    std.sort.sort(Message, messages, {}, compareByTime);

    for (messages) |msg| {
        handleMessage(msg);
    }
}

fn compareByTime(context: void, a: Message, b: Message) bool {
    _ = context;
    return a.getTime() < b.getTime();
}
```

### 4. 错误恢复

WebSocket 可能因网络波动断开，确保有完善的错误恢复：

```zig
ws.on_disconnect = handleDisconnect;

fn handleDisconnect() void {
    // 记录断开时间
    const disconnect_time = std.time.timestamp();

    // WebSocket 会自动重连
    // 重连后，考虑重新获取快照数据
    logger.warn("WebSocket disconnected at {}", .{disconnect_time});
}
```

## 完整示例

```zig
const std = @import("std");
const HyperliquidWS = @import("exchange/hyperliquid/websocket.zig").HyperliquidWS;
const OrderBook = @import("core/orderbook.zig").OrderBook;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = HyperliquidWS.HyperliquidWSConfig{
        .ws_url = HyperliquidWS.HyperliquidWSConfig.DEFAULT_TESTNET_WS_URL,
        .reconnect_interval_ms = 1000,
        .max_reconnect_attempts = 5,
        .ping_interval_ms = 30000,
    };

    var ws = try HyperliquidWS.init(allocator, config, logger);
    defer ws.deinit();

    // 本地订单簿
    var eth_orderbook = try OrderBook.init(allocator, "ETH");
    defer eth_orderbook.deinit();

    // 设置回调
    ws.on_message = struct {
        fn callback(msg: Message) void {
            switch (msg) {
                .l2_book => |book| {
                    if (std.mem.eql(u8, book.coin, "ETH")) {
                        // 更新本地订单簿
                        eth_orderbook.applySnapshot(
                            book.levels[0],
                            book.levels[1],
                            book.time,
                        ) catch |err| {
                            std.debug.print("Failed to update orderbook: {}\n", .{err});
                        };
                    }
                },
                else => {},
            }
        }
    }.callback;

    // 连接
    try ws.connect();

    // 订阅 ETH 订单簿
    try ws.subscribe(.{
        .channel = .l2Book,
        .coin = "ETH",
    });

    // 订阅 ETH 交易数据
    try ws.subscribe(.{
        .channel = .trades,
        .coin = "ETH",
    });

    // 保持运行
    while (true) {
        std.time.sleep(std.time.ns_per_s);

        // 打印最优价格
        if (eth_orderbook.getBestBid()) |bid| {
            std.debug.print("Best Bid: {}\n", .{bid.price.toFloat()});
        }
    }
}
```

## 参考资料

- [Hyperliquid WebSocket API](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket)
- [Subscriptions](./subscriptions.md) - 订阅类型详解
- [Message Types](./message-types.md) - 消息格式参考
- [websocket.zig Library](https://github.com/karlseguin/websocket.zig)
