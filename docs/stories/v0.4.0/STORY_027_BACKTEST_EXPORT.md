# Story: 回测结果导出和可视化

**ID**: `STORY-027`
**版本**: `v0.4.0`
**创建日期**: 2024-12-26
**状态**: 📋 待开始
**优先级**: P2 (中优先级)
**预计工时**: 2-3 天
**依赖**: Story 020 (BacktestEngine), Story 021 (PerformanceAnalyzer)

---

## 📋 需求描述

### 用户故事
作为量化交易者，我希望能够导出回测结果到文件（JSON/CSV），以便我可以：
- 保存历史回测记录
- 在外部工具中分析和可视化
- 比较不同策略和参数的表现
- 生成专业的策略报告

### 背景
v0.3.0 的回测结果只在终端显示，没有持久化能力。用户需要：
1. 将回测结果导出为结构化数据（JSON）
2. 导出交易明细（CSV）
3. 导出权益曲线数据
4. 可选：生成简单的 HTML 报告

参考平台：
- **Freqtrade**: 支持 JSON 导出和 Plotly 可视化
- **Backtrader**: 支持多种格式导出和 matplotlib 可视化
- **QuantConnect**: 提供在线可视化和报告生成

### 范围
- **包含**:
  - JSON 格式完整回测结果导出
  - CSV 格式交易明细导出
  - CSV 格式权益曲线导出
  - CLI 参数支持 `--output` 选项
  - 导出文件的加载和解析工具
  - (可选) 简单的 HTML 报告模板

- **不包含**:
  - 实时可视化（v0.6.0）
  - 交互式图表（v1.0）
  - Web Dashboard（v1.0）
  - PDF 报告生成（v1.0）

---

## 🎯 验收标准

### JSON 导出

- [ ] **AC1**: 完整的回测结果 JSON 导出
  ```json
  {
    "metadata": {
      "strategy": "dual_ma",
      "pair": "BTC-USDT",
      "timeframe": "1h",
      "start_time": "2024-01-01T00:00:00Z",
      "end_time": "2024-12-31T23:59:59Z",
      "backtest_date": "2024-12-26T10:30:00Z",
      "total_candles": 8784
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
      "max_drawdown": -0.125,
      "avg_trade_duration_hours": 48.5,
      "final_equity": 11600.00,
      "total_return": 0.16
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
        "exit_reason": "Death cross: fast MA crossed below slow MA"
      }
    ],
    "equity_curve": [
      {"time": "2024-01-01T00:00:00Z", "equity": 10000.00},
      {"time": "2024-01-02T00:00:00Z", "equity": 10050.00}
    ]
  }
  ```

- [ ] **AC2**: JSON 格式验证
  - 符合标准 JSON 规范
  - 数字精度保持（Decimal 转换）
  - 时间戳格式统一（ISO 8601）

### CSV 导出

- [ ] **AC3**: 交易明细 CSV 导出
  ```csv
  id,entry_time,entry_price,exit_time,exit_price,quantity,side,pnl,pnl_percent,commission,duration_hours,entry_reason,exit_reason
  1,2024-01-05T10:00:00Z,42500.00,2024-01-08T15:00:00Z,43200.00,0.235,long,164.50,1.65,20.12,77,"Golden cross","Death cross"
  ```

- [ ] **AC4**: 权益曲线 CSV 导出
  ```csv
  timestamp,equity,drawdown,trade_count
  2024-01-01T00:00:00Z,10000.00,0.00,0
  2024-01-02T00:00:00Z,10050.00,0.00,1
  ```

### CLI 集成

- [ ] **AC5**: backtest 命令支持 --output 参数
  ```bash
  # JSON 导出
  zigquant backtest \
    --strategy dual_ma \
    --config examples/strategies/dual_ma.json \
    --output results/dual_ma_2024.json

  # 同时导出 trades.csv 和 equity.csv
  zigquant backtest \
    --strategy dual_ma \
    --config examples/strategies/dual_ma.json \
    --output results/dual_ma_2024.json \
    --export-trades results/trades.csv \
    --export-equity results/equity.csv
  ```

- [ ] **AC6**: optimize 命令支持结果导出
  ```bash
  zigquant optimize \
    --strategy dual_ma \
    --config examples/strategies/dual_ma_optimize.json \
    --output results/optimization_results.json \
    --top 10
  ```

### 加载和解析

