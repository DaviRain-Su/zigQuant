# Story 023: CLI 策略命令集成

**Story ID**: 023
**Version**: v0.3.0
**Week**: Week 3
**Priority**: P0
**Estimated Effort**: 2 天
**Status**: 待开始

---

## 📋 概述

### 标题
CLI 策略命令集成

### 描述
为 zigQuant CLI 添加策略相关命令，包括策略回测、参数优化和策略列表查看等功能。提供友好的命令行界面，支持丰富的配置选项和清晰的输出格式。

### 业务价值
- **易用性**: 提供简单易用的 CLI 界面，降低使用门槛
- **自动化**: 支持脚本化调用，便于 CI/CD 集成
- **可观测性**: 提供清晰的输出和详细的日志
- **生产力**: 快速验证策略和参数，加速开发迭代

### 用户故事
作为策略开发者，我希望能通过简单的命令行命令运行策略回测和参数优化，而不需要编写复杂的代码，这样我就可以快速验证策略想法。

---

## 🎯 目标与范围

### 功能目标
1. ✅ 实现 `strategy backtest` 命令
2. ✅ 实现 `strategy optimize` 命令
3. ✅ 实现 `strategy list` 命令
4. ✅ 支持配置文件和命令行参数
5. ✅ 提供清晰的输出格式（表格、JSON）
6. ✅ 完善的帮助文档和错误提示

### 非功能目标
- **用户体验**: 命令直观易用，帮助文档完整
- **健壮性**: 完善的错误处理和友好的错误提示
- **性能**: 命令响应时间 < 200ms（不含回测时间）
- **可测试**: CLI 测试覆盖率 > 80%

### 范围界定

#### 包含内容
- `strategy backtest` 命令实现
- `strategy optimize` 命令实现
- `strategy list` 命令实现
- 配置文件支持
- 多种输出格式（表格、JSON、CSV）
- 完整的单元测试

#### 不包含内容
- Web UI 界面
- 实时策略监控
- 策略部署功能
- 策略编辑器

---

## 📝 详细任务分解

### Task 1: 创建 CLI 策略模块基础结构 (2小时)

**文件**: `src/cli/strategy.zig`

**实现内容**:
```zig
const std = @import("std");
const clap = @import("clap");
const Logger = @import("../logger.zig").Logger;
const BacktestEngine = @import("../backtest/engine.zig").BacktestEngine;
const GridSearchOptimizer = @import("../optimizer/grid_search.zig").GridSearchOptimizer;
const IStrategy = @import("../strategy/interface.zig").IStrategy;

/// CLI 策略命令处理器
pub const StrategyCommands = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    pub fn init(allocator: std.mem.Allocator, logger: Logger) StrategyCommands {
        return .{
            .allocator = allocator,
            .logger = logger,
        };
    }

    pub fn deinit(self: *StrategyCommands) void {
        _ = self;
    }

    /// 执行策略命令
    pub fn execute(self: *StrategyCommands, args: []const []const u8) !void {
        if (args.len < 1) {
            try self.printHelp();
            return error.InvalidCommand;
        }

        const subcommand = args[0];

        if (std.mem.eql(u8, subcommand, "backtest")) {
            try self.runBacktest(args[1..]);
        } else if (std.mem.eql(u8, subcommand, "optimize")) {
            try self.runOptimize(args[1..]);
        } else if (std.mem.eql(u8, subcommand, "list")) {
            try self.listStrategies(args[1..]);
        } else {
            self.logger.err("Unknown subcommand: {s}", .{subcommand});
            try self.printHelp();
            return error.UnknownSubcommand;
        }
    }

    fn printHelp(self: *StrategyCommands) !void {
        const help_text =
            \\Usage: zigquant strategy <subcommand> [options]
            \\
            \\Subcommands:
            \\  backtest    Run strategy backtest
            \\  optimize    Optimize strategy parameters
            \\  list        List available strategies
            \\
            \\Run 'zigquant strategy <subcommand> --help' for more information.
        ;
        try self.logger.info(help_text, .{});
    }

    fn runBacktest(self: *StrategyCommands, args: []const []const u8) !void;
    fn runOptimize(self: *StrategyCommands, args: []const []const u8) !void;
    fn listStrategies(self: *StrategyCommands, args: []const []const u8) !void;
};
```

