# Vectorized Backtest - 向量化回测引擎

> 利用 SIMD 指令加速的高性能批量回测引擎

**状态**: 📋 待开始
**版本**: v0.6.0
**Story**: [Story 028](../../stories/v0.6.0/STORY_028_VECTORIZED_BACKTESTER.md)
**最后更新**: 2025-12-27

---

## 概述

向量化回测引擎是 zigQuant v0.6.0 的核心组件，通过 SIMD (Single Instruction Multiple Data) 指令和内存映射技术实现超高速回测，目标性能 > 100,000 bars/s。

### 为什么需要向量化回测？

传统事件驱动回测逐 bar 处理，存在以下瓶颈：
- 每个 bar 触发函数调用开销
- 指标计算重复初始化
- CPU 缓存利用率低
- 性能约 ~10,000 bars/s

向量化回测通过批量处理解决这些问题：
- 利用 CPU SIMD 指令 (AVX2/AVX-512)
- 一次计算多个数据点
- 更好的内存局部性
- 性能可达 100,000+ bars/s

### 核心特性

- **SIMD 加速**: 利用 @Vector 类型实现并行计算
- **内存映射**: 使用 mmap 高效加载大型数据文件
- **批量信号**: 一次生成全部交易信号
- **批量模拟**: 批量订单执行模拟
- **兼容模式**: 提供标量回退支持旧 CPU

---

## 快速开始

### 基本使用

```zig
const VectorizedBacktester = @import("zigQuant").VectorizedBacktester;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建向量化回测器
    var backtester = VectorizedBacktester.init(allocator, .{
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = Decimal.fromFloat(0.001),
        .use_simd = true,
    });
    defer backtester.deinit();

    // 加载数据 (使用 mmap)
    const data = try backtester.loadData("data/BTCUSDT_1h_2024.csv");

    // 运行回测
    const result = try backtester.run(data, &dual_ma_strategy);

    // 输出结果
    std.debug.print("Total Return: {d:.2}%\n", .{result.total_return_pct});
    std.debug.print("Sharpe Ratio: {d:.2}\n", .{result.sharpe_ratio});
}
```

---

## 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - SIMD 优化技术
- [测试文档](./testing.md) - 性能基准测试
- [Bug 追踪](./bugs.md) - 已知问题
- [变更日志](./changelog.md) - 版本历史

---

## 核心 API

```zig
pub const VectorizedBacktester = struct {
    allocator: Allocator,
    config: Config,

    pub const Config = struct {
        initial_capital: Decimal,
        commission_rate: Decimal,
        slippage: Decimal,
        use_simd: bool = true,
        chunk_size: usize = 1024,
    };

    /// 初始化回测器
    pub fn init(allocator: Allocator, config: Config) VectorizedBacktester;

    /// 释放资源
    pub fn deinit(self: *VectorizedBacktester) void;

    /// 加载数据 (内存映射)
    pub fn loadData(self: *VectorizedBacktester, path: []const u8) !DataSet;

    /// 批量计算指标
    pub fn computeIndicators(
        self: *VectorizedBacktester,
        data: DataSet,
        config: IndicatorConfig,
    ) !IndicatorResults;

    /// 批量生成信号
    pub fn generateSignals(
        self: *VectorizedBacktester,
        indicators: IndicatorResults,
        strategy: IStrategy,
    ) ![]Signal;

    /// 运行完整回测
    pub fn run(
        self: *VectorizedBacktester,
        data: DataSet,
        strategy: IStrategy,
    ) !BacktestResult;
};
```

---

## 最佳实践

### DO

```zig
// 使用大数据集发挥 SIMD 优势
const data = try backtester.loadData("large_dataset.csv"); // 100k+ bars

// 批量计算多个指标
const indicators = try backtester.computeIndicators(data, .{
    .sma_periods = &[_]usize{ 10, 20, 50, 100 },
    .rsi_period = 14,
});
```

### DON'T

```zig
// 避免小数据集 - SIMD 开销可能超过收益
const tiny_data = data[0..100]; // 太小，用标量更快

// 避免频繁切换 SIMD/标量模式
for (chunks) |chunk| {
    if (chunk.len < 4) {
        // 不要这样频繁切换
    }
}
```

---

## 使用场景

### 适用

- 大规模参数优化 (数千组合)
- 多策略批量回测
- 历史数据研究 (数年数据)
- 性能基准测试

### 不适用

- 小数据集 (< 1000 bars)
- 需要逐 bar 精确控制
- 复杂的订单逻辑 (需事件驱动)
- 实盘交易 (使用 LiveTradingEngine)

---

## 性能指标

| 指标 | 目标 | 说明 |
|------|------|------|
| 回测速度 | > 100,000 bars/s | 标准策略 |
| 内存效率 | < 2x 数据大小 | 使用 mmap |
| 指标计算 | < 1ms / 10k bars | SIMD 加速 |
| 信号生成 | < 0.5ms / 10k bars | 批量处理 |

---

## 与事件驱动回测对比

| 特性 | 向量化回测 | 事件驱动回测 |
|------|-----------|-------------|
| 速度 | 100k+ bars/s | ~10k bars/s |
| 内存 | mmap, 按需加载 | 全部加载 |
| 精度 | 批量近似 | 逐 bar 精确 |
| 复杂订单 | 有限支持 | 完整支持 |
| 代码复用 | 独立实现 | 与实盘相同 |
| 适用场景 | 参数优化 | 策略验证 |

---

## 未来改进

- [ ] AVX-512 支持 (更宽向量)
- [ ] GPU 加速 (OpenCL/CUDA)
- [ ] 分布式回测
- [ ] 增量更新支持

---

*Last updated: 2025-12-27*
