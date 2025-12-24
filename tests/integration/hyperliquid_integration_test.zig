//! Hyperliquid Integration Tests
//!
//! 测试与 Hyperliquid testnet 的实际连接和交易功能
//!
//! 运行前需要：
//! 1. 复制 test_config.example.json 为 test_config.json
//! 2. 填入你的 Hyperliquid testnet API 密钥
//! 3. 运行: zig build test-integration
//!
//! 环境变量覆盖：
//! - ZIGQUANT_TEST_API_KEY: Hyperliquid 钱包地址
//! - ZIGQUANT_TEST_API_SECRET: 私钥（十六进制）

const std = @import("std");
const zigQuant = @import("zigQuant");

// Test configuration
const TestConfig = struct {
    api_key: []const u8,
    api_secret: []const u8,
    testnet: bool = true,
};

// ============================================================================
// Configuration Loading
// ============================================================================

/// Load test configuration from environment variables or config file
fn loadTestConfig(allocator: std.mem.Allocator) !TestConfig {
    // Try environment variables first
    if (std.process.getEnvVarOwned(allocator, "ZIGQUANT_TEST_API_KEY")) |api_key| {
        errdefer allocator.free(api_key);

        const api_secret = try std.process.getEnvVarOwned(allocator, "ZIGQUANT_TEST_API_SECRET");
        errdefer allocator.free(api_secret);

        return TestConfig{
            .api_key = api_key,
            .api_secret = api_secret,
            .testnet = true,
        };
    } else |_| {
        // Fall back to config file
        const config_path = "tests/integration/test_config.json";

        // Check if file exists
        const file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
            std.debug.print("\n" ++
                "===============================================\n" ++
                "Integration Test Configuration Not Found\n" ++
                "===============================================\n" ++
                "Please create {s} with your credentials:\n" ++
                "  1. Copy test_config.example.json to test_config.json\n" ++
                "  2. Fill in your Hyperliquid testnet API key and secret\n" ++
                "\n" ++
                "Or set environment variables:\n" ++
                "  export ZIGQUANT_TEST_API_KEY=your_wallet_address\n" ++
                "  export ZIGQUANT_TEST_API_SECRET=your_private_key_hex\n" ++
                "===============================================\n\n", .{config_path});
            return err;
        };
        defer file.close();

        const file_content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(file_content);

        const parsed = try std.json.parseFromSlice(
            zigQuant.AppConfig,
            allocator,
            file_content,
            .{ .allocate = .alloc_always },
        );
        defer parsed.deinit();

        const config = parsed.value;

        if (config.exchanges.len == 0) {
            return error.NoExchangeConfigured;
        }

        const exchange_config = config.exchanges[0];

        return TestConfig{
            .api_key = try allocator.dupe(u8, exchange_config.api_key),
            .api_secret = try allocator.dupe(u8, exchange_config.api_secret),
            .testnet = exchange_config.testnet,
        };
    }
}

