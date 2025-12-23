# Story: Hyperliquid WebSocket 实时数据流

**ID**: `STORY-007`
**版本**: `v0.2`
**创建日期**: 2025-12-23
**状态**: 📋 计划中
**优先级**: P0 (必须)
**预计工时**: 4 天

---

## 📋 需求描述

### 用户故事
作为**量化交易开发者**，我希望**通过 WebSocket 接收 Hyperliquid 的实时数据流**，以便**及时获取市场变化和账户更新**。

### 背景
量化交易需要实时数据流来：
- 维护本地订单簿状态
- 监控市场价格变化
- 接收交易执行通知
- 跟踪账户余额和仓位变化

Hyperliquid 提供 WebSocket API 支持多种订阅频道，延迟极低（< 10ms）。

### 范围
- **包含**:
  - WebSocket 连接管理（连接、断线重连）
  - 订单簿频道订阅（L2 Book）
  - 交易频道订阅（Trades）
  - 用户订单更新频道（User Events）
  - 账户状态更新频道（User Fills）
  - 消息解析和分发
  - 心跳机制

- **不包含**:
  - 订单簿维护逻辑（见 Story 008）
  - 订单状态管理（见 Story 010）
  - 数据持久化

---

## 🎯 验收标准

- [ ] WebSocket 连接成功建立
- [ ] 支持订阅所有核心频道（订单簿、交易、用户事件）
- [ ] 消息解析正确，数据完整
- [ ] 断线自动重连，重连后自动重新订阅
- [ ] 心跳机制正常工作，连接保持稳定
- [ ] 消息回调机制清晰，便于上层使用
- [ ] 所有测试用例通过
- [ ] 连接稳定性 > 99.5%

---

## 🔧 技术设计

### 架构概览

```
src/exchange/hyperliquid/
├── websocket.zig         # WebSocket 客户端核心
├── ws_types.zig          # WebSocket 消息类型
├── subscription.zig      # 订阅管理器
├── message_handler.zig   # 消息处理器
└── websocket_test.zig    # 测试
```

### 核心数据结构

#### 1. WebSocket 客户端

