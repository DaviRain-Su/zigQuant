# Strategy Framework 变更历史

**模块**: Strategy Framework
**初始版本**: v0.3.0

---

## [0.3.0] - 2025-12-25（计划中）

### Added

#### 核心接口

- ✨ **IStrategy 接口** - 统一策略接口（VTable 模式）
  - `init()` - 初始化策略
  - `deinit()` - 清理资源
  - `populateIndicators()` - 计算技术指标
  - `generateEntrySignal()` - 生成入场信号
  - `generateExitSignal()` - 生成出场信号
  - `calculatePositionSize()` - 计算仓位大小
  - `getParameters()` - 获取策略参数
  - `getMetadata()` - 获取策略元数据

- ✨ **StrategyContext** - 策略执行上下文
  - MarketDataProvider - 市场数据提供者
  - OrderExecutor - 订单执行器
  - PositionManager - 仓位管理器
  - RiskManager - 风险管理器
  - IndicatorManager - 指标管理器

- ✨ **Signal 类型** - 交易信号定义
  - SignalType - 信号类型枚举（entry_long, entry_short, exit_long, exit_short, hold）
  - SignalMetadata - 信号附加信息

- ✨ **StrategyMetadata** - 策略元数据（参考 Freqtrade）
  - 基本信息（name, version, author, description）
  - 策略类型（trend_following, mean_reversion, breakout, etc.）
  - 时间周期配置
  - MinimalROI - 分阶段止盈目标
  - StopLoss - 止损配置
  - TrailingStop - 追踪止损配置

- ✨ **StrategyParameter** - 策略参数系统
  - 参数类型（integer, decimal, boolean, string）
  - 参数范围（用于优化）
  - 优化标记

#### 技术指标库

- ✨ **IIndicator 接口** - 统一指标接口
- ✨ **SMA (Simple Moving Average)** - 简单移动平均
- ✨ **EMA (Exponential Moving Average)** - 指数移动平均
- ✨ **RSI (Relative Strength Index)** - 相对强弱指标
- ✨ **MACD (Moving Average Convergence Divergence)** - MACD 指标
- ✨ **Bollinger Bands** - 布林带
- ✨ **IndicatorManager** - 指标缓存管理器

#### 内置策略

- ✨ **DualMAStrategy** - 双均线策略
  - 金叉做多，死叉做空
  - 可配置快慢周期
  - 趋势跟随类型

- ✨ **RSIMeanReversionStrategy** - RSI 均值回归策略
  - RSI 超卖做多，超买做空
  - 可配置 RSI 周期和阈值
  - 均值回归类型

- ✨ **BollingerBreakoutStrategy** - 布林带突破策略
  - 价格突破上轨做多，突破下轨做空
  - 可配置布林带周期和标准差
  - 突破类型

#### 风险管理

- ✨ **RiskManager** - 风险管理器
  - 订单验证（仓位大小、杠杆、余额）
  - 止损检查（基于 StrategyMetadata.stoploss）
  - 止盈检查（基于 StrategyMetadata.minimal_roi）
  - 追踪止损（基于 StrategyMetadata.trailing_stop）

#### 辅助类型

- ✨ **Candles** - 蜡烛数据结构
  - OHLCV 数据存储
  - 指标数据管理
  - 内存自动管理

- ✨ **Candle** - 单根蜡烛定义
  - timestamp, open, high, low, close, volume

### Documentation

- 📚 完整的策略框架文档
  - README.md - 功能概述和快速开始
  - api.md - 完整 API 参考
  - implementation.md - 实现细节说明
  - testing.md - 测试策略和用例
  - bugs.md - Bug 追踪
  - changelog.md - 变更历史

### Tests

- ✅ IStrategy 接口测试
- ✅ 技术指标测试（SMA, EMA, RSI, MACD, Bollinger Bands）
- ✅ 内置策略测试（DualMA, RSIMeanReversion, BollingerBreakout）
- ✅ RiskManager 测试
- ✅ 策略端到端集成测试
- ✅ 性能基准测试

### Performance

- ⚡ SMA 计算: < 500μs (1000 蜡烛, period=20)
- ⚡ EMA 计算: < 400μs (1000 蜡烛, period=20)
- ⚡ RSI 计算: < 600μs (1000 蜡烛, period=14)
- ⚡ MACD 计算: < 800μs (1000 蜡烛)
- ⚡ Bollinger Bands 计算: < 700μs (1000 蜡烛)
- ⚡ 信号生成: < 100μs (单次)
- ⚡ 策略执行延迟: < 1ms

---

## 设计参考

- **Hummingbot V2**: [Architecture](https://hummingbot.org/v2-strategies/)
  - Controller 模式 → StrategyContext
  - Executor 模式 → OrderExecutor
  - 事件驱动架构

- **Freqtrade**: [Strategy Customization](https://www.freqtrade.io/en/stable/strategy-customization/)
  - `populate_indicators()` → `populateIndicators()`
  - `populate_entry_trend()` → `generateEntrySignal()`
  - `populate_exit_trend()` → `generateExitSignal()`
  - `minimal_roi` → StrategyMetadata.minimal_roi
  - `stoploss` → StrategyMetadata.stoploss
  - `trailing_stop` → StrategyMetadata.trailing_stop

- **TA-Lib**: [Technical Analysis Library](https://ta-lib.org/)
  - 技术指标计算参考

---

## 版本规范

遵循 [语义化版本 2.0.0](https://semver.org/lang/zh-CN/)：

- **MAJOR** (x.0.0): 不兼容的 API 变更
- **MINOR** (0.x.0): 向后兼容的功能新增
- **PATCH** (0.0.x): 向后兼容的 Bug 修复

---

## 下一版本计划

### v0.4.0 - 回测引擎和参数优化（计划中）

- [ ] 回测引擎 (BacktestEngine)
  - [ ] HistoricalDataFeed - 历史数据加载
  - [ ] EventSimulator - 事件模拟
  - [ ] PerformanceAnalyzer - 性能分析
  - [ ] BacktestResult - 回测结果类型

- [ ] 参数优化器
  - [ ] GridSearchOptimizer - 网格搜索
  - [ ] GeneticOptimizer - 遗传算法（可选）
  - [ ] OptimizationResult - 优化结果

- [ ] 更多技术指标
  - [ ] ATR (Average True Range)
  - [ ] Stochastic Oscillator
  - [ ] ADX (Average Directional Index)
  - [ ] Volume indicators

- [ ] CLI 集成
  - [ ] `strategy backtest` 命令
  - [ ] `strategy optimize` 命令
  - [ ] `strategy list` 命令

### v0.5.0 - 实时交易支持（计划中）

- [ ] 实时策略执行引擎
- [ ] WebSocket 事件处理
- [ ] 策略状态持久化
- [ ] 多策略并行运行
- [ ] 策略监控和告警

---

**当前版本**: v0.3.0 (设计阶段)
**更新时间**: 2025-12-25
