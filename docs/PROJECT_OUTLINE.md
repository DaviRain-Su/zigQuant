# ZigQuant - Zig 量化交易机器人框架

> 基于 Zig 语言重新实现 Hummingbot + Freqtrade 的核心功能

## 📋 项目愿景

构建一个高性能、低延迟、内存安全的量化交易框架，结合 Hummingbot 的做市/套利能力和 Freqtrade 的策略回测/自动交易能力。

---

## 🎯 项目阶段总览

```
Phase 0: 基础设施 (Foundation)
    ↓
Phase 1: MVP - 最小可行产品
    ↓
Phase 2: 核心交易引擎
    ↓
Phase 3: 策略框架
    ↓
Phase 4: 回测系统
    ↓
Phase 5: 做市与套利
    ↓
Phase 6: 生产级功能
    ↓
Phase 7: 高级特性
```

---

# Phase 0: 基础设施 (2-3 周)

## 0.1 项目结构设计

```
zigquant/
├── build.zig                 # 构建配置
├── build.zig.zon            # 依赖管理
├── src/
│   ├── main.zig             # 入口点
│   ├── core/                # 核心模块
│   │   ├── types.zig        # 基础类型定义
│   │   ├── decimal.zig      # 高精度十进制数
│   │   ├── time.zig         # 时间处理
│   │   └── errors.zig       # 错误类型
│   ├── exchange/            # 交易所连接器
│   │   ├── connector.zig    # 连接器接口
│   │   ├── binance/         # Binance 实现
│   │   ├── okx/             # OKX 实现
│   │   └── mock/            # 模拟交易所
│   ├── market/              # 市场数据
│   │   ├── orderbook.zig    # 订单簿
│   │   ├── ticker.zig       # 行情数据
│   │   ├── kline.zig        # K线数据
│   │   └── trade.zig        # 成交数据
│   ├── order/               # 订单管理
│   │   ├── order.zig        # 订单类型
│   │   ├── manager.zig      # 订单管理器
│   │   └── tracker.zig      # 订单跟踪
│   ├── strategy/            # 策略框架
│   │   ├── base.zig         # 策略基类
│   │   ├── signal.zig       # 信号系统
│   │   └── builtin/         # 内置策略
│   ├── backtest/            # 回测引擎
│   │   ├── engine.zig       # 回测引擎
│   │   ├── data_feed.zig    # 数据源
│   │   └── metrics.zig      # 性能指标
│   ├── risk/                # 风险管理
│   │   ├── manager.zig      # 风险管理器
│   │   └── limits.zig       # 限制规则
│   ├── network/             # 网络层
│   │   ├── http.zig         # HTTP 客户端
│   │   ├── websocket.zig    # WebSocket 客户端
│   │   └── rate_limit.zig   # 限流器
│   ├── storage/             # 数据存储
│   │   ├── sqlite.zig       # SQLite 封装
│   │   └── csv.zig          # CSV 处理
│   ├── ui/                  # 用户界面
│   │   └── cli.zig          # 命令行界面
│   └── utils/               # 工具函数
│       ├── logger.zig       # 日志系统
│       ├── config.zig       # 配置管理
│       └── crypto.zig       # 加密工具
├── strategies/              # 用户策略目录
├── data/                    # 数据目录
├── config/                  # 配置文件
├── tests/                   # 测试
└── docs/                    # 文档
```

## 0.2 核心类型定义

```zig
// src/core/types.zig

/// 交易对
pub const TradingPair = struct {
    base: []const u8,      // 基础货币 (BTC)
    quote: []const u8,     // 计价货币 (USDT)
    
    pub fn symbol(self: TradingPair) []const u8 {
        // 返回 "BTC/USDT" 或 "BTCUSDT"
    }
};

/// 订单方向
pub const Side = enum {
    buy,
    sell,
};

/// 订单类型
pub const OrderType = enum {
    market,
    limit,
    stop_loss,
    stop_loss_limit,
    take_profit,
    take_profit_limit,
};

/// 订单状态
pub const OrderStatus = enum {
    pending,
    open,
    partially_filled,
    filled,
    cancelled,
    rejected,
    expired,
};

/// 时间周期
pub const Timeframe = enum {
    m1,   // 1分钟
    m5,   // 5分钟
    m15,  // 15分钟
    m30,  // 30分钟
    h1,   // 1小时
    h4,   // 4小时
    d1,   // 1天
    w1,   // 1周
    
    pub fn toMillis(self: Timeframe) u64 {
        return switch (self) {
            .m1 => 60_000,
            .m5 => 300_000,
            // ...
        };
    }
};
```

## 0.3 高精度十进制数

```zig
// src/core/decimal.zig
// 金融计算必须使用高精度，避免浮点数误差

pub const Decimal = struct {
    value: i128,           // 内部值
    scale: u8,             // 小数位数 (通常 8-18)
    
    pub const SCALE: u8 = 18;
    pub const ONE: Decimal = .{ .value = 1_000_000_000_000_000_000, .scale = 18 };
    pub const ZERO: Decimal = .{ .value = 0, .scale = 18 };
    
    pub fn fromFloat(f: f64) Decimal { ... }
    pub fn fromString(s: []const u8) !Decimal { ... }
    pub fn toFloat(self: Decimal) f64 { ... }
    
    pub fn add(self: Decimal, other: Decimal) Decimal { ... }
    pub fn sub(self: Decimal, other: Decimal) Decimal { ... }
    pub fn mul(self: Decimal, other: Decimal) Decimal { ... }
    pub fn div(self: Decimal, other: Decimal) !Decimal { ... }
    
    pub fn cmp(self: Decimal, other: Decimal) std.math.Order { ... }
    pub fn isPositive(self: Decimal) bool { ... }
    pub fn isNegative(self: Decimal) bool { ... }
    pub fn abs(self: Decimal) Decimal { ... }
    
    pub fn format(...) { ... }  // 格式化输出
};
```

## 0.4 依赖项

```zig
// build.zig.zon
.{
    .name = "zigquant",
    .version = "0.1.0",
    .dependencies = .{
        // HTTP/WebSocket
        .zap = .{ ... },           // HTTP server/client
        .websocket = .{ ... },     // WebSocket
        
        // 数据处理
        .zig_json = .{ ... },      // JSON 解析
        .sqlite = .{ ... },        // SQLite 绑定
        
        // 加密
        .zig_crypto = .{ ... },    // HMAC-SHA256 等
        
    },
}
```

---

# Phase 1: MVP - 最小可行产品 (3-4 周)

## 1.1 MVP 目标

> **能够连接一个交易所，获取行情，执行一次买卖操作**

### 核心功能清单

- [ ] 连接 Binance 获取 BTC/USDT 实时价格
- [ ] 显示简单的订单簿
- [ ] 手动下单（市价单）
- [ ] 查询账户余额
- [ ] 查询订单状态
- [ ] 基础日志输出

## 1.2 交易所连接器接口

```zig
// src/exchange/connector.zig

pub const ExchangeConnector = struct {
    ptr: *anyopaque,
    vtable: *const VTable,
    
    pub const VTable = struct {
        // 市场数据
        getTicker: *const fn(*anyopaque, TradingPair) anyerror!Ticker,
        getOrderbook: *const fn(*anyopaque, TradingPair, u32) anyerror!Orderbook,
        getKlines: *const fn(*anyopaque, TradingPair, Timeframe, u32) anyerror![]Kline,
        
        // 账户
        getBalance: *const fn(*anyopaque) anyerror!Balance,
        
        // 订单
        createOrder: *const fn(*anyopaque, OrderRequest) anyerror!Order,
        cancelOrder: *const fn(*anyopaque, []const u8) anyerror!void,
        getOrder: *const fn(*anyopaque, []const u8) anyerror!Order,
        getOpenOrders: *const fn(*anyopaque, ?TradingPair) anyerror![]Order,
        
        // WebSocket
        subscribeOrderbook: *const fn(*anyopaque, TradingPair, OrderbookCallback) anyerror!void,
        subscribeTrades: *const fn(*anyopaque, TradingPair, TradeCallback) anyerror!void,
        subscribeUserData: *const fn(*anyopaque, UserDataCallback) anyerror!void,
    };
    
    // 代理方法
    pub fn getTicker(self: ExchangeConnector, pair: TradingPair) !Ticker {
        return self.vtable.getTicker(self.ptr, pair);
    }
    // ... 其他方法
};
```

## 1.3 Binance 连接器实现

```zig
// src/exchange/binance/connector.zig

pub const BinanceConnector = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    api_secret: []const u8,
    base_url: []const u8 = "https://api.binance.com",
    ws_url: []const u8 = "wss://stream.binance.com:9443/ws",
    
    http_client: HttpClient,
    ws_client: ?WebSocketClient,
    rate_limiter: RateLimiter,
    
    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, api_secret: []const u8) !BinanceConnector {
        return .{
            .allocator = allocator,
            .api_key = api_key,
            .api_secret = api_secret,
            .http_client = try HttpClient.init(allocator),
            .ws_client = null,
            .rate_limiter = RateLimiter.init(1200, 60_000), // 1200 requests/min
        };
    }
    
    pub fn connector(self: *BinanceConnector) ExchangeConnector {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }
    
    // --- 实现方法 ---
    
    fn getTicker(ptr: *anyopaque, pair: TradingPair) !Ticker {
        const self: *BinanceConnector = @ptrCast(@alignCast(ptr));
        
        const symbol = try pairToSymbol(pair);  // "BTCUSDT"
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/v3/ticker/price?symbol={s}",
            .{ self.base_url, symbol }
        );
        defer self.allocator.free(url);
        
        try self.rate_limiter.acquire();
        const response = try self.http_client.get(url);
        
        // 解析 JSON 响应
        const parsed = try std.json.parseFromSlice(TickerResponse, self.allocator, response, .{});
        defer parsed.deinit();
        
        return Ticker{
            .pair = pair,
            .price = try Decimal.fromString(parsed.value.price),
            .timestamp = std.time.milliTimestamp(),
        };
    }
    
    fn createOrder(ptr: *anyopaque, request: OrderRequest) !Order {
        const self: *BinanceConnector = @ptrCast(@alignCast(ptr));
        
        // 构建签名请求
        var params = std.StringHashMap([]const u8).init(self.allocator);
        try params.put("symbol", try pairToSymbol(request.pair));
        try params.put("side", if (request.side == .buy) "BUY" else "SELL");
        try params.put("type", orderTypeToString(request.order_type));
        try params.put("quantity", try request.amount.toString(self.allocator));
        
        if (request.price) |price| {
            try params.put("price", try price.toString(self.allocator));
            try params.put("timeInForce", "GTC");
        }
        
        const timestamp = std.time.milliTimestamp();
        try params.put("timestamp", try std.fmt.allocPrint(self.allocator, "{d}", .{timestamp}));
        
        // 签名
        const query_string = try buildQueryString(self.allocator, params);
        const signature = try hmacSha256(self.api_secret, query_string);
        
        // 发送请求
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/v3/order?{s}&signature={s}",
            .{ self.base_url, query_string, signature }
        );
        
        try self.rate_limiter.acquire();
        const response = try self.http_client.post(url, null, .{
            .{ "X-MBX-APIKEY", self.api_key },
        });
        
        // 解析响应并返回 Order
        // ...
    }
    
    const vtable = ExchangeConnector.VTable{
        .getTicker = getTicker,
        .getOrderbook = getOrderbook,
        .getKlines = getKlines,
        .getBalance = getBalance,
        .createOrder = createOrder,
        .cancelOrder = cancelOrder,
        .getOrder = getOrder,
        .getOpenOrders = getOpenOrders,
        .subscribeOrderbook = subscribeOrderbook,
        .subscribeTrades = subscribeTrades,
        .subscribeUserData = subscribeUserData,
    };
};
```

