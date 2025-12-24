# CLI 界面 - 功能概览

> 命令行界面，用于快速测试交易功能和监控系统状态

**状态**: ✅ 已完成
**版本**: v0.2.0
**Story**: [../../stories/v0.2-mvp/012-cli-interface.md](../../stories/v0.2-mvp/012-cli-interface.md)
**最后更新**: 2025-12-24

---

## 📋 概述

CLI 界面是 ZigQuant MVP 阶段的主要用户界面，提供命令行方式访问所有核心交易功能。通过简洁的命令结构和交互式 REPL 模式，开发者可以快速测试策略、查询市场数据、执行交易操作并监控账户状态。

### 为什么需要 CLI 界面？

在 MVP 阶段，CLI 是最快速、最灵活的用户界面选择：

- **快速测试**: 无需图形界面即可测试所有交易功能
- **脚本支持**: 支持批处理和自动化测试脚本
- **开发友好**: 命令行输出便于日志记录和调试
- **轻量级**: 无额外依赖，启动快速
- **灵活性**: 支持单命令模式和交互式 REPL 模式

### 核心特性

- ✅ **简洁命令**: 直接命令模式，无需子命令层级
- ✅ **交互式 REPL**: 支持多命令会话
- ✅ **彩色输出**: 使用 ANSI 转义码的彩色终端输出
- ✅ **配置管理**: 支持 JSON 格式配置文件
- ✅ **错误处理**: 友好的错误提示和日志
- ✅ **实时交易**: 支持连接 Hyperliquid testnet/mainnet
- ✅ **完整功能**: 市场数据、订单管理、账户查询

---

## 🚀 快速开始

### 构建和运行

```bash
# 构建项目
$ zig build

# 使用配置文件运行
$ zig build run -- -c config.test.json <command>

# 或者直接运行编译后的二进制
$ ./zig-out/bin/zigQuant -c config.test.json <command>
```

### 配置文件

CLI 需要一个 JSON 配置文件来连接交易所。创建 `config.test.json`:

```json
{
  "exchanges": [{
    "name": "hyperliquid",
    "enabled": true,
    "testnet": true,
    "api_url": "https://api.hyperliquid-testnet.xyz",
    "ws_url": "wss://api.hyperliquid-testnet.xyz/ws",
    "credentials": {
      "api_key": "your_wallet_address",
      "secret_key": "your_private_key_hex"
    }
  }],
  "logging": {
    "level": "info",
    "format": "json",
    "output": "stdout"
  }
}
```

### 基本使用

#### 1. 查看帮助

```bash
$ zig build run -- -c config.test.json help

Available commands:
  help                           - Show this help message
  price <PAIR>                   - Get ticker/price for a trading pair
  book <PAIR> [depth]            - Get orderbook (default depth: 10)
  balance                        - Get account balance
  positions                      - Get open positions
  orders [PAIR]                  - Get open orders (optionally filtered by pair)
  buy <PAIR> <QTY> <PRICE>       - Place a limit buy order
  sell <PAIR> <QTY> <PRICE>      - Place a limit sell order
  cancel <ORDER_ID>              - Cancel a specific order
  cancel-all [PAIR]              - Cancel all orders (optionally filtered by pair)
  repl                           - Enter interactive REPL mode
```

#### 2. 查询市场数据

```bash
# 查询 BTC 价格
$ zig build run -- -c config.test.json price BTC-USDC
BTC-USDC: 101924.0000

# 查询订单簿（默认深度 10）
$ zig build run -- -c config.test.json book BTC-USDC
=== BTC-USDC Order Book (Depth: 10) ===

Asks:
  101925.0000 | 0.2150
  101926.0000 | 0.5320
  101927.0000 | 1.0450
  ...

Bids:
  101923.0000 | 0.3240
  101922.0000 | 0.8150
  101921.0000 | 1.2340
  ...

# 指定深度
$ zig build run -- -c config.test.json book ETH-USDC 5
```

#### 3. 查询账户信息

```bash
# 查询余额
$ zig build run -- -c config.test.json balance
=== Account Balance ===
Asset: USDC
  Total: 10000.0000
  Available: 9500.0000
  Locked: 500.0000

# 查询持仓
$ zig build run -- -c config.test.json positions
=== Open Positions ===
Position: BTC-USDC
  Side: LONG
  Size: 0.1000
  Entry Price: 100000.0000
  Unrealized PnL: +192.4000
  Leverage: 1.0000
```

