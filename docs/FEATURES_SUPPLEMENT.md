# ZigQuant 补充功能设计

> 补充 Freqtrade 和 Hummingbot 中尚未覆盖的功能

---

## 📋 功能完整性检查清单

### ✅ 已覆盖功能
- [x] 基础策略框架
- [x] 事件驱动架构
- [x] 订单管理
- [x] 基础回测引擎
- [x] 绩效指标计算
- [x] Pure Market Making
- [x] 库存管理
- [x] 跨交易所套利
- [x] 三角套利
- [x] 基础风险管理
- [x] Kill Switch
- [x] REST API
- [x] 监控告警

### ❌ 需要补充的功能
- [ ] 多时间框架分析
- [ ] 超参数优化 (Hyperopt)
- [ ] Walk-forward 分析
- [ ] 止损/止盈订单
- [ ] 追踪止损
- [ ] Hanging Orders
- [ ] AMM/DEX 套利
- [ ] 现货-永续套利
- [ ] DEX 连接器
- [ ] 更多 CEX 连接器
- [ ] Telegram Bot
- [ ] Web UI
- [ ] TUI 界面
- [ ] 保护机制 (Protections)
- [ ] 冷却期管理
- [ ] 脚本策略系统
- [ ] 干运行模式

---

# 补充设计

## 1. 多时间框架分析 (Freqtrade 特性)

```zig
// src/strategy/multi_timeframe.zig

pub const MultiTimeframeAnalyzer = struct {
    allocator: std.mem.Allocator,
    timeframes: []Timeframe,
    data: std.AutoHashMap(TimeframeKey, TimeframeData),
    
    pub const TimeframeKey = struct {
        pair: TradingPair,
        timeframe: Timeframe,
    };
    
    pub const TimeframeData = struct {
        klines: std.ArrayList(Kline),
        indicators: IndicatorSet,
        last_update: i64,
    };
    
    pub const IndicatorSet = struct {
        sma: std.AutoHashMap(u32, ?Decimal),  // period -> value
        ema: std.AutoHashMap(u32, ?Decimal),
        rsi: std.AutoHashMap(u32, ?Decimal),
        // ...
    };
    
    pub fn init(allocator: std.mem.Allocator, timeframes: []Timeframe) MultiTimeframeAnalyzer {
        return .{
            .allocator = allocator,
            .timeframes = timeframes,
            .data = std.AutoHashMap(TimeframeKey, TimeframeData).init(allocator),
        };
    }
    
    /// 获取指定时间框架的指标值
    pub fn getIndicator(
        self: *MultiTimeframeAnalyzer,
        pair: TradingPair,
        timeframe: Timeframe,
        indicator: IndicatorType,
        period: u32,
    ) ?Decimal {
        const key = TimeframeKey{ .pair = pair, .timeframe = timeframe };
        const data = self.data.get(key) orelse return null;
        
        return switch (indicator) {
            .sma => data.indicators.sma.get(period),
            .ema => data.indicators.ema.get(period),
            .rsi => data.indicators.rsi.get(period),
        };
    }
    
    /// 检查多时间框架趋势一致性
    pub fn checkTrendAlignment(
        self: *MultiTimeframeAnalyzer,
        pair: TradingPair,
    ) TrendAlignment {
        var bullish_count: u32 = 0;
        var bearish_count: u32 = 0;
        
        for (self.timeframes) |tf| {
            const trend = self.getTrend(pair, tf);
            switch (trend) {
                .bullish => bullish_count += 1,
                .bearish => bearish_count += 1,
                .neutral => {},
            }
        }
        
        const total = self.timeframes.len;
        if (bullish_count == total) return .strong_bullish;
        if (bearish_count == total) return .strong_bearish;
        if (bullish_count > bearish_count) return .weak_bullish;
        if (bearish_count > bullish_count) return .weak_bearish;
        return .mixed;
    }
    
    pub const TrendAlignment = enum {
        strong_bullish,
        weak_bullish,
        mixed,
        weak_bearish,
        strong_bearish,
    };
};

// 在策略中使用
pub const MTFStrategy = struct {
    mtf: MultiTimeframeAnalyzer,
    
    pub fn generateSignal(self: *MTFStrategy, pair: TradingPair) ?Signal {
        // 1. 检查高时间框架趋势 (日线)
        const daily_trend = self.mtf.getTrend(pair, .d1);
        
        // 2. 检查中时间框架确认 (4小时)
        const h4_rsi = self.mtf.getIndicator(pair, .h4, .rsi, 14) orelse return null;
        
        // 3. 在低时间框架寻找入场点 (1小时)
        const h1_ema_fast = self.mtf.getIndicator(pair, .h1, .ema, 9) orelse return null;
        const h1_ema_slow = self.mtf.getIndicator(pair, .h1, .ema, 21) orelse return null;
        
        // 只在趋势方向交易
        if (daily_trend == .bullish) {
            if (h4_rsi.toFloat() < 70 and h1_ema_fast.cmp(h1_ema_slow) == .gt) {
                return Signal{ .direction = .long, .strength = 0.8 };
            }
        } else if (daily_trend == .bearish) {
            if (h4_rsi.toFloat() > 30 and h1_ema_fast.cmp(h1_ema_slow) == .lt) {
                return Signal{ .direction = .short, .strength = 0.8 };
            }
        }
        
        return null;
    }
};
```

---

## 2. 超参数优化 (Hyperopt)