## 1.4 MVP 主程序

```zig
// src/main.zig (MVP 版本)

const std = @import("std");
const BinanceConnector = @import("exchange/binance/connector.zig").BinanceConnector;
const Config = @import("utils/config.zig").Config;
const Logger = @import("utils/logger.zig").Logger;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 加载配置
    const config = try Config.load(allocator, "config/config.json");
    defer config.deinit();
    
    // 初始化日志
    var logger = try Logger.init(allocator, .info);
    defer logger.deinit();
    
    logger.info("ZigQuant MVP Starting...", .{});
    
    // 初始化交易所连接器
    var binance = try BinanceConnector.init(
        allocator,
        config.binance.api_key,
        config.binance.api_secret,
    );
    defer binance.deinit();
    
    const exchange = binance.connector();
    
    // 获取行情
    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
    const ticker = try exchange.getTicker(pair);
    logger.info("BTC/USDT Price: {d}", .{ticker.price.toFloat()});
    
    // 获取账户余额
    const balance = try exchange.getBalance();
    logger.info("USDT Balance: {d}", .{balance.get("USDT").?.free.toFloat()});
    
    // 简单的命令行交互
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    
    while (true) {
        try stdout.print("\n[Commands: price, balance, buy <amount>, sell <amount>, quit]\n> ", .{});
        
        const line = try stdin.readUntilDelimiterAlloc(allocator, '\n', 1024);
        defer allocator.free(line);
        
        var iter = std.mem.splitScalar(u8, line, ' ');
        const cmd = iter.first();
        
        if (std.mem.eql(u8, cmd, "quit")) {
            break;
        } else if (std.mem.eql(u8, cmd, "price")) {
            const t = try exchange.getTicker(pair);
            try stdout.print("BTC/USDT: {d}\n", .{t.price.toFloat()});
        } else if (std.mem.eql(u8, cmd, "balance")) {
            const b = try exchange.getBalance();
            try stdout.print("USDT: {d}, BTC: {d}\n", .{
                b.get("USDT").?.free.toFloat(),
                b.get("BTC").?.free.toFloat(),
            });
        } else if (std.mem.eql(u8, cmd, "buy")) {
            if (iter.next()) |amount_str| {
                const amount = try Decimal.fromString(amount_str);
                const order = try exchange.createOrder(.{
                    .pair = pair,
                    .side = .buy,
                    .order_type = .market,
                    .amount = amount,
                    .price = null,
                });
                try stdout.print("Order created: {s}\n", .{order.id});
            }
        }
        // ... 更多命令
    }
    
    logger.info("ZigQuant MVP Shutdown.", .{});
}
```

---

# Phase 2: 核心交易引擎 (4-5 周)

## 2.1 目标

- [ ] 完整的订单生命周期管理
- [ ] WebSocket 实时数据流
- [ ] 本地订单簿维护
- [ ] 多交易对支持
- [ ] 事件驱动架构

## 2.2 事件系统

```zig
// src/core/event.zig

pub const EventType = enum {
    // 市场事件
    ticker_update,
    orderbook_update,
    trade_update,
    kline_update,
    
    // 订单事件
    order_created,
    order_filled,
    order_partially_filled,
    order_cancelled,
    order_rejected,
    
    // 系统事件
    connected,
    disconnected,
    error,
};

pub const Event = struct {
    type: EventType,
    timestamp: i64,
    data: EventData,
    
    pub const EventData = union(EventType) {
        ticker_update: Ticker,
        orderbook_update: OrderbookUpdate,
        trade_update: Trade,
        kline_update: Kline,
        order_created: Order,
        order_filled: OrderFill,
        // ...
    };
};

pub const EventBus = struct {
    allocator: std.mem.Allocator,
    subscribers: std.AutoHashMap(EventType, std.ArrayList(Subscriber)),
    event_queue: std.fifo(Event),
    mutex: std.Thread.Mutex,
    
    pub const Subscriber = struct {
        callback: *const fn(Event) void,
        filter: ?EventFilter,
    };
    
    pub fn subscribe(self: *EventBus, event_type: EventType, callback: *const fn(Event) void) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const list = try self.subscribers.getOrPut(event_type);
        if (!list.found_existing) {
            list.value_ptr.* = std.ArrayList(Subscriber).init(self.allocator);
        }
        try list.value_ptr.append(.{ .callback = callback, .filter = null });
    }
    
    pub fn publish(self: *EventBus, event: Event) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.subscribers.get(event.type)) |subs| {
            for (subs.items) |sub| {
                sub.callback(event);
            }
        }
    }
    
    pub fn publishAsync(self: *EventBus, event: Event) !void {
        try self.event_queue.writeItem(event);
    }
};
```

## 2.3 订单管理器

```zig
// src/order/manager.zig

pub const OrderManager = struct {
    allocator: std.mem.Allocator,
    exchange: ExchangeConnector,
    event_bus: *EventBus,
    
    // 订单存储
    orders: std.StringHashMap(Order),
    open_orders: std.ArrayList([]const u8),
    
    // 订单统计
    stats: OrderStats,
    
    pub const OrderStats = struct {
        total_orders: u64 = 0,
        filled_orders: u64 = 0,
        cancelled_orders: u64 = 0,
        total_volume: Decimal = Decimal.ZERO,
        total_fees: Decimal = Decimal.ZERO,
    };
    
    pub fn init(allocator: std.mem.Allocator, exchange: ExchangeConnector, event_bus: *EventBus) OrderManager {
        return .{
            .allocator = allocator,
            .exchange = exchange,
            .event_bus = event_bus,
            .orders = std.StringHashMap(Order).init(allocator),
            .open_orders = std.ArrayList([]const u8).init(allocator),
            .stats = .{},
        };
    }
    
    pub fn submitOrder(self: *OrderManager, request: OrderRequest) !Order {
        // 1. 验证订单
        try self.validateOrder(request);
        
        // 2. 发送到交易所
        const order = try self.exchange.createOrder(request);
        
        // 3. 本地存储
        try self.orders.put(order.id, order);
        if (order.status == .open) {
            try self.open_orders.append(order.id);
        }
        
        // 4. 发布事件
        self.event_bus.publish(.{
            .type = .order_created,
            .timestamp = std.time.milliTimestamp(),
            .data = .{ .order_created = order },
        });
        
        // 5. 更新统计
        self.stats.total_orders += 1;
        
        return order;
    }
    
    pub fn cancelOrder(self: *OrderManager, order_id: []const u8) !void {
        try self.exchange.cancelOrder(order_id);
        
        if (self.orders.getPtr(order_id)) |order| {
            order.status = .cancelled;
            self.stats.cancelled_orders += 1;
            
            // 从 open_orders 中移除
            // ...
            
            self.event_bus.publish(.{
                .type = .order_cancelled,
                .timestamp = std.time.milliTimestamp(),
                .data = .{ .order_cancelled = order.* },
            });
        }
    }
    
    pub fn syncOrders(self: *OrderManager) !void {
        // 从交易所同步订单状态
        const exchange_orders = try self.exchange.getOpenOrders(null);
        
        for (exchange_orders) |ex_order| {
            if (self.orders.getPtr(ex_order.id)) |local_order| {
                if (local_order.status != ex_order.status) {
                    local_order.* = ex_order;
                    // 发布状态更新事件
                }
            }
        }
    }
    
    fn validateOrder(self: *OrderManager, request: OrderRequest) !void {
        // 检查最小下单量
        // 检查价格精度
        // 检查余额
        // ...
    }
};
```

## 2.4 本地订单簿

```zig
// src/market/orderbook.zig

pub const Orderbook = struct {
    pair: TradingPair,
    bids: PriceLevel,        // 买单（从高到低）
    asks: PriceLevel,        // 卖单（从低到高）
    last_update_id: u64,
    timestamp: i64,
    
    pub const PriceLevel = struct {
        price: Decimal,
        quantity: Decimal,
    };
    
    // 使用红黑树保持排序
    bids_tree: std.Treap(PriceLevel, compareBidsDesc),
    asks_tree: std.Treap(PriceLevel, compareAsksAsc),
    
    pub fn init(allocator: std.mem.Allocator, pair: TradingPair) Orderbook {
        return .{
            .pair = pair,
            .bids_tree = std.Treap(PriceLevel, compareBidsDesc).init(allocator),
            .asks_tree = std.Treap(PriceLevel, compareAsksAsc).init(allocator),
            .last_update_id = 0,
            .timestamp = 0,
        };
    }
    
    pub fn update(self: *Orderbook, update: OrderbookUpdate) !void {
        // 检查更新序列号
        if (update.last_update_id <= self.last_update_id) {
            return; // 跳过旧更新
        }
        
        // 更新买单
        for (update.bids) |bid| {
            if (bid.quantity.isZero()) {
                _ = self.bids_tree.delete(bid.price);
            } else {
                try self.bids_tree.insert(.{ .price = bid.price, .quantity = bid.quantity });
            }
        }
        
        // 更新卖单
        for (update.asks) |ask| {
            if (ask.quantity.isZero()) {
                _ = self.asks_tree.delete(ask.price);
            } else {
                try self.asks_tree.insert(.{ .price = ask.price, .quantity = ask.quantity });
            }
        }
        
        self.last_update_id = update.last_update_id;
        self.timestamp = update.timestamp;
    }
    
    pub fn getBestBid(self: *const Orderbook) ?PriceLevel {
        return self.bids_tree.first();
    }
    
    pub fn getBestAsk(self: *const Orderbook) ?PriceLevel {
        return self.asks_tree.first();
    }
    
    pub fn getSpread(self: *const Orderbook) ?Decimal {
        const bid = self.getBestBid() orelse return null;
        const ask = self.getBestAsk() orelse return null;
        return ask.price.sub(bid.price);
    }
    
    pub fn getMidPrice(self: *const Orderbook) ?Decimal {
        const bid = self.getBestBid() orelse return null;
        const ask = self.getBestAsk() orelse return null;
        return bid.price.add(ask.price).div(Decimal.fromInt(2));
    }
    
    pub fn getDepth(self: *const Orderbook, levels: u32) struct { bids: []PriceLevel, asks: []PriceLevel } {
        // 返回指定层数的订单簿深度
    }
};
```

