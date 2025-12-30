# Hyperliquid 连接器 - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-30

---

## [Unreleased]

### Planned
- [ ] 实现异步 HTTP 请求
- [ ] 添加连接池支持
- [ ] 实现批量 API 请求
- [ ] 支持 HTTP/2
- [ ] 修复 AlertManager HashMap 内存问题

---

## [0.2.6] - 2025-12-30

### 🎉 实盘交易签名问题修复

本次发布修复了 2 个关键的签名相关 bug，使实盘网格交易能够正常运行。

### Fixed
- 🐛 **Bug #7: 价格/数量格式化保留尾部零导致签名失败** (Critical)
  - 问题：`formatPrice()` 输出 `"87000.0"` 而非 `"87000"`，导致签名验证失败
  - 现象：每次运行返回不同的错误地址 "User or API Wallet does not exist: 0xXXXX"
  - 修复：更新 `formatPrice()` 和 `formatSize()` 移除尾部零
  - 原理：匹配 Python SDK 的 `Decimal.normalize()` 行为
  - 位置：
    - `src/exchange/hyperliquid/types.zig`:304-336 - `formatPrice()`
    - `src/exchange/hyperliquid/types.zig`:347-379 - `formatSize()`
  - 测试：
    - `87000.0` → `"87000"` ✅
    - `87736.5` → `"87736.5"` ✅
    - `0.0010` → `"0.001"` ✅

- 🐛 **Bug #8: cancelAllOrders 使用错误的账户地址** (High)
  - 问题：使用 `signer.address`（API wallet）而非 `config.api_key`（主账户）
  - 修复：改用 `self.config.api_key` 查询挂单
  - 位置：`src/exchange/hyperliquid/connector.zig`:555-556

### Known Issues
- ⚠️ **AlertManager HashMap 内存问题**
  - 状态：临时禁用 `isThrottled()` 函数
  - 影响：告警节流功能暂时不可用
  - 位置：`src/risk/alert.zig`

### Technical Highlights
- 📐 **Wire Format 兼容性**：价格/数量字符串格式现在与 Python SDK 完全兼容
- 🔐 **签名验证**：实盘订单签名验证通过，订单正常执行
- 📊 **Grid Trading**：网格策略实盘测试通过
  - LONG Exit FILLED
  - SHORT Entry FILLED

### Performance
- ⚡ 下单延迟：~200-300ms（testnet）
- ⚡ 网格策略：稳定运行

---

## [0.2.5] - 2025-12-25

### 🎉 重大突破：完整订单生命周期集成测试通过

本次发布完成了 Hyperliquid 订单生命周期的完整实现，修复了 4 个关键 bug，新增 MessagePack 编码器，实现了从下单→查询→撤单的完整流程。

### Added
- ✨ **MessagePack 编码器**（`src/exchange/hyperliquid/msgpack.zig`）
  - 实现 MessagePack 格式编码（Hyperliquid 要求）
  - 支持编码：Map, Array, String, Boolean, Uint
  - 新增 `packOrderAction()` - 编码下单请求
  - 新增 `packCancelAction()` - 编码撤单请求
  - 包含完整的单元测试（6 个测试用例）
  - 符合 MessagePack 规范（https://msgpack.org/）

- ✅ **订单生命周期集成测试**（`tests/integration/order_lifecycle_test.zig`）
  - Phase 1: 连接 Hyperliquid testnet
  - Phase 2: 获取 BTC 市场信息（meta + oracle price）
  - Phase 3: 查询初始账户状态（balance + positions）
  - Phase 4: 下单（使用 oracle price 避免价格偏差过大）
  - Phase 5: 验证订单成功提交（检查 exchange_order_id）
  - Phase 6: 撤单
  - Phase 7: 验证订单已撤销
  - Phase 8: 查询最终账户状态
  - ✅ 所有阶段通过
  - ✅ 无内存泄漏（0 leaks）

### Fixed
- 🐛 **Bug #1: Asset index hardcoded to 0** (Critical)
  - 问题：所有订单都被提交到 SOL 市场（index 0），导致"价格偏离 80%"错误
  - 修复：在 `types.zig` 添加 `asset_index` 字段，在 `connector.zig` 动态查询 asset index
  - 影响：所有下单操作
  - 位置：
    - `src/exchange/hyperliquid/types.zig`:66 - 添加 `asset_index` 字段
    - `src/exchange/hyperliquid/connector.zig`:387 - 查询 asset index
    - `src/exchange/hyperliquid/exchange_api.zig`:67 - 使用 `asset_index`

