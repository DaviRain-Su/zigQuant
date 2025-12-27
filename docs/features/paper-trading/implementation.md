# Paper Trading 实现细节

**版本**: v0.6.0
**状态**: 📋 待开始

---

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                    PaperTradingEngine                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           HyperliquidDataProvider                    │   │
│  │     (WebSocket 连接 - 实时市场数据)                  │   │
│  └────────────────────────┬────────────────────────────┘   │
│                           │                                  │
│                           ↓ 市场数据事件                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  MessageBus                          │   │
│  └────────────────────────┬────────────────────────────┘   │
│                           │                                  │
│         ┌─────────────────┼─────────────────┐              │
│         ↓                 ↓                 ↓              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Cache     │  │  Strategy   │  │   Logger    │        │
│  │ (数据缓存) │  │ (生成信号) │  │ (日志记录) │        │
│  └─────────────┘  └──────┬──────┘  └─────────────┘        │
│                          │                                  │
│                          ↓ 交易信号                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              SimulatedExecutor                       │   │
│  │           (模拟订单执行逻辑)                         │   │
│  └────────────────────────┬────────────────────────────┘   │
│                           │                                  │
│                           ↓ 成交事件                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              SimulatedAccount                        │   │
│  │         (余额、仓位、PnL 管理)                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 数据流

### 1. 市场数据接收

```zig
fn onMarketData(self: *PaperTradingEngine, event: Event) void {
    if (!self.running.load(.seq_cst)) return;

    switch (event) {
        .market_data => |data| {
            // 1. 更新缓存
            self.cache.updateQuote(.{
                .symbol = data.instrument_id,
                .bid = Decimal.fromFloat(data.bid),
                .ask = Decimal.fromFloat(data.ask),
                .timestamp = Timestamp.fromNanos(data.timestamp),
            }) catch {};

            // 2. 传递给策略
            if (self.strategy) |strategy| {
                const signal = strategy.vtable.onData(strategy.ptr, data);

                // 3. 处理信号
                if (signal.direction != .neutral) {
                    self.executeSignal(data.instrument_id, signal);
                }
            }

            // 4. 更新未实现盈亏
            self.simulated_account.updateUnrealizedPnl(&self.cache);
        },
        else => {},
    }
}
```

### 2. 信号执行

```zig
fn executeSignal(self: *PaperTradingEngine, symbol: []const u8, signal: Signal) void {
    const quote = self.cache.getQuote(symbol) orelse return;

    // 计算订单大小
    const order_size = self.calculateOrderSize(signal, quote);
    if (order_size.isZero()) return;

    const order = Order{
        .client_order_id = generateOrderId(),
        .symbol = symbol,
        .side = if (signal.direction == .long) .buy else .sell,
        .order_type = .market,
        .quantity = order_size,
        .price = null,
    };

    self.simulated_executor.executeOrder(order) catch |err| {
        log.err("Order execution failed: {}", .{err});
    };
}

fn calculateOrderSize(self: *PaperTradingEngine, signal: Signal, quote: Quote) Decimal {
    const available = self.simulated_account.available_balance;
    const price = quote.ask;  // 买入用 ask

    // 使用信号强度调整仓位大小
    const position_pct = Decimal.fromFloat(signal.strength * 0.1);  // 最大 10%
    const notional = available.mul(position_pct);

    return notional.div(price);
}
```

---

## 模拟执行

### 市价单执行

