# Exchange Router - 实现细节

> 深入了解 VTable 模式、符号映射、Connector 实现等内部细节

**最后更新**: 2025-12-23

---

## 架构概览

```
src/exchange/
├── interface.zig              # IExchange vtable 接口
├── types.zig                  # 统一数据类型
├── registry.zig               # ExchangeRegistry
├── symbol_mapper.zig          # SymbolMapper
│
└── hyperliquid/               # Hyperliquid 实现
    ├── connector.zig          # HyperliquidConnector
    ├── http.zig               # HTTP 客户端
    ├── websocket.zig          # WebSocket 客户端
    ├── auth.zig               # Ed25519 签名
    ├── info_api.zig           # Info API
    ├── exchange_api.zig       # Exchange API
    ├── types.zig              # Hyperliquid 类型
    └── rate_limiter.zig       # 速率限制
```

---

## Phase A: 核心类型系统

### 统一数据类型 (types.zig)

所有交易所必须将其原生格式转换为这些统一类型。

#### TradingPair - 交易对

```zig
pub const TradingPair = struct {
    base: []const u8,   // 基础货币: "BTC", "ETH"
    quote: []const u8,  // 计价货币: "USDT", "USDC"

    pub fn symbol(self: TradingPair, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s}-{s}", .{ self.base, self.quote });
    }

    pub fn fromSymbol(sym: []const u8) !TradingPair {
        if (std.mem.indexOf(u8, sym, "-")) |idx| {
            return .{
                .base = sym[0..idx],
                .quote = sym[idx + 1 ..],
            };
        }
        return error.InvalidSymbolFormat;
    }

    pub fn eql(self: TradingPair, other: TradingPair) bool {
        return std.mem.eql(u8, self.base, other.base) and
               std.mem.eql(u8, self.quote, other.quote);
    }
};
```

**设计要点**:
- 使用 `[]const u8` 而非 `[]u8`，避免意外修改
- 提供 `symbol()` 生成标准格式（BASE-QUOTE）
- 提供 `fromSymbol()` 解析多种格式（支持 `-` 和 `/` 分隔符）
- 提供 `eql()` 用于比较，避免字符串比较错误

**内存管理**:
- `symbol()` 分配新字符串，调用者负责释放
- `fromSymbol()` 返回指向原字符串的切片，无需释放

#### OrderRequest - 订单请求

```zig
pub const OrderRequest = struct {
    pair: TradingPair,
    side: Side,              // buy/sell
    order_type: OrderType,   // limit/market
    amount: Decimal,
    price: ?Decimal = null,
    time_in_force: TimeInForce = .gtc,
    reduce_only: bool = false,
    client_order_id: ?[]const u8 = null,

    pub fn validate(self: OrderRequest) !void {
        if (!self.amount.isPositive()) {
            return error.InvalidAmount;
        }

        if (self.order_type == .limit and self.price == null) {
            return error.LimitOrderRequiresPrice;
        }

        if (self.order_type == .market and self.price != null) {
            return error.MarketOrderShouldNotHavePrice;
        }

        if (self.price) |p| {
            if (!p.isPositive()) {
                return error.InvalidPrice;
            }
        }
    }
};
```

**验证逻辑**:
1. 数量必须为正数
2. 限价单必须有价格
3. 市价单不应有价格
4. 价格（如果提供）必须为正数

