//! HyperliquidDataProvider - Hyperliquid 数据提供者
//!
//! 实现 IDataProvider 接口，封装 HyperliquidWS WebSocket 客户端。
//! 将 Hyperliquid 消息转换为标准的 DataMessage 格式。

const std = @import("std");
const Allocator = std.mem.Allocator;

// Core types
const Decimal = @import("../../core/decimal.zig").Decimal;
const Timestamp = @import("../../core/time.zig").Timestamp;
const Logger = @import("../../core/logger.zig").Logger;

// Data engine types
const data_engine = @import("../../core/data_engine.zig");
const IDataProvider = data_engine.IDataProvider;
const DataMessage = data_engine.DataMessage;
const Subscription = data_engine.Subscription;
const SubscriptionType = data_engine.SubscriptionType;
const QuoteMessage = data_engine.QuoteMessage;
const OrderbookMessage = data_engine.OrderbookMessage;
const TradeMessage = data_engine.TradeMessage;
const ErrorMessage = data_engine.ErrorMessage;
const Level = @import("../../market/orderbook.zig").Level;

// Hyperliquid types
const HyperliquidWS = @import("../../exchange/hyperliquid/websocket.zig").HyperliquidWS;
const ws_types = @import("../../exchange/hyperliquid/ws_types.zig");
const HLSubscription = ws_types.Subscription;
const Channel = ws_types.Channel;
const Message = ws_types.Message;
const AllMidsData = ws_types.AllMidsData;
const L2BookData = ws_types.L2BookData;
const TradesData = ws_types.TradesData;

/// 消息队列节点
const MessageNode = struct {
    data: DataMessage,
    next: ?*MessageNode = null,
};

