# Story 031: Paper Trading

**版本**: v0.6.0
**状态**: 规划中
**优先级**: P1
**预计时间**: 3-4 天
**前置条件**: Story 029 (DataProvider)

---

## 目标

实现 Paper Trading (模拟交易) 模式，使用真实市场数据但不实际执行订单，为策略验证提供无风险的测试环境。

---

## 核心设计

### 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    PaperTradingEngine                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           HyperliquidDataProvider                    │   │
│  │              (真实市场数据)                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                         ↓                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   Strategy                           │   │
│  │              (交易策略执行)                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                         ↓                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              SimulatedExecutor                       │   │
│  │         (模拟订单执行 - 不连接交易所)                │   │
│  └─────────────────────────────────────────────────────┘   │
│                         ↓                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              SimulatedAccount                        │   │
│  │        (模拟账户余额、仓位、PnL)                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 核心接口

```zig
pub const PaperTradingEngine = struct {
    allocator: Allocator,
    config: Config,
    message_bus: MessageBus,
    cache: Cache,
    data_provider: IDataProvider,
    simulated_executor: SimulatedExecutor,
    simulated_account: SimulatedAccount,
    strategy: ?IStrategy,
    running: std.atomic.Value(bool),

    pub const Config = struct {
        initial_balance: Decimal = Decimal.fromInt(10000),
        commission_rate: Decimal = Decimal.fromFloat(0.0005),  // 0.05%
        slippage: Decimal = Decimal.fromFloat(0.0001),  // 0.01%
        symbols: []const []const u8,
        tick_interval_ms: u32 = 1000,
        log_trades: bool = true,
    };

    /// 初始化
    pub fn init(allocator: Allocator, config: Config) !PaperTradingEngine {
        var self: PaperTradingEngine = .{
            .allocator = allocator,
            .config = config,
            .message_bus = MessageBus.init(allocator),
            .cache = undefined,
            .data_provider = undefined,
            .simulated_executor = undefined,
            .simulated_account = SimulatedAccount.init(config.initial_balance),
            .strategy = null,
            .running = std.atomic.Value(bool).init(false),
        };

        self.cache = Cache.init(allocator, &self.message_bus, .{});

        // 创建真实数据提供者
        var data_provider = try HyperliquidDataProvider.init(
            allocator,
            &self.message_bus,
            &self.cache,
            .{},
        );
        self.data_provider = data_provider.asProvider();

        // 创建模拟执行器
        self.simulated_executor = SimulatedExecutor.init(
            allocator,
            &self.message_bus,
            &self.cache,
            &self.simulated_account,
            .{
                .commission_rate = config.commission_rate,
                .slippage = config.slippage,
            },
        );

        return self;
    }

    /// 设置策略
    pub fn setStrategy(self: *PaperTradingEngine, strategy: IStrategy) void {
        self.strategy = strategy;
    }

    /// 启动 Paper Trading
    pub fn start(self: *PaperTradingEngine) !void {
        if (self.strategy == null) return error.NoStrategy;

        self.running.store(true, .seq_cst);

        // 启动数据提供者
        try self.data_provider.vtable.start(self.data_provider.ptr);

        // 订阅交易对
        for (self.config.symbols) |symbol| {
            try self.data_provider.vtable.subscribe(self.data_provider.ptr, symbol);
        }

        // 订阅市场数据事件
        try self.message_bus.subscribe("market_data.*", self.onMarketData);

        log.info("Paper Trading started with {} USDT", .{self.config.initial_balance.toFloat()});
    }

    /// 停止
    pub fn stop(self: *PaperTradingEngine) void {
        self.running.store(false, .seq_cst);
        self.data_provider.vtable.stop(self.data_provider.ptr);

        // 打印最终统计
        self.printSummary();
    }

    /// 市场数据回调
    fn onMarketData(self: *PaperTradingEngine, event: Event) void {
        if (!self.running.load(.seq_cst)) return;

        switch (event) {
            .market_data => |data| {
                // 更新策略
                if (self.strategy) |strategy| {
                    const signal = strategy.vtable.onData(strategy.ptr, data);

                    if (signal.direction != .neutral) {
                        self.executeSignal(data.instrument_id, signal);
                    }
                }
            },
            else => {},
        }
    }

    /// 执行信号
    fn executeSignal(self: *PaperTradingEngine, symbol: []const u8, signal: Signal) void {
        const quote = self.cache.getQuote(symbol) orelse return;

        const order = Order{
            .client_order_id = generateOrderId(),
            .symbol = symbol,
            .side = if (signal.direction == .long) .buy else .sell,
            .order_type = .market,
            .quantity = self.calculateOrderSize(signal, quote),
            .price = null,
        };

        self.simulated_executor.executeOrder(order) catch |err| {
            log.err("Failed to execute order: {}", .{err});
        };
    }

    /// 打印统计摘要
    fn printSummary(self: *PaperTradingEngine) void {
        const stats = self.simulated_account.getStats();

        std.debug.print("\n", .{});
        std.debug.print("═══════════════════════════════════════════════════\n", .{});
        std.debug.print("              Paper Trading Summary\n", .{});
        std.debug.print("═══════════════════════════════════════════════════\n", .{});
        std.debug.print("  Initial Balance:  {d:.2} USDT\n", .{self.config.initial_balance.toFloat()});
        std.debug.print("  Final Balance:    {d:.2} USDT\n", .{stats.current_balance.toFloat()});
        std.debug.print("  Total PnL:        {d:.2} USDT ({d:.2}%)\n", .{
            stats.total_pnl.toFloat(),
            stats.total_return_pct,
        });
        std.debug.print("  Total Trades:     {d}\n", .{stats.total_trades});
        std.debug.print("  Win Rate:         {d:.1}%\n", .{stats.win_rate * 100});
        std.debug.print("  Max Drawdown:     {d:.2}%\n", .{stats.max_drawdown * 100});
        std.debug.print("═══════════════════════════════════════════════════\n", .{});
    }
};
```

