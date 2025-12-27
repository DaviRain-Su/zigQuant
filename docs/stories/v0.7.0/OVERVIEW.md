# v0.7.0 Overview - 做市策略与回测精度

**版本**: v0.7.0
**状态**: 规划中
**开始时间**: 待定
**前置版本**: v0.6.0 (已完成)
**预计时间**: 3-4 周
**参考**:
- [竞争分析 - Hummingbot 做市](../../architecture/COMPETITIVE_ANALYSIS.md)
- [架构模式 - Clock-Driven/Queue Position/Dual Latency](../../architecture/ARCHITECTURE_PATTERNS.md)

---

## 目标

实现专业做市策略和高精度回测系统。借鉴 Hummingbot 的 Clock-Driven 架构和 HFTBacktest 的精度建模，为 zigQuant 增加生产级做市能力。

## 核心理念

```
┌─────────────────────────────────────────────────────────────────┐
│                   zigQuant v0.7.0                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              做市策略 (Market Making)                     │   │
│  │                                                            │   │
│  │  ┌─────────────────┐    ┌─────────────────┐              │   │
│  │  │  Clock-Driven   │    │  Pure MM        │              │   │
│  │  │  (Tick驱动模式) │    │  (做市策略)     │              │   │
│  │  └─────────────────┘    └─────────────────┘              │   │
│  │           ↓                      ↓                        │   │
│  │  ┌─────────────────┐    ┌─────────────────┐              │   │
│  │  │  Inventory Mgmt │    │  Cross-Exchange │              │   │
│  │  │  (库存管理)     │    │  (套利策略)     │              │   │
│  │  └─────────────────┘    └─────────────────┘              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                         ↓                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              回测精度 (Backtest Accuracy)                 │   │
│  │                                                            │   │
│  │  ┌─────────────────┐    ┌─────────────────┐              │   │
│  │  │ Queue Position  │    │  Dual Latency   │              │   │
│  │  │ (队列位置建模)  │    │  (延迟模拟)     │              │   │
│  │  └─────────────────┘    └─────────────────┘              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                         ↓                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              数据持久化 (Data Persistence)                │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐                 │   │
│  │  │ zig-sqlite│ │ K线存储  │ │回测结果  │                 │   │
│  │  └──────────┘ └──────────┘ └──────────┘                 │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Stories 规划

| Story | 名称 | 描述 | 优先级 | 预计时间 |
|-------|------|------|--------|----------|
| **033** | Clock-Driven 模式 | Tick 驱动策略执行 | P0 | 3-4 天 |
| **034** | Pure Market Making 策略 | 双边报价做市 | P0 | 3-4 天 |
| **035** | Inventory Management | 库存风险管理 | P1 | 2-3 天 |
| **036** | zig-sqlite 数据持久化 | K 线和回测结果存储 | P1 | 3-4 天 |
| **037** | Cross-Exchange Arbitrage | 跨交易所套利 | P2 | 3-4 天 |
| **038** | Queue Position Modeling | 队列位置建模 (HFTBacktest) | P1 | 3-4 天 |
| **039** | Dual Latency Simulation | 双向延迟模拟 (HFTBacktest) | P1 | 2-3 天 |

**总计**: 7 个 Stories, 预计 3-4 周

---

## Story 033: Clock-Driven 模式

### 目标
实现定时 Tick 驱动的策略执行模式，适合做市等需要定期更新报价的场景。

### Event-Driven vs Clock-Driven

```
Event-Driven (趋势策略):
  OrderbookUpdate → Strategy.onOrderbook() → 可能生成信号
  每次事件都可能触发策略

Clock-Driven (做市策略):
  每 1 秒 → Strategy.tick() → 更新双边报价
  定时执行,不关心每次 OrderbookUpdate
```

### 核心功能

```zig
pub const Clock = struct {
    tick_interval: Duration,  // 默认 1 秒
    strategies: ArrayList(*IClockStrategy),
    running: std.atomic.Value(bool),
    tick_count: u64,

    /// 启动时钟
    pub fn start(self: *Clock) !void {
        self.running.store(true, .seq_cst);

        while (self.running.load(.seq_cst)) {
            const tick_start = std.time.nanoTimestamp();
            self.tick_count += 1;

            // 触发所有策略的 tick
            for (self.strategies.items) |strategy| {
                try strategy.onTick(self.tick_count, tick_start);
            }

            // 等待下一个 tick
            const elapsed = std.time.nanoTimestamp() - tick_start;
            const sleep_time = self.tick_interval.nanos - elapsed;
            if (sleep_time > 0) {
                std.time.sleep(@intCast(sleep_time));
            }
        }
    }

    /// 停止时钟
    pub fn stop(self: *Clock) void {
        self.running.store(false, .seq_cst);
    }
};

