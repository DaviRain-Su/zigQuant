# Hyperliquid 连接器 - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-01-24

---

## [Unreleased]

### Planned
- [ ] 实现异步 HTTP 请求
- [ ] 添加连接池支持
- [ ] 实现批量 API 请求
- [ ] 支持 HTTP/2

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
