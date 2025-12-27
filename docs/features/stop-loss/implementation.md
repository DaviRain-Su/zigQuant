# StopLoss - 实现细节

> 深入了解止损系统的内部实现

**最后更新**: 2025-12-27

---

## 内部表示

### 数据结构

```zig
pub const StopLossManager = struct {
    allocator: Allocator,
    positions: *PositionTracker,
    execution: *ExecutionEngine,
    stops: std.StringHashMap(StopConfig),
    mutex: std.Thread.Mutex,

    // 统计
    stops_triggered: u64,
    takes_triggered: u64,
    trailing_updates: u64,
};

pub const StopConfig = struct {
    // 固定止损
    stop_loss: ?Decimal = null,
    stop_loss_type: StopType = .market,

    // 固定止盈
    take_profit: ?Decimal = null,
    take_profit_type: StopType = .market,

    // 跟踪止损
    trailing_stop_pct: ?f64 = null,
    trailing_stop_distance: ?Decimal = null,
    trailing_stop_active: bool = false,
    trailing_stop_high: ?Decimal = null,  // 多头追踪最高价
    trailing_stop_low: ?Decimal = null,   // 空头追踪最低价

    // 部分平仓
    partial_close_pct: f64 = 1.0,

    // 时间止损
    time_stop: ?i64 = null,
    time_stop_action: TimeStopAction = .close,

    // 元数据
    created_at: i64 = 0,
    last_updated: i64 = 0,
};
```

---

## 核心算法

### 止损触发判断

```zig
/// 判断是否触发止损 (多头/空头逻辑不同)
fn shouldTriggerStopLoss(self: *Self, pos: Position, current: Decimal, stop: Decimal) bool {
    _ = self;
    return switch (pos.side) {
        // 多头: 当前价格 <= 止损价
        .long => current.cmp(stop) != .gt,
        // 空头: 当前价格 >= 止损价
        .short => current.cmp(stop) != .lt,
    };
}

/// 判断是否触发止盈 (多头/空头逻辑不同)
fn shouldTriggerTakeProfit(self: *Self, pos: Position, current: Decimal, take: Decimal) bool {
    _ = self;
    return switch (pos.side) {
        // 多头: 当前价格 >= 止盈价
        .long => current.cmp(take) != .lt,
        // 空头: 当前价格 <= 止盈价
        .short => current.cmp(take) != .gt,
    };
}
```

**说明**: 使用 `cmp` 比较确保 Decimal 精度，避免浮点数比较误差。

### 跟踪止损更新

```zig
/// 更新跟踪止损追踪价格
fn updateTrailingStop(self: *Self, pos: Position, current: Decimal, config: *StopConfig) void {
    switch (pos.side) {
        .long => {
            // 多头: 追踪最高价
            if (config.trailing_stop_high) |high| {
                if (current.cmp(high) == .gt) {
                    config.trailing_stop_high = current;
                    self.trailing_updates += 1;
                }
            } else {
                config.trailing_stop_high = current;
            }
        },
        .short => {
            // 空头: 追踪最低价
            if (config.trailing_stop_low) |low| {
                if (current.cmp(low) == .lt) {
                    config.trailing_stop_low = current;
                    self.trailing_updates += 1;
                }
            } else {
                config.trailing_stop_low = current;
            }
        },
    }
}

/// 计算跟踪止损触发价格
fn calculateTrailingStopPrice(pos: Position, config: StopConfig) ?Decimal {
    switch (pos.side) {
        .long => {
            const high = config.trailing_stop_high orelse return null;
            if (config.trailing_stop_pct) |pct| {
                // 百分比模式: 最高价 * (1 - 百分比)
                return high.mul(Decimal.fromFloat(1.0 - pct));
            } else if (config.trailing_stop_distance) |dist| {
                // 固定距离模式: 最高价 - 距离
                return high.sub(dist);
            }
        },
        .short => {
            const low = config.trailing_stop_low orelse return null;
            if (config.trailing_stop_pct) |pct| {
                // 百分比模式: 最低价 * (1 + 百分比)
                return low.mul(Decimal.fromFloat(1.0 + pct));
            } else if (config.trailing_stop_distance) |dist| {
                // 固定距离模式: 最低价 + 距离
                return low.add(dist);
            }
        },
    }
    return null;
}
```

**复杂度**: O(1)
**说明**: 跟踪止损只会向有利方向移动，永不回退

### 检查和执行流程

```zig
pub fn checkAndExecute(self: *Self, symbol: []const u8, current_price: Decimal) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const positions = self.positions.getBySymbol(symbol);

    for (positions) |pos| {
        const config = self.stops.get(pos.id) orelse continue;

        // 1. 检查固定止损
        if (config.stop_loss) |sl| {
            if (self.shouldTriggerStopLoss(pos, current_price, sl)) {
                try self.executeStop(pos, config, .stop_loss);
                self.stops_triggered += 1;
                continue; // 已平仓，跳过后续检查
            }
        }

        // 2. 检查固定止盈
        if (config.take_profit) |tp| {
            if (self.shouldTriggerTakeProfit(pos, current_price, tp)) {
                try self.executeStop(pos, config, .take_profit);
                self.takes_triggered += 1;
                continue;
            }
        }

        // 3. 更新并检查跟踪止损
        if (config.trailing_stop_active) {
            // 先更新追踪价格
            self.updateTrailingStop(pos, current_price, self.stops.getPtr(pos.id).?);

            // 再检查是否触发
            if (self.calculateTrailingStopPrice(pos, config)) |stop_price| {
                if (self.shouldTriggerStopLoss(pos, current_price, stop_price)) {
                    try self.executeStop(pos, config, .trailing_stop);
                    self.stops_triggered += 1;
                    continue;
                }
            }
        }

        // 4. 检查时间止损
        if (config.time_stop) |ts| {
            if (std.time.timestamp() >= ts) {
                try self.executeTimeStop(pos, config);
            }
        }
    }
}
```

