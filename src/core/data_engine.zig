//! DataEngine - 数据引擎
//!
//! 管理市场数据的获取、处理和分发。
//!
//! ## 功能
//! - 订阅和接收市场数据 (WebSocket/HTTP)
//! - 数据解析和验证
//! - 更新 Cache 缓存
//! - 通过 MessageBus 发布数据事件
//! - 支持多数据源
//!
//! ## 设计原则
//! - 单线程事件驱动
//! - 与 Cache 和 MessageBus 集成
//! - 支持回测和实盘模式
//! - 可扩展的数据提供者接口

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("decimal.zig").Decimal;
const Timestamp = @import("time.zig").Timestamp;
const MessageBus = @import("message_bus.zig").MessageBus;
const Event = @import("message_bus.zig").Event;
const Cache = @import("cache.zig").Cache;
const Quote = @import("cache.zig").Quote;
const Bar = @import("cache.zig").Bar;
const Timeframe = @import("cache.zig").Timeframe;
const OrderBook = @import("../market/orderbook.zig").OrderBook;
const Level = @import("../market/orderbook.zig").Level;

// ============================================================================
// 数据提供者接口
// ============================================================================

/// 数据提供者类型
pub const ProviderType = enum {
    hyperliquid,
    binance,
    mock,
    csv,
};

/// 订阅类型
pub const SubscriptionType = enum {
    quote, // Tick/Quote 数据
    orderbook, // 订单簿
    trade, // 成交记录
    candle, // K线数据
    all, // 全部
};

/// 订阅配置
pub const Subscription = struct {
    symbol: []const u8,
    sub_type: SubscriptionType,
    timeframe: ?Timeframe = null, // 仅 candle 需要
};

/// 数据提供者接口
pub const IDataProvider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        connect: *const fn (ptr: *anyopaque) anyerror!void,
        disconnect: *const fn (ptr: *anyopaque) void,
        subscribe: *const fn (ptr: *anyopaque, sub: Subscription) anyerror!void,
        unsubscribe: *const fn (ptr: *anyopaque, symbol: []const u8) void,
        poll: *const fn (ptr: *anyopaque) ?DataMessage,
    };

    pub fn connect(self: IDataProvider) !void {
        return self.vtable.connect(self.ptr);
    }

    pub fn disconnect(self: IDataProvider) void {
        return self.vtable.disconnect(self.ptr);
    }

    pub fn subscribe(self: IDataProvider, sub: Subscription) !void {
        return self.vtable.subscribe(self.ptr, sub);
    }

    pub fn unsubscribe(self: IDataProvider, symbol: []const u8) void {
        return self.vtable.unsubscribe(self.ptr, symbol);
    }

    pub fn poll(self: IDataProvider) ?DataMessage {
        return self.vtable.poll(self.ptr);
    }
};

/// 数据消息类型
pub const DataMessage = union(enum) {
    quote: QuoteMessage,
    orderbook: OrderbookMessage,
    trade: TradeMessage,
    candle: CandleMessage,
    err: ErrorMessage,
    connected: void,
    disconnected: void,
};

pub const QuoteMessage = struct {
    symbol: []const u8,
    bid: Decimal,
    ask: Decimal,
    bid_size: Decimal,
    ask_size: Decimal,
    timestamp: Timestamp,
};

pub const OrderbookMessage = struct {
    symbol: []const u8,
    bids: []const Level,
    asks: []const Level,
    is_snapshot: bool,
    timestamp: Timestamp,
};

pub const TradeMessage = struct {
    symbol: []const u8,
    price: Decimal,
    size: Decimal,
    side: Side,
    timestamp: Timestamp,

    pub const Side = enum { buy, sell };
};

pub const CandleMessage = struct {
    symbol: []const u8,
    timeframe: Timeframe,
    open: Decimal,
    high: Decimal,
    low: Decimal,
    close: Decimal,
    volume: Decimal,
    timestamp: Timestamp,
    is_closed: bool,
};

pub const ErrorMessage = struct {
    code: u32,
    message: []const u8,
};

// ============================================================================
// DataEngine 错误
// ============================================================================

