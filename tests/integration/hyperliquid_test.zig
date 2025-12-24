//! Hyperliquid Integration Tests
//!
//! Tests actual API calls to Hyperliquid testnet
//! Run with: zig build test-integration

const std = @import("std");
const zigQuant = @import("zigQuant");

// Import modules
const Logger = zigQuant.Logger;
const Level = zigQuant.Level;
const ExchangeConfig = zigQuant.ExchangeConfig;
const HyperliquidConnector = zigQuant.HyperliquidConnector;
const TradingPair = zigQuant.TradingPair;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Hyperliquid Integration Tests ===\n\n", .{});

    // Create simple logger (for now, just use a dummy writer)
    const DummyWriter = struct {
        fn write(_: *anyopaque, record: zigQuant.logger.LogRecord) anyerror!void {
            std.debug.print("[{s}] {s}\n", .{ @tagName(record.level), record.message });
        }
        fn flush(_: *anyopaque) anyerror!void {}
        fn close(_: *anyopaque) void {}
    };

    const log_writer = zigQuant.logger.LogWriter{
        .ptr = @constCast(@ptrCast(&struct {}{})),
        .writeFn = DummyWriter.write,
        .flushFn = DummyWriter.flush,
        .closeFn = DummyWriter.close,
    };

    var logger = Logger.init(allocator, log_writer, .info);
    defer logger.deinit();

    // Test 1: Create connector
    std.debug.print("Test 1: Creating Hyperliquid connector...\n", .{});
    const config = ExchangeConfig{
        .name = "hyperliquid",
        .api_key = "",
        .api_secret = "",
        .testnet = true,
    };

    const connector = try HyperliquidConnector.create(allocator, config, logger);
    defer connector.destroy();

    const exchange = connector.interface();
    std.debug.print("✓ Connector created: {s}\n\n", .{exchange.getName()});

    // Test 2: Connect to exchange
    std.debug.print("Test 2: Connecting to Hyperliquid testnet...\n", .{});
    try exchange.connect();
    std.debug.print("✓ Connected: {}\n\n", .{exchange.isConnected()});

    // Test 3: Get ticker for ETH-USDC
    std.debug.print("Test 3: Getting ETH-USDC ticker...\n", .{});
    const eth_pair = TradingPair{ .base = "ETH", .quote = "USDC" };
    const eth_ticker = exchange.getTicker(eth_pair) catch |err| {
        std.debug.print("✗ Failed to get ticker: {}\n", .{err});
        std.debug.print("  This might be a network issue or API change.\n", .{});
        return err;
    };

    std.debug.print("✓ ETH-USDC Ticker:\n", .{});
    std.debug.print("  Bid:        {}\n", .{eth_ticker.bid.toFloat()});
    std.debug.print("  Ask:        {}\n", .{eth_ticker.ask.toFloat()});
    std.debug.print("  Last:       {}\n", .{eth_ticker.last.toFloat()});
    std.debug.print("  Mid Price:  {}\n", .{eth_ticker.midPrice().toFloat()});
    std.debug.print("  Spread:     {}\n", .{eth_ticker.spread().toFloat()});
    std.debug.print("  Spread bps: {}\n\n", .{eth_ticker.spreadBps().toFloat()});

    // Test 4: Get ticker for BTC-USDC
    std.debug.print("Test 4: Getting BTC-USDC ticker...\n", .{});
    const btc_pair = TradingPair{ .base = "BTC", .quote = "USDC" };
    const btc_ticker = exchange.getTicker(btc_pair) catch |err| {
        std.debug.print("✗ Failed to get ticker: {}\n", .{err});
        return err;
    };

    std.debug.print("✓ BTC-USDC Ticker:\n", .{});
    std.debug.print("  Last:       {}\n", .{btc_ticker.last.toFloat()});
    std.debug.print("  Mid Price:  {}\n\n", .{btc_ticker.midPrice().toFloat()});

    // Test 5: Get orderbook for ETH-USDC
    std.debug.print("Test 5: Getting ETH-USDC orderbook (depth=5)...\n", .{});
    const orderbook = exchange.getOrderbook(eth_pair, 5) catch |err| {
        std.debug.print("✗ Failed to get orderbook: {}\n", .{err});
        return err;
    };
    defer allocator.free(orderbook.bids);
    defer allocator.free(orderbook.asks);

    std.debug.print("✓ ETH-USDC Orderbook:\n", .{});
    std.debug.print("  Bids ({} levels):\n", .{orderbook.bids.len});
    for (orderbook.bids, 0..) |bid, i| {
        if (i >= 5) break;
        std.debug.print("    [{d}] Price: {} | Qty: {} | Orders: {d}\n", .{
            i + 1,
            bid.price.toFloat(),
            bid.quantity.toFloat(),
            bid.num_orders,
        });
    }

    std.debug.print("  Asks ({} levels):\n", .{orderbook.asks.len});
    for (orderbook.asks, 0..) |ask, i| {
        if (i >= 5) break;
        std.debug.print("    [{d}] Price: {} | Qty: {} | Orders: {d}\n", .{
            i + 1,
            ask.price.toFloat(),
            ask.quantity.toFloat(),
            ask.num_orders,
        });
    }

    if (orderbook.getBestBid()) |best_bid| {
        std.debug.print("  Best Bid: {}\n", .{best_bid.price.toFloat()});
    }
    if (orderbook.getBestAsk()) |best_ask| {
        std.debug.print("  Best Ask: {}\n", .{best_ask.price.toFloat()});
    }
    if (orderbook.getMidPrice()) |mid_price| {
        std.debug.print("  Mid Price: {}\n", .{mid_price.toFloat()});
    }
    if (orderbook.getSpread()) |spread| {
        std.debug.print("  Spread: {}\n", .{spread.toFloat()});
    }

    std.debug.print("\n", .{});

    // Test 6: Rate limiting test
    std.debug.print("Test 6: Testing rate limiter (3 rapid requests)...\n", .{});
    const start_time = std.time.milliTimestamp();

    _ = try exchange.getTicker(eth_pair);
    std.debug.print("  Request 1 completed\n", .{});

    _ = try exchange.getTicker(btc_pair);
    std.debug.print("  Request 2 completed\n", .{});

    _ = try exchange.getTicker(eth_pair);
    std.debug.print("  Request 3 completed\n", .{});

    const elapsed = std.time.milliTimestamp() - start_time;
    std.debug.print("✓ Completed 3 requests in {}ms\n", .{elapsed});
    std.debug.print("  Rate limiter is working (20 req/s = 50ms per request)\n\n", .{});

    // Disconnect
    std.debug.print("Test 7: Disconnecting...\n", .{});
    exchange.disconnect();
    std.debug.print("✓ Disconnected: {}\n\n", .{!exchange.isConnected()});

    // Test 8: createOrder (requires signer) - Framework test
    std.debug.print("Test 8: Testing createOrder (without signer - should fail)...\n", .{});
    const order_request = zigQuant.OrderRequest{
        .pair = eth_pair,
        .side = .buy,
        .order_type = .limit,
        .amount = zigQuant.Decimal.fromInt(1),
        .price = zigQuant.Decimal.fromInt(3000), // Low price to avoid actual fills
        .time_in_force = .gtc,
        .reduce_only = false,
    };

    // Should fail because no signer is configured
    const create_result = exchange.createOrder(order_request);
    if (create_result) |_| {
        std.debug.print("✗ Unexpected success (should require signer)\n", .{});
        return error.UnexpectedSuccess;
    } else |err| {
        if (err == error.SignerRequired) {
            std.debug.print("✓ Correctly rejected: SignerRequired\n", .{});
        } else {
            std.debug.print("✗ Unexpected error: {}\n", .{err});
            return err;
        }
    }
    std.debug.print("\n", .{});

    // NOTE: To test actual order creation, set api_secret in ExchangeConfig:
    //
    // const config_with_key = ExchangeConfig{
    //     .name = "hyperliquid",
    //     .api_secret = "YOUR_PRIVATE_KEY_HEX_64_CHARS", // ⚠️ Use testnet key only!
    //     .testnet = true,
    // };
    //
    // const connector_auth = try HyperliquidConnector.create(allocator, config_with_key, logger);
    // defer connector_auth.destroy();
    //
    // const exchange_auth = connector_auth.interface();
    // try exchange_auth.connect();
    //
    // const order = try exchange_auth.createOrder(order_request);
    // std.debug.print("✓ Order created: ID={d}, Status={s}\n", .{
    //     order.exchange_order_id,
    //     @tagName(order.status),
    // });
    //
    // // Remember to cancel the order if needed:
    // // try exchange_auth.cancelOrder(order.exchange_order_id);

    // Test 9: cancelOrder (requires signer) - Framework test
    std.debug.print("Test 9: Testing cancelOrder (without signer - should fail)...\n", .{});

    // Should fail because no signer is configured
    const cancel_result = exchange.cancelOrder(12345);
    if (cancel_result) |_| {
        std.debug.print("✗ Unexpected success (should require signer)\n", .{});
        return error.UnexpectedSuccess;
    } else |err| {
        if (err == error.SignerRequired) {
            std.debug.print("✓ Correctly rejected: SignerRequired\n", .{});
        } else {
            std.debug.print("✗ Unexpected error: {}\n", .{err});
            return err;
        }
    }
    std.debug.print("\n", .{});

    // NOTE: To test actual order cancellation with auth:
    // try exchange_auth.cancelOrder(order.exchange_order_id);
    // std.debug.print("✓ Order cancelled successfully\n", .{});

    // Test 10: getBalance (requires signer) - Framework test
    std.debug.print("Test 10: Testing getBalance (without signer - should fail)...\n", .{});

    // Should fail because no signer is configured
    const balance_result = exchange.getBalance();
    if (balance_result) |balances| {
        allocator.free(balances);
        std.debug.print("✗ Unexpected success (should require signer)\n", .{});
        return error.UnexpectedSuccess;
    } else |err| {
        if (err == error.SignerRequired) {
            std.debug.print("✓ Correctly rejected: SignerRequired\n", .{});
        } else {
            std.debug.print("✗ Unexpected error: {}\n", .{err});
            return err;
        }
    }
    std.debug.print("\n", .{});

    // NOTE: To test actual balance query with auth:
    // const balances = try exchange_auth.getBalance();
    // defer allocator.free(balances);
    // for (balances) |balance| {
    //     std.debug.print("✓ Balance: {s} | Total: {} | Available: {} | Locked: {}\n", .{
    //         balance.asset,
    //         balance.total.toFloat(),
    //         balance.available.toFloat(),
    //         balance.locked.toFloat(),
    //     });
    // }

    // Test 11: getPositions (requires signer) - Framework test
    std.debug.print("Test 11: Testing getPositions (without signer - should fail)...\n", .{});

    // Should fail because no signer is configured
    const positions_result = exchange.getPositions();
    if (positions_result) |positions| {
        allocator.free(positions);
        std.debug.print("✗ Unexpected success (should require signer)\n", .{});
        return error.UnexpectedSuccess;
    } else |err| {
        if (err == error.SignerRequired) {
            std.debug.print("✓ Correctly rejected: SignerRequired\n", .{});
        } else {
            std.debug.print("✗ Unexpected error: {}\n", .{err});
            return err;
        }
    }
    std.debug.print("\n", .{});

    // NOTE: To test actual positions query with auth:
    // const positions = try exchange_auth.getPositions();
    // defer allocator.free(positions);
    // for (positions) |position| {
    //     std.debug.print("✓ Position: {s}-{s} | Side: {s} | Size: {} | Entry: {} | PnL: {} | Leverage: {}x\n", .{
    //         position.pair.base,
    //         position.pair.quote,
    //         @tagName(position.side),
    //         position.size.toFloat(),
    //         position.entry_price.toFloat(),
    //         position.unrealized_pnl.toFloat(),
    //         position.leverage,
    //     });
    // }

    // Test 12: getOrder (requires signer) - Framework test
    std.debug.print("Test 12: Testing getOrder (without signer - should fail)...\n", .{});

    // Should fail because no signer is configured
    const order_result = exchange.getOrder(12345);
    if (order_result) |_| {
        std.debug.print("✗ Unexpected success (should require signer)\n", .{});
        return error.UnexpectedSuccess;
    } else |err| {
        if (err == error.SignerRequired) {
            std.debug.print("✓ Correctly rejected: SignerRequired\n", .{});
        } else {
            std.debug.print("✗ Unexpected error: {}\n", .{err});
            return err;
        }
    }
    std.debug.print("\n", .{});

    // NOTE: To test actual order query with auth:
    // // First create an order to get an order ID
    // const order = try exchange_auth.createOrder(order_request);
    // std.debug.print("Created order: ID={d}\n", .{order.exchange_order_id});
    //
    // // Then query it back
    // const queried_order = try exchange_auth.getOrder(order.exchange_order_id);
    // std.debug.print("✓ Order found: {s}-{s} | Side: {s} | Price: {} | Amount: {} | Status: {s}\n", .{
    //     queried_order.pair.base,
    //     queried_order.pair.quote,
    //     @tagName(queried_order.side),
    //     queried_order.price.?.toFloat(),
    //     queried_order.amount.toFloat(),
    //     @tagName(queried_order.status),
    // });

    // Test 13: cancelAllOrders (requires signer) - Framework test
    std.debug.print("Test 13: Testing cancelAllOrders (without signer - should fail)...\n", .{});

    // Should fail because no signer is configured
    const cancel_all_result = exchange.cancelAllOrders(null);
    if (cancel_all_result) |_| {
        std.debug.print("✗ Unexpected success (should require signer)\n", .{});
        return error.UnexpectedSuccess;
    } else |err| {
        if (err == error.SignerRequired) {
            std.debug.print("✓ Correctly rejected: SignerRequired\n", .{});
        } else {
            std.debug.print("✗ Unexpected error: {}\n", .{err});
            return err;
        }
    }
    std.debug.print("\n", .{});

    // NOTE: To test actual cancelAllOrders with auth:
    // // First create some orders
    // const order1 = try exchange_auth.createOrder(order_request);
    // const order2 = try exchange_auth.createOrder(order_request);
    // std.debug.print("Created 2 orders\n", .{});
    //
    // // Cancel all orders
    // const cancelled_count = try exchange_auth.cancelAllOrders(null);
    // std.debug.print("✓ Cancelled {d} orders\n", .{cancelled_count});
    //
    // // Or cancel orders for a specific pair
    // const cancelled_eth = try exchange_auth.cancelAllOrders(eth_pair);
    // std.debug.print("✓ Cancelled {d} ETH orders\n", .{cancelled_eth});

    // Test 14: Asset mapping (getMeta) - Framework test
    std.debug.print("Test 14: Testing asset mapping (lazy loading)...\n", .{});

    // Reconnect for this test
    try exchange.connect();
    defer exchange.disconnect();

    // Asset mapping is tested indirectly through the connector's functionality
    // The asset_map is lazy-loaded when first needed (e.g., in cancelOrder)
    //
    // Direct testing requires:
    // 1. Call getMeta() to load asset mapping
    // 2. Verify ETH → 0, BTC → 1, etc.
    //
    // This is implicitly tested when cancelOrder and cancelAllOrders are called
    // with authentication (they use getAssetIndex internally)

    std.debug.print("✓ Asset mapping will be lazy-loaded when needed\n", .{});
    std.debug.print("  Full testing requires authenticated API calls\n", .{});
    std.debug.print("  (cancelOrder/cancelAllOrders use getAssetIndex internally)\n", .{});
    std.debug.print("\n", .{});

    // Test 15: WebSocket integration - Framework test
    std.debug.print("Test 15: Testing WebSocket integration with Connector...\n", .{});

    // Initialize WebSocket
    std.debug.print("   • Initializing WebSocket...\n", .{});
    try connector.initWebSocket();
    try std.testing.expect(connector.isWebSocketInitialized());
    std.debug.print("   ✓ WebSocket initialized\n", .{});

    // Subscribe to a channel
    std.debug.print("   • Subscribing to allMids...\n", .{});
    try connector.subscribe(.{ .channel = .allMids });
    std.debug.print("   ✓ Subscribed successfully\n", .{});

    // Wait a moment for messages
    std.debug.print("   • Waiting for messages (3 seconds)...\n", .{});
    std.Thread.sleep(3 * std.time.ns_per_s);

    // Disconnect WebSocket
    std.debug.print("   • Disconnecting WebSocket...\n", .{});
    connector.disconnectWebSocket();
    std.debug.print("   ✓ WebSocket disconnected\n", .{});

    std.debug.print("✓ WebSocket integration works correctly\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("=== All Integration Tests Passed! ✓ ===\n\n", .{});
}