---

## SimulatedExecutor 实现

```zig
pub const SimulatedExecutor = struct {
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    account: *SimulatedAccount,
    config: Config,
    open_orders: std.StringHashMap(Order),

    pub const Config = struct {
        commission_rate: Decimal,
        slippage: Decimal,
        fill_delay_ms: u32 = 0,  // 模拟填充延迟
    };

    /// 执行订单 (模拟)
    pub fn executeOrder(self: *SimulatedExecutor, order: Order) !void {
        // 获取当前报价
        const quote = self.cache.getQuote(order.symbol) orelse return error.NoQuote;

        // 计算成交价格 (含滑点)
        const base_price = if (order.side == .buy) quote.ask else quote.bid;
        const slippage_adj = if (order.side == .buy)
            Decimal.one().add(self.config.slippage)
        else
            Decimal.one().sub(self.config.slippage);
        const fill_price = base_price.mul(slippage_adj);

        // 计算手续费
        const notional = fill_price.mul(order.quantity);
        const commission = notional.mul(self.config.commission_rate);

        // 检查账户余额
        if (order.side == .buy) {
            const required = notional.add(commission);
            if (self.account.available_balance.lessThan(required)) {
                return error.InsufficientBalance;
            }
        }

        // 模拟成交
        const fill = OrderFill{
            .order_id = order.client_order_id,
            .symbol = order.symbol,
            .side = order.side,
            .fill_price = fill_price,
            .fill_quantity = order.quantity,
            .commission = commission,
            .timestamp = Timestamp.now(),
        };

        // 更新账户
        try self.account.applyFill(fill);

        // 发布事件
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
                .timestamp = Timestamp.now().nanos,
            },
        });

        if (self.config.log_trades) {
            log.info("[PAPER] {s} {s} {d:.4} @ {d:.2}", .{
                if (order.side == .buy) "BUY" else "SELL",
                order.symbol,
                order.quantity.toFloat(),
                fill_price.toFloat(),
            });
        }
    }
};
```

---

## SimulatedAccount 实现

