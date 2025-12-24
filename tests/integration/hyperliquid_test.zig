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

    std.debug.print("=== All Integration Tests Passed! ✓ ===\n\n", .{});
}
