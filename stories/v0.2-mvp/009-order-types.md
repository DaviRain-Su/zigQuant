# Story: 订单类型定义

> **更新日期**: 2025-12-23
> **更新内容**: 基于 Hyperliquid 真实 API 规范更新（参考: [API Research](HYPERLIQUID_API_RESEARCH.md)）

**ID**: `STORY-009`
**版本**: `v0.2`
**创建日期**: 2025-12-23
**状态**: 📋 计划中
**优先级**: P0 (必须)
**预计工时**: 2 天

---

## 📋 需求描述

### 用户故事
作为**量化交易开发者**，我希望**有清晰的订单类型定义**，以便**表达各种交易意图并与交易所交互**。

### 背景
交易所支持多种订单类型，每种类型有不同的执行逻辑：
- **限价单（Limit Order）**: 指定价格和数量
- **市价单（Market Order）**: 立即以最优价格成交
- **止损单（Stop Order）**: 触发条件单
- **TP/SL（Take Profit / Stop Loss）**: 止盈止损单

需要定义统一的订单数据结构，支持：
- 不同交易所的订单类型映射
- 订单状态追踪
- 订单验证

### 范围
- **包含**:
  - 订单类型枚举
  - 订单数据结构
  - 订单状态枚举
  - 订单方向（买/卖）
  - 订单时效（GTC, IOC, FOK, ALO）
  - 订单验证逻辑

- **不包含**:
  - 订单执行逻辑（见 Story 010）
  - 订单持久化
  - 复杂策略订单（Iceberg, TWAP 等）

---

## 🎯 验收标准

- [ ] 所有订单类型定义完成
- [ ] 订单数据结构清晰，字段完整
- [ ] 订单状态转换逻辑正确
- [ ] 订单验证逻辑实现
- [ ] 支持 Hyperliquid 所有订单类型
- [ ] 所有测试用例通过
- [ ] 文档完整

---

## 🔧 技术设计

### 架构概览

```
src/core/
├── order.zig             # 订单核心定义
├── order_types.zig       # 订单类型
└── order_test.zig        # 测试
```

### 核心数据结构

#### 1. 订单类型