/// Hyperliquid 数据提供者
pub const HyperliquidDataProvider = struct {
    allocator: Allocator,
    ws_client: HyperliquidWS,
    logger: Logger,

    // 消息队列 (线程安全)
    message_queue_head: ?*MessageNode,
    message_queue_tail: ?*MessageNode,
    queue_mutex: std.Thread.Mutex,

    // 状态
    is_connected: bool,

    // 配置
    config: Config,

    // TODO config WILL be config by config file
    pub const Config = struct {
        /// WebSocket 主机
        host: []const u8 = "api.hyperliquid.xyz",
        /// 端口
        port: u16 = 443,
        /// 路径
        path: []const u8 = "/ws",
        /// 使用 TLS
        use_tls: bool = true,
        /// 最大消息大小
        max_message_size: usize = 1024 * 1024,
        /// 缓冲区大小
        buffer_size: usize = 8192,
        /// 握手超时 (毫秒)
        handshake_timeout_ms: u32 = 10000,
        /// 重连间隔 (毫秒)
        reconnect_interval_ms: u64 = 5000,
        /// 最大重连次数
        max_reconnect_attempts: u32 = 10,
        /// Ping 间隔 (毫秒)
        ping_interval_ms: u64 = 30000,
    };

    const Self = @This();

    /// 初始化
    pub fn init(allocator: Allocator, config: Config, logger: Logger) Self {
        const ws_config = HyperliquidWS.Config{
            .ws_url = "wss://api.hyperliquid.xyz/ws",
            .host = config.host,
            .port = config.port,
            .path = config.path,
            .use_tls = config.use_tls,
            .max_message_size = config.max_message_size,
            .buffer_size = config.buffer_size,
            .handshake_timeout_ms = config.handshake_timeout_ms,
            .reconnect_interval_ms = config.reconnect_interval_ms,
            .max_reconnect_attempts = config.max_reconnect_attempts,
            .ping_interval_ms = config.ping_interval_ms,
        };

        var self = Self{
            .allocator = allocator,
            .ws_client = HyperliquidWS.init(allocator, ws_config, logger),
            .logger = logger,
            .message_queue_head = null,
            .message_queue_tail = null,
            .queue_mutex = .{},
            .is_connected = false,
            .config = config,
        };

        // 设置消息回调
        self.ws_client.on_message = &messageCallback;

        return self;
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        self.ws_client.deinit();

        // 清空消息队列
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        while (self.message_queue_head) |node| {
            self.message_queue_head = node.next;
            self.allocator.destroy(node);
        }
        self.message_queue_tail = null;
    }

    /// 获取 IDataProvider 接口
    pub fn asProvider(self: *Self) IDataProvider {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// VTable
    const vtable = IDataProvider.VTable{
        .connect = connect,
        .disconnect = disconnect,
        .subscribe = subscribe,
        .unsubscribe = unsubscribe,
        .poll = poll,
    };

    // ========================================================================
    // IDataProvider 实现
    // ========================================================================

    fn connect(ptr: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.logger.info("Connecting to Hyperliquid...", .{}) catch {};

        try self.ws_client.connect();
        self.is_connected = true;

        // 入队连接成功消息
        self.enqueueMessage(.{ .connected = {} });

        self.logger.info("Connected to Hyperliquid", .{}) catch {};
    }

    fn disconnect(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.logger.info("Disconnecting from Hyperliquid...", .{}) catch {};

        self.ws_client.disconnect();
        self.is_connected = false;

        // 入队断开连接消息
        self.enqueueMessage(.{ .disconnected = {} });

        self.logger.info("Disconnected from Hyperliquid", .{}) catch {};
    }

    fn subscribe(ptr: *anyopaque, sub: Subscription) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // 转换订阅类型
        switch (sub.sub_type) {
            .quote => {
                // 订阅 allMids 获取 quote 数据
                try self.ws_client.subscribe(.{
                    .channel = .allMids,
                });
            },
            .orderbook => {
                // 订阅 l2Book
                try self.ws_client.subscribe(.{
                    .channel = .l2Book,
                    .coin = sub.symbol,
                });
            },
            .trade => {
                // 订阅 trades
                try self.ws_client.subscribe(.{
                    .channel = .trades,
                    .coin = sub.symbol,
                });
            },
            .candle => {
                // Hyperliquid WebSocket 不直接支持 K线订阅
                // 需要从 trades 聚合或使用 REST API
                self.logger.warn("Candle subscription not directly supported via WebSocket", .{}) catch {};
            },
            .all => {
                // 订阅所有相关频道
                try self.ws_client.subscribe(.{
                    .channel = .allMids,
                });
                try self.ws_client.subscribe(.{
                    .channel = .l2Book,
                    .coin = sub.symbol,
                });
                try self.ws_client.subscribe(.{
                    .channel = .trades,
                    .coin = sub.symbol,
                });
            },
        }

        self.logger.debug("Subscribed", .{
            .symbol = sub.symbol,
            .type = @tagName(sub.sub_type),
        }) catch {};
    }

    fn unsubscribe(ptr: *anyopaque, symbol: []const u8) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // 取消所有相关订阅
        self.ws_client.unsubscribe(.{
            .channel = .l2Book,
            .coin = symbol,
        }) catch {};

        self.ws_client.unsubscribe(.{
            .channel = .trades,
            .coin = symbol,
        }) catch {};

        self.logger.debug("Unsubscribed", .{
            .symbol = symbol,
        }) catch {};
    }

    fn poll(ptr: *anyopaque) ?DataMessage {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.dequeueMessage();
    }

    // ========================================================================
    // 消息处理
    // ========================================================================

    /// TODO 需要验证确保这里这样忽略是正确的吗 消息回调 (由 HyperliquidWS 调用)
    fn messageCallback(msg: Message) void {
        // 注意: 这里需要获取 self 指针
        // 由于回调函数签名限制，我们需要用其他方式处理
        // 这里暂时使用一个简化的实现
        _ = msg;
    }

    /// 处理 Hyperliquid 消息并转换为 DataMessage
    pub fn processMessage(self: *Self, msg: Message) void {
        switch (msg) {
            .allMids => |data| self.processAllMids(data),
            .l2Book => |data| self.processL2Book(data),
            .trades => |data| self.processTrades(data),
            .error_msg => |data| self.processError(data),
            .subscriptionResponse => {
                // 订阅确认，可以忽略或记录日志 todo 应该怎么也得记录一个日志吧
            },
            else => {
                // todo 应该怎么也得记录一个日志吧
                // 其他消息类型暂不处理
            },
        }
    }

    /// 处理 AllMids 消息 (转换为 Quote)
    fn processAllMids(self: *Self, data: AllMidsData) void {
        for (data.mids) |mid| {
            // AllMids 只有 mid price，没有 bid/ask
            // 我们用 mid 作为 bid 和 ask 的近似值
            const quote_msg = QuoteMessage{
                .symbol = mid.coin,
                .bid = mid.mid,
                .ask = mid.mid,
                .bid_size = Decimal.ZERO,
                .ask_size = Decimal.ZERO,
                .timestamp = Timestamp.now(),
            };

            self.enqueueMessage(.{ .quote = quote_msg });
        }
    }

    /// 处理 L2Book 消息 (转换为 Orderbook)
    fn processL2Book(self: *Self, data: L2BookData) void {
        // 转换 Hyperliquid Level 到标准 Level
        const bids = self.allocator.alloc(Level, data.levels.bids.len) catch return;
        const asks = self.allocator.alloc(Level, data.levels.asks.len) catch {
            self.allocator.free(bids);
            return;
        };

        for (data.levels.bids, 0..) |bid, i| {
            bids[i] = .{
                .price = bid.px,
                .quantity = bid.sz,
            };
        }

        for (data.levels.asks, 0..) |ask, i| {
            asks[i] = .{
                .price = ask.px,
                .quantity = ask.sz,
            };
        }

        const orderbook_msg = OrderbookMessage{
            .symbol = data.coin,
            .bids = bids,
            .asks = asks,
            .is_snapshot = true,
            .timestamp = Timestamp.fromMillis(data.timestamp),
        };

        self.enqueueMessage(.{ .orderbook = orderbook_msg });
    }

    /// 处理 Trades 消息 (转换为 Trade)
    fn processTrades(self: *Self, data: TradesData) void {
        for (data.trades) |trade| {
            const side: TradeMessage.Side = if (std.mem.eql(u8, trade.side, "B"))
                .buy
            else
                .sell;

            const trade_msg = TradeMessage{
                .symbol = data.coin,
                .price = trade.px,
                .size = trade.sz,
                .side = side,
                .timestamp = Timestamp.fromMillis(trade.time),
            };

            self.enqueueMessage(.{ .trade = trade_msg });
        }
    }

    /// 处理错误消息
    fn processError(self: *Self, data: ws_types.ErrorMessage) void {
        const error_msg = ErrorMessage{
            .code = @as(u32, @intCast(@max(0, data.code))),
            .message = data.msg,
        };

        self.enqueueMessage(.{ .err = error_msg });
    }

    // ========================================================================
    // 消息队列操作 (线程安全)
    // ========================================================================

    /// 入队消息
    fn enqueueMessage(self: *Self, msg: DataMessage) void {
        const node = self.allocator.create(MessageNode) catch return;
        node.* = .{ .data = msg, .next = null };

        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        if (self.message_queue_tail) |tail| {
            tail.next = node;
            self.message_queue_tail = node;
        } else {
            self.message_queue_head = node;
            self.message_queue_tail = node;
        }
    }

    /// 出队消息
    fn dequeueMessage(self: *Self) ?DataMessage {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        if (self.message_queue_head) |node| {
            self.message_queue_head = node.next;
            if (self.message_queue_head == null) {
                self.message_queue_tail = null;
            }

            const msg = node.data;
            self.allocator.destroy(node);
            return msg;
        }

        return null;
    }

    // ========================================================================
    // 工具方法
    // ========================================================================

    /// 检查是否已连接
    pub fn isConnected(self: *Self) bool {
        return self.is_connected and self.ws_client.isConnected();
    }

    /// 获取队列中消息数量
    pub fn queueSize(self: *Self) usize {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        var count: usize = 0;
        var node = self.message_queue_head;
        while (node) |n| {
            count += 1;
            node = n.next;
        }
        return count;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "HyperliquidDataProvider: init and deinit" {
    const allocator = std.testing.allocator;

    // 创建 dummy logger
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../core/logger.zig").LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../core/logger.zig").LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    const logger = @import("../../core/logger.zig").Logger.init(allocator, writer, .debug);

    var provider = HyperliquidDataProvider.init(allocator, .{}, logger);
    defer provider.deinit();

    try std.testing.expect(!provider.isConnected());
}