#### 4. 订单操作

```bash
# 查询当前订单
$ zig build run -- -c config.test.json orders
=== Open Orders ===
Order #12345
  Pair: BTC-USDC
  Side: BUY
  Type: LIMIT
  Price: 100000.0000
  Quantity: 0.1000
  Filled: 0.0000
  Status: OPEN

# 按交易对筛选
$ zig build run -- -c config.test.json orders BTC-USDC

# 下限价买单
$ zig build run -- -c config.test.json buy BTC-USDC 0.1 100000.0
✓ Order created successfully
Order ID: 12346

# 下限价卖单
$ zig build run -- -c config.test.json sell ETH-USDC 1.0 3000.0
✓ Order created successfully
Order ID: 12347

# 撤销指定订单
$ zig build run -- -c config.test.json cancel 12346
✓ Order cancelled successfully

# 撤销所有订单
$ zig build run -- -c config.test.json cancel-all
✓ Cancelled 2 orders

# 撤销指定交易对的所有订单
$ zig build run -- -c config.test.json cancel-all BTC-USDC
✓ Cancelled 1 orders
```

#### 5. 交互式 REPL 模式

```bash
$ zig build run -- -c config.test.json repl

========================================
     ZigQuant CLI - REPL Mode
========================================
Type 'help' for commands, 'exit' to quit

> help
Available commands:
  help, price, book, balance, positions, orders, buy, sell, cancel, cancel-all, exit

> price BTC-USDC
BTC-USDC: 101924.0000

> balance
=== Account Balance ===
Asset: USDC
  Total: 10000.0000
  Available: 9500.0000
  Locked: 500.0000

> positions
=== Open Positions ===
Position: BTC-USDC
  Side: LONG
  Size: 0.1000
  Entry Price: 100000.0000
  Unrealized PnL: +192.4000
  Leverage: 1.0000

> exit
Goodbye!
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的命令和 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 核心 API

### 命令结构

```bash
zigQuant [OPTIONS] <COMMAND> [ARGS...]

Options:
  -c, --config <PATH>   配置文件路径 (必需)

Commands:
  help                           显示帮助信息
  price <PAIR>                   查询价格
  book <PAIR> [depth]            查询订单簿
  balance                        查询账户余额
  positions                      查询持仓
  orders [PAIR]                  查询订单
  buy <PAIR> <QTY> <PRICE>       限价买单
  sell <PAIR> <QTY> <PRICE>      限价卖单
  cancel <ORDER_ID>              撤销订单
  cancel-all [PAIR]              撤销所有订单
  repl                           进入 REPL 模式
```

### 命令详解

#### help
显示所有可用命令和帮助信息。

**用法**:
```bash
$ zigQuant -c config.test.json help
```

#### price
查询指定交易对的当前价格。

**用法**:
```bash
$ zigQuant -c config.test.json price <PAIR>
```

**参数**:
- `PAIR`: 交易对，格式为 `BASE-QUOTE`（如 `BTC-USDC`、`ETH-USDC`）

**示例**:
```bash
$ zigQuant -c config.test.json price BTC-USDC
BTC-USDC: 101924.0000
```

#### book
查询指定交易对的订单簿。

**用法**:
```bash
$ zigQuant -c config.test.json book <PAIR> [depth]
```

**参数**:
- `PAIR`: 交易对，格式为 `BASE-QUOTE`
- `depth`: 可选，订单簿深度（默认 10）

**示例**:
```bash
$ zigQuant -c config.test.json book BTC-USDC 5
```

#### balance
查询账户余额。需要在配置文件中提供有效的 API 凭证。

**用法**:
```bash
$ zigQuant -c config.test.json balance
```

#### positions
查询当前所有持仓。需要在配置文件中提供有效的 API 凭证。

**用法**:
```bash
$ zigQuant -c config.test.json positions
```

#### orders
查询当前所有未成交订单，可选择按交易对筛选。需要在配置文件中提供有效的 API 凭证。

**用法**:
```bash
$ zigQuant -c config.test.json orders [PAIR]
```

**参数**:
- `PAIR`: 可选，交易对筛选

**示例**:
```bash
# 查询所有订单
$ zigQuant -c config.test.json orders

