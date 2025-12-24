# CLI 界面 - Bug 追踪

> 已知问题和修复记录

**状态**: ✅ 已完成
**版本**: v0.2.0
**最后更新**: 2025-12-24

---

## 📊 当前状态

CLI 界面 v0.2.0 已完成开发和测试。

**Bug 统计**:
- **总计**: 6
- **已修复**: 6 (100%)
- **开放**: 0
- **已知限制**: 5

---

## ✅ 已修复的 Bug

### Bug #1: 输出缓冲未刷新

**状态**: ✅ 已修复
**严重性**: 🔴 Critical
**发现日期**: 2025-12-24
**修复日期**: 2025-12-24
**影响版本**: v0.2.0-dev
**修复版本**: v0.2.0

#### 问题描述

CLI 命令执行后没有任何输出显示，程序似乎正常退出但用户看不到结果。

#### 复现步骤

1. 执行任意 CLI 命令
2. 程序退出，退出码为 0
3. 终端无任何输出

**复现命令**:
```bash
$ zig build run -- -c config.test.json price BTC-USDC
# [无输出]
```

#### 根本原因

使用了 buffered writer 提高性能，但在程序退出前未调用 `flush()` 方法，导致缓冲区内容未写入 stdout/stderr。

**相关代码位置**: `src/main.zig:65-66`（修复前缺失这两行）

#### 修复方案

在 `main.zig` 的程序退出前添加缓冲区刷新调用:

```zig
// src/main.zig:65-66
cli.stdout.interface.flush() catch {};
cli.stderr.interface.flush() catch {};
```

#### 验证结果

- ✅ 所有命令正常显示输出
- ✅ 错误信息正常显示到 stderr
- ✅ REPL 模式输出正常

#### 影响范围

- 所有 CLI 命令
- REPL 模式

#### 教训

使用 buffered I/O 时必须在适当位置刷新缓冲区，特别是:
1. 程序退出前
2. 需要立即显示的输出
3. 交互式输入前

---

### Bug #2: console_writer 悬空指针

**状态**: ✅ 已修复
**严重性**: 🔴 Critical
**发现日期**: 2025-12-24
**修复日期**: 2025-12-24
**影响版本**: v0.2.0-dev
**修复版本**: v0.2.0

#### 问题描述

程序启动时立即崩溃，出现 Segmentation fault (core dumped)。

#### 复现步骤

1. 执行任意 CLI 命令
2. 程序启动后立即崩溃
3. 输出 "Segmentation fault (core dumped)"

**复现命令**:
```bash
$ zig build run -- -c config.test.json help
Segmentation fault (core dumped)
```

**调试输出**:
```bash
$ strace zig build run -- -c config.test.json help
...
--- SIGSEGV {si_signo=SIGSEGV, si_code=SEGV_MAPERR, si_addr=...} ---
+++ killed by SIGSEGV (core dumped) +++
```

#### 根本原因

`console_writer` 在 `CLI.init()` 函数中作为栈变量创建，然后将其指针传递给 Logger 等组件。当 `CLI.init()` 返回后，栈变量被销毁，导致悬空指针。

**错误代码**:
```zig
pub fn init(...) !*CLI {
    var console_writer = ConsoleWriter.init(allocator);  // 栈变量
    var logger = try Logger.init(allocator, config, &console_writer.interface);  // 传递栈变量指针
    // ... 函数返回后，console_writer 被销毁，指针失效
}
```

**相关代码位置**: `src/cli/cli.zig:24`（修复前未在 struct 中声明）

#### 修复方案

将 `console_writer` 作为 CLI 结构体的字段，而非栈变量:

```zig
pub const CLI = struct {
    allocator: std.mem.Allocator,
    config: Config.AppConfig,
    console_writer: zigQuant.ConsoleWriter(std.fs.File),  // 结构体字段
    logger: Logger,
    // ...
};

pub fn init(...) !*CLI {
    const self = try allocator.create(CLI);
    self.console_writer = ConsoleWriter.init(allocator);  // 在 struct 中初始化
    self.logger = try Logger.init(..., &self.console_writer.interface);
    // ...
}
```

#### 验证结果

- ✅ 程序正常启动
- ✅ 所有命令正常执行
- ✅ 无 segfault

#### 影响范围

- 程序启动
- 所有功能

#### 教训

不能将栈变量的指针传递到更长生命周期的结构中。需要确保被引用的数据生命周期至少与引用者一样长。

---

### Bug #3: 内存泄漏

**状态**: ✅ 已修复
**严重性**: 🟠 High
**发现日期**: 2025-12-24
**修复日期**: 2025-12-24
**影响版本**: v0.2.0-dev
**修复版本**: v0.2.0

#### 问题描述

GeneralPurposeAllocator 在程序退出时检测到内存泄漏。

#### 复现步骤

1. 执行任意 CLI 命令
2. 程序正常执行并退出
3. 终端显示 `error(gpa)` 提示

