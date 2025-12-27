# 实盘交易准备路线图

**文档创建时间**: 2025-12-26
**最后更新**: 2025-12-27
**当前版本**: v0.6.0
**目标**: 从回测系统到实盘交易的完整路径规划

---

## 📊 当前状态评估

### 已完成 ✅ (v0.2.0 - v0.6.0)

**交易系统核心 (v0.2.0)**:
- ✅ Hyperliquid DEX 完整集成
- ✅ HTTP REST API (查询市场数据、账户、订单)
- ✅ WebSocket 实时数据流 (订单簿、订单更新、成交)
- ✅ 订单管理 (下单、撤单、批量撤单、查询)
- ✅ 仓位跟踪 (实时 PnL、账户状态同步)
- ✅ CLI 界面 (11 个交易命令 + REPL)

**回测系统 (v0.3.0)**:
- ✅ 策略框架完整 (IStrategy 接口)
- ✅ 技术指标库 (6 个指标: SMA, EMA, RSI, MACD, BB, ATR)
- ✅ 内置策略 (3 个: Dual MA, RSI MR, BB Breakout)
- ✅ BacktestEngine 事件驱动架构
- ✅ PerformanceAnalyzer 完整性能指标
- ✅ CLI backtest 命令
- ✅ 真实数据验证 (8784 根 BTC/USDT K 线)

**优化器增强 (v0.4.0)**:
- ✅ Walk-Forward 分析器
- ✅ 15 个技术指标 (新增 8 个)
- ✅ 并行优化线程池
- ✅ 回测结果导出 (JSON/CSV)

**事件驱动架构 (v0.5.0)**:
- ✅ MessageBus 消息总线
- ✅ Cache 高性能缓存
- ✅ DataEngine 数据引擎
- ✅ ExecutionEngine 执行引擎
- ✅ LiveTradingEngine 统一接口

**混合计算模式 (v0.6.0)**:
- ✅ 向量化回测 (12.6M bars/s)
- ✅ HyperliquidDataProvider
- ✅ HyperliquidExecutionClient
- ✅ Paper Trading 模拟交易
- ✅ 策略热重载

**测试和质量**:
- ✅ 558/558 单元测试通过
- ✅ 零内存泄漏 (GPA 验证)
- ✅ 策略经过真实数据验证

### 关键缺失 ❌ (必须先实现才能实盘)

**P0 - 绝对必须**:
- ❌ **风险管理系统** (仓位计算、止损止盈、风险限制)
- ❌ **Paper Trading 模式** (虚拟交易验证)
- ❌ **实时策略执行引擎** (WebSocket + 异步执行)
- ❌ **监控和告警系统** (实时监控、异常告警)

**P1 - 强烈推荐**:
- ❌ **参数优化器** (GridSearchOptimizer, Story 022)
- ❌ **更多策略验证** (多策略分散风险)

**P2 - 建议有**:
- ❌ **结果导出功能** (JSON 结果保存)
- ❌ **策略开发指南** (用户文档)
- ❌ **性能优化** (< 30ms/8k candles)

---

## 🎯 实盘交易最小必需功能集 (MVP)

### 必须完成的 4 大核心系统

1. **风险管理系统** ← 最高优先级！
2. **Paper Trading 引擎** ← 验证策略和系统
3. **实时执行引擎** ← 实盘核心
4. **监控告警系统** ← 安全保障

---

## 📋 详细实施路线图

### Phase 1: 风险管理系统 (必须，1-2 周) - **P0**

**为什么优先**: 保护资金安全，防止灾难性亏损

#### 1.1 仓位管理器 (3-4 天)

**文件**: `src/risk/position_sizing.zig`

**功能接口**:
```zig
pub const PositionSizingMethod = enum {
    kelly_criterion,      // Kelly 公式
    fixed_fractional,     // 固定比例
    fixed_amount,         // 固定金额
    volatility_based,     // 基于波动率
};

pub const PositionSizer = struct {
    allocator: std.mem.Allocator,
    method: PositionSizingMethod,

    pub fn init(allocator: std.mem.Allocator, method: PositionSizingMethod) PositionSizer;

    /// 计算仓位大小
    pub fn calculateSize(
        self: *PositionSizer,
        account_balance: Decimal,      // 账户余额
        risk_per_trade: Decimal,       // 单笔风险比例 (e.g., 0.01 = 1%)
        stop_loss_distance: Decimal,   // 止损距离 (e.g., 0.02 = 2%)
        win_rate: ?f64,                // 胜率 (Kelly 公式需要)
        avg_win_loss_ratio: ?f64,      // 盈亏比 (Kelly 公式需要)
    ) !Decimal;

    /// 验证仓位大小是否在允许范围内
    pub fn validate(
        self: *PositionSizer,
        position_size: Decimal,
        max_position: Decimal,
    ) !void;
};
```

**实现方法**:

1. **Kelly Criterion (凯利公式)**:
   ```
   f = (p * b - q) / b
   其中:
   - f = 应该投入的资金比例
   - p = 胜率
   - q = 败率 (1 - p)
   - b = 盈亏比
   ```

2. **Fixed Fractional (固定比例)**:
   ```
   Position Size = Account Balance × Risk%
   ```

3. **Fixed Amount (固定金额)**:
   ```
   Position Size = Fixed Amount
   ```

4. **Volatility-Based (波动率调整)**:
   ```
   Position Size = (Account Balance × Risk%) / ATR
   ```

**测试要点**:
- [ ] Kelly 公式计算正确性
- [ ] 边界条件处理（0 胜率、极端值）
- [ ] 仓位上限验证
- [ ] 不同方法切换

---

#### 1.2 止损止盈管理器 (2-3 天)

**文件**: `src/risk/stop_loss.zig`

**功能接口**:
```zig
pub const StopLossType = enum {
    fixed_percent,     // 固定百分比
    atr_based,         // ATR 倍数
    trailing,          // 移动止损
    support_resistance,// 支撑阻力位
};

pub const StopLossManager = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StopLossManager;

    /// 计算止损价格
    pub fn calculateStopLoss(
        self: *StopLossManager,
        entry_price: Decimal,
        position_side: PositionSide,  // long/short
        sl_type: StopLossType,
        sl_param: Decimal,            // 参数（百分比或 ATR 倍数）
        atr: ?Decimal,                // ATR 值（如果使用）
    ) !Decimal;

    /// 计算止盈价格
    pub fn calculateTakeProfit(
        self: *StopLossManager,
        entry_price: Decimal,
        stop_loss_price: Decimal,
        risk_reward_ratio: Decimal,   // e.g., 2.0 (2:1)
        position_side: PositionSide,
    ) !Decimal;

    /// 更新移动止损
    pub fn updateTrailingStop(
        self: *StopLossManager,
        current_price: Decimal,
        current_stop: Decimal,
        highest_price: Decimal,       // 持仓期间最高价
        trailing_percent: Decimal,    // 移动止损百分比
        position_side: PositionSide,
    ) !Decimal;

    /// 检查是否触发止损
    pub fn isStopLossTriggered(
        current_price: Decimal,
        stop_loss_price: Decimal,
        position_side: PositionSide,
    ) bool;
};
```

