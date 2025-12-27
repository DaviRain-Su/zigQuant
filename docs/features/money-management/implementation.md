# MoneyManagement - 实现细节

> 深入了解资金管理的内部实现

**最后更新**: 2025-12-27

---

## 内部表示

### 数据结构

```zig
pub const MoneyManager = struct {
    allocator: Allocator,
    account: *Account,
    config: MoneyManagementConfig,

    // 交易历史
    trade_history: std.ArrayList(TradeResult),
    win_count: u64,
    loss_count: u64,
    total_profit: Decimal,
    total_loss: Decimal,
};

pub const TradeResult = struct {
    symbol: []const u8,
    side: Side,
    entry_price: Decimal,
    exit_price: Decimal,
    quantity: Decimal,
    pnl: Decimal,
    timestamp: i64,
};
```

---

## 核心算法

### Kelly 公式

```zig
pub fn kellyPosition(self: *Self) KellyResult {
    const total_trades = self.win_count + self.loss_count;

    // 需要足够的交易历史
    if (total_trades < 10) {
        return KellyResult{
            .position_size = Decimal.ZERO,
            .message = "Insufficient trade history",
        };
    }

    // 计算胜率
    const win_rate = @as(f64, @floatFromInt(self.win_count)) /
                     @as(f64, @floatFromInt(total_trades));

    // 计算平均盈亏
    const avg_win = self.total_profit.div(
        Decimal.fromInt(@intCast(self.win_count))
    );
    const avg_loss = self.total_loss.div(
        Decimal.fromInt(@intCast(self.loss_count))
    );

    // 盈亏比
    const profit_loss_ratio = avg_win.toFloat() / avg_loss.toFloat();

    // Kelly 公式: K = W - (1-W)/R
    var kelly = win_rate - (1.0 - win_rate) / profit_loss_ratio;

    // Kelly 可能为负 (表示不应交易)
    if (kelly <= 0) {
        return KellyResult{
            .position_size = Decimal.ZERO,
            .kelly_fraction = kelly,
            .message = "Negative Kelly: edge insufficient",
        };
    }

    // 应用分数 Kelly (更保守)
    kelly *= self.config.kelly_fraction;

    // 限制最大仓位
    kelly = @min(kelly, self.config.kelly_max_position);

    // 计算仓位
    const position_size = self.account.equity.mul(Decimal.fromFloat(kelly));

    return KellyResult{
        .position_size = position_size,
        .kelly_fraction = kelly,
        .win_rate = win_rate,
        .profit_loss_ratio = profit_loss_ratio,
    };
}
```

**复杂度**: O(1)
**说明**: 使用预计算的统计数据，避免每次遍历交易历史

### 固定分数法

```zig
pub fn fixedFraction(self: *Self, stop_loss_pct: f64) FixedFractionResult {
    if (stop_loss_pct <= 0 or stop_loss_pct >= 1) {
        return FixedFractionResult{
            .position_size = Decimal.ZERO,
            .error_message = "Invalid stop loss percentage",
        };
    }

    // 风险金额 = 账户权益 × 单次风险比例
    const risk_amount = self.account.equity.mul(
        Decimal.fromFloat(self.config.risk_per_trade)
    );

    // 仓位 = 风险金额 / 止损比例
    var position_size = risk_amount.div(Decimal.fromFloat(stop_loss_pct));

    // 限制最大仓位
    const max_position = self.account.equity.mul(
        Decimal.fromFloat(self.config.max_position_pct)
    );
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
```

### 风险平价

