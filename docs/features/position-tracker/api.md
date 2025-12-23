# 仓位追踪器 - API 参考

> 完整的 API 文档和使用说明

**最后更新**: 2025-12-23

---

## 类型定义

### Position

仓位数据结构，表示单个交易对的持仓信息。

```zig
pub const Position = struct {
    symbol: []const u8,
    szi: Decimal,
    side: PositionSide,
    entry_px: Decimal,
    mark_price: ?Decimal,
    liquidation_px: ?Decimal,
    leverage: Leverage,
    max_leverage: u32,
    unrealized_pnl: Decimal,
    realized_pnl: Decimal,
    margin_used: Decimal,
    position_value: Decimal,
    return_on_equity: Decimal,
    cum_funding: CumFunding,
    opened_at: Timestamp,
    updated_at: Timestamp,
    allocator: Allocator,
};
```

**字段说明**:

| 字段 | 类型 | 说明 |
|------|------|------|
| `symbol` | `[]const u8` | 交易对符号（如 "ETH", "BTC"） |
| `szi` | `Decimal` | 有符号仓位大小（+多头，-空头） |
| `side` | `PositionSide` | 仓位方向（从 szi 推断） |
| `entry_px` | `Decimal` | 开仓均价 |
| `mark_price` | `?Decimal` | 标记价格（可选） |
| `liquidation_px` | `?Decimal` | 清算价格（可选） |
| `leverage` | `Leverage` | 杠杆信息 |
| `max_leverage` | `u32` | 最大杠杆倍数 |
| `unrealized_pnl` | `Decimal` | 未实现盈亏 |
| `realized_pnl` | `Decimal` | 已实现盈亏 |
| `margin_used` | `Decimal` | 已用保证金 |
| `position_value` | `Decimal` | 仓位价值 |
| `return_on_equity` | `Decimal` | 权益回报率 ROE |
| `cum_funding` | `CumFunding` | 累计资金费率 |
| `opened_at` | `Timestamp` | 开仓时间 |
| `updated_at` | `Timestamp` | 最后更新时间 |
| `allocator` | `Allocator` | 内存分配器 |

### Leverage

杠杆信息结构。

```zig
pub const Leverage = struct {
    type_: []const u8,      // "cross" 或 "isolated"
    value: u32,             // 杠杆倍数
    raw_usd: Decimal,       // 原始 USD 价值
};
```

### CumFunding

累计资金费率信息。

```zig
pub const CumFunding = struct {
    all_time: Decimal,      // 累计总额
    since_change: Decimal,  // 自上次变动
    since_open: Decimal,    // 自开仓
};
```

### PositionSide

仓位方向枚举。

```zig
pub const PositionSide = enum {
    long,   // 多头
    short,  // 空头
    both,   // 双向（暂不支持）
};
```

### Account

账户信息结构。

```zig
pub const Account = struct {
    margin_summary: MarginSummary,
    cross_margin_summary: MarginSummary,
    withdrawable: Decimal,
    cross_maintenance_margin_used: Decimal,
    total_realized_pnl: Decimal,
};
```

### MarginSummary

保证金摘要信息。

```zig
pub const MarginSummary = struct {
    account_value: Decimal,         // 账户总价值
    total_margin_used: Decimal,     // 总已用保证金
    total_ntl_pos: Decimal,         // 总名义仓位价值
    total_raw_usd: Decimal,         // 总原始 USD
};
```

### PositionTracker

仓位追踪器主结构。

```zig
pub const PositionTracker = struct {
    allocator: Allocator,
    http_client: *HyperliquidClient,
    logger: Logger,
    positions: StringHashMap(*Position),
    account: Account,
    on_position_update: ?*const fn (position: *Position) void,
    on_account_update: ?*const fn (account: *Account) void,
    mutex: std.Thread.Mutex,
};
```

---

## Position API

### `Position.init`

创建新的仓位对象。

```zig
pub fn init(
    allocator: Allocator,
    symbol: []const u8,
    szi: Decimal,
) !Position
```

**参数**:
- `allocator`: 内存分配器
- `symbol`: 交易对符号
- `szi`: 有符号仓位大小

