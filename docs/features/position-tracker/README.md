# 仓位追踪器 - 功能概览

> 实时追踪账户仓位、盈亏和风险指标的核心模块

**状态**: 🚧 开发中
**版本**: v0.2.0
**Story**: [Story 011: 仓位追踪器](../../../stories/v0.2-mvp/011-position-tracker.md)
**最后更新**: 2025-12-23

---

## 📋 概述

仓位追踪器（Position Tracker）是量化交易系统的核心组件，负责实时追踪账户的持仓状态、计算盈亏并提供风险管理所需的关键指标。它基于 Hyperliquid 永续合约交易所的真实 API 规范设计，确保数据的准确性和一致性。

### 为什么需要仓位追踪器？

在量化交易中，准确的仓位追踪是风险管理和策略执行的基础：

- **实时监控**: 掌握每个币种的持仓数量、方向和成本
- **盈亏计算**: 精确计算已实现和未实现盈亏，评估策略表现
- **风险控制**: 监控保证金使用、杠杆倍数和清算价格
- **资金费率**: 追踪累计资金费率成本
- **状态同步**: 通过 WebSocket 保持与交易所的实时同步

### 核心特性

- ✅ **多币种持仓追踪**: 支持同时追踪多个交易对的仓位
- ✅ **精确盈亏计算**: 区分已实现和未实现盈亏，使用高精度 Decimal 类型
- ✅ **双向持仓支持**: 支持多头（Long）和空头（Short）仓位
- ✅ **实时标记价格更新**: 基于最新市场价格计算未实现盈亏
- ✅ **保证金和杠杆管理**: 追踪已用保证金、杠杆倍数和仓位价值
- ✅ **风险指标**: 提供清算价格、权益回报率（ROE）等关键指标
- ✅ **资金费率追踪**: 记录累计资金费率及其对盈亏的影响
- ✅ **账户状态同步**: 从交易所 API 同步账户余额和保证金信息
- ✅ **WebSocket 集成**: 通过成交事件实时更新仓位状态

---

## 🚀 快速开始

### 基本使用

```zig
const std = @import("std");
const PositionTracker = @import("trading/position_tracker.zig").PositionTracker;
const HyperliquidClient = @import("exchange/hyperliquid/http.zig").HyperliquidClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化 HTTP 客户端
    var http_client = try HyperliquidClient.init(allocator, .testnet);
    defer http_client.deinit();

    // 创建仓位追踪器
    var tracker = try PositionTracker.init(allocator, &http_client, logger);
    defer tracker.deinit();

    // 设置回调函数
    tracker.on_position_update = handlePositionUpdate;
    tracker.on_account_update = handleAccountUpdate;

    // 同步账户状态（从交易所获取最新数据）
    try tracker.syncAccountState("0x1234...");

    // 查询所有持仓
    const positions = try tracker.getAllPositions();
    defer allocator.free(positions);

    for (positions) |pos| {
        std.debug.print("Position: {s} {d} @ {d} (PnL: {d})\n", .{
            pos.symbol,
            pos.szi.toFloat(),
            pos.entry_px.toFloat(),
            pos.getTotalPnl().toFloat(),
        });
    }

    // 查询账户信息
    const account = &tracker.account;
    std.debug.print("Account Value: ${d}\n", .{
        account.margin_summary.account_value.toFloat()
    });
    std.debug.print("Total Margin Used: ${d}\n", .{
        account.margin_summary.total_margin_used.toFloat()
    });
}

fn handlePositionUpdate(pos: *Position) void {
    std.debug.print("Position updated: {s} ({s})\n", .{
        pos.symbol,
        if (pos.side == .long) "LONG" else "SHORT"
    });
}

fn handleAccountUpdate(account: *Account) void {
    std.debug.print("Account value updated: ${d}\n", .{
        account.margin_summary.account_value.toFloat()
    });
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

### 仓位数据结构

```zig
pub const Position = struct {
    symbol: []const u8,
    szi: Decimal,                  // 有符号仓位大小（+多头，-空头）
    side: PositionSide,             // 仓位方向
    entry_px: Decimal,              // 开仓均价
    mark_price: ?Decimal,           // 标记价格
    liquidation_px: ?Decimal,       // 清算价格
    leverage: Leverage,             // 杠杆信息
    unrealized_pnl: Decimal,        // 未实现盈亏
    realized_pnl: Decimal,          // 已实现盈亏
    margin_used: Decimal,           // 已用保证金
    position_value: Decimal,        // 仓位价值
    return_on_equity: Decimal,      // 权益回报率
    cum_funding: CumFunding,        // 累计资金费率

    pub fn init(allocator: Allocator, symbol: []const u8, szi: Decimal) !Position;
    pub fn deinit(self: *Position) void;
    pub fn updateMarkPrice(self: *Position, mark_price: Decimal) void;
    pub fn getTotalPnl(self: *const Position) Decimal;
};
```

### 仓位追踪器

```zig
pub const PositionTracker = struct {
    allocator: Allocator,
    http_client: *HyperliquidClient,
    positions: StringHashMap(*Position),
    account: Account,

    pub fn init(allocator: Allocator, http_client: *HyperliquidClient, logger: Logger) !PositionTracker;
    pub fn deinit(self: *PositionTracker) void;
    pub fn syncAccountState(self: *PositionTracker, user_address: []const u8) !void;
    pub fn handleFill(self: *PositionTracker, fill: UserFill) !void;
    pub fn updateMarkPrice(self: *PositionTracker, symbol: []const u8, mark_price: Decimal) !void;
    pub fn getAllPositions(self: *PositionTracker) ![]const *Position;
    pub fn getPosition(self: *PositionTracker, symbol: []const u8) ?*Position;
};
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 定期同步账户状态
try tracker.syncAccountState(user_address);

