# Story 020: BacktestEngine - Implementation-Ready Specification

**Story ID**: STORY-020
**Version**: v0.3.0
**Priority**: P0
**Effort**: 2 days
**Status**: Ready for Implementation
**Created**: 2025-12-25
**Updated**: 2025-12-25

---

## Table of Contents
1. [Overview](#overview)
2. [Data Format Specifications](#data-format-specifications)
3. [Event Loop State Machine](#event-loop-state-machine)
4. [Component Architecture](#component-architecture)
5. [Error Handling Strategy](#error-handling-strategy)
6. [Integration with StrategyContext](#integration-with-strategycontext)
7. [Concrete Configuration Examples](#concrete-configuration-examples)
8. [Sequence Diagrams](#sequence-diagrams)
9. [Testing Specifications](#testing-specifications)
10. [Mock Strategies](#mock-strategies)
11. [Implementation Checklist](#implementation-checklist)

---

## Overview

### User Story
As a **quantitative trading developer**, I want to **use a backtest engine to validate strategies on historical data**, so that **I can evaluate profitability and risk before live trading**.

### Business Value
- Core strategy validation capability
- Historical data replay with event-driven simulation
- Realistic trading environment (orders, fees, slippage)
- Foundation for parameter optimization
- Risk reduction through thorough pre-live testing

### Dependencies
**Prerequisite Stories**:
- STORY-013: IStrategy Interface ✓
- STORY-014: StrategyContext ✓
- STORY-015: Technical Indicators ✓
- STORY-017: DualMAStrategy (for testing)
- STORY-018: RSIMeanReversionStrategy (for testing)
- STORY-019: BollingerBreakoutStrategy (for testing)

**Dependent Stories**:
- STORY-021: PerformanceAnalyzer
- STORY-022: GridSearchOptimizer
- STORY-023: CLI Strategy Commands

---

## Data Format Specifications

### 1. Historical Data Storage Format

#### CSV Format (Primary)
```csv
timestamp,open,high,low,close,volume
1704067200000,42350.50,42450.75,42200.00,42380.25,1234.56
1704067800000,42380.25,42500.00,42350.00,42475.80,987.32
```

**Requirements**:
- Timestamp: Unix milliseconds (i64)
- Prices: String representation of Decimal (18 decimal places)
- Volume: String representation of Decimal
- Sorted ascending by timestamp (MUST be enforced)
- No gaps in time series (validation required)
- File naming: `{pair}_{timeframe}_{start}_{end}.csv`
  - Example: `BTCUSDT_15m_1704067200000_1706745600000.csv`

#### JSON Format (Alternative)
```json
{
  "pair": "BTC/USDT",
  "timeframe": "15m",
  "data": [
    {
      "t": 1704067200000,
      "o": "42350.50",
      "h": "42450.75",
      "l": "42200.00",
      "c": "42380.25",
      "v": "1234.56"
    }
  ]
}
```

### 2. Data Loading Interface

```zig
/// Historical data feed configuration
pub const DataFeedConfig = struct {
    /// Data source type
    source: DataSource,

    /// Base directory for CSV files
    data_dir: []const u8,

    /// Enable data validation
    validate: bool = true,

    /// Cache loaded data in memory
    enable_cache: bool = true,

    pub const DataSource = enum {
        csv,      // Load from CSV files
        json,     // Load from JSON files
        memory,   // Use in-memory test data
    };
};

/// Load historical data from CSV
pub fn loadFromCSV(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) !Candles {
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var buffered = std.io.bufferedReader(file.reader());
    var reader = buffered.reader();

    var candles = Candles.init(allocator);
    errdefer candles.deinit();

    var line_buf: [1024]u8 = undefined;
    var line_num: usize = 0;

    while (try reader.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
        line_num += 1;

        // Skip header
        if (line_num == 1 and std.mem.startsWith(u8, line, "timestamp")) {
            continue;
        }

        const candle = try parseCSVLine(line, line_num);
        try candles.append(candle);
    }

    return candles;
}

fn parseCSVLine(line: []const u8, line_num: usize) !Candle {
    var iter = std.mem.split(u8, line, ",");

    const timestamp_str = iter.next() orelse return error.MissingTimestamp;
    const open_str = iter.next() orelse return error.MissingOpen;
    const high_str = iter.next() orelse return error.MissingHigh;
    const low_str = iter.next() orelse return error.MissingLow;
    const close_str = iter.next() orelse return error.MissingClose;
    const volume_str = iter.next() orelse return error.MissingVolume;

    return Candle{
        .timestamp = try Timestamp.fromUnixMillis(
            try std.fmt.parseInt(i64, timestamp_str, 10)
        ),
        .open = try Decimal.fromString(open_str),
        .high = try Decimal.fromString(high_str),
        .low = try Decimal.fromString(low_str),
        .close = try Decimal.fromString(close_str),
        .volume = try Decimal.fromString(volume_str),
    };
}
```

### 3. Data Validation Requirements

```zig
/// Validate candle data integrity
pub fn validateCandles(candles: *const Candles) !void {
    if (candles.data.len == 0) {
        return error.EmptyDataset;
    }

    // Check each candle's OHLCV consistency
    for (candles.data) |candle| {
        try candle.validate(); // From candles.zig
    }

    // Check time series continuity
    for (1..candles.data.len) |i| {
        const prev = candles.data[i - 1];
        const curr = candles.data[i];

        // Must be sorted ascending
        if (curr.timestamp.unix <= prev.timestamp.unix) {
            std.log.err("Candles not sorted at index {}: {} <= {}", .{
                i, curr.timestamp.unix, prev.timestamp.unix
            });
            return error.DataNotSorted;
        }

        // Check for reasonable gaps (optional, based on timeframe)
        // For 15m data, gap should be exactly 900000ms (15 minutes)
        // Allow some tolerance for exchange downtime
    }
}
```

---

## Event Loop State Machine

### State Diagram

```
┌─────────────┐
│   INITIAL   │
└──────┬──────┘
       │
       │ 1. Load Data
       ▼
┌─────────────────┐
│  DATA_LOADED    │
└──────┬──────────┘
       │
       │ 2. Calculate Indicators
       ▼
┌──────────────────┐
│ INDICATORS_READY │
└──────┬───────────┘
       │
       │ 3. Enter Event Loop
       ▼
┌────────────────────────────────────────────┐
│          EVENT LOOP (per candle)           │
│                                            │
│  ┌─────────────────────────────────────┐  │
│  │ 1. UPDATE_POSITION                  │  │
│  │    - Update unrealized P&L          │  │
│  │    - Update equity                  │  │
│  └──────┬──────────────────────────────┘  │
│         │                                  │
│         ▼                                  │
│  ┌─────────────────────────────────────┐  │
│  │ 2. SNAPSHOT_EQUITY                  │  │
│  │    - Record equity curve point      │  │
│  └──────┬──────────────────────────────┘  │
│         │                                  │
│         ▼                                  │
│  ┌─────────────────────────────────────┐  │
│  │ 3. CHECK_EXIT                       │  │
│  │    - If has position:               │  │
│  │      • Generate exit signal         │  │
│  │      • If signal → EXECUTE_EXIT     │  │
│  │      • Else → CHECK_ENTRY           │  │
│  │    - If no position → CHECK_ENTRY   │  │
│  └──────┬──────────────────────────────┘  │
│         │                                  │
│         ▼                                  │
│  ┌─────────────────────────────────────┐  │
│  │ 4. CHECK_ENTRY                      │  │
│  │    - If no position:                │  │
│  │      • Generate entry signal        │  │
│  │      • If signal → EXECUTE_ENTRY    │  │
│  │    - If has position → skip         │  │
│  └──────┬──────────────────────────────┘  │
│         │                                  │
│         ▼                                  │
│  ┌─────────────────────────────────────┐  │
│  │ 5. ADVANCE_CANDLE                   │  │
│  │    - Move to next candle            │  │
│  │    - If more candles → loop         │  │
│  │    - If done → FINALIZE             │  │
│  └─────────────────────────────────────┘  │
│                                            │
└────────────────────────────────────────────┘
       │
       │ All candles processed
       ▼
┌─────────────────┐
│    FINALIZE     │
│ - Close open    │
│   positions     │
│ - Calculate     │
│   statistics    │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│    COMPLETE     │
└─────────────────┘
```

### State Transitions

```zig
pub const BacktestState = enum {
    initial,
    data_loaded,
    indicators_ready,
    running,
    finalizing,
    complete,
    error_state,
};

pub const BacktestEngine = struct {
    state: BacktestState,

    /// Execute state machine
    pub fn run(self: *BacktestEngine, strategy: IStrategy, config: BacktestConfig) !BacktestResult {
        try self.transitionTo(.initial);

        // 1. Load data
        const candles = try self.loadData(config);
        try self.transitionTo(.data_loaded);

        // 2. Calculate indicators
        try strategy.populateIndicators(&candles);
        try self.transitionTo(.indicators_ready);

        // 3. Run event loop
        try self.transitionTo(.running);
        try self.eventLoop(strategy, &candles, config);

        // 4. Finalize
        try self.transitionTo(.finalizing);
        const result = try self.finalize(strategy, config);

        try self.transitionTo(.complete);
        return result;
    }

    fn transitionTo(self: *BacktestEngine, new_state: BacktestState) !void {
        const valid = switch (self.state) {
            .initial => new_state == .data_loaded,
            .data_loaded => new_state == .indicators_ready,
            .indicators_ready => new_state == .running,
            .running => new_state == .finalizing or new_state == .error_state,
            .finalizing => new_state == .complete or new_state == .error_state,
            .complete => false, // Terminal state
            .error_state => false, // Terminal state
        };

        if (!valid) {
            return error.InvalidStateTransition;
        }

        self.logger.debug("State transition: {} -> {}", .{self.state, new_state});
        self.state = new_state;
    }
};
```

---

## Component Architecture

### High-Level Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      BacktestEngine                          │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              Event Loop Coordinator                    │  │
│  │  - State management                                    │  │
│  │  - Event sequencing                                    │  │
│  │  - Progress tracking                                   │  │
│  └─────┬────────────────────────────────────────────┬─────┘  │
│        │                                            │         │
│  ┌─────▼──────────┐                       ┌────────▼─────┐   │
│  │ DataFeed       │                       │ OrderExecutor│   │
│  │ - Load CSV     │                       │ - Market     │   │
│  │ - Validate     │                       │ - Limit      │   │
│  │ - Cache        │                       │ - Slippage   │   │
│  └────────────────┘                       └──────────────┘   │
│                                                               │
│  ┌────────────────┐                       ┌──────────────┐   │
│  │ AccountManager │                       │ PositionMgr  │   │
│  │ - Balance      │                       │ - Track P&L  │   │
│  │ - Equity       │                       │ - Open/Close │   │
│  │ - Commissions  │                       │ - Exposure   │   │
│  └────────────────┘                       └──────────────┘   │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Result Aggregator                          │ │
│  │  - Collect trades                                       │ │
│  │  - Build equity curve                                   │ │
│  │  - Calculate statistics                                 │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### Component Details

#### 1. BacktestEngine (Core Coordinator)

```zig
pub const BacktestEngine = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    state: BacktestState,

    // Components
    data_feed: HistoricalDataFeed,
    account: Account,
    position_manager: PositionManager,
    executor: OrderExecutor,

    // Results tracking
    trades: std.ArrayList(Trade),
    equity_curve: std.ArrayList(EquitySnapshot),

    // Progress tracking
    processed_candles: usize,
    total_candles: usize,
    start_time: i64,

    pub fn init(allocator: std.mem.Allocator, config: DataFeedConfig) !BacktestEngine {
        return BacktestEngine{
            .allocator = allocator,
            .logger = Logger.init("BacktestEngine"),
            .state = .initial,
            .data_feed = try HistoricalDataFeed.init(allocator, config),
            .account = Account.init(Decimal.ZERO), // Will be set by config
            .position_manager = PositionManager.init(allocator),
            .executor = OrderExecutor.init(allocator),
            .trades = std.ArrayList(Trade).init(allocator),
            .equity_curve = std.ArrayList(EquitySnapshot).init(allocator),
            .processed_candles = 0,
            .total_candles = 0,
            .start_time = 0,
        };
    }

    pub fn deinit(self: *BacktestEngine) void {
        self.data_feed.deinit();
        self.position_manager.deinit();
        self.trades.deinit();
        self.equity_curve.deinit();
    }
};
```

#### 2. HistoricalDataFeed

```zig
pub const HistoricalDataFeed = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    config: DataFeedConfig,

    // Cache: key = "pair_timeframe_start_end", value = Candles
    cache: std.StringHashMap(Candles),

    pub fn init(allocator: std.mem.Allocator, config: DataFeedConfig) !HistoricalDataFeed {
        return HistoricalDataFeed{
            .allocator = allocator,
            .logger = Logger.init("DataFeed"),
            .config = config,
            .cache = std.StringHashMap(Candles).init(allocator),
        };
    }

    pub fn deinit(self: *HistoricalDataFeed) void {
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.cache.deinit();
    }

    pub fn load(
        self: *HistoricalDataFeed,
        pair: TradingPair,
        timeframe: Timeframe,
        start_time: Timestamp,
        end_time: Timestamp,
    ) !Candles {
        // Generate cache key
        const cache_key = try std.fmt.allocPrint(
            self.allocator,
            "{s}_{s}_{d}_{d}",
            .{ pair.toString(), @tagName(timeframe), start_time.unix, end_time.unix }
        );
        defer self.allocator.free(cache_key);

        // Check cache
        if (self.config.enable_cache) {
            if (self.cache.get(cache_key)) |cached| {
                self.logger.debug("Cache hit for {s}", .{cache_key});
                return cached;
            }
        }

        // Load from source
        const candles = switch (self.config.source) {
            .csv => try self.loadCSV(pair, timeframe, start_time, end_time),
            .json => try self.loadJSON(pair, timeframe, start_time, end_time),
            .memory => return error.MemorySourceNotImplemented,
        };

        // Validate
        if (self.config.validate) {
            try validateCandles(&candles);
        }

        // Cache
        if (self.config.enable_cache) {
            const key_copy = try self.allocator.dupe(u8, cache_key);
            try self.cache.put(key_copy, candles);
        }

        return candles;
    }

    fn loadCSV(
        self: *HistoricalDataFeed,
        pair: TradingPair,
        timeframe: Timeframe,
        start_time: Timestamp,
        end_time: Timestamp,
    ) !Candles {
        const filename = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}_{s}_{d}_{d}.csv",
            .{ self.config.data_dir, pair.toString(), @tagName(timeframe),
               start_time.unix, end_time.unix }
        );
        defer self.allocator.free(filename);

        self.logger.info("Loading CSV: {s}", .{filename});
        return try loadFromCSV(self.allocator, filename);
    }
};
```

#### 3. OrderExecutor (Backtest Mode)

```zig
pub const OrderExecutor = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    next_order_id: u64,

    pub fn init(allocator: std.mem.Allocator) OrderExecutor {
        return .{
            .allocator = allocator,
            .logger = Logger.init("OrderExecutor"),
            .next_order_id = 1,
        };
    }

    /// Execute market order with slippage simulation
    pub fn executeMarketOrder(
        self: *OrderExecutor,
        side: Side,
        size: Decimal,
        current_candle: Candle,
        commission_rate: Decimal,
        slippage: Decimal,
    ) !FillEvent {
        const order_id = self.nextOrderId();

        // Calculate fill price with slippage
        // Buy: price * (1 + slippage)
        // Sell: price * (1 - slippage)
        const base_price = current_candle.close;
        const slippage_multiplier = switch (side) {
            .buy => Decimal.ONE.add(slippage),
            .sell => Decimal.ONE.sub(slippage),
        };
        const fill_price = base_price.mul(slippage_multiplier);

        // Calculate commission
        const notional = fill_price.mul(size);
        const commission = notional.mul(commission_rate);

        self.logger.debug(
            "Order {}: {} {} @ {} (slippage: {}, commission: {})",
            .{ order_id, @tagName(side), size, fill_price, slippage, commission }
        );

        return FillEvent{
            .order_id = order_id,
            .timestamp = current_candle.timestamp,
            .side = side,
            .fill_price = fill_price,
            .fill_size = size,
            .commission = commission,
        };
    }

    fn nextOrderId(self: *OrderExecutor) u64 {
        const id = self.next_order_id;
        self.next_order_id += 1;
        return id;
    }
};

pub const FillEvent = struct {
    order_id: u64,
    timestamp: Timestamp,
    side: Side,
    fill_price: Decimal,
    fill_size: Decimal,
    commission: Decimal,
};
```

#### 4. Account Manager

```zig
pub const Account = struct {
    initial_capital: Decimal,
    balance: Decimal,              // Available cash
    equity: Decimal,               // Balance + unrealized P&L
    total_commission: Decimal,
    realized_pnl: Decimal,
    unrealized_pnl: Decimal,

    pub fn init(initial_capital: Decimal) Account {
        return .{
            .initial_capital = initial_capital,
            .balance = initial_capital,
            .equity = initial_capital,
            .total_commission = Decimal.ZERO,
            .realized_pnl = Decimal.ZERO,
            .unrealized_pnl = Decimal.ZERO,
        };
    }

    /// Update equity with current unrealized P&L
    pub fn updateEquity(self: *Account, unrealized_pnl: Decimal) void {
        self.unrealized_pnl = unrealized_pnl;
        self.equity = self.balance.add(unrealized_pnl);
    }

    /// Process buy order fill
    pub fn processBuy(
        self: *Account,
        fill_price: Decimal,
        size: Decimal,
        commission: Decimal,
    ) !void {
        const cost = fill_price.mul(size);
        const total_cost = cost.add(commission);

        if (self.balance.cmp(total_cost) == .lt) {
            return error.InsufficientBalance;
        }

        self.balance = self.balance.sub(total_cost);
        self.total_commission = self.total_commission.add(commission);
    }

    /// Process sell order fill
    pub fn processSell(
        self: *Account,
        fill_price: Decimal,
        size: Decimal,
        commission: Decimal,
        pnl: Decimal,
    ) !void {
        const proceeds = fill_price.mul(size);
        const net_proceeds = proceeds.sub(commission);

        self.balance = self.balance.add(net_proceeds);
        self.total_commission = self.total_commission.add(commission);
        self.realized_pnl = self.realized_pnl.add(pnl);
        self.unrealized_pnl = Decimal.ZERO;
    }
};
```

#### 5. Position Manager

```zig
pub const PositionManager = struct {
    allocator: std.mem.Allocator,
    current_position: ?Position,

    pub const Position = struct {
        pair: TradingPair,
        side: Side,
        size: Decimal,
        entry_price: Decimal,
        entry_time: Timestamp,
        current_price: Decimal,
        unrealized_pnl: Decimal,

        pub fn init(
            pair: TradingPair,
            side: Side,
            size: Decimal,
            entry_price: Decimal,
            entry_time: Timestamp,
        ) Position {
            return .{
                .pair = pair,
                .side = side,
                .size = size,
                .entry_price = entry_price,
                .entry_time = entry_time,
                .current_price = entry_price,
                .unrealized_pnl = Decimal.ZERO,
            };
        }

        pub fn updatePnL(self: *Position, current_price: Decimal) void {
            self.current_price = current_price;

            // Long: (current - entry) * size
            // Short: (entry - current) * size
            const price_diff = switch (self.side) {
                .buy => current_price.sub(self.entry_price),
                .sell => self.entry_price.sub(current_price),
            };

            self.unrealized_pnl = price_diff.mul(self.size);
        }

        pub fn calculateExitPnL(self: Position, exit_price: Decimal) Decimal {
            const price_diff = switch (self.side) {
                .buy => exit_price.sub(self.entry_price),
                .sell => self.entry_price.sub(exit_price),
            };

            return price_diff.mul(self.size);
        }
    };

    pub fn init(allocator: std.mem.Allocator) PositionManager {
        return .{
            .allocator = allocator,
            .current_position = null,
        };
    }

    pub fn deinit(self: *PositionManager) void {
        _ = self;
    }

    pub fn hasPosition(self: *const PositionManager) bool {
        return self.current_position != null;
    }

    pub fn getPosition(self: *PositionManager) ?*Position {
        if (self.current_position) |*pos| {
            return pos;
        }
        return null;
    }

    pub fn openPosition(self: *PositionManager, position: Position) !void {
        if (self.current_position != null) {
            return error.PositionAlreadyOpen;
        }
        self.current_position = position;
    }

    pub fn closePosition(self: *PositionManager) void {
        self.current_position = null;
    }
};
```

---

## Error Handling Strategy

### Error Categories

```zig
/// Backtest engine error types
pub const BacktestError = error{
    // Data errors
    EmptyDataset,
    DataNotSorted,
    InvalidCandleData,
    MissingDataFile,

    // State errors
    InvalidStateTransition,
    AlreadyRunning,
    NotInitialized,

    // Trading errors
    InsufficientBalance,
    PositionAlreadyOpen,
    NoPositionToClose,
    InvalidOrderSize,

    // Configuration errors
    InvalidTimeRange,
    InvalidCommissionRate,
    InvalidSlippage,
    InvalidInitialCapital,

    // Strategy errors
    StrategyInitFailed,
    IndicatorCalculationFailed,
    SignalGenerationFailed,
};
```

### Error Handling Patterns

```zig
pub fn run(
    self: *BacktestEngine,
    strategy: IStrategy,
    config: BacktestConfig,
) BacktestError!BacktestResult {
    // Validate configuration first
    try self.validateConfig(config);

    // State machine ensures clean error handling
    errdefer self.state = .error_state;

    // Each stage handles its own errors
    const candles = self.loadData(config) catch |err| {
        self.logger.err("Failed to load data: {}", .{err});
        return err;
    };

    strategy.populateIndicators(&candles) catch |err| {
        self.logger.err("Failed to calculate indicators: {}", .{err});
        return BacktestError.IndicatorCalculationFailed;
    };

    // Event loop with detailed error context
    self.eventLoop(strategy, &candles, config) catch |err| {
        self.logger.err("Event loop failed at candle {}/{}: {}", .{
            self.processed_candles,
            self.total_candles,
            err,
        });
        return err;
    };

    return try self.finalize(strategy, config);
}

fn validateConfig(self: *BacktestEngine, config: BacktestConfig) !void {
    if (config.initial_capital.cmp(Decimal.ZERO) != .gt) {
        return BacktestError.InvalidInitialCapital;
    }

    if (config.start_time.unix >= config.end_time.unix) {
        return BacktestError.InvalidTimeRange;
    }

    if (config.commission_rate.isNegative()) {
        return BacktestError.InvalidCommissionRate;
    }

    if (config.slippage.isNegative()) {
        return BacktestError.InvalidSlippage;
    }
}
```

---

## Integration with StrategyContext

### Context Creation for Backtest

```zig
/// Create strategy context for backtesting
fn createBacktestContext(
    allocator: std.mem.Allocator,
    config: BacktestConfig,
) !StrategyContext {
    // No real exchange in backtest mode
    const exchange: ?IExchange = null;

    // Create logger for strategy
    const logger = Logger.init("Strategy");

    // Create strategy config
    const strategy_config = StrategyConfig{
        .pair = config.pair,
        .timeframe = config.timeframe,
        .max_open_trades = config.max_positions,
        .stake_amount = config.initial_capital,
    };

    // Initialize context (from STORY-014)
    return try StrategyContext.init(
        allocator,
        logger,
        strategy_config,
        exchange,
    );
}

/// Main backtest run with context integration
pub fn run(
    self: *BacktestEngine,
    strategy: IStrategy,
    config: BacktestConfig,
) !BacktestResult {
    // Create context for strategy
    var ctx = try createBacktestContext(self.allocator, config);
    defer ctx.deinit();

    // Initialize strategy with context
    try strategy.init(ctx);
    defer strategy.deinit();

    // ... rest of backtest logic
}
```

### Position Size Calculation Integration

```zig
/// Handle entry signal with strategy context
fn handleEntry(
    self: *BacktestEngine,
    strategy: IStrategy,
    signal: Signal,
    candle: Candle,
    config: BacktestConfig,
) !void {
    // Create account snapshot for strategy
    const account_snapshot = Account{
        .initial_capital = self.account.initial_capital,
        .balance = self.account.balance,
        .equity = self.account.equity,
        .total_commission = self.account.total_commission,
        .realized_pnl = self.account.realized_pnl,
        .unrealized_pnl = self.account.unrealized_pnl,
    };

    // Let strategy calculate position size
    const position_size = try strategy.calculatePositionSize(
        signal,
        account_snapshot,
    );

    // Validate size
    if (position_size.cmp(Decimal.ZERO) != .gt) {
        self.logger.warn("Invalid position size from strategy: {}", .{position_size});
        return;
    }

    // Execute order
    const fill = try self.executor.executeMarketOrder(
        signal.side,
        position_size,
        candle,
        config.commission_rate,
        config.slippage,
    );

    // Update account
    try self.account.processBuy(fill.fill_price, fill.fill_size, fill.commission);

    // Open position
    const position = PositionManager.Position.init(
        signal.pair,
        signal.side,
        fill.fill_size,
        fill.fill_price,
        candle.timestamp,
    );
    try self.position_manager.openPosition(position);

    self.logger.info("Opened position: {} {} @ {}", .{
        @tagName(signal.side), position_size, fill.fill_price
    });
}
```

---

## Concrete Configuration Examples

### Example 1: Basic DualMA Backtest

```zig
const config = BacktestConfig{
    .pair = TradingPair.fromString("BTC/USDT"),
    .timeframe = .m15,  // 15-minute candles
    .start_time = Timestamp.fromUnixMillis(1704067200000), // 2024-01-01
    .end_time = Timestamp.fromUnixMillis(1706745600000),   // 2024-02-01
    .initial_capital = Decimal.fromFloat(10000.0),
    .commission_rate = Decimal.fromFloat(0.001),  // 0.1% (Binance spot)
    .slippage = Decimal.fromFloat(0.0005),        // 0.05%
    .enable_short = false,  // Long only
    .max_positions = 1,
};

// Run backtest
var engine = try BacktestEngine.init(allocator, .{
    .source = .csv,
    .data_dir = "./data/historical",
    .validate = true,
    .enable_cache = true,
});
defer engine.deinit();

const result = try engine.run(dual_ma_strategy, config);
defer result.deinit(allocator);

std.debug.print("Total Trades: {}\n", .{result.total_trades});
std.debug.print("Win Rate: {d:.2}%\n", .{result.win_rate * 100});
std.debug.print("Net Profit: ${}\n", .{result.net_profit});
```

### Example 2: RSI Strategy with Shorts

```zig
const config = BacktestConfig{
    .pair = TradingPair.fromString("ETH/USDT"),
    .timeframe = .h1,   // 1-hour candles
    .start_time = Timestamp.fromUnixMillis(1672531200000), // 2023-01-01
    .end_time = Timestamp.fromUnixMillis(1704067200000),   // 2024-01-01
    .initial_capital = Decimal.fromFloat(50000.0),
    .commission_rate = Decimal.fromFloat(0.0005), // 0.05% (maker)
    .slippage = Decimal.fromFloat(0.0002),        // 0.02%
    .enable_short = true,   // Allow shorts
    .max_positions = 1,
};
```

### Example 3: High-Frequency Scalping

```zig
const config = BacktestConfig{
    .pair = TradingPair.fromString("SOL/USDT"),
    .timeframe = .m1,   // 1-minute candles
    .start_time = Timestamp.fromUnixMillis(1704067200000),
    .end_time = Timestamp.fromUnixMillis(1704153600000),   // 1 day
    .initial_capital = Decimal.fromFloat(5000.0),
    .commission_rate = Decimal.fromFloat(0.002),  // 0.2% (taker)
    .slippage = Decimal.fromFloat(0.001),         // 0.1% (higher for HFT)
    .enable_short = true,
    .max_positions = 1,
};
```

### BacktestConfig Structure

```zig
pub const BacktestConfig = struct {
    /// Trading pair
    pair: TradingPair,

    /// Candle timeframe
    timeframe: Timeframe,

    /// Start timestamp (inclusive)
    start_time: Timestamp,

    /// End timestamp (inclusive)
    end_time: Timestamp,

    /// Initial capital in quote currency
    initial_capital: Decimal,

    /// Commission rate (0.001 = 0.1%)
    commission_rate: Decimal,

    /// Slippage rate (0.0005 = 0.05%)
    slippage: Decimal,

    /// Allow short positions
    enable_short: bool = true,

    /// Maximum simultaneous positions
    max_positions: u32 = 1,

    /// Validate configuration
    pub fn validate(self: BacktestConfig) !void {
        if (self.initial_capital.cmp(Decimal.ZERO) != .gt) {
            return error.InvalidInitialCapital;
        }

        if (self.start_time.unix >= self.end_time.unix) {
            return error.InvalidTimeRange;
        }

        if (self.commission_rate.isNegative() or
            self.commission_rate.cmp(Decimal.fromFloat(1.0)) == .gt) {
            return error.InvalidCommissionRate;
        }

        if (self.slippage.isNegative() or
            self.slippage.cmp(Decimal.fromFloat(1.0)) == .gt) {
            return error.InvalidSlippage;
        }

        if (self.max_positions == 0) {
            return error.InvalidMaxPositions;
        }
    }
};
```

---

## Sequence Diagrams

### 1. Entry Signal Flow

```
Strategy     BacktestEngine    PositionMgr    OrderExecutor    Account
   │                │               │                │             │
   │  checkEntry    │               │                │             │
   ├───────────────>│               │                │             │
   │                │ hasPosition?  │                │             │
   │                ├──────────────>│                │             │
   │                │     false     │                │             │
   │                │<──────────────┤                │             │
   │                │               │                │             │
   │ generateEntry  │               │                │             │
   │<───────────────┤               │                │             │
   │   Signal       │               │                │             │
   ├───────────────>│               │                │             │
   │                │ calcPosSize   │                │             │
   │<───────────────┤               │                │             │
   │   size         │               │                │             │
   ├───────────────>│               │                │             │
   │                │               │  executeMarket │             │
   │                │               ├───────────────>│             │
   │                │               │   FillEvent    │             │
   │                │               │<───────────────┤             │
   │                │               │                │ processBuy  │
   │                │               │                ├────────────>│
   │                │               │                │   updated   │
   │                │               │                │<────────────┤
   │                │  openPosition │                │             │
   │                ├──────────────>│                │             │
   │                │     done      │                │             │
   │                │<──────────────┤                │             │
   │                │               │                │             │
```

### 2. Exit Signal Flow

```
Strategy     BacktestEngine    PositionMgr    OrderExecutor    Account
   │                │               │                │             │
   │  checkExit     │               │                │             │
   ├───────────────>│               │                │             │
   │                │ getPosition   │                │             │
   │                ├──────────────>│                │             │
   │                │   Position    │                │             │
   │                │<──────────────┤                │             │
   │                │               │                │             │
   │ generateExit   │               │                │             │
   │<───────────────┤               │                │             │
   │   Signal       │               │                │             │
   ├───────────────>│               │                │             │
   │                │               │  executeMarket │             │
   │                │               ├───────────────>│             │
   │                │               │   FillEvent    │             │
   │                │               │<───────────────┤             │
   │                │ calculatePnL  │                │             │
   │                ├──────────────>│                │             │
   │                │     PnL       │                │             │
   │                │<──────────────┤                │             │
   │                │               │                │ processSell │
   │                │               │                ├────────────>│
   │                │               │                │   updated   │
   │                │               │                │<────────────┤
   │                │ closePosition │                │             │
   │                ├──────────────>│                │             │
   │                │ recordTrade   │                │             │
   │                ├───────────────────────────────────────────>  │
   │                │               │                │             │
```

### 3. Complete Event Loop Sequence

```
Engine          DataFeed        Strategy        PositionMgr      Account
  │                 │               │                │              │
  │  loadData       │               │                │              │
  ├────────────────>│               │                │              │
  │   Candles       │               │                │              │
  │<────────────────┤               │                │              │
  │                 │               │                │              │
  │  populateIndicators             │                │              │
  ├─────────────────────────────────>│                │              │
  │   done          │               │                │              │
  │<─────────────────────────────────┤                │              │
  │                 │               │                │              │
  │ ┌──────────────────────────────────────────────────────────┐   │
  │ │ FOR EACH CANDLE                                          │   │
  │ └──────────────────────────────────────────────────────────┘   │
  │                 │               │                │              │
  │  updatePositionPnL               │  updatePnL    │              │
  ├─────────────────────────────────────────────────>│              │
  │                 │               │    done        │              │
  │<─────────────────────────────────────────────────┤              │
  │                 │               │                │  updateEquity│
  │  ───────────────────────────────────────────────────────────────>
  │                 │               │                │              │
  │  snapshotEquity │               │                │              │
  ├───────────────────────────────────────────────────────────────> │
  │                 │               │                │              │
  │  checkExit/Entry│               │                │              │
  ├─────────────────────────────────>│                │              │
  │   Signal/null   │               │                │              │
  │<─────────────────────────────────┤                │              │
  │                 │               │                │              │
  │  (if signal)    │               │                │              │
  │  handleSignal   │               │                │              │
  ├─────────────────────────────────────────────────>│              │
  │                 │               │                │              │
  │ ┌──────────────────────────────────────────────────────────┐   │
  │ │ NEXT CANDLE                                              │   │
  │ └──────────────────────────────────────────────────────────┘   │
```

---

## Testing Specifications

### Unit Test Coverage

#### 1. Account Tests

```zig
test "Account: init with capital" {
    const capital = Decimal.fromFloat(10000.0);
    const account = Account.init(capital);

    try testing.expect(account.balance.equals(capital));
    try testing.expect(account.equity.equals(capital));
    try testing.expect(account.total_commission.equals(Decimal.ZERO));
}

test "Account: process buy reduces balance" {
    var account = Account.init(Decimal.fromFloat(10000.0));

    const fill_price = Decimal.fromFloat(50000.0);
    const size = Decimal.fromFloat(0.1);
    const commission = Decimal.fromFloat(5.0);

    try account.processBuy(fill_price, size, commission);

    // Balance = 10000 - (50000 * 0.1) - 5 = 10000 - 5000 - 5 = 4995
    const expected = Decimal.fromFloat(4995.0);
    try testing.expect(account.balance.equals(expected));
}

test "Account: insufficient balance error" {
    var account = Account.init(Decimal.fromFloat(100.0));

    const fill_price = Decimal.fromFloat(50000.0);
    const size = Decimal.fromFloat(1.0);
    const commission = Decimal.fromFloat(50.0);

    try testing.expectError(
        error.InsufficientBalance,
        account.processBuy(fill_price, size, commission)
    );
}

test "Account: process sell increases balance" {
    var account = Account.init(Decimal.fromFloat(10000.0));

    // Simulate buy first
    try account.processBuy(
        Decimal.fromFloat(50000.0),
        Decimal.fromFloat(0.1),
        Decimal.fromFloat(5.0),
    );

    // Sell with profit
    const pnl = Decimal.fromFloat(500.0);
    try account.processSell(
        Decimal.fromFloat(51000.0),
        Decimal.fromFloat(0.1),
        Decimal.fromFloat(5.1),
        pnl,
    );

    // Balance = 4995 + (51000 * 0.1) - 5.1 = 4995 + 5100 - 5.1 = 10089.9
    try testing.expect(account.balance.cmp(Decimal.fromFloat(10000.0)) == .gt);
}
```

#### 2. Position Manager Tests

```zig
test "PositionManager: open and close position" {
    const allocator = testing.allocator;
    var pm = PositionManager.init(allocator);
    defer pm.deinit();

    try testing.expect(!pm.hasPosition());

    const pos = PositionManager.Position.init(
        TradingPair.fromString("BTC/USDT"),
        .buy,
        Decimal.fromFloat(0.1),
        Decimal.fromFloat(50000.0),
        Timestamp.now(),
    );

    try pm.openPosition(pos);
    try testing.expect(pm.hasPosition());

    pm.closePosition();
    try testing.expect(!pm.hasPosition());
}

test "PositionManager: update unrealized PnL" {
    const allocator = testing.allocator;
    var pm = PositionManager.init(allocator);
    defer pm.deinit();

    var pos = PositionManager.Position.init(
        TradingPair.fromString("BTC/USDT"),
        .buy,
        Decimal.fromFloat(0.1),
        Decimal.fromFloat(50000.0),
        Timestamp.now(),
    );

    pos.updatePnL(Decimal.fromFloat(51000.0));

    // PnL = (51000 - 50000) * 0.1 = 100
    const expected = Decimal.fromFloat(100.0);
    try testing.expect(pos.unrealized_pnl.equals(expected));
}

test "PositionManager: calculate exit PnL for short" {
    const pos = PositionManager.Position.init(
        TradingPair.fromString("BTC/USDT"),
        .sell,  // Short
        Decimal.fromFloat(0.1),
        Decimal.fromFloat(50000.0),
        Timestamp.now(),
    );

    // Price drops to 49000
    const exit_pnl = pos.calculateExitPnL(Decimal.fromFloat(49000.0));

    // Short PnL = (50000 - 49000) * 0.1 = 100
    const expected = Decimal.fromFloat(100.0);
    try testing.expect(exit_pnl.equals(expected));
}
```

#### 3. OrderExecutor Tests

```zig
test "OrderExecutor: market order with slippage" {
    const allocator = testing.allocator;
    var executor = OrderExecutor.init(allocator);

    const candle = Candle{
        .timestamp = Timestamp.now(),
        .open = Decimal.fromFloat(50000.0),
        .high = Decimal.fromFloat(50100.0),
        .low = Decimal.fromFloat(49900.0),
        .close = Decimal.fromFloat(50000.0),
        .volume = Decimal.fromFloat(100.0),
    };

    const fill = try executor.executeMarketOrder(
        .buy,
        Decimal.fromFloat(0.1),
        candle,
        Decimal.fromFloat(0.001),  // 0.1% commission
        Decimal.fromFloat(0.0005), // 0.05% slippage
    );

    // Buy price with slippage = 50000 * 1.0005 = 50025
    const expected_price = Decimal.fromFloat(50025.0);
    try testing.expect(fill.fill_price.equals(expected_price));

    // Commission = 50025 * 0.1 * 0.001 = 5.0025
    try testing.expect(fill.commission.cmp(Decimal.fromFloat(5.0)) == .gt);
}
```

#### 4. Data Loading Tests

```zig
test "DataFeed: load CSV file" {
    const allocator = testing.allocator;

    // Create temp CSV file
    const test_csv =
        \\timestamp,open,high,low,close,volume
        \\1704067200000,50000.0,50100.0,49900.0,50050.0,100.5
        \\1704067800000,50050.0,50200.0,50000.0,50150.0,120.3
    ;

    const temp_file = "/tmp/test_data.csv";
    try std.fs.cwd().writeFile(temp_file, test_csv);
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    const candles = try loadFromCSV(allocator, temp_file);
    defer candles.deinit();

    try testing.expectEqual(@as(usize, 2), candles.data.len);
    try testing.expect(candles.data[0].close.equals(Decimal.fromFloat(50050.0)));
}

test "DataFeed: validate sorted data" {
    const allocator = testing.allocator;

    var candles = Candles.init(allocator);
    defer candles.deinit();

    try candles.append(Candle{
        .timestamp = Timestamp.fromUnixMillis(1000),
        .open = Decimal.fromFloat(100.0),
        .high = Decimal.fromFloat(101.0),
        .low = Decimal.fromFloat(99.0),
        .close = Decimal.fromFloat(100.5),
        .volume = Decimal.fromFloat(10.0),
    });

    try candles.append(Candle{
        .timestamp = Timestamp.fromUnixMillis(2000),
        .open = Decimal.fromFloat(100.5),
        .high = Decimal.fromFloat(102.0),
        .low = Decimal.fromFloat(100.0),
        .close = Decimal.fromFloat(101.0),
        .volume = Decimal.fromFloat(12.0),
    });

    try validateCandles(&candles);
}

test "DataFeed: reject unsorted data" {
    const allocator = testing.allocator;

    var candles = Candles.init(allocator);
    defer candles.deinit();

    try candles.append(Candle{
        .timestamp = Timestamp.fromUnixMillis(2000),
        .open = Decimal.fromFloat(100.0),
        .high = Decimal.fromFloat(101.0),
        .low = Decimal.fromFloat(99.0),
        .close = Decimal.fromFloat(100.5),
        .volume = Decimal.fromFloat(10.0),
    });

    try candles.append(Candle{
        .timestamp = Timestamp.fromUnixMillis(1000), // Earlier!
        .open = Decimal.fromFloat(100.5),
        .high = Decimal.fromFloat(102.0),
        .low = Decimal.fromFloat(100.0),
        .close = Decimal.fromFloat(101.0),
        .volume = Decimal.fromFloat(12.0),
    });

    try testing.expectError(error.DataNotSorted, validateCandles(&candles));
}
```

### Integration Test Scenarios

#### IT-1: End-to-End Backtest Flow

```zig
test "Integration: Complete backtest with DualMA" {
    const allocator = testing.allocator;

    // 1. Create test data
    var candles = try generateTestCandles(allocator, 1000);
    defer candles.deinit();

    // 2. Create mock strategy
    var strategy = try MockDualMAStrategy.create(allocator);
    defer strategy.deinit();

    // 3. Configure backtest
    const config = BacktestConfig{
        .pair = TradingPair.fromString("BTC/USDT"),
        .timeframe = .m15,
        .start_time = candles.data[0].timestamp,
        .end_time = candles.data[candles.data.len - 1].timestamp,
        .initial_capital = Decimal.fromFloat(10000.0),
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.fromFloat(0.0005),
        .enable_short = false,
        .max_positions = 1,
    };

    // 4. Run backtest
    var engine = try BacktestEngine.init(allocator, .{
        .source = .memory,
        .data_dir = "",
        .validate = true,
        .enable_cache = false,
    });
    defer engine.deinit();

    const result = try engine.run(strategy, config);
    defer result.deinit(allocator);

    // 5. Verify results
    try testing.expect(result.total_trades > 0);
    try testing.expect(result.equity_curve.len == candles.data.len);
    try testing.expect(result.winning_trades + result.losing_trades == result.total_trades);
}
```

#### IT-2: State Machine Validation

```zig
test "Integration: State machine transitions" {
    const allocator = testing.allocator;

    var engine = try BacktestEngine.init(allocator, .{
        .source = .memory,
        .data_dir = "",
        .validate = false,
        .enable_cache = false,
    });
    defer engine.deinit();

    try testing.expectEqual(BacktestState.initial, engine.state);

    // Invalid transition should fail
    try testing.expectError(
        error.InvalidStateTransition,
        engine.transitionTo(.complete)
    );

    // Valid transition should succeed
    try engine.transitionTo(.data_loaded);
    try testing.expectEqual(BacktestState.data_loaded, engine.state);
}
```

#### IT-3: Memory Leak Detection

```zig
test "Integration: No memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak detected!");
    }
    const allocator = gpa.allocator();

    var engine = try BacktestEngine.init(allocator, .{
        .source = .memory,
        .data_dir = "",
        .validate = true,
        .enable_cache = true,
    });
    defer engine.deinit();

    var strategy = try MockStrategy.create(allocator);
    defer strategy.deinit();

    const config = BacktestConfig{
        .pair = TradingPair.fromString("BTC/USDT"),
        .timeframe = .m15,
        .start_time = Timestamp.fromUnixMillis(1704067200000),
        .end_time = Timestamp.fromUnixMillis(1704153600000),
        .initial_capital = Decimal.fromFloat(10000.0),
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.fromFloat(0.0005),
        .enable_short = false,
        .max_positions = 1,
    };

    const result = try engine.run(strategy, config);
    defer result.deinit(allocator);
}
```

### Performance Tests

```zig
test "Performance: 10k candles in <10 seconds" {
    const allocator = testing.allocator;

    var candles = try generateTestCandles(allocator, 10000);
    defer candles.deinit();

    var strategy = try MockStrategy.create(allocator);
    defer strategy.deinit();

    const config = BacktestConfig{
        .pair = TradingPair.fromString("BTC/USDT"),
        .timeframe = .m1,
        .start_time = candles.data[0].timestamp,
        .end_time = candles.data[candles.data.len - 1].timestamp,
        .initial_capital = Decimal.fromFloat(10000.0),
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.fromFloat(0.0005),
        .enable_short = false,
        .max_positions = 1,
    };

    var engine = try BacktestEngine.init(allocator, .{
        .source = .memory,
        .data_dir = "",
        .validate = false,
        .enable_cache = true,
    });
    defer engine.deinit();

    const start = std.time.milliTimestamp();
    const result = try engine.run(strategy, config);
    const end = std.time.milliTimestamp();
    defer result.deinit(allocator);

    const duration_ms = end - start;
    const candles_per_sec = @as(f64, 10000.0) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0);

    std.debug.print("Processed {} candles in {}ms ({d:.0} candles/sec)\n", .{
        10000, duration_ms, candles_per_sec
    });

    try testing.expect(duration_ms < 10000); // < 10 seconds
    try testing.expect(candles_per_sec > 1000.0); // > 1000 candles/sec
}
```

---

## Mock Strategies

### 1. AlwaysBuyMock (Minimal Strategy)

```zig
/// Minimal mock strategy that always buys on first candle
pub const AlwaysBuyMock = struct {
    allocator: std.mem.Allocator,
    has_bought: bool,

    pub fn create(allocator: std.mem.Allocator) !IStrategy {
        const self = try allocator.create(AlwaysBuyMock);
        self.* = .{
            .allocator = allocator,
            .has_bought = false,
        };

        return IStrategy{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn initImpl(ptr: *anyopaque, ctx: StrategyContext) !void {
        _ = ptr;
        _ = ctx;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *AlwaysBuyMock = @ptrCast(@alignCast(ptr));
        self.allocator.destroy(self);
    }

    fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
        _ = ptr;
        _ = candles;
        // No indicators needed
    }

    fn generateEntrySignalImpl(
        ptr: *anyopaque,
        candles: *Candles,
        index: usize,
    ) !?Signal {
        const self: *AlwaysBuyMock = @ptrCast(@alignCast(ptr));

        if (!self.has_bought and index >= 10) {
            self.has_bought = true;

            return Signal{
                .type = .entry_long,
                .pair = TradingPair.fromString("BTC/USDT"),
                .side = .buy,
                .price = candles.data[index].close,
                .strength = 1.0,
                .timestamp = candles.data[index].timestamp,
                .metadata = null,
            };
        }

        return null;
    }

    fn generateExitSignalImpl(
        ptr: *anyopaque,
        candles: *Candles,
        position: Position,
    ) !?Signal {
        _ = ptr;
        _ = position;

        // Sell after 10 candles
        const entry_idx = for (candles.data, 0..) |c, i| {
            if (c.timestamp.unix == position.entry_time.unix) break i;
        } else return null;

        const current_idx = candles.data.len - 1;

        if (current_idx >= entry_idx + 10) {
            return Signal{
                .type = .exit_long,
                .pair = position.pair,
                .side = .sell,
                .price = candles.data[current_idx].close,
                .strength = 1.0,
                .timestamp = candles.data[current_idx].timestamp,
                .metadata = null,
            };
        }

        return null;
    }

    fn calculatePositionSizeImpl(
        ptr: *anyopaque,
        signal: Signal,
        account: Account,
    ) !Decimal {
        _ = ptr;
        _ = signal;

        // Use 95% of balance
        const usable = account.balance.mul(Decimal.fromFloat(0.95));
        return usable.div(signal.price);
    }

    fn getParametersImpl(ptr: *anyopaque) []const StrategyParameter {
        _ = ptr;
        return &[_]StrategyParameter{};
    }

    fn getMetadataImpl(ptr: *anyopaque) StrategyMetadata {
        _ = ptr;
        return StrategyMetadata{
            .name = "AlwaysBuyMock",
            .version = "1.0.0",
            .author = "Test",
            .description = "Mock strategy for testing",
            .strategy_type = .custom,
            .timeframe = .m15,
            .startup_candle_count = 10,
            .minimal_roi = MinimalROI.init(&[_]ROITarget{}),
            .stoploss = Decimal.fromFloat(-0.1),
            .trailing_stop = null,
        };
    }

    const vtable = IStrategy.VTable{
        .init = initImpl,
        .deinit = deinitImpl,
        .populateIndicators = populateIndicatorsImpl,
        .generateEntrySignal = generateEntrySignalImpl,
        .generateExitSignal = generateExitSignalImpl,
        .calculatePositionSize = calculatePositionSizeImpl,
        .getParameters = getParametersImpl,
        .getMetadata = getMetadataImpl,
    };
};
```

### 2. RandomSignalMock (Testing Edge Cases)

```zig
/// Mock strategy that generates random signals for stress testing
pub const RandomSignalMock = struct {
    allocator: std.mem.Allocator,
    rng: std.rand.DefaultPrng,
    signal_probability: f64,

    pub fn create(allocator: std.mem.Allocator, signal_probability: f64) !IStrategy {
        const self = try allocator.create(RandomSignalMock);
        self.* = .{
            .allocator = allocator,
            .rng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp())),
            .signal_probability = signal_probability,
        };

        return IStrategy{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn generateEntrySignalImpl(
        ptr: *anyopaque,
        candles: *Candles,
        index: usize,
    ) !?Signal {
        const self: *RandomSignalMock = @ptrCast(@alignCast(ptr));

        if (index < 20) return null;

        const roll = self.rng.random().float(f64);
        if (roll < self.signal_probability) {
            return Signal{
                .type = .entry_long,
                .pair = TradingPair.fromString("BTC/USDT"),
                .side = .buy,
                .price = candles.data[index].close,
                .strength = roll,
                .timestamp = candles.data[index].timestamp,
                .metadata = null,
            };
        }

        return null;
    }

    // ... other vtable implementations
};
```

### 3. Test Data Generator

```zig
/// Generate realistic test candle data
pub fn generateTestCandles(
    allocator: std.mem.Allocator,
    count: usize,
) !Candles {
    var candles = Candles.init(allocator);
    errdefer candles.deinit();

    var rng = std.rand.DefaultPrng.init(42); // Fixed seed for reproducibility
    const random = rng.random();

    var current_price = Decimal.fromFloat(50000.0);
    var timestamp: i64 = 1704067200000; // 2024-01-01
    const interval: i64 = 900000; // 15 minutes in ms

    for (0..count) |_| {
        // Random walk with trend
        const change_pct = (random.float(f64) - 0.5) * 0.02; // ±1% max
        const change = current_price.mul(Decimal.fromFloat(change_pct));
        current_price = current_price.add(change);

        // Generate OHLC
        const volatility = current_price.mul(Decimal.fromFloat(0.005)); // 0.5%
        const high = current_price.add(volatility.mul(Decimal.fromFloat(random.float(f64))));
        const low = current_price.sub(volatility.mul(Decimal.fromFloat(random.float(f64))));
        const open = low.add(high.sub(low).mul(Decimal.fromFloat(random.float(f64))));

        const candle = Candle{
            .timestamp = Timestamp.fromUnixMillis(timestamp),
            .open = open,
            .high = high,
            .low = low,
            .close = current_price,
            .volume = Decimal.fromFloat(100.0 + random.float(f64) * 50.0),
        };

        try candles.append(candle);
        timestamp += interval;
    }

    return candles;
}
```

---

## Implementation Checklist

### Phase 1: Core Types (Day 1, Morning)

- [ ] Define `BacktestConfig` structure with validation
- [ ] Define `BacktestResult` structure
- [ ] Define `Trade` record structure
- [ ] Define `EquitySnapshot` structure
- [ ] Define `FillEvent` structure
- [ ] Define `BacktestState` enum
- [ ] Define `BacktestError` error set
- [ ] Write unit tests for type validation

### Phase 2: Data Loading (Day 1, Afternoon)

- [ ] Implement `DataFeedConfig` structure
- [ ] Implement `HistoricalDataFeed` with CSV loading
- [ ] Implement `loadFromCSV` function
- [ ] Implement `parseCSVLine` function
- [ ] Implement `validateCandles` function
- [ ] Implement data caching mechanism
- [ ] Write unit tests for data loading
- [ ] Write tests for data validation

### Phase 3: Account & Position (Day 1, Evening)

- [ ] Implement `Account` structure
- [ ] Implement `Account.updateEquity`
- [ ] Implement `Account.processBuy`
- [ ] Implement `Account.processSell`
- [ ] Implement `PositionManager.Position`
- [ ] Implement `Position.updatePnL`
- [ ] Implement `Position.calculateExitPnL`
- [ ] Implement `PositionManager` operations
- [ ] Write comprehensive unit tests

### Phase 4: Order Execution (Day 2, Morning)

- [ ] Implement `OrderExecutor` structure
- [ ] Implement `executeMarketOrder` with slippage
- [ ] Implement order ID generation
- [ ] Write unit tests for execution logic
- [ ] Test slippage calculations
- [ ] Test commission calculations

### Phase 5: Event Loop (Day 2, Afternoon)

- [ ] Implement `BacktestEngine.init`
- [ ] Implement `BacktestEngine.deinit`
- [ ] Implement state machine with `transitionTo`
- [ ] Implement `loadData` method
- [ ] Implement `eventLoop` method
- [ ] Implement `handleEntry` method
- [ ] Implement `handleExit` method
- [ ] Implement `finalize` method
- [ ] Write integration tests

### Phase 6: Testing & Validation (Day 2, Evening)

- [ ] Create `AlwaysBuyMock` test strategy
- [ ] Create `RandomSignalMock` test strategy
- [ ] Implement `generateTestCandles` helper
- [ ] Write end-to-end integration test
- [ ] Write state machine validation test
- [ ] Write memory leak detection test
- [ ] Write performance test (10k candles)
- [ ] Run all tests with coverage analysis

### Phase 7: Documentation

- [ ] Add doc comments to all public functions
- [ ] Create usage examples
- [ ] Update architecture documentation
- [ ] Create troubleshooting guide

---

## Acceptance Criteria

### AC-1: Backtest Engine Functionality ✓
- [ ] Successfully loads historical data from CSV
- [ ] Initializes strategy and calculates indicators
- [ ] Drives complete event loop through all candles
- [ ] Correctly executes entry and exit orders
- [ ] Generates complete BacktestResult

### AC-2: Order Execution Accuracy ✓
- [ ] Market orders execute immediately at current candle close
- [ ] Fill price includes configured slippage
- [ ] Commission calculated accurately
- [ ] Account balance updated correctly after each trade
- [ ] Position state tracks entry/exit accurately

### AC-3: No Look-Ahead Bias ✓
- [ ] Strategy only accesses current and historical data
- [ ] Indicators calculated using only past data
- [ ] Signals generated without future information
- [ ] Verified through manual inspection and tests

### AC-4: Performance Requirements ✓
- [ ] Backtest speed > 1000 candles/second
- [ ] 10,000 candle backtest completes in < 10 seconds
- [ ] Memory usage < 50MB for 10k candles
- [ ] Zero memory leaks (verified with GPA)

### AC-5: Test Coverage ✓
- [ ] Unit test coverage > 85%
- [ ] Integration tests pass
- [ ] End-to-end tests with real strategies pass
- [ ] Performance tests pass

### AC-6: Result Accuracy ✓
- [ ] Trade records complete and accurate
- [ ] P&L calculations verified manually
- [ ] Win rate calculated correctly
- [ ] Equity curve continuous and correct

---

## Files to Create

```
src/backtest/
├── engine.zig              (Core BacktestEngine, ~500 lines)
├── types.zig               (Type definitions, ~200 lines)
├── data_feed.zig           (HistoricalDataFeed, ~300 lines)
├── account.zig             (Account manager, ~150 lines)
├── position.zig            (Position manager, ~200 lines)
├── executor.zig            (OrderExecutor, ~150 lines)
├── engine_test.zig         (Unit tests, ~400 lines)
└── test_helpers.zig        (Mock strategies & data, ~300 lines)

tests/integration/
└── backtest_e2e_test.zig   (Integration tests, ~300 lines)

docs/features/backtest/
├── architecture.md          (This document)
├── api.md                   (API documentation)
└── examples.md              (Usage examples)
```

---

**Total Estimated Lines**: ~2,500 lines of implementation + tests

**Implementation Time**: 2 days
- Day 1: Core types, data loading, account/position management
- Day 2: Event loop, order execution, testing & validation

**Status**: Ready for Implementation ✓

---

*Created: 2025-12-25*
*Last Updated: 2025-12-25*
*Document Version: 2.0 (Implementation-Ready)*