**返回**: 初始化的 `Position` 对象

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
const position = try Position.init(
    allocator,
    "ETH",
    try Decimal.fromString("10.5"), // 10.5 ETH 多头
);
defer position.deinit();
```

### `Position.deinit`

释放仓位对象的资源。

```zig
pub fn deinit(self: *Position) void
```

**描述**: 释放内部分配的 `symbol` 字符串。

**示例**:
```zig
defer position.deinit();
```

### `Position.updateMarkPrice`

更新标记价格并重新计算盈亏。

```zig
pub fn updateMarkPrice(self: *Position, mark_price: Decimal) void
```

**参数**:
- `mark_price`: 新的标记价格

**副作用**:
- 更新 `mark_price` 字段
- 重新计算 `unrealized_pnl`
- 重新计算 `position_value`
- 重新计算 `return_on_equity`
- 更新 `updated_at` 时间戳

**示例**:
```zig
const current_price = try Decimal.fromString("2100.5");
position.updateMarkPrice(current_price);

std.debug.print("Unrealized PnL: {d}\n", .{position.unrealized_pnl.toFloat()});
```

### `Position.increase`

增加仓位（开仓或加仓）。

```zig
pub fn increase(
    self: *Position,
    quantity: Decimal,
    price: Decimal,
) void
```

**参数**:
- `quantity`: 增加的数量
- `price`: 成交价格

**副作用**:
- 首次开仓时设置 `entry_px` 和 `szi`
- 加仓时更新 `entry_px`（加权平均）并增加 `szi`
- 更新 `updated_at` 时间戳

**示例**:
```zig
// 首次开仓
position.increase(try Decimal.fromString("5.0"), try Decimal.fromString("2000.0"));
// entry_px = 2000.0, szi = 5.0

// 加仓
position.increase(try Decimal.fromString("3.0"), try Decimal.fromString("2100.0"));
// entry_px = (5*2000 + 3*2100) / (5+3) = 2037.5, szi = 8.0
```

### `Position.decrease`

减少仓位（减仓或平仓）。

```zig
pub fn decrease(
    self: *Position,
    quantity: Decimal,
    price: Decimal,
) Decimal
```

**参数**:
- `quantity`: 减少的数量
- `price`: 成交价格

**返回**: 此次平仓的已实现盈亏

**错误**:
- Panic 如果 `quantity` 大于当前持仓

**副作用**:
- 累加 `realized_pnl`
- 减少 `szi`
- 完全平仓时重置 `entry_px` 和 `unrealized_pnl`
- 更新 `updated_at` 时间戳

**示例**:
```zig
const close_pnl = position.decrease(
    try Decimal.fromString("3.0"),
    try Decimal.fromString("2200.0")
);
std.debug.print("Realized PnL: {d}\n", .{close_pnl.toFloat()});
```

### `Position.isEmpty`

检查是否为空仓。

```zig
pub fn isEmpty(self: *const Position) bool
```

**返回**: `true` 如果 `szi` 为 0

**示例**:
```zig
if (position.isEmpty()) {
    std.debug.print("Position is empty\n", .{});
}
```

### `Position.getTotalPnl`

获取总盈亏（已实现 + 未实现）。

```zig
pub fn getTotalPnl(self: *const Position) Decimal
```

**返回**: 总盈亏

**示例**:
```zig
const total_pnl = position.getTotalPnl();
std.debug.print("Total PnL: {d}\n", .{total_pnl.toFloat()});
```

---

## Account API

### `Account.init`

创建新的账户对象。

```zig
pub fn init() Account
```

**返回**: 初始化的 `Account` 对象（所有字段为 0）

**示例**:
```zig
var account = Account.init();
```

### `Account.updateFromApiResponse`

从 API 响应更新账户信息。

```zig
pub fn updateFromApiResponse(
    self: *Account,
    margin_summary: MarginSummary,
    cross_margin_summary: MarginSummary,
    withdrawable: Decimal,
    cross_maintenance_margin_used: Decimal,
) void
```

**参数**:
- `margin_summary`: 保证金摘要
- `cross_margin_summary`: 全仓保证金摘要
- `withdrawable`: 可提现金额
- `cross_maintenance_margin_used`: 全仓维持保证金

**示例**:
```zig
account.updateFromApiResponse(
    margin_summary,
    cross_margin_summary,
    withdrawable,
    cross_maintenance_margin_used,
);
```

---

## PositionTracker API

### `PositionTracker.init`

创建仓位追踪器。

```zig
pub fn init(
    allocator: Allocator,
    http_client: *HyperliquidClient,
    logger: Logger,
) !PositionTracker
```

**参数**:
- `allocator`: 内存分配器
- `http_client`: Hyperliquid HTTP 客户端
- `logger`: 日志记录器

**返回**: 初始化的 `PositionTracker` 对象

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
var tracker = try PositionTracker.init(allocator, &http_client, logger);
defer tracker.deinit();
```