```zig
// src/exchange/hyperliquid/websocket.zig

const std = @import("std");
const ws = @import("ws"); // 使用 websocket.zig 库
const Logger = @import("../../core/logger.zig").Logger;
const Error = @import("../../core/error.zig").Error;

pub const HyperliquidWSConfig = struct {
    ws_url: []const u8,
    reconnect_interval_ms: u64,
    max_reconnect_attempts: u32,
    ping_interval_ms: u64,

    pub const DEFAULT_WS_URL = "wss://api.hyperliquid.xyz/ws";
    pub const DEFAULT_TESTNET_WS_URL = "wss://api.hyperliquid-testnet.xyz/ws";
};

pub const MessageCallback = *const fn (msg: Message) void;

pub const HyperliquidWS = struct {
    allocator: std.mem.Allocator,
    config: HyperliquidWSConfig,
    client: ws.Client,
    subscription_manager: SubscriptionManager,
    message_handler: MessageHandler,
    logger: Logger,

    // 连接状态
    connected: std.atomic.Value(bool),
    reconnecting: std.atomic.Value(bool),

    // 回调
    on_message: ?MessageCallback,
    on_error: ?*const fn (err: Error) void,
    on_connect: ?*const fn () void,
    on_disconnect: ?*const fn () void,

    pub fn init(
        allocator: std.mem.Allocator,
        config: HyperliquidWSConfig,
        logger: Logger,
    ) !HyperliquidWS {
        return .{
            .allocator = allocator,
            .config = config,
            .client = undefined, // 将在 connect() 中初始化
            .subscription_manager = SubscriptionManager.init(allocator),
            .message_handler = MessageHandler.init(allocator),
            .logger = logger,
            .connected = std.atomic.Value(bool).init(false),
            .reconnecting = std.atomic.Value(bool).init(false),
            .on_message = null,
            .on_error = null,
            .on_connect = null,
            .on_disconnect = null,
        };
    }

    pub fn deinit(self: *HyperliquidWS) void {
        self.disconnect();
        self.subscription_manager.deinit();
        self.message_handler.deinit();
    }

    /// 连接到 WebSocket 服务器
    pub fn connect(self: *HyperliquidWS) !void {
        self.logger.info("Connecting to WebSocket: {s}", .{self.config.ws_url});

        self.client = try ws.Client.init(self.allocator, .{
            .url = self.config.ws_url,
        });

        try self.client.connect();
        self.connected.store(true, .release);

        self.logger.info("WebSocket connected successfully", .{});

        if (self.on_connect) |callback| {
            callback();
        }

        // 启动消息接收循环
        try self.startReceiveLoop();

        // 启动心跳
        try self.startPingLoop();
    }

    /// 断开连接
    pub fn disconnect(self: *HyperliquidWS) void {
        if (!self.connected.load(.acquire)) return;

        self.logger.info("Disconnecting WebSocket...", .{});
        self.connected.store(false, .release);
        self.client.close();

        if (self.on_disconnect) |callback| {
            callback();
        }
    }

    /// 订阅频道
    pub fn subscribe(self: *HyperliquidWS, subscription: Subscription) !void {
        try self.subscription_manager.add(subscription);

        const msg = try subscription.toJSON(self.allocator);
        defer self.allocator.free(msg);

        try self.client.send(msg);

        self.logger.debug("Subscribed to: {s}", .{subscription.channel});
    }

    /// 取消订阅
    pub fn unsubscribe(self: *HyperliquidWS, subscription: Subscription) !void {
        try self.subscription_manager.remove(subscription);

        const msg = try subscription.toUnsubscribeJSON(self.allocator);
        defer self.allocator.free(msg);

        try self.client.send(msg);

        self.logger.debug("Unsubscribed from: {s}", .{subscription.channel});
    }

    /// 消息接收循环
    fn startReceiveLoop(self: *HyperliquidWS) !void {
        const thread = try std.Thread.spawn(.{}, receiveLoop, .{self});
        thread.detach();
    }

    fn receiveLoop(self: *HyperliquidWS) void {
        while (self.connected.load(.acquire)) {
            const msg = self.client.receive() catch |err| {
                self.logger.err("Failed to receive message: {}", .{err});
                self.handleConnectionError(err);
                continue;
            };
            defer self.allocator.free(msg);

            // 解析消息
            const parsed = self.message_handler.parse(msg) catch |err| {
                self.logger.warn("Failed to parse message: {}", .{err});
                continue;
            };

            // 分发消息
            if (self.on_message) |callback| {
                callback(parsed);
            }
        }
    }

    /// 心跳循环
    fn startPingLoop(self: *HyperliquidWS) !void {
        const thread = try std.Thread.spawn(.{}, pingLoop, .{self});
        thread.detach();
    }

    fn pingLoop(self: *HyperliquidWS) void {
        while (self.connected.load(.acquire)) {
            std.time.sleep(self.config.ping_interval_ms * std.time.ns_per_ms);

            self.client.ping() catch |err| {
                self.logger.warn("Ping failed: {}", .{err});
                self.handleConnectionError(err);
            };
        }
    }

    /// 处理连接错误（自动重连）
    fn handleConnectionError(self: *HyperliquidWS, err: anytype) void {
        _ = err;

        if (self.reconnecting.load(.acquire)) return;

        self.reconnecting.store(true, .release);
        defer self.reconnecting.store(false, .release);

        self.logger.warn("Connection lost, attempting to reconnect...", .{});

        var attempts: u32 = 0;
        while (attempts < self.config.max_reconnect_attempts) : (attempts += 1) {
            std.time.sleep(self.config.reconnect_interval_ms * std.time.ns_per_ms);

            self.connect() catch |reconnect_err| {
                self.logger.warn("Reconnect attempt {} failed: {}", .{
                    attempts + 1, reconnect_err,
                });
                continue;
            };

            // 重新订阅所有频道
            self.resubscribeAll() catch |sub_err| {
                self.logger.err("Failed to resubscribe: {}", .{sub_err});
                continue;
            };

            self.logger.info("Reconnected successfully", .{});
            return;
        }

        self.logger.err("Max reconnect attempts reached, giving up", .{});
        if (self.on_error) |callback| {
            callback(Error.ConnectionFailed);
        }
    }

    /// 重新订阅所有频道
    fn resubscribeAll(self: *HyperliquidWS) !void {
        const subs = try self.subscription_manager.getAll();
        defer self.allocator.free(subs);

        for (subs) |sub| {
            try self.subscribe(sub);
        }
    }
};
```

#### 2. 订阅管理器

