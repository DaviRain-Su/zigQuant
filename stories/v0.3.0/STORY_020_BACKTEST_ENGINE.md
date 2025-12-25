# Story 020: BacktestEngine 回测引擎核心实现

**Story ID**: STORY-020
**版本**: v0.3.0
**优先级**: P0
**工作量**: 2天
**状态**: 待开始
**创建时间**: 2025-12-25

---

## 📋 基本信息

### 所属版本
v0.3.0 - Week 2: 内置策略 + 回测引擎

### 依赖关系
- **前置依赖**:
  - STORY-013: IStrategy 接口和核心类型
  - STORY-014: StrategyContext 和辅助组件
  - STORY-015: 技术指标库实现
  - STORY-017: DualMAStrategy（用于测试）
  - STORY-018: RSIMeanReversionStrategy（用于测试）
  - STORY-019: BollingerBreakoutStrategy（用于测试）
- **后置影响**:
  - STORY-021: PerformanceAnalyzer 依赖回测结果
  - STORY-022: GridSearchOptimizer 使用回测引擎
  - STORY-023: CLI 策略命令使用回测引擎

---

## 🎯 Story 描述

### 用户故事
作为一个**量化交易开发者**，我希望**使用回测引擎验证策略在历史数据上的表现**，以便**在实盘前评估策略的盈利能力和风险**。

### 业务价值
- 提供策略验证的核心能力
- 支持历史数据回放和事件驱动模拟
- 模拟真实交易环境（订单执行、手续费、滑点）
- 为参数优化提供基础设施
- 降低实盘风险，提高策略成功率

### 技术背景
回测引擎（Backtesting Engine）是量化交易系统的核心组件：

**核心功能**:
- **历史数据回放**: 按时间顺序重放历史 K 线数据
- **事件驱动**: 使用事件队列驱动策略执行
- **订单模拟**: 模拟市价单、限价单的执行
- **账户管理**: 跟踪资金、持仓、盈亏
- **性能统计**: 记录所有交易用于后续分析

**设计原则**（参考 Freqtrade/Backtrader）:
- **事件驱动**: Market Data Event → Strategy Signal → Order Event → Fill Event
- **向前测试**: 严格避免"未来函数"（look-ahead bias）
- **真实模拟**: 考虑手续费、滑点、市场冲击
- **高性能**: 支持大规模数据回测（10,000+ candles）