**实现方法**:

1. **Fixed Percent Stop Loss**:
   ```
   Long: SL = Entry × (1 - percent)
   Short: SL = Entry × (1 + percent)
   ```

2. **ATR-Based Stop Loss**:
   ```
   Long: SL = Entry - (ATR × multiplier)
   Short: SL = Entry + (ATR × multiplier)
   ```

3. **Trailing Stop**:
   ```
   Long: SL = MAX(current_SL, highest_price × (1 - trailing%))
   Short: SL = MIN(current_SL, lowest_price × (1 + trailing%))
   ```

4. **Take Profit**:
   ```
   TP Distance = |Entry - SL| × RiskRewardRatio
   Long: TP = Entry + TP Distance
   Short: TP = Entry - TP Distance
   ```

**测试要点**:
- [ ] 各种止损类型计算正确
- [ ] Long/Short 方向正确
- [ ] 移动止损只向有利方向移动
- [ ] 边界条件处理

---

#### 1.3 风险限制验证器 (2-3 天)

**文件**: `src/risk/risk_limits.zig`

**功能接口**:
```zig
pub const RiskLimits = struct {
    // 仓位限制
    max_position_size: Decimal,          // 单笔最大仓位（账户余额的百分比）
    max_position_value: Decimal,         // 单笔最大金额
    max_open_positions: u32,             // 最大同时持仓数

    // 风险限制
    max_risk_per_trade: Decimal,         // 单笔最大风险（账户的百分比）
    max_daily_loss: Decimal,             // 每日最大亏损
    max_total_loss: Decimal,             // 累计最大亏损
    max_drawdown: Decimal,               // 最大回撤限制

    // 交易频率限制
    max_trades_per_day: u32,             // 每日最大交易次数
    max_trades_per_hour: u32,            // 每小时最大交易次数

    // 其他
    max_leverage: Decimal,               // 最大杠杆（如果使用）
    require_stop_loss: bool,             // 是否强制止损

    pub fn validate(self: *const RiskLimits) !void;
};

pub const RiskValidator = struct {
    allocator: std.mem.Allocator,
    limits: RiskLimits,

    pub fn init(allocator: std.mem.Allocator, limits: RiskLimits) !RiskValidator;

    /// 验证新订单是否符合风险限制
    pub fn validateOrder(
        self: *RiskValidator,
        order: Order,
        account: Account,
        current_positions: []const Position,
    ) !void;

    /// 验证当前整体风险状态
    pub fn validateRiskState(
        self: *RiskValidator,
        account: Account,
        positions: []const Position,
        daily_pnl: Decimal,
        total_pnl: Decimal,
    ) !void;

    /// 检查是否需要紧急停止交易
    pub fn shouldEmergencyStop(
        self: *RiskValidator,
        account: Account,
        daily_pnl: Decimal,
        max_drawdown_pct: Decimal,
    ) bool;
};
```

**验证规则**:

1. **Pre-Trade 检查**:
   - [ ] 账户余额充足
   - [ ] 仓位大小在限制内
   - [ ] 单笔风险在限制内
   - [ ] 持仓数量未超限
   - [ ] 有止损设置（如果要求）
   - [ ] 杠杆在限制内

2. **Runtime 监控**:
   - [ ] 每日亏损未超限
   - [ ] 总体亏损未超限
   - [ ] 最大回撤未超限
   - [ ] 交易频率未超限

3. **Emergency Stop 条件**:
   - [ ] 每日亏损 > max_daily_loss
   - [ ] 回撤 > max_drawdown
   - [ ] 连续亏损次数过多
   - [ ] 系统异常（网络、数据）

**测试要点**:
- [ ] 各种限制条件验证正确
- [ ] Emergency stop 触发条件正确
- [ ] 边界条件处理
- [ ] 多仓位场景验证

---

#### 1.4 综合风险管理器 (1-2 天)

**文件**: `src/risk/manager.zig`

**功能接口**:
```zig
pub const RiskManager = struct {
    allocator: std.mem.Allocator,
    position_sizer: PositionSizer,
    stop_loss_mgr: StopLossManager,
    risk_validator: RiskValidator,
    limits: RiskLimits,

    pub fn init(
        allocator: std.mem.Allocator,
        limits: RiskLimits,
        sizing_method: PositionSizingMethod,
    ) !RiskManager;

    pub fn deinit(self: *RiskManager) void;

    /// 为信号计算完整的交易参数
    pub fn calculateTradeParams(
        self: *RiskManager,
        signal: Signal,
        account: Account,
        current_positions: []const Position,
        atr: Decimal,
    ) !TradeParams;

    /// 验证交易参数是否安全
    pub fn validateTrade(
        self: *RiskManager,
        params: TradeParams,
        account: Account,
        positions: []const Position,
    ) !void;

    /// 更新移动止损
    pub fn updateTrailingStops(
        self: *RiskManager,
        positions: []Position,
        current_prices: []Decimal,
    ) !void;
};

pub const TradeParams = struct {
    position_size: Decimal,      // 仓位大小
    entry_price: Decimal,        // 入场价格
    stop_loss: Decimal,          // 止损价格
    take_profit: ?Decimal,       // 止盈价格（可选）
    risk_amount: Decimal,        // 风险金额
    risk_percent: Decimal,       // 风险百分比
    approved: bool,              // 是否通过风险检查
    rejection_reason: ?[]const u8, // 拒绝原因
};
```

**使用示例**:
```zig
// 1. 创建风险管理器
var risk_mgr = try RiskManager.init(allocator, risk_limits, .fixed_fractional);
defer risk_mgr.deinit();

// 2. 策略生成信号后，计算交易参数
const signal = try strategy.generateEntrySignal(&candles, i);
if (signal) |sig| {
    defer sig.deinit();

    // 3. 计算完整的交易参数（仓位、止损、止盈）
    const trade_params = try risk_mgr.calculateTradeParams(
        sig,
        account,
        current_positions,
        atr_value,
    );

    // 4. 验证交易是否符合风险限制
    risk_mgr.validateTrade(
        trade_params,
        account,
        current_positions,
    ) catch |err| {
        try logger.warn("Trade rejected: {s}", .{trade_params.rejection_reason.?});
        return;
    };

    // 5. 如果通过验证，执行交易
    if (trade_params.approved) {
        try executeOrder(trade_params);
    }
}
```

