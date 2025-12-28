//! Grid Trading Strategy
//!
//! A classic grid trading strategy that places buy and sell orders at regular
//! price intervals within a defined price range. The strategy profits from
//! price oscillations within the grid.
//!
//! Strategy Parameters:
//! - `upper_price` - Upper bound of the grid (required)
//! - `lower_price` - Lower bound of the grid (required)
//! - `grid_count` - Number of grid levels (default: 10)
//! - `order_size` - Size per grid order (default: 0.001)
//! - `take_profit_pct` - Take profit percentage per grid (default: 0.5%)
//!
//! How it works:
//! 1. Divides price range into equal intervals
//! 2. Places buy orders at lower grid levels
//! 3. Places sell orders at higher grid levels
//! 4. When a buy order fills, places a sell order above it
//! 5. When a sell order fills, places a buy order below it
//!
//! Best suited for:
//! - Range-bound/sideways markets
//! - High volatility within a range
//! - Pairs with good liquidity

const std = @import("std");
const Decimal = @import("../../root.zig").Decimal;
const Candles = @import("../../root.zig").Candles;
const TradingPair = @import("../../root.zig").TradingPair;
const Timestamp = @import("../../root.zig").Timestamp;
const Side = @import("../../root.zig").Side;
const IStrategy = @import("../interface.zig").IStrategy;
const StrategyContext = @import("../interface.zig").StrategyContext;
const Signal = @import("../signal.zig").Signal;
const SignalType = @import("../signal.zig").SignalType;
const SignalMetadata = @import("../signal.zig").SignalMetadata;
const IndicatorValue = @import("../signal.zig").IndicatorValue;
const StrategyMetadata = @import("../types.zig").StrategyMetadata;
const StrategyParameter = @import("../types.zig").StrategyParameter;
const StrategyType = @import("../types.zig").StrategyType;
const Position = @import("../../backtest/position.zig").Position;
const Account = @import("../../backtest/account.zig").Account;
const Logger = @import("../../root.zig").Logger;
const Timeframe = @import("../../root.zig").Timeframe;

// ============================================================================
// Configuration
// ============================================================================

/// Grid Strategy configuration
pub const Config = struct {
    /// Trading pair
    pair: TradingPair,

    /// Upper price bound of the grid
    upper_price: Decimal,

    /// Lower price bound of the grid
    lower_price: Decimal,

    /// Number of grid levels (default: 10)
    grid_count: u32 = 10,

    /// Order size per grid level (in base currency)
    order_size: Decimal = Decimal.fromFloat(0.001),

    /// Take profit percentage per grid (default: 0.5%)
    take_profit_pct: f64 = 0.5,

    /// Enable long orders (buy low, sell high)
    enable_long: bool = true,

    /// Enable short orders (sell high, buy low)
    enable_short: bool = false,

    /// Maximum total position size (in base currency)
    max_position: Decimal = Decimal.fromFloat(1.0),

    /// Validate configuration
    pub fn validate(self: Config) !void {
        if (self.upper_price.cmp(self.lower_price) != .gt) {
            return error.UpperPriceMustBeGreaterThanLower;
        }
        if (self.grid_count < 2) {
            return error.GridCountTooSmall;
        }
        if (self.grid_count > 100) {
            return error.GridCountTooLarge;
        }
        if (self.order_size.cmp(Decimal.ZERO) != .gt) {
            return error.OrderSizeMustBePositive;
        }
        if (self.take_profit_pct <= 0) {
            return error.TakeProfitMustBePositive;
        }
    }

    /// Calculate grid interval (price difference between levels)
    pub fn gridInterval(self: Config) Decimal {
        const range = self.upper_price.sub(self.lower_price);
        const count = Decimal.fromInt(@intCast(self.grid_count));
        return range.div(count) catch Decimal.ZERO;
    }

    /// Get price at a specific grid level (0 = lower, grid_count = upper)
    pub fn priceAtLevel(self: Config, level: u32) Decimal {
        const interval = self.gridInterval();
        const level_dec = Decimal.fromInt(@intCast(level));
        return self.lower_price.add(interval.mul(level_dec));
    }

    /// Find the grid level for a given price
    pub fn levelForPrice(self: Config, price: Decimal) ?u32 {
        if (price.cmp(self.lower_price) == .lt or price.cmp(self.upper_price) == .gt) {
            return null;
        }
        const range = price.sub(self.lower_price);
        const interval = self.gridInterval();
        if (interval.isZero()) return null;
        const level_f = range.div(interval) catch return null;
        const level = @as(u32, @intFromFloat(level_f.toFloat()));
        return @min(level, self.grid_count);
    }
};