```zig
// src/exchange/hyperliquid/subscription.zig

const std = @import("std");

pub const ChannelType = enum {
    l2_book,        // 订单簿更新
    trades,         // 交易数据
    user_events,    // 用户订单事件
    user_fills,     // 用户成交事件
    all_mids,       // 所有币种的中间价
};

pub const Subscription = struct {
    channel: ChannelType,
    coin: ?[]const u8, // 某些频道需要指定币种
    user: ?[]const u8, // 用户频道需要地址

    /// 生成订阅 JSON
    pub fn toJSON(self: Subscription, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        const writer = buffer.writer();

        try writer.writeAll("{\"method\":\"subscribe\",\"subscription\":{");

        switch (self.channel) {
            .l2_book => {
                try writer.print("\"type\":\"l2Book\",\"coin\":\"{s}\"", .{
                    self.coin.?,
                });
            },
            .trades => {
                try writer.print("\"type\":\"trades\",\"coin\":\"{s}\"", .{
                    self.coin.?,
                });
            },
            .user_events => {
                try writer.print("\"type\":\"userEvents\",\"user\":\"{s}\"", .{
                    self.user.?,
                });
            },
            .user_fills => {
                try writer.print("\"type\":\"userFills\",\"user\":\"{s}\"", .{
                    self.user.?,
                });
            },
            .all_mids => {
                try writer.writeAll("\"type\":\"allMids\"");
            },
        }

        try writer.writeAll("}}");

        return buffer.toOwnedSlice();
    }

    /// 生成取消订阅 JSON
    pub fn toUnsubscribeJSON(self: Subscription, allocator: std.mem.Allocator) ![]u8 {
        // 类似 toJSON，但 method 为 "unsubscribe"
        // ...
    }
};

pub const SubscriptionManager = struct {
    allocator: std.mem.Allocator,
    subscriptions: std.ArrayList(Subscription),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) SubscriptionManager {
        return .{
            .allocator = allocator,
            .subscriptions = std.ArrayList(Subscription).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *SubscriptionManager) void {
        self.subscriptions.deinit();
    }

    pub fn add(self: *SubscriptionManager, sub: Subscription) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.subscriptions.append(sub);
    }

    pub fn remove(self: *SubscriptionManager, sub: Subscription) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.subscriptions.items, 0..) |s, i| {
            if (std.mem.eql(u8, @tagName(s.channel), @tagName(sub.channel))) {
                _ = self.subscriptions.swapRemove(i);
                return;
            }
        }
    }

    pub fn getAll(self: *SubscriptionManager) ![]Subscription {
        self.mutex.lock();
        defer self.mutex.unlock();

        return try self.allocator.dupe(Subscription, self.subscriptions.items);
    }
};
```

#### 3. 消息类型

```zig
// src/exchange/hyperliquid/ws_types.zig

const std = @import("std");
const Decimal = @import("../../core/decimal.zig").Decimal;
const Timestamp = @import("../../core/time.zig").Timestamp;

pub const Message = union(enum) {
    l2_book: L2BookUpdate,
    trade: Trade,
    user_event: UserEvent,
    user_fill: UserFill,
    all_mids: AllMids,
    error_msg: ErrorMessage,
    pong: void,
};

/// L2 订单簿更新
pub const L2BookUpdate = struct {
    coin: []const u8,
    time: Timestamp,
    levels: [2][]Level, // [bids, asks]

    pub const Level = struct {
        px: Decimal,
        sz: Decimal,
        n: u32, // 订单数量
    };
};

/// 交易数据
pub const Trade = struct {
    coin: []const u8,
    side: []const u8, // "A" (ask) or "B" (bid)
    px: Decimal,
    sz: Decimal,
    time: Timestamp,
    hash: []const u8,
};

/// 用户订单事件
pub const UserEvent = struct {
    user: []const u8,
    event_type: EventType,
    order: ?OrderUpdate,

    pub const EventType = enum {
        order_placed,
        order_cancelled,
        order_filled,
        order_rejected,
    };

    pub const OrderUpdate = struct {
        oid: u64,
        coin: []const u8,
        side: []const u8,
        px: Decimal,
        sz: Decimal,
        timestamp: Timestamp,
    };
};

/// 用户成交事件
pub const UserFill = struct {
    user: []const u8,
    coin: []const u8,
    px: Decimal,
    sz: Decimal,
    side: []const u8,
    time: Timestamp,
    start_position: Decimal,
    dir: []const u8, // "Open Long", "Close Short", etc.
    closed_pnl: Decimal,
    hash: []const u8,
    oid: u64,
    crossed: bool,
    fee: Decimal,
};

/// 所有币种中间价
pub const AllMids = struct {
    mids: std.StringHashMap(Decimal),
};

/// 错误消息
pub const ErrorMessage = struct {
    error_type: []const u8,
    message: []const u8,
};
```

#### 4. 消息处理器

