# Backtest Engine Implementation Details

**Version**: v0.4.0
**Status**: Planned
**Last Updated**: 2025-12-25

---

## 📋 Table of Contents

1. [File Organization](#file-organization)
2. [Event-Driven Architecture](#event-driven-architecture)
3. [Backtest Lifecycle](#backtest-lifecycle)
4. [Order Execution Simulation](#order-execution-simulation)
5. [Account & Position Management](#account--position-management)
6. [Performance Analysis](#performance-analysis)
7. [Memory Management](#memory-management)
8. [Performance Optimization](#performance-optimization)

---

## 📂 File Organization

### Directory Structure

```
src/backtest/
├── engine.zig              # BacktestEngine core
├── data_feed.zig          # HistoricalDataFeed
├── event.zig              # Event system
├── executor.zig           # OrderExecutor
├── account.zig            # Account management
├── position.zig           # Position management
├── analyzer.zig           # PerformanceAnalyzer
├── metrics.zig            # Performance metrics calculation
├── report.zig             # Report generation
├── types.zig              # Type definitions
│
└── tests/
    ├── engine_test.zig
    ├── executor_test.zig
    ├── analyzer_test.zig
    └── integration_test.zig
```

### Module Exports

**src/root.zig**:
```zig
// Backtest engine
pub const backtest = @import("backtest/engine.zig");
pub const BacktestEngine = backtest.BacktestEngine;
pub const BacktestConfig = @import("backtest/types.zig").BacktestConfig;
pub const BacktestResult = @import("backtest/types.zig").BacktestResult;

// Performance analysis
pub const PerformanceAnalyzer = @import("backtest/analyzer.zig").PerformanceAnalyzer;
pub const PerformanceMetrics = @import("backtest/metrics.zig").PerformanceMetrics;

// Data feed
pub const HistoricalDataFeed = @import("backtest/data_feed.zig").HistoricalDataFeed;
```

---

## 🏗️ Event-Driven Architecture

### Architecture Overview

The backtest engine uses an event-driven architecture to simulate realistic market conditions:

```
┌─────────────────────────────────────────────┐
│         Backtest Event Loop                 │
├─────────────────────────────────────────────┤
│                                              │
│  ┌──────────────┐                           │
│  │  Event Queue │                           │
│  └──────┬───────┘                           │
│         │                                    │
│         ▼                                    │
│  ┌──────────────────┐                       │
│  │  Market Event    │ ──────┐               │
│  │  (New Candle)    │       │               │
│  └──────────────────┘       │               │
│                              ▼               │
│  ┌──────────────────┐  ┌─────────────┐     │
│  │  Signal Event    │  │  Strategy   │     │
│  │  (Buy/Sell)      │◄─┤  Execution  │     │
│  └──────────────────┘  └─────────────┘     │
│         │                                    │
│         ▼                                    │
│  ┌──────────────────┐                       │
│  │  Order Event     │                       │
│  │  (Create Order)  │                       │
│  └──────────────────┘                       │
│         │                                    │
│         ▼                                    │
│  ┌──────────────────┐  ┌─────────────┐     │
│  │  Fill Event      │◄─┤    Order    │     │
│  │  (Order Filled)  │  │  Executor   │     │
│  └──────────────────┘  └─────────────┘     │
│         │                                    │
│         ▼                                    │
│  ┌──────────────────┐  ┌─────────────┐     │
│  │  Update Account  │──│   Account   │     │
│  │  & Position      │  │   Manager   │     │
│  └──────────────────┘  └─────────────┘     │
│                                              │
└─────────────────────────────────────────────┘
```

### Event Types

```zig
// src/backtest/event.zig

pub const EventType = enum {
    market,   // New candle data available
    signal,   // Strategy generated trading signal
    order,    // Order created
    fill,     // Order filled
};

pub const Event = union(EventType) {
    market: MarketEvent,
    signal: SignalEvent,
    order: OrderEvent,
    fill: FillEvent,

    pub fn getTimestamp(self: Event) Timestamp {
        return switch (self) {
            .market => |e| e.timestamp,
            .signal => |e| e.timestamp,
            .order => |e| e.timestamp,
            .fill => |e| e.timestamp,
        };
    }
};
```

### Event Queue Implementation

```zig
pub const EventQueue = struct {
    allocator: std.mem.Allocator,
    queue: std.ArrayList(Event),

    pub fn init(allocator: std.mem.Allocator) EventQueue {
        return .{
            .allocator = allocator,
            .queue = std.ArrayList(Event).init(allocator),
        };
    }

    pub fn deinit(self: *EventQueue) void {
        self.queue.deinit();
    }

    pub fn push(self: *EventQueue, event: Event) !void {
        try self.queue.append(event);
    }

    pub fn pop(self: *EventQueue) ?Event {
        if (self.queue.items.len == 0) return null;
        return self.queue.orderedRemove(0);  // FIFO
    }

    pub fn isEmpty(self: *EventQueue) bool {
        return self.queue.items.len == 0;
    }

    pub fn clear(self: *EventQueue) void {
        self.queue.clearRetainingCapacity();
    }
};
```

---

## 🔄 Backtest Lifecycle

### Complete Backtest Flow

```
1. Initialization Phase
   │
   ├─> BacktestEngine.init(allocator)
   │   │
   │   ├─> Create HistoricalDataFeed
   │   ├─> Initialize Logger
   │   └─> Allocate resources
   │
2. Load Historical Data
   │
   ├─> data_feed.load(pair, timeframe, start_time, end_time)
   │   │
   │   ├─> Query data source (DB/CSV/API)
   │   ├─> Validate data integrity
   │   │   - Check timestamp order
   │   │   - Check OHLCV validity
   │   └─> Return Candles
   │
3. Calculate Indicators
   │
   ├─> strategy.populateIndicators(candles)
   │   │
   │   ├─> Calculate SMA/EMA
   │   ├─> Calculate RSI/MACD/BB
   │   └─> Store in candles.indicators
   │
4. Initialize Backtest State
   │
   ├─> account = Account.init(initial_capital)
   ├─> position_mgr = PositionManager.init(allocator)
   ├─> executor = OrderExecutor.init(allocator, config)
   ├─> trades = ArrayList(Trade).init(allocator)
   └─> equity_curve = ArrayList(EquitySnapshot).init(allocator)
   │
5. Event Loop (Main Simulation)
   │
   └─> for (candles.data, 0..) |candle, i| {
       │
       ├─> 5.1 Update Position Unrealized P&L
       │   │
       │   └─> if (position_mgr.getPosition()) |*pos| {
       │           pos.updateUnrealizedPnL(candle.close)
       │           account.updateEquity(pos.unrealized_pnl)
       │       }
       │
       ├─> 5.2 Record Equity Snapshot
       │   │
       │   └─> equity_curve.append(EquitySnapshot{
       │           .timestamp = candle.timestamp,
       │           .equity = account.equity,
       │           .balance = account.balance,
       │           .unrealized_pnl = current_unrealized,
       │       })
       │
       ├─> 5.3 Check Exit Signals (if in position)
       │   │
       │   └─> if (position_mgr.hasPosition()) {
       │           exit_signal = strategy.generateExitSignal(candles, position)
       │           if (exit_signal) |sig| {
       │               handleExit(sig, candle)
       │               continue
       │           }
       │       }
       │
       ├─> 5.4 Check Entry Signals (if no position)
       │   │
       │   └─> if (!position_mgr.hasPosition()) {
       │           entry_signal = strategy.generateEntrySignal(candles, i)
       │           if (entry_signal) |sig| {
       │               handleEntry(sig, candle, strategy)
       │           }
       │       }
       │
       └─> 5.5 Progress Logging
           │
           └─> if (i % 1000 == 0) {
                   logger.debug("Progress: {}/{}", i, candles.len)
               }
   }
   │
6. Force Close Remaining Positions
   │
   └─> if (position_mgr.getPosition()) |pos| {
           exit_signal = createForceExitSignal(pos, last_candle)
           handleExit(exit_signal, last_candle)
       }
   │
7. Generate Results
   │
   ├─> Calculate basic statistics
   │   - Total trades
   │   - Win rate
   │   - Profit factor
   │
   ├─> Return BacktestResult
   │   - trades: []Trade
   │   - equity_curve: []EquitySnapshot
   │   - metrics: Basic metrics
   │
8. Cleanup
   │
   └─> engine.deinit()
       - Free data feed
       - Free allocations
```

### Entry Signal Handling

```zig
fn handleEntry(
    self: *BacktestEngine,
    executor: *OrderExecutor,
    position_mgr: *PositionManager,
    account: *Account,
    signal: Signal,
    candle: Candle,
    strategy: IStrategy,
) !void {
    // 1. Calculate position size
    const position_size = try strategy.calculatePositionSize(signal, account.*);

    // 2. Create market order
    const order = OrderEvent{
        .id = executor.generateOrderId(),
        .timestamp = signal.timestamp,
        .pair = signal.pair,
        .side = signal.side,
        .type = .market,
        .price = signal.price,
        .size = position_size,
    };

    // 3. Execute order (simulate fill)
    const fill = try executor.executeMarketOrder(order, candle);

    // 4. Update account balance
    const cost = try fill.fill_price.mul(fill.fill_size);
    const total_cost = try cost.add(fill.commission);
    account.balance = try account.balance.sub(total_cost);
    account.total_commission = try account.total_commission.add(fill.commission);

    // 5. Open position
    const position = Position.init(
        signal.pair,
        if (signal.side == .buy) .long else .short,
        fill.fill_size,
        fill.fill_price,
        signal.timestamp,
    );
    try position_mgr.openPosition(position);

    // 6. Log
    self.logger.info("Opened position: {s} {} @ {}", .{
        signal.pair.toString(),
        position.side,
        fill.fill_price,
    });
}
```

### Exit Signal Handling

```zig
fn handleExit(
    self: *BacktestEngine,
    executor: *OrderExecutor,
    position_mgr: *PositionManager,
    account: *Account,
    trades: *std.ArrayList(Trade),
    signal: Signal,
    candle: Candle,
) !void {
    const position = position_mgr.getPosition().?;

    // 1. Create exit order
    const order = OrderEvent{
        .id = executor.generateOrderId(),
        .timestamp = signal.timestamp,
        .pair = signal.pair,
        .side = signal.side,  // Opposite of position
        .type = .market,
        .price = signal.price,
        .size = position.size,
    };

    // 2. Execute order
    const fill = try executor.executeMarketOrder(order, candle);

    // 3. Calculate P&L
    const pnl = try position.calculatePnL(fill.fill_price);
    const net_pnl = try pnl.sub(fill.commission);

    // 4. Update account
    const proceeds = try fill.fill_price.mul(fill.fill_size);
    account.balance = try account.balance.add(proceeds);
    account.balance = try account.balance.add(net_pnl);
    account.total_commission = try account.total_commission.add(fill.commission);

    // 5. Record trade
    const duration = signal.timestamp - position.entry_time;
    const entry_cost = try position.entry_price.mul(position.size);
    try trades.append(Trade{
        .id = order.id,
        .pair = position.pair,
        .side = position.side,
        .entry_time = position.entry_time,
        .exit_time = signal.timestamp,
        .entry_price = position.entry_price,
        .exit_price = fill.fill_price,
        .size = position.size,
        .pnl = net_pnl,
        .pnl_percent = try net_pnl.div(entry_cost),
        .commission = fill.commission,
        .duration_minutes = @intCast(duration / 60000),
    });

    // 6. Close position
    position_mgr.closePosition();

    // 7. Log
    self.logger.info("Closed position: PnL={}", .{net_pnl});
}
```

---

## 💱 Order Execution Simulation

### Market Order Execution

```zig
// src/backtest/executor.zig

pub const OrderExecutor = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    config: BacktestConfig,
    next_order_id: u64,

    pub fn init(allocator: std.mem.Allocator, config: BacktestConfig) OrderExecutor {
        return .{
            .allocator = allocator,
            .logger = Logger.init("OrderExecutor"),
            .config = config,
            .next_order_id = 1,
        };
    }

    pub fn executeMarketOrder(
        self: *OrderExecutor,
        order: OrderEvent,
        current_candle: Candle,
    ) !FillEvent {
        // 1. Base price: use candle close
        const base_price = current_candle.close;

        // 2. Apply slippage
        const slippage_factor = if (order.side == .buy)
            try Decimal.ONE.add(self.config.slippage)
        else
            try Decimal.ONE.sub(self.config.slippage);

        const fill_price = try base_price.mul(slippage_factor);

        // 3. Calculate commission
        const notional = try fill_price.mul(order.size);
        const commission = try notional.mul(self.config.commission_rate);

        // 4. Log execution
        self.logger.info("Order executed: id={}, side={s}, price={}, size={}, fee={}", .{
            order.id,
            @tagName(order.side),
            fill_price,
            order.size,
            commission,
        });

        // 5. Return fill event
        return FillEvent{
            .order_id = order.id,
            .timestamp = order.timestamp,
            .fill_price = fill_price,
            .fill_size = order.size,
            .commission = commission,
        };
    }

    pub fn generateOrderId(self: *OrderExecutor) u64 {
        const id = self.next_order_id;
        self.next_order_id += 1;
        return id;
    }
};
```

### Slippage Model

**Buy Orders**:
```
fill_price = close × (1 + slippage)
```

**Example** (0.05% slippage):
```
close = $2000.00
slippage = 0.0005
fill_price = $2000.00 × 1.0005 = $2001.00
```

**Sell Orders**:
```
fill_price = close × (1 - slippage)
```

**Example** (0.05% slippage):
```
close = $2000.00
slippage = 0.0005
fill_price = $2000.00 × 0.9995 = $1999.00
```

### Commission Calculation

```
commission = fill_price × size × commission_rate
```

**Example** (0.1% fee):
```
fill_price = $2000.00
size = 1.5 ETH
commission_rate = 0.001

commission = $2000.00 × 1.5 × 0.001 = $3.00
```

---

## 📊 Account & Position Management

### Account Implementation

```zig
// src/backtest/account.zig

pub const Account = struct {
    initial_capital: Decimal,
    balance: Decimal,              // Available cash
    equity: Decimal,               // Total account value
    total_commission: Decimal,     // Cumulative fees

    pub fn init(initial_capital: Decimal) Account {
        return .{
            .initial_capital = initial_capital,
            .balance = initial_capital,
            .equity = initial_capital,
            .total_commission = Decimal.ZERO,
        };
    }

    pub fn updateEquity(self: *Account, unrealized_pnl: Decimal) !void {
        self.equity = try self.balance.add(unrealized_pnl);
    }

    pub fn getNetProfit(self: Account) !Decimal {
        return try self.equity.sub(self.initial_capital);
    }

    pub fn getReturnPercent(self: Account) !f64 {
        const net_profit = try self.getNetProfit();
        const return_pct = try net_profit.div(self.initial_capital);
        return try return_pct.toFloat();
    }
};
```

### Position Implementation

```zig
// src/backtest/position.zig

pub const Position = struct {
    pair: TradingPair,
    side: Side,                    // .long or .short
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
    ) Position {
        return .{
            .pair = pair,
            .side = side,
            .size = size,
            .entry_price = entry_price,
            .entry_time = entry_time,
            .unrealized_pnl = Decimal.ZERO,
        };
    }

    pub fn updateUnrealizedPnL(self: *Position, current_price: Decimal) !void {
        const price_diff = if (self.side == .long)
            try current_price.sub(self.entry_price)  // Long: profit when price up
        else
            try self.entry_price.sub(current_price);  // Short: profit when price down

        self.unrealized_pnl = try price_diff.mul(self.size);
    }

    pub fn calculatePnL(self: *Position, exit_price: Decimal) !Decimal {
        const price_diff = if (self.side == .long)
            try exit_price.sub(self.entry_price)
        else
            try self.entry_price.sub(exit_price);

        return try price_diff.mul(self.size);
    }

    pub fn getReturnPercent(self: *Position, exit_price: Decimal) !f64 {
        const pnl = try self.calculatePnL(exit_price);
        const cost = try self.entry_price.mul(self.size);
        const return_pct = try pnl.div(cost);
        return try return_pct.toFloat();
    }
};
```

### Position Manager

```zig
pub const PositionManager = struct {
    allocator: std.mem.Allocator,
    current_position: ?Position,

    pub fn init(allocator: std.mem.Allocator) PositionManager {
        return .{
            .allocator = allocator,
            .current_position = null,
        };
    }

    pub fn hasPosition(self: *PositionManager) bool {
        return self.current_position != null;
    }

    pub fn getPosition(self: *PositionManager) ?Position {
        return self.current_position;
    }

    pub fn openPosition(self: *PositionManager, pos: Position) !void {
        if (self.current_position != null) {
            return error.PositionAlreadyExists;
        }
        self.current_position = pos;
    }

    pub fn closePosition(self: *PositionManager) void {
        self.current_position = null;
    }
};
```

---

## 📈 Performance Analysis

### PerformanceAnalyzer Implementation

```zig
// src/backtest/analyzer.zig

pub const PerformanceAnalyzer = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    pub fn init(allocator: std.mem.Allocator) PerformanceAnalyzer {
        return .{
            .allocator = allocator,
            .logger = Logger.init("PerformanceAnalyzer"),
        };
    }

    pub fn analyze(
        self: *PerformanceAnalyzer,
        result: BacktestResult,
    ) !PerformanceMetrics {
        self.logger.info("Analyzing {} trades", .{result.trades.len});

        // Calculate each category of metrics
        const profit_metrics = try self.calculateProfitMetrics(result.trades);
        const win_metrics = try self.calculateWinMetrics(result.trades);
        const risk_metrics = try self.calculateRiskMetrics(
            result.equity_curve,
            result.config.initial_capital,
        );
        const trade_stats = try self.calculateTradeStats(result.trades);
        const return_metrics = try self.calculateReturnMetrics(
            result.equity_curve,
            result.config.initial_capital,
        );

        // Combine into PerformanceMetrics
        return PerformanceMetrics{
            // ... combine all metrics
        };
    }
};
```

### Maximum Drawdown Calculation

```zig
fn calculateMaxDrawdown(
    self: *PerformanceAnalyzer,
    equity_curve: []BacktestResult.EquitySnapshot,
) !struct {
    max_drawdown: f64,
    duration_days: u32,
} {
    var peak = equity_curve[0].equity;
    var max_dd: f64 = 0.0;
    var peak_time: Timestamp = equity_curve[0].timestamp;
    var max_dd_duration: u64 = 0;

    for (equity_curve) |snapshot| {
        // Update peak if new high
        if (snapshot.equity.gt(peak)) {
            peak = snapshot.equity;
            peak_time = snapshot.timestamp;
        }

        // Calculate current drawdown
        if (snapshot.equity.lt(peak)) {
            const dd_amount = try peak.sub(snapshot.equity);
            const dd_pct = try dd_amount.div(peak).toFloat();

            if (dd_pct > max_dd) {
                max_dd = dd_pct;
            }

            // Track duration
            const duration = snapshot.timestamp - peak_time;
            max_dd_duration = @max(max_dd_duration, duration);
        }
    }

    const duration_days: u32 = @intCast(max_dd_duration / (24 * 60 * 60 * 1000));

    return .{
        .max_drawdown = max_dd,
        .duration_days = duration_days,
    };
}
```

### Sharpe Ratio Calculation

```zig
fn calculateSharpeRatio(
    self: *PerformanceAnalyzer,
    equity_curve: []BacktestResult.EquitySnapshot,
    initial_capital: Decimal,
) !f64 {
    // 1. Calculate daily returns
    var daily_returns = try self.allocator.alloc(f64, equity_curve.len - 1);
    defer self.allocator.free(daily_returns);

    for (1..equity_curve.len) |i| {
        const prev_equity = equity_curve[i - 1].equity;
        const curr_equity = equity_curve[i].equity;
        const ret = try curr_equity.sub(prev_equity).div(prev_equity);
        daily_returns[i - 1] = try ret.toFloat();
    }

    // 2. Calculate mean and std dev
    const mean_return = self.calculateMean(daily_returns);
    const std_dev = self.calculateStdDev(daily_returns, mean_return);

    if (std_dev == 0.0) return 0.0;

    // 3. Annualize (assume 365 trading days)
    const annual_return = mean_return * 365.0;
    const annual_volatility = std_dev * @sqrt(365.0);

    // 4. Calculate Sharpe (risk-free rate = 0)
    const risk_free_rate = 0.0;
    return (annual_return - risk_free_rate) / annual_volatility;
}

fn calculateMean(self: *PerformanceAnalyzer, values: []f64) f64 {
    if (values.len == 0) return 0.0;
    var sum: f64 = 0.0;
    for (values) |v| sum += v;
    return sum / @as(f64, @floatFromInt(values.len));
}

fn calculateStdDev(self: *PerformanceAnalyzer, values: []f64, mean: f64) f64 {
    if (values.len <= 1) return 0.0;
    var sum_sq_diff: f64 = 0.0;
    for (values) |v| {
        const diff = v - mean;
        sum_sq_diff += diff * diff;
    }
    return @sqrt(sum_sq_diff / @as(f64, @floatFromInt(values.len - 1)));
}
```

---

## 🧠 Memory Management

### Memory Allocation Strategy

**Principle**: Caller owns memory for results.

```zig
// Engine creates and owns result
pub fn run(self: *BacktestEngine, strategy: IStrategy, config: BacktestConfig) !BacktestResult {
    var trades = std.ArrayList(Trade).init(self.allocator);
    defer trades.deinit();  // Cleanup if error occurs

    var equity_curve = std.ArrayList(EquitySnapshot).init(self.allocator);
    defer equity_curve.deinit();  // Cleanup if error occurs

    // ... perform backtest ...

    // Transfer ownership to result
    return BacktestResult{
        .trades = try trades.toOwnedSlice(),
        .equity_curve = try equity_curve.toOwnedSlice(),
        // ... other fields ...
    };
}

// Caller must cleanup result
pub fn main() !void {
    const result = try engine.run(strategy, config);
    defer result.deinit();  // Caller owns and cleans up

    // Use result...
}
```

### Resource Cleanup Pattern

```zig
pub const BacktestResult = struct {
    trades: []Trade,
    equity_curve: []EquitySnapshot,
    // ... other fields ...

    pub fn deinit(self: *BacktestResult, allocator: std.mem.Allocator) void {
        allocator.free(self.trades);
        allocator.free(self.equity_curve);
    }
};
```

### Arena Allocator for Temporary Calculations

```zig
pub fn analyze(self: *PerformanceAnalyzer, result: BacktestResult) !PerformanceMetrics {
    // Use arena for temporary allocations
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();  // Frees all at once

    const temp_allocator = arena.allocator();

    // All temporary allocations use arena
    var daily_returns = try temp_allocator.alloc(f64, result.equity_curve.len);
    var monthly_returns = try temp_allocator.alloc(f64, 12);

    // ... calculations ...

    // No need to free individual allocations
    return metrics;
}
```

---

## ⚡ Performance Optimization

### Optimization Targets

**From NFR-020-1**:
- Backtest speed: > 1000 candles/s
- Memory usage: < 50MB for 10,000 candles
- Zero memory leaks

### Optimization Techniques

#### 1. Pre-allocate Arrays

```zig
// BAD: Repeated allocations
pub fn run(self: *BacktestEngine, ...) !BacktestResult {
    var equity_curve = std.ArrayList(EquitySnapshot).init(allocator);

    for (candles.data) |candle| {
        try equity_curve.append(...);  // May reallocate multiple times
    }
}

// GOOD: Pre-allocate known capacity
pub fn run(self: *BacktestEngine, ...) !BacktestResult {
    var equity_curve = try std.ArrayList(EquitySnapshot).initCapacity(
        allocator,
        candles.data.len  // Known size upfront
    );

    for (candles.data) |candle| {
        equity_curve.appendAssumeCapacity(...);  // No allocation
    }
}
```

#### 2. Avoid Unnecessary Calculations

```zig
// Calculate indicators once, not per candle
try strategy.populateIndicators(candles);  // Before loop

for (candles.data, 0..) |candle, i| {
    // Use pre-calculated indicators
    const sma = candles.getIndicator("sma_20").?[i];
}
```

#### 3. Use Comptime When Possible

```zig
// Runtime calculation
const commission_rate = config.commission_rate;
const commission = try fill_price.mul(size).mul(commission_rate);

// Better: if commission_rate is constant, use comptime
const commission_rate = comptime try Decimal.fromFloat(0.001);
```

#### 4. Minimize Decimal Operations

```zig
// BAD: Multiple conversions
const price_f64 = try price.toFloat();
const result = price_f64 * 1.0005;
const final = try Decimal.fromFloat(result);

// GOOD: Keep in Decimal
const slippage = try Decimal.fromFloat(1.0005);
const final = try price.mul(slippage);
```

### Profiling Points

Key areas to profile:
1. Indicator calculation
2. Signal generation
3. Decimal arithmetic
4. Memory allocations
5. Equity curve updates

```zig
// Add timing instrumentation
const start = std.time.nanoTimestamp();
defer {
    const elapsed = std.time.nanoTimestamp() - start;
    logger.debug("Operation took {}ms", .{elapsed / 1_000_000});
}
```

---

## 🧪 Testing Strategy

### Unit Tests

```zig
// src/backtest/engine_test.zig
test "BacktestEngine: basic flow" {
    const allocator = std.testing.allocator;

    var engine = try BacktestEngine.init(allocator);
    defer engine.deinit();

    // Test with minimal strategy
    // ...
}
```

### Integration Tests

```zig
// tests/integration/backtest_e2e_test.zig
test "E2E: DualMA strategy on historical data" {
    // Full backtest with real data
    // Verify all metrics are calculated
    // ...
}
```

---

**Version**: v0.4.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-25
