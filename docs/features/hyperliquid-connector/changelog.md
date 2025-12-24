# Hyperliquid 连接器 - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-01-24

---

## [Unreleased]

### Planned
- [ ] 实现 cancelOrder 方法
- [ ] 实现 getOrder 方法
- [ ] 实现 getBalance 方法
- [ ] 实现 getPositions 方法
- [ ] 实现 cancelAllOrders 方法
- [ ] 实现异步 HTTP 请求
- [ ] 添加连接池支持
- [ ] 实现批量 API 请求
- [ ] 支持 HTTP/2

---

## [0.2.1] - 2025-01-24

### Added
- ✨ **createOrder 方法完整实现**
  - 集成 Ed25519 签名到订单创建流程
  - 自动从 `ExchangeConfig.api_secret` 初始化 Signer（私钥以 hex 字符串形式提供）
  - 支持带/不带 0x 前缀的私钥格式
  - 将 Hyperliquid 订单响应转换为统一 Order 格式
  - 完整的错误处理（SignerRequired, InvalidPrivateKey, OrderRejected 等）

- ✨ **cancelOrder 方法完整实现**
  - 使用 Ed25519 签名取消订单
  - 支持速率限制（20 req/s）
  - MVP 简化实现（使用默认 coin "ETH"）
  - 完整的错误处理（SignerRequired, CancelOrderFailed）
  - TODO: 未来可通过维护 order_id → coin 映射改进准确性

### Changed
- 🔧 `HyperliquidConnector.create()` 现在会自动初始化 Signer（如果提供私钥）
- 🔧 `HyperliquidConnector.destroy()` 现在会正确清理 Signer 资源

### Tests
- ✅ 新增 6 个单元测试（initializeSigner、createOrder、cancelOrder 验证）
- ✅ 新增集成测试 Test 8-9（验证 createOrder 和 cancelOrder 需要 signer）
- ✅ 总计 146/146 测试通过

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