```zig
pub fn executeOrder(self: *SimulatedExecutor, order: Order) !void {
    // 1. 获取当前报价
    const quote = self.cache.getQuote(order.symbol) orelse return error.NoQuote;

    // 2. 计算成交价格 (含滑点)
    const base_price = if (order.side == .buy) quote.ask else quote.bid;
    const slippage_adj = if (order.side == .buy)
        Decimal.one().add(self.config.slippage)
    else
        Decimal.one().sub(self.config.slippage);
    const fill_price = base_price.mul(slippage_adj);

    // 3. 计算交易成本
    const notional = fill_price.mul(order.quantity);
    const commission = notional.mul(self.config.commission_rate);

    // 4. 检查账户余额
    if (order.side == .buy) {
        const required = notional.add(commission);
        if (self.account.available_balance.lessThan(required)) {
            return error.InsufficientBalance;
        }
    } else {
        // 卖出时检查持仓
        const position = self.account.getPosition(order.symbol) orelse
            return error.NoPosition;
        if (position.quantity.lessThan(order.quantity)) {
            return error.InsufficientPosition;
        }
    }

    // 5. 创建成交记录
    const fill = OrderFill{
        .order_id = order.client_order_id,
        .symbol = order.symbol,
        .side = order.side,
        .fill_price = fill_price,
        .fill_quantity = order.quantity,
        .commission = commission,
        .timestamp = Timestamp.now(),
    };

    // 6. 更新账户
    try self.account.applyFill(fill);

    // 7. 发布事件
    self.message_bus.publish("order.filled", .{
        .order_filled = .{
            .order = .{
                .order_id = order.client_order_id,
                .instrument_id = order.symbol,
                .side = order.side,
                .price = fill_price.toFloat(),
                .filled_quantity = order.quantity.toFloat(),
                .status = .filled,
            },
            .fill_price = fill_price.toFloat(),
            .fill_quantity = order.quantity.toFloat(),
            .timestamp = fill.timestamp.nanos,
        },
    });

    // 8. 日志
    if (self.config.log_trades) {
        log.info("[PAPER] {s} {s} {d:.6} @ {d:.2} (fee: {d:.4})", .{
            if (order.side == .buy) "BUY " else "SELL",
            order.symbol,
            order.quantity.toFloat(),
            fill_price.toFloat(),
            commission.toFloat(),
        });
    }
}
```

### 限价单管理

```zig
pub fn placeLimitOrder(self: *SimulatedExecutor, order: Order) !void {
    // 添加到挂单列表
    try self.open_orders.put(order.client_order_id, order);

    log.info("[PAPER] Limit order placed: {s} {s} {d:.6} @ {d:.2}", .{
        if (order.side == .buy) "BUY " else "SELL",
        order.symbol,
        order.quantity.toFloat(),
        order.price.?.toFloat(),
    });
}

pub fn checkLimitOrders(self: *SimulatedExecutor) void {
    var it = self.open_orders.iterator();
    while (it.next()) |entry| {
        const order = entry.value_ptr.*;
        const quote = self.cache.getQuote(order.symbol) orelse continue;

        const triggered = switch (order.side) {
            .buy => quote.ask.lessThanOrEqual(order.price.?),
            .sell => quote.bid.greaterThanOrEqual(order.price.?),
        };

        if (triggered) {
            // 执行订单
            self.executeOrder(order) catch |err| {
                log.err("Limit order execution failed: {}", .{err});
            };

            // 从挂单列表移除
            _ = self.open_orders.remove(entry.key_ptr.*);
        }
    }
}
```

---

## 账户管理

### 余额更新

```zig
pub fn applyFill(self: *SimulatedAccount, fill: OrderFill) !void {
    const notional = fill.fill_price.mul(fill.fill_quantity);

    if (fill.side == .buy) {
        // 买入: 扣除资金
        self.available_balance = self.available_balance
            .sub(notional)
            .sub(fill.commission);

        // 更新仓位
        if (self.positions.getPtr(fill.symbol)) |pos| {
            // 加仓: 计算新的平均价格
            const old_value = pos.entry_price.mul(pos.quantity);
            const new_value = old_value.add(notional);
            const new_quantity = pos.quantity.add(fill.fill_quantity);
            pos.entry_price = new_value.div(new_quantity);
            pos.quantity = new_quantity;
        } else {
            // 新建仓位
            try self.positions.put(fill.symbol, .{
                .symbol = fill.symbol,
                .quantity = fill.fill_quantity,
                .entry_price = fill.fill_price,
                .side = .long,
                .unrealized_pnl = Decimal.zero(),
            });
        }
    } else {
        // 卖出
        if (self.positions.getPtr(fill.symbol)) |pos| {
            // 计算已实现盈亏
            const pnl = fill.fill_price.sub(pos.entry_price).mul(fill.fill_quantity);

            // 更新余额
            self.available_balance = self.available_balance
                .add(notional)
                .sub(fill.commission);
            self.current_balance = self.current_balance
                .add(pnl)
                .sub(fill.commission);

            // 更新仓位
            pos.quantity = pos.quantity.sub(fill.fill_quantity);
            if (pos.quantity.isZero()) {
                _ = self.positions.remove(fill.symbol);
            }

            // 记录交易
            try self.trade_history.append(.{
                .symbol = fill.symbol,
                .side = fill.side,
                .entry_price = pos.entry_price,
                .exit_price = fill.fill_price,
                .quantity = fill.fill_quantity,
                .pnl = pnl.sub(fill.commission),
                .timestamp = fill.timestamp,
            });
        }
    }

    // 更新权益曲线
    try self.updateEquityCurve();
}
```