**验收标准**:
- [ ] 基础结构完整
- [ ] 子命令路由正确
- [ ] 帮助信息清晰
- [ ] 编译通过

---

### Task 2: 实现 `strategy backtest` 命令 (4小时)

**文件**: `src/cli/strategy.zig` (Part 2)

**命令格式**:
```bash
zigquant strategy backtest [options]

Options:
  -s, --strategy <name>      Strategy name (required)
  -p, --pair <pair>          Trading pair (e.g., BTC-USDT)
  -t, --timeframe <tf>       Timeframe (e.g., 1m, 5m, 15m, 1h)
  -S, --start <time>         Start time (ISO 8601 or timestamp)
  -E, --end <time>           End time (ISO 8601 or timestamp)
  -c, --config <file>        Config file path
  -o, --output <format>      Output format (table|json|csv)
  -f, --file <path>          Save report to file
  --capital <amount>         Initial capital (default: 10000)
  --commission <rate>        Commission rate (default: 0.001)
  -h, --help                 Show help
```

**实现内容**:
```zig
/// 回测命令配置
pub const BacktestCommandConfig = struct {
    strategy_name: []const u8,
    pair: []const u8,
    timeframe: []const u8,
    start_time: []const u8,
    end_time: []const u8,
    config_file: ?[]const u8,
    output_format: OutputFormat,
    output_file: ?[]const u8,
    initial_capital: f64,
    commission_rate: f64,

    pub const OutputFormat = enum {
        table,
        json,
        csv,
    };
};

fn runBacktest(self: *StrategyCommands, args: []const []const u8) !void {
    // 1. 解析命令行参数
    const config = try self.parseBacktestArgs(args);

    // 2. 加载策略
    self.logger.info("Loading strategy: {s}", .{config.strategy_name});
    const strategy = try self.loadStrategy(config.strategy_name, config.config_file);
    defer strategy.deinit();

    // 3. 准备回测引擎
    var engine = try BacktestEngine.init(
        self.allocator,
        self.logger,
        /* data feed */,
    );
    defer engine.deinit();

    // 4. 构建回测配置
    const backtest_config = BacktestConfig{
        .pair = try TradingPair.parse(config.pair),
        .timeframe = try Timeframe.parse(config.timeframe),
        .start_time = try Timestamp.parse(config.start_time),
        .end_time = try Timestamp.parse(config.end_time),
        .initial_capital = try Decimal.fromFloat(config.initial_capital),
        .commission_rate = try Decimal.fromFloat(config.commission_rate),
    };

    // 5. 运行回测
    self.logger.info("Running backtest...", .{});
    const start = std.time.milliTimestamp();

    const result = try engine.run(strategy, backtest_config);
    defer result.deinit();

    const elapsed = std.time.milliTimestamp() - start;
    self.logger.info("Backtest completed in {d}ms", .{elapsed});

    // 6. 输出结果
    try self.printBacktestResult(result, config.output_format);

    // 7. 保存到文件（如果指定）
    if (config.output_file) |file_path| {
        try self.saveBacktestResult(result, file_path, config.output_format);
        self.logger.info("Report saved to: {s}", .{file_path});
    }
}

fn parseBacktestArgs(
    self: *StrategyCommands,
    args: []const []const u8,
) !BacktestCommandConfig {
    // 使用 clap 库解析参数
    const params = comptime clap.parseParamsComptime(
        \\-s, --strategy <str>      Strategy name
        \\-p, --pair <str>          Trading pair
        \\-t, --timeframe <str>     Timeframe
        \\-S, --start <str>         Start time
        \\-E, --end <str>           End time
        \\-c, --config <str>        Config file
        \\-o, --output <str>        Output format
        \\-f, --file <str>          Output file
        \\--capital <f64>           Initial capital
        \\--commission <f64>        Commission rate
        \\-h, --help                Show help
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, args, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help) {
        try self.printBacktestHelp();
        return error.HelpRequested;
    }

    // 验证必需参数
    if (res.args.strategy == null) {
        return error.MissingStrategyName;
    }

    return BacktestCommandConfig{
        .strategy_name = res.args.strategy.?,
        .pair = res.args.pair orelse "BTC-USDT",
        .timeframe = res.args.timeframe orelse "15m",
        .start_time = res.args.start orelse "2024-01-01T00:00:00Z",
        .end_time = res.args.end orelse "2024-12-31T23:59:59Z",
        .config_file = res.args.config,
        .output_format = if (res.args.output) |fmt|
            std.meta.stringToEnum(OutputFormat, fmt) orelse .table
        else
            .table,
        .output_file = res.args.file,
        .initial_capital = res.args.capital orelse 10000.0,
        .commission_rate = res.args.commission orelse 0.001,
    };
}

fn printBacktestResult(
    self: *StrategyCommands,
    result: BacktestResult,
    format: OutputFormat,
) !void {
    switch (format) {
        .table => try self.printTableFormat(result),
        .json => try self.printJsonFormat(result),
        .csv => try self.printCsvFormat(result),
    }
}

fn printTableFormat(self: *StrategyCommands, result: BacktestResult) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n", .{});
    try stdout.print("═══════════════════════════════════════════════════\n", .{});
    try stdout.print("             Backtest Results\n", .{});
    try stdout.print("═══════════════════════════════════════════════════\n", .{});
    try stdout.print("\n", .{});

    try stdout.print("Performance Metrics:\n", .{});
    try stdout.print("─────────────────────────────────────────────────\n", .{});
    try stdout.print("  Total Trades:       {d}\n", .{result.total_trades});
    try stdout.print("  Winning Trades:     {d}\n", .{result.winning_trades});
    try stdout.print("  Losing Trades:      {d}\n", .{result.losing_trades});
    try stdout.print("  Win Rate:           {d:.2}%\n", .{result.win_rate * 100});
    try stdout.print("\n", .{});
    try stdout.print("  Net Profit:         {s}\n", .{result.net_profit.toString()});
    try stdout.print("  Total Profit:       {s}\n", .{result.total_profit.toString()});
    try stdout.print("  Total Loss:         {s}\n", .{result.total_loss.toString()});
    try stdout.print("  Profit Factor:      {d:.2}\n", .{result.profit_factor});
    try stdout.print("\n", .{});
    try stdout.print("  Sharpe Ratio:       {d:.2}\n", .{result.sharpe_ratio});
    try stdout.print("  Max Drawdown:       {d:.2}%\n", .{result.max_drawdown * 100});
    try stdout.print("\n", .{});
    try stdout.print("═══════════════════════════════════════════════════\n", .{});
}
```

