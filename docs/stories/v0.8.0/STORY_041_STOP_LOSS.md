# Story 041: 止损/止盈系统

**版本**: v0.8.0
**状态**: 📋 规划中
**优先级**: P0 (关键)
**预计时间**: 3-4 天
**依赖**: Story 040 (RiskEngine)
**参考**: 专业交易平台止损机制

---

## 目标

实现自动化的止损止盈管理系统，包括固定止损止盈和跟踪止损，保护交易利润并限制损失。

## 背景

止损止盈是交易风险管理的基础工具。一个好的止损系统需要:
1. **快速响应**: 在价格触及阈值时立即执行
2. **灵活配置**: 支持多种止损策略
3. **精确执行**: 避免滑点造成的额外损失
4. **可靠性**: 即使在高波动环境下也能正常工作

---

## 核心功能

### 1. 止损止盈管理器

```zig
/// 止损止盈管理器
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

    const Self = @This();

    pub fn init(allocator: Allocator, positions: *PositionTracker, execution: *ExecutionEngine) Self {
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

    pub fn deinit(self: *Self) void {
        self.stops.deinit();
    }
};
```

### 2. 止损配置

```zig
/// 止损止盈配置
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
    partial_close_pct: f64 = 1.0,  // 触发时平仓比例 (1.0 = 全平)

    // 时间止损
    time_stop: ?i64 = null,  // 到期时间戳
    time_stop_action: TimeStopAction = .close,

    // 状态
    created_at: i64 = 0,
    last_updated: i64 = 0,
};

pub const StopType = enum {
    market,      // 市价单
    limit,       // 限价单
    stop_limit,  // 止损限价单
};

pub const TimeStopAction = enum {
    close,       // 平仓
    reduce,      // 减仓
    alert_only,  // 仅告警
};
```

### 3. 设置止损止盈

```zig
/// 设置固定止损
pub fn setStopLoss(self: *Self, position_id: []const u8, price: Decimal, stop_type: StopType) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const position = self.positions.get(position_id) orelse return error.PositionNotFound;

    // 验证止损价格
    if (position.side == .long and price.cmp(position.entry_price) != .lt) {
        return error.InvalidStopLoss; // 多头止损必须低于入场价
    }
    if (position.side == .short and price.cmp(position.entry_price) != .gt) {
        return error.InvalidStopLoss; // 空头止损必须高于入场价
    }

    const config = self.stops.getPtr(position_id) orelse blk: {
        try self.stops.put(position_id, StopConfig{});
        break :blk self.stops.getPtr(position_id).?;
    };

    config.stop_loss = price;
    config.stop_loss_type = stop_type;
    config.last_updated = std.time.timestamp();

    std.log.info("[STOP] Set stop loss for {s} at {d}", .{ position_id, price.toFloat() });
}

/// 设置固定止盈
pub fn setTakeProfit(self: *Self, position_id: []const u8, price: Decimal, stop_type: StopType) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const position = self.positions.get(position_id) orelse return error.PositionNotFound;

    // 验证止盈价格
    if (position.side == .long and price.cmp(position.entry_price) != .gt) {
        return error.InvalidTakeProfit; // 多头止盈必须高于入场价
    }
    if (position.side == .short and price.cmp(position.entry_price) != .lt) {
        return error.InvalidTakeProfit; // 空头止盈必须低于入场价
    }

    const config = self.stops.getPtr(position_id) orelse blk: {
        try self.stops.put(position_id, StopConfig{});
        break :blk self.stops.getPtr(position_id).?;
    };

    config.take_profit = price;
    config.take_profit_type = stop_type;
    config.last_updated = std.time.timestamp();

    std.log.info("[STOP] Set take profit for {s} at {d}", .{ position_id, price.toFloat() });
}

/// 设置跟踪止损 (百分比)
pub fn setTrailingStopPct(self: *Self, position_id: []const u8, trail_pct: f64) !void {
    if (trail_pct <= 0 or trail_pct >= 1) {
        return error.InvalidTrailingPercent;
    }

    self.mutex.lock();
    defer self.mutex.unlock();

    const position = self.positions.get(position_id) orelse return error.PositionNotFound;

    const config = self.stops.getPtr(position_id) orelse blk: {
        try self.stops.put(position_id, StopConfig{});
        break :blk self.stops.getPtr(position_id).?;
    };

    config.trailing_stop_pct = trail_pct;
    config.trailing_stop_active = true;

    // 初始化追踪价格
    if (position.side == .long) {
        config.trailing_stop_high = position.entry_price;
    } else {
        config.trailing_stop_low = position.entry_price;
    }

    config.last_updated = std.time.timestamp();
    std.log.info("[STOP] Set trailing stop {d}% for {s}", .{ trail_pct * 100, position_id });
}

/// 设置跟踪止损 (固定距离)
pub fn setTrailingStopDistance(self: *Self, position_id: []const u8, distance: Decimal) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const position = self.positions.get(position_id) orelse return error.PositionNotFound;

    const config = self.stops.getPtr(position_id) orelse blk: {
        try self.stops.put(position_id, StopConfig{});
        break :blk self.stops.getPtr(position_id).?;
    };

    config.trailing_stop_distance = distance;
    config.trailing_stop_active = true;

    if (position.side == .long) {
        config.trailing_stop_high = position.entry_price;
    } else {
        config.trailing_stop_low = position.entry_price;
    }

    config.last_updated = std.time.timestamp();
}
```

