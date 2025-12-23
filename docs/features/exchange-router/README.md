# Exchange Router - 功能概览

> 多交易所抽象层，提供统一的交易所访问接口

**状态**: 📋 设计中
**版本**: v0.2.0
**Story**: [Phase 0: Exchange Router 设计](../../../.claude/plans/sorted-crunching-sonnet.md)
**最后更新**: 2025-12-23

---

## 📋 概述

Exchange Router 是 ZigQuant 的交易所抽象层，提供统一的接口来访问多个交易所（CEX 和 DEX）。通过这一抽象层，上层业务逻辑（OrderManager、PositionTracker、CLI）无需关心具体的交易所实现细节。

### 为什么需要 Exchange Router？

在量化交易系统中，支持多个交易所是基本需求。但每个交易所的 API 都不同：

**问题**：
- ❌ Hyperliquid 使用 `"ETH"` 作为交易对符号
- ❌ Binance 使用 `"ETHUSDT"` 格式
- ❌ OKX 使用 `"ETH-USDT"` 格式
- ❌ 订单状态、错误码、数据格式各不相同
- ❌ 直接依赖具体交易所会导致后续重构困难

**解决方案**：
- ✅ 定义统一的数据类型（TradingPair, Order, Position）
- ✅ 提供统一的接口（IExchange vtable）
- ✅ 使用 SymbolMapper 转换交易对符号
- ✅ 使用 ExchangeRegistry 管理多个交易所
- ✅ 上层代码只依赖抽象接口，不依赖具体实现

### 核心特性

1. **统一接口**：所有交易所实现 IExchange 接口
2. **类型安全**：使用 Zig 的 vtable 模式实现多态
3. **符号映射**：自动转换不同交易所的交易对格式
4. **注册表**：集中管理多个交易所实例
5. **可扩展**：新增交易所只需实现 IExchange 接口

---

## 🎯 设计目标

### 主要目标

1. **解耦上层逻辑**
   - OrderManager 不应知道使用的是 Hyperliquid 还是 Binance
   - CLI 通过 Registry 访问交易所，支持配置切换

2. **避免重复代码**
   - 统一的错误处理
   - 统一的重试逻辑
   - 统一的日志记录

3. **支持未来扩展**
   - 智能路由（选择最优价格的交易所）
   - 拆单（大订单分发到多个交易所）
   - 跨交易所套利

4. **保持性能**
   - vtable 调用开销极小
   - 零拷贝数据转换（尽可能）
   - 内存分配最小化

---

## 🚀 快速开始

### 架构层次

```
CLI / Strategy Engine
        ↓
OrderManager / PositionTracker
        ↓
ExchangeRegistry
        ↓
IExchange (统一接口)
        ↓
┌─────────┬─────────┬─────────┐
│Hyperliquid│ Binance │   OKX   │
└─────────┴─────────┴─────────┘
```

### 基本使用流程

#### 1. 创建 Exchange Registry

```zig
const std = @import("std");
const ExchangeRegistry = @import("exchange/registry.zig").ExchangeRegistry;
const Logger = @import("core/logger.zig").Logger;

var logger = try Logger.init(allocator, .info);
var registry = ExchangeRegistry.init(allocator, logger);
defer registry.deinit();
```

#### 2. 创建 Hyperliquid Connector

```zig
const HyperliquidConnector = @import("exchange/hyperliquid/connector.zig").HyperliquidConnector;
const ExchangeConfig = @import("core/config.zig").ExchangeConfig;

const config = ExchangeConfig{
    .name = "hyperliquid",
    .api_key = "your_api_key",
    .api_secret = "your_secret",
    .testnet = true,
};

const connector = try HyperliquidConnector.create(allocator, config, logger);
defer connector.destroy();
const exchange = connector.interface();
```

#### 3. 注册到 Registry

```zig
try registry.setExchange(exchange, config);
try registry.connectAll();
```

#### 4. 通过统一接口访问

```zig
const ex = try registry.getExchange();

// 查询行情
const pair = TradingPair{ .base = "ETH", .quote = "USDC" };
const ticker = try ex.getTicker(pair);
std.debug.print("ETH Price: {}\n", .{ticker.last.toFloat()});

// 下单
const order_request = OrderRequest{
    .pair = pair,
    .side = .buy,
    .order_type = .limit,
    .amount = try Decimal.fromString("0.1"),
    .price = try Decimal.fromString("2000.0"),
};
const order = try ex.createOrder(order_request);
std.debug.print("Order ID: {}\n", .{order.exchange_order_id});
```

---

## 📊 核心组件

### 1. 统一数据类型 (types.zig)

**作用**: 定义所有交易所共用的数据格式

```zig
// 交易对
pub const TradingPair = struct {
    base: []const u8,   // "ETH"
    quote: []const u8,  // "USDC"
};

// 订单请求
pub const OrderRequest = struct {
    pair: TradingPair,
    side: Side,              // buy/sell
    order_type: OrderType,   // limit/market
    amount: Decimal,
    price: ?Decimal,
};

// 订单响应
pub const Order = struct {
    exchange_order_id: u64,
    pair: TradingPair,
    status: OrderStatus,
    filled_amount: Decimal,
    // ...
};

// 其他：Ticker, Orderbook, Balance, Position
```

