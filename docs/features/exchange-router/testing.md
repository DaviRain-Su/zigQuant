# Exchange Router - 测试文档

> 测试覆盖、性能基准、测试策略

**最后更新**: 2025-12-23

---

## 测试覆盖率

**当前状态**: 📋 设计阶段

**目标覆盖率**:
- **核心类型**: 90%+
- **接口层**: 85%+
- **Connector**: 80%+
- **集成测试**: 关键路径 100%

---

## 测试策略

### 测试金字塔

```
        /\
       /  \
      / E2E \        集成测试（少量，覆盖关键流程）
     /______\
    /        \
   / Integration\   集成测试（适量，测试组件交互）
  /____________\
 /              \
/  Unit Tests    \  单元测试（大量，覆盖所有边界情况）
/__________________\
```

---

## 单元测试

### 类型测试 (types_test.zig)

#### TradingPair 测试

```zig
test "TradingPair: symbol generation" {
    const pair = TradingPair{ .base = "BTC", .quote = "USDT" };

    const sym = try pair.symbol(std.testing.allocator);
    defer std.testing.allocator.free(sym);

    try std.testing.expectEqualStrings("BTC-USDT", sym);
}

test "TradingPair: fromSymbol - dash separator" {
    const pair = try TradingPair.fromSymbol("BTC-USDT");
    try std.testing.expectEqualStrings("BTC", pair.base);
    try std.testing.expectEqualStrings("USDT", pair.quote);
}

test "TradingPair: fromSymbol - slash separator" {
    const pair = try TradingPair.fromSymbol("ETH/USDC");
    try std.testing.expectEqualStrings("ETH", pair.base);
    try std.testing.expectEqualStrings("USDC", pair.quote);
}

test "TradingPair: fromSymbol - invalid format" {
    const result = TradingPair.fromSymbol("INVALID");
    try std.testing.expectError(error.InvalidSymbolFormat, result);
}

test "TradingPair: equality" {
    const pair1 = TradingPair{ .base = "BTC", .quote = "USDT" };
    const pair2 = TradingPair{ .base = "BTC", .quote = "USDT" };
    const pair3 = TradingPair{ .base = "ETH", .quote = "USDT" };

    try std.testing.expect(pair1.eql(pair2));
    try std.testing.expect(!pair1.eql(pair3));
}
```

#### OrderRequest 验证测试

```zig
test "OrderRequest: valid limit order" {
    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = try Decimal.fromInt(1),
        .price = try Decimal.fromInt(50000),
    };
    try request.validate();
}

test "OrderRequest: invalid amount (zero)" {
    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = Decimal.ZERO,
        .price = try Decimal.fromInt(50000),
    };
    try std.testing.expectError(error.InvalidAmount, request.validate());
}

test "OrderRequest: limit order without price" {
    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = try Decimal.fromInt(1),
        .price = null,
    };
    try std.testing.expectError(error.LimitOrderRequiresPrice, request.validate());
}

test "OrderRequest: market order with price" {
    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .market,
        .amount = try Decimal.fromInt(1),
        .price = try Decimal.fromInt(50000),
    };
    try std.testing.expectError(error.MarketOrderShouldNotHavePrice, request.validate());
}

test "OrderRequest: invalid price (negative)" {
    const request = OrderRequest{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .amount = try Decimal.fromInt(1),
        .price = try Decimal.fromInt(-100),
    };
    try std.testing.expectError(error.InvalidPrice, request.validate());
}
```

#### Order 辅助方法测试