// ============================================================================
// Grid Level State
// ============================================================================

/// State of a single grid level
pub const GridLevel = struct {
    /// Grid level index (0 = lowest price)
    level: u32,
    /// Price at this level
    price: Decimal,
    /// Whether we have a buy order pending at this level
    has_buy_order: bool = false,
    /// Whether we have a sell order pending at this level
    has_sell_order: bool = false,
    /// Whether we hold position from buying at this level
    has_position: bool = false,
    /// Entry price if holding position
    entry_price: ?Decimal = null,
};

// ============================================================================
// Grid Trading Strategy
// ============================================================================

/// Grid Trading Strategy Implementation
pub const GridStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    logger: Logger,
    initialized: bool,

    /// Grid levels state
    grid_levels: []GridLevel,

    /// Current position size
    current_position: Decimal,

    /// Total realized PnL
    realized_pnl: Decimal,

    /// Number of completed grid trades
    trades_completed: u32,

    /// Last known price
    last_price: ?Decimal,

    /// Create a new Grid strategy instance
    pub fn create(allocator: std.mem.Allocator, config: Config) !*GridStrategy {
        // Validate configuration
        try config.validate();

        const self = try allocator.create(GridStrategy);
        errdefer allocator.destroy(self);

        // Initialize grid levels
        const grid_levels = try allocator.alloc(GridLevel, config.grid_count + 1);
        errdefer allocator.free(grid_levels);

        for (0..config.grid_count + 1) |i| {
            const level: u32 = @intCast(i);
            grid_levels[i] = GridLevel{
                .level = level,
                .price = config.priceAtLevel(level),
            };
        }

        self.* = .{
            .allocator = allocator,
            .config = config,
            .logger = undefined, // Will be set in init()
            .initialized = false,
            .grid_levels = grid_levels,
            .current_position = Decimal.ZERO,
            .realized_pnl = Decimal.ZERO,
            .trades_completed = 0,
            .last_price = null,
        };

        return self;
    }

    /// Convert to IStrategy interface
    pub fn toStrategy(self: *GridStrategy) IStrategy {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    /// Destroy strategy and free resources
    pub fn destroy(self: *GridStrategy) void {
        self.allocator.free(self.grid_levels);
        self.allocator.destroy(self);
    }

    /// Get grid level that price crossed from above
    fn findCrossedLevelFromAbove(self: *GridStrategy, prev_price: Decimal, curr_price: Decimal) ?*GridLevel {
        for (self.grid_levels) |*level| {
            // Price crossed this level from above (sell trigger)
            if (prev_price.cmp(level.price) != .lt and curr_price.cmp(level.price) == .lt) {
                return level;
            }
        }
        return null;
    }

    /// Get grid level that price crossed from below
    fn findCrossedLevelFromBelow(self: *GridStrategy, prev_price: Decimal, curr_price: Decimal) ?*GridLevel {
        for (self.grid_levels) |*level| {
            // Price crossed this level from below (buy trigger)
            if (prev_price.cmp(level.price) != .gt and curr_price.cmp(level.price) == .gt) {
                return level;
            }
        }
        return null;
    }

    /// Find lowest level without position (for buy)
    fn findLowestEmptyLevel(self: *GridStrategy, current_price: Decimal) ?*GridLevel {
        var best: ?*GridLevel = null;
        for (self.grid_levels) |*level| {
            if (level.price.cmp(current_price) == .lt and !level.has_position) {
                if (best == null or level.price.cmp(best.?.price) == .lt) {
                    best = level;
                }
            }
        }
        return best;
    }

    /// Find highest level with position (for sell)
    fn findHighestFilledLevel(self: *GridStrategy, current_price: Decimal) ?*GridLevel {
        var best: ?*GridLevel = null;
        for (self.grid_levels) |*level| {
            if (level.price.cmp(current_price) == .lt and level.has_position) {
                if (best == null or level.price.cmp(best.?.price) == .gt) {
                    best = level;
                }
            }
        }
        return best;
    }

    /// Check if we can open more position
    fn canOpenMorePosition(self: *GridStrategy) bool {
        return self.current_position.cmp(self.config.max_position) == .lt;
    }

    /// Calculate take profit price for a buy entry
    fn takeProfitPrice(self: *GridStrategy, entry_price: Decimal) Decimal {
        const tp_multiplier = Decimal.fromFloat(1.0 + self.config.take_profit_pct / 100.0);
        return entry_price.mul(tp_multiplier);
    }

    // ========================================================================
    // VTable Implementation
    // ========================================================================

    fn init(ptr: *anyopaque, ctx: StrategyContext) !void {
        const self: *GridStrategy = @ptrCast(@alignCast(ptr));
        self.logger = ctx.logger;
        self.initialized = true;

        // Log grid configuration
        const interval = self.config.gridInterval();
        try self.logger.info("Grid Strategy initialized:", .{});
        try self.logger.info("  Price range: {d:.2} - {d:.2}", .{
            self.config.lower_price.toFloat(),
            self.config.upper_price.toFloat(),
        });
        try self.logger.info("  Grid count: {d}, Interval: {d:.4}", .{
            self.config.grid_count,
            interval.toFloat(),
        });
        try self.logger.info("  Order size: {d:.6}", .{self.config.order_size.toFloat()});
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *GridStrategy = @ptrCast(@alignCast(ptr));
        self.initialized = false;
    }

    fn populateIndicators(ptr: *anyopaque, candles: *Candles) !void {
        _ = ptr;
        _ = candles;
        // Grid strategy doesn't need technical indicators
        // It only uses price levels
    }

    fn generateEntrySignal(
        ptr: *anyopaque,
        candles: *Candles,
        index: usize,
    ) !?Signal {
        const self: *GridStrategy = @ptrCast(@alignCast(ptr));

        const current_candle = candles.get(index) orelse return null;
        const current_price = current_candle.close;
        const timestamp = current_candle.timestamp;

        // Check if price is within grid range
        if (current_price.cmp(self.config.lower_price) == .lt or
            current_price.cmp(self.config.upper_price) == .gt)
        {
            return null;
        }

        // Need previous price for crossover detection
        if (self.last_price == null) {
            self.last_price = current_price;
            return null;
        }
        const prev_price = self.last_price.?;
        self.last_price = current_price;

        // Long strategy: Buy when price crosses grid level from above
        if (self.config.enable_long) {
            // Look for buy opportunity - price dropped to a grid level
            const crossed_level = self.findCrossedLevelFromAbove(prev_price, current_price);
            if (crossed_level) |level| {
                if (!level.has_position and self.canOpenMorePosition()) {
                    // Mark level as having position
                    level.has_position = true;
                    level.entry_price = level.price;

                    // Update current position
                    self.current_position = self.current_position.add(self.config.order_size);

                    const metadata = try SignalMetadata.init(
                        self.allocator,
                        "Grid Buy: Price dropped to grid level",
                        &[_]IndicatorValue{
                            .{ .name = "grid_level", .value = Decimal.fromInt(@intCast(level.level)) },
                            .{ .name = "grid_price", .value = level.price },
                            .{ .name = "current_position", .value = self.current_position },
                        },
                    );

                    const signal = try Signal.init(
                        .entry_long,
                        self.config.pair,
                        .buy,
                        level.price,
                        0.7, // Signal strength
                        timestamp,
                        metadata,
                    );
                    return signal;
                }
            }
        }

        // Short strategy: Sell when price crosses grid level from below
        if (self.config.enable_short) {
            const crossed_level = self.findCrossedLevelFromBelow(prev_price, current_price);
            if (crossed_level) |level| {
                if (!level.has_sell_order) {
                    level.has_sell_order = true;

                    const metadata = try SignalMetadata.init(
                        self.allocator,
                        "Grid Sell (Short): Price rose to grid level",
                        &[_]IndicatorValue{
                            .{ .name = "grid_level", .value = Decimal.fromInt(@intCast(level.level)) },
                            .{ .name = "grid_price", .value = level.price },
                        },
                    );

                    const signal = try Signal.init(
                        .entry_short,
                        self.config.pair,
                        .sell,
                        level.price,
                        0.7,
                        timestamp,
                        metadata,
                    );
                    return signal;
                }
            }
        }

        return null;
    }

    fn generateExitSignal(
        ptr: *anyopaque,
        candles: *Candles,
        position: Position,
    ) !?Signal {
        const self: *GridStrategy = @ptrCast(@alignCast(ptr));

        const index = candles.len() - 1;
        const current_candle = candles.get(index) orelse return null;
        const current_price = current_candle.close;
        const timestamp = current_candle.timestamp;

        // Exit long positions when price rises above take profit
        if (position.side == .long) {
            // Find the grid level with position that has reached take profit
            for (self.grid_levels) |*level| {
                if (level.has_position and level.entry_price != null) {
                    const tp_price = self.takeProfitPrice(level.entry_price.?);

                    if (current_price.cmp(tp_price) != .lt) {
                        // Take profit reached!
                        level.has_position = false;

                        // Calculate profit
                        const profit = current_price.sub(level.entry_price.?).mul(self.config.order_size);
                        self.realized_pnl = self.realized_pnl.add(profit);
                        self.current_position = self.current_position.sub(self.config.order_size);
                        self.trades_completed += 1;

                        const metadata = try SignalMetadata.init(
                            self.allocator,
                            "Grid Take Profit: Target price reached",
                            &[_]IndicatorValue{
                                .{ .name = "grid_level", .value = Decimal.fromInt(@intCast(level.level)) },
                                .{ .name = "entry_price", .value = level.entry_price.? },
                                .{ .name = "exit_price", .value = current_price },
                                .{ .name = "profit", .value = profit },
                                .{ .name = "total_pnl", .value = self.realized_pnl },
                                .{ .name = "trades_completed", .value = Decimal.fromInt(@intCast(self.trades_completed)) },
                            },
                        );

                        level.entry_price = null;

                        const signal = try Signal.init(
                            .exit_long,
                            position.pair,
                            .sell,
                            current_price,
                            0.9, // High confidence for TP
                            timestamp,
                            metadata,
                        );
                        return signal;
                    }
                }
            }
        }

        // Exit short positions
        if (position.side == .short) {
            for (self.grid_levels) |*level| {
                if (level.has_sell_order and level.entry_price != null) {
                    // Take profit for short = price drops by take_profit_pct
                    const tp_multiplier = Decimal.fromFloat(1.0 - self.config.take_profit_pct / 100.0);
                    const tp_price = level.entry_price.?.mul(tp_multiplier);

                    if (current_price.cmp(tp_price) != .gt) {
                        level.has_sell_order = false;

                        const profit = level.entry_price.?.sub(current_price).mul(self.config.order_size);
                        self.realized_pnl = self.realized_pnl.add(profit);
                        self.trades_completed += 1;

                        const metadata = try SignalMetadata.init(
                            self.allocator,
                            "Grid Short Take Profit",
                            &[_]IndicatorValue{
                                .{ .name = "profit", .value = profit },
                            },
                        );

                        level.entry_price = null;

                        const signal = try Signal.init(
                            .exit_short,
                            position.pair,
                            .buy,
                            current_price,
                            0.9,
                            timestamp,
                            metadata,
                        );
                        return signal;
                    }
                }
            }
        }

        return null;
    }

    fn calculatePositionSize(
        ptr: *anyopaque,
        signal: Signal,
        account: Account,
    ) !Decimal {
        const self: *GridStrategy = @ptrCast(@alignCast(ptr));
        _ = account;
        _ = signal;

        // Grid strategy uses fixed order size
        return self.config.order_size;
    }

    fn getParameters(ptr: *anyopaque) []const StrategyParameter {
        const self: *GridStrategy = @ptrCast(@alignCast(ptr));

        const params = [_]StrategyParameter{
            .{
                .name = "upper_price",
                .description = "Upper price bound",
                .value = .{ .decimal = self.config.upper_price },
            },
            .{
                .name = "lower_price",
                .description = "Lower price bound",
                .value = .{ .decimal = self.config.lower_price },
            },
            .{
                .name = "grid_count",
                .description = "Number of grid levels",
                .value = .{ .integer = @intCast(self.config.grid_count) },
            },
            .{
                .name = "order_size",
                .description = "Order size per level",
                .value = .{ .decimal = self.config.order_size },
            },
            .{
                .name = "take_profit_pct",
                .description = "Take profit percentage",
                .value = .{ .decimal = Decimal.fromFloat(self.config.take_profit_pct) },
            },
        };

        return &params;
    }

    fn getMetadata(ptr: *anyopaque) StrategyMetadata {
        const self: *GridStrategy = @ptrCast(@alignCast(ptr));

        const roi_targets = [_]@import("../types.zig").ROITarget{
            .{ .time_minutes = 0, .profit_ratio = Decimal.fromFloat(0.02) }, // 2% immediate
            .{ .time_minutes = 60, .profit_ratio = Decimal.fromFloat(0.01) }, // 1% after 1hr
        };

        return .{
            .name = "Grid Trading Strategy",
            .version = "1.0.0",
            .author = "zigQuant",
            .description = "Automated grid trading strategy for range-bound markets",
            .strategy_type = .mean_reversion,
            .timeframe = .m1,
            .startup_candle_count = self.config.grid_count,
            .minimal_roi = .{ .targets = &roi_targets },
            .stoploss = Decimal.fromFloat(-0.10), // -10% stop loss (wider for grid)
            .trailing_stop = null,
        };
    }

    const vtable = IStrategy.VTable{
        .init = init,
        .deinit = deinit,
        .populateIndicators = populateIndicators,
        .generateEntrySignal = generateEntrySignal,
        .generateExitSignal = generateExitSignal,
        .calculatePositionSize = calculatePositionSize,
        .getParameters = getParameters,
        .getMetadata = getMetadata,
    };
};

