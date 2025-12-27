# StopLoss - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-27

---

## 类型定义

### StopLossManager

```zig
pub const StopLossManager = struct {
    allocator: Allocator,
    positions: *PositionTracker,
    execution: *ExecutionEngine,
    stops: std.StringHashMap(StopConfig),
    mutex: std.Thread.Mutex,
    stops_triggered: u64,
    takes_triggered: u64,
    trailing_updates: u64,
};
```

### StopConfig

```zig
pub const StopConfig = struct {
    /// 固定止损价格
    stop_loss: ?Decimal = null,

    /// 止损单类型
    stop_loss_type: StopType = .market,

    /// 固定止盈价格
    take_profit: ?Decimal = null,

    /// 止盈单类型
    take_profit_type: StopType = .market,

    /// 跟踪止损百分比 (0.01 = 1%)
    trailing_stop_pct: ?f64 = null,

    /// 跟踪止损固定距离
    trailing_stop_distance: ?Decimal = null,

    /// 跟踪止损是否激活
    trailing_stop_active: bool = false,

    /// 多头追踪的最高价
    trailing_stop_high: ?Decimal = null,

    /// 空头追踪的最低价
    trailing_stop_low: ?Decimal = null,

    /// 触发时平仓比例 (1.0 = 全平)
    partial_close_pct: f64 = 1.0,

    /// 时间止损时间戳
    time_stop: ?i64 = null,

    /// 时间止损动作
    time_stop_action: TimeStopAction = .close,
};
```

### StopType

```zig
pub const StopType = enum {
    /// 市价单 (立即成交)
    market,

    /// 限价单 (指定价格)
    limit,

    /// 止损限价单
    stop_limit,
};
```

### TimeStopAction

```zig
pub const TimeStopAction = enum {
    /// 完全平仓
    close,

    /// 减仓50%
    reduce,

    /// 仅告警不操作
    alert_only,
};
```

### StopTrigger

```zig
pub const StopTrigger = enum {
    stop_loss,
    take_profit,
    trailing_stop,
};
```

### StopLossStats

```zig
pub const StopLossStats = struct {
    /// 止损触发次数
    stops_triggered: u64,

    /// 止盈触发次数
    takes_triggered: u64,

    /// 跟踪止损更新次数
    trailing_updates: u64,

    /// 活跃止损配置数
    active_stops: usize,
};
```

---

## 函数

### `init`

```zig
pub fn init(
    allocator: Allocator,
    positions: *PositionTracker,
    execution: *ExecutionEngine,
) StopLossManager
```

**描述**: 初始化止损管理器

**参数**:
- `allocator`: 内存分配器
- `positions`: 持仓跟踪器指针
- `execution`: 执行引擎指针

**返回**: 初始化后的 StopLossManager 实例

**示例**:
```zig
var stop_manager = StopLossManager.init(allocator, &positions, &execution);
defer stop_manager.deinit();
```

---

### `deinit`

```zig
pub fn deinit(self: *StopLossManager) void
```

**描述**: 释放止损管理器资源

---

### `setStopLoss`

```zig
pub fn setStopLoss(
    self: *Self,
    position_id: []const u8,
    price: Decimal,
    stop_type: StopType,
) !void
```

**描述**: 设置固定止损

**参数**:
- `position_id`: 仓位 ID
- `price`: 止损价格
- `stop_type`: 止损单类型

**错误**:
- `error.PositionNotFound`: 仓位不存在
- `error.InvalidStopLoss`: 止损价格无效

**示例**:
```zig
// 为多头仓位设置止损
try stop_manager.setStopLoss("pos-001", Decimal.fromFloat(49000), .market);
```

---

### `setTakeProfit`

```zig
pub fn setTakeProfit(
    self: *Self,
    position_id: []const u8,
    price: Decimal,
    stop_type: StopType,
) !void
```

**描述**: 设置固定止盈

**参数**:
- `position_id`: 仓位 ID
- `price`: 止盈价格
- `stop_type`: 止盈单类型

**错误**:
- `error.PositionNotFound`: 仓位不存在
- `error.InvalidTakeProfit`: 止盈价格无效

**示例**:
```zig
// 为多头仓位设置止盈
try stop_manager.setTakeProfit("pos-001", Decimal.fromFloat(55000), .market);
```

---

### `setTrailingStopPct`

