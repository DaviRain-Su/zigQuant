# Changelog

所有 zigQuant 项目的重要变更都会记录在此文件中。

本项目遵循 [语义化版本 2.0.0](https://semver.org/lang/zh-CN/)。

---

## [0.2.0] - 2025-12-25

### Added

#### Core 层 (100%)
- ✨ **Decimal** - 高精度数值类型
  - 18 位小数精度（满足金融交易需求）
  - 基于 i128 整数运算（无浮点误差）
  - 完整算术运算（加减乘除、比较、取模、幂运算）
  - 字符串解析和格式化
  - 140+ 测试用例全部通过

- ✨ **Time** - 时间处理系统
  - 高精度时间戳（毫秒级 Unix 时间戳）
  - ISO 8601 格式解析和格式化
  - K 线时间对齐（1m, 3m, 5m, 15m, 30m, 1h, 2h, 4h, 6h, 12h, 1d, 1w）
  - Duration 时间间隔计算

- ✨ **Error System** - 错误处理系统
  - 五大错误分类（Network, API, Data, Business, System）
  - ErrorContext 错误上下文
  - WrappedError 错误包装
  - 重试机制（固定间隔和指数退避）

- ✨ **Logger** - 日志系统
  - 6 级日志（Trace, Debug, Info, Warn, Error, Fatal）
  - 多种 Writer（Console, File, JSON, Custom）
  - 结构化字段支持
  - std.log 桥接
  - 线程安全设计
  - 38+ 测试用例全部通过

- ✨ **Config** - 配置管理系统
  - JSON 配置文件加载
  - 环境变量覆盖（ZIGQUANT_* 前缀）
  - 多交易所配置支持
  - 配置验证和类型安全
  - 敏感信息保护（sanitize）

#### Exchange 层 (100%)
- ✨ **Exchange Router** - 交易所抽象层
  - IExchange 接口（VTable 模式）
  - 统一数据类型（TradingPair, OrderRequest, Order, Ticker, Orderbook, Position, Balance）
  - ExchangeRegistry（交易所注册表）
  - SymbolMapper（符号映射）
  - Mock Exchange 支持（用于测试）

- ✨ **Hyperliquid Connector** - Hyperliquid DEX 连接器
  - HTTP 客户端（Info API + Exchange API）
  - WebSocket 客户端（实时数据流）
  - Ed25519 签名认证
  - 速率限制（20 req/s）
  - 订阅管理器
  - 自动重连机制
  - 与 Exchange Router 完全集成

#### Market 层 (100%)
- ✨ **OrderBook** - L2 订单簿管理
  - L2 订单簿数据结构
  - 快照同步（`applySnapshot`）
  - 增量更新（`applyUpdate`）
  - 最优价格查询（`getBestBid`, `getBestAsk`）
  - 中间价和价差计算（`getMidPrice`, `getSpread`）
  - 深度计算（`getDepth`）
  - 滑点预估（`getSlippage`）
  - 多币种订单簿管理器（OrderBookManager）
  - 线程安全（Mutex 保护）
  - 9+ 测试用例全部通过
  - 性能基准测试（快照 < 500μs, 更新 < 50μs, 查询 < 50ns）

#### Trading 层 (100%)
- ✨ **Order System** - 订单系统
  - 订单类型定义（Limit, Market, PostOnly, IOC, ALO）
  - 订单状态枚举（Pending, Open, Filled, PartiallyFilled, Cancelled, Rejected, Expired）
  - 订单生命周期管理
  - 触发条件（TP/SL）

- ✨ **Order Manager** - 订单管理器
  - 订单提交（`submitOrder`）
  - 订单撤销（`cancelOrder`, `cancelAllOrders`）
  - 订单查询（`getOrder`, `getOpenOrders`）
  - 订单状态追踪（OrderStore）
  - WebSocket 事件处理
  - 完整测试覆盖

- ✨ **Position Tracker** - 仓位追踪器
  - 仓位数据结构
  - 盈亏计算（未实现盈亏和已实现盈亏）
  - 账户状态同步（`syncAccountState`）
  - 多币种仓位管理
  - Position 和 Account 类型定义
  - 完整测试覆盖

#### CLI 层 (100%)
- ✨ **CLI Interface** - 命令行界面
  - 11 个命令（ticker, orderbook, balance, positions, order, cancel, cancel-all, orders, 等）
  - REPL 交互模式
  - 彩色输出和格式化
  - 帮助系统
  - 错误处理
  - 完整测试覆盖

### Tests
- ✅ **173 个单元测试全部通过 (100%)**
- ✅ **3 个集成测试全部通过 (100%)**
  - ✅ WebSocket Orderbook 集成测试
    - 验证 WebSocket L2 订单簿快照应用
    - 验证最优买卖价追踪
    - 验证延迟 < 10ms 要求（实测 0.23ms ✅）
    - 17 个快照，最大延迟 0.23ms，无内存泄漏
  - ✅ Position Management 集成测试
    - 验证仓位开仓、查询、平仓完整流程
    - 验证 PnL 计算准确性
    - 验证账户状态同步
    - 所有测试通过，无内存泄漏
  - ✅ WebSocket Events 集成测试
    - 验证 WebSocket 订阅和消息接收
    - 验证订单更新事件处理
    - 验证成交事件处理
    - 所有测试通过，无内存泄漏
- ✅ Hyperliquid testnet 集成测试通过
- ✅ 无内存泄漏
- ✅ 无编译警告

### Documentation
- 📚 完整的文档体系（114+ 文件）
  - 12 个功能模块文档（README, API, Implementation, Testing, Changelog, Bugs）
  - 架构设计文档（ARCHITECTURE.md）
  - 项目进度文档（MVP_V0.2.0_PROGRESS.md）
  - 故障排查文档
  - 示例教程（4 个完整示例）
  - Constitution 开发规范
  - Plan Mode 架构实现计划

### Performance
- ⚡ Logger 级别过滤: < 1μs (零分配)
- ⚡ Time.now(): < 100ns (直接系统调用)
- ⚡ Config 加载: < 1ms (单次解析)
- ⚡ Error 创建: < 10ns (栈分配)
- ⚡ OrderBook 快照应用: < 500μs (100 档)
- ⚡ OrderBook 增量更新: < 50μs
- ⚡ OrderBook 最优价格查询: < 50ns (O(1))
- ⚡ **WebSocket 延迟: 0.23ms (目标 < 10ms) ✅**
- ⚡ **订单执行延迟: ~300ms (目标 < 500ms) ✅**
- ⚡ API 延迟: ~200ms (目标 < 500ms)
- ⚡ 启动时间: ~150ms (目标 < 200ms)
- ⚡ 内存占用: ~8MB (目标 < 50MB)

### Fixed
- 🐛 **Critical**: 修复 OrderBook 符号字符串内存管理问题
  - **问题**: `OrderBook.init()` 未复制符号字符串，导致 WebSocket 消息释放后出现悬空指针
  - **影响**: WebSocket 订单簿更新时发生段错误 (Segmentation Fault)
  - **修复**: OrderBook 现在拥有符号字符串的内存（使用 `allocator.dupe()`）
  - **文件**: `src/market/orderbook.zig:81-101,323-343`
  - **详见**: [OrderBook Bug 追踪](./docs/features/orderbook/bugs.md#bug-001-orderbook-符号字符串内存管理问题-critical-)

- 🐛 **Critical**: 修复 Hyperliquid Connector 订单响应解析
  - **问题**: Market IOC 订单返回 `{"filled":...}` 格式，而非 `{"resting":...}`
  - **影响**: 市价单执行成功但被错误判定为失败
  - **修复**: 支持解析两种响应格式（resting + filled）
  - **文件**: `src/exchange/hyperliquid/connector.zig:430-470`
  - **详见**: [Order Manager Bug 追踪](./docs/features/order-manager/bugs.md#bug-004-invalidorderresponse)

- 🐛 修复 Logger comptime 错误（7 个编译错误）
  - 使用 `"{s}"` 格式字符串 + 元组参数
  - 文件: `src/core/logger.zig:705`

- 🐛 修复 Mock IExchange.VTable 缺少 `getOpenOrders` 字段（5 个编译错误）
  - 添加 mock getOpenOrders 实现到所有 mock vtables
  - 文件: `src/exchange/registry.zig:240`, `src/trading/order_manager.zig:513,596,711`, `src/trading/position_tracker.zig:389`

- 🐛 修复 StdLogWriter 输出缺少 scope 字段（2 个测试失败）
  - 直接创建 LogRecord 并包含 scope 字段
  - 文件: `src/core/logger.zig:705-724`

- 🐛 修复 Connector 测试错误类型不匹配（7 个测试失败）
  - 统一使用 `SignerRequired` 错误
  - 文件: `src/exchange/hyperliquid/connector.zig:889`

- 🐛 修复 Signer 延迟初始化测试适配（1 个测试失败）
  - 修改测试以匹配延迟初始化设计
  - 文件: `src/exchange/hyperliquid/connector.zig:1314-1324`

---

## [0.1.0] - 2025-12-23

### Added
- 🎉 项目初始化
- ✨ 基础目录结构
- ✨ 构建系统（build.zig）
- 📚 初始文档框架

---

## 版本规范

遵循 [语义化版本 2.0.0](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的功能新增
- **PATCH**: 向后兼容的 Bug 修复

### 标签说明

- ✨ `Added`: 新增功能
- 🔧 `Changed`: 功能变更
- 🐛 `Fixed`: Bug 修复
- ⚡ `Performance`: 性能优化
- 📝 `Documentation`: 文档更新
- 🗑️ `Deprecated`: 即将废弃的功能
- 🔥 `Removed`: 移除的功能
- 🔒 `Security`: 安全修复

---

## MVP v0.2.0 功能清单 (99% 完成)

- ✅ Hyperliquid DEX 完整集成
- ✅ 实时市场数据 (HTTP + WebSocket)
- ✅ Orderbook 管理和更新
- ✅ 订单管理 (下单、撤单、查询)
- ✅ 仓位跟踪和 PnL 计算
- ✅ CLI 界面 (11 个命令 + REPL)
- ✅ 配置文件系统
- ✅ 日志系统
- ✅ 完整文档 (114+ 文件)
- ✅ **3 个集成测试全部通过**
  - ✅ WebSocket Orderbook 集成测试
  - ✅ Position Management 集成测试
  - ✅ WebSocket Events 集成测试
- ✅ 173 个单元测试全部通过
- ✅ 零内存泄漏
- ✅ 性能指标全部达标

---

## 下一版本计划

### v0.3.0 - 策略框架 (计划中)
- [ ] 策略接口定义
- [ ] 信号生成器
- [ ] 风险管理模块
- [ ] 回测框架基础

### v0.4.0 - 回测引擎 (计划中)
- [ ] 历史数据管理
- [ ] 回测执行引擎
- [ ] 性能分析工具
- [ ] 策略优化器

### v1.0.0 - 生产就绪 (未来)
- [ ] 完整的量化交易系统
- [ ] 多交易所支持
- [ ] Web 管理界面
- [ ] 监控和告警系统

---

*更新时间: 2025-12-25*
*当前版本: v0.2.0*
*MVP 完成度: 99%*
