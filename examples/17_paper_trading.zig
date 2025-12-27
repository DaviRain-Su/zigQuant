//! Example 17: Paper Trading Engine (v0.6.0)
//!
//! This example demonstrates the Paper Trading Engine for risk-free strategy
//! testing with real market data but simulated order execution.
//!
//! Features:
//! - Real-time market data connection
//! - Simulated order execution
//! - Position tracking and PnL calculation
//! - Trading statistics and reporting
//!
//! Run: zig build run-example-paper-trading

const std = @import("std");
const zigQuant = @import("zigQuant");

const PaperTradingEngine = zigQuant.PaperTradingEngine;
const PaperTradingConfig = zigQuant.PaperTradingConfig;
const Decimal = zigQuant.Decimal;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    // Using std.debug.print for output

    std.debug.print("\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("       Example 17: Paper Trading Engine (v0.6.0)\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 1: Introduction
    // ========================================================================
    std.debug.print("--- 1. Introduction ---\n\n", .{});
    std.debug.print("Paper Trading Engine provides:\n", .{});
    std.debug.print("  - Risk-free strategy testing\n", .{});
    std.debug.print("  - Real market data simulation\n", .{});
    std.debug.print("  - Realistic order execution with slippage\n", .{});
    std.debug.print("  - Position and balance tracking\n", .{});
    std.debug.print("  - Comprehensive trading statistics\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 2: Configuration
    // ========================================================================
    std.debug.print("--- 2. Configuration ---\n\n", .{});

    std.debug.print("  const PaperTradingConfig = struct {{\n", .{});
    std.debug.print("      initial_balance: Decimal = 10000,\n", .{});
    std.debug.print("      commission_rate: Decimal = 0.0005,  // 0.05%%\n", .{});
    std.debug.print("      slippage: Decimal = 0.0001,         // 0.01%%\n", .{});
    std.debug.print("      log_trades: bool = true,\n", .{});
    std.debug.print("      tick_interval_ms: u32 = 1000,\n", .{});
    std.debug.print("  }};\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 3: Basic Usage
    // ========================================================================
    std.debug.print("--- 3. Basic Usage ---\n\n", .{});

    // Create paper trading engine
    var engine = PaperTradingEngine.init(allocator, .{
        .initial_balance = Decimal.fromInt(100000),
        .commission_rate = Decimal.fromFloat(0.0005),
        .slippage = Decimal.fromFloat(0.0001),
        .log_trades = false, // Disable logging for demo
    });
    defer engine.deinit();

    // Connect internal components
    engine.connectComponents();

    std.debug.print("  Created engine with:\n", .{});
    std.debug.print("    - Initial balance: {d:.2} USDT\n", .{engine.config.initial_balance.toFloat()});
    std.debug.print("    - Commission rate: {d:.4}%%\n", .{engine.config.commission_rate.toFloat() * 100});
    std.debug.print("    - Slippage: {d:.4}%%\n", .{engine.config.slippage.toFloat() * 100});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 4: Trading Simulation
    // ========================================================================
    std.debug.print("--- 4. Trading Simulation ---\n\n", .{});

    // Start paper trading
    engine.start();
    std.debug.print("  Paper trading started!\n", .{});
    std.debug.print("    - Running: {s}\n", .{if (engine.isRunning()) "yes" else "no"});
    std.debug.print("\n", .{});

    // Simulate some trades
    std.debug.print("  Simulating trades:\n\n", .{});

    // Buy ETH
    const buy_order_id = try std.fmt.allocPrint(allocator, "paper-1", .{});
    defer allocator.free(buy_order_id);

    const buy_result = try engine.submitOrder(.{
        .client_order_id = buy_order_id,
        .symbol = "ETH",
        .side = .buy,
        .order_type = .market,
        .quantity = Decimal.fromInt(2),
        .price = Decimal.fromInt(2500), // Simulated market price
    });

    std.debug.print("  Trade 1: BUY 2 ETH @ 2500\n", .{});
    std.debug.print("    - Success: {s}\n", .{if (buy_result.success) "yes" else "no"});

    // Check position
    if (engine.getPosition("ETH")) |pos| {
        std.debug.print("    - Position: {d:.4} ETH\n", .{pos.quantity.toFloat()});
        std.debug.print("    - Entry Price: {d:.2}\n", .{pos.entry_price.toFloat()});
    }
    std.debug.print("\n", .{});

    // Sell half
    const sell_order_id = try std.fmt.allocPrint(allocator, "paper-2", .{});
    defer allocator.free(sell_order_id);

    const sell_result = try engine.submitOrder(.{
        .client_order_id = sell_order_id,
        .symbol = "ETH",
        .side = .sell,
        .order_type = .market,
        .quantity = Decimal.fromInt(1),
        .price = Decimal.fromInt(2600), // Simulated higher price
    });

    std.debug.print("  Trade 2: SELL 1 ETH @ 2600\n", .{});
    std.debug.print("    - Success: {s}\n", .{if (sell_result.success) "yes" else "no"});

    // Check updated position
    if (engine.getPosition("ETH")) |pos| {
        std.debug.print("    - Remaining: {d:.4} ETH\n", .{pos.quantity.toFloat()});
    }
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 5: Account Statistics
    // ========================================================================
    std.debug.print("--- 5. Account Statistics ---\n\n", .{});

    const stats = engine.getStats();

    std.debug.print("  Balance:\n", .{});
    std.debug.print("    - Current: {d:.2} USDT\n", .{stats.current_balance.toFloat()});
    std.debug.print("    - Available: {d:.2} USDT\n", .{engine.getAvailableBalance().toFloat()});
    std.debug.print("    - Equity: {d:.2} USDT\n", .{engine.getEquity().toFloat()});
    std.debug.print("\n", .{});

    std.debug.print("  Trading Stats:\n", .{});
    std.debug.print("    - Total trades: {d}\n", .{stats.total_trades});
    std.debug.print("    - Winning trades: {d}\n", .{stats.winning_trades});
    std.debug.print("    - Losing trades: {d}\n", .{stats.losing_trades});
    std.debug.print("    - Win rate: {d:.1}%%\n", .{stats.win_rate * 100});
    std.debug.print("\n", .{});

    std.debug.print("  PnL:\n", .{});
    std.debug.print("    - Total PnL: {d:.2} USDT\n", .{stats.total_pnl.toFloat()});
    std.debug.print("    - Total return: {d:.2}%%\n", .{stats.total_return_pct});
    std.debug.print("    - Profit factor: {d:.2}\n", .{stats.profit_factor});
    std.debug.print("    - Max drawdown: {d:.2}%%\n", .{stats.max_drawdown * 100});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 6: Price Updates
    // ========================================================================
    std.debug.print("--- 6. Price Updates ---\n\n", .{});

    std.debug.print("  Simulating price movement:\n", .{});

    // Update ETH price and see PnL change
    engine.updatePrice("ETH", Decimal.fromInt(2700));
    std.debug.print("    ETH price -> 2700: ", .{});
    if (engine.getPosition("ETH")) |pos| {
        std.debug.print("Unrealized PnL: {d:.2}\n", .{pos.unrealized_pnl.toFloat()});
    }

    engine.updatePrice("ETH", Decimal.fromInt(2400));
    std.debug.print("    ETH price -> 2400: ", .{});
    if (engine.getPosition("ETH")) |pos| {
        std.debug.print("Unrealized PnL: {d:.2}\n", .{pos.unrealized_pnl.toFloat()});
    }

    std.debug.print("\n", .{});

    // ========================================================================
    // Section 7: Tick Processing
    // ========================================================================
    std.debug.print("--- 7. Tick Processing ---\n\n", .{});

    std.debug.print("  The engine processes ticks for:\n", .{});
    std.debug.print("    - Limit order matching\n", .{});
    std.debug.print("    - Position PnL updates\n", .{});
    std.debug.print("    - Statistics tracking\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  // In your main loop:\n", .{});
    std.debug.print("  while (running) {{\n", .{});
    std.debug.print("      engine.tick();\n", .{});
    std.debug.print("      std.time.sleep(tick_interval_ns);\n", .{});
    std.debug.print("  }}\n", .{});
    std.debug.print("\n", .{});

    // Process some ticks
    for (0..5) |_| {
        engine.tick();
    }
    std.debug.print("  Processed 5 ticks\n", .{});
    std.debug.print("\n", .{});

    // ========================================================================
    // Section 8: Reset and Stop
    // ========================================================================
    std.debug.print("--- 8. Reset and Stop ---\n\n", .{});

    // Stop trading
    engine.stop();
    std.debug.print("  Paper trading stopped.\n", .{});
    std.debug.print("    - Running: {s}\n", .{if (engine.isRunning()) "yes" else "no"});
    std.debug.print("\n", .{});

    // Reset to initial state
    engine.reset();
    std.debug.print("  Engine reset to initial state.\n", .{});
    std.debug.print("    - Balance: {d:.2} USDT\n", .{engine.getBalance().toFloat()});
    std.debug.print("    - Positions: {s}\n", .{if (engine.getPosition("ETH") == null) "none" else "exists"});
    std.debug.print("\n", .{});

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("================================================================\n", .{});
    std.debug.print("  Paper Trading Engine Summary\n", .{});
    std.debug.print("================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Key Features:\n", .{});
    std.debug.print("    - Zero-risk strategy testing\n", .{});
    std.debug.print("    - Realistic execution simulation\n", .{});
    std.debug.print("    - Commission and slippage modeling\n", .{});
    std.debug.print("    - Comprehensive statistics tracking\n", .{});
    std.debug.print("    - Position and balance management\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Use Cases:\n", .{});
    std.debug.print("    - Strategy validation before live trading\n", .{});
    std.debug.print("    - Testing with real market data\n", .{});
    std.debug.print("    - Parameter optimization\n", .{});
    std.debug.print("    - Risk-free experimentation\n", .{});
    std.debug.print("\n", .{});
}
