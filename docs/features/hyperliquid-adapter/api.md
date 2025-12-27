# Hyperliquid Adapter API 参考

**模块**: `zigQuant.adapters.hyperliquid`
**版本**: v0.6.0
**状态**: 📋 待开始

---

## HyperliquidDataProvider

实现 `IDataProvider` 接口的 Hyperliquid 数据源适配器。

### 类型定义

```zig
pub const HyperliquidDataProvider = struct {
    allocator: Allocator,
    config: Config,
    ws_client: WebSocketClient,
    subscriptions: SubscriptionManager,
    message_bus: *MessageBus,
    cache: *Cache,
    connected: std.atomic.Value(bool),
};
```

### Config

```zig
pub const Config = struct {
    /// WebSocket 连接地址
    ws_url: []const u8 = "wss://api.hyperliquid.xyz/ws",

    /// 是否使用测试网
    testnet: bool = false,

    /// 重连延迟 (毫秒)
    reconnect_delay_ms: u32 = 1000,

    /// 最大重连尝试次数
    max_reconnect_attempts: u32 = 10,

    /// Ping 间隔 (毫秒)
    ping_interval_ms: u32 = 30000,
};
```

### 方法

#### init

```zig
pub fn init(
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    config: Config,
) !HyperliquidDataProvider
```

初始化数据提供者。

**参数**:
- `allocator`: 内存分配器
- `message_bus`: 消息总线引用
- `cache`: 缓存引用
- `config`: 配置选项

**返回**: 初始化的数据提供者实例

---

#### deinit

```zig
pub fn deinit(self: *HyperliquidDataProvider) void
```

释放资源，关闭连接。

---

#### start

```zig
pub fn start(self: *HyperliquidDataProvider) !void
```

启动 WebSocket 连接。

**错误**:
- `ConnectionFailed`: 无法建立连接
- `HandshakeFailed`: WebSocket 握手失败

---

#### stop

```zig
pub fn stop(self: *HyperliquidDataProvider) void
```

停止连接并清理订阅。

---

#### subscribe

```zig
pub fn subscribe(self: *HyperliquidDataProvider, symbol: []const u8) !void
```

订阅指定交易对的市场数据。

**参数**:
- `symbol`: 交易对符号 (如 "BTC", "ETH")

**错误**:
- `NotConnected`: 未连接
- `SubscriptionFailed`: 订阅请求失败

---

#### unsubscribe

```zig
pub fn unsubscribe(self: *HyperliquidDataProvider, symbol: []const u8) void
```

取消订阅指定交易对。

---

#### isConnected

```zig
pub fn isConnected(self: *HyperliquidDataProvider) bool
```

检查连接状态。

---

#### asProvider

```zig
pub fn asProvider(self: *HyperliquidDataProvider) IDataProvider
```

获取 `IDataProvider` 接口。

---

## HyperliquidExecutionClient

实现 `IExecutionClient` 接口的 Hyperliquid 执行客户端。

### 类型定义

```zig
pub const HyperliquidExecutionClient = struct {
    allocator: Allocator,
    config: Config,
    http_client: HttpClient,
    ws_client: *WebSocketClient,
    wallet: Wallet,
    order_manager: OrderManager,
    message_bus: *MessageBus,
};
```

### Config

```zig
pub const Config = struct {
    /// REST API 地址
    api_url: []const u8 = "https://api.hyperliquid.xyz",

    /// 是否使用测试网
    testnet: bool = false,

    /// 私钥 (hex 格式, 不含 0x 前缀)
    private_key: []const u8,

    /// Vault 地址 (可选, 用于子账户交易)
    vault_address: ?[]const u8 = null,
};
```

### 方法

#### init

```zig
pub fn init(
    allocator: Allocator,
    message_bus: *MessageBus,
    ws_client: *WebSocketClient,
    config: Config,
) !HyperliquidExecutionClient
```

初始化执行客户端。

---

#### submitOrder

```zig
pub fn submitOrder(self: *HyperliquidExecutionClient, order: Order) !OrderResult
```

提交订单到交易所。

**参数**:
- `order`: 订单详情

**返回**: 订单结果 (包含交易所订单 ID)

**错误**:
- `SignatureFailed`: 签名失败
- `ApiError`: API 返回错误
- `InsufficientBalance`: 余额不足

---

#### cancelOrder

```zig
pub fn cancelOrder(self: *HyperliquidExecutionClient, order_id: []const u8) !bool
```

取消指定订单。

**参数**:
- `order_id`: 客户端订单 ID

**返回**: 是否成功取消

---

#### cancelAllOrders

```zig
pub fn cancelAllOrders(self: *HyperliquidExecutionClient) !u32
```

取消所有活动订单。

**返回**: 成功取消的订单数量

---

#### getOrderStatus

```zig
pub fn getOrderStatus(self: *HyperliquidExecutionClient, order_id: []const u8) !?OrderStatus
```

查询订单状态。

---

#### getPosition

```zig
pub fn getPosition(self: *HyperliquidExecutionClient, symbol: []const u8) !?Position
```

查询指定交易对的持仓。

---

#### getAccount

```zig
pub fn getAccount(self: *HyperliquidExecutionClient) !Account
```

查询账户信息。

---

## 数据类型

### Quote

```zig
pub const Quote = struct {
    symbol: []const u8,
    mid: Decimal,
    timestamp: Timestamp,
};
```

### OrderBook

```zig
pub const OrderBook = struct {
    symbol: []const u8,
    bids: []PriceLevel,
    asks: []PriceLevel,
    timestamp: Timestamp,
};

pub const PriceLevel = struct {
    price: Decimal,
    quantity: Decimal,
};
```

### Order

```zig
pub const Order = struct {
    client_order_id: []const u8,
    symbol: []const u8,
    side: Side,
    order_type: OrderType,
    quantity: Decimal,
    price: ?Decimal,
};

pub const Side = enum { buy, sell };
pub const OrderType = enum { market, limit };
```

### Position

```zig
pub const Position = struct {
    symbol: []const u8,
    side: PositionSide,
    quantity: Decimal,
    entry_price: Decimal,
    unrealized_pnl: Decimal,
    leverage: Decimal,
};

pub const PositionSide = enum { long, short };
```

### Account

```zig
pub const Account = struct {
    balance: Decimal,
    available: Decimal,
    margin_used: Decimal,
    unrealized_pnl: Decimal,
};
```

---

*Last updated: 2025-12-27*
