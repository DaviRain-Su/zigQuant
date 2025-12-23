# Hyperliquid 连接器 - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-23

---

## [Unreleased]

### Planned
- [ ] 实现异步 HTTP 请求
- [ ] 添加连接池支持
- [ ] 实现批量 API 请求
- [ ] 支持 HTTP/2

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
