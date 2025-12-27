# Vectorized Backtest API 参考

**模块**: `zigQuant.backtest.vectorized`
**版本**: v0.6.0
**状态**: 📋 待开始

---

## VectorizedBacktester

主要的向量化回测器结构体。

### 类型定义

```zig
pub const VectorizedBacktester = struct {
    allocator: Allocator,
    config: Config,
    data_loader: MmapDataLoader,
    simd_indicators: SimdIndicators,
    signal_generator: BatchSignalGenerator,
    order_simulator: BatchOrderSimulator,
};
```

### Config

```zig
pub const Config = struct {
    /// 初始资金
    initial_capital: Decimal = Decimal.fromInt(10000),

    /// 手续费率
    commission_rate: Decimal = Decimal.fromFloat(0.001),

    /// 滑点
    slippage: Decimal = Decimal.fromFloat(0.0001),

    /// 是否启用 SIMD
    use_simd: bool = true,

    /// SIMD 批处理大小
    chunk_size: usize = 1024,

    /// 是否验证数据
    validate_data: bool = true,
};
```

### 方法

#### init

```zig
pub fn init(allocator: Allocator, config: Config) VectorizedBacktester
```

初始化向量化回测器。

**参数**:
- `allocator`: 内存分配器
- `config`: 配置选项

**返回**: 初始化的回测器实例

---

#### deinit

```zig
pub fn deinit(self: *VectorizedBacktester) void
```

释放回测器资源。

---

#### loadData

```zig
pub fn loadData(self: *VectorizedBacktester, path: []const u8) !DataSet
```

使用内存映射加载数据文件。

**参数**:
- `path`: 数据文件路径 (CSV 格式)

**返回**: 加载的数据集

**错误**:
- `FileNotFound`: 文件不存在
- `InvalidFormat`: CSV 格式错误

---

#### computeIndicators

```zig
pub fn computeIndicators(
    self: *VectorizedBacktester,
    data: DataSet,
    config: IndicatorConfig,
) !IndicatorResults
```

批量计算技术指标。

**参数**:
- `data`: 输入数据集
- `config`: 指标配置

**返回**: 计算的指标结果

---

#### generateSignals

```zig
pub fn generateSignals(
    self: *VectorizedBacktester,
    indicators: IndicatorResults,
    strategy: IStrategy,
) ![]Signal
```

批量生成交易信号。

**参数**:
- `indicators`: 指标计算结果
- `strategy`: 策略实例

**返回**: 信号数组

---

#### run

```zig
pub fn run(
    self: *VectorizedBacktester,
    data: DataSet,
    strategy: IStrategy,
) !BacktestResult
```

运行完整回测流程。

**参数**:
- `data`: 输入数据集
- `strategy`: 策略实例

**返回**: 回测结果

---

## SimdIndicators

SIMD 加速的指标计算模块。

### 方法

#### computeSMA

```zig
pub fn computeSMA(
    prices: []const f64,
    period: usize,
    result: []f64,
) void
```

SIMD 加速的 SMA 计算。

#### computeEMA

```zig
pub fn computeEMA(
    prices: []const f64,
    period: usize,
    result: []f64,
) void
```

优化的 EMA 计算。

#### computeRSI

```zig
pub fn computeRSI(
    prices: []const f64,
    period: usize,
    result: []f64,
) void
```

SIMD 加速的 RSI 计算。

---

## DataSet

数据集结构。

```zig
pub const DataSet = struct {
    candles: []Candle,
    symbol: []const u8,
    timeframe: Timeframe,
    start_time: Timestamp,
    end_time: Timestamp,

    pub fn len(self: DataSet) usize;
    pub fn getClose(self: DataSet) []f64;
    pub fn getVolume(self: DataSet) []f64;
};
```

---

## BacktestResult

回测结果结构。

```zig
pub const BacktestResult = struct {
    /// 交易列表
    trades: []Trade,

    /// 最终资金
    final_capital: Decimal,

    /// 总收益率 (%)
    total_return_pct: f64,

    /// 年化收益率
    annualized_return: f64,

    /// 夏普比率
    sharpe_ratio: f64,

    /// 最大回撤 (%)
    max_drawdown_pct: f64,

    /// 胜率
    win_rate: f64,

    /// 盈亏比
    profit_factor: f64,

    /// 权益曲线
    equity_curve: []EquityPoint,
};
```

---

*Last updated: 2025-12-27*