- [ ] **AC7**: 提供结果加载工具
  ```zig
  const result = try BacktestResult.loadFromJSON(allocator, "results/dual_ma_2024.json");
  defer result.deinit();
  ```

- [ ] **AC8**: 结果对比工具
  ```zig
  const result1 = try BacktestResult.loadFromJSON(allocator, "results/dual_ma.json");
  const result2 = try BacktestResult.loadFromJSON(allocator, "results/triple_ma.json");

  const comparison = try ResultComparison.compare(allocator, result1, result2);
  try comparison.printSummary();
  ```

### (可选) HTML 报告

- [ ] **AC9**: 生成简单的 HTML 报告
  - 使用内置模板
  - 包含关键指标
  - 交易列表
  - 基础 CSS 样式

### 质量标准

- [ ] **AC10**: 性能达标
  - 导出 1000 笔交易 < 100ms
  - 内存使用合理

- [ ] **AC11**: 错误处理
  - 文件写入失败处理
  - 无效路径检测
  - 权限问题提示

- [ ] **AC12**: 单元测试覆盖率 > 85%
  - JSON 序列化测试
  - CSV 格式测试
  - 文件 I/O 测试
  - 加载和解析测试

---

## 🔧 技术设计

### 架构概览

```
src/backtest/
    ├── engine.zig              # 已存在
    ├── types.zig               # 已存在
    ├── analyzer.zig            # 已存在
    ├── export.zig              # 新增 ✨
    ├── json_exporter.zig       # 新增 ✨
    ├── csv_exporter.zig        # 新增 ✨
    └── result_loader.zig       # 新增 ✨

docs/features/backtest/
    ├── README.md               # 更新
    ├── api.md                  # 更新
    └── export.md               # 新增 ✨
```

### 数据结构

#### 1. Export Module (export.zig)

```zig
const std = @import("std");
const zigQuant = @import("../root.zig");

const BacktestResult = zigQuant.BacktestResult;
const BacktestConfig = zigQuant.BacktestConfig;

pub const ExportFormat = enum {
    json,
    csv,
    html,
};

pub const ExportOptions = struct {
    format: ExportFormat,
    output_path: []const u8,
    pretty_json: bool = true,
    include_trades: bool = true,
    include_equity_curve: bool = true,
};

pub const Exporter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Exporter {
        return .{ .allocator = allocator };
    }

    pub fn exportResult(
        self: *Exporter,
        result: *const BacktestResult,
        config: *const BacktestConfig,
        options: ExportOptions,
    ) !void {
        switch (options.format) {
            .json => try self.exportJSON(result, config, options),
            .csv => try self.exportCSV(result, config, options),
            .html => try self.exportHTML(result, config, options),
        }
    }

    fn exportJSON(
        self: *Exporter,
        result: *const BacktestResult,
        config: *const BacktestConfig,
        options: ExportOptions,
    ) !void {
        var json_exporter = JSONExporter.init(self.allocator);
        try json_exporter.export(result, config, options);
    }

    fn exportCSV(
        self: *Exporter,
        result: *const BacktestResult,
        config: *const BacktestConfig,
        options: ExportOptions,
    ) !void {
        var csv_exporter = CSVExporter.init(self.allocator);
        try csv_exporter.export(result, config, options);
    }

    fn exportHTML(
        self: *Exporter,
        result: *const BacktestResult,
        config: *const BacktestConfig,
        options: ExportOptions,
    ) !void {
        // HTML 报告生成（可选）
    }
};
```

#### 2. JSON Exporter (json_exporter.zig)

