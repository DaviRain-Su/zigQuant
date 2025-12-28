# ZigQuant Features Documentation

> 导航: [首页](../../README.md) / Features

本目录包含 ZigQuant 所有核心功能的详细文档。

**当前版本**: v0.8.0
**更新时间**: 2025-12-28

---

## 📊 版本概览

| 版本 | 功能模块数 | 状态 |
|------|-----------|------|
| v0.2.0 | 7 个模块 | ✅ 完成 |
| v0.3.0 | 4 个模块 | ✅ 完成 |
| v0.4.0 | 增强更新 | ✅ 完成 |
| v0.5.0 | 5 个模块 | ✅ 完成 |
| v0.6.0 | 5 个模块 | ✅ 完成 |
| v0.7.0 | 7 个模块 | ✅ 完成 |
| v0.8.0 | 6 个模块 | ✅ 完成 |
| v1.0.0 | Web 管理 | 📋 规划中 |

---

## 📖 文档结构说明

每个功能模块都遵循统一的文档结构，包含以下标准文件：

- **README.md** - 功能概览、快速开始、核心API
- **implementation.md** - 内部实现细节、算法和数据结构
- **api.md** - 完整的 API 参考文档
- **testing.md** - 测试覆盖和性能基准
- **bugs.md** - 已知问题和修复记录
- **changelog.md** - 版本历史和更新记录

---

## 功能模块

### 1. Hyperliquid 连接器

Hyperliquid DEX 集成模块，提供 HTTP API 和 WebSocket 支持。

- [功能概览](./hyperliquid-connector/README.md)
- [实现细节](./hyperliquid-connector/implementation.md)
- [API 参考](./hyperliquid-connector/api.md)
- [测试文档](./hyperliquid-connector/testing.md)
- [Bug 追踪](./hyperliquid-connector/bugs.md)
- [变更日志](./hyperliquid-connector/changelog.md)

**Story**: [006-hyperliquid-http](../../stories/v0.2-mvp/006-hyperliquid-http.md) | [007-hyperliquid-ws](../../stories/v0.2-mvp/007-hyperliquid-ws.md)

---

### 2. 订单簿

高性能 L2 订单簿实现，支持快照和增量更新。

- [功能概览](./orderbook/README.md)
- [实现细节](./orderbook/implementation.md)
- [API 参考](./orderbook/api.md)
- [测试文档](./orderbook/testing.md)
- [Bug 追踪](./orderbook/bugs.md)
- [变更日志](./orderbook/changelog.md)

**Story**: [008-orderbook](../../stories/v0.2-mvp/008-orderbook.md)

---

### 3. 订单系统

订单类型定义、验证和生命周期管理。

- [功能概览](./order-system/README.md)
- [实现细节](./order-system/implementation.md)
- [API 参考](./order-system/api.md)
- [测试文档](./order-system/testing.md)
- [Bug 追踪](./order-system/bugs.md)
- [变更日志](./order-system/changelog.md)

**Story**: [009-order-types](../../stories/v0.2-mvp/009-order-types.md)

---

### 4. 订单管理器

订单提交、取消、状态追踪和事件处理。

- [功能概览](./order-manager/README.md)
- [实现细节](./order-manager/implementation.md)
- [API 参考](./order-manager/api.md)
- [测试文档](./order-manager/testing.md)
- [Bug 追踪](./order-manager/bugs.md)
- [变更日志](./order-manager/changelog.md)

**Story**: [010-order-manager](../../stories/v0.2-mvp/010-order-manager.md)

---

### 5. 仓位追踪器

实时仓位追踪、盈亏计算和风险指标。

- [功能概览](./position-tracker/README.md)
- [实现细节](./position-tracker/implementation.md)
- [API 参考](./position-tracker/api.md)
- [测试文档](./position-tracker/testing.md)
- [Bug 追踪](./position-tracker/bugs.md)
- [变更日志](./position-tracker/changelog.md)

**Story**: [011-position-tracker](../../stories/v0.2-mvp/011-position-tracker.md)

---

