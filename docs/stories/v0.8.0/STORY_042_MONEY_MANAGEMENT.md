# Story 042: 资金管理模块

**版本**: v0.8.0
**状态**: 📋 规划中
**优先级**: P1 (重要)
**预计时间**: 3-4 天
**依赖**: Story 041 (止损/止盈系统)
**参考**: Kelly Criterion, Risk Parity

---

## 目标

实现科学的资金管理策略，帮助交易者确定最优仓位大小，在风险可控的前提下最大化长期收益。

## 背景

资金管理是交易成功的关键因素之一。过大的仓位可能导致破产，过小的仓位则会限制收益。常用的资金管理方法包括:
1. **Kelly 公式**: 数学上最优的仓位大小
2. **固定分数**: 每笔交易风险固定比例的资金
3. **风险平价**: 基于波动率分配仓位
4. **反马丁格尔**: 盈利后加仓，亏损后减仓

---

## 核心功能

### 1. 资金管理器

```zig
/// 资金管理器
pub const MoneyManager = struct {
    allocator: Allocator,
    account: *Account,
    config: MoneyManagementConfig,

    // 历史数据 (用于计算统计)
    trade_history: std.ArrayList(TradeResult),
    win_count: u64,
    loss_count: u64,
    total_profit: Decimal,
    total_loss: Decimal,

    const Self = @This();

    pub fn init(allocator: Allocator, account: *Account, config: MoneyManagementConfig) Self {
        return .{
            .allocator = allocator,
            .account = account,
            .config = config,
            .trade_history = std.ArrayList(TradeResult).init(allocator),
            .win_count = 0,
            .loss_count = 0,
            .total_profit = Decimal.ZERO,
            .total_loss = Decimal.ZERO,
        };
    }

    pub fn deinit(self: *Self) void {
        self.trade_history.deinit();
    }
};
```

### 2. 资金管理配置

```zig
/// 资金管理配置
pub const MoneyManagementConfig = struct {
    // 策略选择
    method: MoneyManagementMethod = .fixed_fraction,

    // Kelly 公式参数
    kelly_fraction: f64 = 0.5,           // Kelly 分数 (0.5 = 半 Kelly)
    kelly_max_position: f64 = 0.25,       // Kelly 最大仓位占比

    // 固定分数参数
    risk_per_trade: f64 = 0.02,           // 单次交易风险 (2%)
    max_position_pct: f64 = 0.20,         // 单仓位最大占比 (20%)

    // 风险平价参数
    target_volatility: f64 = 0.15,        // 目标年化波动率 (15%)
    lookback_period: usize = 20,          // 波动率计算周期

    // 反马丁格尔参数
    anti_martingale_factor: f64 = 1.5,    // 盈利后加仓倍数
    anti_martingale_reset: u32 = 3,       // 连续亏损后重置

    // 通用限制
    max_total_exposure: f64 = 1.0,        // 总敞口限制 (100%)
    min_position_size: Decimal = Decimal.ZERO, // 最小仓位
    max_positions: usize = 10,            // 最大持仓数量

    // 资金管理启用/禁用
    enabled: bool = true,
};

pub const MoneyManagementMethod = enum {
    kelly,              // Kelly 公式
    fixed_fraction,     // 固定分数
    risk_parity,        // 风险平价
    anti_martingale,    // 反马丁格尔
    fixed_size,         // 固定大小
};
```

### 3. Kelly 公式

```zig
/// Kelly 公式计算最优仓位
///
/// Kelly = W - (1-W)/R
/// W = 胜率
/// R = 盈亏比 (平均盈利/平均亏损)
///
pub fn kellyPosition(self: *Self) KellyResult {
    // 计算胜率
    const total_trades = self.win_count + self.loss_count;
    if (total_trades < 10) {
        return KellyResult{
            .position_size = Decimal.ZERO,
            .kelly_fraction = 0,
            .message = "Insufficient trade history (need 10+ trades)",
        };
    }

    const win_rate = @as(f64, @floatFromInt(self.win_count)) / @as(f64, @floatFromInt(total_trades));

    // 计算盈亏比
    const avg_win = self.total_profit.div(Decimal.fromInt(@intCast(self.win_count)));
    const avg_loss = self.total_loss.div(Decimal.fromInt(@intCast(self.loss_count)));
    const profit_loss_ratio = avg_win.toFloat() / avg_loss.toFloat();

    // Kelly 公式
    var kelly = win_rate - (1.0 - win_rate) / profit_loss_ratio;

    // Kelly 可能为负 (不应交易)
    if (kelly <= 0) {
        return KellyResult{
            .position_size = Decimal.ZERO,
            .kelly_fraction = kelly,
            .message = "Negative Kelly: edge is insufficient",
        };
    }

    // 应用 Kelly 分数 (通常使用半 Kelly)
    kelly *= self.config.kelly_fraction;

    // 限制最大仓位
    kelly = @min(kelly, self.config.kelly_max_position);

    // 计算仓位大小
    const position_size = self.account.equity.mul(Decimal.fromFloat(kelly));

    return KellyResult{
        .position_size = position_size,
        .kelly_fraction = kelly,
        .win_rate = win_rate,
        .profit_loss_ratio = profit_loss_ratio,
        .message = null,
    };
}

pub const KellyResult = struct {
    position_size: Decimal,
    kelly_fraction: f64,
    win_rate: f64 = 0,
    profit_loss_ratio: f64 = 0,
    message: ?[]const u8 = null,
};
```