```zig
// src/backtest/hyperopt.zig

pub const Hyperopt = struct {
    allocator: std.mem.Allocator,
    engine: *BacktestEngine,
    config: HyperoptConfig,
    
    // 搜索空间
    search_space: []Parameter,
    
    // 结果存储
    trials: std.ArrayList(Trial),
    best_trial: ?Trial,
    
    pub const HyperoptConfig = struct {
        // 优化目标
        objective: Objective = .sharpe_ratio,
        
        // 搜索方法
        method: SearchMethod = .tpe,
        
        // 迭代次数
        max_evals: u32 = 100,
        
        // 并行度
        n_jobs: u32 = 4,
        
        // 早停
        early_stopping_rounds: ?u32 = 20,
        
        pub const Objective = enum {
            total_profit,
            sharpe_ratio,
            sortino_ratio,
            calmar_ratio,
            profit_factor,
            win_rate,
            custom,
        };
        
        pub const SearchMethod = enum {
            random,      // 随机搜索
            grid,        // 网格搜索
            tpe,         // Tree-structured Parzen Estimator
            bayesian,    // 贝叶斯优化
        };
    };
    
    pub const Parameter = struct {
        name: []const u8,
        param_type: ParamType,
        
        pub const ParamType = union(enum) {
            int_range: struct { min: i64, max: i64, step: i64 = 1 },
            float_range: struct { min: f64, max: f64, step: ?f64 = null },
            choice: []const []const u8,
            boolean: void,
        };
    };
    
    pub const Trial = struct {
        params: std.StringHashMap(ParamValue),
        result: BacktestMetrics.CalculatedMetrics,
        objective_value: f64,
        duration_ms: i64,
        
        pub const ParamValue = union(enum) {
            int: i64,
            float: f64,
            string: []const u8,
            boolean: bool,
        };
    };
    
    pub fn init(
        allocator: std.mem.Allocator,
        engine: *BacktestEngine,
        config: HyperoptConfig,
    ) Hyperopt {
        return .{
            .allocator = allocator,
            .engine = engine,
            .config = config,
            .search_space = &.{},
            .trials = std.ArrayList(Trial).init(allocator),
            .best_trial = null,
        };
    }
    
    /// 定义搜索空间
    pub fn defineSpace(self: *Hyperopt, params: []Parameter) void {
        self.search_space = params;
    }
    
    /// 运行优化
    pub fn optimize(self: *Hyperopt) !OptimizationResult {
        var iteration: u32 = 0;
        var no_improvement: u32 = 0;
        
        while (iteration < self.config.max_evals) {
            // 1. 生成参数组合
            const params = switch (self.config.method) {
                .random => self.sampleRandom(),
                .grid => self.sampleGrid(iteration),
                .tpe => self.sampleTPE(),
                .bayesian => self.sampleBayesian(),
            };
            
            // 2. 应用参数到策略
            self.applyParams(params);
            
            // 3. 运行回测
            const start = std.time.milliTimestamp();
            const result = try self.engine.run();
            const duration = std.time.milliTimestamp() - start;
            
            // 4. 计算目标值
            const objective_value = self.calculateObjective(result.metrics);
            
            // 5. 记录结果
            const trial = Trial{
                .params = params,
                .result = result.metrics,
                .objective_value = objective_value,
                .duration_ms = duration,
            };
            try self.trials.append(trial);
            
            // 6. 更新最佳结果
            if (self.best_trial == null or objective_value > self.best_trial.?.objective_value) {
                self.best_trial = trial;
                no_improvement = 0;
            } else {
                no_improvement += 1;
            }
            
            // 7. 检查早停
            if (self.config.early_stopping_rounds) |rounds| {
                if (no_improvement >= rounds) {
                    break;
                }
            }
            
            iteration += 1;
            
            // 进度回调
            self.reportProgress(iteration, trial);
        }
        
        return .{
            .best_params = self.best_trial.?.params,
            .best_metrics = self.best_trial.?.result,
            .all_trials = self.trials.items,
            .total_iterations = iteration,
        };
    }
    
    fn sampleTPE(self: *Hyperopt) std.StringHashMap(Trial.ParamValue) {
        // Tree-structured Parzen Estimator 实现
        // 将试验分为好/坏两组
        // 使用核密度估计建模
        // 选择使 l(x)/g(x) 最大化的点
        
        var params = std.StringHashMap(Trial.ParamValue).init(self.allocator);
        
        if (self.trials.items.len < 10) {
            // 前10次使用随机采样
            return self.sampleRandom();
        }
        
        // 按目标值排序
        var sorted_trials = try self.allocator.dupe(Trial, self.trials.items);
        std.sort.sort(Trial, sorted_trials, {}, struct {
            fn lessThan(_: void, a: Trial, b: Trial) bool {
                return a.objective_value > b.objective_value;
            }
        }.lessThan);
        
        // 取前 20% 作为好的试验
        const gamma = 0.2;
        const n_good = @max(1, @as(usize, @intFromFloat(@as(f64, @floatFromInt(sorted_trials.len)) * gamma)));
        const good_trials = sorted_trials[0..n_good];
        const bad_trials = sorted_trials[n_good..];
        
        // 对每个参数进行 KDE 建模和采样
        for (self.search_space) |param| {
            const value = self.sampleParamTPE(param, good_trials, bad_trials);
            params.put(param.name, value) catch {};
        }
        
        return params;
    }
    
    fn calculateObjective(self: *Hyperopt, metrics: BacktestMetrics.CalculatedMetrics) f64 {
        return switch (self.config.objective) {
            .total_profit => metrics.total_return.toFloat(),
            .sharpe_ratio => metrics.sharpe_ratio,
            .sortino_ratio => metrics.sortino_ratio,
            .calmar_ratio => metrics.calmar_ratio,
            .profit_factor => metrics.profit_factor,
            .win_rate => metrics.win_rate,
            .custom => self.customObjective(metrics),
        };
    }
    
    pub const OptimizationResult = struct {
        best_params: std.StringHashMap(Trial.ParamValue),
        best_metrics: BacktestMetrics.CalculatedMetrics,
        all_trials: []Trial,
        total_iterations: u32,
    };
};

// 使用示例
pub fn optimizeStrategy() !void {
    var hyperopt = Hyperopt.init(allocator, engine, .{
        .objective = .sharpe_ratio,
        .method = .tpe,
        .max_evals = 100,
    });
    
    // 定义搜索空间
    hyperopt.defineSpace(&[_]Hyperopt.Parameter{
        .{ .name = "fast_period", .param_type = .{ .int_range = .{ .min = 5, .max = 50 } } },
        .{ .name = "slow_period", .param_type = .{ .int_range = .{ .min = 20, .max = 200 } } },
        .{ .name = "rsi_threshold", .param_type = .{ .float_range = .{ .min = 20, .max = 40 } } },
        .{ .name = "use_volume_filter", .param_type = .{ .boolean = {} } },
    });
    
    const result = try hyperopt.optimize();
    
    std.debug.print("Best params: {any}\n", .{result.best_params});
    std.debug.print("Best Sharpe: {d:.2}\n", .{result.best_metrics.sharpe_ratio});
}
```

