# zigQuant v0.5.0 Release Notes

**Release Date**: 2025-12-27
**Version**: 0.5.0
**Codename**: Event-Driven Architecture

---

## Overview

v0.5.0 introduces a complete event-driven architecture for zigQuant, laying the foundation for production-grade live trading systems. This release adds 5 major core components (4736 lines of code), 49 new tests, and 2 new examples.

---

## Highlights

### Event-Driven Core Architecture

Inspired by NautilusTrader and Hummingbot, zigQuant now features a complete event-driven architecture:

- **MessageBus** - High-performance message passing with Pub/Sub, Request/Response, and Command patterns
- **Cache** - Central data store for quotes, candles, orders, positions with O(1) access
- **DataEngine** - Market data processing with IDataProvider interface (VTable)
- **ExecutionEngine** - Order execution with pre-tracking and risk controls
- **LiveTradingEngine** - Unified trading interface for event-driven and tick-driven modes

### Key Features

- **Wildcard Topic Matching**: Subscribe to `market_data.*` to receive all market data events
- **VTable Polymorphism**: IDataProvider and IExecutionClient interfaces for exchange adapters
- **Order Pre-Tracking**: Hummingbot-style order tracking prevents order loss during API timeouts
- **Risk Controls**: Order size limits, open order limits, position limits

---

## New Components

### MessageBus (863 lines)

```zig
const MessageBus = zigQuant.MessageBus;
var bus = MessageBus.init(allocator);

// Subscribe to events
try bus.subscribe("market_data.*", handler);

// Publish events
bus.publish("market_data.quote", .{
    .market_data = .{
        .instrument_id = "BTC-USDT",
        .bid = 50000.0,
        .ask = 50010.0,
        ...
    },
});
```

### Cache (939 lines)

```zig
const Cache = zigQuant.Cache;
var cache = Cache.init(allocator, &bus, .{
    .enable_notifications = true,
});

// Update quote
try cache.updateQuote(.{
    .symbol = "ETH-USDT",
    .bid = Decimal.fromInt(3000),
    .ask = Decimal.fromInt(3010),
    ...
});

// Get quote
if (cache.getQuote("ETH-USDT")) |quote| {
    // Use quote data
}
```

### DataEngine (1039 lines)

```zig
const DataEngine = zigQuant.DataEngine;
var data_engine = DataEngine.init(allocator, &bus, &cache, .{
    .data_validation = true,
});

// Register data provider (VTable interface)
try data_engine.registerProvider(my_provider);
```

### ExecutionEngine (1036 lines)

```zig
const ExecutionEngine = zigQuant.ExecutionEngine;
var exec_engine = ExecutionEngine.init(allocator, &bus, &cache, .{
    .max_order_size = Decimal.fromInt(1000),
    .max_open_orders = 100,
});

// Set execution client (VTable interface)
exec_engine.setClient(my_client);
try exec_engine.start();
```

### LiveTradingEngine (859 lines)

```zig
const LiveTradingEngine = zigQuant.LiveTradingEngine;
var engine = LiveTradingEngine.init(allocator, .{
    .mode = .event_driven,
    .heartbeat_interval_ms = 1000,
    .tick_interval_ms = 100,
});
```

---

## New Examples

### Example 13: Event-Driven Architecture

```bash
zig build run-example-event-driven
```

Demonstrates:
- MessageBus event subscription and publishing
- Cache quote updates with notifications
- DataEngine and ExecutionEngine initialization
- Component statistics and event flow

### Example 14: Async Trading Engine

```bash
zig build run-example-async-engine
```

Demonstrates:
- Core component initialization
- Event subscription with wildcard patterns
- Simulated market data and order execution
- System tick events and architecture overview

---

## Statistics

| Metric | Value |
|--------|-------|
| Total Tests | 502 (up from 453) |
| New Tests | 49 |
| Integration Tests | 7 (new) |
| Total Examples | 14 (up from 12) |
| New Code Lines | 4736 |
| Memory Leaks | 0 |

### Code Breakdown

| File | Lines | Description |
|------|-------|-------------|
| `src/core/message_bus.zig` | 863 | Message bus core |
| `src/core/cache.zig` | 939 | Central data cache |
| `src/core/data_engine.zig` | 1039 | Data engine |
| `src/core/execution_engine.zig` | 1036 | Execution engine |
| `src/trading/live_engine.zig` | 859 | Live trading engine |
| **Total** | **4736** | **Core code** |

---

## Breaking Changes

None. v0.5.0 is fully backward compatible with v0.4.0.

---

## Migration Guide

No migration required. The new event-driven components are additive and do not affect existing backtest or CLI functionality.

To use the new components:

```zig
const zigQuant = @import("zigQuant");

// New v0.5.0 imports
const MessageBus = zigQuant.MessageBus;
const Cache = zigQuant.Cache;
const DataEngine = zigQuant.DataEngine;
const ExecutionEngine = zigQuant.ExecutionEngine;
const LiveTradingEngine = zigQuant.LiveTradingEngine;
```

---

## Documentation

- [v0.5.0 Overview](./stories/v0.5.0/OVERVIEW.md)
- [Story 023: MessageBus](./stories/v0.5.0/STORY_023_MESSAGE_BUS.md)
- [Story 024: Cache](./stories/v0.5.0/STORY_024_CACHE.md)
- [Story 025: DataEngine](./stories/v0.5.0/STORY_025_DATA_ENGINE.md)
- [Story 026: ExecutionEngine](./stories/v0.5.0/STORY_026_EXECUTION_ENGINE.md)
- [Story 027: LiveTradingEngine](./stories/v0.5.0/STORY_027_LIBXEV_INTEGRATION.md)

---

## What's Next (v0.6.0)

- Vectorized backtesting engine (SIMD optimization)
- HyperliquidDataProvider (IDataProvider implementation)
- HyperliquidExecutionClient (IExecutionClient implementation)
- Paper trading mode
- `zigquant run-strategy --paper` command

See [NEXT_STEPS.md](./NEXT_STEPS.md) for the full roadmap.

---

## Contributors

- Claude (Implementation)
- zigQuant Community

---

## Installation

```bash
# Clone repository
git clone https://github.com/your-repo/zigQuant.git
cd zigQuant

# Build
zig build

# Run tests
zig build test

# Run examples
zig build run-example-event-driven
zig build run-example-async-engine
```

---

**Full Changelog**: v0.4.0...v0.5.0