pub const DataEngineError = error{
    NotConnected,
    SubscriptionFailed,
    ProviderError,
    InvalidData,
    OutOfMemory,
};

// ============================================================================
// DataEngine 主结构
// ============================================================================

pub const DataEngine = struct {
    allocator: Allocator,
    bus: *MessageBus,
    cache: *Cache,

    // 数据提供者
    providers: std.ArrayList(IDataProvider),
    active_provider: ?*IDataProvider,

    // 订阅管理
    subscriptions: std.StringHashMap(SubscriptionType),

    // 状态
    state: State,
    config: Config,
    stats: Stats,

    pub const State = enum {
        stopped,
        connecting,
        running,
        failed,
    };

    pub const Config = struct {
        auto_reconnect: bool = true,
        reconnect_interval_ms: u64 = 5000,
        max_reconnect_attempts: u32 = 10,
        data_validation: bool = true,
    };

    pub const Stats = struct {
        messages_received: u64 = 0,
        quotes_processed: u64 = 0,
        orderbook_updates: u64 = 0,
        trades_processed: u64 = 0,
        candles_processed: u64 = 0,
        errors: u64 = 0,
        last_update_time: ?Timestamp = null,
    };

    // ========================================================================
    // 初始化和清理
    // ========================================================================

    /// 初始化 DataEngine
    pub fn init(
        allocator: Allocator,
        bus: *MessageBus,
        cache: *Cache,
        config: Config,
    ) DataEngine {
        return .{
            .allocator = allocator,
            .bus = bus,
            .cache = cache,
            .providers = .{},
            .active_provider = null,
            .subscriptions = std.StringHashMap(SubscriptionType).init(allocator),
            .state = .stopped,
            .config = config,
            .stats = .{},
        };
    }

    /// 释放资源
    pub fn deinit(self: *DataEngine) void {
        // 只断开连接，不发布事件
        if (self.active_provider) |provider| {
            provider.disconnect();
        }
        self.state = .stopped;

        // 释放订阅
        var iter = self.subscriptions.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.subscriptions.deinit();

        // 释放提供者列表
        self.providers.deinit(self.allocator);
    }

    // ========================================================================
    // 数据提供者管理
    // ========================================================================

    /// 添加数据提供者
    pub fn addProvider(self: *DataEngine, provider: IDataProvider) !void {
        try self.providers.append(self.allocator, provider);

        // 如果没有活跃提供者，设置第一个
        if (self.active_provider == null) {
            self.active_provider = &self.providers.items[self.providers.items.len - 1];
        }
    }

    /// 设置活跃提供者
    pub fn setActiveProvider(self: *DataEngine, index: usize) void {
        if (index < self.providers.items.len) {
            self.active_provider = &self.providers.items[index];
        }
    }

    // ========================================================================
    // 生命周期管理
    // ========================================================================

    /// 启动数据引擎
    pub fn start(self: *DataEngine) !void {
        if (self.active_provider == null) {
            return DataEngineError.ProviderError;
        }

        self.state = .connecting;

        // 连接数据提供者
        try self.active_provider.?.connect();

        self.state = .running;

        // 发布启动事件
        self.bus.publish("data_engine.started", .{
            .tick = .{
                .timestamp = Timestamp.now().millis * 1_000_000,
                .tick_number = 0,
            },
        });
    }

    /// 停止数据引擎
    pub fn stop(self: *DataEngine) void {
        if (self.active_provider) |provider| {
            provider.disconnect();
        }

        self.state = .stopped;

        // 发布停止事件
        self.bus.publish("data_engine.stopped", .{
            .shutdown = .{
                .reason = .user_request,
                .message = "DataEngine stopped",
            },
        });
    }

    // ========================================================================
    // 订阅管理
    // ========================================================================

    /// 订阅市场数据
    pub fn subscribe(self: *DataEngine, symbol: []const u8, sub_type: SubscriptionType) !void {
        if (self.active_provider == null) {
            return DataEngineError.NotConnected;
        }

        // 保存订阅
        const owned_symbol = try self.allocator.dupe(u8, symbol);
        errdefer self.allocator.free(owned_symbol);

        const result = try self.subscriptions.getOrPut(owned_symbol);
        if (result.found_existing) {
            self.allocator.free(owned_symbol);
        } else {
            result.key_ptr.* = owned_symbol;
        }
        result.value_ptr.* = sub_type;

        // 通过提供者订阅
        try self.active_provider.?.subscribe(.{
            .symbol = symbol,
            .sub_type = sub_type,
        });
    }

    /// 订阅 K线数据
    pub fn subscribeCandles(
        self: *DataEngine,
        symbol: []const u8,
        timeframe: Timeframe,
    ) !void {
        if (self.active_provider == null) {
            return DataEngineError.NotConnected;
        }

        try self.active_provider.?.subscribe(.{
            .symbol = symbol,
            .sub_type = .candle,
            .timeframe = timeframe,
        });
    }

    /// 取消订阅
    pub fn unsubscribe(self: *DataEngine, symbol: []const u8) void {
        if (self.subscriptions.fetchRemove(symbol)) |kv| {
            self.allocator.free(kv.key);
        }

        if (self.active_provider) |provider| {
            provider.unsubscribe(symbol);
        }
    }

    // ========================================================================
    // 数据处理
    // ========================================================================

    /// 处理一条数据消息
    pub fn processMessage(self: *DataEngine, message: DataMessage) !void {
        self.stats.messages_received += 1;
        self.stats.last_update_time = Timestamp.now();

        switch (message) {
            .quote => |q| try self.processQuote(q),
            .orderbook => |ob| try self.processOrderbook(ob),
            .trade => |t| try self.processTrade(t),
            .candle => |c| try self.processCandle(c),
            .err => |e| self.processError(e),
            .connected => self.handleConnected(),
            .disconnected => self.handleDisconnected(),
        }
    }

    /// 轮询并处理消息 (非阻塞)
    pub fn poll(self: *DataEngine) !void {
        if (self.active_provider) |provider| {
            while (provider.poll()) |message| {
                try self.processMessage(message);
            }
        }
    }

    // ========================================================================
    // 内部处理函数
    // ========================================================================

    fn processQuote(self: *DataEngine, msg: QuoteMessage) !void {
        // 验证数据
        if (self.config.data_validation) {
            if (msg.bid.cmp(Decimal.ZERO) == .lt or msg.ask.cmp(Decimal.ZERO) == .lt) {
                self.stats.errors += 1;
                return DataEngineError.InvalidData;
            }
        }

        // 更新 Cache
        try self.cache.updateQuote(.{
            .symbol = msg.symbol,
            .bid = msg.bid,
            .ask = msg.ask,
            .bid_size = msg.bid_size,
            .ask_size = msg.ask_size,
            .timestamp = msg.timestamp,
        });

        self.stats.quotes_processed += 1;

        // 发布事件
        self.bus.publish("market_data.quote", .{
            .market_data = .{
                .instrument_id = msg.symbol,
                .timestamp = msg.timestamp.millis * 1_000_000,
                .bid = msg.bid.toFloat(),
                .ask = msg.ask.toFloat(),
                .bid_size = msg.bid_size.toFloat(),
                .ask_size = msg.ask_size.toFloat(),
            },
        });
    }

    fn processOrderbook(self: *DataEngine, msg: OrderbookMessage) !void {
        // 更新 Cache
        try self.cache.updateOrderBook(msg.symbol, msg.bids, msg.asks);

        self.stats.orderbook_updates += 1;

        // 发布事件
        self.bus.publish("market_data.orderbook", .{
            .orderbook_update = .{
                .instrument_id = msg.symbol,
                .timestamp = msg.timestamp.millis * 1_000_000,
                .is_snapshot = msg.is_snapshot,
            },
        });
    }

    fn processTrade(self: *DataEngine, msg: TradeMessage) !void {
        self.stats.trades_processed += 1;

        // 发布事件
        const side: @import("message_bus.zig").TradeEvent.Side = switch (msg.side) {
            .buy => .buy,
            .sell => .sell,
        };

        self.bus.publish("market_data.trade", .{
            .trade = .{
                .instrument_id = msg.symbol,
                .timestamp = msg.timestamp.millis * 1_000_000,
                .price = msg.price.toFloat(),
                .quantity = msg.size.toFloat(),
                .side = side,
            },
        });
    }

    fn processCandle(self: *DataEngine, msg: CandleMessage) !void {
        // 更新 Cache
        try self.cache.updateBar(.{
            .symbol = msg.symbol,
            .timeframe = msg.timeframe,
            .open = msg.open,
            .high = msg.high,
            .low = msg.low,
            .close = msg.close,
            .volume = msg.volume,
            .timestamp = msg.timestamp,
            .is_closed = msg.is_closed,
        });

        self.stats.candles_processed += 1;

        // 发布事件 (仅闭合的 K线)
        if (msg.is_closed) {
            // 现在使用统一的 Timeframe 类型，无需转换
            self.bus.publish("market_data.candle", .{
                .candle = .{
                    .instrument_id = msg.symbol,
                    .timestamp = msg.timestamp.millis * 1_000_000,
                    .timeframe = msg.timeframe,
                    .open = msg.open.toFloat(),
                    .high = msg.high.toFloat(),
                    .low = msg.low.toFloat(),
                    .close = msg.close.toFloat(),
                    .volume = msg.volume.toFloat(),
                },
            });
        }
    }

    fn processError(self: *DataEngine, msg: ErrorMessage) void {
        self.stats.errors += 1;
        _ = msg;

        // 发布错误事件
        self.bus.publish("data_engine.error", .{
            .shutdown = .{
                .reason = .fatal_error,
                .message = "DataEngine error",
            },
        });
    }

    fn handleConnected(self: *DataEngine) void {
        self.state = .running;

        self.bus.publish("data_engine.connected", .{
            .tick = .{
                .timestamp = Timestamp.now().millis * 1_000_000,
                .tick_number = 0,
            },
        });
    }

    fn handleDisconnected(self: *DataEngine) void {
        self.state = .stopped;

        self.bus.publish("data_engine.disconnected", .{
            .shutdown = .{
                .reason = .signal,
                .message = "Connection lost",
            },
        });
    }

    // ========================================================================
    // 工具方法
    // ========================================================================

    /// 获取状态
    pub fn getState(self: *const DataEngine) State {
        return self.state;
    }

    /// 获取统计信息
    pub fn getStats(self: *const DataEngine) Stats {
        return self.stats;
    }

    /// 是否正在运行
    pub fn isRunning(self: *const DataEngine) bool {
        return self.state == .running;
    }

    /// 获取订阅数量
    pub fn subscriptionCount(self: *const DataEngine) usize {
        return self.subscriptions.count();
    }

    // ========================================================================
    // 历史数据操作 (回测模式)
    // ========================================================================

    /// 历史数据回放配置
    pub const ReplayConfig = struct {
        /// 回放速度倍数 (1.0 = 实时, 0 = 尽快)
        speed_multiplier: f64 = 0,
        /// 是否发布事件到 MessageBus
        publish_events: bool = true,
        /// 是否更新 Cache
        update_cache: bool = true,
        /// 回放完成后的回调
        on_complete: ?*const fn () void = null,
    };

    /// 回放历史数据
    /// 用于回测模式，将历史数据按时间顺序回放
    pub fn replayHistoricalData(
        self: *DataEngine,
        candles: []const CandleMessage,
        config: ReplayConfig,
    ) !ReplayStats {
        var stats = ReplayStats{};
        const start_time = std.time.milliTimestamp();

        for (candles) |candle| {
            // 处理 K 线数据
            if (config.update_cache) {
                try self.cache.updateBar(.{
                    .symbol = candle.symbol,
                    .timeframe = candle.timeframe,
                    .open = candle.open,
                    .high = candle.high,
                    .low = candle.low,
                    .close = candle.close,
                    .volume = candle.volume,
                    .timestamp = candle.timestamp,
                    .is_closed = candle.is_closed,
                });
            }

            // 发布事件
            if (config.publish_events and candle.is_closed) {
                // 现在使用统一的 Timeframe 类型，无需转换
                self.bus.publish("market_data.candle", .{
                    .candle = .{
                        .instrument_id = candle.symbol,
                        .timestamp = candle.timestamp.millis * 1_000_000,
                        .timeframe = candle.timeframe,
                        .open = candle.open.toFloat(),
                        .high = candle.high.toFloat(),
                        .low = candle.low.toFloat(),
                        .close = candle.close.toFloat(),
                        .volume = candle.volume.toFloat(),
                    },
                });
            }

            stats.candles_replayed += 1;
            self.stats.candles_processed += 1;

            // 模拟延迟 (如果 speed_multiplier > 0)
            if (config.speed_multiplier > 0) {
                const delay_ns: u64 = @intFromFloat(1_000_000.0 / config.speed_multiplier);
                std.Thread.sleep(delay_ns);
            }
        }

        stats.duration_ms = @intCast(std.time.milliTimestamp() - start_time);

        // 回调
        if (config.on_complete) |callback| {
            callback();
        }

        // 发布回放完成事件
        self.bus.publish("data_engine.replay_complete", .{
            .tick = .{
                .timestamp = Timestamp.now().millis * 1_000_000,
                .tick_number = stats.candles_replayed,
            },
        });

        return stats;
    }

    /// 回放统计
    pub const ReplayStats = struct {
        candles_replayed: u64 = 0,
        duration_ms: u64 = 0,
    };

    /// 加载历史 K 线数据
    /// 从 CSV 或其他数据源加载历史数据到内存
    pub fn loadHistoricalCandles(
        self: *DataEngine,
        symbol: []const u8,
        timeframe: Timeframe,
        start_time: Timestamp,
        end_time: Timestamp,
    ) ![]CandleMessage {
        // 尝试从 CSV 文件加载历史数据
        // 文件命名约定: data/<symbol>_<timeframe>.csv
        // 例如: data/ETH_h1.csv, data/BTC_m15.csv

        const tf_str = @tagName(timeframe);

        // 构建文件路径
        const file_path = try std.fmt.allocPrint(
            self.allocator,
            "data/{s}_{s}.csv",
            .{ symbol, tf_str },
        );
        defer self.allocator.free(file_path);

        // 尝试读取文件
        const csv_data = std.fs.cwd().readFileAlloc(
            self.allocator,
            file_path,
            10 * 1024 * 1024, // 10MB max
        ) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    // 文件不存在时返回空数组
                    return &[_]CandleMessage{};
                },
                else => return err,
            }
        };
        defer self.allocator.free(csv_data);

        // 解析 CSV 数据
        var all_candles = try self.parseCsvCandles(csv_data, symbol, timeframe);
        defer all_candles.deinit(self.allocator);

        // 按时间范围过滤
        var filtered: std.ArrayList(CandleMessage) = .{};
        errdefer filtered.deinit(self.allocator);

        for (all_candles.items) |candle| {
            const ts = candle.timestamp.millis;
            if (ts >= start_time.millis and ts <= end_time.millis) {
                try filtered.append(self.allocator, candle);
            }
        }

        // 返回切片 (调用者负责释放)
        return try filtered.toOwnedSlice(self.allocator);
    }

    /// 从 CSV 数据创建 CandleMessage 数组
    pub fn parseCsvCandles(
        self: *DataEngine,
        csv_data: []const u8,
        symbol: []const u8,
        timeframe: Timeframe,
    ) !std.ArrayList(CandleMessage) {
        var candles: std.ArrayList(CandleMessage) = .{};
        errdefer candles.deinit(self.allocator);

        var lines = std.mem.splitScalar(u8, csv_data, '\n');

        // 跳过标题行
        _ = lines.next();

        while (lines.next()) |line| {
            if (line.len == 0) continue;

            var fields = std.mem.splitScalar(u8, line, ',');

            // 期望格式: timestamp,open,high,low,close,volume
            const ts_str = fields.next() orelse continue;
            const open_str = fields.next() orelse continue;
            const high_str = fields.next() orelse continue;
            const low_str = fields.next() orelse continue;
            const close_str = fields.next() orelse continue;
            const volume_str = fields.next() orelse continue;

            const timestamp_ms = std.fmt.parseInt(i64, ts_str, 10) catch continue;

            try candles.append(self.allocator, .{
                .symbol = symbol,
                .timeframe = timeframe,
                .open = Decimal.fromFloat(std.fmt.parseFloat(f64, open_str) catch 0),
                .high = Decimal.fromFloat(std.fmt.parseFloat(f64, high_str) catch 0),
                .low = Decimal.fromFloat(std.fmt.parseFloat(f64, low_str) catch 0),
                .close = Decimal.fromFloat(std.fmt.parseFloat(f64, close_str) catch 0),
                .volume = Decimal.fromFloat(std.fmt.parseFloat(f64, volume_str) catch 0),
                .timestamp = Timestamp.fromMillis(timestamp_ms),
                .is_closed = true,
            });
        }

        return candles;
    }
};