### 4. 固定分数法

```zig
/// 固定分数计算仓位
///
/// 仓位 = (账户权益 * 风险比例) / 止损距离
///
/// 例如: 账户 $100,000, 风险 2%, 止损 5%
/// 仓位 = ($100,000 * 0.02) / 0.05 = $40,000
///
pub fn fixedFraction(self: *Self, stop_loss_pct: f64) FixedFractionResult {
    if (stop_loss_pct <= 0 or stop_loss_pct >= 1) {
        return FixedFractionResult{
            .position_size = Decimal.ZERO,
            .error_message = "Invalid stop loss percentage",
        };
    }

    // 风险金额 = 账户权益 * 单次风险比例
    const risk_amount = self.account.equity.mul(Decimal.fromFloat(self.config.risk_per_trade));

    // 仓位 = 风险金额 / 止损比例
    var position_size = risk_amount.div(Decimal.fromFloat(stop_loss_pct));

    // 限制最大仓位
    const max_position = self.account.equity.mul(Decimal.fromFloat(self.config.max_position_pct));
    if (position_size.cmp(max_position) == .gt) {
        position_size = max_position;
    }

    // 限制最小仓位
    if (position_size.cmp(self.config.min_position_size) == .lt) {
        position_size = self.config.min_position_size;
    }

    return FixedFractionResult{
        .position_size = position_size,
        .risk_amount = risk_amount,
        .position_pct = position_size.toFloat() / self.account.equity.toFloat(),
    };
}

pub const FixedFractionResult = struct {
    position_size: Decimal,
    risk_amount: Decimal = Decimal.ZERO,
    position_pct: f64 = 0,
    error_message: ?[]const u8 = null,
};
```

### 5. 风险平价

```zig
/// 风险平价计算仓位
///
/// 仓位权重 = 目标波动率 / 资产波动率
///
/// 例如: 目标波动率 15%, BTC 波动率 60%
/// 权重 = 15% / 60% = 25%
///
pub fn riskParity(self: *Self, asset_volatility: f64) RiskParityResult {
    if (asset_volatility <= 0) {
        return RiskParityResult{
            .position_size = Decimal.ZERO,
            .error_message = "Invalid asset volatility",
        };
    }

    // 计算权重
    var weight = self.config.target_volatility / asset_volatility;

    // 限制权重不超过 100%
    weight = @min(weight, 1.0);

    // 限制最大仓位
    weight = @min(weight, self.config.max_position_pct);

    // 计算仓位大小
    const position_size = self.account.equity.mul(Decimal.fromFloat(weight));

    return RiskParityResult{
        .position_size = position_size,
        .weight = weight,
        .asset_volatility = asset_volatility,
        .target_volatility = self.config.target_volatility,
    };
}

pub const RiskParityResult = struct {
    position_size: Decimal,
    weight: f64 = 0,
    asset_volatility: f64 = 0,
    target_volatility: f64 = 0,
    error_message: ?[]const u8 = null,
};

/// 计算历史波动率
pub fn calculateVolatility(self: *Self, returns: []const f64) f64 {
    _ = self;
    if (returns.len < 2) return 0;

    // 计算均值
    var sum: f64 = 0;
    for (returns) |r| {
        sum += r;
    }
    const mean = sum / @as(f64, @floatFromInt(returns.len));

    // 计算方差
    var variance: f64 = 0;
    for (returns) |r| {
        const diff = r - mean;
        variance += diff * diff;
    }
    variance /= @as(f64, @floatFromInt(returns.len - 1));

    // 标准差
    const daily_vol = @sqrt(variance);

    // 年化波动率 (假设 252 交易日)
    return daily_vol * @sqrt(252.0);
}
```

### 6. 反马丁格尔

