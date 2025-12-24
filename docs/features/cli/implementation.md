# CLI 界面 - 实现细节

> 深入了解 CLI 命令行界面的内部实现

**状态**: ✅ 已完成
**版本**: v0.2.0
**最后更新**: 2025-12-24

---

## 📐 架构概览

### 实际目录结构

```
src/
├── main.zig                 # CLI 入口点（主函数）
├── cli/
│   ├── cli.zig              # CLI 主逻辑（命令处理）
│   ├── format.zig           # 彩色输出格式化（ConsoleWriter）
│   └── repl.zig             # REPL 循环实现
└── ...
```

### 架构设计原则

**选择直接命令模式的原因**:
1. **简洁性**: 无需子命令层级，降低用户学习成本
2. **快速**: 更少的参数解析，更快的启动时间
3. **直观**: 命令语义更清晰（`price` vs `market ticker`）
4. **易扩展**: 添加新命令只需添加一个函数

---

## 🏗️ 核心组件实现

### 1. 主入口点 - src/main.zig

**职责**: 程序启动、配置加载、交易所连接

#### 关键实现

```zig
pub fn main() !void {
    // 1. 内存管理 - 使用 GPA 检测内存泄漏
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};\n    defer _ = gpa.deinit();  // 退出时检查泄漏
    const allocator = gpa.allocator();

    // 2. 参数解析 - 提取配置文件路径和命令
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // 跳过程序名
    const cli_args = if (args.len > 1) args[1..] else &[_][]const u8{};

    // 3. 解析 -c/--config 选项
    var config_path: ?[]const u8 = null;
    var command_start: usize = 0;

    for (cli_args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, \"-c\") or std.mem.eql(u8, arg, \"--config\")) {
            if (i + 1 < cli_args.len) {
                config_path = cli_args[i + 1];
                command_start = i + 2;
                break;
            }
        } else if (std.mem.startsWith(u8, arg, \"--config=\")) {
            config_path = arg[\"--config=\".len..];
            command_start = i + 1;
            break;
        }
    }

    // 4. 初始化 CLI
    const cli = CLI.init(allocator, config_path) catch |err| {
        // 错误处理和友好提示
        var stderr_buffer: [4096]u8 = undefined;
        var stderr = std.fs.File.stderr().writer(&stderr_buffer);
        try format.printError(&stderr.interface, \"Failed to initialize: {s}\", .{@errorName(err)});
        std.process.exit(1);
    };
    defer cli.deinit();  // 释放资源

    // 5. 连接交易所
    cli.connect() catch |err| {
        try format.printError(&cli.stderr.interface, \"Failed to connect: {s}\", .{@errorName(err)});
        std.process.exit(1);
    };

    // 6. 执行命令
    const command_args = if (command_start < cli_args.len)
        cli_args[command_start..]
    else
        &[_][]const u8{};

    cli.executeCommand(command_args) catch |err| {
        try format.printError(&cli.stderr.interface, \"Command failed: {s}\", .{@errorName(err)});
        cli.stderr.interface.flush() catch {};
        std.process.exit(1);
    };

    // 7. 刷新输出缓冲（关键！避免无输出问题）
    cli.stdout.interface.flush() catch {};
    cli.stderr.interface.flush() catch {};
}
```

#### 设计要点

1. **GeneralPurposeAllocator**: 自动检测内存泄漏
2. **Buffered I/O**: 提高输出性能，但必须手动刷新
3. **错误传播**: 使用 Zig 的 `!` 错误联合类型
4. **资源清理**: 使用 `defer` 确保资源释放

---

### 2. CLI 主逻辑 - src/cli/cli.zig

**职责**: 命令路由、命令执行、资源管理

#### CLI 结构体设计

```zig
pub const CLI = struct {
    allocator: std.mem.Allocator,
    config: Config.AppConfig,
    config_parsed: std.json.Parsed(zigQuant.AppConfig),  // 持有 JSON 解析结果
    console_writer: zigQuant.ConsoleWriter(std.fs.File),  // 彩色输出
    logger: Logger,
    registry: ExchangeRegistry,
    connector: ?*HyperliquidConnector = null,  // 懒加载

    // 输出流
    stdout: *zigQuant.ConsoleWriter(std.fs.File).BufferedInterface,
    stderr: *zigQuant.ConsoleWriter(std.fs.File).BufferedInterface,

    // ... 方法
};
```

**关键设计决策**:

1. **console_writer 作为字段**: 避免悬空指针（Bug #2 修复）
2. **config_parsed 持有**: 避免内存泄漏（Bug #3 修复）
3. **connector 可选**: 支持懒加载
4. **stdout/stderr 分离**: 错误输出到 stderr

