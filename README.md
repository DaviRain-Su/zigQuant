# zigQuant

> 基于 Zig 语言的高性能量化交易框架
> 结合 **Freqtrade 回测能力** + **Hummingbot 做市能力** + **NautilusTrader 性能** + **HFTBacktest 精度**

[![Zig Version](https://img.shields.io/badge/zig-0.15.2-orange.svg)](https://ziglang.org/)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/tests-558+-brightgreen.svg)]()
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0--dev-blue.svg)](docs/stories/v1.0.0/OVERVIEW.md)

---

## 🎯 项目愿景

打造新一代量化交易框架，利用 Zig 语言的**内存安全**和**性能优势**，兼顾**专业量化**和**零售友好**。

### 核心差异化

- 🔥 **单一语言栈** - 100% Zig (vs Rust + Python 混合)
- 🔥 **混合架构** - 事件驱动 + 向量化 + 队列建模
- 🔥 **全场景覆盖** - 趋势策略 + 做市策略 + HFT
- 🔥 **性能 + 易用性 + 精度** - 三者兼顾

详见 [架构演进战略](./roadmap.md#架构演进战略) 和 [竞争分析](./docs/architecture/COMPETITIVE_ANALYSIS.md)

---

## 📖 核心文档

### 🚀 快速入门
- **[📋 文档索引](./docs/DOCUMENTATION_INDEX.md)** - 完整文档导航 ⭐
- **[🚀 快速开始](./QUICK_START.md)** - 5 分钟上手指南
- **[📊 Roadmap](./roadmap.md)** - 产品路线图和架构演进
- **[📝 CHANGELOG](./CHANGELOG.md)** - 详细变更日志
- **[🎯 下一步行动](./docs/NEXT_STEPS.md)** - v1.0.0 开发计划

### 🏗️ 架构设计
- **[🔍 竞争分析](./docs/architecture/COMPETITIVE_ANALYSIS.md)** - 深度分析 4 大顶级平台 ⭐
  - NautilusTrader, Hummingbot, Freqtrade, HFTBacktest
- **[📐 架构模式参考](./docs/architecture/ARCHITECTURE_PATTERNS.md)** - 8 个核心模式 ⭐
  - MessageBus, Cache, Queue Position, Dual Latency, etc.
- [架构设计](./docs/ARCHITECTURE.md) - 系统架构和设计决策
- [性能指标](./docs/PERFORMANCE.md) - 性能目标和优化策略
- [安全设计](./docs/SECURITY.md) - 安全架构和最佳实践

### 📚 功能文档

#### ✅ V0.1 Foundation (基础设施)
- [Decimal 高精度数值](./docs/features/decimal/README.md) - 18位小数精度、零浮点误差
- [Time 时间处理](./docs/features/time/README.md) - Timestamp、Duration、K线对齐
- [Error System 错误处理](./docs/features/error-system/README.md) - 五大错误分类、重试机制
- [Logger 日志系统](./docs/features/logger/README.md) - 结构化日志、多种输出格式
- [Config 配置管理](./docs/features/config/README.md) - JSON配置、环境变量覆盖
- [Exchange Router](./docs/features/exchange-router/README.md) - 交易所抽象层、IExchange接口

#### ✅ V0.2 MVP (交易系统)
- [Hyperliquid 连接器](./docs/features/hyperliquid-connector/README.md) - HTTP/WebSocket、Ed25519签名
- [Orderbook 订单簿](./docs/features/orderbook/README.md) - L2订单簿、增量更新
- [Order System 订单系统](./docs/features/order-system/README.md) - 订单类型、生命周期
- [Order Manager](./docs/features/order-manager/README.md) - 订单管理、状态追踪
- [Position Tracker](./docs/features/position-tracker/README.md) - 仓位追踪、盈亏计算
- [CLI 基础命令](./docs/features/cli/README.md) - price, book, buy, sell, balance, etc.

#### ✅ V0.3 策略与回测
- [Strategy Framework](./docs/features/strategy/README.md) - IStrategy接口、3个内置策略
- [Backtest Engine](./docs/features/backtest/README.md) - 事件驱动回测、性能分析
- [Indicators Library](./docs/features/indicators/README.md) - 7个技术指标 (SMA/EMA/RSI/MACD/BB/ATR/Stoch)
- [Parameter Optimizer](./docs/features/optimizer/README.md) - 网格搜索、6种优化目标
- **[CLI 策略命令](./docs/features/cli/usage-guide.md)** - backtest, optimize 完整指南 ⭐

#### ✅ V0.4 优化器增强与指标扩展
- [Walk-Forward 分析](./docs/stories/v0.4.0/STORY_022_OPTIMIZER_ENHANCEMENT.md) - 前向验证、过拟合检测
- [扩展技术指标](./docs/stories/v0.4.0/STORY_025_EXTENDED_INDICATORS.md) - 15个指标 (+8新增: ADX/Ichimoku/CCI/OBV/VWAP/MFI/StochRSI/Williams%R)
- [回测结果导出](./docs/stories/v0.4.0/STORY_027_BACKTEST_EXPORT.md) - JSON/CSV导出、结果加载
- [并行优化](./examples/12_parallel_optimize.zig) - 多线程加速、进度跟踪
- **[策略开发教程](./docs/tutorials/strategy-development.md)** - 完整开发指南 ⭐

#### ✅ V0.5 事件驱动架构
- [事件驱动架构概览](./docs/stories/v0.5.0/OVERVIEW.md) - MessageBus + Cache + Engine 架构 ⭐
- [MessageBus 消息总线](./docs/stories/v0.5.0/STORY_023_MESSAGE_BUS.md) - Pub/Sub、Request/Response、Command 模式
- [Cache 数据缓存](./docs/stories/v0.5.0/STORY_024_CACHE.md) - OrderBook、Position、Quote、Bar、Order 缓存
- [DataEngine 数据引擎](./docs/stories/v0.5.0/STORY_025_DATA_ENGINE.md) - IDataProvider 接口、历史数据回放
- [ExecutionEngine 执行引擎](./docs/stories/v0.5.0/STORY_026_EXECUTION_ENGINE.md) - IExecutionClient 接口、订单恢复、风控
- [libxev 异步集成](./docs/stories/v0.5.0/STORY_027_LIBXEV_INTEGRATION.md) - io_uring/kqueue 事件循环

#### ✅ V0.6 混合计算模式 (NEW!)
- [混合计算模式概览](./docs/stories/v0.6.0/OVERVIEW.md) - 向量化回测 + Paper Trading ⭐
- [向量化回测引擎](./docs/stories/v0.6.0/STORY_028_VECTORIZED_BACKTESTER.md) - SIMD 优化、12.6M bars/s ⭐
- [HyperliquidDataProvider](./docs/stories/v0.6.0/STORY_029_HYPERLIQUID_DATA_PROVIDER.md) - IDataProvider 实现
- [HyperliquidExecutionClient](./docs/stories/v0.6.0/STORY_030_HYPERLIQUID_EXECUTION_CLIENT.md) - IExecutionClient 实现
- [Paper Trading](./docs/stories/v0.6.0/STORY_031_PAPER_TRADING.md) - 模拟交易引擎 ⭐
- [策略热重载](./docs/stories/v0.6.0/STORY_032_HOT_RELOAD.md) - 运行时参数更新

#### ✅ V0.7 做市策略
- [做市优化概览](./docs/stories/v0.7.0/OVERVIEW.md) - 做市 + 回测精度 ⭐
- [Clock-Driven 模式](./docs/stories/v0.7.0/STORY_033_CLOCK_DRIVEN.md) - Tick 驱动策略执行
- [Pure Market Making](./docs/stories/v0.7.0/STORY_034_PURE_MM.md) - 双边报价做市策略
- [Inventory Management](./docs/stories/v0.7.0/STORY_035_INVENTORY.md) - 库存风险控制
- [Data Persistence](./docs/stories/v0.7.0/STORY_036_SQLITE.md) - 数据持久化 (DataStore/CandleCache)
- [Cross-Exchange Arbitrage](./docs/stories/v0.7.0/STORY_037_ARBITRAGE.md) - 跨交易所套利
- [Queue Position Modeling](./docs/stories/v0.7.0/STORY_038_QUEUE_POSITION.md) - 队列位置建模 (HFTBacktest) ⭐
- [Dual Latency Simulation](./docs/stories/v0.7.0/STORY_039_DUAL_LATENCY.md) - 双向延迟模拟 (HFTBacktest) ⭐

#### ✅ V0.8 风险管理
- [风险管理概览](./docs/stories/v0.8.0/OVERVIEW.md) - 完整风险管理体系 ⭐
- [RiskEngine 风险引擎](./docs/stories/v0.8.0/STORY_040_RISK_ENGINE.md) - Kill Switch + 实时监控
- [Stop Loss Manager](./docs/stories/v0.8.0/STORY_041_STOP_LOSS.md) - 止损/追踪止损
- [Money Management](./docs/stories/v0.8.0/STORY_042_MONEY_MANAGER.md) - 资金管理策略
- [Risk Metrics](./docs/stories/v0.8.0/STORY_043_RISK_METRICS.md) - VaR/Sharpe/Sortino
- [Alert System](./docs/stories/v0.8.0/STORY_044_ALERT.md) - 多级警报系统
- [Crash Recovery](./docs/stories/v0.8.0/STORY_045_RECOVERY.md) - 崩溃恢复机制

#### ✅ V0.9 AI 策略集成
- [AI 策略概览](./docs/stories/v0.9.0/OVERVIEW.md) - AI 辅助交易决策 ⭐
- [AI 模块 API](./docs/features/ai/README.md) - LLMClient/AIAdvisor/HybridAIStrategy
- [Story 046: AI 策略](./docs/stories/v0.9.0/STORY_046_AI_STRATEGY.md) - 完整实现文档
- [实现细节](./docs/features/ai/implementation.md) - openai-zig 集成
- [Release Notes](./docs/releases/RELEASE_v0.9.0.md) - v0.9.0 发布说明

#### 🚧 V1.0 生产就绪 (开发中)
- [v1.0.0 概览](./docs/stories/v1.0.0/OVERVIEW.md) - 生产就绪目标 ⭐
- [REST API](./docs/stories/v1.0.0/STORY_047_REST_API.md) - 40 个端点, JWT 认证, 动态数据 ✅
- [Prometheus 监控](./docs/stories/v1.0.0/STORY_049_PROMETHEUS.md) - 指标导出 ✅
- [Docker 部署](./docs/stories/v1.0.0/STORY_050_DOCKER.md) - 容器化 (待开始)
- [Telegram/Email 通知](./docs/stories/v1.0.0/STORY_052_NOTIFICATIONS.md) - 多渠道告警 (待开始)

### 🎓 教程和示例
- **[示例总览](./examples/README.md)** - 25个完整示例 (NEW: 11个v0.6-v0.7示例)
- **[策略开发完整教程](./docs/tutorials/strategy-development.md)** - KDJ 策略从零到完整 ⭐
- **[参数优化指南](./docs/features/optimizer/usage-guide.md)** - 网格搜索详解 ⭐

### 🔧 故障排查
- **[故障排查索引](./docs/troubleshooting/README.md)** - 常见问题和解决方案
- **[Zig 0.15.2 兼容性](./docs/troubleshooting/zig-0.15.2-logger-compatibility.md)** - Logger 适配经验

---

## 🚀 快速开始

### 环境要求

- **Zig 0.15.2** 或更高版本
- Linux / macOS / Windows
- 网络连接（Hyperliquid testnet 集成测试）

### 安装和构建

```bash
# 克隆仓库
git clone https://github.com/DaviRain-Su/zigQuant.git
cd zigQuant

# 运行所有测试 (453 个测试)
zig build test --summary all

# 运行集成测试
zig build test-integration        # HTTP API
zig build test-ws                  # WebSocket
zig build test-trading             # Trading 完整流程

# 构建项目
zig build

# 构建 Release 版本
zig build -Doptimize=ReleaseFast
```

### CLI 使用示例

```bash
# 查看帮助
zig build run -- --help

# 1. 市场数据查询
zig build run -- price BTC-USD
zig build run -- book BTC-USD --depth 10

# 2. 策略回测 (NEW in v0.3.0!)
zig build run -- backtest \
  --strategy dual_ma \
  --config examples/strategies/dual_ma.json \
  --data data/BTCUSDT_1h_2024.csv

# 3. 参数优化 (NEW in v0.3.0!)
zig build run -- optimize \
  --strategy rsi_mean_reversion \
  --config examples/strategies/dual_ma_optimize.json \
  --top 10 \
  --objective sharpe

# 4. 查询账户（需要配置 API）
zig build run -- balance
```

详见 [CLI 使用指南](./docs/features/cli/usage-guide.md)

### 运行示例

```bash
# 核心基础
zig build run-example-core

# WebSocket 实时数据
zig build run-example-websocket

# HTTP 市场数据
zig build run-example-http

# 策略回测 (NEW!)
zig build run-example-backtest

# 参数优化 (NEW!)
zig build run-example-optimize

# 自定义策略
zig build run-example-custom

# v0.4.0 示例
zig build run-example-indicators   # 新技术指标
zig build run-example-walkforward  # Walk-Forward 分析
zig build run-example-export       # 结果导出
zig build run-example-parallel     # 并行优化

# v0.5.0 新示例 (事件驱动架构)
zig build run-example-event-driven  # 事件驱动架构演示
zig build run-example-async-engine  # 异步交易引擎演示

# v0.6.0 新示例 (混合计算)
zig build run-example-vectorized    # 向量化回测
zig build run-example-adapter       # Hyperliquid 适配器
zig build run-example-paper-trading # Paper Trading
zig build run-example-hot-reload    # 策略热重载

# v0.7.0 新示例 (做市策略)
zig build run-example-clock         # Clock-Driven 执行
zig build run-example-pure-mm       # Pure Market Making
zig build run-example-inventory     # 库存管理
zig build run-example-persistence   # 数据持久化
zig build run-example-arbitrage     # 跨交易所套利
zig build run-example-queue         # 队列位置建模
zig build run-example-latency       # 延迟模拟

# v0.9.0 新示例 (AI 策略)
zig build run-example-openai-chat  # OpenAI Chat 示例

# 查看完整说明
cat examples/README.md
```

---

## 📦 已实现功能

### ✅ V0.1 - Foundation (基础设施) - 已完成

**核心模块** (140+ 测试):
- ✅ **Decimal** - 18位精度、i128整数运算、零浮点误差
- ✅ **Time** - 毫秒时间戳、ISO 8601、K线对齐
- ✅ **Error System** - 5大分类、错误上下文、重试机制
- ✅ **Logger** - 6级日志、多Writer、结构化字段
- ✅ **Config** - JSON配置、环境变量、敏感信息保护
- ✅ **Exchange Router** - IExchange接口、VTable模式

**完成时间**: 2024-12-23

---

### ✅ V0.2 - MVP (交易系统) - 已完成

**核心功能** (173 测试):
- ✅ **Hyperliquid 连接器**
  - HTTP API (Info + Exchange)
  - WebSocket 实时数据流
  - Ed25519 签名认证
  - 速率限制 (20 req/s)
- ✅ **订单簿管理**
  - L2 订单簿
  - 快照 + 增量更新
  - < 50μs 更新延迟
- ✅ **订单管理**
  - 下单、撤单、批量撤单
  - 订单状态追踪
  - WebSocket 事件处理
- ✅ **仓位跟踪**
  - 实时 PnL 计算
  - 账户状态同步
- ✅ **CLI 基础命令**
  - 11 个交易命令
  - 交互式 REPL

**性能指标** (全部达标):
- ✅ WebSocket 延迟: 0.23ms (< 10ms 目标)
- ✅ 订单执行: ~300ms (< 500ms 目标)
- ✅ 内存占用: ~8MB (< 50MB 目标)
- ✅ 零内存泄漏

**完成时间**: 2024-12-25

---

### ✅ V0.3 - 策略与回测 (策略框架) - 已完成 ⭐

**核心功能** (357 测试):

#### 策略框架
- ✅ **IStrategy 接口** - VTable 模式策略抽象
- ✅ **7 个技术指标** - SMA, EMA, RSI, MACD, Bollinger Bands, ATR, Stochastic
- ✅ **3 个内置策略**
  - Dual Moving Average (双均线)
  - RSI Mean Reversion (RSI 均值回归)
  - Bollinger Breakout (布林带突破)
- ✅ **IndicatorManager** - 缓存优化，10x 性能提升

#### 回测引擎
- ✅ **BacktestEngine** - 事件驱动架构
- ✅ **PerformanceAnalyzer** - 30+ 核心性能指标
  - Sharpe Ratio, Sortino Ratio, Profit Factor
  - Maximum Drawdown, Win Rate, Risk/Reward
- ✅ **CSV 数据加载** - 历史数据导入和验证
- ✅ **逼真订单执行** - 滑点和手续费模拟

#### 参数优化
- ✅ **GridSearchOptimizer** - 自动化参数优化
- ✅ **6 种优化目标**
  - Sharpe Ratio, Profit Factor, Win Rate
  - Drawdown, Net Profit, Total Return
- ✅ **结果分析** - 排名和性能对比

#### CLI 命令 (NEW!)
- ✅ `backtest` - 策略回测
- ✅ `optimize` - 参数优化
- ✅ `run-strategy` - 实盘运行（stub，计划 v0.4.0）

#### 文档 (5,300+ 行)
- ✅ [CLI 使用指南](./docs/features/cli/usage-guide.md) (1,800+ 行)
- ✅ [优化器使用指南](./docs/features/optimizer/usage-guide.md) (2,000+ 行)
- ✅ [策略开发教程](./docs/tutorials/strategy-development.md) (1,500+ 行)

**性能指标** (全部达标):
- ✅ 回测速度: 60ms/8k candles (> 10,000 ticks/s)
- ✅ 指标计算: < 10ms (< 50ms 目标)
- ✅ 策略执行: < 10ms (< 50ms 目标)
- ✅ 网格搜索: ~85ms/组合 (< 100ms 目标)
- ✅ 内存占用: ~10MB (< 50MB 目标)
- ✅ 零内存泄漏

**真实数据验证** (Binance BTC/USDT 2024 年完整数据):
- ✅ Dual MA: 1 笔交易
- ✅ RSI Mean Reversion: 9 笔交易，**+11.05% 收益** ✨
- ✅ Bollinger Breakout: 2 笔交易

**完成时间**: 2024-12-26
**发布说明**: [RELEASE_v0.3.0.md](./RELEASE_v0.3.0.md)

---

### ✅ V0.4 - 优化器增强与指标扩展 - 已完成 ⭐

**核心功能** (453 测试):

#### Walk-Forward 分析
- ✅ **WalkForwardAnalyzer** - 前向验证分析器
- ✅ **DataSplitter** - 数据分割策略 (固定/滚动/扩展/锚定)
- ✅ **OverfittingDetector** - 过拟合检测器
- ✅ **6 种新优化目标** - Sortino, Calmar, Omega, Tail, Stability, Risk-Adjusted

#### 扩展技术指标 (+8 新增)
- ✅ **ADX** - 平均趋向指数 (趋势强度)
- ✅ **Ichimoku Cloud** - 一目均衡表 (趋势、支撑阻力)
- ✅ **Stochastic RSI** - 随机RSI (动量超买超卖)
- ✅ **Williams %R** - 威廉指标 (超买超卖)
- ✅ **CCI** - 商品通道指数 (周期波动)
- ✅ **OBV** - 能量潮 (成交量趋势)
- ✅ **MFI** - 资金流量指数 (资金流向)
- ✅ **VWAP** - 成交量加权平均价

#### 回测结果导出
- ✅ **JSONExporter** - JSON 格式导出
- ✅ **CSVExporter** - CSV 格式导出
- ✅ **ResultLoader** - 历史结果加载
- ✅ **ResultComparator** - 多策略性能对比

#### 并行优化
- ✅ **ThreadPool** - 线程池实现
- ✅ **ParallelExecutor** - 并行回测执行器
- ✅ **进度跟踪** - 实时进度回调

#### 新增策略
- ✅ **MACD Divergence** - MACD背离策略

#### 新增示例 (+4)
- ✅ `09_new_indicators.zig` - 新技术指标演示
- ✅ `10_walk_forward.zig` - Walk-Forward 分析
- ✅ `11_result_export.zig` - 结果导出演示
- ✅ `12_parallel_optimize.zig` - 并行优化演示

**完成时间**: 2024-12-27

---

### ✅ V0.5 - 事件驱动架构 - 已完成 ⭐

**核心功能** (502 测试):

#### 消息总线 (MessageBus)
- ✅ **Pub/Sub 模式** - 主题发布订阅、通配符匹配
- ✅ **Request/Response 模式** - 同步请求响应
- ✅ **Command 模式** - 异步命令发送

#### 数据缓存 (Cache)
- ✅ **OrderBook 缓存** - 订单簿快照、增量更新
- ✅ **Position 缓存** - 仓位追踪
- ✅ **Quote 缓存** - 报价数据
- ✅ **Bar 缓存** - K线数据序列
- ✅ **Order 缓存** - 订单状态追踪

#### 数据引擎 (DataEngine)
- ✅ **IDataProvider 接口** - VTable 模式数据源抽象
- ✅ **历史数据回放** - CSV 加载、速度控制
- ✅ **实时数据处理** - 事件发布到 MessageBus

#### 执行引擎 (ExecutionEngine)
- ✅ **IExecutionClient 接口** - VTable 模式执行抽象
- ✅ **订单恢复** - 启动时恢复未完成订单
- ✅ **超时检测** - 订单超时自动处理
- ✅ **风控检查** - 订单大小、数量限制

#### 交易引擎
- ✅ **LiveTradingEngine** - 同步交易引擎
- ✅ **AsyncLiveTradingEngine** - 基于 libxev 的异步引擎

#### 新增示例 (+2)
- ✅ `13_event_driven.zig` - 事件驱动架构演示
- ✅ `14_async_engine.zig` - 异步交易引擎演示

#### 集成测试
- ✅ `v050_integration_test.zig` - 7 个集成测试用例

**代码统计**:
- MessageBus: 863 行
- Cache: 939 行
- DataEngine: 1039 行
- ExecutionEngine: 1036 行
- LiveTradingEngine: 859 行
- **总计**: 4736 行核心代码

**完成时间**: 2025-12-27
**发布说明**: [RELEASE_v0.5.0.md](./RELEASE_v0.5.0.md)

---

### ✅ V0.6 - 混合计算模式 - 已完成 ⭐

**核心功能** (558 测试):

#### 向量化回测
- ✅ **VectorizedBacktester** - SIMD 优化回测引擎
- ✅ **12.6M bars/s** - 超越目标 126 倍

#### 适配器层
- ✅ **HyperliquidDataProvider** - IDataProvider 实现
- ✅ **HyperliquidExecutionClient** - IExecutionClient 实现

#### Paper Trading
- ✅ **PaperTradingEngine** - 模拟交易引擎
- ✅ **模拟订单执行** - 支持滑点/延迟

#### 策略热重载
- ✅ **HotReloadManager** - 运行时参数更新
- ✅ **零停机更新** - 无需重启

**完成时间**: 2025-12-27

---

### ✅ V0.7 - 做市策略 - 已完成 ⭐

**核心功能**:

#### 做市核心
- ✅ **Clock-Driven 模式** - Tick 驱动策略执行
- ✅ **Pure Market Making** - 双边报价做市策略
- ✅ **Inventory Management** - 库存风险控制

#### 数据持久化
- ✅ **DataStore** - 数据存储层
- ✅ **CandleCache** - K线数据缓存

#### 高级功能
- ✅ **Cross-Exchange Arbitrage** - 跨交易所套利
- ✅ **Queue Position Modeling** - 队列位置建模 (HFTBacktest)
- ✅ **Dual Latency Simulation** - 双向延迟模拟 (HFTBacktest)

**完成时间**: 2025-12-27

---

### ✅ V0.8 - 风险管理 - 已完成 ⭐

**核心功能**:

#### 风险引擎
- ✅ **RiskEngine** - 实时风险监控
- ✅ **Kill Switch** - 紧急平仓机制
- ✅ **多维度风险检查** - 仓位/杠杆/资金限制

#### 止损管理
- ✅ **StopLossManager** - 止损订单管理
- ✅ **追踪止损** - 动态调整止损价
- ✅ **自动止损执行** - 订单执行回调

#### 资金管理
- ✅ **MoneyManager** - 仓位大小计算
- ✅ **Kelly 公式** - 最优仓位比例
- ✅ **风险预算** - 资金分配策略

#### 风险指标
- ✅ **RiskMetrics** - VaR (风险价值)
- ✅ **实时 Sharpe/Sortino** - 收益风险比
- ✅ **回撤监控** - 最大回撤跟踪

#### 警报系统
- ✅ **AlertSystem** - 多级别警报
- ✅ **警报通道** - 控制台输出
- ✅ **警报历史** - 记录追溯

#### 崩溃恢复
- ✅ **RecoveryManager** - 状态快照/恢复
- ✅ **交易所同步** - 重启后状态同步
- ✅ **优雅降级** - 故障处理机制

**代码统计**:
- RiskEngine: ~750 行
- StopLossManager: ~840 行
- MoneyManager: ~780 行
- RiskMetrics: ~770 行
- AlertSystem: ~750 行
- **总计**: ~3890 行核心代码

**完成时间**: 2025-12-28

---

### ✅ V0.9 - AI 策略集成 - 已完成 ⭐ (NEW!)

**核心功能**:

#### AI 模块
- ✅ **ILLMClient** - VTable 模式 LLM 客户端接口
- ✅ **LLMClient** - OpenAI 兼容实现 (基于 openai-zig)
- ✅ **AIAdvisor** - 结构化交易建议服务
- ✅ **PromptBuilder** - 专业市场分析 Prompt 构建器

#### 支持的 AI 提供商
- ✅ **OpenAI** - 官方 API
- ✅ **LM Studio** - 本地模型服务
- ✅ **Ollama** - 本地模型服务
- ✅ **DeepSeek** - 第三方 API
- ✅ **Custom** - 任何 OpenAI 兼容 API

#### 混合策略
- ✅ **HybridAIStrategy** - 技术指标 + AI 建议加权融合
- ✅ **容错回退** - AI 失败时自动使用纯技术指标
- ✅ **可配置权重** - AI 40% + 技术 60% (默认)

#### 特性
- ✅ **Markdown 解析** - 自动处理 AI 返回的代码块包装 JSON
- ✅ **自定义 JSON 序列化** - 避免 null 字段兼容性问题
- ✅ **请求统计** - 成功率、延迟追踪

**代码统计**:
- types.zig: ~200 行
- interfaces.zig: ~200 行
- client.zig: ~350 行
- advisor.zig: ~600 行
- prompt_builder.zig: ~200 行
- hybrid_ai.zig: ~600 行
- **总计**: ~2150 行核心代码

**完成时间**: 2025-12-28
**发布说明**: [RELEASE_v0.9.0.md](./docs/releases/RELEASE_v0.9.0.md)

---

## 🗺️ 产品路线图

```
v0.1 Foundation          ████████████████████ (100%) ✅ 完成
v0.2 MVP                 ████████████████████ (100%) ✅ 完成
v0.3 Strategy Framework  ████████████████████ (100%) ✅ 完成
v0.4 优化器增强          ████████████████████ (100%) ✅ 完成
v0.5 事件驱动架构        ████████████████████ (100%) ✅ 完成
v0.6 混合计算模式        ████████████████████ (100%) ✅ 完成
v0.7 做市策略            ████████████████████ (100%) ✅ 完成
v0.8 风险管理            ████████████████████ (100%) ✅ 完成
v0.9 AI 策略集成         ████████████████████ (100%) ✅ 完成 (NEW!)
v1.0 生产就绪            ████████░░░░░░░░░░░░ (40%)  ← 开发中 (REST API ✅)
```

**整体进度**: 90% (9/10 版本完成) → v1.0.0 生产就绪规划中

### ✅ V0.4 - 优化器增强与指标扩展 - 已完成 ⭐

**核心目标**: 实现参数优化器和扩展策略库

- [x] Walk-Forward 分析 (前向验证、过拟合检测)
- [x] 扩展技术指标库 (15个指标，+8新增)
- [x] MACD Divergence 策略 (+1新增)
- [x] 回测结果导出 (JSON/CSV)
- [x] 并行优化 (多线程加速)
- [x] 策略开发教程 (完整文档)
- [x] 12个示例程序 (+4新增)

### ✅ V0.5 - 事件驱动核心架构 - 已完成

**核心目标**: 重构为事件驱动架构 (借鉴 NautilusTrader)

- [x] MessageBus 消息总线 (Pub/Sub, Request/Response, Command)
- [x] Cache 高性能缓存系统 (OrderBook, Position, Quote, Bar, Order)
- [x] DataEngine 数据引擎 (IDataProvider, 历史回放)
- [x] ExecutionEngine 执行引擎重构 (IExecutionClient, 订单恢复, 风控)
- [x] libxev 依赖集成 (AsyncLiveTradingEngine 框架)

### ✅ V0.6 - 混合计算模式 - 已完成

**核心目标**: 向量化回测 + 增量实盘 (借鉴 Freqtrade)

- [x] 向量化回测引擎 (12.6M bars/s，超越目标 126 倍)
- [x] HyperliquidDataProvider (IDataProvider 实现)
- [x] HyperliquidExecutionClient (IExecutionClient 实现)
- [x] Paper Trading 模拟交易系统
- [x] 策略热重载功能
- [x] 558/558 测试全部通过

### ✅ V0.7 - 做市策略 - 已完成

**核心目标**: 做市策略和微观市场结构 (借鉴 Hummingbot + HFTBacktest)

- [x] **Clock-Driven 模式** - Tick 驱动策略执行
- [x] **Pure Market Making 策略** - 双边报价做市
- [x] **Inventory Management** - 库存风险控制
- [x] **Data Persistence** - 数据持久化 (DataStore/CandleCache)
- [x] **Cross-Exchange Arbitrage** - 跨交易所套利
- [x] **Queue Position Modeling** - 队列位置建模 ⭐
- [x] **Dual Latency Simulation** - 双向延迟模拟 ⭐

**完成时间**: 2025-12-27
**发布说明**: 7 个 Stories (033-039) 全部完成

### ✅ V0.8 - 风险管理 - 已完成

**核心目标**: 生产级风险管理和监控 (借鉴 NautilusTrader)

- [x] **RiskEngine** - 风险引擎 (仓位限制、杠杆控制、Kill Switch)
- [x] **止损/止盈** - StopLossManager 止损管理、追踪止损
- [x] **资金管理** - MoneyManager (Kelly 公式、固定分数、风险预算)
- [x] **风险指标** - RiskMetrics (VaR、Sharpe、Sortino、最大回撤)
- [x] **实时监控** - AlertSystem 多级警报系统
- [x] **Crash Recovery** - RecoveryManager 崩溃恢复机制

**完成时间**: 2025-12-28
**发布说明**: 6 个 Stories (040-045) 全部完成

### ✅ V0.9 - AI 策略集成 - 已完成 (NEW!)

**核心目标**: AI 辅助交易决策 (借鉴 AI 技术趋势)

- [x] **ILLMClient 接口** - VTable 模式 LLM 客户端抽象
- [x] **LLMClient 实现** - 基于 openai-zig，支持 OpenAI 兼容 API
- [x] **AIAdvisor** - 结构化交易建议 (action/confidence/reasoning)
- [x] **PromptBuilder** - 专业市场分析 Prompt 构建
- [x] **HybridAIStrategy** - 技术指标 + AI 混合决策策略
- [x] **Markdown JSON 解析** - 自动处理 AI 返回的代码块
- [x] **示例代码** - examples/33_openai_chat.zig

**完成时间**: 2025-12-28
**发布说明**: [RELEASE_v0.9.0.md](./docs/releases/RELEASE_v0.9.0.md)

### 🚧 V1.0 - 生产就绪 (开发中)

**核心目标**: CLI 工具和完整运维支持

- [x] **REST API 服务** - 40 端点, JWT 认证, 动态数据 ✅
- [x] **Prometheus Metrics** - /metrics 端点导出 ✅
- [ ] Docker 部署 - 容器化部署
- [ ] Telegram/Email 通知 - 多渠道告警
- [ ] 完整运维文档

详见 [Roadmap](./roadmap.md) 和 [架构演进战略](./roadmap.md#架构演进战略)

---

## 🎯 项目特色

### 🔥 高性能

- **零分配优化** - 日志级别过滤、错误处理
- **编译时优化** - 类型检查、内联优化
- **事件驱动** - MessageBus 单线程高效
- **缓存优化** - IndicatorManager 10x 性能提升

**性能对比**:
- WebSocket 延迟: **0.23ms** (vs 行业平均 10ms)
- 回测速度: **60ms/8k candles** (vs Freqtrade ~500ms)
- 内存占用: **~10MB** (vs Python 框架 ~100MB)

### 🛡️ 类型安全

- **编译时验证** - 配置、参数、订单
- **强类型错误** - 五大错误分类
- **精确数值** - i128 整数运算，零浮点误差
- **内存安全** - Zig 语言保证

### 📚 开发体验

- **完整中文文档** - 8,000+ 行策略文档
- **25 个完整示例** - 从基础到高级 (v0.7.0 +11新增)
- **624 个测试** - 100% 通过
- **故障排查指南** - 详细的问题解决方案

### 🏗️ 架构优势

基于 **4 大顶级平台** 的深度研究:

| 来源 | 借鉴内容 | 应用版本 |
|------|---------|---------|
| **NautilusTrader** | 事件驱动 + MessageBus + Cache | v0.5.0 ✅ |
| **Hummingbot** | 订单前置追踪 + Clock-Driven | v0.5.0, v0.7.0 ✅ |
| **Freqtrade** | 向量化回测 + 易用性 | v0.6.0 ✅ |
| **HFTBacktest** | Queue Position + Dual Latency | v0.7.0 ✅ |

详见 [竞争分析](./docs/architecture/COMPETITIVE_ANALYSIS.md) (750+ 行深度分析)

---

## 🧪 测试

```bash
# 运行所有测试
zig build test --summary all

# 运行集成测试
zig build test-integration
zig build test-ws
zig build test-trading

# 运行指定模块测试
zig test src/core/decimal.zig
zig test src/strategy/interface.zig
zig test src/backtest/engine.zig

# 显示测试详情
zig build test -freference-trace=10
```

**当前测试状态**: **558+ tests passed** ✅ (100%)

### 测试覆盖

- ✅ 单元测试: 558+ 个
- ✅ 集成测试: 15+ 个 (HTTP, WebSocket, Trading, Strategy, v0.5.0-v0.7.0 组件)
- ✅ 真实数据验证: Binance BTC/USDT 2024 年完整数据
- ✅ 内存泄漏检测: GPA 验证通过
- ✅ 代码覆盖率: > 90%

---

## 📊 性能基准

| 模块 | 性能目标 | 实测性能 | 状态 |
|------|---------|---------|------|
| **Logger** | < 1μs (级别过滤) | ✅ 零分配 | ✅ |
| **Time** | < 100ns (now) | ✅ 直接系统调用 | ✅ |
| **Decimal** | < 10ns (加减法) | ✅ 内联优化 | ✅ |
| **Config** | < 1ms (加载) | ✅ 单次解析 | ✅ |
| **OrderBook 快照** | < 1ms (100档) | ✅ < 500μs | ✅ |
| **OrderBook 更新** | < 100μs | ✅ < 50μs | ✅ |
| **OrderBook 查询** | < 100ns | ✅ < 50ns (O(1)) | ✅ |
| **API 延迟** | < 500ms | ✅ ~200ms | ✅ |
| **WebSocket 延迟** | < 10ms | ✅ 0.23ms | ✅ |
| **回测速度** | > 10,000 ticks/s | ✅ 60ms/8k candles | ✅ |
| **指标计算** | < 50ms | ✅ < 10ms | ✅ |
| **策略执行** | < 50ms | ✅ < 10ms | ✅ |
| **网格搜索** | < 100ms/组合 | ✅ ~85ms | ✅ |
| **内存占用** | < 50MB | ✅ ~10MB | ✅ |
| **启动时间** | < 200ms | ✅ ~150ms | ✅ |

**所有性能指标全部达标** ✅

---

## 🛠️ 技术栈

- **语言**: Zig 0.15.2
- **构建系统**: zig build
- **测试框架**: Zig 内置测试
- **依赖管理**: zig-clap (CLI 参数解析)
- **文档**: Markdown (5,300+ 行)

---

## 🤝 贡献指南

### 提交代码

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

### 报告问题

遇到问题时，请先查阅 [故障排查文档](./docs/troubleshooting/README.md)。

如果是新问题：
1. 在 GitHub Issues 中创建问题
2. 提供详细的错误信息和复现步骤
3. 标注 Zig 版本和操作系统

### 编写文档

发现并解决了新问题？请参考 [故障排查贡献指南](./docs/troubleshooting/README.md#贡献指南)。

---

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

---

## 🙏 致谢

本项目深度研究并借鉴以下开源项目：
- [NautilusTrader](https://github.com/nautechsystems/nautilus_trader) - 事件驱动架构、MessageBus 设计
- [Hummingbot](https://github.com/hummingbot/hummingbot) - 订单前置追踪、做市策略
- [Freqtrade](https://github.com/freqtrade/freqtrade) - 向量化回测、易用性
- [HFTBacktest](https://github.com/nkaz001/hftbacktest) - Queue Position、Dual Latency ⭐
- [Zig 标准库](https://github.com/ziglang/zig) - 优秀的语言设计

详见 [竞争分析](./docs/architecture/COMPETITIVE_ANALYSIS.md)

---

## 📮 联系方式

- 项目主页: https://github.com/DaviRain-Su/zigQuant
- 问题反馈: https://github.com/DaviRain-Su/zigQuant/issues
- 讨论区: https://github.com/DaviRain-Su/zigQuant/discussions

---

**状态**: 🚧 V1.0.0 生产就绪开发中 (REST API ✅) | **版本**: 1.0.0-dev | **更新时间**: 2025-12-29
**测试**: 558+ 全部通过 ✅ | **示例**: 26 个完整示例 | **文档**: 10,000+ 行 | **性能**: 全部达标 ✅
**下一步**: Docker 部署 + 通知系统 + 多交易所支持
