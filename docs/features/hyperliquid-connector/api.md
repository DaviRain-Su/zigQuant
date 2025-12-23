# Hyperliquid 连接器 - API 参考

> 完整的 HTTP API 和 WebSocket API 文档

**最后更新**: 2025-12-23

---

## 目录

- [HTTP API](#http-api)
  - [Info API (市场数据)](#info-api)
  - [Exchange API (交易操作)](#exchange-api)
- [WebSocket API](#websocket-api)
  - [订阅管理](#订阅管理)
  - [消息类型](#消息类型)
- [错误处理](#错误处理)

---

## HTTP API

所有 HTTP API 通过 `HyperliquidClient` 访问。

### 配置

```zig
pub const HyperliquidConfig = struct {
    base_url: []const u8,
    api_key: ?[]const u8,
    secret_key: ?[]const u8,
    testnet: bool,
    timeout_ms: u64,
    max_retries: u8,

    pub const DEFAULT_MAINNET_URL = "https://api.hyperliquid.xyz";
    pub const DEFAULT_TESTNET_URL = "https://api.hyperliquid-testnet.xyz";
};
```

---

## Info API

Info API 用于查询市场数据和账户信息，所有端点都通过 `POST /info` 访问，使用 `type` 字段区分。

### getAllMids

获取所有交易对的中间价格（订单簿 mid price）。

**函数签名**:
```zig
pub fn getAllMids(client: *HyperliquidClient) !std.StringHashMap(Decimal)
```

**参数**: 无

**返回值**: 币种名称到价格的映射

**错误**: `error.NetworkError`, `error.ParseError`

**示例**:
```zig
const all_mids = try InfoAPI.getAllMids(&client);
defer all_mids.deinit();

const eth_price = all_mids.get("ETH").?;
std.debug.print("ETH: ${}\n", .{eth_price.toFloat()});
```

---

### getMeta

获取所有可交易资产的元数据信息。

**函数签名**:
```zig
pub fn getMeta(client: *HyperliquidClient) !Meta
```

**返回结构**:
```zig
pub const Meta = struct {
    universe: []AssetInfo,
};

pub const AssetInfo = struct {
    name: []const u8,           // 资产名称
    szDecimals: u8,             // 数量精度
    maxLeverage: u32,           // 最大杠杆
    onlyIsolated: bool,         // 是否仅支持逐仓
};
```

**示例**:
```zig
const meta = try InfoAPI.getMeta(&client);
defer allocator.free(meta.universe);

for (meta.universe) |asset| {
    std.debug.print("{s}: max leverage={}x\n", .{
        asset.name, asset.maxLeverage,
    });
}
```

---

### getL2Book

获取指定币种的 L2 订单簿快照。

**函数签名**:
```zig
pub fn getL2Book(
    client: *HyperliquidClient,
    coin: []const u8,
) !OrderBook
```

**参数**:
- `coin`: 币种名称（如 "ETH", "BTC"）

**返回结构**:
```zig
pub const OrderBook = struct {
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

**示例**:
```zig
const orderbook = try InfoAPI.getL2Book(&client, "ETH");
defer allocator.free(orderbook.bids);
defer allocator.free(orderbook.asks);

std.debug.print("Best Bid: {} @ {}\n", .{
    orderbook.bids[0].sz.toFloat(),
    orderbook.bids[0].px.toFloat(),
});
```

---

### getUserState

获取用户的永续合约账户摘要，包括余额、仓位、保证金等。

**函数签名**:
```zig
pub fn getUserState(
    client: *HyperliquidClient,
    user_address: []const u8,
) !UserState
```

**参数**:
- `user_address`: 用户地址（主账户或子账户地址，**非** API wallet 地址）

**返回结构**:
```zig
pub const UserState = struct {
    assetPositions: []AssetPosition,
    marginSummary: MarginSummary,
    crossMarginSummary: MarginSummary,
    crossMaintenanceMarginUsed: Decimal,
    withdrawable: Decimal,
    time: Timestamp,

    pub const MarginSummary = struct {
        accountValue: Decimal,       // 账户总价值
        totalMarginUsed: Decimal,    // 总已用保证金
        totalNtlPos: Decimal,        // 总名义仓位价值
        totalRawUsd: Decimal,        // 总原始 USD
    };

    pub const AssetPosition = struct {
        position: Position,
        type_: []const u8,  // "oneWay" 或 "hedge"
    };
};
```

**示例**:
```zig
const user_address = try client.auth.getUserAddress();
defer allocator.free(user_address);

const state = try InfoAPI.getUserState(&client, user_address);

std.debug.print("Account Value: ${}\n", .{
    state.marginSummary.accountValue.toFloat(),
});

for (state.assetPositions) |asset_pos| {
    const pos = asset_pos.position;
    std.debug.print("{s}: {} @ {}\n", .{
        pos.coin, pos.szi.toFloat(), pos.entryPx.toFloat(),
    });
}
```

---

### getUserFills

获取用户的成交记录。

**函数签名**:
```zig
pub fn getUserFills(
    client: *HyperliquidClient,
    user_address: []const u8,
) ![]Fill
```

**返回结构**:
```zig
pub const Fill = struct {
    coin: []const u8,
    px: Decimal,                     // 成交价格
    sz: Decimal,                     // 成交数量
    side: []const u8,                // "B" (买) 或 "A" (卖)
    time: Timestamp,
    startPosition: Decimal,
    dir: []const u8,                 // "Open Long", "Close Short", 等
    closedPnl: Decimal,              // 已实现盈亏
    hash: []const u8,
    oid: u64,                        // 订单 ID
    crossed: bool,
    fee: Decimal,
    feeToken: []const u8,            // 手续费币种
    tid: u64,                        // 成交 ID
};
```

---

### getOpenOrders

获取用户当前所有未完成的订单。

**函数签名**:
```zig
pub fn getOpenOrders(
    client: *HyperliquidClient,
    user_address: []const u8,
) ![]OpenOrder
```

---

## Exchange API

Exchange API 用于执行交易操作，所有端点都通过 `POST /exchange` 访问，**需要 Ed25519 签名**。

### placeOrder

下限价单或市价单。

**函数签名**:
```zig
pub fn placeOrder(
    client: *HyperliquidClient,
    order: OrderRequest,
) !OrderResponse
```

**参数结构**:
```zig
pub const OrderRequest = struct {
    coin: []const u8,
    is_buy: bool,
    sz: Decimal,
    limit_px: Decimal,
    order_type: OrderType,
    reduce_only: bool,
    cloid: ?[]const u8 = null,  // 客户端订单 ID (可选)

    pub const OrderType = struct {
        limit: ?LimitOrder = null,
        trigger: ?TriggerOrder = null,

        pub const LimitOrder = struct {
            tif: []const u8,  // "Gtc", "Ioc", "Alo"
        };
    };
};
```

**返回结构**:
```zig
pub const OrderResponse = struct {
    status: []const u8,  // "ok" or "err"
    response: Response,

    pub const Status = union(enum) {
        resting: RestingOrder,   // 订单挂单成功
        filled: FilledOrder,     // 订单完全成交
        error: []const u8,       // 错误消息

        pub const RestingOrder = struct {
            oid: u64,
        };

        pub const FilledOrder = struct {
            totalSz: []const u8,
            avgPx: []const u8,
            oid: u64,
        };
    };
};
```

**示例**:
```zig
// GTC 限价单
const order = OrderRequest{
    .coin = "ETH",
    .is_buy = true,
    .sz = try Decimal.fromString("0.1"),
    .limit_px = try Decimal.fromString("2000.0"),
    .order_type = .{
        .limit = .{ .tif = "Gtc" },
    },
    .reduce_only = false,
};

const response = try ExchangeAPI.placeOrder(&client, order);

if (std.mem.eql(u8, response.status, "ok")) {
    const status = response.response.data.statuses[0];
    switch (status) {
        .resting => |resting| {
            std.debug.print("Order placed: OID={}\n", .{resting.oid});
        },
        .filled => |filled| {
            std.debug.print("Order filled: {} @ {}\n", .{
                filled.totalSz, filled.avgPx,
            });
        },
        .error => |err| {
            std.debug.print("Order failed: {s}\n", .{err});
        },
    }
}
```

---

### cancelOrder

撤销单个订单。

**函数签名**:
```zig
pub fn cancelOrder(
    client: *HyperliquidClient,
    coin: []const u8,
    oid: u64,
) !CancelResponse
```

**示例**:
```zig
const cancel_result = try ExchangeAPI.cancelOrder(&client, "ETH", 77738308);

if (std.mem.eql(u8, cancel_result.status, "ok")) {
    std.debug.print("Order cancelled successfully\n", .{});
}
```

---

### bulkCancel

批量撤销多个订单。

**函数签名**:
```zig
pub fn bulkCancel(
    client: *HyperliquidClient,
    cancels: []CancelRequest,
) !CancelResponse
```

---

### marketOpen

以市价开仓（使用 IOC 限价单模拟）。

**函数签名**:
```zig
pub fn marketOpen(
    client: *HyperliquidClient,
    coin: []const u8,
    is_buy: bool,
    sz: Decimal,
    slippage: Decimal,
) !OrderResponse
```

**参数**:
- `slippage`: 滑点保护（如 0.05 表示 5%）

**示例**:
```zig
// 市价买入 0.1 ETH，5% 滑点保护
const result = try ExchangeAPI.marketOpen(
    &client,
    "ETH",
    true,
    try Decimal.fromString("0.1"),
    try Decimal.fromString("0.05"),
);
```

---

## WebSocket API

WebSocket API 提供实时数据流，延迟 < 10ms。

### 连接

```zig
pub const HyperliquidWSConfig = struct {
    ws_url: []const u8,
    reconnect_interval_ms: u64,
    max_reconnect_attempts: u32,
    ping_interval_ms: u64,

    pub const DEFAULT_WS_URL = "wss://api.hyperliquid.xyz/ws";
    pub const DEFAULT_TESTNET_WS_URL = "wss://api.hyperliquid-testnet.xyz/ws";
};
```

**初始化**:
```zig
var ws = try HyperliquidWS.init(allocator, config, logger);
defer ws.deinit();

try ws.connect();
```

---

## 订阅管理

### 订阅类型

```zig
pub const ChannelType = enum {
    // 市场数据订阅
    allMids,                        // 所有币种中间价
    l2Book,                         // L2 订单簿
    trades,                         // 交易数据
    candle,                         // K线数据
    bbo,                            // 最优买卖价
    activeAssetCtx,                 // 资产上下文

    // 用户数据订阅 (需要 user 参数)
    notification,                   // 用户通知
    webData3,                       // Web 数据
    twapStates,                     // TWAP 状态
    clearinghouseState,             // 账户状态
    openOrders,                     // 未完成订单
    orderUpdates,                   // 订单更新
    userEvents,                     // 用户事件
    userFills,                      // 用户成交
    userFundings,                   // 用户资金费用
    userNonFundingLedgerUpdates,    // 非资金费用账本
    activeAssetData,                // 资产数据
    userTwapSliceFills,             // TWAP 切片成交
    userTwapHistory,                // TWAP 历史
};
```

### subscribe

订阅频道。

**函数签名**:
```zig
pub fn subscribe(self: *HyperliquidWS, subscription: Subscription) !void

pub const Subscription = struct {
    channel: ChannelType,
    coin: ?[]const u8 = null,       // 某些频道需要币种
    user: ?[]const u8 = null,       // 用户频道需要地址
    interval: ?[]const u8 = null,   // K线周期
    nSigFigs: ?u8 = null,           // 订单簿精度
    mantissa: ?u32 = null,          // 订单簿尾数
    aggregateByTime: ?bool = null,  // 是否按时间聚合
};
```

**示例**:
```zig
// 订阅 ETH 订单簿
try ws.subscribe(.{
    .channel = .l2Book,
    .coin = "ETH",
});

// 订阅用户成交
const user_address = try client.auth.getUserAddress();
try ws.subscribe(.{
    .channel = .userFills,
    .user = user_address,
});
```

---

### unsubscribe

取消订阅。

**函数签名**:
```zig
pub fn unsubscribe(self: *HyperliquidWS, subscription: Subscription) !void
```

---

## 消息类型

### WsBook - L2 订单簿

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

---

### WsTrade - 交易数据

```zig
pub const WsTrade = struct {
    coin: []const u8,
    side: []const u8,      // "B" (买) 或 "A" (卖)
    px: Decimal,           // 成交价格
    sz: Decimal,           // 成交数量
    time: Timestamp,
    hash: []const u8,
    tid: ?u64 = null,      // 成交 ID
};
```

---

### WsUserFills - 用户成交

```zig
pub const WsUserFills = struct {
    isSnapshot: bool,
    user: []const u8,
    fills: []UserFill,

    pub const UserFill = struct {
        coin: []const u8,
        px: Decimal,
        sz: Decimal,
        side: []const u8,
        time: Timestamp,
        startPosition: Decimal,
        dir: []const u8,         // "Open Long", "Close Short", 等
        closedPnl: Decimal,
        hash: []const u8,
        oid: u64,
        crossed: bool,
        fee: Decimal,
        feeToken: []const u8,
        tid: u64,
    };
};
```

**dir 取值**:
- `"Open Long"` - 开多仓
- `"Close Long"` - 平多仓
- `"Open Short"` - 开空仓
- `"Close Short"` - 平空仓

---

### WsUserEvent - 用户事件

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

    pub const NonUserCancel = struct {
        coin: []const u8,
        oid: u64,
    };
};
```

---

### 消息回调

```zig
pub const Message = union(enum) {
    l2_book: WsBook,
    trades: []WsTrade,
    user_fills: WsUserFills,
    user_events: WsUserEvent,
    order_updates: []WsOrder,
    all_mids: AllMids,
    candle: []Candle,
    clearinghouse_state: ClearinghouseState,
    subscription_response: SubscriptionResponse,
    pong: void,
    unknown: []const u8,
};

// 设置回调
ws.on_message = handleMessage;

fn handleMessage(msg: Message) void {
    switch (msg) {
        .l2_book => |book| {
            // 处理订单簿更新
        },
        .trades => |trades| {
            // 处理交易数据
        },
        .user_fills => |fills| {
            // 处理用户成交
        },
        else => {},
    }
}
```

---

## 错误处理

所有 API 调用都可能返回以下错误：

| 错误类型 | 说明 | 处理建议 |
|---------|------|---------|
| `error.NetworkError` | 网络连接失败 | 重试 |
| `error.Timeout` | 请求超时 | 重试 |
| `error.RateLimitExceeded` | 超过速率限制 | 等待后重试 |
| `error.ParseError` | 响应解析失败 | 检查 API 版本 |
| `error.OrderRejected` | 订单被拒绝 | 检查订单参数 |
| `error.SignatureError` | 签名验证失败 | 检查密钥和签名逻辑 |

**错误处理示例**:
```zig
const result = InfoAPI.getUserState(&client, user_address) catch |err| {
    switch (err) {
        error.NetworkError => {
            logger.warn("Network error, retrying...", .{});
            std.time.sleep(1 * std.time.ns_per_s);
            return err;
        },
        error.RateLimitExceeded => {
            logger.warn("Rate limited, waiting 10s...", .{});
            std.time.sleep(10 * std.time.ns_per_s);
            return err;
        },
        else => return err,
    }
};
```

---

## 参考资料

- [Hyperliquid API Documentation](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api)
- [Info API Endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint)
- [Exchange API Endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint)
- [WebSocket API](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket)

---

*Last updated: 2025-12-23*
