# Backtest Guide - 回测使用指南

**版本**: v0.4.0
**更新时间**: 2025-12-27

---

## 目录

1. [快速开始](#快速开始)
2. [数据准备](#数据准备)
3. [运行回测](#运行回测)
4. [解读结果](#解读结果)
5. [导出结果](#导出结果)
6. [高级用法](#高级用法)

---

## 快速开始

### 1. 准备数据文件

确保你有 CSV 格式的历史数据文件：

```csv
timestamp,open,high,low,close,volume
1704067200000,42000.5,42150.0,41950.0,42100.0,1234.5
1704070800000,42100.0,42300.0,42050.0,42250.0,1567.8
...
```

### 2. 运行回测

```bash
# 使用内置策略
zig build run -- backtest \
  --strategy dual_ma \
  --data data/BTCUSDT_1h_2024.csv

# 使用配置文件
zig build run -- backtest \
  --strategy dual_ma \
  --config examples/strategies/dual_ma.json \
  --data data/BTCUSDT_1h_2024.csv
```

### 3. 查看结果

回测完成后会显示详细的性能指标：

```
╔════════════════════════════════════════════════╗
║           Backtest Results                      ║
╠════════════════════════════════════════════════╣
║ Strategy:      Dual MA Crossover               ║
║ Period:        2024-01-01 to 2024-12-31        ║
║ Total Trades:  45                              ║
║ Win Rate:      62.2%                           ║
║ Sharpe Ratio:  1.85                            ║
║ Max Drawdown:  -8.5%                           ║
║ Total Return:  +24.6%                          ║
╚════════════════════════════════════════════════╝
```

---

## 数据准备

### CSV 格式要求

| 列名 | 类型 | 说明 |
|------|------|------|
| `timestamp` | 整数 | Unix 毫秒时间戳 |
| `open` | 浮点数 | 开盘价 |
| `high` | 浮点数 | 最高价 |
| `low` | 浮点数 | 最低价 |
| `close` | 浮点数 | 收盘价 |
| `volume` | 浮点数 | 成交量 |

### 数据来源

1. **Binance 历史数据** (推荐):
   ```bash
   # 下载 BTC/USDT 1小时数据
   wget https://data.binance.vision/data/spot/monthly/klines/BTCUSDT/1h/BTCUSDT-1h-2024-01.zip
   ```

2. **使用 ccxt 获取**:
   ```python
   import ccxt
   exchange = ccxt.binance()
   ohlcv = exchange.fetch_ohlcv('BTC/USDT', '1h')
   ```

3. **项目自带数据**:
   - `data/BTCUSDT_1h_2024.csv` - 2024年完整数据

---

## 运行回测

### 内置策略

| 策略 | 说明 | 适用场景 |
|------|------|---------|
| `dual_ma` | 双均线交叉 | 趋势市场 |
| `rsi_mean_reversion` | RSI均值回归 | 震荡市场 |
| `bollinger_breakout` | 布林带突破 | 突破交易 |
| `macd_divergence` | MACD背离 | 趋势反转 (v0.4.0) |

### 命令行参数

```bash
zig build run -- backtest [OPTIONS]

选项:
  --strategy <name>     策略名称 (必需)
  --data <path>         数据文件路径 (必需)
  --config <path>       配置文件路径 (可选)
  --output <path>       结果输出路径 (可选)
  --format <json|csv>   输出格式 (默认: json)
```

### 示例

```bash
# 基本回测
zig build run -- backtest \
  --strategy dual_ma \
  --data data/BTCUSDT_1h_2024.csv

# 带配置文件
zig build run -- backtest \
  --strategy rsi_mean_reversion \
  --config examples/strategies/rsi_config.json \
  --data data/BTCUSDT_1h_2024.csv

# 导出结果
zig build run -- backtest \
  --strategy dual_ma \
  --data data/BTCUSDT_1h_2024.csv \
  --output results/backtest_result.json
```

---

## 解读结果

### 核心指标

| 指标 | 说明 | 理想值 |
|------|------|--------|
| **Total Return** | 总收益率 | > 0 |
| **Win Rate** | 胜率 | > 50% |
| **Sharpe Ratio** | 夏普比率 | > 1.0 |
| **Max Drawdown** | 最大回撤 | < 20% |
| **Profit Factor** | 盈亏比 | > 1.5 |

### 风险指标

| 指标 | 说明 | 解读 |
|------|------|------|
| **Sortino Ratio** | 下行风险调整收益 | 只考虑亏损波动 |
| **Calmar Ratio** | 收益/最大回撤 | 风险调整后收益 |
| **Max Drawdown Duration** | 最大回撤持续时间 | 恢复能力 |

### 交易统计

| 指标 | 说明 |
|------|------|
| **Total Trades** | 总交易次数 |
| **Winning Trades** | 盈利交易次数 |
| **Losing Trades** | 亏损交易次数 |
| **Average Win** | 平均盈利 |
| **Average Loss** | 平均亏损 |
| **Largest Win** | 最大单笔盈利 |
| **Largest Loss** | 最大单笔亏损 |

---

## 导出结果

### JSON 格式 (v0.4.0)

```bash
zig build run -- backtest \
  --strategy dual_ma \
  --data data/BTCUSDT_1h_2024.csv \
  --output results/result.json \
  --format json
```

输出示例:
```json
{
  "strategy": "dual_ma",
  "period": {
    "start": "2024-01-01T00:00:00Z",
    "end": "2024-12-31T23:59:59Z"
  },
  "metrics": {
    "total_return": 0.246,
    "sharpe_ratio": 1.85,
    "max_drawdown": -0.085,
    "win_rate": 0.622,
    "profit_factor": 2.1
  },
  "trades": [...]
}
```

### CSV 格式 (v0.4.0)

```bash
zig build run -- backtest \
  --strategy dual_ma \
  --data data/BTCUSDT_1h_2024.csv \
  --output results/trades.csv \
  --format csv
```

---

## 高级用法

### 使用代码运行回测

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 加载数据
    var feed = try zigQuant.HistoricalDataFeed.init(allocator);
    defer feed.deinit();
    try feed.loadCSV("data/BTCUSDT_1h_2024.csv");

    // 2. 创建策略
    var strategy = try zigQuant.DualMAStrategy.init(allocator, 10, 30);
    defer strategy.deinit();

    // 3. 配置回测
    const config = zigQuant.BacktestConfig{
        .initial_capital = 10000.0,
        .commission = 0.001,
        .slippage = 0.0005,
    };

    // 4. 运行回测
    var engine = try zigQuant.BacktestEngine.init(allocator, config);
    defer engine.deinit();

    const result = try engine.run(&strategy.interface(), &feed);

    // 5. 分析结果
    var analyzer = zigQuant.PerformanceAnalyzer.init(allocator);
    analyzer.analyze(result);
    analyzer.printReport();
}
```

### 多策略对比

```zig
// 运行多个策略
const strategies = [_][]const u8{ "dual_ma", "rsi_mean_reversion", "bollinger_breakout" };
var results = std.ArrayList(BacktestResult).init(allocator);

for (strategies) |name| {
    const strategy = try StrategyFactory.create(name, allocator);
    defer strategy.deinit();

    const result = try engine.run(&strategy.interface(), &feed);
    try results.append(result);
}

// 对比结果
try compareResults(results.items);
```

---

## 注意事项

### 过拟合风险

- 避免在同一数据集上反复优化
- 使用 Walk-Forward 分析验证策略
- 预留足够的样本外数据测试

### 数据质量

- 检查数据是否有缺失值
- 验证时间戳连续性
- 注意价格异常值

### 交易成本

- 设置真实的手续费率
- 考虑滑点影响
- 高频策略需特别注意

---

## 相关文档

- [优化指南](./OPTIMIZATION_GUIDE.md) - 参数优化
- [策略开发教程](../tutorials/strategy-development.md) - 自定义策略
- [示例程序](../../examples/README.md) - 完整示例

---

**版本**: v0.4.0
**状态**: ✅ 完成
**更新时间**: 2025-12-27
