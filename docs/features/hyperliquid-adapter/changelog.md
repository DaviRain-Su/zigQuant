# Hyperliquid Adapter 变更日志

本文档记录 Hyperliquid 适配器模块的所有重要变更。

---

## [未发布] - v0.6.0

### 计划功能

#### HyperliquidDataProvider
- **WebSocket 连接**: 建立和维护 WebSocket 连接
- **数据订阅**: 支持 allMids, l2Book, trades, candle 频道
- **自动重连**: 断线自动重连并恢复订阅
- **消息解析**: JSON 消息解析和类型转换
- **事件发布**: 通过 MessageBus 发布市场数据事件

#### HyperliquidExecutionClient
- **订单提交**: 限价单、市价单
- **订单取消**: 单个取消、批量取消
- **状态查询**: 订单状态、仓位、账户
- **EIP-712 签名**: 符合 Hyperliquid 签名规范
- **状态同步**: WebSocket 订单更新订阅

### 性能目标

- 连接延迟: < 500ms
- 数据延迟: < 10ms
- 下单延迟: < 100ms
- 重连成功率: > 99%

---

## 版本规范

- **Major**: 不兼容的 API 变更
- **Minor**: 向后兼容的功能新增
- **Patch**: 向后兼容的 bug 修复

---

*Last updated: 2025-12-27*
