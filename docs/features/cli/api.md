# CLI 界面 - API 参考

> 完整的命令和 API 文档

**最后更新**: 2025-12-23

---

## 命令概览

```bash
zigquant [OPTIONS] <COMMAND>

Commands:
  market      市场数据命令
  order       订单命令
  position    仓位命令
  account     账户命令
  config      配置命令
  repl        交互式模式

Options:
  -c, --config <PATH>   配置文件路径 (默认: config.toml)
  -v, --verbose         详细输出
  -h, --help            显示帮助
```

---

## 全局选项

### `--config` / `-c`

指定配置文件路径。

**语法**:
```bash
zigquant --config <PATH> <COMMAND>
```

**参数**:
- `<PATH>`: 配置文件路径（TOML 格式）

**默认**: `config.toml`

**示例**:
```bash
zigquant --config /etc/zigquant/prod.toml market ticker ETH
```

---

### `--verbose` / `-v`

启用详细输出模式，显示更多调试信息。

**语法**:
```bash
zigquant --verbose <COMMAND>
```

**示例**:
```bash
zigquant --verbose order buy ETH 0.1 2000.0
```

---

### `--help` / `-h`

显示帮助信息。

**语法**:
```bash
zigquant --help
zigquant <COMMAND> --help
```

**示例**:
```bash
zigquant --help
zigquant market --help
```

---

## Market 命令

查询市场数据。

### `market ticker`

显示指定交易对的最优买卖价和中间价。

**语法**:
```bash
zigquant market ticker <SYMBOL>
```

**参数**:
- `<SYMBOL>`: 交易对符号（如 ETH, BTC）

**输出**:
```
=== ETH Ticker ===
Best Bid: [数量] @ [价格]
Best Ask: [数量] @ [价格]
Mid Price: [价格]
```

**示例**:
```bash
$ zigquant market ticker ETH
=== ETH Ticker ===
Best Bid: 10.5 @ 2145.23
Best Ask: 8.2 @ 2145.67
Mid Price: 2145.45
```

---

### `market orderbook`

显示指定交易对的订单簿。

**语法**:
```bash
zigquant market orderbook <SYMBOL> [DEPTH]
```

**参数**:
- `<SYMBOL>`: 交易对符号
- `[DEPTH]`: 显示深度（可选，默认 10）

**输出**:
```
=== [SYMBOL] Order Book (Depth: [深度]) ===

Asks:
  [数量] @ [价格]
  ...

Bids:
  [数量] @ [价格]
  ...
```

**示例**:
```bash
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
```

---

### `market trades`

显示指定交易对的最近成交记录。

**语法**:
```bash
zigquant market trades <SYMBOL> [LIMIT]
```

**参数**:
- `<SYMBOL>`: 交易对符号
- `[LIMIT]`: 显示条数（可选，默认 20）

**示例**:
```bash
zigquant market trades ETH 10
```

---

## Order 命令

订单操作。

### `order buy`

下限价买单。

**语法**:
```bash
zigquant order buy <SYMBOL> <QUANTITY> <PRICE>
```

**参数**:
- `<SYMBOL>`: 交易对符号
- `<QUANTITY>`: 买入数量（Decimal）
- `<PRICE>`: 限价价格（Decimal）

**输出**:
```
Placing BUY order: [SYMBOL] [数量] @ [价格]
Order submitted: [订单ID]
```

**示例**:
```bash
$ zigquant order buy ETH 0.1 2000.0
Placing BUY order: ETH 0.1 @ 2000.0
Order submitted: CLIENT_1640000000000_12345
```

---

### `order sell`

下限价卖单。

**语法**:
```bash
zigquant order sell <SYMBOL> <QUANTITY> <PRICE>
```

**参数**:
- `<SYMBOL>`: 交易对符号
- `<QUANTITY>`: 卖出数量（Decimal）
- `<PRICE>`: 限价价格（Decimal）