**验收标准**:
- [ ] 命令参数解析正确
- [ ] 支持所有配置选项
- [ ] 回测正常运行
- [ ] 输出格式清晰美观
- [ ] 错误处理完善

---

### Task 3: 实现 `strategy optimize` 命令 (4小时)

**文件**: `src/cli/strategy.zig` (Part 3)

**命令格式**:
```bash
zigquant strategy optimize [options]

Options:
  -s, --strategy <name>      Strategy name (required)
  -p, --pair <pair>          Trading pair
  -t, --timeframe <tf>       Timeframe
  -S, --start <time>         Start time
  -E, --end <time>           End time
  -c, --config <file>        Config file (defines parameter ranges)
  -O, --objective <obj>      Optimization objective (sharpe|profit|winrate)
  -o, --output <format>      Output format (table|json|csv)
  -f, --file <path>          Save report to file
  --top <n>                  Show top N results (default: 10)
  --max-combinations <n>     Max combinations to test
  -h, --help                 Show help
```

**实现内容**:
```zig
pub const OptimizeCommandConfig = struct {
    strategy_name: []const u8,
    pair: []const u8,
    timeframe: []const u8,
    start_time: []const u8,
    end_time: []const u8,
    config_file: ?[]const u8,
    objective: OptimizationObjective,
    output_format: OutputFormat,
    output_file: ?[]const u8,
    top_n: u32,
    max_combinations: ?u32,
};

fn runOptimize(self: *StrategyCommands, args: []const []const u8) !void {
    // 1. 解析参数
    const config = try self.parseOptimizeArgs(args);

    // 2. 加载策略和参数范围
    self.logger.info("Loading strategy: {s}", .{config.strategy_name});
    const strategy_meta = try self.loadStrategyMetadata(config.strategy_name);
    const param_ranges = try self.loadParameterRanges(config.config_file);

    // 3. 准备优化器
    var backtest_engine = try BacktestEngine.init(/* ... */);
    defer backtest_engine.deinit();

    var optimizer = GridSearchOptimizer.init(
        self.allocator,
        self.logger,
        &backtest_engine,
    );
    defer optimizer.deinit();

    // 4. 构建优化配置
    const backtest_config = BacktestConfig{
        .pair = try TradingPair.parse(config.pair),
        .timeframe = try Timeframe.parse(config.timeframe),
        .start_time = try Timestamp.parse(config.start_time),
        .end_time = try Timestamp.parse(config.end_time),
        .initial_capital = try Decimal.fromFloat(10000.0),
        .commission_rate = try Decimal.fromFloat(0.001),
    };

    const opt_config = OptimizationConfig{
        .objective = config.objective,
        .backtest_config = backtest_config,
        .parameters = param_ranges,
        .max_combinations = config.max_combinations,
        .enable_parallel = false,
    };

    // 5. 运行优化
    self.logger.info("Starting optimization...", .{});
    const start = std.time.milliTimestamp();

    const strategy_factory = struct {
        fn create(params: ParameterSet) !IStrategy {
            // 根据参数创建策略实例
        }
    }.create;

    const result = try optimizer.optimize(strategy_factory, opt_config);
    defer result.deinit();

    const elapsed = std.time.milliTimestamp() - start;
    self.logger.info("Optimization completed in {d}ms", .{elapsed});

    // 6. 输出结果
    try self.printOptimizationResult(result, config);

    // 7. 保存到文件
    if (config.output_file) |file_path| {
        try self.saveOptimizationResult(result, file_path, config.output_format);
        self.logger.info("Report saved to: {s}", .{file_path});
    }
}

fn printOptimizationResult(
    self: *StrategyCommands,
    result: OptimizationResult,
    config: OptimizeCommandConfig,
) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n", .{});
    try stdout.print("═══════════════════════════════════════════════════\n", .{});
    try stdout.print("          Optimization Results\n", .{});
    try stdout.print("═══════════════════════════════════════════════════\n", .{});
    try stdout.print("\n", .{});
    try stdout.print("Total Combinations Tested: {d}\n", .{result.total_combinations});
    try stdout.print("Elapsed Time: {d}ms\n", .{result.elapsed_time_ms});
    try stdout.print("\n", .{});

    try stdout.print("Best Parameters:\n", .{});
    try stdout.print("─────────────────────────────────────────────────\n", .{});

    var iter = result.best_params.values.iterator();
    while (iter.next()) |entry| {
        try stdout.print("  {s}: ", .{entry.key_ptr.*});
        switch (entry.value_ptr.*) {
            .integer => |v| try stdout.print("{d}\n", .{v}),
            .decimal => |v| try stdout.print("{s}\n", .{v.toString()}),
            .boolean => |v| try stdout.print("{}\n", .{v}),
            .string => |v| try stdout.print("{s}\n", .{v}),
        }
    }

    try stdout.print("\n", .{});
    try stdout.print("Best Score: {d:.4}\n", .{result.best_score});
    try stdout.print("\n", .{});

    // 显示 Top N 结果
    try stdout.print("Top {d} Results:\n", .{config.top_n});
    try stdout.print("─────────────────────────────────────────────────\n", .{});
    // ... 表格形式输出 Top N

    try stdout.print("═══════════════════════════════════════════════════\n", .{});
}
```

