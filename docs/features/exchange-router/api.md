# Exchange Router - API 参考

> 完整的 IExchange 接口、统一数据类型、Registry API 文档

**最后更新**: 2025-12-23

---

## 目录

- [IExchange 接口](#iexchange-接口)
- [统一数据类型](#统一数据类型)
- [ExchangeRegistry API](#exchangeregistry-api)
- [SymbolMapper API](#symbolmapper-api)
- [完整示例](#完整示例)

---

## IExchange 接口

所有交易所连接器必须实现的统一接口。

### 类型定义

```zig
pub const IExchange = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        getName: *const fn (*anyopaque) []const u8,
        connect: *const fn (*anyopaque) anyerror!void,
        disconnect: *const fn (*anyopaque) void,
        isConnected: *const fn (*anyopaque) bool,
        getTicker: *const fn (*anyopaque, TradingPair) anyerror!Ticker,
        getOrderbook: *const fn (*anyopaque, TradingPair, u32) anyerror!Orderbook,
        createOrder: *const fn (*anyopaque, OrderRequest) anyerror!Order,
        cancelOrder: *const fn (*anyopaque, u64) anyerror!void,
        cancelAllOrders: *const fn (*anyopaque, ?TradingPair) anyerror!u32,
        getOrder: *const fn (*anyopaque, u64) anyerror!Order,
        getBalance: *const fn (*anyopaque) anyerror![]Balance,
        getPositions: *const fn (*anyopaque) anyerror![]Position,
    };
};
```

---

### 连接管理

#### `getName`

获取交易所名称。

```zig
pub fn getName(self: IExchange) []const u8
```

**返回**: 交易所名称（如 "hyperliquid", "binance"）

**示例**:
```zig
const name = exchange.getName();
std.debug.print("Exchange: {s}\n", .{name});
```

---

#### `connect`

连接到交易所（测试 API 连通性）。

```zig
pub fn connect(self: IExchange) !void
```

**错误**:
- `error.ConnectionFailed`: 连接失败
- `error.AuthenticationFailed`: 认证失败

**示例**:
```zig
try exchange.connect();
```

---

#### `disconnect`

断开交易所连接，释放资源。

```zig
pub fn disconnect(self: IExchange) void
```

**示例**:
```zig
defer exchange.disconnect();
```

---

#### `isConnected`

检查是否已连接。

```zig
pub fn isConnected(self: IExchange) bool
```

**返回**: 是否已连接

**示例**:
```zig
if (exchange.isConnected()) {
    // 执行操作
}
```

---

### 市场数据

#### `getTicker`

获取指定交易对的行情数据。

```zig
pub fn getTicker(self: IExchange, pair: TradingPair) !Ticker
```

**参数**:
- `pair`: 交易对

**返回**: Ticker 结构

**错误**:
- `error.SymbolNotFound`: 交易对不存在
- `error.NetworkError`: 网络错误

**示例**:
```zig
const pair = TradingPair{ .base = "ETH", .quote = "USDC" };
const ticker = try exchange.getTicker(pair);

std.debug.print("ETH Price: {}\n", .{ticker.last.toFloat()});
std.debug.print("Bid: {} | Ask: {}\n", .{
    ticker.bid.toFloat(),
    ticker.ask.toFloat(),
});
```

---

#### `getOrderbook`

获取指定交易对的订单簿。

```zig
pub fn getOrderbook(
    self: IExchange,
    pair: TradingPair,
    depth: u32,
) !Orderbook
```

**参数**:
- `pair`: 交易对
- `depth`: 深度（每侧最多返回的价格档位数）

**返回**: Orderbook 结构

**错误**:
- `error.SymbolNotFound`: 交易对不存在
- `error.InvalidDepth`: 深度参数无效

**示例**:
```zig
const orderbook = try exchange.getOrderbook(pair, 10);
defer allocator.free(orderbook.bids);
defer allocator.free(orderbook.asks);

if (orderbook.getBestBid()) |best_bid| {
    std.debug.print("Best Bid: {} @ {}\n", .{
        best_bid.quantity.toFloat(),
        best_bid.price.toFloat(),
    });
}

const mid = orderbook.getMidPrice() orelse return;
std.debug.print("Mid Price: {}\n", .{mid.toFloat()});
```

---

### 交易操作

#### `createOrder`

创建订单（限价单或市价单）。

```zig
pub fn createOrder(self: IExchange, request: OrderRequest) !Order
```

**参数**:
- `request`: 订单请求

**返回**: Order 结构

**错误**:
- `error.InvalidOrderRequest`: 订单参数无效
- `error.InsufficientBalance`: 余额不足
- `error.OrderRejected`: 订单被拒绝

**示例 - 限价单**:
```zig
const request = OrderRequest{
    .pair = .{ .base = "ETH", .quote = "USDC" },
    .side = .buy,
    .order_type = .limit,
    .amount = try Decimal.fromString("0.1"),
    .price = try Decimal.fromString("2000.0"),
    .time_in_force = .gtc,
    .reduce_only = false,
};

try request.validate();

const order = try exchange.createOrder(request);
std.debug.print("Order created: ID={}\n", .{order.exchange_order_id});
```

**示例 - 市价单**:
```zig
const market_request = OrderRequest{
    .pair = .{ .base = "BTC", .quote = "USDC" },
    .side = .sell,
    .order_type = .market,
    .amount = try Decimal.fromString("0.01"),
    .price = null,  // 市价单无需价格
};

try market_request.validate();
const order = try exchange.createOrder(market_request);
```

---

#### `cancelOrder`

撤销单个订单。

```zig
pub fn cancelOrder(self: IExchange, order_id: u64) !void
```

**参数**:
- `order_id`: 交易所订单 ID

**错误**:
- `error.OrderNotFound`: 订单不存在
- `error.OrderAlreadyCancelled`: 订单已撤销

**示例**:
```zig
try exchange.cancelOrder(12345678);
std.debug.print("Order cancelled\n", .{});
```

---

#### `cancelAllOrders`

撤销所有订单（可选指定交易对）。

```zig
pub fn cancelAllOrders(
    self: IExchange,
    pair: ?TradingPair,
) !u32
```

**参数**:
- `pair`: 交易对（null 表示所有交易对）

**返回**: 撤销的订单数量

**错误**:
- `error.CancelFailed`: 撤销失败

**示例**:
```zig
// 撤销 ETH-USDC 的所有订单
const cancelled = try exchange.cancelAllOrders(.{
    .base = "ETH",
    .quote = "USDC",
});
std.debug.print("Cancelled {} orders\n", .{cancelled});

// 撤销所有订单
const all_cancelled = try exchange.cancelAllOrders(null);
std.debug.print("Cancelled {} orders across all pairs\n", .{all_cancelled});
```

---

#### `getOrder`

查询订单状态。

```zig
pub fn getOrder(self: IExchange, order_id: u64) !Order
```

**参数**:
- `order_id`: 交易所订单 ID

**返回**: Order 结构

**错误**:
- `error.OrderNotFound`: 订单不存在

**示例**:
```zig
const order = try exchange.getOrder(12345678);

std.debug.print("Order Status: {s}\n", .{order.status.toString()});
std.debug.print("Filled: {} / {}\n", .{
    order.filled_amount.toFloat(),
    order.amount.toFloat(),
});

if (order.isComplete()) {
    std.debug.print("Order completed\n", .{});
}
```

---

### 账户查询

#### `getBalance`

获取账户余额。

```zig
pub fn getBalance(self: IExchange) ![]Balance
```

**返回**: Balance 数组（调用者负责释放）

**错误**:
- `error.AuthenticationRequired`: 需要认证

**示例**:
```zig
const balances = try exchange.getBalance();
defer allocator.free(balances);

for (balances) |balance| {
    std.debug.print("{s}: Total={} | Available={} | Locked={}\n", .{
        balance.asset,
        balance.total.toFloat(),
        balance.available.toFloat(),
        balance.locked.toFloat(),
    });

    try balance.validate();
}
```

---

#### `getPositions`

获取当前持仓（期货/永续合约）。

```zig
pub fn getPositions(self: IExchange) ![]Position
```

**返回**: Position 数组（调用者负责释放）

**错误**:
- `error.AuthenticationRequired`: 需要认证

**示例**:
```zig
const positions = try exchange.getPositions();
defer allocator.free(positions);

for (positions) |pos| {
    const direction = if (pos.isLong()) "LONG" else "SHORT";

    std.debug.print("{s}-{s} {s}: Size={} | Entry={} | PnL={}\n", .{
        pos.pair.base,
        pos.pair.quote,
        direction,
        pos.size.toFloat(),
        pos.entry_price.toFloat(),
        pos.unrealized_pnl.toFloat(),
    });

    if (pos.pnlPercent()) |pnl_pct| {
        std.debug.print("  PnL%: {}%\n", .{pnl_pct.toFloat()});
    }
}
```

---

## 统一数据类型

### TradingPair

交易对（基础货币 + 计价货币）。

```zig
pub const TradingPair = struct {
    base: []const u8,
    quote: []const u8,

    pub fn symbol(self: TradingPair, allocator: std.mem.Allocator) ![]const u8
    pub fn fromSymbol(sym: []const u8) !TradingPair
    pub fn eql(self: TradingPair, other: TradingPair) bool
};
```

**示例**:
```zig
const pair = TradingPair{ .base = "BTC", .quote = "USDT" };

const sym = try pair.symbol(allocator);
defer allocator.free(sym);
// sym = "BTC-USDT"

const parsed = try TradingPair.fromSymbol("ETH/USDC");
// parsed = TradingPair{ .base = "ETH", .quote = "USDC" }
```

---

### Side

订单方向。

```zig
pub const Side = enum {
    buy,
    sell,

    pub fn toString(self: Side) []const u8
    pub fn fromString(s: []const u8) !Side
};
```

---

### OrderType

订单类型。

```zig
pub const OrderType = enum {
    limit,   // 限价单
    market,  // 市价单

    pub fn toString(self: OrderType) []const u8
    pub fn fromString(s: []const u8) !OrderType
};
```

---

### TimeInForce

订单有效期类型。

```zig
pub const TimeInForce = enum {
    gtc,  // Good-Til-Cancel (一直有效直到成交或撤销)
    ioc,  // Immediate-or-Cancel (立即成交否则取消)
    alo,  // Add-Liquidity-Only (仅限 Maker 订单)
    fok,  // Fill-or-Kill (全部成交否则取消)

    pub fn toString(self: TimeInForce) []const u8
    pub fn fromString(s: []const u8) !TimeInForce
};
```

---

### OrderStatus

订单状态。

```zig
pub const OrderStatus = enum {
    pending,          // 待提交
    open,             // 挂单中
    filled,           // 完全成交
    partially_filled, // 部分成交
    cancelled,        // 已撤销
    rejected,         // 已拒绝

    pub fn toString(self: OrderStatus) []const u8
    pub fn fromString(s: []const u8) !OrderStatus
};
```

---

### OrderRequest

订单请求。

```zig
pub const OrderRequest = struct {
    pair: TradingPair,
    side: Side,
    order_type: OrderType,
    amount: Decimal,
    price: ?Decimal = null,
    time_in_force: TimeInForce = .gtc,
    reduce_only: bool = false,
    client_order_id: ?[]const u8 = null,

    pub fn validate(self: OrderRequest) !void
};
```

---

### Order

订单响应。

```zig
pub const Order = struct {
    exchange_order_id: u64,
    client_order_id: ?[]const u8 = null,
    pair: TradingPair,
    side: Side,
    order_type: OrderType,
    status: OrderStatus,
    amount: Decimal,
    price: ?Decimal,
    filled_amount: Decimal,
    avg_fill_price: ?Decimal = null,
    created_at: Timestamp,
    updated_at: Timestamp,

    pub fn remainingAmount(self: Order) Decimal
    pub fn isComplete(self: Order) bool
    pub fn isActive(self: Order) bool
};
```

---

### Ticker

行情数据。

```zig
pub const Ticker = struct {
    pair: TradingPair,
    bid: Decimal,
    ask: Decimal,
    last: Decimal,
    volume_24h: Decimal,
    timestamp: Timestamp,

    pub fn midPrice(self: Ticker) Decimal
    pub fn spread(self: Ticker) Decimal
    pub fn spreadBps(self: Ticker) Decimal
};
```

---

### OrderbookLevel

订单簿价格档位。

```zig
pub const OrderbookLevel = struct {
    price: Decimal,
    quantity: Decimal,
    num_orders: u32 = 1,

    pub fn notional(self: OrderbookLevel) Decimal
};
```

---

### Orderbook

L2 订单簿。

```zig
pub const Orderbook = struct {
    pair: TradingPair,
    bids: []OrderbookLevel,  // 买盘（从高到低）
    asks: []OrderbookLevel,  // 卖盘（从低到高）
    timestamp: Timestamp,

    pub fn getBestBid(self: Orderbook) ?OrderbookLevel
    pub fn getBestAsk(self: Orderbook) ?OrderbookLevel
    pub fn getMidPrice(self: Orderbook) ?Decimal
    pub fn getSpread(self: Orderbook) ?Decimal
};
```

---

### Balance

账户余额。

```zig
pub const Balance = struct {
    asset: []const u8,
    total: Decimal,
    available: Decimal,
    locked: Decimal,

    pub fn validate(self: Balance) !void
};
```

---

### Position

持仓信息。

```zig
pub const Position = struct {
    pair: TradingPair,
    side: Side,
    size: Decimal,
    entry_price: Decimal,
    mark_price: ?Decimal = null,
    liquidation_price: ?Decimal = null,
    unrealized_pnl: Decimal,
    leverage: u32,
    margin_used: Decimal,

    pub fn pnlPercent(self: Position) ?Decimal
    pub fn isLong(self: Position) bool
    pub fn isShort(self: Position) bool
};
```

---

## ExchangeRegistry API

### 类型定义

```zig
pub const ExchangeRegistry = struct {
    allocator: std.mem.Allocator,
    exchange: ?IExchange,
    config: ?ExchangeConfig,
    logger: Logger,

    pub fn init(allocator: std.mem.Allocator, logger: Logger) ExchangeRegistry
    pub fn setExchange(self: *ExchangeRegistry, exchange: IExchange, config: ExchangeConfig) !void
    pub fn getExchange(self: *ExchangeRegistry) !IExchange
    pub fn connectAll(self: *ExchangeRegistry) !void
    pub fn isConnected(self: *ExchangeRegistry) bool
    pub fn deinit(self: *ExchangeRegistry) void
};
```

---

### `init`

初始化注册表。

```zig
pub fn init(allocator: std.mem.Allocator, logger: Logger) ExchangeRegistry
```

**参数**:
- `allocator`: 内存分配器
- `logger`: 日志记录器

**返回**: ExchangeRegistry 实例

**示例**:
```zig
var logger = try Logger.init(allocator, .info);
var registry = ExchangeRegistry.init(allocator, logger);
defer registry.deinit();
```

---

### `setExchange`

注册交易所。

```zig
pub fn setExchange(
    self: *ExchangeRegistry,
    exchange: IExchange,
    config: ExchangeConfig,
) !void
```

**参数**:
- `exchange`: IExchange 接口实例
- `config`: 交易所配置

**示例**:
```zig
const exchange = try HyperliquidConnector.create(allocator, config, logger);
try registry.setExchange(exchange, config);
```

---

### `getExchange`

获取注册的交易所。

```zig
pub fn getExchange(self: *ExchangeRegistry) !IExchange
```

**返回**: IExchange 接口

**错误**:
- `error.NoExchangeRegistered`: 没有注册的交易所

**示例**:
```zig
const exchange = try registry.getExchange();
const ticker = try exchange.getTicker(pair);
```

---

### `connectAll`

连接所有注册的交易所。

```zig
pub fn connectAll(self: *ExchangeRegistry) !void
```

**示例**:
```zig
try registry.connectAll();
```

---

## SymbolMapper API

### 类型定义

```zig
pub const SymbolMapper = struct {
    pub fn init() SymbolMapper
    pub fn toHyperliquid(self: SymbolMapper, pair: TradingPair) ![]const u8
    pub fn fromHyperliquid(self: SymbolMapper, symbol: []const u8) !TradingPair
};
```

---

### `toHyperliquid`

转换为 Hyperliquid 格式。

```zig
pub fn toHyperliquid(self: SymbolMapper, pair: TradingPair) ![]const u8
```

**参数**:
- `pair`: 标准交易对

**返回**: Hyperliquid 符号（如 "ETH"）

**错误**:
- `error.UnsupportedQuoteCurrency`: 不支持的计价货币

**示例**:
```zig
var mapper = SymbolMapper.init();

const pair = TradingPair{ .base = "ETH", .quote = "USDC" };
const symbol = try mapper.toHyperliquid(pair);
// symbol = "ETH"
```

---

### `fromHyperliquid`

从 Hyperliquid 格式转换。

```zig
pub fn fromHyperliquid(self: SymbolMapper, symbol: []const u8) !TradingPair
```

**参数**:
- `symbol`: Hyperliquid 符号

**返回**: 标准交易对

**示例**:
```zig
const pair = try mapper.fromHyperliquid("BTC");
// pair = TradingPair{ .base = "BTC", .quote = "USDC" }
```

---

## 完整示例

### 示例 1: 基础使用

```zig
const std = @import("std");
const ExchangeRegistry = @import("exchange/registry.zig").ExchangeRegistry;
const HyperliquidConnector = @import("exchange/hyperliquid/connector.zig").HyperliquidConnector;
const TradingPair = @import("exchange/types.zig").TradingPair;
const OrderRequest = @import("exchange/types.zig").OrderRequest;
const Decimal = @import("core/decimal.zig").Decimal;
const Logger = @import("core/logger.zig").Logger;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 创建 Logger
    var logger = try Logger.init(allocator, .info);
    defer logger.deinit();

    // 2. 创建 Registry
    var registry = ExchangeRegistry.init(allocator, logger);
    defer registry.deinit();

    // 3. 创建 Hyperliquid Connector
    const config = .{
        .name = "hyperliquid",
        .api_key = "your_api_key",
        .api_secret = "your_secret",
        .testnet = true,
    };

    const exchange = try HyperliquidConnector.create(allocator, config, logger);

    // 4. 注册并连接
    try registry.setExchange(exchange, config);
    try registry.connectAll();

    // 5. 查询行情
    const pair = TradingPair{ .base = "ETH", .quote = "USDC" };
    const ticker = try exchange.getTicker(pair);

    std.debug.print("ETH Price: {}\n", .{ticker.last.toFloat()});
    std.debug.print("Spread: {} bps\n", .{ticker.spreadBps().toFloat()});

    // 6. 查询订单簿
    const orderbook = try exchange.getOrderbook(pair, 5);
    defer allocator.free(orderbook.bids);
    defer allocator.free(orderbook.asks);

    if (orderbook.getBestBid()) |bid| {
        std.debug.print("Best Bid: {}\n", .{bid.price.toFloat()});
    }

    // 7. 下限价单
    const order_request = OrderRequest{
        .pair = pair,
        .side = .buy,
        .order_type = .limit,
        .amount = try Decimal.fromString("0.1"),
        .price = try Decimal.fromString("2000.0"),
        .time_in_force = .gtc,
    };

    try order_request.validate();

    const order = try exchange.createOrder(order_request);
    std.debug.print("Order created: ID={}\n", .{order.exchange_order_id});

    // 8. 查询账户余额
    const balances = try exchange.getBalance();
    defer allocator.free(balances);

    for (balances) |balance| {
        std.debug.print("{s}: {}\n", .{
            balance.asset,
            balance.available.toFloat(),
        });
    }
}
```

---

### 示例 2: 错误处理

```zig
pub fn placeOrderWithRetry(
    exchange: IExchange,
    request: OrderRequest,
    logger: Logger,
) !Order {
    var retries: u8 = 0;
    const max_retries = 3;

    while (retries < max_retries) : (retries += 1) {
        const order = exchange.createOrder(request) catch |err| {
            switch (err) {
                error.NetworkError => {
                    logger.warn("Network error, retrying... ({}/{})", .{
                        retries + 1, max_retries,
                    });
                    std.time.sleep(std.time.ns_per_s * (retries + 1));
                    continue;
                },
                error.InsufficientBalance => {
                    logger.err("Insufficient balance", .{});
                    return err;
                },
                else => return err,
            }
        };

        return order;
    }

    return error.MaxRetriesExceeded;
}
```

---

### 示例 3: 批量操作

```zig
pub fn cancelAllOpenOrders(
    exchange: IExchange,
    logger: Logger,
) !void {
    // 方法 1: 使用 cancelAllOrders
    const cancelled = try exchange.cancelAllOrders(null);
    logger.info("Cancelled {} orders", .{cancelled});

    // 方法 2: 逐个撤销（精细控制）
    const positions = try exchange.getPositions();
    defer allocator.free(positions);

    for (positions) |pos| {
        const cancelled_count = try exchange.cancelAllOrders(pos.pair);
        logger.info("Cancelled {} orders for {s}-{s}", .{
            cancelled_count,
            pos.pair.base,
            pos.pair.quote,
        });
    }
}
```

---

## 参考资料

- **类型定义**: `/home/davirain/dev/zigQuant/src/exchange/types.zig`
- **接口定义**: `/home/davirain/dev/zigQuant/src/exchange/interface.zig`
- **Registry 实现**: `/home/davirain/dev/zigQuant/src/exchange/registry.zig`

---

*Last updated: 2025-12-23*