```zig
test "Order: remainingAmount" {
    const order = Order{
        .exchange_order_id = 12345,
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .status = .partially_filled,
        .amount = try Decimal.fromInt(10),
        .price = try Decimal.fromInt(50000),
        .filled_amount = try Decimal.fromInt(3),
        .created_at = Timestamp.now(),
        .updated_at = Timestamp.now(),
    };

    const remaining = order.remainingAmount();
    try std.testing.expect((try Decimal.fromInt(7)).eql(remaining));
}

test "Order: isComplete" {
    var order = Order{
        .exchange_order_id = 12345,
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .status = .open,
        .amount = try Decimal.fromInt(10),
        .price = try Decimal.fromInt(50000),
        .filled_amount = Decimal.ZERO,
        .created_at = Timestamp.now(),
        .updated_at = Timestamp.now(),
    };

    try std.testing.expect(!order.isComplete());

    order.status = .filled;
    try std.testing.expect(order.isComplete());

    order.status = .cancelled;
    try std.testing.expect(order.isComplete());

    order.status = .rejected;
    try std.testing.expect(order.isComplete());
}

test "Order: isActive" {
    var order = Order{
        .exchange_order_id = 12345,
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .side = .buy,
        .order_type = .limit,
        .status = .open,
        .amount = try Decimal.fromInt(10),
        .price = try Decimal.fromInt(50000),
        .filled_amount = Decimal.ZERO,
        .created_at = Timestamp.now(),
        .updated_at = Timestamp.now(),
    };

    try std.testing.expect(order.isActive());

    order.status = .partially_filled;
    try std.testing.expect(order.isActive());

    order.status = .filled;
    try std.testing.expect(!order.isActive());
}
```

---

### Registry 测试 (registry_test.zig)

```zig
const std = @import("std");
const ExchangeRegistry = @import("registry.zig").ExchangeRegistry;
const IExchange = @import("interface.zig").IExchange;
const Logger = @import("../core/logger.zig").Logger;

test "ExchangeRegistry: init and deinit" {
    var logger = try Logger.init(std.testing.allocator, .info);
    defer logger.deinit();

    var registry = ExchangeRegistry.init(std.testing.allocator, logger);
    defer registry.deinit();

    try std.testing.expect(!registry.isConnected());
}

test "ExchangeRegistry: setExchange and getExchange" {
    var logger = try Logger.init(std.testing.allocator, .info);
    defer logger.deinit();

    var registry = ExchangeRegistry.init(std.testing.allocator, logger);
    defer registry.deinit();

    // 创建 Mock Exchange
    var mock = MockExchange{};
    const exchange = mock.interface();

    const config = .{
        .name = "mock",
        .api_key = null,
        .api_secret = null,
        .testnet = true,
    };

    try registry.setExchange(exchange, config);

    const retrieved = try registry.getExchange();
    try std.testing.expectEqualStrings("mock", retrieved.getName());
}

test "ExchangeRegistry: getExchange without setting" {
    var logger = try Logger.init(std.testing.allocator, .info);
    defer logger.deinit();

    var registry = ExchangeRegistry.init(std.testing.allocator, logger);
    defer registry.deinit();

    const result = registry.getExchange();
    try std.testing.expectError(error.NoExchangeRegistered, result);
}

test "ExchangeRegistry: connectAll" {
    var logger = try Logger.init(std.testing.allocator, .info);
    defer logger.deinit();

    var registry = ExchangeRegistry.init(std.testing.allocator, logger);
    defer registry.deinit();

    var mock = MockExchange{};
    const exchange = mock.interface();

    const config = .{
        .name = "mock",
        .api_key = null,
        .api_secret = null,
        .testnet = true,
    };

    try registry.setExchange(exchange, config);
    try registry.connectAll();

    try std.testing.expect(registry.isConnected());
    try std.testing.expect(mock.connected);
}
```

---

### SymbolMapper 测试 (symbol_mapper_test.zig)

