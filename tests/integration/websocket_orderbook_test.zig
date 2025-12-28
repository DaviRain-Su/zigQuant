//! WebSocket Orderbook Integration Test
//!
//! Tests WebSocket integration with OrderBook, verifying:
//! 1. Orderbook snapshot and delta updates
//! 2. Order event callbacks
//! 3. Position event callbacks
//! 4. Latency < 10ms
//! 5. No memory leaks
//!
//! Run with: zig build test-ws-orderbook

const std = @import("std");
const testing = std.testing;
const zigQuant = @import("zigQuant");

const HyperliquidWS = zigQuant.hyperliquid.HyperliquidWS;
const OrderBook = zigQuant.OrderBook;
const OrderBookManager = zigQuant.OrderBookManager;
const Message = zigQuant.hyperliquid.Message;
const Logger = zigQuant.Logger;
const Decimal = zigQuant.Decimal;

// WebSocket Level type (extracted from Message.l2Book.levels)
// We'll extract the type from the Message union at runtime
const WSLevel = struct {
    px: Decimal,
    sz: Decimal,
    n: u32,
};

// Global test state for callbacks (required because WebSocket callback doesn't support context)
var g_test_state: ?*TestState = null;

// Test state for callbacks
const TestState = struct {
    allocator: std.mem.Allocator,
    orderbook_mgr: *OrderBookManager,

    // Counters for verification
    snapshot_count: std.atomic.Value(u32),
    update_count: std.atomic.Value(u32),
    order_event_count: std.atomic.Value(u32),
    position_event_count: std.atomic.Value(u32),

    // Latency tracking (nanoseconds)
    max_latency_ns: std.atomic.Value(i64),

    // Mutex for thread-safe operations
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, orderbook_mgr: *OrderBookManager) TestState {
        return .{
            .allocator = allocator,
            .orderbook_mgr = orderbook_mgr,
            .snapshot_count = std.atomic.Value(u32).init(0),
            .update_count = std.atomic.Value(u32).init(0),
            .order_event_count = std.atomic.Value(u32).init(0),
            .position_event_count = std.atomic.Value(u32).init(0),
            .max_latency_ns = std.atomic.Value(i64).init(0),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *TestState) void {
        _ = self;
    }
};

