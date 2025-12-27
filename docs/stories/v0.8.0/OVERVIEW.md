# v0.8.0 Overview - 风险管理

**版本**: v0.8.0
**状态**: 规划中
**开始时间**: 待定
**前置版本**: v0.7.0 (已完成)
**预计时间**: 3-4 周
**参考**:
- [竞争分析 - NautilusTrader 风险管理](../../architecture/COMPETITIVE_ANALYSIS.md)

---

## 目标

实现生产级风险管理系统，包括风险引擎、止损止盈、资金管理、实时监控和崩溃恢复。借鉴 NautilusTrader 的 RiskEngine 设计和 Crash-only 恢复机制。

## 核心理念

```
┌─────────────────────────────────────────────────────────────────┐
│                   zigQuant v0.8.0                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              风险引擎 (RiskEngine)                        │   │
│  │                                                            │   │
│  │  ┌─────────────────┐    ┌─────────────────┐              │   │
│  │  │  订单风控检查   │    │  Kill Switch    │              │   │
│  │  │  (仓位/杠杆)    │    │  (紧急停止)     │              │   │
│  │  └─────────────────┘    └─────────────────┘              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                         ↓                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              止损止盈 (Stop Loss / Take Profit)          │   │
│  │                                                            │   │
│  │  ┌─────────────────┐    ┌─────────────────┐              │   │
│  │  │  固定止损止盈   │    │  跟踪止损       │              │   │
│  │  └─────────────────┘    └─────────────────┘              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                         ↓                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              资金管理 (Money Management)                  │   │
│  │                                                            │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐                 │   │
│  │  │  Kelly   │ │ 固定分数 │ │ 风险平价 │                 │   │
│  │  └──────────┘ └──────────┘ └──────────┘                 │   │
│  └──────────────────────────────────────────────────────────┘   │
│                         ↓                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              监控与恢复 (Monitoring & Recovery)           │   │
│  │                                                            │   │
│  │  ┌─────────────────┐    ┌─────────────────┐              │   │
│  │  │  风险指标监控   │    │  Crash Recovery │              │   │
│  │  │  (VaR/Drawdown) │    │  (崩溃恢复)     │              │   │
│  │  └─────────────────┘    └─────────────────┘              │   │
│  │                                                            │   │
│  │  ┌─────────────────┐                                      │   │
│  │  │  告警系统       │                                      │   │
│  │  │  (Telegram/邮件)│                                      │   │
│  │  └─────────────────┘                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Stories 规划

| Story | 名称 | 描述 | 优先级 | 预计时间 |
|-------|------|------|--------|----------|
| **040** | RiskEngine 风险引擎 | 仓位/杠杆限制、Kill Switch | P0 | 4-5 天 |
| **041** | 止损/止盈系统 | 固定止损止盈、跟踪止损 | P0 | 3-4 天 |
| **042** | 资金管理模块 | Kelly 公式、固定分数 | P1 | 3-4 天 |
| **043** | 风险指标监控 | VaR、最大回撤、夏普比率 | P1 | 2-3 天 |
| **044** | 告警和通知系统 | Telegram、Email、Webhook | P2 | 2-3 天 |
| **045** | Crash Recovery | 状态持久化、崩溃恢复 | P1 | 3-4 天 |

**总计**: 6 个 Stories, 预计 3-4 周

---

## Story 040: RiskEngine 风险引擎

### 目标
实现生产级风险控制引擎，在订单提交前进行风控检查。

### 核心功能

```zig
/// 风险引擎
pub const RiskEngine = struct {
    config: RiskConfig,
    positions: *PositionTracker,
    account: *Account,
    daily_pnl: Decimal,
    order_count_per_minute: u32,
    last_minute_start: i64,

    const Self = @This();

    /// 订单风控检查
    pub fn checkOrder(self: *Self, order: OrderRequest) !RiskCheckResult {
        // 1. 仓位大小限制
        if (order.quantity.cmp(self.config.max_position_size) == .gt) {
            return RiskCheckResult{
                .passed = false,
                .reason = .position_size_exceeded,
            };
        }

        // 2. 杠杆限制
        const current_leverage = self.calculateLeverage();
        if (current_leverage > self.config.max_leverage) {
            return RiskCheckResult{
                .passed = false,
                .reason = .leverage_exceeded,
            };
        }

        // 3. 日损失限制
        if (self.daily_pnl.abs().cmp(self.config.max_daily_loss) == .gt) {
            return RiskCheckResult{
                .passed = false,
                .reason = .daily_loss_exceeded,
            };
        }

        // 4. 订单频率限制
        if (self.order_count_per_minute > self.config.max_orders_per_minute) {
            return RiskCheckResult{
                .passed = false,
                .reason = .order_rate_exceeded,
            };
        }

        return RiskCheckResult{ .passed = true };
    }

    /// Kill Switch - 紧急停止
    pub fn killSwitch(self: *Self, execution: *ExecutionEngine) !void {
        // 1. 取消所有订单
        try execution.cancelAllOrders();

        // 2. 平掉所有仓位
        for (self.positions.getAll()) |pos| {
            try execution.closePosition(pos);
        }

        // 3. 记录日志
        std.log.warn("Kill Switch triggered!", .{});
    }
};