```zig
// src/core/order_types.zig

const std = @import("std");
const Decimal = @import("decimal.zig").Decimal;
const Timestamp = @import("time.zig").Timestamp;

/// 订单方向
pub const Side = enum {
    buy,
    sell,

    pub fn toString(self: Side) []const u8 {
        return switch (self) {
            .buy => "BUY",
            .sell => "SELL",
        };
    }
};

/// 订单类型
/// 基于真实 API: Hyperliquid 订单类型包括 limit 和 trigger
pub const OrderType = enum {
    limit,      // 限价单 (带 TIF)
    trigger,    // 触发单 (止损/止盈)

    pub fn toString(self: OrderType) []const u8 {
        return switch (self) {
            .limit => "LIMIT",
            .trigger => "TRIGGER",
        };
    }
};

/// Hyperliquid API 订单类型结构 (基于真实 API)
pub const HyperliquidOrderType = struct {
    limit: ?LimitOrderType = null,
    trigger: ?TriggerOrderType = null,

    pub const LimitOrderType = struct {
        tif: TimeInForce,  // Gtc, Ioc, 或 Alo
    };

    pub const TriggerOrderType = struct {
        triggerPx: []const u8,    // 触发价格
        isMarket: bool,           // 是否为市价单
        tpsl: TriggerDirection,   // 止盈或止损

        pub const TriggerDirection = enum {
            tp,  // Take Profit (止盈)
            sl,  // Stop Loss (止损)

            pub fn toString(self: TriggerDirection) []const u8 {
                return switch (self) {
                    .tp => "tp",
                    .sl => "sl",
                };
            }
        };
    };
};

/// 订单时效（Time in Force）
/// 基于真实 API: Hyperliquid 只支持 Gtc, Ioc, Alo（没有 FOK）
pub const TimeInForce = enum {
    gtc,  // Good-Til-Cancelled (一直有效直到取消)
    ioc,  // Immediate-Or-Cancel (立即成交，未成交部分取消)
    alo,  // Add-Liquidity-Only (只做 Maker，Post-only)

    pub fn toString(self: TimeInForce) []const u8 {
        return switch (self) {
            .gtc => "Gtc",
            .ioc => "Ioc",
            .alo => "Alo",
        };
    }

    /// 从字符串解析 (基于真实 API)
    pub fn fromString(s: []const u8) !TimeInForce {
        if (std.mem.eql(u8, s, "Gtc")) return .gtc;
        if (std.mem.eql(u8, s, "Ioc")) return .ioc;
        if (std.mem.eql(u8, s, "Alo")) return .alo;
        return error.InvalidTimeInForce;
    }
};

/// 订单状态 (基于真实 API)
/// Hyperliquid 订单状态包括: filled, open, canceled, triggered, rejected, marginCanceled
pub const OrderStatus = enum {
    pending,          // 客户端待提交 (本地状态)
    submitted,        // 已提交 (本地状态)
    open,             // 已挂单 (API 状态)
    filled,           // 完全成交 (API 状态)
    canceled,         // 已取消 (API 状态)
    triggered,        // 已触发 (API 状态，止损/止盈单)
    rejected,         // 被拒绝 (API 状态)
    marginCanceled,   // 因保证金不足被取消 (API 状态)

    pub fn toString(self: OrderStatus) []const u8 {
        return switch (self) {
            .pending => "PENDING",
            .submitted => "SUBMITTED",
            .open => "open",
            .filled => "filled",
            .canceled => "canceled",
            .triggered => "triggered",
            .rejected => "rejected",
            .marginCanceled => "marginCanceled",
        };
    }

    /// 从 API 字符串解析 (基于真实 API)
    pub fn fromString(s: []const u8) !OrderStatus {
        if (std.mem.eql(u8, s, "open")) return .open;
        if (std.mem.eql(u8, s, "filled")) return .filled;
        if (std.mem.eql(u8, s, "canceled")) return .canceled;
        if (std.mem.eql(u8, s, "triggered")) return .triggered;
        if (std.mem.eql(u8, s, "rejected")) return .rejected;
        if (std.mem.eql(u8, s, "marginCanceled")) return .marginCanceled;
        return error.InvalidOrderStatus;
    }

    /// 是否为终态
    pub fn isFinal(self: OrderStatus) bool {
        return switch (self) {
            .filled, .canceled, .rejected, .marginCanceled => true,
            else => false,
        };
    }

    /// 是否为活跃状态
    pub fn isActive(self: OrderStatus) bool {
        return switch (self) {
            .open, .triggered => true,
            else => false,
        };
    }
};

/// 仓位方向（对于合约）
pub const PositionSide = enum {
    long,   // 多头
    short,  // 空头
    both,   // 双向持仓模式

    pub fn toString(self: PositionSide) []const u8 {
        return switch (self) {
            .long => "LONG",
            .short => "SHORT",
            .both => "BOTH",
        };
    }
};
```

#### 2. 订单数据结构

