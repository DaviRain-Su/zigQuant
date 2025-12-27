# Story 028: 向量化回测引擎

**版本**: v0.6.0
**状态**: 规划中
**优先级**: P0
**预计时间**: 5-7 天
**前置条件**: v0.5.0 完成

---

## 目标

实现高性能向量化回测引擎，利用 SIMD 指令和内存映射技术，达到 100,000+ bars/s 的回测速度，为大规模参数优化和策略研究提供基础。

---

## 背景

### 当前回测性能

v0.3.0/v0.4.0 的回测引擎基于事件驱动：
- 逐 bar 处理
- 每个 bar 触发指标计算
- 性能约 ~10,000 bars/s

### 向量化优势

借鉴 Freqtrade 的向量化设计：
- 批量计算所有 bars 的指标
- 利用 CPU SIMD 指令 (AVX2/AVX-512)
- 减少函数调用开销
- 更好的 CPU 缓存利用

---

## 核心设计

### 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                  VectorizedBacktester                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  DataLoader │  │ Indicators  │  │  Signals    │         │
│  │   (mmap)    │  │   (SIMD)    │  │  (Batch)    │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         ↓                ↓                ↓                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Candle[] → Indicator[] → Signal[]       │   │
│  │                    (批量处理管道)                     │   │
│  └─────────────────────────────────────────────────────┘   │
│         ↓                                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              OrderSimulator (批量订单模拟)            │   │
│  └─────────────────────────────────────────────────────┘   │
│         ↓                                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              PerformanceAnalyzer (结果分析)          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 核心接口

```zig
pub const VectorizedBacktester = struct {
    allocator: Allocator,
    config: Config,

    pub const Config = struct {
        initial_capital: Decimal,
        commission_rate: Decimal,
        slippage: Decimal,
        use_simd: bool = true,
        chunk_size: usize = 1024,  // SIMD 批处理大小
    };

    /// 初始化
    pub fn init(allocator: Allocator, config: Config) VectorizedBacktester;

    /// 加载数据 (内存映射)
    pub fn loadData(self: *VectorizedBacktester, path: []const u8) !DataSet;

    /// 批量计算指标
    pub fn computeIndicators(
        self: *VectorizedBacktester,
        data: DataSet,
        indicator_config: IndicatorConfig,
    ) !IndicatorResults;

    /// 批量生成信号
    pub fn generateSignals(
        self: *VectorizedBacktester,
        indicators: IndicatorResults,
        strategy: IStrategy,
    ) ![]Signal;

    /// 模拟执行
    pub fn simulate(
        self: *VectorizedBacktester,
        data: DataSet,
        signals: []Signal,
    ) !BacktestResult;

    /// 完整回测流程
    pub fn run(
        self: *VectorizedBacktester,
        data_path: []const u8,
        strategy: IStrategy,
    ) !BacktestResult;
};
```

---

## 实现细节

### 1. 内存映射数据加载

```zig
pub const MmapDataLoader = struct {
    /// 使用 mmap 加载大型 CSV 文件
    pub fn loadCsv(path: []const u8) !DataSet {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const mapped = try std.os.mmap(
            null,
            stat.size,
            std.os.PROT.READ,
            std.os.MAP.PRIVATE,
            file.handle,
            0,
        );

        // 解析 CSV 到 Candle 数组
        return parseCandles(mapped);
    }
};
```

### 2. SIMD 指标计算

```zig
pub const SimdIndicators = struct {
    /// SIMD 加速 SMA 计算
    pub fn computeSMA(prices: []const f64, period: usize, result: []f64) void {
        const Vec4 = @Vector(4, f64);

        var i: usize = period - 1;
        while (i + 4 <= prices.len) : (i += 4) {
            // 批量计算 4 个 SMA 值
            var sums: Vec4 = @splat(0.0);
            var j: usize = 0;
            while (j < period) : (j += 1) {
                const idx = i - period + 1 + j;
                sums += Vec4{
                    prices[idx],
                    prices[idx + 1],
                    prices[idx + 2],
                    prices[idx + 3],
                };
            }
            const avg = sums / @as(Vec4, @splat(@floatFromInt(period)));
            result[i..][0..4].* = avg;
        }
    }

    /// SIMD 加速 EMA 计算
    pub fn computeEMA(prices: []const f64, period: usize, result: []f64) void {
        const multiplier = 2.0 / @as(f64, @floatFromInt(period + 1));

        // EMA 有数据依赖，使用标量循环但优化内存访问
        result[0] = prices[0];
        for (1..prices.len) |i| {
            result[i] = (prices[i] - result[i - 1]) * multiplier + result[i - 1];
        }
    }

    /// SIMD 加速 RSI 计算
    pub fn computeRSI(prices: []const f64, period: usize, result: []f64) void {
        const Vec4 = @Vector(4, f64);

        // 1. 计算价格变化
        var changes = allocator.alloc(f64, prices.len - 1);
        defer allocator.free(changes);

        var i: usize = 0;
        while (i + 4 <= changes.len) : (i += 4) {
            const curr: Vec4 = prices[i + 1 ..][0..4].*;
            const prev: Vec4 = prices[i..][0..4].*;
            const diff = curr - prev;
            changes[i..][0..4].* = diff;
        }

        // 2. 分离涨跌
        // 3. 计算平均涨跌幅
        // 4. 计算 RSI
    }
};
```

