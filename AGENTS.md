# AGENTS.md - Developer Guidelines for zigQuant

A Zig-based quantitative trading framework. This document provides build, test, code style, and development conventions for agentic coding assistants operating in this repository.

## Build, Test & Run Commands

### Build Commands
```bash
# Standard build (debug)
zig build

# Build with optimizations
zig build -Doptimize=ReleaseFast

# Fetch dependencies
zig build --fetch

# View available build steps
zig build --help
```

### Run Main Application
```bash
# Run main CLI
zig build run -- <command> [options]

# Common commands
zig build run -- backtest ...
zig build run -- optimize ...
zig build run -- serve --port 3000
```

### Test Commands
```bash
# Run all tests (unit + integration)
zig build test

# Run specific integration test
zig build test-integration
zig build test-strategy-full
zig build test-websocket-orderbook
zig build test-order-lifecycle
zig build test-position-management
zig build test-websocket-events

# Run a single test file (basic approach)
zig build test 2>&1 | grep -A 20 "your_test_name"

# Build and run specific example
zig build run-example-backtest
zig build run-example-optimize
zig build run-example-websocket   # requires network
```

### Key Build Configuration
- **Minimum Zig Version**: 0.15.2
- **Modules**: zigQuant (library), main executable
- **Dependencies**: zigeth, websocket, clap, libxev, openai_zig, zap

---

## Code Style Guidelines

### Formatting & Structure
- **Indentation**: 4 spaces (Zig standard)
- **Line Length**: 100 characters (soft limit, can exceed for readability)
- **File Header**: Start with `//!` doc comment describing the module purpose
- **Blank Lines**: Use between logical sections, around functions

### Imports & Module Organization
```zig
// Standard library first
const std = @import("std");
const Allocator = std.mem.Allocator;

// Internal imports - always import from root.zig
const zigQuant = @import("zigQuant");  // In executable
const root = @import("../root.zig");    // In library modules

// Specific imports
const Logger = zigQuant.Logger;
const Decimal = zigQuant.Decimal;
const OrderRequest = zigQuant.OrderRequest;

// Conditional imports for tests only
const testing = std.testing;
const expect = testing.expect;
```

**Key Rule**: Internal modules should import from `root.zig` (public interface) not directly from sibling modules to maintain clean dependency graph.

### Type Declarations
- **structs/enums/unions**: PascalCase (e.g., `OrderExecutor`, `StrategyType`, `NetworkError`)
- **Functions**: camelCase (e.g., `executeOrder`, `validateConfig`, `parseJSON`)
- **Constants**: snake_case (e.g., `max_retries`, `default_timeout`, `version`)
- **Error sets**: PascalCase + Error suffix (e.g., `ConfigError`, `NetworkError`)
- **Private/Internal**: prefix with underscore not used; rely on `pub` keyword visibility

### Naming Conventions

**Variables & Parameters**:
- Use descriptive names: `order_id` not `oid`, `max_position_size` not `mps`
- Single-letter loops acceptable: `for (items) |item|` or `for (items) |_, i|`
- Boolean prefixes: `is_valid`, `has_orders`, `can_execute`

**Functions**:
- Verb first for actions: `executeOrder`, `validateRequest`, `updateCache`
- Noun first for getters: `getOpenOrders`, `getOrderStatus`
- Use `init` for constructors, `deinit` for cleanup
- Prefer `try` prefix for fallible operations: `tryParse`, `tryConnect`

**Constants**:
- Global constants: `SCREAMING_SNAKE_CASE` for magic numbers
- Config defaults: snake_case in struct fields
- Module exports: use descriptive names matching their purpose

### Error Handling

**Error Categories** (defined in `src/core/errors.zig`):
```zig
pub const NetworkError = error{ConnectionFailed, Timeout, ...};
pub const APIError = error{Unauthorized, RateLimitExceeded, ...};
pub const DataError = error{InvalidFormat, ParseError, ...};
pub const BusinessError = error{InsufficientBalance, OrderNotFound, ...};
pub const SystemError = error{OutOfMemory, FileNotFound, ...};
pub const TradingError = NetworkError || APIError || DataError || BusinessError || SystemError;
```

**Error Handling Pattern**:
```zig
// Use error unions for fallible operations
pub fn validateOrder(self: *Executor, req: OrderRequest) !void {
    if (req.quantity <= 0) {
        return error.InvalidQuantity;
    }
    // ...
}

// Use try keyword for propagation
const result = try self.parseResponse(data);

// Use catch for recovery
const value = self.tryParse(data) catch |err| {
    logger.error("parse failed", .{.error = err});
    return err;
};

// Always handle resource cleanup with defer/errdefer
var file = try std.fs.cwd().openFile("data.csv", .{});
defer file.close();

var buf = try allocator.alloc(u8, 1024);
defer allocator.free(buf);
```

**Error Context**: Use `ErrorContext` struct for rich error metadata:
```zig
const ErrorContext = struct {
    code: ?i32 = null,
    message: ?[]const u8 = null,
    timestamp: i64,
    context: ?[]const u8 = null,
};
```

### Comments & Documentation