### 未实现盈亏

```zig
pub fn updateUnrealizedPnl(self: *SimulatedAccount, cache: *Cache) void {
    var it = self.positions.iterator();
    while (it.next()) |entry| {
        const pos = entry.value_ptr;
        const quote = cache.getQuote(pos.symbol) orelse continue;

        const current_price = if (pos.side == .long) quote.bid else quote.ask;
        const price_diff = current_price.sub(pos.entry_price);
        const sign = if (pos.side == .long) Decimal.one() else Decimal.one().negate();

        pos.unrealized_pnl = price_diff.mul(pos.quantity).mul(sign);
    }
}

pub fn calculateTotalEquity(self: *SimulatedAccount) Decimal {
    var total_unrealized = Decimal.zero();

    var it = self.positions.iterator();
    while (it.next()) |entry| {
        total_unrealized = total_unrealized.add(entry.value_ptr.unrealized_pnl);
    }

    return self.current_balance.add(total_unrealized);
}
```

### 回撤计算

```zig
fn updateEquityCurve(self: *SimulatedAccount) !void {
    const equity = self.calculateTotalEquity();

    try self.equity_curve.append(.{
        .timestamp = Timestamp.now(),
        .equity = equity,
    });

    // 更新峰值
    if (equity.greaterThan(self.peak_equity)) {
        self.peak_equity = equity;
    } else {
        // 计算回撤
        const drawdown = self.peak_equity.sub(equity).div(self.peak_equity);
        if (drawdown.greaterThan(self.max_drawdown)) {
            self.max_drawdown = drawdown;
        }
    }
}
```

---

## 统计计算

```zig
pub fn getStats(self: *SimulatedAccount) Stats {
    const total_pnl = self.current_balance.sub(self.initial_balance);

    var winning_trades: usize = 0;
    var total_profit = Decimal.zero();
    var total_loss = Decimal.zero();

    for (self.trade_history.items) |trade| {
        if (trade.pnl.greaterThan(Decimal.zero())) {
            winning_trades += 1;
            total_profit = total_profit.add(trade.pnl);
        } else {
            total_loss = total_loss.add(trade.pnl.abs());
        }
    }

    const total_trades = self.trade_history.items.len;
    const win_rate = if (total_trades > 0)
        @as(f64, @floatFromInt(winning_trades)) / @as(f64, @floatFromInt(total_trades))
    else
        0;

    const profit_factor = if (!total_loss.isZero())
        total_profit.div(total_loss).toFloat()
    else if (!total_profit.isZero())
        std.math.inf(f64)
    else
        0;

    return .{
        .current_balance = self.current_balance,
        .total_pnl = total_pnl,
        .total_return_pct = total_pnl.div(self.initial_balance).mul(Decimal.fromInt(100)).toFloat(),
        .total_trades = total_trades,
        .win_rate = win_rate,
        .max_drawdown = self.max_drawdown.toFloat(),
        .profit_factor = profit_factor,
        .winning_trades = winning_trades,
        .losing_trades = total_trades - winning_trades,
    };
}
```

---

## 文件结构

```
src/trading/paper/
├── mod.zig                     # 模块入口
├── paper_trading_engine.zig    # PaperTradingEngine
├── simulated_executor.zig      # SimulatedExecutor
├── simulated_account.zig       # SimulatedAccount
├── statistics.zig              # 统计计算
└── tests/
    ├── executor_test.zig
    ├── account_test.zig
    └── integration_test.zig
```

---

*Last updated: 2025-12-27*
