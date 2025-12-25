# Backtest Engine API Reference

**Version**: v0.4.0
**Status**: Planned
**Last Updated**: 2025-12-25

---

## Table of Contents

1. [BacktestEngine](#backtestengine)
2. [BacktestConfig](#backtestconfig)
3. [BacktestResult](#backtestresult)
4. [PerformanceAnalyzer](#performanceanalyzer)
5. [PerformanceMetrics](#performancemetrics)
6. [HistoricalDataFeed](#historicaldatafeed)
7. [Event System](#event-system)
8. [OrderExecutor](#orderexecutor)
9. [Account & Position](#account--position)
10. [Error Types](#error-types)
11. [Usage Examples](#usage-examples)

---

## BacktestEngine

### Overview

BacktestEngine is the core component that orchestrates the entire backtesting process using historical data to validate strategy performance.

### Definition

```zig
pub const BacktestEngine = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    data_feed: *HistoricalDataFeed,

    pub fn init(allocator: std.mem.Allocator) !BacktestEngine;
    pub fn deinit(self: *BacktestEngine) void;
    pub fn run(
        self: *BacktestEngine,
        strategy: IStrategy,
        config: BacktestConfig,
    ) !BacktestResult;
};
```

### Methods

#### init

Create a new BacktestEngine instance.

```zig
pub fn init(allocator: std.mem.Allocator) !BacktestEngine
```

**Parameters**:
- `allocator`: Memory allocator for engine and data structures

**Returns**:
- `BacktestEngine`: Initialized backtest engine

**Errors**:
- `OutOfMemory`: If allocation fails

**Example**:
```zig
var engine = try BacktestEngine.init(allocator);
defer engine.deinit();
```

---

#### deinit

Clean up engine resources.

```zig
pub fn deinit(self: *BacktestEngine) void
```

**Description**:
- Frees data feed and internal allocations
- Must be called when engine is no longer needed

**Example**:
```zig
var engine = try BacktestEngine.init(allocator);
defer engine.deinit();
```

---

#### run

Execute a backtest for the given strategy and configuration.

```zig
pub fn run(
    self: *BacktestEngine,
    strategy: IStrategy,
    config: BacktestConfig,
) !BacktestResult
```

**Parameters**:
- `strategy`: Strategy implementing IStrategy interface
- `config`: Backtest configuration (pair, timeframe, dates, capital)

**Returns**:
- `BacktestResult`: Comprehensive backtest results with trades and metrics

**Errors**:
- `InsufficientData`: Not enough historical data
- `InvalidConfig`: Invalid backtest configuration
- `StrategyError`: Strategy execution error
- `OutOfMemory`: Memory allocation failed

**Description**:
- Loads historical data for specified date range
- Calculates indicators via `strategy.populateIndicators()`
- Simulates event-driven trading loop
- Executes entry/exit signals with realistic fills
- Tracks account balance and positions
- Generates comprehensive performance report

**Process Flow**:
1. Load historical candles from data feed
2. Calculate all indicators for the strategy
3. Initialize account with starting capital
4. For each candle:
   - Update position unrealized P&L
   - Check exit signals (if in position)
   - Check entry signals (if no position)
   - Execute orders with simulated fills
   - Record trades and equity snapshots
5. Force close any remaining positions
6. Calculate performance metrics
7. Return BacktestResult

**Example**:
```zig
const allocator = std.heap.page_allocator;

// Create strategy
var strategy = try DualMAStrategy.create(allocator, .{
    .fast_period = 10,
    .slow_period = 20,
});
defer strategy.deinit();

// Configure backtest
const config = BacktestConfig{
    .pair = TradingPair.fromString("ETH/USDC"),
    .timeframe = .m15,
    .start_time = try Timestamp.fromISO8601("2024-01-01T00:00:00Z"),
    .end_time = try Timestamp.fromISO8601("2024-12-31T23:59:59Z"),
    .initial_capital = try Decimal.fromInt(10000),
    .commission_rate = try Decimal.fromFloat(0.001),
    .slippage = try Decimal.fromFloat(0.0005),
};

// Run backtest
var engine = try BacktestEngine.init(allocator);
defer engine.deinit();

const result = try engine.run(strategy, config);
defer result.deinit();

// Display results
std.debug.print("Total Trades: {}\n", .{result.total_trades});
std.debug.print("Win Rate: {d:.2}%\n", .{result.win_rate * 100});
std.debug.print("Net Profit: {}\n", .{result.net_profit});
```

---

## BacktestConfig

### Overview

Configuration parameters for backtest execution.

### Definition

```zig
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
    commission_rate: Decimal = try Decimal.fromFloat(0.001),

    /// Slippage factor (default: 0.0005 = 0.05%)
    slippage: Decimal = try Decimal.fromFloat(0.0005),

    /// Enable short positions (default: true)
    enable_short: bool = true,

    /// Max simultaneous positions (default: 1)
    max_positions: u32 = 1,
};
```

### Fields

#### pair
Trading pair for the backtest (e.g., ETH/USDC, BTC/USDT).

#### timeframe
Candle timeframe enum:
- `.m1`: 1 minute
- `.m5`: 5 minutes
- `.m15`: 15 minutes
- `.m30`: 30 minutes
- `.h1`: 1 hour
- `.h4`: 4 hours
- `.d1`: 1 day

#### start_time / end_time
Unix timestamp in milliseconds defining the backtest date range.

**Helper Functions**:
```zig
// From ISO 8601 string
const start = try Timestamp.fromISO8601("2024-01-01T00:00:00Z");

// From date components
const end = try Timestamp.fromDate(2024, 12, 31, 23, 59, 59);
```

#### initial_capital
Starting capital in quote currency (e.g., USDC).

#### commission_rate
Trading fee as decimal (0.001 = 0.1%). Applied to both entry and exit.

**Common Values**:
- Maker fee: 0.0002 (0.02%)
- Taker fee: 0.0005 (0.05%)
- Hyperliquid: 0.00025 (0.025% taker)

#### slippage
Simulated price slippage as decimal (0.0005 = 0.05%).

**Calculation**:
```zig
fill_price = close_price * (1 + slippage)  // For buys
fill_price = close_price * (1 - slippage)  // For sells
```

#### enable_short
Allow strategy to open short positions.

#### max_positions
Maximum number of simultaneous positions (currently only 1 supported).

### Example

```zig
const config = BacktestConfig{
    .pair = TradingPair.fromString("BTC/USDT"),
    .timeframe = .h1,
    .start_time = try Timestamp.fromDate(2024, 1, 1, 0, 0, 0),
    .end_time = try Timestamp.fromDate(2024, 12, 31, 23, 59, 59),
    .initial_capital = try Decimal.fromInt(100000),
    .commission_rate = try Decimal.fromFloat(0.0005),
    .slippage = try Decimal.fromFloat(0.0003),
    .enable_short = true,
    .max_positions = 1,
};
```

---

## BacktestResult

### Overview

Comprehensive results from a backtest execution.

### Definition

```zig
pub const BacktestResult = struct {
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

    pub fn deinit(self: *BacktestResult) void;
    pub fn calculateTotalCommission(self: *BacktestResult) Decimal;
    pub fn calculateDays(self: *BacktestResult) u32;

    pub const EquitySnapshot = struct {
        timestamp: Timestamp,
        equity: Decimal,
        balance: Decimal,
        unrealized_pnl: Decimal,
    };
};
```

### Fields

#### Trading Statistics
- `total_trades`: Number of completed round-trip trades
- `winning_trades`: Number of profitable trades
- `losing_trades`: Number of losing trades

#### P&L Statistics
- `total_profit`: Sum of all profits from winning trades
- `total_loss`: Sum of all losses from losing trades
- `net_profit`: `total_profit - total_loss`

#### Performance Metrics
- `win_rate`: `winning_trades / total_trades` (0.0 to 1.0)
- `profit_factor`: `total_profit / total_loss` (higher is better)

#### Detailed Data
- `trades`: Array of all executed trades
- `equity_curve`: Time series of account equity

### Methods

#### deinit

Free backtest result resources.

```zig
pub fn deinit(self: *BacktestResult) void
```

**Example**:
```zig
const result = try engine.run(strategy, config);
defer result.deinit();
```

---

#### calculateTotalCommission

Calculate total fees paid during backtest.

```zig
pub fn calculateTotalCommission(self: *BacktestResult) Decimal
```

**Returns**:
- `Decimal`: Total commission paid across all trades

**Example**:
```zig
const total_fees = result.calculateTotalCommission();
std.debug.print("Total fees paid: {}\n", .{total_fees});
```

---

#### calculateDays

Calculate backtest duration in days.

```zig
pub fn calculateDays(self: *BacktestResult) u32
```

**Returns**:
- `u32`: Number of days from start to end

**Example**:
```zig
const days = result.calculateDays();
std.debug.print("Backtest duration: {} days\n", .{days});
```

---

### Trade

Represents a single completed trade.

```zig
pub const Trade = struct {
    id: u64,
    pair: TradingPair,
    side: Side,  // .long or .short
    entry_time: Timestamp,
    exit_time: Timestamp,
    entry_price: Decimal,
    exit_price: Decimal,
    size: Decimal,
    pnl: Decimal,
    pnl_percent: Decimal,
    commission: Decimal,
    duration_minutes: u64,
};
```

**Fields**:
- `id`: Unique trade identifier
- `pair`: Trading pair
- `side`: Position side (long/short)
- `entry_time` / `exit_time`: Trade timestamps
- `entry_price` / `exit_price`: Fill prices
- `size`: Position size in base asset
- `pnl`: Net profit/loss (after fees)
- `pnl_percent`: P&L as percentage of entry cost
- `commission`: Total fees for this trade
- `duration_minutes`: How long position was held

---

## PerformanceAnalyzer

### Overview

Analyzes backtest results and calculates comprehensive performance metrics.

### Definition

```zig
pub const PerformanceAnalyzer = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    pub fn init(allocator: std.mem.Allocator) PerformanceAnalyzer;
    pub fn analyze(
        self: *PerformanceAnalyzer,
        result: BacktestResult,
    ) !PerformanceMetrics;
};
```

### Methods

#### init

Create a new PerformanceAnalyzer.

```zig
pub fn init(allocator: std.mem.Allocator) PerformanceAnalyzer
```

**Example**:
```zig
var analyzer = PerformanceAnalyzer.init(allocator);
```

---

#### analyze

Calculate comprehensive performance metrics.

```zig
pub fn analyze(
    self: *PerformanceAnalyzer,
    result: BacktestResult,
) !PerformanceMetrics
```

**Parameters**:
- `result`: Backtest result to analyze

**Returns**:
- `PerformanceMetrics`: Detailed performance analysis

**Example**:
```zig
var analyzer = PerformanceAnalyzer.init(allocator);
const metrics = try analyzer.analyze(result);

std.debug.print("Sharpe Ratio: {d:.2}\n", .{metrics.sharpe_ratio});
std.debug.print("Max Drawdown: {d:.2}%\n", .{metrics.max_drawdown * 100});
std.debug.print("Annual Return: {d:.2}%\n", .{metrics.annualized_return * 100});
```

---

## PerformanceMetrics

### Overview

Comprehensive performance analysis metrics.

### Definition

```zig
pub const PerformanceMetrics = struct {
    // Profit metrics
    total_profit: Decimal,
    total_loss: Decimal,
    net_profit: Decimal,
    profit_factor: f64,
    average_profit: Decimal,
    average_loss: Decimal,
    expectancy: Decimal,

    // Win rate metrics
    total_trades: u32,
    winning_trades: u32,
    losing_trades: u32,
    win_rate: f64,
    max_consecutive_wins: u32,
    max_consecutive_losses: u32,

    // Risk metrics
    max_drawdown: f64,
    max_drawdown_duration_days: u32,
    sharpe_ratio: f64,
    sortino_ratio: f64,
    calmar_ratio: f64,

    // Trade statistics
    average_hold_time_minutes: f64,
    max_hold_time_minutes: u64,
    min_hold_time_minutes: u64,
    average_trade_interval_minutes: f64,

    // Return metrics
    total_return: f64,
    annualized_return: f64,
    best_month_return: f64,
    worst_month_return: f64,

    // Equity curve
    equity_peak: Decimal,
    equity_trough: Decimal,
    equity_volatility: f64,

    // Configuration
    initial_capital: Decimal,
    final_equity: Decimal,
    total_commission: Decimal,
    backtest_days: u32,
};
```

### Key Metrics Explained

#### Profit Factor
Ratio of total profit to total loss. Higher is better.
- `< 1.0`: Strategy loses money
- `1.0 - 1.5`: Marginal profitability
- `1.5 - 2.0`: Good profitability
- `> 2.0`: Excellent profitability

**Formula**: `total_profit / total_loss`

---

#### Expectancy
Expected profit per trade.

**Formula**: `avg_profit × win_rate - avg_loss × (1 - win_rate)`

---

#### Sharpe Ratio
Risk-adjusted return metric. Higher is better.
- `< 1.0`: Poor risk-adjusted returns
- `1.0 - 2.0`: Good
- `2.0 - 3.0`: Very good
- `> 3.0`: Excellent

**Formula**: `(annual_return - risk_free_rate) / annual_volatility`

---

#### Sortino Ratio
Similar to Sharpe but only considers downside volatility.

**Formula**: `(annual_return - risk_free_rate) / downside_volatility`

---

#### Calmar Ratio
Return relative to maximum drawdown.

**Formula**: `annualized_return / max_drawdown`

---

#### Maximum Drawdown
Largest peak-to-trough decline in equity.
- `< 10%`: Low risk
- `10% - 20%`: Moderate risk
- `20% - 30%`: High risk
- `> 30%`: Very high risk

**Formula**: `max((peak - trough) / peak)` over all time periods

---

## HistoricalDataFeed

### Overview

Loads and validates historical candle data for backtesting.

### Definition

```zig
pub const HistoricalDataFeed = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    pub fn init(allocator: std.mem.Allocator) HistoricalDataFeed;
    pub fn load(
        self: *HistoricalDataFeed,
        pair: TradingPair,
        timeframe: Timeframe,
        start_time: Timestamp,
        end_time: Timestamp,
    ) !Candles;
};
```

### Methods

#### load

Load historical candle data.

```zig
pub fn load(
    self: *HistoricalDataFeed,
    pair: TradingPair,
    timeframe: Timeframe,
    start_time: Timestamp,
    end_time: Timestamp,
) !Candles
```

**Parameters**:
- `pair`: Trading pair
- `timeframe`: Candle interval
- `start_time`: Start timestamp (ms)
- `end_time`: End timestamp (ms)

**Returns**:
- `Candles`: Loaded and validated candle data

**Errors**:
- `NoData`: No data available for range
- `DataNotSorted`: Timestamps not in order
- `InvalidData`: Validation failed

**Data Sources** (in order of priority):
1. Local database cache
2. CSV files
3. Exchange API (Hyperliquid, etc.)

**Validation**:
- Timestamps in ascending order
- No duplicate timestamps
- Valid OHLCV data (high ≥ low, etc.)

**Example**:
```zig
var data_feed = HistoricalDataFeed.init(allocator);

const candles = try data_feed.load(
    TradingPair.fromString("ETH/USDC"),
    .m15,
    try Timestamp.fromDate(2024, 1, 1, 0, 0, 0),
    try Timestamp.fromDate(2024, 12, 31, 23, 59, 59),
);
defer candles.deinit();

std.debug.print("Loaded {} candles\n", .{candles.data.len});
```

---

## Event System

### Overview

Event-driven architecture for realistic trade simulation.

### Event Types

```zig
pub const EventType = enum {
    market,   // New candle data
    signal,   // Strategy generated signal
    order,    // Order created
    fill,     // Order filled
};

pub const Event = union(EventType) {
    market: MarketEvent,
    signal: SignalEvent,
    order: OrderEvent,
    fill: FillEvent,
};
```

### MarketEvent

New candle arrives.

```zig
pub const MarketEvent = struct {
    timestamp: Timestamp,
    candle: Candle,
};
```

### SignalEvent

Strategy generates trading signal.

```zig
pub const SignalEvent = struct {
    timestamp: Timestamp,
    signal: Signal,
};
```

### OrderEvent

Order created.

```zig
pub const OrderEvent = struct {
    id: u64,
    timestamp: Timestamp,
    pair: TradingPair,
    side: Side,  // .buy or .sell
    type: OrderType,  // .market or .limit
    price: Decimal,
    size: Decimal,

    pub const OrderType = enum {
        market,
        limit,
    };
};
```

### FillEvent

Order executed.

```zig
pub const FillEvent = struct {
    order_id: u64,
    timestamp: Timestamp,
    fill_price: Decimal,
    fill_size: Decimal,
    commission: Decimal,
};
```

---

## OrderExecutor

### Overview

Simulates order execution with realistic fills, slippage, and commissions.

### Definition

```zig
pub const OrderExecutor = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    config: BacktestConfig,
    next_order_id: u64,

    pub fn init(allocator: std.mem.Allocator, config: BacktestConfig) OrderExecutor;
    pub fn executeMarketOrder(
        self: *OrderExecutor,
        order: OrderEvent,
        current_candle: Candle,
    ) !FillEvent;
    pub fn generateOrderId(self: *OrderExecutor) u64;
};
```

### Methods

#### executeMarketOrder

Execute a market order against current candle.

```zig
pub fn executeMarketOrder(
    self: *OrderExecutor,
    order: OrderEvent,
    current_candle: Candle,
) !FillEvent
```

**Parameters**:
- `order`: Order to execute
- `current_candle`: Current market candle

**Returns**:
- `FillEvent`: Execution details

**Execution Logic**:
1. Use candle close price as base
2. Apply slippage:
   - Buy: `price × (1 + slippage)`
   - Sell: `price × (1 - slippage)`
3. Calculate commission: `fill_price × size × commission_rate`
4. Generate FillEvent

**Example**:
```zig
var executor = OrderExecutor.init(allocator, config);

const order = OrderEvent{
    .id = executor.generateOrderId(),
    .timestamp = candle.timestamp,
    .pair = config.pair,
    .side = .buy,
    .type = .market,
    .price = candle.close,
    .size = try Decimal.fromFloat(1.0),
};

const fill = try executor.executeMarketOrder(order, candle);
std.debug.print("Filled at: {}\n", .{fill.fill_price});
std.debug.print("Commission: {}\n", .{fill.commission});
```

---

## Account & Position

### Account

Tracks account balance and equity.

```zig
pub const Account = struct {
    initial_capital: Decimal,
    balance: Decimal,
    equity: Decimal,
    total_commission: Decimal,

    pub fn init(initial_capital: Decimal) Account;
    pub fn updateEquity(self: *Account, unrealized_pnl: Decimal) !void;
};
```

**Fields**:
- `initial_capital`: Starting capital
- `balance`: Available cash
- `equity`: Total account value (balance + unrealized P&L)
- `total_commission`: Cumulative fees

---

### Position

Tracks open position.

```zig
pub const Position = struct {
    pair: TradingPair,
    side: Side,  // .long or .short
    size: Decimal,
    entry_price: Decimal,
    entry_time: Timestamp,
    unrealized_pnl: Decimal,

    pub fn init(
        pair: TradingPair,
        side: Side,
        size: Decimal,
        entry_price: Decimal,
        entry_time: Timestamp,
    ) Position;

    pub fn updateUnrealizedPnL(self: *Position, current_price: Decimal) !void;
    pub fn calculatePnL(self: *Position, exit_price: Decimal) !Decimal;
};
```

**Methods**:

#### updateUnrealizedPnL

Update unrealized P&L based on current price.

```zig
pub fn updateUnrealizedPnL(self: *Position, current_price: Decimal) !void
```

**Example**:
```zig
var position = Position.init(pair, .long, size, entry_price, timestamp);

for (candles) |candle| {
    try position.updateUnrealizedPnL(candle.close);
    std.debug.print("Unrealized P&L: {}\n", .{position.unrealized_pnl});
}
```

---

#### calculatePnL

Calculate realized P&L for given exit price.

```zig
pub fn calculatePnL(self: *Position, exit_price: Decimal) !Decimal
```

**Formula**:
- Long: `(exit_price - entry_price) × size`
- Short: `(entry_price - exit_price) × size`

**Example**:
```zig
const pnl = try position.calculatePnL(exit_price);
if (pnl.isPositive()) {
    std.debug.print("Profit: {}\n", .{pnl});
} else {
    std.debug.print("Loss: {}\n", .{try pnl.abs()});
}
```

---

## Error Types

```zig
pub const BacktestError = error{
    /// Insufficient historical data
    InsufficientData,

    /// Invalid backtest configuration
    InvalidConfig,

    /// Strategy execution error
    StrategyError,

    /// Data feed error
    DataFeedError,

    /// No data available
    NoData,

    /// Data validation failed
    DataNotSorted,
    InvalidData,

    /// Position already exists
    PositionAlreadyExists,

    /// Memory allocation failed
    OutOfMemory,
};
```

---

## Usage Examples

### Basic Backtest

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create strategy
    var strategy = try zigQuant.DualMAStrategy.create(allocator, .{
        .fast_period = 10,
        .slow_period = 20,
    });
    defer strategy.deinit();

    // Configure backtest
    const config = zigQuant.BacktestConfig{
        .pair = zigQuant.TradingPair.fromString("ETH/USDC"),
        .timeframe = .m15,
        .start_time = try zigQuant.Timestamp.fromDate(2024, 1, 1, 0, 0, 0),
        .end_time = try zigQuant.Timestamp.fromDate(2024, 12, 31, 23, 59, 59),
        .initial_capital = try zigQuant.Decimal.fromInt(10000),
    };

    // Run backtest
    var engine = try zigQuant.BacktestEngine.init(allocator);
    defer engine.deinit();

    const result = try engine.run(strategy, config);
    defer result.deinit();

    // Print results
    std.debug.print("=== Backtest Results ===\n", .{});
    std.debug.print("Total Trades: {}\n", .{result.total_trades});
    std.debug.print("Win Rate: {d:.1}%\n", .{result.win_rate * 100});
    std.debug.print("Net Profit: {}\n", .{result.net_profit});
    std.debug.print("Profit Factor: {d:.2}\n", .{result.profit_factor});
}
```

---

### With Performance Analysis

```zig
pub fn main() !void {
    // ... setup allocator, strategy, config ...

    // Run backtest
    var engine = try BacktestEngine.init(allocator);
    defer engine.deinit();

    const result = try engine.run(strategy, config);
    defer result.deinit();

    // Analyze performance
    var analyzer = PerformanceAnalyzer.init(allocator);
    const metrics = try analyzer.analyze(result);

    // Print comprehensive metrics
    std.debug.print("=== Performance Report ===\n", .{});
    std.debug.print("Total Return: {d:.2}%\n", .{metrics.total_return * 100});
    std.debug.print("Annual Return: {d:.2}%\n", .{metrics.annualized_return * 100});
    std.debug.print("Sharpe Ratio: {d:.2}\n", .{metrics.sharpe_ratio});
    std.debug.print("Max Drawdown: {d:.2}%\n", .{metrics.max_drawdown * 100});
    std.debug.print("Win Rate: {d:.1}%\n", .{metrics.win_rate * 100});
    std.debug.print("Profit Factor: {d:.2}\n", .{metrics.profit_factor});
    std.debug.print("Expectancy: {}\n", .{metrics.expectancy});
}
```

---

### Analyzing Trade List

```zig
pub fn analyzeBacktest(result: BacktestResult) !void {
    std.debug.print("=== Trade Analysis ===\n", .{});

    for (result.trades, 0..) |trade, i| {
        const side_str = if (trade.side == .long) "LONG" else "SHORT";
        const pnl_str = if (trade.pnl.isPositive()) "PROFIT" else "LOSS";

        std.debug.print("Trade {}: {} {} {}\n", .{
            i + 1,
            side_str,
            trade.pair.toString(),
            pnl_str,
        });
        std.debug.print("  Entry: {} @ {}\n", .{
            trade.entry_time,
            trade.entry_price,
        });
        std.debug.print("  Exit: {} @ {}\n", .{
            trade.exit_time,
            trade.exit_price,
        });
        std.debug.print("  P&L: {} ({d:.2}%)\n", .{
            trade.pnl,
            try trade.pnl_percent.toFloat() * 100,
        });
        std.debug.print("  Duration: {} minutes\n", .{trade.duration_minutes});
        std.debug.print("  Fees: {}\n\n", .{trade.commission});
    }
}
```

---

### Equity Curve Analysis

```zig
pub fn plotEquityCurve(result: BacktestResult) !void {
    var max_equity = result.equity_curve[0].equity;
    var peak_timestamp = result.equity_curve[0].timestamp;
    var max_dd: f64 = 0.0;

    std.debug.print("=== Equity Curve ===\n", .{});

    for (result.equity_curve) |snapshot| {
        // Update peak
        if (snapshot.equity.gt(max_equity)) {
            max_equity = snapshot.equity;
            peak_timestamp = snapshot.timestamp;
        }

        // Calculate drawdown
        const dd_amount = try max_equity.sub(snapshot.equity);
        const dd_pct = try dd_amount.div(max_equity).toFloat();
        max_dd = @max(max_dd, dd_pct);

        // Print snapshot
        std.debug.print("{}: Equity={} DD={d:.2}%\n", .{
            snapshot.timestamp,
            snapshot.equity,
            dd_pct * 100,
        });
    }

    std.debug.print("\nMax Drawdown: {d:.2}%\n", .{max_dd * 100});
}
```

---

**Version**: v0.4.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-25