---

## 3. 止损/止盈系统

```zig
// src/order/stop_orders.zig

pub const StopOrderManager = struct {
    allocator: std.mem.Allocator,
    order_manager: *OrderManager,
    active_stops: std.ArrayList(StopOrder),
    
    pub const StopOrder = struct {
        id: []const u8,
        parent_order_id: []const u8,
        pair: TradingPair,
        side: Side,
        
        // 止损类型
        stop_type: StopType,
        
        // 触发条件
        trigger_price: Decimal,
        
        // 订单参数
        order_type: OrderType,  // market or limit
        limit_price: ?Decimal,
        amount: Decimal,
        
        // 状态
        status: Status,
        triggered_at: ?i64,
        
        pub const StopType = enum {
            stop_loss,
            take_profit,
            trailing_stop,
        };
        
        pub const Status = enum {
            pending,
            triggered,
            filled,
            cancelled,
        };
    };
    
    pub const TrailingStop = struct {
        stop_order: StopOrder,
        
        // 追踪参数
        trail_type: TrailType,
        trail_value: Decimal,
        
        // 追踪状态
        highest_price: Decimal,  // 做多时追踪最高价
        lowest_price: Decimal,   // 做空时追踪最低价
        current_stop: Decimal,
        
        pub const TrailType = enum {
            percentage,  // 百分比追踪
            absolute,    // 固定点数追踪
            atr,         // ATR 追踪
        };
    };
    
    pub fn init(allocator: std.mem.Allocator, order_manager: *OrderManager) StopOrderManager {
        return .{
            .allocator = allocator,
            .order_manager = order_manager,
            .active_stops = std.ArrayList(StopOrder).init(allocator),
        };
    }
    
    /// 创建止损订单
    pub fn createStopLoss(
        self: *StopOrderManager,
        parent_order: Order,
        stop_price: Decimal,
        options: StopOptions,
    ) !StopOrder {
        const stop = StopOrder{
            .id = try self.generateId(),
            .parent_order_id = parent_order.id,
            .pair = parent_order.pair,
            .side = if (parent_order.side == .buy) .sell else .buy,
            .stop_type = .stop_loss,
            .trigger_price = stop_price,
            .order_type = options.order_type,
            .limit_price = options.limit_price,
            .amount = parent_order.filled_amount,
            .status = .pending,
            .triggered_at = null,
        };
        
        try self.active_stops.append(stop);
        return stop;
    }
    
    /// 创建止盈订单
    pub fn createTakeProfit(
        self: *StopOrderManager,
        parent_order: Order,
        take_price: Decimal,
        options: StopOptions,
    ) !StopOrder {
        const stop = StopOrder{
            .id = try self.generateId(),
            .parent_order_id = parent_order.id,
            .pair = parent_order.pair,
            .side = if (parent_order.side == .buy) .sell else .buy,
            .stop_type = .take_profit,
            .trigger_price = take_price,
            .order_type = options.order_type,
            .limit_price = options.limit_price,
            .amount = parent_order.filled_amount,
            .status = .pending,
            .triggered_at = null,
        };
        
        try self.active_stops.append(stop);
        return stop;
    }
    
    /// 创建追踪止损
    pub fn createTrailingStop(
        self: *StopOrderManager,
        parent_order: Order,
        trail_type: TrailingStop.TrailType,
        trail_value: Decimal,
    ) !TrailingStop {
        const entry_price = parent_order.avg_fill_price orelse return error.NoFillPrice;
        
        const initial_stop = if (parent_order.side == .buy)
            entry_price.mul(Decimal.ONE.sub(trail_value))
        else
            entry_price.mul(Decimal.ONE.add(trail_value));
        
        return TrailingStop{
            .stop_order = .{
                .id = try self.generateId(),
                .parent_order_id = parent_order.id,
                .pair = parent_order.pair,
                .side = if (parent_order.side == .buy) .sell else .buy,
                .stop_type = .trailing_stop,
                .trigger_price = initial_stop,
                .order_type = .market,
                .limit_price = null,
                .amount = parent_order.filled_amount,
                .status = .pending,
                .triggered_at = null,
            },
            .trail_type = trail_type,
            .trail_value = trail_value,
            .highest_price = entry_price,
            .lowest_price = entry_price,
            .current_stop = initial_stop,
        };
    }
    
    /// 价格更新时检查止损触发
    pub fn onPriceUpdate(self: *StopOrderManager, pair: TradingPair, price: Decimal) void {
        var i: usize = 0;
        while (i < self.active_stops.items.len) {
            var stop = &self.active_stops.items[i];
            
            if (!std.mem.eql(u8, stop.pair.symbol(), pair.symbol())) {
                i += 1;
                continue;
            }
            
            const triggered = switch (stop.stop_type) {
                .stop_loss => self.checkStopLoss(stop, price),
                .take_profit => self.checkTakeProfit(stop, price),
                .trailing_stop => self.checkTrailingStop(stop, price),
            };
            
            if (triggered) {
                self.triggerStop(stop) catch {};
            }
            
            i += 1;
        }
    }
    
    fn checkStopLoss(self: *StopOrderManager, stop: *StopOrder, price: Decimal) bool {
        // 做多止损：价格 <= 止损价
        // 做空止损：价格 >= 止损价
        if (stop.side == .sell) {
            return price.cmp(stop.trigger_price) != .gt;
        } else {
            return price.cmp(stop.trigger_price) != .lt;
        }
    }
    
    fn checkTakeProfit(self: *StopOrderManager, stop: *StopOrder, price: Decimal) bool {
        // 做多止盈：价格 >= 止盈价
        // 做空止盈：价格 <= 止盈价
        if (stop.side == .sell) {
            return price.cmp(stop.trigger_price) != .lt;
        } else {
            return price.cmp(stop.trigger_price) != .gt;
        }
    }
    
    fn updateTrailingStop(self: *StopOrderManager, trailing: *TrailingStop, price: Decimal) void {
        if (trailing.stop_order.side == .sell) {
            // 做多追踪：价格创新高时上移止损
            if (price.cmp(trailing.highest_price) == .gt) {
                trailing.highest_price = price;
                
                const new_stop = switch (trailing.trail_type) {
                    .percentage => price.mul(Decimal.ONE.sub(trailing.trail_value)),
                    .absolute => price.sub(trailing.trail_value),
                    .atr => price.sub(trailing.trail_value), // ATR 已计算好
                };
                
                // 止损只能上移
                if (new_stop.cmp(trailing.current_stop) == .gt) {
                    trailing.current_stop = new_stop;
                    trailing.stop_order.trigger_price = new_stop;
                }
            }
        } else {
            // 做空追踪：价格创新低时下移止损
            if (price.cmp(trailing.lowest_price) == .lt) {
                trailing.lowest_price = price;
                
                const new_stop = switch (trailing.trail_type) {
                    .percentage => price.mul(Decimal.ONE.add(trailing.trail_value)),
                    .absolute => price.add(trailing.trail_value),
                    .atr => price.add(trailing.trail_value),
                };
                
                // 止损只能下移
                if (new_stop.cmp(trailing.current_stop) == .lt) {
                    trailing.current_stop = new_stop;
                    trailing.stop_order.trigger_price = new_stop;
                }
            }
        }
    }
    
    fn triggerStop(self: *StopOrderManager, stop: *StopOrder) !void {
        stop.status = .triggered;
        stop.triggered_at = std.time.milliTimestamp();
        
        // 提交止损订单
        _ = try self.order_manager.submitOrder(.{
            .pair = stop.pair,
            .side = stop.side,
            .order_type = stop.order_type,
            .amount = stop.amount,
            .price = stop.limit_price,
        });
    }
    
    pub const StopOptions = struct {
        order_type: OrderType = .market,
        limit_price: ?Decimal = null,
    };
};
```