#### 初始化流程

```zig
pub fn init(allocator: std.mem.Allocator, config_path: ?[]const u8) !*CLI {
    // 1. 加载并解析配置文件
    const path = config_path orelse \"config.json\";
    const config_parsed = try Config.loadFromFile(path, allocator);
    const config = config_parsed.value;

    // 2. 分配 CLI 结构
    const self = try allocator.create(CLI);
    errdefer allocator.destroy(self);

    // 3. 初始化 ConsoleWriter（必须在 struct 字段中）
    self.console_writer = zigQuant.ConsoleWriter(std.fs.File).init(allocator);

    // 4. 初始化 Logger
    self.logger = try Logger.init(allocator, config.logging, &self.console_writer.interface);

    // 5. 初始化 ExchangeRegistry
    self.registry = ExchangeRegistry.init(allocator, self.logger);

    // 6. 获取输出流
    self.stdout = try self.console_writer.interface.getBufferedWriter(std.io.getStdOut());
    self.stderr = try self.console_writer.interface.getBufferedWriter(std.io.getStdErr());

    // 7. 设置其他字段
    self.* = .{
        .allocator = allocator,
        .config = config,
        .config_parsed = config_parsed,  // 持有所有权
        .console_writer = self.console_writer,
        .logger = self.logger,
        .registry = self.registry,
        .connector = null,
        .stdout = self.stdout,
        .stderr = self.stderr,
    };

    return self;
}
```

#### 资源清理

```zig
pub fn deinit(self: *CLI) void {
    // 1. 销毁 connector（如果已创建）
    if (self.connector) |conn| {
        conn.destroy(self.allocator);
        self.connector = null;
    }

    // 2. 清理 registry
    self.registry.deinit();

    // 3. 清理 logger
    self.logger.deinit();

    // 4. 清理 console_writer
    self.console_writer.deinit();

    // 5. 释放 JSON 解析结果（含 arena）
    self.config_parsed.deinit();

    // 6. 释放 CLI 自身
    self.allocator.destroy(self);
}
```

**内存管理要点**:
- 所有 `init` 必须有对应的 `deinit`
- 使用 `defer` 确保异常时也能清理
- 持有 JSON 解析结果以避免 dangling pointers

#### 命令路由

```zig
pub fn executeCommand(self: *CLI, args: []const []const u8) !void {
    if (args.len == 0) {
        try self.cmdHelp();
        return;
    }

    const cmd = args[0];

    // 直接命令匹配（无子命令层级）
    if (std.mem.eql(u8, cmd, \"help\")) {
        try self.cmdHelp();
    } else if (std.mem.eql(u8, cmd, \"price\")) {
        try self.cmdPrice(args[1..]);
    } else if (std.mem.eql(u8, cmd, \"book\")) {
        try self.cmdBook(args[1..]);
    } else if (std.mem.eql(u8, cmd, \"balance\")) {
        try self.cmdBalance();
    } else if (std.mem.eql(u8, cmd, \"positions\")) {
        try self.cmdPositions();
    } else if (std.mem.eql(u8, cmd, \"orders\")) {
        try self.cmdOrders(args[1..]);
    } else if (std.mem.eql(u8, cmd, \"buy\")) {
        try self.cmdBuy(args[1..]);
    } else if (std.mem.eql(u8, cmd, \"sell\")) {
        try self.cmdSell(args[1..]);
    } else if (std.mem.eql(u8, cmd, \"cancel\")) {
        try self.cmdCancel(args[1..]);
    } else if (std.mem.eql(u8, cmd, \"cancel-all\")) {
        try self.cmdCancelAll(args[1..]);
    } else if (std.mem.eql(u8, cmd, \"repl\")) {
        try self.cmdRepl();
    } else {
        try format.printError(self.stderr, \"Unknown command: {s}\", .{cmd});
        try self.cmdHelp();
    }
}
```

**设计特点**:
- 简单的字符串匹配
- 每个命令一个方法
- 统一的错误处理

#### 命令实现示例 - price

```zig
fn cmdPrice(self: *CLI, args: []const []const u8) !void {
    if (args.len < 1) {
        try format.printError(self.stderr, \"Usage: price <PAIR>\", .{});
        return;
    }

    const pair_str = args[0];
    const pair = parseTradingPair(pair_str) catch {
        try format.printError(self.stderr, \"Invalid trading pair: {s}\", .{pair_str});
        return;
    };

    const exchange = try self.registry.getExchange();
    const ticker = try exchange.getTicker(pair);

    try self.stdout.writer().print(\"{s}-{s}: {}\n\", .{
        pair.base,
        pair.quote,
        ticker.last,
    });
}
```

