# 订单系统 - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-23

---

## [0.2.0] - 2025-12-23

### Added
- ✨ 新增订单核心类型定义
  - `Side` 枚举（买/卖方向）
  - `OrderType` 枚举（限价单/触发单）
  - `TimeInForce` 枚举（Gtc/Ioc/Alo）
  - `OrderStatus` 枚举（完整状态机）
  - `PositionSide` 枚举（多/空/双向）

- ✨ 新增 `Order` 核心数据结构
  - 完整的订单字段定义
  - 订单创建和初始化 (`init`)
  - 订单验证逻辑 (`validate`)
  - 状态更新方法 (`updateStatus`)
  - 成交信息更新 (`updateFill`)
  - 成交百分比计算 (`getFillPercentage`)
  - 内存管理 (`deinit`)

- ✨ 新增 `OrderBuilder` 构建器模式
  - 流畅的链式 API
  - 自动验证
  - 类型安全的订单构建

- ✨ 新增 Hyperliquid API 适配
  - `HyperliquidOrderType` 结构定义
  - 限价单类型 (`LimitOrderType`)
  - 触发单类型 (`TriggerOrderType`)
  - 止盈止损方向 (`TriggerDirection`)

- ✨ 新增辅助功能
  - 客户端订单 ID 自动生成
  - 枚举类型字符串转换 (`toString`/`fromString`)
  - 状态判断辅助函数 (`isFinal`/`isActive`/`isCancellable`)
  - 平均成交价自动计算

- 📚 新增完整文档
  - README.md - 功能概览
  - implementation.md - 实现细节
  - api.md - API 参考
  - testing.md - 测试文档
  - bugs.md - Bug 追踪
  - changelog.md - 变更日志

### Changed
- 🔄 基于 Hyperliquid 真实 API 规范更新订单类型
  - 移除 `market` 订单类型（Hyperliquid 使用 limit + Ioc）
  - 移除 `fok` 时效（Hyperliquid 不支持）
  - 调整状态枚举以匹配 API 返回值

### Implementation Details
- 📁 文件结构
  - `src/core/order.zig` - 订单核心实现
  - `src/core/order_types.zig` - 订单类型定义
  - `src/core/order_test.zig` - 测试用例

- 🔧 技术特性
  - 使用 Decimal 类型保证精度
  - 内存安全（手动管理，无泄漏）
  - 状态机模式管理订单生命周期
  - Builder 模式提供友好 API

### Testing
- ✅ 30+ 单元测试覆盖所有核心功能
- ✅ 订单创建、验证、状态转换测试
- ✅ 成交更新和平均价计算测试
- ✅ OrderBuilder 流畅 API 测试
- ✅ 边界情况和错误处理测试
- 📊 性能基准测试框架

---

## [Unreleased]

### Planned
- [ ] 支持复杂订单类型
  - [ ] Iceberg 订单（冰山单）
  - [ ] TWAP 订单（时间加权平均价格）
  - [ ] VWAP 订单（成交量加权平均价格）

- [ ] 订单管理增强
  - [ ] 批量订单提交
  - [ ] 订单关联（OCO - One-Cancels-Other）
  - [ ] 订单模板系统

- [ ] 持久化和序列化
  - [ ] JSON 序列化/反序列化
  - [ ] 订单持久化到数据库
  - [ ] 订单历史查询

- [ ] 多交易所支持
  - [ ] Binance 订单类型映射
  - [ ] OKX 订单类型映射
  - [ ] 统一抽象层

- [ ] 性能优化
  - [ ] 订单池（避免频繁分配）
  - [ ] 并发访问优化
  - [ ] 内存布局优化

- [ ] 测试增强
  - [ ] 集成测试
  - [ ] 压力测试
  - [ ] 模糊测试

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
  - 示例: 移除公共字段，修改函数签名

- **MINOR**: 向后兼容的功能新增
  - 示例: 添加新的订单类型，新增辅助方法

- **PATCH**: 向后兼容的 Bug 修复
  - 示例: 修复验证逻辑错误，修复内存泄漏

---

## 迁移指南

### 从 0.1.x 迁移到 0.2.0

**不适用** - v0.2.0 是订单系统的首个版本

---

## 贡献者

- Story 009 设计和实现
- 基于 [Hyperliquid API 文档](https://hyperliquid.gitbook.io/hyperliquid-docs/) 的规范设计

---

## 参考资料

- [Story 009: Order Types](../../../stories/v0.2-mvp/009-order-types.md)
- [Hyperliquid Order Types](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/order-types)
- [Hyperliquid API Research](../../../stories/v0.2-mvp/HYPERLIQUID_API_RESEARCH.md)

---

*记录所有重要变更，保持文档同步*
