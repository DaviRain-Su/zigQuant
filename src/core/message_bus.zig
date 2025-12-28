//! MessageBus - 事件驱动消息总线
//!
//! v0.5.0 核心组件，提供三种通信模式：
//! - Pub/Sub: 一对多事件广播
//! - Request/Response: 同步请求-响应
//! - Command: Fire-and-Forget 命令
//!
//! 设计特点：
//! - 单线程执行，避免锁开销
//! - 同步分发，事件立即到达
//! - 类型安全，编译时类型检查
//! - 零拷贝，事件通过引用传递
//! - 支持通配符主题匹配

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Event Types
// ============================================================================

/// 市场数据事件
pub const MarketDataEvent = struct {
    instrument_id: []const u8,
    timestamp: i64,
    bid: ?f64 = null,
    ask: ?f64 = null,
    last: ?f64 = null,
    bid_size: ?f64 = null,
    ask_size: ?f64 = null,
    volume_24h: ?f64 = null,
};

/// 订单簿更新事件
pub const OrderbookEvent = struct {
    instrument_id: []const u8,
    timestamp: i64,
    is_snapshot: bool = false,
    bids: []const PriceLevel = &.{},
    asks: []const PriceLevel = &.{},

    pub const PriceLevel = struct {
        price: f64,
        quantity: f64,
    };
};

/// 交易事件
pub const TradeEvent = struct {
    instrument_id: []const u8,
    timestamp: i64,
    price: f64,
    quantity: f64,
    side: Side,
    trade_id: ?[]const u8 = null,

    pub const Side = enum { buy, sell };
};

/// K线事件
pub const CandleEvent = struct {
    instrument_id: []const u8,
    timestamp: i64,
    timeframe: Timeframe,
    open: f64,
    high: f64,
    low: f64,
    close: f64,
    volume: f64,

    pub const Timeframe = enum { m1, m5, m15, m30, h1, h4, d1, w1 };
};

/// 订单事件
pub const OrderEvent = struct {
    order_id: []const u8,
    client_order_id: ?[]const u8 = null,
    instrument_id: []const u8,
    side: Side,
    order_type: OrderType,
    quantity: f64,
    filled_quantity: f64 = 0,
    price: ?f64 = null,
    status: OrderStatus,
    timestamp: i64,

    pub const Side = enum { buy, sell };
    pub const OrderType = enum { market, limit, stop_market, stop_limit };
    pub const OrderStatus = enum { pending, submitted, accepted, partially_filled, filled, cancelled, rejected };
};

/// 订单拒绝事件
pub const OrderRejectEvent = struct {
    order: OrderEvent,
    reason: []const u8,
    timestamp: i64,
};

/// 订单成交事件
pub const OrderFillEvent = struct {
    order: OrderEvent,
    fill_price: f64,
    fill_quantity: f64,
    commission: f64 = 0,
    timestamp: i64,
};

/// 仓位事件
pub const PositionEvent = struct {
    instrument_id: []const u8,
    side: Side,
    quantity: f64,
    entry_price: f64,
    mark_price: ?f64 = null,
    unrealized_pnl: f64 = 0,
    realized_pnl: f64 = 0,
    timestamp: i64,

    pub const Side = enum { long, short, flat };
};

/// 账户事件
pub const AccountEvent = struct {
    account_id: []const u8,
    balance: f64,
    available: f64,
    margin_used: f64 = 0,
    unrealized_pnl: f64 = 0,
    timestamp: i64,
};

/// Tick 事件 (时钟驱动)
pub const TickEvent = struct {
    timestamp: i64,
    tick_number: u64 = 0,
};

/// 关闭事件
pub const ShutdownEvent = struct {
    reason: Reason,
    message: ?[]const u8 = null,

    pub const Reason = enum { user_request, fatal_error, signal, backtest_complete };
};

/// 配置重载事件
pub const ConfigReloadedEvent = struct {
    config_path: []const u8,
    reload_count: u64,
    timestamp: i64,
};