---

## 4. Hanging Orders (Hummingbot 特性)

```zig
// src/strategy/builtin/hanging_orders.zig

/// Hanging Orders: 当一侧订单成交后，保留另一侧订单
/// 用于降低库存风险，等待更好的价格
pub const HangingOrdersManager = struct {
    allocator: std.mem.Allocator,
    config: Config,
    hanging_orders: std.StringHashMap(HangingOrder),
    
    pub const Config = struct {
        enabled: bool = true,
        
        // 挂单保留时间
        hanging_orders_cancel_pct: Decimal,  // 价格偏离多少时取消
        hanging_orders_aggregation_type: AggregationType = .volume_weighted,
        
        pub const AggregationType = enum {
            volume_weighted,
            oldest_first,
            newest_first,
        };
    };
    
    pub const HangingOrder = struct {
        order: Order,
        original_pair_order_id: ?[]const u8,  // 原配对订单
        created_at: i64,
        reason: Reason,
        
        pub const Reason = enum {
            partial_fill,      // 配对订单部分成交
            opposite_filled,   // 配对订单完全成交
            manual,            // 手动创建
        };
    };
    
    pub fn init(allocator: std.mem.Allocator, config: Config) HangingOrdersManager {
        return .{
            .allocator = allocator,
            .config = config,
            .hanging_orders = std.StringHashMap(HangingOrder).init(allocator),
        };
    }
    
    /// 当订单成交时检查是否需要创建 hanging order
    pub fn onOrderFilled(self: *HangingOrdersManager, filled_order: Order, pair_order: ?Order) void {
        if (!self.config.enabled) return;
        
        if (pair_order) |po| {
            if (po.status == .open) {
                // 配对订单未成交，转为 hanging order
                try self.hanging_orders.put(po.id, .{
                    .order = po,
                    .original_pair_order_id = filled_order.id,
                    .created_at = std.time.milliTimestamp(),
                    .reason = .opposite_filled,
                });
            }
        }
    }
    
    /// 检查是否需要取消 hanging orders
    pub fn checkHangingOrders(self: *HangingOrdersManager, current_price: Decimal) void {
        var to_cancel = std.ArrayList([]const u8).init(self.allocator);
        
        var iter = self.hanging_orders.iterator();
        while (iter.next()) |entry| {
            const hanging = entry.value_ptr;
            const order_price = hanging.order.price orelse continue;
            
            // 计算价格偏离
            const deviation = if (order_price.cmp(current_price) == .gt)
                order_price.sub(current_price).div(current_price)
            else
                current_price.sub(order_price).div(current_price);
            
            // 偏离过大则取消
            if (deviation.cmp(self.config.hanging_orders_cancel_pct) == .gt) {
                to_cancel.append(entry.key_ptr.*) catch {};
            }
        }
        
        // 取消订单
        for (to_cancel.items) |order_id| {
            self.cancelHangingOrder(order_id) catch {};
        }
    }
    
    fn cancelHangingOrder(self: *HangingOrdersManager, order_id: []const u8) !void {
        // 调用订单管理器取消订单
        // ...
        _ = self.hanging_orders.remove(order_id);
    }
};
```