```zig
const std = @import("std");
const zigQuant = @import("../root.zig");

const BacktestResult = zigQuant.BacktestResult;
const BacktestConfig = zigQuant.BacktestConfig;
const Decimal = zigQuant.Decimal;
const Timestamp = zigQuant.Timestamp;

pub const JSONExporter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) JSONExporter {
        return .{ .allocator = allocator };
    }

    pub fn export(
        self: *JSONExporter,
        result: *const BacktestResult,
        config: *const BacktestConfig,
        options: ExportOptions,
    ) !void {
        // 创建 JSON 对象
        var root = std.json.ObjectMap.init(self.allocator);
        defer root.deinit();

        // Metadata
        try root.put("metadata", try self.buildMetadata(result, config));

        // Config
        try root.put("config", try self.buildConfig(config));

        // Metrics
        try root.put("metrics", try self.buildMetrics(result));

        // Trades
        if (options.include_trades) {
            try root.put("trades", try self.buildTrades(result));
        }

        // Equity curve
        if (options.include_equity_curve) {
            try root.put("equity_curve", try self.buildEquityCurve(result));
        }

        // 写入文件
        const file = try std.fs.cwd().createFile(options.output_path, .{});
        defer file.close();

        const write_options = std.json.WriteOptions{
            .whitespace = if (options.pretty_json) .indent_2 else .minified,
        };

        try std.json.stringify(root, write_options, file.writer());
    }

    fn buildMetadata(
        self: *JSONExporter,
        result: *const BacktestResult,
        config: *const BacktestConfig,
    ) !std.json.Value {
        var metadata = std.json.ObjectMap.init(self.allocator);

        try metadata.put("strategy", .{ .string = result.strategy_name });
        try metadata.put("pair", .{ .string = try self.formatPair(config.pair) });
        try metadata.put("timeframe", .{ .string = try self.formatTimeframe(config.timeframe) });
        try metadata.put("start_time", .{ .string = try config.start_time.toISO8601() });
        try metadata.put("end_time", .{ .string = try config.end_time.toISO8601() });
        try metadata.put("backtest_date", .{ .string = try Timestamp.now().toISO8601() });
        try metadata.put("total_candles", .{ .integer = result.total_candles });

        return .{ .object = metadata };
    }

    fn buildMetrics(
        self: *JSONExporter,
        result: *const BacktestResult,
    ) !std.json.Value {
        var metrics = std.json.ObjectMap.init(self.allocator);

        try metrics.put("total_trades", .{ .integer = result.total_trades });
        try metrics.put("winning_trades", .{ .integer = result.winning_trades });
        try metrics.put("losing_trades", .{ .integer = result.losing_trades });
        try metrics.put("win_rate", .{ .float = result.win_rate });
        try metrics.put("total_profit", .{ .float = try result.total_profit.toFloat() });
        try metrics.put("total_loss", .{ .float = try result.total_loss.toFloat() });
        try metrics.put("net_profit", .{ .float = try result.net_profit.toFloat() });
        try metrics.put("profit_factor", .{ .float = result.profit_factor });
        try metrics.put("sharpe_ratio", .{ .float = result.sharpe_ratio });
        try metrics.put("max_drawdown", .{ .float = result.max_drawdown });
        // ... 其他指标

        return .{ .object = metrics };
    }

    fn buildTrades(
        self: *JSONExporter,
        result: *const BacktestResult,
    ) !std.json.Value {
        var trades_array = std.json.Array.init(self.allocator);

        for (result.trades, 0..) |trade, i| {
            var trade_obj = std.json.ObjectMap.init(self.allocator);

            try trade_obj.put("id", .{ .integer = i + 1 });
            try trade_obj.put("entry_time", .{ .string = try trade.entry_time.toISO8601() });
            try trade_obj.put("entry_price", .{ .float = try trade.entry_price.toFloat() });
            try trade_obj.put("exit_time", .{ .string = try trade.exit_time.toISO8601() });
            try trade_obj.put("exit_price", .{ .float = try trade.exit_price.toFloat() });
            // ... 其他字段

            try trades_array.append(.{ .object = trade_obj });
        }

        return .{ .array = trades_array };
    }
};
```

#### 3. CSV Exporter (csv_exporter.zig)

```zig
pub const CSVExporter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CSVExporter {
        return .{ .allocator = allocator };
    }

    pub fn exportTrades(
        self: *CSVExporter,
        trades: []const Trade,
        output_path: []const u8,
    ) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        const writer = file.writer();

        // 写入表头
        try writer.writeAll("id,entry_time,entry_price,exit_time,exit_price,quantity,side,pnl,pnl_percent,commission,duration_hours,entry_reason,exit_reason\n");

        // 写入数据行
        for (trades, 0..) |trade, i| {
            try writer.print(
                "{},{s},{d},{s},{d},{d},{s},{d},{d},{d},{d},\"{s}\",\"{s}\"\n",
                .{
                    i + 1,
                    try trade.entry_time.toISO8601(),
                    try trade.entry_price.toFloat(),
                    try trade.exit_time.toISO8601(),
                    try trade.exit_price.toFloat(),
                    try trade.quantity.toFloat(),
                    @tagName(trade.side),
                    try trade.pnl.toFloat(),
                    trade.pnl_percent,
                    try trade.commission.toFloat(),
                    trade.duration_hours,
                    trade.entry_reason,
                    trade.exit_reason,
                },
            );
        }
    }

    pub fn exportEquityCurve(
        self: *CSVExporter,
        equity_curve: []const EquityPoint,
        output_path: []const u8,
    ) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        const writer = file.writer();

        // 写入表头
        try writer.writeAll("timestamp,equity,drawdown,trade_count\n");

        // 写入数据行
        for (equity_curve) |point| {
            try writer.print(
                "{s},{d},{d},{}\n",
                .{
                    try point.timestamp.toISO8601(),
                    try point.equity.toFloat(),
                    point.drawdown,
                    point.trade_count,
                },
            );
        }
    }
};
```

