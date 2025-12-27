# Story 040: RiskEngine 风险引擎

**版本**: v0.8.0
**状态**: 📋 规划中
**优先级**: P0 (关键)
**预计时间**: 4-5 天
**依赖**: 无 (基础模块)
**参考**: NautilusTrader RiskEngine

---

## 目标

实现生产级风险控制引擎，在订单提交前进行全面的风控检查，保护交易账户免受过度风险敞口。

## 背景

风险引擎是量化交易系统的核心防线。无论策略多么优秀，没有风控就可能导致灾难性损失。借鉴 NautilusTrader 的 RiskEngine 设计，我们需要实现一个可配置、高性能的风险控制系统。

---

## 核心功能

### 1. 风险引擎结构

```zig
/// 风险引擎 - 订单提交前的风控检查
pub const RiskEngine = struct {
    allocator: Allocator,
    config: RiskConfig,
    positions: *PositionTracker,
    account: *Account,

    // 状态跟踪
    daily_pnl: Decimal,
    daily_start_equity: Decimal,
    order_count_per_minute: u32,
    last_minute_start: i64,
    kill_switch_active: std.atomic.Value(bool),

    // 统计
    total_checks: u64,
    rejected_orders: u64,

    const Self = @This();

    pub fn init(allocator: Allocator, config: RiskConfig, positions: *PositionTracker, account: *Account) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .positions = positions,
            .account = account,
            .daily_pnl = Decimal.ZERO,
            .daily_start_equity = account.equity,
            .order_count_per_minute = 0,
            .last_minute_start = std.time.timestamp(),
            .kill_switch_active = std.atomic.Value(bool).init(false),
            .total_checks = 0,
            .rejected_orders = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};
```

### 2. 订单风控检查

```zig
/// 订单风控检查
pub fn checkOrder(self: *Self, order: OrderRequest) RiskCheckResult {
    self.total_checks += 1;

    // 0. Kill Switch 检查
    if (self.kill_switch_active.load(.acquire)) {
        self.rejected_orders += 1;
        return RiskCheckResult{
            .passed = false,
            .reason = .kill_switch_active,
            .message = "Kill switch is active, all trading halted",
        };
    }

    // 1. 仓位大小限制
    const position_check = self.checkPositionSize(order);
    if (!position_check.passed) {
        self.rejected_orders += 1;
        return position_check;
    }

    // 2. 杠杆限制
    const leverage_check = self.checkLeverage(order);
    if (!leverage_check.passed) {
        self.rejected_orders += 1;
        return leverage_check;
    }

    // 3. 日损失限制
    const daily_loss_check = self.checkDailyLoss();
    if (!daily_loss_check.passed) {
        self.rejected_orders += 1;
        return daily_loss_check;
    }

    // 4. 订单频率限制
    const rate_check = self.checkOrderRate();
    if (!rate_check.passed) {
        self.rejected_orders += 1;
        return rate_check;
    }

    // 5. 可用余额检查
    const margin_check = self.checkAvailableMargin(order);
    if (!margin_check.passed) {
        self.rejected_orders += 1;
        return margin_check;
    }

    return RiskCheckResult{ .passed = true };
}
```

### 3. 各项风控检查实现

```zig
/// 仓位大小检查
fn checkPositionSize(self: *Self, order: OrderRequest) RiskCheckResult {
    const order_value = order.quantity.mul(order.price orelse Decimal.ONE);

    if (order_value.cmp(self.config.max_position_size) == .gt) {
        return RiskCheckResult{
            .passed = false,
            .reason = .position_size_exceeded,
            .message = "Order size exceeds maximum position limit",
            .details = .{
                .limit = self.config.max_position_size,
                .actual = order_value,
            },
        };
    }

    // 检查总持仓
    const current_position = self.positions.get(order.symbol);
    const new_position_size = if (current_position) |pos|
        pos.quantity.add(if (order.side == .buy) order.quantity else order.quantity.negate())
    else
        order.quantity;

    if (new_position_size.abs().cmp(self.config.max_position_size) == .gt) {
        return RiskCheckResult{
            .passed = false,
            .reason = .position_size_exceeded,
            .message = "Total position would exceed maximum limit",
        };
    }

    return RiskCheckResult{ .passed = true };
}

/// 杠杆检查
fn checkLeverage(self: *Self, order: OrderRequest) RiskCheckResult {
    const order_value = order.quantity.mul(order.price orelse Decimal.ONE);
    const total_exposure = self.calculateTotalExposure().add(order_value);
    const current_leverage = total_exposure.div(self.account.equity);

    if (current_leverage.cmp(self.config.max_leverage) == .gt) {
        return RiskCheckResult{
            .passed = false,
            .reason = .leverage_exceeded,
            .message = "Order would exceed maximum leverage",
            .details = .{
                .limit = self.config.max_leverage,
                .actual = current_leverage,
            },
        };
    }

    return RiskCheckResult{ .passed = true };
}

/// 日损失检查
fn checkDailyLoss(self: *Self) RiskCheckResult {
    self.updateDailyPnL();

    // 检查绝对损失
    if (self.daily_pnl.negate().cmp(self.config.max_daily_loss) == .gt) {
        return RiskCheckResult{
            .passed = false,
            .reason = .daily_loss_exceeded,
            .message = "Daily loss limit reached",
        };
    }

    // 检查百分比损失
    const loss_pct = self.daily_pnl.negate().div(self.daily_start_equity).toFloat();
    if (loss_pct > self.config.max_daily_loss_pct) {
        return RiskCheckResult{
            .passed = false,
            .reason = .daily_loss_exceeded,
            .message = "Daily loss percentage limit reached",
        };
    }

    return RiskCheckResult{ .passed = true };
}

/// 订单频率检查
fn checkOrderRate(self: *Self) RiskCheckResult {
    const now = std.time.timestamp();

    // 重置分钟计数
    if (now - self.last_minute_start >= 60) {
        self.order_count_per_minute = 0;
        self.last_minute_start = now;
    }

    self.order_count_per_minute += 1;

    if (self.order_count_per_minute > self.config.max_orders_per_minute) {
        return RiskCheckResult{
            .passed = false,
            .reason = .order_rate_exceeded,
            .message = "Order rate limit exceeded",
        };
    }

    return RiskCheckResult{ .passed = true };
}

/// 可用保证金检查
fn checkAvailableMargin(self: *Self, order: OrderRequest) RiskCheckResult {
    const required_margin = self.calculateRequiredMargin(order);
    const available = self.account.available_balance;

    if (required_margin.cmp(available) == .gt) {
        return RiskCheckResult{
            .passed = false,
            .reason = .insufficient_margin,
            .message = "Insufficient available margin",
            .details = .{
                .required = required_margin,
                .available = available,
            },
        };
    }

    return RiskCheckResult{ .passed = true };
}
```