```zig
// src/core/order.zig

const std = @import("std");
const Decimal = @import("decimal.zig").Decimal;
const Timestamp = @import("time.zig").Timestamp;
const OrderTypes = @import("order_types.zig");

pub const Order = struct {
    // 唯一标识
    id: ?u64,                    // 客户端订单 ID
    exchange_order_id: ?u64,     // 交易所订单 ID
    client_order_id: []const u8, // 客户端自定义 ID

    // 基本信息
    symbol: []const u8,          // 交易对 (e.g., "ETH")
    side: OrderTypes.Side,       // 买/卖
    order_type: OrderTypes.OrderType, // 订单类型
    time_in_force: OrderTypes.TimeInForce, // 时效

    // 价格和数量
    price: ?Decimal,             // 限价（市价单为 null）
    quantity: Decimal,           // 数量
    filled_quantity: Decimal,    // 已成交数量
    remaining_quantity: Decimal, // 剩余数量

    // 止损参数（可选）
    stop_price: ?Decimal,        // 止损价
    trigger_price: ?Decimal,     // 触发价

    // 仓位参数（合约）
    position_side: ?OrderTypes.PositionSide, // 仓位方向
    reduce_only: bool,           // 只减仓

    // 状态
    status: OrderTypes.OrderStatus,
    error_message: ?[]const u8,  // 拒绝原因

    // 时间戳
    created_at: Timestamp,       // 创建时间
    submitted_at: ?Timestamp,    // 提交时间
    updated_at: ?Timestamp,      // 更新时间
    filled_at: ?Timestamp,       // 完全成交时间

    // 成交信息
    avg_fill_price: ?Decimal,    // 平均成交价
    total_fee: Decimal,          // 总手续费
    fee_currency: []const u8,    // 手续费币种

    // 元数据
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        symbol: []const u8,
        side: OrderTypes.Side,
        order_type: OrderTypes.OrderType,
        price: ?Decimal,
        quantity: Decimal,
    ) !Order {
        return .{
            .id = null,
            .exchange_order_id = null,
            .client_order_id = try generateClientOrderId(allocator),
            .symbol = try allocator.dupe(u8, symbol),
            .side = side,
            .order_type = order_type,
            .time_in_force = .gtc, // 默认 GTC
            .price = price,
            .quantity = quantity,
            .filled_quantity = Decimal.ZERO,
            .remaining_quantity = quantity,
            .stop_price = null,
            .trigger_price = null,
            .position_side = null,
            .reduce_only = false,
            .status = .pending,
            .error_message = null,
            .created_at = Timestamp.now(),
            .submitted_at = null,
            .updated_at = null,
            .filled_at = null,
            .avg_fill_price = null,
            .total_fee = Decimal.ZERO,
            .fee_currency = "USD",
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Order) void {
        self.allocator.free(self.symbol);
        self.allocator.free(self.client_order_id);
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// 验证订单参数
    pub fn validate(self: *const Order) !void {
        // 数量必须大于 0
        if (!self.quantity.isPositive()) {
            return error.InvalidQuantity;
        }

        // 限价单必须有价格
        if (self.order_type == .limit and self.price == null) {
            return error.MissingPrice;
        }

        // 市价单不应有价格
        if (self.order_type == .market and self.price != null) {
            return error.UnexpectedPrice;
        }

        // 止损单必须有触发价
        if ((self.order_type == .stop_limit or self.order_type == .stop_market) and
            self.stop_price == null)
        {
            return error.MissingStopPrice;
        }

        // 符号不能为空
        if (self.symbol.len == 0) {
            return error.EmptySymbol;
        }
    }

    /// 更新状态
    pub fn updateStatus(self: *Order, new_status: OrderTypes.OrderStatus) void {
        self.status = new_status;
        self.updated_at = Timestamp.now();

        if (new_status == .filled) {
            self.filled_at = Timestamp.now();
            self.filled_quantity = self.quantity;
            self.remaining_quantity = Decimal.ZERO;
        }
    }

    /// 更新成交信息
    pub fn updateFill(
        self: *Order,
        filled_qty: Decimal,
        fill_price: Decimal,
        fee: Decimal,
    ) void {
        self.filled_quantity = self.filled_quantity.add(filled_qty);
        self.remaining_quantity = self.quantity.sub(self.filled_quantity);

        // 更新平均成交价
        if (self.avg_fill_price) |avg| {
            const total_cost = avg.mul(self.filled_quantity.sub(filled_qty));
            const new_cost = fill_price.mul(filled_qty);
            self.avg_fill_price = total_cost.add(new_cost).div(self.filled_quantity) catch null;
        } else {
            self.avg_fill_price = fill_price;
        }

        self.total_fee = self.total_fee.add(fee);
        self.updated_at = Timestamp.now();

        // 更新状态
        if (self.remaining_quantity.isZero()) {
            self.updateStatus(.filled);
        } else {
            self.updateStatus(.partially_filled);
        }
    }

    /// 计算成交百分比
    pub fn getFillPercentage(self: *const Order) Decimal {
        if (self.quantity.isZero()) return Decimal.ZERO;
        return self.filled_quantity.div(self.quantity) catch Decimal.ZERO;
    }

    /// 是否完全成交
    pub fn isFilled(self: *const Order) bool {
        return self.status == .filled;
    }

    /// 是否可取消
    pub fn isCancellable(self: *const Order) bool {
        return self.status.isActive();
    }

    // 辅助函数
    fn generateClientOrderId(allocator: std.mem.Allocator) ![]u8 {
        const timestamp = std.time.milliTimestamp();
        const random = std.crypto.random.int(u32);
        return std.fmt.allocPrint(allocator, "CLIENT_{d}_{d}", .{ timestamp, random });
    }
};

/// 订单构建器（Builder 模式）
pub const OrderBuilder = struct {
    order: Order,

    pub fn init(
        allocator: std.mem.Allocator,
        symbol: []const u8,
        side: OrderTypes.Side,
    ) !OrderBuilder {
        return .{
            .order = try Order.init(
                allocator,
                symbol,
                side,
                .limit, // 默认限价单
                null,
                Decimal.ZERO,
            ),
        };
    }

    pub fn withOrderType(self: *OrderBuilder, order_type: OrderTypes.OrderType) *OrderBuilder {
        self.order.order_type = order_type;
        return self;
    }

    pub fn withPrice(self: *OrderBuilder, price: Decimal) *OrderBuilder {
        self.order.price = price;
        return self;
    }

    pub fn withQuantity(self: *OrderBuilder, quantity: Decimal) *OrderBuilder {
        self.order.quantity = quantity;
        self.order.remaining_quantity = quantity;
        return self;
    }

    pub fn withTimeInForce(self: *OrderBuilder, tif: OrderTypes.TimeInForce) *OrderBuilder {
        self.order.time_in_force = tif;
        return self;
    }

    pub fn withStopPrice(self: *OrderBuilder, stop_price: Decimal) *OrderBuilder {
        self.order.stop_price = stop_price;
        return self;
    }

    pub fn withReduceOnly(self: *OrderBuilder, reduce_only: bool) *OrderBuilder {
        self.order.reduce_only = reduce_only;
        return self;
    }

    pub fn build(self: *OrderBuilder) !Order {
        try self.order.validate();
        return self.order;
    }
};
```