test "HyperliquidDataProvider: message queue" {
    const allocator = std.testing.allocator;

    // 创建 dummy logger
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../core/logger.zig").LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../core/logger.zig").LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    const logger = @import("../../core/logger.zig").Logger.init(allocator, writer, .debug);

    var provider = HyperliquidDataProvider.init(allocator, .{}, logger);
    defer provider.deinit();

    // 测试入队和出队
    provider.enqueueMessage(.{ .connected = {} });
    provider.enqueueMessage(.{ .disconnected = {} });

    try std.testing.expectEqual(@as(usize, 2), provider.queueSize());

    const msg1 = provider.dequeueMessage();
    try std.testing.expect(msg1 != null);
    try std.testing.expect(msg1.? == .connected);

    const msg2 = provider.dequeueMessage();
    try std.testing.expect(msg2 != null);
    try std.testing.expect(msg2.? == .disconnected);

    const msg3 = provider.dequeueMessage();
    try std.testing.expect(msg3 == null);

    try std.testing.expectEqual(@as(usize, 0), provider.queueSize());
}

test "HyperliquidDataProvider: asProvider" {
    const allocator = std.testing.allocator;

    // 创建 dummy logger
    const DummyWriter = struct {
        fn write(_: *anyopaque, _: @import("../../core/logger.zig").LogRecord) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = @import("../../core/logger.zig").LogWriter{
        .ptr = @ptrCast(@constCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    const logger = @import("../../core/logger.zig").Logger.init(allocator, writer, .debug);

    var provider = HyperliquidDataProvider.init(allocator, .{}, logger);
    defer provider.deinit();

    const data_provider = provider.asProvider();

    // 验证 vtable 和 ptr 正确设置
    try std.testing.expect(data_provider.vtable == &HyperliquidDataProvider.vtable);
    try std.testing.expect(@intFromPtr(data_provider.ptr) != 0);
}