```zig
/// 反马丁格尔计算仓位
///
/// 盈利后增加仓位，亏损后减少仓位
/// 与马丁格尔相反，更适合趋势市场
///
pub fn antiMartingale(self: *Self, base_position: Decimal) AntiMartingaleResult {
    // 获取最近交易结果
    const recent_trades = self.getRecentTrades(5);
    if (recent_trades.len == 0) {
        return AntiMartingaleResult{
            .position_size = base_position,
            .multiplier = 1.0,
        };
    }

    // 计算连续盈利/亏损次数
    var consecutive_wins: u32 = 0;
    var consecutive_losses: u32 = 0;

    for (recent_trades) |trade| {
        if (trade.pnl.cmp(Decimal.ZERO) == .gt) {
            if (consecutive_losses > 0) break;
            consecutive_wins += 1;
        } else {
            if (consecutive_wins > 0) break;
            consecutive_losses += 1;
        }
    }

    // 计算倍数
    var multiplier: f64 = 1.0;

    if (consecutive_wins > 0) {
        // 连续盈利: 加仓
        multiplier = std.math.pow(f64, self.config.anti_martingale_factor, @floatFromInt(consecutive_wins));
        // 限制最大倍数
        multiplier = @min(multiplier, 4.0);
    } else if (consecutive_losses >= self.config.anti_martingale_reset) {
        // 连续亏损达到阈值: 重置为基础仓位
        multiplier = 1.0;
    } else if (consecutive_losses > 0) {
        // 连续亏损: 减仓
        multiplier = std.math.pow(f64, 1.0 / self.config.anti_martingale_factor, @floatFromInt(consecutive_losses));
        // 限制最小倍数
        multiplier = @max(multiplier, 0.25);
    }

    var position_size = base_position.mul(Decimal.fromFloat(multiplier));

    // 限制最大仓位
    const max_position = self.account.equity.mul(Decimal.fromFloat(self.config.max_position_pct));
    if (position_size.cmp(max_position) == .gt) {
        position_size = max_position;
    }

    return AntiMartingaleResult{
        .position_size = position_size,
        .multiplier = multiplier,
        .consecutive_wins = consecutive_wins,
        .consecutive_losses = consecutive_losses,
    };
}

pub const AntiMartingaleResult = struct {
    position_size: Decimal,
    multiplier: f64,
    consecutive_wins: u32 = 0,
    consecutive_losses: u32 = 0,
};
```

### 7. 统一接口

```zig
/// 计算推荐仓位 (根据配置的方法)
pub fn calculatePosition(self: *Self, context: PositionContext) PositionRecommendation {
    if (!self.config.enabled) {
        return PositionRecommendation{
            .position_size = context.requested_size,
            .method = .disabled,
        };
    }

    return switch (self.config.method) {
        .kelly => blk: {
            const result = self.kellyPosition();
            break :blk PositionRecommendation{
                .position_size = result.position_size,
                .method = .kelly,
                .details = .{ .kelly = result },
            };
        },
        .fixed_fraction => blk: {
            const result = self.fixedFraction(context.stop_loss_pct);
            break :blk PositionRecommendation{
                .position_size = result.position_size,
                .method = .fixed_fraction,
                .details = .{ .fixed_fraction = result },
            };
        },
        .risk_parity => blk: {
            const result = self.riskParity(context.asset_volatility);
            break :blk PositionRecommendation{
                .position_size = result.position_size,
                .method = .risk_parity,
                .details = .{ .risk_parity = result },
            };
        },
        .anti_martingale => blk: {
            const result = self.antiMartingale(context.requested_size);
            break :blk PositionRecommendation{
                .position_size = result.position_size,
                .method = .anti_martingale,
                .details = .{ .anti_martingale = result },
            };
        },
        .fixed_size => PositionRecommendation{
            .position_size = context.requested_size,
            .method = .fixed_size,
        },
    };
}

pub const PositionContext = struct {
    symbol: []const u8,
    requested_size: Decimal,
    stop_loss_pct: f64 = 0.02,
    asset_volatility: f64 = 0.5,
    current_price: Decimal = Decimal.ZERO,
};

pub const PositionRecommendation = struct {
    position_size: Decimal,
    method: MoneyManagementMethod,
    details: ?PositionDetails = null,
};

pub const PositionDetails = union {
    kelly: KellyResult,
    fixed_fraction: FixedFractionResult,
    risk_parity: RiskParityResult,
    anti_martingale: AntiMartingaleResult,
};
```

### 8. 交易历史更新