**验收标准**:
- [ ] 命令参数解析正确
- [ ] 优化器集成正常
- [ ] 进度显示清晰
- [ ] 结果展示完整
- [ ] 支持多种输出格式

---

### Task 4: 实现 `strategy list` 命令 (2小时)

**文件**: `src/cli/strategy.zig` (Part 4)

**命令格式**:
```bash
zigquant strategy list [options]

Options:
  -t, --type <type>          Filter by strategy type
  -o, --output <format>      Output format (table|json)
  -v, --verbose              Show detailed information
  -h, --help                 Show help
```

**实现内容**:
```zig
pub const ListCommandConfig = struct {
    filter_type: ?StrategyType,
    output_format: OutputFormat,
    verbose: bool,
};

fn listStrategies(self: *StrategyCommands, args: []const []const u8) !void {
    const config = try self.parseListArgs(args);

    // 1. 获取所有可用策略
    const strategies = try self.getAvailableStrategies();
    defer self.allocator.free(strategies);

    // 2. 过滤策略
    var filtered = std.ArrayList(StrategyInfo).init(self.allocator);
    defer filtered.deinit();

    for (strategies) |strategy| {
        if (config.filter_type) |filter| {
            if (strategy.type == filter) {
                try filtered.append(strategy);
            }
        } else {
            try filtered.append(strategy);
        }
    }

    // 3. 输出策略列表
    switch (config.output_format) {
        .table => try self.printStrategyListTable(filtered.items, config.verbose),
        .json => try self.printStrategyListJson(filtered.items, config.verbose),
        else => unreachable,
    }
}

fn printStrategyListTable(
    self: *StrategyCommands,
    strategies: []const StrategyInfo,
    verbose: bool,
) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n", .{});
    try stdout.print("Available Strategies:\n", .{});
    try stdout.print("═══════════════════════════════════════════════════\n", .{});

    if (!verbose) {
        // 简洁模式
        try stdout.print("{s:<20} {s:<15} {s:<10}\n", .{"Name", "Type", "Version"});
        try stdout.print("─────────────────────────────────────────────────\n", .{});

        for (strategies) |strategy| {
            try stdout.print("{s:<20} {s:<15} {s:<10}\n", .{
                strategy.name,
                @tagName(strategy.type),
                strategy.version,
            });
        }
    } else {
        // 详细模式
        for (strategies) |strategy| {
            try stdout.print("\n", .{});
            try stdout.print("Name:        {s}\n", .{strategy.name});
            try stdout.print("Version:     {s}\n", .{strategy.version});
            try stdout.print("Author:      {s}\n", .{strategy.author});
            try stdout.print("Type:        {s}\n", .{@tagName(strategy.type)});
            try stdout.print("Description: {s}\n", .{strategy.description});
            try stdout.print("Parameters:\n", .{});
            for (strategy.parameters) |param| {
                try stdout.print("  - {s} ({s})\n", .{param.name, @tagName(param.type)});
            }
            try stdout.print("─────────────────────────────────────────────────\n", .{});
        }
    }

    try stdout.print("\n", .{});
    try stdout.print("Total: {d} strategies\n", .{strategies.len});
    try stdout.print("═══════════════════════════════════════════════════\n", .{});
}

pub const StrategyInfo = struct {
    name: []const u8,
    version: []const u8,
    author: []const u8,
    type: StrategyType,
    description: []const u8,
    parameters: []ParameterInfo,
};

pub const ParameterInfo = struct {
    name: []const u8,
    type: ParameterType,
    default_value: ParameterValue,
};
```