### 6. Exchange Router

多交易所抽象层，提供统一的交易所访问接口。

- [功能概览](./exchange-router/README.md)
- [实现细节](./exchange-router/implementation.md)
- [API 参考](./exchange-router/api.md)
- [测试文档](./exchange-router/testing.md)
- [Bug 追踪](./exchange-router/bugs.md)
- [变更日志](./exchange-router/changelog.md)

**Story**: [Phase 0: Exchange Router 设计](../../.claude/plans/sorted-crunching-sonnet.md)

---

### 7. CLI 界面

命令行界面，提供交互式和脚本化的交易操作。

- [功能概览](./cli/README.md)
- [实现细节](./cli/implementation.md)
- [API 参考](./cli/api.md)
- [测试文档](./cli/testing.md)
- [Bug 追踪](./cli/bugs.md)
- [变更日志](./cli/changelog.md)

**Story**: [012-cli-interface](../../stories/v0.2-mvp/012-cli-interface.md)

---

## v0.3.0 功能模块

### 8. 策略框架 (Strategy Framework)

统一的策略开发框架，支持自定义策略和内置策略。

- [功能概览](./strategy/README.md)
- [实现细节](./strategy/implementation.md)
- [API 参考](./strategy/api.md)
- [测试文档](./strategy/testing.md)

**核心特性**:
- IStrategy 接口 (VTable 模式)
- 三个内置策略 (DualMA, RSI Mean Reversion, Bollinger Breakout)
- StrategyContext 执行上下文
- 信号生成和仓位管理

**Story**: [Story 016-019](../../stories/v0.3.0/)

---

### 9. 回测引擎 (Backtest Engine)

使用历史数据验证策略效果的回测系统。

- [功能概览](./backtest/README.md)
- [使用指南](../guides/BACKTEST_GUIDE.md)

**核心特性**:
- BacktestEngine - 核心回测引擎
- PerformanceAnalyzer - 性能分析器
- CSV/API 数据加载
- 手续费和滑点模拟
- 权益曲线生成

**Story**: [Story 016-019](../../stories/v0.3.0/)

---

### 10. 技术指标库 (Indicators Library)

完整的技术指标实现，支持趋势、动量、波动率等多种指标。

- [功能概览](./indicators/README.md)
- [实现细节](./indicators/implementation.md)
- [API 参考](./indicators/api.md)

**v0.3.0 指标** (7 个):
- SMA, EMA - 移动平均
- RSI - 相对强弱指标
- MACD - 移动平均收敛散度
- Bollinger Bands - 布林带
- ATR - 平均真实范围
- Volume Profile - 成交量分布

**v0.4.0 新增指标** (8 个):
- ADX - 趋势强度
- Ichimoku Cloud - 一目均衡表
- Stochastic RSI - 随机 RSI
- Williams %R - 威廉指标
- CCI - 商品通道指数
- OBV - 能量潮
- MFI - 资金流量指标
- VWAP - 成交量加权平均价

**Story**: [Story 020](../../stories/v0.3.0/), [Story 021](../../stories/v0.4.0/)

---

### 11. 参数优化器 (Optimizer)

自动寻找最佳策略参数组合的优化系统。

- [功能概览](./optimizer/README.md)
- [使用指南](../guides/OPTIMIZATION_GUIDE.md)

**v0.3.0 功能**:
- GridSearchOptimizer - 网格搜索
- 6 个基础优化目标 (Sharpe, Profit Factor, Win Rate, Max Drawdown, Net Profit, Total Return)
- 完整回测验证

**v0.4.0 增强功能**:
- Walk-Forward 分析 (避免过拟合)
- 并行优化 (多线程加速)
- 6 个高级优化目标 (Sortino, Calmar, Omega, Tail, Stability, Risk-Adjusted)
- 过拟合检测
- 结果导出 (JSON/CSV)

**Story**: [Story 020](../../stories/v0.3.0/), [Story 022](../../stories/v0.4.0/)

---

## v0.5.0 功能模块 ✅

### 12. MessageBus (消息总线)

