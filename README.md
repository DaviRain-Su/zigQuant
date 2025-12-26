# zigQuant

> 基于 Zig 语言的高性能量化交易框架

[![Zig Version](https://img.shields.io/badge/zig-0.15.2-orange.svg)](https://ziglang.org/)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/tests-passing-brightgreen.svg)]()
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.3.0-blue.svg)](CHANGELOG.md)

## 📖 项目文档

### 核心文档
- **[📋 文档索引](./docs/DOCUMENTATION_INDEX.md)** - 完整文档导航 ⭐
- **[📊 项目进度](./docs/PROGRESS.md)** - 完整的项目进度跟踪和状态
- [项目大纲](./docs/PROJECT_OUTLINE.md) - 项目愿景、阶段规划和路线图
- [架构设计](./docs/ARCHITECTURE.md) - 系统架构和设计决策
- [功能补充说明](./docs/FEATURES_SUPPLEMENT.md) - 各模块功能详细说明
- [性能指标](./docs/PERFORMANCE.md) - 性能目标和优化策略
- [安全设计](./docs/SECURITY.md) - 安全架构和最佳实践
- [测试策略](./docs/TESTING.md) - 测试框架和覆盖率
- [部署指南](./docs/DEPLOYMENT.md) - 生产环境部署文档

### V0.1 Foundation 功能文档
- [Decimal 高精度数值](./docs/features/decimal/README.md) - 18位小数精度、零浮点误差
- [Time 时间处理](./docs/features/time/README.md) - Timestamp、Duration、K线对齐
- [Error System 错误处理](./docs/features/error-system/README.md) - 五大错误分类、重试机制
- [Logger 日志系统](./docs/features/logger/README.md) - 结构化日志、多种输出格式
- [Config 配置管理](./docs/features/config/README.md) - JSON配置、环境变量覆盖
- [Exchange Router](./docs/features/exchange-router/README.md) - 交易所抽象层、IExchange接口

### V0.2 MVP 功能文档
- [Hyperliquid 连接器](./docs/features/hyperliquid-connector/README.md) - HTTP/WebSocket客户端、Ed25519签名
- [Orderbook 订单簿](./docs/features/orderbook/README.md) - L2订单簿、增量更新
- [Order System 订单系统](./docs/features/order-system/README.md) - 订单类型、生命周期
- [Order Manager](./docs/features/order-manager/README.md) - 订单管理、状态追踪
- [Position Tracker](./docs/features/position-tracker/README.md) - 仓位追踪、盈亏计算

### V0.3 策略与回测功能文档
- [Strategy Framework 策略框架](./docs/features/strategy/README.md) - IStrategy接口、三个内置策略
- [Backtest Engine 回测引擎](./docs/features/backtest/README.md) - 历史数据回测、性能分析
- [Indicators Library 指标库](./docs/features/indicators/README.md) - 7个技术指标(SMA/EMA/RSI/MACD/BB/ATR/Stoch)
- [Parameter Optimizer 参数优化](./docs/features/optimizer/README.md) - 网格搜索优化器

### 🎓 示例教程
- **[示例总览](./examples/README.md)** - 8个完整示例
- [Core Basics](./examples/01_core_basics.zig) - Logger、Decimal、Time基础
- [WebSocket Stream](./examples/02_websocket_stream.zig) - 实时市场数据
- [HTTP Market Data](./examples/03_http_market_data.zig) - REST API查询
- [Exchange Connector](./examples/04_exchange_connector.zig) - 交易所抽象层
- [Colored Logging](./examples/05_colored_logging.zig) - 彩色日志输出
- [Strategy Backtest](./examples/06_strategy_backtest.zig) - 策略回测
- [Strategy Optimize](./examples/07_strategy_optimize.zig) - 参数优化
- [Custom Strategy](./examples/08_custom_strategy.zig) - 自定义策略

