# ZigQuant 完整文档索引

> **最后更新**: 2025-12-28
> **当前版本**: v0.8.0
> **整体进度**: 89% (8/9 版本完成)

---

## 📊 文档统计

- **总文档数**: 347+ 个文档
- **功能模块**: 40+ 个核心模块
- **核心项目文档**: 15+ 个
- **故障排查文档**: 4 个
- **设计决策文档**: 3 个
- **发布说明**: 5 个 (v0.3.0 - v0.8.0)

---

## 📚 核心项目文档

### 快速开始
- **[README.md](../README.md)** - 项目介绍、特性、快速开始 ⭐
- **[QUICK_START.md](../QUICK_START.md)** - 5分钟快速上手指南 ⭐
- **[CHANGELOG.md](../CHANGELOG.md)** - 完整版本历史和变更记录

### 项目规划和进度
- **[PROJECT_OUTLINE.md](PROJECT_OUTLINE.md)** - 项目愿景和 Phase 0-7 路线图
- **[roadmap.md](../roadmap.md)** - 产品路线图和架构演进战略
- **[NEXT_STEPS.md](NEXT_STEPS.md)** - v1.0.0 开发计划

### 架构和设计
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - 系统架构设计和模块说明
- **[FEATURES_SUPPLEMENT.md](FEATURES_SUPPLEMENT.md)** - 各模块功能详细说明
- **[api-quick-reference.md](api-quick-reference.md)** - API 快速参考

### 质量保障
- **[TESTING.md](TESTING.md)** - 测试策略和框架
- **[PERFORMANCE.md](PERFORMANCE.md)** - 性能目标和优化策略
- **[SECURITY.md](SECURITY.md)** - 安全架构和最佳实践
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - 生产环境部署指南

---

## 🎯 功能模块文档

每个功能模块包含 6 个标准文档：`README.md`, `api.md`, `implementation.md`, `testing.md`, `bugs.md`, `changelog.md`

### V0.1 Foundation - 核心基础设施 (6个模块)

#### 1. Decimal - 高精度数值
- **[README](features/decimal/README.md)** - 18位小数精度、零浮点误差
- [API Reference](features/decimal/api.md) - 完整 API 和代码示例
- [Implementation](features/decimal/implementation.md) - 基于 i128 的实现细节
- [Testing](features/decimal/testing.md) - 140+ 测试用例
- [Bugs](features/decimal/bugs.md) - Bug 追踪
- [Changelog](features/decimal/changelog.md) - 版本历史

#### 2. Time - 时间处理
- **[README](features/time/README.md)** - 时间戳、K线对齐、ISO 8601
- [API Reference](features/time/api.md) - Timestamp, Duration, KlineInterval
- [Implementation](features/time/implementation.md) - 时间对齐算法
- [Testing](features/time/testing.md) - 测试覆盖
- [Bugs](features/time/bugs.md) - Bug 追踪
- [Changelog](features/time/changelog.md) - 版本历史

#### 3. Error System - 错误处理
- **[README](features/error-system/README.md)** - 五大错误分类、重试机制
- [API Reference](features/error-system/api.md) - ErrorContext, WrappedError
- [Implementation](features/error-system/implementation.md) - 实现细节
- [Testing](features/error-system/testing.md) - 测试文档
- [Bugs](features/error-system/bugs.md) - Bug 追踪
- [Changelog](features/error-system/changelog.md) - 版本历史

#### 4. Logger - 日志系统
- **[README](features/logger/README.md)** - 6级日志、结构化输出
- [API Reference](features/logger/api.md) - Logger API
- [Usage Guide](features/logger/usage-guide.md) - 使用指南 ⭐
- [std.log Bridge](features/logger/std-log-bridge.md) - 标准库桥接
- [Comparison](features/logger/comparison.md) - 与其他日志系统对比
- [Implementation](features/logger/implementation.md) - 实现细节
- [Testing](features/logger/testing.md) - 38+ 测试用例
- [Bugs](features/logger/bugs.md) - Bug 追踪
- [Changelog](features/logger/changelog.md) - 版本历史

