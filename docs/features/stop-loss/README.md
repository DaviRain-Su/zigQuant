# StopLoss - 止损/止盈系统

> 自动化止损止盈管理，保护交易利润并限制损失

**状态**: 📋 待开始
**版本**: v0.8.0
**Story**: [STORY-041](../../stories/v0.8.0/STORY_041_STOP_LOSS.md)
**最后更新**: 2025-12-27

---

## 📋 概述

StopLoss 模块提供自动化的止损止盈管理功能，支持固定止损止盈、跟踪止损和时间止损，是风险管理的基础组件。

### 为什么需要 StopLoss？

- **保护利润**: 通过跟踪止损锁定已获得的利润
- **限制损失**: 自动平仓避免损失扩大
- **纪律执行**: 消除人为情绪干扰
- **7x24 监控**: 全天候自动监控价格

### 核心特性

- ✅ **固定止损**: 价格触及设定值时平仓
- ✅ **固定止盈**: 达到目标利润时平仓
- ✅ **跟踪止损**: 随价格有利移动自动调整
- ✅ **时间止损**: 到达指定时间自动平仓
- ✅ **部分平仓**: 支持分批平仓
- ✅ **多仓位管理**: 独立管理每个仓位

---

## 🚀 快速开始

### 基本使用

```zig
const std = @import("std");
const risk = @import("zigQuant").risk;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建止损管理器
    var stop_manager = risk.StopLossManager.init(allocator, &positions, &execution);
    defer stop_manager.deinit();

    // 假设有一个多头仓位，入场价 $50,000
    const position_id = "pos-001";

    // 设置固定止损 (入场价的 2% 下方)
    try stop_manager.setStopLoss(position_id, Decimal.fromFloat(49000), .market);

    // 设置固定止盈 (入场价的 6% 上方)
    try stop_manager.setTakeProfit(position_id, Decimal.fromFloat(53000), .market);

    // 设置 1% 跟踪止损
    try stop_manager.setTrailingStopPct(position_id, 0.01);

    // 在价格更新时检查止损
    try stop_manager.checkAndExecute("BTC-USDT", current_price);
}
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 核心 API

### StopLossManager

```zig
pub const StopLossManager = struct {
    /// 初始化止损管理器
    pub fn init(allocator: Allocator, positions: *PositionTracker, execution: *ExecutionEngine) StopLossManager;

    /// 释放资源
    pub fn deinit(self: *StopLossManager) void;

    /// 设置固定止损
    pub fn setStopLoss(self: *Self, position_id: []const u8, price: Decimal, stop_type: StopType) !void;

    /// 设置固定止盈
    pub fn setTakeProfit(self: *Self, position_id: []const u8, price: Decimal, stop_type: StopType) !void;

    /// 设置跟踪止损 (百分比)
    pub fn setTrailingStopPct(self: *Self, position_id: []const u8, trail_pct: f64) !void;

    /// 设置跟踪止损 (固定距离)
    pub fn setTrailingStopDistance(self: *Self, position_id: []const u8, distance: Decimal) !void;

    /// 检查并执行止损止盈
    pub fn checkAndExecute(self: *Self, symbol: []const u8, current_price: Decimal) !void;

    /// 取消止损
    pub fn cancelStopLoss(self: *Self, position_id: []const u8) void;

    /// 获取统计信息
    pub fn getStats(self: *Self) StopLossStats;
};
```

### StopConfig

```zig
pub const StopConfig = struct {
    stop_loss: ?Decimal = null,            // 固定止损价
    stop_loss_type: StopType = .market,    // 止损单类型
    take_profit: ?Decimal = null,          // 固定止盈价
    take_profit_type: StopType = .market,  // 止盈单类型
    trailing_stop_pct: ?f64 = null,        // 跟踪止损百分比
    trailing_stop_distance: ?Decimal = null, // 跟踪止损距离
    trailing_stop_active: bool = false,    // 跟踪止损是否激活
    partial_close_pct: f64 = 1.0,          // 触发时平仓比例
    time_stop: ?i64 = null,                // 时间止损时间戳
};
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 开仓时立即设置止损止盈
pub fn onPositionOpened(position: Position) void {
    const entry = position.entry_price;

    // 2% 止损
    const stop_loss = if (position.side == .long)
        entry.mul(Decimal.fromFloat(0.98))
    else
        entry.mul(Decimal.fromFloat(1.02));

    // 6% 止盈 (3:1 盈亏比)
    const take_profit = if (position.side == .long)
        entry.mul(Decimal.fromFloat(1.06))
    else
        entry.mul(Decimal.fromFloat(0.94));

    stop_manager.setStopLoss(position.id, stop_loss, .market) catch {};
    stop_manager.setTakeProfit(position.id, take_profit, .market) catch {};
}

// 2. 在有利后添加跟踪止损锁定利润
if (position.unrealized_pnl_pct > 0.02) {
    try stop_manager.setTrailingStopPct(position.id, 0.01);
}

// 3. 使用合理的盈亏比
// 止盈距离应该 >= 2-3 倍止损距离
```

### ❌ DON'T

```zig
// 1. 不要设置过紧的止损
// BAD: 0.5% 止损容易被噪音触发
// GOOD: 根据波动率设置合理止损

// 2. 不要频繁修改止损
// BAD: 每次价格变动都调整止损
// GOOD: 只在有利方向移动止损

// 3. 不要忽略止损触发后的仓位清理
stop_manager.removeAll(position_id);
```

---

## 🎯 使用场景

### ✅ 适用

- **趋势跟踪策略**: 使用跟踪止损锁定利润
- **波段交易**: 使用固定止损止盈
- **日内交易**: 使用时间止损避免隔夜持仓
- **多仓位管理**: 每个仓位独立止损设置

### ❌ 不适用

- **做市策略**: 做市需要更复杂的仓位管理
- **套利策略**: 套利依赖价差而非单边价格

---

## 📊 性能指标

- **价格检查延迟**: < 100μs
- **止损执行延迟**: < 1ms
- **内存占用**: O(n) n = 活跃仓位数
- **线程安全**: 支持多线程并发

---

## 💡 未来改进

- [ ] OCO (One-Cancels-Other) 订单支持
- [ ] 基于 ATR 的动态止损
- [ ] 阶梯止盈 (分批止盈)
- [ ] 止损订单的滑点控制
- [ ] 与策略系统深度集成

---

*Last updated: 2025-12-27*