### `PositionTracker.deinit`

释放仓位追踪器的所有资源。

```zig
pub fn deinit(self: *PositionTracker) void
```

**描述**: 释放所有仓位对象和 HashMap。

**示例**:
```zig
defer tracker.deinit();
```

### `PositionTracker.syncAccountState`

从交易所同步账户状态。

```zig
pub fn syncAccountState(self: *PositionTracker, user_address: []const u8) !void
```

**参数**:
- `user_address`: 用户钱包地址

**副作用**:
- 更新 `account` 信息
- 更新所有仓位数据
- 触发 `on_position_update` 和 `on_account_update` 回调

**错误**:
- `error.HttpRequestFailed`: HTTP 请求失败
- `error.JsonParseFailed`: JSON 解析失败

**示例**:
```zig
try tracker.syncAccountState("0x1234567890abcdef...");
```

### `PositionTracker.handleFill`

处理 WebSocket 成交事件。

```zig
pub fn handleFill(
    self: *PositionTracker,
    fill: WsUserFills.UserFill,
) !void
```

**参数**:
- `fill`: WebSocket 成交事件数据

**副作用**:
- 更新或创建相应仓位
- 更新账户已实现盈亏
- 触发 `on_position_update` 和 `on_account_update` 回调

**错误**:
- `error.OutOfMemory`: 内存分配失败
- `error.InvalidNumber`: 数字解析失败

**示例**:
```zig
try tracker.handleFill(fill_event);
```

### `PositionTracker.updateMarkPrice`

更新指定仓位的标记价格。

```zig
pub fn updateMarkPrice(
    self: *PositionTracker,
    symbol: []const u8,
    mark_price: Decimal,
) !void
```

**参数**:
- `symbol`: 交易对符号
- `mark_price`: 新的标记价格

**副作用**:
- 如果仓位存在，更新其标记价格和未实现盈亏
- 触发 `on_position_update` 回调

**示例**:
```zig
try tracker.updateMarkPrice("ETH", try Decimal.fromString("2100.5"));
```

### `PositionTracker.getAllPositions`

获取所有持仓。

```zig
pub fn getAllPositions(self: *PositionTracker) ![]const *Position
```

**返回**: 所有仓位的切片（调用者负责释放）

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
const positions = try tracker.getAllPositions();
defer allocator.free(positions);

for (positions) |pos| {
    std.debug.print("{s}: {d}\n", .{pos.symbol, pos.szi.toFloat()});
}
```

### `PositionTracker.getPosition`

获取指定交易对的仓位。

```zig
pub fn getPosition(self: *PositionTracker, symbol: []const u8) ?*Position
```

**参数**:
- `symbol`: 交易对符号

**返回**: 仓位指针，如果不存在则返回 `null`

**示例**:
```zig
if (tracker.getPosition("ETH")) |position| {
    std.debug.print("ETH position: {d}\n", .{position.szi.toFloat()});
} else {
    std.debug.print("No ETH position\n", .{});
}
```

---

## 回调函数

### 仓位更新回调

```zig
on_position_update: ?*const fn (position: *Position) void
```

**描述**: 当仓位更新时调用（开仓、平仓、标记价格更新等）

**示例**:
```zig
fn handlePositionUpdate(position: *Position) void {
    std.debug.print("Position {s} updated: szi={d}, unrealized_pnl={d}\n", .{
        position.symbol,
        position.szi.toFloat(),
        position.unrealized_pnl.toFloat(),
    });
}

tracker.on_position_update = handlePositionUpdate;
```

### 账户更新回调

```zig
on_account_update: ?*const fn (account: *Account) void
```

**描述**: 当账户信息更新时调用（余额、保证金、已实现盈亏等）

**示例**:
```zig
fn handleAccountUpdate(account: *Account) void {
    std.debug.print("Account updated: value={d}, margin_used={d}\n", .{
        account.margin_summary.account_value.toFloat(),
        account.margin_summary.total_margin_used.toFloat(),
    });
}