// ============================================================================
// Mock 数据提供者 (用于测试)
// ============================================================================

pub const MockDataProvider = struct {
    allocator: Allocator,
    messages: std.ArrayList(DataMessage),
    is_connected: bool,
    current_index: usize,

    pub fn init(allocator: Allocator) MockDataProvider {
        return .{
            .allocator = allocator,
            .messages = .{},
            .is_connected = false,
            .current_index = 0,
        };
    }

    pub fn deinit(self: *MockDataProvider) void {
        self.messages.deinit(self.allocator);
    }

    /// 添加测试消息
    pub fn addMessage(self: *MockDataProvider, message: DataMessage) !void {
        try self.messages.append(self.allocator, message);
    }

    /// 获取 IDataProvider 接口
    pub fn asProvider(self: *MockDataProvider) IDataProvider {
        return .{
            .ptr = self,
            .vtable = &.{
                .connect = connect,
                .disconnect = disconnect,
                .subscribe = subscribe,
                .unsubscribe = unsubscribe,
                .poll = poll,
            },
        };
    }

    fn connect(ptr: *anyopaque) anyerror!void {
        const self: *MockDataProvider = @ptrCast(@alignCast(ptr));
        self.is_connected = true;
    }

    fn disconnect(ptr: *anyopaque) void {
        const self: *MockDataProvider = @ptrCast(@alignCast(ptr));
        self.is_connected = false;
    }

    fn subscribe(_: *anyopaque, _: Subscription) anyerror!void {
        // Mock: 不做任何事
    }

    fn unsubscribe(_: *anyopaque, _: []const u8) void {
        // Mock: 不做任何事
    }

    fn poll(ptr: *anyopaque) ?DataMessage {
        const self: *MockDataProvider = @ptrCast(@alignCast(ptr));

        if (self.current_index < self.messages.items.len) {
            const msg = self.messages.items[self.current_index];
            self.current_index += 1;
            return msg;
        }

        return null;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "DataEngine: init and deinit" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = DataEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    try std.testing.expectEqual(DataEngine.State.stopped, engine.getState());
    try std.testing.expect(!engine.isRunning());
}

test "DataEngine: with mock provider" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = DataEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    var mock = MockDataProvider.init(std.testing.allocator);
    defer mock.deinit();

    try engine.addProvider(mock.asProvider());
    try engine.start();

    try std.testing.expect(engine.isRunning());
}

