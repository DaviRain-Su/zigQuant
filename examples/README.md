# zigQuant Examples

This directory contains practical examples demonstrating how to use zigQuant's various features.

## 📋 Examples

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
