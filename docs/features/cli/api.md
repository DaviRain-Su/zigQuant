# CLI 界面 - API 参考

> 完整的命令和 API 文档

**状态**: ✅ 已完成
**版本**: v0.2.0
**最后更新**: 2025-12-24

---

## 📋 命令概览

zigQuant CLI 使用简洁的直接命令模式，无需子命令层级。

```bash
zigQuant [OPTIONS] <COMMAND> [ARGS...]

Options:
  -c, --config <PATH>   配置文件路径 (必需)

Commands:
  help                           显示帮助信息
  price <PAIR>                   查询交易对价格
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

---

## 🔧 全局选项

### `--config` / `-c` (必需)

指定 JSON 格式的配置文件路径。

**语法**:
```bash
zigQuant -c <PATH> <COMMAND>
```

**参数**:
- `<PATH>`: 配置文件路径（JSON 格式）

**示例**:
```bash
zigQuant -c config.test.json price BTC-USDC
zigQuant -c /etc/zigquant/prod.json balance
```

**配置文件格式**:
```json
{
  "exchanges": [{
    "name": "hyperliquid",
    "enabled": true,
    "testnet": true,
    "api_url": "https://api.hyperliquid-testnet.xyz",
    "ws_url": "wss://api.hyperliquid-testnet.xyz/ws",
    "credentials": {
      "api_key": "0x...",
      "secret_key": "..."
    }
  }],
  "logging": {
    "level": "info",
    "format": "json",
    "output": "stdout"
  }
}
```

---

## 📖 命令详细参考

### 1. help - 显示帮助

显示所有可用命令和帮助信息。

**语法**:
```bash
zigQuant -c <config> help
```

**输出**:
```
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

Examples:
  zigQuant -c config.json price BTC-USDC
  zigQuant -c config.json buy ETH-USDC 1.0 3000.0
  zigQuant -c config.json repl
```

**示例**:
```bash
$ zig build run -- -c config.test.json help
```

---

### 2. price - 查询价格

查询指定交易对的当前价格。

**语法**:
```bash
zigQuant -c <config> price <PAIR>
```

**参数**:
- `<PAIR>`: 交易对，格式为 `BASE-QUOTE`（如 `BTC-USDC`, `ETH-USDC`）

**返回**:
- 成功: 显示价格（mid price）
- 失败: 错误信息

**输出格式**:
```
<PAIR>: <PRICE>
```

**示例**:
```bash
$ zigQuant -c config.test.json price BTC-USDC
BTC-USDC: 101924.0000

$ zigQuant -c config.test.json price ETH-USDC
ETH-USDC: 3842.5000
```

**错误示例**:
```bash
$ zigQuant -c config.test.json price INVALID
✗ Error: Symbol not found
```

**实现位置**: `src/cli/cli.zig::cmdPrice()`

---

### 3. book - 查询订单簿

查询指定交易对的订单簿（买卖盘口）。

**语法**:
```bash
zigQuant -c <config> book <PAIR> [depth]
```

**参数**:
- `<PAIR>`: 交易对
- `[depth]`: 可选，订单簿深度（默认 10）

**返回**:
- 成功: 显示订单簿（asks 和 bids）
- 失败: 错误信息

**输出格式**:
```
=== <PAIR> Order Book (Depth: <depth>) ===

Asks:
  <price> | <quantity>
  ...

Bids:
  <price> | <quantity>
  ...
```

**示例**:
```bash
$ zigQuant -c config.test.json book BTC-USDC
=== BTC-USDC Order Book (Depth: 10) ===

Asks:
  101925.0000 | 0.2150
  101926.0000 | 0.5320
  101927.0000 | 1.0450
  101928.0000 | 0.3210
  101929.0000 | 0.7650
  101930.0000 | 1.2340
  101931.0000 | 0.4560
  101932.0000 | 0.8900
  101933.0000 | 1.5670
  101934.0000 | 0.2340

Bids:
  101923.0000 | 0.3240
  101922.0000 | 0.8150
  101921.0000 | 1.2340
  101920.0000 | 0.5670
  101919.0000 | 0.9870
  101918.0000 | 1.4560
  101917.0000 | 0.3450
  101916.0000 | 0.7890
  101915.0000 | 1.6780
  101914.0000 | 0.2100
```

**指定深度示例**:
```bash
$ zigQuant -c config.test.json book ETH-USDC 5
=== ETH-USDC Order Book (Depth: 5) ===

Asks:
  3843.0000 | 5.2150
  3844.0000 | 3.5320
  3845.0000 | 2.0450
  3846.0000 | 4.3210
  3847.0000 | 1.7650

Bids:
  3842.0000 | 3.3240
  3841.0000 | 5.8150
  3840.0000 | 2.2340
  3839.0000 | 4.5670
  3838.0000 | 1.9870