**测试要点**:
- [ ] 完整流程测试
- [ ] 各组件集成正确
- [ ] 拒绝原因正确记录
- [ ] 内存正确管理

---

### Phase 2: Paper Trading 系统 (必须，1 周开发 + 2-4 周测试) - **P0**

**为什么重要**: 零风险验证策略和系统，发现潜在问题

#### 2.1 虚拟账户管理器 (1-2 天)

**文件**: `src/paper_trading/virtual_account.zig`

**功能接口**:
```zig
pub const VirtualAccount = struct {
    allocator: std.mem.Allocator,
    initial_balance: Decimal,
    current_balance: Decimal,
    equity: Decimal,              // 权益 = 余额 + 未实现盈亏
    positions: std.ArrayList(VirtualPosition),
    orders: std.ArrayList(VirtualOrder),
    trades: std.ArrayList(Trade),

    pub fn init(allocator: std.mem.Allocator, initial_balance: Decimal) !VirtualAccount;
    pub fn deinit(self: *VirtualAccount) void;

    /// 模拟开仓
    pub fn openPosition(
        self: *VirtualAccount,
        signal: Signal,
        size: Decimal,
        entry_price: Decimal,
    ) !void;

    /// 模拟平仓
    pub fn closePosition(
        self: *VirtualAccount,
        position_id: u64,
        exit_price: Decimal,
    ) !void;

    /// 更新未实现盈亏
    pub fn updateUnrealizedPnL(
        self: *VirtualAccount,
        current_prices: std.StringHashMap(Decimal),
    ) !void;

    /// 获取当前状态
    pub fn getStatus(self: *const VirtualAccount) AccountStatus;
};

pub const VirtualPosition = struct {
    id: u64,
    pair: TradingPair,
    side: PositionSide,
    size: Decimal,
    entry_price: Decimal,
    entry_time: Timestamp,
    stop_loss: Decimal,
    take_profit: ?Decimal,
    unrealized_pnl: Decimal,
};

pub const VirtualOrder = struct {
    id: u64,
    pair: TradingPair,
    side: OrderSide,
    size: Decimal,
    price: Decimal,
    order_type: OrderType,
    status: OrderStatus,
    created_at: Timestamp,
};

pub const AccountStatus = struct {
    balance: Decimal,
    equity: Decimal,
    unrealized_pnl: Decimal,
    total_pnl: Decimal,
    open_positions: usize,
    total_trades: usize,
    win_rate: f64,
};
```

**测试要点**:
- [ ] 开平仓逻辑正确
- [ ] 盈亏计算准确
- [ ] 账户状态更新及时
- [ ] 内存管理正确

---

#### 2.2 Paper Trading 引擎 (3-4 天)

**文件**: `src/paper_trading/engine.zig`

**功能接口**:
```zig
pub const PaperTradingEngine = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    // 核心组件
    strategy: IStrategy,
    risk_manager: RiskManager,
    virtual_account: VirtualAccount,

    // WebSocket 数据流
    ws_manager: *WebSocketManager,
    orderbook: *Orderbook,

    // 指标计算
    candles_buffer: std.ArrayList(Candle),  // 滚动窗口
    indicator_values: IndicatorCache,

    // 状态
    is_running: bool,
    start_time: Timestamp,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        strategy: IStrategy,
        risk_manager: RiskManager,
        initial_balance: Decimal,
    ) !PaperTradingEngine;

    pub fn deinit(self: *PaperTradingEngine) void;

    /// 启动 paper trading
    pub fn start(self: *PaperTradingEngine, pair: TradingPair) !void;

    /// 停止 paper trading
    pub fn stop(self: *PaperTradingEngine) !void;

    /// WebSocket 数据回调
    pub fn onOrderbookUpdate(
        self: *PaperTradingEngine,
        orderbook: Orderbook,
    ) !void;

    /// 主循环（每根 K 线）
    fn processCandleClose(
        self: *PaperTradingEngine,
        candle: Candle,
    ) !void {
        // 1. 更新 K 线缓冲区
        try self.candles_buffer.append(candle);

        // 2. 计算指标
        const candles_data = Candles{
            .allocator = self.allocator,
            .candles = self.candles_buffer.items,
            // ...
        };
        try self.strategy.populateIndicators(&candles_data);

        // 3. 更新未实现盈亏
        // ...

        // 4. 检查止损/止盈
        try self.checkExits(candle.close);

        // 5. 生成入场信号
        const signal = try self.strategy.generateEntrySignal(
            &candles_data,
            self.candles_buffer.items.len - 1,
        );

        if (signal) |sig| {
            defer sig.deinit();

            // 6. 计算交易参数
            const trade_params = try self.risk_manager.calculateTradeParams(
                sig,
                self.virtual_account.getStatus(),
                self.virtual_account.positions.items,
                atr,
            );

            // 7. 验证风险
            try self.risk_manager.validateTrade(
                trade_params,
                self.virtual_account.getStatus(),
                self.virtual_account.positions.items,
            );

            // 8. 执行虚拟订单
            if (trade_params.approved) {
                try self.executeVirtualOrder(trade_params, candle.close);
            }
        }

        // 9. 记录状态
        try self.logStatus();
    }

    fn executeVirtualOrder(
        self: *PaperTradingEngine,
        params: TradeParams,
        current_price: Decimal,
    ) !void;

    fn checkExits(
        self: *PaperTradingEngine,
        current_price: Decimal,
    ) !void;

    fn logStatus(self: *PaperTradingEngine) !void;

    /// 生成最终报告
    pub fn generateReport(self: *PaperTradingEngine) !PaperTradingReport;
};

pub const PaperTradingReport = struct {
    duration: i64,                    // 运行时长（秒）
    total_trades: usize,              // 总交易数
    winning_trades: usize,            // 盈利交易
    losing_trades: usize,             // 亏损交易
    win_rate: f64,                    // 胜率
    total_pnl: Decimal,               // 总盈亏
    max_drawdown: Decimal,            // 最大回撤
    sharpe_ratio: f64,                // 夏普比率
    trades: []Trade,                  // 交易明细

    pub fn saveToJSON(self: *PaperTradingReport, path: []const u8) !void;
};
```

