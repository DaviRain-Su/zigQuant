# Integration Tests

集成测试用于验证 zigQuant 与 Hyperliquid testnet 的实际连接和交易功能。

## 前置要求

### 1. Hyperliquid Testnet 账户

你需要一个 Hyperliquid testnet 账户来运行集成测试。

**获取 testnet 账户**:
1. 访问 [Hyperliquid Testnet](https://app.hyperliquid-testnet.xyz/)
2. 连接你的钱包（MetaMask 或其他 EVM 钱包）
3. 从 faucet 获取测试 USDC

### 2. API 密钥配置

集成测试需要你的钱包地址和私钥。

**安全提示**:
- ⚠️ **仅使用 testnet 账户！**
- ⚠️ **切勿提交包含真实私钥的配置文件！**
- ⚠️ 使用环境变量或本地配置文件（已在 .gitignore 中）

## 配置方式

### 方式 1: 环境变量（推荐）

```bash
export ZIGQUANT_TEST_API_KEY="0x你的钱包地址"
export ZIGQUANT_TEST_API_SECRET="你的私钥十六进制（不带0x前缀）"
```

### 方式 2: 配置文件

1. 复制示例配置：
   ```bash
   cp tests/integration/test_config.example.json tests/integration/test_config.json
   ```

2. 编辑 `test_config.json` 填入你的凭证：
   ```json
   {
     "exchanges": [
       {
         "name": "hyperliquid",
         "api_key": "0x你的钱包地址",
         "api_secret": "你的私钥十六进制",
         "testnet": true
       }
     ]
   }
   ```

3. **重要**: `test_config.json` 已在 `.gitignore` 中，不会被提交到 git

### 验证配置

运行验证工具确保私钥和钱包地址匹配：

```bash
zig build verify-keys
```

**输出示例**:
```
✅ MATCH: Private key and address are correctly paired

You can use this configuration for Hyperliquid testnet.
Make sure the wallet 0x0c219488e878b66d9e098ed59ab714c5c29eb0df exists on testnet and has USDC balance.
```

如果显示不匹配，工具会告诉你如何修复。

## 运行测试

### 运行所有集成测试

```bash
zig build test-integration
```

### 运行单个集成测试

```bash
# WebSocket 订单簿测试
zig build test-ws-orderbook

# 订单生命周期测试（需要账户和余额）
zig build test-order-lifecycle
```

### 测试列表

集成测试包括以下测试用例：

#### 1. **连接测试**
- ✅ 连接到 Hyperliquid testnet
- ✅ 验证连接状态
- ✅ 断开连接

#### 2. **市场数据测试**
- ✅ 获取 ETH ticker（价格数据）
- ✅ 获取 BTC orderbook（订单簿）
- ✅ 验证数据有效性

#### 3. **账户测试**
- ✅ 查询账户余额
- ✅ 查询持仓信息

#### 4. **订单管理测试**
- ✅ 初始化 OrderManager
- ⚠️ 下单测试（注释掉，需手动启用）

#### 5. **仓位追踪测试**
- ✅ 初始化 PositionTracker
- ✅ 同步账户状态
- ✅ 获取统计信息
- ✅ 获取所有仓位

#### 6. **完整交易流程测试**
- ⚠️ 下单 → 撤单流程（注释掉，需手动启用）

#### 7. **订单生命周期测试** (`test-order-lifecycle`)
- ✅ 创建 Hyperliquid Connector
- ✅ 创建 OrderManager
- ✅ 提交限价订单（远离市场价，避免成交）
- ✅ 查询订单状态
- ✅ 取消订单
- ✅ 验证订单已取消
- ✅ 验证订单不在活跃订单列表中

**运行命令**:
```bash
zig build test-order-lifecycle
```

**测试流程**:
1. Phase 1: 创建 Hyperliquid Connector 并连接
2. Phase 2: 创建 OrderManager
3. Phase 3: 提交限价买单（ETH @ $1000，远低于市价）
4. Phase 4: 查询订单状态（等待 2 秒）
5. Phase 5: 取消订单
6. Phase 6: 验证订单状态为 `cancelled`
7. Phase 7: 验证订单不在活跃订单列表中

**前置要求**:
- Hyperliquid testnet 账户
- 账户中有足够的 USDC 余额（用于下单保证金）

## 测试输出示例

```
[debug] getTicker called for ETH-USDC (HL: ETH)

✓ ETH Ticker:
  Bid: $3421.50
  Ask: $3421.50
  Last: $3421.50

[debug] getOrderbook called for BTC (BTC-USDC) depth=5

✓ BTC Orderbook (depth 5):
  Bids:
    [0] Price: $68234.50, Qty: 0.125
    [1] Price: $68230.00, Qty: 0.250
    ...
  Asks:
    [0] Price: $68235.50, Qty: 0.100
    [1] Price: $68240.00, Qty: 0.300
    ...

[debug] getBalance called

✓ Account Balances:
  USDC:
    Total: 10000.00
    Available: 9800.00
    Locked: 200.00

✓ Positions (2):
  ETH-USDC:
    Side: buy
    Size: 0.1
    Entry Price: $3400.00
    Mark Price: $3421.50
    Unrealized PnL: $2.15
    Leverage: 5x
```

## 跳过的测试

如果配置文件不存在或环境变量未设置，集成测试将被跳过：

```
Skipping integration test: config not found
```

这是正常行为，不会导致 `zig build test` 失败。

## 实际交易测试

⚠️ **警告**: 默认情况下，涉及实际下单的测试已被注释掉。

如果你想测试实际下单功能：

1. 在 `hyperliquid_integration_test.zig` 中找到注释的测试用例
2. 仔细阅读代码，确保理解每个参数的含义
3. 调整参数（币种、数量、价格）
4. 取消注释并运行

**建议的安全测试方式**:
- 使用非常小的数量（如 0.001 ETH）
- 使用远离市场价的价格（如市价的 10%），确保不会成交
- 测试后立即撤单

示例（已注释的测试）:
```zig
// 0.001 ETH @ $100（远低于市价，不会成交）
const order_request = zigQuant.OrderRequest{
    .pair = .{ .base = "ETH", .quote = "USDC" },
    .side = .buy,
    .amount = try zigQuant.Decimal.fromString("0.001"),
    .price = try zigQuant.Decimal.fromString("100.0"),
    .time_in_force = .gtc,
};
```

## 故障排查

### 错误: "config not found"

**原因**: 未找到配置文件且未设置环境变量

**解决**:
- 检查环境变量是否设置：`echo $ZIGQUANT_TEST_API_KEY`
- 检查配置文件是否存在：`ls tests/integration/test_config.json`

### 错误: "SignerRequired"

**原因**: API 密钥或私钥未正确配置

**解决**:
- 验证 `api_key` 格式：应以 `0x` 开头
- 验证 `api_secret` 格式：64 位十六进制字符串（不带 `0x`）

### 错误: "SymbolNotFound"

**原因**: 交易对不存在或格式错误

**解决**:
- 确认使用正确的交易对（如 "ETH-USDC"）
- 确认符号在 Hyperliquid testnet 可用

### 错误: "OrderRejected"

**原因**: 订单被交易所拒绝

**可能原因**:
- 余额不足
- 订单参数无效（价格、数量）
- 触发风控限制

## 持续集成（CI）

集成测试需要网络访问和 API 凭证，通常不在 CI 中运行。

如果需要在 CI 中运行：

1. 在 CI 环境设置密钥变量：
   - `ZIGQUANT_TEST_API_KEY`
   - `ZIGQUANT_TEST_API_SECRET`

2. 确保 CI 可以访问 Hyperliquid testnet（无防火墙阻止）

3. 使用专用的 CI 测试账户（不要用个人账户）

## 下一步

通过所有集成测试后，你可以：

1. 实现自己的交易策略
2. 连接 mainnet（⚠️ 真实资金，谨慎操作）
3. 开发 CLI 工具
4. 集成到自动化交易系统

---

**提示**: 集成测试是验证系统功能的重要环节，但也会消耗网络配额和可能产生手续费（testnet 免费）。请合理运行测试。