### 4. 价格更新和检查

```zig
/// 检查并执行止损止盈 (每次价格更新时调用)
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
                continue;
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
            self.updateTrailingStop(pos, current_price, self.stops.getPtr(pos.id).?);

            if (self.shouldTriggerTrailingStop(pos, current_price, config)) {
                try self.executeStop(pos, config, .trailing_stop);
                self.stops_triggered += 1;
                continue;
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

/// 判断是否触发止损
fn shouldTriggerStopLoss(self: *Self, pos: Position, current: Decimal, stop: Decimal) bool {
    _ = self;
    return switch (pos.side) {
        .long => current.cmp(stop) != .gt,   // 多头: 当前价 <= 止损价
        .short => current.cmp(stop) != .lt,  // 空头: 当前价 >= 止损价
    };
}

/// 判断是否触发止盈
fn shouldTriggerTakeProfit(self: *Self, pos: Position, current: Decimal, take: Decimal) bool {
    _ = self;
    return switch (pos.side) {
        .long => current.cmp(take) != .lt,   // 多头: 当前价 >= 止盈价
        .short => current.cmp(take) != .gt,  // 空头: 当前价 <= 止盈价
    };
}

/// 更新跟踪止损
fn updateTrailingStop(self: *Self, pos: Position, current: Decimal, config: *StopConfig) void {
    switch (pos.side) {
        .long => {
            // 多头: 追踪最高价
            if (config.trailing_stop_high) |high| {
                if (current.cmp(high) == .gt) {
                    config.trailing_stop_high = current;
                    self.trailing_updates += 1;
                    std.log.debug("[STOP] Trailing high updated to {d}", .{current.toFloat()});
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
                    std.log.debug("[STOP] Trailing low updated to {d}", .{current.toFloat()});
                }
            } else {
                config.trailing_stop_low = current;
            }
        },
    }
}

/// 判断是否触发跟踪止损
fn shouldTriggerTrailingStop(self: *Self, pos: Position, current: Decimal, config: StopConfig) bool {
    _ = self;

    // 计算跟踪止损价格
    const stop_price: Decimal = switch (pos.side) {
        .long => blk: {
            const high = config.trailing_stop_high orelse return false;
            if (config.trailing_stop_pct) |pct| {
                break :blk high.mul(Decimal.fromFloat(1.0 - pct));
            } else if (config.trailing_stop_distance) |dist| {
                break :blk high.sub(dist);
            } else {
                return false;
            }
        },
        .short => blk: {
            const low = config.trailing_stop_low orelse return false;
            if (config.trailing_stop_pct) |pct| {
                break :blk low.mul(Decimal.fromFloat(1.0 + pct));
            } else if (config.trailing_stop_distance) |dist| {
                break :blk low.add(dist);
            } else {
                return false;
            }
        },
    };

    return switch (pos.side) {
        .long => current.cmp(stop_price) != .gt,
        .short => current.cmp(stop_price) != .lt,
    };
}
```