### 2. 统一接口 (interface.zig)

**作用**: 定义所有交易所必须实现的方法

```zig
pub const IExchange = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        // 连接管理
        connect: *const fn (*anyopaque) anyerror!void,
        disconnect: *const fn (*anyopaque) void,

        // 市场数据
        getTicker: *const fn (*anyopaque, TradingPair) anyerror!Ticker,
        getOrderbook: *const fn (*anyopaque, TradingPair, u32) anyerror!Orderbook,

        // 交易
        createOrder: *const fn (*anyopaque, OrderRequest) anyerror!Order,
        cancelOrder: *const fn (*anyopaque, u64) anyerror!void,

        // 账户
        getBalance: *const fn (*anyopaque) anyerror![]Balance,
        getPositions: *const fn (*anyopaque) anyerror![]Position,
    };
};
```

### 3. 符号映射器 (symbol_mapper.zig)

**作用**: 在统一格式和交易所特定格式之间转换

```zig
pub const SymbolMapper = struct {
    // ETH-USDC → "ETH" (Hyperliquid)
    pub fn toHyperliquid(pair: TradingPair) ![]const u8

    // "ETH" → ETH-USDC (不返回错误)
    pub fn fromHyperliquid(symbol: []const u8) TradingPair

    // 未来：toBinance, toOKX, etc.
};
```

### 4. 交易所注册表 (registry.zig)

**作用**: 管理和访问交易所实例

```zig
pub const ExchangeRegistry = struct {
    exchange: ?IExchange,  // MVP: 单交易所
    config: ?ExchangeConfig,
    logger: Logger,

    pub fn setExchange(self, exchange: IExchange, config: ExchangeConfig) !void
    pub fn getExchange(self) !IExchange
    pub fn connectAll(self) !void
};
```

### 5. Hyperliquid Connector (connector.zig)

**作用**: Hyperliquid 的 IExchange 实现

```zig
pub const HyperliquidConnector = struct {
    http: HyperliquidClient,
    symbol_mapper: SymbolMapper,

    pub fn create(allocator, config, logger) !*HyperliquidConnector
    pub fn destroy(self) void
    pub fn interface(self) IExchange

    // VTable 实现
    fn getTicker(ptr: *anyopaque, pair: TradingPair) !Ticker {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

        // 1. 转换符号
        const symbol = try symbol_mapper.toHyperliquid(pair);

        // 2. 调用 Hyperliquid API
        const mids = try InfoAPI.getAllMids(&self.http);
        const mid_price = mids.get(symbol) orelse return error.SymbolNotFound;

        // 3. 返回统一格式
        return Ticker{
            .pair = pair,
            .bid = mid_price,
            .ask = mid_price,
            .last = mid_price,
            .timestamp = Timestamp.now(),
        };
    }
};
```

---

## 🔄 数据流

### 查询行情流程

```
CLI
  ↓ getTicker(TradingPair{.base="ETH", .quote="USDC"})
Registry.getExchange()
  ↓ IExchange.getTicker(pair)
HyperliquidConnector.getTicker(ptr, pair)
  ↓ symbol_mapper.toHyperliquid(pair) → "ETH"
InfoAPI.getAllMids(http_client)
  ↓ POST /info {"type": "allMids"}
Hyperliquid API
  ← {"ETH": "2145.5", ...}
HyperliquidConnector
  ← Ticker{pair, bid, ask, last, timestamp}
CLI
```

### 下单流程

```
CLI
  ↓ createOrder(OrderRequest)
OrderManager
  ↓ registry.getExchange().createOrder(request)
HyperliquidConnector.createOrder(ptr, request)
  ↓ symbol_mapper.toHyperliquid(request.pair)
  ↓ 转换为 Hyperliquid 订单格式
ExchangeAPI.placeOrder(http_client, hl_request)
  ↓ POST /exchange {"action": {"type": "order", ...}}
Hyperliquid API
  ← {"status": "ok", "response": {"data": {...}}}
HyperliquidConnector
  ← Order{exchange_order_id, status, filled_amount, ...}
OrderManager
  ← 存储订单并返回
CLI
```

---

## 📐 设计模式

### VTable 模式（类似面向对象的多态）

```zig
// 定义接口
pub const IExchange = struct {
    ptr: *anyopaque,        // 指向具体实现的指针
    vtable: *const VTable,  // 函数表

    pub const VTable = struct {
        getTicker: *const fn (*anyopaque, TradingPair) anyerror!Ticker,
        // ... 其他方法
    };

    // 代理方法
    pub fn getTicker(self: IExchange, pair: TradingPair) !Ticker {
        return self.vtable.getTicker(self.ptr, pair);
    }
};

// 具体实现
pub const HyperliquidConnector = struct {
    // ... 字段

    pub fn interface(self: *HyperliquidConnector) IExchange {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn getTicker(ptr: *anyopaque, pair: TradingPair) !Ticker {
        const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));
        // 实际实现
    }

    const vtable = IExchange.VTable{
        .getTicker = getTicker,
        // ...
    };
};
```

