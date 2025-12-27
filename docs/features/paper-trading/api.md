# Paper Trading API 参考

**模块**: `zigQuant.trading.paper`
**版本**: v0.6.0
**状态**: 📋 待开始

---

## PaperTradingEngine

Paper Trading 核心引擎。

### 类型定义

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
};
```

### Config

```zig
pub const Config = struct {
    /// 初始账户余额
    initial_balance: Decimal = Decimal.fromInt(10000),

    /// 手续费率
    commission_rate: Decimal = Decimal.fromFloat(0.0005),

    /// 滑点
    slippage: Decimal = Decimal.fromFloat(0.0001),

    /// 订阅的交易对
    symbols: []const []const u8,

    /// tick 间隔 (毫秒)
    tick_interval_ms: u32 = 1000,

    /// 是否记录交易日志
    log_trades: bool = true,
};
```

### 方法

#### init

```zig
pub fn init(allocator: Allocator, config: Config) !PaperTradingEngine
```

初始化 Paper Trading 引擎。

**参数**:
- `allocator`: 内存分配器
- `config`: 配置选项

**返回**: 初始化的引擎实例

---

#### deinit

```zig
pub fn deinit(self: *PaperTradingEngine) void
```

释放所有资源。

---

#### setStrategy

```zig
pub fn setStrategy(self: *PaperTradingEngine, strategy: IStrategy) void
```

设置交易策略。

**参数**:
- `strategy`: 实现 IStrategy 接口的策略

---

#### start

```zig
pub fn start(self: *PaperTradingEngine) !void
```

启动 Paper Trading。

**错误**:
- `NoStrategy`: 未设置策略
- `ConnectionFailed`: 数据连接失败

---

#### stop

```zig
pub fn stop(self: *PaperTradingEngine) void
```

停止 Paper Trading 并打印统计摘要。

---

#### isRunning

```zig
pub fn isRunning(self: *PaperTradingEngine) bool
```

检查是否正在运行。

---

#### getStats

```zig
pub fn getStats(self: *PaperTradingEngine) Stats
```

获取当前统计信息。

---

## SimulatedExecutor

模拟订单执行器。

### 类型定义

```zig
pub const SimulatedExecutor = struct {
    allocator: Allocator,
    message_bus: *MessageBus,
    cache: *Cache,
    account: *SimulatedAccount,
    config: Config,
    open_orders: std.StringHashMap(Order),
};
```

### Config

```zig
pub const Config = struct {
    /// 手续费率
    commission_rate: Decimal,

    /// 滑点
    slippage: Decimal,

    /// 模拟成交延迟 (毫秒)
    fill_delay_ms: u32 = 0,
};
```

### 方法

#### executeOrder

```zig
pub fn executeOrder(self: *SimulatedExecutor, order: Order) !void
```

模拟执行订单。

**参数**:
- `order`: 待执行的订单

**错误**:
- `NoQuote`: 没有可用报价
- `InsufficientBalance`: 余额不足

---

#### placeLimitOrder

```zig
pub fn placeLimitOrder(self: *SimulatedExecutor, order: Order) !void
```

放置限价单 (等待触发)。

---

#### cancelOrder

```zig
pub fn cancelOrder(self: *SimulatedExecutor, order_id: []const u8) !bool
```

取消挂单。

---

## SimulatedAccount

模拟账户。

### 类型定义

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
};
```

### Position

```zig
pub const Position = struct {
    symbol: []const u8,
    quantity: Decimal,
    entry_price: Decimal,
    side: Side,
    unrealized_pnl: Decimal,
};
```

### 方法

#### init

```zig
pub fn init(initial_balance: Decimal) SimulatedAccount
```

初始化模拟账户。

---

#### applyFill

```zig
pub fn applyFill(self: *SimulatedAccount, fill: OrderFill) !void
```

应用订单成交，更新余额和仓位。

---

#### getPosition

```zig
pub fn getPosition(self: *SimulatedAccount, symbol: []const u8) ?Position
```

获取指定交易对的持仓。

---

#### getStats

```zig
pub fn getStats(self: *SimulatedAccount) Stats
```

获取账户统计信息。

---

## 数据类型

### Stats

```zig
pub const Stats = struct {
    current_balance: Decimal,
    total_pnl: Decimal,
    total_return_pct: f64,
    total_trades: usize,
    win_rate: f64,
    max_drawdown: f64,
};
```

### OrderFill

```zig
pub const OrderFill = struct {
    order_id: []const u8,
    symbol: []const u8,
    side: Side,
    fill_price: Decimal,
    fill_quantity: Decimal,
    commission: Decimal,
    timestamp: Timestamp,
};
```

### Trade

```zig
pub const Trade = struct {
    symbol: []const u8,
    side: Side,
    entry_price: Decimal,
    exit_price: Decimal,
    quantity: Decimal,
    pnl: Decimal,
    timestamp: Timestamp,
};
```

### EquityPoint

```zig
pub const EquityPoint = struct {
    timestamp: Timestamp,
    equity: Decimal,
};
```

---

*Last updated: 2025-12-27*
