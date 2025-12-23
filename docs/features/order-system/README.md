# 订单系统 - 功能概览

> 提供完整的订单类型定义、验证和生命周期管理，支持 Hyperliquid 交易所的所有订单类型

**状态**: 🚧 开发中
**版本**: v0.2.0
**Story**: [009-order-types](../../../stories/v0.2-mvp/009-order-types.md)
**最后更新**: 2025-12-23

---

## 📋 概述

订单系统是量化交易框架的核心组件，提供统一的订单类型定义、状态管理和验证逻辑。系统设计遵循 Hyperliquid 交易所的真实 API 规范，确保与实际交易环境的完全兼容。

### 为什么需要订单系统？

在量化交易中，订单是表达交易意图的基本单元。一个完善的订单系统需要：

- **标准化的订单类型定义**：统一表示限价单、触发单等不同订单类型
- **严格的订单验证**：确保订单参数合法，避免提交无效订单
- **完整的生命周期管理**：追踪订单从创建到成交/取消的全过程
- **交易所兼容性**：与 Hyperliquid API 规范完全对齐

### 核心特性

- ✅ **订单类型支持**: Limit（限价单）和 Trigger（触发单）两大类型
- ✅ **时效管理**: 支持 Gtc（一直有效）、Ioc（立即成交或取消）、Alo（只做 Maker）
- ✅ **状态追踪**: 完整的订单状态机，包含 pending、open、filled、canceled 等状态
- ✅ **订单验证**: 内置验证逻辑，确保订单参数的合法性
- ✅ **Builder 模式**: 提供流畅的 API 构建订单
- ✅ **止盈止损**: 支持 TP/SL 触发单

---

## 🚀 快速开始

### 基本使用

```zig
const std = @import("std");
const Order = @import("core/order.zig").Order;
const OrderBuilder = @import("core/order.zig").OrderBuilder;
const OrderTypes = @import("core/order_types.zig");
const Decimal = @import("decimal.zig").Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建限价买单
    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),  // 价格
        try Decimal.fromString("1.0"),      // 数量
    );
    defer order.deinit();

    // 验证订单
    try order.validate();

    std.debug.print("订单创建成功: {s} {s} {} @ {}\n", .{
        order.side.toString(),
        order.symbol,
        order.quantity.toFloat(),
        order.price.?.toFloat(),
    });
}
```

### 使用 Builder 模式

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 使用 Builder 创建复杂订单
    var builder = try OrderBuilder.init(allocator, "BTC", .sell);
    var order = try builder
        .withOrderType(.limit)
        .withPrice(try Decimal.fromString("50000.0"))
        .withQuantity(try Decimal.fromString("0.1"))
        .withTimeInForce(.ioc)  // 立即成交或取消
        .withReduceOnly(true)    // 只减仓
        .build();
    defer order.deinit();
}
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 核心 API

### 订单类型枚举

```zig
/// 订单类型
pub const OrderType = enum {
    limit,      // 限价单 (带 TIF)
    trigger,    // 触发单 (止损/止盈)
};

/// 订单时效（Time in Force）
pub const TimeInForce = enum {
    gtc,  // Good-Til-Cancelled (一直有效直到取消)
    ioc,  // Immediate-Or-Cancel (立即成交，未成交部分取消)
    alo,  // Add-Liquidity-Only (只做 Maker，Post-only)
};

/// 订单状态
pub const OrderStatus = enum {
    pending,          // 客户端待提交
    submitted,        // 已提交
    open,             // 已挂单
    filled,           // 完全成交
    canceled,         // 已取消
    triggered,        // 已触发 (止损/止盈单)
    rejected,         // 被拒绝
    marginCanceled,   // 因保证金不足被取消
};
```

### 订单数据结构

```zig
pub const Order = struct {
    // 唯一标识
    id: ?u64,
    exchange_order_id: ?u64,
    client_order_id: []const u8,

    // 基本信息
    symbol: []const u8,
    side: OrderTypes.Side,
    order_type: OrderTypes.OrderType,
    time_in_force: OrderTypes.TimeInForce,

    // 价格和数量
    price: ?Decimal,
    quantity: Decimal,
    filled_quantity: Decimal,
    remaining_quantity: Decimal,

    // 状态
    status: OrderTypes.OrderStatus,

    // 方法
    pub fn init(...) !Order;
    pub fn validate(self: *const Order) !void;
    pub fn updateStatus(self: *Order, new_status: OrderTypes.OrderStatus) void;
    pub fn updateFill(self: *Order, filled_qty: Decimal, fill_price: Decimal, fee: Decimal) void;
};
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 始终验证订单
var order = try Order.init(allocator, "ETH", .buy, .limit, price, qty);
try order.validate();  // ✅ 验证参数

// 2. 使用 Builder 模式构建复杂订单
var builder = try OrderBuilder.init(allocator, "BTC", .sell);
var order = try builder
    .withOrderType(.limit)
    .withPrice(price)
    .withQuantity(qty)
    .withTimeInForce(.alo)  // 只做 Maker
    .build();  // ✅ 自动验证

// 3. 正确处理订单生命周期
defer order.deinit();  // ✅ 释放资源
```

### ❌ DON'T

```zig
// 1. 不要跳过验证
var order = try Order.init(allocator, "ETH", .buy, .limit, price, qty);
// ❌ 直接使用未验证的订单

// 2. 不要混淆订单类型
var order = try Order.init(allocator, "ETH", .buy, .market, price, qty);
// ❌ 市价单不应该有价格参数

// 3. 不要忘记释放资源
var order = try Order.init(allocator, "ETH", .buy, .limit, price, qty);
// ❌ 缺少 defer order.deinit()
```

---

## 🎯 使用场景

### ✅ 适用

- **限价交易**: 指定价格挂单，等待成交
- **止盈止损**: 设置触发价格的自动平仓
- **流动性提供**: 使用 Alo 时效只做 Maker
- **快速成交**: 使用 Ioc 时效立即成交或取消
- **仓位管理**: 使用 reduce_only 标志只减仓

### ❌ 不适用

- **复杂策略订单**: Iceberg（冰山单）、TWAP（时间加权平均价格）等需要额外实现
- **批量订单**: 当前版本不支持批量提交，每次只能提交一个订单
- **订单关联**: OCO（One-Cancels-Other）等关联订单需要在订单管理器层面实现

---

## 📊 订单状态流转

```
pending → submitted → open → filled ✅
                        ↓
                    canceled ✅

pending → submitted → rejected ✅

pending → submitted → open → triggered → filled ✅ (触发单)
```

### 状态说明

- **pending**: 客户端创建，尚未提交到交易所
- **submitted**: 已提交到交易所，等待确认
- **open**: 交易所已接受，订单处于活跃状态
- **filled**: 订单完全成交
- **canceled**: 订单已取消（用户主动或交易所取消）
- **triggered**: 触发单已触发（仅适用于止损/止盈单）
- **rejected**: 交易所拒绝订单
- **marginCanceled**: 因保证金不足被取消

---

## 💡 未来改进

- [ ] 支持复杂订单类型（Iceberg, TWAP, VWAP）
- [ ] 实现订单模板系统
- [ ] 支持批量订单提交和管理
- [ ] 添加订单关联功能（OCO - One-Cancels-Other）
- [ ] 实现订单持久化到数据库
- [ ] 支持多交易所订单类型映射

---

*Last updated: 2025-12-23*