```zig
pub fn riskParity(self: *Self, asset_volatility: f64) RiskParityResult {
    if (asset_volatility <= 0) {
        return RiskParityResult{
            .position_size = Decimal.ZERO,
            .error_message = "Invalid asset volatility",
        };
    }

    // 计算权重: 目标波动率 / 资产波动率
    var weight = self.config.target_volatility / asset_volatility;

    // 限制权重
    weight = @min(weight, 1.0);
    weight = @min(weight, self.config.max_position_pct);

    // 计算仓位
    const position_size = self.account.equity.mul(Decimal.fromFloat(weight));

    return RiskParityResult{
        .position_size = position_size,
        .weight = weight,
        .asset_volatility = asset_volatility,
        .target_volatility = self.config.target_volatility,
    };
}

/// 计算历史波动率
pub fn calculateVolatility(returns: []const f64) f64 {
    if (returns.len < 2) return 0;

    // 计算均值
    var sum: f64 = 0;
    for (returns) |r| sum += r;
    const mean = sum / @as(f64, @floatFromInt(returns.len));

    // 计算方差
    var variance: f64 = 0;
    for (returns) |r| {
        const diff = r - mean;
        variance += diff * diff;
    }
    variance /= @as(f64, @floatFromInt(returns.len - 1));

    // 年化波动率
    const daily_vol = @sqrt(variance);
    return daily_vol * @sqrt(252.0);
}
```

### 反马丁格尔

```zig
pub fn antiMartingale(self: *Self, base_position: Decimal) AntiMartingaleResult {
    const recent_trades = self.getRecentTrades(5);
    if (recent_trades.len == 0) {
        return AntiMartingaleResult{
            .position_size = base_position,
            .multiplier = 1.0,
        };
    }

    // 计算连续盈亏
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
        multiplier = std.math.pow(
            f64,
            self.config.anti_martingale_factor,
            @floatFromInt(consecutive_wins)
        );
        multiplier = @min(multiplier, 4.0); // 限制最大倍数
    } else if (consecutive_losses >= self.config.anti_martingale_reset) {
        // 连续亏损达到阈值: 重置
        multiplier = 1.0;
    } else if (consecutive_losses > 0) {
        // 连续亏损: 减仓
        multiplier = std.math.pow(
            f64,
            1.0 / self.config.anti_martingale_factor,
            @floatFromInt(consecutive_losses)
        );
        multiplier = @max(multiplier, 0.25); // 限制最小倍数
    }

    var position_size = base_position.mul(Decimal.fromFloat(multiplier));

    // 限制最大仓位
    const max_position = self.account.equity.mul(
        Decimal.fromFloat(self.config.max_position_pct)
    );
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
```

---

## 交易历史管理

```zig
pub fn recordTrade(self: *Self, result: TradeResult) !void {
    try self.trade_history.append(result);

    // 更新统计
    if (result.pnl.cmp(Decimal.ZERO) == .gt) {
        self.win_count += 1;
        self.total_profit = self.total_profit.add(result.pnl);
    } else {
        self.loss_count += 1;
        self.total_loss = self.total_loss.add(result.pnl.abs());
    }

    // 限制历史大小
    if (self.trade_history.items.len > 1000) {
        // 移除最旧的，更新统计
        const old = self.trade_history.orderedRemove(0);
        if (old.pnl.cmp(Decimal.ZERO) == .gt) {
            self.win_count -= 1;
            self.total_profit = self.total_profit.sub(old.pnl);
        } else {
            self.loss_count -= 1;
            self.total_loss = self.total_loss.sub(old.pnl.abs());
        }
    }
}

fn getRecentTrades(self: *Self, count: usize) []const TradeResult {
    const len = self.trade_history.items.len;
    if (len <= count) return self.trade_history.items;
    return self.trade_history.items[len - count..];
}
```

---

## 统一接口

```zig
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
            };
        },
        .fixed_fraction => blk: {
            const result = self.fixedFraction(context.stop_loss_pct);
            break :blk PositionRecommendation{
                .position_size = result.position_size,
                .method = .fixed_fraction,
            };
        },
        .risk_parity => blk: {
            const result = self.riskParity(context.asset_volatility);
            break :blk PositionRecommendation{
                .position_size = result.position_size,
                .method = .risk_parity,
            };
        },
        .anti_martingale => blk: {
            const result = self.antiMartingale(context.requested_size);
            break :blk PositionRecommendation{
                .position_size = result.position_size,
                .method = .anti_martingale,
            };
        },
        .fixed_size => PositionRecommendation{
            .position_size = context.requested_size,
            .method = .fixed_size,
        },
    };
}
```

---

*完整实现请参考: `src/risk/money_manager.zig`*