/// Create a test logger (using std.debug.print for simplicity)
fn createTestLogger(allocator: std.mem.Allocator) !zigQuant.Logger {
    const ConsoleWriter = struct {
        fn write(_: *anyopaque, record: zigQuant.logger.LogRecord) anyerror!void {
            // Get color based on log level
            const color = switch (record.level) {
                .trace => "\x1b[90m", // Bright black (gray)
                .debug => "\x1b[36m", // Cyan
                .info => "\x1b[34m", // Blue
                .warn => "\x1b[33m", // Yellow
                .err => "\x1b[31m", // Red
                .fatal => "\x1b[35m", // Magenta
            };
            const reset = "\x1b[0m";

            // Start with color for entire line
            std.debug.print("{s}[{s}] ", .{ color, record.level.toString() });

            // Format message by replacing placeholders with field values
            var msg = record.message;
            var field_idx: usize = 0;

            while (field_idx < record.fields.len) : (field_idx += 1) {
                // Find the next placeholder
                const placeholder_start = std.mem.indexOf(u8, msg, "{") orelse {
                    // No more placeholders, print remaining message
                    std.debug.print("{s}", .{msg});
                    break;
                };

                // Print text before placeholder
                std.debug.print("{s}", .{msg[0..placeholder_start]});

                // Find end of placeholder
                const placeholder_end = std.mem.indexOfPos(u8, msg, placeholder_start, "}") orelse {
                    // Malformed placeholder, print as-is
                    std.debug.print("{s}", .{msg[placeholder_start..]});
                    break;
                };

                // Print field value
                const field = record.fields[field_idx];
                switch (field.value) {
                    .string => |s| std.debug.print("{s}", .{s}),
                    .int => |i| std.debug.print("{d}", .{i}),
                    .uint => |u| std.debug.print("{d}", .{u}),
                    .float => |f| std.debug.print("{d}", .{f}),
                    .bool => |b| std.debug.print("{}", .{b}),
                }

                // Move to text after placeholder
                msg = msg[placeholder_end + 1 ..];
            }

            // If we've used all fields but there's still message left
            if (field_idx == record.fields.len and msg.len > 0) {
                std.debug.print("{s}", .{msg});
            }

            // Reset color at end of line
            std.debug.print("{s}\n", .{reset});
        }

        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const writer = zigQuant.logger.LogWriter{
        .ptr = @constCast(@ptrCast(&struct {}{})),
        .writeFn = ConsoleWriter.write,
        .flushFn = ConsoleWriter.flush,
        .closeFn = ConsoleWriter.close,
    };

    return zigQuant.Logger.init(allocator, writer, .debug);
}

/// Create HyperliquidConnector for testing
fn createTestConnector(
    allocator: std.mem.Allocator,
    config: TestConfig,
    logger: zigQuant.Logger,
) !*zigQuant.HyperliquidConnector {
    const exchange_config = zigQuant.ExchangeConfig{
        .name = "hyperliquid",
        .api_key = config.api_key,
        .api_secret = config.api_secret,
        .testnet = config.testnet,
    };

    return try zigQuant.HyperliquidConnector.create(allocator, exchange_config, logger);
}

// ============================================================================
// Market Data Tests
// ============================================================================

test "Integration: Connect to Hyperliquid testnet" {
    const allocator = std.testing.allocator;

    const config = loadTestConfig(allocator) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Skipping integration test: config not found\n", .{});
            return error.SkipZigTest;
        }
        return err;
    };
    defer allocator.free(config.api_key);
    defer allocator.free(config.api_secret);

    const logger = try createTestLogger(allocator);
    var connector = try createTestConnector(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();

    // Test connection
    try exchange.connect();
    try std.testing.expect(exchange.isConnected());

    std.debug.print("\n✓ Connected to Hyperliquid testnet\n", .{});

    exchange.disconnect();
    try std.testing.expect(!exchange.isConnected());

    std.debug.print("✓ Disconnected successfully\n", .{});
}

test "Integration: Get ticker for BTC" {
    const allocator = std.testing.allocator;

    const config = loadTestConfig(allocator) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Skipping integration test: config not found\n", .{});
            return error.SkipZigTest;
        }
        return err;
    };
    defer allocator.free(config.api_key);
    defer allocator.free(config.api_secret);

    const logger = try createTestLogger(allocator);
    var connector = try createTestConnector(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();
    try exchange.connect();
    defer exchange.disconnect();

    // Get ticker for BTC
    const pair = zigQuant.TradingPair{ .base = "BTC", .quote = "USDC" };
    const ticker = try exchange.getTicker(pair);

    std.debug.print("\n✓ BTC Ticker:\n", .{});
    std.debug.print("  Bid: ${d}\n", .{ticker.bid.toFloat()});
    std.debug.print("  Ask: ${d}\n", .{ticker.ask.toFloat()});
    std.debug.print("  Last: ${d}\n", .{ticker.last.toFloat()});

    // Sanity checks
    try std.testing.expect(ticker.bid.cmp(zigQuant.Decimal.ZERO) == .gt);
    try std.testing.expect(ticker.ask.cmp(zigQuant.Decimal.ZERO) == .gt);
}