#### Order - 订单响应

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

    pub fn remainingAmount(self: Order) Decimal {
        return self.amount.sub(self.filled_amount) catch Decimal.ZERO;
    }

    pub fn isComplete(self: Order) bool {
        return self.status == .filled or
               self.status == .cancelled or
               self.status == .rejected;
    }

    pub fn isActive(self: Order) bool {
        return self.status == .open or
               self.status == .partially_filled;
    }
};
```

**辅助方法**:
- `remainingAmount()`: 计算剩余未成交数量
- `isComplete()`: 判断订单是否终结
- `isActive()`: 判断订单是否活跃

---

## Phase B: 接口抽象层

### VTable 模式实现 (interface.zig)

VTable 是 Zig 中实现多态的标准模式，类似于 C++ 的虚函数表。

#### IExchange 接口定义

```zig
pub const IExchange = struct {
    ptr: *anyopaque,        // 指向具体实现的指针
    vtable: *const VTable,  // 函数表（编译时常量）

    pub const VTable = struct {
        // 连接管理
        getName: *const fn (*anyopaque) []const u8,
        connect: *const fn (*anyopaque) anyerror!void,
        disconnect: *const fn (*anyopaque) void,
        isConnected: *const fn (*anyopaque) bool,

        // 市场数据
        getTicker: *const fn (*anyopaque, TradingPair) anyerror!Ticker,
        getOrderbook: *const fn (*anyopaque, TradingPair, u32) anyerror!Orderbook,

        // 交易操作
        createOrder: *const fn (*anyopaque, OrderRequest) anyerror!Order,
        cancelOrder: *const fn (*anyopaque, u64) anyerror!void,
        cancelAllOrders: *const fn (*anyopaque, ?TradingPair) anyerror!u32,
        getOrder: *const fn (*anyopaque, u64) anyerror!Order,

        // 账户查询
        getBalance: *const fn (*anyopaque) anyerror![]Balance,
        getPositions: *const fn (*anyopaque) anyerror![]Position,
    };

    // 代理方法
    pub fn getName(self: IExchange) []const u8 {
        return self.vtable.getName(self.ptr);
    }

    pub fn connect(self: IExchange) !void {
        return self.vtable.connect(self.ptr);
    }

    pub fn getTicker(self: IExchange, pair: TradingPair) !Ticker {
        return self.vtable.getTicker(self.ptr, pair);
    }

    pub fn createOrder(self: IExchange, request: OrderRequest) !Order {
        return self.vtable.createOrder(self.ptr, request);
    }

    // ... 其他代理方法
};
```

**设计要点**:
1. **ptr**: 使用 `*anyopaque` 类型擦除，可以指向任何具体实现
2. **vtable**: 使用 `*const` 确保函数表不可变（编译时优化）
3. **代理方法**: 提供类型安全的包装，调用 vtable 中的函数指针
4. **错误处理**: 使用 `anyerror` 允许各实现返回不同错误类型

**性能特性**:
- VTable 调用是直接函数指针调用，开销 < 1ns
- 编译器可以内联代理方法
- 无运行时类型信息（RTTI）开销

---

## Phase C: Hyperliquid Connector 实现

### Connector 结构 (connector.zig)

```zig
pub const HyperliquidConnector = struct {
    allocator: std.mem.Allocator,
    config: ExchangeConfig,
    logger: Logger,
    connected: bool,
    // TODO Phase D: Add HTTP and WebSocket clients
    // http: HyperliquidClient,
    // ws: ?WebSocketClient,

    pub fn create(
        allocator: std.mem.Allocator,
        config: ExchangeConfig,
        logger: Logger,
    ) !*HyperliquidConnector {
        const self = try allocator.create(HyperliquidConnector);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .logger = logger,
            .connected = false,
        };

        return self;
    }

    pub fn destroy(self: *HyperliquidConnector) void {
        if (self.connected) {
            disconnect(self);
        }
        self.allocator.destroy(self);
    }

    pub fn interface(self: *HyperliquidConnector) IExchange {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    // VTable 常量（编译时初始化）
    const vtable = IExchange.VTable{
        .getName = getName,
        .connect = connect,
        .disconnect = disconnect,
        .isConnected = isConnected,
        .getTicker = getTicker,
        .getOrderbook = getOrderbook,
        .createOrder = createOrder,
        .cancelOrder = cancelOrder,
        .cancelAllOrders = cancelAllOrders,
        .getOrder = getOrder,
        .getBalance = getBalance,
        .getPositions = getPositions,
    };

    // VTable 实现函数
    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "hyperliquid";
    }

    fn connect(ptr: *anyopaque) !void {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));
        self.logger.info("Connecting to Hyperliquid...", .{});

        // 测试连接：获取 meta 信息
        _ = try InfoAPI.getMeta(&self.http);

        self.connected = true;
        self.logger.info("Connected to Hyperliquid successfully", .{});
    }

    fn getTicker(ptr: *anyopaque, pair: TradingPair) !Ticker {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        // 1. 转换符号: ETH-USDC → "ETH"
        const symbol = try symbol_mapper.toHyperliquid(pair);

        // TODO Phase D: 调用 Info API
        // const mids = try InfoAPI.getAllMids(&self.http);
        // defer mids.deinit();
        //
        // const mid_price = mids.get(symbol) orelse return error.SymbolNotFound;
        //
        // return Ticker{
        //     .pair = pair,
        //     .bid = mid_price,
        //     .ask = mid_price,
        //     .last = mid_price,
        //     .volume_24h = Decimal.ZERO,
        //     .timestamp = Timestamp.now(),
        // };

        return error.NotImplemented;
    }

    // ... 其他方法实现
};
```

**关键实现细节**:

1. **类型转换**: `@ptrCast(@alignCast(ptr))` 将 `*anyopaque` 转回具体类型
2. **错误处理**: 直接返回错误，由调用者处理
3. **日志记录**: 记录所有重要操作
4. **符号映射**: 使用 SymbolMapper 转换交易对格式

---

### 符号映射器 (symbol_mapper.zig)

```zig
pub const SymbolMapper = struct {
    /// 转换为 Hyperliquid 格式: ETH-USDC → "ETH"
    pub fn toHyperliquid(pair: TradingPair) ![]const u8 {
        // Hyperliquid 永续合约只使用 base 币种
        // 所有合约都是 USDC 结算
        if (!std.mem.eql(u8, pair.quote, "USDC")) {
            return error.InvalidQuoteAsset;
        }

        return pair.base;
    }

    /// 从 Hyperliquid 格式转换: "ETH" → ETH-USDC
    pub fn fromHyperliquid(symbol: []const u8) TradingPair {
        return TradingPair{
            .base = symbol,
            .quote = "USDC",
        };
    }
};
```

**复杂度**: O(1)
**说明**: Hyperliquid 的符号映射非常简单，未来可扩展为 HashMap 缓存

**未来扩展** (Binance):
```zig
pub fn toBinance(self: SymbolMapper, pair: TradingPair) ![]const u8 {
    // ETH-USDT → "ETHUSDT"
    return try std.fmt.allocPrint(
        self.allocator,
        "{s}{s}",
        .{ pair.base, pair.quote }
    );
}
```

---

### 数据流示例

#### 查询行情完整流程

```
1. CLI 调用
   ↓
   const pair = TradingPair{ .base = "ETH", .quote = "USDC" };
   const ticker = try exchange.getTicker(pair);

