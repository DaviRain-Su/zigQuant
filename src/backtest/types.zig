//! Backtest Engine - Type Definitions
//!
//! Core types for backtesting functionality including configuration,
//! results, trades, and equity snapshots.

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const TradingPair = @import("../exchange/types.zig").TradingPair;
const Timeframe = @import("../exchange/types.zig").Timeframe;

// ============================================================================
// Position Side
// ============================================================================

/// Position side (long or short) for backtest tracking
pub const PositionSide = enum {
    long,
    short,

    pub fn toString(self: PositionSide) []const u8 {
        return switch (self) {
            .long => "long",
            .short => "short",
        };
    }
};

// ============================================================================
// Configuration Types
// ============================================================================

/// Backtest configuration parameters
pub const BacktestConfig = struct {
    /// Trading pair to backtest
    pair: TradingPair,

    /// Candle timeframe
    timeframe: Timeframe,

    /// Start timestamp (milliseconds)
    start_time: Timestamp,

    /// End timestamp (milliseconds)
    end_time: Timestamp,

    /// Starting capital
    initial_capital: Decimal,

    /// Commission rate (default: 0.001 = 0.1%)
    commission_rate: Decimal,

    /// Slippage factor (default: 0.0005 = 0.05%)
    slippage: Decimal,

    /// Enable short positions (default: true)
    enable_short: bool = true,

    /// Max simultaneous positions (default: 1, only 1 supported in v0.4.0)
    max_positions: u32 = 1,

    /// Validate configuration
    pub fn validate(self: BacktestConfig) !void {
        // Validate time range
        if (self.end_time.millis <= self.start_time.millis) {
            return error.InvalidTimeRange;
        }

        // Validate capital
        if (!self.initial_capital.isPositive()) {
            return error.InvalidInitialCapital;
        }

        // Validate rates
        if (self.commission_rate.isNegative() or self.slippage.isNegative()) {
            return error.InvalidRates;
        }

        // Validate max positions
        if (self.max_positions == 0) {
            return error.InvalidMaxPositions;
        }
    }
};

// ============================================================================
// Trade Types
// ============================================================================

/// Represents a single completed trade
pub const Trade = struct {
    /// Unique trade identifier
    id: u64,

    /// Trading pair
    pair: TradingPair,

    /// Position side (long or short)
    side: PositionSide,

    /// Entry timestamp
    entry_time: Timestamp,

    /// Exit timestamp
    exit_time: Timestamp,

    /// Entry price
    entry_price: Decimal,

    /// Exit price
    exit_price: Decimal,

    /// Position size in base asset
    size: Decimal,

    /// Net profit/loss (after fees)
    pnl: Decimal,

    /// P&L as percentage of entry cost
    pnl_percent: Decimal,

    /// Total fees for this trade (entry + exit)
    commission: Decimal,

    /// How long position was held (minutes)
    duration_minutes: u64,

    /// Check if trade was profitable
    pub fn isWinning(self: Trade) bool {
        return self.pnl.isPositive();
    }

    /// Check if trade was a loss
    pub fn isLosing(self: Trade) bool {
        return self.pnl.isNegative();
    }
};

// ============================================================================
// Equity Snapshot
// ============================================================================

/// Equity snapshot for a point in time
pub const EquitySnapshot = struct {
    /// Timestamp of snapshot
    timestamp: Timestamp,

    /// Total account equity (balance + unrealized P&L)
    equity: Decimal,

    /// Available cash balance
    balance: Decimal,

    /// Unrealized P&L from open positions
    unrealized_pnl: Decimal,
};

// ============================================================================
// Backtest Result
// ============================================================================