### 5. 执行平仓

```zig
/// 执行止损/止盈
fn executeStop(self: *Self, pos: Position, config: StopConfig, trigger: StopTrigger) !void {
    const close_qty = pos.quantity.mul(Decimal.fromFloat(config.partial_close_pct));

    std.log.warn("[STOP] Triggered {s} for {s}, closing {d}", .{
        @tagName(trigger),
        pos.id,
        close_qty.toFloat(),
    });

    const order_type: OrderType = switch (trigger) {
        .stop_loss => if (config.stop_loss_type == .market) .market else .limit,
        .take_profit => if (config.take_profit_type == .market) .market else .limit,
        .trailing_stop => .market,
    };

    const order = OrderRequest{
        .symbol = pos.symbol,
        .side = if (pos.side == .long) .sell else .buy,
        .order_type = order_type,
        .quantity = close_qty,
        .price = switch (trigger) {
            .stop_loss => config.stop_loss,
            .take_profit => config.take_profit,
            .trailing_stop => null,
        },
        .time_in_force = .ioc,  // 立即执行或取消
    };

    try self.execution.submitOrder(order);

    // 如果是全平，移除止损配置
    if (config.partial_close_pct >= 1.0) {
        _ = self.stops.remove(pos.id);
    }
}

/// 执行时间止损
fn executeTimeStop(self: *Self, pos: Position, config: StopConfig) !void {
    std.log.warn("[STOP] Time stop triggered for {s}", .{pos.id});

    switch (config.time_stop_action) {
        .close => {
            try self.execution.closePosition(pos);
            _ = self.stops.remove(pos.id);
        },
        .reduce => {
            const reduce_qty = pos.quantity.mul(Decimal.fromFloat(0.5));
            const order = OrderRequest{
                .symbol = pos.symbol,
                .side = if (pos.side == .long) .sell else .buy,
                .order_type = .market,
                .quantity = reduce_qty,
            };
            try self.execution.submitOrder(order);
        },
        .alert_only => {
            // 仅发送告警 (Story 044 实现)
        },
    }
}

pub const StopTrigger = enum {
    stop_loss,
    take_profit,
    trailing_stop,
};
```

### 6. 辅助功能

```zig
/// 获取仓位的止损配置
pub fn getConfig(self: *Self, position_id: []const u8) ?StopConfig {
    self.mutex.lock();
    defer self.mutex.unlock();
    return self.stops.get(position_id);
}

/// 取消止损
pub fn cancelStopLoss(self: *Self, position_id: []const u8) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.stops.getPtr(position_id)) |config| {
        config.stop_loss = null;
        config.last_updated = std.time.timestamp();
    }
}

/// 取消止盈
pub fn cancelTakeProfit(self: *Self, position_id: []const u8) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.stops.getPtr(position_id)) |config| {
        config.take_profit = null;
        config.last_updated = std.time.timestamp();
    }
}

/// 取消跟踪止损
pub fn cancelTrailingStop(self: *Self, position_id: []const u8) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.stops.getPtr(position_id)) |config| {
        config.trailing_stop_active = false;
        config.trailing_stop_pct = null;
        config.trailing_stop_distance = null;
        config.trailing_stop_high = null;
        config.trailing_stop_low = null;
        config.last_updated = std.time.timestamp();
    }
}

/// 移除所有止损设置
pub fn removeAll(self: *Self, position_id: []const u8) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    _ = self.stops.remove(position_id);
}

/// 获取统计
pub fn getStats(self: *Self) StopLossStats {
    return .{
        .stops_triggered = self.stops_triggered,
        .takes_triggered = self.takes_triggered,
        .trailing_updates = self.trailing_updates,
        .active_stops = self.stops.count(),
    };
}

pub const StopLossStats = struct {
    stops_triggered: u64,
    takes_triggered: u64,
    trailing_updates: u64,
    active_stops: usize,
};
```

---

## 与策略集成

