# Story 029: HyperliquidDataProvider

**版本**: v0.6.0
**状态**: 规划中
**优先级**: P0
**预计时间**: 4-5 天
**前置条件**: v0.5.0 DataEngine 完成

---

## 目标

实现 `IDataProvider` 接口的 Hyperliquid 适配器，将 Hyperliquid WebSocket 实时数据流接入 v0.5.0 事件驱动架构，为实盘交易和 Paper Trading 提供数据源。

---

## 背景

### v0.5.0 架构回顾

```zig
// IDataProvider 接口定义 (v0.5.0)
pub const IDataProvider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        start: *const fn (*anyopaque) anyerror!void,
        stop: *const fn (*anyopaque) void,
        subscribe: *const fn (*anyopaque, []const u8) anyerror!void,
        unsubscribe: *const fn (*anyopaque, []const u8) void,
        isConnected: *const fn (*anyopaque) bool,
    };
};
```

### Hyperliquid WebSocket API

```json
// 订阅请求
{"method": "subscribe", "subscription": {"type": "allMids"}}
{"method": "subscribe", "subscription": {"type": "l2Book", "coin": "BTC"}}
{"method": "subscribe", "subscription": {"type": "trades", "coin": "ETH"}}

// 数据推送
{"channel": "allMids", "data": {"mids": {"BTC": "50000.5", "ETH": "3000.2"}}}
{"channel": "l2Book", "data": {"coin": "BTC", "levels": [...]}}
{"channel": "trades", "data": {"coin": "ETH", "trades": [...]}}
```

---

## 核心设计

### 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                 HyperliquidDataProvider                      │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │  WebSocketClient │    │  MessageParser  │                │
│  │  (连接管理)      │    │  (JSON解析)     │                │
│  └────────┬────────┘    └────────┬────────┘                │
│           │                      │                          │
│           ↓                      ↓                          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              SubscriptionManager                      │  │
│  │         (订阅状态管理 + 重连恢复)                     │  │
│  └──────────────────────────────────────────────────────┘  │
│           │                                                 │
│           ↓                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │     Cache       │    │   MessageBus    │                │
│  │   (数据缓存)    │    │   (事件发布)    │                │
│  └─────────────────┘    └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### 核心接口

```zig
pub const HyperliquidDataProvider = struct {
    allocator: Allocator,
    config: Config,
    ws_client: WebSocketClient,
    subscriptions: SubscriptionManager,
    message_bus: *MessageBus,
    cache: *Cache,
    connected: std.atomic.Value(bool),

    pub const Config = struct {
        ws_url: []const u8 = "wss://api.hyperliquid.xyz/ws",
        testnet: bool = false,
        reconnect_delay_ms: u32 = 1000,
        max_reconnect_attempts: u32 = 10,
        ping_interval_ms: u32 = 30000,
    };

    // IDataProvider VTable 实现
    pub const vtable = IDataProvider.VTable{
        .start = start,
        .stop = stop,
        .subscribe = subscribe,
        .unsubscribe = unsubscribe,
        .isConnected = isConnected,
    };

    /// 获取 IDataProvider 接口
    pub fn asProvider(self: *HyperliquidDataProvider) IDataProvider {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// 初始化
    pub fn init(
        allocator: Allocator,
        message_bus: *MessageBus,
        cache: *Cache,
        config: Config,
    ) !HyperliquidDataProvider;

    /// 启动连接
    fn start(ctx: *anyopaque) !void;

    /// 停止连接
    fn stop(ctx: *anyopaque) void;

    /// 订阅交易对
    fn subscribe(ctx: *anyopaque, symbol: []const u8) !void;

    /// 取消订阅
    fn unsubscribe(ctx: *anyopaque, symbol: []const u8) void;

    /// 检查连接状态
    fn isConnected(ctx: *anyopaque) bool;
};
```

---

## 实现细节

### 1. WebSocket 连接管理

```zig
const WebSocketClient = struct {
    allocator: Allocator,
    uri: std.Uri,
    connection: ?std.http.Client.Connection,
    recv_buffer: [65536]u8,

    pub fn connect(self: *WebSocketClient) !void {
        // 1. 建立 TCP 连接
        var client = std.http.Client{ .allocator = self.allocator };
        self.connection = try client.connect(self.uri.host.?, self.uri.port.?);

        // 2. WebSocket 握手
        try self.performHandshake();

        // 3. 启动接收循环
        try self.startReceiveLoop();
    }

    pub fn send(self: *WebSocketClient, message: []const u8) !void {
        // WebSocket 帧封装
        const frame = try encodeFrame(message);
        try self.connection.?.stream.writeAll(frame);
    }

    fn startReceiveLoop(self: *WebSocketClient) !void {
        while (true) {
            const frame = try self.readFrame();
            switch (frame.opcode) {
                .text => self.onMessage(frame.payload),
                .ping => try self.sendPong(frame.payload),
                .close => return,
                else => {},
            }
        }
    }
};
```