/// Clock-Driven 策略接口
pub const IClockStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        onTick: *const fn (ptr: *anyopaque, tick: u64, timestamp: i128) anyerror!void,
        onStart: *const fn (ptr: *anyopaque) anyerror!void,
        onStop: *const fn (ptr: *anyopaque) void,
    };
};
```

### 详细文档
- [STORY_033_CLOCK_DRIVEN.md](./STORY_033_CLOCK_DRIVEN.md)

---

## Story 034: Pure Market Making 策略

### 目标
实现基础做市策略，在 mid price 两侧放置买卖单。

### 核心功能

```zig
/// Pure Market Making 策略
pub const PureMarketMaking = struct {
    // 配置
    spread_bps: u32,           // 价差 (basis points, 如 10 = 0.1%)
    order_amount: Decimal,     // 单边订单数量
    order_levels: u32,         // 价格层级数 (每边)
    level_spread_bps: u32,     // 层级间价差

    // 状态
    active_bids: ArrayList(OrderId),
    active_asks: ArrayList(OrderId),
    last_mid_price: ?Decimal,

    /// 实现 IClockStrategy
    pub fn onTick(self: *Self, tick: u64, timestamp: i128) !void {
        // 1. 获取当前 mid price
        const mid = self.getMidPrice() orelse return;

        // 2. 检查是否需要更新报价
        if (self.shouldUpdateQuotes(mid)) {
            try self.cancelAllOrders();
            try self.placeNewQuotes(mid);
        }

        self.last_mid_price = mid;
    }
};
```

### 策略参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `spread_bps` | 买卖价差 (basis points) | 10 (0.1%) |
| `order_amount` | 单边订单数量 | 0.1 |
| `order_levels` | 价格层级数 | 3 |
| `level_spread_bps` | 层级间价差 | 5 (0.05%) |

### 详细文档
- [STORY_034_PURE_MM.md](./STORY_034_PURE_MM.md)

---

## Story 035: Inventory Management

### 目标
实现做市策略的库存风险控制，动态调整报价以管理仓位。

### 核心功能

```zig
pub const InventoryManager = struct {
    target_inventory: i64,        // 目标库存 (通常为 0)
    max_inventory: i64,           // 最大库存
    current_inventory: i64,       // 当前库存
    inventory_skew: f64,          // 库存偏斜系数

    /// 调整报价 (库存偏斜)
    pub fn adjustQuotes(self: *InventoryManager, bid: Decimal, ask: Decimal, mid: Decimal)
        struct { bid: Decimal, ask: Decimal }
    {
        const skew = self.inventorySkew();
        // 正库存 → 降低买价, 提高卖价 → 鼓励卖出
        // 负库存 → 提高买价, 降低卖价 → 鼓励买入
        // ...
    }
};
```

### 详细文档
- [STORY_035_INVENTORY.md](./STORY_035_INVENTORY.md)

---

## Story 036: zig-sqlite 数据持久化

### 目标
集成 zig-sqlite 实现数据持久化，存储 K 线数据和回测结果。

### 核心功能

```zig
pub const DataStore = struct {
    db: sqlite.Database,
    allocator: Allocator,

    pub fn storeCandles(self: *DataStore, symbol: []const u8, tf: Timeframe, candles: []const Candle) !void;
    pub fn loadCandles(self: *DataStore, symbol: []const u8, tf: Timeframe, start: i64, end: i64) ![]Candle;
    pub fn storeBacktestResult(self: *DataStore, result: BacktestResult) !void;
};
```

### 详细文档
- [STORY_036_SQLITE.md](./STORY_036_SQLITE.md)

---

## Story 037: Cross-Exchange Arbitrage

### 目标
实现跨交易所套利策略，捕捉不同交易所之间的价差。

### 核心功能

```zig
pub const CrossExchangeArbitrage = struct {
    exchange_a: *IExchange,
    exchange_b: *IExchange,
    min_profit_bps: u32,

    pub fn detectOpportunity(self: *Self) ?ArbitrageOpportunity;
    pub fn executeArbitrage(self: *Self, opp: ArbitrageOpportunity) !ArbitrageResult;
};
```

### 详细文档
- [STORY_037_ARBITRAGE.md](./STORY_037_ARBITRAGE.md)

---

## Story 038: Queue Position Modeling

> 来源: **HFTBacktest**
> 重要性: **极高** - 做市策略回测精度的关键

### 目标
实现订单队列位置建模，真实反映限价单在订单簿中的成交概率。

### 问题场景

```
❌ 传统回测 (过于乐观):
1. 下限价买单 @ $100
2. 市场价 = $100 → 假设立即成交
3. 结果: Sharpe 虚高 20-30%