- 🐛 **Bug #2: Querying wrong account address** (High)
  - 问题：查询订单时使用 API wallet 地址而非主账户地址，导致返回空结果
  - 修复：在查询操作中使用 `self.config.api_key`（主账户地址）
  - 影响：`getOrder()`, `getOpenOrders()`, 间接影响 `cancelOrder()`
  - Hyperliquid 双地址系统：
    - **主账户地址** (api_key): 持有资产和订单
    - **API wallet 地址** (signer.address): 用于签名操作
  - 位置：
    - `src/exchange/hyperliquid/connector.zig`:489 - `getOrder()`
    - `src/exchange/hyperliquid/connector.zig`:604 - `getOpenOrders()`
    - `src/exchange/hyperliquid/connector.zig`:428 - `cancelOrder()` 注释

- 🐛 **Bug #3: client_order_id memory leak** (High)
  - 问题：`order_manager.zig` 过早释放 `client_order_id`，导致 `Order` 指向已释放内存（悬空指针）
  - 修复：
    - `order_manager.zig`: 延后释放，让 `order_store` 先完成 key 复制
    - `order_store.zig`: `dupe` key 并统一 `Order.client_order_id` 指针
  - 影响：所有使用 `client_order_id` 的操作
  - 位置：
    - `src/trading/order_manager.zig`:192-202 - 调整释放时机
    - `src/trading/order_store.zig`:41-49 - 统一指针

- 🐛 **Bug #4: Cancel order msgpack encoding** (Critical)
  - 问题：`cancelOrder()` 签名 JSON 字符串而非 msgpack 数据，导致签名验证失败
  - 现象：每次返回不同的错误地址 "User or API Wallet does not exist: 0xXXXXXXXX"
  - 修复：
    - 新增 `msgpack.zig` 中的 `CancelRequest` 和 `packCancelAction()`
    - 在 `exchange_api.zig` 中使用 msgpack 编码后签名
  - 影响：`cancelOrder()` 撤单操作
  - 位置：
    - `src/exchange/hyperliquid/msgpack.zig`:226-276 - 新增 cancel action 编码
    - `src/exchange/hyperliquid/exchange_api.zig`:210-222 - 使用 msgpack 签名

### Changed
- 🔧 `ExchangeAPI.placeOrder()` 现在使用动态 asset index 而非硬编码
- 🔧 `Connector.createOrder()` 调用 `getAssetIndex()` 查询 asset index
- 🔧 `OrderManager.submitOrder()` 调整内存管理策略（延后释放 client_order_id）
- 🔧 `OrderStore.add()` 统一 client_order_id 指针管理

### Tests
- ✅ 新增完整的订单生命周期集成测试（8 个阶段）
- ✅ 新增 MessagePack 编码器单元测试（6 个测试用例）
- ✅ 所有集成测试通过（testnet 验证）
- ✅ 内存泄漏检测：0 leaks

### Technical Highlights
- 📐 **MessagePack 编码**：完全符合 Hyperliquid 签名要求
  - 固定字段顺序：`{"type": ..., "orders": [...], "grouping": ...}`
  - 固定订单字段顺序：`{a, b, p, s, r, t}`
  - 固定取消字段顺序：`{a, o}`

- 🔐 **EIP-712 签名**：完整的 Keccak-256 + Phantom Agent 签名流程
  - Phantom Agent: `{"source": "b", "connectionId": keccak256(nonce)}`
  - 签名数据：msgpack(action)
  - 签名算法：Ed25519

- 🏗️ **双地址架构**：正确区分主账户和 API wallet
  - 查询操作：使用主账户地址（api_key）
  - 签名操作：使用 API wallet（signer.address）

### Performance
- ⚡ 订单提交延迟：~200-300ms（testnet）
- ⚡ 订单查询延迟：~100-150ms（testnet）
- ⚡ 撤单延迟：~200-250ms（testnet）
- 💾 内存使用：稳定，无泄漏

### Documentation
- 📝 更新 `bugs.md`：记录所有 4 个修复的 bug
- 📝 更新 `changelog.md`：详细版本变更记录
- 📝 代码注释：添加关键逻辑说明

### Commit
- 🔖 Commit hash: `40355bd`
- 📦 Files changed: 11 files
- ➕ Insertions: 1353
- ➖ Deletions: 68

---

## [0.2.4] - 2025-12-24

### Fixed
- 🐛 **Bug #4: Signer lazy loading for balance/positions commands**
  - 修复 `getBalance()` 和 `getPositions()` 在 signer 未初始化时崩溃的问题
  - 实现 `ensureSigner()` 懒加载机制，在首次使用时自动初始化 signer
  - 确保 signer 在使用前已正确初始化
  - 适用于所有需要认证的命令：`getBalance`, `getPositions`, `getOpenOrders`, `cancelOrder`, `cancelAllOrders`
  - 位置：`src/exchange/hyperliquid/connector.zig` 第 426, 441, 586, 677, 721 行

