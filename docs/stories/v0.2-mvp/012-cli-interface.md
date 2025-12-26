# Story: CLI 界面

**ID**: `STORY-012`
**版本**: `v0.2`
**创建日期**: 2025-12-23
**状态**: 📋 计划中
**优先级**: P0 (必须)
**预计工时**: 3 天

---

## 📋 需求描述

### 用户故事
作为**量化交易开发者**，我希望**有一个命令行界面（CLI）**，以便**快速测试交易功能并监控系统状态**。

### 背景
CLI 是 MVP 阶段的主要用户界面，提供：
- 查询市场数据（订单簿、价格）
- 下单和撤单操作
- 查询账户和仓位信息
- 监控订单状态
- 系统配置和测试

CLI 应该：
- 简单易用
- 支持交互式和脚本模式
- 提供清晰的输出格式
- 错误提示友好

### 范围
- **包含**:
  - 命令行参数解析
  - 子命令系统（market, order, position, account）
  - 交互式 REPL 模式
  - 表格化输出
  - 配置文件加载
  - 彩色输出

- **不包含**:
  - GUI 界面
  - Web 界面
  - 图表可视化

---

## 🎯 验收标准

- [ ] CLI 框架实现完成
- [ ] 支持所有核心命令（market, order, position, account）
- [ ] 支持交互式模式（REPL）
- [ ] 支持脚本模式（批处理）
- [ ] 输出格式清晰（表格）
- [ ] 错误处理友好
- [ ] 配置文件加载正常
- [ ] 帮助文档完整

---

## 🔧 技术设计

### 架构概览

```
src/cli/
├── main.zig              # CLI 入口
├── commands/
│   ├── market.zig        # 市场数据命令
│   ├── order.zig         # 订单命令
│   ├── position.zig      # 仓位命令
│   └── account.zig       # 账户命令
├── repl.zig              # 交互式模式
├── format.zig            # 输出格式化
└── cli_test.zig          # 测试
```

### 命令结构

```
zigquant [OPTIONS] <COMMAND>

Commands:
  market      市场数据命令
  order       订单命令
  position    仓位命令
  account     账户命令
  config      配置命令
  repl        交互式模式

Options:
  -c, --config <PATH>   配置文件路径
  -v, --verbose         详细输出
  -h, --help            显示帮助
```

### 核心实现

#### 1. CLI 主程序

```zig
// src/cli/main.zig

const std = @import("std");
const clap = @import("clap"); // zig-clap 库
const Config = @import("../core/config.zig").AppConfig;
const Logger = @import("../core/logger.zig").Logger;
const HyperliquidClient = @import("../exchange/hyperliquid/http.zig").HyperliquidClient;
const OrderManager = @import("../trading/order_manager.zig").OrderManager;
const PositionTracker = @import("../trading/position_tracker.zig").PositionTracker;

const commands = struct {
    const market = @import("commands/market.zig");
    const order = @import("commands/order.zig");
    const position = @import("commands/position.zig");
    const account = @import("commands/account.zig");
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 解析命令行参数
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             显示帮助
        \\-c, --config <str>     配置文件路径
        \\-v, --verbose          详细输出
        \\<str>                  命令
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try printHelp();
        return;
    }

    // 加载配置
    const config_path = res.args.config orelse "config.toml";
    const config = try Config.loadFromFile(allocator, config_path);
    defer config.deinit();

    // 初始化 Logger
    var logger = try Logger.init(allocator, config.logging);
    defer logger.deinit();

    // 初始化客户端
    var http_client = try HyperliquidClient.init(allocator, config.exchange, logger);
    defer http_client.deinit();

    // 解析命令
    const args = res.positionals;
    if (args.len == 0) {
        std.debug.print("Error: No command specified. Use --help for usage.\n", .{});
        return;
    }

    const command = args[0];

    if (std.mem.eql(u8, command, "market")) {
        try commands.market.run(allocator, &http_client, args[1..]);
    } else if (std.mem.eql(u8, command, "order")) {
        try commands.order.run(allocator, &http_client, args[1..]);
    } else if (std.mem.eql(u8, command, "position")) {
        try commands.position.run(allocator, &http_client, args[1..]);
    } else if (std.mem.eql(u8, command, "account")) {
        try commands.account.run(allocator, &http_client, args[1..]);
    } else if (std.mem.eql(u8, command, "repl")) {
        try runRepl(allocator, &http_client, logger);
    } else {
        std.debug.print("Error: Unknown command '{s}'\n", .{command});
        try printHelp();
    }
}

fn printHelp() !void {
    const help_text =
        \\ZigQuant CLI - Quantitative Trading Framework
        \\
        \\Usage: zigquant [OPTIONS] <COMMAND>
        \\
        \\Commands:
        \\  market      查询市场数据
        \\  order       订单操作
        \\  position    查询仓位
        \\  account     查询账户
        \\  repl        交互式模式
        \\
        \\Options:
        \\  -c, --config <PATH>   配置文件路径 (默认: config.toml)
        \\  -v, --verbose         详细输出
        \\  -h, --help            显示帮助
        \\
        \\Examples:
        \\  zigquant market ticker ETH
        \\  zigquant order buy ETH 1.0 2000.0
        \\  zigquant position list
        \\  zigquant repl
        \\
    ;

    try std.io.getStdOut().writeAll(help_text);
}

fn runRepl(
    allocator: std.mem.Allocator,
    http_client: *HyperliquidClient,
    logger: Logger,
) !void {
    const repl = @import("repl.zig");
    try repl.run(allocator, http_client, logger);
}
```