```

**实现位置**: `src/cli/cli.zig::cmdBook()`

---

### 4. balance - 查询余额

查询账户余额。需要在配置文件中提供有效的 API 凭证。

**语法**:
```bash
zigQuant -c <config> balance
```

**参数**: 无

**返回**:
- 成功: 显示所有资产余额
- 失败: 错误信息（如凭证无效）

**输出格式**:
```
=== Account Balance ===
Asset: <ASSET>
  Total: <TOTAL>
  Available: <AVAILABLE>
  Locked: <LOCKED>
```

**示例**:
```bash
$ zigQuant -c config.test.json balance
=== Account Balance ===
Asset: USDC
  Total: 10000.0000
  Available: 9500.0000
  Locked: 500.0000
```

**错误示例**:
```bash
$ zigQuant -c invalid_config.json balance
✗ Error: SignerRequired - Invalid credentials
```

**实现位置**: `src/cli/cli.zig::cmdBalance()`

**注意事项**:
- 需要有效的 Hyperliquid 私钥（`secret_key`）
- 私钥格式：64 个十六进制字符，不含 `0x` 前缀
- API 密钥格式：42 个字符，含 `0x` 前缀（钱包地址）

---

### 5. positions - 查询持仓

查询当前所有持仓。需要在配置文件中提供有效的 API 凭证。

**语法**:
```bash
zigQuant -c <config> positions
```

**参数**: 无

**返回**:
- 成功: 显示所有持仓
- 失败: 错误信息

**输出格式**:
```
=== Open Positions ===
Position: <PAIR>
  Side: <LONG|SHORT>
  Size: <SIZE>
  Entry Price: <ENTRY_PRICE>
  Unrealized PnL: <PNL>
  Leverage: <LEVERAGE>
```

**示例**:
```bash
$ zigQuant -c config.test.json positions
=== Open Positions ===
Position: BTC-USDC
  Side: LONG
  Size: 0.1000
  Entry Price: 100000.0000
  Unrealized PnL: +192.4000
  Leverage: 1.0000

Position: ETH-USDC
  Side: LONG
  Size: 1.0000
  Entry Price: 3800.0000
  Unrealized PnL: +42.5000
  Leverage: 1.0000
```

**无持仓示例**:
```bash
$ zigQuant -c config.test.json positions
=== Open Positions ===
(No open positions)
```

**实现位置**: `src/cli/cli.zig::cmdPositions()`

---

### 6. orders - 查询订单

查询当前所有未成交订单，可选择按交易对筛选。需要在配置文件中提供有效的 API 凭证。

**语法**:
```bash
zigQuant -c <config> orders [PAIR]
```

**参数**:
- `[PAIR]`: 可选，交易对筛选

**返回**:
- 成功: 显示所有未成交订单
- 失败: 错误信息

**输出格式**:
```
=== Open Orders ===
Order #<ORDER_ID>
  Pair: <PAIR>
  Side: <BUY|SELL>
  Type: <LIMIT|MARKET>
  Price: <PRICE>
  Quantity: <QUANTITY>
  Filled: <FILLED>
  Status: <OPEN|PARTIAL>
```

**示例**:
```bash
$ zigQuant -c config.test.json orders
=== Open Orders ===
Order #12345
  Pair: BTC-USDC
  Side: BUY
  Type: LIMIT
  Price: 100000.0000
  Quantity: 0.1000
  Filled: 0.0000
  Status: OPEN

Order #12346
  Pair: ETH-USDC
  Side: SELL
  Type: LIMIT
  Price: 3900.0000
  Quantity: 1.0000
  Filled: 0.5000
  Status: PARTIAL
```

**按交易对筛选示例**:
```bash
$ zigQuant -c config.test.json orders BTC-USDC
=== Open Orders ===
Order #12345
  Pair: BTC-USDC
  Side: BUY
  Type: LIMIT
  Price: 100000.0000
  Quantity: 0.1000
  Filled: 0.0000
  Status: OPEN
```

**无订单示例**:
```bash
$ zigQuant -c config.test.json orders
=== Open Orders ===
(No open orders)
```

**实现位置**: `src/cli/cli.zig::cmdOrders()`

---

### 7. buy - 限价买单

下限价买单。需要在配置文件中提供有效的 API 凭证。

**语法**:
```bash
zigQuant -c <config> buy <PAIR> <QTY> <PRICE>
```

**参数**:
- `<PAIR>`: 交易对
- `<QTY>`: 购买数量（Decimal）
- `<PRICE>`: 限价价格（Decimal）

**返回**:
- 成功: 显示订单 ID
- 失败: 错误信息（余额不足、参数无效等）

**输出格式**:
```
✓ Order created successfully
Order ID: <ORDER_ID>
```

**示例**:
```bash
$ zigQuant -c config.test.json buy BTC-USDC 0.1 100000.0
✓ Order created successfully
Order ID: 12347
```

**错误示例**:
```bash
$ zigQuant -c config.test.json buy BTC-USDC 100.0 100000.0
✗ Error: Insufficient funds