参考实现：
- [Freqtrade Backtesting](https://www.freqtrade.io/en/stable/backtesting/)
- [Backtrader Engine](https://www.backtrader.com/docu/concepts/)
- [Hummingbot Backtesting](https://hummingbot.org/academy/backtesting/)

---

## 📝 详细需求

### 功能需求

#### FR-020-1: 回测引擎核心（BacktestEngine）
- **职责**: 协调整个回测流程
- **功能**:
  - 加载历史数据
  - 初始化策略和账户
  - 驱动事件循环
  - 收集回测结果
  - 生成性能报告
- **接口**:
  ```zig
  pub fn run(
      self: *BacktestEngine,
      strategy: IStrategy,
      config: BacktestConfig,
  ) !BacktestResult
  ```

#### FR-020-2: 历史数据提供者（HistoricalDataFeed）
- **职责**: 提供历史 K 线数据
- **功能**:
  - 从文件/数据库加载数据
  - 支持多种时间周期（1m, 5m, 15m, 1h, 4h, 1d）
  - 按时间顺序迭代数据
  - 数据验证（完整性、连续性）
- **接口**:
  ```zig
  pub fn load(
      self: *HistoricalDataFeed,
      pair: TradingPair,
      timeframe: Timeframe,
      start_time: Timestamp,
      end_time: Timestamp,
  ) !Candles
  ```

#### FR-020-3: 事件系统（Event System）
- **事件类型**:
  - `MarketEvent`: 新 K 线数据到达
  - `SignalEvent`: 策略生成交易信号
  - `OrderEvent`: 创建订单
  - `FillEvent`: 订单成交
- **事件队列**: FIFO 队列，严格按时间顺序处理
- **事件分发**: 根据事件类型分发给相应处理器

#### FR-020-4: 订单执行模拟器（OrderExecutor）
- **订单类型**:
  - 市价单（Market Order）: 立即按当前价格成交
  - 限价单（Limit Order）: 价格达到时成交（未来扩展）
- **执行逻辑**:
  - 市价单: 使用当前 K 线的 close 价格 + 滑点
  - 滑点计算: `fill_price = close * (1 + slippage)`（做多）
  - 手续费: `fee = fill_price * size * commission_rate`
- **成交确认**: 生成 FillEvent

#### FR-020-5: 账户和持仓管理（Account & Position Manager）
- **账户管理**:
  - 初始资金
  - 可用余额
  - 冻结资金（持仓占用）
  - 总权益（余额 + 持仓市值）
  - 累计盈亏
- **持仓管理**:
  - 当前持仓（多头/空头/空仓）
  - 持仓成本
  - 未实现盈亏
  - 持仓时间

#### FR-020-6: 回测配置（BacktestConfig）
- **配置项**:
  - `pair: TradingPair` - 交易对
  - `timeframe: Timeframe` - 时间周期
  - `start_time: Timestamp` - 开始时间
  - `end_time: Timestamp` - 结束时间
  - `initial_capital: Decimal` - 初始资金
  - `commission_rate: Decimal` - 手续费率（默认：0.001，即 0.1%）
  - `slippage: Decimal` - 滑点（默认：0.0005，即 0.05%）
  - `enable_short: bool` - 是否允许做空（默认：true）
  - `max_positions: u32` - 最大同时持仓数（默认：1）

#### FR-020-7: 回测结果（BacktestResult）
- **交易记录**:
  - 所有已完成交易的列表（Trade）
  - 每笔交易包含: 入场时间、出场时间、入场价、出场价、方向、盈亏
- **账户快照**:
  - 权益曲线（Equity Curve）
  - 每日净值
- **基础统计**:
  - 总交易次数
  - 盈利/亏损交易数
  - 总盈利/总亏损
  - 净利润
  - 胜率
  - 盈亏比

### 非功能需求

#### NFR-020-1: 性能要求
- **回测速度**: > 1000 candles/s（单策略）
- **内存占用**: < 50MB（10,000 根 K 线）
- **支持规模**: 支持至少 50,000 根 K 线的回测

#### NFR-020-2: 准确性要求
- **向前测试**: 严格避免未来函数
- **时间精度**: 毫秒级时间戳
- **数值精度**: 使用 Decimal 避免浮点误差
- **成交模拟**: 真实模拟滑点和手续费

#### NFR-020-3: 代码质量
- **模块化**: 各组件职责单一，低耦合
- **可测试**: 所有组件可独立测试
- **可扩展**: 支持添加新的订单类型、执行逻辑
- **文档**: 详细的架构文档和 API 文档

#### NFR-020-4: 可观测性
- **日志**: 记录关键事件（订单、成交、错误）
- **进度**: 显示回测进度（已处理 K 线数/总数）
- **调试**: 支持详细模式（打印所有事件）

---

## ✅ 验收标准

### AC-020-1: 回测引擎功能完整
- [ ] 能成功加载历史数据
- [ ] 能初始化策略并计算指标
- [ ] 能驱动完整的事件循环
- [ ] 能正确执行订单
- [ ] 能生成完整的回测结果

### AC-020-2: 订单执行准确性
- [ ] 市价单立即成交
- [ ] 成交价格考虑滑点
- [ ] 手续费计算准确
- [ ] 账户余额更新正确
- [ ] 持仓状态正确

### AC-020-3: 无未来函数
- [ ] 策略只能访问当前和历史数据
- [ ] 指标计算不使用未来数据
- [ ] 信号生成不使用未来数据
- [ ] 通过严格的向前测试验证

### AC-020-4: 性能达标
- [ ] 回测速度 > 1000 candles/s
- [ ] 10,000 根 K 线回测 < 10 秒
- [ ] 内存占用 < 50MB
- [ ] 零内存泄漏

### AC-020-5: 测试完整性
- [ ] 单元测试覆盖率 > 85%
- [ ] 集成测试通过
- [ ] 端到端测试通过
- [ ] 使用真实策略验证

### AC-020-6: 结果准确性
- [ ] 交易记录完整
- [ ] 盈亏计算准确（手工验证）
- [ ] 胜率计算正确
- [ ] 权益曲线连续

---

## 📂 涉及文件

### 新建文件
- `src/backtest/engine.zig` - 回测引擎核心（~400 行）
- `src/backtest/data_feed.zig` - 历史数据提供者（~200 行）
- `src/backtest/event.zig` - 事件系统（~300 行）
- `src/backtest/executor.zig` - 订单执行器（~250 行）
- `src/backtest/account.zig` - 账户管理（~200 行）
- `src/backtest/position.zig` - 持仓管理（~150 行）
- `src/backtest/types.zig` - 类型定义（~200 行）
- `src/backtest/engine_test.zig` - 单元测试（~400 行）
- `tests/integration/backtest_e2e_test.zig` - 端到端测试（~300 行）
- `docs/features/backtest/architecture.md` - 架构文档
- `docs/features/backtest/api.md` - API 文档

### 修改文件
- `src/backtest/mod.zig` - 模块导出
- `build.zig` - 添加回测模块和测试
- `src/strategy/context.zig` - 可能需要扩展上下文

### 参考文件
- `src/strategy/interface.zig` - 策略接口
- `docs/v0.3.0_STRATEGY_FRAMEWORK_DESIGN.md` - 设计文档

---

## 🔨 技术实现

### 实现步骤

#### Step 1: 定义核心类型（2小时）
```zig
// src/backtest/types.zig

/// 回测配置
pub const BacktestConfig = struct {
    pair: TradingPair,
    timeframe: Timeframe,
    start_time: Timestamp,
    end_time: Timestamp,
    initial_capital: Decimal,
    commission_rate: Decimal = try Decimal.fromFloat(0.001),  // 0.1%
    slippage: Decimal = try Decimal.fromFloat(0.0005),        // 0.05%
    enable_short: bool = true,
    max_positions: u32 = 1,
};

/// 交易记录
pub const Trade = struct {
    id: u64,
    pair: TradingPair,
    side: Side,  // long/short
    entry_time: Timestamp,
    exit_time: Timestamp,
    entry_price: Decimal,
    exit_price: Decimal,
    size: Decimal,
    pnl: Decimal,
    pnl_percent: Decimal,
    commission: Decimal,
    duration_minutes: u64,
};

/// 回测结果
pub const BacktestResult = struct {
    // 基础统计
    total_trades: u32,
    winning_trades: u32,
    losing_trades: u32,

    total_profit: Decimal,
    total_loss: Decimal,
    net_profit: Decimal,

    win_rate: f64,
    profit_factor: f64,  // total_profit / total_loss

    // 详细数据
    trades: []Trade,
    equity_curve: []EquitySnapshot,

    // 配置
    config: BacktestConfig,
    strategy_name: []const u8,

    pub const EquitySnapshot = struct {
        timestamp: Timestamp,
        equity: Decimal,
        balance: Decimal,
        unrealized_pnl: Decimal,
    };
};
```

#### Step 2: 实现事件系统（3小时）
```zig
// src/backtest/event.zig

/// 事件类型
pub const EventType = enum {
    market,
    signal,
    order,
    fill,
};

/// 基础事件
pub const Event = union(EventType) {
    market: MarketEvent,
    signal: SignalEvent,
    order: OrderEvent,
    fill: FillEvent,
};

/// 市场事件：新 K 线到达
pub const MarketEvent = struct {
    timestamp: Timestamp,
    candle: Candle,
};

/// 信号事件：策略生成信号
pub const SignalEvent = struct {
    timestamp: Timestamp,
    signal: Signal,
};

/// 订单事件：创建订单
pub const OrderEvent = struct {
    id: u64,
    timestamp: Timestamp,
    pair: TradingPair,
    side: Side,
    type: OrderType,
    price: Decimal,  // 限价单价格（市价单忽略）
    size: Decimal,

    pub const OrderType = enum {
        market,
        limit,
    };
};

/// 成交事件：订单执行完成
pub const FillEvent = struct {
    order_id: u64,
    timestamp: Timestamp,
    fill_price: Decimal,
    fill_size: Decimal,
    commission: Decimal,
};

/// 事件队列
pub const EventQueue = struct {
    allocator: std.mem.Allocator,
    queue: std.ArrayList(Event),

    pub fn init(allocator: std.mem.Allocator) EventQueue {
        return .{
            .allocator = allocator,
            .queue = std.ArrayList(Event).init(allocator),
        };
    }

    pub fn push(self: *EventQueue, event: Event) !void {
        try self.queue.append(event);
    }

    pub fn pop(self: *EventQueue) ?Event {
        if (self.queue.items.len == 0) return null;
        return self.queue.orderedRemove(0);
    }

    pub fn isEmpty(self: *EventQueue) bool {
        return self.queue.items.len == 0;
    }
};
```

#### Step 3: 实现账户和持仓管理（3小时）
```zig
// src/backtest/account.zig

pub const Account = struct {
    initial_capital: Decimal,
    balance: Decimal,           // 可用余额
    equity: Decimal,            // 总权益（余额 + 持仓市值）
    total_commission: Decimal,  // 累计手续费

    pub fn init(initial_capital: Decimal) Account {
        return .{
            .initial_capital = initial_capital,
            .balance = initial_capital,
            .equity = initial_capital,
            .total_commission = Decimal.ZERO,
        };
    }

    pub fn updateEquity(self: *Account, unrealized_pnl: Decimal) !void {
        self.equity = try self.balance.add(unrealized_pnl);
    }
};

// src/backtest/position.zig

pub const Position = struct {
    pair: TradingPair,
    side: Side,
    size: Decimal,
    entry_price: Decimal,
    entry_time: Timestamp,
    unrealized_pnl: Decimal,

    pub fn init(
        pair: TradingPair,
        side: Side,
        size: Decimal,
        entry_price: Decimal,
        entry_time: Timestamp,
    ) Position {
        return .{
            .pair = pair,
            .side = side,
            .size = size,
            .entry_price = entry_price,
            .entry_time = entry_time,
            .unrealized_pnl = Decimal.ZERO,
        };
    }

    pub fn updateUnrealizedPnL(self: *Position, current_price: Decimal) !void {
        const price_diff = if (self.side == .long)
            try current_price.sub(self.entry_price)
        else
            try self.entry_price.sub(current_price);

        self.unrealized_pnl = try price_diff.mul(self.size);
    }

    pub fn calculatePnL(self: *Position, exit_price: Decimal) !Decimal {
        const price_diff = if (self.side == .long)
            try exit_price.sub(self.entry_price)
        else
            try self.entry_price.sub(exit_price);

        return try price_diff.mul(self.size);
    }
};

pub const PositionManager = struct {
    allocator: std.mem.Allocator,
    current_position: ?Position,

    pub fn hasPosition(self: *PositionManager) bool {
        return self.current_position != null;
    }

    pub fn getPosition(self: *PositionManager) ?Position {
        return self.current_position;
    }

    pub fn openPosition(self: *PositionManager, pos: Position) !void {
        if (self.current_position != null) {
            return error.PositionAlreadyExists;
        }
        self.current_position = pos;
    }

    pub fn closePosition(self: *PositionManager) void {
        self.current_position = null;
    }
};
```

#### Step 4: 实现订单执行器（3小时）
```zig
// src/backtest/executor.zig

pub const OrderExecutor = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    config: BacktestConfig,
    next_order_id: u64,

    pub fn init(allocator: std.mem.Allocator, config: BacktestConfig) OrderExecutor {
        return .{
            .allocator = allocator,
            .logger = Logger.init("OrderExecutor"),
            .config = config,
            .next_order_id = 1,
        };
    }

    /// 执行市价单
    pub fn executeMarketOrder(
        self: *OrderExecutor,
        order: OrderEvent,
        current_candle: Candle,
    ) !FillEvent {
        // 计算成交价格（考虑滑点）
        const base_price = current_candle.close;
        const slippage_factor = if (order.side == .buy)
            try Decimal.ONE.add(self.config.slippage)
        else
            try Decimal.ONE.sub(self.config.slippage);

        const fill_price = try base_price.mul(slippage_factor);

        // 计算手续费
        const notional = try fill_price.mul(order.size);
        const commission = try notional.mul(self.config.commission_rate);

        self.logger.info("Order executed: id={}, price={}, size={}, commission={}", .{
            order.id, fill_price, order.size, commission,
        });

        return FillEvent{
            .order_id = order.id,
            .timestamp = order.timestamp,
            .fill_price = fill_price,
            .fill_size = order.size,
            .commission = commission,
        };
    }

    pub fn generateOrderId(self: *OrderExecutor) u64 {
        const id = self.next_order_id;
        self.next_order_id += 1;
        return id;
    }
};
```

#### Step 5: 实现历史数据提供者（2小时）
```zig
// src/backtest/data_feed.zig

pub const HistoricalDataFeed = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    pub fn init(allocator: std.mem.Allocator) HistoricalDataFeed {
        return .{
            .allocator = allocator,
            .logger = Logger.init("DataFeed"),
        };
    }

    /// 从文件加载历史数据
    pub fn load(
        self: *HistoricalDataFeed,
        pair: TradingPair,
        timeframe: Timeframe,
        start_time: Timestamp,
        end_time: Timestamp,
    ) !Candles {
        self.logger.info("Loading data: {s} {} {}-{}", .{
            pair.toString(), timeframe, start_time, end_time,
        });

        // TODO: 从文件/数据库加载数据
        // 临时实现：返回空数据
        var candles = Candles.init(self.allocator);

        // 验证数据
        try self.validateData(&candles);

        self.logger.info("Loaded {} candles", .{candles.data.len});
        return candles;
    }

    fn validateData(self: *HistoricalDataFeed, candles: *Candles) !void {
        if (candles.data.len == 0) {
            return error.NoData;
        }

        // 检查时间连续性
        for (1..candles.data.len) |i| {
            if (candles.data[i].timestamp <= candles.data[i-1].timestamp) {
                self.logger.err("Data not sorted: index {}", .{i});
                return error.DataNotSorted;
            }
        }
    }
};
```

#### Step 6: 实现回测引擎核心（5小时）
```zig
// src/backtest/engine.zig

pub const BacktestEngine = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    data_feed: *HistoricalDataFeed,

    pub fn init(allocator: std.mem.Allocator) !BacktestEngine {
        const data_feed = try allocator.create(HistoricalDataFeed);
        data_feed.* = HistoricalDataFeed.init(allocator);

        return .{
            .allocator = allocator,
            .logger = Logger.init("BacktestEngine"),
            .data_feed = data_feed,
        };
    }

    pub fn deinit(self: *BacktestEngine) void {
        self.allocator.destroy(self.data_feed);
    }

    /// 运行回测
    pub fn run(
        self: *BacktestEngine,
        strategy: IStrategy,
        config: BacktestConfig,
    ) !BacktestResult {
        self.logger.info("Starting backtest: {s}", .{config.pair.toString()});

        // 1. 加载历史数据
        var candles = try self.data_feed.load(
            config.pair,
            config.timeframe,
            config.start_time,
            config.end_time,
        );
        defer candles.deinit();

        // 2. 计算指标
        self.logger.info("Calculating indicators...", .{});
        try strategy.populateIndicators(&candles);

        // 3. 初始化回测状态
        var account = Account.init(config.initial_capital);
        var position_mgr = PositionManager.init(self.allocator);
        var executor = OrderExecutor.init(self.allocator, config);
        var trades = std.ArrayList(Trade).init(self.allocator);
        defer trades.deinit();
        var equity_curve = std.ArrayList(BacktestResult.EquitySnapshot).init(self.allocator);
        defer equity_curve.deinit();

        // 4. 事件循环
        self.logger.info("Running event loop: {} candles", .{candles.data.len});

        for (candles.data, 0..) |candle, i| {
            // 4.1 更新持仓未实现盈亏
            if (position_mgr.getPosition()) |*pos| {
                try pos.updateUnrealizedPnL(candle.close);
                try account.updateEquity(pos.unrealized_pnl);
            }

            // 4.2 记录权益快照
            try equity_curve.append(.{
                .timestamp = candle.timestamp,
                .equity = account.equity,
                .balance = account.balance,
                .unrealized_pnl = if (position_mgr.getPosition()) |pos|
                    pos.unrealized_pnl else Decimal.ZERO,
            });

            // 4.3 检查出场信号
            if (position_mgr.getPosition()) |pos| {
                const exit_signal = try strategy.generateExitSignal(&candles, pos);
                if (exit_signal) |sig| {
                    try self.handleExit(&executor, &position_mgr, &account, &trades, sig, candle);
                    continue;
                }
            }

            // 4.4 检查入场信号（无持仓时）
            if (!position_mgr.hasPosition()) {
                const entry_signal = try strategy.generateEntrySignal(&candles, i);
                if (entry_signal) |sig| {
                    try self.handleEntry(&executor, &position_mgr, &account, sig, candle, strategy);
                }
            }

            // 进度显示
            if (i % 1000 == 0) {
                self.logger.debug("Progress: {}/{}", .{i, candles.data.len});
            }
        }

        // 5. 强制平仓（如果还有持仓）
        if (position_mgr.getPosition()) |pos| {
            const last_candle = candles.data[candles.data.len - 1];
            const exit_signal = Signal{
                .type = if (pos.side == .long) .exit_long else .exit_short,
                .pair = pos.pair,
                .side = if (pos.side == .long) .sell else .buy,
                .price = last_candle.close,
                .strength = 1.0,
                .timestamp = last_candle.timestamp,
                .metadata = null,
            };
            try self.handleExit(&executor, &position_mgr, &account, &trades, exit_signal, last_candle);
        }

        // 6. 生成回测结果
        return try self.generateResult(config, strategy, trades.items, equity_curve.items, account);
    }

    fn handleEntry(
        self: *BacktestEngine,
        executor: *OrderExecutor,
        position_mgr: *PositionManager,
        account: *Account,
        signal: Signal,
        candle: Candle,
        strategy: IStrategy,
    ) !void {
        // 计算仓位大小
        const position_size = try strategy.calculatePositionSize(signal, account.*);

        // 创建订单
        const order = OrderEvent{
            .id = executor.generateOrderId(),
            .timestamp = signal.timestamp,
            .pair = signal.pair,
            .side = signal.side,
            .type = .market,
            .price = signal.price,
            .size = position_size,
        };

        // 执行订单
        const fill = try executor.executeMarketOrder(order, candle);

        // 更新账户
        const cost = try fill.fill_price.mul(fill.fill_size);
        const total_cost = try cost.add(fill.commission);
        account.balance = try account.balance.sub(total_cost);
        account.total_commission = try account.total_commission.add(fill.commission);

        // 开仓
        const position = Position.init(
            signal.pair,
            if (signal.side == .buy) .long else .short,
            fill.fill_size,
            fill.fill_price,
            signal.timestamp,
        );
        try position_mgr.openPosition(position);

        self.logger.info("Opened position: {s} {} @ {}", .{
            signal.pair.toString(), position.side, fill.fill_price,
        });
    }

    fn handleExit(
        self: *BacktestEngine,
        executor: *OrderExecutor,
        position_mgr: *PositionManager,
        account: *Account,
        trades: *std.ArrayList(Trade),
        signal: Signal,
        candle: Candle,
    ) !void {
        const position = position_mgr.getPosition().?;

        // 创建订单
        const order = OrderEvent{
            .id = executor.generateOrderId(),
            .timestamp = signal.timestamp,
            .pair = signal.pair,
            .side = signal.side,
            .type = .market,
            .price = signal.price,
            .size = position.size,
        };

        // 执行订单
        const fill = try executor.executeMarketOrder(order, candle);

        // 计算盈亏
        const pnl = try position.calculatePnL(fill.fill_price);
        const net_pnl = try pnl.sub(fill.commission);

        // 更新账户
        const proceeds = try fill.fill_price.mul(fill.fill_size);
        account.balance = try account.balance.add(proceeds).add(net_pnl);
        account.total_commission = try account.total_commission.add(fill.commission);

        // 记录交易
        const duration = signal.timestamp - position.entry_time;
        try trades.append(Trade{
            .id = order.id,
            .pair = position.pair,
            .side = position.side,
            .entry_time = position.entry_time,
            .exit_time = signal.timestamp,
            .entry_price = position.entry_price,
            .exit_price = fill.fill_price,
            .size = position.size,
            .pnl = net_pnl,
            .pnl_percent = try net_pnl.div(try position.entry_price.mul(position.size)),
            .commission = fill.commission,
            .duration_minutes = @intCast(duration / 60000),  // ms to minutes
        });

        // 平仓
        position_mgr.closePosition();

        self.logger.info("Closed position: PnL={}", .{net_pnl});
    }

    fn generateResult(
        self: *BacktestEngine,
        config: BacktestConfig,
        strategy: IStrategy,
        trades: []Trade,
        equity_curve: []BacktestResult.EquitySnapshot,
        account: Account,
    ) !BacktestResult {
        var winning_trades: u32 = 0;
        var losing_trades: u32 = 0;
        var total_profit = Decimal.ZERO;
        var total_loss = Decimal.ZERO;

        for (trades) |trade| {
            if (trade.pnl.isPositive()) {
                winning_trades += 1;
                total_profit = try total_profit.add(trade.pnl);
            } else {
                losing_trades += 1;
                total_loss = try total_loss.add(try trade.pnl.abs());
            }
        }

        const win_rate = if (trades.len > 0)
            @as(f64, @floatFromInt(winning_trades)) / @as(f64, @floatFromInt(trades.len))
        else
            0.0;

        const profit_factor = if (!total_loss.isZero())
            try total_profit.div(total_loss).toFloat()
        else
            0.0;

        return BacktestResult{
            .total_trades = @intCast(trades.len),
            .winning_trades = winning_trades,
            .losing_trades = losing_trades,
            .total_profit = total_profit,
            .total_loss = total_loss,
            .net_profit = try total_profit.sub(total_loss),
            .win_rate = win_rate,
            .profit_factor = profit_factor,
            .trades = try self.allocator.dupe(Trade, trades),
            .equity_curve = try self.allocator.dupe(BacktestResult.EquitySnapshot, equity_curve),
            .config = config,
            .strategy_name = try self.allocator.dupe(u8, strategy.getMetadata().name),
        };
    }
};
```

#### Step 7: 编写测试（4小时）
```zig
// src/backtest/engine_test.zig

test "BacktestEngine: basic flow" {
    const allocator = std.testing.allocator;

    var engine = try BacktestEngine.init(allocator);
    defer engine.deinit();

    // 创建测试策略
    var strategy = try DualMAStrategy.create(allocator, .{
        .fast_period = 5,
        .slow_period = 10,
    });
    defer strategy.deinit();

    // 回测配置
    const config = BacktestConfig{
        .pair = TradingPair.fromString("BTC/USDT"),
        .timeframe = .m15,
        .start_time = 1704067200000,  // 2024-01-01
        .end_time = 1706745600000,    // 2024-02-01
        .initial_capital = try Decimal.fromInt(10000),
    };

    // 运行回测
    const result = try engine.run(strategy, config);
    defer result.deinit();

    // 验证结果
    try std.testing.expect(result.total_trades > 0);
    try std.testing.expect(result.equity_curve.len > 0);
}

// tests/integration/backtest_e2e_test.zig

test "Backtest E2E: DualMA strategy on real data" {
    // 端到端测试...
}
```

### 技术决策

#### 决策 1: 事件驱动架构
- **选择**: 使用事件队列驱动回测
- **理由**: 模拟真实交易流程，易于扩展
- **权衡**: 比直接循环复杂，但更真实

#### 决策 2: 市价单立即成交
- **选择**: 市价单使用当前 K 线收盘价成交
- **理由**: 简化实现，大多数回测引擎也这么做
- **权衡**: 不够精确（真实可能用下根 K 线开盘价）

#### 决策 3: 单一持仓
- **选择**: 同时只允许一个持仓
- **理由**: 简化逻辑，满足大多数策略需求
- **权衡**: 无法测试网格等多仓位策略（未来扩展）

---

## 🧪 测试计划

### 单元测试

#### UT-020-1: 事件队列测试
- 测试 push/pop 顺序
- 测试 FIFO 特性

#### UT-020-2: 账户管理测试
- 测试余额更新
- 测试权益计算

#### UT-020-3: 持仓管理测试
- 测试开平仓
- 测试未实现盈亏

#### UT-020-4: 订单执行测试
- 测试市价单成交
- 测试滑点和手续费

#### UT-020-5: 数据加载测试
- 测试数据验证
- 测试异常处理

### 集成测试

#### IT-020-1: 完整回测流程
- 使用 DualMA 策略
- 验证结果合理性

#### IT-020-2: 多策略测试
- 测试 RSI 策略
- 测试 BB 策略

### 性能测试

#### PT-020-1: 回测速度测试
- 10,000 根 K 线
- 目标: < 10 秒

---

## 📊 成功指标

### 功能指标
- ✅ 所有验收标准通过
- ✅ 测试覆盖率 > 85%

### 性能指标
- ✅ 回测速度 > 1000 candles/s
- ✅ 零内存泄漏

### 准确性指标
- ✅ 手工验证交易盈亏准确
- ✅ 无未来函数

---

## 📖 参考资料

- [Freqtrade Backtesting](https://www.freqtrade.io/en/stable/backtesting/)
- [Backtrader Documentation](https://www.backtrader.com/)
- [Backtesting Best Practices](https://www.quantstart.com/articles/Backtesting-Systematic-Trading-Strategies-in-Python-Considerations-and-Open-Source-Frameworks/)

---

**创建时间**: 2025-12-25
**预计开始**: Week 2 Day 4
**预计完成**: Week 2 Day 5

---

Generated with Claude Code