```zig
pub fn setTrailingStopPct(
    self: *Self,
    position_id: []const u8,
    trail_pct: f64,
) !void
```

**描述**: 设置百分比跟踪止损

**参数**:
- `position_id`: 仓位 ID
- `trail_pct`: 跟踪百分比 (0.01 = 1%)

**错误**:
- `error.PositionNotFound`: 仓位不存在
- `error.InvalidTrailingPercent`: 百分比无效 (需要 0 < pct < 1)

**示例**:
```zig
// 设置 2% 跟踪止损
try stop_manager.setTrailingStopPct("pos-001", 0.02);
```

---

### `setTrailingStopDistance`

```zig
pub fn setTrailingStopDistance(
    self: *Self,
    position_id: []const u8,
    distance: Decimal,
) !void
```

**描述**: 设置固定距离跟踪止损

**参数**:
- `position_id`: 仓位 ID
- `distance`: 跟踪距离 (价格单位)

**示例**:
```zig
// 设置 $500 跟踪止损距离
try stop_manager.setTrailingStopDistance("pos-001", Decimal.fromFloat(500));
```

---

### `checkAndExecute`

```zig
pub fn checkAndExecute(
    self: *Self,
    symbol: []const u8,
    current_price: Decimal,
) !void
```

**描述**: 检查并执行止损止盈 (每次价格更新时调用)

**参数**:
- `symbol`: 交易对
- `current_price`: 当前价格

**示例**:
```zig
// 在价格更新回调中
pub fn onPriceUpdate(symbol: []const u8, price: Decimal) !void {
    try stop_manager.checkAndExecute(symbol, price);
}
```

---

### `cancelStopLoss`

```zig
pub fn cancelStopLoss(self: *Self, position_id: []const u8) void
```

**描述**: 取消止损设置

---

### `cancelTakeProfit`

```zig
pub fn cancelTakeProfit(self: *Self, position_id: []const u8) void
```

**描述**: 取消止盈设置

---

### `cancelTrailingStop`

```zig
pub fn cancelTrailingStop(self: *Self, position_id: []const u8) void
```

**描述**: 取消跟踪止损

---

### `removeAll`

```zig
pub fn removeAll(self: *Self, position_id: []const u8) void
```

**描述**: 移除所有止损设置

---

### `getConfig`

```zig
pub fn getConfig(self: *Self, position_id: []const u8) ?StopConfig
```

**描述**: 获取仓位的止损配置

**返回**: 止损配置，如果不存在返回 null

---

### `getStats`

```zig
pub fn getStats(self: *Self) StopLossStats
```

**描述**: 获取统计信息

---

## 完整示例

```zig
const std = @import("std");
const risk = @import("zigQuant").risk;
const Decimal = @import("zigQuant").Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化依赖
    var positions = PositionTracker.init(allocator);
    defer positions.deinit();

    var execution = ExecutionEngine.init(allocator);
    defer execution.deinit();

    // 创建止损管理器
    var stop_manager = risk.StopLossManager.init(allocator, &positions, &execution);
    defer stop_manager.deinit();

    // 模拟开仓
    const position = Position{
        .id = "pos-001",
        .symbol = "BTC-USDT",
        .side = .long,
        .quantity = Decimal.fromFloat(0.5),
        .entry_price = Decimal.fromFloat(50000),
    };
    try positions.add(position);

    // 设置止损止盈
    try stop_manager.setStopLoss("pos-001", Decimal.fromFloat(49000), .market);
    try stop_manager.setTakeProfit("pos-001", Decimal.fromFloat(53000), .market);
    try stop_manager.setTrailingStopPct("pos-001", 0.01);

    // 模拟价格变动
    const prices = [_]f64{ 50500, 51000, 51500, 52000, 51800, 51500, 51200, 51000, 50500 };

    for (prices) |price| {
        const current = Decimal.fromFloat(price);
        std.debug.print("Price: {d}\n", .{price});
        try stop_manager.checkAndExecute("BTC-USDT", current);
    }

    // 打印统计
    const stats = stop_manager.getStats();
    std.debug.print("\n--- Stop Loss Stats ---\n", .{});
    std.debug.print("Stops triggered: {}\n", .{stats.stops_triggered});
    std.debug.print("Takes triggered: {}\n", .{stats.takes_triggered});
    std.debug.print("Trailing updates: {}\n", .{stats.trailing_updates});
}
```

---

*完整 API 请参考: `src/risk/stop_loss.zig`*