---

## 📝 任务分解

### Phase 1: 类型定义 📋
- [ ] 任务 1.1: 定义 Side 枚举
- [ ] 任务 1.2: 定义 OrderType 枚举
- [ ] 任务 1.3: 定义 TimeInForce 枚举
- [ ] 任务 1.4: 定义 OrderStatus 枚举
- [ ] 任务 1.5: 定义 PositionSide 枚举

### Phase 2: 订单数据结构 📋
- [ ] 任务 2.1: 定义 Order 结构体
- [ ] 任务 2.2: 实现 Order.init
- [ ] 任务 2.3: 实现订单验证逻辑
- [ ] 任务 2.4: 实现状态更新方法
- [ ] 任务 2.5: 实现成交更新方法

### Phase 3: 辅助工具 📋
- [ ] 任务 3.1: 实现 OrderBuilder
- [ ] 任务 3.2: 实现 Client Order ID 生成
- [ ] 任务 3.3: 实现订单序列化/反序列化（JSON）

### Phase 4: 测试与文档 📋
- [ ] 任务 4.1: 编写单元测试
- [ ] 任务 4.2: 编写验证测试
- [ ] 任务 4.3: 更新文档
- [ ] 任务 4.4: 代码审查

---

## 🧪 测试策略

### 单元测试

