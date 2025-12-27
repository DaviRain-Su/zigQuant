# Cross-Exchange Arbitrage 实现细节

> 跨交易所套利模块的内部实现文档

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 目录

1. [架构概述](#架构概述)
2. [套利检测](#套利检测)
3. [利润计算](#利润计算)
4. [订单执行](#订单执行)
5. [风险控制](#风险控制)
6. [性能优化](#性能优化)

---

## 架构概述

### 模块结构

```
src/arbitrage/
├── cross_exchange.zig     # 主策略模块
├── opportunity.zig        # 机会检测
├── profit_calc.zig        # 利润计算
├── executor.zig           # 订单执行
├── risk.zig               # 风险控制
└── tests/
    └── arbitrage_test.zig # 测试
```

### 组件关系

```
┌─────────────────────────────────────────────────────────────┐
│                  CrossExchangeArbitrage                      │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ Opportunity  │───▶│  ProfitCalc  │───▶│   Executor   │  │
│  │  Detector    │    │              │    │              │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│         │                   │                   │           │
│         ▼                   ▼                   ▼           │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ RiskManager  │    │    Stats     │    │   Logger     │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
└─────────────────────────────────────────────────────────────┘
              │                                    │
              ▼                                    ▼
┌──────────────────────┐            ┌──────────────────────┐
│     Exchange A       │            │     Exchange B       │
│  ┌────────────────┐  │            │  ┌────────────────┐  │
│  │ MarketProvider │  │            │  │ MarketProvider │  │
│  │ OrderExecutor  │  │            │  │ OrderExecutor  │  │
│  └────────────────┘  │            │  └────────────────┘  │
└──────────────────────┘            └──────────────────────┘
```

---

## 套利检测

### 检测原理

```
Exchange A                 Exchange B
┌─────────────┐           ┌─────────────┐
│ Bid: 1995   │           │ Bid: 2005   │ ← B.bid > A.ask
│ Ask: 2000   │ ← A.ask   │ Ask: 2010   │
└─────────────┘           └─────────────┘

套利条件: A.ask < B.bid
操作: 在 A 买入 @ 2000, 在 B 卖出 @ 2005
毛利润: (2005 - 2000) / 2000 = 0.25% = 25 bps

反向套利:
如果 B.ask < A.bid, 则在 B 买入, 在 A 卖出
```

### 检测算法

```zig
pub fn detectOpportunity(self: *CrossExchangeArbitrage) ?ArbitrageOpportunity {
    // 获取两个交易所的最优报价
    const quote_a = self.provider_a.getBestQuote(self.config.symbol) orelse return null;
    const quote_b = self.provider_b.getBestQuote(self.config.symbol) orelse return null;

    // 检查正向套利: A买 → B卖
    if (quote_a.ask.lessThan(quote_b.bid)) {
        const profit = self.calculateNetProfit(quote_a.ask, quote_b.bid);
        if (profit.net_bps >= self.config.min_profit_bps) {
            return ArbitrageOpportunity{
                .buy_exchange = .exchange_a,
                .sell_exchange = .exchange_b,
                .buy_price = quote_a.ask,
                .sell_price = quote_b.bid,
                .gross_profit_bps = profit.gross_bps,
                .net_profit_bps = profit.net_bps,
                .amount = self.calculateAmount(quote_a.ask_size, quote_b.bid_size),
                .expected_profit = profit.profit,
                .detected_at = std.time.nanoTimestamp(),
            };
        }
    }

    // 检查反向套利: B买 → A卖
    if (quote_b.ask.lessThan(quote_a.bid)) {
        const profit = self.calculateNetProfit(quote_b.ask, quote_a.bid);
        if (profit.net_bps >= self.config.min_profit_bps) {
            return ArbitrageOpportunity{
                .buy_exchange = .exchange_b,
                .sell_exchange = .exchange_a,
                .buy_price = quote_b.ask,
                .sell_price = quote_a.bid,
                .gross_profit_bps = profit.gross_bps,
                .net_profit_bps = profit.net_bps,
                .amount = self.calculateAmount(quote_b.ask_size, quote_a.bid_size),
                .expected_profit = profit.profit,
                .detected_at = std.time.nanoTimestamp(),
            };
        }
    }

    return null;
}
```

### 数量计算

```zig
fn calculateAmount(
    self: *CrossExchangeArbitrage,
    available_buy: Decimal,
    available_sell: Decimal,
) Decimal {
    // 取三者最小值: 配置交易量、买方深度、卖方深度
    var amount = self.config.trade_amount;

    if (available_buy.lessThan(amount)) {
        amount = available_buy;
    }

    if (available_sell.lessThan(amount)) {
        amount = available_sell;
    }

    // 检查仓位限制
    const remaining_position = self.config.max_position.sub(self.current_position.abs());
    if (remaining_position.lessThan(amount)) {
        amount = remaining_position;
    }

    return amount;
}
```

---

## 利润计算

### 费用模型

```
毛利润 = 卖价 - 买价
买入费用 = 买价 × 买入费率
卖出费用 = 卖价 × 卖出费率
净利润 = 毛利润 - 买入费用 - 卖出费用
```

### 实现

```zig
pub fn calculateNetProfit(
    self: *CrossExchangeArbitrage,
    buy_price: Decimal,
    sell_price: Decimal,
) struct { gross_bps: u32, net_bps: u32, profit: Decimal } {
    const amount = self.config.trade_amount;

    // 毛利润
    const gross_profit = sell_price.sub(buy_price).mul(amount);
    const gross_bps = self.priceToBps(buy_price, sell_price);

    // 费用计算
    const buy_fee = buy_price.mul(amount).mulBps(self.config.fee_bps_a);
    const sell_fee = sell_price.mul(amount).mulBps(self.config.fee_bps_b);
    const total_fee = buy_fee.add(sell_fee);

    // 净利润
    const net_profit = gross_profit.sub(total_fee);
    const net_bps = self.profitToBps(buy_price, amount, net_profit);

    return .{
        .gross_bps = gross_bps,
        .net_bps = if (net_profit.isPositive()) net_bps else 0,
        .profit = net_profit,
    };
}

fn priceToBps(self: *CrossExchangeArbitrage, buy: Decimal, sell: Decimal) u32 {
    // (sell - buy) / buy * 10000
    const diff = sell.sub(buy);
    const ratio = diff.div(buy);
    return @intFromFloat(ratio.toFloat() * 10000);
}
```

### 滑点考虑

```zig
fn applySlippage(
    self: *CrossExchangeArbitrage,
    opportunity: ArbitrageOpportunity,
) ArbitrageOpportunity {
    var adjusted = opportunity;

    // 买入滑点: 价格可能更高
    adjusted.buy_price = opportunity.buy_price.mulBps(10000 + self.config.max_slippage_bps);

    // 卖出滑点: 价格可能更低
    adjusted.sell_price = opportunity.sell_price.mulBps(10000 - self.config.max_slippage_bps);

    // 重新计算利润
    const profit = self.calculateNetProfit(adjusted.buy_price, adjusted.sell_price);
    adjusted.net_profit_bps = profit.net_bps;
    adjusted.expected_profit = profit.profit;

    return adjusted;
}
```

---

## 订单执行

### 执行策略

**同步执行** (推荐):
两边订单同时提交，降低单边风险。

```zig
pub fn executeArbitrage(
    self: *CrossExchangeArbitrage,
    opportunity: ArbitrageOpportunity,
) !ExecutionResult {
    // 检查冷却时间
    if (self.isInCooldown()) {
        return error.Cooldown;
    }

    // 检查机会有效性
    if (!opportunity.isValid(1000)) { // 1秒有效期
        return error.OpportunityExpired;
    }

    const start_time = std.time.milliTimestamp();

    if (self.config.sync_execution) {
        return self.executeSynchronously(opportunity, start_time);
    } else {
        return self.executeSequentially(opportunity, start_time);
    }
}
```

### 同步执行实现

```zig
fn executeSynchronously(
    self: *CrossExchangeArbitrage,
    opportunity: ArbitrageOpportunity,
    start_time: i64,
) !ExecutionResult {
    // 准备两个订单
    const buy_order = Order{
        .symbol = self.config.symbol,
        .side = .buy,
        .order_type = .limit,
        .price = opportunity.buy_price,
        .quantity = opportunity.amount,
    };

    const sell_order = Order{
        .symbol = self.config.symbol,
        .side = .sell,
        .order_type = .limit,
        .price = opportunity.sell_price,
        .quantity = opportunity.amount,
    };

    // 获取对应的执行器
    const buy_executor = self.getExecutor(opportunity.buy_exchange);
    const sell_executor = self.getExecutor(opportunity.sell_exchange);

    // 并行提交订单
    var buy_result: ?OrderResult = null;
    var sell_result: ?OrderResult = null;

    // 使用线程或异步执行两个订单
    const thread_buy = try std.Thread.spawn(.{}, struct {
        fn submit(exec: *OrderExecutor, order: Order) ?OrderResult {
            return exec.submit(order) catch null;
        }
    }.submit, .{ buy_executor, buy_order });

    const thread_sell = try std.Thread.spawn(.{}, struct {
        fn submit(exec: *OrderExecutor, order: Order) ?OrderResult {
            return exec.submit(order) catch null;
        }
    }.submit, .{ sell_executor, sell_order });

    buy_result = thread_buy.join();
    sell_result = thread_sell.join();

    // 处理结果
    return self.processResults(buy_result, sell_result, opportunity, start_time);
}
```

### 结果处理

```zig
fn processResults(
    self: *CrossExchangeArbitrage,
    buy_result: ?OrderResult,
    sell_result: ?OrderResult,
    opportunity: ArbitrageOpportunity,
    start_time: i64,
) ExecutionResult {
    const end_time = std.time.milliTimestamp();
    const execution_time = @intCast(u32, end_time - start_time);

    // 两边都成功
    if (buy_result != null and sell_result != null) {
        const actual_profit = self.calculateActualProfit(
            buy_result.?.fill_price,
            buy_result.?.fill_qty,
            buy_result.?.fee,
            sell_result.?.fill_price,
            sell_result.?.fill_qty,
            sell_result.?.fee,
        );

        self.stats.successful += 1;
        self.stats.total_profit = self.stats.total_profit.add(actual_profit);

        return ExecutionResult{
            .success = true,
            .buy_fill = buy_result.?.toFill(opportunity.buy_exchange),
            .sell_fill = sell_result.?.toFill(opportunity.sell_exchange),
            .actual_profit = actual_profit,
            .execution_time_ms = execution_time,
            .error_message = null,
        };
    }

    // 单边成交，需要处理
    if (buy_result != null and sell_result == null) {
        // 买入成功，卖出失败 → 持有仓位
        self.handlePartialFill(.buy, buy_result.?);
    } else if (buy_result == null and sell_result != null) {
        // 卖出成功，买入失败 → 空头仓位
        self.handlePartialFill(.sell, sell_result.?);
    }

    self.stats.failed += 1;

    return ExecutionResult{
        .success = false,
        .buy_fill = if (buy_result) |r| r.toFill(opportunity.buy_exchange) else null,
        .sell_fill = if (sell_result) |r| r.toFill(opportunity.sell_exchange) else null,
        .actual_profit = Decimal.zero,
        .execution_time_ms = execution_time,
        .error_message = "Partial execution",
    };
}
```

---

## 风险控制

### 仓位限制

```zig
fn checkPosition(self: *CrossExchangeArbitrage, amount: Decimal) !void {
    const new_position = self.current_position.add(amount).abs();
    if (new_position.greaterThan(self.config.max_position)) {
        return error.PositionExceeded;
    }
}
```

### 冷却时间

```zig
fn isInCooldown(self: *CrossExchangeArbitrage) bool {
    const now = std.time.milliTimestamp();
    const elapsed = now - self.last_execution_time;
    return elapsed < self.config.cooldown_ms;
}
```

### 单边成交处理

```zig
fn handlePartialFill(
    self: *CrossExchangeArbitrage,
    filled_side: OrderSide,
    result: OrderResult,
) void {
    // 更新仓位
    switch (filled_side) {
        .buy => self.current_position = self.current_position.add(result.fill_qty),
        .sell => self.current_position = self.current_position.sub(result.fill_qty),
    }

    // 记录未平仓位
    self.pending_positions.append(.{
        .side = filled_side,
        .quantity = result.fill_qty,
        .price = result.fill_price,
        .timestamp = std.time.nanoTimestamp(),
    });

    // 触发告警
    self.alertPartialFill(filled_side, result);
}
```

---

## 性能优化

### 报价缓存

```zig
pub const QuoteCache = struct {
    quote_a: ?Quote = null,
    quote_b: ?Quote = null,
    last_update: i64 = 0,

    pub fn update(self: *QuoteCache, exchange: ExchangeId, quote: Quote) void {
        switch (exchange) {
            .exchange_a => self.quote_a = quote,
            .exchange_b => self.quote_b = quote,
        }
        self.last_update = std.time.nanoTimestamp();
    }

    pub fn isStale(self: *QuoteCache, max_age_ns: i64) bool {
        return std.time.nanoTimestamp() - self.last_update > max_age_ns;
    }
};
```

### 预计算费用

```zig
// 在初始化时预计算常用值
pub fn init(allocator: Allocator, config: ArbitrageConfig, ...) CrossExchangeArbitrage {
    return CrossExchangeArbitrage{
        .config = config,
        // 预计算总费率
        .total_fee_bps = config.fee_bps_a + config.fee_bps_b,
        // 预计算最小毛利润阈值
        .min_gross_bps = config.min_profit_bps + config.fee_bps_a + config.fee_bps_b,
        ...
    };
}
```

---

*Last updated: 2025-12-27*