#### 2. Market 命令

```zig
// src/cli/commands/market.zig

const std = @import("std");
const HyperliquidClient = @import("../../exchange/hyperliquid/http.zig").HyperliquidClient;
const InfoAPI = @import("../../exchange/hyperliquid/info_api.zig");
const format = @import("../format.zig");

pub fn run(
    allocator: std.mem.Allocator,
    client: *HyperliquidClient,
    args: []const []const u8,
) !void {
    if (args.len == 0) {
        try printHelp();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "ticker")) {
        try ticker(allocator, client, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "orderbook")) {
        try orderbook(allocator, client, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "trades")) {
        try trades(allocator, client, args[1..]);
    } else {
        std.debug.print("Error: Unknown subcommand '{s}'\n", .{subcommand});
        try printHelp();
    }
}

fn ticker(
    allocator: std.mem.Allocator,
    client: *HyperliquidClient,
    args: []const []const u8,
) !void {
    if (args.len < 1) {
        std.debug.print("Usage: zigquant market ticker <SYMBOL>\n", .{});
        return;
    }

    const symbol = args[0];

    const ob = try InfoAPI.getOrderBook(client, symbol);
    defer allocator.free(ob.bids);
    defer allocator.free(ob.asks);

    const best_bid = if (ob.bids.len > 0) ob.bids[0] else null;
    const best_ask = if (ob.asks.len > 0) ob.asks[0] else null;

    std.debug.print("\n=== {s} Ticker ===\n", .{symbol});
    if (best_bid) |bid| {
        std.debug.print("Best Bid: {} @ {}\n", .{
            bid.size.toFloat(), bid.price.toFloat(),
        });
    }
    if (best_ask) |ask| {
        std.debug.print("Best Ask: {} @ {}\n", .{
            ask.size.toFloat(), ask.price.toFloat(),
        });
    }
    if (best_bid != null and best_ask != null) {
        const mid = best_bid.?.price.add(best_ask.?.price).div(Decimal.fromInt(2)) catch unreachable;
        std.debug.print("Mid Price: {}\n", .{mid.toFloat()});
    }
    std.debug.print("\n", .{});
}

fn orderbook(
    allocator: std.mem.Allocator,
    client: *HyperliquidClient,
    args: []const []const u8,
) !void {
    if (args.len < 1) {
        std.debug.print("Usage: zigquant market orderbook <SYMBOL> [DEPTH]\n", .{});
        return;
    }

    const symbol = args[0];
    const depth: usize = if (args.len > 1)
        try std.fmt.parseInt(usize, args[1], 10)
    else
        10;

    const ob = try InfoAPI.getOrderBook(client, symbol);
    defer allocator.free(ob.bids);
    defer allocator.free(ob.asks);

    std.debug.print("\n=== {s} Order Book (Depth: {}) ===\n\n", .{ symbol, depth });

    // 打印 Asks (从低到高)
    std.debug.print("Asks:\n", .{});
    const ask_count = @min(depth, ob.asks.len);
    var i: usize = ask_count;
    while (i > 0) {
        i -= 1;
        const ask = ob.asks[i];
        std.debug.print("  {} @ {}\n", .{ ask.size.toFloat(), ask.price.toFloat() });
    }

    std.debug.print("\n", .{});

    // 打印 Bids (从高到低)
    std.debug.print("Bids:\n", .{});
    const bid_count = @min(depth, ob.bids.len);
    for (ob.bids[0..bid_count]) |bid| {
        std.debug.print("  {} @ {}\n", .{ bid.size.toFloat(), bid.price.toFloat() });
    }

    std.debug.print("\n", .{});
}

fn printHelp() !void {
    const help_text =
        \\Market Commands:
        \\  ticker <SYMBOL>             显示最优买卖价
        \\  orderbook <SYMBOL> [DEPTH]  显示订单簿
        \\  trades <SYMBOL> [LIMIT]     显示最近成交
        \\
    ;
    try std.io.getStdOut().writeAll(help_text);
}
```