```zig
// src/exchange/hyperliquid/message_handler.zig

const std = @import("std");
const Message = @import("ws_types.zig").Message;

pub const MessageHandler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MessageHandler {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *MessageHandler) void {
        _ = self;
    }

    /// 解析 WebSocket 消息
    pub fn parse(self: *MessageHandler, raw: []const u8) !Message {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            raw,
            .{},
        );
        defer parsed.deinit();

        const root = parsed.value.object;
        const channel = root.get("channel").?.string;

        if (std.mem.eql(u8, channel, "l2Book")) {
            return Message{ .l2_book = try parseL2Book(self.allocator, root) };
        } else if (std.mem.eql(u8, channel, "trades")) {
            return Message{ .trade = try parseTrade(self.allocator, root) };
        } else if (std.mem.eql(u8, channel, "userEvents")) {
            return Message{ .user_event = try parseUserEvent(self.allocator, root) };
        } else if (std.mem.eql(u8, channel, "userFills")) {
            return Message{ .user_fill = try parseUserFill(self.allocator, root) };
        } else if (std.mem.eql(u8, channel, "allMids")) {
            return Message{ .all_mids = try parseAllMids(self.allocator, root) };
        } else if (std.mem.eql(u8, channel, "pong")) {
            return Message{ .pong = {} };
        } else {
            return Message{ .error_msg = .{
                .error_type = "unknown_channel",
                .message = channel,
            } };
        }
    }

    fn parseL2Book(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !L2BookUpdate {
        // 实现解析逻辑
        // ...
    }

    // 其他解析函数...
};
```

---

## 📝 任务分解

### Phase 1: WebSocket 基础设施 📋
- [ ] 任务 1.1: 选择并集成 WebSocket 库（websocket.zig）
- [ ] 任务 1.2: 实现 WebSocket 客户端基础类
- [ ] 任务 1.3: 实现连接管理（连接、断开）
- [ ] 任务 1.4: 实现断线重连逻辑
- [ ] 任务 1.5: 实现心跳机制

### Phase 2: 订阅管理 📋
- [ ] 任务 2.1: 定义订阅类型和数据结构
- [ ] 任务 2.2: 实现订阅管理器
- [ ] 任务 2.3: 实现订阅/取消订阅功能
- [ ] 任务 2.4: 实现重连后自动重新订阅

### Phase 3: 消息处理 📋
- [ ] 任务 3.1: 定义所有 WebSocket 消息类型
- [ ] 任务 3.2: 实现消息解析器
- [ ] 任务 3.3: 实现消息分发机制（回调）
- [ ] 任务 3.4: 实现错误消息处理

### Phase 4: 测试与文档 📋
- [ ] 任务 4.1: 编写单元测试（模拟 WebSocket）
- [ ] 任务 4.2: 编写集成测试（连接测试网）
- [ ] 任务 4.3: 稳定性测试（长时间连接）
- [ ] 任务 4.4: 重连测试（模拟断线）
- [ ] 任务 4.5: 更新文档
- [ ] 任务 4.6: 代码审查

---

## 🧪 测试策略

### 单元测试

```zig
test "Subscription: generate JSON" {
    const sub = Subscription{
        .channel = .l2_book,
        .coin = "ETH",
        .user = null,
    };

    const json = try sub.toJSON(testing.allocator);
    defer testing.allocator.free(json);

    try testing.expectEqualStrings(
        "{\"method\":\"subscribe\",\"subscription\":{\"type\":\"l2Book\",\"coin\":\"ETH\"}}",
        json,
    );
}

test "MessageHandler: parse L2 book update" {
    const raw_msg =
        \\{"channel":"l2Book","data":{"coin":"ETH","time":1640000000000,"levels":[[],[]]}}
    ;

    var handler = MessageHandler.init(testing.allocator);
    defer handler.deinit();

    const msg = try handler.parse(raw_msg);

    try testing.expect(msg == .l2_book);
    try testing.expectEqualStrings("ETH", msg.l2_book.coin);
}
```

### 集成测试

```zig
test "Integration: connect and subscribe" {
    const config = HyperliquidWSConfig{
        .ws_url = HyperliquidWSConfig.DEFAULT_TESTNET_WS_URL,
        .reconnect_interval_ms = 1000,
        .max_reconnect_attempts = 3,
        .ping_interval_ms = 30000,
    };

    var ws_client = try HyperliquidWS.init(testing.allocator, config, logger);
    defer ws_client.deinit();

    // 连接
    try ws_client.connect();
    defer ws_client.disconnect();

    // 订阅订单簿
    try ws_client.subscribe(.{
        .channel = .l2_book,
        .coin = "ETH",
        .user = null,
    });

    // 等待消息
    std.time.sleep(5 * std.time.ns_per_s);

    try testing.expect(ws_client.connected.load(.acquire));
}
```

