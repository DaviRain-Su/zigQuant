# RiskEngine - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-27

---

## 类型定义

### RiskEngine

```zig
pub const RiskEngine = struct {
    allocator: Allocator,
    config: RiskConfig,
    positions: *PositionTracker,
    account: *Account,
    daily_pnl: Decimal,
    daily_start_equity: Decimal,
    order_count_per_minute: u32,
    last_minute_start: i64,
    kill_switch_active: std.atomic.Value(bool),
    total_checks: u64,
    rejected_orders: u64,
};
```

### RiskConfig

```zig
pub const RiskConfig = struct {
    /// 单个仓位最大值 (USD)
    max_position_size: Decimal,

    /// 单品种最大仓位 (USD)
    max_position_per_symbol: Decimal,

    /// 最大杠杆倍数
    max_leverage: Decimal,

    /// 日损失限制 (绝对值 USD)
    max_daily_loss: Decimal,

    /// 日损失限制 (百分比, 0.05 = 5%)
    max_daily_loss_pct: f64,

    /// 最大回撤限制 (百分比)
    max_drawdown_pct: f64,

    /// 每分钟最大订单数
    max_orders_per_minute: u32,

    /// 单笔订单最大金额 (USD)
    max_order_value: Decimal,

    /// Kill Switch 触发阈值 (USD)
    kill_switch_threshold: Decimal,

    /// Kill Switch 触发时是否平仓
    close_positions_on_kill_switch: bool,
};
```

### RiskCheckResult

```zig
pub const RiskCheckResult = struct {
    /// 是否通过风控检查
    passed: bool,

    /// 拒绝原因 (如果未通过)
    reason: ?RiskRejectReason = null,

    /// 人类可读的消息
    message: ?[]const u8 = null,

    /// 详细信息
    details: ?RiskCheckDetails = null,
};
```

### RiskRejectReason

```zig
pub const RiskRejectReason = enum {
    /// 仓位大小超限
    position_size_exceeded,

    /// 杠杆超限
    leverage_exceeded,

    /// 日损失超限
    daily_loss_exceeded,

    /// 订单频率超限
    order_rate_exceeded,

    /// 保证金不足
    insufficient_margin,

    /// Kill Switch 已激活
    kill_switch_active,

    /// 品种不允许交易
    symbol_not_allowed,

    /// 订单金额超限
    order_value_exceeded,

    /// 最大回撤超限
    max_drawdown_exceeded,
};
```

### RiskCheckDetails

```zig
pub const RiskCheckDetails = struct {
    /// 限制值
    limit: ?Decimal = null,

    /// 实际值
    actual: ?Decimal = null,

    /// 需要的金额
    required: ?Decimal = null,

    /// 可用金额
    available: ?Decimal = null,
};
```

---

## 函数

### `init`

```zig
pub fn init(
    allocator: Allocator,
    config: RiskConfig,
    positions: *PositionTracker,
    account: *Account,
) RiskEngine
```

**描述**: 初始化风险引擎

**参数**:
- `allocator`: 内存分配器
- `config`: 风控配置
- `positions`: 持仓跟踪器指针
- `account`: 账户信息指针

**返回**: 初始化后的 RiskEngine 实例

**示例**:
```zig
var risk_engine = RiskEngine.init(
    allocator,
    RiskConfig.default(),
    &position_tracker,
    &account,
);
```

---

### `deinit`

```zig
pub fn deinit(self: *RiskEngine) void
```

**描述**: 释放风险引擎资源

**参数**:
- `self`: RiskEngine 指针

**返回**: 无

**示例**:
```zig
defer risk_engine.deinit();
```

---

### `checkOrder`

```zig
pub fn checkOrder(self: *RiskEngine, order: OrderRequest) RiskCheckResult
```

**描述**: 检查订单是否通过风控

**参数**:
- `self`: RiskEngine 指针
- `order`: 待检查的订单请求

**返回**: 风控检查结果

**示例**:
```zig
const order = OrderRequest{
    .symbol = "BTC-USDT",
    .side = .buy,
    .quantity = Decimal.fromFloat(0.1),
    .price = Decimal.fromFloat(50000),
};

const result = risk_engine.checkOrder(order);
if (result.passed) {
    // 提交订单
} else {
    std.log.warn("Order rejected: {s}", .{result.message orelse "Unknown"});
}
```

---

### `killSwitch`

```zig
pub fn killSwitch(self: *RiskEngine, execution: *ExecutionEngine) !void
```

**描述**: 触发 Kill Switch，取消所有订单并可选平仓

**参数**:
- `self`: RiskEngine 指针
- `execution`: 执行引擎指针

**返回**: 无

**错误**:
- `error.CancelFailed`: 取消订单失败
- `error.CloseFailed`: 平仓失败

**示例**:
```zig
if (risk_engine.checkKillSwitchConditions()) {
    try risk_engine.killSwitch(&execution_engine);
}
```

---

### `resetKillSwitch`

```zig
pub fn resetKillSwitch(self: *RiskEngine) void
```

**描述**: 重置 Kill Switch 状态，允许继续交易

**参数**:
- `self`: RiskEngine 指针

**返回**: 无