/// 风控配置
pub const RiskConfig = struct {
    max_position_size: Decimal,      // 单个仓位最大值
    max_leverage: Decimal,           // 最大杠杆
    max_daily_loss: Decimal,         // 日损失限制
    max_daily_loss_pct: f64,         // 日损失百分比
    max_orders_per_minute: u32,      // 订单频率限制
    kill_switch_threshold: Decimal,  // Kill Switch 触发阈值
};

/// 风控检查结果
pub const RiskCheckResult = struct {
    passed: bool,
    reason: ?RiskRejectReason = null,
};

pub const RiskRejectReason = enum {
    position_size_exceeded,
    leverage_exceeded,
    daily_loss_exceeded,
    order_rate_exceeded,
    kill_switch_active,
};
```

### 详细文档
- [STORY_040_RISK_ENGINE.md](./STORY_040_RISK_ENGINE.md)

---

## Story 041: 止损/止盈系统

### 目标
实现自动化的止损止盈管理，包括固定止损止盈和跟踪止损。

### 核心功能

```zig
/// 止损止盈管理器
pub const StopLossManager = struct {
    positions: *PositionTracker,
    execution: *ExecutionEngine,
    stops: std.AutoHashMap([]const u8, StopConfig),

    const Self = @This();

    /// 设置止损
    pub fn setStopLoss(self: *Self, position_id: []const u8, price: Decimal) !void {
        const config = self.stops.getPtr(position_id) orelse {
            try self.stops.put(position_id, StopConfig{});
            return self.setStopLoss(position_id, price);
        };
        config.stop_loss = price;
    }

    /// 设置跟踪止损
    pub fn setTrailingStop(self: *Self, position_id: []const u8, trail_pct: f64) !void {
        const config = self.stops.getPtr(position_id) orelse return;
        config.trailing_stop_pct = trail_pct;
        config.trailing_stop_active = true;
    }

    /// 设置止盈
    pub fn setTakeProfit(self: *Self, position_id: []const u8, price: Decimal) !void {
        const config = self.stops.getPtr(position_id) orelse return;
        config.take_profit = price;
    }

    /// 检查并执行止损止盈
    pub fn checkAndExecute(self: *Self, symbol: []const u8, current_price: Decimal) !void {
        const positions = self.positions.getBySymbol(symbol);
        for (positions) |pos| {
            if (self.stops.get(pos.id)) |config| {
                // 检查止损
                if (config.stop_loss) |sl| {
                    if (self.shouldTriggerStopLoss(pos, current_price, sl)) {
                        try self.execution.closePosition(pos);
                    }
                }

                // 检查止盈
                if (config.take_profit) |tp| {
                    if (self.shouldTriggerTakeProfit(pos, current_price, tp)) {
                        try self.execution.closePosition(pos);
                    }
                }

                // 更新跟踪止损
                if (config.trailing_stop_active) {
                    self.updateTrailingStop(pos, current_price, config);
                }
            }
        }
    }
};

/// 止损止盈配置
pub const StopConfig = struct {
    stop_loss: ?Decimal = null,
    take_profit: ?Decimal = null,
    trailing_stop_pct: f64 = 0,
    trailing_stop_active: bool = false,
    trailing_stop_high: ?Decimal = null,
};
```

### 详细文档
- [STORY_041_STOP_LOSS.md](./STORY_041_STOP_LOSS.md)

---

## Story 042: 资金管理模块

### 目标
实现科学的资金管理策略，帮助确定最优仓位大小。

### 核心功能

```zig
/// 资金管理器
pub const MoneyManager = struct {
    account: *Account,
    config: MoneyManagementConfig,

    const Self = @This();

    /// Kelly 公式计算仓位
    pub fn kellyPosition(self: *Self, win_rate: f64, avg_win: Decimal, avg_loss: Decimal) Decimal {
        // Kelly = W - (1-W)/R
        // W = 胜率, R = 盈亏比
        const r = avg_win.toFloat() / avg_loss.toFloat();
        const kelly = win_rate - (1 - win_rate) / r;

        // 使用半 Kelly
        const position_pct = kelly * self.config.kelly_fraction;
        return self.account.equity.mul(Decimal.fromFloat(position_pct));
    }

    /// 固定分数计算仓位
    pub fn fixedFraction(self: *Self, risk_per_trade: f64, stop_loss_pct: f64) Decimal {
        // 风险金额 = 账户权益 * 单次风险比例
        const risk_amount = self.account.equity.mul(Decimal.fromFloat(risk_per_trade));
        // 仓位 = 风险金额 / 止损比例
        return risk_amount.div(Decimal.fromFloat(stop_loss_pct));
    }

    /// 风险平价计算仓位
    pub fn riskParity(self: *Self, volatility: f64, target_vol: f64) Decimal {
        // 仓位 = 目标波动率 / 资产波动率
        const weight = target_vol / volatility;
        return self.account.equity.mul(Decimal.fromFloat(weight));
    }
};