**复现命令**:
```bash
$ zig build run -- -c config.test.json balance
=== Account Balance ===
Asset: USDC
  Total: 10000.0000
  Available: 9500.0000
  Locked: 500.0000
error(gpa): memory leak detected
```

#### 根本原因

两个资源未正确释放:

1. **config_parsed**: JSON 解析结果包含 arena allocator，未调用 `deinit()`
2. **connector**: HyperliquidConnector 创建后未调用 `destroy()`

**相关代码位置**:
- `src/cli/cli.zig:25-26`（修复前未声明这些字段）
- `src/cli/cli.zig:86-89`（修复前 deinit 中未释放）

#### 修复方案

1. 在 CLI 结构体中持有这些资源:

```zig
pub const CLI = struct {
    // ...
    config_parsed: std.json.Parsed(zigQuant.AppConfig),  // 持有 JSON 解析结果
    connector: ?*HyperliquidConnector = null,  // 持有 connector
    // ...
};
```

2. 在 `deinit()` 中正确释放:

```zig
pub fn deinit(self: *CLI) void {
    // 销毁 connector（如果已创建）
    if (self.connector) |conn| {
        conn.destroy(self.allocator);
        self.connector = null;
    }

    // ... 其他清理 ...

    // 释放 JSON 解析结果（含 arena）
    self.config_parsed.deinit();

    // 释放 CLI 自身
    self.allocator.destroy(self);
}
```

#### 验证结果

- ✅ 所有命令执行后无内存泄漏
- ✅ REPL 模式长时间运行无泄漏
- ✅ GPA 不再报告 error(gpa)

#### 影响范围

- 所有命令
- 长时间运行场景

#### 教训

必须持有所有需要释放的资源，并在适当时机释放。使用 RAII 模式确保资源管理。

---

### Bug #4: balance/positions Signer 懒加载

**状态**: ✅ 已修复
**严重性**: 🟠 High
**发现日期**: 2025-12-24
**修复日期**: 2025-12-24
**影响版本**: v0.2.0-dev
**修复版本**: v0.2.0

#### 问题描述

`balance` 和 `positions` 命令返回 `SignerRequired` 错误，即使配置文件中提供了有效的私钥。

#### 复现步骤

1. 在 config.test.json 中配置真实的私钥
2. 执行 `balance` 或 `positions` 命令
3. 返回 SignerRequired 错误

**复现命令**:
```bash
$ zig build run -- -c config.test.json balance
✗ Error: SignerRequired
```

#### 根本原因

`getBalance()` 和 `getPositions()` 方法检查 `self.signer == null`，但没有调用 `ensureSigner()` 来初始化 Signer。Signer 使用懒加载模式，需要显式调用初始化方法。

**错误代码**:
```zig
fn getBalance(ptr: *anyopaque) anyerror![]Balance {
    const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

    if (self.signer == null) {
        return error.SignerRequired;  // 错误：未尝试初始化
    }

    return try InfoAPI.getUserState(&self.http, self.signer.?);
}
```

**相关代码位置**:
- `src/exchange/hyperliquid/connector.zig:426`（getBalance）
- `src/exchange/hyperliquid/connector.zig:451`（getPositions）

#### 修复方案

调用 `ensureSigner()` 替代空检查:

```zig
fn getBalance(ptr: *anyopaque) anyerror![]Balance {
    const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));

    // 懒加载 signer（仅在需要时初始化）
    try self.ensureSigner();

    return try InfoAPI.getUserState(&self.http, self.signer.?);
}
```

#### 验证结果

- ✅ balance 命令正常返回余额
- ✅ positions 命令正常返回持仓
- ✅ Signer 懒加载机制正常工作

#### 影响范围

- balance 命令
- positions 命令
- 所有需要签名的 API

#### 教训

懒加载模式需要一致的初始化调用，不能简单地检查 null 值。

---

### Bug #5: orders 命令未实现

**状态**: ✅ 已修复
**严重性**: 🟡 Medium
**发现日期**: 2025-12-24
**修复日期**: 2025-12-24
**影响版本**: v0.2.0-dev
**修复版本**: v0.2.0

#### 问题描述

执行 `orders` 命令时显示 "Feature not yet implemented" 提示。

#### 复现步骤

1. 执行 orders 命令
2. 显示未实现提示

**复现命令**:
```bash
$ zig build run -- -c config.test.json orders
ℹ️ TODO | Feature not yet implemented
```

#### 根本原因

IExchange 接口缺少 `getOpenOrders` 方法，CLI 中的 `cmdOrders` 只是显示 TODO 消息。

**相关代码位置**:
- `src/exchange/interface.zig:93`（缺少接口定义）
- `src/exchange/hyperliquid/connector.zig:581-666`（缺少实现）

#### 修复方案

1. 在 IExchange.VTable 中添加 `getOpenOrders`:

```zig
pub const VTable = struct {
    // ... 其他方法 ...

    /// Get all open orders (optionally filtered by trading pair)
    getOpenOrders: *const fn (ptr: *anyopaque, pair: ?TradingPair) anyerror![]Order,
};
```