### 2. 订阅管理

```zig
const SubscriptionManager = struct {
    subscriptions: std.StringHashMap(SubscriptionState),
    allocator: Allocator,

    pub const SubscriptionState = struct {
        channel: Channel,
        symbol: []const u8,
        subscribed_at: i64,
        last_update: i64,
    };

    pub const Channel = enum {
        allMids,
        l2Book,
        trades,
        candle,
    };

    /// 添加订阅
    pub fn add(self: *SubscriptionManager, channel: Channel, symbol: []const u8) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{
            @tagName(channel),
            symbol,
        });
        try self.subscriptions.put(key, .{
            .channel = channel,
            .symbol = symbol,
            .subscribed_at = std.time.milliTimestamp(),
            .last_update = 0,
        });
    }

    /// 获取所有订阅 (用于重连恢复)
    pub fn getAll(self: *SubscriptionManager) []SubscriptionState {
        return self.subscriptions.values();
    }

    /// 构建订阅消息
    pub fn buildSubscribeMessage(channel: Channel, symbol: []const u8) []const u8 {
        return switch (channel) {
            .allMids => "{\"method\":\"subscribe\",\"subscription\":{\"type\":\"allMids\"}}",
            .l2Book => std.fmt.allocPrint(allocator,
                "{{\"method\":\"subscribe\",\"subscription\":{{\"type\":\"l2Book\",\"coin\":\"{s}\"}}}}",
                .{symbol}),
            .trades => std.fmt.allocPrint(allocator,
                "{{\"method\":\"subscribe\",\"subscription\":{{\"type\":\"trades\",\"coin\":\"{s}\"}}}}",
                .{symbol}),
            .candle => std.fmt.allocPrint(allocator,
                "{{\"method\":\"subscribe\",\"subscription\":{{\"type\":\"candle\",\"coin\":\"{s}\",\"interval\":\"1m\"}}}}",
                .{symbol}),
        };
    }
};
```

### 3. 消息解析与事件发布

```zig
const MessageParser = struct {
    allocator: Allocator,

    pub fn parse(self: *MessageParser, raw: []const u8) !ParsedMessage {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            raw,
            .{},
        );
        defer parsed.deinit();

        const channel = parsed.value.object.get("channel") orelse return error.InvalidMessage;

        return switch (channel.string) {
            "allMids" => self.parseAllMids(parsed.value),
            "l2Book" => self.parseL2Book(parsed.value),
            "trades" => self.parseTrades(parsed.value),
            else => error.UnknownChannel,
        };
    }

    fn parseAllMids(self: *MessageParser, value: std.json.Value) !ParsedMessage {
        const data = value.object.get("data").?.object;
        const mids = data.get("mids").?.object;

        var quotes = std.ArrayList(Quote).init(self.allocator);
        var it = mids.iterator();
        while (it.next()) |entry| {
            const symbol = entry.key_ptr.*;
            const mid_price = try std.fmt.parseFloat(f64, entry.value_ptr.string);
            try quotes.append(.{
                .symbol = symbol,
                .mid = Decimal.fromFloat(mid_price),
                .timestamp = Timestamp.now(),
            });
        }

        return .{ .all_mids = quotes.toOwnedSlice() };
    }

    fn parseL2Book(self: *MessageParser, value: std.json.Value) !ParsedMessage {
        const data = value.object.get("data").?.object;
        const coin = data.get("coin").?.string;
        const levels = data.get("levels").?.array;

        var bids = std.ArrayList(PriceLevel).init(self.allocator);
        var asks = std.ArrayList(PriceLevel).init(self.allocator);

        // 解析 bids 和 asks
        // ...

        return .{
            .orderbook = .{
                .symbol = coin,
                .bids = bids.toOwnedSlice(),
                .asks = asks.toOwnedSlice(),
                .timestamp = Timestamp.now(),
            },
        };
    }
};
```

### 4. 事件发布

