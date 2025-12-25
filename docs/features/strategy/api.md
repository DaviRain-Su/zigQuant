# Strategy Framework API 参考

**版本**: v0.3.0
**更新时间**: 2025-12-25

---

## 📋 目录

1. [IStrategy 接口](#istrategy-接口)
2. [StrategyContext](#strategycontext)
3. [Signal 类型](#signal-类型)
4. [StrategyMetadata](#strategymetadata)
5. [StrategyParameter](#strategyparameter)
6. [辅助类型](#辅助类型)

---

## IStrategy 接口

### 概述

所有策略必须实现的统一接口，基于 VTable 模式。

```zig
pub const IStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        init: *const fn (*anyopaque, StrategyContext) anyerror!void,
        deinit: *const fn (*anyopaque) void,
        populateIndicators: *const fn (*anyopaque, *Candles) anyerror!void,
        generateEntrySignal: *const fn (*anyopaque, *Candles, usize) anyerror!?Signal,
        generateExitSignal: *const fn (*anyopaque, *Candles, Position) anyerror!?Signal,
        calculatePositionSize: *const fn (*anyopaque, Signal, Account) anyerror!Decimal,
        getParameters: *const fn (*anyopaque) []StrategyParameter,
        getMetadata: *const fn (*anyopaque) StrategyMetadata,
    };
};
```

### 方法详解

#### init

初始化策略实例。

```zig
pub fn init(self: IStrategy, ctx: StrategyContext) anyerror!void
```

**参数**:
- `ctx`: 策略执行上下文

**说明**:
- 在策略开始执行前调用一次
- 用于保存上下文引用和初始化内部状态
- 不应在此方法中进行耗时操作

**示例**:
```zig
fn initImpl(ptr: *anyopaque, ctx: StrategyContext) !void {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));
    self.ctx = ctx;
    self.last_signal_time = null;
}
```

---

#### deinit

清理策略资源。

```zig
pub fn deinit(self: IStrategy) void
```

**说明**:
- 在策略执行完成后调用
- 释放策略分配的所有内存
- 必须是无错误的操作

**示例**:
```zig
fn deinitImpl(ptr: *anyopaque) void {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));
    if (self.cached_data) |data| {
        self.allocator.free(data);
    }
    self.allocator.destroy(self);
}
```

---

#### populateIndicators

计算技术指标并添加到蜡烛数据中（参考 Freqtrade `populate_indicators`）。

```zig
pub fn populateIndicators(self: IStrategy, candles: *Candles) anyerror!void
```

**参数**:
- `candles`: 蜡烛数据，包含 OHLCV 数据

**说明**:
- 在策略执行前调用一次（回测模式）
- 实时模式下每收到新蜡烛时调用
- 使用 `candles.addIndicator()` 添加指标结果
- 指标值数组长度必须与 `candles.data.len` 相同

**示例**:
```zig
fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
    const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

    // 计算快速 MA
    const fast_ma = try SMA.init(self.allocator, self.fast_period).calculate(candles.data);
    try candles.addIndicator("ma_fast", fast_ma);

    // 计算慢速 MA
    const slow_ma = try SMA.init(self.allocator, self.slow_period).calculate(candles.data);
    try candles.addIndicator("ma_slow", slow_ma);

    // 计算 RSI
    const rsi = try RSI.init(self.allocator, 14).calculate(candles.data);
    try candles.addIndicator("rsi", rsi);
}
```

---

#### generateEntrySignal

生成入场信号（参考 Freqtrade `populate_entry_trend`）。

```zig
pub fn generateEntrySignal(
    self: IStrategy,
    candles: *Candles,
    index: usize
) anyerror!?Signal
```

**参数**:
- `candles`: 蜡烛数据（包含已计算的指标）
- `index`: 当前蜡烛索引

**返回**:
- `?Signal`: 信号（如果没有信号则返回 `null`）

**说明**:
- 回测模式: 遍历每根蜡烛时调用
- 实时模式: 每收到新蜡烛时调用
- 只能使用 `index` 及之前的数据（避免未来函数）
- 返回 `null` 表示无入场信号

**示例**:
```zig
fn generateEntrySignalImpl(ptr: *anyopaque, candles: *Candles, index: usize) !?Signal {
    const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

    if (index < self.slow_period) return null;

    const fast_ma = candles.getIndicator("ma_fast") orelse return null;
    const slow_ma = candles.getIndicator("ma_slow") orelse return null;

    const prev_fast = fast_ma[index - 1];
    const prev_slow = slow_ma[index - 1];
    const curr_fast = fast_ma[index];
    const curr_slow = slow_ma[index];

    // 金叉 - 快线上穿慢线
    if (prev_fast.lte(prev_slow) and curr_fast.gt(curr_slow)) {
        return Signal{
            .type = .entry_long,
            .pair = self.ctx.config.pair,
            .side = .buy,
            .price = candles.data[index].close,
            .strength = 0.8,
            .timestamp = candles.data[index].timestamp,
            .metadata = null,
        };
    }

    return null;
}
```

---

#### generateExitSignal

生成出场信号（参考 Freqtrade `populate_exit_trend`）。

```zig
pub fn generateExitSignal(
    self: IStrategy,
    candles: *Candles,
    pos: Position
) anyerror!?Signal
```

**参数**:
- `candles`: 蜡烛数据（包含已计算的指标）
- `pos`: 当前持仓

**返回**:
- `?Signal`: 出场信号（如果不需要出场则返回 `null`）

**说明**:
- 仅在有持仓时调用
- 用于主动平仓逻辑（止盈、止损、反向信号等）
- 如果返回 `null`，框架会根据 `StrategyMetadata` 中的配置执行被动止盈止损

**示例**:
```zig
fn generateExitSignalImpl(ptr: *anyopaque, candles: *Candles, pos: Position) !?Signal {
    const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

    const fast_ma = candles.getIndicator("ma_fast") orelse return null;
    const slow_ma = candles.getIndicator("ma_slow") orelse return null;

    const index = candles.data.len - 1;
    const prev_fast = fast_ma[index - 1];
    const prev_slow = slow_ma[index - 1];
    const curr_fast = fast_ma[index];
    const curr_slow = slow_ma[index];

    // 如果持有多单，遇到死叉则平仓
    if (pos.side == .long and prev_fast.gte(prev_slow) and curr_fast.lt(curr_slow)) {
        return Signal{
            .type = .exit_long,
            .pair = pos.pair,
            .side = .sell,
            .price = candles.data[index].close,
            .strength = 0.8,
            .timestamp = candles.data[index].timestamp,
            .metadata = null,
        };
    }

    return null;
}
```

---

#### calculatePositionSize

计算仓位大小。

```zig
pub fn calculatePositionSize(
    self: IStrategy,
    signal: Signal,
    account: Account
) anyerror!Decimal
```

**参数**:
- `signal`: 入场信号
- `account`: 账户状态（余额、已用保证金等）

**返回**:
- `Decimal`: 仓位大小（以 base asset 计价）

**说明**:
- 在生成入场信号后调用
- 根据账户状态、风险管理规则计算合适的仓位大小
- 返回值会被 RiskManager 进一步验证

**示例**:
```zig
fn calculatePositionSizeImpl(ptr: *anyopaque, signal: Signal, account: Account) !Decimal {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));

    // 固定比例: 使用 10% 的可用余额
    const available = account.balance.available;
    const allocation = try available.mul(try Decimal.fromFloat(0.1));

    // 根据价格计算数量
    const quantity = try allocation.div(signal.price);

    return quantity;
}
```

---

#### getParameters

获取策略参数列表（用于参数优化）。

```zig
pub fn getParameters(self: IStrategy) []StrategyParameter
```

**返回**:
- `[]StrategyParameter`: 参数数组

**说明**:
- 定义策略的所有可调参数
- 用于参数优化和策略配置
- 标记 `optimize = true` 的参数会参与优化过程

**示例**:
```zig
fn getParametersImpl(ptr: *anyopaque) []StrategyParameter {
    _ = ptr;

    const params = [_]StrategyParameter{
        .{
            .name = "fast_period",
            .type = .integer,
            .default_value = .{ .integer = 10 },
            .range = .{ .integer = .{ .min = 5, .max = 20, .step = 1 } },
            .optimize = true,
        },
        .{
            .name = "slow_period",
            .type = .integer,
            .default_value = .{ .integer = 20 },
            .range = .{ .integer = .{ .min = 15, .max = 50, .step = 5 } },
            .optimize = true,
        },
    };

    return &params;
}
```

---

#### getMetadata

获取策略元数据。

```zig
pub fn getMetadata(self: IStrategy) StrategyMetadata
```

**返回**:
- `StrategyMetadata`: 策略元数据

**说明**:
- 描述策略的基本信息和风险参数
- 包含止盈止损配置（参考 Freqtrade）
- 框架会根据元数据自动执行被动风控

**示例**:
```zig
fn getMetadataImpl(ptr: *anyopaque) StrategyMetadata {
    const self: *DualMAStrategy = @ptrCast(@alignCast(ptr));

    return StrategyMetadata{
        .name = "Dual Moving Average",
        .version = "1.0.0",
        .author = "zigQuant",
        .description = "Classic dual MA crossover strategy",
        .strategy_type = .trend_following,
        .timeframe = .m15,
        .startup_candle_count = self.slow_period,
        .minimal_roi = MinimalROI{
            .targets = &[_]MinimalROI.ROITarget{
                .{ .time_minutes = 0, .profit_ratio = try Decimal.fromFloat(0.02) },   // 2% 立即止盈
                .{ .time_minutes = 30, .profit_ratio = try Decimal.fromFloat(0.01) },  // 30分钟后 1% 止盈
            },
        },
        .stoploss = try Decimal.fromFloat(-0.05),  // -5% 止损
        .trailing_stop = null,
    };
}
```

---

## StrategyContext

### 定义

```zig
pub const StrategyContext = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    /// 市场数据提供者
    market_data: *MarketDataProvider,

    /// 订单执行器
    executor: *OrderExecutor,

    /// 仓位管理器
    position_manager: *PositionManager,

    /// 风险管理器
    risk_manager: *RiskManager,

    /// 指标管理器
    indicator_manager: *IndicatorManager,

    /// 交易所接口
    exchange: IExchange,

    /// 策略配置
    config: StrategyConfig,
};
```

### 字段说明

#### allocator
内存分配器，用于策略内部分配内存。

#### logger
日志记录器，用于记录策略执行日志。

#### market_data
市场数据提供者，提供实时和历史行情数据。

**方法**:
- `getCandles(pair, timeframe, count)`: 获取最新 N 根蜡烛
- `getOrderbook(pair, depth)`: 获取订单簿
- `getTicker(pair)`: 获取 ticker 数据

#### executor
订单执行器，处理订单提交和管理。

**方法**:
- `executeSignal(signal, size)`: 执行交易信号
- `cancelOrder(order_id)`: 撤销订单
- `getOpenOrders()`: 获取未完成订单

#### position_manager
仓位管理器，追踪当前持仓状态。

**方法**:
- `getPosition(pair)`: 获取指定交易对的仓位
- `getAllPositions()`: 获取所有仓位
- `updatePosition(trade)`: 更新仓位（框架自动调用）

#### risk_manager
风险管理器，执行风险控制规则。

**方法**:
- `validateOrder(order, account)`: 验证订单是否符合风控规则
- `checkStopLoss(position, current_price)`: 检查止损
- `checkTakeProfit(position, current_price)`: 检查止盈

#### indicator_manager
指标管理器，缓存和管理技术指标计算结果。

**方法**:
- `getIndicator(name, candles, calculate_fn)`: 获取指标（带缓存）
- `clearCache()`: 清除缓存

#### exchange
交易所接口，用于获取市场数据和执行交易。

#### config
策略配置，包含交易对、时间周期等。

---

## Signal 类型

### 定义

```zig
pub const Signal = struct {
    /// 信号类型
    type: SignalType,

    /// 交易对
    pair: TradingPair,

    /// 方向
    side: Side,

    /// 建议价格
    price: Decimal,

    /// 信号强度 [0.0, 1.0]
    strength: f64,

    /// 信号时间
    timestamp: Timestamp,

    /// 附加信息
    metadata: ?SignalMetadata,
};

pub const SignalType = enum {
    entry_long,      // 做多入场
    entry_short,     // 做空入场
    exit_long,       // 多单出场
    exit_short,      // 空单出场
    hold,           // 持有
};

pub const SignalMetadata = struct {
    reason: []const u8,           // 信号原因
    indicators: []IndicatorValue, // 相关指标值
};
```

### 字段说明

#### type
信号类型，决定交易动作。

#### pair
交易对（如 ETH-USDC）。

#### side
交易方向（buy 或 sell）。

#### price
建议执行价格（通常是当前蜡烛的收盘价）。

#### strength
信号强度，范围 [0.0, 1.0]：
- `0.0 - 0.3`: 弱信号
- `0.4 - 0.6`: 中等信号
- `0.7 - 1.0`: 强信号

可用于仓位大小调整。

#### timestamp
信号生成时间。

#### metadata
附加信息，用于调试和分析。

---

## StrategyMetadata

### 定义

```zig
pub const StrategyMetadata = struct {
    name: []const u8,
    version: []const u8,
    author: []const u8,
    description: []const u8,

    /// 策略类型
    strategy_type: StrategyType,

    /// 时间周期
    timeframe: Timeframe,

    /// 启动需要的蜡烛数
    startup_candle_count: u32,

    /// 最小 ROI 目标（参考 Freqtrade）
    minimal_roi: MinimalROI,

    /// 止损百分比
    stoploss: Decimal,

    /// 追踪止损配置
    trailing_stop: ?TrailingStopConfig,
};

pub const StrategyType = enum {
    trend_following,    // 趋势跟随
    mean_reversion,     // 均值回归
    breakout,          // 突破
    arbitrage,         // 套利
    market_making,     // 做市
    grid_trading,      // 网格交易
    custom,            // 自定义
};
```

### MinimalROI

```zig
pub const MinimalROI = struct {
    targets: []ROITarget,

    pub const ROITarget = struct {
        time_minutes: u32,
        profit_ratio: Decimal,
    };
};
```

**说明**:
参考 Freqtrade 的 minimal_roi 设计，定义分阶段止盈目标：

```zig
.minimal_roi = MinimalROI{
    .targets = &[_]MinimalROI.ROITarget{
        .{ .time_minutes = 0, .profit_ratio = try Decimal.fromFloat(0.04) },   // 立即 4% 止盈
        .{ .time_minutes = 20, .profit_ratio = try Decimal.fromFloat(0.02) },  // 20分钟后 2% 止盈
        .{ .time_minutes = 60, .profit_ratio = try Decimal.fromFloat(0.01) },  // 1小时后 1% 止盈
    },
},
```

框架会自动检查：
- 如果持仓时间 < 20分钟且收益 >= 4%，则平仓
- 如果持仓时间 >= 20分钟且收益 >= 2%，则平仓
- 如果持仓时间 >= 60分钟且收益 >= 1%，则平仓

### TrailingStopConfig

```zig
pub const TrailingStopConfig = struct {
    enabled: bool,
    positive_offset: Decimal,  // 正收益后才启动
    only_offset_is_reached: bool,
};
```

**示例**:
```zig
.trailing_stop = TrailingStopConfig{
    .enabled = true,
    .positive_offset = try Decimal.fromFloat(0.01),  // 收益达到 1% 后启动追踪止损
    .only_offset_is_reached = true,                   // 仅在达到 offset 后启动
},
```

---

## StrategyParameter

### 定义

```zig
pub const StrategyParameter = struct {
    name: []const u8,
    type: ParameterType,
    default_value: ParameterValue,
    range: ?ParameterRange,
    optimize: bool,  // 是否参与优化
};

pub const ParameterType = enum {
    integer,
    decimal,
    boolean,
    string,
};

pub const ParameterValue = union(ParameterType) {
    integer: i64,
    decimal: Decimal,
    boolean: bool,
    string: []const u8,
};

pub const ParameterRange = union(enum) {
    integer: struct { min: i64, max: i64, step: i64 },
    decimal: struct { min: Decimal, max: Decimal, step: Decimal },
};
```

### 示例

```zig
const params = [_]StrategyParameter{
    .{
        .name = "fast_period",
        .type = .integer,
        .default_value = .{ .integer = 10 },
        .range = .{ .integer = .{ .min = 5, .max = 20, .step = 1 } },
        .optimize = true,
    },
    .{
        .name = "use_trailing_stop",
        .type = .boolean,
        .default_value = .{ .boolean = true },
        .range = null,
        .optimize = false,
    },
};
```

---

## 辅助类型

### Candles

```zig
pub const Candles = struct {
    allocator: std.mem.Allocator,
    data: []Candle,
    indicators: std.StringHashMap([]Decimal),

    pub fn addIndicator(self: *Candles, name: []const u8, values: []Decimal) !void;
    pub fn getIndicator(self: *Candles, name: []const u8) ?[]Decimal;
    pub fn deinit(self: *Candles) void;
};
```

### Candle

```zig
pub const Candle = struct {
    timestamp: Timestamp,
    open: Decimal,
    high: Decimal,
    low: Decimal,
    close: Decimal,
    volume: Decimal,
};
```

### Position

```zig
pub const Position = struct {
    pair: TradingPair,
    side: PositionSide,
    size: Decimal,
    entry_price: Decimal,
    timestamp: Timestamp,
};

pub const PositionSide = enum {
    long,
    short,
};
```

### Account

```zig
pub const Account = struct {
    balance: Balance,
    used_margin: Decimal,
    leverage: u32,
};

pub const Balance = struct {
    asset: []const u8,
    total: Decimal,
    available: Decimal,
    locked: Decimal,
};
```

---

## 错误类型

```zig
pub const StrategyError = error{
    InsufficientData,       // 蜡烛数据不足
    InvalidParameter,       // 无效参数
    IndicatorNotFound,      // 指标未找到
    CalculationFailed,      // 计算失败
    ContextNotInitialized,  // 上下文未初始化
};
```

---

**版本**: v0.3.0
**状态**: 设计阶段
**更新时间**: 2025-12-25
