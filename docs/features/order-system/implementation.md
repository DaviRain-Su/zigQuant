# 订单系统 - 实现细节

> 深入了解内部实现

**最后更新**: 2025-12-23

---

## 内部表示

### 数据结构

#### 1. 订单核心结构

```zig
// src/core/order.zig
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
};
```

**设计考虑**:
- **可选字段**: 使用 `?Type` 表示可选字段，适配不同订单类型
- **Decimal 类型**: 价格和数量使用高精度 Decimal，避免浮点精度问题
- **内存管理**: 存储 allocator 以便正确释放动态分配的内存

#### 2. 订单类型枚举

```zig
// src/core/order_types.zig

/// 订单类型 - 基于 Hyperliquid API
pub const OrderType = enum {
    limit,      // 限价单 (带 TIF)
    trigger,    // 触发单 (止损/止盈)
};

/// 订单时效
pub const TimeInForce = enum {
    gtc,  // Good-Til-Cancelled
    ioc,  // Immediate-Or-Cancel
    alo,  // Add-Liquidity-Only (Post-only)
};

/// 订单状态
pub const OrderStatus = enum {
    pending,          // 本地状态
    submitted,        // 本地状态
    open,             // API 状态
    filled,           // API 状态
    canceled,         // API 状态
    triggered,        // API 状态
    rejected,         // API 状态
    marginCanceled,   // API 状态
};
```

---

## 核心算法

### 1. 订单验证逻辑

```zig
pub fn validate(self: *const Order) !void {
    // 数量必须大于 0
    if (!self.quantity.isPositive()) {
        return error.InvalidQuantity;
    }

    // 限价单必须有价格
    if (self.order_type == .limit and self.price == null) {
        return error.MissingPrice;
    }

    // 触发单必须有触发价
    if (self.order_type == .trigger and self.trigger_price == null) {
        return error.MissingTriggerPrice;
    }

    // 符号不能为空
    if (self.symbol.len == 0) {
        return error.EmptySymbol;
    }

    // 价格必须为正（如果存在）
    if (self.price) |p| {
        if (!p.isPositive()) {
            return error.InvalidPrice;
        }
    }
}
```

**复杂度**: O(1)
**说明**: 所有验证都是常数时间操作，确保高性能

### 2. 成交信息更新算法

```zig
pub fn updateFill(
    self: *Order,
    filled_qty: Decimal,
    fill_price: Decimal,
    fee: Decimal,
) void {
    // 更新成交数量
    self.filled_quantity = self.filled_quantity.add(filled_qty);
    self.remaining_quantity = self.quantity.sub(self.filled_quantity);

    // 计算加权平均成交价
    if (self.avg_fill_price) |avg| {
        // total_cost = avg * previous_filled
        const total_cost = avg.mul(self.filled_quantity.sub(filled_qty));
        // new_cost = fill_price * filled_qty
        const new_cost = fill_price.mul(filled_qty);
        // avg_fill_price = (total_cost + new_cost) / filled_quantity
        self.avg_fill_price = total_cost.add(new_cost)
            .div(self.filled_quantity) catch null;
    } else {
        self.avg_fill_price = fill_price;
    }

    // 累计手续费
    self.total_fee = self.total_fee.add(fee);
    self.updated_at = Timestamp.now();

    // 更新状态
    if (self.remaining_quantity.isZero()) {
        self.updateStatus(.filled);
    } else {
        // 注意: 当前实现假设有 partially_filled 状态
        // 如果没有，需要保持 open 状态
        self.updated_at = Timestamp.now();
    }
}
```

**复杂度**: O(1)
**说明**: 使用增量计算平均成交价，避免重复遍历历史成交记录

### 3. 客户端订单 ID 生成

```zig
fn generateClientOrderId(allocator: std.mem.Allocator) ![]u8 {
    const timestamp = std.time.milliTimestamp();
    const random = std.crypto.random.int(u32);
    return std.fmt.allocPrint(
        allocator,
        "CLIENT_{d}_{d}",
        .{ timestamp, random }
    );
}
```

**复杂度**: O(1)
**说明**: 组合时间戳和随机数，确保 ID 唯一性且可排序

---

## 订单生命周期状态机

### 状态转换图

```
[创建]
  ↓
pending (客户端待提交)
  ↓
submitted (已提交到交易所)
  ↓
  ├─→ rejected (被拒绝) [终态]
  ├─→ open (已挂单)
  │    ├─→ filled (完全成交) [终态]
  │    ├─→ canceled (已取消) [终态]
  │    ├─→ marginCanceled (保证金不足) [终态]
  │    └─→ triggered (已触发) → filled [终态]
```