## 2.5 WebSocket 数据流

```zig
// src/exchange/binance/websocket.zig

pub const BinanceWebSocket = struct {
    allocator: std.mem.Allocator,
    client: WebSocketClient,
    event_bus: *EventBus,
    subscriptions: std.StringHashMap(SubscriptionInfo),
    
    reconnect_attempts: u32 = 0,
    max_reconnect_attempts: u32 = 10,
    
    pub fn init(allocator: std.mem.Allocator, event_bus: *EventBus) !BinanceWebSocket {
        return .{
            .allocator = allocator,
            .client = try WebSocketClient.init(allocator),
            .event_bus = event_bus,
            .subscriptions = std.StringHashMap(SubscriptionInfo).init(allocator),
        };
    }
    
    pub fn connect(self: *BinanceWebSocket) !void {
        try self.client.connect("wss://stream.binance.com:9443/ws");
        
        self.event_bus.publish(.{
            .type = .connected,
            .timestamp = std.time.milliTimestamp(),
            .data = .{ .connected = {} },
        });
        
        // 启动消息处理线程
        _ = try std.Thread.spawn(.{}, messageLoop, .{self});
    }
    
    pub fn subscribeOrderbook(self: *BinanceWebSocket, pair: TradingPair) !void {
        const symbol = try pairToSymbol(pair);
        const stream = try std.fmt.allocPrint(
            self.allocator,
            "{s}@depth@100ms",
            .{std.ascii.lowerString(symbol)}
        );
        
        try self.subscribe(stream);
    }
    
    pub fn subscribeTrades(self: *BinanceWebSocket, pair: TradingPair) !void {
        const symbol = try pairToSymbol(pair);
        const stream = try std.fmt.allocPrint(
            self.allocator,
            "{s}@trade",
            .{std.ascii.lowerString(symbol)}
        );
        
        try self.subscribe(stream);
    }
    
    fn subscribe(self: *BinanceWebSocket, stream: []const u8) !void {
        const msg = try std.json.stringifyAlloc(self.allocator, .{
            .method = "SUBSCRIBE",
            .params = &[_][]const u8{stream},
            .id = self.getNextId(),
        }, .{});
        
        try self.client.send(msg);
    }
    
    fn messageLoop(self: *BinanceWebSocket) void {
        while (true) {
            const message = self.client.receive() catch |err| {
                // 处理断线重连
                self.handleDisconnect(err);
                continue;
            };
            
            self.processMessage(message) catch |err| {
                // 记录错误但继续处理
                std.log.err("Error processing message: {}", .{err});
            };
        }
    }
    
    fn processMessage(self: *BinanceWebSocket, raw: []const u8) !void {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, raw, .{});
        defer parsed.deinit();
        
        const obj = parsed.value.object;
        
        if (obj.get("e")) |event_type| {
            const e = event_type.string;
            
            if (std.mem.eql(u8, e, "depthUpdate")) {
                const update = try parseOrderbookUpdate(obj);
                self.event_bus.publish(.{
                    .type = .orderbook_update,
                    .timestamp = std.time.milliTimestamp(),
                    .data = .{ .orderbook_update = update },
                });
            } else if (std.mem.eql(u8, e, "trade")) {
                const trade = try parseTrade(obj);
                self.event_bus.publish(.{
                    .type = .trade_update,
                    .timestamp = std.time.milliTimestamp(),
                    .data = .{ .trade_update = trade },
                });
            }
            // ... 更多事件类型
        }
    }
    
    fn handleDisconnect(self: *BinanceWebSocket, err: anyerror) void {
        self.event_bus.publish(.{
            .type = .disconnected,
            .timestamp = std.time.milliTimestamp(),
            .data = .{ .disconnected = err },
        });
        
        // 指数退避重连
        if (self.reconnect_attempts < self.max_reconnect_attempts) {
            const delay = std.math.pow(u64, 2, self.reconnect_attempts) * 1000;
            std.time.sleep(delay * std.time.ns_per_ms);
            
            self.reconnect_attempts += 1;
            self.connect() catch {};
        }
    }
};
```

---

# Phase 3: 策略框架 (4-5 周)

## 3.1 目标

- [ ] 策略基类与生命周期
- [ ] 信号生成系统
- [ ] 仓位管理
- [ ] 内置指标库 (MA, RSI, MACD, BB 等)
- [ ] 策略配置系统

## 3.2 策略基类

```zig
// src/strategy/base.zig

pub const Strategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,
    
    // 策略元信息
    name: []const u8,
    version: []const u8,
    author: []const u8,
    
    // 运行状态
    status: Status,
    position: Position,
    
    pub const Status = enum {
        stopped,
        running,
        paused,
        error,
    };
    
    pub const VTable = struct {
        // 生命周期
        onInit: *const fn(*anyopaque, *StrategyContext) anyerror!void,
        onStart: *const fn(*anyopaque) anyerror!void,
        onStop: *const fn(*anyopaque) void,
        
        // 数据事件
        onTick: *const fn(*anyopaque, Ticker) void,
        onOrderbook: *const fn(*anyopaque, Orderbook) void,
        onTrade: *const fn(*anyopaque, Trade) void,
        onKline: *const fn(*anyopaque, Kline) void,
        
        // 订单事件
        onOrderFilled: *const fn(*anyopaque, Order) void,
        onOrderCancelled: *const fn(*anyopaque, Order) void,
        
        // 策略逻辑
        generateSignals: *const fn(*anyopaque) []Signal,
    };
    
    // 代理方法
    pub fn init(self: Strategy, ctx: *StrategyContext) !void {
        return self.vtable.onInit(self.ptr, ctx);
    }
    
    pub fn start(self: Strategy) !void {
        return self.vtable.onStart(self.ptr);
    }
    
    pub fn onTick(self: Strategy, ticker: Ticker) void {
        self.vtable.onTick(self.ptr, ticker);
    }
    
    // ...
};

pub const StrategyContext = struct {
    allocator: std.mem.Allocator,
    exchange: ExchangeConnector,
    order_manager: *OrderManager,
    event_bus: *EventBus,
    config: StrategyConfig,
    logger: *Logger,
    
    // 数据访问
    orderbooks: std.StringHashMap(*Orderbook),
    klines: std.StringHashMap([]Kline),
    
    pub fn getOrderbook(self: *StrategyContext, pair: TradingPair) ?*Orderbook {
        return self.orderbooks.get(pair.symbol());
    }
    
    pub fn getKlines(self: *StrategyContext, pair: TradingPair, timeframe: Timeframe) ?[]Kline {
        const key = try std.fmt.allocPrint(
            self.allocator,
            "{s}_{s}",
            .{ pair.symbol(), @tagName(timeframe) }
        );
        return self.klines.get(key);
    }
    
    // 交易操作
    pub fn buy(self: *StrategyContext, pair: TradingPair, amount: Decimal, price: ?Decimal) !Order {
        return self.order_manager.submitOrder(.{
            .pair = pair,
            .side = .buy,
            .order_type = if (price) |_| .limit else .market,
            .amount = amount,
            .price = price,
        });
    }
    
    pub fn sell(self: *StrategyContext, pair: TradingPair, amount: Decimal, price: ?Decimal) !Order {
        return self.order_manager.submitOrder(.{
            .pair = pair,
            .side = .sell,
            .order_type = if (price) |_| .limit else .market,
            .amount = amount,
            .price = price,
        });
    }
    
    pub fn cancelAllOrders(self: *StrategyContext, pair: ?TradingPair) !void {
        // ...
    }
};
```

## 3.3 信号系统

```zig
// src/strategy/signal.zig

pub const Signal = struct {
    pair: TradingPair,
    direction: Direction,
    strength: f64,          // 0.0 - 1.0
    source: []const u8,     // 信号来源
    timestamp: i64,
    metadata: ?std.json.Value,
    
    pub const Direction = enum {
        long,       // 做多
        short,      // 做空
        close,      // 平仓
        neutral,    // 中性
    };
};

pub const SignalAggregator = struct {
    signals: std.ArrayList(Signal),
    weights: std.StringHashMap(f64),
    
    pub fn init(allocator: std.mem.Allocator) SignalAggregator {
        return .{
            .signals = std.ArrayList(Signal).init(allocator),
            .weights = std.StringHashMap(f64).init(allocator),
        };
    }
    
    pub fn addSignal(self: *SignalAggregator, signal: Signal) !void {
        try self.signals.append(signal);
    }
    
    pub fn setWeight(self: *SignalAggregator, source: []const u8, weight: f64) !void {
        try self.weights.put(source, weight);
    }
    
    pub fn aggregate(self: *SignalAggregator) AggregatedSignal {
        var long_score: f64 = 0;
        var short_score: f64 = 0;
        var total_weight: f64 = 0;
        
        for (self.signals.items) |signal| {
            const weight = self.weights.get(signal.source) orelse 1.0;
            total_weight += weight;
            
            switch (signal.direction) {
                .long => long_score += signal.strength * weight,
                .short => short_score += signal.strength * weight,
                else => {},
            }
        }
        
        if (total_weight == 0) {
            return .{ .direction = .neutral, .confidence = 0 };
        }
        
        const normalized_long = long_score / total_weight;
        const normalized_short = short_score / total_weight;
        
        if (normalized_long > normalized_short and normalized_long > 0.5) {
            return .{ .direction = .long, .confidence = normalized_long };
        } else if (normalized_short > normalized_long and normalized_short > 0.5) {
            return .{ .direction = .short, .confidence = normalized_short };
        } else {
            return .{ .direction = .neutral, .confidence = 0 };
        }
    }
    
    pub const AggregatedSignal = struct {
        direction: Signal.Direction,
        confidence: f64,
    };
};
```

## 3.4 技术指标库