- 🐛 **Bug #5: Missing getOpenOrders() implementation**
  - 实现 `IExchange.getOpenOrders()` 接口方法
  - 新增完整的 `connector.zig` 中的 `getOpenOrders()` 实现（第 581-666 行）
  - 支持查询所有挂单或按交易对过滤
  - 自动转换 Hyperliquid 订单格式到统一 Order 格式
  - 正确处理订单状态、价格、数量、成交信息
  - 返回动态分配的订单数组（调用者负责释放）

### Changed
- 🔧 所有需要认证的方法现在都调用 `ensureSigner()` 确保 signer 已初始化
- 🔧 `getBalance()` 和 `getPositions()` 不再假设 signer 已存在

### Tests
- ✅ Bug #4 和 Bug #5 的修复已通过集成测试验证
- ✅ `ensureSigner()` 机制在所有认证方法中正常工作

---

## [0.2.3] - 2025-12-24

### Added
- ✨ **WebSocket 实时数据流完整集成**
  - 新增 `ws: ?*HyperliquidWS` 字段到 HyperliquidConnector
  - 新增 `initWebSocket()` 方法初始化 WebSocket 连接
  - 新增 `subscribe(subscription)` 方法订阅频道
  - 新增 `unsubscribe(subscription)` 方法取消订阅
  - 新增 `setMessageCallback(callback)` 设置消息回调
  - 新增 `isWebSocketInitialized()` 检查 WebSocket 状态
  - 新增 `disconnectWebSocket()` 断开 WebSocket 连接
  - 支持 8 种频道：allMids, l2Book, trades, user, orderUpdates, userFills, userFundings, userNonFundingLedgerUpdates
  - 自动重连机制（最多 5 次）
  - 心跳机制（30 秒 ping 间隔）
  - 线程安全的订阅管理

### Changed
- 🔧 `HyperliquidConnector.destroy()` 现在清理 WebSocket 资源
- 🔧 WebSocket 采用懒加载策略，仅在调用 `initWebSocket()` 时初始化

### Architecture
- 📐 WebSocket 方法直接暴露在 Connector 层，不通过 IExchange 接口
- 📐 设计理念：保持 IExchange 专注于同步 REST API，WebSocket 作为可选功能

### Tests
- ✅ 新增集成测试 Test 15（WebSocket initialization, subscribe, disconnect）
- ✅ 总计 152/152 测试通过

### Examples
- ✅ 完整的 WebSocket 示例（examples/02_websocket_stream.zig）
- ✅ 演示订阅 allMids, l2Book, trades 频道
- ✅ 30 秒内接收 117+ 实时消息

---

## [0.2.2] - 2025-01-24

### Added
- ✨ **Asset 映射表完整实现（getMeta）**
  - 新增 `asset_map: ?std.StringHashMap(u64)` 字段存储 coin → asset_index 映射
  - 新增 `loadAssetMap()` 方法从 `getMeta` API 加载映射表
  - 新增 `getAssetIndex(coin)` 方法查询 coin 的 asset index
  - 支持懒加载（首次使用时自动加载）
  - 自动管理内存（destroy 时清理所有 key 和 map）

- ✅ **cancelOrder 方法完全实现**
  - 移除硬编码的 "ETH" 限制
  - 查询 open orders 获取订单的 coin 名称
  - 使用 `getAssetIndex()` 动态查找 asset index
  - 支持所有 Hyperliquid 支持的币种
  - 完整的错误处理（OrderNotFound, AssetNotFound）

- ✅ **cancelAllOrders 方法完全实现**
  - 移除硬编码的 asset index 限制
  - 使用 `getAssetIndex()` 动态查找 asset index
  - 支持取消所有订单 (pair=null)
  - 支持取消指定币种订单 (pair=TradingPair)
  - 支持所有 Hyperliquid 支持的币种

### Changed
- 🔧 `ExchangeAPI.cancelOrder()` 现在接受 `asset_index` 参数而非 `coin` 字符串
- 🔧 `ExchangeAPI.cancelAllOrders()` 现在接受 `?u64` asset_index 而非 `?[]const u8` coin
- 🔧 `HyperliquidConnector.create()` 初始化 `asset_map = null`（懒加载）
- 🔧 `HyperliquidConnector.destroy()` 现在清理 asset_map 的所有 keys 和 map 本身

### Tests
- ✅ 新增单元测试（asset mapping lazy initialization）
- ✅ 新增集成测试 Test 14（asset mapping lazy loading）
- ✅ 总计 151/151 测试通过

