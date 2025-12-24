# Hyperliquid 连接器 - API 参考

> 完整的 HTTP API 和 WebSocket API 文档

**最后更新**: 2025-12-24

---

## 目录

- [IExchange 接口](#iexchange-接口)
- [HTTP API](#http-api)
  - [Info API (市场数据)](#info-api)
  - [Exchange API (交易操作)](#exchange-api)
- [WebSocket API](#websocket-api)
  - [订阅管理](#订阅管理)
  - [消息类型](#消息类型)
- [错误处理](#错误处理)

---

## IExchange 接口

Hyperliquid 连接器通过 `IExchange` 接口提供统一的 API。

### 配置

```zig
pub const ExchangeConfig = struct {
    name: []const u8,          // "hyperliquid"
    api_key: []const u8 = "",
    api_secret: []const u8 = "",
    testnet: bool = false,
};
```

### 创建连接器

```zig
const connector = try HyperliquidConnector.create(allocator, config, logger);
defer connector.destroy();

const exchange = connector.interface();
```

---

## HTTP API

HTTP API 通过 `HttpClient` 和 `InfoAPI`/`ExchangeAPI` 模块实现。

### HttpClient

```zig
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,           // API 基础 URL
    http_client: std.http.Client,   // Zig 标准库 HTTP 客户端
    logger: Logger,

    // API 端点常量
    pub const API_BASE_URL_MAINNET = "https://api.hyperliquid.xyz";
    pub const API_BASE_URL_TESTNET = "https://api.hyperliquid-testnet.xyz";
    pub const INFO_ENDPOINT = "/info";
    pub const EXCHANGE_ENDPOINT = "/exchange";
};
```

---

## Info API

Info API 用于查询市场数据和账户信息，所有端点都通过 `POST /info` 访问，使用 `type` 字段区分。

### getAllMids

获取所有交易对的中间价格（订单簿 mid price）。

**函数签名**:
```zig
pub fn getAllMids(self: *InfoAPI) !std.StringHashMap([]const u8)
```

**参数**: 无

**返回值**: 币种名称到价格字符串的映射 (调用者必须调用 `freeAllMids()` 释放)

**错误**: `NetworkError.ConnectionFailed`, `NetworkError.HttpError`

**示例**:
```zig
var mids = try connector.info_api.getAllMids();
defer connector.info_api.freeAllMids(&mids);

const eth_price_str = mids.get("ETH").?;
const eth_price = try types.parsePrice(eth_price_str);
std.debug.print("ETH: ${}\n", .{eth_price.toFloat()});
```

**内部实现**:
- 发送 POST 请求到 `/info`，body 为 `{"type":"allMids"}`
- 解析 JSON 响应为 `std.StringHashMap([]const u8)`
- 返回的字符串需要手动释放（使用 `freeAllMids()`）

---

### getMeta

获取所有可交易资产的元数据信息。

**函数签名**:
```zig
pub fn getMeta(self: *InfoAPI) !std.json.Parsed(types.MetaResponse)
```

**返回结构**:
```zig
pub const MetaResponse = struct {
    universe: []AssetMeta,
};

pub const AssetMeta = struct {
    name: []const u8,
    szDecimals: ?u8 = null,
};
```

**示例**:
```zig
const parsed_meta = try connector.info_api.getMeta();
defer parsed_meta.deinit();

const meta = parsed_meta.value;
for (meta.universe) |asset| {
    std.debug.print("{s}: szDecimals={?}\n", .{
        asset.name, asset.szDecimals,
    });
}
```

**注意**: 返回的 `std.json.Parsed(types.MetaResponse)` 需要调用 `deinit()` 释放。

---

### getL2Book

获取指定币种的 L2 订单簿快照。

**函数签名**:
```zig
pub fn getL2Book(self: *InfoAPI, coin: []const u8) !std.json.Parsed(types.L2BookResponse)
```

**参数**:
- `coin`: 币种名称（如 "ETH", "BTC"）

**返回结构**:
```zig
pub const L2BookResponse = struct {
    coin: []const u8,
    levels: [2][]L2Level,  // [0]=bids, [1]=asks
    time: u64,
};

pub const L2Level = struct {
    px: []const u8,  // 价格字符串
    sz: []const u8,  // 数量字符串
    n: u32,          // 订单数量
};
```

**示例**:
```zig
const parsed_l2 = try connector.info_api.getL2Book("ETH");
defer parsed_l2.deinit();

const l2_data = parsed_l2.value;

// 获取最优买价
const best_bid = l2_data.levels[0][0];
const bid_price = try types.parsePrice(best_bid.px);
const bid_size = try types.parseSize(best_bid.sz);

std.debug.print("Best Bid: {} @ {}\n", .{
    bid_size.toFloat(),
    bid_price.toFloat(),
});
```

**注意**:
- 返回的 `std.json.Parsed(types.L2BookResponse)` 需要调用 `deinit()` 释放
- 价格和数量以字符串形式返回，需要使用 `types.parsePrice()` 和 `types.parseSize()` 转换

---

### getUserState

获取用户的永续合约账户摘要，包括余额、仓位、保证金等。

**函数签名**:
```zig
pub fn getUserState(self: *InfoAPI, user: []const u8) !types.UserStateResponse
```

**参数**:
- `user`: 用户地址（主账户或子账户地址）

**返回结构**:
```zig
pub const UserStateResponse = struct {
    assetPositions: []AssetPosition,
    crossMarginSummary: MarginSummary,
    marginSummary: MarginSummary,
    withdrawable: []const u8,
};

pub const MarginSummary = struct {
    accountValue: []const u8,     // 账户总价值（字符串）
    totalMarginUsed: []const u8,  // 总已用保证金（字符串）
    totalNtlPos: []const u8,      // 总名义仓位价值（字符串）
    totalRawUsd: []const u8,      // 总原始 USD（字符串）
    withdrawable: []const u8,     // 可提取金额（字符串）
};

pub const AssetPosition = struct {
    position: struct {
        coin: []const u8,
        entryPx: ?[]const u8,
        leverage: struct {
            type: []const u8,
            value: u32,
        },
        liquidationPx: ?[]const u8,
        marginUsed: []const u8,
        positionValue: []const u8,
        returnOnEquity: []const u8,
        szi: []const u8,          // 仓位大小（字符串）
        unrealizedPnl: []const u8,
    },
    type: []const u8,  // "oneWay" 或 "hedge"
};
```

**示例**:
```zig
const user_state = try connector.info_api.getUserState(user_address);

std.debug.print("Account Value: {s}\n", .{
    user_state.crossMarginSummary.accountValue,
});

for (user_state.assetPositions) |asset_pos| {
    const pos = asset_pos.position;
    std.debug.print("{s}: size={s}\n", .{
        pos.coin, pos.szi,
    });
}
```

**注意**: 此函数返回的 `UserStateResponse` 内部字段已被复制，调用者无需手动释放。

---

**注意**: Info API 还支持其他端点（如 `getUserFills`, `getOpenOrders`），但当前实现中未单独封装。可以通过直接构造 JSON 请求调用 `http_client.postInfo()` 实现。

---

## Exchange API

Exchange API 用于执行交易操作，所有端点都通过 `POST /exchange` 访问，**需要 EIP-712 签名**。

### placeOrder

下限价单或市价单。

**函数签名**:
```zig
pub fn placeOrder(
    self: *ExchangeAPI,
    order_request: types.OrderRequest,
) !types.OrderResponse
```

**参数结构**:
```zig
pub const OrderRequest = struct {
    coin: []const u8,
    is_buy: bool,
    sz: []const u8,          // 数量（字符串）
    limit_px: []const u8,    // 限价（字符串）
    order_type: HyperliquidOrderType,
    reduce_only: bool,
};

pub const HyperliquidOrderType = struct {
    limit: ?LimitOrderParams = null,
    market: ?MarketOrderParams = null,
};

pub const LimitOrderParams = struct {
    tif: []const u8,  // "Gtc", "Ioc", "Alo"
};
```

**返回结构**:
```zig
pub const OrderResponse = struct {
    status: []const u8,  // "ok" or 错误消息
    response: ?struct {
        type: []const u8,
        data: ?struct {
            statuses: []struct {
                resting: ?struct {
                    oid: u64,  // 订单 ID
                },
            },
        },
    },
};
```

**示例**:
```zig
// 构造订单请求
const order_request = types.OrderRequest{
    .coin = "ETH",
    .is_buy = true,
    .sz = "0.1",
    .limit_px = "2000.0",
    .order_type = .{ .limit = .{ .tif = "Gtc" } },
    .reduce_only = false,
};

// 下单（需要配置 signer）
const response = try connector.exchange_api.placeOrder(order_request);

if (std.mem.eql(u8, response.status, "ok")) {
    std.debug.print("Order placed successfully\n", .{});
}
```

**注意**:
- 需要在 `ExchangeAPI` 初始化时传入 `Signer` 实例
- 当前实现返回 `error.NotImplemented`，因为签名集成尚未完全完成

---

### cancelOrder

撤销单个订单。

**函数签名**:
```zig
pub fn cancelOrder(
    self: *ExchangeAPI,
    coin: []const u8,
    order_id: u64,
) !types.CancelResponse
```

**示例**:
```zig
const cancel_result = try connector.exchange_api.cancelOrder("ETH", 77738308);

if (std.mem.eql(u8, cancel_result.status, "ok")) {
    std.debug.print("Order cancelled successfully\n", .{});
}
```

**注意**: 当前实现返回 `error.NotImplemented`。

---

### cancelAllOrders

批量撤销所有订单（或指定币种的订单）。

**函数签名**:
```zig
pub fn cancelAllOrders(
    self: *ExchangeAPI,
    coin: ?[]const u8,
) !types.CancelResponse
```

**注意**: 当前实现返回 `error.NotImplemented`。

---

## WebSocket API

WebSocket API 提供实时数据流，延迟 < 10ms。

### 连接配置

```zig
pub const Config = struct {
    ws_url: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8 = "/ws",
    use_tls: bool = true,
    max_message_size: usize = 1024 * 1024, // 1MB
    buffer_size: usize = 8192,
    handshake_timeout_ms: u32 = 10000,
    reconnect_interval_ms: u64 = 5000,
    max_reconnect_attempts: u32 = 10,
    ping_interval_ms: u64 = 30000,
};
```

**初始化**:
```zig
const ws_config = HyperliquidWS.Config{
    .ws_url = "wss://api.hyperliquid-testnet.xyz/ws",
    .host = "api.hyperliquid-testnet.xyz",
    .port = 443,
};

var ws = HyperliquidWS.init(allocator, ws_config, logger);
defer ws.deinit();

try ws.connect();
```

---

## 订阅管理

### 订阅类型

```zig
pub const Channel = enum {
    // 市场数据订阅
    allMids,                        // 所有币种中间价
    l2Book,                         // L2 订单簿
    trades,                         // 交易数据
    user,                           // 用户数据（通用）

    // 用户数据订阅 (需要 user 参数)
    orderUpdates,                   // 订单更新
    userFills,                      // 用户成交
    userFundings,                   // 用户资金费用
    userNonFundingLedgerUpdates,    // 非资金费用账本

    pub fn toString(self: Channel) []const u8 {
        return switch (self) {
            .allMids => "allMids",
            .l2Book => "l2Book",
            .trades => "trades",
            .user => "user",
            .orderUpdates => "orderUpdates",
            .userFills => "userFills",
            .userFundings => "userFundings",
            .userNonFundingLedgerUpdates => "userNonFundingLedgerUpdates",
        };
    }
};
```

### subscribe

订阅频道。

**函数签名**:
```zig
pub fn subscribe(self: *HyperliquidWS, sub: Subscription) !void

pub const Subscription = struct {
    channel: Channel,
    coin: ?[]const u8 = null,  // l2Book, trades 需要
    user: ?[]const u8 = null,  // 用户频道需要地址

    pub fn toJSON(self: Subscription, allocator: std.mem.Allocator) ![]u8;
};
```

**示例**:
```zig
// 订阅 ETH L2 订单簿
try ws.subscribe(.{
    .channel = .l2Book,
    .coin = "ETH",
});

// 订阅所有中间价
try ws.subscribe(.{
    .channel = .allMids,
});

// 订阅用户成交（需要用户地址）
try ws.subscribe(.{
    .channel = .userFills,
    .user = "0x1234...",
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

WebSocket 消息通过 `Message` union 类型表示：

```zig
pub const Message = union(enum) {
    allMids: AllMidsData,
    l2Book: L2BookData,
    trades: TradesData,
    user: UserData,
    orderUpdate: OrderUpdateData,
    userFill: UserFillData,
    subscriptionResponse: SubscriptionResponse,
    error_msg: ErrorMessage,
    unknown: []const u8,

    pub fn deinit(self: Message, allocator: std.mem.Allocator) void;
};
```

### L2BookData - L2 订单簿

```zig
pub const L2BookData = struct {
    coin: []const u8,
    time: u64,
    levels: [2][]Level,  // [0]=bids, [1]=asks

    pub const Level = struct {
        px: []const u8,  // 价格字符串
        sz: []const u8,  // 数量字符串
        n: u32,          // 订单数量
    };
};
```

### AllMidsData - 所有中间价

```zig
pub const AllMidsData = struct {
    mids: []MidPrice,

    pub const MidPrice = struct {
        coin: []const u8,
        price: []const u8,
    };
};
```

### TradesData - 交易数据

```zig
pub const TradesData = struct {
    trades: []Trade,

    pub const Trade = struct {
        coin: []const u8,
        side: []const u8,  // "B" 或 "A"
        px: []const u8,
        sz: []const u8,
        time: u64,
        hash: []const u8,
        tid: ?u64 = null,
    };
};
```

---

### 消息回调

设置消息回调函数以处理接收到的 WebSocket 消息：

```zig
// 定义回调函数
fn handleMessage(msg: ws_types.Message) void {
    switch (msg) {
        .l2Book => |book| {
            // 处理 L2 订单簿更新
            std.debug.print("L2 Book for {s}\n", .{book.coin});
        },
        .trades => |trades_data| {
            // 处理交易数据
            for (trades_data.trades) |trade| {
                std.debug.print("Trade: {s} {s} @ {s}\n", .{
                    trade.coin, trade.side, trade.px,
                });
            }
        },
        .allMids => |mids_data| {
            // 处理所有中间价
            for (mids_data.mids) |mid| {
                std.debug.print("{s}: {s}\n", .{mid.coin, mid.price});
            }
        },
        .userFill => |fill| {
            // 处理用户成交
            std.debug.print("Fill: {s}\n", .{fill});
        },
        .subscriptionResponse => |resp| {
            // 处理订阅确认
            std.debug.print("Subscription response: {}\n", .{resp});
        },
        .error_msg => |err| {
            // 处理错误消息
            std.debug.print("Error: {s}\n", .{err.error_msg});
        },
        .unknown => |raw| {
            // 处理未知消息
            std.debug.print("Unknown message: {s}\n", .{raw});
        },
        else => {},
    }
}

// 设置回调
ws.on_message = handleMessage;
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

## 认证 (EIP-712 签名)

Exchange API 需要使用 EIP-712 签名进行认证。

### Signer

```zig
pub const Signer = struct {
    allocator: Allocator,
    wallet: zigeth.signer.Wallet,  // Ethereum 钱包 (secp256k1)
    address: []const u8,            // 以太坊地址 (0x...)

    pub fn init(allocator: Allocator, private_key: [32]u8) !Signer;
    pub fn deinit(self: *Signer) void;
    pub fn signAction(self: *Signer, action_data: []const u8) !Signature;
};

pub const Signature = struct {
    r: []const u8,  // 32 bytes as hex string
    s: []const u8,  // 32 bytes as hex string
    v: u8,          // Recovery ID (27 or 28)
};
```

**示例**:
```zig
// 初始化签名器
const private_key = [_]u8{0x42} ** 32;  // 替换为实际私钥
var signer = try Signer.init(allocator, private_key);
defer signer.deinit();

// 签名 action
const action_json = "...";  // Action JSON
const signature = try signer.signAction(action_json);
defer allocator.free(signature.r);
defer allocator.free(signature.s);

std.debug.print("Signature: r={s}, s={s}, v={}\n", .{
    signature.r, signature.s, signature.v,
});
```

---

*Last updated: 2025-12-24*