$ zigQuant -c config.test.json buy BTC-USDC -0.1 100000.0
✗ Error: Invalid quantity (must be positive)

$ zigQuant -c config.test.json buy BTC-USDC 0.1 0
✗ Error: Invalid price (must be positive)
```

**实现位置**: `src/cli/cli.zig::cmdBuy()`

**注意事项**:
- 数量和价格必须为正数
- 检查账户余额是否足够
- 价格偏离市场价过多可能导致订单长时间未成交

---

### 8. sell - 限价卖单

下限价卖单。需要在配置文件中提供有效的 API 凭证。

**语法**:
```bash
zigQuant -c <config> sell <PAIR> <QTY> <PRICE>
```

**参数**:
- `<PAIR>`: 交易对
- `<QTY>`: 出售数量（Decimal）
- `<PRICE>`: 限价价格（Decimal）

**返回**:
- 成功: 显示订单 ID
- 失败: 错误信息

**输出格式**:
```
✓ Order created successfully
Order ID: <ORDER_ID>
```

**示例**:
```bash
$ zigQuant -c config.test.json sell ETH-USDC 1.0 3900.0
✓ Order created successfully
Order ID: 12348
```

**实现位置**: `src/cli/cli.zig::cmdSell()`

---

### 9. cancel - 撤销订单

撤销指定订单。需要在配置文件中提供有效的 API 凭证。

**语法**:
```bash
zigQuant -c <config> cancel <ORDER_ID>
```

**参数**:
- `<ORDER_ID>`: 订单 ID（整数）

**返回**:
- 成功: 确认消息
- 失败: 错误信息（订单不存在等）

**输出格式**:
```
✓ Order cancelled successfully
```

**示例**:
```bash
$ zigQuant -c config.test.json cancel 12347
✓ Order cancelled successfully
```

**错误示例**:
```bash
$ zigQuant -c config.test.json cancel 99999
✗ Error: Order not found
```

**实现位置**: `src/cli/cli.zig::cmdCancel()`

---

### 10. cancel-all - 撤销所有订单

撤销所有订单，或撤销指定交易对的所有订单。需要在配置文件中提供有效的 API 凭证。

**语法**:
```bash
zigQuant -c <config> cancel-all [PAIR]
```

**参数**:
- `[PAIR]`: 可选，交易对筛选

**返回**:
- 成功: 显示撤销的订单数量
- 失败: 错误信息

**输出格式**:
```
✓ Cancelled <N> orders
```

**示例**:
```bash
# 撤销所有订单
$ zigQuant -c config.test.json cancel-all
✓ Cancelled 3 orders

# 仅撤销 BTC-USDC 的订单
$ zigQuant -c config.test.json cancel-all BTC-USDC
✓ Cancelled 1 orders

# 无订单可撤销
$ zigQuant -c config.test.json cancel-all
✓ Cancelled 0 orders
```

**实现位置**: `src/cli/cli.zig::cmdCancelAll()`

**警告**: 此操作不可逆，请谨慎使用。

---

### 11. repl - 交互式模式

进入交互式 REPL 模式，可以连续执行多个命令而无需重复启动程序。

**语法**:
```bash
zigQuant -c <config> repl
```

**参数**: 无

**REPL 特殊命令**:
- `exit` 或 `quit`: 退出 REPL 模式
- `help`: 显示帮助
- 其他命令与普通模式相同，但无需指定配置文件和程序名

**示例**:
```bash
$ zigQuant -c config.test.json repl

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

> orders
=== Open Orders ===
(No open orders)

> buy BTC-USDC 0.01 101000.0
✓ Order created successfully
Order ID: 12349

> orders
=== Open Orders ===
Order #12349
  Pair: BTC-USDC
  Side: BUY
  Type: LIMIT
  Price: 101000.0000
  Quantity: 0.0100
  Filled: 0.0000
  Status: OPEN

> cancel 12349
✓ Order cancelled successfully