/// 资金管理配置
pub const MoneyManagementConfig = struct {
    kelly_fraction: f64 = 0.5,        // Kelly 分数 (通常使用半 Kelly)
    max_position_pct: f64 = 0.2,      // 单仓位最大占比
    max_total_exposure: f64 = 1.0,    // 总敞口限制
    risk_per_trade: f64 = 0.02,       // 单次交易风险
};
```

### 详细文档
- [STORY_042_MONEY_MANAGEMENT.md](./STORY_042_MONEY_MANAGEMENT.md)

---

## Story 043: 风险指标监控

### 目标
实时计算和监控关键风险指标。

### 核心功能

```zig
/// 风险指标监控器
pub const RiskMetricsMonitor = struct {
    equity_history: std.ArrayList(EquitySnapshot),
    returns_history: std.ArrayList(f64),
    config: RiskMetricsConfig,

    const Self = @This();

    /// 计算 VaR (Value at Risk)
    pub fn calculateVaR(self: *Self, confidence: f64) Decimal {
        // 历史模拟法
        var sorted_returns = self.returns_history.items;
        std.sort.sort(f64, sorted_returns, {}, std.sort.asc(f64));

        const index = @floatToInt(usize, (1 - confidence) * @intToFloat(f64, sorted_returns.len));
        return Decimal.fromFloat(sorted_returns[index]);
    }

    /// 计算最大回撤
    pub fn calculateMaxDrawdown(self: *Self) DrawdownResult {
        var max_equity = Decimal.ZERO;
        var max_drawdown = Decimal.ZERO;
        var current_drawdown_start: usize = 0;
        var max_drawdown_start: usize = 0;
        var max_drawdown_end: usize = 0;

        for (self.equity_history.items, 0..) |snapshot, i| {
            if (snapshot.equity.cmp(max_equity) == .gt) {
                max_equity = snapshot.equity;
                current_drawdown_start = i;
            }

            const drawdown = max_equity.sub(snapshot.equity).div(max_equity);
            if (drawdown.cmp(max_drawdown) == .gt) {
                max_drawdown = drawdown;
                max_drawdown_start = current_drawdown_start;
                max_drawdown_end = i;
            }
        }

        return DrawdownResult{
            .max_drawdown = max_drawdown,
            .start_index = max_drawdown_start,
            .end_index = max_drawdown_end,
        };
    }

    /// 计算滚动夏普比率
    pub fn calculateRollingSharpe(self: *Self, window: usize) f64 {
        if (self.returns_history.items.len < window) return 0;

        const recent_returns = self.returns_history.items[self.returns_history.items.len - window..];
        const mean = calculateMean(recent_returns);
        const std_dev = calculateStdDev(recent_returns, mean);

        return (mean - self.config.risk_free_rate) / std_dev * @sqrt(@as(f64, 252)); // 年化
    }
};
```

### 详细文档
- [STORY_043_RISK_METRICS.md](./STORY_043_RISK_METRICS.md)

---

## Story 044: 告警和通知系统

### 目标
实现多渠道告警，及时通知重要事件。

### 核心功能

```zig
/// 告警管理器
pub const AlertManager = struct {
    channels: std.ArrayList(IAlertChannel),
    config: AlertConfig,

    const Self = @This();

    /// 发送告警
    pub fn sendAlert(self: *Self, alert: Alert) !void {
        for (self.channels.items) |channel| {
            try channel.send(alert);
        }
    }
};

/// 告警通道接口
pub const IAlertChannel = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        send: *const fn (ptr: *anyopaque, alert: Alert) anyerror!void,
    };
};

/// Telegram 通道
pub const TelegramChannel = struct {
    bot_token: []const u8,
    chat_id: []const u8,

    pub fn send(self: *TelegramChannel, alert: Alert) !void {
        // 发送 Telegram 消息
    }
};