---

### 3. 彩色输出 - src/cli/format.zig

**职责**: ANSI 颜色码、格式化输出

#### ConsoleWriter 实现

```zig
pub fn ConsoleWriter(comptime FileType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        interface: Interface,

        const Self = @This();

        pub const Interface = struct {
            // 方法指针...

            pub fn init(allocator: std.mem.Allocator) Interface {
                // 初始化接口
            }

            pub fn getBufferedWriter(self: *Interface, file: FileType) !*BufferedInterface {
                // 创建缓冲writer
            }
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .interface = Interface.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.interface.deinit();
        }
    };
}
```

#### ANSI 颜色支持

```zig
pub const Color = enum {
    reset,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,

    pub fn code(self: Color) []const u8 {
        return switch (self) {
            .reset => \"\\x1b[0m\",
            .red => \"\\x1b[31m\",
            .green => \"\\x1b[32m\",
            .yellow => \"\\x1b[33m\",
            .blue => \"\\x1b[34m\",
            .magenta => \"\\x1b[35m\",
            .cyan => \"\\x1b[36m\",
            .white => \"\\x1b[37m\",
        };
    }
};

pub fn printSuccess(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try writer.print(Color.green.code(), .{});
    try writer.print(\"✓ \" ++ fmt ++ \"\\n\", args);
    try writer.print(Color.reset.code(), .{});
}

pub fn printError(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try writer.print(Color.red.code(), .{});
    try writer.print(\"✗ \" ++ fmt ++ \"\\n\", args);
    try writer.print(Color.reset.code(), .{});
}
```

---

### 4. REPL 模式 - src/cli/repl.zig

**职责**: 交互式命令循环

#### REPL 实现

```zig
pub fn run(cli: *CLI) !void {
    const stdin = std.io.getStdIn().reader();
    var buf: [4096]u8 = undefined;

    // 打印欢迎信息
    try cli.stdout.writer().print(\"\\n\" ++
        \"========================================\\n\" ++
        \"     ZigQuant CLI - REPL Mode\\n\" ++
        \"========================================\\n\" ++
        \"Type 'help' for commands, 'exit' to quit\\n\\n\", .{});
    try cli.stdout.interface.flush();

    // 主循环
    while (true) {
        // 打印提示符
        try cli.stdout.writer().print(\"> \", .{});
        try cli.stdout.interface.flush();

        // 读取输入
        const line = (try stdin.readUntilDelimiterOrEof(&buf, '\\n')) orelse break;
        const trimmed = std.mem.trim(u8, line, \" \\t\\r\\n\");

        if (trimmed.len == 0) continue;

        // 检查退出命令
        if (std.mem.eql(u8, trimmed, \"exit\") or std.mem.eql(u8, trimmed, \"quit\")) {
            try cli.stdout.writer().print(\"Goodbye!\\n\", .{});
            break;
        }

        // 分割命令和参数
        var args = std.ArrayList([]const u8).init(cli.allocator);
        defer args.deinit();

        var iter = std.mem.split(u8, trimmed, \" \");
        while (iter.next()) |arg| {
            if (arg.len > 0) {
                try args.append(arg);
            }
        }

        // 执行命令
        cli.executeCommand(args.items) catch |err| {
            try format.printError(cli.stderr, \"Error: {s}\", .{@errorName(err)});
        };

        // 刷新输出
        try cli.stdout.interface.flush();
        try cli.stderr.interface.flush();
    }
}
```

**关键设计**:
1. **简单的行读取**: 使用 `readUntilDelimiterOrEof`
2. **命令分割**: 基于空格分割参数
3. **错误隔离**: 单个命令错误不影响 REPL
4. **即时刷新**: 每次命令后刷新输出

---

## 🔑 关键设计决策

### 1. 为什么选择直接命令而非子命令？

**优点**:
- ✅ 更简洁：`price BTC-USDC` vs `market ticker BTC-USDC`
- ✅ 更快：减少参数解析层级
- ✅ 更直观：命令语义清晰
- ✅ 更易扩展：添加命令只需一个函数

**缺点**:
- ❌ 命令数量增加时可能混乱（当前 11 个命令可接受）
- ❌ 无法按功能分组（通过命名前缀缓解，如 cancel-all）

**决策**: 当前命令数量适中，直接命令模式更优。

---

### 2. 懒加载 Signer

**问题**: Ed25519 密钥生成需要读取熵源，可能阻塞启动

**解决**: 仅在需要时初始化 Signer

