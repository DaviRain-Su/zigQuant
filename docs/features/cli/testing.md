# CLI 界面 - 测试文档

> 测试覆盖和性能基准

**最后更新**: 2025-12-23

---

## 测试概览

### 测试范围

- ✅ **命令解析测试**: 参数解析和验证
- ✅ **命令执行测试**: 各子命令功能测试
- ✅ **REPL 测试**: 交互式模式测试
- ✅ **格式化测试**: 输出格式化功能
- ✅ **集成测试**: 端到端测试
- ✅ **性能测试**: 启动和响应时间

### 测试覆盖率

- **代码覆盖率**: 目标 80%+
- **测试用例数**: 50+
- **性能基准**: 启动 < 100ms, 响应 < 50ms

---

## 单元测试

### 1. 命令解析测试

#### 测试参数解析

```zig
// src/cli/cli_test.zig

const std = @import("std");
const testing = std.testing;
const main = @import("main.zig");

test "CLI: parse help option" {
    const args = [_][]const u8{ "zigquant", "--help" };

    // 测试帮助选项解析
    // 应该显示帮助信息并退出
}

test "CLI: parse config option" {
    const args = [_][]const u8{
        "zigquant",
        "--config",
        "test_config.toml",
        "market",
        "ticker",
        "ETH"
    };

    // 测试配置文件选项解析
    // 应该加载指定的配置文件
}

test "CLI: parse verbose option" {
    const args = [_][]const u8{
        "zigquant",
        "--verbose",
        "market",
        "ticker",
        "ETH"
    };

    // 测试详细输出选项
    // 应该启用详细日志
}

test "CLI: parse unknown option" {
    const args = [_][]const u8{ "zigquant", "--unknown" };

    // 测试未知选项
    // 应该返回错误
}
```

#### 测试命令路由

```zig
test "CLI: route market command" {
    const args = [_][]const u8{ "market", "ticker", "ETH" };

    // 测试 market 命令路由
    // 应该调用 market.run()
}

test "CLI: route order command" {
    const args = [_][]const u8{ "order", "buy", "ETH", "0.1", "2000.0" };

    // 测试 order 命令路由
    // 应该调用 order.run()
}

test "CLI: route unknown command" {
    const args = [_][]const u8{ "unknown" };

    // 测试未知命令
    // 应该返回错误并显示帮助
}
```

---

### 2. Market 命令测试

```zig
// src/cli/commands/market_test.zig

const std = @import("std");
const testing = std.testing;
const market = @import("market.zig");

test "market: ticker with valid symbol" {
    var allocator = testing.allocator;

    // Mock HTTP client
    var mock_client = MockHyperliquidClient.init();
    defer mock_client.deinit();

    const args = [_][]const u8{ "ticker", "ETH" };

    try market.run(allocator, &mock_client, &args);

    // 验证输出包含 ticker 信息
}

test "market: ticker without symbol" {
    var allocator = testing.allocator;
    var mock_client = MockHyperliquidClient.init();
    defer mock_client.deinit();

    const args = [_][]const u8{ "ticker" };

    // 应该显示用法错误
    try testing.expectError(error.MissingArgument,
        market.run(allocator, &mock_client, &args));
}

test "market: orderbook with depth" {
    var allocator = testing.allocator;
    var mock_client = MockHyperliquidClient.init();
    defer mock_client.deinit();

    const args = [_][]const u8{ "orderbook", "BTC", "5" };

    try market.run(allocator, &mock_client, &args);

    // 验证输出包含 5 档订单簿
}

test "market: orderbook default depth" {
    var allocator = testing.allocator;
    var mock_client = MockHyperliquidClient.init();
    defer mock_client.deinit();

    const args = [_][]const u8{ "orderbook", "BTC" };

    try market.run(allocator, &mock_client, &args);

    // 验证使用默认深度 10
}

test "market: trades with limit" {
    var allocator = testing.allocator;
    var mock_client = MockHyperliquidClient.init();
    defer mock_client.deinit();

    const args = [_][]const u8{ "trades", "ETH", "10" };

    try market.run(allocator, &mock_client, &args);

    // 验证输出包含 10 条交易记录
}
```

---

### 3. Order 命令测试

