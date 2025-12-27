//! Example 13: 事件驱动架构 (v0.5.0)
//!
//! 本示例展示 v0.5.0 的事件驱动架构核心组件:
//! - MessageBus: 消息总线 (Pub/Sub, Request/Response)
//! - Cache: 中央数据缓存
//! - DataEngine: 数据引擎
//! - ExecutionEngine: 执行引擎
//! - LiveTradingEngine: 统一交易接口
//!
//! 运行: zig build run-example-event-driven

const std = @import("std");
const zigQuant = @import("zigQuant");

const MessageBus = zigQuant.MessageBus;
const Event = zigQuant.message_bus.Event;
const Cache = zigQuant.Cache;
const DataEngine = zigQuant.DataEngine;
const ExecutionEngine = zigQuant.ExecutionEngine;
const LiveTradingEngine = zigQuant.LiveTradingEngine;
const Decimal = zigQuant.Decimal;
const Timestamp = zigQuant.Timestamp;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("       zigQuant v0.5.0 - Event-Driven Architecture Demo\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // 1. MessageBus 演示
    // ========================================================================
    std.debug.print("----------------------------------------------------------------\n", .{});
    std.debug.print("  1. MessageBus - Message Bus\n", .{});
    std.debug.print("----------------------------------------------------------------\n", .{});

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    // 订阅市场数据事件
    const market_handler = struct {
        fn handle(event: Event) void {
            switch (event) {
                .market_data => |m| {
                    std.debug.print("     [MarketData] {s}: bid={?d:.2}, ask={?d:.2}\n", .{
                        m.instrument_id,
                        m.bid,
                        m.ask,
                    });
                },
                else => {},
            }
        }
    }.handle;

    try bus.subscribe("market_data.*", market_handler);
    std.debug.print("  [OK] Subscribed to market_data.* events\n", .{});

    // 订阅订单事件
    const order_handler = struct {
        fn handle(event: Event) void {
            switch (event) {
                .order_submitted => |o| {
                    std.debug.print("     [Order] {s}: {} {d:.4} @ market\n", .{
                        o.order_id,
                        o.side,
                        o.quantity,
                    });
                },
                else => {},
            }
        }
    }.handle;

    try bus.subscribe("order.*", order_handler);
    std.debug.print("  [OK] Subscribed to order.* events\n", .{});

    // 发布市场数据事件
    std.debug.print("\n  Publishing market data events...\n", .{});
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

    // 发布订单事件
    std.debug.print("  Publishing order events...\n", .{});
    bus.publish("order.submitted", .{
        .order_submitted = .{
            .order_id = "test-001",
            .instrument_id = "BTC-USDT",
            .side = .buy,
            .order_type = .market,
            .quantity = 0.1,
            .price = null,
            .status = .submitted,
            .timestamp = std.time.milliTimestamp() * 1_000_000,
        },
    });

    const bus_stats = bus.getStats();
    std.debug.print("\n  MessageBus Stats:\n", .{});
    std.debug.print("    - Events published: {d}\n", .{bus_stats.events_published});
    std.debug.print("    - Subscribers: {d}\n", .{bus_stats.subscribers_count});

    // ========================================================================
    // 2. Cache 演示
    // ========================================================================
    std.debug.print("\n", .{});
    std.debug.print("----------------------------------------------------------------\n", .{});
    std.debug.print("  2. Cache - Central Data Store\n", .{});
    std.debug.print("----------------------------------------------------------------\n", .{});

    var cache = Cache.init(allocator, &bus, .{
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
    std.debug.print("  [OK] Updated quote for ETH-USDT\n", .{});

    // 读取 Quote
    if (cache.getQuote("ETH-USDT")) |quote| {
        std.debug.print("  [GET] ETH-USDT: bid={d}, ask={d}\n", .{
            quote.bid.toFloat(),
            quote.ask.toFloat(),
        });
    }

    // ========================================================================
    // 3. DataEngine 演示
    // ========================================================================
    std.debug.print("\n", .{});
    std.debug.print("----------------------------------------------------------------\n", .{});
    std.debug.print("  3. DataEngine - Data Processing\n", .{});
    std.debug.print("----------------------------------------------------------------\n", .{});

    var data_engine = DataEngine.init(allocator, &bus, &cache, .{});
    defer data_engine.deinit();

    const data_stats = data_engine.getStats();
    std.debug.print("  DataEngine Stats:\n", .{});
    std.debug.print("    - Quotes processed: {d}\n", .{data_stats.quotes_processed});
    std.debug.print("    - Candles processed: {d}\n", .{data_stats.candles_processed});

    // ========================================================================
    // 4. ExecutionEngine 演示
    // ========================================================================
    std.debug.print("\n", .{});
    std.debug.print("----------------------------------------------------------------\n", .{});
    std.debug.print("  4. ExecutionEngine - Order Execution\n", .{});
    std.debug.print("----------------------------------------------------------------\n", .{});

    var execution_engine = ExecutionEngine.init(allocator, &bus, &cache, .{
        .max_order_size = Decimal.fromInt(100),
        .max_open_orders = 10,
    });
    defer execution_engine.deinit();

    try execution_engine.start();
    std.debug.print("  [OK] ExecutionEngine started\n", .{});

    const exec_stats = execution_engine.getStats();
    std.debug.print("  ExecutionEngine Stats:\n", .{});
    std.debug.print("    - Orders submitted: {d}\n", .{exec_stats.orders_submitted});
    std.debug.print("    - Orders filled: {d}\n", .{exec_stats.orders_filled});

    // ========================================================================
    // 5. LiveTradingEngine 演示
    // ========================================================================
    std.debug.print("\n", .{});
    std.debug.print("----------------------------------------------------------------\n", .{});
    std.debug.print("  5. LiveTradingEngine - Unified Interface\n", .{});
    std.debug.print("----------------------------------------------------------------\n", .{});

    var live_engine = LiveTradingEngine.init(allocator, .{
        .mode = .event_driven,
        .heartbeat_interval_ms = 1000,
        .tick_interval_ms = 100,
    });
    defer live_engine.deinit();

    std.debug.print("  [OK] LiveTradingEngine initialized in event-driven mode\n", .{});

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("  Example completed successfully!\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});
}

test "event driven example compiles" {
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    var cache = Cache.init(allocator, &bus, .{});
    defer cache.deinit();

    var data_engine = DataEngine.init(allocator, &bus, &cache, .{});
    defer data_engine.deinit();

    var execution_engine = ExecutionEngine.init(allocator, &bus, &cache, .{});
    defer execution_engine.deinit();

    try std.testing.expect(bus.getStats().events_published == 0);
}