// 2. 使用回调监听仓位变化
tracker.on_position_update = handlePositionUpdate;

// 3. 使用线程安全的方法访问仓位
const position = tracker.getPosition("ETH");

// 4. 检查清算风险
if (position.liquidation_px) |liq_px| {
    if (position.mark_price) |mark_px| {
        const distance = mark_px.sub(liq_px).abs();
        if (distance.cmp(threshold) == .lt) {
            // 接近清算价格，采取行动
        }
    }
}
```

### ❌ DON'T

```zig
// 1. 不要直接修改 Position 结构体内部字段
position.szi = new_value; // ❌ 应该使用 handleFill

// 2. 不要忽略盈亏计算的精度问题
const pnl = position.unrealized_pnl.toFloat() + position.realized_pnl.toFloat(); // ❌
const pnl = position.getTotalPnl(); // ✅

// 3. 不要假设仓位一定存在
const position = tracker.positions.get(symbol).?; // ❌ 可能为 null
const position = tracker.getPosition(symbol) orelse return; // ✅
```

---

## 🎯 使用场景

### ✅ 适用

- 永续合约交易仓位追踪
- 实时盈亏监控和报告
- 风险管理和清算预警
- 资金费率成本分析
- 多策略仓位聚合

### ❌ 不适用

- 现货交易（需要不同的数据结构）
- 多账户聚合（当前仅支持单账户）
- 历史仓位分析（未实现持久化）
- 跨交易所仓位汇总

---

## 📊 性能指标

- **同步延迟**: < 100ms（从交易所获取状态）
- **更新延迟**: < 10ms（处理 WebSocket 成交事件）
- **内存占用**: 约 200 bytes/仓位（取决于 symbol 长度）
- **并发安全**: 支持（通过 Mutex 保护）

---

## 💡 未来改进

- [ ] 支持多账户管理和聚合
- [ ] 实现仓位历史记录和持久化
- [ ] 添加更多风险指标（Sharpe ratio, max drawdown）
- [ ] 生成仓位报表和图表
- [ ] 支持仓位分组和标签
- [ ] 实现仓位快照和回放功能
- [ ] 优化大量仓位时的性能

---

*Last updated: 2025-12-23*