**示例**:
```zig
// 手动重置 Kill Switch
risk_engine.resetKillSwitch();
std.log.info("Kill switch reset, trading resumed", .{});
```

---

### `checkKillSwitchConditions`

```zig
pub fn checkKillSwitchConditions(self: *RiskEngine) bool
```

**描述**: 检查是否满足 Kill Switch 触发条件

**参数**:
- `self`: RiskEngine 指针

**返回**: 如果应触发 Kill Switch 返回 true

**示例**:
```zig
// 定期检查
if (risk_engine.checkKillSwitchConditions()) {
    try risk_engine.killSwitch(&execution);
}
```

---

### `isKillSwitchActive`

```zig
pub fn isKillSwitchActive(self: *RiskEngine) bool
```

**描述**: 检查 Kill Switch 是否激活

**参数**:
- `self`: RiskEngine 指针

**返回**: Kill Switch 是否激活

**示例**:
```zig
if (risk_engine.isKillSwitchActive()) {
    std.log.warn("Trading is halted due to kill switch", .{});
    return;
}
```

---

### `getStats`

```zig
pub fn getStats(self: *RiskEngine) RiskEngineStats
```

**描述**: 获取风控引擎统计信息

**参数**:
- `self`: RiskEngine 指针

**返回**: 统计信息结构

```zig
pub const RiskEngineStats = struct {
    total_checks: u64,
    rejected_orders: u64,
    rejection_rate: f64,
    daily_pnl: Decimal,
    current_leverage: Decimal,
    kill_switch_active: bool,
};
```

**示例**:
```zig
const stats = risk_engine.getStats();
std.debug.print("Rejection rate: {d:.2}%\n", .{stats.rejection_rate * 100});
```

---

### `RiskConfig.default`

```zig
pub fn default() RiskConfig
```

**描述**: 获取默认风控配置

**返回**: 默认配置

```zig
// 默认值:
.max_position_size = 100000,      // $100k
.max_position_per_symbol = 50000, // $50k
.max_leverage = 3.0,
.max_daily_loss = 5000,           // $5k
.max_daily_loss_pct = 0.05,       // 5%
.max_orders_per_minute = 60,
.kill_switch_threshold = 10000,   // $10k
.close_positions_on_kill_switch = true,
```

---

### `RiskConfig.conservative`

```zig
pub fn conservative() RiskConfig
```

**描述**: 获取保守风控配置

**返回**: 保守配置

```zig
// 保守值:
.max_position_size = 25000,       // $25k
.max_position_per_symbol = 10000, // $10k
.max_leverage = 1.0,
.max_daily_loss = 1000,           // $1k
.max_daily_loss_pct = 0.02,       // 2%
.max_orders_per_minute = 30,
.kill_switch_threshold = 2000,    // $2k
.close_positions_on_kill_switch = true,
```

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
    var position_tracker = PositionTracker.init(allocator);
    defer position_tracker.deinit();

    var account = Account{
        .equity = Decimal.fromFloat(100000),
        .balance = Decimal.fromFloat(100000),
        .available_balance = Decimal.fromFloat(100000),
    };

    // 创建风控配置
    const config = risk.RiskConfig{
        .max_position_size = Decimal.fromFloat(50000),
        .max_leverage = Decimal.fromFloat(2.0),
        .max_daily_loss = Decimal.fromFloat(2000),
        .max_daily_loss_pct = 0.03,
        .max_orders_per_minute = 30,
        .kill_switch_threshold = Decimal.fromFloat(5000),
        .close_positions_on_kill_switch = true,
    };

    // 创建风险引擎
    var risk_engine = risk.RiskEngine.init(allocator, config, &position_tracker, &account);
    defer risk_engine.deinit();

    // 模拟订单检查
    const orders = [_]OrderRequest{
        .{ .symbol = "BTC-USDT", .side = .buy, .quantity = Decimal.fromFloat(0.5), .price = Decimal.fromFloat(50000) },
        .{ .symbol = "ETH-USDT", .side = .buy, .quantity = Decimal.fromFloat(10), .price = Decimal.fromFloat(3000) },
        .{ .symbol = "BTC-USDT", .side = .buy, .quantity = Decimal.fromFloat(2), .price = Decimal.fromFloat(50000) }, // 会超限
    };

    for (orders) |order| {
        const result = risk_engine.checkOrder(order);
        if (result.passed) {
            std.debug.print("Order passed: {s} {d} @ {d}\n", .{
                order.symbol,
                order.quantity.toFloat(),
                order.price.?.toFloat(),
            });
        } else {
            std.debug.print("Order rejected: {s} - {s}\n", .{
                order.symbol,
                result.message orelse "Unknown reason",
            });
        }
    }

    // 打印统计
    const stats = risk_engine.getStats();
    std.debug.print("\n--- Risk Engine Stats ---\n", .{});
    std.debug.print("Total checks: {}\n", .{stats.total_checks});
    std.debug.print("Rejected: {}\n", .{stats.rejected_orders});
    std.debug.print("Rejection rate: {d:.2}%\n", .{stats.rejection_rate * 100});
}
```

---

*完整 API 请参考: `src/risk/risk_engine.zig`*