### 🔧 故障排查
- **[故障排查索引](./docs/troubleshooting/README.md)** - 常见问题和解决方案
- **[Zig 0.15.2 兼容性问题详解](./docs/troubleshooting/zig-0.15.2-logger-compatibility.md)** ⭐ - Logger 模块适配经验
- **[Zig 0.15.2 快速参考](./docs/troubleshooting/quick-reference-zig-0.15.2.md)** - API 变更速查表
- [BufferedWriter 陷阱](./docs/troubleshooting/bufferedwriter-trap.md) - 缓冲写入器常见问题

## 🚀 快速开始

### 环境要求

- **Zig 0.15.2** 或更高版本
- Linux / macOS / Windows
- 网络连接（用于 Hyperliquid testnet 集成测试）

### 构建项目

```bash
# 克隆仓库
git clone https://github.com/your-username/zigQuant.git
cd zigQuant

# 运行所有测试
zig build test --summary all

# 运行集成测试
zig build test-integration        # HTTP API 集成测试
zig build test-ws                  # WebSocket 集成测试
zig build test-ws-orderbook        # WebSocket 订单簿集成测试

# 运行 CLI 程序
zig build run

# 构建 Release 版本
zig build -Doptimize=ReleaseFast
```

📚 **详细指南**: 查看 [快速开始指南](QUICK_START.md) 了解更多信息。

### 运行示例

```bash
# 运行核心基础示例
zig build run-example-core

# 运行 WebSocket 实时数据流示例（需要网络）
zig build run-example-websocket

# 运行 HTTP 市场数据示例（需要网络）
zig build run-example-http

# 运行交易所连接器示例（需要网络）
zig build run-example-connector

# 运行彩色日志示例
zig build run-example-colored-logging

# 运行策略回测示例
zig build run-example-backtest

# 运行参数优化示例
zig build run-example-optimize

# 运行自定义策略示例
zig build run-example-custom

# 查看完整示例说明
cat examples/README.md
```

## 📦 已实现模块

### ✅ V0.1 Foundation: 核心基础设施（已完成）

#### Decimal - 高精度数值 (`src/core/decimal.zig`)
- ✅ 18位小数精度（满足金融交易需求）
- ✅ 基于 i128 整数运算（无浮点误差）
- ✅ 完整算术运算（加减乘除、比较）
- ✅ 字符串解析和格式化
- ✅ 零内存分配（除字符串操作）
- ✅ 140/140 测试通过

#### Time - 时间处理 (`src/core/time.zig`)
- ✅ 高精度时间戳（毫秒级 Unix 时间戳）
- ✅ ISO 8601 格式解析和格式化
- ✅ K线时间对齐（1m, 3m, 5m, 15m, 30m, 1h, 2h, 4h, 6h, 12h, 1d, 1w）
- ✅ Duration 时间间隔计算
- ✅ 时间比较和运算

#### Error System - 错误处理 (`src/core/errors.zig`)
- ✅ 五大错误分类（Network, API, Data, Business, System）
- ✅ ErrorContext 错误上下文
- ✅ WrappedError 错误包装
- ✅ 重试机制（固定间隔和指数退避）
- ✅ 错误工具函数

#### Logger - 日志系统 (`src/core/logger.zig`)
- ✅ 6 级日志（Trace, Debug, Info, Warn, Error, Fatal）
- ✅ 多种 Writer（Console, File, JSON）
- ✅ 结构化字段支持
- ✅ std.log 桥接
- ✅ 线程安全设计
- ✅ 38/38 测试通过

#### Config - 配置管理 (`src/core/config.zig`)
- ✅ JSON 配置文件加载
- ✅ 环境变量覆盖（ZIGQUANT_* 前缀）
- ✅ 多交易所配置支持
- ✅ 配置验证和类型安全
- ✅ 敏感信息保护（sanitize）

#### Exchange Router - 交易所抽象层 (`src/exchange/`)
- ✅ IExchange 接口（VTable 模式）
- ✅ 统一数据类型（TradingPair, OrderRequest, Ticker, Orderbook）
- ✅ ExchangeRegistry（交易所注册表）
- ✅ SymbolMapper（符号映射）