**验收标准**:
- [ ] 能正确列出所有内置策略
- [ ] 类型过滤功能正常
- [ ] 输出格式清晰
- [ ] 详细模式显示完整信息

---

### Task 5: 添加配置文件支持 (2小时)

**配置文件格式**: TOML

**示例配置**: `strategy_config.toml`
```toml
[strategy]
name = "DualMA"
version = "1.0.0"

[strategy.parameters]
fast_period = 10
slow_period = 20

[backtest]
pair = "BTC-USDT"
timeframe = "15m"
start_time = "2024-01-01T00:00:00Z"
end_time = "2024-12-31T23:59:59Z"
initial_capital = 10000.0
commission_rate = 0.001

[optimization]
objective = "maximize_sharpe_ratio"
max_combinations = 1000

[optimization.parameters.fast_period]
min = 5
max = 20
step = 5

[optimization.parameters.slow_period]
min = 20
max = 50
step = 10
```

**实现内容**:
```zig
/// 配置文件加载器
pub const ConfigLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConfigLoader {
        return .{ .allocator = allocator };
    }

    pub fn loadBacktestConfig(self: *ConfigLoader, file_path: []const u8) !BacktestCommandConfig {
        // 使用 TOML 解析器加载配置
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        // 解析 TOML
        // ... 返回配置
    }

    pub fn loadOptimizationConfig(self: *ConfigLoader, file_path: []const u8) !OptimizeCommandConfig {
        // 类似实现
    }
};
```