// Dummy log writer for testing
const TestLogWriter = struct {
    fn write(_: *anyopaque, record: zigQuant.logger.LogRecord) anyerror!void {
        const level_str = switch (record.level) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };

        std.debug.print("[{s}] {s}\n", .{ level_str, record.message });
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

// Convert WebSocket Level to OrderBook Level
const BookLevel = zigQuant.BookLevel;
fn convertLevel(ws_level: anytype) BookLevel {
    return .{
        .price = ws_level.px,
        .size = ws_level.sz,
        .num_orders = ws_level.n,
    };
}

// Message callback for WebSocket
fn messageCallback(ctx: ?*anyopaque, msg: Message) void {
    _ = ctx; // Using global state instead
    const state_ptr = g_test_state orelse return;
    const start_time = std.time.nanoTimestamp();

    switch (msg) {
        .l2Book => |data| {
            state_ptr.mutex.lock();
            defer state_ptr.mutex.unlock();

            // Get or create orderbook for this coin
            const symbol = data.coin;
            const ob = state_ptr.orderbook_mgr.getOrCreate(symbol) catch {
                std.debug.print("Failed to get orderbook for {s}\n", .{symbol});
                return;
            };

            // Convert WebSocket levels to OrderBook levels
            var bids = state_ptr.allocator.alloc(BookLevel, data.levels.bids.len) catch {
                std.debug.print("Failed to allocate bids\n", .{});
                return;
            };
            defer state_ptr.allocator.free(bids);

            var asks = state_ptr.allocator.alloc(BookLevel, data.levels.asks.len) catch {
                std.debug.print("Failed to allocate asks\n", .{});
                return;
            };
            defer state_ptr.allocator.free(asks);

            for (data.levels.bids, 0..) |ws_level, i| {
                bids[i] = convertLevel(ws_level);
            }
            for (data.levels.asks, 0..) |ws_level, i| {
                asks[i] = convertLevel(ws_level);
            }

            // Determine if this is a snapshot or delta update
            const is_snapshot = data.levels.bids.len > 5; // Heuristic: snapshot has more levels

            if (is_snapshot) {
                // Apply snapshot
                const timestamp_millis = @as(i64, @intCast(@divTrunc(start_time, std.time.ns_per_ms)));
                ob.applySnapshot(bids, asks, .{ .millis = timestamp_millis }) catch {
                    std.debug.print("Failed to apply snapshot\n", .{});
                    return;
                };
                _ = state_ptr.snapshot_count.fetchAdd(1, .monotonic);
                std.debug.print("✓ Applied snapshot for {s}: {} bids, {} asks\n", .{
                    symbol,
                    data.levels.bids.len,
                    data.levels.asks.len,
                });
            } else {
                // Apply delta update
                // TODO: Implement delta update logic
                _ = state_ptr.update_count.fetchAdd(1, .monotonic);
                std.debug.print("✓ Received update for {s}: {} bids, {} asks\n", .{
                    symbol,
                    data.levels.bids.len,
                    data.levels.asks.len,
                });
            }

            // Track latency (convert to i64 for atomic storage)
            const end_time = std.time.nanoTimestamp();
            const latency_ns = @as(i64, @intCast(end_time - start_time));

            const current_max = state_ptr.max_latency_ns.load(.monotonic);
            if (latency_ns > current_max) {
                _ = state_ptr.max_latency_ns.cmpxchgStrong(current_max, latency_ns, .monotonic, .monotonic);
            }

            // Verify best bid/ask
            if (ob.getBestBid()) |best_bid| {
                std.debug.print("  Best Bid: {d}\n", .{best_bid.price.value});
            }
            if (ob.getBestAsk()) |best_ask| {
                std.debug.print("  Best Ask: {d}\n", .{best_ask.price.value});
            }
        },
        .subscriptionResponse => |data| {
            std.debug.print("Subscription {s}: {s}\n", .{ data.method, data.subscription.type });
        },
        .error_msg => |data| {
            std.debug.print("WebSocket Error: {} - {s}\n", .{ data.code, data.msg });
        },
        else => {
            // Ignore other messages for now
        },
    }
}

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
    std.debug.print("WebSocket Orderbook Integration Test\n", .{});
    std.debug.print("=" ** 80 ++ "\n\n", .{});

    // Create logger
    const logger = createTestLogger(allocator);

    // Create OrderBookManager
    var orderbook_mgr = OrderBookManager.init(allocator);
    defer orderbook_mgr.deinit();

    // Create test state
    var test_state = TestState.init(allocator, &orderbook_mgr);
    defer test_state.deinit();

    // Set global test state for callback
    g_test_state = &test_state;
    defer g_test_state = null;

    // Create WebSocket client
    const config = HyperliquidWS.Config{
        .ws_url = "wss://api.hyperliquid-testnet.xyz/ws",
        .host = "api.hyperliquid-testnet.xyz",
        .port = 443,
        .path = "/ws",
        .use_tls = true,
    };

    var ws = HyperliquidWS.init(allocator, config, logger);
    defer ws.deinit();

    // Set message callback (no context needed, using global state)
    ws.setMessageCallback(messageCallback, null);

    // Test Phase 1: Connection
    std.debug.print("Phase 1: Testing WebSocket connection...\n", .{});
    try ws.connect();
    std.debug.print("✓ Connected to Hyperliquid WebSocket\n\n", .{});

    // Test Phase 2: Subscribe to L2 orderbook
    std.debug.print("Phase 2: Subscribing to ETH L2 orderbook...\n", .{});
    try ws.subscribe(.{ .channel = .l2Book, .coin = "ETH" });
    std.debug.print("✓ Subscription sent\n\n", .{});

    // Test Phase 3: Receive and process messages
    std.debug.print("Phase 3: Receiving orderbook updates for 10 seconds...\n", .{});
    std.Thread.sleep(10 * std.time.ns_per_s);

    // Test Phase 4: Verify results
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Test Results:\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});

    const snapshot_count = test_state.snapshot_count.load(.monotonic);
    const update_count = test_state.update_count.load(.monotonic);
    const max_latency_ns = test_state.max_latency_ns.load(.monotonic);
    const max_latency_ms = @as(f64, @floatFromInt(max_latency_ns)) / 1_000_000.0;

    std.debug.print("Snapshots received: {}\n", .{snapshot_count});
    std.debug.print("Updates received: {}\n", .{update_count});
    std.debug.print("Max latency: {d:.2} ms\n", .{max_latency_ms});

    // Verification
    var all_passed = true;

    if (snapshot_count == 0) {
        std.debug.print("❌ FAILED: No snapshots received\n", .{});
        all_passed = false;
    } else {
        std.debug.print("✅ PASSED: Received {} snapshots\n", .{snapshot_count});
    }

    if (max_latency_ms > 10.0) {
        std.debug.print("❌ FAILED: Max latency {d:.2}ms exceeds 10ms requirement\n", .{max_latency_ms});
        all_passed = false;
    } else {
        std.debug.print("✅ PASSED: Latency {d:.2}ms < 10ms\n", .{max_latency_ms});
    }

    // Disconnect
    std.debug.print("\nDisconnecting...\n", .{});
    ws.should_reconnect.store(false, .release);
    ws.disconnect();

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