```zig
fn publishQuoteEvent(self: *HyperliquidDataProvider, quote: Quote) void {
    // 1. 更新 Cache
    self.cache.updateQuote(.{
        .symbol = quote.symbol,
        .bid = quote.mid,  // 使用 mid 作为近似
        .ask = quote.mid,
        .timestamp = quote.timestamp,
    }) catch |err| {
        log.err("Failed to update cache: {}", .{err});
    };

    // 2. 发布到 MessageBus
    self.message_bus.publish("market_data.quote", .{
        .market_data = .{
            .instrument_id = quote.symbol,
            .bid = quote.mid.toFloat(),
            .ask = quote.mid.toFloat(),
            .timestamp = quote.timestamp.nanos,
        },
    });
}

fn publishOrderbookEvent(self: *HyperliquidDataProvider, book: OrderBook) void {
    // 1. 更新 Cache
    self.cache.updateOrderBook(.{
        .symbol = book.symbol,
        .bids = book.bids,
        .asks = book.asks,
        .timestamp = book.timestamp,
    }) catch |err| {
        log.err("Failed to update orderbook cache: {}", .{err});
    };

    // 2. 发布到 MessageBus
    self.message_bus.publish("market_data.orderbook", .{
        .orderbook_update = .{
            .instrument_id = book.symbol,
            .bids = book.bids,
            .asks = book.asks,
            .timestamp = book.timestamp.nanos,
        },
    });
}
```

### 5. 重连机制

```zig
fn handleDisconnect(self: *HyperliquidDataProvider) void {
    self.connected.store(false, .seq_cst);

    // 发布断开事件
    self.message_bus.publish("system.disconnected", .{
        .system = .{ .message = "WebSocket disconnected" },
    });

    // 尝试重连
    var attempts: u32 = 0;
    while (attempts < self.config.max_reconnect_attempts) : (attempts += 1) {
        std.time.sleep(self.config.reconnect_delay_ms * std.time.ns_per_ms);

        if (self.reconnect()) |_| {
            log.info("Reconnected after {} attempts", .{attempts + 1});
            self.resubscribeAll();
            return;
        } else |err| {
            log.warn("Reconnect attempt {} failed: {}", .{ attempts + 1, err });
        }
    }

    log.err("Failed to reconnect after {} attempts", .{self.config.max_reconnect_attempts});
}

fn resubscribeAll(self: *HyperliquidDataProvider) void {
    for (self.subscriptions.getAll()) |sub| {
        const msg = SubscriptionManager.buildSubscribeMessage(sub.channel, sub.symbol);
        self.ws_client.send(msg) catch |err| {
            log.err("Failed to resubscribe {s}: {}", .{ sub.symbol, err });
        };
    }
}
```

---

## 测试计划

### 单元测试

```zig
test "message parsing: allMids" {
    const raw =
        \\{"channel":"allMids","data":{"mids":{"BTC":"50000.5","ETH":"3000.2"}}}
    ;
    var parser = MessageParser.init(testing.allocator);
    const result = try parser.parse(raw);

    try testing.expectEqual(@as(usize, 2), result.all_mids.len);
}

test "subscription management" {
    var manager = SubscriptionManager.init(testing.allocator);
    try manager.add(.l2Book, "BTC");
    try manager.add(.trades, "ETH");

    try testing.expectEqual(@as(usize, 2), manager.subscriptions.count());
}
```

### 集成测试

```zig
test "integration: connect and subscribe" {
    // 需要网络连接
    if (!std.os.getenv("RUN_NETWORK_TESTS")) return error.SkipTest;

    var bus = MessageBus.init(testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(testing.allocator, &bus, .{});
    defer cache.deinit();

    var provider = try HyperliquidDataProvider.init(
        testing.allocator,
        &bus,
        &cache,
        .{ .testnet = true },
    );
    defer provider.deinit();

    try provider.start();
    try provider.subscribe("BTC");

    // 等待数据
    std.time.sleep(5 * std.time.ns_per_s);

    // 验证收到数据
    try testing.expect(cache.getQuote("BTC") != null);
}
```

---

## 成功指标

| 指标 | 目标 | 说明 |
|------|------|------|
| 连接延迟 | < 500ms | 建立 WebSocket 连接 |
| 数据延迟 | < 10ms | 从收到消息到更新 Cache |
| 重连成功率 | > 99% | 自动重连机制 |
| 订阅恢复 | 100% | 重连后恢复所有订阅 |

---

## 文件结构

```
src/adapters/hyperliquid/
├── mod.zig                     # 模块入口
├── data_provider.zig           # HyperliquidDataProvider
├── websocket_client.zig        # WebSocket 客户端
├── subscription_manager.zig    # 订阅管理
├── message_parser.zig          # 消息解析
└── tests/
    └── data_provider_test.zig  # 测试
```

---

**Story**: 029
**状态**: 规划中
**创建时间**: 2025-12-27