/// 统一事件类型
pub const Event = union(enum) {
    // 市场数据事件
    market_data: MarketDataEvent,
    orderbook_update: OrderbookEvent,
    trade: TradeEvent,
    candle: CandleEvent,

    // 订单事件
    order_pending: OrderEvent,
    order_submitted: OrderEvent,
    order_accepted: OrderEvent,
    order_rejected: OrderRejectEvent,
    order_filled: OrderFillEvent,
    order_partially_filled: OrderFillEvent,
    order_cancelled: OrderEvent,

    // 仓位事件
    position_opened: PositionEvent,
    position_updated: PositionEvent,
    position_closed: PositionEvent,

    // 账户事件
    account_updated: AccountEvent,

    // 系统事件
    tick: TickEvent,
    shutdown: ShutdownEvent,
    config_reloaded: ConfigReloadedEvent,

    /// 获取事件时间戳
    pub fn getTimestamp(self: Event) i64 {
        return switch (self) {
            .market_data => |e| e.timestamp,
            .orderbook_update => |e| e.timestamp,
            .trade => |e| e.timestamp,
            .candle => |e| e.timestamp,
            .order_pending, .order_submitted, .order_accepted, .order_cancelled => |e| e.timestamp,
            .order_rejected => |e| e.timestamp,
            .order_filled, .order_partially_filled => |e| e.timestamp,
            .position_opened, .position_updated, .position_closed => |e| e.timestamp,
            .account_updated => |e| e.timestamp,
            .tick => |e| e.timestamp,
            .shutdown => std.time.milliTimestamp(),
            .config_reloaded => |e| e.timestamp,
        };
    }

    /// 获取事件类型名称
    pub fn getTypeName(self: Event) []const u8 {
        return @tagName(self);
    }
};

// ============================================================================
// Request/Response Types
// ============================================================================

/// 请求类型
pub const Request = union(enum) {
    /// 验证订单请求
    validate_order: struct {
        instrument_id: []const u8,
        side: OrderEvent.Side,
        quantity: f64,
        price: ?f64 = null,
    },
    /// 提交订单请求
    submit_order: struct {
        instrument_id: []const u8,
        side: OrderEvent.Side,
        order_type: OrderEvent.OrderType,
        quantity: f64,
        price: ?f64 = null,
        client_order_id: ?[]const u8 = null,
    },
    /// 取消订单请求
    cancel_order: struct {
        order_id: []const u8,
    },
    /// 查询订单请求
    query_order: struct {
        order_id: []const u8,
    },
    /// 风控检查请求
    risk_check: struct {
        instrument_id: []const u8,
        side: OrderEvent.Side,
        quantity: f64,
        price: ?f64 = null,
    },
};

/// 响应类型
pub const Response = union(enum) {
    /// 订单验证响应
    order_validated: struct {
        valid: bool,
        reason: ?[]const u8 = null,
    },
    /// 订单提交响应
    order_submitted: struct {
        order_id: []const u8,
        status: OrderEvent.OrderStatus,
    },
    /// 订单取消响应
    order_cancelled: struct {
        order_id: []const u8,
        success: bool,
    },
    /// 订单查询响应
    order_info: struct {
        order: ?OrderEvent,
    },
    /// 风控检查响应
    risk_result: struct {
        passed: bool,
        reason: ?[]const u8 = null,
    },
    /// 错误响应
    error_response: struct {
        code: u32,
        message: []const u8,
    },
};

/// 命令类型
pub const Command = union(enum) {
    /// 提交订单命令
    submit_order: struct {
        instrument_id: []const u8,
        side: OrderEvent.Side,
        order_type: OrderEvent.OrderType,
        quantity: f64,
        price: ?f64 = null,
    },
    /// 取消订单命令
    cancel_order: struct {
        order_id: []const u8,
    },
    /// 取消所有订单命令
    cancel_all_orders: struct {
        instrument_id: ?[]const u8 = null,
    },
};

// ============================================================================
// MessageBus Core
// ============================================================================

pub const MessageBusError = error{
    EndpointNotFound,
    EndpointAlreadyRegistered,
    HandlerError,
    OutOfMemory,
    TopicTooLong,
};