### 🚧 V0.2 MVP: 交易功能（进行中）

#### Hyperliquid 连接器 (`src/exchange/hyperliquid/`)
- ✅ HTTP 客户端（Info API + Exchange API）
- ✅ WebSocket 客户端（实时数据流）
- ✅ Ed25519 签名认证
- ✅ 速率限制（20 req/s）
- ✅ 与 Exchange Router 集成

#### Orderbook - 订单簿 (`src/trading/orderbook.zig`)
- ✅ L2 订单簿数据结构
- ✅ 快照和增量更新机制
- ✅ 查询接口（最优价格、价差、深度）

#### Order System - 订单系统 (`src/trading/types.zig`)
- ✅ 订单类型定义（Limit, Market, Post-only, IOC）
- ✅ 订单状态枚举
- ✅ 订单生命周期

#### Order Manager - 订单管理 (`src/trading/order_manager.zig`)
- ✅ 订单提交和撤单接口
- ✅ 订单状态追踪
- ✅ WebSocket 事件处理
- ✅ 完整集成测试通过

#### Position Tracker - 仓位追踪 (`src/trading/position_tracker.zig`)
- ✅ 仓位数据结构
- ✅ 盈亏计算
- ✅ 账户状态同步
- ✅ 完整集成测试通过

### ✅ V0.3 策略与回测: 策略系统（已完成）

#### Strategy Framework - 策略框架 (`src/strategy/`)
- ✅ IStrategy 接口（VTable 模式）
- ✅ 三个内置策略（Dual MA, RSI Mean Reversion, Bollinger Breakout）
- ✅ IndicatorManager（指标缓存和管理）
- ✅ Signal 和 SignalMetadata（信号生成）
- ✅ StrategyParameter（参数定义和范围）

#### Backtest Engine - 回测引擎 (`src/backtest/`)
- ✅ BacktestEngine（核心回测引擎）
- ✅ PerformanceAnalyzer（性能分析器）
- ✅ PerformanceMetrics（性能指标计算）
- ✅ Trade & Position 跟踪
- ✅ Account 管理
- ✅ CSV 数据加载（HistoricalDataFeed）

#### Indicators Library - 指标库 (`src/indicators/`)
- ✅ SMA（Simple Moving Average）
- ✅ EMA（Exponential Moving Average）
- ✅ RSI（Relative Strength Index）
- ✅ MACD（Moving Average Convergence Divergence）
- ✅ Bollinger Bands（布林带）
- ✅ ATR（Average True Range）
- ✅ Stochastic Oscillator（随机指标）

#### Parameter Optimizer - 参数优化器 (`src/optimizer/`)
- ✅ GridSearchOptimizer（网格搜索优化）
- ✅ CombinationGenerator（参数组合生成）
- ✅ OptimizationResult（优化结果分析）
- ✅ 6种优化目标（Sharpe, Profit Factor, Win Rate, etc.）

## 🎯 项目特色

### 高性能
- 零分配日志级别过滤
- 编译时类型检查
- 内联优化和泛型特化
- 最小运行时开销

### 类型安全
- 编译时配置验证
- 强类型错误系统
- 精确的数值类型（避免浮点误差）

### 开发体验
- 完整的中文注释
- 详细的文档和示例
- 全面的测试覆盖（38/38 通过）
- 故障排查指南

## 🧪 测试

```bash
# 运行所有测试
zig build test --summary all

# 运行指定模块测试
zig test src/core/time.zig
zig test src/core/errors.zig
zig test src/core/logger.zig
zig test src/core/config.zig

# 显示测试详情
zig build test -freference-trace=10
```

当前测试状态：**173/173 tests passed** ✅ (100%)

## 📊 性能指标