> exit
Goodbye!
```

**实现位置**: `src/cli/repl.zig::run()`

**优势**:
- 无需每次重复启动程序
- 更快的命令执行（连接复用）
- 适合交互式测试和调试

---

## 🚨 错误处理

### 命令参数错误

| 错误信息 | 原因 | 解决方法 |
|---------|------|----------|
| `Invalid arguments` | 参数数量或格式错误 | 检查命令语法，使用 `help` 查看正确用法 |
| `Invalid trading pair format` | 交易对格式错误 | 使用 `BASE-QUOTE` 格式（如 `BTC-USDC`） |
| `Invalid quantity` | 数量格式错误或为负数 | 确保数量为正数 |
| `Invalid price` | 价格格式错误或为负数 | 确保价格为正数 |

### 配置文件错误

| 错误信息 | 原因 | 解决方法 |
|---------|------|----------|
| `Failed to load config` | 配置文件不存在或格式错误 | 检查文件路径和 JSON 格式 |
| `Invalid config format` | JSON 解析失败 | 使用 `jq .` 验证 JSON 格式 |
| `Missing required field` | 配置缺少必需字段 | 参考配置文件模板补全 |

### 网络和 API 错误

| 错误信息 | 原因 | 解决方法 |
|---------|------|----------|
| `Failed to connect` | 无法连接到交易所 | 检查网络连接和 API URL |
| `API request failed` | API 请求失败 | 查看详细错误信息，检查凭证 |
| `SignerRequired` | 缺少或无效的私钥 | 检查配置文件中的 `credentials` |

### 交易错误

| 错误信息 | 原因 | 解决方法 |
|---------|------|----------|
| `Insufficient funds` | 余额不足 | 查询余额，减少订单数量 |
| `Order not found` | 订单不存在或已完成 | 使用 `orders` 查看当前订单 |
| `Symbol not found` | 交易对不存在 | 检查交易对符号是否正确 |

---

## 📊 完整使用示例

### 示例 1: 查询市场数据

```bash
# 查询 BTC 价格
$ zigQuant -c config.test.json price BTC-USDC
BTC-USDC: 101924.0000

# 查询 ETH 订单簿
$ zigQuant -c config.test.json book ETH-USDC 5
=== ETH-USDC Order Book (Depth: 5) ===
Asks:
  3843.0000 | 5.2150
  ...
```

### 示例 2: 账户查询

```bash
# 查询余额
$ zigQuant -c config.test.json balance
=== Account Balance ===
Asset: USDC
  Total: 10000.0000
  Available: 9500.0000
  Locked: 500.0000

# 查询持仓
$ zigQuant -c config.test.json positions
=== Open Positions ===
Position: BTC-USDC
  Side: LONG
  Size: 0.1000
  ...

# 查询订单
$ zigQuant -c config.test.json orders
=== Open Orders ===
(No open orders)
```

### 示例 3: 交易流程

```bash
# 1. 查询价格
$ zigQuant -c config.test.json price BTC-USDC
BTC-USDC: 101924.0000

# 2. 下买单
$ zigQuant -c config.test.json buy BTC-USDC 0.01 101000.0
✓ Order created successfully
Order ID: 12350

# 3. 查询订单
$ zigQuant -c config.test.json orders BTC-USDC
=== Open Orders ===
Order #12350
  Pair: BTC-USDC
  Side: BUY
  Type: LIMIT
  Price: 101000.0000
  Quantity: 0.0100
  Filled: 0.0000
  Status: OPEN

# 4. 撤销订单
$ zigQuant -c config.test.json cancel 12350
✓ Order cancelled successfully
```

### 示例 4: REPL 模式

```bash
$ zigQuant -c config.test.json repl
========================================
     ZigQuant CLI - REPL Mode
========================================
Type 'help' for commands, 'exit' to quit

> price BTC-USDC
BTC-USDC: 101924.0000

> price ETH-USDC
ETH-USDC: 3842.5000

> balance
=== Account Balance ===
Asset: USDC
  Total: 10000.0000
  ...

> exit
Goodbye!
```

### 示例 5: 批处理脚本

```bash
#!/bin/bash
# monitor.sh - 监控脚本

CONFIG="config.test.json"

echo "=== Market Data ==="
zigQuant -c $CONFIG price BTC-USDC
zigQuant -c $CONFIG price ETH-USDC

echo ""
echo "=== Account Status ==="
zigQuant -c $CONFIG balance
zigQuant -c $CONFIG positions
zigQuant -c $CONFIG orders
```

运行:
```bash
$ chmod +x monitor.sh
$ ./monitor.sh
=== Market Data ===
BTC-USDC: 101924.0000
ETH-USDC: 3842.5000

=== Account Status ===
=== Account Balance ===
Asset: USDC
  Total: 10000.0000
  ...
```

---

## 🔗 相关文档

- [功能概览](./README.md) - CLI 功能介绍和快速开始
- [实现细节](./implementation.md) - 内部架构和设计
- [测试文档](./testing.md) - 测试覆盖和结果
- [Bug 列表](./bugs.md) - 已知问题和已修复 bug
- [变更日志](./changelog.md) - 版本历史

---

## 📞 技术支持

如遇问题，请参考:
1. [故障排除指南](./README.md#故障排除)
2. [Bug 列表](./bugs.md)
3. GitHub Issues

---

*API 参考文档 - 完整且准确 ✅*
*最后更新: 2025-12-24*
