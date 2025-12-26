# zigQuant 核心架构模式参考

**创建时间**: 2024-12-26
**来源**: [竞争分析](./COMPETITIVE_ANALYSIS.md) - NautilusTrader/Hummingbot/Freqtrade 深度研究
**用途**: 后续开发的快速参考指南

---

## 📚 快速索引

1. [MessageBus 消息总线](#messagebus-消息总线) (NautilusTrader)
2. [Cache 高性能缓存](#cache-高性能缓存) (NautilusTrader)
3. [订单前置追踪](#订单前置追踪) (Hummingbot)
4. [向量化回测](#向量化回测) (Freqtrade)
5. [Clock-Driven 模式](#clock-driven-模式) (Hummingbot)
6. [Crash Recovery 崩溃恢复](#crash-recovery-崩溃恢复) (NautilusTrader)

---

## MessageBus 消息总线

> 来源: **NautilusTrader**
> 实施版本: **v0.5.0**

### 核心理念

单线程高效消息传递系统,避免线程切换开销,类似 Actor 模型。

### Zig 实现伪代码

```zig
pub const MessageBus = struct {
    allocator: Allocator,
    subscribers: StringHashMap(ArrayList(Handler)),
    endpoints: StringHashMap(RequestHandler),

    pub const Handler = *const fn(Event) void;
    pub const RequestHandler = *const fn(Request) anyerror!Response;

    /// Publish-Subscribe 模式
    pub fn publish(self: *MessageBus, topic: []const u8, event: Event) !void {
        if (self.subscribers.get(topic)) |handlers| {
            for (handlers.items) |handler| {
                handler(event);
            }
        }
    }

    /// 订阅事件
    pub fn subscribe(self: *MessageBus, topic: []const u8, handler: Handler) !void {
        const entry = try self.subscribers.getOrPut(topic);
        if (!entry.found_existing) {
            entry.value_ptr.* = ArrayList(Handler).init(self.allocator);
        }
        try entry.value_ptr.append(handler);
    }

    /// Request-Response 模式
    pub fn request(self: *MessageBus, endpoint: []const u8, req: Request) !Response {
        if (self.endpoints.get(endpoint)) |handler| {
            return try handler(req);
        }
        return error.EndpointNotFound;
    }

    /// 注册 endpoint
    pub fn register(self: *MessageBus, endpoint: []const u8, handler: RequestHandler) !void {
        try self.endpoints.put(endpoint, handler);
    }

    /// Command 模式 (fire-and-forget)
    pub fn send(self: *MessageBus, command: Command) void {
        // 直接执行命令,不等待响应
        command.execute();
    }
};
```

### 使用场景

- **DataEngine** → 发布 `market_data.orderbook_update` 事件
- **Strategy** → 订阅 `market_data.*` 事件
- **ExecutionEngine** → 处理 `order.submit` 命令
- **RiskEngine** → 验证 `order.submit` 请求

### 关键优势

- ✅ 解耦组件 (DataEngine 不知道 Strategy 的存在)
- ✅ 单线程 → 无锁,无竞态
- ✅ 可扩展 (新组件只需订阅/发布)

---

## Cache 高性能缓存

> 来源: **NautilusTrader**
> 实施版本: **v0.5.0**

### 核心理念

内存缓存常用对象 (订单、仓位、账户),避免重复查询,提供纳秒级访问。

### Zig 实现伪代码

```zig
pub const Cache = struct {
    allocator: Allocator,

    // 核心缓存
    instruments: StringHashMap(Instrument),
    orders: StringHashMap(Order),
    positions: StringHashMap(Position),
    accounts: StringHashMap(Account),

    // 索引
    orders_open: StringHashMap(*Order),
    orders_closed: StringHashMap(*Order),

    /// 获取订单 (纳秒级)
    pub fn getOrder(self: *Cache, order_id: []const u8) ?*Order {
        return self.orders.get(order_id);
    }

    /// 获取所有开仓订单
    pub fn getOpenOrders(self: *Cache) []const *Order {
        var result = ArrayList(*Order).init(self.allocator);
        var iter = self.orders_open.valueIterator();
        while (iter.next()) |order| {
            result.append(order.*) catch unreachable;
        }
        return result.items;
    }

    /// 更新订单状态
    pub fn updateOrder(self: *Cache, order: Order) !void {
        try self.orders.put(order.id, order);

        // 更新索引
        if (order.status == .open) {
            try self.orders_open.put(order.id, &order);
            _ = self.orders_closed.remove(order.id);
        } else {
            try self.orders_closed.put(order.id, &order);
            _ = self.orders_open.remove(order.id);
        }
    }

    /// 获取仓位
    pub fn getPosition(self: *Cache, instrument_id: []const u8) ?Position {
        return self.positions.get(instrument_id);
    }

    /// 更新仓位
    pub fn updatePosition(self: *Cache, position: Position) !void {
        try self.positions.put(position.instrument_id, position);
    }
};
```

### 使用场景

- **Strategy** → 快速查询当前仓位
- **ExecutionEngine** → 检查订单状态
- **RiskEngine** → 计算账户总风险敞口
- **PerformanceAnalyzer** → 统计订单胜率

### 关键优势

- ✅ 纳秒级访问速度
- ✅ 避免数据库查询
- ✅ 单一数据源 (single source of truth)

---

## 订单前置追踪

> 来源: **Hummingbot**
> 实施版本: **v0.5.0** (ExecutionEngine 重构)

### 核心理念

在提交订单到交易所**之前**就开始追踪,防止 API 超时/失败导致订单丢失。

### 问题场景

```
❌ 传统流程:
1. submitOrder() → API 调用
2. API 超时/失败 → 订单状态未知
3. 策略不知道订单是否已提交
4. 可能重复下单或遗漏订单

✅ Hummingbot 流程:
1. trackOrder() → 立即保存到本地 pending_orders
2. submitOrder() → API 调用
3. 如果 API 超时:
   - WebSocket 监听订单更新
   - 收到成交确认 → 从 pending 移到 tracked
   - 超时仍未确认 → 查询订单状态
4. 零订单丢失
```

### Zig 实现伪代码

```zig
pub const OrderTracker = struct {
    allocator: Allocator,

    // 前置追踪 (提交前)
    pending_orders: StringHashMap(Order),

    // 已追踪 (已提交)
    tracked_orders: StringHashMap(Order),

    /// 步骤 1: 前置追踪
    pub fn trackOrder(self: *Self, order: Order) !void {
        try self.pending_orders.put(order.client_order_id, order);
        logger.debug("Order pre-tracked: {s}", .{order.client_order_id});
    }

    /// 步骤 2: 提交订单
    pub fn submitOrder(self: *Self, order: Order) !void {
        defer {
            // 无论成功失败,都从 pending 移除
            _ = self.pending_orders.remove(order.client_order_id);
        }

        // 提交到交易所
        const exchange_order_id = try self.exchange.submitOrder(order);

        // 关联 client_order_id → exchange_order_id
        order.exchange_order_id = exchange_order_id;

        // 移到 tracked
        try self.tracked_orders.put(order.client_order_id, order);
        logger.info("Order submitted and tracked: {s}", .{order.client_order_id});
    }

    /// WebSocket 回调: 订单更新
    pub fn onOrderUpdate(self: *Self, update: OrderUpdate) !void {
        // 检查是否是 pending 订单
        if (self.pending_orders.get(update.client_order_id)) |order| {
            logger.info("Pending order confirmed: {s}", .{order.client_order_id});
            _ = self.pending_orders.remove(order.client_order_id);
            try self.tracked_orders.put(order.client_order_id, order);
        }

        // 更新已追踪订单
        if (self.tracked_orders.getPtr(update.client_order_id)) |order| {
            order.status = update.status;
            order.filled_qty = update.filled_qty;
        }
    }
};
```

### 使用场景

- **高延迟网络** (DEX 链上交易)
- **API 不稳定** (超时、重试)
- **可靠性要求高** (生产环境)

### 关键优势

- ✅ 零订单丢失
- ✅ API 失败容错
- ✅ 可靠性 > 简单性

---

## 向量化回测

> 来源: **Freqtrade**
> 实施版本: **v0.6.0**

### 核心理念

批量计算指标和信号,而不是逐根 K 线迭代,利用 SIMD 和缓存局部性。

### 传统 vs 向量化

```zig
// ❌ 传统逐根计算 (慢)
for (candles) |candle, i| {
    const sma = calculateSMA(candles[0..i+1], 20);
    const signal = if (candle.close > sma) .buy else .sell;
}

// ✅ 向量化批量计算 (快 10-100x)
const sma_values = calculateSMABatch(candles, 20);  // 一次性计算所有
const signals = generateSignalsBatch(candles, sma_values);
```

### Zig 实现伪代码

```zig
pub const VectorizedBacktest = struct {
    /// 批量计算 SMA
    pub fn calculateSMABatch(candles: []Candle, period: usize) ![]Decimal {
        var result = try allocator.alloc(Decimal, candles.len);

        // SIMD 优化: 4 个价格同时求和
        var i: usize = period - 1;
        while (i < candles.len) : (i += 1) {
            var sum: Decimal = Decimal.zero;
            for (candles[i - period + 1..i + 1]) |c| {
                sum = sum.add(c.close);
            }
            result[i] = sum.div(Decimal.fromInt(period));
        }

        return result;
    }

    /// 批量生成信号
    pub fn generateSignalsBatch(
        candles: []Candle,
        sma: []Decimal,
    ) ![]Signal {
        var signals = try allocator.alloc(Signal, candles.len);

        for (candles, sma, signals) |candle, sma_val, *signal| {
            signal.* = if (candle.close.gt(sma_val)) .buy else .sell;
        }

        return signals;
    }

    /// Look-ahead Bias 保护
    pub fn populateIndicators(strategy: *IStrategy, candles: []Candle) !void {
        // ⚠️ 重要: 只使用当前和历史数据,不能访问未来数据
        for (candles, 0..) |candle, i| {
            const historical = candles[0..i+1];  // 只看到当前及之前
            strategy.indicators[i] = calculateIndicators(historical);
        }
    }
};
```

### 使用场景

- **回测** (历史数据已全部可用)
- **批量分析** (参数优化时大量回测)
- **研究** (快速迭代策略想法)

### 关键优势

- ✅ 回测速度 10-100x
- ✅ 利用 SIMD 和缓存
- ✅ 适合参数优化

### 注意事项

- ⚠️ **不适合实盘** (实时数据逐笔到达)
- ⚠️ **Look-ahead Bias** (必须防止访问未来数据)

---

## Clock-Driven 模式

> 来源: **Hummingbot**
> 实施版本: **v0.7.0**

### 核心理念

定时 Tick 驱动策略,适合做市等需要定期更新报价的场景。

### Event-Driven vs Clock-Driven

```
Event-Driven (趋势策略):
  OrderbookUpdate → Strategy.onOrderbook() → 可能生成信号
  每次事件都可能触发策略

Clock-Driven (做市策略):
  每 1 秒 → Strategy.tick() → 更新双边报价
  定时执行,不关心每次 OrderbookUpdate
```

### Zig 实现伪代码

```zig
pub const ClockDrivenStrategy = struct {
    clock: Clock,
    tick_interval: Duration,  // 1 秒

    pub fn start(self: *Self) !void {
        while (self.is_running) {
            self.clock.waitUntilNextTick(self.tick_interval);

            // 每秒执行一次
            try self.onTick();
        }
    }

    /// 每秒调用一次
    pub fn onTick(self: *Self) !void {
        // 1. 获取最新订单簿
        const book = self.exchange.getOrderbook();

        // 2. 计算最优报价
        const mid_price = book.midPrice();
        const spread = self.config.spread;

        const bid_price = mid_price.sub(spread.div(Decimal.two));
        const ask_price = mid_price.add(spread.div(Decimal.two));

        // 3. 取消旧订单
        try self.cancelAllOrders();

        // 4. 下新订单
        try self.placeOrder(.buy, bid_price, self.config.order_amount);
        try self.placeOrder(.sell, ask_price, self.config.order_amount);
    }
};
```

### 使用场景

- **做市策略** (定期更新双边报价)
- **网格交易** (定期检查价格区间)
- **定投策略** (定时买入)

### 关键优势

- ✅ 简单可预测 (每秒固定执行)
- ✅ 适合定期操作 (挂单刷新)
- ✅ 易于调试 (时间可控)

---

## Crash Recovery 崩溃恢复

> 来源: **NautilusTrader** "Crash-only design"
> 实施版本: **v0.8.0**

### 核心理念

**崩溃恢复即主初始化路径** - 系统启动时总是假设上次崩溃,从持久化状态恢复。

### 传统 vs Crash-only

```
❌ 传统设计:
  正常启动: init() → 加载配置 → 启动组件
  崩溃恢复: init() → 加载配置 → recover() → 启动组件
  (两条路径,增加复杂度)

✅ Crash-only 设计:
  启动 (总是): init() → recover_from_state() → 启动组件
  (单一路径,总是从持久化状态恢复)
```

### Zig 实现伪代码

```zig
pub const TradingSystem = struct {
    state_db: StateDatabase,  // zig-sqlite

    /// 启动总是走恢复路径
    pub fn start(self: *Self) !void {
        logger.info("Starting system (crash-recovery mode)...");

        // 1. 恢复缓存
        try self.recoverCache();

        // 2. 恢复订单
        try self.recoverOrders();

        // 3. 恢复仓位
        try self.recoverPositions();

        // 4. 重连交易所
        try self.reconnectExchanges();

        logger.info("System recovered and running");
    }

    /// 从数据库恢复缓存
    fn recoverCache(self: *Self) !void {
        const orders = try self.state_db.loadOrders();
        for (orders) |order| {
            try self.cache.updateOrder(order);
        }

        const positions = try self.state_db.loadPositions();
        for (positions) |pos| {
            try self.cache.updatePosition(pos);
        }
    }

    /// 恢复挂单 (重新提交到交易所)
    fn recoverOrders(self: *Self) !void {
        const open_orders = self.cache.getOpenOrders();

        for (open_orders) |order| {
            // 查询交易所确认订单状态
            const status = try self.exchange.queryOrder(order.id);

            if (status == .cancelled or status == .rejected) {
                // 订单已失效,更新状态
                order.status = status;
                try self.cache.updateOrder(order);
            } else {
                // 订单仍有效,重新追踪
                try self.order_tracker.trackExisting(order);
            }
        }
    }

    /// 每次状态变化都持久化
    pub fn onOrderFilled(self: *Self, order: Order) !void {
        // 1. 更新缓存
        order.status = .filled;
        try self.cache.updateOrder(order);

        // 2. 持久化 (立即写入数据库)
        try self.state_db.saveOrder(order);

        // 3. 更新仓位
        try self.updatePosition(order);
    }
};
```

### 使用场景

- **生产环境** (必须快速恢复)
- **长期运行** (不可避免的崩溃)
- **高可靠性要求** (零数据丢失)

### 关键优势

- ✅ 简化设计 (单一初始化路径)
- ✅ 强制状态持久化
- ✅ 快速恢复 (< 1 分钟)

---

## 实施优先级

根据 [roadmap.md](../../roadmap.md),推荐实施顺序:

### v0.5.0 (3-4 周)
1. **MessageBus** (2 周) - 核心基础设施
2. **Cache** (1 周) - 高性能访问
3. **订单前置追踪** (1 周) - 可靠性

### v0.6.0 (2-3 周)
4. **向量化回测** (2 周) - 速度优化

### v0.7.0 (2-3 周)
5. **Clock-Driven** (1 周) - 做市支持

### v0.8.0 (2-3 周)
6. **Crash Recovery** (2 周) - 生产级可靠性

---

## 参考资料

- [竞争分析完整版](./COMPETITIVE_ANALYSIS.md)
- [Roadmap](../../roadmap.md)
- [NEXT_STEPS](../NEXT_STEPS.md)

---

**最后更新**: 2024-12-26
**作者**: Claude (Sonnet 4.5)