事件驱动架构的核心基础设施，提供高效的组件间通信。

- [功能概览](./message-bus/README.md)

**核心特性**:
- Publish-Subscribe 模式 (一对多)
- Request-Response 模式 (一对一)
- Command 模式 (Fire-and-Forget)
- 通配符订阅支持

**Story**: [Story 023](../../stories/v0.5.0/STORY_023_MESSAGE_BUS.md)

---

### 13. Cache (高性能缓存)

高性能内存缓存系统，提供纳秒级访问常用对象。

- [功能概览](./cache/README.md)

**核心特性**:
- 订单、仓位、账户缓存
- 多索引加速查询
- 与 MessageBus 自动同步
- 纳秒级查询延迟

**Story**: [Story 024](../../stories/v0.5.0/STORY_024_CACHE.md)

---

### 14. DataEngine (数据引擎)

数据引擎重构，实现回测与实盘代码统一 (Code Parity)。

- [功能概览](./data-engine/README.md)

**核心特性**:
- 多数据源支持 (WebSocket, REST, Historical)
- 统一事件发布
- Code Parity (回测/实盘代码相同)
- 自动缓存更新

**Story**: [Story 025](../../stories/v0.5.0/STORY_025_DATA_ENGINE.md)

---

### 15. ExecutionEngine (执行引擎)

订单执行引擎，支持订单前置追踪确保零丢单。

- [功能概览](./execution-engine/README.md)

**核心特性**:
- 订单前置追踪 (Hummingbot 模式)
- 零订单丢失
- API 超时容错
- 订单状态恢复

**Story**: [Story 026](../../stories/v0.5.0/STORY_026_EXECUTION_ENGINE.md)

---

### 16. LiveTrading (实时交易)

基于 libxev 的实时交易引擎，支持高性能异步 I/O。

- [功能概览](./live-trading/README.md)

**核心特性**:
- libxev 事件循环 (io_uring)
- WebSocket 异步连接
- 自动重连机制
- Event-Driven & Clock-Driven 模式

**Story**: [Story 027](../../stories/v0.5.0/STORY_027_LIBXEV_INTEGRATION.md)

---

## v0.6.0 功能模块 ✅

### 17. Vectorized Backtest (向量化回测)

利用 SIMD 指令加速的高性能批量回测引擎。

- [功能概览](./vectorized-backtest/README.md)
- [API 参考](./vectorized-backtest/api.md)
- [实现细节](./vectorized-backtest/implementation.md)
- [测试文档](./vectorized-backtest/testing.md)
- [Bug 追踪](./vectorized-backtest/bugs.md)
- [变更日志](./vectorized-backtest/changelog.md)

**核心特性**:
- SIMD 加速 (@Vector 类型)
- 内存映射 (mmap) 数据加载
- 批量信号生成
- 目标: > 100,000 bars/s

**Story**: [Story 028](../../stories/v0.6.0/STORY_028_VECTORIZED_BACKTESTER.md)

---

### 18. Hyperliquid Adapter (交易所适配器)

Hyperliquid DEX 的数据源和执行客户端适配器。

- [功能概览](./hyperliquid-adapter/README.md)
- [API 参考](./hyperliquid-adapter/api.md)
- [实现细节](./hyperliquid-adapter/implementation.md)
- [测试文档](./hyperliquid-adapter/testing.md)
- [Bug 追踪](./hyperliquid-adapter/bugs.md)
- [变更日志](./hyperliquid-adapter/changelog.md)

**核心特性**:
- HyperliquidDataProvider (实现 IDataProvider)
- HyperliquidExecutionClient (实现 IExecutionClient)
- WebSocket 实时数据
- EIP-712 签名

**Story**: [Story 029](../../stories/v0.6.0/STORY_029_HYPERLIQUID_DATA_PROVIDER.md), [Story 030](../../stories/v0.6.0/STORY_030_HYPERLIQUID_EXECUTION_CLIENT.md)

---

### 19. Paper Trading (模拟交易)

使用真实市场数据的无风险策略验证环境。

