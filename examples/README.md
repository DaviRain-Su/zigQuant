# zigQuant Examples

This directory contains practical examples demonstrating how to use zigQuant's various features.

## 📋 Examples (14 total)

### 1. Core Basics (`01_core_basics.zig`)

Learn the fundamentals of zigQuant:
- **Logger**: Console, file, and JSON logging with structured fields
- **Decimal**: High-precision arithmetic (18 decimal places)
- **Time**: Timestamps, durations, and kline intervals
- **Errors**: Error context and wrapping

**Run:**
```bash
zig build run-example-core
```

**What you'll see:**
- Structured logging at different levels
- Decimal arithmetic (multiplication, division, comparison)
- Timestamp creation and formatting
- Duration calculations
- Error handling patterns

---

### 2. WebSocket Stream (`02_websocket_stream.zig`)

Real-time market data streaming from Hyperliquid:
- Connect to Hyperliquid WebSocket
- Subscribe to multiple channels (allMids, l2Book, trades)
- Handle incoming messages
- Track statistics
- Graceful shutdown

**Run:**
```bash
zig build run-example-websocket
```

**What you'll see:**
- Live connection to Hyperliquid
- Real-time price updates (all markets)
- ETH orderbook updates
- BTC trade stream
- Message statistics counter

**Note:** Requires network connection to Hyperliquid mainnet.

---

### 3. HTTP Market Data (`03_http_market_data.zig`)

Fetch market data via HTTP REST API:
- Get market metadata
- Fetch all mid prices
- Get L2 orderbook with spread calculation

**Run:**
```bash
zig build run-example-http
```

**What you'll see:**
- List of all trading pairs
- Current prices for major coins (BTC, ETH, SOL, etc.)
- Detailed ETH orderbook (bids/asks)
- Spread calculation

**Note:** Requires network connection to Hyperliquid mainnet.

---

### 4. Exchange Connector (`04_exchange_connector.zig`)

Use the exchange abstraction layer:
- Create HyperliquidConnector
- Use IExchange interface
- Get ticker data for multiple pairs
- Fetch orderbook
- Symbol mapping (unified ↔ exchange-specific)

**Run:**
```bash
zig build run-example-connector
```

**What you'll see:**
- Exchange connector initialization
- Ticker data for ETH, BTC, SOL
- ETH orderbook (top 5 levels)
- Mid price calculation
- Symbol format conversion

**Key Benefit:** The same code works with any exchange that implements `IExchange`!

---

### 5. Colored Logging (`05_colored_logging.zig`)

Demonstrate colored log output:
- Different colors for different log levels
- ANSI color codes
- Enable/disable colors
- Structured logging with colors

**Run:**
```bash
zig build run-example-colored-logging
```

**What you'll see:**
- **TRACE**: Gray (dim/subtle)
- **DEBUG**: Cyan (technical info)
- **INFO**: Green (normal operations)
- **WARN**: Yellow (attention needed)
- **ERROR**: Red (errors)
- **FATAL**: Bold Red (critical failures)
- Comparison with non-colored output
- Real trading scenario with colored logs

**Key Feature:** Improves log readability and helps quickly identify important messages!

---

### 6. Strategy Backtest (`06_strategy_backtest.zig`)

Run backtests on trading strategies:
- Load historical candle data from CSV
- Test builtin strategies (Dual MA, RSI Mean Reversion, Bollinger Breakout)
- Generate performance metrics
- Analyze trade results

**Run:**
```bash
zig build run-example-backtest
```

**What you'll see:**
- Strategy initialization and configuration
- Backtest execution over historical data
- Performance metrics (Total Trades, Win Rate, Profit Factor, Sharpe Ratio, Max Drawdown)
- Detailed trade log
- Equity curve statistics

**Key Feature:** Validate strategy performance before live trading!

---

### 7. Strategy Optimize (`07_strategy_optimize.zig`)

Optimize strategy parameters using grid search:
- Define parameter ranges to test
- Run grid search optimization
- Find best parameter combinations
- Compare performance across combinations

**Run:**
```bash
zig build run-example-optimize
```

