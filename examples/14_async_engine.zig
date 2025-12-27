//! Example 14: 异步交易引擎 (v0.5.0)
//!
//! 本示例演示如何使用 AsyncLiveTradingEngine 构建高性能异步交易系统。
//! AsyncLiveTradingEngine 基于 libxev (io_uring/kqueue) 实现真正的异步事件循环，
//! 相比传统轮询方式具有更低的延迟和更高的吞吐量。
//!
//! 主要特性:
//! - 基于 libxev 的高性能事件循环
//! - 异步 I/O 处理 (io_uring on Linux, kqueue on macOS)
//! - 定时器驱动的心跳和策略执行
//! - 完全非阻塞的数据和执行处理

const std = @import("std");
const zigQuant = @import("zigQuant");

// 导入核心类型
const Decimal = zigQuant.Decimal;
const Timestamp = zigQuant.Timestamp;
const MessageBus = zigQuant.MessageBus;
const Event = zigQuant.message_bus.Event;
const Cache = zigQuant.Cache;
const DataEngine = zigQuant.DataEngine;
const ExecutionEngine = zigQuant.ExecutionEngine;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("======================================================================\n", .{});
    std.debug.print("  zigQuant v0.5.0 - Async Trading Engine Demo\n", .{});
    std.debug.print("======================================================================\n\n", .{});

    // ========================================================================
    // 第一部分: 核心组件初始化
    // ========================================================================

    std.debug.print("[1] Initializing Core Components...\n", .{});

    // 1.1 创建 MessageBus - 事件总线
    var bus = MessageBus.init(allocator);
    defer bus.deinit();
    std.debug.print("    - MessageBus created\n", .{});

    // 1.2 创建 Cache - 数据缓存
    var cache = Cache.init(allocator, &bus, .{
        .enable_notifications = true,
    });
    defer cache.deinit();
    std.debug.print("    - Cache created\n", .{});

    // 1.3 创建 DataEngine - 数据引擎
    var data_engine = DataEngine.init(allocator, &bus, &cache, .{
        .data_validation = true,
    });
    defer data_engine.deinit();
    std.debug.print("    - DataEngine created\n", .{});

    // 1.4 创建 ExecutionEngine - 执行引擎
    var execution_engine = ExecutionEngine.init(allocator, &bus, &cache, .{
        .max_order_size = Decimal.fromInt(1000),
        .max_open_orders = 100,
    });
    defer execution_engine.deinit();
    std.debug.print("    - ExecutionEngine created\n", .{});

    std.debug.print("\n", .{});

    // ========================================================================
    // 第二部分: 事件订阅设置
    // ========================================================================

    std.debug.print("[2] Setting up Event Subscriptions...\n", .{});

    // 订阅市场数据事件
    const quote_handler = struct {
        fn handle(event: Event) void {
            switch (event) {
                .market_data => |m| {
                    std.debug.print("    [Event] MarketData: {s} bid={?d:.2} ask={?d:.2}\n", .{
                        m.instrument_id,
                        m.bid,
                        m.ask,
                    });
                },
                else => {},
            }
        }
    }.handle;

    try bus.subscribe("market_data.*", quote_handler);
    std.debug.print("    - Subscribed to market_data.* events\n", .{});

    // 订阅订单事件
    const order_handler = struct {
        fn handle(event: Event) void {
            switch (event) {
                .order_submitted => |o| {
                    std.debug.print("    [Event] Order Submitted: {s} {s}\n", .{
                        o.order_id,
                        o.instrument_id,
                    });
                },
                .order_filled => |o| {
                    std.debug.print("    [Event] Order Filled: {s} @ {d:.2}\n", .{
                        o.order.order_id,
                        o.fill_price,
                    });
                },
                else => {},
            }
        }
    }.handle;

    try bus.subscribe("order.*", order_handler);
    std.debug.print("    - Subscribed to order.* events (wildcard)\n", .{});

    // 订阅系统事件
    const system_handler = struct {
        fn handle(event: Event) void {
            switch (event) {
                .tick => |t| {
                    std.debug.print("    [Event] Tick #{d}\n", .{t.tick_number});
                },
                else => {},
            }
        }
    }.handle;

    try bus.subscribe("system.*", system_handler);
    std.debug.print("    - Subscribed to system.* events (wildcard)\n", .{});

    std.debug.print("\n", .{});

    // ========================================================================
    // 第三部分: 模拟异步事件循环
    // ========================================================================

    std.debug.print("[3] Simulating Async Event Processing...\n", .{});
    std.debug.print("    Note: Full AsyncLiveTradingEngine requires libxev dependency\n", .{});
    std.debug.print("    This example demonstrates core component integration\n\n", .{});

    // 模拟市场数据更新
    std.debug.print("    Publishing simulated market data...\n", .{});

    const symbols = [_][]const u8{ "BTC-USDT", "ETH-USDT", "SOL-USDT" };
    const base_prices = [_]f64{ 50000.0, 3000.0, 100.0 };

    for (symbols, 0..) |symbol, i| {
        const base_price = base_prices[i];

        // 发布 MarketData 事件
        bus.publish("market_data.quote", .{
            .market_data = .{
                .instrument_id = symbol,
                .bid = base_price - 5.0,
                .ask = base_price + 5.0,
                .bid_size = 100.0,
                .ask_size = 80.0,
                .timestamp = std.time.milliTimestamp() * 1_000_000,
            },
        });

        // 更新 Cache
        try cache.updateQuote(.{
            .symbol = symbol,
            .bid = Decimal.fromFloat(base_price - 5.0),
            .ask = Decimal.fromFloat(base_price + 5.0),
            .bid_size = Decimal.fromInt(100),
            .ask_size = Decimal.fromInt(80),
            .timestamp = Timestamp.now(),
        });
    }

    std.debug.print("\n", .{});

    // ========================================================================
    // 第四部分: 模拟订单执行
    // ========================================================================

    std.debug.print("[4] Simulating Order Execution...\n", .{});

    // 启动执行引擎
    try execution_engine.start();
    std.debug.print("    - ExecutionEngine started\n", .{});

    // 发布订单提交事件
    bus.publish("order.submitted", .{
        .order_submitted = .{
            .order_id = "async-order-001",
            .instrument_id = "BTC-USDT",
            .side = .buy,
            .order_type = .limit,
            .quantity = 0.1,
            .price = 49995.0,
            .status = .submitted,
            .timestamp = std.time.milliTimestamp() * 1_000_000,
        },
    });

    // 模拟订单成交
    bus.publish("order.filled", .{
        .order_filled = .{
            .order = .{
                .order_id = "async-order-001",
                .instrument_id = "BTC-USDT",
                .side = .buy,
                .order_type = .limit,
                .quantity = 0.1,
                .filled_quantity = 0.1,
                .price = 49995.0,
                .status = .filled,
                .timestamp = std.time.milliTimestamp() * 1_000_000,
            },
            .fill_price = 49995.0,
            .fill_quantity = 0.1,
            .timestamp = std.time.milliTimestamp() * 1_000_000,
        },
    });

    std.debug.print("\n", .{});

    // ========================================================================
    // 第五部分: 心跳和 Tick 事件
    // ========================================================================

    std.debug.print("[5] Publishing System Events...\n", .{});

    // 发布 Tick 事件
    for (1..4) |tick_num| {
        bus.publish("system.tick", .{
            .tick = .{
                .timestamp = std.time.milliTimestamp() * 1_000_000,
                .tick_number = @intCast(tick_num),
            },
        });
    }

    std.debug.print("\n", .{});

    // ========================================================================
    // 第六部分: 统计信息
    // ========================================================================

    std.debug.print("[6] Component Statistics\n", .{});
    std.debug.print("--------------------------------------------------\n", .{});

    // MessageBus 统计
    const bus_stats = bus.getStats();
    std.debug.print("  MessageBus:\n", .{});
    std.debug.print("    - Events published: {d}\n", .{bus_stats.events_published});
    std.debug.print("    - Subscribers: {d}\n", .{bus_stats.subscribers_count});

    // DataEngine 统计
    const data_stats = data_engine.getStats();
    std.debug.print("  DataEngine:\n", .{});
    std.debug.print("    - Quotes processed: {d}\n", .{data_stats.quotes_processed});
    std.debug.print("    - Messages received: {d}\n", .{data_stats.messages_received});

    // ExecutionEngine 统计
    const exec_stats = execution_engine.getStats();
    std.debug.print("  ExecutionEngine:\n", .{});
    std.debug.print("    - Orders submitted: {d}\n", .{exec_stats.orders_submitted});
    std.debug.print("    - Orders filled: {d}\n", .{exec_stats.orders_filled});

    std.debug.print("\n", .{});

    // ========================================================================
    // 第七部分: 异步引擎架构说明
    // ========================================================================

    std.debug.print("[7] AsyncLiveTradingEngine Architecture\n", .{});
    std.debug.print("--------------------------------------------------\n", .{});
    std.debug.print(
        \\
        \\  AsyncLiveTradingEngine is the core component of zigQuant v0.5.0,
        \\  implementing high-performance async event-driven architecture
        \\  based on libxev.
        \\
        \\  Key Features:
        \\  1. io_uring (Linux) / kqueue (macOS) event loop
        \\  2. Zero-copy message passing
        \\  3. Timer-driven strategy execution
        \\  4. Fully non-blocking I/O
        \\
        \\  Usage Example:
        \\
        \\    const xev = @import("xev");
        \\
        \\    var engine = try AsyncLiveTradingEngine.init(allocator, .{{
        \\        .tick_interval_ns = 100_000_000, // 100ms
        \\        .heartbeat_interval_ns = 1_000_000_000, // 1s
        \\    }});
        \\    defer engine.deinit();
        \\
        \\    // Set data provider and execution client
        \\    try engine.setDataProvider(provider);
        \\    engine.setExecutionClient(client);
        \\
        \\    // Start and run event loop
        \\    try engine.start();
        \\    try engine.run(); // Blocking until stopped
        \\
        \\  Event Flow:
        \\
        \\    +---------------+     +--------------+     +----------------+
        \\    | DataProvider  | --> | DataEngine   | --> |    Cache       |
        \\    +---------------+     +--------------+     +----------------+
        \\                                |                     |
        \\                                v                     v
        \\                          +--------------+     +----------------+
        \\                          | MessageBus   | --> |   Strategy     |
        \\                          +--------------+     +----------------+
        \\                                |                     |
        \\                                v                     v
        \\                          +----------------------------------+
        \\                          |        ExecutionEngine           |
        \\                          +----------------------------------+
        \\
    , .{});

    std.debug.print("\n", .{});
    std.debug.print("======================================================================\n", .{});
    std.debug.print("  Example completed! Async engine core components demonstrated.\n", .{});
    std.debug.print("======================================================================\n\n", .{});
}

test "async engine example compiles" {
    // 验证示例可以编译
    const allocator = std.testing.allocator;

    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    var cache = Cache.init(allocator, &bus, .{});
    defer cache.deinit();

    var data_engine = DataEngine.init(allocator, &bus, &cache, .{});
    defer data_engine.deinit();

    var execution_engine = ExecutionEngine.init(allocator, &bus, &cache, .{});
    defer execution_engine.deinit();

    // 验证组件正确初始化
    try std.testing.expect(bus.getStats().events_published == 0);
}