// ============================================================================
// Tests
// ============================================================================

test "GridStrategy: config validation" {
    const testing = std.testing;

    // Valid config
    const valid_config = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(50000),
        .lower_price = Decimal.fromFloat(40000),
        .grid_count = 10,
    };
    try valid_config.validate();

    // Invalid: upper <= lower
    const invalid_config1 = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(40000),
        .lower_price = Decimal.fromFloat(50000),
        .grid_count = 10,
    };
    try testing.expectError(error.UpperPriceMustBeGreaterThanLower, invalid_config1.validate());

    // Invalid: grid_count too small
    const invalid_config2 = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(50000),
        .lower_price = Decimal.fromFloat(40000),
        .grid_count = 1,
    };
    try testing.expectError(error.GridCountTooSmall, invalid_config2.validate());
}

test "GridStrategy: grid interval calculation" {
    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(50000),
        .lower_price = Decimal.fromFloat(40000),
        .grid_count = 10,
    };

    const interval = config.gridInterval();
    // (50000 - 40000) / 10 = 1000
    try std.testing.expectApproxEqAbs(@as(f64, 1000.0), interval.toFloat(), 0.01);
}

test "GridStrategy: price at level" {
    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(50000),
        .lower_price = Decimal.fromFloat(40000),
        .grid_count = 10,
    };

    // Level 0 should be lower_price
    const level0 = config.priceAtLevel(0);
    try std.testing.expectApproxEqAbs(@as(f64, 40000.0), level0.toFloat(), 0.01);

    // Level 5 should be midpoint
    const level5 = config.priceAtLevel(5);
    try std.testing.expectApproxEqAbs(@as(f64, 45000.0), level5.toFloat(), 0.01);

    // Level 10 should be upper_price
    const level10 = config.priceAtLevel(10);
    try std.testing.expectApproxEqAbs(@as(f64, 50000.0), level10.toFloat(), 0.01);
}