# 仅查询 BTC-USDC 的订单
$ zigQuant -c config.test.json orders BTC-USDC
```

#### buy
下限价买单。需要在配置文件中提供有效的 API 凭证。

**用法**:
```bash
$ zigQuant -c config.test.json buy <PAIR> <QTY> <PRICE>
```

**参数**:
- `PAIR`: 交易对
- `QTY`: 购买数量
- `PRICE`: 限价价格

**示例**:
```bash
$ zigQuant -c config.test.json buy BTC-USDC 0.1 100000.0
```

#### sell
下限价卖单。需要在配置文件中提供有效的 API 凭证。

**用法**:
```bash
$ zigQuant -c config.test.json sell <PAIR> <QTY> <PRICE>
```

**参数**:
- `PAIR`: 交易对
- `QTY`: 出售数量
- `PRICE`: 限价价格

**示例**:
```bash
$ zigQuant -c config.test.json sell ETH-USDC 1.0 3000.0
```

#### cancel
撤销指定订单。需要在配置文件中提供有效的 API 凭证。

**用法**:
```bash
$ zigQuant -c config.test.json cancel <ORDER_ID>
```

**参数**:
- `ORDER_ID`: 订单 ID

**示例**:
```bash
$ zigQuant -c config.test.json cancel 12345
```

#### cancel-all
撤销所有订单，或撤销指定交易对的所有订单。需要在配置文件中提供有效的 API 凭证。

**用法**:
```bash
$ zigQuant -c config.test.json cancel-all [PAIR]
```

**参数**:
- `PAIR`: 可选，交易对筛选

**示例**:
```bash
# 撤销所有订单
$ zigQuant -c config.test.json cancel-all

# 仅撤销 BTC-USDC 的所有订单
$ zigQuant -c config.test.json cancel-all BTC-USDC
```

#### repl
进入交互式 REPL 模式，可以连续执行多个命令而无需重复启动程序。

**用法**:
```bash
$ zigQuant -c config.test.json repl
```

**REPL 特殊命令**:
- `exit` 或 `quit`: 退出 REPL 模式
- 其他命令与普通模式相同，但无需重复指定配置文件

---

## 📝 最佳实践

### ✅ DO

```bash
# 始终使用配置文件管理连接信息和凭证
$ zigQuant -c config.test.json price BTC-USDC

# 在脚本中使用单命令模式
$ ./trading_script.sh
#!/bin/bash
zigQuant -c config.test.json price BTC-USDC > price.txt
zigQuant -c config.test.json positions > positions.txt

# 使用 REPL 进行交互式测试和快速操作
$ zigQuant -c config.test.json repl

# 保护好配置文件权限
$ chmod 600 config.test.json

# 使用不同的配置文件区分 testnet 和 mainnet
$ zigQuant -c config.testnet.json balance   # testnet
$ zigQuant -c config.mainnet.json balance   # mainnet（谨慎！）
```

### ❌ DON'T

```bash
# 不要在命令行或环境变量中暴露私钥
$ export SECRET_KEY="0x..."  # 错误！

# 不要将包含真实私钥的配置文件提交到版本控制
$ git add config.mainnet.json  # 危险！

# 不要在自动化脚本中使用 REPL 模式
$ echo "price BTC-USDC" | zigQuant -c config.test.json repl  # 低效

