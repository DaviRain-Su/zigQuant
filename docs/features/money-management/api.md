# MoneyManagement - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-27

---

## 类型定义

### MoneyManager

```zig
pub const MoneyManager = struct {
    allocator: Allocator,
    account: *Account,
    config: MoneyManagementConfig,
    trade_history: std.ArrayList(TradeResult),
    win_count: u64,
    loss_count: u64,
    total_profit: Decimal,
    total_loss: Decimal,
};
```

### MoneyManagementConfig

```zig
pub const MoneyManagementConfig = struct {
    method: MoneyManagementMethod = .fixed_fraction,
    kelly_fraction: f64 = 0.5,
    kelly_max_position: f64 = 0.25,
    risk_per_trade: f64 = 0.02,
    max_position_pct: f64 = 0.20,
    target_volatility: f64 = 0.15,
    lookback_period: usize = 20,
    anti_martingale_factor: f64 = 1.5,
    anti_martingale_reset: u32 = 3,
    max_total_exposure: f64 = 1.0,
    min_position_size: Decimal = Decimal.ZERO,
    max_positions: usize = 10,
    enabled: bool = true,
};
```

### MoneyManagementMethod

```zig
pub const MoneyManagementMethod = enum {
    kelly,
    fixed_fraction,
    risk_parity,
    anti_martingale,
    fixed_size,
};
```

---

## 函数

### `init`

```zig
pub fn init(allocator: Allocator, account: *Account, config: MoneyManagementConfig) MoneyManager
```

**描述**: 初始化资金管理器

---

### `kellyPosition`

```zig
pub fn kellyPosition(self: *Self) KellyResult
```

**描述**: 使用 Kelly 公式计算最优仓位

**返回**:
```zig
pub const KellyResult = struct {
    position_size: Decimal,
    kelly_fraction: f64,
    win_rate: f64 = 0,
    profit_loss_ratio: f64 = 0,
    message: ?[]const u8 = null,
};
```

---

### `fixedFraction`

```zig
pub fn fixedFraction(self: *Self, stop_loss_pct: f64) FixedFractionResult
```

**描述**: 使用固定分数法计算仓位

**参数**:
- `stop_loss_pct`: 止损百分比 (0.05 = 5%)

---

### `riskParity`

```zig
pub fn riskParity(self: *Self, asset_volatility: f64) RiskParityResult
```

**描述**: 使用风险平价计算仓位

**参数**:
- `asset_volatility`: 资产年化波动率

---

### `antiMartingale`

```zig
pub fn antiMartingale(self: *Self, base_position: Decimal) AntiMartingaleResult
```

**描述**: 使用反马丁格尔计算仓位

---

### `calculatePosition`

```zig
pub fn calculatePosition(self: *Self, context: PositionContext) PositionRecommendation
```

**描述**: 统一接口，根据配置选择方法计算仓位

---

### `recordTrade`

```zig
pub fn recordTrade(self: *Self, result: TradeResult) !void
```

**描述**: 记录交易结果，用于更新统计

---

### `getStats`

```zig
pub fn getStats(self: *Self) MoneyManagerStats
```

**描述**: 获取交易统计信息

**返回**:
```zig
pub const MoneyManagerStats = struct {
    total_trades: u64,
    win_count: u64,
    loss_count: u64,
    win_rate: f64,
    avg_win: f64,
    avg_loss: f64,
    profit_factor: f64,
    net_pnl: Decimal,
};
```

---

## 完整示例

```zig
const std = @import("std");
const risk = @import("zigQuant").risk;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var account = Account{ .equity = Decimal.fromFloat(100000) };

    const config = risk.MoneyManagementConfig{
        .method = .fixed_fraction,
        .risk_per_trade = 0.02,
        .max_position_pct = 0.20,
    };

    var mm = risk.MoneyManager.init(allocator, &account, config);
    defer mm.deinit();

    // 记录交易历史
    for (0..50) |i| {
        const pnl = if (i % 3 == 0) -200.0 else 400.0;
        try mm.recordTrade(.{ .pnl = Decimal.fromFloat(pnl), ... });
    }

    // 各种方法计算
    const ff = mm.fixedFraction(0.05);
    const kelly = mm.kellyPosition();

    std.debug.print("Fixed Fraction: ${d}\n", .{ff.position_size.toFloat()});
    std.debug.print("Kelly: ${d} ({d:.1}%)\n", .{
        kelly.position_size.toFloat(),
        kelly.kelly_fraction * 100,
    });

    // 统计
    const stats = mm.getStats();
    std.debug.print("Win Rate: {d:.1}%\n", .{stats.win_rate * 100});
}
```

---

*完整 API 请参考: `src/risk/money_manager.zig`*