**实现流程**:

1. **初始化**:
   - [ ] 连接 WebSocket
   - [ ] 订阅市场数据
   - [ ] 初始化策略
   - [ ] 初始化虚拟账户

2. **运行循环** (每根 K 线):
   - [ ] 接收实时数据
   - [ ] 更新 K 线缓冲区
   - [ ] 计算技术指标
   - [ ] 更新未实现盈亏
   - [ ] 检查止损/止盈
   - [ ] 生成交易信号
   - [ ] 风险管理验证
   - [ ] 执行虚拟订单
   - [ ] 记录日志

3. **结束**:
   - [ ] 关闭所有虚拟仓位
   - [ ] 生成报告
   - [ ] 保存结果

**测试要点**:
- [ ] WebSocket 数据正确接收
- [ ] 指标计算正确
- [ ] 虚拟订单执行正确
- [ ] 风险管理正确应用
- [ ] 报告生成正确

---

#### 2.3 CLI 命令实现 (1 天)

**文件**: `src/cli/commands/run_strategy.zig` (更新)

**命令格式**:
```bash
# Paper trading 模式
zigquant run-strategy \
  --strategy rsi_mean_reversion \
  --config config.json \
  --paper \
  --initial-balance 10000 \
  --duration 24h \
  --output paper_results.json
```

**参数说明**:
- `--strategy`: 策略名称
- `--config`: 策略配置文件
- `--paper`: Paper trading 模式（必需）
- `--initial-balance`: 初始虚拟资金（默认 10000）
- `--duration`: 运行时长（如 1h, 24h, 7d）
- `--output`: 结果保存路径（可选）

**实现**:
```zig
pub fn cmdRunStrategy(
    allocator: std.mem.Allocator,
    logger: *Logger,
    args: []const []const u8,
) !void {
    // 1. 解析参数
    var res = try clap.parseEx(...);
    defer res.deinit();

    // 2. 检查模式
    if (!res.args.paper) {
        try logger.err("Live trading not yet implemented", .{});
        try logger.info("Please use --paper for paper trading", .{});
        return error.NotImplemented;
    }

    // 3. 加载策略配置
    const config_json = try loadConfigFile(res.args.config);
    defer allocator.free(config_json);

    // 4. 创建策略
    var factory = StrategyFactory.init(allocator);
    var strategy_wrapper = try factory.create(res.args.strategy, config_json);
    defer strategy_wrapper.deinit();

    // 5. 创建风险管理器
    var risk_mgr = try RiskManager.init(allocator, risk_limits, .fixed_fractional);
    defer risk_mgr.deinit();

    // 6. 创建 paper trading engine
    var engine = try PaperTradingEngine.init(
        allocator,
        logger.*,
        strategy_wrapper.interface,
        risk_mgr,
        initial_balance,
    );
    defer engine.deinit();

    // 7. 启动 paper trading
    try logger.info("Starting paper trading...", .{});
    try logger.info("Strategy: {s}", .{res.args.strategy});
    try logger.info("Initial balance: {}", .{initial_balance});
    try logger.info("Duration: {s}", .{res.args.duration});
    try logger.info("", .{});

    try engine.start(pair);

    // 8. 运行指定时长
    // TODO: 实现定时器或信号处理

    // 9. 停止并生成报告
    try engine.stop();
    const report = try engine.generateReport();
    defer report.deinit();

    // 10. 显示结果
    try displayReport(logger, report);

    // 11. 保存到文件（如果指定）
    if (res.args.output) |output_path| {
        try report.saveToJSON(output_path);
        try logger.info("Results saved to: {s}", .{output_path});
    }
}
```

**测试要点**:
- [ ] 参数解析正确
- [ ] 策略加载正确
- [ ] Engine 启动和停止正常
- [ ] 报告生成和显示正确

---

#### 2.4 监控和日志 (2 天)

**文件**: `src/paper_trading/monitor.zig`

**功能接口**:
```zig
pub const TradingMonitor = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    log_file: ?std.fs.File,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        log_file_path: ?[]const u8,
    ) !TradingMonitor;

    pub fn deinit(self: *TradingMonitor) void;

    /// 记录信号
    pub fn logSignal(self: *TradingMonitor, signal: Signal) !void;

    /// 记录订单
    pub fn logOrder(self: *TradingMonitor, order: VirtualOrder) !void;

    /// 记录仓位
    pub fn logPosition(self: *TradingMonitor, position: VirtualPosition) !void;

    /// 记录性能指标
    pub fn logMetrics(self: *TradingMonitor, metrics: LiveMetrics) !void;

    /// 检查告警条件
    pub fn checkAlerts(
        self: *TradingMonitor,
        account: VirtualAccount,
        daily_pnl: Decimal,
    ) !void;
};

pub const LiveMetrics = struct {
    timestamp: Timestamp,
    balance: Decimal,
    equity: Decimal,
    unrealized_pnl: Decimal,
    open_positions: usize,
    total_trades: usize,
    win_rate: f64,
    daily_pnl: Decimal,
};
```

**日志格式示例**:
```
[2024-12-26 10:30:00] SIGNAL: RSI Mean Reversion - LONG @ 45000.00
  Reason: RSI oversold (28.5)
  Strength: 0.85

[2024-12-26 10:30:01] ORDER: BUY 0.001 BTC @ 45000.00
  Stop Loss: 44100.00 (-2%)
  Take Profit: 46800.00 (+4%, R:R = 2:1)
  Risk: $90.00 (0.9%)

[2024-12-26 10:35:00] POSITION: Opened LONG position
  Entry: 45000.00
  Size: 0.001 BTC
  Value: $45.00

[2024-12-26 15:00:00] METRICS:
  Balance: $10,050.00
  Equity: $10,065.00 (unrealized: +$15.00)
  Open Positions: 1
  Total Trades: 3
  Win Rate: 66.7%
  Daily P&L: +$50.00 (+0.5%)
```

**告警条件**:
- [ ] 每日亏损 > 2%
- [ ] 连续亏损 3 次
- [ ] 最大回撤 > 10%
- [ ] 单笔亏损 > 3%
- [ ] WebSocket 断连 > 30s
- [ ] 数据延迟 > 5s

**测试要点**:
- [ ] 日志格式正确
- [ ] 告警及时触发
- [ ] 文件正确写入
- [ ] 性能不受影响

---

### Phase 3: 参数优化器 (推荐，1 周) - **P1**

**详见**: `docs/NEXT_STEPS.md` 中的 Story 022 规划

**核心价值**: 自动化参数搜索，提高策略胜率