```zig
// src/strategy/indicators/mod.zig

pub const indicators = struct {
    pub const sma = @import("sma.zig");
    pub const ema = @import("ema.zig");
    pub const rsi = @import("rsi.zig");
    pub const macd = @import("macd.zig");
    pub const bollinger = @import("bollinger.zig");
    pub const atr = @import("atr.zig");
    pub const volume = @import("volume.zig");
};

// src/strategy/indicators/sma.zig
pub const SMA = struct {
    period: u32,
    values: std.ArrayList(Decimal),
    sum: Decimal,
    
    pub fn init(allocator: std.mem.Allocator, period: u32) SMA {
        return .{
            .period = period,
            .values = std.ArrayList(Decimal).init(allocator),
            .sum = Decimal.ZERO,
        };
    }
    
    pub fn update(self: *SMA, value: Decimal) ?Decimal {
        try self.values.append(value);
        self.sum = self.sum.add(value);
        
        if (self.values.items.len > self.period) {
            const old = self.values.orderedRemove(0);
            self.sum = self.sum.sub(old);
        }
        
        if (self.values.items.len >= self.period) {
            return self.sum.div(Decimal.fromInt(self.period));
        }
        return null;
    }
    
    pub fn current(self: *const SMA) ?Decimal {
        if (self.values.items.len >= self.period) {
            return self.sum.div(Decimal.fromInt(self.period));
        }
        return null;
    }
};

// src/strategy/indicators/rsi.zig
pub const RSI = struct {
    period: u32,
    gains: std.ArrayList(Decimal),
    losses: std.ArrayList(Decimal),
    prev_close: ?Decimal,
    avg_gain: ?Decimal,
    avg_loss: ?Decimal,
    
    pub fn init(allocator: std.mem.Allocator, period: u32) RSI {
        return .{
            .period = period,
            .gains = std.ArrayList(Decimal).init(allocator),
            .losses = std.ArrayList(Decimal).init(allocator),
            .prev_close = null,
            .avg_gain = null,
            .avg_loss = null,
        };
    }
    
    pub fn update(self: *RSI, close: Decimal) ?Decimal {
        if (self.prev_close) |prev| {
            const change = close.sub(prev);
            
            if (change.isPositive()) {
                try self.gains.append(change);
                try self.losses.append(Decimal.ZERO);
            } else {
                try self.gains.append(Decimal.ZERO);
                try self.losses.append(change.abs());
            }
            
            if (self.gains.items.len >= self.period) {
                // 计算平均收益和平均损失
                if (self.avg_gain == null) {
                    // 第一次计算：简单平均
                    self.avg_gain = self.calculateAverage(self.gains.items);
                    self.avg_loss = self.calculateAverage(self.losses.items);
                } else {
                    // 后续计算：平滑平均
                    const n = Decimal.fromInt(self.period);
                    self.avg_gain = self.avg_gain.?.mul(n.sub(Decimal.ONE)).add(self.gains.getLast()).div(n);
                    self.avg_loss = self.avg_loss.?.mul(n.sub(Decimal.ONE)).add(self.losses.getLast()).div(n);
                }
                
                // 计算 RSI
                if (self.avg_loss.?.isZero()) {
                    return Decimal.fromInt(100);
                }
                
                const rs = self.avg_gain.?.div(self.avg_loss.?);
                const rsi = Decimal.fromInt(100).sub(
                    Decimal.fromInt(100).div(Decimal.ONE.add(rs))
                );
                
                return rsi;
            }
        }
        
        self.prev_close = close;
        return null;
    }
};

// src/strategy/indicators/macd.zig
pub const MACD = struct {
    fast_ema: EMA,
    slow_ema: EMA,
    signal_ema: EMA,
    
    pub fn init(allocator: std.mem.Allocator, fast: u32, slow: u32, signal: u32) MACD {
        return .{
            .fast_ema = EMA.init(allocator, fast),
            .slow_ema = EMA.init(allocator, slow),
            .signal_ema = EMA.init(allocator, signal),
        };
    }
    
    pub fn update(self: *MACD, value: Decimal) ?MACDResult {
        const fast = self.fast_ema.update(value) orelse return null;
        const slow = self.slow_ema.update(value) orelse return null;
        
        const macd_line = fast.sub(slow);
        const signal = self.signal_ema.update(macd_line) orelse return null;
        const histogram = macd_line.sub(signal);
        
        return .{
            .macd = macd_line,
            .signal = signal,
            .histogram = histogram,
        };
    }
    
    pub const MACDResult = struct {
        macd: Decimal,
        signal: Decimal,
        histogram: Decimal,
    };
};
```

## 3.5 示例策略：双均线策略

```zig
// src/strategy/builtin/dual_ma.zig

pub const DualMAStrategy = struct {
    allocator: std.mem.Allocator,
    ctx: ?*StrategyContext,
    config: Config,
    
    // 指标
    fast_ma: indicators.SMA,
    slow_ma: indicators.SMA,
    
    // 状态
    position: Position,
    last_signal: ?Signal.Direction,
    
    pub const Config = struct {
        pair: TradingPair,
        fast_period: u32 = 10,
        slow_period: u32 = 20,
        timeframe: Timeframe = .h1,
        position_size: Decimal,
    };
    
    pub fn init(allocator: std.mem.Allocator, config: Config) DualMAStrategy {
        return .{
            .allocator = allocator,
            .ctx = null,
            .config = config,
            .fast_ma = indicators.SMA.init(allocator, config.fast_period),
            .slow_ma = indicators.SMA.init(allocator, config.slow_period),
            .position = .{},
            .last_signal = null,
        };
    }
    
    pub fn strategy(self: *DualMAStrategy) Strategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
            .name = "DualMA",
            .version = "1.0.0",
            .author = "ZigQuant",
            .status = .stopped,
            .position = self.position,
        };
    }
    
    fn onInit(ptr: *anyopaque, ctx: *StrategyContext) !void {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));
        self.ctx = ctx;
        
        // 加载历史数据预热指标
        const klines = try ctx.exchange.getKlines(
            self.config.pair,
            self.config.timeframe,
            self.config.slow_period * 2,
        );
        
        for (klines) |kline| {
            _ = self.fast_ma.update(kline.close);
            _ = self.slow_ma.update(kline.close);
        }
        
        ctx.logger.info("DualMA Strategy initialized", .{});
    }
    
    fn onKline(ptr: *anyopaque, kline: Kline) void {
        const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));
        const ctx = self.ctx orelse return;
        
        // 更新指标
        const fast = self.fast_ma.update(kline.close) orelse return;
        const slow = self.slow_ma.update(kline.close) orelse return;
        
        // 生成信号
        const current_signal: Signal.Direction = if (fast.cmp(slow) == .gt) .long else .short;
        
        // 检测交叉
        if (self.last_signal) |last| {
            if (last != current_signal) {
                // 发生交叉
                ctx.logger.info("MA Crossover: {s} -> {s}", .{
                    @tagName(last),
                    @tagName(current_signal),
                });
                
                self.executeSignal(current_signal) catch |err| {
                    ctx.logger.err("Failed to execute signal: {}", .{err});
                };
            }
        }
        
        self.last_signal = current_signal;
    }
    
    fn executeSignal(self: *DualMAStrategy, signal: Signal.Direction) !void {
        const ctx = self.ctx orelse return;
        
        // 先平掉反向仓位
        if (self.position.size.isPositive()) {
            if (signal == .short) {
                _ = try ctx.sell(self.config.pair, self.position.size, null);
            }
        } else if (self.position.size.isNegative()) {
            if (signal == .long) {
                _ = try ctx.buy(self.config.pair, self.position.size.abs(), null);
            }
        }
        
        // 开新仓位
        switch (signal) {
            .long => {
                _ = try ctx.buy(self.config.pair, self.config.position_size, null);
            },
            .short => {
                _ = try ctx.sell(self.config.pair, self.config.position_size, null);
            },
            else => {},
        }
    }
    
    const vtable = Strategy.VTable{
        .onInit = onInit,
        .onStart = onStart,
        .onStop = onStop,
        .onTick = onTick,
        .onOrderbook = onOrderbook,
        .onTrade = onTrade,
        .onKline = onKline,
        .onOrderFilled = onOrderFilled,
        .onOrderCancelled = onOrderCancelled,
        .generateSignals = generateSignals,
    };
};
```

---

# Phase 4: 回测系统 (4-5 周)

## 4.1 目标

- [ ] 历史数据管理与下载
- [ ] 高性能回测引擎
- [ ] 交易成本模拟（手续费、滑点）
- [ ] 详细的绩效报告
- [ ] 可视化分析

## 4.2 数据源管理

```zig
// src/backtest/data_feed.zig

pub const DataFeed = struct {
    allocator: std.mem.Allocator,
    storage: DataStorage,
    cache: std.AutoHashMap(CacheKey, []Kline),
    
    pub const CacheKey = struct {
        pair: TradingPair,
        timeframe: Timeframe,
        start: i64,
        end: i64,
    };
    
    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !DataFeed {
        return .{
            .allocator = allocator,
            .storage = try DataStorage.init(allocator, data_dir),
            .cache = std.AutoHashMap(CacheKey, []Kline).init(allocator),
        };
    }
    
    /// 获取历史 K 线数据
    pub fn getKlines(
        self: *DataFeed,
        pair: TradingPair,
        timeframe: Timeframe,
        start: i64,
        end: i64,
    ) ![]Kline {
        const key = CacheKey{ .pair = pair, .timeframe = timeframe, .start = start, .end = end };
        
        // 检查缓存
        if (self.cache.get(key)) |cached| {
            return cached;
        }
        
        // 从存储加载
        const klines = try self.storage.loadKlines(pair, timeframe, start, end);
        
        // 缓存结果
        try self.cache.put(key, klines);
        
        return klines;
    }
    
    /// 下载历史数据
    pub fn download(
        self: *DataFeed,
        exchange: ExchangeConnector,
        pair: TradingPair,
        timeframe: Timeframe,
        start: i64,
        end: i64,
    ) !void {
        var current = start;
        const batch_size: u32 = 1000;
        
        while (current < end) {
            const klines = try exchange.getKlines(pair, timeframe, batch_size);
            try self.storage.saveKlines(pair, timeframe, klines);
            
            if (klines.len == 0) break;
            current = klines[klines.len - 1].timestamp + timeframe.toMillis();
            
            // 限流
            std.time.sleep(100 * std.time.ns_per_ms);
        }
    }
};

pub const DataStorage = struct {
    allocator: std.mem.Allocator,
    db: sqlite.Database,
    
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !DataStorage {
        var db = try sqlite.Database.open(path);
        
        // 创建表
        try db.exec(
            \\CREATE TABLE IF NOT EXISTS klines (
            \\  pair TEXT NOT NULL,
            \\  timeframe TEXT NOT NULL,
            \\  timestamp INTEGER NOT NULL,
            \\  open TEXT NOT NULL,
            \\  high TEXT NOT NULL,
            \\  low TEXT NOT NULL,
            \\  close TEXT NOT NULL,
            \\  volume TEXT NOT NULL,
            \\  PRIMARY KEY (pair, timeframe, timestamp)
            \\)
        );
        
        return .{
            .allocator = allocator,
            .db = db,
        };
    }
    
    pub fn saveKlines(self: *DataStorage, pair: TradingPair, timeframe: Timeframe, klines: []Kline) !void {
        var stmt = try self.db.prepare(
            \\INSERT OR REPLACE INTO klines 
            \\(pair, timeframe, timestamp, open, high, low, close, volume)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        );
        defer stmt.deinit();
        
        for (klines) |k| {
            try stmt.bind(.{
                pair.symbol(),
                @tagName(timeframe),
                k.timestamp,
                k.open.toString(),
                k.high.toString(),
                k.low.toString(),
                k.close.toString(),
                k.volume.toString(),
            });
            try stmt.step();
            stmt.reset();
        }
    }
    
    pub fn loadKlines(
        self: *DataStorage,
        pair: TradingPair,
        timeframe: Timeframe,
        start: i64,
        end: i64,
    ) ![]Kline {
        var stmt = try self.db.prepare(
            \\SELECT timestamp, open, high, low, close, volume
            \\FROM klines
            \\WHERE pair = ? AND timeframe = ? AND timestamp >= ? AND timestamp <= ?
            \\ORDER BY timestamp ASC
        );
        defer stmt.deinit();
        
        try stmt.bind(.{ pair.symbol(), @tagName(timeframe), start, end });
        
        var klines = std.ArrayList(Kline).init(self.allocator);
        
        while (try stmt.step()) |row| {
            try klines.append(.{
                .timestamp = row.get(i64, 0),
                .open = try Decimal.fromString(row.get([]const u8, 1)),
                .high = try Decimal.fromString(row.get([]const u8, 2)),
                .low = try Decimal.fromString(row.get([]const u8, 3)),
                .close = try Decimal.fromString(row.get([]const u8, 4)),
                .volume = try Decimal.fromString(row.get([]const u8, 5)),
            });
        }
        
        return klines.toOwnedSlice();
    }
};
```