**验收标准**:
- [ ] 能正确解析 TOML 配置文件
- [ ] 配置文件参数优先于命令行默认值
- [ ] 命令行参数覆盖配置文件
- [ ] 配置文件格式验证

---

### Task 6: 编写 CLI 测试 (3小时)

**文件**: `src/cli/strategy_test.zig`

**测试内容**:
```zig
const std = @import("std");
const testing = std.testing;
const StrategyCommands = @import("strategy.zig").StrategyCommands;

test "CLI: backtest 命令参数解析" {
    const allocator = testing.allocator;
    var logger = try Logger.init(allocator, .info);
    defer logger.deinit();

    var commands = StrategyCommands.init(allocator, logger);
    defer commands.deinit();

    const args = [_][]const u8{
        "backtest",
        "--strategy", "DualMA",
        "--pair", "BTC-USDT",
        "--timeframe", "15m",
        "--start", "2024-01-01T00:00:00Z",
        "--end", "2024-12-31T23:59:59Z",
        "--output", "table",
    };

    // 测试参数解析
    const config = try commands.parseBacktestArgs(args[1..]);

    try testing.expectEqualStrings("DualMA", config.strategy_name);
    try testing.expectEqualStrings("BTC-USDT", config.pair);
    try testing.expectEqualStrings("15m", config.timeframe);
}

test "CLI: optimize 命令参数解析" {
    // 测试优化命令参数解析
}

test "CLI: list 命令" {
    // 测试策略列表命令
}

test "CLI: 配置文件加载" {
    // 测试配置文件加载
}

test "CLI: 输出格式" {
    // 测试不同输出格式
}

test "CLI: 错误处理" {
    // 测试缺少必需参数
    // 测试无效参数
    // 测试文件不存在
}
```

**验收标准**:
- [ ] 所有测试用例通过
- [ ] 测试覆盖率 > 80%
- [ ] 参数解析测试完整
- [ ] 错误处理测试完整

---

### Task 7: 文档和集成 (1小时)

**文档更新**:
- 更新 `/home/davirain/dev/zigQuant/docs/features/cli/strategy_commands.md`
- 添加命令使用示例
- 添加配置文件示例
- 更新主 README.md

**CLI 帮助文档**:
```zig
fn printBacktestHelp(self: *StrategyCommands) !void {
    const help_text =
        \\Usage: zigquant strategy backtest [options]
        \\
        \\Run a strategy backtest on historical data.
        \\
        \\Options:
        \\  -s, --strategy <name>      Strategy name (required)
        \\  -p, --pair <pair>          Trading pair (default: BTC-USDT)
        \\  -t, --timeframe <tf>       Timeframe (default: 15m)
        \\  -S, --start <time>         Start time (ISO 8601)
        \\  -E, --end <time>           End time (ISO 8601)
        \\  -c, --config <file>        Load config from file
        \\  -o, --output <format>      Output format: table|json|csv (default: table)
        \\  -f, --file <path>          Save report to file
        \\  --capital <amount>         Initial capital (default: 10000)
        \\  --commission <rate>        Commission rate (default: 0.001)
        \\  -h, --help                 Show this help message
        \\
        \\Examples:
        \\  # Basic backtest
        \\  zigquant strategy backtest --strategy DualMA --pair BTC-USDT
        \\
        \\  # Backtest with custom parameters
        \\  zigquant strategy backtest -s DualMA -p ETH-USDT -t 1h \
        \\    --start 2024-01-01T00:00:00Z --end 2024-06-30T23:59:59Z
        \\
        \\  # Use config file
        \\  zigquant strategy backtest -c strategy_config.toml
        \\
        \\  # Save report to file
        \\  zigquant strategy backtest -s DualMA -o json -f report.json
    ;
    try self.logger.info(help_text, .{});
}
```

**验收标准**:
- [ ] 帮助文档完整清晰
- [ ] 使用示例准确
- [ ] CLI 文档更新
- [ ] README 更新