**时间安排**: 可与 Paper Trading 测试并行进行

---

### Phase 4: 实盘交易系统 (2-3 周) - **P0**

**前置条件**: Phase 1, 2, 3 全部完成并验证通过

#### 4.1 实时策略执行引擎 (1 周)

**文件**: `src/live_trading/engine.zig`

**功能接口**:
```zig
pub const LiveTradingEngine = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    // 真实组件
    exchange: *IExchange,              // 真实交易所连接
    strategy: IStrategy,               // 策略
    risk_manager: RiskManager,         // 风险管理
    position_tracker: *PositionTracker, // 真实仓位跟踪
    order_manager: *OrderManager,      // 真实订单管理

    // WebSocket 数据流
    ws_manager: *WebSocketManager,
    orderbook: *Orderbook,

    // 状态
    is_running: bool,
    emergency_stop: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        exchange: *IExchange,
        strategy: IStrategy,
        risk_manager: RiskManager,
    ) !LiveTradingEngine;

    pub fn deinit(self: *LiveTradingEngine) void;

    /// 启动实盘交易
    pub fn start(self: *LiveTradingEngine, pair: TradingPair) !void;

    /// 停止实盘交易（安全停止，不平仓）
    pub fn stop(self: *LiveTradingEngine) !void;

    /// 紧急停止（平掉所有仓位，撤销所有订单）
    pub fn emergencyStop(self: *LiveTradingEngine) !void {
        try self.logger.warn("EMERGENCY STOP TRIGGERED!", .{});

        // 1. 设置紧急停止标志
        self.emergency_stop = true;

        // 2. 撤销所有挂单
        try self.order_manager.cancelAllOrders();

        // 3. 平掉所有仓位（使用市价单）
        const positions = try self.position_tracker.getAllPositions();
        for (positions) |pos| {
            try self.closePositionMarket(pos);
        }

        // 4. 停止 WebSocket
        try self.ws_manager.disconnect();

        try self.logger.warn("Emergency stop completed", .{});
    }

    /// 主循环处理
    fn processCandleClose(
        self: *LiveTradingEngine,
        candle: Candle,
    ) !void {
        // 检查紧急停止标志
        if (self.emergency_stop) return;

        // 1. 更新 K 线缓冲区
        // 2. 计算指标
        // 3. 检查止损/止盈（真实订单）
        // 4. 生成入场信号
        // 5. 风险管理验证
        // 6. 执行真实订单
        // 7. 监控和日志
    }

    fn executeRealOrder(
        self: *LiveTradingEngine,
        params: TradeParams,
    ) !void;

    fn closePositionMarket(
        self: *LiveTradingEngine,
        position: Position,
    ) !void;
};
```

**与 Paper Trading 的区别**:
- 使用真实的 Exchange 连接
- 订单真实发送到交易所
- 使用真实的 OrderManager 和 PositionTracker
- 更严格的错误处理
- 紧急停止机制

**测试要点**:
- [ ] 真实订单正确发送
- [ ] 仓位同步正确
- [ ] 紧急停止功能正常
- [ ] 异常情况处理正确

---

#### 4.2 安全检查系统 (3-4 天)

**文件**: `src/live_trading/safety.zig`

**功能接口**:
```zig
pub const SafetyChecker = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    risk_limits: RiskLimits,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        limits: RiskLimits,
    ) SafetyChecker;

    /// Pre-trade 全面检查
    pub fn validateBeforeTrade(
        self: *SafetyChecker,
        signal: Signal,
        params: TradeParams,
        account: Account,
        positions: []const Position,
    ) !void {
        try self.logger.debug("Running pre-trade safety checks...", .{});

        // 1. 账户余额检查
        if (account.balance.lessThan(params.position_size)) {
            try self.logger.err("Insufficient balance", .{});
            return error.InsufficientBalance;
        }

        // 2. 风险限制检查
        if (params.risk_percent.greaterThan(self.risk_limits.max_risk_per_trade)) {
            try self.logger.err("Risk exceeds limit: {} > {}", .{
                params.risk_percent,
                self.risk_limits.max_risk_per_trade,
            });
            return error.RiskTooHigh;
        }

        // 3. 仓位数量检查
        if (positions.len >= self.risk_limits.max_open_positions) {
            try self.logger.err("Max positions reached: {}", .{positions.len});
            return error.MaxPositionsReached;
        }

        // 4. 止损设置检查
        if (self.risk_limits.require_stop_loss and params.stop_loss == null) {
            try self.logger.err("Stop loss required but not set", .{});
            return error.StopLossRequired;
        }

        // 5. 流动性检查（检查订单簿深度）
        // TODO: 实现订单簿深度检查

        try self.logger.debug("Pre-trade checks passed", .{});
    }

    /// Runtime 持续监控
    pub fn monitorRuntime(
        self: *SafetyChecker,
        account: Account,
        positions: []const Position,
        daily_pnl: Decimal,
        max_dd_pct: Decimal,
    ) !RuntimeStatus {
        var status = RuntimeStatus{
            .is_safe = true,
            .warnings = std.ArrayList([]const u8).init(self.allocator),
            .should_stop = false,
        };

        // 1. 每日亏损检查
        if (daily_pnl.lessThan(self.risk_limits.max_daily_loss.negate())) {
            try status.warnings.append("Daily loss limit exceeded");
            status.should_stop = true;
        }

        // 2. 最大回撤检查
        if (max_dd_pct.greaterThan(self.risk_limits.max_drawdown)) {
            try status.warnings.append("Max drawdown exceeded");
            status.should_stop = true;
        }

        // 3. 连接状态检查
        // TODO: 检查 WebSocket 连接

        // 4. 数据延迟检查
        // TODO: 检查数据时间戳

        return status;
    }

    /// 检查网络连接
    pub fn checkNetworkHealth(self: *SafetyChecker) !void;

    /// 检查数据完整性
    pub fn checkDataIntegrity(
        self: *SafetyChecker,
        last_candle_time: Timestamp,
    ) !void;
};

pub const RuntimeStatus = struct {
    is_safe: bool,
    warnings: std.ArrayList([]const u8),
    should_stop: bool,

    pub fn deinit(self: *RuntimeStatus) void {
        self.warnings.deinit();
    }
};
```

**安全检查清单**:

**Pre-Trade 检查**:
- [ ] 账户余额充足
- [ ] 风险在限制内
- [ ] 仓位数量未超限
- [ ] 止损止盈设置正确
- [ ] 订单簿流动性充足
- [ ] 无异常市场条件

