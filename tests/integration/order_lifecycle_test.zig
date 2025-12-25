//! Order Lifecycle Integration Test
//!
//! Tests the complete order lifecycle with Hyperliquid testnet:
//! 1. Submit limit order
//! 2. Query order status
//! 3. Cancel order
//! 4. Verify order cancelled
//!
//! Run with: zig build test-order-lifecycle
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
const OrderManager = zigQuant.OrderManager;
const Logger = zigQuant.Logger;
const ExchangeConfig = zigQuant.ExchangeConfig;
const TradingPair = zigQuant.TradingPair;
const Side = zigQuant.Side;
const OrderType = zigQuant.OrderType;
const TimeInForce = zigQuant.TimeInForce;
const OrderStatus = zigQuant.OrderStatus;
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
    std.debug.print("Order Lifecycle Integration Test\n", .{});
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

    // Test Phase 2: Create OrderManager
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 2: Creating OrderManager\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    var order_manager = OrderManager.init(allocator, exchange, logger);
    defer order_manager.deinit();
    std.debug.print("✓ OrderManager created\n", .{});

    // Test Phase 3: Check account balance
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 3: Checking account balance\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    // Get user state to check balance
    // IMPORTANT: Use api_key (main account address), not api_secret derived address!
    // api_key = main account with funds
    // api_secret = API wallet for signing (authorized to trade on behalf of main account)
    const user_state = try connector.info_api.getUserState(connector.config.api_key);
    defer user_state.deinit();

    std.debug.print("Account balance (api_key: {s}):\n", .{connector.config.api_key});
    std.debug.print("  Withdrawable: {s} USDC\n", .{user_state.value.withdrawable});
    std.debug.print("  Account Value: {s} USDC\n", .{user_state.value.crossMarginSummary.accountValue});
    std.debug.print("  Total Margin Used: {s} USDC\n", .{user_state.value.crossMarginSummary.totalMarginUsed});

    // Test Phase 4: Submit a limit order
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 4: Submitting limit order\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    // Create a trading pair (BTC-USDC) - better liquidity on testnet
    const pair = TradingPair{
        .base = "BTC",
        .quote = "USDC",
    };

    // Get meta and asset contexts to determine mark price (reference price for validation)
    std.debug.print("Fetching asset contexts for {s}-{s}...\n", .{ pair.base, pair.quote });

    // Access info_api through connector
    const parsed = try connector.info_api.getMetaAndAssetCtxs();
    defer parsed.deinit();

    const response_array = parsed.value.array;
    if (response_array.items.len != 2) {
        std.debug.print("❌ FAILED: Invalid response format\n", .{});
        return error.InvalidResponse;
    }

    // First element: metadata with universe
    const meta_obj = response_array.items[0].object;
    const universe = meta_obj.get("universe") orelse return error.MissingUniverse;
    const universe_array = universe.array;

    // Find BTC in the universe to get its asset index
    var btc_index: ?usize = null;
    for (universe_array.items, 0..) |asset, i| {
        const asset_obj = asset.object;
        const name = asset_obj.get("name") orelse continue;
        if (std.mem.eql(u8, name.string, "BTC")) {
            btc_index = i;
            break;
        }
    }

    if (btc_index == null) {
        std.debug.print("❌ FAILED: BTC not found in asset universe\n", .{});
        return error.AssetNotFound;
    }

    // Second element: array of asset contexts
    const contexts_array = response_array.items[1].array;
    if (btc_index.? >= contexts_array.items.len) {
        std.debug.print("❌ FAILED: BTC index out of range\n", .{});
        return error.IndexOutOfRange;
    }

    const btc_ctx = contexts_array.items[btc_index.?].object;

    // Get mark price for BTC
    const mark_price_str = blk: {
        if (btc_ctx.get("markPx")) |mp| {
            if (mp == .string) break :blk mp.string;
        }
        if (btc_ctx.get("midPx")) |mp| {
            if (mp == .string) break :blk mp.string;
        }
        std.debug.print("❌ FAILED: No mark price available for BTC\n", .{});
        return error.NoPriceAvailable;
    };

    const mark_price = try Decimal.fromString(mark_price_str);
    std.debug.print("✓ Mark price: ${d}\n", .{mark_price.toFloat()});

    // Get oracle price - this might be the "reference price" for validation
    const oracle_price = blk: {
        if (btc_ctx.get("oraclePx")) |oracle_px_val| {
            if (oracle_px_val == .string) {
                std.debug.print("  Oracle price: ${s}\n", .{oracle_px_val.string});
                break :blk try Decimal.fromString(oracle_px_val.string);
            }
        }
        break :blk mark_price; // Fallback to mark if no oracle
    };

    if (btc_ctx.get("midPx")) |mid_px_val| {
        if (mid_px_val == .string) {
            std.debug.print("  Mid price: ${s}\n", .{mid_px_val.string});
        }
    }

    const amount = try Decimal.fromString("0.01"); // 0.01 BTC (~$886) - minimum size for BTC on testnet

    // Try using oracle price as the reference for order placement
    // Oracle price might be the actual "reference price" used by Hyperliquid for validation
    const limit_price_decimal = oracle_price;

    // Round to whole number to satisfy BTC tick size requirements
    const price_float = limit_price_decimal.toFloat();
    const price_rounded = @floor(price_float);
    const price_str = try std.fmt.allocPrint(allocator, "{d:.0}", .{price_rounded});
    defer allocator.free(price_str);
    const limit_price = try Decimal.fromString(price_str);

    std.debug.print("Submitting LIMIT order (挂单): BUY {d} {s} @ ${d}\n", .{
        amount.toFloat(),
        pair.base,
        limit_price.toFloat(),
    });
    std.debug.print("  Oracle price: ${d}, Order price: ${d} (using oracle as reference)\n", .{
        oracle_price.toFloat(),
        limit_price.toFloat(),
    });

    // Submit limit order at mark price
    const submitted_order = try order_manager.submitOrder(
        pair,
        .buy,
        .limit, // 限价单（挂单）
        amount,
        limit_price, // Price at mark price
        .gtc, // Good-till-cancelled
        false, // Not reduce-only
    );

    std.debug.print("✓ Order submitted successfully\n", .{});
    if (submitted_order.client_order_id) |client_id| {
        std.debug.print("  Client Order ID: {s}\n", .{client_id});
    }
    if (submitted_order.exchange_order_id) |ex_id| {
        std.debug.print("  Exchange Order ID: {d}\n", .{ex_id});
    }
    std.debug.print("  Status: {s}\n", .{@tagName(submitted_order.status)});

    // Verify exchange order ID exists
    if (submitted_order.exchange_order_id == null) {
        std.debug.print("❌ FAILED: Exchange order ID is null\n", .{});
        return error.OrderSubmissionFailed;
    }

    const exchange_order_id = submitted_order.exchange_order_id.?;

    // Test Phase 5: Query order status
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 5: Querying order status\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    // Wait a moment for order to be processed
    std.debug.print("Waiting 2 seconds for order to be processed...\n", .{});
    std.Thread.sleep(2 * std.time.ns_per_s);

    // Refresh order status from exchange
    std.debug.print("Refreshing order status from exchange...\n", .{});
    try order_manager.refreshOrderStatus(exchange_order_id);

    const queried_order = order_manager.getOrderByExchangeId(exchange_order_id) orelse {
        std.debug.print("❌ FAILED: Order not found in OrderManager\n", .{});
        return error.OrderNotFound;
    };

    std.debug.print("✓ Order status refreshed\n", .{});
    std.debug.print("  Status: {s}\n", .{@tagName(queried_order.status)});
    std.debug.print("  Filled: {d} / {d}\n", .{
        queried_order.filled_amount.toFloat(),
        queried_order.amount.toFloat(),
    });

    // Verify order is still open (should not be filled at $1000)
    if (queried_order.status != .open) {
        std.debug.print("⚠️  WARNING: Order status is not 'open', it's '{s}'\n", .{@tagName(queried_order.status)});
    }

    // Test Phase 6: Cancel order
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 6: Cancelling order\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    std.debug.print("Cancelling order ID: {d}\n", .{exchange_order_id});
    try order_manager.cancelOrder(exchange_order_id);
    std.debug.print("✓ Order cancellation request sent\n", .{});

    // Wait for cancellation to be processed
    std.debug.print("Waiting 2 seconds for cancellation to be processed...\n", .{});
    std.Thread.sleep(2 * std.time.ns_per_s);

    // Test Phase 7: Verify order is cancelled
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 7: Verifying order is cancelled\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    // Get order from internal state (cancelled orders won't be in exchange's openOrders)
    const final_order = order_manager.getOrderByExchangeId(exchange_order_id) orelse {
        std.debug.print("❌ FAILED: Order not found in order manager\n", .{});
        return error.OrderNotFound;
    };

    std.debug.print("Final order status: {s}\n", .{@tagName(final_order.status)});

    // Verify status is cancelled
    var all_passed = true;
    if (final_order.status != .cancelled) {
        std.debug.print("❌ FAILED: Expected status 'cancelled', got '{s}'\n", .{@tagName(final_order.status)});
        all_passed = false;
    } else {
        std.debug.print("✅ PASSED: Order successfully cancelled\n", .{});
    }

    // Test Phase 8: Verify order no longer in active orders
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Phase 8: Verifying order not in active orders\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    const active_orders = try order_manager.getActiveOrders();
    defer allocator.free(active_orders);

    var found_in_active = false;
    for (active_orders) |active_order| {
        if (active_order.exchange_order_id) |id| {
            if (id == exchange_order_id) {
                found_in_active = true;
                break;
            }
        }
    }

    if (found_in_active) {
        std.debug.print("❌ FAILED: Cancelled order still in active orders\n", .{});
        all_passed = false;
    } else {
        std.debug.print("✅ PASSED: Order not in active orders\n", .{});
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