```zig
test "SymbolMapper: toHyperliquid - valid pair" {
    var mapper = SymbolMapper.init();

    const pair = TradingPair{ .base = "ETH", .quote = "USDC" };
    const symbol = try mapper.toHyperliquid(pair);

    try std.testing.expectEqualStrings("ETH", symbol);
}

test "SymbolMapper: toHyperliquid - invalid quote" {
    var mapper = SymbolMapper.init();

    const pair = TradingPair{ .base = "ETH", .quote = "USDT" };
    const result = mapper.toHyperliquid(pair);

    try std.testing.expectError(error.UnsupportedQuoteCurrency, result);
}

test "SymbolMapper: fromHyperliquid" {
    var mapper = SymbolMapper.init();

    const pair = try mapper.fromHyperliquid("BTC");

    try std.testing.expectEqualStrings("BTC", pair.base);
    try std.testing.expectEqualStrings("USDC", pair.quote);
}

test "SymbolMapper: round-trip conversion" {
    var mapper = SymbolMapper.init();

    const original = TradingPair{ .base = "ETH", .quote = "USDC" };
    const symbol = try mapper.toHyperliquid(original);
    const converted = try mapper.fromHyperliquid(symbol);

    try std.testing.expect(original.eql(converted));
}
```

---

## Mock Exchange 实现

用于单元测试和集成测试的 Mock Exchange。

```zig
// src/exchange/mock/connector.zig

const std = @import("std");
const IExchange = @import("../interface.zig").IExchange;
const TradingPair = @import("../types.zig").TradingPair;
const OrderRequest = @import("../types.zig").OrderRequest;
const Order = @import("../types.zig").Order;
const Ticker = @import("../types.zig").Ticker;
const Orderbook = @import("../types.zig").Orderbook;
const Balance = @import("../types.zig").Balance;
const Position = @import("../types.zig").Position;
const Decimal = @import("../../core/decimal.zig").Decimal;
const Timestamp = @import("../../core/time.zig").Timestamp;

pub const MockExchange = struct {
    connected: bool = false,
    next_order_id: u64 = 1,

    pub fn interface(self: *MockExchange) IExchange {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "mock";
    }

    fn connect(ptr: *anyopaque) !void {
        const self: *MockExchange = @ptrCast(@alignCast(ptr));
        self.connected = true;
    }

    fn disconnect(ptr: *anyopaque) void {
        const self: *MockExchange = @ptrCast(@alignCast(ptr));
        self.connected = false;
    }

    fn isConnected(ptr: *anyopaque) bool {
        const self: *MockExchange = @ptrCast(@alignCast(ptr));
        return self.connected;
    }

    fn getTicker(ptr: *anyopaque, pair: TradingPair) !Ticker {
        const self: *MockExchange = @ptrCast(@alignCast(ptr));
        _ = self;

        return Ticker{
            .pair = pair,
            .bid = try Decimal.fromInt(2000),
            .ask = try Decimal.fromInt(2001),
            .last = try Decimal.fromInt(2000),
            .volume_24h = try Decimal.fromInt(1000),
            .timestamp = Timestamp.now(),
        };
    }

    fn getOrderbook(ptr: *anyopaque, pair: TradingPair, depth: u32) !Orderbook {
        const self: *MockExchange = @ptrCast(@alignCast(ptr));
        _ = self;
        _ = depth;

        // 返回简单的 mock 数据
        var bids = [_]OrderbookLevel{
            .{ .price = try Decimal.fromInt(2000), .quantity = try Decimal.fromInt(10) },
        };

        var asks = [_]OrderbookLevel{
            .{ .price = try Decimal.fromInt(2001), .quantity = try Decimal.fromInt(8) },
        };

        return Orderbook{
            .pair = pair,
            .bids = &bids,
            .asks = &asks,
            .timestamp = Timestamp.now(),
        };
    }

    fn createOrder(ptr: *anyopaque, request: OrderRequest) !Order {
        const self: *MockExchange = @ptrCast(@alignCast(ptr));

        const order_id = self.next_order_id;
        self.next_order_id += 1;

        return Order{
            .exchange_order_id = order_id,
            .pair = request.pair,
            .side = request.side,
            .order_type = request.order_type,
            .status = .open,
            .amount = request.amount,
            .price = request.price,
            .filled_amount = Decimal.ZERO,
            .created_at = Timestamp.now(),
            .updated_at = Timestamp.now(),
        };
    }

    fn cancelOrder(ptr: *anyopaque, order_id: u64) !void {
        _ = ptr;
        _ = order_id;
        // Mock: 总是成功
    }

    fn cancelAllOrders(ptr: *anyopaque, pair: ?TradingPair) !u32 {
        _ = ptr;
        _ = pair;
        return 0; // Mock: 返回 0 个撤销订单
    }

    fn getOrder(ptr: *anyopaque, order_id: u64) !Order {
        _ = ptr;
        _ = order_id;
        return error.OrderNotFound;
    }

    fn getBalance(ptr: *anyopaque) ![]Balance {
        _ = ptr;
        return &[_]Balance{};
    }

    fn getPositions(ptr: *anyopaque) ![]Position {
        _ = ptr;
        return &[_]Position{};
    }

    const vtable = IExchange.VTable{
        .getName = getName,
        .connect = connect,
        .disconnect = disconnect,
        .isConnected = isConnected,
        .getTicker = getTicker,
        .getOrderbook = getOrderbook,
        .createOrder = createOrder,
        .cancelOrder = cancelOrder,
        .cancelAllOrders = cancelAllOrders,
        .getOrder = getOrder,
        .getBalance = getBalance,
        .getPositions = getPositions,
    };
};
```