**Runtime 监控**:
- [ ] 每日亏损监控
- [ ] 最大回撤监控
- [ ] WebSocket 连接状态
- [ ] 数据延迟监控
- [ ] 订单执行状态
- [ ] 仓位同步状态

**Emergency Stop 触发条件**:
- [ ] 每日亏损超限
- [ ] 最大回撤超限
- [ ] 连续亏损 N 次
- [ ] WebSocket 断连超时
- [ ] 数据异常
- [ ] 系统错误

**测试要点**:
- [ ] 各种检查条件正确触发
- [ ] Emergency stop 正常工作
- [ ] 告警及时发出
- [ ] 日志完整记录

---

#### 4.3 CLI 命令实现 (1 天)

**文件**: `src/cli/commands/run_strategy.zig` (最终版本)

**命令格式**:
```bash
# 实盘交易模式（需要明确确认）
zigquant run-strategy \
  --strategy rsi_mean_reversion \
  --config config.json \
  --live \
  --confirm "I understand the risks and accept potential losses"
```

**安全措施**:
1. **多重确认**:
   ```zig
   if (res.args.live) {
       if (res.args.confirm == null) {
           try logger.err("Live trading requires --confirm flag", .{});
           return error.ConfirmationRequired;
       }

       // 二次确认
       try logger.warn("═══════════════════════════════════════", .{});
       try logger.warn("  LIVE TRADING MODE - REAL MONEY!", .{});
       try logger.warn("═══════════════════════════════════════", .{});
       try logger.info("", .{});
       try logger.info("You are about to start live trading:", .{});
       try logger.info("  Strategy: {s}", .{res.args.strategy});
       try logger.info("  Pair: {s}", .{pair});
       try logger.info("  Risk per trade: {}%", .{risk_percent});
       try logger.info("", .{});
       try logger.warn("Are you sure? Type 'YES' to continue:", .{});

       // 读取用户输入
       var buf: [100]u8 = undefined;
       const stdin = std.io.getStdIn().reader();
       const line = try stdin.readUntilDelimiter(&buf, '\n');

       if (!std.mem.eql(u8, std.mem.trim(u8, line, " \r\n"), "YES")) {
           try logger.info("Cancelled", .{});
           return;
       }
   }
   ```

2. **小额测试建议**:
   ```zig
   if (initial_balance.greaterThan(try Decimal.fromString("1000"))) {
       try logger.warn("⚠️  Large initial balance detected!", .{});
       try logger.warn("⚠️  Recommend starting with $100-500 for testing", .{});
       try logger.info("", .{});
   }
   ```

3. **风险提示**:
   ```zig
   try logger.warn("RISK DISCLOSURE:", .{});
   try logger.warn("- Trading involves risk of loss", .{});
   try logger.warn("- Past performance does not guarantee future results", .{});
   try logger.warn("- Only trade with money you can afford to lose", .{});
   try logger.warn("- Monitor your trades actively", .{});
   try logger.warn("- Emergency stop: Ctrl+C or kill the process", .{});
   try logger.info("", .{});
   ```

**测试要点**:
- [ ] 确认机制正常工作
- [ ] 风险提示清晰显示
- [ ] 用户输入正确处理
- [ ] 取消操作正常工作

---

#### 4.4 监控和报告 (3-4 天)

**文件**: `src/live_trading/monitoring.zig`

**功能**:

1. **实时监控仪表盘**:
   ```
   ═══════════════════════════════════════════════════════════
   ZigQuant Live Trading - RSI Mean Reversion
   ═══════════════════════════════════════════════════════════

   Account Status:
     Balance:         $10,125.50
     Equity:          $10,140.00  (+$14.50)
     Total P&L:       +$140.00 (+1.40%)
     Daily P&L:       +$25.50 (+0.25%)

   Positions:
     BTC/USDT LONG   0.001 @ $45,000  P&L: +$15.00 (+0.33%)

   Today's Performance:
     Trades:          5
     Win Rate:        60.0% (3W/2L)
     Largest Win:     +$50.00
     Largest Loss:    -$25.00
     Drawdown:        -0.5%

   System Status:
     WebSocket:       ✓ Connected (0.5ms latency)
     Last Update:     2s ago
     Data Quality:    ✓ Good

   [Ctrl+C to stop | Updates every 5s]
   ═══════════════════════════════════════════════════════════
   ```

2. **告警通知** (可选):
   - 邮件通知
   - Webhook (Telegram, Discord, etc.)
   - 系统通知

3. **每日报告**:
   ```
   Daily Trading Report - 2024-12-26
   ═══════════════════════════════════

   Summary:
     Total Trades:     12
     Win Rate:         58.3% (7W/5L)
     Total P&L:        +$145.00 (+1.45%)
     Largest Win:      +$80.00
     Largest Loss:     -$40.00
     Max Drawdown:     -1.2%

   Trades:
     [10:30] BUY  0.001 BTC @ 45000 → [11:00] SELL @ 45800  P&L: +$0.80
     [12:15] BUY  0.001 BTC @ 45500 → [12:45] SELL @ 45200  P&L: -$0.30
     ...

   Performance vs Backtest:
     Backtest Win Rate:    62.0%
     Live Win Rate:        58.3%  (-3.7%)
     ✓ Within expected variance
   ```

**测试要点**:
- [ ] 仪表盘正确显示
- [ ] 告警及时发送
- [ ] 报告准确生成
- [ ] 性能数据正确

---

## 🚦 实盘交易前检查清单

### 技术准备 ✅

#### 系统功能
- [ ] **风险管理系统完整实现**
  - [ ] PositionSizer 实现并测试通过
  - [ ] StopLossManager 实现并测试通过
  - [ ] RiskValidator 实现并测试通过
  - [ ] RiskManager 集成测试通过

- [ ] **Paper Trading 验证通过**
  - [ ] 至少运行 2 周 paper trading
  - [ ] 策略表现符合预期（接近回测结果）
  - [ ] 无系统错误或崩溃
  - [ ] 内存泄漏检查通过

- [ ] **安全机制完善**
  - [ ] Emergency stop 功能测试通过
  - [ ] Pre-trade 检查完整
  - [ ] Runtime 监控正常
  - [ ] 异常情况处理验证

- [ ] **监控和告警系统**
  - [ ] 实时监控正常工作
  - [ ] 告警机制测试通过
  - [ ] 日志记录完整
  - [ ] 每日报告生成正常

#### 代码质量
- [ ] **单元测试**
  - [ ] 所有新增功能有测试
  - [ ] 测试覆盖率 > 80%
  - [ ] 所有测试通过

