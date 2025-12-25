//! Position Management Integration Test
//!
//! Tests the complete position lifecycle with Hyperliquid testnet:
//! 1. Check initial positions
//! 2. Open position (market buy order)
//! 3. Verify position increased
//! 4. Close position (market sell with reduce_only)
//! 5. Verify position closed
//!
//! Run with: zig build test-position-management
//!
//! Prerequisites:
//! 1. Copy test_config.example.json to test_config.json
//! 2. Fill in your Hyperliquid testnet credentials
//! 3. Ensure testnet account has USDC balance
//!
//! Environment variables:
//! - ZIGQUANT_TEST_API_KEY: Hyperliquid wallet address
//! - ZIGQUANT_TEST_API_SECRET: Private key (hex)

const std = @import("std");
const zigQuant = @import("zigQuant");

const HyperliquidConnector = zigQuant.HyperliquidConnector;
const PositionTracker = zigQuant.PositionTracker;
const OrderManager = zigQuant.OrderManager;
const Logger = zigQuant.Logger;
const ExchangeConfig = zigQuant.ExchangeConfig;
const TradingPair = zigQuant.TradingPair;
const Side = zigQuant.Side;
const OrderType = zigQuant.OrderType;
const TimeInForce = zigQuant.TimeInForce;
const Decimal = zigQuant.Decimal;

// ============================================================================
// Test Configuration
// ============================================================================

const TestConfig = struct {
    api_key: []const u8,
    api_secret: []const u8,
    testnet: bool = true,
};

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

// ============================================================================
// Logger Setup
// ============================================================================

const TestLogWriter = struct {
    fn write(_: *anyopaque, record: zigQuant.logger.LogRecord) anyerror!void {
        const color = switch (record.level) {
            .trace => "\x1b[90m",
            .debug => "\x1b[36m",
            .info => "\x1b[34m",
            .warn => "\x1b[33m",
            .err => "\x1b[31m",
            .fatal => "\x1b[35m",
        };
        const reset = "\x1b[0m";

        std.debug.print("{s}[{s}] {s}{s}\n", .{ color, record.level.toString(), record.message, reset });
    }

    fn flush(_: *anyopaque) anyerror!void {}
    fn close(_: *anyopaque) void {}
};

fn createTestLogger(allocator: std.mem.Allocator) Logger {
    const dummy = struct {};
    const log_writer = zigQuant.logger.LogWriter{
        .ptr = @constCast(@ptrCast(&dummy)),
        .writeFn = TestLogWriter.write,
        .flushFn = TestLogWriter.flush,
        .closeFn = TestLogWriter.close,
    };
    return Logger.init(allocator, log_writer, .debug);
}

