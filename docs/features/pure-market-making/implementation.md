# Pure Market Making - 实现细节

> 深入了解内部实现

**最后更新**: 2025-12-27

---

## 内部表示

### 数据结构

```zig
pub const PureMarketMaking = struct {
    // 配置和分配器
    allocator: Allocator,
    config: PureMMConfig,

    // 状态
    current_position: Decimal,           // 当前持仓
    active_bids: ArrayList(OrderInfo),   // 活跃买单
    active_asks: ArrayList(OrderInfo),   // 活跃卖单
    last_mid_price: ?Decimal,            // 上次中间价
    last_update_tick: u64,               // 上次更新 tick

    // 统计
    total_trades: u64,
    total_volume: Decimal,
    realized_pnl: Decimal,

    // 依赖注入
    data_provider: *IDataProvider,
    executor: *IExecutionClient,
};
```

---

## 核心算法

### 1. 中间价计算

```zig
fn getMidPrice(self: *Self) ?Decimal {
    const quote = self.data_provider.getQuote(self.config.symbol) orelse return null;

    // mid = (bid + ask) / 2
    return quote.bid.add(quote.ask).div(Decimal.fromInt(2));
}
```

**说明**: 使用最佳买卖价的算术平均值作为中间价

---

### 2. 报价刷新判断

```zig
fn shouldRefreshQuotes(self: *Self, current_mid: Decimal) bool {
    const last_mid = self.last_mid_price orelse return true;  // 首次必须更新

    // 计算变化幅度 (basis points)
    // change_bps = |current - last| / last * 10000
    const change = current_mid.sub(last_mid).abs();
    const change_bps = change.div(last_mid).mul(Decimal.fromInt(10000));

    return change_bps.toFloat() >= @as(f64, @floatFromInt(self.config.min_refresh_bps));
}
```

**复杂度**: O(1)

---

### 3. 多层级报价计算

```zig
fn placeQuotes(self: *Self, mid: Decimal) !void {
    // 计算半价差
    // half_spread = mid * (spread_bps / 20000)
    const half_spread = mid.mul(
        Decimal.fromFloat(@as(f64, @floatFromInt(self.config.spread_bps)) / 20000.0)
    );

    // 多层级报价
    for (0..self.config.order_levels) |i| {
        // 层级偏移 = mid * (i * level_spread_bps / 10000)
        const level_offset = if (i == 0)
            Decimal.zero
        else
            mid.mul(Decimal.fromFloat(
                @as(f64, @floatFromInt(i * self.config.level_spread_bps)) / 10000.0
            ));

        // 买单价格 = mid - half_spread - level_offset
        const bid_price = mid.sub(half_spread).sub(level_offset);

        // 卖单价格 = mid + half_spread + level_offset
        const ask_price = mid.add(half_spread).add(level_offset);

        try self.placeBid(bid_price, self.config.order_amount);
        try self.placeAsk(ask_price, self.config.order_amount);
    }
}
```

**示例** (mid=2000, spread=10bps, levels=3, level_spread=5bps):

| 层级 | 买价 | 卖价 |
|------|------|------|
| 0 | 1999.0 | 2001.0 |
| 1 | 1998.0 | 2002.0 |
| 2 | 1997.0 | 2003.0 |

---

### 4. 仓位限制检查

```zig
fn placeQuotes(self: *Self, mid: Decimal) !void {
    // 检查仓位限制
    if (self.current_position.abs().compare(self.config.max_position) == .gt) {
        std.log.warn("[PureMM] Max position reached, skipping quotes", .{});
        return;
    }

    // 根据仓位方向决定报价方向
    if (self.config.dual_side or self.current_position.toFloat() < 0) {
        // 有空仓或启用双边：放买单
        try self.placeBid(bid_price, amount);
    }

    if (self.config.dual_side or self.current_position.toFloat() > 0) {
        // 有多仓或启用双边：放卖单
        try self.placeAsk(ask_price, amount);
    }
}
```

