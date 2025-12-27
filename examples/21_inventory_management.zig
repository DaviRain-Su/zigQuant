//! Example 21: Inventory Management (v0.7.0)
//!
//! This example demonstrates Inventory Management with skew adjustments
//! for market making strategies to control position risk.
//!
//! Features:
//! - Position tracking
//! - Quote skewing based on inventory
//! - Multiple skew modes
//! - Rebalance actions
//!
//! Run: zig build run-example-inventory

const std = @import("std");
const zigQuant = @import("zigQuant");

const market_making = zigQuant.market_making;
const InventoryManager = market_making.InventoryManager;
const InventoryConfig = market_making.InventoryConfig;
const SkewMode = market_making.SkewMode;
const InventoryStats = market_making.InventoryStats;

const Decimal = zigQuant.Decimal;

pub fn main() !void {
    // Using std.debug.print for output
    // This example demonstrates Inventory Management concepts

    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("      Example 21: Inventory Management (v0.7.0)\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 1: Introduction
    // ========================================================================
    std.debug.print("--- 1. Introduction ---\n\n", .{});
    std.debug.print("Inventory Management addresses:\n", .{});
    std.debug.print("  - Position accumulation risk\n", .{});
    std.debug.print("  - Directional exposure\n", .{});
    std.debug.print("  - Capital efficiency\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Solution: Skew quotes to incentivize rebalancing\n", .{});
    std.debug.print("    - Long inventory -> Favor selling\n", .{});
    std.debug.print("    - Short inventory -> Favor buying\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 2: Configuration
    // ========================================================================
    std.debug.print("--- 2. Configuration ---\n\n", .{});

    std.debug.print("  InventoryConfig = struct {{\n", .{});
    std.debug.print("      target_inventory: Decimal,  // Target inventory (0=neutral)\n", .{});
    std.debug.print("      max_inventory: Decimal,     // Max absolute inventory\n", .{});
    std.debug.print("      skew_factor: f64,           // Skew intensity (0.0-1.0)\n", .{});
    std.debug.print("      skew_mode: SkewMode,        // Skew algorithm\n", .{});
    std.debug.print("      rebalance_threshold: f64,   // Rebalance trigger (%%)\n", .{});
    std.debug.print("      emergency_threshold: f64,   // Emergency liquidation\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // Create sample config
    const config = InventoryConfig{
        .max_inventory = Decimal.fromFloat(100.0),
    };
    std.debug.print("  Sample config:\n", .{});
    std.debug.print("    - target_inventory: {d:.1}\n", .{config.target_inventory.toFloat()});
    std.debug.print("    - max_inventory: {d:.1}\n", .{config.max_inventory.toFloat()});
    std.debug.print("    - skew_factor: {d:.2}\n", .{config.skew_factor});
    std.debug.print("    - rebalance_threshold: {d:.0}%%\n", .{config.rebalance_threshold * 100});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 3: Skew Modes
    // ========================================================================
    std.debug.print("--- 3. Skew Modes ---\n\n", .{});

    std.debug.print("  SkewMode.Linear:\n", .{});
    std.debug.print("    skew = skew_factor * inventory_deviation\n", .{});
    std.debug.print("    Simple, predictable\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  SkewMode.Exponential:\n", .{});
    std.debug.print("    skew = skew_factor * exp(abs(deviation)) - 1\n", .{});
    std.debug.print("    Aggressive at extremes\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  SkewMode.StepFunction:\n", .{});
    std.debug.print("    skew = fixed steps at thresholds\n", .{});
    std.debug.print("    Discrete levels\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 4: Usage
    // ========================================================================
    std.debug.print("--- 4. Usage ---\n\n", .{});

    // Create manager
    var manager = InventoryManager.init(.{
        .max_inventory = Decimal.fromFloat(100.0),
        .skew_factor = 0.5,
        .skew_mode = .linear,
    });

    std.debug.print("  Created InventoryManager\n", .{});
    std.debug.print("    - Max inventory: 100.0\n", .{});
    std.debug.print("    - Skew factor: 0.5\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 5: Skew Calculation
    // ========================================================================
    std.debug.print("--- 5. Skew Calculation Example ---\n\n", .{});

    // Update inventory and calculate skew
    manager.setInventory(Decimal.fromFloat(30.0));
    const skew = manager.calculateSkew();

    std.debug.print("  Current state:\n", .{});
    std.debug.print("    - Inventory: 30.0 (30%% of max)\n", .{});
    std.debug.print("    - Inventory ratio: {d:.2}\n", .{manager.inventoryRatio()});
    std.debug.print("    - Calculated skew: {d:.4}\n", .{skew});
    std.debug.print("\n", .{});

    // Adjust quotes based on inventory skew
    const mid = Decimal.fromFloat(2500);
    const base_spread = Decimal.fromFloat(0.001);
    const base_bid = mid.sub(mid.mul(base_spread));
    const base_ask = mid.add(mid.mul(base_spread));

    std.debug.print("  Original quotes (0.1%% spread):\n", .{});
    std.debug.print("    - Bid: {d:.2}\n", .{base_bid.toFloat()});
    std.debug.print("    - Ask: {d:.2}\n", .{base_ask.toFloat()});
    std.debug.print("\n", .{});

    // Apply inventory-based quote adjustment
    const adjusted = manager.adjustQuotes(base_bid, base_ask, mid);
    std.debug.print("  Adjusted quotes (with inventory skew):\n", .{});
    std.debug.print("    - Bid: {d:.2}\n", .{adjusted.bid.toFloat()});
    std.debug.print("    - Ask: {d:.2}\n", .{adjusted.ask.toFloat()});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 6: Rebalance Actions
    // ========================================================================
    std.debug.print("--- 6. Rebalance Actions ---\n\n", .{});

    std.debug.print("  RebalanceAction = enum {{\n", .{});
    std.debug.print("      None,          // No action needed\n", .{});
    std.debug.print("      ReduceLong,    // Sell some position\n", .{});
    std.debug.print("      ReduceShort,   // Buy to cover\n", .{});
    std.debug.print("      EmergencyFlat, // Flatten immediately\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    if (manager.getRebalanceAction()) |action| {
        std.debug.print("  Rebalance action:\n", .{});
        std.debug.print("    - Direction: {s}\n", .{@tagName(action.direction)});
        std.debug.print("    - Amount: {d:.4}\n", .{action.amount.toFloat()});
        std.debug.print("    - Urgency: {s}\n", .{@tagName(action.urgency)});
    } else {
        std.debug.print("  No rebalance needed\n", .{});
    }
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 7: Statistics
    // ========================================================================
    std.debug.print("--- 7. Statistics ---\n\n", .{});

    const stats = manager.getStats();
    std.debug.print("  InventoryStats:\n", .{});
    std.debug.print("    - Current: {d:.4}\n", .{stats.current.toFloat()});
    std.debug.print("    - Ratio: {d:.2}\n", .{stats.ratio});
    std.debug.print("    - Skew: {d:.4}\n", .{stats.skew});
    std.debug.print("    - Peak: {d:.4}\n", .{stats.peak.toFloat()});
    std.debug.print("    - Needs rebalance: {s}\n", .{if (stats.needs_rebalance) "yes" else "no"});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 8: Integration
    // ========================================================================
    std.debug.print("--- 8. Integration with Market Making ---\n\n", .{});

    std.debug.print("  // In market making strategy onTick:\n", .{});
    std.debug.print("  fn onTick(self: *Self, ...) !void {{\n", .{});
    std.debug.print("      // Get skew adjustment\n", .{});
    std.debug.print("      const adj = self.inventory.getQuoteAdjustment(mid);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("      // Apply to quotes\n", .{});
    std.debug.print("      const bid = mid.sub(spread).add(adj.bid_skew);\n", .{});
    std.debug.print("      const ask = mid.add(spread).add(adj.ask_skew);\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("      // Check rebalance\n", .{});
    std.debug.print("      if (self.inventory.getRebalanceAction() == .ReduceLong) {{\n", .{});
    std.debug.print("          // Execute market sell\n", .{});
    std.debug.print("      }}\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("================================================================\n", .{});
    std.debug.print("  Inventory Management Summary\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Key Features:\n", .{});
    std.debug.print("    - Position tracking\n", .{});
    std.debug.print("    - Dynamic quote skewing\n", .{});
    std.debug.print("    - Multiple skew algorithms\n", .{});
    std.debug.print("    - Rebalance triggers\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Benefits:\n", .{});
    std.debug.print("    - Reduced directional exposure\n", .{});
    std.debug.print("    - Better capital efficiency\n", .{});
    std.debug.print("    - Risk-controlled market making\n", .{});
    std.debug.print("\n", .{});
}
