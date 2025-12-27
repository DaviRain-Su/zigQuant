# Pure Market Making - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-27

---

## 类型定义

### PureMMConfig

做市策略配置结构。

```zig
pub const PureMMConfig = struct {
    /// 交易对 (如 "ETH-USD")
    symbol: []const u8,

    /// 价差 (basis points, 1 bp = 0.01%)
    /// 默认: 10 bps = 0.1%
    spread_bps: u32 = 10,

    /// 单边订单数量
    order_amount: Decimal,

    /// 价格层级数 (每边)
    /// 默认: 1 (单层报价)
    order_levels: u32 = 1,

    /// 层级间价差 (basis points)
    /// 默认: 5 bps
    level_spread_bps: u32 = 5,

    /// 最小报价更新阈值 (mid price 变化)
    /// 默认: 2 bps
    min_refresh_bps: u32 = 2,

    /// 订单有效时间 (ticks)
    /// 默认: 60 ticks
    order_ttl_ticks: u32 = 60,

    /// 最大仓位
    max_position: Decimal,

    /// 是否启用两侧报价
    /// 默认: true
    dual_side: bool = true,
};
```

### PureMarketMaking

做市策略主结构。

```zig
pub const PureMarketMaking = struct {
    allocator: Allocator,
    config: PureMMConfig,
    current_position: Decimal,
    active_bids: ArrayList(OrderInfo),
    active_asks: ArrayList(OrderInfo),
    last_mid_price: ?Decimal,
    last_update_tick: u64,
    total_trades: u64,
    total_volume: Decimal,
    realized_pnl: Decimal,
    data_provider: *IDataProvider,
    executor: *IExecutionClient,
};
```

### OrderInfo

订单信息结构。

```zig
pub const OrderInfo = struct {
    order_id: u64,
    price: Decimal,
    amount: Decimal,
};
```

### OrderFill

成交回报结构。

```zig
pub const OrderFill = struct {
    order_id: u64,
    side: Side,
    quantity: Decimal,
    price: Decimal,
    timestamp: i128,
};
```

### MMStats

策略统计信息。

```zig
pub const MMStats = struct {
    total_trades: u64,
    total_volume: Decimal,
    current_position: Decimal,
    realized_pnl: Decimal,
    active_bids: usize,
    active_asks: usize,
};
```

---

## PureMarketMaking 函数

### `init`

```zig
pub fn init(
    allocator: Allocator,
    config: PureMMConfig,
    data_provider: *IDataProvider,
    executor: *IExecutionClient,
) PureMarketMaking
```

**描述**: 初始化做市策略

**参数**:
- `allocator`: 内存分配器
- `config`: 策略配置
- `data_provider`: 数据提供者 (获取行情)
- `executor`: 执行客户端 (下单)

**返回**: 初始化的策略实例

**示例**:
```zig
var mm = PureMarketMaking.init(allocator, config, &provider, &executor);
defer mm.deinit();
```

---

### `deinit`

```zig
pub fn deinit(self: *PureMarketMaking) void
```

**描述**: 释放策略资源

---

### `asClockStrategy`

```zig
pub fn asClockStrategy(self: *PureMarketMaking) IClockStrategy
```

**描述**: 获取 IClockStrategy 接口，用于注册到 Clock

**返回**: IClockStrategy 接口实例

**示例**:
```zig
try clock.addStrategy(&mm.asClockStrategy());
```

---

### `onFill`

```zig
pub fn onFill(self: *PureMarketMaking, fill: OrderFill) void
```

**描述**: 处理订单成交回报

**参数**:
- `fill`: 成交信息

**示例**:
```zig
mm.onFill(.{
    .order_id = 12345,
    .side = .buy,
    .quantity = Decimal.fromFloat(0.1),
    .price = Decimal.fromInt(2000),
    .timestamp = std.time.nanoTimestamp(),
});
```

---

### `getStats`

```zig
pub fn getStats(self: *PureMarketMaking) MMStats
```

**描述**: 获取策略统计信息

**返回**: MMStats 结构

**示例**:
```zig
const stats = mm.getStats();
std.debug.print("Trades: {}, Position: {}\n", .{
    stats.total_trades,
    stats.current_position,
});
```

---

## IClockStrategy 回调

### onTick

每个 tick 触发，执行做市逻辑。

```zig
fn onTickImpl(ptr: *anyopaque, tick: u64, timestamp: i128) !void
```

**流程**:
1. 获取当前 mid price
2. 检查是否需要刷新报价
3. 取消旧订单
4. 计算新报价
5. 下新订单

---

### onStart

策略启动时调用。

```zig
fn onStartImpl(ptr: *anyopaque) !void
```

---

### onStop

策略停止时调用，取消所有活跃订单。

```zig
fn onStopImpl(ptr: *anyopaque) void
```

---

## 完整示例

```zig
const std = @import("std");
const Clock = @import("market_making/clock.zig").Clock;
const PureMarketMaking = @import("market_making/pure_mm.zig").PureMarketMaking;
const PureMMConfig = @import("market_making/pure_mm.zig").PureMMConfig;
const Decimal = @import("core/decimal.zig").Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 配置
    const config = PureMMConfig{
        .symbol = "ETH-USD",
        .spread_bps = 10,
        .order_amount = Decimal.fromFloat(0.1),
        .order_levels = 2,
        .level_spread_bps = 5,
        .min_refresh_bps = 2,
        .max_position = Decimal.fromFloat(1.0),
        .dual_side = true,
    };

    // 初始化依赖
    var provider = MockDataProvider.init();
    var executor = MockExecutor.init(allocator);
    defer executor.deinit();

    // 创建策略
    var mm = PureMarketMaking.init(allocator, config, &provider, &executor);
    defer mm.deinit();

    // 创建时钟
    var clock = Clock.init(allocator, 1000);
    defer clock.deinit();

    // 注册策略
    try clock.addStrategy(&mm.asClockStrategy());

    // 后台运行
    const thread = try std.Thread.spawn(.{}, Clock.start, .{&clock});

    // 运行 60 秒
    std.time.sleep(60_000_000_000);

    // 停止
    clock.stop();
    thread.join();

    // 打印统计
    const stats = mm.getStats();
    std.debug.print("\n=== Market Making Stats ===\n", .{});
    std.debug.print("Total trades: {}\n", .{stats.total_trades});
    std.debug.print("Total volume: {d:.4}\n", .{stats.total_volume.toFloat()});
    std.debug.print("Current position: {d:.4}\n", .{stats.current_position.toFloat()});
    std.debug.print("Realized PnL: {d:.4}\n", .{stats.realized_pnl.toFloat()});
}
```

---

*完整实现请参考: `src/market_making/pure_mm.zig`*