- [功能概览](./paper-trading/README.md)
- [API 参考](./paper-trading/api.md)
- [实现细节](./paper-trading/implementation.md)
- [测试文档](./paper-trading/testing.md)
- [Bug 追踪](./paper-trading/bugs.md)
- [变更日志](./paper-trading/changelog.md)

**核心特性**:
- 真实市场数据 + 模拟执行
- 滑点和手续费模拟
- 实时 PnL 统计
- SimulatedAccount 账户管理

**Story**: [Story 031](../../stories/v0.6.0/STORY_031_PAPER_TRADING.md)

---

### 20. Hot Reload (策略热重载)

运行时策略参数更新，无需重启交易引擎。

- [功能概览](./hot-reload/README.md)
- [API 参考](./hot-reload/api.md)
- [实现细节](./hot-reload/implementation.md)
- [测试文档](./hot-reload/testing.md)
- [Bug 追踪](./hot-reload/bugs.md)
- [变更日志](./hot-reload/changelog.md)

**核心特性**:
- 配置文件监控
- 参数验证
- 安全重载调度
- 备份和回滚

**Story**: [Story 032](../../stories/v0.6.0/STORY_032_HOT_RELOAD.md)

---

## v0.7.0 功能模块 ✅

### 21. Clock-Driven Mode (时钟驱动模式)

按固定时间间隔触发策略执行，适合做市场景。

**核心特性**:
- Clock 定时器 (可配置 tick interval)
- IClockStrategy 接口 (VTable 模式)
- 策略注册和生命周期管理
- ClockStats 统计信息

**Story**: [Story 033](../../stories/v0.7.0/STORY_033_CLOCK_DRIVEN.md)

---

### 22. Pure Market Making (做市策略)

双边报价做市策略，支持多级订单。

**核心特性**:
- PureMarketMaking 策略
- 双边报价 (bid/ask)
- 可配置价差和订单量
- Clock 集成

**Story**: [Story 034](../../stories/v0.7.0/STORY_034_PURE_MM.md)

---

### 23. Inventory Management (库存管理)

库存风险控制和动态报价调整。

**核心特性**:
- InventoryManager 库存管理器
- 多种 Skew 模式 (Linear/Exponential/StepFunction)
- 动态报价调整
- 再平衡建议

**Story**: [Story 035](../../stories/v0.7.0/STORY_035_INVENTORY.md)

---

### 24. Data Persistence (数据持久化)

数据存储和缓存系统。

**核心特性**:
- DataStore 数据存储
- CandleCache LRU 缓存
- 二进制和文件存储
- 数据验证

**Story**: [Story 036](../../stories/v0.7.0/STORY_036_SQLITE.md)

---

### 25. Cross-Exchange Arbitrage (跨交易所套利)

跨交易所套利策略和机会检测。

**核心特性**:
- CrossExchangeArbitrage 套利策略
- 机会检测算法
- 利润计算 (含手续费)
- 统计跟踪

**Story**: [Story 037](../../stories/v0.7.0/STORY_037_ARBITRAGE.md)

---

### 26. Queue Position Modeling (队列位置建模)

HFTBacktest 风格的队列位置追踪和成交概率估算。

**核心特性**:
- Level-3 订单簿 (Market-By-Order)
- QueuePosition 队列位置追踪
- 4 种成交概率模型
- 队列推进逻辑

**Story**: [Story 038](../../stories/v0.7.0/STORY_038_QUEUE_POSITION.md)

---

### 27. Dual Latency Simulation (双向延迟模拟)

HFTBacktest 风格的行情和订单延迟模拟。

**核心特性**:
- FeedLatencyModel 行情延迟
- OrderLatencyModel 订单延迟
- 3 种延迟模型 (Constant/Normal/Interpolated)
- LatencyStats 统计

**Story**: [Story 039](../../stories/v0.7.0/STORY_039_DUAL_LATENCY.md)

---

## v0.8.0 功能模块 ✅

### 28. RiskEngine (风险引擎)

生产级风险管理引擎，提供 Kill Switch 紧急停止。