- [ ] **内存管理**
  - [ ] GPA 检查零泄漏
  - [ ] 长时间运行稳定
  - [ ] 内存占用合理

- [ ] **错误处理**
  - [ ] 网络异常处理
  - [ ] 数据异常处理
  - [ ] 订单失败处理
  - [ ] 系统崩溃恢复

---

### 策略准备 ✅

#### 回测验证
- [ ] **历史数据回测**
  - [ ] 至少 1 年数据回测
  - [ ] Sharpe Ratio > 1.0
  - [ ] Max Drawdown < 20%
  - [ ] Win Rate > 40%
  - [ ] Profit Factor > 1.5

- [ ] **参数优化**
  - [ ] 使用 GridSearchOptimizer 优化
  - [ ] Walk-forward 验证通过
  - [ ] 无明显过拟合
  - [ ] 参数在多个时间段稳定

#### Paper Trading 验证
- [ ] **2-4 周 paper trading**
  - [ ] 实际表现接近回测结果（误差 < 20%）
  - [ ] 无重大偏差或异常
  - [ ] 系统稳定运行
  - [ ] 所有功能正常

- [ ] **多种市场环境测试**
  - [ ] 震荡市场
  - [ ] 趋势市场
  - [ ] 高波动市场
  - [ ] 低流动性时段

#### 风险评估
- [ ] **风险参数设置**
  - [ ] 单笔风险 ≤ 1-2% 账户
  - [ ] 最大回撤承受能力明确
  - [ ] 止损止盈规则清晰
  - [ ] 仓位大小合理

- [ ] **心理准备**
  - [ ] 准备好承受亏损
  - [ ] 不会情绪化操作
  - [ ] 有明确的退出条件
  - [ ] 不会频繁干预系统

---

### 资金准备 ✅

#### 小额测试
- [ ] **使用小额资金**
  - [ ] 初始资金 $100-500
  - [ ] 测试 1-2 周
  - [ ] 验证系统稳定性
  - [ ] 验证策略有效性

#### 风险承受
- [ ] **资金管理**
  - [ ] 只使用可承受损失的资金
  - [ ] 准备好心理承受亏损
  - [ ] 不使用杠杆（初期）
  - [ ] 不使用生活必需资金

#### 退出计划
- [ ] **明确退出条件**
  - [ ] 每日最大亏损限制
  - [ ] 总体风险敞口限制
  - [ ] 连续亏损次数限制
  - [ ] 策略失效判断标准

---

## 📅 推荐时间线

### 保守路径（8-12 周，推荐）

**Week 1-2: Phase 1 - 风险管理系统** ✨ **从这里开始！**
- Week 1:
  - Day 1-2: PositionSizer 实现
  - Day 3-4: StopLossManager 实现
  - Day 5: 单元测试
- Week 2:
  - Day 1-2: RiskValidator 实现
  - Day 3-4: RiskManager 集成
  - Day 5: 完整测试

**Week 3: Phase 2 - Paper Trading 实现**
- Day 1-2: VirtualAccount 实现
- Day 3-4: PaperTradingEngine 实现
- Day 5: CLI 命令 + 监控

**Week 4-7: Paper Trading 测试（关键！）**
- Week 4-5: 持续运行 paper trading
- Week 6-7: 多种市场环境验证
- 同时进行：Week 5-6 实现参数优化器

**Week 8: Phase 4 - 实盘准备**
- Day 1-3: LiveTradingEngine 实现
- Day 4-5: SafetyChecker 完善

**Week 9-10: 小额实盘测试**
- 使用 $100-500 测试
- 密切监控
- 调整参数

**Week 11-12: 逐步扩大**
- 根据表现逐步增加资金
- 持续监控和优化

### 激进路径（4-6 周，风险较高，不推荐）

**Week 1-2: 风险管理 + Paper Trading 实现**
**Week 3-4: Paper Trading 测试（最少 2 周）**
**Week 5: 实盘准备**
**Week 6: 小额测试**

⚠️ **警告**: 激进路径风险很高，缺少充分验证！

---

## 🎯 核心功能优先级

### P0 - 绝对必须（实盘前必须完成）

1. **风险管理系统** (1-2 周)
   - 最高优先级
   - 保护资金安全
   - 防止灾难性亏损

2. **Paper Trading** (1 周开发 + 2-4 周测试)
   - 验证策略有效性
   - 发现系统问题
   - 积累运行经验

3. **监控和告警** (3-4 天)
   - 实时监控系统状态
   - 异常及时告警
   - 紧急停止机制

### P1 - 强烈推荐（提高成功率）

4. **参数优化器** (1 周)
   - 自动化参数搜索
   - Walk-forward 验证
   - 避免过拟合

5. **更多策略验证** (3-5 天)
   - 测试多个策略
   - 分散风险
   - 提高胜率

### P2 - 建议有（改善体验）

6. **结果导出** (2-3 天)
7. **策略开发指南** (2 天)
8. **性能优化** (1-2 天)

### P3 - 可以延后（高级功能）

9. **多策略组合**
10. **自适应参数**
11. **机器学习集成**

---

## 💡 实施建议

### 最安全的路径

```
当前 v0.3.0 (回测系统)
  ↓
Phase 1: 风险管理系统 (1-2 周) ← 🎯 从这里开始！
  ↓
Phase 3: 参数优化器 (1 周) ← 可与 Phase 2 并行
  ↓
Phase 2: Paper Trading 实现 (1 周)
  ↓
Paper Trading 测试 (2-4 周) ← ⚠️ 关键验证期，不可跳过
  ↓
Phase 4: 实盘准备 (1 周)
  ↓
小额实盘测试 ($100-500, 1-2 周) ← ⚠️ 谨慎开始
  ↓
逐步增加资金 ← ⚠️ 根据表现调整
```

### 关键原则

1. **安全第一** 🛡️
   - 完善的风险管理比策略优化更重要
   - 宁可错过机会，不要冒险亏损
   - 始终设置止损

2. **充分验证** ✅
   - Paper trading 至少 2 周
   - 观察各种市场情况
   - 验证系统稳定性

3. **小额开始** 💰
   - 实盘先用 $100-500 测试
   - 确认系统稳定后再增加
   - 不要一次性投入大量资金

4. **持续监控** 👀
   - 实盘后要持续监控
   - 及时发现问题
   - 准备随时停止

5. **心理准备** 🧠
   - 准备好承受亏损
   - 不要情绪化操作
   - 相信系统，不要频繁干预

---

## 🚨 风险警告

### 技术风险