#### 5. Config - 配置管理
- **[README](features/config/README.md)** - JSON配置、环境变量覆盖
- [API Reference](features/config/api.md) - Config API
- [Implementation](features/config/implementation.md) - 实现细节
- [Testing](features/config/testing.md) - 测试文档
- [Bugs](features/config/bugs.md) - Bug 追踪
- [Changelog](features/config/changelog.md) - 版本历史

#### 6. Exchange Router - 交易所抽象层
- **[README](features/exchange-router/README.md)** - IExchange接口、VTable模式
- [API Reference](features/exchange-router/api.md) - 统一接口 API
- [Implementation](features/exchange-router/implementation.md) - VTable实现
- [Testing](features/exchange-router/testing.md) - 测试文档
- [Bugs](features/exchange-router/bugs.md) - Bug 追踪
- [Changelog](features/exchange-router/changelog.md) - 版本历史

### V0.2 MVP - 交易功能 (6个模块)

#### 7. Hyperliquid Connector - Hyperliquid DEX 连接器
- **[README](features/hyperliquid-connector/README.md)** - HTTP + WebSocket 完整集成
- [API Reference](features/hyperliquid-connector/api.md) - Info API, Exchange API
- [Implementation](features/hyperliquid-connector/implementation.md) - Ed25519签名、速率限制
- [Testing](features/hyperliquid-connector/testing.md) - 单元测试 + 集成测试
- [Bugs](features/hyperliquid-connector/bugs.md) - Bug 追踪
- [Changelog](features/hyperliquid-connector/changelog.md) - 版本历史

#### 8. OrderBook - L2 订单簿管理
- **[README](features/orderbook/README.md)** - 快照更新、深度查询
- [API Reference](features/orderbook/api.md) - OrderBook API
- [Implementation](features/orderbook/implementation.md) - 数据结构和算法
- [Testing](features/orderbook/testing.md) - 性能测试 (< 1ms 更新)
- [Bugs](features/orderbook/bugs.md) - Bug 追踪
- [Changelog](features/orderbook/changelog.md) - 版本历史

#### 9. Order System - 订单类型定义
- **[README](features/order-system/README.md)** - 订单类型和生命周期
- [API Reference](features/order-system/api.md) - Order types API
- [Implementation](features/order-system/implementation.md) - 订单状态机
- [Testing](features/order-system/testing.md) - 测试文档
- [Bugs](features/order-system/bugs.md) - Bug 追踪
- [Changelog](features/order-system/changelog.md) - 版本历史

#### 10. Order Manager - 订单管理器
- **[README](features/order-manager/README.md)** - 下单、撤单、查询
- [API Reference](features/order-manager/api.md) - OrderManager API
- [Implementation](features/order-manager/implementation.md) - 订单追踪和事件处理
- [Testing](features/order-manager/testing.md) - 集成测试结果 ✅
- [Bugs](features/order-manager/bugs.md) - Bug 追踪
- [Changelog](features/order-manager/changelog.md) - 版本历史

#### 11. Position Tracker - 仓位追踪器
- **[README](features/position-tracker/README.md)** - 仓位管理和 PnL 计算
- [API Reference](features/position-tracker/api.md) - PositionTracker API
- [Implementation](features/position-tracker/implementation.md) - PnL 算法
- [Testing](features/position-tracker/testing.md) - 集成测试结果 ✅
- [Bugs](features/position-tracker/bugs.md) - Bug 追踪
- [Changelog](features/position-tracker/changelog.md) - 版本历史

#### 12. CLI - 命令行界面
- **[README](features/cli/README.md)** - 11个命令 + REPL
- [API Reference](features/cli/api.md) - CLI 命令参考
- [Usage Guide](features/cli/usage-guide.md) - CLI 使用指南 ⭐
- [Implementation](features/cli/implementation.md) - REPL 实现
- [Testing](features/cli/testing.md) - CLI 测试
- [Bugs](features/cli/bugs.md) - Bug 追踪
- [Changelog](features/cli/changelog.md) - 版本历史