**核心特性**:
- RiskEngine 核心 (VTable 模式)
- 仓位大小限制
- 杠杆限制
- 日损失限制
- Kill Switch 紧急停止 (< 100ms 响应)

**Story**: [Story 040](../../stories/v0.8.0/STORY_040_RISK_ENGINE.md)

---

### 29. StopLoss Manager (止损管理)

自动止损止盈管理系统。

**核心特性**:
- StopLossManager 止损管理器
- 固定止损/止盈
- 跟踪止损
- 自动执行

**Story**: [Story 041](../../stories/v0.8.0/STORY_041_STOP_LOSS.md)

---

### 30. Money Management (资金管理)

资金分配和仓位大小计算。

**核心特性**:
- MoneyManager 资金管理器
- Kelly 公式计算
- 固定分数法
- 风险平价

**Story**: [Story 042](../../stories/v0.8.0/STORY_042_MONEY_MANAGEMENT.md)

---

### 31. Risk Metrics (风险指标)

实时风险指标计算和监控。

**核心特性**:
- RiskMetrics 风险指标
- VaR 计算 (历史模拟法)
- 最大回撤监控
- 实时夏普比率

**Story**: [Story 043](../../stories/v0.8.0/STORY_043_RISK_METRICS.md)

---

### 32. Alert System (告警系统)

多级告警和通知系统。

**核心特性**:
- AlertSystem 告警系统
- Webhook 集成
- 多级告警 (INFO/WARNING/CRITICAL)
- 可扩展通知接口

**Story**: [Story 044](../../stories/v0.8.0/STORY_044_ALERT_SYSTEM.md)

---

### 33. Crash Recovery (崩溃恢复)

状态持久化和自动恢复机制。

**核心特性**:
- CrashRecovery 崩溃恢复
- 状态持久化
- 自动恢复
- 未完成订单恢复

**Story**: [Story 045](../../stories/v0.8.0/STORY_045_CRASH_RECOVERY.md)

---

## 文档结构

```
docs/features/
├── README.md (本文件)
├── templates/                          # 文档模板
│
├── ─────── v0.2.0 模块 ───────
├── hyperliquid-connector/              # Hyperliquid 连接器
├── orderbook/                          # 订单簿
├── order-system/                       # 订单系统
├── order-manager/                      # 订单管理器
├── position-tracker/                   # 仓位追踪器
├── exchange-router/                    # Exchange Router
├── cli/                                # CLI 界面
│
├── ─────── v0.3.0 模块 ───────
├── strategy/                           # 策略框架
│   ├── README.md
│   ├── implementation.md
│   ├── api.md
│   └── testing.md
├── backtest/                           # 回测引擎
│   └── README.md
├── indicators/                         # 技术指标库
│   ├── README.md
│   ├── implementation.md
│   └── api.md
├── optimizer/                          # 参数优化器
│   └── README.md
│
├── ─────── v0.5.0 模块 ───────
├── message-bus/                        # 消息总线
│   └── README.md
├── cache/                              # 高性能缓存
│   └── README.md
├── data-engine/                        # 数据引擎
│   └── README.md
├── execution-engine/                   # 执行引擎
│   └── README.md
├── live-trading/                       # 实时交易
│   └── README.md
│
├── ─────── v0.6.0 模块 (规划中) ───────
├── vectorized-backtest/                # 向量化回测
│   ├── README.md
│   ├── api.md
│   ├── implementation.md
│   ├── testing.md
│   ├── bugs.md
│   └── changelog.md
├── hyperliquid-adapter/                # Hyperliquid 适配器
│   ├── README.md
│   ├── api.md
│   ├── implementation.md
│   ├── testing.md
│   ├── bugs.md
│   └── changelog.md
├── paper-trading/                      # 模拟交易
│   ├── README.md
│   ├── api.md
│   ├── implementation.md
│   ├── testing.md
│   ├── bugs.md
│   └── changelog.md
├── hot-reload/                         # 策略热重载
│   ├── README.md
│   ├── api.md
│   ├── implementation.md
│   ├── testing.md
│   ├── bugs.md
│   └── changelog.md
│
├── ─────── 基础设施模块 ───────
├── decimal/                            # 高精度小数
├── time/                               # 时间处理
├── logger/                             # 日志系统
├── config/                             # 配置管理
└── error-system/                       # 错误处理
```

