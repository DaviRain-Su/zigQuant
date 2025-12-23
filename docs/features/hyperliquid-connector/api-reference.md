# Hyperliquid API 参考

> 导航: [首页](../../../README.md) / [Features](../../README.md) / [Hyperliquid 连接器](./README.md) / API 参考

## Info API

Info API 用于查询市场数据和账户信息，所有端点都通过 `POST /info` 访问，使用 `type` 字段区分。

### getAllMids - 获取所有币种中间价

获取所有交易对的中间价格（订单簿 mid price）。

**函数签名**:
```zig
pub fn getAllMids(client: *HyperliquidClient) !std.StringHashMap(Decimal)
```

**请求示例**:
```zig
const all_mids = try InfoAPI.getAllMids(&client);
defer all_mids.deinit();

const eth_price = all_mids.get("ETH").?;
std.debug.print("ETH: ${}\n", .{eth_price.toFloat()});
```

**返回值**: 币种名称到价格的映射

**错误**: `error.NetworkError`, `error.ParseError`

---

### getMeta - 获取交易所元数据

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

**使用示例**:
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

### getL2Book - 获取订单簿快照

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

**使用示例**:
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

### getUserState - 获取用户账户状态

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

**使用示例**:
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

### getUserFills - 获取用户成交历史

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

### getOpenOrders - 获取未完成订单

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

### placeOrder - 下单

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

**使用示例**:
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

**返回结构**:
```zig
pub const OrderResponse = struct {
    status: []const u8,  // "ok" or "err"
    response: Response,

    pub const Status = union(enum) {
        resting: RestingOrder,   // 订单挂单成功
        filled: FilledOrder,     // 订单完全成交
        error: []const u8,       // 错误消息
    };
};
```

---

### cancelOrder - 撤单

撤销单个订单。

**函数签名**:
```zig
pub fn cancelOrder(
    client: *HyperliquidClient,
    coin: []const u8,
    oid: u64,
) !CancelResponse
```

**使用示例**:
```zig
const cancel_result = try ExchangeAPI.cancelOrder(&client, "ETH", 77738308);

if (std.mem.eql(u8, cancel_result.status, "ok")) {
    std.debug.print("Order cancelled successfully\n", .{});
}
```

---

### bulkCancel - 批量撤单

批量撤销多个订单。

**函数签名**:
```zig
pub fn bulkCancel(
    client: *HyperliquidClient,
    cancels: []CancelRequest,
) !CancelResponse
```

---

### marketOpen - 市价开仓

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

**使用示例**:
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

## 参考资料

- [Hyperliquid API Documentation](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api)
- [Info API Endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint)
- [Exchange API Endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint)
- [Authentication Guide](./authentication.md)
