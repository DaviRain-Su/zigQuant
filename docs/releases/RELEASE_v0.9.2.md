# Release v0.9.2 - Live Trading & Interface Transition

## Overview

Version 0.9.2 focuses on live trading improvements and API enhancements.

## Release Date
December 2024

## Status: In Development

---

## New Features

### Live Trading Improvements
- Historical candle loading from Hyperliquid REST API
- Initial capital configuration (0 = use real exchange balance)
- Leverage setting support (1-100x)
- Order size configuration for grid strategy
- Market order handling with IOC limit conversion

### API Enhancements
- `updateLeverage` API for Hyperliquid exchange
- Graceful shutdown with `stopAllLive()` and `stopAllStrategies()`
- Improved error logging with HTTP response bodies

---

## Known Issues

### Critical Issues

#### 1. Leverage Setting Not Working
**Symptom**: Configured leverage (e.g., 1x) doesn't apply; exchange uses default (e.g., 20x)

**Root Cause**: The `updateLeverage` API signature may not match Hyperliquid's expected format

**Status**: Under investigation

#### 2. Shutdown Issues
**Symptom**: Pressing Ctrl+C causes excessive log output and doesn't cleanly terminate

**Root Cause**: 
- WebSocket read threads are detached and don't respond to shutdown signals
- Background threads continue processing after `should_stop` is set
- Thread join timeout insufficient

**Status**: Partial fix applied, but still has issues

#### 3. WebSocket Thread Management
**Symptom**: WebSocket connections don't cleanly close during shutdown

**Root Cause**: 
- Threads started with `detach()` cannot be joined
- No mechanism to forcefully terminate read loops

---

## Web Interface Deprecation Notice

The Web interface (React + Zap HTTP server) has fundamental architectural issues:

1. **Multi-process complexity**: Browser, HTTP server, WebSocket handlers
2. **Thread management**: Detached threads can't be cleanly stopped
3. **Debugging difficulty**: Async communication between components
4. **Resource overhead**: Higher memory and CPU usage

---

## Changes Summary

### Files Modified

#### Exchange Integration
- `src/exchange/hyperliquid/exchange_api.zig` - Added `updateLeverage` API
- `src/exchange/hyperliquid/auth.zig` - Added `signActionJson` method
- `src/exchange/hyperliquid/http.zig` - Improved error logging
- `src/exchange/hyperliquid/info_api.zig` - Added candle snapshot API
- `src/exchange/hyperliquid/types.zig` - Added candle data types
- `src/exchange/hyperliquid/websocket.zig` - Improved shutdown handling

#### Adapters
- `src/adapters/hyperliquid/execution_client.zig` - Market order conversion, leverage setting
- `src/adapters/hyperliquid/data_provider.zig` - Connection management

#### Engine
- `src/engine/runners/live_runner.zig` - Historical candles, leverage, order size
- `src/engine/manager.zig` - Graceful shutdown methods

#### API
- `src/api/zap_server.zig` - Leverage and initial capital in requests

#### Main
- `src/main.zig` - Graceful shutdown sequence

### Files Added
- `src/core/log_buffer.zig` - Log buffer for API
- `src/exchange/hyperliquid/live_adapter.zig` - Live trading adapter

---

## Upgrade Guide

### From v0.9.1

1. Rebuild:
   ```bash
   zig build -Doptimize=ReleaseSafe
   ```

2. Web frontend (optional, experimental):
   ```bash
   cd web && npm install && npm run build
   ```

3. Test live trading:
   ```bash
   ./zig-out/bin/zigQuant serve -p 8080
   ```

### Configuration Changes

New fields in live session request:
```json
{
  "leverage": 5,
  "initial_capital": 0,
  "order_size": 0.001
}
```

- `leverage`: 1-100, default 1
- `initial_capital`: 0 = use real exchange balance
- `order_size`: For grid strategy, size per grid order

---

## Roadmap

### v0.9.3 (Planned)
- Fix leverage setting
- Clean shutdown implementation

### v1.0.0 (Future)
- Production-ready live trading
- Multi-exchange support
- Strategy marketplace

---

## Testing

### Manual Testing Required

1. **Leverage Setting**:
   ```bash
   # Create session with leverage
   curl -X POST http://localhost:8080/api/v2/live \
     -d '{"name":"test","symbols":["BTC"],"strategy":"grid","leverage":5,...}'
   
   # Check exchange position - verify leverage is 5x
   ```

2. **Graceful Shutdown**:
   ```bash
   # Start server with running session
   ./zig-out/bin/zigQuant serve -p 8080
   # Create a session, let it run
   # Press Ctrl+C
   # Verify clean shutdown messages
   ```

3. **Market Orders**:
   ```bash
   # Grid strategy should submit orders as IOC limit orders
   # Check logs for "Market order → IOC limit" messages
   ```

---

## Contributors

- Core development team

## License

MIT License