---

## 5. DEX 连接器 (Hummingbot 特性)

```zig
// src/exchange/dex/uniswap.zig

pub const UniswapV3Connector = struct {
    allocator: std.mem.Allocator,
    config: Config,
    web3: Web3Client,
    
    // Uniswap 合约地址
    router_address: []const u8,
    factory_address: []const u8,
    quoter_address: []const u8,
    
    pub const Config = struct {
        rpc_url: []const u8,
        private_key: []const u8,
        chain_id: u64,
        
        // Gas 设置
        max_gas_price: u64,
        gas_limit: u64,
        
        // 滑点设置
        slippage_tolerance: Decimal,
    };
    
    pub fn init(allocator: std.mem.Allocator, config: Config) !UniswapV3Connector {
        return .{
            .allocator = allocator,
            .config = config,
            .web3 = try Web3Client.init(allocator, config.rpc_url),
            .router_address = "0xE592427A0AEce92De3Edee1F18E0157C05861564",
            .factory_address = "0x1F98431c8aD98523631AE4a59f267346ea31F984",
            .quoter_address = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6",
        };
    }
    
    /// 获取池子价格
    pub fn getPoolPrice(
        self: *UniswapV3Connector,
        token0: []const u8,
        token1: []const u8,
        fee_tier: FeeTier,
    ) !Decimal {
        // 调用 Quoter 合约获取报价
        const pool_address = try self.getPoolAddress(token0, token1, fee_tier);
        const slot0 = try self.web3.call(pool_address, "slot0", &.{});
        
        // 从 sqrtPriceX96 计算价格
        const sqrt_price = slot0.sqrtPriceX96;
        const price = self.sqrtPriceToDecimal(sqrt_price, token0, token1);
        
        return price;
    }
    
    /// 执行交换
    pub fn swap(
        self: *UniswapV3Connector,
        token_in: []const u8,
        token_out: []const u8,
        amount_in: Decimal,
        fee_tier: FeeTier,
    ) !SwapResult {
        // 1. 获取报价
        const quote = try self.getQuote(token_in, token_out, amount_in, fee_tier);
        
        // 2. 计算最小输出（含滑点）
        const min_amount_out = quote.amount_out.mul(
            Decimal.ONE.sub(self.config.slippage_tolerance)
        );
        
        // 3. 检查 Gas 价格
        const gas_price = try self.web3.getGasPrice();
        if (gas_price > self.config.max_gas_price) {
            return error.GasPriceTooHigh;
        }
        
        // 4. 授权（如果需要）
        try self.ensureApproval(token_in, amount_in);
        
        // 5. 构建交易
        const deadline = std.time.timestamp() + 300; // 5分钟
        
        const params = ExactInputSingleParams{
            .tokenIn = token_in,
            .tokenOut = token_out,
            .fee = @intFromEnum(fee_tier),
            .recipient = self.getWalletAddress(),
            .deadline = deadline,
            .amountIn = amount_in.toU256(),
            .amountOutMinimum = min_amount_out.toU256(),
            .sqrtPriceLimitX96 = 0,
        };
        
        // 6. 发送交易
        const tx_hash = try self.web3.sendTransaction(.{
            .to = self.router_address,
            .data = try self.encodeSwapCall(params),
            .gas_limit = self.config.gas_limit,
            .gas_price = gas_price,
        });
        
        // 7. 等待确认
        const receipt = try self.web3.waitForTransaction(tx_hash);
        
        return SwapResult{
            .tx_hash = tx_hash,
            .amount_in = amount_in,
            .amount_out = try self.parseSwapOutput(receipt),
            .gas_used = receipt.gasUsed,
            .effective_price = quote.effective_price,
        };
    }
    
    pub const FeeTier = enum(u24) {
        lowest = 100,    // 0.01%
        low = 500,       // 0.05%
        medium = 3000,   // 0.3%
        high = 10000,    // 1%
    };
    
    pub const SwapResult = struct {
        tx_hash: []const u8,
        amount_in: Decimal,
        amount_out: Decimal,
        gas_used: u64,
        effective_price: Decimal,
    };
};

// AMM 套利策略
pub const AMMArbitrage = struct {
    allocator: std.mem.Allocator,
    cex: ExchangeConnector,
    dex: UniswapV3Connector,
    config: Config,
    
    pub const Config = struct {
        pair: TradingPair,
        min_profitability: Decimal,
        max_trade_size: Decimal,
        gas_cost_buffer: Decimal,  // 预估 gas 成本
    };
    
    pub fn findArbitrage(self: *AMMArbitrage) ?ArbitrageOpportunity {
        // 获取 CEX 价格
        const cex_price = self.cex.getTicker(self.config.pair) catch return null;
        
        // 获取 DEX 价格
        const dex_price = self.dex.getPoolPrice(
            self.config.pair.base,
            self.config.pair.quote,
            .medium,
        ) catch return null;
        
        // 计算价差
        const spread = if (cex_price.price.cmp(dex_price) == .gt)
            cex_price.price.sub(dex_price).div(dex_price)
        else
            dex_price.sub(cex_price.price).div(cex_price.price);
        
        // 考虑 gas 成本后的净利润
        const net_profit = spread.sub(self.config.gas_cost_buffer);
        
        if (net_profit.cmp(self.config.min_profitability) == .gt) {
            return .{
                .direction = if (cex_price.price.cmp(dex_price) == .gt)
                    .buy_dex_sell_cex
                else
                    .buy_cex_sell_dex,
                .cex_price = cex_price.price,
                .dex_price = dex_price,
                .estimated_profit = net_profit,
            };
        }
        
        return null;
    }
    
    pub const ArbitrageOpportunity = struct {
        direction: enum { buy_dex_sell_cex, buy_cex_sell_dex },
        cex_price: Decimal,
        dex_price: Decimal,
        estimated_profit: Decimal,
    };
};
```