/// MessageBus - 事件驱动消息总线
pub const MessageBus = struct {
    allocator: Allocator,

    /// 精确匹配订阅 (优化性能)
    exact_subscribers: std.StringHashMap(HandlerList),

    /// 通配符订阅
    wildcard_subscribers: WildcardList,

    /// Request/Response 端点注册表
    endpoints: std.StringHashMap(RequestHandler),

    /// Command 处理器
    command_handler: ?CommandHandler,

    /// 统计信息
    stats: Stats,

    pub const Handler = *const fn (Event) void;
    pub const RequestHandler = *const fn (Request) MessageBusError!Response;
    pub const CommandHandler = *const fn (Command) void;

    const HandlerList = std.ArrayList(Handler);
    const WildcardList = std.ArrayList(WildcardSubscription);

    const WildcardSubscription = struct {
        pattern: []const u8,
        handler: Handler,
    };

    pub const Stats = struct {
        events_published: u64 = 0,
        requests_handled: u64 = 0,
        commands_sent: u64 = 0,
        subscribers_count: usize = 0,
        endpoints_count: usize = 0,
    };

    /// 初始化 MessageBus
    pub fn init(allocator: Allocator) MessageBus {
        return .{
            .allocator = allocator,
            .exact_subscribers = std.StringHashMap(HandlerList).init(allocator),
            .wildcard_subscribers = .{},
            .endpoints = std.StringHashMap(RequestHandler).init(allocator),
            .command_handler = null,
            .stats = .{},
        };
    }

    /// 释放资源
    pub fn deinit(self: *MessageBus) void {
        // 释放精确订阅
        var exact_iter = self.exact_subscribers.iterator();
        while (exact_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.exact_subscribers.deinit();

        // 释放通配符订阅
        for (self.wildcard_subscribers.items) |sub| {
            self.allocator.free(sub.pattern);
        }
        self.wildcard_subscribers.deinit(self.allocator);

        // 释放端点
        var ep_iter = self.endpoints.iterator();
        while (ep_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.endpoints.deinit();
    }

    // ========================================================================
    // Pub/Sub Pattern
    // ========================================================================

    /// 发布事件到指定主题
    ///
    /// 事件会分发给所有匹配的订阅者（精确匹配 + 通配符匹配）
    pub fn publish(self: *MessageBus, topic: []const u8, event: Event) void {
        self.stats.events_published += 1;

        // 1. 精确匹配订阅者
        if (self.exact_subscribers.get(topic)) |handlers| {
            for (handlers.items) |handler| {
                handler(event);
            }
        }

        // 2. 通配符匹配订阅者
        for (self.wildcard_subscribers.items) |sub| {
            if (matchWildcard(sub.pattern, topic)) {
                sub.handler(event);
            }
        }
    }

    /// 订阅主题
    ///
    /// 支持通配符 `*` 在末尾匹配任意字符
    /// 示例: "market_data.*" 匹配 "market_data.BTC-USDT"
    pub fn subscribe(self: *MessageBus, topic: []const u8, handler: Handler) !void {
        // 检查是否是通配符订阅
        if (topic.len > 0 and topic[topic.len - 1] == '*') {
            // 通配符订阅
            const owned_pattern = try self.allocator.dupe(u8, topic);
            try self.wildcard_subscribers.append(self.allocator, .{
                .pattern = owned_pattern,
                .handler = handler,
            });
        } else {
            // 精确匹配订阅
            const result = try self.exact_subscribers.getOrPut(topic);
            if (!result.found_existing) {
                result.key_ptr.* = try self.allocator.dupe(u8, topic);
                result.value_ptr.* = .{};
            }
            try result.value_ptr.append(self.allocator, handler);
        }

        self.stats.subscribers_count += 1;
    }

    /// 取消订阅
    pub fn unsubscribe(self: *MessageBus, topic: []const u8, handler: Handler) void {
        // 检查精确匹配
        if (self.exact_subscribers.getPtr(topic)) |handlers| {
            var i: usize = 0;
            while (i < handlers.items.len) {
                if (handlers.items[i] == handler) {
                    _ = handlers.orderedRemove(i);
                    self.stats.subscribers_count -|= 1;
                } else {
                    i += 1;
                }
            }
        }

        // 检查通配符订阅
        var i: usize = 0;
        while (i < self.wildcard_subscribers.items.len) {
            const sub = self.wildcard_subscribers.items[i];
            if (std.mem.eql(u8, sub.pattern, topic) and sub.handler == handler) {
                self.allocator.free(sub.pattern);
                _ = self.wildcard_subscribers.orderedRemove(i);
                self.stats.subscribers_count -|= 1;
            } else {
                i += 1;
            }
        }
    }

    // ========================================================================
    // Request/Response Pattern
    // ========================================================================

    /// 注册请求端点
    pub fn register(self: *MessageBus, endpoint: []const u8, handler: RequestHandler) !void {
        if (self.endpoints.contains(endpoint)) {
            return MessageBusError.EndpointAlreadyRegistered;
        }

        const owned_key = try self.allocator.dupe(u8, endpoint);
        try self.endpoints.put(owned_key, handler);
        self.stats.endpoints_count += 1;
    }

    /// 发送请求并等待响应
    pub fn request(self: *MessageBus, endpoint: []const u8, req: Request) MessageBusError!Response {
        self.stats.requests_handled += 1;

        const handler = self.endpoints.get(endpoint) orelse {
            return MessageBusError.EndpointNotFound;
        };

        return handler(req);
    }

    /// 注销端点
    pub fn unregister(self: *MessageBus, endpoint: []const u8) void {
        if (self.endpoints.fetchRemove(endpoint)) |kv| {
            self.allocator.free(kv.key);
            self.stats.endpoints_count -|= 1;
        }
    }

    // ========================================================================
    // Command Pattern (Fire-and-Forget)
    // ========================================================================

    /// 设置命令处理器
    pub fn setCommandHandler(self: *MessageBus, handler: CommandHandler) void {
        self.command_handler = handler;
    }

    /// 发送命令 (不等待响应)
    pub fn send(self: *MessageBus, command: Command) void {
        self.stats.commands_sent += 1;

        if (self.command_handler) |handler| {
            handler(command);
        }
    }

    // ========================================================================
    // Utilities
    // ========================================================================

    /// 获取统计信息
    pub fn getStats(self: *const MessageBus) Stats {
        return self.stats;
    }

    /// 重置统计信息
    pub fn resetStats(self: *MessageBus) void {
        self.stats = .{
            .subscribers_count = self.stats.subscribers_count,
            .endpoints_count = self.stats.endpoints_count,
        };
    }

    /// 检查主题是否有订阅者
    pub fn hasSubscribers(self: *const MessageBus, topic: []const u8) bool {
        // 检查精确匹配
        if (self.exact_subscribers.get(topic)) |handlers| {
            if (handlers.items.len > 0) return true;
        }

        // 检查通配符
        for (self.wildcard_subscribers.items) |sub| {
            if (matchWildcard(sub.pattern, topic)) return true;
        }

        return false;
    }
};

// ============================================================================
// Wildcard Matching
// ============================================================================

/// 通配符匹配
///
/// 规则:
/// - `*` 仅在末尾有效，匹配任意字符序列
/// - 示例: "market_data.*" 匹配 "market_data.BTC-USDT"
fn matchWildcard(pattern: []const u8, topic: []const u8) bool {
    // 检查是否以 * 结尾
    if (pattern.len > 0 and pattern[pattern.len - 1] == '*') {
        const prefix = pattern[0 .. pattern.len - 1];
        return std.mem.startsWith(u8, topic, prefix);
    }
    // 精确匹配
    return std.mem.eql(u8, pattern, topic);
}

// ============================================================================
// Tests
// ============================================================================

test "MessageBus: init and deinit" {
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    const stats = bus.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.events_published);
    try std.testing.expectEqual(@as(usize, 0), stats.subscribers_count);
}

test "MessageBus: publish to single subscriber" {
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    // 使用静态变量来跟踪
    const State = struct {
        var event_received: bool = false;
    };

    const handler = struct {
        fn handle(_: Event) void {
            State.event_received = true;
        }
    }.handle;

    try bus.subscribe("test.topic", handler);

    bus.publish("test.topic", .{
        .tick = .{ .timestamp = 1000, .tick_number = 1 },
    });

    try std.testing.expect(State.event_received);
}

test "MessageBus: wildcard subscription" {
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    const State = struct {
        var count: u32 = 0;
    };
    State.count = 0;

    const handler = struct {
        fn handle(_: Event) void {
            State.count += 1;
        }
    }.handle;

    // 订阅通配符主题
    try bus.subscribe("market_data.*", handler);

    // 发布到不同主题
    bus.publish("market_data.BTC-USDT", .{
        .market_data = .{ .instrument_id = "BTC-USDT", .timestamp = 1000 },
    });

    bus.publish("market_data.ETH-USDT", .{
        .market_data = .{ .instrument_id = "ETH-USDT", .timestamp = 1001 },
    });

    // 不匹配的主题
    bus.publish("order.submitted", .{
        .tick = .{ .timestamp = 1002 },
    });

    try std.testing.expectEqual(@as(u32, 2), State.count);
}

test "MessageBus: request-response" {
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    // 注册端点
    const handler = struct {
        fn handle(req: Request) MessageBusError!Response {
            switch (req) {
                .validate_order => |order_req| {
                    const valid = order_req.quantity > 0;
                    return .{
                        .order_validated = .{
                            .valid = valid,
                            .reason = if (!valid) "Quantity must be positive" else null,
                        },
                    };
                },
                else => return .{
                    .error_response = .{ .code = 400, .message = "Unsupported request" },
                },
            }
        }
    }.handle;

    try bus.register("order.validate", handler);

    // 发送有效请求
    const response = try bus.request("order.validate", .{
        .validate_order = .{
            .instrument_id = "BTC-USDT",
            .side = .buy,
            .quantity = 1.0,
        },
    });

    switch (response) {
        .order_validated => |result| {
            try std.testing.expect(result.valid);
        },
        else => try std.testing.expect(false),
    }
}

test "MessageBus: request to unknown endpoint" {
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    const result = bus.request("nonexistent", .{
        .validate_order = .{
            .instrument_id = "BTC",
            .side = .buy,
            .quantity = 1.0,
        },
    });

    try std.testing.expectError(MessageBusError.EndpointNotFound, result);
}

test "MessageBus: command" {
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    const State = struct {
        var command_received: bool = false;
    };
    State.command_received = false;

    bus.setCommandHandler(struct {
        fn handle(_: Command) void {
            State.command_received = true;
        }
    }.handle);

    bus.send(.{
        .submit_order = .{
            .instrument_id = "BTC-USDT",
            .side = .buy,
            .order_type = .market,
            .quantity = 0.1,
        },
    });

    try std.testing.expect(State.command_received);
}

test "MessageBus: unsubscribe" {
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    const State = struct {
        var count: u32 = 0;
    };
    State.count = 0;

    const handler = struct {
        fn handle(_: Event) void {
            State.count += 1;
        }
    }.handle;

    try bus.subscribe("test.topic", handler);

    // 第一次发布
    bus.publish("test.topic", .{ .tick = .{ .timestamp = 1000 } });
    try std.testing.expectEqual(@as(u32, 1), State.count);

    // 取消订阅
    bus.unsubscribe("test.topic", handler);

    // 第二次发布
    bus.publish("test.topic", .{ .tick = .{ .timestamp = 1001 } });
    try std.testing.expectEqual(@as(u32, 1), State.count); // 不再增加
}

test "MessageBus: multiple subscribers" {
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    const State = struct {
        var count: u32 = 0;
    };
    State.count = 0;

    const handler1 = struct {
        fn handle(_: Event) void {
            State.count += 1;
        }
    }.handle;

    const handler2 = struct {
        fn handle(_: Event) void {
            State.count += 10;
        }
    }.handle;

    try bus.subscribe("test.topic", handler1);
    try bus.subscribe("test.topic", handler2);

    bus.publish("test.topic", .{ .tick = .{ .timestamp = 1000 } });

    try std.testing.expectEqual(@as(u32, 11), State.count);
}

test "matchWildcard: basic patterns" {
    // 精确匹配
    try std.testing.expect(matchWildcard("order.filled", "order.filled"));
    try std.testing.expect(!matchWildcard("order.filled", "order.rejected"));

    // 通配符匹配
    try std.testing.expect(matchWildcard("order.*", "order.filled"));
    try std.testing.expect(matchWildcard("order.*", "order.rejected"));
    try std.testing.expect(matchWildcard("market_data.*", "market_data.BTC-USDT"));

    // 不匹配
    try std.testing.expect(!matchWildcard("order.*", "position.opened"));
    try std.testing.expect(!matchWildcard("market_data.*", "order.filled"));
}

test "Event: getTimestamp" {
    const event = Event{
        .market_data = .{
            .instrument_id = "BTC-USDT",
            .timestamp = 1704067200000,
        },
    };

    try std.testing.expectEqual(@as(i64, 1704067200000), event.getTimestamp());
}

test "Event: getTypeName" {
    const event = Event{
        .tick = .{ .timestamp = 1000, .tick_number = 1 },
    };

    try std.testing.expectEqualStrings("tick", event.getTypeName());
}

test "MessageBus: stats tracking" {
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    const handler = struct {
        fn handle(_: Event) void {}
    }.handle;

    try bus.subscribe("test", handler);
    bus.publish("test", .{ .tick = .{ .timestamp = 1000 } });
    bus.publish("test", .{ .tick = .{ .timestamp = 1001 } });

    const stats = bus.getStats();
    try std.testing.expectEqual(@as(u64, 2), stats.events_published);
    try std.testing.expectEqual(@as(usize, 1), stats.subscribers_count);
}

test "MessageBus: hasSubscribers" {
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    const handler = struct {
        fn handle(_: Event) void {}
    }.handle;

    try std.testing.expect(!bus.hasSubscribers("test.topic"));

    try bus.subscribe("test.topic", handler);
    try std.testing.expect(bus.hasSubscribers("test.topic"));

    // 通配符测试
    try bus.subscribe("market.*", handler);
    try std.testing.expect(bus.hasSubscribers("market.BTC"));
}
