# Position Tracker - 仓位追踪和风险管理

> Position Tracker 提供完整的仓位追踪、盈亏计算和账户管理功能

**最后更新**: 2025-12-24
**状态**: ✅ 完成
**测试**: 165/165 通过

---

## 目录

- [概述](#概述)
- [核心组件](#核心组件)
- [使用指南](#使用指南)
- [API 参考](#api-参考)
- [测试](#测试)

---

## 概述

### 功能特性

Position Tracker 是 zigQuant 交易系统的核心组件，提供以下功能：

#### 📊 仓位管理

- **多币种追踪**：同时管理多个币种的仓位
- **双向仓位**：支持多头和空头仓位
- **实时更新**：标记价格实时更新，未实现盈亏自动计算
- **仓位操作**：
  - 开仓/加仓（`increase`）
  - 减仓/平仓（`decrease`）
  - 完全平仓时自动清理

#### 💰 盈亏计算

- **未实现盈亏**：基于标记价格实时计算
  - 公式：`PnL = szi * (mark_price - entry_price)`
  - szi: 有符号仓位大小（正=多头，负=空头）
- **已实现盈亏**：成交时累计
  - 多头：`(close_price - entry_price) * quantity`
  - 空头：`(entry_price - close_price) * quantity`
- **总盈亏**：已实现 + 未实现

#### 📈 账户追踪

- **账户价值**：实时计算总资产价值
- **保证金管理**：
  - 已用保证金
  - 可用保证金
  - 保证金使用率
- **可提现金额**：基于 API 返回数据

#### 🔒 线程安全

- **Mutex 保护**：所有公开方法使用 `std.Thread.Mutex`
- **并发安全**：支持多线程环境

#### 🔌 交易所抽象

- **基于 IExchange 接口**：与具体交易所解耦
- **统一数据类型**：使用 exchange/types.zig 中的统一类型
- **易于扩展**：添加新交易所只需实现 IExchange 接口

---

## 核心组件

### 1. Position (trading/position.zig)

仓位数据结构，基于 Hyperliquid API 规范。

**核心字段**：
```zig
pub const Position = struct {
    coin: []const u8,           // 币种（e.g. "ETH"）
    szi: Decimal,               // 有符号仓位大小（正=多，负=空）
    side: Side,                 // 方向（buy/sell）
    entry_px: Decimal,          // 开仓均价
    mark_price: ?Decimal,       // 标记价格
    unrealized_pnl: Decimal,    // 未实现盈亏
    realized_pnl: Decimal,      // 已实现盈亏
    margin_used: Decimal,       // 已用保证金
    leverage: Leverage,         // 杠杆信息
    // ...更多字段
};
```

**核心方法**：
- `init()`: 初始化仓位
- `increase()`: 增加仓位（开仓/加仓）
- `decrease()`: 减少仓位（减仓/平仓）
- `updateMarkPrice()`: 更新标记价格
- `getTotalPnl()`: 获取总盈亏

### 2. Account (trading/account.zig)

账户信息，基于 Hyperliquid API 规范。

**核心字段**：
```zig
pub const Account = struct {
    margin_summary: MarginSummary,
    cross_margin_summary: MarginSummary,
    withdrawable: Decimal,
    total_realized_pnl: Decimal,
};
```

**核心方法**：
- `getAccountValue()`: 获取账户总价值
- `getAvailableMargin()`: 获取可用保证金
- `getMarginUsageRate()`: 获取保证金使用率

### 3. PositionTracker (trading/position_tracker.zig)

仓位追踪器，管理所有仓位和账户状态。

**核心方法**：
- `syncAccountState()`: 从交易所同步账户状态
- `handleOrderFill()`: 处理订单成交事件
- `updateMarkPrice()`: 更新标记价格
- `getAllPositions()`: 获取所有仓位
- `getPosition()`: 获取单个仓位
- `getAccount()`: 获取账户信息
- `getStats()`: 获取统计信息

---

## 使用指南

### 基础用法

#### 1. 创建 PositionTracker

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

// 准备组件
const allocator = std.heap.page_allocator;
const exchange = try HyperliquidConnector.create(allocator, config, logger);
const logger = try Logger.init(allocator, log_writer, .info);

// 创建 PositionTracker
var tracker = zigQuant.PositionTracker.init(allocator, exchange, logger);
defer tracker.deinit();
```

#### 2. 同步账户状态

```zig
// 从交易所同步仓位和账户信息
try tracker.syncAccountState();

// 获取所有仓位
const positions = try tracker.getAllPositions();
defer allocator.free(positions);

for (positions) |pos| {
    std.debug.print("Position: {s} szi={} entry={} PnL={}\n", .{
        pos.coin,
        pos.szi.toFloat(),
        pos.entry_px.toFloat(),
        pos.getTotalPnl().toFloat(),
    });
}

// 获取账户信息
const account = tracker.getAccount();
std.debug.print("Account Value: ${}\n", .{account.getAccountValue().toFloat()});
```

#### 3. 处理订单成交

```zig
// 当订单成交时调用（通常在 OrderManager 的回调中）
try tracker.handleOrderFill(
    "ETH",                                  // 币种
    .buy,                                   // 方向
    try zigQuant.Decimal.fromString("1.0"), // 数量
    try zigQuant.Decimal.fromString("2000"), // 价格
);
```

#### 4. 更新标记价格

```zig
// 从 WebSocket 或定时更新获取标记价格
try tracker.updateMarkPrice(
    "ETH",
    try zigQuant.Decimal.fromString("2050"),
);

// 未实现盈亏会自动更新
if (tracker.getPosition("ETH")) |pos| {
    std.debug.print("Unrealized PnL: {}\n", .{pos.unrealized_pnl.toFloat()});
}
```

### 高级用法

#### 1. 设置回调

```zig
// 仓位更新回调
fn onPositionUpdate(pos: *zigQuant.TradingPosition) void {
    std.debug.print("Position updated: {s} szi={} PnL={}\n", .{
        pos.coin,
        pos.szi.toFloat(),
        pos.getTotalPnl().toFloat(),
    });
}

// 账户更新回调
fn onAccountUpdate(account: *zigQuant.Account) void {
    std.debug.print("Account updated: Value=${}\n", .{
        account.getAccountValue().toFloat(),
    });
}

// 设置回调
tracker.on_position_update = onPositionUpdate;
tracker.on_account_update = onAccountUpdate;
```

#### 2. 统计信息

```zig
const stats = tracker.getStats();

std.debug.print("Statistics:\n", .{});
std.debug.print("  Positions: {d}\n", .{stats.position_count});
std.debug.print("  Account Value: ${}\n", .{stats.account_value.toFloat()});
std.debug.print("  Realized PnL: ${}\n", .{stats.total_realized_pnl.toFloat()});
std.debug.print("  Unrealized PnL: ${}\n", .{stats.total_unrealized_pnl.toFloat()});
```

#### 3. 与 OrderManager 集成

```zig
// OrderManager 的订单成交回调
fn onOrderFill(order: *zigQuant.Order) void {
    // 提取成交信息
    const coin = order.pair.base;
    const side = order.side;
    const filled = order.filled_amount;
    const price = order.avg_fill_price.?;

    // 更新仓位追踪器
    tracker.handleOrderFill(coin, side, filled, price) catch |err| {
        std.debug.print("Failed to update position: {}\n", .{err});
    };
}

// 设置回调
order_mgr.on_order_fill = onOrderFill;
```

---

## API 参考

### Position Methods

#### `init(allocator, coin, szi) !Position`

创建新仓位。

**参数**:
- `allocator`: 内存分配器
- `coin`: 币种名称
- `szi`: 有符号仓位大小

---

#### `increase(quantity, price) !void`

增加仓位（开仓或加仓）。

**参数**:
- `quantity`: 增加数量
- `price`: 成交价格

---

#### `decrease(quantity, price) !Decimal`

减少仓位（减仓或平仓）。

**参数**:
- `quantity`: 减少数量
- `price`: 成交价格

**返回**: 此次平仓的已实现盈亏

---

#### `updateMarkPrice(mark_price) !void`

更新标记价格并重新计算未实现盈亏。

---

### PositionTracker Methods

#### `syncAccountState() !void`

从交易所同步账户状态和仓位信息。

---

#### `handleOrderFill(coin, side, quantity, price) !void`

处理订单成交事件，更新仓位。

**参数**:
- `coin`: 币种
- `side`: 方向（buy/sell）
- `quantity`: 成交数量
- `price`: 成交价格

---

#### `updateMarkPrice(coin, mark_price) !void`

更新指定币种的标记价格。

---

#### `getAllPositions() ![]const *Position`

获取所有仓位。返回的切片需要调用者释放。

---

#### `getPosition(coin) ?*Position`

获取单个仓位。

---

#### `getStats() Stats`

获取统计信息。

---

## 测试

### 单元测试

**覆盖范围**:
```
✅ Position: init and deinit
✅ Position: increase (open and add)
✅ Position: decrease (close)
✅ Position: unrealized PnL
✅ Account: init
✅ Account: updateFromApiResponse
✅ Account: getAvailableMargin
✅ Account: getMarginUsageRate
✅ PositionTracker: init and deinit
```

**运行测试**:
```bash
zig build test
```

**结果**:
```
Build Summary: 8/8 steps succeeded; 165/165 tests passed
```

---

## 性能特性

- **查询复杂度**: O(1) - 基于 HashMap 索引
- **内存管理**: 自动管理 Position 对象和字符串
- **线程安全**: Mutex 保护的并发访问

---

## 下一步

- [ ] 添加集成测试（连接 testnet）
- [ ] 实现仓位报表生成
- [ ] 添加风险指标（Sharpe ratio, max drawdown）
- [ ] 实现仓位持久化（数据库存储）

---

## 参考资料

- [IExchange Interface](../../core/exchange-router.md)
- [Order Manager](../order-manager/README.md)
- [Hyperliquid API Documentation](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint)
- [Story 011 - Position Tracker](../../../stories/v0.2-mvp/011-position-tracker.md)