---

## 集成测试

### Hyperliquid Testnet 集成测试

```zig
// src/exchange/hyperliquid/connector_integration_test.zig

const std = @import("std");
const HyperliquidConnector = @import("connector.zig").HyperliquidConnector;
const TradingPair = @import("../types.zig").TradingPair;
const Logger = @import("../../core/logger.zig").Logger;

test "HyperliquidConnector: connect to testnet" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var logger = try Logger.init(std.testing.allocator, .info);
    defer logger.deinit();

    const config = .{
        .name = "hyperliquid",
        .api_key = null,
        .api_secret = null,
        .testnet = true,
    };

    const exchange = try HyperliquidConnector.create(
        std.testing.allocator,
        config,
        logger,
    );
    defer exchange.disconnect();

    try exchange.connect();
    try std.testing.expect(exchange.isConnected());
}

test "HyperliquidConnector: getTicker" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var logger = try Logger.init(std.testing.allocator, .info);
    defer logger.deinit();

    const config = .{
        .name = "hyperliquid",
        .api_key = null,
        .api_secret = null,
        .testnet = true,
    };

    const exchange = try HyperliquidConnector.create(
        std.testing.allocator,
        config,
        logger,
    );
    defer exchange.disconnect();

    try exchange.connect();

    const pair = TradingPair{ .base = "ETH", .quote = "USDC" };
    const ticker = try exchange.getTicker(pair);

    // 验证返回的数据合理
    try std.testing.expect(ticker.bid.isPositive());
    try std.testing.expect(ticker.ask.isPositive());
    try std.testing.expect(ticker.last.isPositive());
}

test "HyperliquidConnector: getOrderbook" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var logger = try Logger.init(std.testing.allocator, .info);
    defer logger.deinit();

    const config = .{
        .name = "hyperliquid",
        .api_key = null,
        .api_secret = null,
        .testnet = true,
    };

    const exchange = try HyperliquidConnector.create(
        std.testing.allocator,
        config,
        logger,
    );
    defer exchange.disconnect();

    try exchange.connect();

    const pair = TradingPair{ .base = "ETH", .quote = "USDC" };
    const orderbook = try exchange.getOrderbook(pair, 5);
    defer std.testing.allocator.free(orderbook.bids);
    defer std.testing.allocator.free(orderbook.asks);

    // 验证订单簿数据
    try std.testing.expect(orderbook.bids.len > 0);
    try std.testing.expect(orderbook.asks.len > 0);

    const best_bid = orderbook.getBestBid().?;
    const best_ask = orderbook.getBestAsk().?;

    try std.testing.expect(best_bid.price.isPositive());
    try std.testing.expect(best_ask.price.isPositive());
    try std.testing.expect(best_ask.price.gt(best_bid.price));
}
```

---

## 性能基准测试

### VTable 调用性能