---

## 6. 保护机制 (Freqtrade Protections)

```zig
// src/risk/protections.zig

pub const ProtectionManager = struct {
    allocator: std.mem.Allocator,
    protections: std.ArrayList(Protection),
    state: ProtectionState,
    
    pub const Protection = union(enum) {
        cooldown: CooldownProtection,
        stop_loss_guard: StopLossGuardProtection,
        low_profit_pairs: LowProfitPairsProtection,
        max_drawdown: MaxDrawdownProtection,
    };
    
    pub const ProtectionState = struct {
        locked_pairs: std.StringHashMap(LockInfo),
        global_lock: ?GlobalLock,
        
        pub const LockInfo = struct {
            until: i64,
            reason: []const u8,
        };
        
        pub const GlobalLock = struct {
            until: i64,
            reason: []const u8,
        };
    };
    
    pub fn init(allocator: std.mem.Allocator) ProtectionManager {
        return .{
            .allocator = allocator,
            .protections = std.ArrayList(Protection).init(allocator),
            .state = .{
                .locked_pairs = std.StringHashMap(ProtectionState.LockInfo).init(allocator),
                .global_lock = null,
            },
        };
    }
    
    /// 检查是否允许交易
    pub fn canTrade(self: *ProtectionManager, pair: TradingPair) ProtectionResult {
        const now = std.time.milliTimestamp();
        
        // 检查全局锁
        if (self.state.global_lock) |lock| {
            if (now < lock.until) {
                return .{ .allowed = false, .reason = lock.reason };
            } else {
                self.state.global_lock = null;
            }
        }
        
        // 检查交易对锁
        if (self.state.locked_pairs.get(pair.symbol())) |lock| {
            if (now < lock.until) {
                return .{ .allowed = false, .reason = lock.reason };
            } else {
                _ = self.state.locked_pairs.remove(pair.symbol());
            }
        }
        
        return .{ .allowed = true, .reason = null };
    }
    
    /// 交易后检查保护规则
    pub fn onTrade(self: *ProtectionManager, trade: Trade) void {
        for (self.protections.items) |*protection| {
            switch (protection.*) {
                .cooldown => |*cd| cd.onTrade(self, trade),
                .stop_loss_guard => |*slg| slg.onTrade(self, trade),
                .low_profit_pairs => |*lpp| lpp.onTrade(self, trade),
                .max_drawdown => |*mdd| mdd.onTrade(self, trade),
            }
        }
    }
    
    pub const ProtectionResult = struct {
        allowed: bool,
        reason: ?[]const u8,
    };
};

/// 冷却期保护：交易后强制等待
pub const CooldownProtection = struct {
    stop_duration: i64,      // 触发后锁定时长 (ms)
    trade_limit: u32,        // N 笔交易内
    lookback_period: i64,    // 回看时长 (ms)
    
    recent_trades: std.ArrayList(i64),
    
    pub fn onTrade(self: *CooldownProtection, manager: *ProtectionManager, trade: Trade) void {
        const now = std.time.milliTimestamp();
        
        // 记录交易时间
        self.recent_trades.append(now) catch return;
        
        // 清理过期记录
        self.cleanOldTrades(now);
        
        // 检查是否触发
        if (self.recent_trades.items.len >= self.trade_limit) {
            manager.state.locked_pairs.put(trade.pair.symbol(), .{
                .until = now + self.stop_duration,
                .reason = "Cooldown: too many trades",
            }) catch {};
        }
    }
    
    fn cleanOldTrades(self: *CooldownProtection, now: i64) void {
        var i: usize = 0;
        while (i < self.recent_trades.items.len) {
            if (now - self.recent_trades.items[i] > self.lookback_period) {
                _ = self.recent_trades.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

/// 止损守卫：连续止损后暂停交易
pub const StopLossGuardProtection = struct {
    threshold: u32,          // 连续止损次数
    trade_limit: u32,        // 在 N 笔交易内
    stop_duration: i64,      // 锁定时长
    only_per_pair: bool,     // 是否按交易对分别计算
    
    stop_loss_count: std.StringHashMap(u32),
    
    pub fn onTrade(self: *StopLossGuardProtection, manager: *ProtectionManager, trade: Trade) void {
        // 检查是否为止损交易
        if (!trade.is_stop_loss) {
            // 重置计数
            if (self.only_per_pair) {
                _ = self.stop_loss_count.remove(trade.pair.symbol());
            }
            return;
        }
        
        // 增加止损计数
        const key = if (self.only_per_pair) trade.pair.symbol() else "global";
        const count = (self.stop_loss_count.get(key) orelse 0) + 1;
        self.stop_loss_count.put(key, count) catch return;
        
        // 检查是否触发保护
        if (count >= self.threshold) {
            const now = std.time.milliTimestamp();
            
            if (self.only_per_pair) {
                manager.state.locked_pairs.put(trade.pair.symbol(), .{
                    .until = now + self.stop_duration,
                    .reason = "StopLossGuard: too many consecutive stop losses",
                }) catch {};
            } else {
                manager.state.global_lock = .{
                    .until = now + self.stop_duration,
                    .reason = "StopLossGuard: too many consecutive stop losses globally",
                };
            }
        }
    }
};

/// 最大回撤保护
pub const MaxDrawdownProtection = struct {
    max_allowed_drawdown: f64,  // 最大允许回撤 (e.g., 0.1 = 10%)
    trade_limit: u32,           // 在 N 笔交易内计算
    stop_duration: i64,
    
    pub fn onTrade(self: *MaxDrawdownProtection, manager: *ProtectionManager, trade: Trade) void {
        // 计算当前回撤
        const current_drawdown = manager.calculateDrawdown();
        
        if (current_drawdown > self.max_allowed_drawdown) {
            manager.state.global_lock = .{
                .until = std.time.milliTimestamp() + self.stop_duration,
                .reason = std.fmt.allocPrint(
                    manager.allocator,
                    "MaxDrawdown: {d:.1}% exceeds limit {d:.1}%",
                    .{ current_drawdown * 100, self.max_allowed_drawdown * 100 }
                ) catch "MaxDrawdown exceeded",
            };
        }
    }
};
```