---

## 📚 相关文档

### 设计文档
- [ ] `docs/features/hyperliquid-connector/websocket.md` - WebSocket 使用指南
- [ ] `docs/features/hyperliquid-connector/subscriptions.md` - 订阅频道说明
- [ ] `docs/features/hyperliquid-connector/message-types.md` - 消息类型参考

### 参考资料
- [Hyperliquid WebSocket API](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket)
- [websocket.zig Library](https://github.com/karlseguin/websocket.zig)

---

## 🔗 依赖关系

### 前置条件
- [x] Story 001: Decimal 类型
- [x] Story 002: Time Utils
- [x] Story 003: Error System
- [x] Story 004: Logger
- [ ] Story 006: Hyperliquid HTTP 客户端

### 被依赖
- Story 008: 订单簿维护（使用 L2 订单簿数据流）
- Story 010: 订单管理器（使用用户订单事件）
- Story 011: 仓位追踪器（使用用户成交事件）

---

## ⚠️ 风险与挑战

### 已识别风险
1. **连接稳定性**: WebSocket 可能因网络波动断线
   - **影响**: 高
   - **缓解措施**: 完善的断线重连机制

2. **消息丢失**: 重连期间可能错过消息
   - **影响**: 中
   - **缓解措施**: 重连后重新获取快照数据

3. **消息顺序**: 网络延迟可能导致消息乱序
   - **影响**: 中
   - **缓解措施**: 使用时间戳排序

### 技术挑战
1. **WebSocket 库选择**: Zig 的 WebSocket 库生态较少
   - **解决方案**: 使用 websocket.zig，或基于 std.http 自己实现

2. **并发处理**: 接收循环和心跳循环需要并发
   - **解决方案**: 使用线程，注意线程安全

---

## 📊 进度追踪

### 时间线
- 开始日期: 待定
- 预计完成: 待定
- 实际完成: 待定

---

## ✅ 验收检查清单

- [ ] 所有验收标准已满足
- [ ] 所有任务已完成
- [ ] 单元测试通过
- [ ] 集成测试通过
- [ ] 稳定性测试通过（24 小时连接）
- [ ] 重连机制正常工作
- [ ] 代码已审查
- [ ] 文档已更新

---

## 📸 演示

### 使用示例

```zig
const std = @import("std");
const HyperliquidWS = @import("exchange/hyperliquid/websocket.zig").HyperliquidWS;
const Subscription = @import("exchange/hyperliquid/subscription.zig").Subscription;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = HyperliquidWS.Config{
        .ws_url = HyperliquidWS.Config.DEFAULT_TESTNET_WS_URL,
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

    // 订阅 ETH 订单簿
    try ws.subscribe(.{
        .channel = .l2_book,
        .coin = "ETH",
        .user = null,
    });

    // 订阅 ETH 交易数据
    try ws.subscribe(.{
        .channel = .trades,
        .coin = "ETH",
        .user = null,
    });

    // 保持运行
    while (true) {
        std.time.sleep(std.time.ns_per_s);
    }
}

fn handleMessage(msg: Message) void {
    switch (msg) {
        .l2_book => |book| {
            std.debug.print("Order Book Update: {s}\n", .{book.coin});
            if (book.levels[0].len > 0) {
                std.debug.print("  Best Bid: {} @ {}\n", .{
                    book.levels[0][0].sz.toFloat(),
                    book.levels[0][0].px.toFloat(),
                });
            }
        },
        .trade => |trade| {
            std.debug.print("Trade: {s} {} @ {}\n", .{
                trade.side, trade.sz.toFloat(), trade.px.toFloat(),
            });
        },
        else => {},
    }
}

fn handleConnect() void {
    std.debug.print("WebSocket connected!\n", .{});
}

fn handleDisconnect() void {
    std.debug.print("WebSocket disconnected!\n", .{});
}
```

---

## 💡 未来改进

- [ ] 支持消息压缩（减少带宽）
- [ ] 实现消息缓冲队列
- [ ] 支持多个 WebSocket 连接（负载均衡）
- [ ] 添加消息统计（延迟、吞吐量）
- [ ] 实现智能重连（指数退避）

---

*Last updated: 2025-12-23*
*Assignee: TBD*
*Status: 📋 Planning*