| 模块 | 性能目标 | 当前状态 |
|------|---------|---------|
| Logger | < 1μs (级别过滤) | ✅ 零分配 |
| Time | < 100ns (now) | ✅ 直接系统调用 |
| Config | < 1ms (加载) | ✅ 单次解析 |
| Error | < 10ns (创建) | ✅ 栈分配 |
| OrderBook 快照 | < 1ms (100档) | ✅ < 500μs |
| OrderBook 更新 | < 100μs | ✅ < 50μs |
| OrderBook 查询 | < 100ns | ✅ < 50ns (O(1)) |
| API 延迟 | < 500ms | ✅ ~200ms |
| WebSocket 延迟 | < 10ms | ✅ 0.23ms |
| 启动时间 | < 200ms | ✅ ~150ms |
| 内存占用 | < 50MB | ✅ ~8MB |

## 🛠️ 技术栈

- **语言:** Zig 0.15.2
- **构建系统:** zig build
- **测试框架:** Zig 内置测试
- **文档:** Markdown + JSX 图表

## 📈 开发进度

### V0.1 Foundation（✅ 已完成）
- [x] Decimal - 高精度数值
- [x] Time - 时间处理
- [x] Error System - 错误处理
- [x] Logger - 日志系统
- [x] Config - 配置管理
- [x] Exchange Router - 交易所抽象层

### V0.2 MVP（✅ 已完成 - 100%）
- [x] Hyperliquid Connector - HTTP/WebSocket 客户端（100%）
- [x] Orderbook - L2 订单簿（100%）
- [x] Order System - 订单类型定义（100%）
- [x] Order Manager - 订单管理（100%）
- [x] Position Tracker - 仓位追踪（100%）
- [x] CLI - 命令行界面（100%）
- [x] **集成测试**（100%）✨
  - [x] WebSocket Orderbook 集成测试
  - [x] Position Management 集成测试
  - [x] WebSocket Events 集成测试

### V0.3 策略与回测（✅ 已完成 - 100%）
- [x] Strategy Framework - 策略框架（100%）
  - [x] IStrategy 接口（VTable 模式）
  - [x] 三个内置策略（Dual MA, RSI, Bollinger）
  - [x] IndicatorManager 指标管理
- [x] Backtest Engine - 回测引擎（100%）
  - [x] BacktestEngine 核心引擎
  - [x] PerformanceAnalyzer 性能分析
  - [x] Trade & Position 跟踪
- [x] Indicators Library - 指标库（100%）
  - [x] 7个技术指标（SMA/EMA/RSI/MACD/BB/ATR/Stoch）
- [x] Parameter Optimizer - 参数优化（100%）
  - [x] GridSearchOptimizer 网格搜索
  - [x] 6种优化目标
- [x] **示例与测试**（100%）✨
  - [x] 3个策略示例（Backtest, Optimize, Custom）
  - [x] 集成测试通过
  - [x] 文档完善

### 未来规划
- [ ] V0.4: CLI 策略命令集成
- [ ] V0.5: 实盘交易集成
- [ ] V1.0: 完整的量化交易系统

详见 [变更日志](./CHANGELOG.md) 和 [MVP 进度](./docs/MVP_V0.2.0_PROGRESS.md)

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

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 🙏 致谢

本项目受以下开源项目启发：
- [Hummingbot](https://github.com/hummingbot/hummingbot) - 做市和套利策略
- [Freqtrade](https://github.com/freqtrade/freqtrade) - 回测和自动交易
- [Zig 标准库](https://github.com/ziglang/zig) - 优秀的语言设计

## 📮 联系方式

- 项目主页: https://github.com/your-username/zigQuant
- 问题反馈: https://github.com/your-username/zigQuant/issues
- 讨论区: https://github.com/your-username/zigQuant/discussions

---

**状态:** ✅ V0.3 策略与回测完成 | **版本:** 0.3.0 | **更新时间:** 2024-12-26
**测试:** 全部通过 ✅ | **示例:** 8个完整示例 | **文档:** 完善 | **性能:** 全部达标 ✅