#### 3. Order 命令

```zig
// src/cli/commands/order.zig

const std = @import("std");
const HyperliquidClient = @import("../../exchange/hyperliquid/http.zig").HyperliquidClient;
const OrderManager = @import("../../trading/order_manager.zig").OrderManager;
const OrderBuilder = @import("../../core/order.zig").OrderBuilder;
const Decimal = @import("../../core/decimal.zig").Decimal;

pub fn run(
    allocator: std.mem.Allocator,
    client: *HyperliquidClient,
    args: []const []const u8,
) !void {
    if (args.len == 0) {
        try printHelp();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "buy")) {
        try buy(allocator, client, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "sell")) {
        try sell(allocator, client, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "cancel")) {
        try cancel(allocator, client, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        try list(allocator, client, args[1..]);
    } else {
        std.debug.print("Error: Unknown subcommand '{s}'\n", .{subcommand});
        try printHelp();
    }
}

fn buy(
    allocator: std.mem.Allocator,
    client: *HyperliquidClient,
    args: []const []const u8,
) !void {
    if (args.len < 3) {
        std.debug.print("Usage: zigquant order buy <SYMBOL> <QUANTITY> <PRICE>\n", .{});
        return;
    }

    const symbol = args[0];
    const quantity = try Decimal.fromString(args[1]);
    const price = try Decimal.fromString(args[2]);

    var builder = try OrderBuilder.init(allocator, symbol, .buy);
    var order = try builder
        .withPrice(price)
        .withQuantity(quantity)
        .build();
    defer order.deinit();

    // TODO: 使用 OrderManager 提交订单
    std.debug.print("Placing BUY order: {s} {} @ {}\n", .{
        symbol, quantity.toFloat(), price.toFloat(),
    });
}

fn printHelp() !void {
    const help_text =
        \\Order Commands:
        \\  buy <SYMBOL> <QTY> <PRICE>      下限价买单
        \\  sell <SYMBOL> <QTY> <PRICE>     下限价卖单
        \\  cancel <ORDER_ID>               撤单
        \\  list                            列出所有订单
        \\
    ;
    try std.io.getStdOut().writeAll(help_text);
}
```

#### 4. REPL 交互式模式

```zig
// src/cli/repl.zig

const std = @import("std");
const HyperliquidClient = @import("../exchange/hyperliquid/http.zig").HyperliquidClient;
const Logger = @import("../core/logger.zig").Logger;

pub fn run(
    allocator: std.mem.Allocator,
    client: *HyperliquidClient,
    logger: Logger,
) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("ZigQuant REPL - Type 'help' for commands, 'exit' to quit\n\n");

    var buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.writeAll("zigquant> ");

        const line = (try stdin.readUntilDelimiterOrEof(&buffer, '\n')) orelse break;
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        if (trimmed.len == 0) continue;

        if (std.mem.eql(u8, trimmed, "exit") or std.mem.eql(u8, trimmed, "quit")) {
            break;
        }

        if (std.mem.eql(u8, trimmed, "help")) {
            try printReplHelp(stdout);
            continue;
        }

        // 解析命令
        var iter = std.mem.split(u8, trimmed, " ");
        var args = std.ArrayList([]const u8).init(allocator);
        defer args.deinit();

        while (iter.next()) |arg| {
            try args.append(arg);
        }

        if (args.items.len == 0) continue;

        // 执行命令
        executeCommand(allocator, client, logger, args.items) catch |err| {
            try stdout.print("Error: {}\n", .{err});
        };
    }

    try stdout.writeAll("Goodbye!\n");
}

fn printReplHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Available commands:
        \\  market ticker <SYMBOL>
        \\  order buy <SYMBOL> <QTY> <PRICE>
        \\  position list
        \\  account info
        \\  help
        \\  exit
        \\
    );
}

fn executeCommand(
    allocator: std.mem.Allocator,
    client: *HyperliquidClient,
    logger: Logger,
    args: []const []const u8,
) !void {
    _ = logger;

    const commands_pkg = struct {
        const market = @import("commands/market.zig");
        const order = @import("commands/order.zig");
        const position = @import("commands/position.zig");
        const account = @import("commands/account.zig");
    };

    const command = args[0];

    if (std.mem.eql(u8, command, "market")) {
        try commands_pkg.market.run(allocator, client, args[1..]);
    } else if (std.mem.eql(u8, command, "order")) {
        try commands_pkg.order.run(allocator, client, args[1..]);
    } else if (std.mem.eql(u8, command, "position")) {
        try commands_pkg.position.run(allocator, client, args[1..]);
    } else if (std.mem.eql(u8, command, "account")) {
        try commands_pkg.account.run(allocator, client, args[1..]);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
    }
}
```

---

## 📝 任务分解

