# MoneyManagement - 资金管理模块

> 科学的资金管理策略，确定最优仓位大小

**状态**: 📋 待开始
**版本**: v0.8.0
**Story**: [STORY-042](../../stories/v0.8.0/STORY_042_MONEY_MANAGEMENT.md)
**最后更新**: 2025-12-27

---

## 📋 概述

MoneyManagement 模块实现多种资金管理策略，帮助交易者确定最优仓位大小，在风险可控的前提下最大化长期收益。

### 为什么需要资金管理？

- **过大仓位**: 可能导致破产风险
- **过小仓位**: 限制收益潜力
- **科学方法**: 数学最优化仓位大小
- **风险控制**: 与止损配合限制单笔风险

### 核心特性

- ✅ **Kelly 公式**: 数学上最优的仓位大小
- ✅ **固定分数**: 每笔交易风险固定比例
- ✅ **风险平价**: 基于波动率分配仓位
- ✅ **反马丁格尔**: 盈利加仓，亏损减仓
- ✅ **交易历史**: 自动计算胜率和盈亏比

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

    // 配置
    const config = risk.MoneyManagementConfig{
        .method = .fixed_fraction,
        .risk_per_trade = 0.02,  // 2% 风险
        .max_position_pct = 0.20, // 20% 最大仓位
    };

    // 创建资金管理器
    var mm = risk.MoneyManager.init(allocator, &account, config);
    defer mm.deinit();

    // 固定分数计算
    const result = mm.fixedFraction(0.05); // 5% 止损
    std.debug.print("Position size: ${d}\n", .{result.position_size.toFloat()});

    // 模拟交易历史 (用于 Kelly)
    try mm.recordTrade(.{ .pnl = Decimal.fromFloat(500), ... });
    try mm.recordTrade(.{ .pnl = Decimal.fromFloat(-200), ... });

    // Kelly 公式计算
    const kelly = mm.kellyPosition();
    std.debug.print("Kelly Position: ${d}\n", .{kelly.position_size.toFloat()});
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

### MoneyManager

```zig
pub const MoneyManager = struct {
    /// 初始化
    pub fn init(allocator: Allocator, account: *Account, config: MoneyManagementConfig) MoneyManager;

    /// Kelly 公式计算
    pub fn kellyPosition(self: *Self) KellyResult;

    /// 固定分数计算
    pub fn fixedFraction(self: *Self, stop_loss_pct: f64) FixedFractionResult;

    /// 风险平价计算
    pub fn riskParity(self: *Self, asset_volatility: f64) RiskParityResult;

    /// 反马丁格尔计算
    pub fn antiMartingale(self: *Self, base_position: Decimal) AntiMartingaleResult;

    /// 统一接口
    pub fn calculatePosition(self: *Self, context: PositionContext) PositionRecommendation;

    /// 记录交易结果
    pub fn recordTrade(self: *Self, result: TradeResult) !void;

    /// 获取统计
    pub fn getStats(self: *Self) MoneyManagerStats;
};
```

### MoneyManagementConfig

```zig
pub const MoneyManagementConfig = struct {
    method: MoneyManagementMethod = .fixed_fraction,
    kelly_fraction: f64 = 0.5,           // Kelly 分数
    risk_per_trade: f64 = 0.02,           // 单次风险
    max_position_pct: f64 = 0.20,         // 最大仓位
    target_volatility: f64 = 0.15,        // 目标波动率
};

pub const MoneyManagementMethod = enum {
    kelly,
    fixed_fraction,
    risk_parity,
    anti_martingale,
    fixed_size,
};
```

---

## 📝 资金管理策略

### Kelly 公式

```
Kelly = W - (1-W)/R

W = 胜率
R = 盈亏比 (平均盈利/平均亏损)
```

**示例**: 胜率 60%，盈亏比 2:1
- Kelly = 0.6 - 0.4/2 = 0.4 (40%)
- 半 Kelly = 0.2 (20%) - 更保守

### 固定分数

```
仓位 = (账户权益 × 单次风险) / 止损比例

例如: $100,000 账户, 2% 风险, 5% 止损
仓位 = ($100,000 × 0.02) / 0.05 = $40,000
```

### 风险平价

```
权重 = 目标波动率 / 资产波动率

例如: 目标 15%, BTC 波动率 60%
权重 = 15% / 60% = 25%
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 使用半 Kelly 而不是全 Kelly
.kelly_fraction = 0.5,

// 2. 始终设置最大仓位限制
.max_position_pct = 0.20,

// 3. 积累足够交易历史再使用 Kelly
if (mm.getStats().total_trades >= 30) {
    const kelly = mm.kellyPosition();
}

// 4. 根据策略类型选择合适方法
// 趋势策略 -> Kelly 或反马丁格尔
// 均值回归 -> 固定分数
// 多资产 -> 风险平价
```

### ❌ DON'T

```zig
// 1. 不要使用全 Kelly
// BAD: kelly_fraction = 1.0 (波动太大)
// GOOD: kelly_fraction = 0.25 - 0.5

// 2. 不要在交易历史不足时使用 Kelly
// 需要至少 30+ 笔交易

// 3. 不要忽略最大仓位限制
// 即使 Kelly 建议 50%，也应限制在 20-25%
```

---

## 🎯 使用场景

### ✅ 适用

- **趋势跟踪**: Kelly 或反马丁格尔
- **均值回归**: 固定分数
- **多资产组合**: 风险平价
- **高频交易**: 固定分数 (快速计算)

### ❌ 不适用

- **新策略**: 交易历史不足时避免 Kelly
- **极端波动**: 考虑减小仓位

---

## 📊 性能指标

- **计算延迟**: < 1ms
- **内存占用**: O(n) n = 交易历史长度

---

## 💡 未来改进

- [ ] 动态调整 Kelly 分数
- [ ] 基于回撤的仓位调整
- [ ] 多策略组合优化
- [ ] 实时波动率计算

---

*Last updated: 2025-12-27*