```zig
fn ensureSigner(self: *HyperliquidConnector) !void {
    if (self.signer != null) return;

    // 从配置中读取私钥
    const secret_key_hex = self.config.credentials.secret_key;

    // 初始化 Signer（可能阻塞）
    self.signer = try Signer.fromHex(secret_key_hex, self.allocator);
}
```

**使用示例**:
```zig
fn getBalance(ptr: *anyopaque) anyerror![]Balance {
    const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

    // 懒加载 signer（仅在需要时初始化）
    try self.ensureSigner();

    // 调用需要签名的 API
    return try InfoAPI.getUserState(&self.http, self.signer.?);
}
```

**好处**:
- ✅ price/book 等公开 API 无需私钥，启动更快
- ✅ 避免不必要的熵读取
- ✅ 仅在真正需要时才初始化

---

### 3. 输出缓冲和刷新

**问题**: Buffered Writer 提高性能，但忘记刷新导致无输出（Bug #1）

**解决**: 在关键位置手动刷新

```zig
// main.zig 退出前刷新
cli.stdout.interface.flush() catch {};
cli.stderr.interface.flush() catch {};

// REPL 每个命令后刷新
try cli.stdout.interface.flush();
try cli.stderr.interface.flush();
```

**教训**: 使用 buffered I/O 必须记得刷新！

---

### 4. 内存管理策略

**原则**:
1. **所有 allocation 必须有对应的 free**
2. **使用 `defer` 确保异常安全**
3. **GPA 检测泄漏**
4. **持有长生命周期数据**

**示例**:
```zig
// 持有 JSON 解析结果（包含 arena）
config_parsed: std.json.Parsed(zigQuant.AppConfig),

// 清理时释放
self.config_parsed.deinit();  // 释放整个 arena
```

---

## 🐛 已修复的设计缺陷

### Bug #1: 输出缓冲未刷新

**症状**: 命令执行后无输出

**原因**: buffered writer 在程序退出前未刷新

**修复**: 在 `main.zig:65-66` 添加刷新调用

**教训**: buffered I/O 需要手动管理

---

### Bug #2: console_writer 悬空指针

**症状**: 程序启动 segfault

**原因**: `console_writer` 是栈变量，传递后成为悬空指针

**修复**: 将 `console_writer` 作为 CLI 结构体字段

**教训**: 不能将栈变量指针传递到更长生命周期的结构

---

### Bug #3: 内存泄漏

**症状**: GPA 检测到内存泄漏

**原因**: `config_parsed` arena 和 `connector` 未释放

**修复**:
- 添加 `config_parsed` 字段持有 JSON 解析结果
- 添加 `connector` 字段并在 deinit 中销毁

**教训**: 必须持有所有需要释放的资源

---

### Bug #4: balance/positions Signer 懒加载

**症状**: 返回 SignerRequired 错误

**原因**: 检查 `signer == null` 但未调用 `ensureSigner()`

**修复**: 用 `try self.ensureSigner()` 替代空检查

**教训**: 懒加载需要一致的初始化调用

---

## 📊 性能考虑

### 启动时间优化

1. **懒加载 Signer**: 避免不必要的熵读取
2. **配置缓存**: 一次加载，多次使用
3. **连接复用**: REPL 模式重用连接

### 内存占用

- **基准**: ~5-8MB（无内存泄漏）
- **GPA 检测**: 自动发现泄漏
- **Arena**: JSON 解析使用 arena 快速释放

### 响应时间

- **命令解析**: < 1ms
- **本地操作**: < 10ms
- **网络请求**: 100-500ms（取决于 API）

---

## 🔧 测试和调试

### 内存泄漏检测

```bash
# GPA 自动检测
$ zig build run -- -c config.test.json balance
# 退出时如有泄漏会打印 error(gpa)
```

### Debug 日志

```json
{
  \"logging\": {
    \"level\": \"debug\",  // 启用 debug 日志
    \"format\": \"json\",
    \"output\": \"stdout\"
  }
}
```

### Segfault 调试

```bash
# 使用 strace 追踪系统调用
$ strace zig build run -- -c config.test.json price BTC-USDC

# 查找 futex 阻塞或 SIGSEGV
```

---

## 🔗 相关文档

- [API 参考](./api.md) - 完整命令 API
- [测试文档](./testing.md) - 测试覆盖和结果
- [Bug 列表](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 📝 未来改进

### 短期
- [ ] 添加命令历史（上下箭头）
- [ ] 添加 Tab 补全
- [ ] JSON 输出格式

### 长期
- [ ] TUI 界面（使用 termbox）
- [ ] 批处理脚本支持
- [ ] 插件系统

---

*实现文档 - 完整且准确 ✅*
*最后更新: 2025-12-24*