**Module Header** (required in all files):
```zig
//! Module Name - Brief description
//!
//! Longer description of what this module provides:
//! - Feature 1
//! - Feature 2
//!
//! Design principles:
//! - Principle 1
//! - Principle 2

const std = @import("std");
```

**Function Documentation**:
```zig
/// Brief description
/// 
/// Longer description if needed. Explain parameters and return values.
/// 
/// Errors: Can return ConfigError if X is invalid
pub fn loadConfig(allocator: Allocator, path: []const u8) !Config {
```

**Inline Comments**: Use sparingly, only for non-obvious logic
```zig
// Update indices when order status changes
try self.orders_open.remove(order.id);
try self.orders_closed.put(order.id, order);
```

### Struct & Type Design

**Struct Definition Pattern**:
```zig
pub const OrderExecutor = struct {
    allocator: std.mem.Allocator,
    exchange: ?IExchange,
    logger: Logger,
    simulation_mode: bool,

    /// Initialize executor
    pub fn init(allocator: std.mem.Allocator, exchange: ?IExchange, logger: Logger) OrderExecutor {
        return OrderExecutor{
            .allocator = allocator,
            .exchange = exchange,
            .logger = logger,
            .simulation_mode = exchange == null,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *OrderExecutor) void {
        _ = self;  // Mark as deliberately unused
    }

    /// Execute an order
    pub fn executeOrder(self: *OrderExecutor, request: OrderRequest) !Order {
        // Implementation
    }
};
```

**Interface Pattern**:
```zig
pub const IExchange = struct {
    ptr: *anyopaque,
    submitOrderFn: *const fn (*anyopaque, OrderRequest) anyerror!Order,
    
    pub fn submitOrder(self: IExchange, request: OrderRequest) !Order {
        return self.submitOrderFn(self.ptr, request);
    }
};
```

### Memory Management

- **Allocator**: Always accept `allocator: std.mem.Allocator` as parameter in functions that allocate
- **Ownership**: Clear ownership of allocated memory (who frees it?)
- **Resource Cleanup**: Use `defer` / `errdefer` for cleanup guarantees
- **Collections**: Use `std.ArrayList`, `std.StringHashMap` from std library
- **Slices**: Prefer slices over owned vectors for parameters

```zig
pub fn processItems(allocator: Allocator, items: []const Item) !void {
    var result = std.ArrayList(Result).init(allocator);
    defer result.deinit();
    
    for (items) |item| {
        try result.append(try processItem(allocator, item));
    }
    
    return result.items;
}
```

### Testing Conventions

**Test File Structure**:
- Location: `tests/integration/` or inline with `test "description" { ... }`
- Use `std.testing` for assertions
- Create helper functions for common setup
- Validate memory is not leaked

```zig
test "order executor validates requests" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var executor = OrderExecutor.init(allocator, null, logger);
    defer executor.deinit();
    
    const request = OrderRequest{ /* ... */ };
    try testing.expectError(error.InvalidQuantity, executor.validateOrder(request));
}
```

---

## Architecture & Design Patterns

The codebase implements several key patterns (see `docs/architecture/ARCHITECTURE_PATTERNS.md`):

1. **MessageBus**: Pub/Sub event system (v0.5.0)
2. **Cache**: High-performance in-memory cache for orders/positions
3. **Engine Pattern**: DataEngine, ExecutionEngine, BacktestEngine
4. **Strategy Interface**: `IStrategy` for pluggable strategies
5. **Clock-Driven**: Tick-based strategy execution (v0.7.0)
6. **Event-Driven**: Event loop with libxev integration

---

## Version & Dependencies

- **Current Version**: 0.7.0 (see build.zig.zon)
- **Zig Version**: 0.15.2+
- **Key Dependencies**:
  - `zigeth` - Ethereum crypto (Ed25519 signing)
  - `websocket` - WebSocket client/server
  - `clap` - CLI argument parsing
  - `libxev` - Async event loop
  - `openai_zig` - OpenAI API client
  - `zap` - HTTP/WebSocket server (v0.10+)

---

## Project Structure

```
src/
  ├── core/           # Fundamentals (time, decimal, error, config, logger)
  ├── exchange/       # Exchange adapters (Hyperliquid, interface, registry)
  ├── strategy/       # Strategy framework, indicators, executor
  ├── backtest/       # Backtest engine, analyzer, optimizer
  ├── market/         # Orderbook, candles
  ├── api/            # HTTP API server (Zap)
  ├── trading/        # Live trading engine, hot reload
  └── main.zig        # CLI entry point

tests/
  └── integration/    # Integration tests (requires network/APIs)

examples/
  └── *.zig           # Self-contained examples
```

---

## When Making Changes

1. **Read existing code** in the area you're modifying first
2. **Follow naming patterns** of that module
3. **Add doc comments** for public APIs
4. **Validate memory safety** - use defer for cleanup
5. **Handle errors properly** - don't ignore or panic
6. **Write tests** for new functionality
7. **Update CHANGELOG.md** if user-facing changes

---

## References

- **Zig Language**: https://ziglang.org/documentation/
- **Architecture Patterns**: `docs/architecture/ARCHITECTURE_PATTERNS.md`
- **Quick Start**: `QUICK_START.md`
- **API Reference**: `docs/api-quick-reference.md`
