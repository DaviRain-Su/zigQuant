# zigQuant 快速开始指南

> 5 分钟快速上手 zigQuant 量化交易框架

---

## 📋 目录

1. [环境准备](#环境准备)
2. [安装和构建](#安装和构建)
3. [运行测试](#运行测试)
4. [第一个程序](#第一个程序)
5. [连接交易所](#连接交易所)
6. [使用 CLI](#使用-cli)
7. [配置文件](#配置文件)
8. [下一步](#下一步)

---

## 环境准备

### 1. 安装 Zig

zigQuant 需要 **Zig 0.15.2** 或更高版本。

#### Linux / macOS
```bash
# 下载 Zig 0.15.2
wget https://ziglang.org/download/0.15.2/zig-linux-x86_64-0.15.2.tar.xz
tar -xf zig-linux-x86_64-0.15.2.tar.xz

# 添加到 PATH
export PATH=$PATH:$PWD/zig-linux-x86_64-0.15.2

# 验证安装
zig version  # 应该显示 0.15.2
```

#### Windows
```powershell
# 下载 Zig 0.15.2
# https://ziglang.org/download/

# 解压并添加到 PATH
# 验证安装
zig version
```

### 2. 检查环境

```bash
# 确认 Zig 版本
zig version  # 输出: 0.15.2

# 确认网络连接（用于集成测试）
ping api.hyperliquid-testnet.xyz
```

---

## 安装和构建

### 1. 克隆仓库

```bash
git clone https://github.com/your-username/zigQuant.git
cd zigQuant
```

### 2. 构建项目

```bash
# 首次构建（会下载依赖）
zig build

# 构建 Release 版本
zig build -Doptimize=ReleaseFast

# 构建并运行
zig build run
```

**预期输出**:
```
zigQuant CLI - 量化交易框架
使用 'help' 查看可用命令
>
```

---

## 运行测试

### 1. 单元测试

```bash
# 运行所有单元测试
zig build test --summary all

# 预期输出
Build Summary: 8/8 steps succeeded
✅ 173/173 tests passed
```

### 2. 集成测试

**注意**: 集成测试需要网络连接到 Hyperliquid testnet。

```bash
# HTTP API 集成测试
zig build test-integration

# WebSocket 集成测试
zig build test-ws

# WebSocket 订单簿集成测试
zig build test-ws-orderbook
```

**预期输出（test-ws-orderbook）**:
```
================================================================================
WebSocket Orderbook Integration Test
================================================================================
Phase 1: Testing WebSocket connection...
✓ Connected to Hyperliquid WebSocket

Phase 2: Subscribing to ETH L2 orderbook...
✓ Subscription sent

Phase 3: Receiving orderbook updates for 10 seconds...
✓ Applied snapshot for ETH: 20 bids, 20 asks
  Best Bid: 2953200000000000000000
  Best Ask: 3009100000000000000000

================================================================================
Test Results:
================================================================================
Snapshots received: 17
Max latency: 0.23 ms
✅ PASSED: Received 17 snapshots
✅ PASSED: Latency 0.23ms < 10ms
✅ No memory leaks
```

---

## 第一个程序

### 1. 使用核心模块

创建文件 `my_first_quant.zig`:

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

const Decimal = zigQuant.Decimal;
const Time = zigQuant.Time;
const Logger = zigQuant.Logger;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 创建 Logger
    const stdout = std.io.getStdOut().writer();
    var console_writer = zigQuant.logger.ConsoleLogWriter.init(allocator, stdout);
    defer console_writer.deinit();

    var logger = Logger.init(allocator, console_writer.writer(), .info);
    defer logger.deinit();

    // 2. 使用 Decimal 高精度计算
    const price = try Decimal.fromString("2950.50");
    const quantity = try Decimal.fromString("1.5");
    const total = try price.mul(quantity);

    try logger.info("价格计算", .{
        .price = price.value,
        .quantity = quantity.value,
        .total = total.value,
    });

    // 3. 使用时间戳
    const now = Time.Timestamp.now();
    const iso = try now.toISO8601(allocator);
    defer allocator.free(iso);

    try logger.info("当前时间", .{ .timestamp = iso });

    std.debug.print("\n✅ 程序运行成功！\n", .{});
}
```

### 2. 运行程序

```bash
zig run my_first_quant.zig -lc
```

**预期输出**:
```
[INFO] 价格计算 {"price":2950500000000000000000,"quantity":1500000000000000000,"total":4425750000000000000000}
[INFO] 当前时间 {"timestamp":"2025-12-25T10:30:00.000Z"}

✅ 程序运行成功！
```

---

## 连接交易所

### 1. 创建配置文件

创建 `config.json`:

```json
{
  "exchanges": [
    {
      "name": "hyperliquid",
      "enabled": true,
      "testnet": true,
      "credentials": {
        "type": "private_key",
        "private_key": "your-private-key-here"
      },
      "websocket": {
        "enabled": true,
        "url": "wss://api.hyperliquid-testnet.xyz/ws"
      },
      "http": {
        "info_url": "https://api.hyperliquid-testnet.xyz/info",
        "exchange_url": "https://api.hyperliquid-testnet.xyz/exchange"
      }
    }
  ],
  "logging": {
    "level": "info",
    "format": "json",
    "outputs": ["console"]
  }
}
```

**注意**:
- 将 `your-private-key-here` 替换为你的 Hyperliquid testnet 私钥
- **永远不要**提交包含真实私钥的配置文件到版本控制

### 2. 使用 Exchange Connector

查看示例: `examples/04_exchange_connector.zig`

```bash
# 运行交易所连接器示例
zig build run-example-connector
```

---

## 使用 CLI

### 1. 启动 CLI

```bash
zig build run
```

### 2. 可用命令

```bash
# 查看帮助
> help

# 查看市场行情
> ticker ETH

# 查看订单簿
> orderbook ETH 10

# 查看账户余额
> balance

# 查看持仓
> positions

# 下单（limit order）
> order buy ETH 1.0 2950.0

# 撤单
> cancel <order-id>

# 撤销所有订单
> cancel-all

# 查看所有未完成订单
> orders

# 退出
> exit
```

### 3. CLI 示例会话

```
zigQuant CLI - 量化交易框架
使用 'help' 查看可用命令

> ticker ETH
ETH Ticker:
  Bid: 2953.20
  Ask: 3009.10
  Last: 2981.15
  Volume 24h: 123456.78

> orderbook ETH 5
ETH Orderbook (Top 5):
  Bids:
    2953.20 | 10.5
    2953.10 | 5.2
    2952.90 | 8.3
    2952.70 | 15.1
    2952.50 | 12.8
  Asks:
    3009.10 | 8.2
    3009.30 | 12.5
    3009.50 | 6.7
    3009.70 | 9.3
    3009.90 | 11.2

> balance
Account Balance:
  USDC: 10000.00 (available: 9500.00, locked: 500.00)

> exit
再见！
```

---

## 配置文件

### 1. 配置结构

zigQuant 支持 JSON 配置文件，位于项目根目录的 `config.json`。

**完整配置示例**:

```json
{
  "exchanges": [
    {
      "name": "hyperliquid",
      "enabled": true,
      "testnet": true,
      "credentials": {
        "type": "private_key",
        "private_key": "0x..."
      },
      "websocket": {
        "enabled": true,
        "url": "wss://api.hyperliquid-testnet.xyz/ws",
        "reconnect": true,
        "ping_interval_ms": 30000
      },
      "http": {
        "info_url": "https://api.hyperliquid-testnet.xyz/info",
        "exchange_url": "https://api.hyperliquid-testnet.xyz/exchange",
        "timeout_ms": 5000,
        "rate_limit": 20
      }
    }
  ],
  "logging": {
    "level": "info",
    "format": "json",
    "outputs": ["console", "file"],
    "file_path": "logs/zigquant.log",
    "rotation": {
      "enabled": true,
      "max_size_mb": 100,
      "max_files": 10
    }
  },
  "trading": {
    "default_slippage": 0.001,
    "max_position_size": 1000.0,
    "risk_limits": {
      "max_loss_per_trade": 100.0,
      "max_daily_loss": 500.0
    }
  }
}
```

### 2. 环境变量覆盖

配置可以通过环境变量覆盖：

```bash
# 设置日志级别
export ZIGQUANT_LOGGING_LEVEL=debug

# 设置私钥（推荐用于生产环境）
export ZIGQUANT_EXCHANGES_0_CREDENTIALS_PRIVATE_KEY="0x..."

# 运行程序
zig build run
```

### 3. 加载配置

```zig
const Config = zigQuant.Config;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 从文件加载配置
    var config = try Config.loadFromFile(allocator, "config.json");
    defer config.deinit(allocator);

    // 使用配置
    const log_level = config.logging.level;  // .info
    const testnet = config.exchanges[0].testnet;  // true
}
```

---

## 下一步

### 📚 深入学习

1. **核心模块**
   - [Decimal 高精度数值](./docs/features/decimal/README.md)
   - [Time 时间处理](./docs/features/time/README.md)
   - [Logger 日志系统](./docs/features/logger/README.md)
   - [Config 配置管理](./docs/features/config/README.md)

2. **Exchange 集成**
   - [Exchange Router 抽象层](./docs/features/exchange-router/README.md)
   - [Hyperliquid Connector](./docs/features/hyperliquid-connector/README.md)

3. **Trading 模块**
   - [OrderBook 订单簿](./docs/features/orderbook/README.md)
   - [Order Manager 订单管理](./docs/features/order-manager/README.md)
   - [Position Tracker 仓位追踪](./docs/features/position-tracker/README.md)

### 🎓 示例教程

查看 [examples/README.md](./examples/README.md) 了解更多示例：

1. [01_core_basics.zig](./examples/01_core_basics.zig) - 核心模块基础
2. [02_websocket_stream.zig](./examples/02_websocket_stream.zig) - WebSocket 实时数据
3. [03_http_market_data.zig](./examples/03_http_market_data.zig) - HTTP 市场数据
4. [04_exchange_connector.zig](./examples/04_exchange_connector.zig) - 交易所连接器

运行示例：

```bash
zig build run-example-core
zig build run-example-websocket
zig build run-example-http
zig build run-example-connector
```

### 🔧 故障排查

遇到问题？查看 [故障排查文档](./docs/troubleshooting/README.md)：

- [Zig 0.15.2 兼容性问题](./docs/troubleshooting/zig-0.15.2-logger-compatibility.md)
- [Zig 0.15.2 快速参考](./docs/troubleshooting/quick-reference-zig-0.15.2.md)
- [BufferedWriter 陷阱](./docs/troubleshooting/bufferedwriter-trap.md)

### 🤝 参与贡献

- 查看 [CHANGELOG.md](./CHANGELOG.md) 了解项目历史
- 查看 [MVP 进度](./docs/MVP_V0.2.0_PROGRESS.md) 了解开发状态
- 阅读 [Constitution](./. agent/constitution.md) 了解开发规范

---

## 📞 获取帮助

- **文档**: 查看 [文档索引](./docs/DOCUMENTATION_INDEX.md)
- **Issues**: 在 GitHub 提交问题
- **Discussions**: 参与社区讨论

---

**祝您使用愉快！** 🚀

*更新时间: 2025-12-25*
*版本: v0.2.0*