```zig
test "Order: create limit order" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order.deinit();

    try testing.expectEqual(.buy, order.side);
    try testing.expectEqual(.limit, order.order_type);
    try testing.expect(order.price.?.toFloat() == 2000.0);
}

test "Order: validation" {
    const allocator = testing.allocator;

    // 无效数量
    var bad_order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        Decimal.ZERO, // ❌ 数量为 0
    );
    defer bad_order.deinit();

    try testing.expectError(error.InvalidQuantity, bad_order.validate());
}

test "Order: fill update" {
    const allocator = testing.allocator;

    var order = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("10.0"),
    );
    defer order.deinit();

    // 部分成交
    order.updateFill(
        try Decimal.fromString("5.0"),
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );

    try testing.expect(order.filled_quantity.toFloat() == 5.0);
    try testing.expect(order.remaining_quantity.toFloat() == 5.0);
    try testing.expectEqual(.partially_filled, order.status);

    // 完全成交
    order.updateFill(
        try Decimal.fromString("5.0"),
        try Decimal.fromString("2001.0"),
        try Decimal.fromString("1.0"),
    );

    try testing.expect(order.isFilled());
    try testing.expectEqual(.filled, order.status);
}

test "OrderBuilder: fluent API" {
    const allocator = testing.allocator;

    var builder = try OrderBuilder.init(allocator, "ETH", .buy);
    const order = try builder
        .withOrderType(.limit)
        .withPrice(try Decimal.fromString("2000.0"))
        .withQuantity(try Decimal.fromString("1.0"))
        .withTimeInForce(.ioc)
        .build();
    defer order.deinit();

    try testing.expectEqual(.ioc, order.time_in_force);
}
```

---

## 📚 相关文档

### 设计文档
- [ ] `docs/features/order-system/README.md` - 订单系统概览
- [ ] `docs/features/order-system/order-types.md` - 订单类型详解
- [ ] `docs/features/order-system/order-lifecycle.md` - 订单生命周期

### 参考资料
- [Hyperliquid Order Types](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/order-types)
- [Binance Order Types](https://www.binance.com/en/support/faq/understanding-the-different-order-types-360033779452)

---

## 🔗 依赖关系

### 前置条件
- [x] Story 001: Decimal 类型
- [x] Story 002: Time Utils

### 被依赖
- Story 010: 订单管理器
- Story 011: 仓位追踪器
- 未来: 策略引擎

---

## ⚠️ 风险与挑战

### 已识别风险
1. **订单类型兼容性**: 不同交易所订单类型不同
   - **影响**: 中
   - **缓解措施**: 定义通用订单类型，交易所适配层映射

### 技术挑战
1. **状态转换复杂性**: 订单状态转换逻辑复杂
   - **解决方案**: 使用状态机模式，明确定义所有转换

---

## 📊 进度追踪

### 时间线
- 开始日期: 待定
- 预计完成: 待定

---

## ✅ 验收检查清单

- [ ] 所有验收标准已满足
- [ ] 所有任务已完成
- [ ] 单元测试通过
- [ ] 文档已更新
- [ ] 代码已审查

---

## 📸 演示

### 使用示例

```zig
const std = @import("std");
const Order = @import("core/order.zig").Order;
const OrderBuilder = @import("core/order.zig").OrderBuilder;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 方式 1: 直接创建
    var order1 = try Order.init(
        allocator,
        "ETH",
        .buy,
        .limit,
        try Decimal.fromString("2000.0"),
        try Decimal.fromString("1.0"),
    );
    defer order1.deinit();

    // 方式 2: 使用 Builder
    var builder = try OrderBuilder.init(allocator, "BTC", .sell);
    var order2 = try builder
        .withOrderType(.limit)
        .withPrice(try Decimal.fromString("50000.0"))
        .withQuantity(try Decimal.fromString("0.1"))
        .withTimeInForce(.ioc)
        .withReduceOnly(true)
        .build();
    defer order2.deinit();

    std.debug.print("Order 1: {s} {s} {} @ {}\n", .{
        order1.side.toString(),
        order1.symbol,
        order1.quantity.toFloat(),
        order1.price.?.toFloat(),
    });
}
```

---

## 💡 未来改进

- [ ] 支持复杂订单（Iceberg, TWAP, VWAP）
- [ ] 实现订单模板
- [ ] 支持批量订单
- [ ] 添加订单关联（OCO - One-Cancels-Other）
- [ ] 实现订单持久化

---

*Last updated: 2025-12-23*
*Assignee: TBD*
*Status: 📋 Planning*
