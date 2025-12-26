# Changelog

所有 zigQuant 项目的重要变更都会记录在此文件中。

本项目遵循 [语义化版本 2.0.0](https://semver.org/lang/zh-CN/)。

---

## [0.3.0] - 2024-12-26

### Added

#### Strategy Framework (100%)
- ✨ **IStrategy Interface** - 策略接口和核心类型
  - VTable 模式策略抽象
  - Signal/SignalMetadata 信号系统
  - StrategyContext 上下文管理
  - StrategyParameter 参数定义
  - 生命周期管理（init → populate → entry/exit → cleanup）

- ✨ **Indicators Library** - 技术指标库 (7 个指标)
  - SMA (Simple Moving Average) - 简单移动平均
  - EMA (Exponential Moving Average) - 指数移动平均
  - RSI (Relative Strength Index) - 相对强弱指标
  - MACD (Moving Average Convergence Divergence) - 平滑异同移动平均
  - Bollinger Bands - 布林带
  - ATR (Average True Range) - 真实波幅
  - Stochastic Oscillator - 随机指标
  - IndicatorManager 缓存优化（10x 性能提升）

- ✨ **Built-in Strategies** - 内置策略 (3 个)
  - Dual Moving Average Strategy - 双均线策略
  - RSI Mean Reversion Strategy - RSI 均值回归策略
  - Bollinger Breakout Strategy - 布林带突破策略
  - 所有策略经过真实历史数据验证

#### Backtest Engine (100%)
- ✨ **BacktestEngine** - 回测引擎核心
  - 事件驱动架构（MarketEvent → SignalEvent → OrderEvent → FillEvent）
  - HistoricalDataFeed CSV 数据加载
  - OrderExecutor 订单模拟（滑点 + 手续费）
  - Account/Position 管理
  - Trade 跟踪和记录

- ✨ **PerformanceAnalyzer** - 性能分析器
  - 30+ 核心性能指标
  - Sharpe Ratio（夏普比率）
  - Maximum Drawdown（最大回撤）
  - Profit Factor（盈利因子）
  - Win Rate（胜率）
  - 风险调整收益指标
  - 彩色格式化输出

#### Parameter Optimizer (100%)
- ✨ **GridSearchOptimizer** - 网格搜索优化器
  - 参数组合生成器
  - 6 种优化目标支持：
    - Sharpe Ratio (推荐)
    - Profit Factor
    - Win Rate
    - Maximum Drawdown
    - Net Profit
    - Total Return
  - 优化结果排名和分析
  - JSON 结果导出

#### CLI Strategy Commands (100%)
- ✨ **Strategy Commands** - 策略命令集成
  - `strategy backtest` - 策略回测
    - 支持自定义配置文件
    - 支持自定义数据文件
    - 完整性能报告输出
  - `strategy optimize` - 参数优化
    - 网格搜索优化
    - 多种优化目标
    - Top N 结果显示
    - JSON 结果导出
  - `strategy run-strategy` - 实盘运行 (stub)
  - StrategyFactory 策略工厂
  - zig-clap 参数解析

#### Documentation (100%)
- 📚 **完整的使用文档**
  - [CLI 使用指南](./docs/features/cli/usage-guide.md) (1,800+ 行)
    - Backtest 命令详解
    - Optimize 命令详解
    - 配置文件格式
    - 示例场景和 FAQ
  - [参数优化器使用指南](./docs/features/optimizer/usage-guide.md) (2,000+ 行)
    - 网格搜索原理
    - 参数配置详解
    - 优化目标选择
    - 结果分析和最佳实践
  - [策略开发完整教程](./docs/tutorials/strategy-development.md) (1,500+ 行)
    - KDJ 策略完整示例
    - 开发流程详解
    - 最佳实践指南

#### Examples (100%)
- ✨ **Strategy Examples** - 策略示例
  - `examples/06_strategy_backtest.zig` - 策略回测示例
  - `examples/07_strategy_optimize.zig` - 参数优化示例
  - `examples/08_custom_strategy.zig` - 自定义策略示例
  - 策略配置文件示例（dual_ma.json, rsi_mean_reversion.json, bollinger_breakout.json）

### Tests
- ✅ **357 个单元测试全部通过 (100%)** (从 173 增长到 357)
- ✅ 策略回测验证（真实 BTC/USDT 2024 年数据，8784 根 K 线）
  - Dual MA: 1 笔交易
  - RSI Mean Reversion: 9 笔交易，**+11.05% 收益** ✨
  - Bollinger Breakout: 2 笔交易
- ✅ 参数优化测试（网格搜索 9 组合 / 767ms）
- ✅ 零内存泄漏（GPA 验证）
- ✅ 零编译警告

### Performance
- ⚡ 回测速度: > 10,000 ticks/s (60ms/8k candles)
- ⚡ 指标计算: < 10ms (目标 < 50ms)
- ⚡ IndicatorManager 缓存: 10x 性能提升
- ⚡ 网格搜索: ~85ms/组合
- ⚡ 结果排序: < 1ms
- ⚡ 内存占用: ~10MB (目标 < 50MB)

### Fixed
- 🐛 修复 BacktestEngine Signal 内存泄漏
  - 问题：entry_signal 和 exit_signal 未正确释放
  - 修复：添加 defer signal.deinit()
  - 文件：`src/backtest/engine.zig:134,151`

- 🐛 修复 calculateDays 整数溢出
  - 问题：使用 maxInt(i64) 导致溢出
  - 修复：使用实际交易时间范围 + 溢出保护
  - 文件：`src/backtest/types.zig:236`

- 🐛 修复控制台输出问题
  - 问题：使用错误的 stdout API + 缺少 flush
  - 修复：使用 std.fs.File.stdout() + 添加 flush
  - 文件：`src/main.zig:36-40`

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