#### 4. Result Loader (result_loader.zig)

```zig
pub const ResultLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResultLoader {
        return .{ .allocator = allocator };
    }

    pub fn loadFromJSON(
        self: *ResultLoader,
        file_path: []const u8,
    ) !BacktestResult {
        // 读取文件
        const json_data = try std.fs.cwd().readFileAlloc(
            self.allocator,
            file_path,
            10 * 1024 * 1024, // 10MB max
        );
        defer self.allocator.free(json_data);

        // 解析 JSON
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            json_data,
            .{},
        );
        defer parsed.deinit();

        // 构建 BacktestResult
        return try self.parseResult(parsed.value);
    }

    fn parseResult(self: *ResultLoader, value: std.json.Value) !BacktestResult {
        // 解析逻辑
    }
};
```

### CLI 集成

更新 `src/cli/commands/backtest.zig`:

```zig
const params = clap.parseParamsComptime(
    \\-h, --help                Display help
    \\-s, --strategy <str>      Strategy name
    \\-c, --config <str>        Strategy config JSON file (required)
    \\-d, --data <str>          Historical data CSV file (optional)
    \\    --start <str>         Start timestamp
    \\    --end <str>           End timestamp
    \\    --capital <str>       Initial capital (default: 10000)
    \\-o, --output <str>        Save results to JSON file (NEW) ✨
    \\    --export-trades <str> Export trades to CSV file (NEW) ✨
    \\    --export-equity <str> Export equity curve to CSV (NEW) ✨
    \\
);
```

---

## 📊 使用示例

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
```

### 程序化使用

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 运行回测
    const result = try runBacktest(allocator);
    defer result.deinit();

    // 导出 JSON
    var exporter = zigQuant.Exporter.init(allocator);
    try exporter.exportResult(
        &result,
        &config,
        .{
            .format = .json,
            .output_path = "results/backtest.json",
            .pretty_json = true,
        },
    );

    // 导出交易 CSV
    var csv_exporter = zigQuant.CSVExporter.init(allocator);
    try csv_exporter.exportTrades(
        result.trades,
        "results/trades.csv",
    );

    // 加载之前的结果
    var loader = zigQuant.ResultLoader.init(allocator);
    const loaded = try loader.loadFromJSON("results/backtest.json");
    defer loaded.deinit();
}
```

---

## 📚 文档要求

### 导出格式文档

创建 `docs/features/backtest/export.md`，包含：

1. **支持的导出格式**
   - JSON 完整结构
   - CSV 格式说明
   - HTML 模板说明

2. **CLI 使用指南**
   - 基本导出命令
   - 多格式导出
   - 批量导出

3. **API 使用指南**
   - Exporter 类使用
   - ResultLoader 类使用
   - 自定义导出格式

4. **最佳实践**
   - 文件命名约定
   - 目录组织
   - 结果归档

---

## 🔗 相关文档

- [Story 020: BacktestEngine](../v0.3.0/STORY_020_BACKTEST_ENGINE.md)
- [Story 021: PerformanceAnalyzer](../v0.3.0/STORY_021_PERFORMANCE_ANALYZER.md)
- [Backtest Engine 文档](../../features/backtest/README.md)

---

## ✅ 完成标准

- [ ] JSON 导出功能实现完成
- [ ] CSV 导出功能实现完成
- [ ] CLI 参数集成完成
- [ ] ResultLoader 实现完成
- [ ] 所有单元测试通过（覆盖率 > 85%）
- [ ] 性能测试通过
- [ ] 文档完成（export.md）
- [ ] CLI 帮助信息更新
- [ ] 示例文件创建

---

**创建时间**: 2024-12-26
**最后更新**: 2024-12-26
**作者**: Claude (Sonnet 4.5)