### 执行平仓

```zig
fn executeStop(self: *Self, pos: Position, config: StopConfig, trigger: StopTrigger) !void {
    // 计算平仓数量
    const close_qty = pos.quantity.mul(Decimal.fromFloat(config.partial_close_pct));

    std.log.warn("[STOP] Triggered {s} for {s}, closing {d}", .{
        @tagName(trigger),
        pos.id,
        close_qty.toFloat(),
    });

    // 确定订单类型
    const order_type: OrderType = switch (trigger) {
        .stop_loss => if (config.stop_loss_type == .market) .market else .limit,
        .take_profit => if (config.take_profit_type == .market) .market else .limit,
        .trailing_stop => .market,
    };

    // 确定限价
    const price: ?Decimal = switch (trigger) {
        .stop_loss => config.stop_loss,
        .take_profit => config.take_profit,
        .trailing_stop => null, // 跟踪止损使用市价
    };

    // 构建订单
    const order = OrderRequest{
        .symbol = pos.symbol,
        .side = if (pos.side == .long) .sell else .buy,
        .order_type = order_type,
        .quantity = close_qty,
        .price = price,
        .time_in_force = .ioc, // 立即执行或取消
    };

    // 提交订单
    try self.execution.submitOrder(order);

    // 如果是全平，移除止损配置
    if (config.partial_close_pct >= 1.0) {
        _ = self.stops.remove(pos.id);
    }
}
```

---

## 性能优化

### 1. 互斥锁粒度

使用单个互斥锁保护整个检查过程：

```zig
self.mutex.lock();
defer self.mutex.unlock();
// 所有检查操作
```

**权衡**: 简单但可能成为瓶颈。未来可考虑读写锁或分片锁。

### 2. 按品种索引

只检查特定品种的仓位：

```zig
const positions = self.positions.getBySymbol(symbol);
```

避免遍历所有仓位。

### 3. 短路检查

一旦触发某个止损，立即跳过该仓位的后续检查：

```zig
if (triggered) {
    continue; // 跳过止盈和跟踪止损检查
}
```

---

## 内存管理

### 分配策略

```zig
pub fn init(allocator: Allocator, positions: *PositionTracker, execution: *ExecutionEngine) StopLossManager {
    return .{
        .allocator = allocator,
        .positions = positions,
        .execution = execution,
        .stops = std.StringHashMap(StopConfig).init(allocator),
        .mutex = .{},
        .stops_triggered = 0,
        .takes_triggered = 0,
        .trailing_updates = 0,
    };
}

pub fn deinit(self: *StopLossManager) void {
    self.stops.deinit();
}
```

### 内存增长

- `stops` HashMap 随活跃仓位数增长
- 每个 StopConfig 约 100 字节
- 1000 个仓位约需 100KB

---

## 边界情况

### 情况 1: 仓位不存在

```zig
pub fn setStopLoss(self: *Self, position_id: []const u8, price: Decimal, stop_type: StopType) !void {
    const position = self.positions.get(position_id) orelse {
        return error.PositionNotFound;
    };
    // ...
}
```

### 情况 2: 无效止损价格

```zig
// 验证止损价格对于多头/空头是否合理
if (position.side == .long and price.cmp(position.entry_price) != .lt) {
    return error.InvalidStopLoss; // 多头止损必须低于入场价
}
if (position.side == .short and price.cmp(position.entry_price) != .gt) {
    return error.InvalidStopLoss; // 空头止损必须高于入场价
}
```

### 情况 3: 跟踪止损百分比无效

```zig
pub fn setTrailingStopPct(self: *Self, position_id: []const u8, trail_pct: f64) !void {
    if (trail_pct <= 0 or trail_pct >= 1) {
        return error.InvalidTrailingPercent;
    }
    // ...
}
```

### 情况 4: 价格跳空

如果价格跳过止损价直接到更差的价格：

```zig
// 使用 != .gt 而不是 == .lt 确保跳空情况也能触发
current.cmp(stop) != .gt  // 包括 < 和 = 的情况
```

---

## 与其他模块集成

### 与策略集成

```zig
pub const TrendStrategy = struct {
    stop_manager: *StopLossManager,

    pub fn onPositionOpened(self: *Self, position: Position) void {
        const entry = position.entry_price;

        // 自动设置 2% 止损，6% 止盈
        const sl = entry.mul(Decimal.fromFloat(0.98));
        const tp = entry.mul(Decimal.fromFloat(1.06));

        self.stop_manager.setStopLoss(position.id, sl, .market) catch {};
        self.stop_manager.setTakeProfit(position.id, tp, .market) catch {};
    }

    pub fn onTick(self: *Self, symbol: []const u8, price: Decimal) !void {
        try self.stop_manager.checkAndExecute(symbol, price);
    }
};
```

### 与告警系统集成

```zig
fn executeStop(self: *Self, pos: Position, config: StopConfig, trigger: StopTrigger) !void {
    // ... 执行平仓 ...

    // 发送告警
    if (self.alert_manager) |alerts| {
        try alerts.sendAlert(.{
            .level = .warning,
            .category = switch (trigger) {
                .stop_loss => .trade_stop_loss,
                .take_profit => .trade_take_profit,
                .trailing_stop => .trade_stop_loss,
            },
            .title = "Stop Triggered",
            .message = std.fmt.allocPrint(allocator, "{s} {s} at {d}", .{
                @tagName(trigger),
                pos.symbol,
                current_price.toFloat(),
            }),
        });
    }
}
```

---

*完整实现请参考: `src/risk/stop_loss.zig`*
