//! Example 26: Grid Trading Strategy
//!
//! This example demonstrates how to use the Grid Trading strategy
//! for automated trading within a price range.
//!
//! Grid trading works by:
//! 1. Dividing a price range into equal intervals (grids)
//! 2. Placing buy orders at lower grid levels
//! 3. When a buy fills, placing a sell order at entry + take_profit%
//! 4. When a sell fills, placing a new buy order at the original level
//! 5. Profiting from price oscillations within the grid
//!
//! To run:
//! ```bash
//! zig build example-26
//! ./zig-out/bin/example-26
//! ```
//!
//! Or use the CLI:
//! ```bash
//! # Paper trading (simulated)
//! zigquant grid --pair BTC-USDC --upper 100000 --lower 90000 --grids 10 --paper
//!
//! # Testnet trading
//! zigquant grid --pair BTC-USDC --upper 100000 --lower 90000 --grids 10 --testnet \
//!               --wallet 0x... --key abc123...
//! ```

const std = @import("std");
const zigQuant = @import("zigQuant");

const Decimal = zigQuant.Decimal;
const TradingPair = zigQuant.TradingPair;
const GridStrategy = zigQuant.GridStrategy;
const GridStrategyConfig = zigQuant.GridStrategyConfig;
const Candle = zigQuant.Candle;
const Candles = zigQuant.Candles;
const Timestamp = zigQuant.Timestamp;
const Logger = zigQuant.Logger;
const ConsoleWriter = zigQuant.ConsoleWriter;
const StrategyContext = zigQuant.strategy_interface.StrategyContext;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    var console_writer = ConsoleWriter(std.fs.File).init(allocator, std.io.getStdErr());
    var logger = Logger.init(allocator, console_writer.writer(), .info);
    defer logger.deinit();

    try logger.info("", .{});
    try logger.info("╔════════════════════════════════════════════════════╗", .{});
    try logger.info("║     Example 26: Grid Trading Strategy              ║", .{});
    try logger.info("╚════════════════════════════════════════════════════╝", .{});
    try logger.info("", .{});

    // =========================================================================
    // 1. Create Grid Strategy Configuration
    // =========================================================================

    try logger.info("Step 1: Creating Grid Strategy Configuration", .{});
    try logger.info("", .{});

    const config = GridStrategyConfig{
        .pair = TradingPair{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(100000), // Upper bound: $100,000
        .lower_price = Decimal.fromFloat(90000), // Lower bound: $90,000
        .grid_count = 10, // 10 grid levels
        .order_size = Decimal.fromFloat(0.001), // 0.001 BTC per grid
        .take_profit_pct = 0.5, // 0.5% profit per grid trade
        .enable_long = true, // Enable buy low, sell high
        .enable_short = false, // Disable shorting
        .max_position = Decimal.fromFloat(0.1), // Max 0.1 BTC total position
    };

    // Validate configuration
    try config.validate();
    try logger.info("Configuration validated successfully!", .{});
    try logger.info("", .{});

    // Print grid configuration
    try logger.info("Grid Configuration:", .{});
    try logger.info("  Price Range:    ${d:.2} - ${d:.2}", .{
        config.lower_price.toFloat(),
        config.upper_price.toFloat(),
    });
    try logger.info("  Grid Count:     {}", .{config.grid_count});
    try logger.info("  Grid Interval:  ${d:.2}", .{config.gridInterval().toFloat()});
    try logger.info("  Order Size:     {} BTC", .{config.order_size.toFloat()});
    try logger.info("  Take Profit:    {}%", .{config.take_profit_pct});
    try logger.info("", .{});

    // =========================================================================
    // 2. Print Grid Levels
    // =========================================================================

    try logger.info("Step 2: Grid Levels", .{});
    try logger.info("", .{});

    for (0..config.grid_count + 1) |i| {
        const level: u32 = @intCast(i);
        const price = config.priceAtLevel(level);
        try logger.info("  Level {d:2}: ${d:.2}", .{ level, price.toFloat() });
    }
    try logger.info("", .{});

    // =========================================================================
    // 3. Create Strategy Instance
    // =========================================================================

    try logger.info("Step 3: Creating Strategy Instance", .{});
    try logger.info("", .{});

    const strategy = try GridStrategy.create(allocator, config);
    defer strategy.destroy();

    // Initialize strategy
    const ctx = StrategyContext{
        .allocator = allocator,
        .logger = logger,
    };
    const interface = strategy.toStrategy();
    try interface.init(ctx);

    // Get metadata
    const metadata = interface.getMetadata();
    try logger.info("Strategy: {s}", .{metadata.name});
    try logger.info("Version:  {s}", .{metadata.version});
    try logger.info("Author:   {s}", .{metadata.author});
    try logger.info("", .{});

    // =========================================================================
    // 4. Simulate Price Movement
    // =========================================================================

    try logger.info("Step 4: Simulating Price Movement", .{});
    try logger.info("", .{});

    // Create simulated candles with price oscillating within the grid
    var candles = Candles.init(allocator);
    defer candles.deinit();

    // Simulate price movement: starts at 95000, drops to 92000, rises to 98000
    const prices = [_]f64{
        95000, 94500, 94000, 93500, 93000, // Dropping
        92500, 92000, 92500, 93000, 93500, // Bouncing
        94000, 94500, 95000, 95500, 96000, // Rising
        96500, 97000, 97500, 98000, 97500, // Peak and pullback
        97000, 96500, 96000, 95500, 95000, // Dropping
        94500, 94000, 94500, 95000, 95500, // Oscillating
    };

    var timestamp = Timestamp.fromMillis(1700000000000);
    for (prices) |price| {
        const candle = Candle{
            .timestamp = timestamp,
            .open = Decimal.fromFloat(price),
            .high = Decimal.fromFloat(price * 1.001),
            .low = Decimal.fromFloat(price * 0.999),
            .close = Decimal.fromFloat(price),
            .volume = Decimal.fromFloat(100),
        };
        try candles.append(candle);
        timestamp = timestamp.add(zigQuant.Duration.fromMinutes(1));
    }

    try logger.info("Created {} simulated candles", .{candles.len()});
    try logger.info("", .{});

    // =========================================================================
    // 5. Generate Signals
    // =========================================================================

    try logger.info("Step 5: Generating Trading Signals", .{});
    try logger.info("", .{});

    // Populate indicators (grid strategy doesn't use technical indicators)
    try interface.populateIndicators(&candles);

    var signal_count: u32 = 0;
    for (0..candles.len()) |i| {
        const candle = candles.get(i) orelse continue;
        const signal = try interface.generateEntrySignal(&candles, i);

        if (signal) |s| {
            defer s.deinit();
            signal_count += 1;

            try logger.info("[Signal {}] {} at price ${d:.2}", .{
                signal_count,
                @tagName(s.type),
                candle.close.toFloat(),
            });
        }
    }

    try logger.info("", .{});
    try logger.info("Total signals generated: {}", .{signal_count});
    try logger.info("", .{});

    // =========================================================================
    // 6. Summary
    // =========================================================================

    try logger.info("═══════════════════════════════════════════════════════", .{});
    try logger.info("                    Summary", .{});
    try logger.info("═══════════════════════════════════════════════════════", .{});
    try logger.info("", .{});
    try logger.info("Grid trading strategy demonstration complete!", .{});
    try logger.info("", .{});
    try logger.info("To run grid trading in real-time:", .{});
    try logger.info("", .{});
    try logger.info("  # Paper trading (simulated)", .{});
    try logger.info("  zigquant grid --pair BTC-USDC --upper 100000 --lower 90000 \\", .{});
    try logger.info("                --grids 10 --size 0.001 --paper", .{});
    try logger.info("", .{});
    try logger.info("  # Testnet trading (no real money)", .{});
    try logger.info("  zigquant grid --pair BTC-USDC --upper 100000 --lower 90000 \\", .{});
    try logger.info("                --grids 10 --size 0.001 --testnet \\", .{});
    try logger.info("                --wallet 0x... --key abc123...", .{});
    try logger.info("", .{});
    try logger.info("Key parameters to adjust:", .{});
    try logger.info("  - upper/lower: Price range (should match current market)", .{});
    try logger.info("  - grids: More grids = more trades but smaller profits", .{});
    try logger.info("  - size: Order size per grid (risk management)", .{});
    try logger.info("  - tp: Take profit % per grid trade", .{});
    try logger.info("", .{});
}