**优势**:
- ✅ 类型安全（编译时检查）
- ✅ 性能优秀（直接函数调用，无虚表查找开销）
- ✅ Zig 原生支持
- ✅ 易于测试（可以创建 Mock 实现）

---

## 💡 最佳实践

### DO ✅

1. **始终通过 IExchange 访问交易所**
   ```zig
   const exchange = try registry.getExchange();
   const ticker = try exchange.getTicker(pair);
   ```

2. **使用统一的数据类型**
   ```zig
   const pair = TradingPair{ .base = "BTC", .quote = "USDT" };
   ```

3. **验证订单请求**
   ```zig
   try order_request.validate();
   const order = try exchange.createOrder(order_request);
   ```

4. **处理错误**
   ```zig
   const ticker = exchange.getTicker(pair) catch |err| {
       logger.err("Failed to get ticker: {}", .{err});
       return err;
   };
   ```

### DON'T ❌

1. **不要直接使用具体的交易所实现**
   ```zig
   // ❌ 错误
   var hl = HyperliquidClient.init(...);
   const data = hl.getAllMids();

   // ✅ 正确
   const exchange = try registry.getExchange();
   const ticker = try exchange.getTicker(pair);
   ```

2. **不要绕过类型验证**
   ```zig
   // ❌ 错误
   const order = Order{ .amount = Decimal.ZERO, ... };

   // ✅ 正确
   const request = OrderRequest{ ... };
   try request.validate();
   ```

3. **不要硬编码交易所特定格式**
   ```zig
   // ❌ 错误
   const symbol = "ETHUSDT";  // Binance 格式

   // ✅ 正确
   const pair = TradingPair{ .base = "ETH", .quote = "USDT" };
   const symbol = try mapper.toBinance(pair);
   ```

---

## 🎯 适用场景

### ✅ 适用

- 需要支持多个交易所
- 需要跨交易所套利
- 需要智能订单路由
- 需要统一的交易接口
- 需要方便地切换交易所

### ❌ 不适用

- 只使用单一交易所且永不更换（极少见）
- 需要直接访问交易所特定功能（应扩展 IExchange 接口）

---

## 📈 性能指标

### 目标性能

| 指标 | 目标 | 说明 |
|------|------|------|
| VTable 调用开销 | < 1ns | 直接函数指针调用 |
| 符号转换 | < 100ns | 简单字符串操作 |
| 类型转换 | < 1μs | Decimal 和结构体构造 |
| 接口调用总开销 | < 2μs | 可忽略不计 |

### 实测性能

（待实现后补充）

---

## 🔮 未来扩展

### v0.3: 多交易所支持

```zig
pub const ExchangeRegistry = struct {
    exchanges: std.StringHashMap(IExchange),  // 支持多个交易所

    pub fn addExchange(self, name: []const u8, exchange: IExchange) !void
    pub fn getExchange(self, name: []const u8) ?IExchange
};
```

### v0.4: 智能路由

```zig
pub const ExchangeRouter = struct {
    registry: *ExchangeRegistry,
    strategy: RoutingStrategy,

    pub const RoutingStrategy = enum {
        best_price,   // 选择最优价格
        lowest_fee,   // 选择最低手续费
        split,        // 拆单到多个交易所
    };

    pub fn routeOrder(self, request: OrderRequest) ![]Order
};
```

### v0.5: 聚合订单簿

```zig
pub fn getAggregatedOrderbook(
    self: *ExchangeRouter,
    pair: TradingPair,
) !AggregatedOrderbook {
    // 合并所有交易所的订单簿
    // 返回最优价格排序的聚合订单簿
}
```

---

## 📚 相关文档

- [实现细节](./implementation.md) - 详细的实现说明
- [API 参考](./api.md) - 完整的 API 文档
- [测试策略](./testing.md) - 测试方法和用例
- [Bug 追踪](./bugs.md) - 已知问题
- [变更日志](./changelog.md) - 版本历史

**Story 文档**:
- [实施计划](../../../.claude/plans/sorted-crunching-sonnet.md) - 详细的实施计划

**架构文档**:
- [系统架构](../../ARCHITECTURE.md) - 完整的系统架构设计

---

## 🎓 学习资源

### 理解 VTable 模式

- [Zig 官方文档 - anyopaque](https://ziglang.org/documentation/master/#anyopaque)
- [Zig 设计模式 - Interface Pattern](https://github.com/ziglings/exercises)

### 交易所 API 文档

- [Hyperliquid API](https://hyperliquid.gitbook.io/hyperliquid-docs/)
- [Binance API](https://binance-docs.github.io/apidocs/)
- [OKX API](https://www.okx.com/docs-v5/en/)

---

*本文档描述的是 Exchange Router 的设计和使用方法。MVP (v0.2) 阶段只支持单个交易所（Hyperliquid），但架构已为多交易所扩展做好准备。*