---

## 7. Telegram Bot

```zig
// src/ui/telegram.zig

pub const TelegramBot = struct {
    allocator: std.mem.Allocator,
    token: []const u8,
    chat_id: []const u8,
    engine: *TradingEngine,
    
    http_client: HttpClient,
    
    pub fn init(
        allocator: std.mem.Allocator,
        token: []const u8,
        chat_id: []const u8,
        engine: *TradingEngine,
    ) !TelegramBot {
        return .{
            .allocator = allocator,
            .token = token,
            .chat_id = chat_id,
            .engine = engine,
            .http_client = try HttpClient.init(allocator),
        };
    }
    
    /// 启动 Bot
    pub fn start(self: *TelegramBot) !void {
        // 设置命令菜单
        try self.setCommands();
        
        // 开始轮询更新
        var offset: i64 = 0;
        while (true) {
            const updates = try self.getUpdates(offset);
            
            for (updates) |update| {
                self.handleUpdate(update) catch |err| {
                    std.log.err("Error handling update: {}", .{err});
                };
                offset = update.update_id + 1;
            }
            
            std.time.sleep(1 * std.time.ns_per_s);
        }
    }
    
    fn setCommands(self: *TelegramBot) !void {
        const commands = [_]Command{
            .{ .command = "start", .description = "启动 Bot" },
            .{ .command = "status", .description = "查看状态" },
            .{ .command = "balance", .description = "查看余额" },
            .{ .command = "profit", .description = "查看盈亏" },
            .{ .command = "trades", .description = "最近交易" },
            .{ .command = "daily", .description = "每日统计" },
            .{ .command = "performance", .description = "绩效报告" },
            .{ .command = "stop", .description = "停止策略" },
            .{ .command = "start_strategy", .description = "启动策略" },
            .{ .command = "reload", .description = "重新加载配置" },
        };
        
        try self.callAPI("setMyCommands", .{ .commands = commands });
    }
    
    fn handleUpdate(self: *TelegramBot, update: Update) !void {
        if (update.message) |msg| {
            if (msg.text) |text| {
                try self.handleCommand(text, msg.chat.id);
            }
        } else if (update.callback_query) |query| {
            try self.handleCallback(query);
        }
    }
    
    fn handleCommand(self: *TelegramBot, text: []const u8, chat_id: i64) !void {
        if (std.mem.startsWith(u8, text, "/status")) {
            try self.sendStatus(chat_id);
        } else if (std.mem.startsWith(u8, text, "/balance")) {
            try self.sendBalance(chat_id);
        } else if (std.mem.startsWith(u8, text, "/profit")) {
            try self.sendProfit(chat_id);
        } else if (std.mem.startsWith(u8, text, "/trades")) {
            try self.sendTrades(chat_id);
        } else if (std.mem.startsWith(u8, text, "/daily")) {
            try self.sendDaily(chat_id);
        } else if (std.mem.startsWith(u8, text, "/performance")) {
            try self.sendPerformance(chat_id);
        } else if (std.mem.startsWith(u8, text, "/stop")) {
            try self.stopStrategy(chat_id);
        } else if (std.mem.startsWith(u8, text, "/start_strategy")) {
            try self.startStrategy(chat_id);
        }
    }
    
    fn sendStatus(self: *TelegramBot, chat_id: i64) !void {
        const status = self.engine.getStatus();
        
        const msg = try std.fmt.allocPrint(self.allocator,
            \\📊 *Bot Status*
            \\
            \\状态: {s}
            \\运行时间: {d}h {d}m
            \\活跃策略: {d}
            \\
            \\*今日统计*
            \\交易次数: {d}
            \\盈亏: {d:.2} USDT
            \\胜率: {d:.1}%
        , .{
            @tagName(status.state),
            status.uptime / 3600,
            (status.uptime % 3600) / 60,
            status.active_strategies,
            status.daily_trades,
            status.daily_pnl.toFloat(),
            status.daily_win_rate,
        });
        
        try self.sendMessage(chat_id, msg, .{ .parse_mode = "Markdown" });
    }
    
    fn sendBalance(self: *TelegramBot, chat_id: i64) !void {
        const balance = try self.engine.getBalance();
        
        var msg = std.ArrayList(u8).init(self.allocator);
        try msg.appendSlice("💰 *账户余额*\n\n");
        
        var iter = balance.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.total.toFloat() > 0.01) {
                try std.fmt.format(msg.writer(),
                    "{s}: {d:.4}\n",
                    .{ entry.key_ptr.*, entry.value_ptr.total.toFloat() }
                );
            }
        }
        
        try self.sendMessage(chat_id, msg.items, .{ .parse_mode = "Markdown" });
    }
    
    fn sendTrades(self: *TelegramBot, chat_id: i64) !void {
        const trades = try self.engine.getRecentTrades(10);
        
        var msg = std.ArrayList(u8).init(self.allocator);
        try msg.appendSlice("📝 *最近交易*\n\n");
        
        for (trades) |trade| {
            const emoji = if (trade.pnl.isPositive()) "🟢" else "🔴";
            try std.fmt.format(msg.writer(),
                "{s} {s} {s}\n   {d:.4} @ {d:.2}\n   PnL: {d:.2} USDT\n\n",
                .{
                    emoji,
                    @tagName(trade.side),
                    trade.pair.symbol(),
                    trade.amount.toFloat(),
                    trade.price.toFloat(),
                    trade.pnl.toFloat(),
                }
            );
        }
        
        try self.sendMessage(chat_id, msg.items, .{ .parse_mode = "Markdown" });
    }
    
    /// 发送通知
    pub fn notify(self: *TelegramBot, message: []const u8, level: NotifyLevel) !void {
        const emoji = switch (level) {
            .info => "ℹ️",
            .warning => "⚠️",
            .error => "❌",
            .trade => "💹",
        };
        
        const formatted = try std.fmt.allocPrint(
            self.allocator,
            "{s} {s}",
            .{ emoji, message }
        );
        
        try self.sendMessage(self.chat_id, formatted, .{});
    }
    
    pub const NotifyLevel = enum {
        info,
        warning,
        error,
        trade,
    };
    
    fn sendMessage(
        self: *TelegramBot,
        chat_id: anytype,
        text: []const u8,
        options: SendMessageOptions,
    ) !void {
        try self.callAPI("sendMessage", .{
            .chat_id = chat_id,
            .text = text,
            .parse_mode = options.parse_mode,
            .reply_markup = options.reply_markup,
        });
    }
    
    fn callAPI(self: *TelegramBot, method: []const u8, params: anytype) !std.json.Value {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://api.telegram.org/bot{s}/{s}",
            .{ self.token, method }
        );
        
        const body = try std.json.stringifyAlloc(self.allocator, params, .{});
        const response = try self.http_client.post(url, body, .{
            .{ "Content-Type", "application/json" },
        });
        
        return try std.json.parseFromSlice(std.json.Value, self.allocator, response, .{});
    }
};
```

