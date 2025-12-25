# 订单簿 - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-25

---

## [0.2.1] - 2025-12-25

### Fixed
- 🐛 **Critical**: 修复 OrderBook 符号字符串内存管理问题
  - **问题**: `OrderBook.init()` 未复制符号字符串，导致 WebSocket 消息释放后出现悬空指针
  - **影响**: WebSocket 订单簿更新时发生段错误 (Segmentation Fault)
  - **修复**: `OrderBook.init()` 现在使用 `allocator.dupe()` 复制符号字符串
  - **修复**: `OrderBook.deinit()` 释放拥有的符号字符串
  - **修复**: `OrderBookManager.getOrCreate()` 使用 OrderBook 拥有的符号作为 HashMap 键
  - **文件**: `src/market/orderbook.zig:81-101,323-343`

### Added
- ✨ WebSocket 订单簿集成测试 (`tests/integration/websocket_orderbook_test.zig`)
  - 验证 WebSocket L2 订单簿快照应用
  - 验证最优买卖价追踪
  - 验证延迟 < 10ms 要求
  - 验证无内存泄漏
  - **测试结果**: 17 个快照，最大延迟 0.23ms ✅
- 🔧 构建系统添加 `test-ws-orderbook` 步骤 (`build.zig:195-209`)

### Performance
- ⚡ WebSocket 订单簿更新延迟: 0.23ms (< 10ms 要求) ✅

---

## [0.2.0] - 2025-12-23

### Added
- ✨ 初始实现 L2 订单簿数据结构
- ✨ 快照同步功能（`applySnapshot`）
- ✨ 增量更新功能（`applyUpdate`）
- ✨ 最优价格查询（`getBestBid`, `getBestAsk`）
- ✨ 中间价和价差计算（`getMidPrice`, `getSpread`）
- ✨ 深度计算功能（`getDepth`）
- ✨ 滑点预估功能（`getSlippage`）
- ✨ 多币种订单簿管理器（`OrderBookManager`）
- ✨ 线程安全的并发访问（使用 `Mutex`）
- ✨ 完整的单元测试套件（20+ 测试用例）
- ✨ 性能基准测试
- 📚 完整的文档体系（README、API、实现细节、测试、Bug 追踪）

### Performance
- ⚡ 快照应用：< 500 μs (100 档)
- ⚡ 增量更新：< 50 μs
- ⚡ 最优价格查询：< 50 ns (O(1))
- ⚡ 深度计算：< 1 μs (10 档)
- ⚡ 滑点计算：< 2 μs (10 档)

### Architecture
- 📁 核心文件：`src/core/orderbook.zig`
- 📁 测试文件：`src/core/orderbook_test.zig`
- 📁 管理器：`src/core/orderbook_manager.zig`

---

## [Unreleased]

### Planned
- [ ] 二分查找优化（提升更新性能）
- [ ] 有序插入代替全量排序
- [ ] 序列号跳跃检测和自动重新同步
- [ ] 订单簿快照持久化
- [ ] 订单簿回放功能（用于回测）
- [ ] VWAP 计算
- [ ] 订单簿差异检测
- [ ] 并发访问性能优化（读写锁）
- [ ] 大规模订单簿支持（1000+ 档）
- [ ] 模糊测试（Fuzz Testing）

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的功能新增
- **PATCH**: 向后兼容的 Bug 修复

### 当前版本：v0.2.0

**状态**: 🚧 开发中

订单簿模块是 zigQuant v0.2 MVP 的核心组件之一，当前版本实现了基本功能和性能目标。未来版本将专注于性能优化和高级特性。

---

## 里程碑

### v0.2.0 (当前)
- ✅ 核心数据结构
- ✅ 基本查询功能
- ✅ 快照和增量更新
- ✅ 测试覆盖 > 90%
- 🚧 性能优化（进行中）

### v0.3.0 (计划)
- [ ] 性能优化（二分查找、有序插入）
- [ ] 序列号跳跃检测
- [ ] 并发性能优化
- [ ] 大规模订单簿支持

### v0.4.0 (未来)
- [ ] 订单簿持久化
- [ ] 回放功能
- [ ] VWAP 和高级指标
- [ ] 可视化接口支持

---

## 依赖关系

### 前置依赖
- `Decimal` (v0.1.0) - 高精度数值计算
- `Timestamp` (v0.1.0) - 时间戳处理

### 集成依赖
- `Hyperliquid HTTP` (v0.2.0) - 快照数据获取
- `Hyperliquid WebSocket` (v0.2.0) - 增量更新订阅

---

## 相关 Story

- [STORY-008: 订单簿数据结构与维护](../../../stories/v0.2-mvp/008-orderbook.md)

---

*版本历史追踪从 v0.2.0 开始。*