✅ Queue-Aware 回测 (真实):
1. 下限价买单 @ $100
2. 计算队列位置: 你前面有 50 BTC
3. 市场成交 30 BTC → 你的订单未成交
4. 结果: 真实反映市场微观结构
```

### 四种队列模型

```zig
pub const QueueModel = enum {
    RiskAverse,   // 保守: 假设在队尾
    Probability,  // 概率: 线性分布
    PowerLaw,     // 幂函数: x^2 或 x^3
    Logarithmic,  // 对数: log(1+x)
};

pub const QueuePosition = struct {
    order_id: []const u8,
    price_level: Decimal,
    position_in_queue: usize,      // 当前位置 (0 = 队头)
    total_quantity_ahead: Decimal,  // 前方总量

    /// 计算成交概率
    pub fn fillProbability(self: QueuePosition, model: QueueModel) f64 {
        const x = @as(f64, @floatFromInt(self.position_in_queue)) /
                  @as(f64, @floatFromInt(self.total_quantity_ahead));

        return switch (model) {
            .RiskAverse => if (x < 0.01) 0.0 else 1.0,
            .Probability => x,
            .PowerLaw => std.math.pow(f64, x, 2.0),
            .Logarithmic => @log(1.0 + x) / @log(2.0),
        };
    }

    /// 推进队列位置 (当前方订单成交/撤单)
    pub fn advance(self: *QueuePosition, executed_qty: Decimal) void {
        if (executed_qty >= self.total_quantity_ahead) {
            self.position_in_queue = 0;
            self.total_quantity_ahead = Decimal.zero;
        } else {
            self.total_quantity_ahead = self.total_quantity_ahead.sub(executed_qty);
        }
    }
};
```

### Level-3 OrderBook 支持

```zig
pub const OrderBook = struct {
    pub const PriceLevel = struct {
        price: Decimal,
        orders: ArrayList(*Order),  // 该价位所有订单 (Level-3)
        total_quantity: Decimal,

        /// 添加订单到队尾
        pub fn addOrder(self: *PriceLevel, order: *Order) !void {
            // 计算队列位置并记录
            order.queue_position = QueuePosition{ ... };
        }
    };

    /// 处理成交事件 (更新所有订单队列位置)
    pub fn onTrade(self: *OrderBook, trade: Trade) !void {
        // 推进队列中所有订单的位置
    }
};
```

### 使用场景
- **做市策略** (必须 - 队列位置决定收益)
- **限价单策略** (重要 - 避免过度乐观)
- **HFT 策略** (关键 - 微秒级竞争)

### 预期效果
- Sharpe 比率差异 **20-30%** (回测 vs 实盘更接近)
- 避免过度乐观的回测结果

### 详细文档
- [STORY_038_QUEUE_POSITION.md](./STORY_038_QUEUE_POSITION.md)

---

## Story 039: Dual Latency Simulation

> 来源: **HFTBacktest**
> 重要性: **高** - HFT/做市策略延迟敏感

### 目标
实现双向延迟模拟: Feed Latency (市场数据) 和 Order Latency (订单执行)。

### 问题场景

```
❌ 传统回测 (零延迟):
1. 市场价格变化 → 立即可见
2. 下订单 → 立即成交
3. 结果: 不现实

✅ Dual Latency 回测:
1. 市场价格变化 @ t0
2. 策略接收数据 @ t0 + 10ms (Feed Latency)
3. 下订单 @ t0 + 11ms
4. 订单到达交易所 @ t0 + 21ms (Entry Latency)
5. 交易所确认 @ t0 + 25ms (Response Latency)
6. 结果: 真实 25ms 往返延迟
```

### 核心功能

```zig
pub const FeedLatencyModel = struct {
    model_type: enum { Constant, Normal, Interpolated },

    /// 模拟 Feed Latency
    pub fn simulate(self: *FeedLatencyModel, event_time: i64) !i64 {
        return switch (self.model_type) {
            .Constant => event_time + 10_000_000,  // 10ms
            .Normal => {
                // 正态分布: mean=10ms, std=2ms
                const latency_ns = sampleNormal(10_000_000, 2_000_000);
                return event_time + latency_ns;
            },
            .Interpolated => {
                // 基于历史数据插值
                return event_time + interpolateLatency(event_time);
            },
        };
    }
};