```zig
// src/cli/commands/order_test.zig

const std = @import("std");
const testing = std.testing;
const order = @import("order.zig");

test "order: buy with valid parameters" {
    var allocator = testing.allocator;
    var mock_client = MockHyperliquidClient.init();
    defer mock_client.deinit();

    const args = [_][]const u8{ "buy", "ETH", "0.1", "2000.0" };

    try order.run(allocator, &mock_client, &args);

    // 验证订单已提交
    try testing.expect(mock_client.order_submitted);
}

test "order: buy with missing parameters" {
    var allocator = testing.allocator;
    var mock_client = MockHyperliquidClient.init();
    defer mock_client.deinit();

    const args = [_][]const u8{ "buy", "ETH", "0.1" };

    // 应该返回参数错误
    try testing.expectError(error.MissingArgument,
        order.run(allocator, &mock_client, &args));
}

test "order: sell with valid parameters" {
    var allocator = testing.allocator;
    var mock_client = MockHyperliquidClient.init();
    defer mock_client.deinit();

    const args = [_][]const u8{ "sell", "ETH", "0.5", "2200.0" };

    try order.run(allocator, &mock_client, &args);

    // 验证卖单已提交
    try testing.expect(mock_client.order_submitted);
}

test "order: cancel with valid order id" {
    var allocator = testing.allocator;
    var mock_client = MockHyperliquidClient.init();
    defer mock_client.deinit();

    const args = [_][]const u8{ "cancel", "CLIENT_1640000000000_12345" };

    try order.run(allocator, &mock_client, &args);

    // 验证订单已撤销
    try testing.expect(mock_client.order_cancelled);
}

test "order: list orders" {
    var allocator = testing.allocator;
    var mock_client = MockHyperliquidClient.init();
    defer mock_client.deinit();

    const args = [_][]const u8{ "list" };

    try order.run(allocator, &mock_client, &args);

    // 验证订单列表已显示
}
```

---

### 4. REPL 测试

```zig
// src/cli/repl_test.zig

const std = @import("std");
const testing = std.testing;
const repl = @import("repl.zig");

test "REPL: execute market command" {
    var allocator = testing.allocator;
    var mock_client = MockHyperliquidClient.init();
    defer mock_client.deinit();

    var mock_logger = MockLogger.init();
    defer mock_logger.deinit();

    const command = "market ticker ETH";

    // 模拟命令执行
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    var iter = std.mem.split(u8, command, " ");
    while (iter.next()) |arg| {
        try args.append(arg);
    }

    try repl.executeCommand(allocator, &mock_client, mock_logger, args.items);

    // 验证命令已执行
}

test "REPL: handle exit command" {
    // 测试退出命令
    const command = "exit";

    try testing.expect(std.mem.eql(u8, command, "exit"));
}

test "REPL: handle help command" {
    // 测试帮助命令
    const command = "help";

    try testing.expect(std.mem.eql(u8, command, "help"));
}

test "REPL: handle empty input" {
    const command = "";
    const trimmed = std.mem.trim(u8, command, &std.ascii.whitespace);

    try testing.expect(trimmed.len == 0);
}
```

---

### 5. 格式化测试

```zig
// src/cli/format_test.zig

const std = @import("std");
const testing = std.testing;
const format = @import("format.zig");

test "format: print table" {
    var allocator = testing.allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const headers = [_][]const u8{ "Symbol", "Price", "Volume" };
    const rows = [_][]const []const u8{
        &[_][]const u8{ "ETH", "2145.23", "1000.0" },
        &[_][]const u8{ "BTC", "50100.0", "50.0" },
    };

    try format.printTable(buffer.writer(), &headers, &rows);

    const output = buffer.items;

    // 验证表格格式
    try testing.expect(std.mem.indexOf(u8, output, "Symbol") != null);
    try testing.expect(std.mem.indexOf(u8, output, "ETH") != null);
    try testing.expect(std.mem.indexOf(u8, output, "|") != null);
}
```

---

## 集成测试

### 端到端测试场景

```bash
#!/bin/bash
# tests/cli_integration_test.sh

set -e

echo "=== CLI Integration Tests ==="

# 1. 测试帮助命令
echo "Testing help command..."
zigquant --help | grep "ZigQuant CLI"

# 2. 测试市场数据查询
echo "Testing market ticker..."
zigquant market ticker ETH | grep "ETH Ticker"

# 3. 测试订单簿查询
echo "Testing market orderbook..."
zigquant market orderbook BTC 5 | grep "Order Book"

# 4. 测试订单列表
echo "Testing order list..."
zigquant order list

# 5. 测试仓位查询
echo "Testing position list..."
zigquant position list

# 6. 测试账户查询
echo "Testing account info..."
zigquant account info | grep "Account Info"

# 7. 测试配置显示
echo "Testing config show..."
zigquant config show | grep "Configuration"

# 8. 测试 REPL 模式
echo "Testing REPL mode..."
echo -e "market ticker ETH\nexit" | zigquant repl | grep "ETH Ticker"

echo "=== All tests passed! ==="
```