### Phase 1: CLI 框架 📋
- [ ] 任务 1.1: 选择命令行解析库（zig-clap）
- [ ] 任务 1.2: 实现主程序入口
- [ ] 任务 1.3: 实现命令路由
- [ ] 任务 1.4: 实现配置加载

### Phase 2: 核心命令 📋
- [ ] 任务 2.1: 实现 market 命令
- [ ] 任务 2.2: 实现 order 命令
- [ ] 任务 2.3: 实现 position 命令
- [ ] 任务 2.4: 实现 account 命令

### Phase 3: REPL 模式 📋
- [ ] 任务 3.1: 实现 REPL 循环
- [ ] 任务 3.2: 实现命令解析
- [ ] 任务 3.3: 实现命令执行
- [ ] 任务 3.4: 实现自动补全（可选）

### Phase 4: 输出格式化 📋
- [ ] 任务 4.1: 实现表格输出
- [ ] 任务 4.2: 实现彩色输出
- [ ] 任务 4.3: 实现进度条（可选）

### Phase 5: 测试与文档 📋
- [ ] 任务 5.1: 编写命令测试
- [ ] 任务 5.2: 编写 REPL 测试
- [ ] 任务 5.3: 编写用户手册
- [ ] 任务 5.4: 录制演示视频
- [ ] 任务 5.5: 代码审查

---

## 🧪 测试策略

### 集成测试

```bash
# 测试 market 命令
$ zigquant market ticker ETH
$ zigquant market orderbook BTC 5

# 测试 order 命令
$ zigquant order buy ETH 0.1 2000.0
$ zigquant order list

# 测试 REPL 模式
$ zigquant repl
zigquant> market ticker ETH
zigquant> order buy ETH 0.1 2000.0
zigquant> exit
```

---

## 📚 相关文档

### 设计文档
- [ ] `docs/cli/README.md` - CLI 使用指南
- [ ] `docs/cli/commands.md` - 命令参考
- [ ] `docs/cli/examples.md` - 使用示例

### 参考资料
- [zig-clap](https://github.com/Hejsil/zig-clap) - 命令行解析库

---

## 🔗 依赖关系

### 前置条件
- [x] Story 001-005: 基础组件
- [ ] Story 006-011: 交易功能

### 被依赖
- 无（CLI 是终端用户界面）

---

## ⚠️ 风险与挑战

### 已识别风险
1. **用户体验**: CLI 可能不够直观
   - **影响**: 中
   - **缓解措施**: 提供详细帮助和示例

### 技术挑战
1. **命令解析**: 复杂参数解析
   - **解决方案**: 使用成熟的 zig-clap 库

---

## 📊 进度追踪

### 时间线
- 开始日期: 待定
- 预计完成: 待定

---

## ✅ 验收检查清单

- [ ] 所有验收标准已满足
- [ ] 所有任务已完成
- [ ] CLI 测试通过
- [ ] 用户手册完成
- [ ] 代码已审查

---

## 📸 演示

### 使用示例

```bash
# 查询 ETH 价格
$ zigquant market ticker ETH
=== ETH Ticker ===
Best Bid: 10.5 @ 2145.23
Best Ask: 8.2 @ 2145.67
Mid Price: 2145.45

# 查询订单簿
$ zigquant market orderbook BTC 5
=== BTC Order Book (Depth: 5) ===

Asks:
  1.2 @ 50105.5
  0.8 @ 50104.0
  2.5 @ 50103.2
  1.5 @ 50102.8
  3.0 @ 50101.5

Bids:
  2.0 @ 50100.0
  1.5 @ 50099.5
  0.9 @ 50098.2
  2.2 @ 50097.0
  1.8 @ 50096.5

# 下单
$ zigquant order buy ETH 0.1 2000.0
Placing BUY order: ETH 0.1 @ 2000.0
Order submitted: CLIENT_1640000000000_12345

# 交互式模式
$ zigquant repl
ZigQuant REPL - Type 'help' for commands, 'exit' to quit

zigquant> market ticker ETH
=== ETH Ticker ===
Best Bid: 10.5 @ 2145.23
Best Ask: 8.2 @ 2145.67

zigquant> order buy ETH 0.1 2000.0
Order submitted successfully!

zigquant> position list
Symbol  | Side | Size | Entry Price | PnL
--------|------|------|-------------|-----
ETH     | LONG | 1.0  | 2100.0      | +50.5
BTC     | LONG | 0.1  | 50000.0     | +100.0

zigquant> exit
Goodbye!
```

---

## 💡 未来改进

- [ ] 支持彩色输出
- [ ] 实现自动补全
- [ ] 添加历史命令
- [ ] 支持脚本批处理
- [ ] 添加进度条和加载动画

---

*Last updated: 2025-12-23*
*Assignee: TBD*
*Status: 📋 Planning*
