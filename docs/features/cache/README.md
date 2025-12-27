# Cache - 高性能内存缓存

**版本**: v0.5.0
**状态**: 计划中
**层级**: Core Layer
**依赖**: MessageBus

---

## 功能概述

Cache 是 zigQuant 的高性能内存缓存系统，提供纳秒级访问常用对象（订单、仓位、账户、合约）。

### 设计目标

参考 **NautilusTrader** 的 Cache 设计：

- **高性能**: 纳秒级查询延迟
- **单一数据源**: 作为系统状态的唯一真相来源
- **自动同步**: 与 MessageBus 集成，自动更新状态
- **索引优化**: 维护多种索引加速查询

---

## 核心功能

### 数据存储

| 数据类型 | 描述 | 索引 |
|----------|------|------|
| **Instruments** | 交易品种信息 | by ID |
| **Orders** | 订单数据 | by ID, by status, by instrument |
| **Positions** | 仓位数据 | by instrument |
| **Accounts** | 账户数据 | by ID |

### 索引类型

- **orders_open**: 所有开仓订单
- **orders_closed**: 所有已平仓订单
- **orders_by_instrument**: 按品种分组的订单

---

## 核心 API

### Cache

```zig
pub const Cache = struct {
    /// 初始化
    pub fn init(allocator: Allocator, message_bus: *MessageBus) !Cache;

    // ========== 合约查询 ==========
    pub fn getInstrument(self: *Cache, id: []const u8) ?Instrument;
    pub fn getAllInstruments(self: *Cache) []const Instrument;

    // ========== 订单查询 ==========
    pub fn getOrder(self: *Cache, order_id: []const u8) ?*Order;
    pub fn getOpenOrders(self: *Cache) []*Order;
    pub fn getOrdersByInstrument(self: *Cache, instrument_id: []const u8) []*Order;
    pub fn orderCount(self: *Cache) usize;
    pub fn openOrderCount(self: *Cache) usize;

    // ========== 仓位查询 ==========
    pub fn getPosition(self: *Cache, instrument_id: []const u8) ?Position;
    pub fn getAllPositions(self: *Cache) []const Position;
    pub fn hasPosition(self: *Cache, instrument_id: []const u8) bool;

    // ========== 账户查询 ==========
    pub fn getAccount(self: *Cache, account_id: []const u8) ?Account;

    // ========== 更新操作 ==========
    pub fn updateInstrument(self: *Cache, instrument: Instrument) !void;
    pub fn updateOrder(self: *Cache, order: Order) !void;
    pub fn updatePosition(self: *Cache, position: Position) !void;
    pub fn updateAccount(self: *Cache, account: Account) !void;

    /// 清理
    pub fn deinit(self: *Cache) void;
};
```

---

## 数据结构

### Order

```zig
pub const Order = struct {
    id: []const u8,
    client_order_id: []const u8,
    instrument_id: []const u8,
    side: Side,
    order_type: OrderType,
    quantity: Decimal,
    filled_quantity: Decimal,
    price: ?Decimal,
    status: OrderStatus,
    created_at: i64,
    updated_at: i64,
};
```

### Position

```zig
pub const Position = struct {
    instrument_id: []const u8,
    side: Side,
    quantity: Decimal,
    entry_price: Decimal,
    unrealized_pnl: Decimal,
    realized_pnl: Decimal,
    margin: Decimal,
    leverage: Decimal,
    updated_at: i64,
};
```

### Account

```zig
pub const Account = struct {
    id: []const u8,
    balance: Decimal,
    available: Decimal,
    margin_used: Decimal,
    unrealized_pnl: Decimal,
    realized_pnl: Decimal,
    updated_at: i64,
};
```

---

## 使用示例

### 策略查询仓位

```zig
pub fn generateSignal(self: *Strategy, data: MarketData) !?Signal {
    // 快速查询仓位 (纳秒级)
    const position = self.cache.getPosition(data.instrument_id);

    if (position) |pos| {
        // 已有仓位，检查止损
        if (pos.unrealized_pnl.lt(self.stop_loss)) {
            return Signal{ .type = .exit };
        }
    } else {
        // 无仓位，检查入场
        if (self.shouldEnter(data)) {
            return Signal{ .type = .entry, .side = .buy };
        }
    }

    return null;
}
```

### 风险管理查询

```zig
pub fn checkRiskLimits(self: *RiskManager) !bool {
    // 获取所有开仓订单
    const open_orders = self.cache.getOpenOrders();

    // 计算总挂单量
    var total_pending = Decimal.zero;
    for (open_orders) |order| {
        total_pending = total_pending.add(
            order.quantity.sub(order.filled_quantity)
        );
    }

    // 检查风险限制
    const account = self.cache.getAccount(self.account_id) orelse
        return error.AccountNotFound;

    return total_pending.le(account.available.mul(self.max_exposure));
}
```

---

## MessageBus 集成

Cache 自动订阅 MessageBus 事件，保持状态同步：

```zig
// 初始化时自动订阅
try message_bus.subscribe("order.*", cache.onOrderEvent);
try message_bus.subscribe("position.*", cache.onPositionEvent);
try message_bus.subscribe("account.*", cache.onAccountEvent);
```

---

## 性能指标

| 指标 | 目标 |
|------|------|
| 单次查询延迟 | < 100ns |
| 批量查询 (100 orders) | < 10μs |
| 更新延迟 | < 1μs |
| 内存占用 | < 1KB per order |

---

## 文件结构

```
src/core/
├── cache.zig                # Cache 实现
└── types/
    ├── order.zig            # Order 类型
    ├── position.zig         # Position 类型
    └── account.zig          # Account 类型
```

---

## 相关文档

- [Story 024: Cache](../../stories/v0.5.0/STORY_024_CACHE.md)
- [v0.5.0 Overview](../../stories/v0.5.0/OVERVIEW.md)
- [MessageBus](../message-bus/README.md)

---

**版本**: v0.5.0
**状态**: 计划中
**创建时间**: 2025-12-27