```zig
/// 记录交易结果
pub fn recordTrade(self: *Self, result: TradeResult) !void {
    try self.trade_history.append(result);

    if (result.pnl.cmp(Decimal.ZERO) == .gt) {
        self.win_count += 1;
        self.total_profit = self.total_profit.add(result.pnl);
    } else {
        self.loss_count += 1;
        self.total_loss = self.total_loss.add(result.pnl.abs());
    }

    // 限制历史记录大小
    if (self.trade_history.items.len > 1000) {
        _ = self.trade_history.orderedRemove(0);
    }
}

pub const TradeResult = struct {
    symbol: []const u8,
    side: Side,
    entry_price: Decimal,
    exit_price: Decimal,
    quantity: Decimal,
    pnl: Decimal,
    timestamp: i64,
};

/// 获取交易统计
pub fn getStats(self: *Self) MoneyManagerStats {
    const total_trades = self.win_count + self.loss_count;
    const win_rate = if (total_trades > 0)
        @as(f64, @floatFromInt(self.win_count)) / @as(f64, @floatFromInt(total_trades))
    else
        0;

    const avg_win = if (self.win_count > 0)
        self.total_profit.toFloat() / @as(f64, @floatFromInt(self.win_count))
    else
        0;

    const avg_loss = if (self.loss_count > 0)
        self.total_loss.toFloat() / @as(f64, @floatFromInt(self.loss_count))
    else
        0;

    return MoneyManagerStats{
        .total_trades = total_trades,
        .win_count = self.win_count,
        .loss_count = self.loss_count,
        .win_rate = win_rate,
        .avg_win = avg_win,
        .avg_loss = avg_loss,
        .profit_factor = if (avg_loss > 0) avg_win / avg_loss else 0,
        .net_pnl = self.total_profit.sub(self.total_loss),
    };
}

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

## 实现任务

### Task 1: 实现 MoneyManagementConfig
- [ ] 配置结构定义
- [ ] 默认配置
- [ ] 配置验证

### Task 2: 实现 Kelly 公式
- [ ] 胜率计算
- [ ] 盈亏比计算
- [ ] Kelly 值计算
- [ ] 分数 Kelly 支持

### Task 3: 实现固定分数法
- [ ] 风险金额计算
- [ ] 仓位大小计算
- [ ] 限制检查

### Task 4: 实现风险平价
- [ ] 波动率计算
- [ ] 权重计算
- [ ] 仓位分配

### Task 5: 实现反马丁格尔
- [ ] 连续盈亏计算
- [ ] 倍数计算
- [ ] 重置逻辑

### Task 6: 实现统一接口
- [ ] calculatePosition 函数
- [ ] 交易记录功能
- [ ] 统计功能

### Task 7: 单元测试
- [ ] Kelly 公式测试
- [ ] 固定分数测试
- [ ] 风险平价测试
- [ ] 反马丁格尔测试
- [ ] 边界条件测试

---

## 验收标准

### 功能
- [ ] Kelly 公式计算正确
- [ ] 固定分数计算正确
- [ ] 风险平价计算正确
- [ ] 反马丁格尔逻辑正确
- [ ] 所有方法限制生效

### 性能
- [ ] 仓位计算 < 1ms
- [ ] 内存稳定

### 测试
- [ ] 数学公式验证
- [ ] 极端情况处理
- [ ] 历史数据不足处理

---

## 示例代码

```zig
const std = @import("std");
const MoneyManager = @import("risk").MoneyManager;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 配置
    const config = MoneyManagementConfig{
        .method = .fixed_fraction,
        .risk_per_trade = 0.02,  // 2% 风险
        .max_position_pct = 0.20, // 20% 最大仓位
    };

    // 创建资金管理器
    var mm = MoneyManager.init(allocator, &account, config);
    defer mm.deinit();

    // 固定分数计算
    const ff_result = mm.fixedFraction(0.05); // 5% 止损
    std.debug.print("Fixed Fraction Position: ${d}\n", .{ff_result.position_size.toFloat()});

    // 模拟一些交易历史
    try mm.recordTrade(.{ .pnl = Decimal.fromFloat(500), ... });
    try mm.recordTrade(.{ .pnl = Decimal.fromFloat(-200), ... });
    // ... 更多交易

    // Kelly 公式计算
    const kelly_result = mm.kellyPosition();
    std.debug.print("Kelly Position: ${d} (fraction: {d}%)\n", .{
        kelly_result.position_size.toFloat(),
        kelly_result.kelly_fraction * 100,
    });

    // 打印统计
    const stats = mm.getStats();
    std.debug.print("Win Rate: {d}%, Profit Factor: {d}\n", .{
        stats.win_rate * 100,
        stats.profit_factor,
    });
}
```

---

## 相关文档

- [v0.8.0 Overview](./OVERVIEW.md)
- [Story 041: 止损/止盈系统](./STORY_041_STOP_LOSS.md)
- [Story 043: 风险指标监控](./STORY_043_RISK_METRICS.md)

---

**Story ID**: STORY-042
**状态**: 📋 规划中
**创建时间**: 2025-12-27
