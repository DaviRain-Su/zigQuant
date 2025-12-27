//! v0.5.0 集成测试
//!
//! 测试事件驱动架构的核心组件集成:
//! - MessageBus 消息传递
//! - Cache 数据缓存
//! - DataEngine 数据处理
//! - ExecutionEngine 订单执行
//! - LiveTradingEngine 统一接口

const std = @import("std");
const zigQuant = @import("zigQuant");

// 导入核心组件
const MessageBus = zigQuant.MessageBus;
const Event = zigQuant.message_bus.Event;
const Cache = zigQuant.Cache;
const DataEngine = zigQuant.DataEngine;
const ExecutionEngine = zigQuant.ExecutionEngine;
const LiveTradingEngine = zigQuant.LiveTradingEngine;
const Decimal = zigQuant.Decimal;
const Timestamp = zigQuant.Timestamp;

// ============================================================================
// 测试 1: MessageBus Pub/Sub 集成
// ============================================================================

test "Integration: MessageBus pub/sub with multiple subscribers" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    // 订阅者 1
    const handler1 = struct {
        fn handle(_: Event) void {
            // 处理事件
        }
    }.handle;

    // 订阅者 2 (使用通配符)
    const handler2 = struct {
        fn handle(_: Event) void {
            // 处理事件
        }
    }.handle;

    try bus.subscribe("market_data.quote", handler1);
    try bus.subscribe("market_data.*", handler2);

    // 发布事件
    bus.publish("market_data.quote", .{
        .market_data = .{
            .instrument_id = "BTC-USDT",
            .bid = 50000.0,
            .ask = 50010.0,
            .bid_size = 10.0,
            .ask_size = 5.0,
            .timestamp = std.time.milliTimestamp() * 1_000_000,
        },
    });

    // 验证统计
    const stats = bus.getStats();
    try std.testing.expect(stats.events_published > 0);
}

// ============================================================================
// 测试 2: Cache 与 MessageBus 集成
// ============================================================================

test "Integration: Cache updates with MessageBus notifications" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{
        .enable_notifications = true,
    });
    defer cache.deinit();

    // 更新 Quote
    try cache.updateQuote(.{
        .symbol = "ETH-USDT",
        .bid = Decimal.fromInt(3000),
        .ask = Decimal.fromInt(3010),
        .bid_size = Decimal.fromInt(100),
        .ask_size = Decimal.fromInt(50),
        .timestamp = Timestamp.now(),
    });

    // 验证缓存
    const quote = cache.getQuote("ETH-USDT");
    try std.testing.expect(quote != null);
    try std.testing.expectEqual(Decimal.fromInt(3000), quote.?.bid);

    // 验证 Cache 统计
    const cache_stats = cache.getStats();
    try std.testing.expect(cache_stats.quote_updates > 0);
}

// ============================================================================
// 测试 3: DataEngine 初始化
// ============================================================================

test "Integration: DataEngine initialization" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var data_engine = DataEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer data_engine.deinit();

    // 验证初始状态
    const stats = data_engine.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.quotes_processed);
    try std.testing.expectEqual(@as(u64, 0), stats.candles_processed);
}

// ============================================================================
// 测试 4: ExecutionEngine 初始化
// ============================================================================

test "Integration: ExecutionEngine initialization" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{});
    defer cache.deinit();

    var engine = ExecutionEngine.init(std.testing.allocator, &bus, &cache, .{
        .max_order_size = Decimal.fromInt(100),
        .max_open_orders = 10,
    });
    defer engine.deinit();

    // 验证初始状态 (没有客户端无法启动)
    const stats = engine.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.orders_submitted);
    try std.testing.expectEqual(@as(u64, 0), stats.orders_filled);
}

// ============================================================================
// 测试 5: LiveTradingEngine 初始化
// ============================================================================

test "Integration: LiveTradingEngine initialization" {
    var engine = LiveTradingEngine.init(std.testing.allocator, .{
        .mode = .event_driven,
        .heartbeat_interval_ms = 1000,
        .tick_interval_ms = 100,
    });
    defer engine.deinit();

    // 验证初始状态
    try std.testing.expect(!engine.isRunning());
}

// ============================================================================
// 测试 6: 事件订阅链集成
// ============================================================================

test "Integration: Event subscription chain" {
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    // 订阅处理器
    const handler = struct {
        fn handle(_: Event) void {
            // 处理事件
        }
    }.handle;

    try bus.subscribe("order.*", handler);
    try bus.subscribe("market_data.*", handler);
    try bus.subscribe("system.*", handler);

    // 发布各种事件
    bus.publish("order.submitted", .{
        .order_submitted = .{
            .order_id = "test-001",
            .instrument_id = "BTC-USDT",
            .side = .buy,
            .order_type = .market,
            .quantity = 1.0,
            .price = null,
            .status = .submitted,
            .timestamp = std.time.milliTimestamp() * 1_000_000,
        },
    });

    bus.publish("market_data.quote", .{
        .market_data = .{
            .instrument_id = "BTC-USDT",
            .bid = 50000.0,
            .ask = 50010.0,
            .bid_size = 10.0,
            .ask_size = 5.0,
            .timestamp = std.time.milliTimestamp() * 1_000_000,
        },
    });

    bus.publish("system.tick", .{
        .tick = .{
            .timestamp = std.time.milliTimestamp() * 1_000_000,
            .tick_number = 1,
        },
    });

    // 验证统计
    const stats = bus.getStats();
    try std.testing.expectEqual(@as(u64, 3), stats.events_published);
}

// ============================================================================
// 测试 7: 完整组件链集成
// ============================================================================

test "Integration: Full component chain" {
    // 创建所有核心组件
    var bus = MessageBus.init(std.testing.allocator);
    defer bus.deinit();

    var cache = Cache.init(std.testing.allocator, &bus, .{
        .enable_notifications = true,
    });
    defer cache.deinit();

    var data_engine = DataEngine.init(std.testing.allocator, &bus, &cache, .{});
    defer data_engine.deinit();

    var execution_engine = ExecutionEngine.init(std.testing.allocator, &bus, &cache, .{
        .max_order_size = Decimal.fromInt(1000),
        .max_open_orders = 100,
    });
    defer execution_engine.deinit();

    // ExecutionEngine 需要客户端才能启动，这里只验证初始化

    // 更新 Cache
    try cache.updateQuote(.{
        .symbol = "BTC-USDT",
        .bid = Decimal.fromInt(50000),
        .ask = Decimal.fromInt(50010),
        .bid_size = Decimal.fromInt(10),
        .ask_size = Decimal.fromInt(5),
        .timestamp = Timestamp.now(),
    });

    // 验证 Cache 更新
    const quote = cache.getQuote("BTC-USDT");
    try std.testing.expect(quote != null);

    // 发布 Tick 事件
    bus.publish("system.tick", .{
        .tick = .{
            .timestamp = std.time.milliTimestamp() * 1_000_000,
            .tick_number = 1,
        },
    });

    // 验证统计
    const bus_stats = bus.getStats();
    try std.testing.expect(bus_stats.events_published > 0);

    const cache_stats = cache.getStats();
    try std.testing.expect(cache_stats.quote_updates > 0);
}
