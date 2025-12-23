# CLI 界面 - 实现细节

> 深入了解 CLI 命令行界面的内部实现

**最后更新**: 2025-12-23

---

## 架构概览

### 目录结构

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

### 模块依赖

```
main.zig
  ├─> zig-clap (参数解析)
  ├─> core/config.zig (配置管理)
  ├─> core/logger.zig (日志)
  ├─> exchange/hyperliquid/http.zig (HTTP 客户端)
  ├─> commands/*.zig (子命令)
  └─> repl.zig (交互模式)
```

---

## CLI 框架实现

### 1. 主程序入口

#### 参数解析

使用 `zig-clap` 库进行命令行参数解析：

```zig
// src/cli/main.zig

const std = @import("std");
const clap = @import("clap");
const Config = @import("../core/config.zig").AppConfig;
const Logger = @import("../core/logger.zig").Logger;
const HyperliquidClient = @import("../exchange/hyperliquid/http.zig").HyperliquidClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 定义参数结构
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             显示帮助
        \\-c, --config <str>     配置文件路径
        \\-v, --verbose          详细输出
        \\<str>                  命令
    );

    // 解析参数
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    // 处理帮助选项
    if (res.args.help != 0) {
        try printHelp();
        return;
    }

    // 加载配置
    const config_path = res.args.config orelse "config.toml";
    const config = try Config.loadFromFile(allocator, config_path);
    defer config.deinit();

    // 初始化组件
    var logger = try Logger.init(allocator, config.logging);
    defer logger.deinit();

    var http_client = try HyperliquidClient.init(allocator, config.exchange, logger);
    defer http_client.deinit();

    // 命令路由
    try routeCommand(allocator, &http_client, logger, res.positionals);
}
```

#### 命令路由

```zig
fn routeCommand(
    allocator: std.mem.Allocator,
    http_client: *HyperliquidClient,
    logger: Logger,
    args: []const []const u8,
) !void {
    if (args.len == 0) {
        std.debug.print("Error: No command specified. Use --help for usage.\n", .{});
        return;
    }

    const command = args[0];

    const commands = struct {
        const market = @import("commands/market.zig");
        const order = @import("commands/order.zig");
        const position = @import("commands/position.zig");
        const account = @import("commands/account.zig");
    };

    if (std.mem.eql(u8, command, "market")) {
        try commands.market.run(allocator, http_client, args[1..]);
    } else if (std.mem.eql(u8, command, "order")) {
        try commands.order.run(allocator, http_client, args[1..]);
    } else if (std.mem.eql(u8, command, "position")) {
        try commands.position.run(allocator, http_client, args[1..]);
    } else if (std.mem.eql(u8, command, "account")) {
        try commands.account.run(allocator, http_client, args[1..]);
    } else if (std.mem.eql(u8, command, "repl")) {
        try runRepl(allocator, http_client, logger);
    } else {
        std.debug.print("Error: Unknown command '{s}'\n", .{command});
        try printHelp();
    }
}
```

---

## 核心命令实现

### 2. Market 命令

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
```

### 3. Order 命令

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
```

---

## REPL 模式实现

### 4. 交互式循环

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

## 输出格式化

### 表格输出

```zig
// src/cli/format.zig

const std = @import("std");

pub fn printTable(
    writer: anytype,
    headers: []const []const u8,
    rows: []const []const []const u8,
) !void {
    // 计算列宽
    var col_widths = try std.ArrayList(usize).initCapacity(
        std.heap.page_allocator,
        headers.len,
    );
    defer col_widths.deinit();

    for (headers) |header| {
        try col_widths.append(header.len);
    }

    // 打印表头
    for (headers, 0..) |header, i| {
        try writer.print("{s}", .{header});
        if (i < headers.len - 1) try writer.writeAll(" | ");
    }
    try writer.writeAll("\n");

    // 打印分隔线
    for (col_widths.items, 0..) |width, i| {
        for (0..width) |_| try writer.writeAll("-");
        if (i < col_widths.items.len - 1) try writer.writeAll("-|-");
    }
    try writer.writeAll("\n");

    // 打印数据行
    for (rows) |row| {
        for (row, 0..) |cell, i| {
            try writer.print("{s}", .{cell});
            if (i < row.len - 1) try writer.writeAll(" | ");
        }
        try writer.writeAll("\n");
    }
}
```

---

## 错误处理

### 友好的错误信息

```zig
fn handleError(err: anyerror, writer: anytype) !void {
    switch (err) {
        error.InvalidSymbol => {
            try writer.writeAll("Error: Invalid symbol. Please check the symbol name.\n");
        },
        error.InsufficientFunds => {
            try writer.writeAll("Error: Insufficient funds for this order.\n");
        },
        error.NetworkError => {
            try writer.writeAll("Error: Network connection failed. Please check your internet.\n");
        },
        else => {
            try writer.print("Error: {}\n", .{err});
        },
    }
}
```

---

## 性能优化

### 1. 内存管理

- 使用 Arena Allocator 管理临时内存
- 及时释放大对象（如订单簿数据）
- 复用缓冲区减少分配

### 2. 启动优化

- 延迟加载非必需模块
- 并行初始化独立组件
- 缓存配置文件解析结果

### 3. 输出优化

- 批量写入减少系统调用
- 使用缓冲 Writer
- 条件编译移除调试输出

---

## 依赖库

### zig-clap

命令行参数解析库：

```zig
.{
    .name = "zig-clap",
    .url = "https://github.com/Hejsil/zig-clap",
}
```

---

*完整实现请参考: `src/cli/main.zig`*