**输出**:
```
Placing SELL order: [SYMBOL] [数量] @ [价格]
Order submitted: [订单ID]
```

**示例**:
```bash
$ zigquant order sell ETH 0.5 2200.0
Placing SELL order: ETH 0.5 @ 2200.0
Order submitted: CLIENT_1640000000000_12346
```

---

### `order cancel`

撤销指定订单。

**语法**:
```bash
zigquant order cancel <ORDER_ID>
```

**参数**:
- `<ORDER_ID>`: 订单ID（Client Order ID）

**输出**:
```
Cancelling order: [订单ID]
Order cancelled successfully
```

**示例**:
```bash
$ zigquant order cancel CLIENT_1640000000000_12345
Cancelling order: CLIENT_1640000000000_12345
Order cancelled successfully
```

---

### `order list`

列出所有活跃订单。

**语法**:
```bash
zigquant order list
```

**输出**:
```
Order ID                      | Symbol | Side | Quantity | Price   | Status
------------------------------|--------|------|----------|---------|--------
CLIENT_1640000000000_12345    | ETH    | BUY  | 0.1      | 2000.0  | OPEN
CLIENT_1640000000000_12346    | BTC    | SELL | 0.05     | 51000.0 | OPEN
```

**示例**:
```bash
zigquant order list
```

---

## Position 命令

仓位查询。

### `position list`

列出所有持仓。

**语法**:
```bash
zigquant position list
```

**输出**:
```
Symbol  | Side | Size | Entry Price | Current Price | PnL     | PnL %
--------|------|------|-------------|---------------|---------|-------
ETH     | LONG | 1.0  | 2100.0      | 2150.5        | +50.5   | +2.40%
BTC     | LONG | 0.1  | 50000.0     | 51000.0       | +100.0  | +2.00%
```

**示例**:
```bash
$ zigquant position list
Symbol  | Side | Size | Entry Price | PnL
--------|------|------|-------------|-----
ETH     | LONG | 1.0  | 2100.0      | +50.5
BTC     | LONG | 0.1  | 50000.0     | +100.0
```

---

### `position info`

查询指定交易对的仓位详情。

**语法**:
```bash
zigquant position info <SYMBOL>
```

**参数**:
- `<SYMBOL>`: 交易对符号

**输出**:
```
=== ETH Position ===
Side: LONG
Size: 1.0
Entry Price: 2100.0
Current Price: 2150.5
Unrealized PnL: +50.5 (+2.40%)
Leverage: 5x
Liquidation Price: 1890.0
```

**示例**:
```bash
zigquant position info ETH
```

---

## Account 命令

账户信息查询。

### `account info`

显示账户总览信息。

**语法**:
```bash
zigquant account info
```

**输出**:
```
=== Account Info ===
Account Value: $10,500.00
Available Balance: $5,200.00
Margin Used: $5,300.00
Unrealized PnL: +$150.50
```

**示例**:
```bash
$ zigquant account info
=== Account Info ===
Account Value: $10,500.00
Available Balance: $5,200.00
```

---

### `account balance`

显示资金余额详情。

**语法**:
```bash
zigquant account balance
```

**输出**:
```
Asset   | Total    | Available | Locked
--------|----------|-----------|--------
USDC    | 10000.0  | 8000.0    | 2000.0
```

**示例**:
```bash
zigquant account balance
```

---

## Config 命令

配置管理。

### `config show`

显示当前配置。

**语法**:
```bash
zigquant config show
```

**输出**:
```
=== Configuration ===
Exchange: Hyperliquid
API Endpoint: https://api.hyperliquid.xyz
WebSocket: wss://api.hyperliquid.xyz/ws
```

**示例**:
```bash
zigquant config show
```

---

## REPL 命令

交互式模式。

### `repl`

启动交互式 REPL 环境。

**语法**:
```bash
zigquant repl
```

**交互命令**:
在 REPL 模式下，可以使用所有上述命令（无需 `zigquant` 前缀）：