### V0.3-V0.4 策略与回测 (6个模块)

#### 13. Strategy - 策略框架
- **[README](features/strategy/README.md)** - IStrategy 接口、VTable 模式
- [API Reference](features/strategy/api.md) - 策略 API

#### 14. Indicators - 技术指标库
- **[README](features/indicators/README.md)** - 14 个技术指标
- [API Reference](features/indicators/api.md) - 指标 API

#### 15. Backtest - 回测引擎
- **[README](features/backtest/README.md)** - 事件驱动回测
- [API Reference](features/backtest/api.md) - 回测 API
- [Export](features/backtest/export.md) - 结果导出

#### 16. Optimizer - 参数优化器
- **[README](features/optimizer/README.md)** - 网格搜索、Walk-Forward
- [Usage Guide](features/optimizer/usage-guide.md) - 优化器使用指南 ⭐

### V0.5 事件驱动架构 (5个模块)

#### 17. MessageBus - 消息总线
- **[README](features/message-bus/README.md)** - Pub/Sub、Request/Response

#### 18. Cache - 数据缓存
- **[README](features/cache/README.md)** - OrderBook/Position/Quote 缓存

#### 19. DataEngine - 数据引擎
- **[README](features/data-engine/README.md)** - IDataProvider 接口

#### 20. ExecutionEngine - 执行引擎
- **[README](features/execution-engine/README.md)** - IExecutionClient 接口

#### 21. LiveTrading - 实时交易
- **[README](features/live-trading/README.md)** - 同步/异步交易引擎

### V0.6 混合计算模式 (4个模块)

#### 22. VectorizedBacktest - 向量化回测
- **[README](features/vectorized-backtest/README.md)** - SIMD 优化，12.6M bars/s

#### 23. HyperliquidAdapter - Hyperliquid 适配器
- **[README](features/hyperliquid-adapter/README.md)** - IDataProvider/IExecutionClient 实现

#### 24. PaperTrading - 模拟交易
- **[README](features/paper-trading/README.md)** - 模拟订单执行

#### 25. HotReload - 策略热重载
- **[README](features/hot-reload/README.md)** - 运行时参数更新

### V0.7 做市优化 (7个模块)

#### 26. ClockDriven - 时钟驱动模式
- **[README](features/clock-driven/README.md)** - Tick 驱动策略执行

#### 27. PureMarketMaking - 做市策略
- **[README](features/pure-market-making/README.md)** - 双边报价做市

#### 28. InventoryManagement - 库存管理
- **[README](features/inventory-management/README.md)** - 库存偏斜控制

#### 29. SQLiteStorage - 数据持久化
- **[README](features/sqlite-storage/README.md)** - DataStore/CandleCache

#### 30. CrossExchangeArbitrage - 跨交易所套利
- **[README](features/cross-exchange-arbitrage/README.md)** - 套利检测

#### 31. QueuePosition - 队列位置建模
- **[README](features/queue-position/README.md)** - HFTBacktest 风格

#### 32. DualLatency - 双向延迟模拟
- **[README](features/dual-latency/README.md)** - Feed/Order 延迟

### V0.8 风险管理 (6个模块)

#### 33. RiskEngine - 风险引擎
- **[README](features/risk-engine/README.md)** - Kill Switch、实时监控

#### 34. StopLoss - 止损管理
- **[README](features/stop-loss/README.md)** - 止损/追踪止损

#### 35. MoneyManagement - 资金管理
- **[README](features/money-management/README.md)** - Kelly 公式、风险预算

#### 36. RiskMetrics - 风险指标
- **[README](features/risk-metrics/README.md)** - VaR、Sharpe、Sortino

#### 37. AlertSystem - 警报系统
- **[README](features/alert-system/README.md)** - 多级警报

#### 38. CrashRecovery - 崩溃恢复
- **[README](features/crash-recovery/README.md)** - 状态快照/恢复

### 功能总索引
- **[features/README.md](features/README.md)** - 所有功能模块导航

---