### 3. 批量信号生成

```zig
pub const BatchSignalGenerator = struct {
    /// 批量生成交叉信号
    pub fn generateCrossSignals(
        fast_ma: []const f64,
        slow_ma: []const f64,
        result: []Signal,
    ) void {
        // 上一个状态: fast > slow ?
        var prev_above = fast_ma[0] > slow_ma[0];

        for (1..fast_ma.len) |i| {
            const curr_above = fast_ma[i] > slow_ma[i];

            if (curr_above and !prev_above) {
                // 金叉 - 买入信号
                result[i] = .{ .direction = .long, .strength = 1.0 };
            } else if (!curr_above and prev_above) {
                // 死叉 - 卖出信号
                result[i] = .{ .direction = .short, .strength = 1.0 };
            } else {
                result[i] = .{ .direction = .neutral, .strength = 0.0 };
            }

            prev_above = curr_above;
        }
    }

    /// 批量生成 RSI 信号
    pub fn generateRSISignals(
        rsi: []const f64,
        oversold: f64,
        overbought: f64,
        result: []Signal,
    ) void {
        for (rsi, 0..) |r, i| {
            if (r < oversold) {
                result[i] = .{ .direction = .long, .strength = (oversold - r) / oversold };
            } else if (r > overbought) {
                result[i] = .{ .direction = .short, .strength = (r - overbought) / (100 - overbought) };
            } else {
                result[i] = .{ .direction = .neutral, .strength = 0.0 };
            }
        }
    }
};
```

### 4. 批量订单模拟

```zig
pub const BatchOrderSimulator = struct {
    config: Config,

    pub const Config = struct {
        initial_capital: f64,
        commission_rate: f64,
        slippage: f64,
    };

    /// 批量模拟订单执行
    pub fn simulate(
        self: *BatchOrderSimulator,
        candles: []const Candle,
        signals: []const Signal,
    ) SimulationResult {
        var capital = self.config.initial_capital;
        var position: f64 = 0;
        var trades = std.ArrayList(Trade).init(allocator);

        for (candles, signals, 0..) |candle, signal, i| {
            switch (signal.direction) {
                .long => {
                    if (position <= 0) {
                        // 开多仓
                        const price = candle.close * (1 + self.config.slippage);
                        const size = capital / price;
                        position = size;
                        capital = 0;
                        try trades.append(.{
                            .entry_index = i,
                            .entry_price = price,
                            .side = .buy,
                        });
                    }
                },
                .short => {
                    if (position > 0) {
                        // 平多仓
                        const price = candle.close * (1 - self.config.slippage);
                        capital = position * price * (1 - self.config.commission_rate);
                        position = 0;
                        trades.items[trades.items.len - 1].exit_index = i;
                        trades.items[trades.items.len - 1].exit_price = price;
                    }
                },
                .neutral => {},
            }
        }

        return .{
            .trades = trades.toOwnedSlice(),
            .final_capital = capital + position * candles[candles.len - 1].close,
        };
    }
};
```

---

## 测试计划

### 单元测试

```zig
test "SIMD SMA matches scalar SMA" {
    const prices = [_]f64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var simd_result: [10]f64 = undefined;
    var scalar_result: [10]f64 = undefined;

    SimdIndicators.computeSMA(&prices, 3, &simd_result);
    ScalarIndicators.computeSMA(&prices, 3, &scalar_result);

    for (simd_result, scalar_result) |s, r| {
        try std.testing.expectApproxEqAbs(s, r, 1e-10);
    }
}

test "vectorized backtest matches event-driven" {
    // 使用相同数据和策略比较结果
}
```

### 性能测试

```zig
test "benchmark: 100k bars backtest" {
    const data = generateTestData(100_000);
    var timer = std.time.Timer{};

    timer.start();
    const result = backtester.run(data, strategy);
    const elapsed = timer.read();

    // 目标: < 1 秒 (100k bars/s)
    try std.testing.expect(elapsed < std.time.ns_per_s);
}
```

---

## 成功指标

| 指标 | 目标 | 说明 |
|------|------|------|
| 回测速度 | > 100,000 bars/s | 10x 当前速度 |
| 内存效率 | < 2x 数据大小 | 使用 mmap |
| 准确性 | 100% | 结果与事件驱动一致 |
| 测试覆盖 | > 90% | 完整测试 |

---

## 文件结构

```
src/backtest/
├── vectorized/
│   ├── mod.zig                 # 模块入口
│   ├── backtester.zig          # VectorizedBacktester
│   ├── data_loader.zig         # MmapDataLoader
│   ├── simd_indicators.zig     # SIMD 指标计算
│   ├── signal_generator.zig    # 批量信号生成
│   └── order_simulator.zig     # 批量订单模拟
└── tests/
    └── vectorized_test.zig     # 测试文件
```

---

## 风险和缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| SIMD 兼容性 | 部分 CPU 不支持 | 提供标量回退 |
| 浮点精度差异 | 结果不一致 | 使用容差比较 |
| mmap 跨平台 | Windows 支持 | 使用标准文件 I/O 回退 |

---

**Story**: 028
**状态**: 规划中
**创建时间**: 2025-12-27