---

## 快速导航

### 按功能分类

**策略与回测** (v0.3.0+):
- [策略框架](./strategy/README.md) - 策略开发和执行
- [内置策略](./strategy/README.md#内置策略) - DualMA, RSI, Bollinger
- [回测引擎](./backtest/README.md) - 历史数据验证
- [回测指南](../guides/BACKTEST_GUIDE.md) - 使用教程

**技术指标** (v0.3.0+):
- [指标库](./indicators/README.md) - 15 个技术指标
- [趋势指标](./indicators/README.md#趋势指标) - SMA, EMA, ADX, Ichimoku
- [动量指标](./indicators/README.md#动量指标) - RSI, MACD, CCI, Williams %R
- [成交量指标](./indicators/README.md#成交量指标) - OBV, MFI, VWAP

**参数优化** (v0.3.0+):
- [优化器](./optimizer/README.md) - 参数寻优
- [优化指南](../guides/OPTIMIZATION_GUIDE.md) - 使用教程
- [Walk-Forward](./optimizer/README.md#walk-forward-分析) - 过拟合检测

**事件驱动架构** (v0.5.0):
- [MessageBus](./message-bus/README.md) - 消息总线
- [Cache](./cache/README.md) - 高性能缓存
- [DataEngine](./data-engine/README.md) - 数据引擎
- [ExecutionEngine](./execution-engine/README.md) - 执行引擎
- [LiveTrading](./live-trading/README.md) - 实时交易

**混合计算模式** (v0.6.0):
- [VectorizedBacktest](./vectorized-backtest/README.md) - 向量化回测 (SIMD 加速)
- [HyperliquidAdapter](./hyperliquid-adapter/README.md) - Hyperliquid 交易所适配器
- [PaperTrading](./paper-trading/README.md) - 模拟交易
- [HotReload](./hot-reload/README.md) - 策略热重载

**做市与套利** (v0.7.0):
- Clock-Driven Mode - 时钟驱动模式
- Pure Market Making - 做市策略
- Inventory Management - 库存管理
- Cross-Exchange Arbitrage - 跨交易所套利
- Queue Position Modeling - 队列位置建模
- Dual Latency Simulation - 延迟模拟

**风险管理** (v0.8.0):
- RiskEngine - 风险引擎 (Kill Switch)
- StopLoss Manager - 止损管理
- Money Management - 资金管理
- Risk Metrics - 风险指标
- Alert System - 告警系统
- Crash Recovery - 崩溃恢复

**市场数据**:
- [订单簿维护](./orderbook/README.md)
- [WebSocket 订阅](./hyperliquid-connector/README.md#websocket-客户端)
- [实时数据流](./hyperliquid-connector/implementation.md#websocket-客户端实现)

**交易操作**:
- [订单提交和取消](./order-manager/README.md)
- [订单类型](./order-system/README.md)
- [订单验证](./order-system/implementation.md#订单验证逻辑)

**账户管理**:
- [仓位追踪](./position-tracker/README.md)
- [盈亏计算](./position-tracker/implementation.md#盈亏计算算法)
- [风险指标](./position-tracker/api.md#仓位数据结构)

**集成**:
- [Exchange Router 抽象层](./exchange-router/README.md)
- [多交易所管理](./exchange-router/api.md#exchangeregistry)
- [统一交易接口](./exchange-router/api.md#iexchange-接口)
- [符号映射](./exchange-router/implementation.md#symbolmapper-实现)
- [HTTP 客户端](./hyperliquid-connector/README.md#http-客户端)
- [WebSocket 客户端](./hyperliquid-connector/README.md#websocket-客户端)
- [Ed25519 签名](./hyperliquid-connector/implementation.md#ed25519-认证实现)

**用户界面**:
- [CLI 命令行界面](./cli/README.md)
- [市场数据查询](./cli/api.md#market-命令)
- [订单操作](./cli/api.md#order-命令)
- [交互式 REPL](./cli/implementation.md#repl-交互式模式)

### 按开发阶段

**初始化**:
1. [创建 Exchange Registry](./exchange-router/README.md#快速开始)
2. [注册交易所连接器](./exchange-router/implementation.md#hyperliquid-connector)
3. [创建 HTTP 客户端](./hyperliquid-connector/README.md#快速开始)
4. [创建 WebSocket 客户端](./hyperliquid-connector/README.md#websocket-客户端)
5. [初始化订单簿](./orderbook/README.md#快速开始)
6. [初始化订单管理器](./order-manager/README.md#快速开始)
7. [初始化仓位追踪器](./position-tracker/README.md#快速开始)

**开发**:
1. [Exchange Router 架构](./exchange-router/implementation.md#架构设计)
2. [IExchange 接口实现](./exchange-router/implementation.md#iexchange-接口实现)
3. [订单提交流程](./order-manager/implementation.md#订单提交流程)
4. [订单簿更新](./orderbook/implementation.md#快照应用)
5. [仓位追踪](./position-tracker/implementation.md#仓位追踪实现)

**测试**:
1. [Exchange Router 测试](./exchange-router/testing.md)
2. [Mock Exchange 实现](./exchange-router/testing.md#mock-exchange)
3. [HTTP 客户端测试](./hyperliquid-connector/testing.md)
4. [订单系统测试](./order-system/testing.md)
5. [订单管理器测试](./order-manager/testing.md)
6. [仓位追踪器测试](./position-tracker/testing.md)
7. [CLI 测试](./cli/testing.md)

---

## 相关资源

- **Templates**: [文档模板](./templates/) - 用于创建新功能文档的标准模板
- **Stories v0.2**: [v0.2 技术设计](../../stories/v0.2-mvp/) - MVP 设计文档
- **Stories v0.3**: [v0.3 技术设计](../../stories/v0.3.0/) - 策略框架设计
- **Stories v0.4**: [v0.4 技术设计](../../stories/v0.4.0/) - 优化增强设计
- **Stories v0.5**: [v0.5 技术设计](../../stories/v0.5.0/) - 事件驱动架构设计
- **Stories v0.6**: [v0.6 技术设计](../../stories/v0.6.0/) - 混合计算模式设计
- **Stories v0.7**: [v0.7 技术设计](../../stories/v0.7.0/) - 做市策略设计
- **Stories v0.8**: [v0.8 技术设计](../../stories/v0.8.0/) - 风险管理设计
- **使用指南**: [回测指南](../guides/BACKTEST_GUIDE.md) | [优化指南](../guides/OPTIMIZATION_GUIDE.md)
- **示例代码**: [Examples](../../examples/README.md) - 31 个完整示例

---

## 文档版本

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| v0.8.0 | 2025-12-28 | 添加风险管理：RiskEngine、StopLoss、MoneyManagement、RiskMetrics、AlertSystem、CrashRecovery |
| v0.7.0 | 2025-12-27 | 添加做市策略：Clock-Driven、PureMarketMaking、Inventory、Arbitrage、QueuePosition、LatencySimulation |
| v0.6.0 | 2025-12-27 | 添加混合计算模式：VectorizedBacktest、HyperliquidAdapter、PaperTrading、HotReload |
| v0.5.0 | 2025-12-27 | 添加事件驱动架构：MessageBus、Cache、DataEngine、ExecutionEngine、LiveTrading |
| v0.4.0 | 2025-12-27 | 添加优化器增强、8个新指标、使用指南 |
| v0.3.0 | 2025-12-26 | 添加策略框架、回测引擎、指标库、优化器 |
| v0.2.0 | 2025-12-23 | 初始版本，7 个核心功能模块 |

---

*所有功能文档遵循统一的模板结构，确保一致性和可维护性*
*最后更新: 2025-12-28*