2. IExchange 代理方法
   ↓
   pub fn getTicker(self: IExchange, pair: TradingPair) !Ticker {
       return self.vtable.getTicker(self.ptr, pair);
   }

3. HyperliquidConnector.getTicker
   ↓
   fn getTicker(ptr: *anyopaque, pair: TradingPair) !Ticker {
       const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

4. SymbolMapper 转换
   ↓
   const symbol = try symbol_mapper.toHyperliquid(pair);
   // "ETH-USDC" → "ETH"

5. InfoAPI.getAllMids
   ↓
   const mids = try InfoAPI.getAllMids(&self.http);
   // POST /info {"type": "allMids"}

6. Hyperliquid API 响应
   ↓
   {"ETH": "2145.5", "BTC": "45123.0", ...}

7. 构造 Ticker
   ↓
   return Ticker{
       .pair = pair,
       .bid = mid_price,
       .ask = mid_price,
       .last = mid_price,
       .volume_24h = Decimal.ZERO,
       .timestamp = Timestamp.now(),
   };

8. 返回到 CLI
   ↓
   std.debug.print("ETH Price: {}\n", .{ticker.last.toFloat()});
```

#### 下单完整流程

```
1. CLI 提交订单
   ↓
   const request = OrderRequest{
       .pair = .{ .base = "ETH", .quote = "USDC" },
       .side = .buy,
       .order_type = .limit,
       .amount = try Decimal.fromString("0.1"),
       .price = try Decimal.fromString("2000.0"),
       .time_in_force = .gtc,
   };

2. 验证请求
   ↓
   try request.validate();

3. IExchange.createOrder
   ↓
   const order = try exchange.createOrder(request);

4. HyperliquidConnector.createOrder
   ↓
   fn createOrder(ptr: *anyopaque, request: OrderRequest) !Order {
       const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

5. 转换为 Hyperliquid 格式
   ↓
   const symbol = try symbol_mapper.toHyperliquid(request.pair);
   const hl_order = HyperliquidOrderRequest{
       .coin = symbol,
       .is_buy = request.side == .buy,
       .sz = request.amount,
       .limit_px = request.price.?,
       .order_type = .{
           .limit = .{ .tif = "Gtc" },
       },
       .reduce_only = request.reduce_only,
   };

6. ExchangeAPI.placeOrder
   ↓
   const response = try ExchangeAPI.placeOrder(&self.http, hl_order);
   // POST /exchange (签名后)

7. 解析响应并转换
   ↓
   return Order{
       .exchange_order_id = response.data.statuses[0].resting.oid,
       .pair = request.pair,
       .side = request.side,
       .order_type = request.order_type,
       .status = .open,
       .amount = request.amount,
       .price = request.price,
       .filled_amount = Decimal.ZERO,
       .created_at = Timestamp.now(),
       .updated_at = Timestamp.now(),
   };

8. 返回到 CLI
   ↓
   std.debug.print("Order placed: ID={}\n", .{order.exchange_order_id});
```

---

## Phase D: Registry 实现

### ExchangeRegistry (registry.zig)

```zig
pub const ExchangeRegistry = struct {
    allocator: std.mem.Allocator,
    exchange: ?IExchange,        // MVP: 单交易所
    config: ?ExchangeConfig,
    logger: Logger,

    pub fn init(allocator: std.mem.Allocator, logger: Logger) ExchangeRegistry {
        return .{
            .allocator = allocator,
            .exchange = null,
            .config = null,
            .logger = logger,
        };
    }

    pub fn setExchange(
        self: *ExchangeRegistry,
        exchange: IExchange,
        config: ExchangeConfig,
    ) !void {
        if (self.exchange != null) {
            self.logger.warn("Replacing existing exchange", .{});
        }

        self.exchange = exchange;
        self.config = config;

        self.logger.info("Exchange registered: {s}", .{exchange.getName()});
    }

    pub fn getExchange(self: *ExchangeRegistry) !IExchange {
        return self.exchange orelse error.NoExchangeRegistered;
    }

    pub fn connectAll(self: *ExchangeRegistry) !void {
        const exchange = try self.getExchange();

        self.logger.info("Connecting to exchange: {s}", .{exchange.getName()});
        try exchange.connect();
        self.logger.info("All exchanges connected", .{});
    }

    pub fn isConnected(self: *ExchangeRegistry) bool {
        const exchange = self.exchange orelse return false;
        return exchange.isConnected();
    }

    pub fn deinit(self: *ExchangeRegistry) void {
        if (self.exchange) |exchange| {
            exchange.disconnect();
        }
    }
};
```

**复杂度**:
- `setExchange`: O(1)
- `getExchange`: O(1)
- `connectAll`: O(1) （MVP 单交易所）

**未来扩展** (v0.3):
```zig
pub const ExchangeRegistry = struct {
    exchanges: std.StringHashMap(IExchange),

    pub fn addExchange(self: *ExchangeRegistry, name: []const u8, exchange: IExchange) !void {
        try self.exchanges.put(name, exchange);
    }

    pub fn getExchange(self: *ExchangeRegistry, name: []const u8) ?IExchange {
        return self.exchanges.get(name);
    }
};
```

---

## 内存管理

### Connector 内存

```zig
// 创建
const connector = try HyperliquidConnector.create(allocator, config, logger);
defer connector.destroy();

// 使用接口
const exchange = connector.interface();

// 释放（通过 destroy）
pub fn destroy(self: *HyperliquidConnector) void {
    if (self.connected) {
        disconnect(self);
    }
    // TODO Phase D: cleanup HTTP client
    // self.http.deinit();
    self.allocator.destroy(self);
}
```

### 订单数据

```zig
// Ticker (栈分配，无需释放)
return Ticker{ ... };

// Orderbook (需要释放 levels)
const orderbook = try exchange.getOrderbook(pair, 10);
defer allocator.free(orderbook.bids);
defer allocator.free(orderbook.asks);
```

### 字符串处理

```zig
// symbol() 分配新字符串
const sym = try pair.symbol(allocator);
defer allocator.free(sym);

// fromSymbol() 返回切片，无需释放
const pair = try TradingPair.fromSymbol("ETH-USDC");
```

---

## 错误处理策略

### 错误分类

```zig
pub const ExchangeError = error{
    // 连接错误
    NoExchangeRegistered,
    NotConnected,
    ConnectionFailed,

    // 交易错误
    InvalidOrderRequest,
    OrderRejected,
    InsufficientBalance,
    SymbolNotFound,

    // 数据错误
    InvalidSymbolFormat,
    InvalidQuoteAsset,
    ParseError,
};
```

### 错误传播

```zig
// Connector 方法直接返回错误
fn getTicker(ptr: *anyopaque, pair: TradingPair) !Ticker {
    const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

    const symbol = try symbol_mapper.toHyperliquid(pair);
    // TODO Phase D: Call API
    // const mids = try InfoAPI.getAllMids(&self.http);
    // 错误自动传播
}

// 上层处理错误
const ticker = exchange.getTicker(pair) catch |err| {
    logger.err("Failed to get ticker: {}", .{err});
    return err;
};
```

---

## 性能优化

### 1. 栈分配优先

```zig
// 使用栈缓冲区
var buffer: [256]u8 = undefined;
const msg = try std.fmt.bufPrint(&buffer, "{s}-{s}", .{base, quote});
```

### 2. 避免重复转换

```zig
// 缓存符号映射结果（未来优化）
const cached_symbol = symbol_cache.get(pair) orelse {
    const symbol = try mapper.toHyperliquid(pair);
    try symbol_cache.put(pair, symbol);
    return symbol;
};
```

### 3. VTable 调用优化

```zig
// 编译器自动内联代理方法
pub inline fn getTicker(self: IExchange, pair: TradingPair) !Ticker {
    return self.vtable.getTicker(self.ptr, pair);
}
```

---

## 线程安全

### Registry 线程安全（未来）

```zig
pub const ExchangeRegistry = struct {
    exchanges: std.StringHashMap(IExchange),
    mutex: std.Thread.Mutex,

    pub fn getExchange(self: *ExchangeRegistry, name: []const u8) ?IExchange {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.exchanges.get(name);
    }
};
```

### Connector 线程安全

- HTTP 客户端使用连接池（std.http.Client 线程安全）
- 速率限制器使用原子操作

---

## 参考实现

- **完整类型定义**: `/home/davirain/dev/zigQuant/src/exchange/types.zig`
- **接口定义**: `/home/davirain/dev/zigQuant/src/exchange/interface.zig`
- **Registry 实现**: `/home/davirain/dev/zigQuant/src/exchange/registry.zig`
- **Connector 实现**: `/home/davirain/dev/zigQuant/src/exchange/hyperliquid/connector.zig`

---

*Last updated: 2025-12-23*