```zig
// 在策略中使用止损管理器
pub const TrendStrategy = struct {
    stop_manager: *StopLossManager,
    // ...

    pub fn onPositionOpened(self: *Self, position: Position) void {
        // 自动设置止损止盈
        const entry = position.entry_price;

        // 2% 止损
        const stop_loss = if (position.side == .long)
            entry.mul(Decimal.fromFloat(0.98))
        else
            entry.mul(Decimal.fromFloat(1.02));

        // 6% 止盈
        const take_profit = if (position.side == .long)
            entry.mul(Decimal.fromFloat(1.06))
        else
            entry.mul(Decimal.fromFloat(0.94));

        self.stop_manager.setStopLoss(position.id, stop_loss, .market) catch {};
        self.stop_manager.setTakeProfit(position.id, take_profit, .market) catch {};

        // 1% 跟踪止损
        self.stop_manager.setTrailingStopPct(position.id, 0.01) catch {};
    }

    pub fn onTick(self: *Self, symbol: []const u8, price: Decimal) !void {
        // 检查止损止盈
        try self.stop_manager.checkAndExecute(symbol, price);
    }
};
```

---

## 实现任务

### Task 1: 实现 StopConfig 配置结构
- [ ] 固定止损止盈配置
- [ ] 跟踪止损配置
- [ ] 时间止损配置
- [ ] 部分平仓配置

### Task 2: 实现 StopLossManager 核心
- [ ] 初始化和资源管理
- [ ] 设置止损/止盈方法
- [ ] 设置跟踪止损方法

### Task 3: 实现价格检查逻辑
- [ ] checkAndExecute 主函数
- [ ] shouldTriggerStopLoss
- [ ] shouldTriggerTakeProfit
- [ ] updateTrailingStop
- [ ] shouldTriggerTrailingStop

### Task 4: 实现执行逻辑
- [ ] executeStop 函数
- [ ] 市价单执行
- [ ] 限价单执行
- [ ] 部分平仓

### Task 5: 实现辅助功能
- [ ] 取消方法
- [ ] 查询方法
- [ ] 统计功能

### Task 6: 单元测试
- [ ] 固定止损测试
- [ ] 固定止盈测试
- [ ] 跟踪止损测试
- [ ] 时间止损测试
- [ ] 边界条件测试

---

## 验收标准

### 功能
- [ ] 固定止损正常触发
- [ ] 固定止盈正常触发
- [ ] 跟踪止损正确更新和触发
- [ ] 时间止损正常工作
- [ ] 部分平仓正确执行

### 性能
- [ ] 价格检查 < 100μs
- [ ] 线程安全
- [ ] 内存稳定

### 测试
- [ ] 多头/空头场景覆盖
- [ ] 极端价格测试
- [ ] 并发安全测试

---

## 示例代码

```zig
const std = @import("std");
const StopLossManager = @import("risk").StopLossManager;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建止损管理器
    var stop_manager = StopLossManager.init(allocator, &positions, &execution);
    defer stop_manager.deinit();

    // 假设有一个多头仓位
    const position_id = "pos-001";

    // 设置固定止损 (入场价的 2% 下方)
    try stop_manager.setStopLoss(position_id, Decimal.fromFloat(49000), .market);

    // 设置固定止盈 (入场价的 6% 上方)
    try stop_manager.setTakeProfit(position_id, Decimal.fromFloat(53000), .market);

    // 设置 1% 跟踪止损
    try stop_manager.setTrailingStopPct(position_id, 0.01);

    // 价格更新循环
    const prices = [_]f64{ 50500, 51000, 51500, 52000, 51800, 51500, 51200 };
    for (prices) |price| {
        try stop_manager.checkAndExecute("BTC-USDT", Decimal.fromFloat(price));
    }

    // 打印统计
    const stats = stop_manager.getStats();
    std.debug.print("Stops: {}, Takes: {}, Trailing updates: {}\n", .{
        stats.stops_triggered,
        stats.takes_triggered,
        stats.trailing_updates,
    });
}
```

---

## 相关文档

- [v0.8.0 Overview](./OVERVIEW.md)
- [Story 040: RiskEngine](./STORY_040_RISK_ENGINE.md)
- [Story 043: 风险指标监控](./STORY_043_RISK_METRICS.md)

---

**Story ID**: STORY-041
**状态**: 📋 规划中
**创建时间**: 2025-12-27
