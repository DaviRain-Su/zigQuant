# RiskEngine - 风险引擎

> 生产级风险控制引擎，在订单提交前进行全面风控检查

**状态**: 📋 待开始
**版本**: v0.8.0
**Story**: [STORY-040](../../stories/v0.8.0/STORY_040_RISK_ENGINE.md)
**最后更新**: 2025-12-27

---

## 📋 概述

RiskEngine 是 zigQuant 的核心风险控制模块，负责在订单提交到交易所之前进行全面的风控检查，防止过度风险敞口导致的灾难性损失。

### 为什么需要 RiskEngine？

量化交易系统面临多种风险：
- **仓位风险**: 单个持仓过大可能导致巨额损失
- **杠杆风险**: 过高杠杆放大了市场波动的影响
- **日内风险**: 单日亏损过多需要及时止损
- **系统风险**: 程序错误可能导致频繁下单

RiskEngine 通过在订单提交前进行检查，将这些风险控制在可接受范围内。

### 核心特性

- ✅ **仓位限制**: 单品种/总仓位大小限制
- ✅ **杠杆控制**: 最大杠杆倍数限制
- ✅ **日损失限制**: 绝对值和百分比双重限制
- ✅ **订单频率控制**: 防止异常高频下单
- ✅ **Kill Switch**: 紧急停止所有交易
- ✅ **可配置规则**: 灵活的风控参数配置

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

    // 创建风控配置
    const config = risk.RiskConfig{
        .max_position_size = Decimal.fromFloat(50000),  // $50k 单仓位限制
        .max_leverage = Decimal.fromFloat(2.0),          // 2x 杠杆限制
        .max_daily_loss = Decimal.fromFloat(2000),       // $2k 日损失限制
        .max_daily_loss_pct = 0.03,                      // 3% 日损失百分比
        .max_orders_per_minute = 30,                     // 每分钟30单
        .kill_switch_threshold = Decimal.fromFloat(5000), // $5k 触发 Kill Switch
    };

    // 创建风险引擎
    var risk_engine = risk.RiskEngine.init(allocator, config, &positions, &account);
    defer risk_engine.deinit();

    // 检查订单
    const order = OrderRequest{
        .symbol = "BTC-USDT",
        .side = .buy,
        .quantity = Decimal.fromFloat(0.5),
        .price = Decimal.fromFloat(50000),
    };

    const result = risk_engine.checkOrder(order);
    if (result.passed) {
        std.debug.print("Order passed risk check\n", .{});
        // 继续提交订单...
    } else {
        std.debug.print("Order rejected: {s}\n", .{result.message orelse "Unknown"});
    }
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

### RiskEngine

```zig
pub const RiskEngine = struct {
    config: RiskConfig,
    positions: *PositionTracker,
    account: *Account,

    /// 初始化风险引擎
    pub fn init(allocator: Allocator, config: RiskConfig, positions: *PositionTracker, account: *Account) RiskEngine;

    /// 释放资源
    pub fn deinit(self: *RiskEngine) void;

    /// 检查订单是否通过风控
    pub fn checkOrder(self: *RiskEngine, order: OrderRequest) RiskCheckResult;

    /// 触发 Kill Switch
    pub fn killSwitch(self: *RiskEngine, execution: *ExecutionEngine) !void;

    /// 重置 Kill Switch
    pub fn resetKillSwitch(self: *RiskEngine) void;

    /// 检查是否应触发 Kill Switch
    pub fn checkKillSwitchConditions(self: *RiskEngine) bool;
};
```

### RiskConfig

```zig
pub const RiskConfig = struct {
    max_position_size: Decimal,       // 单仓位最大值
    max_position_per_symbol: Decimal, // 单品种最大仓位
    max_leverage: Decimal,            // 最大杠杆
    max_daily_loss: Decimal,          // 日损失限制 (绝对值)
    max_daily_loss_pct: f64,          // 日损失限制 (百分比)
    max_orders_per_minute: u32,       // 每分钟最大订单数
    kill_switch_threshold: Decimal,   // Kill Switch 阈值
    close_positions_on_kill_switch: bool, // 触发时是否平仓

    pub fn default() RiskConfig;      // 默认配置
    pub fn conservative() RiskConfig; // 保守配置
};
```

### RiskCheckResult

```zig
pub const RiskCheckResult = struct {
    passed: bool,
    reason: ?RiskRejectReason = null,
    message: ?[]const u8 = null,
    details: ?RiskCheckDetails = null,
};

pub const RiskRejectReason = enum {
    position_size_exceeded,
    leverage_exceeded,
    daily_loss_exceeded,
    order_rate_exceeded,
    insufficient_margin,
    kill_switch_active,
};
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 始终在提交订单前检查风控
const result = risk_engine.checkOrder(order);
if (!result.passed) {
    log.warn("Order rejected: {s}", .{result.message});
    return error.RiskCheckFailed;
}

// 2. 使用保守配置进行初期测试
const config = RiskConfig.conservative();

// 3. 定期检查 Kill Switch 条件
if (risk_engine.checkKillSwitchConditions()) {
    try risk_engine.killSwitch(execution);
}

// 4. 记录被拒绝的订单用于分析
if (!result.passed) {
    try logRejectedOrder(order, result);
}
```

### ❌ DON'T

```zig
// 1. 不要绕过风控检查直接下单
// BAD: execution.submitOrder(order);
// GOOD: 先检查 risk_engine.checkOrder(order)

// 2. 不要忽略 Kill Switch 状态
// BAD: 继续下单
// GOOD: 检查 kill_switch_active 状态

// 3. 不要设置过于宽松的限制
// BAD: max_leverage = 100x
// GOOD: max_leverage = 2-5x (根据策略调整)
```

---

## 🎯 使用场景

### ✅ 适用

- **所有自动化交易**: 任何自动化策略都应该使用风控
- **高频策略**: 需要订单频率限制
- **杠杆交易**: 需要杠杆控制
- **多策略组合**: 统一的风控入口

### ❌ 不适用

- **纯手动交易**: 可以使用但不是必须
- **模拟回测**: 回测时可以禁用以加快速度

---

## 📊 性能指标

- **风控检查延迟**: < 1ms (目标)
- **Kill Switch 响应**: < 100ms (目标)
- **内存占用**: O(1) 常量内存
- **线程安全**: 支持多线程并发检查

---

## 💡 未来改进

- [ ] 支持自定义风控规则
- [ ] 基于历史波动率的动态限制
- [ ] 多账户风控聚合
- [ ] 风控规则热更新
- [ ] 与告警系统集成

---

*Last updated: 2025-12-27*