- `market ticker <SYMBOL>`
- `order buy <SYMBOL> <QTY> <PRICE>`
- `position list`
- `account info`
- `help` - 显示帮助
- `exit` / `quit` - 退出 REPL

**示例**:
```bash
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

zigquant> exit
Goodbye!
```

---

## 错误码

### 命令错误

| 错误信息 | 说明 | 解决方法 |
|---------|------|----------|
| `Error: No command specified` | 未指定命令 | 使用 `--help` 查看可用命令 |
| `Error: Unknown command` | 未知命令 | 检查命令拼写或使用 `--help` |
| `Error: Invalid symbol` | 无效的交易对 | 检查交易对符号是否正确 |
| `Error: Invalid quantity` | 无效的数量 | 确保数量为正数且格式正确 |
| `Error: Invalid price` | 无效的价格 | 确保价格为正数且格式正确 |

### 网络错误

| 错误信息 | 说明 | 解决方法 |
|---------|------|----------|
| `Error: Network connection failed` | 网络连接失败 | 检查网络连接 |
| `Error: API request timeout` | API 请求超时 | 重试或检查网络状况 |
| `Error: Invalid API response` | API 响应无效 | 联系技术支持 |

### 交易错误

| 错误信息 | 说明 | 解决方法 |
|---------|------|----------|
| `Error: Insufficient funds` | 余额不足 | 充值或减少下单量 |
| `Error: Order not found` | 订单不存在 | 检查订单ID是否正确 |
| `Error: Position not found` | 仓位不存在 | 确认交易对是否有持仓 |

---

## 完整示例

### 完整交易流程

```bash
# 1. 查看配置
$ zigquant config show

# 2. 查询市场价格
$ zigquant market ticker ETH
=== ETH Ticker ===
Best Bid: 10.5 @ 2145.23
Best Ask: 8.2 @ 2145.67
Mid Price: 2145.45

# 3. 查看订单簿
$ zigquant market orderbook ETH 5

# 4. 查询账户余额
$ zigquant account balance
Asset   | Total    | Available | Locked
--------|----------|-----------|--------
USDC    | 10000.0  | 8000.0    | 2000.0

# 5. 下买单
$ zigquant order buy ETH 0.1 2140.0
Placing BUY order: ETH 0.1 @ 2140.0
Order submitted: CLIENT_1640000000000_12345

# 6. 查看订单状态
$ zigquant order list
Order ID                      | Symbol | Side | Quantity | Price   | Status
------------------------------|--------|------|----------|---------|--------
CLIENT_1640000000000_12345    | ETH    | BUY  | 0.1      | 2140.0  | FILLED

# 7. 查看仓位
$ zigquant position list
Symbol  | Side | Size | Entry Price | PnL
--------|------|------|-------------|-----
ETH     | LONG | 0.1  | 2140.0      | +0.5

# 8. 平仓
$ zigquant order sell ETH 0.1 2145.5
Order submitted: CLIENT_1640000000000_12346
```

### 使用脚本自动化

```bash
#!/bin/bash
# trading_monitor.sh - 定期监控交易状态

while true; do
    echo "=== $(date) ==="

    # 查询账户
    zigquant account info

    # 查询仓位
    zigquant position list

    # 查询订单
    zigquant order list

    echo ""
    sleep 60
done
```

---

## 环境变量

支持通过环境变量配置：

| 变量名 | 说明 | 默认值 |
|-------|------|--------|
| `ZIGQUANT_CONFIG` | 配置文件路径 | `config.toml` |
| `ZIGQUANT_LOG_LEVEL` | 日志级别 | `info` |
| `ZIGQUANT_API_ENDPOINT` | API 端点 | - |

**示例**:
```bash
export ZIGQUANT_CONFIG=/etc/zigquant/prod.toml
export ZIGQUANT_LOG_LEVEL=debug
zigquant market ticker ETH
```

---

*完整 API 实现请参考: [implementation.md](./implementation.md)*
