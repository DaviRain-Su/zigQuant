# Backtest Result Export - 回测结果导出

**版本**: v0.4.0
**状态**: 📋 计划中
**层级**: Strategy Layer
**依赖**: BacktestEngine, PerformanceAnalyzer
**Story**: [STORY-027](../../stories/v0.4.0/STORY_027_BACKTEST_EXPORT.md)

---

## 📋 目录

1. [功能概述](#功能概述)
2. [导出格式](#导出格式)
3. [CLI 使用](#cli-使用)
4. [API 使用](#api-使用)
5. [数据结构](#数据结构)
6. [最佳实践](#最佳实践)

---

## 🎯 功能概述

Backtest Result Export 提供回测结果的持久化和导出功能，支持多种格式，便于结果分析、比较和归档。

### 设计目标

- **完整性**: 导出所有回测数据和指标
- **标准化**: 使用通用格式（JSON/CSV）
- **可读性**: 格式清晰，易于解析
- **性能**: 高效的文件 I/O
- **兼容性**: 可被外部工具使用

### 核心功能

- ✅ JSON 格式完整导出
- ✅ CSV 格式交易明细导出
- ✅ CSV 格式权益曲线导出
- ✅ 结果加载和解析
- ✅ 结果对比工具
- ⏳ HTML 报告生成（可选）

---

## 📄 导出格式

### 1. JSON 格式

#### 完整回测结果

```json
{
  "metadata": {
    "strategy": "dual_ma",
    "pair": "BTC-USDT",
    "timeframe": "1h",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-12-31T23:59:59Z",
    "backtest_date": "2024-12-26T10:30:00Z",
    "total_candles": 8784,
    "platform": "zigQuant v0.4.0"
  },
  "config": {
    "initial_capital": 10000.00,
    "commission_rate": 0.001,
    "slippage": 0.0005,
    "parameters": {
      "fast_period": 10,
      "slow_period": 20,
      "ma_type": "sma"
    }
  },
  "metrics": {
    "total_trades": 42,
    "winning_trades": 28,
    "losing_trades": 14,
    "win_rate": 0.6667,
    "total_profit": 2800.00,
    "total_loss": -1200.00,
    "net_profit": 1600.00,
    "profit_factor": 2.88,
    "sharpe_ratio": 1.45,
    "sortino_ratio": 1.82,
    "max_drawdown": -0.125,
    "max_drawdown_duration_hours": 168,
    "avg_trade_duration_hours": 48.5,
    "final_equity": 11600.00,
    "total_return": 0.16,
    "annualized_return": 0.16,
    "avg_win": 100.00,
    "avg_loss": -85.71,
    "largest_win": 450.00,
    "largest_loss": -280.00,
    "consecutive_wins": 7,
    "consecutive_losses": 3
  },
  "trades": [
    {
      "id": 1,
      "entry_time": "2024-01-05T10:00:00Z",
      "entry_price": 42500.00,
      "exit_time": "2024-01-08T15:00:00Z",
      "exit_price": 43200.00,
      "quantity": 0.235,
      "side": "long",
      "pnl": 164.50,
      "pnl_percent": 1.65,
      "commission": 20.12,
      "duration_hours": 77,
      "entry_reason": "Golden cross: fast MA crossed above slow MA",
      "exit_reason": "Death cross: fast MA crossed below slow MA",
      "mae": -50.00,
      "mfe": 200.00
    }
  ],
  "equity_curve": [
    {
      "timestamp": "2024-01-01T00:00:00Z",
      "equity": 10000.00,
      "drawdown": 0.00,
      "trade_count": 0
    },
    {
      "timestamp": "2024-01-02T00:00:00Z",
      "equity": 10050.00,
      "drawdown": 0.00,
      "trade_count": 1
    }
  ]
}
```

#### 优化结果导出

```json
{
  "metadata": {
    "strategy": "dual_ma",
    "optimization_date": "2024-12-26T12:00:00Z",
    "objective": "sharpe_ratio",
    "total_combinations": 100,
    "completed": 100
  },
  "param_grid": {
    "fast_period": [5, 10, 15, 20],
    "slow_period": [20, 30, 40, 50]
  },
  "results": [
    {
      "rank": 1,
      "parameters": {
        "fast_period": 10,
        "slow_period": 30
      },
      "objective_value": 1.82,
      "metrics": {
        "sharpe_ratio": 1.82,
        "total_return": 0.24,
        "max_drawdown": -0.10,
        "total_trades": 35
      }
    }
  ]
}
```

### 2. CSV 格式

#### 交易明细 (trades.csv)

```csv
id,entry_time,entry_price,exit_time,exit_price,quantity,side,pnl,pnl_percent,commission,duration_hours,entry_reason,exit_reason,mae,mfe
1,2024-01-05T10:00:00Z,42500.00,2024-01-08T15:00:00Z,43200.00,0.235,long,164.50,1.65,20.12,77,"Golden cross","Death cross",-50.00,200.00
2,2024-01-15T09:00:00Z,44000.00,2024-01-18T14:00:00Z,43500.00,0.227,long,-113.50,-1.14,20.00,77,"Golden cross","Stop loss",-113.50,80.00
```

**字段说明**:
- `id`: 交易序号
- `entry_time`: 入场时间 (ISO 8601)
- `entry_price`: 入场价格
- `exit_time`: 出场时间 (ISO 8601)
- `exit_price`: 出场价格
- `quantity`: 交易数量
- `side`: 方向 (long/short)
- `pnl`: 盈亏 (绝对值)
- `pnl_percent`: 盈亏百分比
- `commission`: 手续费
- `duration_hours`: 持仓时长（小时）
- `entry_reason`: 入场原因
- `exit_reason`: 出场原因
- `mae`: 最大不利偏移 (Maximum Adverse Excursion)
- `mfe`: 最大有利偏移 (Maximum Favorable Excursion)

#### 权益曲线 (equity.csv)

```csv
timestamp,equity,drawdown,drawdown_percent,trade_count,cum_return
2024-01-01T00:00:00Z,10000.00,0.00,0.00,0,0.00
2024-01-02T00:00:00Z,10050.00,0.00,0.00,1,0.005
2024-01-05T00:00:00Z,10164.50,0.00,0.00,2,0.01645
2024-01-10T00:00:00Z,10100.00,-64.50,-0.0063,3,0.01
```

**字段说明**:
- `timestamp`: 时间戳 (ISO 8601)
- `equity`: 当前权益
- `drawdown`: 回撤 (绝对值)
- `drawdown_percent`: 回撤百分比
- `trade_count`: 累计交易数
- `cum_return`: 累计收益率

---

## 🖥️ CLI 使用

### 基本导出

```bash
# 导出完整 JSON 结果
zigquant backtest \
  --strategy dual_ma \
  --config examples/strategies/dual_ma.json \
  --output results/dual_ma_backtest.json

# 同时导出 CSV
zigquant backtest \
  --strategy dual_ma \
  --config examples/strategies/dual_ma.json \
  --output results/dual_ma_backtest.json \
  --export-trades results/dual_ma_trades.csv \
  --export-equity results/dual_ma_equity.csv

# 仅导出 CSV（不输出 JSON）
zigquant backtest \
  --strategy dual_ma \
  --config examples/strategies/dual_ma.json \
  --export-trades results/trades.csv
```

### 优化结果导出

```bash
# 导出优化结果
zigquant optimize \
  --strategy dual_ma \
  --config examples/strategies/dual_ma_optimize.json \
  --output results/optimization_results.json \
  --top 10

# 导出所有组合结果
zigquant optimize \
  --strategy dual_ma \
  --config examples/strategies/dual_ma_optimize.json \
  --output results/full_optimization.json \
  --top 0  # 0 表示全部
```

---

## 🔧 API 使用

### 导出结果

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 运行回测
    var engine = BacktestEngine.init(allocator, logger);
    defer engine.deinit();

    const result = try engine.run(strategy, config);
    defer result.deinit();

    // 2. 导出 JSON
    var exporter = zigQuant.Exporter.init(allocator);
    try exporter.exportResult(
        &result,
        &config,
        .{
            .format = .json,
            .output_path = "results/backtest.json",
            .pretty_json = true,
            .include_trades = true,
            .include_equity_curve = true,
        },
    );

    // 3. 导出交易 CSV
    var csv_exporter = zigQuant.CSVExporter.init(allocator);
    try csv_exporter.exportTrades(
        result.trades,
        "results/trades.csv",
    );

    // 4. 导出权益曲线 CSV
    try csv_exporter.exportEquityCurve(
        result.equity_curve,
        "results/equity.csv",
    );
}
```

### 加载结果

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 加载之前的回测结果
    var loader = zigQuant.ResultLoader.init(allocator);
    const result = try loader.loadFromJSON("results/backtest.json");
    defer result.deinit();

    // 2. 访问数据
    std.debug.print("策略: {s}\n", .{result.strategy_name});
    std.debug.print("总交易数: {}\n", .{result.total_trades});
    std.debug.print("净利润: {}\n", .{result.net_profit});
    std.debug.print("夏普比率: {d:.2}\n", .{result.sharpe_ratio});

    // 3. 遍历交易
    for (result.trades) |trade| {
        std.debug.print("交易 #{}: PnL = {}\n", .{
            trade.id,
            trade.pnl,
        });
    }
}
```

### 比较多个结果

```zig
pub fn compareResults(
    allocator: std.mem.Allocator,
    result1_path: []const u8,
    result2_path: []const u8,
) !void {
    var loader = zigQuant.ResultLoader.init(allocator);

    const result1 = try loader.loadFromJSON(result1_path);
    defer result1.deinit();

    const result2 = try loader.loadFromJSON(result2_path);
    defer result2.deinit();

    // 对比指标
    const comparison = zigQuant.ResultComparison{
        .result1 = result1,
        .result2 = result2,
    };

    try comparison.printSummary();
    /*
    ╔════════════════════════════════════╗
    ║ 策略对比                            ║
    ╚════════════════════════════════════╝

    指标             策略 A      策略 B      差异
    ─────────────────────────────────────────
    总交易数         42          35          +7
    胜率             66.7%       60.0%       +6.7%
    净利润           $1,600      $1,200      +$400
    夏普比率         1.45        1.25        +0.20
    最大回撤         -12.5%      -10.0%      -2.5%
    */
}
```

---

## 📦 数据结构

### ExportOptions

```zig
pub const ExportOptions = struct {
    /// 导出格式
    format: ExportFormat,

    /// 输出文件路径
    output_path: []const u8,

    /// JSON 美化（仅 JSON 格式）
    pretty_json: bool = true,

    /// 包含交易明细
    include_trades: bool = true,

    /// 包含权益曲线
    include_equity_curve: bool = true,

    /// CSV 分隔符（仅 CSV 格式）
    csv_delimiter: u8 = ',',

    /// 压缩输出（未来功能）
    compress: bool = false,
};

pub const ExportFormat = enum {
    json,
    csv,
    html,  // 可选
};
```

### Exporter

```zig
pub const Exporter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Exporter;

    pub fn exportResult(
        self: *Exporter,
        result: *const BacktestResult,
        config: *const BacktestConfig,
        options: ExportOptions,
    ) !void;
};
```

### ResultLoader

```zig
pub const ResultLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResultLoader;

    pub fn loadFromJSON(
        self: *ResultLoader,
        file_path: []const u8,
    ) !BacktestResult;

    pub fn loadFromCSV(
        self: *ResultLoader,
        trades_path: []const u8,
        equity_path: []const u8,
    ) !BacktestResult;
};
```

---

## 💡 最佳实践

### 文件命名约定

```
results/
    ├── backtests/
    │   ├── dual_ma_btc_2024.json
    │   ├── dual_ma_btc_2024_trades.csv
    │   ├── dual_ma_btc_2024_equity.csv
    │   ├── rsi_eth_2024.json
    │   └── ...
    ├── optimizations/
    │   ├── dual_ma_grid_search_2024.json
    │   ├── rsi_optimize_2024.json
    │   └── ...
    └── comparisons/
        ├── strategies_comparison_2024.json
        └── ...
```

**命名格式**: `{strategy}_{pair}_{timeperiod}.{ext}`

### 目录组织

```
.
├── results/              # 回测结果
│   ├── backtests/
│   ├── optimizations/
│   └── comparisons/
├── data/                 # 历史数据
│   ├── BTCUSDT_1h_2024.csv
│   └── ...
├── examples/
│   └── strategies/
└── docs/
```

### 数据归档

```bash
# 压缩旧结果
tar -czf results_2024_Q1.tar.gz results/2024-Q1/

# 备份到云存储
aws s3 sync results/ s3://my-bucket/zigquant-results/

# 定期清理
find results/ -name "*.json" -mtime +90 -delete
```

### 性能建议

1. **大文件处理**: 对于大量交易（>10,000），考虑:
   - 使用流式写入
   - 分批导出
   - 压缩输出

2. **并发导出**: 多个格式可并行导出
   ```zig
   // 并发导出 JSON 和 CSV
   const thread1 = try std.Thread.spawn(.{}, exportJSON, .{...});
   const thread2 = try std.Thread.spawn(.{}, exportCSV, .{...});

   thread1.join();
   thread2.join();
   ```

3. **内存优化**: 对于超大结果集，使用迭代器而非一次性加载
   ```zig
   var iterator = try ResultIterator.init("results/huge.json");
   while (try iterator.next()) |trade| {
       // 处理每笔交易
   }
   ```

---

## 🔗 相关文档

- [Story 027: 回测结果导出](../../stories/v0.4.0/STORY_027_BACKTEST_EXPORT.md)
- [BacktestEngine 文档](./README.md)
- [PerformanceAnalyzer 文档](./analyzer.md)
- [CLI 使用指南](../cli/usage-guide.md)

---

## ✅ v0.4.0 完成标准

- [ ] JSON 导出实现
- [ ] CSV 导出实现
- [ ] Result Loader 实现
- [ ] CLI 集成完成
- [ ] 单元测试通过
- [ ] 性能测试通过
- [ ] 文档完成
- [ ] 示例代码完成

---

**创建时间**: 2024-12-26
**最后更新**: 2024-12-26
**作者**: Claude (Sonnet 4.5)
