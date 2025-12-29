# Changelog

所有 zigQuant 项目的重要变更都会记录在此文件中。

本项目遵循 [语义化版本 2.0.0](https://semver.org/lang/zh-CN/)。

---

## [0.9.1] - 2025-12-29

### Added

#### Engine Architecture Unification (Steps 2 & 3)

##### LiveRunner 实盘交易封装
- ✨ **LiveRunner** - 统一实盘交易管理 (`src/engine/runners/live_runner.zig`)
  - `LiveRequest` 配置类型 (strategy_type, exchange, symbol, mode, initial_capital)
  - `LiveStatus` 状态枚举 (stopped, starting, running, paused, stopping, error)
  - `LiveStats` 统计信息 (ticks_processed, orders_placed, orders_filled, current_pnl)
  - `OrderHistoryEntry` 订单历史记录
  - 线程安全执行 (Mutex + Atomic flags)
  - 生命周期管理 (start/stop/pause/resume)

##### EngineManager 扩展
- ✨ **Live Trading API** - EngineManager 新增实盘管理
  - `live_runners: HashMap<*LiveRunner>` 会话存储
  - `startLive()` / `stopLive()` / `pauseLive()` / `resumeLive()` 方法
  - `getLiveStatus()` / `getLiveStats()` 查询方法
  - `listLiveSessions()` 列出所有会话
  - `activateKillSwitch()` 联动停止所有实盘
  - `getSystemHealth()` 包含 `running_live` 统计

##### REST API 扩展
- ✨ **Live Trading REST API** - 7 个新端点 (`/api/v2/live`)
  - `GET /api/v2/live` - 列出所有实盘会话
  - `POST /api/v2/live` - 启动新会话
  - `GET /api/v2/live/:id` - 会话详情
  - `DELETE /api/v2/live/:id` - 停止会话
  - `POST /api/v2/live/:id/pause` - 暂停会话
  - `POST /api/v2/live/:id/resume` - 恢复会话
  - `POST /api/v2/live/:id/subscribe` - 订阅交易对

##### 模块导出
- ✨ **engine/mod.zig** 新增导出:
  - LiveRunner, LiveRequest, LiveStatus, LiveStats
  - OrderHistoryEntry, LiveTradingMode
  - AIRuntimeConfig, AIStatus

#### AI 策略集成完善

##### StrategyFactory 扩展
- ✨ **hybrid_ai 策略支持** (`src/strategy/factory.zig`)
  - 添加 `HybridAIStrategy` 到策略列表 (共 5 个策略)
  - 添加 `llm_client` 字段用于 AI 策略
  - `setLLMClient()` / `clearLLMClient()` 方法
  - `createHybridAI()` 支持完整参数配置

##### EngineManager AI 管理
- ✨ **AIRuntimeConfig** - 运行时 AI 配置
  - provider, model_id, api_endpoint, api_key
  - enabled, timeout_ms
- ✨ **AIStatus** - 安全状态暴露 (不含 API key)
- ✨ **AI 配置方法**:
  - `configureAI()` / `updateAIConfig()` - 配置管理
  - `initAIClient()` / `disableAI()` - 客户端生命周期
  - `getAIStatus()` / `getLLMClient()` / `isAIReady()` - 状态查询

##### REST API AI 端点
- ✨ **AI Configuration REST API** - 3 个新端点 (`/api/v2/ai`)
  - `GET /api/v2/ai/config` - 获取 AI 配置状态
  - `POST /api/v2/ai/config` - 更新 AI 配置
  - `POST /api/v2/ai/enable` - 启用 AI (初始化客户端)
  - `POST /api/v2/ai/disable` - 禁用 AI

### Changed

- 🔧 `SystemHealth` 结构新增 `running_live` 字段
- 🔧 `KillSwitchResult` 结构新增 `live_sessions_stopped` 字段
- 🔧 `getManagerStats()` 包含实盘会话统计
- 🔧 `StrategyFactory` 支持 LLM 客户端注入

### Tests
- ✅ 781 个单元测试通过 (从 776 增长)
- ✅ 所有集成测试通过
- ✅ 零内存泄漏 (GPA 验证)

### Documentation
- 📚 更新 `STORY_047_REST_API.md` - 添加 Live Trading API 和 AI API 文档
- 📚 更新 `paper-trading/README.md` - 添加架构说明
- 📚 更新 `live-trading/README.md` - 添加 LiveRunner 文档
- 📚 更新 `features/ai/README.md` - 添加 REST API 配置部分
- 📚 更新 `NEXT_STEPS.md` - v0.9.1 进度

---

## [0.9.0] - 2025-12-28

### Added

#### AI 策略集成 (Story 046)

##### ILLMClient 接口
- ✨ **ILLMClient** - VTable 模式 LLM 客户端抽象
  - generateText() 文本生成
  - generateObject() 结构化输出 (JSON Schema)
  - getModel() 获取模型信息
  - isConnected() 连接状态检查

##### LLMClient 实现
- ✨ **LLMClient** - OpenAI 兼容客户端
  - 支持 OpenAI API (GPT-4o, o1, o3 系列)
  - 支持 LM Studio 本地模型 (http://127.0.0.1:1234)
  - 支持 Ollama 本地模型 (http://localhost:11434)
  - 支持 DeepSeek API (https://api.deepseek.com)
  - 支持任何 OpenAI 兼容 API

##### AIAdvisor 服务
- ✨ **AIAdvisor** - AI 交易建议服务
  - 结构化交易建议 (AIAdvice)
  - 5 种 Action: strong_buy, buy, hold, sell, strong_sell
  - 置信度评分 [0.0, 1.0]
  - AI 推理解释
  - 请求统计和延迟追踪

##### PromptBuilder 构建器
- ✨ **PromptBuilder** - 专业市场分析 Prompt 构建
  - 市场数据格式化
  - 技术指标解读
  - 仓位上下文
  - JSON Schema 结构化输出

##### HybridAIStrategy 混合策略
- ✨ **HybridAIStrategy** - 混合决策策略
  - 技术指标权重 (默认 60%)
  - AI 建议权重 (默认 40%)
  - AI 失败时自动回退到纯技术指标
  - 完整 IStrategy 接口实现

#### 依赖
- ✨ **openai-zig** - OpenAI 兼容 Zig 客户端
  - 聊天补全 API
  - JSON Schema 结构化输出
  - Markdown 代码块自动解析

### Examples
- ✨ `33_openai_chat.zig` - OpenAI 聊天示例

### Tests
- ✅ 700+ 个单元测试通过
- ✅ 所有集成测试通过
- ✅ 零内存泄漏 (GPA 验证)

### Performance
- AI API 调用延迟: 500ms - 5s (取决于模型和网络)
- 本地技术指标计算: < 1ms
- Prompt 构建: < 1ms

---

## [0.8.0] - 2025-12-28

### Added

#### 风险管理引擎 (Stories 040-045)

##### RiskEngine 核心 (Story 040)
- ✨ **RiskEngine** - 风险管理引擎
  - 仓位限制检查
  - 日度亏损限制
  - 止损/止盈触发
  - VaR 风险价值计算

##### 止损止盈系统 (Story 041)
- ✨ **StopLossManager** - 止损管理
  - 固定止损 (Fixed Stop Loss)
  - 追踪止损 (Trailing Stop)
  - 时间止损 (Time Stop)
  - ATR 动态止损
- ✨ **TakeProfitManager** - 止盈管理
  - 固定止盈
  - 分批止盈
  - 追踪止盈

##### 资金管理 (Story 042)
- ✨ **MoneyManager** - 资金管理模块
  - 固定金额模式
  - 固定百分比模式
  - 凯利公式
  - 风险平价
  - 反马丁格尔

##### 风险指标监控 (Story 043)
- ✨ **RiskMonitor** - 风险监控
  - 实时 VaR 计算
  - 最大回撤追踪
  - 波动率监控
  - 相关性分析

##### 告警系统 (Story 044)
- ✨ **AlertSystem** - 告警通知
  - 多级告警 (Info, Warning, Critical)
  - 告警规则配置
  - 告警历史记录
  - 告警去重

##### Crash Recovery (Story 045)
- ✨ **StateManager** - 状态管理
  - 状态快照保存
  - 状态恢复加载
  - 定时自动保存
- ✨ **RecoveryManager** - 崩溃恢复
  - 启动时自动检测
  - 仓位状态恢复
  - 未完成订单处理

### Examples
- ✨ `26_risk_engine.zig` - 风险引擎示例
- ✨ `27_stop_loss.zig` - 止损止盈示例
- ✨ `28_money_management.zig` - 资金管理示例
- ✨ `29_risk_monitoring.zig` - 风险监控示例
- ✨ `30_alert_system.zig` - 告警系统示例
- ✨ `31_crash_recovery.zig` - 崩溃恢复示例
- ✨ `32_full_risk_demo.zig` - 完整风险管理演示

### Tests
- ✅ 670+ 个单元测试通过
- ✅ 所有集成测试通过
- ✅ 零内存泄漏 (GPA 验证)

### Performance
- 风险检查延迟: < 1ms
- VaR 计算: < 10ms
- 状态保存: < 100ms

---

## [0.7.0] - 2025-12-27

### Added

#### 做市策略 (Market Making)

##### Clock-Driven 模式 (Story 033)
- ✨ **Clock** - Tick 驱动策略执行
  - 可配置 tick interval
  - 策略注册和生命周期管理
  - ClockStats 统计信息
- ✨ **IClockStrategy** - Clock 策略接口
  - VTable 模式实现
  - onTick/onStart/onStop 回调

##### Pure Market Making (Story 034)
- ✨ **PureMarketMaking** - 双边报价做市策略
  - 可配置价差 (spread_bps)
  - 可配置订单量 (order_amount)
  - 自动刷新报价
  - Clock 集成

##### Inventory Management (Story 035)
- ✨ **InventoryManager** - 库存风险控制
  - 多种 Skew 模式 (Linear/Exponential/StepFunction)
  - 动态报价调整
  - 再平衡建议

##### Data Persistence (Story 036)
- ✨ **DataStore** - 数据持久化
  - 二进制存储格式
  - 文件系统存储
- ✨ **CandleCache** - K 线缓存
  - LRU 淘汰策略
  - 自动加载/卸载

##### Cross-Exchange Arbitrage (Story 037)
- ✨ **CrossExchangeArbitrage** - 跨交易所套利
  - 套利机会检测
  - 利润计算 (含手续费)
  - 统计跟踪

#### 回测精度 (Backtest Accuracy)

##### Queue Position Modeling (Story 038)
- ✨ **Level3OrderBook** - Level-3 订单簿 (Market-By-Order)
  - 单个订单粒度追踪
  - 价格层级管理
- ✨ **QueuePosition** - 队列位置追踪
  - 4 种成交概率模型:
    - RiskAverse (保守模型)
    - Probability (概率模型)
    - PowerLaw (幂函数模型)
    - Logarithmic (对数模型)
  - 队列推进逻辑

##### Dual Latency Simulation (Story 039)
- ✨ **FeedLatencyModel** - 行情延迟模拟
  - Constant 固定延迟
  - Normal 正态分布
  - Interpolated 插值模型
- ✨ **OrderLatencyModel** - 订单延迟模拟
  - 提交延迟 (entry latency)
  - 响应延迟 (response latency)
- ✨ **LatencyStats** - 延迟统计

### Examples
- ✨ 11 个新示例 (15-25):
  - `15_vectorized_backtest.zig` - 向量化回测
  - `16_hyperliquid_adapter.zig` - 交易所适配器
  - `17_paper_trading.zig` - Paper Trading
  - `18_hot_reload.zig` - 策略热重载
  - `19_clock_driven.zig` - Clock-Driven 执行
  - `20_pure_market_making.zig` - 做市策略
  - `21_inventory_management.zig` - 库存管理
  - `22_data_persistence.zig` - 数据持久化
  - `23_cross_exchange_arb.zig` - 跨交易所套利
  - `24_queue_position.zig` - 队列位置建模
  - `25_latency_simulation.zig` - 延迟模拟

### Tests
- ✅ 624 个单元测试通过 (从 558 增长)
- ✅ 所有集成测试通过
- ✅ 零内存泄漏

### Fixed
- 🐛 修复 ArrayList Zig 0.15 API 兼容性问题
- 🐛 修复 signed integer division 需要 @divTrunc 问题
- 🐛 修复多个 example 中的 API 不匹配问题

---

## [0.6.0] - 2025-12-27

### Added

#### 向量化回测引擎 (Story 028)
- ✨ **VectorizedBacktester** - SIMD 优化的高性能回测引擎
  - 回测速度: 12.6M bars/s (目标 100K，超越 126 倍)
  - SIMD 向量化指标计算
  - 批量信号生成
  - 内存映射数据加载

#### Hyperliquid 交易所适配器 (Stories 029-030)
- ✨ **HyperliquidDataProvider** - 实现 IDataProvider 接口
  - WebSocket 实时数据流
  - Quote/Candle/OrderBook 订阅
  - MessageBus 事件发布
  - Cache 自动更新

- ✨ **HyperliquidExecutionClient** - 实现 IExecutionClient 接口
  - 订单提交/取消/查询
  - 仓位和余额查询
  - 订单状态同步
  - VTable 接口实现

#### Paper Trading (Story 031)
- ✨ **PaperTradingEngine** - 模拟交易引擎
  - 使用真实市场数据
  - 模拟订单执行
  - 滑点和手续费模拟
  - 实时 PnL 计算

- ✨ **SimulatedAccount** - 虚拟账户
  - 余额和仓位跟踪
  - 交易历史记录
  - 权益曲线
  - 统计分析 (胜率、盈亏比、最大回撤)

- ✨ **SimulatedExecutor** - 模拟执行器
  - 实现 IExecutionClient 接口
  - 市价单/限价单支持
  - 挂单管理

#### 策略热重载 (Story 032)
- ✨ **HotReloadManager** - 配置文件监控
  - 自动检测文件变化
  - 线程安全监控
  - 自动备份

- ✨ **ParamValidator** - 参数验证
  - min/max 范围验证
  - 配置比较

- ✨ **SafeReloadScheduler** - 安全重载调度
  - tick 间隙重载
  - 原子操作
  - 重载统计

### Performance
- 向量化回测: 12,600,000 bars/s
- 实盘数据延迟: 0.23ms
- 订单执行延迟: ~50ms
- 内存占用: ~8MB

### Tests
- 单元测试: 558 个 (从 502 增长)
- 所有测试通过
- 零内存泄漏

---

## [0.5.0] - 2025-12-27

### Added

#### 事件驱动架构
- ✨ **MessageBus** - 消息总线
- ✨ **Cache** - 中央数据缓存
- ✨ **DataEngine** - 数据引擎
- ✨ **ExecutionEngine** - 执行引擎
- ✨ **LiveTradingEngine** - 实时交易引擎

---

## [0.4.0] - 2025-12-27

### Added

#### 优化器增强
- ✨ **Walk-Forward 分析** - 前向验证
- ✨ **扩展指标** - 8 个新指标
- ✨ **结果导出** - JSON/CSV 导出
- ✨ **并行优化** - 多线程加速

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

### v1.0.0 - 生产就绪 (规划中)
- [ ] REST API 服务 (http.zig)
- [ ] Web Dashboard UI
- [ ] Prometheus Metrics 导出
- [ ] Docker 容器化部署
- [ ] Telegram/Email 通知系统
- [ ] 完整运维文档

### v1.1.0 - 多交易所与套利 (计划中)
- [ ] 多交易所连接器 (Binance, OKX, Bybit)
- [ ] 智能路由引擎
- [ ] 资金费率套利策略
- [ ] 投资组合管理
- [ ] 统一账户视图

### v1.2.0 - DEX 扩展 (计划中)
- [ ] DEX 连接器 (Uniswap, dYdX, GMX, Jupiter)
- [ ] 链上数据分析
- [ ] MEV 保护机制

### v1.3.0 - 另类市场 (计划中)
- [ ] Polymarket 预测市场
- [ ] 预测市场策略框架
- [ ] 事件驱动交易

---

*更新时间: 2025-12-29*
*当前版本: v0.9.1*
*完成度: 71% (9.1/13 版本完成)*