**网络和系统**:
- ⚠️ **WebSocket 断连**: 可能错过重要数据
- ⚠️ **数据延迟**: 导致错误决策
- ⚠️ **系统崩溃**: 程序异常退出
- ⚠️ **内存泄漏**: 长时间运行不稳定

**缓解措施**:
- ✅ 断线重连机制
- ✅ 数据延迟监控
- ✅ 异常恢复机制
- ✅ 内存泄漏检测

**交易执行**:
- ⚠️ **订单被拒**: 余额不足、参数错误
- ⚠️ **部分成交**: 流动性不足
- ⚠️ **滑点**: 实际价格偏离预期
- ⚠️ **订单延迟**: 网络延迟导致成交价差

**缓解措施**:
- ✅ Pre-trade 验证
- ✅ 流动性检查
- ✅ 滑点限制
- ✅ 订单超时处理

### 市场风险

**市场波动**:
- ⚠️ **黑天鹅事件**: 极端市场波动
- ⚠️ **闪崩**: 瞬间大幅下跌
- ⚠️ **流动性枯竭**: 无法按预期价格成交
- ⚠️ **策略失效**: 市场环境变化

**缓解措施**:
- ✅ 严格的风险限制
- ✅ 止损保护
- ✅ 仓位控制
- ✅ 定期评估策略

**策略风险**:
- ⚠️ **过拟合**: 回测好但实盘差
- ⚠️ **参数敏感**: 小变化导致大差异
- ⚠️ **市场适应**: 策略不适应新环境
- ⚠️ **相关性**: 多仓位同时亏损

**缓解措施**:
- ✅ Walk-forward 验证
- ✅ 参数鲁棒性测试
- ✅ 多策略分散
- ✅ 相关性监控

### 操作风险

**人为错误**:
- ⚠️ **配置错误**: 参数设置错误
- ⚠️ **手动干预**: 情绪化操作
- ⚠️ **监控缺失**: 未及时发现问题
- ⚠️ **资金管理失误**: 仓位过大

**缓解措施**:
- ✅ 配置验证
- ✅ 自动化执行
- ✅ 实时监控
- ✅ 严格风控

---

## 🎯 何时可以开始实盘？

### 最低要求（必须全部满足）

1. ✅ **风险管理系统完整**
   - 1-2 周开发
   - 所有功能测试通过

2. ✅ **Paper trading 2-4 周验证通过**
   - 策略表现符合预期
   - 系统稳定无崩溃
   - 无重大偏差

3. ✅ **监控和告警系统完善**
   - 实时监控正常
   - 告警及时触发

4. ✅ **紧急停止机制测试通过**
   - Emergency stop 功能正常
   - 异常处理完善

5. ✅ **小额资金测试 1-2 周**
   - $100-500 测试
   - 验证真实环境表现

### 推荐要求（强烈建议）

6. ✅ **参数优化完成**
   - GridSearchOptimizer 实现
   - 策略参数经过优化
   - Walk-forward 验证通过

7. ✅ **多个策略验证**
   - 至少 2-3 个策略
   - 分散风险

8. ✅ **3+ 个月历史数据回测**
   - 充分验证策略
   - 多种市场环境

### 心理准备

9. ✅ **风险意识**
   - 理解可能亏损
   - 只用闲置资金
   - 不影响生活

10. ✅ **执行纪律**
    - 相信系统
    - 不情绪化
    - 坚持规则

---

## 📊 总时间估算

### 最快路径（不推荐）
- **时间**: 4-6 周
- **风险**: 高
- **成功率**: 低-中
- **适用**: 经验丰富的交易者

### 推荐路径（稳健）
- **时间**: 8-12 周
- **风险**: 中
- **成功率**: 中-高
- **适用**: 大多数情况

### 理想路径（最安全）
- **时间**: 3-6 个月
- **风险**: 低-中
- **成功率**: 高
- **适用**: 新手、大额资金

---

## 🚀 立即开始的行动步骤

### 今天就可以做

1. **阅读本文档** ✅
   - 理解完整路径
   - 评估时间和风险
   - 制定个人计划

2. **评估当前状态**
   ```bash
   # 运行现有测试
   zig build test

   # 回顾回测结果
   ./zigquant backtest --strategy rsi_mean_reversion \
     --config examples/strategies/rsi_mean_reversion.json \
     --data data/BTCUSDT_1h_2024.csv
   ```

3. **制定实施计划**
   - 确定可投入时间
   - 选择路径（推荐 8-12 周）
   - 设定里程碑

### 本周可以做

**Week 1: 开始 Phase 1 - 风险管理系统**

```bash
# 1. 创建目录结构
mkdir -p src/risk
touch src/risk/position_sizing.zig
touch src/risk/stop_loss.zig
touch src/risk/risk_limits.zig
touch src/risk/manager.zig

# 2. 开始实现 PositionSizer
vim src/risk/position_sizing.zig

# 3. 编写测试
touch tests/risk_tests.zig

# 4. 运行测试
zig build test
```

**参考实现计划**: 见本文档 Phase 1 详细设计

---

## 📚 相关文档

### 项目文档
- `docs/MVP_V0.3.0_PROGRESS.md` - v0.3.0 进度
- `docs/NEXT_STEPS.md` - 下一步计划（Story 022 等）
- `docs/STORY_023_COMPLETE.md` - Story 023 完成报告

### 技术文档
- `docs/features/backtest/` - 回测系统文档
- `docs/features/strategy/` - 策略框架文档（待创建）
- `docs/features/risk/` - 风险管理文档（待创建）

### 用户指南（待创建）
- `docs/guides/RISK_MANAGEMENT.md` - 风险管理指南
- `docs/guides/PAPER_TRADING.md` - Paper trading 指南
- `docs/guides/LIVE_TRADING.md` - 实盘交易指南

---

## 🎯 总结

### 核心建议

1. **不要着急！**
   - 实盘交易需要充分准备
   - 宁可多花时间验证，也不要草率上线

2. **安全第一！**
   - 风险管理是基石
   - 保护资金比赚钱更重要

3. **小额开始！**
   - 先用 $100-500 测试
   - 验证系统后再增加资金

4. **持续学习！**
   - 市场在变化
   - 策略需要调整
   - 系统需要优化

### 现在就开始

**Phase 1: 风险管理系统是实盘交易的基石，也是当前最高优先级任务！**

建议从 **PositionSizer** 开始实现，这是整个风险管理系统的核心。

需要我帮你开始实现吗？ 🚀

---

**文档版本**: v1.0
**最后更新**: 2025-12-26
**作者**: Claude (Sonnet 4.5)
**状态**: ✅ 完整