## 4.3 回测引擎

```zig
// src/backtest/engine.zig

pub const BacktestEngine = struct {
    allocator: std.mem.Allocator,
    config: BacktestConfig,
    data_feed: *DataFeed,
    strategy: Strategy,
    
    // 模拟状态
    current_time: i64,
    balance: std.StringHashMap(Decimal),
    positions: std.StringHashMap(Position),
    orders: std.ArrayList(Order),
    trades: std.ArrayList(Trade),
    
    // 统计
    metrics: BacktestMetrics,
    
    pub const BacktestConfig = struct {
        start_time: i64,
        end_time: i64,
        initial_balance: std.StringHashMap(Decimal),
        
        // 费用设置
        maker_fee: Decimal = Decimal.fromFloat(0.001),  // 0.1%
        taker_fee: Decimal = Decimal.fromFloat(0.001),  // 0.1%
        slippage: Decimal = Decimal.fromFloat(0.0005),  // 0.05%
        
        // 其他设置
        timeframe: Timeframe = .h1,
        pairs: []TradingPair,
    };
    
    pub fn init(
        allocator: std.mem.Allocator,
        config: BacktestConfig,
        data_feed: *DataFeed,
        strategy: Strategy,
    ) BacktestEngine {
        var balance = std.StringHashMap(Decimal).init(allocator);
        var iter = config.initial_balance.iterator();
        while (iter.next()) |entry| {
            balance.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
        }
        
        return .{
            .allocator = allocator,
            .config = config,
            .data_feed = data_feed,
            .strategy = strategy,
            .current_time = config.start_time,
            .balance = balance,
            .positions = std.StringHashMap(Position).init(allocator),
            .orders = std.ArrayList(Order).init(allocator),
            .trades = std.ArrayList(Trade).init(allocator),
            .metrics = BacktestMetrics.init(),
        };
    }
    
    pub fn run(self: *BacktestEngine) !BacktestResult {
        // 初始化策略
        var mock_ctx = self.createMockContext();
        try self.strategy.init(&mock_ctx);
        try self.strategy.start();
        
        // 预加载所有数据
        var all_klines = std.ArrayList(KlineEvent).init(self.allocator);
        
        for (self.config.pairs) |pair| {
            const klines = try self.data_feed.getKlines(
                pair,
                self.config.timeframe,
                self.config.start_time,
                self.config.end_time,
            );
            
            for (klines) |kline| {
                try all_klines.append(.{ .pair = pair, .kline = kline });
            }
        }
        
        // 按时间排序
        std.sort.sort(KlineEvent, all_klines.items, {}, KlineEvent.lessThan);
        
        // 主回测循环
        for (all_klines.items) |event| {
            self.current_time = event.kline.timestamp;
            
            // 更新订单簿模拟
            self.updateMockOrderbook(event.pair, event.kline);
            
            // 处理挂单
            try self.processOrders(event.kline);
            
            // 调用策略
            self.strategy.onKline(event.kline);
            
            // 更新净值曲线
            self.metrics.recordEquity(self.current_time, self.calculateEquity());
        }
        
        self.strategy.stop();
        
        // 计算最终统计
        return self.generateResult();
    }
    
    fn processOrders(self: *BacktestEngine, kline: Kline) !void {
        var i: usize = 0;
        while (i < self.orders.items.len) {
            var order = &self.orders.items[i];
            
            if (order.status != .open) {
                i += 1;
                continue;
            }
            
            const filled = switch (order.order_type) {
                .market => true,
                .limit => self.checkLimitFill(order, kline),
                .stop_loss => self.checkStopFill(order, kline),
                else => false,
            };
            
            if (filled) {
                try self.fillOrder(order, kline);
            }
            
            i += 1;
        }
    }
    
    fn fillOrder(self: *BacktestEngine, order: *Order, kline: Kline) !void {
        // 计算成交价（含滑点）
        var fill_price = order.price orelse kline.close;
        
        if (order.order_type == .market) {
            const slippage_amount = fill_price.mul(self.config.slippage);
            fill_price = if (order.side == .buy)
                fill_price.add(slippage_amount)
            else
                fill_price.sub(slippage_amount);
        }
        
        // 计算手续费
        const fee_rate = if (order.order_type == .limit)
            self.config.maker_fee
        else
            self.config.taker_fee;
        
        const notional = fill_price.mul(order.amount);
        const fee = notional.mul(fee_rate);
        
        // 更新余额
        if (order.side == .buy) {
            const cost = notional.add(fee);
            const quote_balance = self.balance.get(order.pair.quote) orelse Decimal.ZERO;
            self.balance.put(order.pair.quote, quote_balance.sub(cost)) catch {};
            
            const base_balance = self.balance.get(order.pair.base) orelse Decimal.ZERO;
            self.balance.put(order.pair.base, base_balance.add(order.amount)) catch {};
        } else {
            const base_balance = self.balance.get(order.pair.base) orelse Decimal.ZERO;
            self.balance.put(order.pair.base, base_balance.sub(order.amount)) catch {};
            
            const proceeds = notional.sub(fee);
            const quote_balance = self.balance.get(order.pair.quote) orelse Decimal.ZERO;
            self.balance.put(order.pair.quote, quote_balance.add(proceeds)) catch {};
        }
        
        // 更新仓位
        self.updatePosition(order.pair, order.side, order.amount, fill_price);
        
        // 记录成交
        try self.trades.append(.{
            .timestamp = self.current_time,
            .pair = order.pair,
            .side = order.side,
            .price = fill_price,
            .amount = order.amount,
            .fee = fee,
            .order_id = order.id,
        });
        
        // 更新订单状态
        order.status = .filled;
        order.filled_amount = order.amount;
        order.avg_fill_price = fill_price;
        
        // 通知策略
        self.strategy.onOrderFilled(order.*);
        
        // 更新统计
        self.metrics.total_trades += 1;
        self.metrics.total_fees = self.metrics.total_fees.add(fee);
    }
    
    fn createMockContext(self: *BacktestEngine) StrategyContext {
        return .{
            .allocator = self.allocator,
            .exchange = self.createMockExchange(),
            .order_manager = self.createMockOrderManager(),
            .event_bus = undefined,  // 回测不需要事件总线
            .config = .{},
            .logger = undefined,
            .orderbooks = std.StringHashMap(*Orderbook).init(self.allocator),
            .klines = std.StringHashMap([]Kline).init(self.allocator),
        };
    }
    
    fn generateResult(self: *BacktestEngine) BacktestResult {
        return .{
            .metrics = self.metrics.calculate(),
            .trades = self.trades.items,
            .equity_curve = self.metrics.equity_curve.items,
        };
    }
};
```

## 4.4 绩效指标