---

## ✅ 验收标准

### 功能验收
- [ ] `strategy backtest` 命令可用
- [ ] `strategy optimize` 命令可用
- [ ] `strategy list` 命令可用
- [ ] 配置文件支持正常
- [ ] 多种输出格式正确

### 用户体验验收
- [ ] 命令直观易用
- [ ] 帮助文档完整
- [ ] 错误提示清晰友好
- [ ] 输出格式美观

### 代码质量
- [ ] 代码符合项目规范
- [ ] 所有函数有文档注释
- [ ] 无编译警告
- [ ] 通过 `zig fmt` 检查

### 测试验收
- [ ] CLI 测试覆盖率 > 80%
- [ ] 所有测试通过
- [ ] 集成测试通过
- [ ] 端到端测试通过

### 性能验收
- [ ] 命令响应时间 < 200ms
- [ ] 参数解析高效
- [ ] 无内存泄漏

---

## 🔗 依赖关系

### 依赖项
- **Story 020**: BacktestEngine 回测引擎（必须完成）
- **Story 022**: GridSearchOptimizer 优化器（必须完成）
- **Story 013-019**: 策略接口和内置策略（必须完成）
- `src/cli/`: CLI 基础框架
- TOML 解析库（如 `zig-toml`）

### 被依赖项
- **Story 024**: 示例和文档（依赖本 Story）

---

## 🧪 测试策略

### 单元测试
- **参数解析测试**
  - 正常参数解析
  - 缺少必需参数
  - 无效参数值
  - 参数冲突

- **配置加载测试**
  - TOML 配置解析
  - 配置文件不存在
  - 配置格式错误
  - 参数优先级

- **输出格式测试**
  - 表格格式
  - JSON 格式
  - CSV 格式

### 集成测试
- 端到端回测流程
- 端到端优化流程
- 策略列表查看
- 配置文件集成

### 用户场景测试
- 新手使用场景
- 高级用户场景
- 错误恢复场景
- 批处理场景

---

## 📚 参考资料

### 外部参考
- [Freqtrade CLI](https://www.freqtrade.io/en/stable/bot-usage/): CLI 设计参考
- [Clap Library](https://github.com/Hejsil/zig-clap): Zig 命令行参数解析
- [TOML Format](https://toml.io/): TOML 配置文件格式

### 内部参考
- `docs/features/cli/README.md`: CLI 框架文档
- `docs/features/backtest/engine.md`: 回测引擎文档
- `docs/features/strategy/interface.md`: 策略接口文档

---

## 📊 进度追踪

### 检查清单
- [ ] Task 1: 创建 CLI 策略模块基础结构（2小时）
- [ ] Task 2: 实现 strategy backtest 命令（4小时）
- [ ] Task 3: 实现 strategy optimize 命令（4小时）
- [ ] Task 4: 实现 strategy list 命令（2小时）
- [ ] Task 5: 添加配置文件支持（2小时）
- [ ] Task 6: 编写 CLI 测试（3小时）
- [ ] Task 7: 文档和集成（1小时）

### 总计工作量
- **开发时间**: 14 小时
- **测试时间**: 3 小时
- **文档时间**: 1 小时
- **总计**: 18 小时（约 2 天）

---

## 🔄 后续改进

### v0.4.0 可能的增强
- [ ] 交互式模式
- [ ] 实时进度条
- [ ] 彩色输出
- [ ] Shell 自动补全
- [ ] 回测结果可视化（图表）
- [ ] 策略性能对比工具
- [ ] 批量回测支持

---

## 📝 备注

### 技术选择
- 使用 `zig-clap` 库进行参数解析
- 使用 TOML 作为配置文件格式
- 使用表格输出提供最佳可读性

### 风险与缓解
- **风险**: TOML 库可能不够成熟
  - **缓解**: 准备 JSON 配置文件作为备选方案

- **风险**: 复杂的参数组合可能导致用户困惑
  - **缓解**: 提供详细帮助和常见用例示例

---

**创建时间**: 2025-12-25
**预计开始**: Week 3 Day 3
**预计完成**: Week 3 Day 4
**实际开始**:
**实际完成**:

---

Generated with [Claude Code](https://claude.com/claude-code)
