# Technical Indicators Library API Reference

**Version**: v0.3.0
**Update Time**: 2025-12-25

---

## Table of Contents

1. [IIndicator Interface](#iindicator-interface)
2. [SMA - Simple Moving Average](#sma---simple-moving-average)
3. [EMA - Exponential Moving Average](#ema---exponential-moving-average)
4. [RSI - Relative Strength Index](#rsi---relative-strength-index)
5. [MACD - Moving Average Convergence Divergence](#macd---moving-average-convergence-divergence)
6. [Bollinger Bands](#bollinger-bands)
7. [IndicatorManager](#indicatormanager)
8. [Error Types](#error-types)
9. [Helper Types](#helper-types)

---

## IIndicator Interface

### Overview

All technical indicators implement this unified interface based on the VTable pattern.

```zig
pub const IIndicator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Calculate indicator values
        calculate: *const fn (*anyopaque, []Candle) anyerror![]Decimal,

        /// Get indicator name
        getName: *const fn (*anyopaque) []const u8,

        /// Get required minimum number of candles
        getRequiredCandles: *const fn (*anyopaque) u32,

        /// Clean up resources
        deinit: *const fn (*anyopaque) void,
    };
};
```

### Method Details

#### calculate

Calculate indicator values from candle data.

```zig
pub fn calculate(self: IIndicator, candles: []Candle) anyerror![]Decimal
```

**Parameters**:
- `candles`: Array of OHLCV candle data

**Returns**:
- `[]Decimal`: Array of indicator values with same length as input

**Description**:
- Returns array of same length as input candles
- Early values may be NaN if insufficient data for calculation
- Caller must free the returned array
- Throws `InsufficientData` if input array too small

**Example**:
```zig
const sma = SMA.init(allocator, 20);
const indicator = sma.toInterface();
const values = try indicator.calculate(candles);
defer allocator.free(values);

// First 19 values will be NaN, rest are valid SMA values
for (values, 0..) |value, i| {
    if (!value.isNaN()) {
        std.debug.print("Candle {}: SMA = {}\n", .{ i, value });
    }
}
```

---

#### getName

Get the indicator's name identifier.

```zig
pub fn getName(self: IIndicator) []const u8
```

**Returns**:
- `[]const u8`: Indicator name (e.g., "SMA", "EMA", "RSI")

**Description**:
- Returns a static string identifier
- Used for caching and logging
- Format: uppercase abbreviation (e.g., "SMA", "MACD")

**Example**:
```zig
const indicator = sma.toInterface();
const name = indicator.getName(); // "SMA"
```

---

#### getRequiredCandles

Get the minimum number of candles needed for valid calculation.

```zig
pub fn getRequiredCandles(self: IIndicator) u32
```

**Returns**:
- `u32`: Minimum required candles

**Description**:
- Equals the period for simple indicators (SMA, EMA)
- May be larger for composite indicators (MACD)
- Used to validate data before calculation

**Example**:
```zig
const sma = SMA.init(allocator, 20);
const indicator = sma.toInterface();
const required = indicator.getRequiredCandles(); // 20

if (candles.len < required) {
    return error.InsufficientData;
}
```

---

#### deinit

Clean up indicator resources.

```zig
pub fn deinit(self: IIndicator) void
```

**Description**:
- Frees any internal allocations
- Must be called when indicator is no longer needed
- Safe to call multiple times

**Example**:
```zig
const indicator = sma.toInterface();
defer indicator.deinit();
```

---

## SMA - Simple Moving Average

### Overview

Simple Moving Average (SMA) calculates the arithmetic mean of closing prices over a specified period.

**Formula**:
```
SMA[i] = (Close[i] + Close[i-1] + ... + Close[i-period+1]) / period
```

### Definition

```zig
pub const SMA = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub fn init(allocator: std.mem.Allocator, period: u32) SMA;
    pub fn calculate(self: SMA, candles: []const Candle) ![]Decimal;
    pub fn toInterface(self: *SMA) IIndicator;
};
```

### Methods

#### init

Create a new SMA indicator instance.

```zig
pub fn init(allocator: std.mem.Allocator, period: u32) SMA
```

**Parameters**:
- `allocator`: Memory allocator for result arrays
- `period`: Number of candles in the moving average window

**Returns**:
- `SMA`: Configured SMA indicator

**Example**:
```zig
const sma = SMA.init(allocator, 20); // 20-period SMA
```

---

#### calculate

Calculate SMA values for given candles.

```zig
pub fn calculate(self: SMA, candles: []const Candle) ![]Decimal
```

**Parameters**:
- `candles`: Array of candle data

**Returns**:
- `[]Decimal`: Array of SMA values (same length as input)

**Errors**:
- `InsufficientData`: If `candles.len < period`
- `OutOfMemory`: If allocation fails

**Description**:
- First `period-1` values are set to `Decimal.NaN`
- Valid values start at index `period-1`
- Uses closing price for calculations
- Result array must be freed by caller

**Example**:
```zig
const allocator = std.heap.page_allocator;
const sma = SMA.init(allocator, 20);

const candles = try loadHistoricalData();
const values = try sma.calculate(candles);
defer allocator.free(values);

// First 19 values are NaN
std.debug.assert(values[0].isNaN());
std.debug.assert(values[18].isNaN());

// 20th value onwards are valid
std.debug.assert(!values[19].isNaN());

for (values[19..], 19..) |value, i| {
    std.debug.print("Candle {}: SMA(20) = {}\n", .{ i, value });
}
```

---

#### toInterface

Convert to generic IIndicator interface.

```zig
pub fn toInterface(self: *SMA) IIndicator
```

**Returns**:
- `IIndicator`: Generic indicator interface

**Example**:
```zig
var sma = SMA.init(allocator, 20);
const indicator = sma.toInterface();
const values = try indicator.calculate(candles);
```

---

### Use Cases

**Trend Identification**:
- Price above SMA: Uptrend
- Price below SMA: Downtrend

**Support/Resistance**:
- SMA acts as dynamic support in uptrends
- SMA acts as dynamic resistance in downtrends

**Crossover Strategies**:
- Golden Cross: Fast SMA crosses above slow SMA (bullish)
- Death Cross: Fast SMA crosses below slow SMA (bearish)

**Common Periods**:
- 20-day: Short-term trend
- 50-day: Medium-term trend
- 200-day: Long-term trend

---

## EMA - Exponential Moving Average

### Overview

Exponential Moving Average (EMA) gives more weight to recent prices, making it more responsive to price changes than SMA.

**Formula**:
```
α = 2 / (period + 1)
EMA[0] = Close[0]
EMA[t] = α × Close[t] + (1 - α) × EMA[t-1]
```

### Definition

```zig
pub const EMA = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub fn init(allocator: std.mem.Allocator, period: u32) EMA;
    pub fn calculate(self: EMA, candles: []const Candle) ![]Decimal;
    pub fn toInterface(self: *EMA) IIndicator;
};
```

### Methods

#### init

Create a new EMA indicator instance.

```zig
pub fn init(allocator: std.mem.Allocator, period: u32) EMA
```

**Parameters**:
- `allocator`: Memory allocator for result arrays
- `period`: Number of periods for smoothing constant calculation

**Returns**:
- `EMA`: Configured EMA indicator

**Example**:
```zig
const ema = EMA.init(allocator, 12); // 12-period EMA
```

---

#### calculate

Calculate EMA values for given candles.

```zig
pub fn calculate(self: EMA, candles: []const Candle) ![]Decimal
```

**Parameters**:
- `candles`: Array of candle data

**Returns**:
- `[]Decimal`: Array of EMA values (same length as input)

**Errors**:
- `InsufficientData`: If `candles.len < 1`
- `OutOfMemory`: If allocation fails

**Description**:
- First value equals first closing price
- Each subsequent value uses exponential smoothing formula
- More responsive to recent price changes than SMA
- No NaN values (all values are valid)
- Result array must be freed by caller

**Example**:
```zig
const allocator = std.heap.page_allocator;
const ema = EMA.init(allocator, 12);

const candles = try loadHistoricalData();
const values = try ema.calculate(candles);
defer allocator.free(values);

// All values are valid (no NaN)
std.debug.assert(!values[0].isNaN());

// EMA is more responsive than SMA
for (values, 0..) |value, i| {
    std.debug.print("Candle {}: EMA(12) = {}\n", .{ i, value });
}
```

---

### Use Cases

**Trend Following**:
- Price above EMA: Bullish trend
- Price below EMA: Bearish trend

**MACD Indicator**:
- MACD uses EMA(12) and EMA(26)
- Signal line is EMA(9) of MACD line

**Crossover Systems**:
- EMA(12) and EMA(26) crossovers
- More responsive than SMA crossovers

**Common Periods**:
- 12-day: Fast EMA (MACD)
- 26-day: Slow EMA (MACD)
- 9-day: Signal line
- 200-day: Long-term trend

---

## RSI - Relative Strength Index

### Overview

Relative Strength Index (RSI) is a momentum oscillator that measures the speed and magnitude of price changes. Values range from 0 to 100.

**Formula**:
```
RS = Average Gain / Average Loss
RSI = 100 - (100 / (1 + RS))
```

**Interpretation**:
- RSI > 70: Overbought
- RSI < 30: Oversold
- RSI = 50: Neutral

### Definition

```zig
pub const RSI = struct {
    allocator: std.mem.Allocator,
    period: u32,

    pub fn init(allocator: std.mem.Allocator, period: u32) RSI;
    pub fn calculate(self: RSI, candles: []const Candle) ![]Decimal;
    pub fn toInterface(self: *RSI) IIndicator;
};
```

### Methods

#### init

Create a new RSI indicator instance.

```zig
pub fn init(allocator: std.mem.Allocator, period: u32) RSI
```

**Parameters**:
- `allocator`: Memory allocator for result arrays
- `period`: Lookback period for calculating average gains/losses

**Returns**:
- `RSI`: Configured RSI indicator

**Example**:
```zig
const rsi = RSI.init(allocator, 14); // Standard 14-period RSI
```

---

#### calculate

Calculate RSI values for given candles.

```zig
pub fn calculate(self: RSI, candles: []const Candle) ![]Decimal
```

**Parameters**:
- `candles`: Array of candle data

**Returns**:
- `[]Decimal`: Array of RSI values in range [0, 100]

**Errors**:
- `InsufficientData`: If `candles.len < period + 1`
- `OutOfMemory`: If allocation fails

**Description**:
- First `period` values are set to `Decimal.NaN`
- Valid values start at index `period`
- Values range from 0 to 100
- Uses Wilder's smoothing (EMA-based)
- Result array must be freed by caller

**Example**:
```zig
const allocator = std.heap.page_allocator;
const rsi = RSI.init(allocator, 14);

const candles = try loadHistoricalData();
const values = try rsi.calculate(candles);
defer allocator.free(values);

// First 14 values are NaN
for (values[0..14]) |value| {
    std.debug.assert(value.isNaN());
}

// Check for overbought/oversold conditions
for (values[14..], 14..) |value, i| {
    if (value.gte(try Decimal.fromFloat(70.0))) {
        std.debug.print("Candle {}: OVERBOUGHT (RSI = {})\n", .{ i, value });
    } else if (value.lte(try Decimal.fromFloat(30.0))) {
        std.debug.print("Candle {}: OVERSOLD (RSI = {})\n", .{ i, value });
    }
}
```

---

### Use Cases

**Overbought/Oversold Detection**:
- RSI > 70: Consider selling (overbought)
- RSI < 30: Consider buying (oversold)

**Divergence Trading**:
- Bullish Divergence: Price makes lower low, RSI makes higher low
- Bearish Divergence: Price makes higher high, RSI makes lower high

**Trend Confirmation**:
- Uptrend: RSI stays above 40-50
- Downtrend: RSI stays below 50-60

**Failure Swings**:
- Top Failure Swing: Bearish reversal pattern
- Bottom Failure Swing: Bullish reversal pattern

**Common Periods**:
- 14-day: Standard period (Wilder's original)
- 9-day: More sensitive to price changes
- 25-day: Less sensitive, fewer signals

---

## MACD - Moving Average Convergence Divergence

### Overview

MACD is a trend-following momentum indicator that shows the relationship between two exponential moving averages.

**Components**:
1. **MACD Line**: EMA(12) - EMA(26)
2. **Signal Line**: EMA(9) of MACD Line
3. **Histogram**: MACD Line - Signal Line

### Definition

```zig
pub const MACD = struct {
    allocator: std.mem.Allocator,
    fast_period: u32 = 12,
    slow_period: u32 = 26,
    signal_period: u32 = 9,

    pub const MACDResult = struct {
        macd_line: []Decimal,
        signal_line: []Decimal,
        histogram: []Decimal,

        pub fn deinit(self: *MACDResult, allocator: std.mem.Allocator) void;
    };

    pub fn init(allocator: std.mem.Allocator) MACD;
    pub fn initCustom(
        allocator: std.mem.Allocator,
        fast_period: u32,
        slow_period: u32,
        signal_period: u32
    ) MACD;
    pub fn calculate(self: MACD, candles: []const Candle) !MACDResult;
};
```

### Methods

#### init

Create a new MACD indicator with standard parameters (12, 26, 9).

```zig
pub fn init(allocator: std.mem.Allocator) MACD
```

**Parameters**:
- `allocator`: Memory allocator for result arrays

**Returns**:
- `MACD`: MACD indicator with default periods

**Example**:
```zig
const macd = MACD.init(allocator); // MACD(12, 26, 9)
```

---

#### initCustom

Create a new MACD indicator with custom parameters.

```zig
pub fn initCustom(
    allocator: std.mem.Allocator,
    fast_period: u32,
    slow_period: u32,
    signal_period: u32
) MACD
```

**Parameters**:
- `allocator`: Memory allocator for result arrays
- `fast_period`: Fast EMA period (typically 12)
- `slow_period`: Slow EMA period (typically 26)
- `signal_period`: Signal line EMA period (typically 9)

**Returns**:
- `MACD`: MACD indicator with custom periods

**Example**:
```zig
const macd = MACD.initCustom(allocator, 8, 17, 9); // Custom MACD
```

---

#### calculate

Calculate MACD components for given candles.

```zig
pub fn calculate(self: MACD, candles: []const Candle) !MACDResult
```

**Parameters**:
- `candles`: Array of candle data

**Returns**:
- `MACDResult`: Struct containing MACD line, signal line, and histogram

**Errors**:
- `InsufficientData`: If `candles.len < slow_period + signal_period`
- `OutOfMemory`: If allocation fails

**Description**:
- Returns three aligned arrays of same length as input
- Early values may be NaN if insufficient data
- All three arrays must be freed via `MACDResult.deinit()`

**Example**:
```zig
const allocator = std.heap.page_allocator;
const macd = MACD.init(allocator);

const candles = try loadHistoricalData();
var result = try macd.calculate(candles);
defer result.deinit(allocator);

// Check for crossovers
for (result.macd_line, 0..) |macd_value, i| {
    if (i == 0) continue;

    const prev_macd = result.macd_line[i - 1];
    const prev_signal = result.signal_line[i - 1];
    const curr_macd = macd_value;
    const curr_signal = result.signal_line[i];

    // Bullish crossover: MACD crosses above signal
    if (prev_macd.lte(prev_signal) and curr_macd.gt(curr_signal)) {
        std.debug.print("Candle {}: BULLISH CROSSOVER\n", .{i});
    }

    // Bearish crossover: MACD crosses below signal
    if (prev_macd.gte(prev_signal) and curr_macd.lt(curr_signal)) {
        std.debug.print("Candle {}: BEARISH CROSSOVER\n", .{i});
    }

    // Histogram analysis
    if (!result.histogram[i].isNaN()) {
        std.debug.print("Candle {}: Histogram = {}\n", .{ i, result.histogram[i] });
    }
}
```

---

### MACDResult

#### deinit

Free all arrays in the MACD result.

```zig
pub fn deinit(self: *MACDResult, allocator: std.mem.Allocator) void
```

**Parameters**:
- `allocator`: Same allocator used to create the result

**Example**:
```zig
var result = try macd.calculate(candles);
defer result.deinit(allocator);
```

---

### Use Cases

**Signal Line Crossovers**:
- MACD crosses above signal: Bullish signal (buy)
- MACD crosses below signal: Bearish signal (sell)

**Zero Line Crossovers**:
- MACD crosses above zero: Bullish momentum
- MACD crosses below zero: Bearish momentum

**Histogram Analysis**:
- Positive histogram: Bullish momentum
- Negative histogram: Bearish momentum
- Histogram divergence: Potential reversal

**Divergence Trading**:
- Bullish Divergence: Price lower low, MACD higher low
- Bearish Divergence: Price higher high, MACD lower high

**Common Variations**:
- Standard: MACD(12, 26, 9)
- Fast: MACD(8, 17, 9)
- Slow: MACD(5, 35, 5)

---

## Bollinger Bands

### Overview

Bollinger Bands consist of a middle band (SMA) and two outer bands placed at standard deviations above and below the middle band. They measure volatility and potential overbought/oversold conditions.

**Components**:
1. **Middle Band**: SMA(period)
2. **Upper Band**: Middle Band + (std_dev × Standard Deviation)
3. **Lower Band**: Middle Band - (std_dev × Standard Deviation)

### Definition

```zig
pub const BollingerBands = struct {
    allocator: std.mem.Allocator,
    period: u32 = 20,
    std_dev: f64 = 2.0,

    pub const BBResult = struct {
        upper: []Decimal,
        middle: []Decimal,
        lower: []Decimal,

        pub fn deinit(self: *BBResult, allocator: std.mem.Allocator) void;
    };

    pub fn init(allocator: std.mem.Allocator) BollingerBands;
    pub fn initCustom(
        allocator: std.mem.Allocator,
        period: u32,
        std_dev: f64
    ) BollingerBands;
    pub fn calculate(self: BollingerBands, candles: []const Candle) !BBResult;
};
```

### Methods

#### init

Create Bollinger Bands with standard parameters (20, 2.0).

```zig
pub fn init(allocator: std.mem.Allocator) BollingerBands
```

**Parameters**:
- `allocator`: Memory allocator for result arrays

**Returns**:
- `BollingerBands`: Indicator with default parameters

**Example**:
```zig
const bb = BollingerBands.init(allocator); // BB(20, 2.0)
```

---

#### initCustom

Create Bollinger Bands with custom parameters.

```zig
pub fn initCustom(
    allocator: std.mem.Allocator,
    period: u32,
    std_dev: f64
) BollingerBands
```

**Parameters**:
- `allocator`: Memory allocator for result arrays
- `period`: SMA period for middle band
- `std_dev`: Standard deviation multiplier for outer bands

**Returns**:
- `BollingerBands`: Indicator with custom parameters

**Example**:
```zig
const bb = BollingerBands.initCustom(allocator, 20, 2.5); // Wider bands
```

---

#### calculate

Calculate Bollinger Bands for given candles.

```zig
pub fn calculate(self: BollingerBands, candles: []const Candle) !BBResult
```

**Parameters**:
- `candles`: Array of candle data

**Returns**:
- `BBResult`: Struct containing upper, middle, and lower bands

**Errors**:
- `InsufficientData`: If `candles.len < period`
- `OutOfMemory`: If allocation fails

**Description**:
- Returns three aligned arrays of same length as input
- First `period-1` values are NaN
- All three arrays must be freed via `BBResult.deinit()`

**Example**:
```zig
const allocator = std.heap.page_allocator;
const bb = BollingerBands.init(allocator);

const candles = try loadHistoricalData();
var result = try bb.calculate(candles);
defer result.deinit(allocator);

// Check for price touching bands
for (candles, 0..) |candle, i| {
    if (result.upper[i].isNaN()) continue;

    const close = candle.close;
    const upper = result.upper[i];
    const middle = result.middle[i];
    const lower = result.lower[i];

    // Price at upper band: potential overbought
    if (close.gte(upper)) {
        std.debug.print("Candle {}: PRICE AT UPPER BAND\n", .{i});
    }

    // Price at lower band: potential oversold
    if (close.lte(lower)) {
        std.debug.print("Candle {}: PRICE AT LOWER BAND\n", .{i});
    }

    // Calculate bandwidth (volatility measure)
    const bandwidth = try upper.sub(lower).div(middle);
    std.debug.print("Candle {}: Bandwidth = {}\n", .{ i, bandwidth });
}
```

---

### BBResult

#### deinit

Free all arrays in the Bollinger Bands result.

```zig
pub fn deinit(self: *BBResult, allocator: std.mem.Allocator) void
```

**Parameters**:
- `allocator`: Same allocator used to create the result

**Example**:
```zig
var result = try bb.calculate(candles);
defer result.deinit(allocator);
```

---

### Use Cases

**Overbought/Oversold**:
- Price at upper band: Potential overbought
- Price at lower band: Potential oversold

**Volatility Analysis**:
- Narrow bands: Low volatility (squeeze)
- Wide bands: High volatility (expansion)
- Band squeeze often precedes breakout

**Breakout Trading**:
- Price breaks above upper band: Strong bullish momentum
- Price breaks below lower band: Strong bearish momentum

**Mean Reversion**:
- Buy when price touches lower band
- Sell when price touches upper band

**Bollinger Squeeze**:
- Bandwidth at historic lows
- Indicates consolidation
- Often followed by significant move

**Common Variations**:
- Standard: BB(20, 2.0)
- Tight: BB(20, 1.5) - More sensitive
- Wide: BB(20, 2.5) - Less sensitive
- Short-term: BB(10, 2.0)

---

## IndicatorManager

### Overview

IndicatorManager provides caching and lifecycle management for technical indicators, avoiding redundant calculations and managing memory efficiently.

### Definition

```zig
pub const IndicatorManager = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap([]Decimal),
    logger: Logger,

    pub fn init(allocator: std.mem.Allocator, logger: Logger) IndicatorManager;
    pub fn deinit(self: *IndicatorManager) void;
    pub fn getIndicator(
        self: *IndicatorManager,
        name: []const u8,
        candles: []Candle,
        calculate_fn: fn ([]Candle) anyerror![]Decimal
    ) ![]Decimal;
    pub fn clearCache(self: *IndicatorManager) void;
    pub fn removeIndicator(self: *IndicatorManager, name: []const u8) void;
};
```

### Methods

#### init

Create a new IndicatorManager instance.

```zig
pub fn init(allocator: std.mem.Allocator, logger: Logger) IndicatorManager
```

**Parameters**:
- `allocator`: Memory allocator for cache storage
- `logger`: Logger for debugging and monitoring

**Returns**:
- `IndicatorManager`: Initialized manager

**Example**:
```zig
var manager = IndicatorManager.init(allocator, logger);
defer manager.deinit();
```

---

#### deinit

Clean up all cached indicators and free memory.

```zig
pub fn deinit(self: *IndicatorManager) void
```

**Description**:
- Frees all cached indicator arrays
- Clears the internal hash map
- Must be called before manager goes out of scope

**Example**:
```zig
var manager = IndicatorManager.init(allocator, logger);
defer manager.deinit();
```

---

#### getIndicator

Get indicator values with automatic caching.

```zig
pub fn getIndicator(
    self: *IndicatorManager,
    name: []const u8,
    candles: []Candle,
    calculate_fn: fn ([]Candle) anyerror![]Decimal
) ![]Decimal
```

**Parameters**:
- `name`: Unique identifier for this indicator (e.g., "sma_20", "rsi_14")
- `candles`: Candle data for calculation
- `calculate_fn`: Function to calculate indicator if not cached

**Returns**:
- `[]Decimal`: Indicator values (from cache or newly calculated)

**Errors**:
- `OutOfMemory`: If allocation fails
- Any error from `calculate_fn`

**Description**:
- First call calculates and caches the result
- Subsequent calls return cached result
- Cache key is the `name` parameter
- Cached arrays are freed by `deinit()` or `clearCache()`

**Example**:
```zig
var manager = IndicatorManager.init(allocator, logger);
defer manager.deinit();

const candles = try loadHistoricalData();

// First call calculates SMA
const sma1 = try manager.getIndicator("sma_20", candles, struct {
    fn calc(c: []Candle) ![]Decimal {
        return SMA.init(allocator, 20).calculate(c);
    }
}.calc);

// Second call returns cached result (no calculation)
const sma2 = try manager.getIndicator("sma_20", candles, struct {
    fn calc(c: []Candle) ![]Decimal {
        return SMA.init(allocator, 20).calculate(c);
    }
}.calc);

std.debug.assert(sma1.ptr == sma2.ptr); // Same array pointer
```

---

#### clearCache

Clear all cached indicators.

```zig
pub fn clearCache(self: *IndicatorManager) void
```

**Description**:
- Frees all cached indicator arrays
- Clears the cache map
- Next `getIndicator` calls will recalculate

**Use Cases**:
- New candle received in live trading
- Switching to different timeframe
- Memory optimization

**Example**:
```zig
// Use indicators with current candles
const sma = try manager.getIndicator("sma_20", candles, calculate_sma);

// New candle arrives
manager.clearCache();

// Next call will recalculate with updated candles
const new_sma = try manager.getIndicator("sma_20", updated_candles, calculate_sma);
```

---

#### removeIndicator

Remove a specific indicator from cache.

```zig
pub fn removeIndicator(self: *IndicatorManager, name: []const u8) void
```

**Parameters**:
- `name`: Identifier of indicator to remove

**Description**:
- Frees the array for specified indicator
- Removes entry from cache map
- No-op if indicator not in cache

**Example**:
```zig
// Cache multiple indicators
try manager.getIndicator("sma_20", candles, calc_sma);
try manager.getIndicator("ema_12", candles, calc_ema);
try manager.getIndicator("rsi_14", candles, calc_rsi);

// Remove only SMA
manager.removeIndicator("sma_20");

// SMA is recalculated, EMA and RSI are cached
const sma = try manager.getIndicator("sma_20", candles, calc_sma);
const ema = try manager.getIndicator("ema_12", candles, calc_ema); // From cache
```

---

### Usage in Strategies

```zig
fn populateIndicatorsImpl(ptr: *anyopaque, candles: *Candles) !void {
    const self: *MyStrategy = @ptrCast(@alignCast(ptr));

    // Use IndicatorManager from context
    const manager = self.ctx.indicator_manager;

    // Get SMA with caching
    const sma_20 = try manager.getIndicator("sma_20", candles.data, struct {
        fn calc(c: []Candle) ![]Decimal {
            return SMA.init(self.allocator, 20).calculate(c);
        }
    }.calc);
    try candles.addIndicator("sma_20", sma_20);

    // Get RSI with caching
    const rsi_14 = try manager.getIndicator("rsi_14", candles.data, struct {
        fn calc(c: []Candle) ![]Decimal {
            return RSI.init(self.allocator, 14).calculate(c);
        }
    }.calc);
    try candles.addIndicator("rsi_14", rsi_14);

    // MACD requires special handling (multiple arrays)
    const macd = MACD.init(self.allocator);
    var macd_result = try macd.calculate(candles.data);
    // Note: MACD arrays are owned by strategy, not manager
    try candles.addIndicator("macd_line", macd_result.macd_line);
    try candles.addIndicator("signal_line", macd_result.signal_line);
    try candles.addIndicator("histogram", macd_result.histogram);
}
```

---

## Error Types

### IndicatorError

```zig
pub const IndicatorError = error{
    /// Input data has fewer candles than required
    InsufficientData,

    /// Invalid parameter value (e.g., period = 0)
    InvalidParameter,

    /// Calculation produced invalid result (NaN, Inf)
    CalculationFailed,

    /// Memory allocation failed
    OutOfMemory,

    /// Indicator not found in cache
    IndicatorNotFound,

    /// Division by zero during calculation
    DivisionByZero,
};
```

### Error Handling Examples

```zig
// Handle insufficient data
const sma = SMA.init(allocator, 20);
const values = sma.calculate(candles) catch |err| switch (err) {
    error.InsufficientData => {
        std.debug.print("Need at least 20 candles, got {}\n", .{candles.len});
        return error.InsufficientData;
    },
    error.OutOfMemory => {
        std.debug.print("Failed to allocate memory\n", .{});
        return error.OutOfMemory;
    },
    else => return err,
};

// Validate parameters
pub fn init(allocator: std.mem.Allocator, period: u32) !SMA {
    if (period == 0) {
        return error.InvalidParameter;
    }
    return SMA{
        .allocator = allocator,
        .period = period,
    };
}

// Check for calculation errors
const result = try calculation;
if (result.isNaN() or result.isInf()) {
    return error.CalculationFailed;
}
```

---

## Helper Types

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

**Description**:
- OHLCV (Open, High, Low, Close, Volume) candlestick data
- `timestamp`: Unix timestamp in milliseconds
- Price fields use `Decimal` for precision
- Volume represents trading volume in base asset

---

### Candles

```zig
pub const Candles = struct {
    allocator: std.mem.Allocator,
    data: []Candle,
    indicators: std.StringHashMap([]Decimal),

    pub fn init(allocator: std.mem.Allocator, data: []Candle) Candles;
    pub fn deinit(self: *Candles) void;
    pub fn addIndicator(self: *Candles, name: []const u8, values: []Decimal) !void;
    pub fn getIndicator(self: *Candles, name: []const u8) ?[]Decimal;
    pub fn removeIndicator(self: *Candles, name: []const u8) void;
};
```

**Description**:
- Container for candle data and associated indicators
- Indicators stored in hash map by name
- Used in strategy `populateIndicators()` method

**Example**:
```zig
var candles = Candles.init(allocator, candle_data);
defer candles.deinit();

// Add indicators
const sma = try SMA.init(allocator, 20).calculate(candles.data);
try candles.addIndicator("sma_20", sma);

// Retrieve indicators
const sma_values = candles.getIndicator("sma_20") orelse return error.IndicatorNotFound;
```

---

### Decimal

```zig
// Decimal type from core library - arbitrary precision decimal
pub const Decimal = @import("decimal").Decimal;

// Common constants
pub const ZERO = Decimal.ZERO;
pub const ONE = Decimal.ONE;
pub const NaN = Decimal.NaN;

// Common operations
pub fn fromFloat(value: f64) !Decimal;
pub fn fromInt(value: i64) !Decimal;
pub fn add(self: Decimal, other: Decimal) !Decimal;
pub fn sub(self: Decimal, other: Decimal) !Decimal;
pub fn mul(self: Decimal, other: Decimal) !Decimal;
pub fn div(self: Decimal, other: Decimal) !Decimal;
pub fn abs(self: Decimal) !Decimal;
pub fn isNaN(self: Decimal) bool;
pub fn isInf(self: Decimal) bool;
pub fn isPositive(self: Decimal) bool;
pub fn gt(self: Decimal, other: Decimal) bool;
pub fn gte(self: Decimal, other: Decimal) bool;
pub fn lt(self: Decimal, other: Decimal) bool;
pub fn lte(self: Decimal, other: Decimal) bool;
```

**Description**:
- Arbitrary precision decimal type
- Avoids floating-point rounding errors
- Used for all price and indicator calculations

---

### Timestamp

```zig
pub const Timestamp = i64; // Unix timestamp in milliseconds
```

**Description**:
- Unix timestamp in milliseconds
- Compatible with most exchange APIs
- Signed integer for historical flexibility

---

## Performance Considerations

### Memory Management

**Indicator Calculation**:
```zig
// GOOD: Caller manages memory
const sma = SMA.init(allocator, 20);
const values = try sma.calculate(candles);
defer allocator.free(values); // Explicit cleanup

// BETTER: Use IndicatorManager for automatic cleanup
const values = try manager.getIndicator("sma_20", candles, calc_fn);
// Manager handles cleanup
```

**Composite Indicators**:
```zig
// MACD returns struct with multiple arrays
var result = try macd.calculate(candles);
defer result.deinit(allocator); // Frees all three arrays

// Individual array access
const macd_line = result.macd_line;
const signal_line = result.signal_line;
const histogram = result.histogram;
```

### Optimization Tips

1. **Use IndicatorManager**: Avoid recalculating indicators
2. **Batch Processing**: Calculate all indicators once in `populateIndicators()`
3. **Minimal Periods**: Use smallest period that meets strategy needs
4. **Reuse Allocators**: Arena allocator for batch operations
5. **Pre-allocation**: Allocate result arrays upfront when size known

### Benchmark Guidelines

**Target Performance**:
- SMA/EMA: < 1ms for 1000 candles
- RSI: < 2ms for 1000 candles
- MACD: < 3ms for 1000 candles
- Bollinger Bands: < 2ms for 1000 candles

**Memory Usage**:
- Each indicator: ~8KB per 1000 candles (f64 values)
- With caching: Linear growth with number of indicators
- Without caching: Constant memory per calculation

---

## Complete Usage Example

```zig
const std = @import("std");
const indicators = @import("indicators");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load historical data
    const candles = try loadHistoricalData(allocator);
    defer allocator.free(candles);

    // Initialize indicator manager
    var manager = indicators.IndicatorManager.init(allocator, logger);
    defer manager.deinit();

    // Calculate SMA
    const sma_20 = try manager.getIndicator("sma_20", candles, struct {
        fn calc(c: []indicators.Candle) ![]indicators.Decimal {
            return indicators.SMA.init(allocator, 20).calculate(c);
        }
    }.calc);

    // Calculate RSI
    const rsi_14 = try manager.getIndicator("rsi_14", candles, struct {
        fn calc(c: []indicators.Candle) ![]indicators.Decimal {
            return indicators.RSI.init(allocator, 14).calculate(c);
        }
    }.calc);

    // Calculate MACD (not cached due to multiple arrays)
    const macd = indicators.MACD.init(allocator);
    var macd_result = try macd.calculate(candles);
    defer macd_result.deinit(allocator);

    // Calculate Bollinger Bands
    const bb = indicators.BollingerBands.init(allocator);
    var bb_result = try bb.calculate(candles);
    defer bb_result.deinit(allocator);

    // Analyze latest candle
    const idx = candles.len - 1;
    const current_price = candles[idx].close;

    std.debug.print("=== Latest Candle Analysis ===\n", .{});
    std.debug.print("Price: {}\n", .{current_price});
    std.debug.print("SMA(20): {}\n", .{sma_20[idx]});
    std.debug.print("RSI(14): {}\n", .{rsi_14[idx]});
    std.debug.print("MACD: {}\n", .{macd_result.macd_line[idx]});
    std.debug.print("Signal: {}\n", .{macd_result.signal_line[idx]});
    std.debug.print("BB Upper: {}\n", .{bb_result.upper[idx]});
    std.debug.print("BB Middle: {}\n", .{bb_result.middle[idx]});
    std.debug.print("BB Lower: {}\n", .{bb_result.lower[idx]});

    // Generate trading signal
    if (rsi_14[idx].lt(try indicators.Decimal.fromFloat(30.0)) and
        current_price.lte(bb_result.lower[idx]))
    {
        std.debug.print("\n🟢 BUY SIGNAL: Oversold + at lower BB\n", .{});
    } else if (rsi_14[idx].gt(try indicators.Decimal.fromFloat(70.0)) and
        current_price.gte(bb_result.upper[idx]))
    {
        std.debug.print("\n🔴 SELL SIGNAL: Overbought + at upper BB\n", .{});
    }
}
```

---

**Version**: v0.3.0
**Status**: Design Phase
**Last Updated**: 2025-12-25