```zig
// src/backtest/metrics.zig

pub const BacktestMetrics = struct {
    // 原始数据
    equity_curve: std.ArrayList(EquityPoint),
    trades: []Trade,
    
    // 计算结果
    pub const CalculatedMetrics = struct {
        // 收益指标
        total_return: Decimal,
        total_return_pct: f64,
        annualized_return: f64,
        
        // 风险指标
        max_drawdown: f64,
        max_drawdown_duration: i64,
        volatility: f64,
        downside_deviation: f64,
        
        // 风险调整收益
        sharpe_ratio: f64,
        sortino_ratio: f64,
        calmar_ratio: f64,
        
        // 交易统计
        total_trades: u64,
        winning_trades: u64,
        losing_trades: u64,
        win_rate: f64,
        
        profit_factor: f64,
        avg_win: Decimal,
        avg_loss: Decimal,
        largest_win: Decimal,
        largest_loss: Decimal,
        
        avg_trade_duration: i64,
        
        // 费用
        total_fees: Decimal,
        
        // 曝险
        avg_exposure: f64,
        max_exposure: f64,
    };
    
    pub const EquityPoint = struct {
        timestamp: i64,
        equity: Decimal,
        drawdown: f64,
    };
    
    pub fn init(allocator: std.mem.Allocator) BacktestMetrics {
        return .{
            .equity_curve = std.ArrayList(EquityPoint).init(allocator),
            .trades = &.{},
        };
    }
    
    pub fn recordEquity(self: *BacktestMetrics, timestamp: i64, equity: Decimal) void {
        const peak = if (self.equity_curve.items.len > 0)
            @max(self.equity_curve.getLast().equity, equity)
        else
            equity;
        
        const drawdown = if (peak.isPositive())
            (peak.sub(equity)).div(peak).toFloat()
        else
            0;
        
        self.equity_curve.append(.{
            .timestamp = timestamp,
            .equity = equity,
            .drawdown = drawdown,
        }) catch {};
    }
    
    pub fn calculate(self: *BacktestMetrics) CalculatedMetrics {
        if (self.equity_curve.items.len < 2) {
            return CalculatedMetrics{};
        }
        
        const initial = self.equity_curve.items[0].equity;
        const final = self.equity_curve.getLast().equity;
        
        // 总收益
        const total_return = final.sub(initial);
        const total_return_pct = total_return.div(initial).toFloat() * 100;
        
        // 最大回撤
        var max_dd: f64 = 0;
        for (self.equity_curve.items) |point| {
            max_dd = @max(max_dd, point.drawdown);
        }
        
        // 波动率
        const returns = self.calculateReturns();
        const volatility = self.stdDev(returns);
        
        // 夏普比率 (假设无风险利率 2%)
        const risk_free = 0.02 / 365;
        const avg_return = self.mean(returns);
        const sharpe = if (volatility > 0)
            (avg_return - risk_free) / volatility * @sqrt(365.0)
        else
            0;
        
        // 交易统计
        var winning: u64 = 0;
        var losing: u64 = 0;
        var total_profit = Decimal.ZERO;
        var total_loss = Decimal.ZERO;
        
        for (self.trades) |trade| {
            if (trade.pnl.isPositive()) {
                winning += 1;
                total_profit = total_profit.add(trade.pnl);
            } else {
                losing += 1;
                total_loss = total_loss.add(trade.pnl.abs());
            }
        }
        
        const win_rate = if (self.trades.len > 0)
            @as(f64, @floatFromInt(winning)) / @as(f64, @floatFromInt(self.trades.len))
        else
            0;
        
        const profit_factor = if (total_loss.isPositive())
            total_profit.div(total_loss).toFloat()
        else
            std.math.inf(f64);
        
        return .{
            .total_return = total_return,
            .total_return_pct = total_return_pct,
            .max_drawdown = max_dd * 100,
            .volatility = volatility * @sqrt(365.0) * 100,
            .sharpe_ratio = sharpe,
            .total_trades = @intCast(self.trades.len),
            .winning_trades = winning,
            .losing_trades = losing,
            .win_rate = win_rate * 100,
            .profit_factor = profit_factor,
            // ... 其他指标
        };
    }
    
    fn calculateReturns(self: *BacktestMetrics) []f64 {
        // 计算日收益率序列
    }
    
    fn mean(self: *BacktestMetrics, data: []f64) f64 {
        // 计算平均值
    }
    
    fn stdDev(self: *BacktestMetrics, data: []f64) f64 {
        // 计算标准差
    }
};

// 报告生成
pub const ReportGenerator = struct {
    pub fn generateText(metrics: BacktestMetrics.CalculatedMetrics) []const u8 {
        // 生成文本报告
    }
    
    pub fn generateHTML(metrics: BacktestMetrics.CalculatedMetrics, equity_curve: []EquityPoint) []const u8 {
        // 生成 HTML 报告，含图表
    }
    
    pub fn generateJSON(metrics: BacktestMetrics.CalculatedMetrics) []const u8 {
        // 生成 JSON 报告
    }
};
```

---

# Phase 5: 做市与套利 (5-6 周)

> 这是 Hummingbot 的核心功能

## 5.1 目标

- [ ] 纯做市策略
- [ ] 跨交易所套利
- [ ] 三角套利
- [ ] 库存管理
- [ ] 智能价差计算

## 5.2 做市策略

```zig
// src/strategy/builtin/pure_market_making.zig

pub const PureMarketMaking = struct {
    allocator: std.mem.Allocator,
    ctx: ?*StrategyContext,
    config: Config,
    
    // 状态
    active_orders: ActiveOrders,
    inventory: InventoryManager,
    spread_calculator: SpreadCalculator,
    
    pub const Config = struct {
        pair: TradingPair,
        
        // 价差设置
        bid_spread: Decimal,           // 买单价差 (e.g., 0.001 = 0.1%)
        ask_spread: Decimal,           // 卖单价差
        
        // 订单设置
        order_amount: Decimal,         // 每单数量
        order_levels: u32 = 1,         // 订单层数
        order_level_spread: Decimal,   // 层间价差
        
        // 库存管理
        inventory_target_pct: f64 = 0.5,  // 目标持仓比例
        inventory_range_multiplier: f64 = 1.0,
        
        // 风险管理
        max_order_age: i64 = 60_000,   // 最大挂单时间 (ms)
        filled_order_delay: i64 = 1_000, // 成交后延迟 (ms)
        
        // 高级设置
        price_source: PriceSource = .mid_price,
        price_ceiling: ?Decimal = null,
        price_floor: ?Decimal = null,
    };
    
    pub const PriceSource = enum {
        mid_price,
        last_price,
        best_bid,
        best_ask,
        external,
    };
    
    pub fn init(allocator: std.mem.Allocator, config: Config) PureMarketMaking {
        return .{
            .allocator = allocator,
            .ctx = null,
            .config = config,
            .active_orders = ActiveOrders.init(allocator),
            .inventory = InventoryManager.init(allocator, config.inventory_target_pct),
            .spread_calculator = SpreadCalculator.init(config),
        };
    }
    
    fn onTick(ptr: *anyopaque, ticker: Ticker) void {
        const self: *PureMarketMaking = @ptrCast(@alignCast(ptr));
        const ctx = self.ctx orelse return;
        
        // 1. 获取参考价格
        const ref_price = self.getReferencePrice() orelse return;
        
        // 2. 检查价格边界
        if (self.config.price_ceiling) |ceiling| {
            if (ref_price.cmp(ceiling) == .gt) return;
        }
        if (self.config.price_floor) |floor| {
            if (ref_price.cmp(floor) == .lt) return;
        }
        
        // 3. 计算库存偏移
        const inventory_skew = self.inventory.calculateSkew();
        
        // 4. 计算调整后的价差
        const spreads = self.spread_calculator.calculate(ref_price, inventory_skew);
        
        // 5. 取消旧订单
        self.cancelStaleOrders() catch {};
        
        // 6. 创建新订单
        self.createOrders(ref_price, spreads) catch |err| {
            ctx.logger.err("Failed to create orders: {}", .{err});
        };
    }
    
    fn createOrders(self: *PureMarketMaking, ref_price: Decimal, spreads: Spreads) !void {
        const ctx = self.ctx orelse return;
        
        for (0..self.config.order_levels) |level| {
            const level_offset = Decimal.fromInt(@intCast(level)).mul(self.config.order_level_spread);
            
            // 买单
            const bid_price = ref_price.mul(Decimal.ONE.sub(spreads.bid).sub(level_offset));
            if (!self.active_orders.hasOrderAt(.buy, bid_price)) {
                const order = try ctx.buy(self.config.pair, self.config.order_amount, bid_price);
                try self.active_orders.track(order);
            }
            
            // 卖单
            const ask_price = ref_price.mul(Decimal.ONE.add(spreads.ask).add(level_offset));
            if (!self.active_orders.hasOrderAt(.sell, ask_price)) {
                const order = try ctx.sell(self.config.pair, self.config.order_amount, ask_price);
                try self.active_orders.track(order);
            }
        }
    }
    
    fn onOrderFilled(ptr: *anyopaque, order: Order) void {
        const self: *PureMarketMaking = @ptrCast(@alignCast(ptr));
        
        // 更新库存
        self.inventory.update(order);
        
        // 从活跃订单中移除
        self.active_orders.remove(order.id);
        
        // 记录盈亏
        // ...
    }
};

// 库存管理器
pub const InventoryManager = struct {
    allocator: std.mem.Allocator,
    target_pct: f64,
    
    base_balance: Decimal,
    quote_balance: Decimal,
    avg_buy_price: Decimal,
    avg_sell_price: Decimal,
    
    pub fn init(allocator: std.mem.Allocator, target_pct: f64) InventoryManager {
        return .{
            .allocator = allocator,
            .target_pct = target_pct,
            .base_balance = Decimal.ZERO,
            .quote_balance = Decimal.ZERO,
            .avg_buy_price = Decimal.ZERO,
            .avg_sell_price = Decimal.ZERO,
        };
    }
    
    /// 计算库存偏移 (-1 到 1)
    /// 正值表示持仓过多，应降低买单价格/提高卖单价格
    /// 负值表示持仓过少，应提高买单价格/降低卖单价格
    pub fn calculateSkew(self: *InventoryManager) f64 {
        const total_value = self.base_balance.add(self.quote_balance);
        if (total_value.isZero()) return 0;
        
        const current_pct = self.base_balance.div(total_value).toFloat();
        return (current_pct - self.target_pct) / self.target_pct;
    }
    
    pub fn update(self: *InventoryManager, order: Order) void {
        if (order.side == .buy) {
            self.base_balance = self.base_balance.add(order.filled_amount);
            // 更新平均买入价...
        } else {
            self.base_balance = self.base_balance.sub(order.filled_amount);
            // 更新平均卖出价...
        }
    }
};

// 价差计算器
pub const SpreadCalculator = struct {
    config: PureMarketMaking.Config,
    volatility_tracker: VolatilityTracker,
    
    pub const Spreads = struct {
        bid: Decimal,
        ask: Decimal,
    };
    
    pub fn calculate(self: *SpreadCalculator, ref_price: Decimal, inventory_skew: f64) Spreads {
        var bid_spread = self.config.bid_spread;
        var ask_spread = self.config.ask_spread;
        
        // 根据库存偏移调整价差
        if (inventory_skew > 0) {
            // 持仓过多，降低买价，提高卖价
            bid_spread = bid_spread.mul(Decimal.fromFloat(1 + inventory_skew));
            ask_spread = ask_spread.mul(Decimal.fromFloat(1 - inventory_skew * 0.5));
        } else if (inventory_skew < 0) {
            // 持仓过少，提高买价，降低卖价
            bid_spread = bid_spread.mul(Decimal.fromFloat(1 + inventory_skew * 0.5));
            ask_spread = ask_spread.mul(Decimal.fromFloat(1 - inventory_skew));
        }
        
        // 根据波动率调整价差
        if (self.volatility_tracker.isHighVolatility()) {
            const vol_multiplier = self.volatility_tracker.getMultiplier();
            bid_spread = bid_spread.mul(vol_multiplier);
            ask_spread = ask_spread.mul(vol_multiplier);
        }
        
        return .{
            .bid = bid_spread,
            .ask = ask_spread,
        };
    }
};
```

## 5.3 跨交易所套利