test "DataEngine: process quote" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = DataEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    var mock = MockDataProvider.init(std.testing.allocator);
    defer mock.deinit();

    // 添加测试消息
    try mock.addMessage(.{
        .quote = .{
            .symbol = "BTC-USDT",
            .bid = Decimal.fromInt(50000),
            .ask = Decimal.fromInt(50010),
            .bid_size = Decimal.fromInt(10),
            .ask_size = Decimal.fromInt(5),
            .timestamp = Timestamp.now(),
        },
    });

    try engine.addProvider(mock.asProvider());
    try engine.start();

    // 处理消息
    try engine.poll();

    // 验证 Cache 更新
    const quote = cache.getQuote("BTC-USDT");
    try std.testing.expect(quote != null);
    try std.testing.expectEqual(Decimal.fromInt(50000), quote.?.bid);

    // 验证统计
    try std.testing.expectEqual(@as(u64, 1), engine.stats.quotes_processed);
    try std.testing.expectEqual(@as(u64, 1), engine.stats.messages_received);
}

test "DataEngine: subscription" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = DataEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    var mock = MockDataProvider.init(std.testing.allocator);
    defer mock.deinit();

    try engine.addProvider(mock.asProvider());
    try engine.start();

    try engine.subscribe("BTC-USDT", .quote);
    try engine.subscribe("ETH-USDT", .orderbook);

    try std.testing.expectEqual(@as(usize, 2), engine.subscriptionCount());

    engine.unsubscribe("BTC-USDT");
    try std.testing.expectEqual(@as(usize, 1), engine.subscriptionCount());
}