/// Email 通道
pub const EmailChannel = struct {
    smtp_config: SmtpConfig,
    recipients: []const []const u8,

    pub fn send(self: *EmailChannel, alert: Alert) !void {
        // 发送邮件
    }
};

/// Webhook 通道
pub const WebhookChannel = struct {
    url: []const u8,

    pub fn send(self: *WebhookChannel, alert: Alert) !void {
        // 发送 HTTP POST
    }
};
```

### 详细文档
- [STORY_044_ALERT_SYSTEM.md](./STORY_044_ALERT_SYSTEM.md)

---

## Story 045: Crash Recovery

### 目标
实现崩溃恢复机制，确保系统在崩溃后能快速恢复状态。

### 核心功能

```zig
/// 恢复管理器
pub const RecoveryManager = struct {
    checkpoint_dir: []const u8,
    state: *TradingState,
    execution: *ExecutionEngine,

    const Self = @This();

    /// 创建检查点
    pub fn checkpoint(self: *Self) !void {
        const checkpoint_file = try self.createCheckpointFile();
        defer checkpoint_file.close();

        // 保存账户状态
        try self.saveAccountState(checkpoint_file);

        // 保存仓位状态
        try self.savePositions(checkpoint_file);

        // 保存未完成订单
        try self.saveOpenOrders(checkpoint_file);

        // 保存策略状态
        try self.saveStrategyState(checkpoint_file);
    }

    /// 从检查点恢复
    pub fn recover(self: *Self) !void {
        const checkpoint_file = try self.openLatestCheckpoint();
        defer checkpoint_file.close();

        // 恢复账户状态
        try self.loadAccountState(checkpoint_file);

        // 恢复仓位状态
        try self.loadPositions(checkpoint_file);

        // 恢复未完成订单
        try self.loadOpenOrders(checkpoint_file);

        // 同步交易所状态
        try self.syncWithExchange();
    }

    /// 同步交易所状态
    pub fn syncWithExchange(self: *Self) !void {
        // 查询交易所当前状态
        const exchange_orders = try self.execution.getOpenOrders();
        const exchange_positions = try self.execution.getPositions();

        // 对比并处理差异
        try self.reconcileOrders(exchange_orders);
        try self.reconcilePositions(exchange_positions);
    }
};
```

### 详细文档
- [STORY_045_CRASH_RECOVERY.md](./STORY_045_CRASH_RECOVERY.md)

---

## 验收标准

### 功能验收

- [ ] RiskEngine 完整实现并通过测试
- [ ] 止损止盈自动执行
- [ ] 资金管理策略可配置
- [ ] 风险指标实时计算
- [ ] 告警系统多渠道支持
- [ ] Crash Recovery 机制完整

### 性能验收

| 指标 | 目标 | 状态 |
|------|------|------|
| 风控检查延迟 | < 1ms | ⏳ |
| Kill Switch 响应 | < 100ms | ⏳ |
| Crash Recovery 时间 | < 10s | ⏳ |
| 单元测试 | 700+ | ⏳ |
| 内存泄漏 | 零 | ⏳ |

### 代码验收

- [ ] 所有测试通过 (目标: 700+)
- [ ] 零内存泄漏
- [ ] 代码文档完整
- [ ] 风险管理示例程序

---

## 依赖关系

```
Story 040 (RiskEngine)
    ↓
Story 041 (止损/止盈) ──→ Story 043 (风险指标)
    ↓                          ↓
Story 042 (资金管理)      Story 044 (告警系统)
                               ↓
                         Story 045 (Crash Recovery)
```

---

## 文件结构

```
src/
├── risk/
│   ├── mod.zig               # 模块导出
│   ├── risk_engine.zig       # 风险引擎
│   ├── stop_loss.zig         # 止损止盈
│   ├── money_manager.zig     # 资金管理
│   ├── metrics.zig           # 风险指标
│   └── alert.zig             # 告警系统
│
├── recovery/
│   ├── mod.zig               # 模块导出
│   ├── recovery_manager.zig  # 恢复管理器
│   └── checkpoint.zig        # 检查点管理
│
└── tests/
    ├── risk_engine_test.zig  # 风险引擎测试
    └── recovery_test.zig     # 恢复测试
```

---

## 相关文档

- [v0.7.0 做市策略](../v0.7.0/OVERVIEW.md)
- [竞争分析 - NautilusTrader 风险管理](../../architecture/COMPETITIVE_ANALYSIS.md)
- [架构模式参考](../../architecture/ARCHITECTURE_PATTERNS.md)

---

**版本**: v0.8.0
**状态**: 规划中
**创建时间**: 2025-12-27
**Stories**: 6 个 (040-045)