```zig
// src/strategy/builtin/cross_exchange_arbitrage.zig

pub const CrossExchangeArbitrage = struct {
    allocator: std.mem.Allocator,
    ctx: ?*StrategyContext,
    config: Config,
    
    // 交易所连接
    maker_exchange: ExchangeConnector,
    taker_exchange: ExchangeConnector,
    
    // 订单簿
    maker_orderbook: ?*Orderbook,
    taker_orderbook: ?*Orderbook,
    
    // 状态
    pending_arb: ?ArbitrageOpportunity,
    
    pub const Config = struct {
        pair: TradingPair,
        
        min_profitability: Decimal,    // 最小利润率 (e.g., 0.003 = 0.3%)
        order_amount: Decimal,         // 交易数量
        
        // 费用
        maker_fee: Decimal,
        taker_fee: Decimal,
        transfer_fee: Decimal,
        
        // 风控
        max_order_age: i64 = 5_000,
        slippage_buffer: Decimal,
    };
    
    pub const ArbitrageOpportunity = struct {
        direction: Direction,
        maker_price: Decimal,
        taker_price: Decimal,
        profit_pct: f64,
        amount: Decimal,
        timestamp: i64,
        
        pub const Direction = enum {
            buy_maker_sell_taker,
            buy_taker_sell_maker,
        };
    };
    
    pub fn init(
        allocator: std.mem.Allocator,
        config: Config,
        maker: ExchangeConnector,
        taker: ExchangeConnector,
    ) CrossExchangeArbitrage {
        return .{
            .allocator = allocator,
            .ctx = null,
            .config = config,
            .maker_exchange = maker,
            .taker_exchange = taker,
            .maker_orderbook = null,
            .taker_orderbook = null,
            .pending_arb = null,
        };
    }
    
    fn onOrderbook(ptr: *anyopaque, orderbook: *Orderbook) void {
        const self: *CrossExchangeArbitrage = @ptrCast(@alignCast(ptr));
        
        // 更新订单簿引用
        // ...
        
        // 检查套利机会
        const opportunity = self.findArbitrage() orelse return;
        
        if (opportunity.profit_pct >= self.config.min_profitability.toFloat()) {
            self.executeArbitrage(opportunity) catch {};
        }
    }
    
    fn findArbitrage(self: *CrossExchangeArbitrage) ?ArbitrageOpportunity {
        const maker_ob = self.maker_orderbook orelse return null;
        const taker_ob = self.taker_orderbook orelse return null;
        
        const maker_bid = maker_ob.getBestBid() orelse return null;
        const maker_ask = maker_ob.getBestAsk() orelse return null;
        const taker_bid = taker_ob.getBestBid() orelse return null;
        const taker_ask = taker_ob.getBestAsk() orelse return null;
        
        // 机会 1: 在 maker 买入，在 taker 卖出
        const profit1 = self.calculateProfit(maker_ask.price, taker_bid.price, .buy_maker_sell_taker);
        
        // 机会 2: 在 taker 买入，在 maker 卖出
        const profit2 = self.calculateProfit(taker_ask.price, maker_bid.price, .buy_taker_sell_maker);
        
        if (profit1 > profit2 and profit1 > 0) {
            return .{
                .direction = .buy_maker_sell_taker,
                .maker_price = maker_ask.price,
                .taker_price = taker_bid.price,
                .profit_pct = profit1,
                .amount = @min(maker_ask.quantity, taker_bid.quantity, self.config.order_amount),
                .timestamp = std.time.milliTimestamp(),
            };
        } else if (profit2 > 0) {
            return .{
                .direction = .buy_taker_sell_maker,
                .maker_price = maker_bid.price,
                .taker_price = taker_ask.price,
                .profit_pct = profit2,
                .amount = @min(taker_ask.quantity, maker_bid.quantity, self.config.order_amount),
                .timestamp = std.time.milliTimestamp(),
            };
        }
        
        return null;
    }
    
    fn calculateProfit(
        self: *CrossExchangeArbitrage,
        buy_price: Decimal,
        sell_price: Decimal,
        direction: ArbitrageOpportunity.Direction,
    ) f64 {
        // 考虑所有费用后的净利润
        const gross = sell_price.sub(buy_price);
        
        const buy_fee = buy_price.mul(
            if (direction == .buy_maker_sell_taker) self.config.maker_fee else self.config.taker_fee
        );
        
        const sell_fee = sell_price.mul(
            if (direction == .buy_maker_sell_taker) self.config.taker_fee else self.config.maker_fee
        );
        
        const total_fee = buy_fee.add(sell_fee).add(self.config.transfer_fee);
        const net = gross.sub(total_fee);
        
        return net.div(buy_price).toFloat();
    }
    
    fn executeArbitrage(self: *CrossExchangeArbitrage, opp: ArbitrageOpportunity) !void {
        const ctx = self.ctx orelse return;
        
        ctx.logger.info("Executing arbitrage: {s}, profit: {d:.2}%", .{
            @tagName(opp.direction),
            opp.profit_pct * 100,
        });
        
        // 同时下单（尽量原子化）
        switch (opp.direction) {
            .buy_maker_sell_taker => {
                // 在 maker 买入
                _ = try self.maker_exchange.createOrder(.{
                    .pair = self.config.pair,
                    .side = .buy,
                    .order_type = .limit,
                    .amount = opp.amount,
                    .price = opp.maker_price,
                });
                
                // 在 taker 卖出
                _ = try self.taker_exchange.createOrder(.{
                    .pair = self.config.pair,
                    .side = .sell,
                    .order_type = .market,
                    .amount = opp.amount,
                    .price = null,
                });
            },
            .buy_taker_sell_maker => {
                // 在 taker 买入
                _ = try self.taker_exchange.createOrder(.{
                    .pair = self.config.pair,
                    .side = .buy,
                    .order_type = .market,
                    .amount = opp.amount,
                    .price = null,
                });
                
                // 在 maker 卖出
                _ = try self.maker_exchange.createOrder(.{
                    .pair = self.config.pair,
                    .side = .sell,
                    .order_type = .limit,
                    .amount = opp.amount,
                    .price = opp.maker_price,
                });
            },
        }
        
        self.pending_arb = opp;
    }
};
```

## 5.4 三角套利

```zig
// src/strategy/builtin/triangular_arbitrage.zig

pub const TriangularArbitrage = struct {
    allocator: std.mem.Allocator,
    ctx: ?*StrategyContext,
    config: Config,
    
    // 三角路径
    triangles: []Triangle,
    
    pub const Config = struct {
        min_profitability: Decimal,
        order_amount_base: Decimal,   // 以基础货币计的交易量
        fee_rate: Decimal,
    };
    
    pub const Triangle = struct {
        // A -> B -> C -> A
        pair_ab: TradingPair,  // A/B
        pair_bc: TradingPair,  // B/C
        pair_ca: TradingPair,  // C/A
        
        // 方向
        ab_buy: bool,
        bc_buy: bool,
        ca_buy: bool,
    };
    
    pub fn findTriangles(allocator: std.mem.Allocator, pairs: []TradingPair) ![]Triangle {
        // 查找所有可能的三角路径
        var triangles = std.ArrayList(Triangle).init(allocator);
        
        // 构建货币图
        var graph = std.StringHashMap(std.ArrayList(TradingPair)).init(allocator);
        
        for (pairs) |pair| {
            const base_list = try graph.getOrPutValue(pair.base, std.ArrayList(TradingPair).init(allocator));
            try base_list.value_ptr.append(pair);
            
            const quote_list = try graph.getOrPutValue(pair.quote, std.ArrayList(TradingPair).init(allocator));
            try quote_list.value_ptr.append(pair);
        }
        
        // DFS 查找三角
        // ...
        
        return triangles.toOwnedSlice();
    }
    
    fn checkTriangle(self: *TriangularArbitrage, triangle: Triangle) ?f64 {
        const ctx = self.ctx orelse return null;
        
        // 获取各交易对的最优价格
        const ob_ab = ctx.getOrderbook(triangle.pair_ab) orelse return null;
        const ob_bc = ctx.getOrderbook(triangle.pair_bc) orelse return null;
        const ob_ca = ctx.getOrderbook(triangle.pair_ca) orelse return null;
        
        // 计算循环收益
        var amount = Decimal.ONE;
        
        // A -> B
        if (triangle.ab_buy) {
            const ask = ob_ab.getBestAsk() orelse return murray;
            amount = amount.div(ask.price);
        } else {
            const bid = ob_ab.getBestBid() orelse return null;
            amount = amount.mul(bid.price);
        }
        amount = amount.mul(Decimal.ONE.sub(self.config.fee_rate));
        
        // B -> C
        if (triangle.bc_buy) {
            const ask = ob_bc.getBestAsk() orelse return null;
            amount = amount.div(ask.price);
        } else {
            const bid = ob_bc.getBestBid() orelse return null;
            amount = amount.mul(bid.price);
        }
        amount = amount.mul(Decimal.ONE.sub(self.config.fee_rate));
        
        // C -> A
        if (triangle.ca_buy) {
            const ask = ob_ca.getBestAsk() orelse return null;
            amount = amount.div(ask.price);
        } else {
            const bid = ob_ca.getBestBid() orelse return null;
            amount = amount.mul(bid.price);
        }
        amount = amount.mul(Decimal.ONE.sub(self.config.fee_rate));
        
        // 利润 = 最终 - 初始
        const profit = amount.sub(Decimal.ONE);
        
        if (profit.isPositive()) {
            return profit.toFloat();
        }
        return null;
    }
};
```

---

# Phase 6: 生产级功能 (4-5 周)

## 6.1 目标

- [ ] 风险管理系统
- [ ] 监控与告警
- [ ] API 服务
- [ ] 配置热更新
- [ ] 日志与审计

## 6.2 风险管理