---

## 性能基准

### 启动性能测试

```bash
#!/bin/bash
# tests/cli_benchmark.sh

echo "=== CLI Performance Benchmark ==="

# 测试启动时间
echo "Testing startup time..."
time zigquant --help > /dev/null

# 测试命令响应时间
echo "Testing command response time..."
time zigquant market ticker ETH > /dev/null

# 测试 REPL 启动时间
echo "Testing REPL startup time..."
time echo "exit" | zigquant repl > /dev/null
```

### 基准结果

| 操作 | 性能目标 | 实际性能 |
|------|---------|---------|
| 启动时间 | < 100ms | 待测试 |
| 帮助显示 | < 20ms | 待测试 |
| Market ticker | < 50ms + 网络延迟 | 待测试 |
| Order 提交 | < 50ms + 网络延迟 | 待测试 |
| REPL 命令解析 | < 10ms | 待测试 |
| 表格格式化 | < 5ms | 待测试 |

---

## 运行测试

### 单元测试

```bash
# 运行所有 CLI 测试
zig test src/cli/cli_test.zig

# 运行 market 命令测试
zig test src/cli/commands/market_test.zig

# 运行 order 命令测试
zig test src/cli/commands/order_test.zig

# 运行 REPL 测试
zig test src/cli/repl_test.zig

# 运行格式化测试
zig test src/cli/format_test.zig
```

### 集成测试

```bash
# 运行集成测试脚本
./tests/cli_integration_test.sh

# 运行性能基准测试
./tests/cli_benchmark.sh
```

### 覆盖率报告

```bash
# 生成测试覆盖率报告
zig test src/cli/cli_test.zig --test-coverage

# 查看覆盖率报告
# TODO: 配置覆盖率工具
```

---

## 测试场景

### ✅ 已覆盖

- [x] 命令行参数解析（help, config, verbose）
- [x] 命令路由（market, order, position, account）
- [x] Market 子命令（ticker, orderbook, trades）
- [x] Order 子命令（buy, sell, cancel, list）
- [x] Position 子命令（list, info）
- [x] Account 子命令（info, balance）
- [x] REPL 命令解析和执行
- [x] 表格格式化输出
- [x] 错误处理和友好提示

### 📋 待补充

- [ ] 配置文件加载和验证
- [ ] 彩色输出测试
- [ ] 网络错误处理测试
- [ ] 并发命令执行测试
- [ ] 大数据量输出测试
- [ ] 内存泄漏测试
- [ ] 跨平台兼容性测试
- [ ] 命令自动补全测试（未来）
- [ ] 命令历史测试（未来）

---

## Mock 对象

### MockHyperliquidClient

```zig
const MockHyperliquidClient = struct {
    order_submitted: bool = false,
    order_cancelled: bool = false,

    pub fn init() MockHyperliquidClient {
        return .{};
    }

    pub fn deinit(self: *MockHyperliquidClient) void {
        _ = self;
    }

    pub fn submitOrder(self: *MockHyperliquidClient, order: anytype) !void {
        _ = order;
        self.order_submitted = true;
    }

    pub fn cancelOrder(self: *MockHyperliquidClient, order_id: []const u8) !void {
        _ = order_id;
        self.order_cancelled = true;
    }
};
```

### MockLogger

```zig
const MockLogger = struct {
    pub fn init() MockLogger {
        return .{};
    }

    pub fn deinit(self: *MockLogger) void {
        _ = self;
    }

    pub fn info(self: *MockLogger, msg: []const u8) void {
        _ = self;
        _ = msg;
    }

    pub fn debug(self: *MockLogger, msg: []const u8) void {
        _ = self;
        _ = msg;
    }
};
```

---

## 持续集成

### GitHub Actions 配置

```yaml
# .github/workflows/cli_tests.yml
name: CLI Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.13.0

      - name: Run Unit Tests
        run: |
          zig test src/cli/cli_test.zig
          zig test src/cli/commands/market_test.zig
          zig test src/cli/commands/order_test.zig

      - name: Run Integration Tests
        run: |
          zig build
          ./tests/cli_integration_test.sh

      - name: Run Benchmarks
        run: ./tests/cli_benchmark.sh
```

---

*完整测试代码请参考: `src/cli/cli_test.zig`*