# 不要在生产环境使用 testnet 配置（反之亦然）
$ zigQuant -c config.testnet.json buy BTC-USDC 10 100000.0  # 确认环境！
```

---

## 🎯 使用场景

### ✅ 适用

- **开发测试**: 快速验证交易逻辑和市场数据获取
- **策略调试**: 交互式执行订单和查询状态
- **手动交易**: 通过命令行快速下单和管理仓位
- **自动化脚本**: 批处理和定时任务
- **监控告警**: 定期查询账户和仓位状态
- **日志记录**: 输出可重定向至文件进行分析
- **学习实验**: 低成本（testnet）环境下学习交易 API

### ❌ 不适用

- **高频交易**: CLI 启动开销不适合高频场景
- **实时监控**: CLI 输出不适合持续刷新的实时数据流
- **图表可视化**: 需要专门的图表工具
- **复杂策略**: 需要编程语言实现策略逻辑

---

## 📊 性能指标

基于实际测试：

- **启动时间**: ~100-200ms（包含配置加载和交易所连接）
- **命令响应**: < 50ms（不含网络请求）
- **内存占用**: ~5-8MB（无内存泄漏）
- **REPL 延迟**: < 10ms（命令解析）
- **网络延迟**: 取决于 Hyperliquid API 响应时间（通常 100-500ms）

---

## 🐛 已知问题和限制

### 当前限制

1. **单交易所支持**: 目前仅支持 Hyperliquid（架构支持多交易所，待实现）
2. **仅限价单**: 暂不支持市价单、止损单等其他订单类型
3. **无命令历史**: REPL 模式下无法使用上下箭头浏览历史命令
4. **无自动补全**: 不支持 Tab 键自动补全
5. **简单输出格式**: 仅支持文本输出，不支持 JSON 等结构化格式

### 已修复的问题

- ✅ 控制台输出缓冲未刷新导致无输出
- ✅ Signer 懒加载导致的 balance/positions 失败
- ✅ 内存泄漏（config_parsed 和 connector 未释放）
- ✅ 日志格式问题（printf-style vs structured logging）
- ✅ orders 命令未实现

---

## 💡 未来改进

### 短期计划

- [ ] 支持市价单和其他订单类型
- [ ] 添加 JSON 输出格式（便于脚本解析）
- [ ] 实现命令历史（上下箭头）
- [ ] 支持命令自动补全（Tab 键）

### 长期计划

- [ ] 支持多交易所（Binance、OKX 等）
- [ ] WebSocket 实时数据流
- [ ] 批处理脚本模式（读取命令文件）
- [ ] TUI 界面（使用 termbox 或类似库）
- [ ] 命令别名系统
- [ ] 插件系统

---

## 🔧 故障排除

### 问题：启动时挂起或崩溃

**可能原因**:
- 配置文件路径错误或格式错误
- 网络连接问题

**解决方法**:
```bash
# 检查配置文件是否存在且格式正确
$ cat config.test.json | jq .

# 检查网络连接
$ ping api.hyperliquid-testnet.xyz

# 查看详细日志（修改配置文件中的 logging.level）
"logging": { "level": "debug", ... }
```

### 问题：balance/positions 返回错误

**可能原因**:
- 配置文件中的私钥不正确
- API 凭证格式错误

**解决方法**:
```bash
# 确认私钥格式（64 个十六进制字符）
"secret_key": "0123456789abcdef..."  # 不含 0x 前缀

# 确认 API 密钥（钱包地址，42 个字符，含 0x 前缀）
"api_key": "0x1234567890123456789012345678901234567890"
```

### 问题：订单创建失败

**可能原因**:
- 价格不合理（偏离市场价过多）
- 数量不符合交易所最小单位要求
- 账户余额不足

**解决方法**:
```bash
# 先查询当前价格
$ zigQuant -c config.test.json price BTC-USDC

# 查询账户余额
$ zigQuant -c config.test.json balance

# 使用合理的价格和数量下单
$ zigQuant -c config.test.json buy BTC-USDC 0.001 101000.0
```

---

## 📚 技术架构

### 核心组件

```
src/
├── main.zig                 # CLI 入口点
├── cli/
│   ├── cli.zig              # CLI 主逻辑
│   ├── format.zig           # 彩色输出格式化
│   └── repl.zig             # REPL 循环
├── core/
│   ├── config.zig           # 配置管理
│   ├── logger.zig           # 日志系统
│   ├── decimal.zig          # 高精度数字
│   └── errors.zig           # 错误处理
└── exchange/
    ├── interface.zig        # IExchange 接口
    ├── registry.zig         # 交易所注册表
    └── hyperliquid/
        ├── connector.zig    # Hyperliquid 实现
        ├── http.zig         # HTTP 客户端
        └── auth.zig         # Ed25519 签名
```

### 关键设计

1. **VTable 接口模式**: 使用 `anyopaque + vtable` 实现运行时多态
2. **懒加载**: Signer 仅在需要时初始化（避免不必要的熵阻塞）
3. **彩色输出**: 使用 `ConsoleWriter` 封装 ANSI 转义码
4. **内存安全**: 使用 `GeneralPurposeAllocator` 检测内存泄漏
5. **错误传播**: 使用 Zig 的 `!` 错误联合类型

---

*Last updated: 2025-12-24*