## 🛠️ 故障排查文档

- **[troubleshooting/README.md](troubleshooting/README.md)** - 故障排查总览
- **[Zig 0.15.2 Logger 兼容性](troubleshooting/zig-0.15.2-logger-compatibility.md)** - Logger 模块适配经验 ⭐
- [Zig 0.15.2 快速参考](troubleshooting/quick-reference-zig-0.15.2.md) - API 变更速查表
- [BufferedWriter 陷阱](troubleshooting/bufferedwriter-trap.md) - 缓冲写入常见问题

---

## 📋 设计决策文档

- [ADR-001: 为什么选择 Zig](decisions/001-why-zig.md)
- [ADR-002: 为什么首选 Hyperliquid](decisions/002-hyperliquid-first-exchange.md)
- [决策文档模板](decisions/template.md)

---

## 📁 完整文档结构

```
docs/
├── DOCUMENTATION_INDEX.md (本文件) ⭐
│
├── 核心项目文档 (15+个)
│   ├── ARCHITECTURE.md
│   ├── DEPLOYMENT.md
│   ├── FEATURES_SUPPLEMENT.md
│   ├── NEXT_STEPS.md
│   ├── PERFORMANCE.md
│   ├── PROJECT_OUTLINE.md
│   ├── SECURITY.md
│   ├── TESTING.md
│   └── api-quick-reference.md
│
├── features/ (38个模块)
│   ├── README.md (功能总索引)
│   ├── V0.1: decimal/, time/, error-system/, logger/, config/, exchange-router/
│   ├── V0.2: hyperliquid-connector/, orderbook/, order-system/, order-manager/, position-tracker/, cli/
│   ├── V0.3-V0.4: strategy/, indicators/, backtest/, optimizer/
│   ├── V0.5: message-bus/, cache/, data-engine/, execution-engine/, live-trading/
│   ├── V0.6: vectorized-backtest/, hyperliquid-adapter/, paper-trading/, hot-reload/
│   ├── V0.7: clock-driven/, pure-market-making/, inventory-management/, sqlite-storage/,
│   │         cross-exchange-arbitrage/, queue-position/, dual-latency/
│   └── V0.8: risk-engine/, stop-loss/, money-management/, risk-metrics/, alert-system/, crash-recovery/
│
├── stories/ (60+个故事文档)
│   ├── v0.1-foundation/
│   ├── v0.2-mvp/
│   ├── v0.3.0/, v0.4.0/, v0.5.0/, v0.6.0/, v0.7.0/, v0.8.0/
│   └── templates/
│
├── releases/ (5个发布说明)
│   ├── RELEASE_v0.3.0.md
│   ├── RELEASE_v0.5.0.md
│   ├── RELEASE_v0.6.0.md
│   ├── RELEASE_v0.7.0.md
│   └── RELEASE_v0.8.0.md
│
├── architecture/ (5个架构文档)
│   ├── ARCHITECTURE_PATTERNS.md
│   ├── COMPETITIVE_ANALYSIS.md
│   └── ...
│
├── troubleshooting/ (4个文件)
│
└── decisions/ (3个文件)
```

---

## 🎯 文档使用指南

### 按角色查找

#### 新用户
1. 阅读 [README.md](../README.md) 了解项目
2. 跟随 [QUICK_START.md](../QUICK_START.md) 快速上手
3. 浏览 [功能总索引](features/README.md)

#### 开发者
1. 查看 [ARCHITECTURE.md](ARCHITECTURE.md) 了解架构
2. 参考各模块的 API Reference
3. 查看 [测试策略](TESTING.md)
4. 参考 [故障排查文档](troubleshooting/README.md)

#### 贡献者
1. 阅读 [PROJECT_OUTLINE.md](PROJECT_OUTLINE.md) 了解路线图
2. 查看 [MVP 进度](MVP_V0.2.0_PROGRESS.md)
3. 查看 [下一步计划](NEXT_STEPS.md)
4. 参考 [设计决策文档](decisions/)

### 按任务查找