test "Integration: Get orderbook for BTC" {
    const allocator = std.testing.allocator;

    const config = loadTestConfig(allocator) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Skipping integration test: config not found\n", .{});
            return error.SkipZigTest;
        }
        return err;
    };
    defer allocator.free(config.api_key);
    defer allocator.free(config.api_secret);

    const logger = try createTestLogger(allocator);
    var connector = try createTestConnector(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();
    try exchange.connect();
    defer exchange.disconnect();

    // Get orderbook for BTC with depth 5
    const pair = zigQuant.TradingPair{ .base = "BTC", .quote = "USDC" };
    const orderbook = try exchange.getOrderbook(pair, 5);
    defer allocator.free(orderbook.bids);
    defer allocator.free(orderbook.asks);

    std.debug.print("\n✓ BTC Orderbook (depth 5):\n", .{});
    std.debug.print("  Bids:\n", .{});
    for (orderbook.bids, 0..) |bid, i| {
        std.debug.print("    [{d}] Price: ${d}, Qty: {d}\n", .{
            i,
            bid.price.toFloat(),
            bid.quantity.toFloat(),
        });
    }

    std.debug.print("  Asks:\n", .{});
    for (orderbook.asks, 0..) |ask, i| {
        std.debug.print("    [{d}] Price: ${d}, Qty: {d}\n", .{
            i,
            ask.price.toFloat(),
            ask.quantity.toFloat(),
        });
    }

    // Sanity checks
    try std.testing.expect(orderbook.bids.len > 0);
    try std.testing.expect(orderbook.asks.len > 0);

    // Best bid should be less than best ask
    if (orderbook.bids.len > 0 and orderbook.asks.len > 0) {
        try std.testing.expect(orderbook.bids[0].price.cmp(orderbook.asks[0].price) == .lt);
    }
}

// ============================================================================
// Account Tests
// ============================================================================

test "Integration: Get account balance" {
    const allocator = std.testing.allocator;

    const config = loadTestConfig(allocator) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Skipping integration test: config not found\n", .{});
            return error.SkipZigTest;
        }
        return err;
    };
    defer allocator.free(config.api_key);
    defer allocator.free(config.api_secret);

    const logger = try createTestLogger(allocator);
    var connector = try createTestConnector(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();
    try exchange.connect();
    defer exchange.disconnect();

    // Get balance
    const balances = try exchange.getBalance();
    defer allocator.free(balances);

    std.debug.print("\n✓ Account Balances:\n", .{});
    for (balances) |balance| {
        std.debug.print("  {s}:\n", .{balance.asset});
        std.debug.print("    Total: {d}\n", .{balance.total.toFloat()});
        std.debug.print("    Available: {d}\n", .{balance.available.toFloat()});
        std.debug.print("    Locked: {d}\n", .{balance.locked.toFloat()});
    }

    // Should have at least USDC balance
    try std.testing.expect(balances.len > 0);
}

test "Integration: Get positions" {
    const allocator = std.testing.allocator;

    const config = loadTestConfig(allocator) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Skipping integration test: config not found\n", .{});
            return error.SkipZigTest;
        }
        return err;
    };
    defer allocator.free(config.api_key);
    defer allocator.free(config.api_secret);

    const logger = try createTestLogger(allocator);
    var connector = try createTestConnector(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();
    try exchange.connect();
    defer exchange.disconnect();

    // Get positions
    const positions = try exchange.getPositions();
    defer allocator.free(positions);

    std.debug.print("\n✓ Positions ({d}):\n", .{positions.len});
    for (positions) |pos| {
        std.debug.print("  {s}-{s}:\n", .{ pos.pair.base, pos.pair.quote });
        std.debug.print("    Side: {s}\n", .{@tagName(pos.side)});
        std.debug.print("    Size: {d}\n", .{pos.size.toFloat()});
        std.debug.print("    Entry Price: ${d}\n", .{pos.entry_price.toFloat()});
        if (pos.mark_price) |mp| {
            std.debug.print("    Mark Price: ${d}\n", .{mp.toFloat()});
        }
        std.debug.print("    Unrealized PnL: ${d}\n", .{pos.unrealized_pnl.toFloat()});
        std.debug.print("    Leverage: {d}x\n", .{pos.leverage});
    }
}

// ============================================================================
// Order Management Tests
// ============================================================================

test "Integration: OrderManager with Hyperliquid" {
    const allocator = std.testing.allocator;

    const config = loadTestConfig(allocator) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Skipping integration test: config not found\n", .{});
            return error.SkipZigTest;
        }
        return err;
    };
    defer allocator.free(config.api_key);
    defer allocator.free(config.api_secret);

    const logger = try createTestLogger(allocator);
    var connector = try createTestConnector(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();
    try exchange.connect();
    defer exchange.disconnect();

    // Create OrderManager
    var order_mgr = zigQuant.OrderManager.init(allocator, exchange, logger);
    defer order_mgr.deinit();

    std.debug.print("\n✓ OrderManager initialized with Hyperliquid\n", .{});

    // Note: Actual order submission test is commented out to avoid unintended trades
    // Uncomment and adjust parameters for real testing

    // Example order (NOT submitted):
    // const order_request = zigQuant.OrderRequest{
    //     .pair = .{ .base = "BTC", .quote = "USDC" },
    //     .side = .buy,
    //     .order_type = .limit,
    //     .amount = try zigQuant.Decimal.fromString("0.0001"), // Very small amount (0.0001 BTC)
    //     .price = try zigQuant.Decimal.fromString("10000.0"), // Very low price (won't fill at $10k)
    //     .time_in_force = .gtc,
    // };
    // const order = try order_mgr.submitOrder(order_request);
}