pub const OrderLatencyModel = struct {
    entry_latency: FeedLatencyModel,    // 提交延迟
    response_latency: FeedLatencyModel, // 确认延迟

    /// 模拟完整订单流程
    pub fn simulateOrderFlow(self: *OrderLatencyModel, order: *Order) !OrderTimeline {
        const leave_time = Time.now();
        const arrive_time = try self.entry_latency.simulate(leave_time);
        const process_time = arrive_time + 100_000;  // 100us 交易所处理
        const ack_time = try self.response_latency.simulate(process_time);

        return OrderTimeline{
            .strategy_submit = leave_time,
            .exchange_arrive = arrive_time,
            .exchange_process = process_time,
            .strategy_ack = ack_time,
            .total_roundtrip = ack_time - leave_time,
        };
    }
};
```

### 回测引擎集成

```zig
pub const BacktestEngine = struct {
    feed_latency: FeedLatencyModel,
    order_latency: OrderLatencyModel,

    /// 处理市场数据事件 (带延迟)
    pub fn onMarketData(self: *BacktestEngine, event: MarketEvent) !void {
        const arrival_time = try self.feed_latency.simulate(event.timestamp);
        try self.eventQueue.schedule(arrival_time, event);
    }

    /// 处理订单提交 (带延迟)
    pub fn submitOrder(self: *BacktestEngine, order: *Order) !void {
        const timeline = try self.order_latency.simulateOrderFlow(order);
        order.exchange_time = timeline.exchange_arrive;
        try self.eventQueue.schedule(timeline.strategy_ack, .{ .type = .OrderAck, .order = order });
    }
};
```

### 延迟模型选择

| 模型 | 描述 | 适用场景 |
|------|------|----------|
| Constant | 固定延迟 (如 10ms) | 快速测试 |
| Normal | 正态分布 (mean, std) | 一般模拟 |
| Interpolated | 从实盘日志拟合 | 高精度回测 |

### 使用场景
- **HFT 策略** (必须 - 微秒级敏感)
- **做市策略** (重要 - 报价时效性)
- **套利策略** (关键 - 延迟决定收益)

### 详细文档
- [STORY_039_DUAL_LATENCY.md](./STORY_039_DUAL_LATENCY.md)

---

## 验收标准

### 功能验收

- [ ] Clock-Driven 模式支持定时 Tick 策略
- [ ] Pure Market Making 策略可在 Paper Trading 中运行
- [ ] Inventory Management 动态调整报价
- [ ] zig-sqlite 集成，支持 K 线和回测结果存储
- [ ] Cross-Exchange Arbitrage 可检测和执行套利
- [ ] **Queue Position Modeling 真实模拟队列成交**
- [ ] **Dual Latency 模拟 Feed/Order 延迟**

### 性能验收

| 指标 | 目标 | 状态 |
|------|------|------|
| Tick 精度 | < 10ms 抖动 | ⏳ |
| 数据库写入 | > 10,000 rows/s | ⏳ |
| 数据库查询 | < 10ms | ⏳ |
| 做市策略 Sharpe | > 2.0 | ⏳ |
| 套利捕获率 | > 80% | ⏳ |
| **回测 vs 实盘 Sharpe 差异** | **< 10%** | ⏳ |
| **延迟模拟精度** | **纳秒级** | ⏳ |

### 代码验收

- [ ] 所有测试通过 (目标: 650+)
- [ ] 零内存泄漏
- [ ] 代码文档完整
- [ ] 做市示例程序

---

## 依赖关系

```
Story 033 (Clock-Driven)
    ↓
Story 034 (Pure MM) ──────→ Story 035 (Inventory)
    ↓                              ↓
    └──────────────────────────────┴──→ Story 038 (Queue Position)
                                              ↓
Story 036 (zig-sqlite)                 Story 039 (Dual Latency)
    ↓
Story 037 (Arbitrage)
```

---

## 文件结构

```
src/
├── market_making/
│   ├── mod.zig                 # 模块导出
│   ├── clock.zig               # Clock-Driven 时钟
│   ├── pure_mm.zig             # Pure Market Making
│   ├── inventory.zig           # 库存管理
│   └── arbitrage.zig           # 套利策略
│
├── backtest/
│   ├── queue_position.zig      # 队列位置建模 (NEW)
│   ├── latency_model.zig       # 延迟模拟 (NEW)
│   └── level3_orderbook.zig    # Level-3 订单簿 (NEW)
│
├── storage/
│   ├── mod.zig                 # 模块导出
│   ├── sqlite.zig              # zig-sqlite 封装
│   ├── candle_store.zig        # K 线存储
│   └── result_store.zig        # 回测结果存储
│
└── tests/
    ├── market_making_test.zig  # 做市测试
    ├── queue_position_test.zig # 队列测试 (NEW)
    └── latency_test.zig        # 延迟测试 (NEW)
```

---

## 相关文档

- [v0.6.0 混合计算模式](../v0.6.0/OVERVIEW.md)
- [竞争分析 - Hummingbot 做市](../../architecture/COMPETITIVE_ANALYSIS.md)
- [架构模式参考](../../architecture/ARCHITECTURE_PATTERNS.md)
  - Clock-Driven 模式
  - Queue Position Modeling
  - Dual Latency 模拟

---

**版本**: v0.7.0
**状态**: 规划中
**创建时间**: 2025-12-27
**Stories**: 7 个 (033-039)