### Fixed
- 🐛 修复 cancelOrder 只支持 ETH 的限制
- 🐛 修复 cancelAllOrders 只支持 ETH 的限制
- 🐛 所有币种现在都可以正常取消订单

---

## [0.2.1] - 2025-01-24

### Added
- ✨ **createOrder 方法完整实现**
  - 集成 Ed25519 签名到订单创建流程
  - 自动从 `ExchangeConfig.api_secret` 初始化 Signer（私钥以 hex 字符串形式提供）
  - 支持带/不带 0x 前缀的私钥格式
  - 将 Hyperliquid 订单响应转换为统一 Order 格式
  - 完整的错误处理（SignerRequired, InvalidPrivateKey, OrderRejected 等）

- ⚠️ **cancelOrder 方法部分实现**
  - 使用 Ed25519 签名取消订单
  - 支持速率限制（20 req/s）
  - **当前限制**: 使用硬编码的 asset index (coin="ETH")
  - **原因**: Hyperliquid API 需要 asset index，但需要 asset 映射表支持
  - **计划**: 在实现 getBalance/getPositions 后完善（需要 getMeta 获取 asset 映射）
  - 完整的错误处理（SignerRequired, CancelOrderFailed）

- ✨ **getBalance 方法完整实现**
  - 使用 `InfoAPI.getUserState()` 获取账户状态
  - 从 `crossMarginSummary` 解析账户余额信息
  - 返回统一的 `Balance` 格式（asset, total, available, locked）
  - 需要 Signer（使用 user address 查询）
  - 完整的错误处理（SignerRequired, 网络错误等）

- ✨ **getPositions 方法完整实现**
  - 使用 `InfoAPI.getUserState()` 获取账户状态
  - 从 `assetPositions` 解析持仓信息
  - 自动跳过零持仓
  - 自动判断多/空方向（基于 szi 的正负）
  - 解析 entry_price、unrealized_pnl、margin_used、leverage
  - 返回统一的 `Position` 格式（pair, side, size, entry_price, unrealized_pnl, leverage, margin_used）
  - Hyperliquid 永续合约统一使用 USDC 作为计价货币
  - 需要 Signer（使用 user address 查询）
  - 完整的错误处理（SignerRequired, 网络错误等）

- ✨ **getOrder 方法完整实现**
  - 新增 `InfoAPI.getOpenOrders()` 方法查询用户所有挂单
  - 通过 order_id 在挂单列表中查找指定订单
  - 解析订单详情（coin, side, limitPx, sz, origSz, timestamp, etc.）
  - 自动计算 filled_amount (origSz - sz)
  - 返回统一的 `Order` 格式（包含 pair, side, price, amount, status, etc.）
  - Side 映射："B" → buy, "A" → sell
  - 需要 Signer（使用 user address 查询）
  - 完整的错误处理（SignerRequired, OrderNotFound, 网络错误等）

- ⚠️ **cancelAllOrders 方法部分实现**
  - 实现 `ExchangeAPI.cancelAllOrders()` 批量取消订单
  - 支持取消所有订单 (pair=null) 或指定交易对的订单 (pair=TradingPair)
  - 智能计数：通过对比取消前后的挂单数量计算取消订单数
  - 优化：如果没有挂单则直接返回 0，避免不必要的 API 调用
  - 返回实际取消的订单数量
  - **当前限制**: 使用硬编码的 asset index (coin="ETH" 或 null)
  - **原因**: 同 cancelOrder，需要 asset 映射表支持
  - **计划**: 在实现 getMeta 后完善
  - 需要 Signer（使用 user address 查询）
  - 完整的错误处理（SignerRequired, CancelAllOrdersFailed, 网络错误等）

### Changed
- 🔧 `HyperliquidConnector.create()` 现在会自动初始化 Signer（如果提供私钥）
- 🔧 `HyperliquidConnector.destroy()` 现在会正确清理 Signer 资源

### Tests
- ✅ 新增 10 个单元测试（initializeSigner、createOrder、cancelOrder、getBalance、getPositions、getOrder、cancelAllOrders 验证）
- ✅ 新增集成测试 Test 8-13（验证 createOrder、cancelOrder、getBalance、getPositions、getOrder、cancelAllOrders 需要 signer）
- ✅ 总计 150/150 测试通过

---

## [0.2.0] - 2025-12-23

### Added
- ✨ HTTP 客户端实现（Info API + Exchange API）
- ✨ WebSocket 客户端实现
- ✨ Ed25519 签名认证
- ✨ 订阅管理器（支持 19 种订阅类型）
- ✨ 自动重连机制
- ✨ 速率限制器（20 req/s）

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的功能新增
- **PATCH**: 向后兼容的 Bug 修复