```zig
pub const SimulatedAccount = struct {
    initial_balance: Decimal,
    current_balance: Decimal,
    available_balance: Decimal,
    positions: std.StringHashMap(Position),
    trade_history: std.ArrayList(Trade),
    equity_curve: std.ArrayList(EquityPoint),
    peak_equity: Decimal,
    max_drawdown: Decimal,

    pub const Position = struct {
        symbol: []const u8,
        quantity: Decimal,
        entry_price: Decimal,
        side: Side,
        unrealized_pnl: Decimal,
    };

    pub fn init(initial_balance: Decimal) SimulatedAccount {
        return .{
            .initial_balance = initial_balance,
            .current_balance = initial_balance,
            .available_balance = initial_balance,
            .positions = std.StringHashMap(Position).init(allocator),
            .trade_history = std.ArrayList(Trade).init(allocator),
            .equity_curve = std.ArrayList(EquityPoint).init(allocator),
            .peak_equity = initial_balance,
            .max_drawdown = Decimal.zero(),
        };
    }

    /// 应用成交
    pub fn applyFill(self: *SimulatedAccount, fill: OrderFill) !void {
        const notional = fill.fill_price.mul(fill.fill_quantity);

        if (fill.side == .buy) {
            // 扣除成本
            self.available_balance = self.available_balance.sub(notional).sub(fill.commission);

            // 更新或创建仓位
            if (self.positions.getPtr(fill.symbol)) |pos| {
                // 加仓
                const new_qty = pos.quantity.add(fill.fill_quantity);
                const new_cost = pos.entry_price.mul(pos.quantity).add(notional);
                pos.entry_price = new_cost.div(new_qty);
                pos.quantity = new_qty;
            } else {
                // 新仓位
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
                self.available_balance = self.available_balance.add(notional).sub(fill.commission);
                self.current_balance = self.current_balance.add(pnl).sub(fill.commission);

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
                    .pnl = pnl,
                    .timestamp = fill.timestamp,
                });
            }
        }

        // 更新权益曲线
        try self.updateEquityCurve();
    }

    /// 更新权益曲线和回撤
    fn updateEquityCurve(self: *SimulatedAccount) !void {
        const equity = self.calculateTotalEquity();

        try self.equity_curve.append(.{
            .timestamp = Timestamp.now(),
            .equity = equity,
        });

        // 更新峰值和回撤
        if (equity.greaterThan(self.peak_equity)) {
            self.peak_equity = equity;
        } else {
            const drawdown = self.peak_equity.sub(equity).div(self.peak_equity);
            if (drawdown.greaterThan(self.max_drawdown)) {
                self.max_drawdown = drawdown;
            }
        }
    }

    /// 获取统计信息
    pub fn getStats(self: *SimulatedAccount) Stats {
        const total_pnl = self.current_balance.sub(self.initial_balance);
        const winning_trades = countWinningTrades(self.trade_history.items);

        return .{
            .current_balance = self.current_balance,
            .total_pnl = total_pnl,
            .total_return_pct = total_pnl.div(self.initial_balance).mul(Decimal.fromInt(100)).toFloat(),
            .total_trades = self.trade_history.items.len,
            .win_rate = if (self.trade_history.items.len > 0)
                @as(f64, @floatFromInt(winning_trades)) / @as(f64, @floatFromInt(self.trade_history.items.len))
            else
                0,
            .max_drawdown = self.max_drawdown.toFloat(),
        };
    }
};
```

---

## CLI 命令

```zig
// src/cli/commands/run_strategy.zig

pub fn runStrategy(args: Args) !void {
    if (args.paper) {
        // Paper Trading 模式
        var engine = try PaperTradingEngine.init(allocator, .{
            .initial_balance = Decimal.fromFloat(args.balance orelse 10000),
            .symbols = args.symbols,
        });
        defer engine.deinit();

        // 加载策略
        const strategy = try loadStrategy(args.strategy);
        engine.setStrategy(strategy);

        // 启动
        try engine.start();

        // 运行直到中断
        while (engine.running.load(.seq_cst)) {
            std.time.sleep(100 * std.time.ns_per_ms);
        }
    } else if (args.live) {
        // 实盘模式 (需要 API 密钥)
        // ...
    }
}
```

### 使用示例

```bash
# 基本使用
zigquant run-strategy --strategy dual_ma --paper

# 指定初始资金
zigquant run-strategy --strategy dual_ma --paper --balance 50000

# 指定交易对
zigquant run-strategy --strategy dual_ma --paper --symbol BTC --symbol ETH

# 详细日志
zigquant run-strategy --strategy dual_ma --paper --verbose
```

---

## 成功指标

| 指标 | 目标 | 说明 |
|------|------|------|
| 实时数据延迟 | < 10ms | 使用真实市场数据 |
| 订单模拟精度 | > 99% | 考虑滑点和手续费 |
| 内存占用 | < 50MB | 长时间运行稳定 |
| 统计准确性 | 100% | 与回测结果可比较 |

---

**Story**: 031
**状态**: 规划中
**创建时间**: 2025-12-27