#### 快速开始
- [安装和构建](../QUICK_START.md#安装和构建)
- [运行测试](../QUICK_START.md#运行测试)
- [第一个程序](../QUICK_START.md#第一个程序)
- [使用 CLI](../QUICK_START.md#使用-cli)

#### 集成 Hyperliquid
- [Hyperliquid Connector README](features/hyperliquid-connector/README.md)
- [API Reference](features/hyperliquid-connector/api.md)
- [Testing Guide](features/hyperliquid-connector/testing.md)

#### 实现交易逻辑
- [Order Manager README](features/order-manager/README.md)
- [Order Types API](features/order-system/api.md)
- [Position Tracker README](features/position-tracker/README.md)

#### 监控市场数据
- [OrderBook README](features/orderbook/README.md)
- [WebSocket 订阅](features/hyperliquid-connector/implementation.md)

#### 解决问题
- [故障排查总览](troubleshooting/README.md)
- [Zig 0.15.2 兼容性](troubleshooting/zig-0.15.2-logger-compatibility.md)

---

## ✅ 版本完成度总览

| 版本 | 核心功能 | 测试 | 状态 |
|------|---------|------|------|
| v0.1.0 | Foundation 基础设施 | 140+ | ✅ 完成 |
| v0.2.0 | MVP 交易系统 | 178 | ✅ 完成 |
| v0.3.0 | 策略回测框架 | 343 | ✅ 完成 |
| v0.4.0 | 优化器增强 | 453 | ✅ 完成 |
| v0.5.0 | 事件驱动架构 | 502 | ✅ 完成 |
| v0.6.0 | 混合计算模式 | 558 | ✅ 完成 |
| v0.7.0 | 做市优化 | 558+ | ✅ 完成 |
| v0.8.0 | 风险管理 | 558+ | ✅ 完成 |
| v1.0.0 | 生产就绪 | - | 📋 下一步 |
| **总计** | **89% (8/9)** | **558+** | **进行中** |

**性能指标**:
- ✅ 向量化回测: 12.6M bars/s
- ✅ WebSocket 延迟: 0.23ms
- ✅ 零内存泄漏
- ✅ ~39,000 行代码

---

## 📝 文档规范

### 标准模块文档结构

每个功能模块包含以下标准文档：

1. **README.md** - 功能概览、快速开始
2. **api.md** - API 参考和代码示例
3. **implementation.md** - 实现细节和设计决策
4. **testing.md** - 测试策略和测试结果
5. **bugs.md** - Bug 追踪和修复记录
6. **changelog.md** - 版本历史和变更记录

### 文档特点

- ✅ **完整性**: 覆盖所有 MVP 核心功能
- ✅ **实用性**: 包含可运行的代码示例
- ✅ **可维护性**: 清晰的目录结构，统一的格式
- ✅ **中文优先**: 完整的中文注释和说明

---

## 🔮 后续计划

### v1.0.0 - 生产就绪 (下一步)
- REST API 服务
- Web Dashboard
- 多策略组合
- 分布式回测
- Binance 适配器

### 低优先级
- OKX 适配器
- 更多警报通道 (Telegram, Email, Webhook)

查看 [roadmap.md](../roadmap.md) 了解完整路线图。

---

## 📁 发布说明

- **[RELEASE_v0.8.0.md](releases/RELEASE_v0.8.0.md)** - 风险管理发布说明 ⭐
- **[RELEASE_v0.7.0.md](releases/RELEASE_v0.7.0.md)** - 做市优化发布说明
- **[RELEASE_v0.6.0.md](releases/RELEASE_v0.6.0.md)** - 混合计算模式发布说明
- **[RELEASE_v0.5.0.md](releases/RELEASE_v0.5.0.md)** - 事件驱动架构发布说明
- **[RELEASE_v0.3.0.md](releases/RELEASE_v0.3.0.md)** - 策略回测框架发布说明

---

**文档总数**: 347+ 个文档
**最后更新**: 2025-12-28
**当前版本**: v0.8.0
**整体进度**: 89% (8/9 版本完成)