// ============================================================================
// Test Main
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ MEMORY LEAK DETECTED!\n", .{});
            std.process.exit(1);
        } else {
            std.debug.print("✅ No memory leaks\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Position Management Integration Test\n", .{});
    std.debug.print("=" ** 80 ++ "\n\n", .{});

    // Load test configuration
    std.debug.print("Loading test configuration...\n", .{});
    const test_config = loadTestConfig(allocator) catch |err| {
        std.debug.print("Failed to load test configuration: {}\n", .{err});
        return err;
    };
    defer allocator.free(test_config.api_key);
    defer allocator.free(test_config.api_secret);

    // Create logger
    const logger = createTestLogger(allocator);

    // Create exchange config
    const exchange_config = ExchangeConfig{
        .name = "hyperliquid",
        .testnet = test_config.testnet,
        .api_key = test_config.api_key,
        .api_secret = test_config.api_secret,
    };

    // Test Phase 1: Create Hyperliquid Connector
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 1: Creating Hyperliquid Connector\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    var connector = try HyperliquidConnector.create(allocator, exchange_config, logger);
    defer connector.destroy();

    const exchange = connector.interface();
    std.debug.print("✓ Connector created: {s}\n", .{exchange.getName()});

    // Connect to exchange
    std.debug.print("Connecting to exchange...\n", .{});
    try exchange.connect();
    std.debug.print("✓ Connected to exchange\n", .{});

    // Test Phase 2: Create PositionTracker and OrderManager
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 2: Creating PositionTracker and OrderManager\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    var position_tracker = PositionTracker.init(allocator, exchange, logger);
    defer position_tracker.deinit();
    std.debug.print("✓ PositionTracker created\n", .{});

    var order_manager = OrderManager.init(allocator, exchange, logger);
    defer order_manager.deinit();
    std.debug.print("✓ OrderManager created\n", .{});

    // Test Phase 3: Check initial positions
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 3: Checking initial positions\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    try position_tracker.syncAccountState();
    const all_positions = try position_tracker.getAllPositions();
    defer allocator.free(all_positions);

    std.debug.print("Initial positions: {d} open positions\n", .{all_positions.len});
    for (all_positions) |pos| {
        std.debug.print("  {s}: {s} {d} @ ${d}\n", .{
            pos.coin,
            @tagName(pos.side),
            pos.szi.abs().toFloat(),
            pos.entry_px.toFloat(),
        });
    }

    // Create a trading pair (BTC-USDC)
    const pair = TradingPair{
        .base = "BTC",
        .quote = "USDC",
    };

    // Check if there's an existing BTC position
    const initial_btc_position = position_tracker.getPosition(pair.base); // Use coin name
    const initial_size = if (initial_btc_position) |pos| pos.szi.abs() else Decimal.ZERO;

    std.debug.print("Initial BTC position size: {d}\n", .{initial_size.toFloat()});

    // Test Phase 4: Open position (market buy order)
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 4: Opening position (market buy)\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    // Use small amount for testing: 0.001 BTC (~$88.6)
    const trade_amount = try Decimal.fromString("0.001");

    std.debug.print("Submitting MARKET BUY order: {d} {s}\n", .{
        trade_amount.toFloat(),
        pair.base,
    });

    // Submit market buy order (should fill immediately)
    const buy_order = try order_manager.submitOrder(
        pair,
        .buy,
        .market, // Market order for immediate execution
        trade_amount,
        null, // Market orders don't have a price
        .ioc, // Immediate-or-cancel
        false, // Not reduce-only
    );

    std.debug.print("✓ Market buy order submitted\n", .{});
    if (buy_order.client_order_id) |client_id| {
        std.debug.print("  Client Order ID: {s}\n", .{client_id});
    }
    if (buy_order.exchange_order_id) |ex_id| {
        std.debug.print("  Exchange Order ID: {d}\n", .{ex_id});
    }
    std.debug.print("  Status: {s}\n", .{@tagName(buy_order.status)});
    std.debug.print("  Filled: {d} / {d}\n", .{
        buy_order.filled_amount.toFloat(),
        buy_order.amount.toFloat(),
    });

    // Wait for order to fill
    std.debug.print("Waiting 3 seconds for order to fill...\n", .{});
    std.Thread.sleep(3 * std.time.ns_per_s);

    // Test Phase 5: Verify position increased
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 5: Verifying position increased\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    // Sync positions from exchange
    try position_tracker.syncAccountState();

    const btc_position = position_tracker.getPosition(pair.base); // Use coin name
    var all_passed = true;

    if (btc_position) |pos| {
        std.debug.print("✓ BTC position found\n", .{});
        std.debug.print("  Side: {s}\n", .{@tagName(pos.side)});
        std.debug.print("  Size (szi): {d} BTC\n", .{pos.szi.toFloat()});
        std.debug.print("  Abs Size: {d} BTC\n", .{pos.szi.abs().toFloat()});
        std.debug.print("  Entry Price: ${d}\n", .{pos.entry_px.toFloat()});
        std.debug.print("  Unrealized PnL: ${d}\n", .{pos.unrealized_pnl.toFloat()});
        std.debug.print("  Leverage: {d}x\n", .{pos.leverage.value});

        // Verify position increased
        const expected_size = initial_size.add(trade_amount);
        const actual_size = pos.szi.abs();
        const size_diff = actual_size.sub(expected_size);
        const tolerance = try Decimal.fromString("0.0001"); // Allow 0.0001 BTC difference

        if (size_diff.abs().cmp(tolerance) == .lt) {
            std.debug.print("✅ PASSED: Position size increased by ~{d} BTC\n", .{trade_amount.toFloat()});
        } else {
            std.debug.print("❌ FAILED: Expected size {d}, got {d} (diff: {d})\n", .{
                expected_size.toFloat(),
                actual_size.toFloat(),
                size_diff.toFloat(),
            });
            all_passed = false;
        }

        if (pos.side != .buy) {
            std.debug.print("❌ FAILED: Expected side 'buy', got '{s}'\n", .{@tagName(pos.side)});
            all_passed = false;
        }
    } else {
        std.debug.print("❌ FAILED: BTC position not found after market buy\n", .{});
        all_passed = false;
    }

    // Test Phase 6: Close position (market sell with reduce_only)
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 6: Closing position (market sell, reduce_only)\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    std.debug.print("Submitting MARKET SELL order (reduce_only): {d} {s}\n", .{
        trade_amount.toFloat(),
        pair.base,
    });

    // Submit market sell order with reduce_only to close the position
    const sell_order = try order_manager.submitOrder(
        pair,
        .sell,
        .market, // Market order for immediate execution
        trade_amount,
        null, // Market orders don't have a price
        .ioc, // Immediate-or-cancel
        true, // reduce_only = true (only close existing position)
    );

    std.debug.print("✓ Market sell order (reduce_only) submitted\n", .{});
    if (sell_order.client_order_id) |client_id| {
        std.debug.print("  Client Order ID: {s}\n", .{client_id});
    }
    if (sell_order.exchange_order_id) |ex_id| {
        std.debug.print("  Exchange Order ID: {d}\n", .{ex_id});
    }
    std.debug.print("  Status: {s}\n", .{@tagName(sell_order.status)});
    std.debug.print("  Filled: {d} / {d}\n", .{
        sell_order.filled_amount.toFloat(),
        sell_order.amount.toFloat(),
    });

    // Wait for order to fill
    std.debug.print("Waiting 3 seconds for order to fill...\n", .{});
    std.Thread.sleep(3 * std.time.ns_per_s);

    // Test Phase 7: Verify position closed
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 7: Verifying position closed/reduced\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    // Sync positions from exchange
    try position_tracker.syncAccountState();

    const final_btc_position = position_tracker.getPosition(pair.base); // Use coin name

    if (final_btc_position) |pos| {
        // Position should be reduced by trade_amount
        const final_size = pos.szi.abs();
        const size_diff = initial_size.sub(final_size);
        const tolerance = try Decimal.fromString("0.0001");

        std.debug.print("Final BTC position:\n", .{});
        std.debug.print("  Size: {d} BTC (initial: {d}, change: {d})\n", .{
            final_size.toFloat(),
            initial_size.toFloat(),
            size_diff.toFloat(),
        });

        if (size_diff.abs().cmp(tolerance) == .lt) {
            std.debug.print("✅ PASSED: Position returned to initial size\n", .{});
        } else {
            std.debug.print("⚠️  WARNING: Position size not exactly initial (diff: {d} BTC)\n", .{
                size_diff.toFloat(),
            });
        }
    } else {
        // If position was fully closed (initial was zero)
        if (initial_size.cmp(Decimal.ZERO) == .eq) {
            std.debug.print("✅ PASSED: Position closed (initial size was 0)\n", .{});
        } else {
            std.debug.print("⚠️  WARNING: Position not found (initial size was {d})\n", .{
                initial_size.toFloat(),
            });
        }
    }

    // Disconnect
    std.debug.print("\nDisconnecting from exchange...\n", .{});
    exchange.disconnect();
    std.debug.print("✓ Disconnected\n", .{});

    // Final results
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    if (all_passed) {
        std.debug.print("✅ ALL TESTS PASSED\n", .{});
        std.debug.print("=" ** 80 ++ "\n\n", .{});
    } else {
        std.debug.print("❌ SOME TESTS FAILED\n", .{});
        std.debug.print("=" ** 80 ++ "\n\n", .{});
        std.process.exit(1);
    }
}
