//! Example 23: Cross-Exchange Arbitrage (v0.7.0)
//!
//! This example demonstrates the Cross-Exchange Arbitrage module for
//! identifying and executing price discrepancies between exchanges.
//!
//! Features:
//! - Multi-exchange price monitoring
//! - Arbitrage opportunity detection
//! - Simultaneous order execution
//! - Fee and slippage consideration
//!
//! Run: zig build run-example-arbitrage

const std = @import("std");
const zigQuant = @import("zigQuant");

const market_making = zigQuant.market_making;
const CrossExchangeArbitrage = market_making.CrossExchangeArbitrage;
const ArbitrageConfig = market_making.ArbitrageConfig;
const ArbitrageOpportunity = market_making.ArbitrageOpportunity;
const Quote = market_making.Quote;
const Direction = market_making.Direction;
const ArbStats = market_making.ArbStats;

const Decimal = zigQuant.Decimal;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    // Using std.debug.print for output

    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("    Example 23: Cross-Exchange Arbitrage (v0.7.0)\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 1: Introduction
    // ========================================================================
    std.debug.print("--- 1. Introduction ---\n\n", .{});
    std.debug.print("Cross-Exchange Arbitrage:\n", .{});
    std.debug.print("  - Monitors prices across multiple exchanges\n", .{});
    std.debug.print("  - Detects price discrepancies\n", .{});
    std.debug.print("  - Executes simultaneous buy/sell\n", .{});
    std.debug.print("  - Captures risk-free profit\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Example:\n", .{});
    std.debug.print("    Exchange A: ETH @ 2500 (ask)\n", .{});
    std.debug.print("    Exchange B: ETH @ 2510 (bid)\n", .{});
    std.debug.print("    -> Buy on A, Sell on B = $10 profit\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 2: Configuration
    // ========================================================================
    std.debug.print("--- 2. Configuration ---\n\n", .{});

    std.debug.print("  ArbitrageConfig = struct {{\n", .{});
    std.debug.print("      symbol: []const u8,\n", .{});
    std.debug.print("      min_spread_bps: Decimal,     // Min spread (basis points)\n", .{});
    std.debug.print("      max_position: Decimal,       // Max position size\n", .{});
    std.debug.print("      order_size: Decimal,         // Order size per trade\n", .{});
    std.debug.print("      fee_rate_a: Decimal,         // Exchange A fee\n", .{});
    std.debug.print("      fee_rate_b: Decimal,         // Exchange B fee\n", .{});
    std.debug.print("      slippage_bps: Decimal,       // Expected slippage\n", .{});
    std.debug.print("      max_exposure_time_ms: u64,   // Max time between legs\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // Create sample config
    const config = ArbitrageConfig{};
    std.debug.print("  Default config:\n", .{});
    std.debug.print("    - Min profit: {d} bps\n", .{config.min_profit_bps});
    std.debug.print("    - Trade amount: {d:.2}\n", .{config.trade_amount.toFloat()});
    std.debug.print("    - Fee A: {d} bps\n", .{config.fee_bps_a});
    std.debug.print("    - Fee B: {d} bps\n", .{config.fee_bps_b});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 3: Usage
    // ========================================================================
    std.debug.print("--- 3. Usage ---\n\n", .{});

    // Create arbitrage strategy
    var arb = CrossExchangeArbitrage.init(allocator, .{
        .symbol = "ETH/USDT",
        .min_profit_bps = 10, // 10 bps = 0.1%
        .trade_amount = Decimal.fromFloat(0.1),
        .fee_bps_a = 10, // 0.1%
        .fee_bps_b = 10,
    });

    std.debug.print("  Created CrossExchangeArbitrage:\n", .{});
    std.debug.print("    - Symbol: ETH/USDT\n", .{});
    std.debug.print("    - Min profit: 10 bps\n", .{});
    std.debug.print("    - Order size: 0.1\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 4: Quote Updates
    // ========================================================================
    std.debug.print("--- 4. Quote Updates ---\n\n", .{});

    // Create quotes with bid_size and ask_size
    const quote_a = Quote{
        .bid = Decimal.fromFloat(2500),
        .ask = Decimal.fromFloat(2501),
        .bid_size = Decimal.fromFloat(10.0),
        .ask_size = Decimal.fromFloat(10.0),
        .timestamp = 1000,
    };

    const quote_b = Quote{
        .bid = Decimal.fromFloat(2510),
        .ask = Decimal.fromFloat(2511),
        .bid_size = Decimal.fromFloat(10.0),
        .ask_size = Decimal.fromFloat(10.0),
        .timestamp = 1000,
    };

    arb.updateQuoteA(quote_a);
    arb.updateQuoteB(quote_b);

    std.debug.print("  Exchange A quotes:\n", .{});
    std.debug.print("    - Bid: 2500, Ask: 2501\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Exchange B quotes:\n", .{});
    std.debug.print("    - Bid: 2510, Ask: 2511\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 5: Opportunity Detection
    // ========================================================================
    std.debug.print("--- 5. Opportunity Detection ---\n\n", .{});

    if (arb.detectOpportunity(quote_a, quote_b)) |opp| {
        std.debug.print("  Opportunity found!\n", .{});
        std.debug.print("    - Direction: {s}\n", .{@tagName(opp.direction)});
        std.debug.print("    - Buy price: {d:.2}\n", .{opp.buy_price.toFloat()});
        std.debug.print("    - Sell price: {d:.2}\n", .{opp.sell_price.toFloat()});
        std.debug.print("    - Net profit: {d} bps\n", .{opp.net_profit_bps});
        std.debug.print("    - Expected profit: {d:.4}\n", .{opp.expected_profit.toFloat()});
        std.debug.print("\n", .{});

        if (opp.direction == .a_to_b) {
            std.debug.print("  Action:\n", .{});
            std.debug.print("    1. Buy on Exchange A @ 2501\n", .{});
            std.debug.print("    2. Sell on Exchange B @ 2510\n", .{});
            std.debug.print("    3. Gross profit: 9.00\n", .{});
            std.debug.print("    4. Minus fees: ~5.00\n", .{});
            std.debug.print("    5. Net profit: ~4.00\n", .{});
        }
    } else {
        std.debug.print("  No opportunity (spread too small)\n", .{});
    }
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 6: Execution
    // ========================================================================
    std.debug.print("--- 6. Execution ---\n\n", .{});

    std.debug.print("  // Execute arbitrage (pseudo-code)\n", .{});
    std.debug.print("  if (arb.checkOpportunity()) |opp| {{\n", .{});
    std.debug.print("      // Simultaneous execution critical!\n", .{});
    std.debug.print("      const tasks = [_]Task{{\n", .{});
    std.debug.print("          exec_a.submitOrder(buy_order),\n", .{});
    std.debug.print("          exec_b.submitOrder(sell_order),\n", .{});
    std.debug.print("      }};\n", .{});
    std.debug.print("      try await_all(&tasks);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("      // Record result\n", .{});
    std.debug.print("      arb.recordExecution(result);\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 7: Statistics
    // ========================================================================
    std.debug.print("--- 7. Statistics ---\n\n", .{});

    const stats = arb.getStats();
    std.debug.print("  ArbStats:\n", .{});
    std.debug.print("    - Opportunities detected: {d}\n", .{stats.opportunities_detected});
    std.debug.print("    - Opportunities executed: {d}\n", .{stats.opportunities_executed});
    std.debug.print("    - Trade count: {d}\n", .{stats.trade_count});
    std.debug.print("    - Total profit: {d:.4}\n", .{stats.total_profit.toFloat()});
    std.debug.print("    - Total fees: {d:.4}\n", .{stats.total_fees.toFloat()});
    std.debug.print("    - Avg profit: {d:.2} bps\n", .{stats.avg_profit_bps});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 8: Risk Considerations
    // ========================================================================
    std.debug.print("--- 8. Risk Considerations ---\n\n", .{});

    std.debug.print("  Execution Risk:\n", .{});
    std.debug.print("    - Latency between legs\n", .{});
    std.debug.print("    - Partial fills\n", .{});
    std.debug.print("    -> Use simultaneous execution\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Market Risk:\n", .{});
    std.debug.print("    - Price moves during execution\n", .{});
    std.debug.print("    - Slippage on large orders\n", .{});
    std.debug.print("    -> Size positions appropriately\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Operational Risk:\n", .{});
    std.debug.print("    - Exchange downtime\n", .{});
    std.debug.print("    - Withdrawal delays\n", .{});
    std.debug.print("    -> Monitor capital on each exchange\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("================================================================\n", .{});
    std.debug.print("  Cross-Exchange Arbitrage Summary\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Key Features:\n", .{});
    std.debug.print("    - Multi-exchange monitoring\n", .{});
    std.debug.print("    - Opportunity detection\n", .{});
    std.debug.print("    - Fee calculation\n", .{});
    std.debug.print("    - Statistics tracking\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Requirements:\n", .{});
    std.debug.print("    - Low-latency execution\n", .{});
    std.debug.print("    - Capital on both exchanges\n", .{});
    std.debug.print("    - Fast quote updates\n", .{});
    std.debug.print("\n", .{});
}