---

### 5. 成交处理

```zig
pub fn onFill(self: *Self, fill: OrderFill) void {
    // 更新仓位
    if (fill.side == .buy) {
        self.current_position = self.current_position.add(fill.quantity);
    } else {
        self.current_position = self.current_position.sub(fill.quantity);
    }

    // 更新统计
    self.total_trades += 1;
    self.total_volume = self.total_volume.add(fill.quantity.mul(fill.price));

    // 计算已实现盈亏 (简化版)
    // 实际应跟踪平均持仓成本
}
```

---

## 性能优化

### 1. 批量取消订单

```zig
fn cancelAllOrders(self: *Self) !void {
    // 取消所有买单
    for (self.active_bids.items) |order| {
        self.executor.cancelOrder(order.order_id) catch |err| {
            std.log.warn("Failed to cancel bid {}: {}", .{ order.order_id, err });
        };
    }
    self.active_bids.clearRetainingCapacity();

    // 取消所有卖单
    for (self.active_asks.items) |order| {
        self.executor.cancelOrder(order.order_id) catch |err| {
            std.log.warn("Failed to cancel ask {}: {}", .{ order.order_id, err });
        };
    }
    self.active_asks.clearRetainingCapacity();
}
```

**优化点**: 使用 `clearRetainingCapacity` 避免重复内存分配

### 2. 避免不必要的更新

```zig
fn onTickImpl(...) !void {
    // 快速路径：价格未变化足够多则跳过
    if (!self.shouldRefreshQuotes(mid)) {
        return;
    }
    // ...
}
```

---

## 内存管理

### 分配策略

| 组件 | 分配时机 | 释放时机 |
|------|----------|----------|
| PureMarketMaking | init() | deinit() |
| active_bids | init() | deinit() |
| active_asks | init() | deinit() |
| OrderInfo | placeOrder() | cancelOrder() |

### 所有权模型

```
PureMarketMaking (拥有)
  ├─ config: PureMMConfig (值类型)
  ├─ active_bids: ArrayList (拥有)
  ├─ active_asks: ArrayList (拥有)
  ├─ data_provider: *IDataProvider (借用)
  └─ executor: *IExecutionClient (借用)
```

---

## 边界情况

### 情况 1: 无行情数据

```zig
fn onTickImpl(...) !void {
    const mid = self.getMidPrice() orelse {
        // 无行情，跳过本次 tick
        return;
    };
    // ...
}
```

### 情况 2: 下单失败

```zig
fn placeBid(self: *Self, price: Decimal, amount: Decimal) !void {
    const order = self.executor.submitOrder(...) catch |err| {
        std.log.err("[PureMM] Failed to place bid: {}", .{err});
        return err;
    };
    // 只有成功才添加到活跃列表
    try self.active_bids.append(...);
}
```

### 情况 3: 仓位溢出

```zig
if (self.current_position.abs().compare(self.config.max_position) == .gt) {
    std.log.warn("[PureMM] Max position reached", .{});
    // 只在有利方向报价
    if (self.current_position.toFloat() > 0) {
        // 只放卖单以减少仓位
    } else {
        // 只放买单以减少仓位
    }
}
```

---

## onTick 流程图

```
onTick(tick, timestamp)
    │
    ▼
┌─────────────────┐
│ 获取 mid price  │
└────────┬────────┘
         │
    null?──────────► return (无行情)
         │
         ▼
┌─────────────────┐
│ 检查是否刷新    │
└────────┬────────┘
         │
    不刷新?─────────► return (价格变化不足)
         │
         ▼
┌─────────────────┐
│ 取消所有旧订单  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 检查仓位限制    │
└────────┬────────┘
         │
    超限?──────────► log.warn, 单边报价
         │
         ▼
┌─────────────────┐
│ 计算新报价      │
│ (多层级)        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 下新订单        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 更新状态        │
└─────────────────┘
```

---

*完整实现请参考: `src/market_making/pure_mm.zig`*