test "MockDataProvider: basic operations" {
    var mock = MockDataProvider.init(std.testing.allocator);
    defer mock.deinit();

    try mock.addMessage(.{ .connected = {} });
    try mock.addMessage(.{
        .quote = .{
            .symbol = "TEST",
            .bid = Decimal.fromInt(100),
            .ask = Decimal.fromInt(101),
            .bid_size = Decimal.fromInt(10),
            .ask_size = Decimal.fromInt(10),
            .timestamp = Timestamp.now(),
        },
    });

    const provider = mock.asProvider();
    try provider.connect();

    const msg1 = provider.poll();
    try std.testing.expect(msg1 != null);
    try std.testing.expect(msg1.? == .connected);

    const msg2 = provider.poll();
    try std.testing.expect(msg2 != null);
    try std.testing.expect(msg2.? == .quote);

    const msg3 = provider.poll();
    try std.testing.expect(msg3 == null);
}

test "DataEngine: replay historical data" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = DataEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    // 创建测试 K 线数据
    const candles = [_]CandleMessage{
        .{
            .symbol = "BTC-USDT",
            .timeframe = .h1,
            .open = Decimal.fromInt(50000),
            .high = Decimal.fromInt(51000),
            .low = Decimal.fromInt(49500),
            .close = Decimal.fromInt(50500),
            .volume = Decimal.fromInt(1000),
            .timestamp = Timestamp.fromMillis(1704067200000),
            .is_closed = true,
        },
        .{
            .symbol = "BTC-USDT",
            .timeframe = .h1,
            .open = Decimal.fromInt(50500),
            .high = Decimal.fromInt(52000),
            .low = Decimal.fromInt(50000),
            .close = Decimal.fromInt(51500),
            .volume = Decimal.fromInt(1200),
            .timestamp = Timestamp.fromMillis(1704070800000),
            .is_closed = true,
        },
    };

    // 回放数据
    const stats = try engine.replayHistoricalData(&candles, .{
        .speed_multiplier = 0, // 尽快
        .publish_events = true,
        .update_cache = true,
    });

    // 验证统计
    try std.testing.expectEqual(@as(u64, 2), stats.candles_replayed);
    try std.testing.expectEqual(@as(u64, 2), engine.stats.candles_processed);

    // 验证 Cache 更新
    const last_bar = cache.getLastBar("BTC-USDT", .h1);
    try std.testing.expect(last_bar != null);
    try std.testing.expectEqual(Decimal.fromInt(51500), last_bar.?.close);
}

test "DataEngine: parse CSV candles" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = DataEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer engine.deinit();

    const csv_data =
        \\timestamp,open,high,low,close,volume
        \\1704067200000,50000,51000,49500,50500,1000
        \\1704070800000,50500,52000,50000,51500,1200
    ;

    var candles = try engine.parseCsvCandles(csv_data, "ETH-USDT", .h1);
    defer candles.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), candles.items.len);
    // 使用 toFloat 比较避免浮点精度问题
    try std.testing.expectApproxEqAbs(@as(f64, 50000), candles.items[0].open.toFloat(), 1);
    try std.testing.expectApproxEqAbs(@as(f64, 51500), candles.items[1].close.toFloat(), 1);
}

test "DataEngine: ReplayConfig defaults" {
    const config = DataEngine.ReplayConfig{};
    try std.testing.expectEqual(@as(f64, 0), config.speed_multiplier);
    try std.testing.expect(config.publish_events);
    try std.testing.expect(config.update_cache);
}