/// Comprehensive results from a backtest execution
pub const BacktestResult = struct {
    allocator: std.mem.Allocator,

    // Trading statistics
    total_trades: u32,
    winning_trades: u32,
    losing_trades: u32,

    // P&L statistics
    total_profit: Decimal,
    total_loss: Decimal,
    net_profit: Decimal,

    // Performance metrics
    win_rate: f64,
    profit_factor: f64,

    // Detailed data
    trades: []Trade,
    equity_curve: []EquitySnapshot,

    // Configuration
    config: BacktestConfig,
    strategy_name: []const u8,

    /// Initialize empty result
    pub fn init(
        allocator: std.mem.Allocator,
        config: BacktestConfig,
        strategy_name: []const u8,
    ) BacktestResult {
        return .{
            .allocator = allocator,
            .total_trades = 0,
            .winning_trades = 0,
            .losing_trades = 0,
            .total_profit = Decimal.ZERO,
            .total_loss = Decimal.ZERO,
            .net_profit = Decimal.ZERO,
            .win_rate = 0.0,
            .profit_factor = 0.0,
            .trades = &[_]Trade{},
            .equity_curve = &[_]EquitySnapshot{},
            .config = config,
            .strategy_name = strategy_name,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *BacktestResult) void {
        if (self.trades.len > 0) {
            self.allocator.free(self.trades);
        }
        if (self.equity_curve.len > 0) {
            self.allocator.free(self.equity_curve);
        }
    }

    /// Calculate total commission paid
    pub fn calculateTotalCommission(self: *const BacktestResult) Decimal {
        var total = Decimal.ZERO;
        for (self.trades) |trade| {
            total = total.add(trade.commission) catch Decimal.ZERO;
        }
        return total;
    }

    /// Calculate backtest duration in days
    pub fn calculateDays(self: *const BacktestResult) u32 {
        const duration_ms = self.config.end_time.millis - self.config.start_time.millis;
        const days: u32 = @intCast(@divTrunc(duration_ms, 24 * 60 * 60 * 1000));
        return days;
    }

    /// Calculate basic statistics from trades
    pub fn calculateStats(self: *BacktestResult) !void {
        if (self.trades.len == 0) {
            return;
        }

        var winning: u32 = 0;
        var losing: u32 = 0;
        var total_profit = Decimal.ZERO;
        var total_loss = Decimal.ZERO;

        for (self.trades) |trade| {
            if (trade.isWinning()) {
                winning += 1;
                total_profit = total_profit.add(trade.pnl);
            } else if (trade.isLosing()) {
                losing += 1;
                total_loss = total_loss.add(trade.pnl.abs());
            }
        }

        self.total_trades = @intCast(self.trades.len);
        self.winning_trades = winning;
        self.losing_trades = losing;
        self.total_profit = total_profit;
        self.total_loss = total_loss;
        self.net_profit = total_profit.sub(total_loss);

        // Calculate win rate
        if (self.total_trades > 0) {
            self.win_rate = @as(f64, @floatFromInt(winning)) /
                @as(f64, @floatFromInt(self.total_trades));
        }

        // Calculate profit factor
        if (!total_loss.isZero()) {
            const pf = try total_profit.div(total_loss);
            self.profit_factor = pf.toFloat();
        } else {
            self.profit_factor = if (total_profit.isPositive()) 999.0 else 0.0;
        }
    }
};

// ============================================================================
// Errors
// ============================================================================

pub const BacktestError = error{
    /// Insufficient historical data
    InsufficientData,

    /// Invalid backtest configuration
    InvalidConfig,
    InvalidTimeRange,
    InvalidInitialCapital,
    InvalidRates,
    InvalidMaxPositions,

    /// Strategy execution error
    StrategyError,

    /// Data feed error
    DataFeedError,
    NoData,
    DataNotSorted,
    InvalidData,

    /// Position errors
    PositionAlreadyExists,
    NoPosition,

    /// File errors
    FileNotFound,
    ParseError,

    /// Memory allocation failed
    OutOfMemory,
};

// ============================================================================
// Tests
// ============================================================================

test "BacktestConfig: validation" {
    const testing = std.testing;

    // Valid config
    const valid_config = BacktestConfig{
        .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
        .timeframe = .m15,
        .start_time = .{ .millis = 1000 },
        .end_time = .{ .millis = 2000 },
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.fromFloat(0.0005),
    };
    try valid_config.validate();

    // Invalid: end before start
    const invalid_time = BacktestConfig{
        .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
        .timeframe = .m15,
        .start_time = .{ .millis = 2000 },
        .end_time = .{ .millis = 1000 },
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.fromFloat(0.0005),
    };
    try testing.expectError(error.InvalidTimeRange, invalid_time.validate());

    // Invalid: zero capital
    const invalid_capital = BacktestConfig{
        .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
        .timeframe = .m15,
        .start_time = .{ .millis = 1000 },
        .end_time = .{ .millis = 2000 },
        .initial_capital = Decimal.ZERO,
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.fromFloat(0.0005),
    };
    try testing.expectError(error.InvalidInitialCapital, invalid_capital.validate());
}

test "Trade: winning/losing detection" {
    const trade_winning = Trade{
        .id = 1,
        .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
        .side = .long,
        .entry_time = .{ .millis = 1000 },
        .exit_time = .{ .millis = 2000 },
        .entry_price = Decimal.fromInt(2000),
        .exit_price = Decimal.fromInt(2100),
        .size = Decimal.fromInt(1),
        .pnl = Decimal.fromInt(100),
        .pnl_percent = Decimal.fromFloat(0.05),
        .commission = Decimal.fromInt(5),
        .duration_minutes = 15,
    };

    try std.testing.expect(trade_winning.isWinning());
    try std.testing.expect(!trade_winning.isLosing());

    const trade_losing = Trade{
        .id = 2,
        .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
        .side = .long,
        .entry_time = .{ .millis = 1000 },
        .exit_time = .{ .millis = 2000 },
        .entry_price = Decimal.fromInt(2000),
        .exit_price = Decimal.fromInt(1900),
        .size = Decimal.fromInt(1),
        .pnl = Decimal.fromInt(-100),
        .pnl_percent = Decimal.fromFloat(-0.05),
        .commission = Decimal.fromInt(5),
        .duration_minutes = 15,
    };

    try std.testing.expect(!trade_losing.isWinning());
    try std.testing.expect(trade_losing.isLosing());
}

test "BacktestResult: calculate stats" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var result = BacktestResult.init(
        allocator,
        BacktestConfig{
            .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
            .timeframe = .m15,
            .start_time = .{ .millis = 0 },
            .end_time = .{ .millis = 1000 },
            .initial_capital = Decimal.fromInt(10000),
            .commission_rate = Decimal.fromFloat(0.001),
            .slippage = Decimal.fromFloat(0.0005),
        },
        "TestStrategy",
    );
    defer result.deinit();

    // Create test trades
    var trades = [_]Trade{
        .{
            .id = 1,
            .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
            .side = .long,
            .entry_time = .{ .millis = 0 },
            .exit_time = .{ .millis = 100 },
            .entry_price = Decimal.fromInt(2000),
            .exit_price = Decimal.fromInt(2100),
            .size = Decimal.fromInt(1),
            .pnl = Decimal.fromInt(100),
            .pnl_percent = Decimal.fromFloat(0.05),
            .commission = Decimal.fromInt(5),
            .duration_minutes = 15,
        },
        .{
            .id = 2,
            .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
            .side = .long,
            .entry_time = .{ .millis = 200 },
            .exit_time = .{ .millis = 300 },
            .entry_price = Decimal.fromInt(2000),
            .exit_price = Decimal.fromInt(1950),
            .size = Decimal.fromInt(1),
            .pnl = Decimal.fromInt(-50),
            .pnl_percent = Decimal.fromFloat(-0.025),
            .commission = Decimal.fromInt(5),
            .duration_minutes = 15,
        },
        .{
            .id = 3,
            .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
            .side = .long,
            .entry_time = .{ .millis = 400 },
            .exit_time = .{ .millis = 500 },
            .entry_price = Decimal.fromInt(2000),
            .exit_price = Decimal.fromInt(2200),
            .size = Decimal.fromInt(1),
            .pnl = Decimal.fromInt(200),
            .pnl_percent = Decimal.fromFloat(0.10),
            .commission = Decimal.fromInt(5),
            .duration_minutes = 15,
        },
    };

    result.trades = &trades;
    try result.calculateStats();

    // Verify statistics (note: setting trades to empty before cleanup to avoid double free)
    try testing.expectEqual(@as(u32, 3), result.total_trades);

    try testing.expectEqual(@as(u32, 2), result.winning_trades);
    try testing.expectEqual(@as(u32, 1), result.losing_trades);

    // Total profit = 100 + 200 = 300
    try testing.expect(result.total_profit.eql(Decimal.fromInt(300)));

    // Total loss = 50
    try testing.expect(result.total_loss.eql(Decimal.fromInt(50)));

    // Net profit = 300 - 50 = 250
    try testing.expect(result.net_profit.eql(Decimal.fromInt(250)));

    // Win rate = 2/3 = 66.67%
    try testing.expectApproxEqAbs(@as(f64, 0.6667), result.win_rate, 0.01);

    // Profit factor = 300/50 = 6.0
    try testing.expectApproxEqAbs(@as(f64, 6.0), result.profit_factor, 0.01);

    // Clear trades pointer before deinit since it points to stack memory
    result.trades = &[_]Trade{};
}

test "BacktestResult: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected!");
        }
    }
    const allocator = gpa.allocator();

    var result = BacktestResult.init(
        allocator,
        BacktestConfig{
            .pair = TradingPair{ .base = "ETH", .quote = "USDC" },
            .timeframe = .m15,
            .start_time = .{ .millis = 0 },
            .end_time = .{ .millis = 1000 },
            .initial_capital = Decimal.fromInt(10000),
            .commission_rate = Decimal.fromFloat(0.001),
            .slippage = Decimal.fromFloat(0.0005),
        },
        "TestStrategy",
    );
    defer result.deinit();

    // Allocate trades
    const trades = try allocator.alloc(Trade, 2);
    result.trades = trades;

    // Allocate equity curve
    const equity_curve = try allocator.alloc(EquitySnapshot, 100);
    result.equity_curve = equity_curve;
}