**What you'll see:**
- Parameter grid definition
- Progress through all combinations
- Best parameters found
- Performance comparison
- Optimization statistics

**Key Feature:** Automatically find optimal parameters for maximum performance!

---

### 8. Custom Strategy (`08_custom_strategy.zig`)

Create your own trading strategy:
- Implement IStrategy interface
- Use IndicatorManager for technical indicators
- Define entry/exit logic
- Backtest custom strategy

**Run:**
```bash
zig build run-example-custom
```

**What you'll see:**
- Custom MACD Cross strategy implementation
- EMA calculation and crossover detection
- Signal generation with stop-loss and take-profit
- Backtest results for custom strategy

**Key Feature:** Full flexibility to implement any trading strategy!

---

### 9. New Technical Indicators (`09_new_indicators.zig`) - v0.4.0

Explore v0.4.0 new technical indicators:
- **ADX** - Average Directional Index (trend strength)
- **Ichimoku Cloud** - Trend, support/resistance
- **CCI** - Commodity Channel Index
- **Williams %R** - Overbought/oversold
- **OBV** - On-Balance Volume
- **VWAP** - Volume Weighted Average Price
- **ROC** - Rate of Change
- **Parabolic SAR** - Trend reversal

**Run:**
```bash
zig build run-example-indicators
```

**What you'll see:**
- Explanation of each indicator's purpose and calculation
- Example calculations with sample data
- Trading signal interpretation
- Indicator classification (trend/momentum/volume)

---

### 10. Walk-Forward Analysis (`10_walk_forward.zig`) - v0.4.0

Prevent strategy overfitting with Walk-Forward analysis:
- Split data into training and testing periods
- Rolling window optimization
- Out-of-sample validation
- Overfitting detection

**Run:**
```bash
zig build run-example-walkforward
```

**What you'll see:**
- Walk-Forward concept explanation
- Data splitting strategies (fixed, rolling, expanding, anchored)
- Simulated Walk-Forward results
- Overfitting detection metrics
- Code usage examples

**Key Feature:** Validate strategy robustness before live trading!

---

### 11. Result Export (`11_result_export.zig`) - v0.4.0

Export and load backtest results:
- Export to JSON format
- Export to CSV format
- Load historical results
- Compare multiple strategies

**Run:**
```bash
zig build run-example-export
```

**What you'll see:**
- JSON/CSV export code examples
- Output format demonstrations
- Result loading examples
- Multi-strategy comparison table
- Recommended directory structure

**Key Feature:** Persist results for external analysis and reporting!

---

### 12. Parallel Optimization (`12_parallel_optimize.zig`) - v0.4.0

Speed up optimization with parallel execution:
- Multi-threaded backtesting
- Progress tracking
- Performance comparison
- Thread safety guidelines

**Run:**
```bash
zig build run-example-parallel
```

**What you'll see:**
- Parallel optimization concepts
- Code examples for parallel execution
- Progress bar demonstration
- Performance comparison table (sequential vs parallel)
- Best practices and safety considerations

**Key Feature:** Dramatically reduce optimization time on multi-core systems!

---

### 13. Event-Driven Architecture (`13_event_driven.zig`) - v0.5.0

Explore v0.5.0 event-driven architecture:
- **MessageBus** - Pub/Sub message passing with wildcards
- **Cache** - Central data store with notifications
- **DataEngine** - Market data processing
- **ExecutionEngine** - Order execution management
- **LiveTradingEngine** - Unified trading interface

**Run:**
```bash
zig build run-example-event-driven
```

**What you'll see:**
- MessageBus event subscription and publishing
- Cache quote updates with notification
- DataEngine and ExecutionEngine initialization
- Component statistics and event flow

**Key Feature:** Foundation for real-time live trading systems!

---

### 14. Async Trading Engine (`14_async_engine.zig`) - v0.5.0

Build high-performance async trading systems:
- **libxev Integration** - io_uring (Linux) / kqueue (macOS)
- **Async Event Loop** - Non-blocking I/O processing
- **Timer-Driven Execution** - Heartbeat and tick events
- **Zero-Copy Messaging** - Efficient event passing