### 4. Kill Switch 紧急停止

```zig
/// Kill Switch - 紧急停止所有交易
pub fn killSwitch(self: *Self, execution: *ExecutionEngine) !void {
    // 设置标志
    self.kill_switch_active.store(true, .release);

    std.log.warn("[RISK] Kill Switch triggered!", .{});

    // 1. 取消所有未完成订单
    try execution.cancelAllOrders();
    std.log.info("[RISK] All open orders cancelled", .{});

    // 2. 平掉所有仓位 (可选，根据配置)
    if (self.config.close_positions_on_kill_switch) {
        for (self.positions.getAll()) |pos| {
            try execution.closePosition(pos);
        }
        std.log.info("[RISK] All positions closed", .{});
    }

    // 3. 发送告警
    // (通过 AlertManager 发送，在 Story 044 实现)
}

/// 解除 Kill Switch
pub fn resetKillSwitch(self: *Self) void {
    self.kill_switch_active.store(false, .release);
    std.log.info("[RISK] Kill switch reset", .{});
}

/// Kill Switch 自动触发检查
pub fn checkKillSwitchConditions(self: *Self) bool {
    // 检查是否达到触发阈值
    self.updateDailyPnL();

    if (self.daily_pnl.negate().cmp(self.config.kill_switch_threshold) == .gt) {
        std.log.warn("[RISK] Kill switch threshold reached", .{});
        return true;
    }

    return false;
}
```

### 5. 风控配置

```zig
/// 风控配置
pub const RiskConfig = struct {
    // 仓位限制
    max_position_size: Decimal,        // 单个仓位最大值 (USD)
    max_position_per_symbol: Decimal,  // 单品种最大仓位

    // 杠杆限制
    max_leverage: Decimal,             // 最大杠杆倍数

    // 损失限制
    max_daily_loss: Decimal,           // 日损失限制 (绝对值)
    max_daily_loss_pct: f64,           // 日损失百分比 (0.05 = 5%)
    max_drawdown_pct: f64,             // 最大回撤限制

    // 订单限制
    max_orders_per_minute: u32,        // 每分钟最大订单数
    max_order_value: Decimal,          // 单笔订单最大金额

    // Kill Switch
    kill_switch_threshold: Decimal,     // Kill Switch 触发阈值
    close_positions_on_kill_switch: bool, // 触发时是否平仓

    // 默认配置
    pub fn default() RiskConfig {
        return .{
            .max_position_size = Decimal.fromFloat(100000), // $100k
            .max_position_per_symbol = Decimal.fromFloat(50000), // $50k
            .max_leverage = Decimal.fromFloat(3.0),
            .max_daily_loss = Decimal.fromFloat(5000), // $5k
            .max_daily_loss_pct = 0.05, // 5%
            .max_drawdown_pct = 0.20, // 20%
            .max_orders_per_minute = 60,
            .max_order_value = Decimal.fromFloat(50000),
            .kill_switch_threshold = Decimal.fromFloat(10000), // $10k
            .close_positions_on_kill_switch = true,
        };
    }

    /// 保守配置
    pub fn conservative() RiskConfig {
        return .{
            .max_position_size = Decimal.fromFloat(25000),
            .max_position_per_symbol = Decimal.fromFloat(10000),
            .max_leverage = Decimal.fromFloat(1.0),
            .max_daily_loss = Decimal.fromFloat(1000),
            .max_daily_loss_pct = 0.02,
            .max_drawdown_pct = 0.10,
            .max_orders_per_minute = 30,
            .max_order_value = Decimal.fromFloat(10000),
            .kill_switch_threshold = Decimal.fromFloat(2000),
            .close_positions_on_kill_switch = true,
        };
    }
};
```