```zig
// src/risk/manager.zig

pub const RiskManager = struct {
    allocator: std.mem.Allocator,
    config: RiskConfig,
    limits: std.ArrayList(RiskLimit),
    
    // 状态追踪
    daily_pnl: Decimal,
    daily_volume: Decimal,
    open_positions_value: Decimal,
    daily_trades: u32,
    
    last_reset: i64,
    
    pub const RiskConfig = struct {
        // 每日限制
        max_daily_loss: Decimal,
        max_daily_volume: Decimal,
        max_daily_trades: u32,
        
        // 仓位限制
        max_position_size: Decimal,
        max_total_exposure: Decimal,
        
        // 订单限制
        max_order_size: Decimal,
        max_orders_per_minute: u32,
        
        // 价格保护
        max_slippage: Decimal,
        price_deviation_threshold: Decimal,
    };
    
    pub const RiskLimit = struct {
        name: []const u8,
        check: *const fn(*RiskManager, OrderRequest) RiskCheckResult,
        enabled: bool,
    };
    
    pub const RiskCheckResult = union(enum) {
        passed,
        rejected: []const u8,
        warning: []const u8,
    };
    
    pub fn init(allocator: std.mem.Allocator, config: RiskConfig) RiskManager {
        var rm = RiskManager{
            .allocator = allocator,
            .config = config,
            .limits = std.ArrayList(RiskLimit).init(allocator),
            .daily_pnl = Decimal.ZERO,
            .daily_volume = Decimal.ZERO,
            .open_positions_value = Decimal.ZERO,
            .daily_trades = 0,
            .last_reset = std.time.milliTimestamp(),
        };
        
        // 注册默认限制
        rm.registerDefaultLimits();
        
        return rm;
    }
    
    fn registerDefaultLimits(self: *RiskManager) void {
        self.limits.append(.{ .name = "daily_loss", .check = checkDailyLoss, .enabled = true }) catch {};
        self.limits.append(.{ .name = "daily_volume", .check = checkDailyVolume, .enabled = true }) catch {};
        self.limits.append(.{ .name = "position_size", .check = checkPositionSize, .enabled = true }) catch {};
        self.limits.append(.{ .name = "order_size", .check = checkOrderSize, .enabled = true }) catch {};
        self.limits.append(.{ .name = "price_deviation", .check = checkPriceDeviation, .enabled = true }) catch {};
    }
    
    pub fn validateOrder(self: *RiskManager, request: OrderRequest) RiskCheckResult {
        // 每日重置检查
        self.checkDailyReset();
        
        // 运行所有检查
        for (self.limits.items) |limit| {
            if (!limit.enabled) continue;
            
            const result = limit.check(self, request);
            switch (result) {
                .rejected => |reason| {
                    std.log.warn("Order rejected by {s}: {s}", .{ limit.name, reason });
                    return result;
                },
                .warning => |msg| {
                    std.log.warn("Risk warning from {s}: {s}", .{ limit.name, msg });
                },
                .passed => {},
            }
        }
        
        return .passed;
    }
    
    fn checkDailyLoss(self: *RiskManager, request: OrderRequest) RiskCheckResult {
        if (self.daily_pnl.cmp(self.config.max_daily_loss.negate()) == .lt) {
            return .{ .rejected = "Daily loss limit exceeded" };
        }
        return .passed;
    }
    
    fn checkPositionSize(self: *RiskManager, request: OrderRequest) RiskCheckResult {
        const projected = self.open_positions_value.add(
            request.amount.mul(request.price orelse Decimal.ZERO)
        );
        
        if (projected.cmp(self.config.max_total_exposure) == .gt) {
            return .{ .rejected = "Total exposure limit exceeded" };
        }
        return .passed;
    }
    
    fn checkPriceDeviation(self: *RiskManager, request: OrderRequest) RiskCheckResult {
        // 检查订单价格是否偏离市价太多
        // ...
        return .passed;
    }
    
    pub fn recordTrade(self: *RiskManager, trade: Trade) void {
        self.daily_trades += 1;
        self.daily_volume = self.daily_volume.add(trade.amount.mul(trade.price));
        // 更新 PnL...
    }
    
    fn checkDailyReset(self: *RiskManager) void {
        const now = std.time.milliTimestamp();
        const day_ms = 24 * 60 * 60 * 1000;
        
        if (now - self.last_reset > day_ms) {
            self.daily_pnl = Decimal.ZERO;
            self.daily_volume = Decimal.ZERO;
            self.daily_trades = 0;
            self.last_reset = now;
        }
    }
};

// 紧急停止
pub const KillSwitch = struct {
    active: std.atomic.Value(bool),
    reason: ?[]const u8,
    triggered_at: ?i64,
    
    pub fn init() KillSwitch {
        return .{
            .active = std.atomic.Value(bool).init(false),
            .reason = null,
            .triggered_at = null,
        };
    }
    
    pub fn trigger(self: *KillSwitch, reason: []const u8) void {
        self.active.store(true, .seq_cst);
        self.reason = reason;
        self.triggered_at = std.time.milliTimestamp();
        
        std.log.err("KILL SWITCH TRIGGERED: {s}", .{reason});
    }
    
    pub fn isActive(self: *KillSwitch) bool {
        return self.active.load(.seq_cst);
    }
    
    pub fn reset(self: *KillSwitch) void {
        self.active.store(false, .seq_cst);
        self.reason = null;
        self.triggered_at = null;
    }
};
```

## 6.3 监控与告警

```zig
// src/monitoring/monitor.zig

pub const Monitor = struct {
    allocator: std.mem.Allocator,
    metrics: Metrics,
    alerter: Alerter,
    health_checker: HealthChecker,
    
    pub const Metrics = struct {
        // 性能指标
        orders_per_second: f64,
        avg_latency_ms: f64,
        p99_latency_ms: f64,
        
        // 交易指标
        total_pnl: Decimal,
        unrealized_pnl: Decimal,
        win_rate: f64,
        
        // 系统指标
        memory_usage: u64,
        cpu_usage: f64,
        ws_reconnects: u32,
        
        // 错误统计
        errors: std.StringHashMap(u64),
        
        pub fn toPrometheus(self: *Metrics) []const u8 {
            // 生成 Prometheus 格式指标
        }
    };
    
    pub fn startServer(self: *Monitor, port: u16) !void {
        // 启动 HTTP 服务器暴露指标
        const server = try std.http.Server.init(self.allocator, port);
        
        server.route("/metrics", self.handleMetrics);
        server.route("/health", self.handleHealth);
        
        try server.listen();
    }
    
    fn handleMetrics(self: *Monitor, request: *Request, response: *Response) void {
        const metrics_text = self.metrics.toPrometheus();
        response.setContentType("text/plain");
        response.write(metrics_text);
    }
};

pub const Alerter = struct {
    channels: std.ArrayList(AlertChannel),
    rules: std.ArrayList(AlertRule),
    
    pub const AlertChannel = union(enum) {
        telegram: TelegramConfig,
        discord: DiscordConfig,
        email: EmailConfig,
        webhook: WebhookConfig,
    };
    
    pub const AlertRule = struct {
        name: []const u8,
        condition: *const fn(*Metrics) bool,
        severity: Severity,
        cooldown: i64,  // ms
        last_triggered: i64,
        
        pub const Severity = enum { info, warning, critical };
    };
    
    pub fn check(self: *Alerter, metrics: *Metrics) void {
        const now = std.time.milliTimestamp();
        
        for (self.rules.items) |*rule| {
            if (rule.condition(metrics)) {
                if (now - rule.last_triggered > rule.cooldown) {
                    self.sendAlert(rule, metrics);
                    rule.last_triggered = now;
                }
            }
        }
    }
    
    fn sendAlert(self: *Alerter, rule: *AlertRule, metrics: *Metrics) void {
        const message = std.fmt.allocPrint(
            self.allocator,
            "[{s}] {s}",
            .{ @tagName(rule.severity), rule.name }
        ) catch return;
        
        for (self.channels.items) |channel| {
            switch (channel) {
                .telegram => |config| self.sendTelegram(config, message),
                .discord => |config| self.sendDiscord(config, message),
                // ...
            }
        }
    }
};
```

## 6.4 REST API

```zig
// src/api/server.zig

pub const APIServer = struct {
    allocator: std.mem.Allocator,
    engine: *TradingEngine,
    server: std.http.Server,
    
    pub fn init(allocator: std.mem.Allocator, engine: *TradingEngine, port: u16) !APIServer {
        var api = APIServer{
            .allocator = allocator,
            .engine = engine,
            .server = try std.http.Server.init(allocator, port),
        };
        
        // 注册路由
        api.server.route("GET", "/api/v1/status", api.getStatus);
        api.server.route("GET", "/api/v1/balance", api.getBalance);
        api.server.route("GET", "/api/v1/positions", api.getPositions);
        api.server.route("GET", "/api/v1/orders", api.getOrders);
        api.server.route("POST", "/api/v1/orders", api.createOrder);
        api.server.route("DELETE", "/api/v1/orders/:id", api.cancelOrder);
        api.server.route("GET", "/api/v1/strategies", api.getStrategies);
        api.server.route("POST", "/api/v1/strategies/:name/start", api.startStrategy);
        api.server.route("POST", "/api/v1/strategies/:name/stop", api.stopStrategy);
        api.server.route("GET", "/api/v1/performance", api.getPerformance);
        
        return api;
    }
    
    fn getStatus(self: *APIServer, req: *Request, res: *Response) void {
        const status = .{
            .status = "running",
            .uptime = self.engine.getUptime(),
            .strategies = self.engine.getActiveStrategies(),
            .connected_exchanges = self.engine.getConnectedExchanges(),
        };
        
        res.json(status);
    }
    
    fn createOrder(self: *APIServer, req: *Request, res: *Response) void {
        const body = req.json(OrderRequest) catch {
            res.status(400).json(.{ .error = "Invalid request body" });
            return;
        };
        
        const order = self.engine.submitOrder(body) catch |err| {
            res.status(500).json(.{ .error = @errorName(err) });
            return;
        };
        
        res.status(201).json(order);
    }
    
    // ... 其他处理器
};
```

---

# Phase 7: 高级特性 (持续迭代)

## 7.1 计划功能

### 机器学习集成

```zig
// src/ml/predictor.zig
pub const MLPredictor = struct {
    // 加载 ONNX 模型进行价格预测
    // 特征工程
    // 在线学习
};
```

### 多策略协调

```zig
// src/strategy/portfolio.zig
pub const StrategyPortfolio = struct {
    // 多策略资金分配
    // 策略间相关性管理
    // 动态权重调整
};
```

### 高级订单类型

```zig
// src/order/advanced.zig
pub const AdvancedOrders = struct {
    // TWAP (时间加权平均价格)
    // VWAP (成交量加权平均价格)
    // 冰山订单
    // 条件单链
};
```

### 模拟交易

```zig
// src/exchange/paper.zig
pub const PaperExchange = struct {
    // 完整的纸上交易环境
    // 延迟模拟
    // 订单簿模拟
};
```

---

# 📅 时间线估算

| Phase | 预计时间 | 累计时间 |
|-------|---------|---------|
| Phase 0: 基础设施 | 2-3 周 | 2-3 周 |
| Phase 1: MVP | 3-4 周 | 5-7 周 |
| Phase 2: 交易引擎 | 4-5 周 | 9-12 周 |
| Phase 3: 策略框架 | 4-5 周 | 13-17 周 |
| Phase 4: 回测系统 | 4-5 周 | 17-22 周 |
| Phase 5: 做市套利 | 5-6 周 | 22-28 周 |
| Phase 6: 生产功能 | 4-5 周 | 26-33 周 |
| Phase 7: 高级特性 | 持续 | - |

**总计：约 6-8 个月完成核心功能**

---

# 🚀 下一步行动

1. **立即开始**：创建项目结构，实现 `Decimal` 类型
2. **本周目标**：完成 HTTP 客户端封装，能调用 Binance API
3. **本月目标**：完成 Phase 1 MVP

---

# 📚 参考资源

- [Hummingbot 源码](https://github.com/hummingbot/hummingbot)
- [Freqtrade 源码](https://github.com/freqtrade/freqtrade)
- [Binance API 文档](https://binance-docs.github.io/apidocs/)
- [Zig 标准库文档](https://ziglang.org/documentation/master/std/)

---

*Last updated: 2025-01*
