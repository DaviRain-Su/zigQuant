//! Example 20: Pure Market Making (v0.7.0)
//!
//! This example demonstrates the Pure Market Making strategy that places
//! orders on both sides of the mid price to earn the bid-ask spread.
//!
//! Features:
//! - Symmetric quote placement
//! - Configurable spread and position limits
//! - Clock-driven execution
//! - Order tracking
//!
//! Run: zig build run-example-pure-mm

const std = @import("std");
const zigQuant = @import("zigQuant");

const market_making = zigQuant.market_making;
const PureMarketMaking = market_making.PureMarketMaking;
const PureMMConfig = market_making.PureMMConfig;
const Clock = market_making.Clock;

const Decimal = zigQuant.Decimal;
const Cache = zigQuant.Cache;

pub fn main() !void {
    // Using std.debug.print for output
    // This example demonstrates Pure Market Making concepts

    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("       Example 20: Pure Market Making (v0.7.0)\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 1: Introduction
    // ========================================================================
    std.debug.print("--- 1. Introduction ---\n\n", .{});
    std.debug.print("Pure Market Making strategy:\n", .{});
    std.debug.print("  - Places bid and ask orders around mid price\n", .{});
    std.debug.print("  - Earns the bid-ask spread on fills\n", .{});
    std.debug.print("  - Manages inventory through symmetric quotes\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Profit source:\n", .{});
    std.debug.print("    Buy at (mid - spread/2)\n", .{});
    std.debug.print("    Sell at (mid + spread/2)\n", .{});
    std.debug.print("    Profit = spread - fees\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 2: Configuration
    // ========================================================================
    std.debug.print("--- 2. Configuration ---\n\n", .{});

    std.debug.print("  PureMMConfig = struct {{\n", .{});
    std.debug.print("      symbol: []const u8,        // Trading symbol\n", .{});
    std.debug.print("      order_amount: Decimal,     // Order size\n", .{});
    std.debug.print("      bid_spread: Decimal,       // Bid offset from mid\n", .{});
    std.debug.print("      ask_spread: Decimal,       // Ask offset from mid\n", .{});
    std.debug.print("      order_refresh_time: u64,   // Quote refresh interval\n", .{});
    std.debug.print("      max_order_age: u64,        // Maximum order lifetime\n", .{});
    std.debug.print("      min_spread: Decimal,       // Minimum allowed spread\n", .{});
    std.debug.print("      price_ceiling: ?Decimal,   // Optional max price\n", .{});
    std.debug.print("      price_floor: ?Decimal,     // Optional min price\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // Sample configuration
    std.debug.print("  Example config (ETH market making):\n", .{});
    std.debug.print("    symbol: \"ETH\"\n", .{});
    std.debug.print("    order_amount: 0.1 ETH\n", .{});
    std.debug.print("    bid_spread: 0.1%% (10 bps)\n", .{});
    std.debug.print("    ask_spread: 0.1%% (10 bps)\n", .{});
    std.debug.print("    min_spread: 0.05%% (5 bps)\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 3: Quote Calculation
    // ========================================================================
    std.debug.print("--- 3. Quote Calculation ---\n\n", .{});

    std.debug.print("  Given:\n", .{});
    std.debug.print("    mid_price = 2500.00\n", .{});
    std.debug.print("    bid_spread = 0.1%% = 2.50\n", .{});
    std.debug.print("    ask_spread = 0.1%% = 2.50\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Quotes:\n", .{});
    std.debug.print("    bid_price = 2500.00 - 2.50 = 2497.50\n", .{});
    std.debug.print("    ask_price = 2500.00 + 2.50 = 2502.50\n", .{});
    std.debug.print("    total_spread = 5.00 (0.2%%)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  If both sides fill:\n", .{});
    std.debug.print("    profit = 5.00 - fees\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 4: Usage Pattern
    // ========================================================================
    std.debug.print("--- 4. Usage Pattern ---\n\n", .{});

    std.debug.print("  // Create strategy\n", .{});
    std.debug.print("  var mm = try PureMarketMaking.init(allocator, .{{\n", .{});
    std.debug.print("      .symbol = \"ETH\",\n", .{});
    std.debug.print("      .order_amount = Decimal.fromFloat(0.1),\n", .{});
    std.debug.print("      .bid_spread = Decimal.fromFloat(0.001),\n", .{});
    std.debug.print("      .ask_spread = Decimal.fromFloat(0.001),\n", .{});
    std.debug.print("  }}, &cache);\n", .{});
    std.debug.print("  defer mm.deinit();\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Register with clock\n", .{});
    std.debug.print("  var clock = try Clock.init(allocator, 100);\n", .{});
    std.debug.print("  try clock.addStrategy(mm.asClockStrategy());\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // Run\n", .{});
    std.debug.print("  try clock.start();\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 5: Order Management
    // ========================================================================
    std.debug.print("--- 5. Order Management ---\n\n", .{});

    std.debug.print("  Order lifecycle:\n", .{});
    std.debug.print("    1. Calculate bid/ask prices\n", .{});
    std.debug.print("    2. Cancel stale orders\n", .{});
    std.debug.print("    3. Place new orders\n", .{});
    std.debug.print("    4. Track open orders\n", .{});
    std.debug.print("    5. Handle fills\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Refresh logic:\n", .{});
    std.debug.print("    - Price moved: Cancel and requote\n", .{});
    std.debug.print("    - Order too old: Cancel and refresh\n", .{});
    std.debug.print("    - Fill received: Update inventory\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 6: Statistics
    // ========================================================================
    std.debug.print("--- 6. Statistics ---\n\n", .{});

    std.debug.print("  MMStats = struct {{\n", .{});
    std.debug.print("      tick_count: u64,           // Ticks processed\n", .{});
    std.debug.print("      orders_placed: u64,        // Orders created\n", .{});
    std.debug.print("      orders_cancelled: u64,     // Orders cancelled\n", .{});
    std.debug.print("      fills_received: u64,       // Fills received\n", .{});
    std.debug.print("      total_volume: Decimal,     // Total traded\n", .{});
    std.debug.print("      total_pnl: Decimal,        // Profit/Loss\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 7: Risk Considerations
    // ========================================================================
    std.debug.print("--- 7. Risk Considerations ---\n\n", .{});

    std.debug.print("  Inventory Risk:\n", .{});
    std.debug.print("    - One-sided fills accumulate position\n", .{});
    std.debug.print("    - Position exposed to price movement\n", .{});
    std.debug.print("    -> Use InventoryManager (Story 035)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Adverse Selection:\n", .{});
    std.debug.print("    - Informed traders trade against you\n", .{});
    std.debug.print("    - Spread may not cover losses\n", .{});
    std.debug.print("    -> Widen spread in volatile markets\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Execution Risk:\n", .{});
    std.debug.print("    - Order latency affects fills\n", .{});
    std.debug.print("    - Stale quotes get picked off\n", .{});
    std.debug.print("    -> Use low-latency execution\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("================================================================\n", .{});
    std.debug.print("  Pure Market Making Summary\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Key Features:\n", .{});
    std.debug.print("    - Symmetric bid/ask quoting\n", .{});
    std.debug.print("    - Configurable spreads\n", .{});
    std.debug.print("    - Clock-driven execution\n", .{});
    std.debug.print("    - Automatic order refresh\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Best Used With:\n", .{});
    std.debug.print("    - InventoryManager for position control\n", .{});
    std.debug.print("    - Low-latency execution\n", .{});
    std.debug.print("    - Liquid markets\n", .{});
    std.debug.print("\n", .{});

}