test "GridStrategy: level for price" {
    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(50000),
        .lower_price = Decimal.fromFloat(40000),
        .grid_count = 10,
    };

    // Price at lower bound
    const level_at_40k = config.levelForPrice(Decimal.fromFloat(40000));
    try std.testing.expectEqual(@as(?u32, 0), level_at_40k);

    // Price at upper bound
    const level_at_50k = config.levelForPrice(Decimal.fromFloat(50000));
    try std.testing.expectEqual(@as(?u32, 10), level_at_50k);

    // Price in middle
    const level_at_45k = config.levelForPrice(Decimal.fromFloat(45000));
    try std.testing.expectEqual(@as(?u32, 5), level_at_45k);

    // Price outside range
    const level_below = config.levelForPrice(Decimal.fromFloat(39000));
    try std.testing.expectEqual(@as(?u32, null), level_below);

    const level_above = config.levelForPrice(Decimal.fromFloat(51000));
    try std.testing.expectEqual(@as(?u32, null), level_above);
}

test "GridStrategy: create and destroy" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(50000),
        .lower_price = Decimal.fromFloat(40000),
        .grid_count = 10,
        .order_size = Decimal.fromFloat(0.01),
    };

    const strategy = try GridStrategy.create(allocator, config);
    defer strategy.destroy();

    try testing.expectEqual(@as(usize, 11), strategy.grid_levels.len); // grid_count + 1
    try testing.expect(strategy.current_position.isZero());
    try testing.expect(strategy.realized_pnl.isZero());
    try testing.expectEqual(@as(u32, 0), strategy.trades_completed);
}

test "GridStrategy: interface" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const config = Config{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(50000),
        .lower_price = Decimal.fromFloat(40000),
        .grid_count = 10,
    };

    const strategy = try GridStrategy.create(allocator, config);
    defer strategy.destroy();

    const interface = strategy.toStrategy();
    const metadata = interface.getMetadata();

    try testing.expectEqualStrings("Grid Trading Strategy", metadata.name);
    try testing.expectEqualStrings("1.0.0", metadata.version);
}