2. 实现代理方法:

```zig
pub fn getOpenOrders(self: IExchange, pair: ?TradingPair) ![]Order {
    return self.vtable.getOpenOrders(self.ptr, pair);
}
```

3. 在 HyperliquidConnector 中实现:

```zig
fn getOpenOrders(ptr: *anyopaque, pair: ?TradingPair) anyerror![]Order {
    const self: *HyperliquidConnector = @ptrCast(@alignCast(ptr));
    try self.ensureSigner();

    // 调用 Info API 获取用户状态
    const user_state = try InfoAPI.getUserState(&self.http, self.signer.?);

    // 转换为统一的 Order 格式
    // ...
}
```

4. 更新 CLI 使用新接口:

```zig
fn cmdOrders(self: *CLI, args: []const []const u8) !void {
    const exchange = try self.registry.getExchange();
    const orders = try exchange.getOpenOrders(pair);
    // 显示订单...
}
```

#### 验证结果

- ✅ orders 命令正常显示订单列表
- ✅ 支持按交易对筛选
- ✅ 空订单正常显示提示

#### 影响范围

- orders 命令

#### 教训

功能规划时应优先实现核心接口，避免留下 TODO。

---

### Bug #6: 日志格式问题

**状态**: ✅ 已修复
**严重性**: 🟢 Low
**发现日期**: 2025-12-24
**修复日期**: 2025-12-24
**影响版本**: v0.2.0-dev
**修复版本**: v0.2.0

#### 问题描述

日志输出显示 `{s} 0=value` 而不是格式化的值。

#### 复现步骤

1. 启动任意 CLI 命令
2. 查看日志输出

**实际输出**:
```
[info] 1766583869209 Exchange registered: {s} 0=hyperliquid
```

**预期输出**:
```
[info] 1766583869209 Exchange registered: hyperliquid
```

#### 根本原因

Logger 设计为 structured logging（字段为 struct），但代码中使用了 printf-style 格式化（字段为 tuple）。

**错误用法**:
```zig
try self.logger.info("Exchange registered: {s}", .{"hyperliquid"});
// fields 是 tuple，但 Logger 期望 struct
```

**相关代码位置**: `src/core/logger.zig:108-121`

#### 修复方案

修改 `Logger.log()` 检测参数类型并相应处理:

```zig
pub fn log(self: *Logger, level: Level, comptime msg: []const u8, fields: anytype) !void {
    // ...

    const FieldsType = @TypeOf(fields);
    const fields_info = @typeInfo(FieldsType);

    const formatted_msg = blk: {
        if (fields_info == .@"struct" and fields_info.@"struct".is_tuple) {
            // Printf-style: 格式化消息
            break :blk try std.fmt.allocPrint(self.allocator, msg, fields);
        } else {
            // Structured logging: 使用原消息
            break :blk try self.allocator.dupe(u8, msg);
        }
    };
    defer self.allocator.free(formatted_msg);

    // ...
}
```

#### 验证结果

- ✅ Printf-style 日志正确格式化
- ✅ Structured logging 仍然正常工作
- ✅ 所有日志输出正确

#### 影响范围

- 所有日志输出

#### 教训

API 设计应考虑兼容性和易用性。同时支持多种使用方式可提高开发效率。

---

## ⚠️ 已知限制

### 1. 仅支持限价单

**影响**: buy 和 sell 命令

**说明**: 当前仅支持限价单，不支持市价单、止损单等其他订单类型。

**计划**: v0.3.0 添加其他订单类型

---

### 2. 无命令历史

**影响**: REPL 模式

**说明**: REPL 模式不支持上下箭头浏览命令历史。

**计划**: v0.3.0 添加命令历史功能

---

### 3. 无自动补全

**影响**: REPL 模式

**说明**: 不支持 Tab 键自动补全命令和参数。

**计划**: v0.3.0 添加自动补全

---

### 4. 仅支持 JSON 配置

**影响**: 配置文件

**说明**: 当前仅支持 JSON 格式配置文件，不支持 TOML 或 YAML。

**计划**: 保持 JSON only（简单够用）

---

### 5. 单交易所支持

**影响**: 所有命令

**说明**: 当前仅支持 Hyperliquid，架构已支持多交易所但未实现。

**计划**: v0.4.0 添加 Binance、OKX 等

---

## 📊 Bug 统计

### 按严重性

| 严重性 | 数量 | 已修复 |
|--------|------|--------|
| Critical | 2 | 2 (100%) |
| High | 2 | 2 (100%) |
| Medium | 1 | 1 (100%) |
| Low | 1 | 1 (100%) |

### 按影响范围

| 范围 | Bug 数量 |
|------|---------|
| 所有功能 | 2 |
| 账户查询 | 2 |
| 订单查询 | 1 |
| 日志输出 | 1 |

---

## 🔗 相关文档

- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [变更日志](./changelog.md)

---

*Bug 追踪文档 - 完整且准确 ✅*
*最后更新: 2025-12-24*