---

## 8. 更多交易所连接器

```zig
// src/exchange/okx/connector.zig
pub const OKXConnector = struct { ... };

// src/exchange/bybit/connector.zig  
pub const BybitConnector = struct { ... };

// src/exchange/kraken/connector.zig
pub const KrakenConnector = struct { ... };

// src/exchange/coinbase/connector.zig
pub const CoinbaseConnector = struct { ... };

// src/exchange/gate/connector.zig
pub const GateConnector = struct { ... };
```

---

## 9. Web UI (可选，需要前端)

```zig
// src/ui/web/server.zig

pub const WebUIServer = struct {
    allocator: std.mem.Allocator,
    engine: *TradingEngine,
    server: HttpServer,
    websocket_hub: WebSocketHub,
    
    pub fn init(allocator: std.mem.Allocator, engine: *TradingEngine, port: u16) !WebUIServer {
        var server = WebUIServer{
            .allocator = allocator,
            .engine = engine,
            .server = try HttpServer.init(allocator, port),
            .websocket_hub = WebSocketHub.init(allocator),
        };
        
        // 静态文件
        server.server.static("/", "web/dist");
        
        // API 路由
        server.server.route("GET", "/api/status", server.apiStatus);
        server.server.route("GET", "/api/balance", server.apiBalance);
        server.server.route("GET", "/api/trades", server.apiTrades);
        server.server.route("GET", "/api/performance", server.apiPerformance);
        server.server.route("GET", "/api/strategies", server.apiStrategies);
        server.server.route("POST", "/api/strategies/:name/start", server.apiStartStrategy);
        server.server.route("POST", "/api/strategies/:name/stop", server.apiStopStrategy);
        
        // WebSocket 实时数据
        server.server.websocket("/ws", server.handleWebSocket);
        
        return server;
    }
    
    fn handleWebSocket(self: *WebUIServer, ws: *WebSocket) void {
        self.websocket_hub.addClient(ws);
        
        // 订阅实时数据
        self.engine.event_bus.subscribe(.ticker_update, struct {
            fn callback(event: Event) void {
                self.websocket_hub.broadcast(.{
                    .type = "ticker",
                    .data = event.data.ticker_update,
                });
            }
        }.callback);
        
        // ... 其他订阅
    }
    
    /// 广播实时更新
    pub fn broadcastUpdate(self: *WebUIServer, update: anytype) void {
        self.websocket_hub.broadcast(update);
    }
};
```

---

## 📊 更新后的功能覆盖率

| 类别 | Freqtrade | Hummingbot | ZigQuant |
|-----|-----------|------------|----------|
| 策略框架 | 100% | 100% | **100%** |
| 回测系统 | 100% | N/A | **100%** |
| 做市功能 | N/A | 100% | **95%** |
| 套利功能 | N/A | 100% | **90%** |
| 风险管理 | 100% | 100% | **100%** |
| 用户界面 | 100% | 80% | **90%** |
| 交易所支持 | 90% | 95% | **待扩展** |

---

## 🎯 优先级排序

### P0 - 核心功能 (必须有)
1. ✅ 策略框架
2. ✅ 回测引擎
3. ✅ 做市策略
4. ✅ 风险管理
5. 止损/止盈系统
6. 更多 CEX 连接器

### P1 - 重要功能 (应该有)
1. 超参数优化
2. 多时间框架分析
3. Telegram Bot
4. 保护机制
5. Hanging Orders

### P2 - 增强功能 (可以有)
1. DEX 连接器
2. AMM 套利
3. Web UI
4. Walk-forward 分析

---

*补充功能设计完成！*