```zig
test "benchmark: vtable call overhead" {
    var mock = MockExchange{};
    const exchange = mock.interface();

    const iterations = 1_000_000;
    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = exchange.getName();
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = @as(f64, @floatFromInt(end - start));
    const avg_ns = elapsed_ns / @as(f64, @floatFromInt(iterations));

    std.debug.print("VTable call overhead: {d:.2} ns/call\n", .{avg_ns});

    // 目标: < 5ns/call
    try std.testing.expect(avg_ns < 5.0);
}
```

### 符号转换性能

```zig
test "benchmark: symbol conversion" {
    var mapper = SymbolMapper.init();
    const pair = TradingPair{ .base = "ETH", .quote = "USDC" };

    const iterations = 100_000;
    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = try mapper.toHyperliquid(pair);
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = @as(f64, @floatFromInt(end - start));
    const avg_ns = elapsed_ns / @as(f64, @floatFromInt(iterations));

    std.debug.print("Symbol conversion: {d:.2} ns/call\n", .{avg_ns});

    // 目标: < 100ns/call
    try std.testing.expect(avg_ns < 100.0);
}
```

---

## 运行测试

### 运行所有单元测试

```bash
zig test src/exchange/types.zig
zig test src/exchange/registry.zig
zig test src/exchange/symbol_mapper.zig
```

### 运行集成测试

```bash
# 需要网络连接
zig test src/exchange/hyperliquid/connector_integration_test.zig
```

### 运行性能基准

```bash
zig test src/exchange/benchmark_test.zig -O ReleaseFast
```

---

## 测试覆盖场景

### ✅ 已覆盖（设计阶段）

#### 核心类型
- [x] TradingPair 构造和解析
- [x] OrderRequest 验证（所有边界情况）
- [x] Order 辅助方法
- [x] Ticker 计算方法
- [x] Orderbook 查询方法
- [x] Balance 验证
- [x] Position 计算

#### Registry
- [x] 注册和查询交易所
- [x] 连接管理
- [x] 错误处理（无交易所）

#### SymbolMapper
- [x] Hyperliquid 符号转换
- [x] 不支持的计价货币错误
- [x] 往返转换

#### Mock Exchange
- [x] 基本接口实现
- [x] 固定返回数据

### 📋 待实施

#### Connector 集成测试
- [ ] 连接 Hyperliquid Testnet
- [ ] 查询行情和订单簿
- [ ] 下单和撤单（小额）
- [ ] 查询账户余额
- [ ] 查询持仓

#### 性能基准
- [ ] VTable 调用开销
- [ ] 符号转换性能
- [ ] 订单创建性能
- [ ] 内存分配分析

#### 边界情况
- [ ] 网络超时重试
- [ ] API 限流处理
- [ ] 无效订单参数
- [ ] 余额不足

---

## 持续集成

### GitHub Actions 配置（未来）

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.13.0

      - name: Run unit tests
        run: |
          zig build test

      - name: Run integration tests
        run: |
          zig build test-integration
        env:
          HYPERLIQUID_TESTNET: true
```

---

## 测试最佳实践

### DO ✅

1. **每个功能都有测试**
   ```zig
   test "feature: basic case" { ... }
   test "feature: edge case 1" { ... }
   test "feature: error case" { ... }
   ```

2. **使用描述性的测试名称**
   ```zig
   // ✅ 好
   test "OrderRequest: limit order without price should error" { ... }

   // ❌ 差
   test "order test 1" { ... }
   ```

3. **测试一个关注点**
   ```zig
   // ✅ 好：只测试验证逻辑
   test "OrderRequest: validate amount" {
       const request = OrderRequest{ .amount = Decimal.ZERO, ... };
       try std.testing.expectError(error.InvalidAmount, request.validate());
   }
   ```

4. **清理资源**
   ```zig
   const data = try allocator.alloc(u8, 100);
   defer allocator.free(data);
   ```

### DON'T ❌

1. **不要依赖测试顺序**
2. **不要使用硬编码的时间戳**
3. **不要忽略错误处理**
4. **不要在单元测试中访问网络**

---

*Last updated: 2025-12-23*