// ============================================================================
// Position Tracker Tests
// ============================================================================

test "Integration: PositionTracker with Hyperliquid" {
    const allocator = std.testing.allocator;

    const config = loadTestConfig(allocator) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Skipping integration test: config not found\n", .{});
            return error.SkipZigTest;
        }
        return err;
    };
    defer allocator.free(config.api_key);
    defer allocator.free(config.api_secret);

    const logger = try createTestLogger(allocator);
    var connector = try createTestConnector(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();
    try exchange.connect();
    defer exchange.disconnect();

    // Create PositionTracker
    var tracker = zigQuant.PositionTracker.init(allocator, exchange, logger);
    defer tracker.deinit();

    std.debug.print("\n✓ PositionTracker initialized\n", .{});

    // Sync account state from exchange
    try tracker.syncAccountState();

    std.debug.print("✓ Account state synced from Hyperliquid\n", .{});

    // Get statistics
    const stats = tracker.getStats();
    std.debug.print("\n✓ Statistics:\n", .{});
    std.debug.print("  Positions: {d}\n", .{stats.position_count});
    std.debug.print("  Account Value: ${d}\n", .{stats.account_value.toFloat()});
    std.debug.print("  Realized PnL: ${d}\n", .{stats.total_realized_pnl.toFloat()});
    std.debug.print("  Unrealized PnL: ${d}\n", .{stats.total_unrealized_pnl.toFloat()});

    // Get all positions
    const positions = try tracker.getAllPositions();
    defer allocator.free(positions);

    std.debug.print("\n✓ All positions from tracker: {d}\n", .{positions.len});
}

// ============================================================================
// Full Trading Flow Test (Commented Out - Manual Use Only)
// ============================================================================

// Uncomment this test ONLY when you want to test actual trading
// Make sure to adjust parameters (coin, size, price) carefully!
//
// test "Integration: Full trading flow" {
//     const allocator = std.testing.allocator;
//
//     const config = try loadTestConfig(allocator);
//     defer allocator.free(config.api_key);
//     defer allocator.free(config.api_secret);
//
//     const logger = try createTestLogger(allocator);
//     var connector = try createTestConnector(allocator, config, logger);
//     defer connector.deinit();
//
//     const exchange = connector.interface();
//     try exchange.connect();
//     defer exchange.disconnect();
//
//     // Create components
//     var order_mgr = try zigQuant.OrderManager.init(allocator, exchange, logger);
//     defer order_mgr.deinit();
//
//     var tracker = zigQuant.PositionTracker.init(allocator, exchange, logger);
//     defer tracker.deinit();
//
//     // Sync initial state
//     try tracker.syncAccountState();
//
//     // Submit a test order (very small, very low price to avoid actual fill)
//     const order_request = zigQuant.OrderRequest{
//         .pair = .{ .base = "BTC", .quote = "USDC" },
//         .side = .buy,
//         .order_type = .limit,
//         .amount = try zigQuant.Decimal.fromString("0.0001"), // 0.0001 BTC
//         .price = try zigQuant.Decimal.fromString("10000.0"),  // $10,000 (way below market)
//         .time_in_force = .gtc,
//     };
//
//     std.debug.print("\n📝 Submitting test order...\n", .{});
//     const order = try order_mgr.submitOrder(order_request);
//
//     std.debug.print("✓ Order submitted: ID={d}\n", .{order.exchange_order_id.?});
//
//     // Wait a bit for order to be processed
//     std.time.sleep(2 * std.time.ns_per_s);
//
//     // Cancel the order
//     std.debug.print("\n🗑️  Cancelling order...\n", .{});
//     try order_mgr.cancelOrder(order.exchange_order_id.?);
//
//     std.debug.print("✓ Order cancelled\n", .{});
//
//     // Re-sync account state
//     try tracker.syncAccountState();
//
//     std.debug.print("\n✓ Full trading flow test completed\n", .{});
// }