**Run:**
```bash
zig build run-example-async-engine
```

**What you'll see:**
- Core component initialization (MessageBus, Cache, DataEngine, ExecutionEngine)
- Event subscription with wildcard patterns
- Simulated market data and order execution
- System tick events and statistics
- Architecture diagram and usage examples

**Key Feature:** Production-ready async trading infrastructure!

---

## 🚀 Quick Start

### Run All Examples

```bash
# Core basics
zig build run-example-core

# WebSocket streaming (requires network)
zig build run-example-websocket

# HTTP market data (requires network)
zig build run-example-http

# Exchange connector (requires network)
zig build run-example-connector

# Colored logging
zig build run-example-colored-logging

# Strategy backtest
zig build run-example-backtest

# Strategy optimization
zig build run-example-optimize

# Custom strategy
zig build run-example-custom

# v0.4.0 Examples
# New indicators
zig build run-example-indicators

# Walk-Forward analysis
zig build run-example-walkforward

# Result export
zig build run-example-export

# Parallel optimization
zig build run-example-parallel

# v0.5.0 Examples
# Event-driven architecture
zig build run-example-event-driven

# Async trading engine
zig build run-example-async-engine

# Run all examples at once
zig build run-examples
```

### Build Without Running

```bash
zig build example-core
zig build example-websocket
zig build example-http
zig build example-connector
```

---

## 📚 Learn More

Each example is heavily commented and demonstrates best practices:

- **Memory Management**: Proper use of allocators and `defer` statements
- **Error Handling**: Using Zig's error unions and context
- **Concurrency**: Atomic operations and thread safety
- **API Design**: Clean interfaces and separation of concerns

### Next Steps

After running the examples, explore the source code:

1. **Read the comments** - Each example has detailed explanations
2. **Modify parameters** - Try different coins, intervals, or depths
3. **Combine features** - Use multiple modules together
4. **Build your own** - Use examples as templates for your application

---

## 🔧 Requirements

- **Zig 0.15** or later
- **Internet connection** for examples 2-4 (WebSocket, HTTP, Connector)
- **No API keys required** - All examples use public endpoints

---

## 💡 Tips

### Logging

All examples use a DummyWriter for console logging. The logger setup follows this pattern:

```zig
const DummyWriter = struct {
    fn write(_: *anyopaque, record: zigQuant.logger.LogRecord) anyerror!void {
        const level_str = switch (record.level) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO ",
            .warn => "WARN ",
            .err => "ERROR",
            .fatal => "FATAL",
        };
        std.debug.print("[{s}] {s}\n", .{ level_str, record.message });
    }
    fn flush(_: *anyopaque) anyerror!void {}
    fn close(_: *anyopaque) void {}
};
```

### Testnet

To use Hyperliquid testnet instead of mainnet:

```zig
const exchange_config = ExchangeConfig{
    .name = "hyperliquid",
    .api_key = "",
    .api_secret = "",
    .testnet = true,  // Set to true for testnet
};

// For HTTP client directly:
var http_client = HyperliquidClient.init(allocator, true, logger);  // true = testnet
```

### Custom Symbols

Try different trading pairs:

```zig
const avax_usdc = TradingPair{ .base = "AVAX", .quote = "USDC" };
const atom_usdc = TradingPair{ .base = "ATOM", .quote = "USDC" };
```

---

## 🐛 Troubleshooting

### "Connection refused"
- Check your internet connection
- Verify Hyperliquid API is accessible
- Check firewall settings

### "Symbol not found"
- Ensure the trading pair exists on Hyperliquid
- Use `getMeta()` to list all available markets

### Memory leaks
- All examples use `std.heap.GeneralPurposeAllocator`
- Check `defer` statements for cleanup (especially for `toString()` results)
- Proper memory management with defer blocks for allocated strings

---

## 📖 Documentation

For more details, see:
- [Main README](../README.md)
- [API Documentation](../docs/)
- [Architecture Guide](../ARCHITECTURE.md)

---

## 🤝 Contributing

Found a bug or want to add an example?
1. Open an issue
2. Submit a pull request
3. Join our community

Happy coding! 🚀