tracker.on_account_update = handleAccountUpdate;
```

---

## 完整示例

### 基本仓位追踪

```zig
const std = @import("std");
const PositionTracker = @import("trading/position_tracker.zig").PositionTracker;
const Decimal = @import("core/decimal.zig").Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var http_client = try HyperliquidClient.init(allocator, .testnet);
    defer http_client.deinit();

    var tracker = try PositionTracker.init(allocator, &http_client, logger);
    defer tracker.deinit();

    // 设置回调
    tracker.on_position_update = onPositionUpdate;
    tracker.on_account_update = onAccountUpdate;

    // 同步账户状态
    try tracker.syncAccountState(user_address);

    // 遍历所有仓位
    const positions = try tracker.getAllPositions();
    defer allocator.free(positions);

    for (positions) |pos| {
        std.debug.print("Symbol: {s}\n", .{pos.symbol});
        std.debug.print("  Size: {d} ({s})\n", .{
            pos.szi.toFloat(),
            if (pos.side == .long) "LONG" else "SHORT",
        });
        std.debug.print("  Entry Price: {d}\n", .{pos.entry_px.toFloat()});
        std.debug.print("  Mark Price: {d}\n", .{
            if (pos.mark_price) |mp| mp.toFloat() else 0.0
        });
        std.debug.print("  Unrealized PnL: {d}\n", .{pos.unrealized_pnl.toFloat()});
        std.debug.print("  Realized PnL: {d}\n", .{pos.realized_pnl.toFloat()});
        std.debug.print("  Total PnL: {d}\n", .{pos.getTotalPnl().toFloat()});
        std.debug.print("  ROE: {d}%\n", .{pos.return_on_equity.toFloat() * 100.0});
    }

    // 查看账户信息
    const account = &tracker.account;
    std.debug.print("\nAccount Summary:\n", .{});
    std.debug.print("  Account Value: ${d}\n", .{
        account.margin_summary.account_value.toFloat()
    });
    std.debug.print("  Total Margin Used: ${d}\n", .{
        account.margin_summary.total_margin_used.toFloat()
    });
    std.debug.print("  Withdrawable: ${d}\n", .{
        account.withdrawable.toFloat()
    });
    std.debug.print("  Total Realized PnL: ${d}\n", .{
        account.total_realized_pnl.toFloat()
    });
}

fn onPositionUpdate(position: *Position) void {
    std.debug.print("[UPDATE] Position {s}: {d} @ {d}\n", .{
        position.symbol,
        position.szi.toFloat(),
        position.entry_px.toFloat(),
    });
}

fn onAccountUpdate(account: *Account) void {
    std.debug.print("[UPDATE] Account value: ${d}\n", .{
        account.margin_summary.account_value.toFloat()
    });
}
```

### 监控清算风险

```zig
pub fn checkLiquidationRisk(tracker: *PositionTracker) !void {
    const positions = try tracker.getAllPositions();
    defer tracker.allocator.free(positions);

    for (positions) |pos| {
        if (pos.liquidation_px) |liq_px| {
            if (pos.mark_price) |mark_px| {
                const distance_pct = mark_px.sub(liq_px).abs()
                    .div(mark_px) catch continue;

                if (distance_pct.cmp(try Decimal.fromString("0.05")) == .lt) {
                    std.debug.print("WARNING: {s} close to liquidation!\n", .{pos.symbol});
                    std.debug.print("  Mark Price: {d}\n", .{mark_px.toFloat()});
                    std.debug.print("  Liquidation Price: {d}\n", .{liq_px.toFloat()});
                    std.debug.print("  Distance: {d}%\n", .{distance_pct.toFloat() * 100.0});
                }
            }
        }
    }
}
```

---

## 线程安全性

所有 `PositionTracker` 的公共方法都是线程安全的，使用内部 `Mutex` 保护。可以安全地从多个线程调用：

```zig
// 线程 1: 处理 WebSocket 事件
const ws_thread = try std.Thread.spawn(.{}, handleWebSocket, .{&tracker});

// 线程 2: 定期同步状态
const sync_thread = try std.Thread.spawn(.{}, syncLoop, .{&tracker});

// 线程 3: 查询仓位
const positions = try tracker.getAllPositions();
```

**注意**: 回调函数会在持有锁的情况下调用，避免在回调中执行耗时操作或调用 `PositionTracker` 的其他方法（会导致死锁）。

---