### 6. 检查结果结构

```zig
/// 风控检查结果
pub const RiskCheckResult = struct {
    passed: bool,
    reason: ?RiskRejectReason = null,
    message: ?[]const u8 = null,
    details: ?RiskCheckDetails = null,
};

/// 拒绝原因
pub const RiskRejectReason = enum {
    position_size_exceeded,
    leverage_exceeded,
    daily_loss_exceeded,
    order_rate_exceeded,
    insufficient_margin,
    kill_switch_active,
    symbol_not_allowed,
    order_value_exceeded,
    max_drawdown_exceeded,
};

/// 检查详情
pub const RiskCheckDetails = struct {
    limit: ?Decimal = null,
    actual: ?Decimal = null,
    required: ?Decimal = null,
    available: ?Decimal = null,
};
```

---

## 与执行引擎集成

```zig
// 在 ExecutionEngine 中集成风控
pub const ExecutionEngine = struct {
    risk_engine: *RiskEngine,
    // ...

    pub fn submitOrder(self: *Self, order: OrderRequest) !OrderResult {
        // 1. 风控检查
        const risk_check = self.risk_engine.checkOrder(order);
        if (!risk_check.passed) {
            return OrderResult{
                .status = .rejected,
                .reason = risk_check.message,
            };
        }

        // 2. 检查 Kill Switch 条件
        if (self.risk_engine.checkKillSwitchConditions()) {
            try self.risk_engine.killSwitch(self);
            return OrderResult{
                .status = .rejected,
                .reason = "Kill switch triggered",
            };
        }

        // 3. 提交订单
        return self.doSubmitOrder(order);
    }
};
```

---

## 实现任务

### Task 1: 创建 risk 模块结构
- [x] 创建 `src/risk/` 目录
- [x] 创建 `mod.zig` 模块导出
- [x] 更新 `root.zig` 导出

### Task 2: 实现 RiskConfig
- [ ] 风控配置结构
- [ ] 默认配置
- [ ] 保守配置
- [ ] 配置验证

### Task 3: 实现 RiskEngine 核心
- [ ] 基础结构和初始化
- [ ] checkOrder 主函数
- [ ] 各项风控检查
- [ ] 状态更新

### Task 4: 实现 Kill Switch
- [ ] killSwitch 函数
- [ ] 自动触发检查
- [ ] 重置功能

### Task 5: 与执行引擎集成
- [ ] 修改 ExecutionEngine
- [ ] 订单提交前检查
- [ ] 错误处理

### Task 6: 单元测试
- [ ] 仓位限制测试
- [ ] 杠杆限制测试
- [ ] 日损失测试
- [ ] 订单频率测试
- [ ] Kill Switch 测试
- [ ] 集成测试

---

## 验收标准

### 功能
- [ ] 仓位大小限制正常工作
- [ ] 杠杆限制正常工作
- [ ] 日损失限制正常工作
- [ ] 订单频率限制正常工作
- [ ] Kill Switch 正常触发和重置

### 性能
- [ ] 单次风控检查 < 1ms
- [ ] Kill Switch 响应 < 100ms

### 测试
- [ ] 覆盖所有风控规则
- [ ] 边界条件测试
- [ ] 并发安全测试

---

## 示例代码

```zig
const std = @import("std");
const RiskEngine = @import("risk").RiskEngine;
const RiskConfig = @import("risk").RiskConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建风控配置
    const config = RiskConfig{
        .max_position_size = Decimal.fromFloat(50000),
        .max_leverage = Decimal.fromFloat(2.0),
        .max_daily_loss = Decimal.fromFloat(2000),
        .max_daily_loss_pct = 0.03,
        .max_orders_per_minute = 30,
        .kill_switch_threshold = Decimal.fromFloat(5000),
        .close_positions_on_kill_switch = true,
    };

    // 创建风险引擎
    var risk_engine = RiskEngine.init(allocator, config, &positions, &account);
    defer risk_engine.deinit();

    // 检查订单
    const order = OrderRequest{
        .symbol = "BTC-USDT",
        .side = .buy,
        .quantity = Decimal.fromFloat(1.0),
        .price = Decimal.fromFloat(50000),
    };

    const result = risk_engine.checkOrder(order);
    if (result.passed) {
        std.debug.print("Order passed risk check\n", .{});
    } else {
        std.debug.print("Order rejected: {s}\n", .{result.message orelse "Unknown"});
    }
}
```

---

## 相关文档

- [v0.8.0 Overview](./OVERVIEW.md)
- [Story 041: 止损/止盈系统](./STORY_041_STOP_LOSS.md)
- [竞争分析 - NautilusTrader](../../architecture/COMPETITIVE_ANALYSIS.md)

---

**Story ID**: STORY-040
**状态**: 📋 规划中
**创建时间**: 2025-12-27