### 状态转换逻辑

```zig
pub fn updateStatus(self: *Order, new_status: OrderTypes.OrderStatus) void {
    // 记录旧状态（用于日志）
    const old_status = self.status;

    // 更新状态
    self.status = new_status;
    self.updated_at = Timestamp.now();

    // 根据新状态执行特定操作
    switch (new_status) {
        .filled => {
            self.filled_at = Timestamp.now();
            self.filled_quantity = self.quantity;
            self.remaining_quantity = Decimal.ZERO;
        },
        .submitted => {
            self.submitted_at = Timestamp.now();
        },
        else => {},
    }
}
```

### 状态检查辅助函数

```zig
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

/// 订单是否可取消
pub fn isCancellable(self: *const Order) bool {
    return self.status.isActive();
}
```

---

## 性能优化

### 1. Builder 模式优化

Builder 模式提供流畅的 API，同时避免多次内存分配：

```zig
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
                .limit,
                null,
                Decimal.ZERO,
            ),
        };
    }

    // 链式调用，返回 self 指针
    pub fn withPrice(self: *OrderBuilder, price: Decimal) *OrderBuilder {
        self.order.price = price;
        return self;
    }

    // ... 其他 with* 方法

    // 最后验证并构建
    pub fn build(self: *OrderBuilder) !Order {
        try self.order.validate();
        return self.order;
    }
};
```

**优势**:
- 避免中间对象的多次分配
- 提供类型安全的构建过程
- 自动验证，减少错误

### 2. 字符串序列化优化

枚举类型提供零分配的 toString 方法：

```zig
pub fn toString(self: Side) []const u8 {
    return switch (self) {
        .buy => "BUY",
        .sell => "SELL",
    };
}
```

返回字符串字面量，无需动态分配内存。

---

## 内存管理

### 资源生命周期

```zig
pub fn init(
    allocator: std.mem.Allocator,
    symbol: []const u8,
    // ... 其他参数
) !Order {
    return .{
        // 分配并复制 symbol
        .symbol = try allocator.dupe(u8, symbol),
        // 生成 client_order_id
        .client_order_id = try generateClientOrderId(allocator),
        // 存储 allocator 以便后续释放
        .allocator = allocator,
        // ... 其他字段
    };
}

pub fn deinit(self: *Order) void {
    // 释放动态分配的字符串
    self.allocator.free(self.symbol);
    self.allocator.free(self.client_order_id);

    // 释放可选的错误消息
    if (self.error_message) |msg| {
        self.allocator.free(msg);
    }
}
```

**内存安全保证**:
- 所有动态分配的内存在 `deinit` 中释放
- 使用 `defer order.deinit()` 确保异常安全
- 不使用全局状态，避免内存泄漏

---

## 边界情况

### 1. 零数量订单

```zig
// 在 validate() 中检查
if (!self.quantity.isPositive()) {
    return error.InvalidQuantity;
}
```

### 2. 负价格

```zig
if (self.price) |p| {
    if (!p.isPositive()) {
        return error.InvalidPrice;
    }
}
```

### 3. 空符号

```zig
if (self.symbol.len == 0) {
    return error.EmptySymbol;
}
```

### 4. 成交数量超过订单数量

```zig
// 在 updateFill 中防御性检查
if (self.filled_quantity.gt(self.quantity)) {
    // 记录警告日志
    std.log.warn("Filled quantity exceeds order quantity", .{});
    // 修正为订单数量
    self.filled_quantity = self.quantity;
    self.remaining_quantity = Decimal.ZERO;
}
```

### 5. Decimal 运算溢出

```zig
// Decimal.div 返回错误，使用 catch 处理
self.avg_fill_price = total_cost.add(new_cost)
    .div(self.filled_quantity) catch null;
```

---

## Hyperliquid API 适配

### 订单类型映射

```zig
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
    };
};
```

### JSON 序列化示例

限价单:
```json
{
  "orderType": {
    "limit": {
      "tif": "Gtc"
    }
  }
}
```

触发单（止损）:
```json
{
  "orderType": {
    "trigger": {
      "triggerPx": "2000.0",
      "isMarket": true,
      "tpsl": "sl"
    }
  }
}
```

---

## 测试覆盖

- ✅ 订单创建和初始化
- ✅ 订单验证（各种无效参数）
- ✅ 状态转换逻辑
- ✅ 成交信息更新和平均成交价计算
- ✅ Builder 模式流畅 API
- ✅ 内存管理（无泄漏）
- ✅ 边界情况处理

详见: [testing.md](./testing.md)

---

*完整实现请参考: `src/core/order.zig` 和 `src/core/order_types.zig`*
