//! Example 24: Queue Position Modeling (v0.7.0)
//!
//! This example demonstrates Queue Position Modeling for realistic
//! backtest simulation of order fills in limit order books.
//!
//! Features:
//! - FIFO queue tracking
//! - Multiple fill probability models
//! - Level-3 (Market-By-Order) orderbook
//! - Realistic fill simulation
//!
//! Run: zig build run-example-queue

const std = @import("std");
const zigQuant = @import("zigQuant");

const queue_position = zigQuant.queue_position;
const QueueModel = queue_position.QueueModel;
const QueuePosition = queue_position.QueuePosition;
const Level3OrderBook = queue_position.Level3OrderBook;
const PriceLevel = queue_position.PriceLevel;

const Decimal = zigQuant.Decimal;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    // Using std.debug.print for output

    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("      Example 24: Queue Position Modeling (v0.7.0)\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 1: Introduction
    // ========================================================================
    std.debug.print("--- 1. Introduction ---\n\n", .{});
    std.debug.print("Queue Position Modeling:\n", .{});
    std.debug.print("  - Tracks order position in FIFO queue\n", .{});
    std.debug.print("  - Simulates realistic fill probability\n", .{});
    std.debug.print("  - Models queue priority at each price level\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Why it matters:\n", .{});
    std.debug.print("    Traditional backtest: Instant fill at limit price\n", .{});
    std.debug.print("    Reality: Must wait in queue behind others\n", .{});
    std.debug.print("    -> More realistic P&L estimation\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 2: Queue Models
    // ========================================================================
    std.debug.print("--- 2. Queue Models ---\n\n", .{});

    std.debug.print("  QueueModel = enum {{\n", .{});
    std.debug.print("      RiskAverse,    // Must clear entire queue\n", .{});
    std.debug.print("      Probability,   // P = (volume / queue_size)\n", .{});
    std.debug.print("      PowerLaw,      // P = (volume / queue_size)^alpha\n", .{});
    std.debug.print("      Logarithmic,   // P = log(volume+1) / log(queue+1)\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 3: Queue Position
    // ========================================================================
    std.debug.print("--- 3. Queue Position ---\n\n", .{});

    // Create queue position (order_id, price, position, qty_ahead, order_qty)
    const queue = QueuePosition.init(
        1, // order_id
        Decimal.fromFloat(2500), // price level
        5, // position in queue (5th in line)
        Decimal.fromFloat(30.0), // quantity ahead
        Decimal.fromFloat(1.0), // order quantity
    );

    std.debug.print("  Created QueuePosition:\n", .{});
    std.debug.print("    - Order ID: {d}\n", .{queue.order_id});
    std.debug.print("    - Price: {d:.2}\n", .{queue.price_level.toFloat()});
    std.debug.print("    - Position: {d}\n", .{queue.position_in_queue});
    std.debug.print("    - Qty ahead: {d:.2}\n", .{queue.total_quantity_ahead.toFloat()});
    std.debug.print("    - Order qty: {d:.2}\n", .{queue.order_quantity.toFloat()});
    std.debug.print("\n", .{});

    // Calculate fill probability with different models
    std.debug.print("  Fill probabilities:\n", .{});
    std.debug.print("    - RiskAverse: {d:.2}%%\n", .{queue.fillProbability(.RiskAverse) * 100});
    std.debug.print("    - Probability: {d:.2}%%\n", .{queue.fillProbability(.Probability) * 100});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 4: Fill Probability
    // ========================================================================
    std.debug.print("--- 4. Fill Probability Calculation ---\n\n", .{});

    std.debug.print("  Example scenario:\n", .{});
    std.debug.print("    Queue size at price: 100\n", .{});
    std.debug.print("    Our position: 30 (30 units ahead)\n", .{});
    std.debug.print("    Trade volume: 50\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("  RiskAverse model:\n", .{});
    std.debug.print("    P = 0 (need 31 volume to fill)\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("  Probability model:\n", .{});
    std.debug.print("    P = min(1, max(0, (50-30)/70)) = 0.286\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("  PowerLaw model (alpha=1.5):\n", .{});
    std.debug.print("    P = (0.286)^1.5 = 0.153\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 5: Level-3 Order Book
    // ========================================================================
    std.debug.print("--- 5. Level-3 Order Book ---\n\n", .{});

    std.debug.print("  Level-3 (Market-By-Order) vs Level-2:\n", .{});
    std.debug.print("    Level-2: Aggregated volume per price\n", .{});
    std.debug.print("    Level-3: Individual orders with IDs\n", .{});
    std.debug.print("\n", .{});

    // Create L3 orderbook
    var orderbook = Level3OrderBook.init(allocator, "ETH");
    defer orderbook.deinit();

    std.debug.print("  Created Level3OrderBook for ETH\n", .{});
    std.debug.print("\n", .{});

    // Add some orders (side, price, quantity, timestamp)
    const ts = std.time.milliTimestamp();
    const ord1 = try orderbook.addOrder(.buy, Decimal.fromFloat(2500), Decimal.fromFloat(1.0), ts);
    const ord2 = try orderbook.addOrder(.buy, Decimal.fromFloat(2500), Decimal.fromFloat(0.5), ts);
    _ = try orderbook.addOrder(.buy, Decimal.fromFloat(2499), Decimal.fromFloat(2.0), ts);
    _ = try orderbook.addOrder(.sell, Decimal.fromFloat(2501), Decimal.fromFloat(1.0), ts);

    std.debug.print("  Added orders:\n", .{});
    std.debug.print("    Bids:\n", .{});
    std.debug.print("      2500: [id-{d}: 1.0] [id-{d}: 0.5]\n", .{ ord1, ord2 });
    std.debug.print("      2499: [id-3: 2.0]\n", .{});
    std.debug.print("    Asks:\n", .{});
    std.debug.print("      2501: [id-4: 1.0]\n", .{});
    std.debug.print("\n", .{});

    // Check order fill
    std.debug.print("  Order {d} position in queue:\n", .{ord2});
    std.debug.print("    - Order {d} is ahead with 1.0\n", .{ord1});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 6: Trade Simulation
    // ========================================================================
    std.debug.print("--- 6. Trade Simulation ---\n\n", .{});

    std.debug.print("  // When trade occurs at our price level:\n", .{});
    std.debug.print("  fn processMarketTrade(volume: Decimal) void {{\n", .{});
    std.debug.print("      // Update queue positions\n", .{});
    std.debug.print("      for (orders_at_price) |order| {{\n", .{});
    std.debug.print("          order.queue_ahead -= volume;\n", .{});
    std.debug.print("          if (order.queue_ahead <= 0) {{\n", .{});
    std.debug.print("              // Order filled!\n", .{});
    std.debug.print("              const fill_qty = min(order.qty, -order.queue_ahead);\n", .{});
    std.debug.print("          }}\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 7: Backtest Integration
    // ========================================================================
    std.debug.print("--- 7. Backtest Integration ---\n\n", .{});

    std.debug.print("  // In backtest engine:\n", .{});
    std.debug.print("  fn onLimitOrderSubmit(order: Order) void {{\n", .{});
    std.debug.print("      // Add to L3 book\n", .{});
    std.debug.print("      orderbook.addOrder(order.id, order.side, order.price, order.qty);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("      // Track queue position\n", .{});
    std.debug.print("      queue.addOrder(order.id, order.price, queue_size);\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  fn onMarketTrade(trade: Trade) void {{\n", .{});
    std.debug.print("      // Update queue and check fills\n", .{});
    std.debug.print("      const fills = queue.processVolume(trade.price, trade.volume);\n", .{});
    std.debug.print("      for (fills) |fill| {{\n", .{});
    std.debug.print("          recordFill(fill);\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 8: Impact on Results
    // ========================================================================
    std.debug.print("--- 8. Impact on Backtest Results ---\n\n", .{});

    std.debug.print("  Comparing fill assumptions:\n", .{});
    std.debug.print("    Strategy: Market Making at best bid/ask\n", .{});
    std.debug.print("    Period: 1 month\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("    Without queue modeling:\n", .{});
    std.debug.print("      - Fill rate: 100%%\n", .{});
    std.debug.print("      - Estimated PnL: +$50,000\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("    With queue modeling (Probability):\n", .{});
    std.debug.print("      - Fill rate: 35%%\n", .{});
    std.debug.print("      - Estimated PnL: +$12,000\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("    More realistic expectation!\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("================================================================\n", .{});
    std.debug.print("  Queue Position Modeling Summary\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Key Features:\n", .{});
    std.debug.print("    - FIFO queue tracking\n", .{});
    std.debug.print("    - Multiple probability models\n", .{});
    std.debug.print("    - Level-3 orderbook support\n", .{});
    std.debug.print("    - Realistic fill simulation\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Benefits:\n", .{});
    std.debug.print("    - More accurate backtest results\n", .{});
    std.debug.print("    - Better strategy evaluation\n", .{});
    std.debug.print("    - Reduced live trading surprises\n", .{});
    std.debug.print("\n", .{});
}
